import 'package:flutter/material.dart';

import '../services/table_options.dart';
import '../theme/app_theme.dart';

export '../services/table_options.dart'
    show
        TableOutputOptions,
        TableDocView,
        TsakFontSize,
        TsakRowSpace,
        applyTableOptions;

/// 표 출력 옵션 편집 시트 — 확인 시 [TableOutputOptions] 를, 취소 시 null 을 준다.
///
/// [columns] 표 헤더, [rows] 예시 행(미리보기 없이 개수만 표기해도 됨).
Future<TableOutputOptions?> showTsakTableOptions(
  BuildContext context, {
  required String title,
  String subtitle = '',
  required List<String> columns,
  TableOutputOptions? initial,
  bool allowLandscape = true,

  /// false 면 출력내용선택·위치이동 패널을 숨긴다(표가 아닌 텍스트 출력용).
  bool allowColumns = true,
}) {
  return showModalBottomSheet<TableOutputOptions>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFBF9F4),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final sel = <int>{
        ...(initial?.cols ?? List<int>.generate(columns.length, (i) => i)),
      };
      var order = <int>[
        ...(initial?.cols ?? List<int>.generate(columns.length, (i) => i)),
      ];
      // 순서 목록에는 반드시 모든 열이 들어가도록(누락 열은 뒤에 붙임).
      for (var i = 0; i < columns.length; i++) {
        if (!order.contains(i)) order.add(i);
      }
      var fontSize = initial?.fontSize ?? TsakFontSize.normal;
      var rowSpace = initial?.rowSpace ?? TsakRowSpace.normal;
      var landscape = initial?.landscape ?? true;

      return StatefulBuilder(
        builder: (ctx, setSheet) {
          void move(int i, int d) {
            final to = i + d;
            if (to < 0 || to >= order.length) return;
            setSheet(() {
              final it = order.removeAt(i);
              order.insert(to, it);
            });
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune, size: 18, color: AppColors.purple),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.purpleDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (subtitle.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, left: 25),
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── 글씨 크기 ──
                          _sec('글씨 크기'),
                          const SizedBox(height: 6),
                          _seg(
                            TsakFontSize.values,
                            fontSize,
                            (v) => v.label,
                            (v) => v.note,
                            (v) => setSheet(() => fontSize = v),
                          ),
                          const SizedBox(height: 16),
                          // ── 줄 간격 (줄간격 유지) ──
                          _sec('줄 간격 (밀도)'),
                          const SizedBox(height: 6),
                          _seg(
                            TsakRowSpace.values,
                            rowSpace,
                            (v) => v.label,
                            (v) => v.note,
                            (v) => setSheet(() => rowSpace = v),
                          ),
                          if (allowLandscape) ...[
                            const SizedBox(height: 16),
                            _sec('출력 용지 방향'),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: _orient(
                                    '세로',
                                    Icons.crop_portrait,
                                    !landscape,
                                    () => setSheet(() => landscape = false),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _orient(
                                    '가로',
                                    Icons.crop_landscape,
                                    landscape,
                                    () => setSheet(() => landscape = true),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          // ── 출력내용 선택 · 위치이동 ──
                          if (allowColumns) ...[
                            Row(
                              children: [
                                _sec('출력내용 선택 · 위치이동'),
                                const Spacer(),
                                Text(
                                  '${sel.length}/${columns.length}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textGray,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'V 표시된 항목만 출력됩니다. 화살표(▲▼)로 순서를 옮기세요.',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textGray,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _mini('전체', () {
                                  setSheet(() {
                                    sel
                                      ..clear()
                                      ..addAll(
                                        List<int>.generate(
                                          columns.length,
                                          (i) => i,
                                        ),
                                      );
                                  });
                                }),
                                _mini('해제', () => setSheet(() => sel.clear())),
                                _mini('기본', () {
                                  setSheet(() {
                                    sel
                                      ..clear()
                                      ..addAll(
                                        List<int>.generate(
                                          columns.length,
                                          (i) => i,
                                        ),
                                      );
                                    order = List<int>.generate(
                                      columns.length,
                                      (i) => i,
                                    );
                                  });
                                }),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.purple.withValues(
                                    alpha: 0.18,
                                  ),
                                ),
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < order.length; i++)
                                    _colRow(
                                      no: i + 1,
                                      index: order[i],
                                      name: columns[order[i]],
                                      on: sel.contains(order[i]),
                                      onTap: () => setSheet(() {
                                        if (sel.contains(order[i])) {
                                          sel.remove(order[i]);
                                        } else {
                                          sel.add(order[i]);
                                        }
                                      }),
                                      onUp: i > 0 ? () => move(i, -1) : null,
                                      onDown: i < order.length - 1
                                          ? () => move(i, 1)
                                          : null,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.purple,
                          ),
                          onPressed: () {
                            final out = order.where(sel.contains).toList();
                            Navigator.pop(
                              ctx,
                              TableOutputOptions(
                                cols: out,
                                fontSize: fontSize,
                                rowSpace: rowSpace,
                                landscape: allowLandscape ? landscape : null,
                              ),
                            );
                          },
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('이 옵션으로 출력'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _sec(String t) => Text(
  t,
  style: const TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    color: AppColors.textGray,
    letterSpacing: 0.2,
  ),
);

Widget _mini(String label, VoidCallback onTap) => TextButton(
  style: TextButton.styleFrom(
    minimumSize: const Size(0, 30),
    padding: const EdgeInsets.symmetric(horizontal: 8),
  ),
  onPressed: onTap,
  child: Text(label, style: const TextStyle(fontSize: 12)),
);

Widget _seg<T>(
  List<T> values,
  T sel,
  String Function(T) label,
  String Function(T) note,
  void Function(T) onTap,
) {
  return Row(
    children: [
      for (var i = 0; i < values.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => onTap(values[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: values[i] == sel ? AppColors.purple : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: values[i] == sel
                      ? AppColors.purple
                      : const Color(0xFFD8D3CA),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    label(values[i]),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: values[i] == sel
                          ? Colors.white
                          : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    note(values[i]),
                    style: TextStyle(
                      fontSize: 10,
                      color: values[i] == sel
                          ? Colors.white.withValues(alpha: 0.85)
                          : AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

Widget _orient(String label, IconData icon, bool on, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: on ? AppColors.purple : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: on ? AppColors.purple : const Color(0xFFD8D3CA),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: on ? Colors.white : AppColors.textDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: on ? Colors.white : AppColors.textDark,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _colRow({
  required int no,
  required int index,
  required String name,
  required bool on,
  required VoidCallback onTap,
  VoidCallback? onUp,
  VoidCallback? onDown,
}) {
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 17,
            height: 17,
            child: on
                ? const Icon(Icons.check, size: 16, color: AppColors.purple)
                : Icon(
                    Icons.check_box_outline_blank,
                    size: 15,
                    color: AppColors.purple.withValues(alpha: 0.35),
                  ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            width: 18,
            child: Text(
              '$no',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12.5,
                color: on ? AppColors.textDark : AppColors.textGray,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: Icon(
              Icons.keyboard_arrow_up,
              size: 18,
              color: onUp == null
                  ? AppColors.textGray.withValues(alpha: 0.3)
                  : AppColors.purpleDark,
            ),
            onPressed: onUp,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: onDown == null
                  ? AppColors.textGray.withValues(alpha: 0.3)
                  : AppColors.purpleDark,
            ),
            onPressed: onDown,
          ),
        ],
      ),
    ),
  );
}
