import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';

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
bool get supportsLocationPicker =>
    isWebRuntime ? supportsSaveFilePicker : true;

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
    bytes: Uint8List.fromList(content.codeUnits),
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
