/// 결산서 실시간 미리보기 — 옆에서 편집하면 즉시 반영.
///
/// ## 요구사항 (그대로)
/// "미리보기 기능을 강화해서 출력시 보여지는 내용을 실시간으로 확인하면
///  편집 할 수 있도록 하자"
///
/// ## 설계
/// PDF 래스터화(느림) 대신 **위젯 표**로 그린다. 그래서
///  · 블록 포함/제외·순서 이동이 **즉시** 반영되고
///  · 표를 직접 만지며(글씨·줄간격·가로/세로·2줄방지) 결과를 확인할 수 있고
///  · 그 상태 그대로 PDF·인쇄로 넘어간다(같은 [SettlementLayout] 사용).
///
/// ## 이번 개선
/// 종전 미리보기는 **보기 전용**이었고, 슬라이더로 고친 서식은 화면에만 적용된
/// 뒤 버려졌다(실제 인쇄물은 기본 서식). 이제 서식은 [SettlementLayout] 에
/// 담겨 **출력 문서까지 그대로** 따라간다 — "보이는 것 = 인쇄되는 것".
library;

import 'package:flutter/material.dart';

import '../services/event_settlement.dart';
import '../services/output_formats.dart';
import '../services/output_templates.dart';
import '../services/settlement_layout.dart';
import '../theme/app_theme.dart';

/// 결산서 표를 화면에서 그대로 보여주는 위젯.
///
/// 문서(PDF)와 **같은 열 구성**(구분 / 항목 / 금액·인원 / 비고)을 쓴다.
class SettlementPaperView extends StatelessWidget {
  const SettlementPaperView({
    super.key,
    required this.layout,
    required this.data,
    this.fontScale = 1.0,
    this.rowSpace = 1.0,
    this.landscape = false,
    this.noWrap = true,
    this.maxHeight,
  });

  final SettlementLayout layout;
  final Map<SettlementBlock, SettlementBlockData> data;

  /// 글씨 배율(0.86 ~ 1.26).
  final double fontScale;

  /// 줄 간격 배율(0.72 ~ 1.5).
  final double rowSpace;

  /// 가로(넓은) 용지 여부 — 좌우 여백만 조절한다.
  final bool landscape;

  /// 두 줄 방지 — true 면 모든 칸을 한 줄로 자른다.
  final bool noWrap;

  final double? maxHeight;

  double get _fs => 11.2 * fontScale;

  /// 지금 미리보기에 적용할 템플릿 — 표형이면 띠/카드를 쓰지 않는다.
  DocTemplate get _tpl =>
      layout.reportStyle ? layout.template : DocTemplate.minimal;

  /// 카드형이면 블록을 둥근 테두리로 감싼다(다른 템플릿은 그대로 통과).
  Widget _tplShell(Widget child) {
    if (!_tpl.cardShell) return child;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color(0xFFCDE7CD).withValues(alpha: 0.9),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = layout.included;
    final pad = landscape ? 16.0 : 11.0;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8D3CA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 인장형 — 문서 위쪽 **이중 실선**(PDF 의 buildBackground 와 같은 규칙).
            if (_tpl.doubleRule) _doubleRule(),
            if (blocks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    '출력할 항목이 없습니다\n왼쪽에서 항목을 켜 주세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textGray,
                      height: 1.5,
                    ),
                  ),
                ),
              )
            else ...[
              for (var i = 0; i < blocks.length; i++)
                _blockTable(blocks[i], data[blocks[i]], i == 0),
              // 요약 꼬리 — 실제 문서의 summary 줄과 같은 내용.
              if (blocks.any((b) => b == SettlementBlock.balance))
                const SizedBox.shrink(),
              // 인장형 — 확인 도장 칸(화면에서도 그대로 보여야 '보이는 것 = 인쇄').
              if (_tpl.stampBox) _stampBox(),
              if (_tpl.doubleRule) _doubleRule(),
            ],
          ],
        ),
      ),
    );
  }

  /// 인장형 전용 — 이중 실선(굵은 선 + 가는 선).
  Widget _doubleRule() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Container(height: 1.7, color: const Color(0xFF6B6660)),
          const SizedBox(height: 2.4),
          Container(height: 0.8, color: const Color(0xFFB9B3A9)),
        ],
      ),
    );
  }

  /// 인장형 전용 — 작성·확인·승인 도장 칸.
  Widget _stampBox() {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (final role in const ['작성', '확인', '승인'])
            Container(
              width: 62,
              margin: const EdgeInsets.only(left: 4),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF6B6660)),
                    ),
                    child: Text(
                      role,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: _fs * 0.66,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: const Color(0xFF6B6660)),
                        right: BorderSide(color: const Color(0xFF6B6660)),
                        bottom: BorderSide(color: const Color(0xFF6B6660)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _blockTable(
    SettlementBlock block,
    SettlementBlockData? d,
    bool first,
  ) {
    final rows = d?.rows ?? const <List<String>>[];
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : _tpl.blockGap * rowSpace),
      child: _tplShell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 블록 제목 띠 — 템플릿이 띠/밑줄을 결정한다.
            Container(
              padding: _tpl.accentBand
                  ? EdgeInsets.fromLTRB(
                      _tpl.cellPadH + (_tpl.isSolidBand ? 0 : 1),
                      3.4 * rowSpace,
                      _tpl.cellPadH + 1,
                      3.4 * rowSpace,
                    )
                  : const EdgeInsets.only(bottom: 3),
              decoration: _tpl.accentBand
                  ? BoxDecoration(
                      // 색면형은 원색으로 **꽉 채운다**(PDF 와 같은 규칙).
                      color: _tpl.isSolidBand
                          ? _blockColor(block).withValues(alpha: 0.92)
                          : _blockColor(
                              block,
                            ).withValues(alpha: _tpl.bandAlpha),
                      border: _tpl.isSolidBand
                          ? null
                          : (_tpl.bandWidth > 0
                                ? Border(
                                    left: BorderSide(
                                      color: _blockColor(block),
                                      width: _tpl.bandWidth,
                                    ),
                                  )
                                : null),
                    )
                  : BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: const Color(0xFFDBD6CC),
                          width: _tpl.gridLines ? 0.9 : 0.6,
                        ),
                      ),
                    ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      block.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _fs * (_tpl.bigFigures ? 1.06 : 0.94),
                        fontWeight: FontWeight.w900,
                        // 색면형은 흰 글씨 — 어두운 배경 위에서 읽히게.
                        color: _tpl.isSolidBand
                            ? Colors.white
                            : (_tpl.accentBand || _tpl.cardShell
                                  ? _blockColor(block)
                                  : AppColors.textDark),
                      ),
                    ),
                  ),
                  Text(
                    '${rows.length}',
                    style: TextStyle(
                      fontSize: _fs * 0.72,
                      fontWeight: FontWeight.w800,
                      color: _tpl.isSolidBand
                          ? Colors.white.withValues(alpha: 0.85)
                          : _blockColor(block).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            // 4열 표
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.1),
                1: FlexColumnWidth(1.9),
                2: FlexColumnWidth(1.35),
                3: FlexColumnWidth(1.45),
              },
              border: _tpl.gridLines
                  ? TableBorder.all(color: const Color(0xFFDBD6CC), width: 0.5)
                  : TableBorder(
                      horizontalInside: BorderSide(
                        color: const Color(0xFFDBD6CC),
                        width: 0.6,
                      ),
                    ),
              children: [
                // (요구) "미리보기에도 세부항목을 선택할 수 있도록"
                //  → 이 블록의 '상세' 가 켜져 있으면 원본 행을 표 안에 이어 붙인다.
                //   PDF(보고서형)도 같은 detailRows() 를 쓰므로 화면=출력이 된다.
                for (final r in _visibleRows(block, d))
                  TableRow(
                    decoration: _isTotal(r) && _tpl.tintTotal > 0
                        ? BoxDecoration(
                            color: _blockColor(
                              block,
                            ).withValues(alpha: _tpl.tintTotal),
                          )
                        : null,
                    children: [
                      _cell(
                        r.isNotEmpty ? r[0] : '',
                        bold: true,
                        color: _isTotal(r)
                            ? _blockColor(block)
                            : (_isDetail(r) ? AppColors.textGray : null),
                      ),
                      _cell(
                        r.length > 1 ? r[1] : '',
                        align: TextAlign.left,
                        color: _isDetail(r) ? AppColors.textGray : null,
                      ),
                      _cell(
                        r.length > 2 ? r[2] : '',
                        align: TextAlign.right,
                        bold: !_isDetail(r),
                        color: _isTotal(r) ? _blockColor(block) : null,
                      ),
                      _cell(
                        r.length > 3 ? r[3] : '',
                        color: _isDetail(r) ? AppColors.textGray : null,
                      ),
                    ],
                  ),
              ],
            ),
            if (d != null && d.note.isNotEmpty && layout.showNotes)
              Padding(
                padding: EdgeInsets.only(top: 2.5 * rowSpace, left: 2),
                child: Text(
                  d.note,
                  maxLines: noWrap ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _fs * 0.74,
                    color: AppColors.textGray,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 이 블록에서 표에 실제로 그릴 행 — 합계 행 + (상세가 켜져 있으면) 원본 행.
  ///
  /// 상세 행은 `['· 상세', 원본내용, '', '']` 형태라 합계 행과 시각적으로
  /// 구분된다(_isDetail 로 흐린 글씨). 미리보기와 PDF 가 **같은 규칙**을 쓴다.
  List<List<String>> _visibleRows(
    SettlementBlock block,
    SettlementBlockData? d,
  ) {
    final base = d?.rows ?? const <List<String>>[];
    if (d == null || !layout.showsDetail(block)) return base;
    return [...base, ...d.detailRows()];
  }

  /// 상세 행인가 — 첫 칸이 '· 상세'.
  static bool _isDetail(List<String> r) =>
      r.isNotEmpty && r[0].startsWith('· 상세');

  static bool _isTotal(List<String> r) {
    final k = r.isNotEmpty ? r[0] : '';
    return k.contains('합계') || k == '잔액' || k == '초과';
  }

  Widget _cell(
    String text, {
    TextAlign align = TextAlign.left,
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3.2 * rowSpace),
      child: Text(
        text,
        textAlign: align,
        maxLines: noWrap ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        softWrap: !noWrap,
        style: TextStyle(
          fontSize: _fs * 0.88,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: color ?? AppColors.textDark,
          height: 1.30,
        ),
      ),
    );
  }

  static Color _blockColor(SettlementBlock b) => switch (b) {
    SettlementBlock.attendees => AppColors.taegeukBlue,
    SettlementBlock.income => AppColors.scoutGreen,
    SettlementBlock.sponsor => AppColors.tigerGold,
    SettlementBlock.expenseCategory => AppColors.taegeukRed,
    SettlementBlock.expenseAccount => AppColors.purple,
    SettlementBlock.balance => AppColors.masterInk,
  };
}

/// 실시간 미리보기 + **편집** 시트.
///
/// 반환값: 사용자가 확정한 [SettlementLayout] (취소하면 null).
///  · 항목 포함/제외·순서까지 이 시트 안에서 바꿀 수 있다.
///  · 서식(글씨·줄간격·용지·두줄)도 여기서 정하고 그대로 출력에 쓴다.
Future<SettlementLayout?> showSettlementPreviewSheet(
  BuildContext context, {
  required SettlementLayout layout,
  required Map<SettlementBlock, SettlementBlockData> data,
  required String title,

  /// (요구) "미리보기 창에 출력버튼을 추가해서 창을 이동시키지 않아도 실시간으로
  ///  보면서 바로 출력할 수 있도록 해줘"
  ///
  /// 미리보기 시트 **안에서** 바로 출력한다. 시트를 닫고 결산 탭으로 돌아가
  /// '출력'을 다시 누르면, 방금 맞춘 서식이 반영됐는지 확인하려고 또 미리보기를
  /// 열어야 했다(왕복 3번). 이제 시트 안에서 서식을 맞추고 그대로 PDF 를 뽑는다.
  ///
  /// [onExport] 를 넘기면 시트 하단에 출력 버튼이 생긴다.
  /// 넘기지 않으면(다른 호출부) 종전과 완전히 동일하게 동작한다.
  void Function(SettlementLayout layout, TsakOutputFormat format, bool open)?
  onExport,

  /// 인쇄(브라우저 인쇄창) — 보고서형 HTML 로 연다.
  void Function(SettlementLayout layout)? onPrint,
}) {
  return showModalBottomSheet<SettlementLayout>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF3F1EC),
    builder: (_) => _PreviewSheet(
      layout: layout.copy(),
      data: data,
      title: title,
      onExport: onExport,
      onPrint: onPrint,
    ),
  );
}

class _PreviewSheet extends StatefulWidget {
  const _PreviewSheet({
    required this.layout,
    required this.data,
    required this.title,
    this.onExport,
    this.onPrint,
  });

  final SettlementLayout layout;
  final Map<SettlementBlock, SettlementBlockData> data;
  final String title;

  /// 시트 안에서 바로 출력(넘기지 않으면 출력 버튼 숨김).
  final void Function(
    SettlementLayout layout,
    TsakOutputFormat format,
    bool open,
  )?
  onExport;

  /// 인쇄 — 넘기지 않으면 인쇄 버튼을 숨긴다.
  final void Function(SettlementLayout layout)? onPrint;

  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  late final SettlementLayout _layout = widget.layout;

  /// 미리보기 확대/축소 — 손가락으로 종이를 키워볼 수 있다.
  double _zoom = 1.0;

  /// 오른쪽 편집 패널을 펼쳤는가(좁은 화면에선 기본 접힘).
  bool _editOpen = true;

  void _touch(VoidCallback fn) => setState(fn);

  /// 블록 타일 부제 — 행 수 + 상세 건수(있으면).
  String _detailLabel(SettlementBlock b, SettlementBlockData d) {
    final rows = '${d.rows.length}행';
    if (!d.hasDetails) return rows;
    final n = d.details.length;
    return _layout.showsDetail(b) ? '$rows + 상세 $n' : '$rows (상세 $n 숨김)';
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = (mq.size.height - mq.viewInsets.bottom) * 0.94;
    final wide = mq.size.width >= 720;

    return SizedBox(
      height: h,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: _paper()),
                      if (_editOpen) SizedBox(width: 258, child: _editPanel()),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: _paper()),
                      if (_editOpen)
                        SizedBox(
                          height: (h * 0.36).clamp(180.0, 300.0),
                          child: _editPanel(),
                        ),
                    ],
                  ),
          ),
          // 옵션 줄이 길어졌다(템플릿 6종 + 출력 버튼). 좁은 화면에서
          //  미리보기를 짓누르지 않도록 하단바 자체를 스크롤한다.
          //  · 높이는 화면의 34%(최대 190)까지만 — 종이가 항상 보이게.
          //  · wide(넓은 화면)에서는 예전처럼 자연 높이.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (mq.size.height * 0.34).clamp(120.0, 190.0),
            ),
            child: SingleChildScrollView(
              primary: false,
              child: _optionsBar(),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────── 헤더
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 5),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_outlined,
            size: 18,
            color: AppColors.purple,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '실시간 미리보기 · ${_layout.includedCount}/${_layout.order.length}개 '
                  '항목 · ${_layout.styleBadge}',
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
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: _editOpen ? '편집 패널 접기' : '편집 패널 열기',
            onPressed: () => _touch(() => _editOpen = !_editOpen),
            icon: Icon(
              _editOpen ? Icons.chevron_right : Icons.chevron_left,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────── 종이면
  Widget _paper() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: LayoutBuilder(
        builder: (_, box) {
          // 확대는 폭 기준 — 넘치면 가로 스크롤.
          final w = box.maxWidth * _zoom;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _zoom <= 1.0 ? box.maxWidth : w,
              child: SettlementPaperView(
                layout: _layout,
                data: widget.data,
                fontScale: _layout.fontScale,
                rowSpace: _layout.rowSpace,
                landscape: _layout.landscape,
                noWrap: _layout.noWrap,
              ),
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────── 편집 패널
  Widget _editPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0DBD2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 15, color: AppColors.purple),
                const SizedBox(width: 5),
                const Expanded(
                  child: Text(
                    '항목 · 순서 편집',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${_layout.includedCount}/${_layout.order.length}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
              itemCount: _layout.order.length,
              itemBuilder: (_, i) {
                final b = _layout.order[i];
                final on = _layout.includes(b);
                final d = widget.data[b];
                final c = _blockColor(b);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Container(
                    decoration: BoxDecoration(
                      color: on
                          ? c.withValues(alpha: 0.055)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: on
                            ? c.withValues(alpha: 0.30)
                            : const Color(0xFFE8E4DC),
                      ),
                    ),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => _touch(() => _layout.toggle(b)),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(
                              on
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 18,
                              color: on ? c : AppColors.textGray,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${i + 1}. ${b.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: on
                                      ? AppColors.textDark
                                      : AppColors.textGray,
                                ),
                              ),
                              if (d != null && d.rows.isNotEmpty)
                                Text(
                                  _detailLabel(b, d),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: on && _layout.showsDetail(b)
                                        ? c.withValues(alpha: 0.9)
                                        : AppColors.textGray,
                                    fontWeight: on && _layout.showsDetail(b)
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // (요구) "미리보기에도 세부항목을 선택할 수 있도록"
                        //  블록(항목)만 켜고 끄면 '합계만 있는 결산'이 된다.
                        //  블록마다 그 합계의 근거(상세 내역)를 켜고 끄는 버튼.
                        if (on && d != null && d.hasDetails)
                          InkWell(
                            onTap: () => _touch(() => _layout.toggleDetail(b)),
                            borderRadius: BorderRadius.circular(6),
                            child: Tooltip(
                              message: _layout.showsDetail(b)
                                  ? '상세 내역 숨기기'
                                  : '상세 내역 보기',
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _layout.showsDetail(b)
                                      ? c.withValues(alpha: 0.16)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: _layout.showsDetail(b)
                                        ? c.withValues(alpha: 0.55)
                                        : const Color(0xFFD8D3CA),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _layout.showsDetail(b)
                                          ? Icons.subject
                                          : Icons.subject_outlined,
                                      size: 11,
                                      color: _layout.showsDetail(b)
                                          ? c
                                          : AppColors.textGray,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '상세',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: _layout.showsDetail(b)
                                            ? c
                                            : AppColors.textGray,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 26,
                          ),
                          tooltip: '위로',
                          icon: const Icon(Icons.arrow_upward, size: 14),
                          onPressed: i == 0
                              ? null
                              : () => _touch(() => _layout.moveUp(b)),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 26,
                          ),
                          tooltip: '아래로',
                          icon: const Icon(Icons.arrow_downward, size: 14),
                          onPressed: i == _layout.order.length - 1
                              ? null
                              : () => _touch(() => _layout.moveDown(b)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: _tiny(
                    label: '전체',
                    icon: Icons.done_all,
                    onTap: () => _touch(_layout.includeAll),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _tiny(
                    label: '해제',
                    icon: Icons.deselect,
                    onTap: () => _touch(_layout.excludeAll),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tiny({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.purple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.purple.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: AppColors.purple),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────── 서식 · 확정줄
  Widget _optionsBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0DBD2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _slider(
                  label: '글씨 ${(_layout.fontScale * 100).round()}%',
                  value: _layout.fontScale,
                  min: 0.86,
                  max: 1.26,
                  onChanged: (v) => _touch(() => _layout.fontScale = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _slider(
                  label: '줄간격 ${(_layout.rowSpace * 100).round()}%',
                  value: _layout.rowSpace,
                  min: 0.72,
                  max: 1.5,
                  onChanged: (v) => _touch(() => _layout.rowSpace = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _templatePicker(),
          const SizedBox(height: 6),
          Row(
            children: [
              _chip(
                label: _layout.landscape ? '가로' : '세로',
                icon: _layout.landscape
                    ? Icons.crop_landscape
                    : Icons.crop_portrait,
                on: _layout.landscape,
                onTap: () =>
                    _touch(() => _layout.landscape = !_layout.landscape),
              ),
              const SizedBox(width: 5),
              _chip(
                label: '두줄방지',
                icon: Icons.wrap_text,
                on: _layout.noWrap,
                onTap: () => _touch(() => _layout.noWrap = !_layout.noWrap),
              ),
              const SizedBox(width: 5),
              _zoomChip(),
              const SizedBox(width: 5),
              // (요구) 상세·메모·설명을 **전체 단위**로도 한 번에 켜고 끈다.
              _chip(
                label: '상세',
                icon: _layout.anyDetail
                    ? Icons.subject
                    : Icons.subject_outlined,
                on: _layout.anyDetail,
                onTap: () =>
                    _touch(() => _layout.setAllDetails(!_layout.anyDetail)),
              ),
              const SizedBox(width: 5),
              _chip(
                label: '메모',
                icon: Icons.sticky_note_2_outlined,
                on: _layout.showMemo,
                onTap: () => _touch(() => _layout.showMemo = !_layout.showMemo),
              ),
              const SizedBox(width: 5),
              _chip(
                label: '설명',
                icon: Icons.notes,
                on: _layout.showNotes,
                onTap: () =>
                    _touch(() => _layout.showNotes = !_layout.showNotes),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                ),
                child: const Text('닫기', style: TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(width: 2),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
                onPressed: () => Navigator.pop(context, _layout.copy()),
                icon: const Icon(Icons.check, size: 15),
                label: const Text(
                  '적용',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          // ── 창을 닫지 않고 **여기서 바로 출력** ────────────────────────
          //
          // (요구) "미리보기 창에 출력버튼을 추가해서 창을 이동시키지 않아도
          //  실시간으로 보면서 바로 출력할 수 있도록 해줘"
          //
          //  종전: 미리보기 닫기 → 결산 탭에서 '출력' → 옵션 시트 → 또 미리보기
          //        (서식 맞추려고 왕복 3번)
          //  이제: 이 줄에서 PDF/미리보기/인쇄를 즉시. 시트는 그대로 열려 있어
          //        결과를 보며 다시 고칠 수 있다.
          if (widget.onExport != null) _exportBar(),
        ],
      ),
    );
  }

  /// 미리보기 시트 하단 출력 줄 — 서식을 맞춘 **그 상태로** 바로 뽑는다.
  Widget _exportBar() {
    void fire(TsakOutputFormat f, {bool open = false}) {
      widget.onExport!(_layout.copy(), f, open);
    }

    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.ios_share,
                size: 13,
                color: AppColors.purple,
              ),
              const SizedBox(width: 4),
              const Text(
                '지금 서식 그대로 출력',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${_layout.template.label} · ${_layout.styleBadge}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textGray,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // 한 줄에 다 들어가도록 균등 분할.
          //
          // (요구) "PDF, JPG, 엑셀, 워드파일 등도 넣어줘"
          //  → 종전에는 PDF·미리보기·인쇄 3개뿐이었다. 미리보기를 보며 서식을
          //    맞춘 **그 자리에서** 원하는 형식을 골라야 왕복이 없다. 그래서
          //    PDF · JPG · 엑셀 · 워드 + 인쇄 5개를 한 줄에 둔다.
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    minimumSize: const Size(0, 36),
                  ),
                  onPressed: () => fire(TsakOutputFormat.pdf),
                  icon: const Icon(Icons.picture_as_pdf, size: 14),
                  label: const Text(
                    'PDF',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              for (final f in const [
                TsakOutputFormat.jpg,
                TsakOutputFormat.excel,
                TsakOutputFormat.word,
              ]) ...[
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      minimumSize: const Size(0, 36),
                      side: BorderSide(
                        color: AppColors.purple.withValues(alpha: 0.5),
                      ),
                    ),
                    onPressed: () => fire(f),
                    icon: Icon(f.icon, size: 13, color: AppColors.purple),
                    label: Text(
                      f.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purple,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                flex: 4,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    minimumSize: const Size(0, 36),
                    side: BorderSide(
                      color: AppColors.scoutGreen.withValues(alpha: 0.55),
                    ),
                  ),
                  onPressed: () => widget.onPrint?.call(_layout.copy()),
                  icon: const Icon(
                    Icons.print_outlined,
                    size: 13,
                    color: AppColors.scoutGreen,
                  ),
                  label: const Text(
                    '인쇄',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.scoutGreen,
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

  /// 출력 템플릿 6종 선택 — **라벨 + 2줄 그리드**로 전부 보이게.
  ///
  /// ## 왜 바꿨나 (실제 피드백)
  /// "탬블릿 6종은 나타나지 않음"
  ///  → 종전에는 높이 34 의 **가로 스크롤 칩 한 줄**이었다. 화면 오른쪽으로
  ///    밀어야 나머지가 보이고, 라벨도 없어서 '옵션 줄'로 인식되지 않았다.
  ///  → 이제 제목 줄('출력 서식') + 3열 그리드로 6종을 **전부 한눈에** 보여준다.
  ///    각 칸에 아이콘·이름·한 줄 설명을 넣어 무엇이 바뀌는지 알 수 있게 했다.
  Widget _templatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.dashboard_customize_outlined,
              size: 13,
              color: AppColors.purple,
            ),
            const SizedBox(width: 4),
            const Text(
              '출력 서식',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: AppColors.purple,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '고른 서식이 아래 미리보기에 바로 적용됩니다',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textGray.withValues(alpha: 0.95),
                ),
              ),
            ),
            if (!_layout.reportStyle)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.taegeukRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '표형(평평한 표)',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.taegeukRed,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        // 3열 × 2줄 — 좁은 화면에서도 6종이 접히지 않고 모두 보인다.
        LayoutBuilder(
          builder: (_, box) {
            const gap = 5.0;
            final w = ((box.maxWidth - gap * 2) / 3).clamp(72.0, 220.0);
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final t in DocTemplate.all)
                  SizedBox(
                    width: w,
                    child: _templateTile(t, on: _layout.template == t),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 템플릿 타일 1개 — **미니 도판 + 이름 + 한 줄 설명**.
  ///
  /// (요구) "총 8가지 템플릿(구분이 확실히 되는 디자인 포멧으로 할 것, 유사한
  ///  것들은 ALT로써는 의미가 없음)"
  ///  → 이름만으로는 8종이 구분되지 않는다. 각 타일에 **그 템플릿의 서식이
  ///    실제로 어떻게 생겼는지** 작은 도판(_templateThumb)을 그려 넣는다.
  ///    색면형은 꽉 찬 띠, 인장형은 이중 괘선 + 도장칸처럼 **모양 자체**가
  ///    다르므로, 눈으로 보고 고를 수 있다.
  Widget _templateTile(DocTemplate t, {required bool on}) {
    final active = on && _layout.reportStyle;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _touch(() {
        _layout.template = t;
        // 표형 상태에서 템플릿을 고르면 서식이 보이도록 보고서형으로 되돌린다.
        _layout.reportStyle = true;
      }),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.purple.withValues(alpha: 0.10)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? AppColors.purple
                : AppColors.purple.withValues(alpha: 0.20),
            width: active ? 1.4 : 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 서식 미니 도판 ──
            _templateThumb(t, active: active),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  _templateIcon(t),
                  size: 12,
                  color: active ? AppColors.purple : AppColors.textGray,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.2,
                      fontWeight: FontWeight.w900,
                      color: active ? AppColors.purple : AppColors.textDark,
                    ),
                  ),
                ),
                if (active)
                  const Icon(
                    Icons.check_circle,
                    size: 11,
                    color: AppColors.purple,
                  ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              t.hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 8.4, color: AppColors.textGray),
            ),
          ],
        ),
      ),
    );
  }

  /// 템플릿의 **서식 미니 도판** — 종이 한 장을 축소해 그 서식의 특징만 그린다.
  ///
  /// 8종이 서로 다른 축(띠/괘선/카드/여백/격자/숫자/색면/인장)을 하나씩
  /// 맡으므로, 도판만 봐도 어느 것인지 구분된다.
  Widget _templateThumb(DocTemplate t, {required bool active}) {
    const lineColor = Color(0xFFCFC9C0);
    const ink = Color(0xFF8C877E);
    final accent = active ? AppColors.purple : const Color(0xFF7C6A9C);

    // 종이 위에 그릴 한 줄(막대) — 폭 비율로 형태를 만든다.
    Widget bar(double w, {Color? c, double h = 2.2}) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: w.clamp(0.05, 1.0),
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: c ?? ink,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );

    Widget rows({double w = 0.86, int n = 3, Color? c}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < n; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: bar(i == n - 1 ? w * 0.7 : w, c: c),
          ),
      ],
    );

    Widget band({
      required Color bg,
      required double h,
      bool leftBar = false,
      Color? textColor,
    }) => Container(
      height: h,
      decoration: BoxDecoration(
        color: bg,
        border: leftBar
            ? Border(left: BorderSide(color: accent, width: 2.2))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      alignment: Alignment.centerLeft,
      child: Container(
        height: 1.8,
        width: 22,
        color: textColor ?? ink,
      ),
    );

    final Widget body = switch (t) {
      // 띠 + 표 — 기본 보고서
      DocTemplate.report => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          band(bg: accent.withValues(alpha: 0.13), h: 7, leftBar: true),
          const SizedBox(height: 3),
          rows(),
        ],
      ),
      // 전면 격자 · 촘촘
      DocTemplate.ledger => Container(
        decoration: BoxDecoration(
          border: Border.all(color: lineColor, width: 0.9),
        ),
        child: Column(
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                height: 4.4,
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: lineColor, width: 0.6)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                alignment: Alignment.centerLeft,
                child: Container(height: 1.4, width: i == 0 ? 16 : 26, color: ink),
              ),
          ],
        ),
      ),
      // 둥근 카드 2개
      DocTemplate.card => Column(
        children: [
          for (var k = 0; k < 2; k++)
            Container(
              margin: const EdgeInsets.only(bottom: 2.5),
              padding: const EdgeInsets.fromLTRB(3, 2, 3, 2.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: lineColor, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  band(bg: accent.withValues(alpha: 0.12), h: 4.5, leftBar: true),
                  const SizedBox(height: 2),
                  bar(0.8, h: 1.6),
                ],
              ),
            ),
        ],
      ),
      // 선·색 최소 — 여백이 주인공
      DocTemplate.minimal => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar(0.34, h: 2.6),
          const SizedBox(height: 5),
          rows(w: 0.9, n: 2, c: lineColor),
          const SizedBox(height: 4),
          bar(0.62, c: lineColor),
          const SizedBox(height: 2.4),
          bar(0.48, c: lineColor),
        ],
      ),
      // 전체 격자 + 가운데 제목
      DocTemplate.official => Container(
        decoration: BoxDecoration(
          border: Border.all(color: ink, width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: ink, width: 0.9)),
              ),
              alignment: Alignment.center,
              child: Container(height: 2, width: 26, color: ink),
            ),
            for (var i = 0; i < 2; i++)
              Container(
                height: 4.6,
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: lineColor, width: 0.6)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                alignment: Alignment.centerLeft,
                child: Container(height: 1.3, width: 24, color: lineColor),
              ),
          ],
        ),
      ),
      // 핵심 숫자를 크게
      DocTemplate.brief => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          band(bg: accent.withValues(alpha: 0.14), h: 6, leftBar: true),
          const SizedBox(height: 2.5),
          Center(
            child: Container(
              height: 8,
              width: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 3),
          rows(w: 0.7, n: 2, c: lineColor),
        ],
      ),
      // 꽉 찬 색면 + 흰 글씨
      DocTemplate.duotone => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 8,
            color: accent.withValues(alpha: 0.92),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.centerLeft,
            child: Container(height: 1.9, width: 20, color: Colors.white),
          ),
          const SizedBox(height: 2.5),
          rows(w: 0.88, n: 2),
          const SizedBox(height: 2),
          Container(
            height: 7,
            color: accent.withValues(alpha: 0.92),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.centerLeft,
            child: Container(height: 1.9, width: 16, color: Colors.white),
          ),
          const SizedBox(height: 2.5),
          rows(w: 0.8, n: 1),
        ],
      ),
      // 이중 괘선 + 도장 칸
      DocTemplate.stamp => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1.6, color: ink),
          const SizedBox(height: 1.6),
          Container(height: 0.8, color: lineColor),
          const SizedBox(height: 3),
          rows(w: 0.82, n: 2),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 2; i++)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(left: 1.6),
                    decoration: BoxDecoration(
                      border: Border.all(color: ink, width: 0.8),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    };

    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFFE2DDD4)),
      ),
      child: body,
    );
  }

  /// 템플릿 8종 아이콘 — 한눈에 구분되게.
  static IconData _templateIcon(DocTemplate t) => switch (t) {
    DocTemplate.report => Icons.article_outlined,
    DocTemplate.ledger => Icons.table_chart_outlined,
    DocTemplate.card => Icons.dashboard_customize_outlined,
    DocTemplate.minimal => Icons.horizontal_rule,
    DocTemplate.official => Icons.gavel_outlined,
    DocTemplate.brief => Icons.insights_outlined,
    DocTemplate.duotone => Icons.gradient_outlined,
    DocTemplate.stamp => Icons.verified_outlined,
  };

  Widget _zoomChip() {
    final on = (_zoom - 1.0).abs() > 0.01;
    final c = on ? AppColors.purple : AppColors.textGray;
    return InkWell(
      onTap: () => _touch(() {
        // 100% → 130% → 160% → 100% 순환.
        _zoom = _zoom < 1.15 ? 1.3 : (_zoom < 1.45 ? 1.6 : 1.0);
      }),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: on ? 0.13 : 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: on ? 0.5 : 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.zoom_in, size: 13, color: c),
            const SizedBox(width: 3),
            Text(
              '${(_zoom * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.textGray,
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
          ),
          child: SizedBox(
            height: 24,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool on,
    required VoidCallback onTap,
  }) {
    final c = on ? AppColors.purple : AppColors.textGray;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: on ? 0.13 : 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: on ? 0.5 : 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _blockColor(SettlementBlock b) =>
      SettlementPaperView._blockColor(b);
}

/// 결산서 옵션(글씨·줄간격·용지)을 담는 값 객체 — 출력 문서에 전달용.
class SettlementPrintOptions {
  const SettlementPrintOptions({
    this.fontScale = 1.0,
    this.rowSpace = 1.0,
    this.landscape = false,
    this.noWrap = true,
  });

  final double fontScale;
  final double rowSpace;
  final bool landscape;
  final bool noWrap;

  /// EventSettlement 금액 표기 헬퍼(외부에서 쓰기 편하게 재노출).
  static String won(int v) => '${EventSettlement.comma(v)}원';
}
