import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// 출력 내보내기 방식 — 저장 · 외부 열기 · 공유 시트.
///
/// ## 규칙 (요구: "모든 포맷도 외부 공유 프로그램으로 내보낼 수 있게")
/// 자체 출력 화면(수품·구매·기획 등)은 `_saveBytes`·`_saveText` 로 **저장**만
/// 했고, 공유는 **PDF 전용**이었다. [TsakOutputMode] 를 [TsakOutputBar] 에
/// 넘겨 **모든 포맷**을 저장/외부 열기/공유 시트로 내보낼 수 있게 한다.
enum TsakOutputMode {
  /// 파일로 저장(기본 폴더/위치 선택).
  save,

  /// 외부 프로그램/뷰어로 열기(웹 새 탭 · 네이티브 공유 시트 폴백).
  open,

  /// OS 공유 시트로 보내기(카톡·메일·드라이브 등).
  share,
}

extension TsakOutputModeX on TsakOutputMode {
  String get label => switch (this) {
    TsakOutputMode.save => '저장',
    TsakOutputMode.open => '열기',
    TsakOutputMode.share => '공유',
  };

  IconData get icon => switch (this) {
    TsakOutputMode.save => Icons.download_outlined,
    TsakOutputMode.open => Icons.open_in_new,
    TsakOutputMode.share => Icons.ios_share,
  };
}

/// 출력 형식 — 프로젝트 규칙(#14): **PDF → JPG → 엑셀 → PPT → 워드 → TXT** 순서.
enum TsakOutputFormat { pdf, jpg, excel, ppt, word, txt }

extension TsakOutputFormatX on TsakOutputFormat {
  String get label => switch (this) {
    TsakOutputFormat.pdf => 'PDF',
    TsakOutputFormat.jpg => 'JPG',
    TsakOutputFormat.excel => '엑셀',
    TsakOutputFormat.ppt => 'PPT',
    TsakOutputFormat.word => '워드',
    TsakOutputFormat.txt => 'TXT',
  };

  IconData get icon => switch (this) {
    TsakOutputFormat.pdf => Icons.picture_as_pdf_outlined,
    TsakOutputFormat.jpg => Icons.image_outlined,
    TsakOutputFormat.excel => Icons.grid_on_outlined,
    TsakOutputFormat.ppt => Icons.slideshow_outlined,
    TsakOutputFormat.word => Icons.description_outlined,
    TsakOutputFormat.txt => Icons.notes_outlined,
  };

  /// 저장 파일 확장자(엑셀은 범용 호환 위해 CSV, 워드는 DOC).
  String get ext => switch (this) {
    TsakOutputFormat.pdf => 'pdf',
    TsakOutputFormat.jpg => 'jpg',
    TsakOutputFormat.excel => 'csv',
    TsakOutputFormat.ppt => 'ppt',
    TsakOutputFormat.word => 'doc',
    TsakOutputFormat.txt => 'txt',
  };
}

/// 규칙 순서(고정): pdf → jpg → 엑셀 → ppt → 워드 → txt.
const List<TsakOutputFormat> kTsakOutputOrder = [
  TsakOutputFormat.pdf,
  TsakOutputFormat.jpg,
  TsakOutputFormat.excel,
  TsakOutputFormat.ppt,
  TsakOutputFormat.word,
  TsakOutputFormat.txt,
];

/// 규칙 순서 안내 문구(모든 출력 다이얼로그 공통).
const String kTsakOutputRule = '규칙 순서: PDF → JPG → 엑셀 → PPT → 워드 → TXT';

/// 출력 형식 버튼 바 — 모든 출력 화면 우측/하단에 동일 규칙으로 배치.
/// 마지막에 '공유'·'이미지 공유'·'링크 공유'를 함께 제공한다.
class TsakOutputBar extends StatelessWidget {
  const TsakOutputBar({
    super.key,
    required this.onFormat,
    this.onMode,
    this.onShare,
    this.onShareImage,
    this.onShareLink,
    this.active,
  });

  final void Function(TsakOutputFormat) onFormat;

  /// 형식 + 방식(저장/열기/공유) 콜백.
  ///
  /// ## 규칙 (요구: "모든 포맷도 외부 공유 프로그램으로 내보낼 수 있게")
  /// 주어지면 **저장·열기·공유** 버튼을 함께 노출해, 자체 출력 화면도
  /// **모든 포맷**을 저장·외부 열기·공유 시트로 내보낼 수 있게 한다.
  final void Function(TsakOutputFormat, TsakOutputMode)? onMode;

  /// 파일 공유(OS 공유 시트) — 모든 기기 공통.
  final VoidCallback? onShare;
  final VoidCallback? onShareImage;
  final VoidCallback? onShareLink;

  /// 현재 선택된 형식(선택 표시용, 없으면 null).
  final TsakOutputFormat? active;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in kTsakOutputOrder)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _fmtChip(f, active == f),
            ),
          const SizedBox(width: 4),
          // (요구) 모든 포맷 × 저장/열기/공유 — 방식별 버튼.
          if (onMode != null) ...[
            for (final m in TsakOutputMode.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: (m == TsakOutputMode.share
                    ? FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.purple,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            onMode!(active ?? kTsakOutputOrder.first, m),
                        icon: Icon(m.icon, size: 15),
                        label: Text(
                          '${m.label} 시트',
                          style: const TextStyle(fontSize: 12),
                        ),
                      )
                    : OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            onMode!(active ?? kTsakOutputOrder.first, m),
                        icon: Icon(m.icon, size: 15),
                        label: Text(
                          m.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                      )),
              ),
          ],
          // (요구) 모든 기기에 OS 공유 시트 — 파일을 곧바로 공유한다.
          if (onMode == null && onShare != null) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onShare,
              icon: const Icon(Icons.ios_share, size: 15),
              label: const Text('공유 시트', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 6),
          ],
          if (onMode == null && onShareImage != null) ...[
            OutlinedButton.icon(
              onPressed: onShareImage,
              icon: const Icon(Icons.image_outlined, size: 15),
              label: const Text('이미지 공유', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 6),
          ],
          if (onMode == null && onShareLink != null)
            OutlinedButton.icon(
              onPressed: onShareLink,
              icon: const Icon(Icons.link, size: 15),
              label: const Text('링크 공유', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _fmtChip(TsakOutputFormat f, bool sel) {
    return GestureDetector(
      onTap: () => onFormat(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? AppColors.purple : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: sel ? AppColors.purple : const Color(0xFFD8D3CA),
          ),
        ),
        child: Row(
          children: [
            Icon(
              f.icon,
              size: 14,
              color: sel ? Colors.white : AppColors.textDark,
            ),
            const SizedBox(width: 4),
            Text(
              f.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 대기(웨이팅) 오버레이 — 긴 작업 중 회전 심볼과 문구 표시.
/// 사용 예: Stack 마지막 자식으로 `WaitingOverlay(visible: _busy)`.
class WaitingOverlay extends StatelessWidget {
  const WaitingOverlay({
    super.key,
    required this.visible,
    this.message = '처리 중입니다...',
  });

  final bool visible;
  final String message;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.38),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 14),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 링크 공유 — 클립보드에 복사하고 안내 스낵바를 띄운다.
Future<void> shareLink(BuildContext context, String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('링크를 복사했습니다. 붙여넣기로 공유하세요.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// 링크 공유 다이얼로그 — URL을 보여주고 복사 버튼 제공.
Future<void> showLinkShareDialog(
  BuildContext context,
  String url, {
  String note = '로그인한 권한자만 열람할 수 있습니다.',
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('링크 공유'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note,
            style: const TextStyle(fontSize: 12, color: AppColors.textGray),
          ),
          const SizedBox(height: 10),
          SelectableText(
            url,
            style: const TextStyle(fontSize: 12, color: AppColors.purple),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('링크를 복사했습니다')));
            }
          },
          child: const Text('복사'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
}
