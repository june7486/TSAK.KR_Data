import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// 상세 시트 항목 — 라벨/값 한 줄.
class TsakDetailEntry {
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final bool mono;
  final bool emphasize;
  final bool copyable;

  const TsakDetailEntry({
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.mono = false,
    this.emphasize = false,
    this.copyable = true,
  });
}

/// 목록의 한 행을 눌렀을 때 뜨는 공통 상세 시트.
///
/// 로그기록·수품 장부·승인요청 등에서 재사용한다. 값은 길면 줄바꿈되고,
/// 탭하면 클립보드로 복사된다. [footer] 로 승인/삭제 같은 동작을 붙일 수 있다.
Future<void> showTsakDetailSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  IconData icon = Icons.description_outlined,
  Color accent = AppColors.purple,
  List<TsakDetailEntry> entries = const [],
  List<Widget> extra = const [],
  Widget? footer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final maxH = MediaQuery.of(ctx).size.height * 0.86;
      return Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(ctx, title, subtitle, icon, accent),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in entries) _entryRow(ctx, e, accent),
                    ...extra,
                  ],
                ),
              ),
            ),
            if (footer != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: footer,
                ),
              ),
          ],
        ),
      );
    },
  );
}

Widget _header(
  BuildContext ctx,
  String title,
  String? subtitle,
  IconData icon,
  Color accent,
) {
  return Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, accent.withValues(alpha: 0.72)],
      ),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: '닫기',
          onPressed: () => Navigator.of(ctx).pop(),
          icon: const Icon(Icons.close, color: Colors.white, size: 20),
        ),
      ],
    ),
  );
}

Widget _entryRow(BuildContext ctx, TsakDetailEntry e, Color accent) {
  final value = e.value.trim();
  final shown = value.isEmpty ? '—' : value;
  final tint = e.color ?? accent;
  return Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: (e.copyable && value.isNotEmpty)
          ? () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text('${e.label} 복사됨'),
                  duration: const Duration(milliseconds: 900),
                ),
              );
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: e.emphasize
                ? tint.withValues(alpha: 0.45)
                : AppColors.purple.withValues(alpha: 0.10),
            width: e.emphasize ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Row(
                children: [
                  if (e.icon != null) ...[
                    Icon(e.icon, size: 13, color: tint),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      e.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: e.icon != null ? tint : AppColors.textGray,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                shown,
                style: TextStyle(
                  fontSize: e.emphasize ? 14 : 13,
                  fontWeight: e.emphasize ? FontWeight.w800 : FontWeight.w500,
                  color: value.isEmpty ? AppColors.textGray : AppColors.textDark,
                  fontFeatures: e.mono
                      ? const [FontFeature.tabularFigures()]
                      : null,
                  letterSpacing: e.mono ? 0.2 : null,
                ),
              ),
            ),
            if (e.copyable && value.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 1),
                child: Icon(
                  Icons.copy_rounded,
                  size: 13,
                  color: AppColors.textGray,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// 값이 있는 항목만 골라 [TsakDetailEntry] 목록을 만든다(편의 함수).
List<TsakDetailEntry> tsakEntries(List<TsakDetailEntry> all) =>
    all.where((e) => e.value.trim().isNotEmpty).toList();
