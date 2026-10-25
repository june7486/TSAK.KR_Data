import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';
import 'web_nav.dart';

/// 파일 저장 공용 헬퍼.
///
/// - **웹(PC 브라우저)**: Blob + `<a download>` 로 저장한다.
///   PC 기본 다운로드 폴더로 바로 저장되며, 별도 다이얼로그 없이 즉시 저장된다.
///   (file_saver 의 웹 구현이 일부 브라우저에서 동작하지 않는 문제를 회피)
/// - **네이티브(안드로이드 등)**: file_saver 로 저장한다.
///
/// 새 저장 기능을 추가할 때도 이 헬퍼를 사용한다(규칙).
Future<void> saveBytes({
  required Uint8List bytes,
  required String name,
  required String ext,
  required String mime,
  MimeType? mimeType,
  bool preferPicker = false,
}) async {
  if (isWebRuntime) {
    // (요구: 폴더 변경 옵션) preferPicker=true 이면 저장 폴더/위치를
    //  사용자가 직접 고르는 File System Access API 를 먼저 시도한다.
    //  지원하지 않거나 취소하면 기본 다운로드(Blob)로 폴백한다.
    if (preferPicker && supportsSaveFilePicker) {
      final saved = await saveViaFilePicker(bytes, '$name.$ext', mime);
      if (saved) return;
    }
    // 아이폰·아이패드: 다운로드 폴더가 없어 Blob 저장이 실패 → 공유 시트로 내보낸다.
    if (isAppleMobileWeb) {
      if (await _appleMobileSaveToShare(bytes, '$name.$ext', mime)) return;
    }
    downloadBytesFile(bytes, '$name.$ext', mime);
    return;
  }
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    ext: ext,
    mimeType: mimeType ?? MimeType.other,
  );
}

/// 이 환경이 '저장 위치 직접 선택'을 지원하는지.
///
/// - **웹(크롬·엣지·웨일 등 Chromium)**: File System Access API → true
/// - **웹(사파리·파이어폭스)**: 미지원 → false (기본 다운로드만 가능)
/// - **안드로이드·아이폰(iOS)·데스크톱 네이티브**: OS 저장 대화상자 → true
bool get supportsLocationPicker => isWebRuntime ? supportsSaveFilePicker : true;

/// 이 환경이 **공유 시트로 내보내기**를 지원하는지.
///
/// - **아이폰·안드로이드 모바일 웹**: Web Share API → true
/// - **PC 웹(파일 공유 미지원/불필요)**: false (기존 위치 선택·기본 저장 유지)
/// - **네이티브(안드로이드·아이폰)**: OS 공유 시트 → true
bool get supportsShareExport =>
    isWebRuntime ? (webSupportsShareFiles && isMobileWeb) : true;

/// 이 환경이 **애플 모바일(아이폰·아이패드)** 인지.
///
/// 아이폰·아이패드는 다운로드(Downloads) 폴더가 없어 Blob `<a download>` 저장이
/// 실패한다 → '저장 방법 선택' 창에서 **공유 시트(사진에 저장)** 를 기본으로 권한다.
bool get isAppleMobile => isWebRuntime && isAppleMobileWeb;

// ─────────────────────────────────────────────────────────────────────────
// 저장 방법 선택 (취소 / 위치 직접 선택 / 공유·내보내기 / 기본 폴더)
// ─────────────────────────────────────────────────────────────────────────

/// '저장 방법 선택' 창의 사용자 선택 결과.
enum TsakSaveOption {
  /// 선택한 위치·앱으로 저장(위치 피커 / 시스템 저장 대화상자).
  choose,

  /// 기기 기본 폴더(다운로드)로 바로 저장.
  defaultFolder,

  /// **공유 시트로 내보내기** — 아이폰 '사진에 저장(이미지 저장)'·외부앱 공유.
  share,
}

/// 아이폰·아이패드에서 Blob 저장이 안 되는 문제를 **공유 시트로 우회**한다.
///
/// 반환: 공유 시트를 띄웠으면 true(호출부는 다운로드로 폴백하지 않음).
Future<bool> _appleMobileSaveToShare(
  Uint8List bytes,
  String filename,
  String mime,
) async {
  if (!webSupportsShareFiles) return false;
  try {
    final r = await shareFileNamed(
      bytes: bytes,
      filename: filename,
      mime: mime,
    );
    // 공유 시트가 떴거나 사용자가 닫았으면 다운로드 폴백을 하지 않는다.
    return r == TsakShareResult.shared || r == TsakShareResult.dismissed;
  } catch (_) {
    return false;
  }
}

/// 저장 방법·위치를 묻는 창 (PC·안드로이드·**아이폰** 공통).
///
/// 반환: [TsakSaveOption] — 취소하면 null.
///
/// ## 요구: "개인사진 다운시 아이폰은 기본폴더 오류가 있음.
/// 저장위치 지정 또는 외부앱, 내사진에 저장 같은 선택지가 필요함"
/// 아이폰(사파리)은 File System Access API 가 없고 다운로드 폴더도 없어,
/// 기존에는 [기본 폴더에 저장]만 뜨고 그 경로(Blob)가 실패했다. 이제
/// **공유 시트(사진에 저장·외부앱)** 선택지를 추가하고, 애플 기기에서는
/// 그 선택지를 기본(강조)으로 제시한다.
Future<TsakSaveOption?> askSaveOption(
  BuildContext context, {
  String? info,
}) async {
  final canPick = supportsLocationPicker;
  final canShare = supportsShareExport;
  final apple = isAppleMobile;
  return showDialog<TsakSaveOption>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.save_alt, color: AppColors.purple, size: 30),
      title: const Text('저장 방법 선택'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info != null && info.isNotEmpty) ...[
            Text(
              info,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            apple
                ? '아이폰·아이패드는 다운로드 폴더가 없어 기본 저장이 실패할 수 있습니다. '
                      '[공유·내보내기]를 누른 뒤 「이미지 저장」을 고르면 사진 앱에 저장됩니다.'
                : '저장 위치를 직접 고르거나, 기기 기본 폴더에 바로 저장할 수 있습니다.',
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            <String>[
              if (canPick)
                apple
                    ? '* [위치 직접 선택] → 파일 앱·드라이브 등 저장 위치를 고릅니다.'
                    : '* [위치 직접 선택] → 저장 위치·앱을 고릅니다(PC: 폴더·파일명).',
              if (canShare) '* [공유·내보내기] → 카톡·메일·드라이브, 아이폰은 「이미지 저장」·「사진에 저장」.',
              '* [기본 폴더에 저장] → 다운로드(Downloads) 폴더에 바로 저장.',
            ].join('\n'),
            style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('취소'),
        ),
        if (canPick)
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, TsakSaveOption.choose),
            icon: const Icon(Icons.folder_open, size: 17),
            label: const Text('위치 직접 선택'),
          ),
        if (canShare)
          apple
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                  ),
                  onPressed: () => Navigator.pop(ctx, TsakSaveOption.share),
                  icon: const Icon(Icons.ios_share, size: 17),
                  label: const Text('공유·내보내기'),
                )
              : OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, TsakSaveOption.share),
                  icon: const Icon(Icons.ios_share, size: 17),
                  label: const Text('공유·내보내기'),
                ),
        apple
            ? OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pop(ctx, TsakSaveOption.defaultFolder),
                icon: const Icon(Icons.download, size: 17),
                label: const Text('기본 폴더에 저장'),
              )
            : FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                ),
                onPressed: () =>
                    Navigator.pop(ctx, TsakSaveOption.defaultFolder),
                icon: const Icon(Icons.download, size: 17),
                label: const Text('기본 폴더에 저장'),
              ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────
// 공유 시트 (OS 공유 대화상자) — **모든 기기 공통**
// ─────────────────────────────────────────────────────────────────────────

/// 공유 동작 결과(호출부가 스낵바 문구를 정확히 고르도록).
enum TsakShareResult {
  /// OS 공유 시트가 열려 공유가 시작됨(웹 Web Share / 네이티브 공유 시트).
  shared,

  /// 공유 미지원 → 대신 파일 다운로드(기본 저장)로 처리됨(웹 폴백).
  downloaded,

  /// 사용자가 공유 시트를 닫음(취소).
  dismissed,

  /// 공유에 실패함(예외).
  failed,

  /// 공유할 내용(파일)이 없음.
  empty,
}

/// 파일을 **OS 공유 시트**로 공유한다 — **모든 기기(PC·안드로이드·아이폰) 공통**.
///
/// ## 왜 필요한가 (요구: "모든기기에도 공유 시트 넣어주세요")
/// 지금까지는 '저장'만 가능해서, 아이폰·안드로이드에서 카톡·메일·드라이브로
/// **바로 보내려면** 먼저 파일앱에 저장한 뒤 다시 공유해야 했다. 이 헬퍼는
/// 생성한 파일을 **곧바로 OS 공유 시트**에 넘겨 어디로든 바로 보낼 수 있게 한다.
///
/// ## 동작 (플랫폼별)
/// - **웹(모바일 사파리·크롬 등)**: Web Share API(`navigator.share`) → OS 공유
///   시트(카톡·메일·드라이브…). 미지원 브라우저(PC 사파리·파폭 등)는 자동으로
///   **파일 다운로드**로 폴백한다(share_plus 가 처리).
/// - **안드로이드·아이폰(iOS)·데스크톱 네이티브**: OS 공유 시트(Android
///   `ACTION_SEND` / iOS `UIActivityViewController`).
///
/// [bytes]를 [XFile.fromData] 로 넘기면 네이티브는 임시파일에 자동 기록 후
/// 공유하고, 웹은 Blob 으로 변환해 공유하므로 **별도 임시파일 관리가 필요 없다**.
///
/// 반환: [TsakShareResult] — 호출부는 이 값으로 사용자 안내 문구를 정한다.
Future<TsakShareResult> shareBytes({
  required Uint8List bytes,
  required String name,
  String ext = '',
  String mime = 'application/octet-stream',
  String? subject,
  String? text,
  Rect? sharePositionOrigin,
}) async {
  if (bytes.isEmpty) return TsakShareResult.empty;
  final filename = (ext.isEmpty || name.toLowerCase().endsWith('.$ext'))
      ? name
      : '$name.$ext';
  try {
    final result = await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          name: filename,
          mimeType: mime.isEmpty ? 'application/octet-stream' : mime,
        ),
      ],
      subject: subject,
      text: text,
      sharePositionOrigin: sharePositionOrigin,
    );
    // 웹에서 Web Share 미지원 → share_plus 가 자동 다운로드로 폴백한 경우.
    if (result.status == ShareResultStatus.unavailable) {
      return TsakShareResult.downloaded;
    }
    if (result.status == ShareResultStatus.dismissed) {
      return TsakShareResult.dismissed;
    }
    return TsakShareResult.shared;
  } catch (_) {
    // 공유 실패 → 파일이라도 잃지 않도록 기본 다운로드로 폴백한다.
    try {
      saveBytes(bytes: bytes, name: name, ext: ext, mime: mime);
      return TsakShareResult.downloaded;
    } catch (_) {
      return TsakShareResult.failed;
    }
  }
}

/// 확장자 포함 파일명으로 공유한다([shareBytes] 의 파일명 편의 래퍼).
Future<TsakShareResult> shareFileNamed({
  required Uint8List bytes,
  required String filename,
  String mime = 'application/octet-stream',
  String? subject,
  String? text,
  Rect? sharePositionOrigin,
}) {
  final i = filename.lastIndexOf('.');
  final hasExt = i > 0;
  final base = hasExt ? filename.substring(0, i) : filename;
  final ext = hasExt ? filename.substring(i + 1) : '';
  return shareBytes(
    bytes: bytes,
    name: base,
    ext: ext,
    mime: mime,
    subject: subject,
    text: text,
    sharePositionOrigin: sharePositionOrigin,
  );
}

/// 공유 결과 → 사용자 안내 문구(공용).
String tsakShareMessage(TsakShareResult r, {String what = '파일'}) => switch (r) {
  TsakShareResult.shared => '$what 공유 창을 열었습니다',
  TsakShareResult.downloaded => '이 브라우저는 공유 미지원 → $what을(를) 다운로드했습니다',
  TsakShareResult.dismissed => '공유를 취소했습니다',
  TsakShareResult.failed => '$what 공유에 실패했습니다',
  TsakShareResult.empty => '공유할 $what이(가) 없습니다',
};

/// 확장자 포함 파일명으로 저장한다 (PC·**모든 모바일(안드로이드·아이폰)** 공통).
///
/// [choose]=true 이고 위치 선택이 가능하면 저장 위치/앱을 사용자가 직접 고른다.
/// 모바일 네이티브(안드로이드·아이폰)에서는 시스템 저장 대화상자가 뜬다.
/// [choose]=false 이면 기기 기본(다운로드) 폴더에 바로 저장한다.
Future<bool> saveFileNamed({
  required Uint8List bytes,
  required String filename,
  required String mime,
  MimeType? mimeType,
  bool choose = false,
}) {
  final i = filename.lastIndexOf('.');
  final hasExt = i > 0;
  final base = hasExt ? filename.substring(0, i) : filename;
  final ext = hasExt ? filename.substring(i + 1) : 'dat';
  return saveBytesChoose(
    bytes: bytes,
    name: base,
    ext: ext,
    mime: mime,
    mimeType: mimeType,
    choose: choose,
  );
}

/// 저장 방법·위치 선택 창 (PC·안드로이드·아이폰 공통).
///
/// 반환: false=기본 폴더로 저장 / true=위치 직접 선택 / null=취소.
/// 위치 선택 미지원(사파리·파폭)이면 안내 문구를 띄우고 기본 저장만 제안한다.
/// 저장 방법·위치 선택 창 (PC·안드로이드·**아이폰** 공통) — **하위호환 shim**.
///
/// 반환: false=기본 폴더로 저장 / true=위치 직접 선택 / null=취소.
/// 내부적으로 [askSaveOption] 을 사용한다(아이폰은 공유·내보내기 선택지 제공).
/// 공유 옵션은 bool 로 표현할 수 없어, 공유를 고르면 '위치 직접 선택'(true)으로
/// 매핑한다([saveBytesChoose] 의 애플 자동 공유 폴백이 처리). 새 코드는
/// [askSaveOption] + [saveFileOption] 을 쓴다.
Future<bool?> askSaveLocation(BuildContext context, {String? info}) async {
  final opt = await askSaveOption(context, info: info);
  return switch (opt) {
    null => null,
    TsakSaveOption.defaultFolder => false,
    TsakSaveOption.choose => true,
    TsakSaveOption.share => true,
  };
}

/// 저장 방법을 지정해 저장한다 (PC·**모든 모바일(안드로이드·아이폰)** 공통).
///
/// - [choose]=false → 기기 기본(다운로드) 폴더로 저장.
/// - [choose]=true  → 사용자가 저장 위치/앱을 직접 선택.
///   · 웹(크롬·엣지·웨일): 폴더·파일명 선택창(File System Access API)
///   · 안드로이드·아이폰: 시스템 저장 대화상자(파일 앱/드라이브 등 선택)
///
/// 반환: 저장(트리거)되면 true, 사용자가 취소하면 false.
Future<bool> saveBytesChoose({
  required Uint8List bytes,
  required String name,
  required String ext,
  required String mime,
  MimeType? mimeType,
  bool choose = false,
}) async {
  if (isWebRuntime) {
    if (choose && supportsSaveFilePicker) {
      // 취소 시 false 를 그대로 반환(의도적 취소 → 다운로드 폴백 안 함).
      return await saveViaFilePicker(bytes, '$name.$ext', mime);
    }
    // 아이폰·아이패드: 기본 다운로드 폴더(Blob)가 실패하므로 공유 시트로 대체한다.
    if (isAppleMobileWeb) {
      if (await _appleMobileSaveToShare(bytes, '$name.$ext', mime)) return true;
    }
    downloadBytesFile(bytes, '$name.$ext', mime);
    return true;
  }
  // 네이티브(안드로이드·아이폰·데스크톱) — 시스템 저장 대화상자.
  if (choose) {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '저장 위치 선택',
        fileName: '$name.$ext',
        bytes: bytes,
        type: FileType.any,
      );
      // path != null 이면 저장 완료(네이티브가 파일 기록까지 수행), null 이면 취소.
      return path != null;
    } catch (_) {
      // saveFile 미지원 플랫폼 → 아래 기본 저장으로 폴백.
    }
  }
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    ext: ext,
    mimeType: mimeType ?? MimeType.other,
  );
  return true;
}

/// [askSaveOption] 의 결과([TsakSaveOption])대로 저장·공유한다 (PC·모든 모바일 공통).
///
/// - [TsakSaveOption.share] → OS 공유 시트(아이폰 「이미지 저장」·카톡·메일·드라이브).
/// - [TsakSaveOption.choose] → 위치 직접 선택(웹: File System Access API).
/// - [TsakSaveOption.defaultFolder] → 기기 기본(다운로드) 폴더.
///
/// 반환: 저장/공유를 시작했으면 true, 사용자가 취소했으면 false.
Future<bool> saveFileOption({
  required Uint8List bytes,
  required String filename,
  required String mime,
  MimeType? mimeType,
  required TsakSaveOption option,
}) async {
  final i = filename.lastIndexOf('.');
  final hasExt = i > 0;
  final base = hasExt ? filename.substring(0, i) : filename;
  final ext = hasExt ? filename.substring(i + 1) : 'dat';
  switch (option) {
    case TsakSaveOption.share:
      final r = await shareFileNamed(
        bytes: bytes,
        filename: filename,
        mime: mime,
      );
      // 공유 시트가 떴거나, 미지원이라 다운로드로 폴백했거나, 사용자가 닫은 경우 모두
      // "저장 흐름을 사용자에게 넘겼다"고 본다(실패만 false).
      return r == TsakShareResult.shared ||
          r == TsakShareResult.downloaded ||
          r == TsakShareResult.dismissed;
    case TsakSaveOption.choose:
      return saveBytesChoose(
        bytes: bytes,
        name: base,
        ext: ext,
        mime: mime,
        mimeType: mimeType,
        choose: true,
      );
    case TsakSaveOption.defaultFolder:
      return saveBytesChoose(
        bytes: bytes,
        name: base,
        ext: ext,
        mime: mime,
        mimeType: mimeType,
        choose: false,
      );
  }
}

/// 문자열(CSV·TXT·HTML) 저장 — 웹에서 확실히 동작.
Future<void> saveText({
  required String content,
  required String name,
  required String ext,
  required String mime,
  MimeType? mimeType,
}) async {
  if (isWebRuntime) {
    downloadTextFile(content, '$name.$ext', mime);
    return;
  }
  await FileSaver.instance.saveFile(
    name: name,
    bytes: Uint8List.fromList(utf8.encode(content)),
    ext: ext,
    mimeType: mimeType ?? MimeType.text,
  );
}

/// 이미지(JPG/PNG) 저장 — 규칙(#14): **기본 저장 위치 = 기기 기본**.
/// - 스마트폰(안드로이드 등): 사진/갤러리 폴더로 저장.
/// - PC(웹): 브라우저 기본 다운로드(Downloads) 폴더로 저장.
/// 사용자가 위치를 바꾸려면 [preferGallery]를 false 로 주거나 OS 저장 대화상자를 쓴다.
Future<void> saveImageBytes({
  required Uint8List bytes,
  required String name,
  String ext = 'jpg',
}) async {
  // 웹은 항상 브라우저 기본(Downloads) 경로로 내려받는다.
  if (isWebRuntime) {
    downloadBytesFile(bytes, '$name.$ext', 'image/$ext');
    return;
  }
  // 네이티브는 file_saver 가 OS 저장 대화상자를 띄워 사용자가 위치 선택 가능.
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    ext: ext,
    mimeType: ext == 'png' ? MimeType.png : MimeType.jpeg,
  );
}
