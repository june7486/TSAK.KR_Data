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
import '../services/file_save.dart';
import '../services/output_formats.dart';
import '../services/settlement_doc.dart';
import '../services/settlement_layout.dart';
import '../services/table_export.dart';
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
    this.onPrint,
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

  /// 결산 **인쇄**(브라우저 인쇄창) — 미리보기 시트 안에서 바로 호출된다.
  final void Function(
    SettlementLayout layout,
    Map<SettlementBlock, SettlementBlockData> data,
  )?
  onPrint;

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

  /// 상세 내역을 **끝까지** 펼친 블록 — 없으면 미리보기 [_detailPreviewLimit] 줄만.
  ///
  /// (요구 2026-10-27) "결산 기본페이지에도 … 상세내역을 노출할 것"
  /// 2,233명짜리 행사에서 참가자 상세를 전부 펼치면 카드 하나가 화면 수십 개가
  /// 된다. 그래서 **먼저 몇 줄 보여주고** 필요하면 '더 보기'로 끝까지 편다.
  /// (줄 단위 체크는 펼친 뒤에도 그대로 동작한다)
  final Set<SettlementBlock> _detailExpanded = <SettlementBlock>{};

  /// 접힌 상태에서 보여줄 상세 줄 수.
  static const int _detailPreviewLimit = 12;

  /// 파일 내보내기 진행 중 — 중복 클릭 방지.
  bool _exporting = false;

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
      // (요구) "미리보기 창에 출력버튼을 추가해서 창을 이동시키지 않아도
      //  실시간으로 보면서 바로 출력할 수 있도록 해줘"
      //
      //  시트 안에서 PDF 를 뽑으면, 시트에 남아 있는 **현재 레이아웃**을
      //  상위(결산 탭)에도 즉시 반영한다. 그래야 시트를 닫았을 때
      //  결산 탭 카드 순서·서식이 방금 맞춘 것과 어긋나지 않는다.
      onExport: (layout, format, open) {
        _bump(() => _layout = layout.copy());
        widget.onOutput(
          layout,
          SettlementBuilder.build(
            settlement: _settlement,
            fees: widget.fees,
            expenses: widget.expenses,
            attendees: widget.attendees,
            won: _won,
            memo: layout.showMemo,
          ),
        );
      },
      onPrint: (layout) {
        _bump(() => _layout = layout.copy());
        widget.onPrint?.call(
          layout,
          SettlementBuilder.build(
            settlement: _settlement,
            fees: widget.fees,
            expenses: widget.expenses,
            attendees: widget.attendees,
            won: _won,
            memo: layout.showMemo,
          ),
        );
      },
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
          // ── [요구 2026-10-27] 상세 내역 **전체 출력** 스위치 ─────────────
          //  "상세항목을 선택하면 모든 상세가 다 보여지는 기능으로 하면 좋겠음"
          //
          //  종전에는 PDF 빌더에 상한 40줄이 하드코딩돼 있어, 상세를 켜도
          //  41건째부터는 `… 외 N건 (출력에서 제외)` 로 잘렸다. 상한을 올릴
          //  방법이 아예 없었다. 여기서 한 번 켜면 상한이 사라진다.
          Row(
            children: [
              Icon(
                Icons.all_inclusive,
                size: 12,
                color: _layout.detailMax >= SettlementLayout.detailMaxAll
                    ? AppColors.purple
                    : AppColors.textGray,
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _bump(
                  () => _layout.detailMax =
                      _layout.detailMax >= SettlementLayout.detailMaxAll
                      ? 40
                      : SettlementLayout.detailMaxAll,
                ),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    _layout.detailMax >= SettlementLayout.detailMaxAll
                        ? '상세 전체 출력 중'
                        : '상세 전체 출력',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: _layout.detailMax >= SettlementLayout.detailMaxAll
                          ? AppColors.purple
                          : AppColors.textGray,
                    ),
                  ),
                ),
              ),
              const Spacer(),
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
                  // 상세 내역 요약 배지 — 본문은 이제 **항상 펼쳐져** 있으므로
                  //  (요구 2026-10-27) 접기/펼치기 대신 '몇 건 중 몇 건이
                  //  출력되는지'만 보여준다. 부분 선택이면 금색으로 경고.
                  if (d?.hasDetails == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '상세 ${_layout.visibleDetailCount(block, d!.details.length)}'
                        '/${d.details.length}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color:
                              _layout.visibleDetailCount(
                                    block,
                                    d.details.length,
                                  ) ==
                                  d.details.length
                              ? color
                              : AppColors.tigerGold,
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
                  _blockTable(
                    rows,
                    color,
                    faded: !on,
                    block: block,
                    enabled: on,
                  ),
                  // ── [요구 2026-10-27] 상세 내역을 **기본으로 펼쳐** 보여주고,
                  //    각 줄 오른쪽 끝에 체크박스를 둔다. ──────────────
                  //
                  //  "결산 기본페이지에도 출력 미리보기 상세항목처럼 상세내역을
                  //   노출할 것 (모든 항목의 우측 끝에, 그 항목에 체크박스를
                  //   넣어서 출력시 포함할지 여부를 선택할 수 있도록 직관적으로
                  //   만들 것, 기본값은 모두 선택)"
                  //
                  //  종전에는 '내역 N' 버튼을 **눌러야** 펼쳐졌고, 펼친 목록은
                  //  읽기 전용이었다(출력 여부는 미리보기 시트에 가서야 정할 수
                  //  있었다). 이제는 카드에서 바로 보이고 바로 고칠 수 있다.
                  if (d != null && d.hasDetails) ...[
                    const SizedBox(height: 5),
                    _detailCheckList(block, d, color, enabled: on),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 상세 내역 체크 목록 — 각 줄 오른쪽 끝에 출력 포함 체크박스.
  ///
  /// ## [요구 2026-10-27] (그대로)
  /// "결산 기본페이지에도 출력 미리보기 상세항목처럼 상세내역을 노출할 것
  ///  (모든 항목의 우측 끝에, 그 항목에 체크박스를 넣어서 출력시 포함할지
  ///   여부를 선택할 수 있도록 직관적으로 만들 것, 기본값은 모두 선택)"
  ///
  /// ## 설계
  ///  · 블록 헤더 우측의 마스터 체크로 **그 블록 전체**를 한 번에 켜고 끈다.
  ///    (부분 선택 상태면 `-(dash)` 아이콘 → "일부만 선택됨"이 한눈에 보인다)
  ///  · 줄마다 체크박스 — 기본값은 전부 선택([SettlementLayout.detailLineOff]
  ///    가 비어 있으면 전부 포함).
  ///  · 끈 줄은 글자에 **취소선 + 흐림** → 목록에서 사라지지 않으므로
  ///    "빠뜨렸다"가 아니라 "내가 뺐다"로 읽힌다.
  ///  · 상세 줄이 많을 때(기본 12줄 초과)는 접어 두고 `더 보기` 로 펼친다.
  ///    (2,233명 행사에서 카드가 끝없이 길어지는 것을 막는다)
  Widget _detailCheckList(
    SettlementBlock block,
    SettlementBlockData d,
    Color color, {
    required bool enabled,
  }) {
    final total = d.details.length;
    final shown = _layout.visibleDetailCount(block, total);
    final allOn = shown == total;
    final noneOn = shown == 0;
    final expanded = _detailExpanded.contains(block);
    final limit = expanded ? total : _detailPreviewLimit;
    final visible = total > limit ? limit : total;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 블록 헤더: 상세 내역 제목 + 전체 선택 체크 (우측 끝) ──
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 2),
            child: Row(
              children: [
                Icon(
                  Icons.subject,
                  size: 12,
                  color: color.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    '상세 내역 $shown/$total건 출력',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: allOn
                          ? color
                          : (noneOn ? AppColors.textGray : AppColors.tigerGold),
                    ),
                  ),
                ),
                // 전체 선택/해제 — 우측 끝.
                _detailCheck(
                  checked: allOn,
                  partial: !allOn && !noneOn,
                  color: color,
                  tooltip: allOn ? '상세 전체 해제' : '상세 전체 선택',
                  enabled: enabled,
                  label: '전체',
                  onTap: () => _bump(() {
                    // 하나라도 꺼져 있으면 '전부 켜기'로 동작(직관적 토글).
                    _layout.setBlockDetailLines(block, !allOn, total);
                  }),
                ),
              ],
            ),
          ),
          // ── 줄별 체크 목록 ──
          for (var i = 0; i < visible; i++)
            _detailLine(
              block: block,
              index: i,
              text: d.details[i],
              color: color,
              enabled: enabled,
            ),
          if (total > visible)
            InkWell(
              onTap: () => setState(() => _detailExpanded.add(block)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '… 외 ${total - visible}건 더 보기',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            )
          else if (expanded && total > _detailPreviewLimit)
            InkWell(
              onTap: () => setState(() => _detailExpanded.remove(block)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '접기',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 상세 줄 1건 — 왼쪽에 원본 내용, **오른쪽 끝에 체크박스**.
  Widget _detailLine({
    required SettlementBlock block,
    required int index,
    required String text,
    required Color color,
    required bool enabled,
  }) {
    final on = _layout.showsDetailLine(block, index);
    return InkWell(
      onTap: enabled
          ? () => _bump(() => _layout.toggleDetailLine(block, index))
          : null,
      borderRadius: BorderRadius.circular(5),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '·',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: color.withValues(alpha: on ? 0.65 : 0.25),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  // 끈 줄은 취소선 + 흐림 — 목록에는 남겨 '내가 뺐다'를 보인다.
                  decoration: on ? null : TextDecoration.lineThrough,
                  color: on
                      ? AppColors.textDark
                      : AppColors.textGray.withValues(alpha: 0.75),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _detailCheck(
              checked: on,
              partial: false,
              color: color,
              tooltip: on ? '출력에서 제외' : '출력에 포함',
              enabled: enabled,
              onTap: () => _bump(() => _layout.toggleDetailLine(block, index)),
            ),
          ],
        ),
      ),
    );
  }

  /// 체크박스 하나 — 3상태(선택/미선택/부분)를 시각적으로 구분한다.
  Widget _detailCheck({
    required bool checked,
    required bool partial,
    required Color color,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
    String? label,
  }) {
    final icon = checked
        ? Icons.check_box
        : (partial
              ? Icons.indeterminate_check_box
              : Icons.check_box_outline_blank);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != null) ...[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: checked ? color : AppColors.textGray,
                  ),
                ),
                const SizedBox(width: 2),
              ],
              Icon(
                icon,
                size: 17,
                color: enabled
                    ? (checked || partial ? color : AppColors.textGray)
                    : AppColors.textGray.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 3열 [항목 · 금액/인원 · 비고] 취합 표 — 여백을 줄이고 3칸을 알차게 쓴다.
  ///
  /// (요구) "참가자 수도 좀더 정리가 잘되고 여백이 덜 보이게 세칸또는 그
  ///  이상을 사용해서 정리해도 될 듯 함"
  /// → 참가자 수는 3번째 칸에 **비율 막대**, 나머지 블록은 건수/비고를 넣는다.
  /// 블록 표 — **모든 줄 오른쪽 끝에 출력 포함 체크박스**.
  ///
  /// ## [요구 2026-10-27] "나머지 항목에도 체크박스를 넣어줘요"
  ///
  /// 종전에는 체크박스가 `상세 내역`(원본 행)에만 있었고, 그 상세가 없는
  /// 블록(수입=합계 1줄 등)은 체크박스가 **하나도 안 보였다**. 사용자가
  /// '참가자 수'에는 체크가 보이는데 '수입'에는 없는 화면을 보고 지적한 것.
  /// → 이제 **표의 모든 행**이 자기 체크박스를 갖는다. 기본값은 전부 선택.
  ///   (끈 행은 취소선 + 흐림 → 목록에서 사라지지 않아 '내가 뺐다'로 읽힌다)
  Widget _blockTable(
    List<List<String>> rows,
    Color color, {
    bool faded = false,
    SettlementBlock? block,
    bool enabled = true,
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
          // 체크박스 전용 칸 — 모든 행의 우측 끝.
          3: FixedColumnWidth(32),
        },
        border: TableBorder(
          horizontalInside: BorderSide(
            color: color.withValues(alpha: 0.10),
            width: 0.8,
          ),
        ),
        children: [
          for (var i = 0; i < rows.length; i++)
            TableRow(
              decoration: _isTotalRow(rows[i])
                  ? BoxDecoration(color: color.withValues(alpha: 0.055))
                  : null,
              children: [
                _cell(
                  rows[i].isNotEmpty ? rows[i][0] : '',
                  bold: true,
                  color: _isTotalRow(rows[i]) ? color : AppColors.textDark,
                ),
                _cell(
                  rows[i].length > 1 ? rows[i][1] : '',
                  align: TextAlign.right,
                  bold: _isTotalRow(rows[i]),
                  color: _isTotalRow(rows[i]) ? color : AppColors.textDark,
                ),
                // 참가자 수 블록은 3번째 칸을 비율 막대로 쓴다(여백 대신 정보).
                _thirdCell(rows[i], color),
                // ── 우측 끝: 출력 포함 체크박스 ──
                _rowCheck(
                  checked: block == null
                      ? true
                      : _layout.showsRow(block, i),
                  enabled: enabled && block != null,
                  color: color,
                  onTap: () {
                    if (block == null || !enabled) return;
                    _bump(() => _layout.toggleRow(block, i));
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 표 행 우측 끝 체크박스 — 출력 포함 여부.
  Widget _rowCheck({
    required bool checked,
    required bool enabled,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Icon(
          checked ? Icons.check_box : Icons.check_box_outline_blank,
          size: 18,
          color: !enabled
              ? AppColors.textGray.withValues(alpha: 0.4)
              : (checked ? color : AppColors.textGray),
        ),
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

  // 하단 고정 버튼 — 미리보기 / PDF / JPG / 엑셀 / 워드 / 결산 출력
  //
  // (요구) "PDF, JPG, 엑셀, 워드파일 등도 넣어줘"
  //  → 종전 하단은 [미리보기] [결산 출력] 두 개뿐이라, 파일을 뽑으려면
  //    시트를 열고 → 형식을 다시 고르고 → 저장 위치를 또 고르는 3단계였다.
  //    이제 **한 줄에서 바로** 형식을 골라 뽑는다. 미리보기는 그대로 남긴다.
  Widget _bottomBar() {
    final empty = _layout.includedCount == 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 9),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0DBD2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 1줄: 미리보기(실시간) + 결산 출력(옵션 시트) ──
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.purple,
                    side: BorderSide(
                      color: AppColors.purple.withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: _openPreview,
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text(
                    '미리보기',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: empty
                      ? null
                      : () => widget.onOutput(_layout.copy(), _data),
                  icon: const Icon(Icons.ios_share, size: 16),
                  label: const Text(
                    '결산 출력',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── 2줄: 파일 형식 바로 뽑기(PDF · JPG · 엑셀 · 워드) ──
          Row(
            children: [
              for (final f in const [
                TsakOutputFormat.pdf,
                TsakOutputFormat.jpg,
                TsakOutputFormat.excel,
                TsakOutputFormat.word,
              ]) ...[
                Expanded(child: _fmtButton(f, enabled: !empty)),
                if (f != TsakOutputFormat.word) const SizedBox(width: 5),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 형식 버튼 1개 — 지금 서식(_layout) 그대로 파일을 만든다.
  Widget _fmtButton(TsakOutputFormat f, {required bool enabled}) {
    final accent = switch (f) {
      TsakOutputFormat.pdf => AppColors.taegeukRed,
      TsakOutputFormat.jpg => AppColors.taegeukBlue,
      TsakOutputFormat.excel => AppColors.scoutGreen,
      TsakOutputFormat.word => AppColors.purple,
      _ => AppColors.textGray,
    };
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        side: BorderSide(color: accent.withValues(alpha: enabled ? 0.45 : 0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: enabled ? () => _export(f) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(f.icon, size: 15, color: enabled ? accent : AppColors.textGray),
          const SizedBox(height: 1),
          Text(
            f.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: enabled ? accent : AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }

  /// 지금 화면의 항목·순서·서식·템플릿 그대로 파일을 만든다.
  ///
  /// (요구) "실시간으로 미리보기 화면을 보면서 출력물의 내용과 디자인을 보면서
  ///  선택할 수 있도록" → 미리보기에서 고른 값이 [_layout] 에 남아 있으므로,
  ///  이 버튼은 **화면에 보이는 그대로** 뽑는다(왕복 없음).
  Future<void> _export(TsakOutputFormat format) async {
    if (_exporting) return;
    if (_layout.includedCount == 0) {
      _snack('출력할 항목이 없습니다');
      return;
    }
    final data = _data;
    final doc = SettlementDoc.build(
      year: widget.year,
      title: widget.title,
      layout: _layout,
      data: data,
      settlement: _settlement,
    );
    final opt = await askSaveOption(
      context,
      info: '${widget.year} ${widget.title} · 결산서 · ${format.label}',
    );
    if (opt == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final file = await buildTsakTableFile(doc, format);
      await saveFileOption(
        bytes: file.bytes,
        filename: '${doc.baseName()}.${file.ext}',
        mime: file.mime,
        option: opt,
      );
      _snack('결산서 ${format.label} 내보내기를 시작했습니다');
    } catch (e) {
      _snack('내보내기 실패: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  static Color _colorOf(SettlementBlock b) => switch (b) {
    SettlementBlock.attendees => AppColors.taegeukBlue,
    // [요구 2026-10-27] "후원 … 항목의 텍스트 컬러를 에르메스오렌지색으로
    //  변경해줘 → 현재 안보임"
    //  tigerGold(0xFFF2B705)는 흰 카드 위에서 대비 1.9:1 이라 11pt 글씨가
    //  사실상 사라져 보였다. 에르메스 오렌지(진한 쪽)로 바꾼다.
    SettlementBlock.income => AppColors.scoutGreen,
    SettlementBlock.sponsor => AppColors.hermesInk,
    SettlementBlock.expenseCategory => AppColors.taegeukRed,
    SettlementBlock.expenseAccount => AppColors.purple,
    SettlementBlock.balance => AppColors.masterInk,
  };
}
