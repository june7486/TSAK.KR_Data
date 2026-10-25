/// 행사 결산 탭 — 항목별 취합 · 출력 선택 · 순서 이동 · 실시간 미리보기.
///
/// ## 요구사항 (그대로)
/// "결산페이지 선택시 각 항목별로 취합된 데이터를 보여주고, 출력여부를 그 페이지
///  에서 선택할 수 있도록 하는 기능을 넣자. 그 페이지에서 어디에 넣을지도 항목별
///  위치 이동을 선택할 수 있도록 하며 미리보기 기능을 강화해서 출력시 보여지는
///  내용을 실시간으로 확인하면 편집 할 수 있도록 하자"
///
/// "행사비 결산은 일목요연하게 세부항목별로 보여지게 해야 함. 현재는 그냥
///  나열되어 있어, 읽고 이해하기가 매우 어려움. 참가자 수도 좀더 정리가 잘되고
///  여백이 덜 보이게 세칸또는 그 이상을 사용해서 정리해도 될 듯 함"
///
/// ## 화면 구성
///  ① 블록 카드(참가자 수 / 수입 / 후원 내역 / 지출 분류별 / 지출 계좌별 / 잔액)
///     — 각 카드가 **자기 데이터**를 표로 보여주고, 카드 머리에
///       [출력 포함 체크] [▲▼ 순서이동] 을 둔다.
///  ② 상단 도구줄 — 전체 포함/해제 · 실시간 미리보기 · 결산 출력.
library;

import 'package:flutter/material.dart';

import '../services/event_settlement.dart';
import '../services/settlement_layout.dart';
import '../theme/app_theme.dart';
import '../widgets/settlement_paper_view.dart';

class EventSettlementTab extends StatefulWidget {
  const EventSettlementTab({
    super.key,
    required this.year,
    required this.title,
    required this.attendees,
    required this.fees,
    required this.expenses,
    required this.onOutput,
    required this.onOutputAttendees,
    this.initialLayout,
    this.onLayoutChanged,
  });

  final String year;
  final String title;
  final List<Map<String, dynamic>> attendees;
  final List<Map<String, dynamic>> fees;
  final List<Map<String, dynamic>> expenses;

  /// 결산 출력 — (레이아웃, 블록데이터)를 넘겨 실제 문서를 만든다.
  final void Function(
    SettlementLayout layout,
    Map<SettlementBlock, SettlementBlockData> data,
  )
  onOutput;

  /// 참가자 명단 출력.
  final VoidCallback onOutputAttendees;

  /// 이전에 정한 배치(순서/포함) — 탭을 오가도 유지.
  final SettlementLayout? initialLayout;

  /// 배치가 바뀔 때 알림(상위에서 보관).
  final ValueChanged<SettlementLayout>? onLayoutChanged;

  @override
  State<EventSettlementTab> createState() => _EventSettlementTabState();
}

class _EventSettlementTabState extends State<EventSettlementTab> {
  late SettlementLayout _layout =
      widget.initialLayout?.copy() ?? SettlementLayout();

  /// 펼쳐 본 블록(집계 근거 원본 행 보기).
  final Set<SettlementBlock> _expanded = <SettlementBlock>{};

  SettlementLayout get _layoutRef => _layout;

  void _bump(VoidCallback fn) {
    setState(fn);
    widget.onLayoutChanged?.call(_layoutRef.copy());
  }

  // ------------------------------------------------------------- 데이터
  EventSettlement get _settlement => EventSettlement(
    title: widget.title,
    year: widget.year,
    attendeeCount: EventAttendeeBreakdown.fromAttendees(widget.attendees),
    attendees: widget.attendees,
    fees: widget.fees.map((e) => EventMoneyRow.fromMap(e)).toList(),
    expenses: widget.expenses
        .map((e) => EventMoneyRow.fromMap(e, expense: true))
        .toList(),
  );

  Map<SettlementBlock, SettlementBlockData> get _data =>
      SettlementBuilder.build(
        settlement: _settlement,
        fees: widget.fees,
        expenses: widget.expenses,
        attendees: widget.attendees,
        won: _won,
        // (요구) "결산시에도 메모 내역을 추가" — 미리보기의 '메모' 스위치를 따른다.
        memo: _layout.showMemo,
      );

  String _won(int v) => '${EventSettlement.comma(v)}원';

  Future<void> _openPreview() async {
    final data = _data;
    final out = await showSettlementPreviewSheet(
      context,
      layout: _layout,
      data: data,
      title: '${widget.year} ${widget.title} · 결산서',
    );
    if (out != null) {
      _bump(() => _layout = out);
    }
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final data = _data;
    final s = _settlement;

    return Column(
      children: [
        _toolbar(data),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
            buildDefaultDragHandles: false,
            itemCount: _layout.order.length,
            onReorder: (oldI, newI) {
              _bump(() {
                final b = _layout.order.removeAt(oldI);
                _layout.order.insert(newI > oldI ? newI - 1 : newI, b);
              });
            },
            itemBuilder: (_, i) {
              final block = _layout.order[i];
              return _blockCard(
                key: ValueKey(block.name),
                index: i,
                block: block,
                d: data[block],
                s: s,
              );
            },
          ),
        ),
        _bottomBar(),
      ],
    );
  }

  // 도구줄 — 전체 포함/해제 · 서식 배지 · 요약
  Widget _toolbar(Map<SettlementBlock, SettlementBlockData> data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _mini(
                label: '전체 포함',
                icon: Icons.done_all,
                onTap: () => _bump(_layout.includeAll),
              ),
              const SizedBox(width: 5),
              _mini(
                label: '전체 해제',
                icon: Icons.deselect,
                onTap: () => _bump(_layout.excludeAll),
              ),
              const Spacer(),
              Text(
                '${_layout.includedCount}/${_layout.order.length} 항목 출력',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _layout.isFiltered
                      ? AppColors.tigerGold
                      : AppColors.scoutGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 서식 줄 — 미리보기에서 정한 서식이 지금 출력에 걸려 있음을 보여준다.
          Row(
            children: [
              Icon(
                Icons.tune,
                size: 12,
                color: _layout.isStyled ? AppColors.purple : AppColors.textGray,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _layout.styleBadge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _layout.isStyled
                        ? AppColors.purple
                        : AppColors.textGray,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _bump(_layout.resetStyle),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  child: Text(
                    '서식 초기화',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textGray,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.purple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.purple.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: AppColors.purple),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 블록 카드
  Widget _blockCard({
    required Key key,
    required int index,
    required SettlementBlock block,
    required SettlementBlockData? d,
    required EventSettlement s,
  }) {
    final on = _layout.includes(block);
    final color = _colorOf(block);
    final rows = d?.rows ?? const <List<String>>[];

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: on
                ? color.withValues(alpha: 0.30)
                : AppColors.textGray.withValues(alpha: 0.20),
            width: on ? 1.2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 카드 머리: 포함체크 · 제목 · 순서 · 드래그 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: on ? '출력에서 제외' : '출력에 포함',
                    icon: Icon(
                      on ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 20,
                      color: on ? color : AppColors.textGray,
                    ),
                    onPressed: () => _bump(() => _layout.toggle(block)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${index + 1}. ${block.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: on ? color : AppColors.textGray,
                              ),
                            ),
                            if (d?.empty == true) ...[
                              const SizedBox(width: 5),
                              const Text(
                                '(내역 없음)',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textGray,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          block.hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 원본 내역 펼쳐보기 — 집계의 근거를 그 자리에서 확인.
                  if (d?.hasDetails == true)
                    InkWell(
                      onTap: () => setState(() {
                        if (!_expanded.remove(block)) _expanded.add(block);
                      }),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 3,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '내역 ${d!.details.length}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                            Icon(
                              _expanded.contains(block)
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 15,
                              color: color,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // 순서 이동
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '위로',
                    icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                    onPressed: index == 0
                        ? null
                        : () => _bump(() => _layout.moveUp(block)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '아래로',
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                    onPressed: index == _layout.order.length - 1
                        ? null
                        : () => _bump(() => _layout.moveDown(block)),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(
                        Icons.drag_handle,
                        size: 20,
                        color: AppColors.textGray,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── 본문: 항목별 취합 표 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _blockTable(rows, color, faded: !on),
                  if (_expanded.contains(block) && (d?.hasDetails ?? false))
                    _detailList(d!.details, color),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 집계 근거 원본 행 목록 — '내역 N' 을 누르면 펼쳐진다.
  Widget _detailList(List<String> details, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '·',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: color.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      s,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (details.length > 40) ...[
            const SizedBox(height: 2),
            Text(
              '… 외 ${details.length - 40}건 (출력에는 모두 포함됩니다)',
              style: const TextStyle(fontSize: 10, color: AppColors.textGray),
            ),
          ],
        ],
      ),
    );
  }

  /// 3열 [항목 · 금액/인원 · 비고] 취합 표 — 여백을 줄이고 3칸을 알차게 쓴다.
  ///
  /// (요구) "참가자 수도 좀더 정리가 잘되고 여백이 덜 보이게 세칸또는 그
  ///  이상을 사용해서 정리해도 될 듯 함"
  /// → 참가자 수는 3번째 칸에 **비율 막대**, 나머지 블록은 건수/비고를 넣는다.
  Widget _blockTable(
    List<List<String>> rows,
    Color color, {
    bool faded = false,
  }) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text(
          '내역 없음',
          style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
        ),
      );
    }
    return Opacity(
      opacity: faded ? 0.45 : 1,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.15),
          1: FlexColumnWidth(1.35),
          2: FlexColumnWidth(1.15),
        },
        border: TableBorder(
          horizontalInside: BorderSide(
            color: color.withValues(alpha: 0.10),
            width: 0.8,
          ),
        ),
        children: [
          for (final r in rows)
            TableRow(
              decoration: _isTotalRow(r)
                  ? BoxDecoration(color: color.withValues(alpha: 0.055))
                  : null,
              children: [
                _cell(
                  r.isNotEmpty ? r[0] : '',
                  bold: true,
                  color: _isTotalRow(r) ? color : AppColors.textDark,
                ),
                _cell(
                  r.length > 1 ? r[1] : '',
                  align: TextAlign.right,
                  bold: _isTotalRow(r),
                  color: _isTotalRow(r) ? color : AppColors.textDark,
                ),
                // 참가자 수 블록은 3번째 칸을 비율 막대로 쓴다(여백 대신 정보).
                _thirdCell(r, color),
              ],
            ),
        ],
      ),
    );
  }

  bool _isTotalRow(List<String> r) {
    final k = r.isNotEmpty ? r[0] : '';
    return k.contains('합계') || k == '합계' || k == '잔액' || k == '초과';
  }

  Widget _thirdCell(List<String> r, Color color) {
    final value = r.length > 1 ? r[1] : '';
    // 'N명' 형태면 막대로 시각화(참가자 수 정리를 한눈에).
    final m = RegExp(r'^(\d+)명$').firstMatch(value);
    if (m == null) {
      // 그 밖의 블록은 비고(3번째 칸) 문자열을 그대로 보여준다.
      final note = r.length > 2 ? r[2] : '';
      if (note.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
        child: Text(
          note,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.75),
          ),
        ),
      );
    }
    final n = int.tryParse(m.group(1) ?? '') ?? 0;
    if (n <= 0) return const SizedBox.shrink();
    // 최대 30명 기준으로 길이를 잡는다(작은 값도 보이게).
    final ratio = (n / 30).clamp(0.05, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: ratio,
          child: Container(
            height: 7,
            decoration: BoxDecoration(
              color: (_isTotalRow(r) ? AppColors.purple : AppColors.taegeukBlue)
                  .withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(
    String text, {
    TextAlign align = TextAlign.left,
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
      child: Text(
        text,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.8,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: color ?? AppColors.textDark,
        ),
      ),
    );
  }

  // 하단 고정 버튼 — 미리보기 / 결산 출력 / 명단 출력
  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0DBD2))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.purple,
                side: BorderSide(
                  color: AppColors.purple.withValues(alpha: 0.45),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _openPreview,
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text(
                '미리보기',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            flex: 3,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _layout.includedCount == 0
                  ? null
                  : () => widget.onOutput(_layout.copy(), _data),
              icon: const Icon(Icons.ios_share, size: 17),
              label: const Text(
                '결산 출력',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _colorOf(SettlementBlock b) => switch (b) {
    SettlementBlock.attendees => AppColors.taegeukBlue,
    SettlementBlock.income => AppColors.scoutGreen,
    SettlementBlock.sponsor => AppColors.tigerGold,
    SettlementBlock.expenseCategory => AppColors.taegeukRed,
    SettlementBlock.expenseAccount => AppColors.purple,
    SettlementBlock.balance => AppColors.masterInk,
  };
}
