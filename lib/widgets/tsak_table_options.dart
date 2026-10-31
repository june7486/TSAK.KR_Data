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
      // 두줄 방지 대상 열(헤더 이름). (요구: 두줄방지 항목 선택)
      final noWrap = <String>{...?initial?.noWrap};
      // (요구 2026-10-31) 항목이 많을 때 **가로줄을 하나 더** — 표를 두 단으로.
      var twoBands = (initial?.effectiveRowBands ?? 1) > 1;
      // 셀 줄 수 — 이름하나당 2줄 이상 허용.
      int? cellLines = initial?.cellLines;

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
                          // ── 두 단 (가로줄 추가) · 셀 줄 수 ──
                          //   (요구) "항목이 많을 경우에는 가로줄을 하나 더 추가해서
                          //    두줄방지 되도록 할 수 있는 옵션도 추가해줘"
                          _sec('항목이 많을 때 (열이 10개 이상)'),
                          const SizedBox(height: 6),
                          _toggleRow(
                            icon: Icons.view_agenda_outlined,
                            title: '두 단으로 나누기',
                            note: '표를 위/아래로 쌓아 열당 폭을 2배로. 단 사이에 가로줄이 하나 더 생깁니다.',
                            value: twoBands,
                            onChanged: (v) => setSheet(() => twoBands = v),
                          ),
                          const SizedBox(height: 8),
                          _sec('셀 줄 수 (이름하나당)'),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              for (final v in const <int?>[null, 1, 2, 3]) ...[
                                if (v != null) const SizedBox(width: 8),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setSheet(() => cellLines = v),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 9,
                                      ),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: cellLines == v
                                            ? AppColors.purple
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: cellLines == v
                                              ? AppColors.purple
                                              : const Color(0xFFD8D3CA),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            v == null ? '자동' : '$v줄',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: cellLines == v
                                                  ? Colors.white
                                                  : AppColors.textDark,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            v == null
                                                ? '1줄 유지'
                                                : '최대 $v줄',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: cellLines == v
                                                  ? Colors.white.withValues(
                                                      alpha: 0.85,
                                                    )
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
                          ),
                          const SizedBox(height: 18),
                          // ── 두줄 방지 항목 선택 ──
                          //   (요구: "행사참가 출력파일 … 두줄방지 항목을 선택할 수 있도록")
                          //   체크한 열은 줄바꿈하지 않고 한 줄로 출력된다(넘치면 자동 축소).
                          Row(
                            children: [
                              _sec('두줄 방지 (한 줄로 출력)'),
                              const Spacer(),
                              Text(
                                '${noWrap.length}개',
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
                            '체크한 항목은 두 줄로 접히지 않습니다. 이름·인가번호처럼 짧은 항목에 권장.',
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
                                  noWrap
                                    ..clear()
                                    ..addAll(columns);
                                });
                              }),
                              _mini('해제', () => setSheet(() => noWrap.clear())),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final c in columns)
                                _noWrapChip(
                                  c,
                                  noWrap.contains(c),
                                  () => setSheet(() {
                                    if (noWrap.contains(c)) {
                                      noWrap.remove(c);
                                    } else {
                                      noWrap.add(c);
                                    }
                                  }),
                                ),
                            ],
                          ),
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
                                noWrap: noWrap,
                                rowBands: twoBands ? 2 : 1,
                                bandAnchors:
                                    initial?.bandAnchors ?? const <String>{},
                                cellLines: cellLines,
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

/// 두줄 방지 선택 칩 — 테두리 토글.
Widget _noWrapChip(String label, bool on, VoidCallback onTap) => InkWell(
  onTap: onTap,
  borderRadius: BorderRadius.circular(20),
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: on ? AppColors.purple : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: on ? AppColors.purple : const Color(0xFFD8D3CA),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          on ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: on ? Colors.white : AppColors.textGray,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w800 : FontWeight.w500,
            color: on ? Colors.white : AppColors.textDark,
          ),
        ),
      ],
    ),
  ),
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

/// 스위치 한 줄 — 제목 + 설명 + 스위치.
Widget _toggleRow({
  required IconData icon,
  required String title,
  required String note,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: value ? AppColors.purple : const Color(0xFFD8D3CA),
      ),
    ),
    child: Row(
      children: [
        Icon(icon, size: 17, color: value ? AppColors.purple : AppColors.textGray),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: value ? AppColors.purpleDark : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                note,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textGray,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          trackColor: WidgetStatePropertyAll(
            value ? AppColors.purple : const Color(0xFFCFC9C0),
          ),
          trackOutlineColor: WidgetStatePropertyAll(
            value ? AppColors.purple : const Color(0xFFCFC9C0),
          ),
        ),
      ],
    ),
  );
}
