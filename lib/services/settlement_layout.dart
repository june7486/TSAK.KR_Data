/// 결산서 '항목 블록' 구성 모델.
///
/// ## 요구사항 (그대로)
/// "결산페이지 선택시 각 항목별로 취합된 데이터를 보여주고, 출력여부를 그 페이지
///  에서 선택할 수 있도록 하는 기능을 넣자. 그 페이지에서 어디에 넣을지도 항목별
///  위치 이동을 선택할 수 있도록 하며 미리보기 기능을 강화해서 출력시 보여지는
///  내용을 실시간으로 확인하면 편집 할 수 있도록 하자"
///
/// ## 설계
/// 결산서는 **블록(항목)의 순서 있는 목록**이다. 관리자는
///  ① 각 블록의 취합 데이터를 그 자리에서 보고
///  ② 블록별로 출력 포함/제외를 켜고 끄고
///  ③ 블록을 위/아래로 옮겨 출력 순서를 정하며
///  ④ 그 결과를 **실시간 미리보기**로 즉시 확인한다.
///
/// 화면 카드 · 미리보기 · 실제 출력문서가 **같은 데이터 소스**
/// ([SettlementBlockData])를 쓰므로 "보이는 것 = 인쇄되는 것"이 보장된다.
library;

import 'donation_kinds.dart';
import 'event_settlement.dart';
import 'print_doc.dart';
import 'table_options.dart';

/// 결산서를 구성하는 항목 블록.
enum SettlementBlock {
  attendees('참가자 수', '직책별 인원과 합계'),
  income('수입', '참가비 · 후원금 · 기타수입'),
  sponsor('후원 내역', '현물 · 서비스 후원(수입 미포함)'),
  expenseCategory('지출 (분류별)', '행사비 · 제작비 등'),
  expenseAccount('지출 (계좌별)', '출금계좌 기준'),
  balance('잔액', '수입 − 지출');

  const SettlementBlock(this.label, this.hint);

  final String label;
  final String hint;

  static SettlementBlock? parse(String k) {
    for (final b in SettlementBlock.values) {
      if (b.name == k) return b;
    }
    return null;
  }
}

/// 한 블록의 취합 결과 — 화면 카드 / 미리보기 / 문서 출력 공용.
class SettlementBlockData {
  const SettlementBlockData({
    required this.block,
    required this.rows,
    required this.note,
    this.empty = false,
    this.details = const <String>[],
  });

  final SettlementBlock block;

  /// 3열 [항목, 금액·인원, 비고] 목록.
  /// (미리보기·문서에서 4열 표에 그대로 얹는다)
  final List<List<String>> rows;

  /// 블록 하단 한 줄 요약(선택).
  final String note;

  /// 데이터가 비어 있는가(카드에서 안내 문구 노출).
  final bool empty;

  /// 집계의 **근거가 된 원본 행** — 카드에서 펼쳐 확인한다.
  /// (요구: "각 항목별로 취합된 데이터를 보여주고")
  /// 예: `'2026-05-12 · 김철수 · 점심식사 12,000원 · 행사비'`
  final List<String> details;

  String get title => block.label;

  bool get hasDetails => details.isNotEmpty;

  /// 상세 내역을 **결산 표의 하위 행**으로 펼친다 — `['· 상세', 원본내용, '', '']`.
  ///
  /// ## 왜 필요한가 (요구: "후원내역 상세 항목, 지출 및 참가비 등도 상세 내역을
  ///  결산시 보여주고 … 출력여부를 상세까지 선택")
  /// [details] 는 `'2026-05-12 · 김철수 · 점심식사 12,000원 · 행사비'` 같은
  /// 한 줄 문자열이다. 결산 표는 `[항목, 금액/인원, 비고, 추가]` 4칸이므로
  /// 원본 줄을 **2번째 칸**에 넣고 1번째 칸에 `· 상세` 표시를 둔다.
  /// (미리보기·PDF·HTML 이 모두 이 함수를 쓰므로 화면=출력이 유지된다)
  ///
  /// [max] 를 주면 상세 줄 수를 제한한다(너무 길어지는 것 방지).
  List<List<String>> detailRows({int max = 40}) {
    if (details.isEmpty) return const [];
    final out = <List<String>>[];
    for (var i = 0; i < details.length && i < max; i++) {
      out.add(['· 상세', details[i], '', '']);
    }
    if (details.length > max) {
      out.add(['· 상세', '… 외 ${details.length - max}건', '', '']);
    }
    return out;
  }
}

/// 결산서 블록 배치 — 순서 + 출력 포함 여부 + 서식(글씨·줄간격·용지·두줄방지).
class SettlementLayout {
  SettlementLayout({
    List<SettlementBlock>? order,
    Set<SettlementBlock>? excluded,
    this.fontScale = 1.0,
    this.rowSpace = 1.0,
    this.landscape = false,
    this.noWrap = true,
    this.showNotes = true,
    this.showMemo = true,
    this.reportStyle = true,
    Set<SettlementBlock>? detailOff,
  }) : order = order ?? [...SettlementBlock.values],
       excluded = excluded ?? <SettlementBlock>{},
       detailOff = detailOff ?? <SettlementBlock>{};

  /// 출력 순서.
  List<SettlementBlock> order;

  /// 출력에서 빼기로 한 블록.
  Set<SettlementBlock> excluded;

  // ── 요구: "결산에 후원내역 상세 항목, 지출 및 참가비 등도 상세 내역을
  //    결산시 보여주고 미리보기 창에서 출력여부를 상세까지 선택할 수 있도록"
  //
  //  블록(소제목)만 켜고 끄면 '합계만 있는 결산'이 된다. 실제로 회계를
  //  확인하는 사람이 보고 싶은 것은 **그 합계가 어디서 나왔는가**이다.
  //  그래서 블록마다 '상세 내역'(원본 행)을 표 아래에 붙일 수 있게 하고,
  //  미리보기 편집창에서 블록별로 켜고 끈다.
  //
  //  ## 설계 (3-상태의 함정을 피한다)
  //  '전체 스위치(showDetails) + 개별 예외(detailOff)' 2개를 두면
  //   (전체 off, 개별 on) 같은 **모순 조합**이 생겨 "전체를 껐는데 한 블록만
  //   켜져 있는" 상태가 만들어진다(실제로 그렇게 구현했다가 테스트에서 잡힘).
  //  → 진실원을 **하나**로 둔다. [detailOff] 만이 "이 블록은 상세를 빼라"를
  //   뜻하고, 전체 스위치([setAllDetails])는 그 집합을 통째로 채우거나 비운다.
  //   그래서 언제나 일관된 상태만 존재한다.

  /// 블록 하단 한 줄 설명(note)을 붙일지.
  bool showNotes;

  /// 상세 내역을 **빼기로 한** 블록 — 이 집합 하나가 진실원이다.
  Set<SettlementBlock> detailOff;

  /// 상세 내역을 통째로 끄면 쓰는 표식(6개 블록 전부 제외 = 전체 끔).
  ///
  /// `detailOff` 가 모든 블록을 담고 있으면 '전체 끔' 상태로 본다.
  static Set<SettlementBlock> get _all => SettlementBlock.values.toSet();

  /// 상세 내역을 **전체로** 붙이는가(어느 한 블록이라도 켜져 있으면 true).
  bool get showDetails => order.any((b) => !detailOff.contains(b));

  /// 이 블록의 상세 내역을 출력하는가.
  bool showsDetail(SettlementBlock b) => !detailOff.contains(b);

  /// 블록별 상세 내역 켜기/끄기 — 그 블록만 바꾼다(다른 블록 불변).
  void toggleDetail(SettlementBlock b) {
    if (detailOff.contains(b)) {
      detailOff.remove(b);
    } else {
      detailOff.add(b);
    }
  }

  /// 상세 내역 전체 켜기/끄기.
  void setAllDetails(bool on) {
    if (on) {
      detailOff.clear();
    } else {
      detailOff.addAll(SettlementBlock.values);
    }
  }

  /// 상세가 하나라도 켜져 있는가(배지 표기용).
  bool get anyDetail => included.any(showsDetail);

  /// 상세를 붙이는 블록 수.
  int get detailCount => included.where(showsDetail).length;

  // ── 서식 — 미리보기에서 바로 조절하고 **출력 문서에도 그대로** 적용된다.
  //    (요구: "미리보기 기능을 강화해서 출력시 보여지는 내용을 실시간으로
  //     확인하면 편집 할 수 있도록 하자")
  //    종전에는 미리보기 슬라이더가 화면에만 반영되고 실제 문서는 기본값으로
  //    나가는 불일치가 있었다. 서식을 [SettlementLayout] 에 담아
  //    화면·미리보기·문서가 **같은 값**을 쓰게 한다.

  /// 글씨 배율(0.86 ~ 1.26).
  double fontScale;

  /// 줄 간격 배율(0.72 ~ 1.5).
  double rowSpace;

  /// 가로(넓은) 용지.
  bool landscape;

  /// 두 줄 방지.
  bool noWrap;

  /// 상세 내역에 **메모**를 함께 보여줄지.
  ///
  /// (요구) "결산시에도 메모 내역을 추가해서 보여주고, 항목을 선택할 수 있도록"
  /// → 메모는 원본 재무 행의 자유 입력란이라 길이·형식이 제각각이다.
  ///   회계 보고서에 넣을지 말지는 **관리자가 고른다**(기본 켜짐).
  bool showMemo;

  /// 보고서형 출력(무인양품 표 대신 블록 제목 띠 + 4열 표)을 쓸지.
  ///
  /// (요구) "pdf 출력물의 형태는 결산의 경우 기존 무인양품 스타일을 버리고,
  ///  미리보기 항목의 내용을 참조해서 항목별로 보기좋게 출력 … 계산서처럼
  ///  보여지기보다는 보고서처럼"
  /// → true 면 [SettlementPaperView] 와 **같은 그래픽**(블록 컬러 띠·4열)으로
  ///   PDF 를 만든다. 화면 미리보기 = PDF 가 된다.
  bool reportStyle;

  bool includes(SettlementBlock b) => !excluded.contains(b);

  /// 실제 출력에 포함되는 블록(순서 유지).
  List<SettlementBlock> get included => order.where(includes).toList();

  int get includedCount => included.length;

  bool get isFiltered => excluded.isNotEmpty;

  void toggle(SettlementBlock b) {
    if (excluded.contains(b)) {
      excluded.remove(b);
    } else {
      excluded.add(b);
    }
  }

  void includeAll() => excluded.clear();

  void excludeAll() => excluded.addAll(SettlementBlock.values);

  /// 위로 한 칸. 이미 맨 위면 false.
  bool moveUp(SettlementBlock b) {
    final i = order.indexOf(b);
    if (i <= 0) return false;
    order.removeAt(i);
    order.insert(i - 1, b);
    return true;
  }

  /// 아래로 한 칸. 이미 맨 아래면 false.
  bool moveDown(SettlementBlock b) {
    final i = order.indexOf(b);
    if (i < 0 || i >= order.length - 1) return false;
    order.removeAt(i);
    order.insert(i + 1, b);
    return true;
  }

  /// 맨 위로.
  bool moveTop(SettlementBlock b) {
    final i = order.indexOf(b);
    if (i <= 0) return false;
    order.removeAt(i);
    order.insert(0, b);
    return true;
  }

  /// 맨 아래로.
  bool moveBottom(SettlementBlock b) {
    final i = order.indexOf(b);
    if (i < 0 || i >= order.length - 1) return false;
    order.removeAt(i);
    order.add(b);
    return true;
  }

  SettlementLayout copy() => SettlementLayout(
    order: [...order],
    excluded: {...excluded},
    fontScale: fontScale,
    rowSpace: rowSpace,
    landscape: landscape,
    noWrap: noWrap,
    showNotes: showNotes,
    showMemo: showMemo,
    reportStyle: reportStyle,
    detailOff: {...detailOff},
  );

  /// 서식만 기본값으로.
  void resetStyle() {
    fontScale = 1.0;
    rowSpace = 1.0;
    landscape = false;
    noWrap = true;
    showNotes = true;
    showMemo = true;
    reportStyle = true;
    detailOff.clear();
  }

  /// 서식이 기본값과 다른가(배지 표기용).
  bool get isStyled =>
      (fontScale - 1.0).abs() > 0.001 ||
      (rowSpace - 1.0).abs() > 0.001 ||
      landscape ||
      !noWrap ||
      detailOff.isNotEmpty ||
      !showNotes ||
      !showMemo ||
      !reportStyle;

  /// 서식 요약 — 예: '가로 · 글씨 108% · 줄간격 92%'.
  String get styleBadge {
    final parts = <String>[];
    parts.add(landscape ? '가로' : '세로');
    if ((fontScale - 1.0).abs() > 0.001) {
      parts.add('글씨 ${(fontScale * 100).round()}%');
    }
    if ((rowSpace - 1.0).abs() > 0.001) {
      parts.add('줄간격 ${(rowSpace * 100).round()}%');
    }
    if (!noWrap) parts.add('두줄허용');
    parts.add(anyDetail ? '상세 $detailCount/${includedCount}' : '상세 없음');
    if (!showNotes) parts.add('설명 없음');
    if (!showMemo) parts.add('메모 없음');
    parts.add(reportStyle ? '보고서형' : '표형');
    return parts.join(' · ');
  }

  /// 출력 문서(TsakTableDoc)에 넘길 옵션 — **미리보기 서식을 그대로** 옮긴다.
  TableOutputOptions toOutputOptions() => TableOutputOptions(
    fontSize: fontScale >= 1.14
        ? TsakFontSize.large
        : (fontScale <= 0.9 ? TsakFontSize.small : TsakFontSize.normal),
    rowSpace: rowSpace >= 1.2
        ? TsakRowSpace.loose
        : (rowSpace <= 0.85 ? TsakRowSpace.tight : TsakRowSpace.normal),
    landscape: landscape,
    noWrap: noWrap ? const {'구분', '항목', '금액/인원'} : const <String>{},
  );

  /// 저장/복원용 — 순서를 문자열 목록으로.
  List<String> toJson() => [for (final b in order) b.name];
  List<String> excludedJson() => [for (final b in excluded) b.name];
  List<String> detailOffJson() => [for (final b in detailOff) b.name];
  static SettlementLayout fromJson(
    List<dynamic>? order,
    List<dynamic>? excluded, {
    double fontScale = 1.0,
    double rowSpace = 1.0,
    bool landscape = false,
    bool noWrap = true,
    bool showDetails = true,
    bool showNotes = true,
    bool showMemo = true,
    bool reportStyle = true,
    List<dynamic>? detailOff,
  }) {
    final ord = <SettlementBlock>[];
    for (final e in order ?? const []) {
      final b = SettlementBlock.parse('$e');
      if (b != null && !ord.contains(b)) ord.add(b);
    }
    // 누락된 블록은 뒤에 붙인다(신규 블록 자동 편입).
    for (final b in SettlementBlock.values) {
      if (!ord.contains(b)) ord.add(b);
    }
    final exc = <SettlementBlock>{};
    for (final e in excluded ?? const []) {
      final b = SettlementBlock.parse('$e');
      if (b != null) exc.add(b);
    }
    final off = <SettlementBlock>{};
    for (final e in detailOff ?? const []) {
      final b = SettlementBlock.parse('$e');
      if (b != null) off.add(b);
    }
    // 옛 저장값 호환 — showDetails=false 였으면 '전체 상세 끔'으로 복원한다.
    if (!showDetails) off.addAll(SettlementBlock.values);
    return SettlementLayout(
      order: ord,
      excluded: exc,
      fontScale: fontScale,
      rowSpace: rowSpace,
      landscape: landscape,
      noWrap: noWrap,
      showNotes: showNotes,
      showMemo: showMemo,
      reportStyle: reportStyle,
      detailOff: off,
    );
  }
}

/// 결산 데이터 → 블록별 취합 결과 목록.
///
/// [fees]·[expenses] 는 **출력에 포함하기로 고른 행만** 넘겨받는다
/// (재무 탭의 '출력 선택'과 동일한 규칙을 결산에도 적용).
///
/// 각 행은 `[항목, 금액·인원, 비고]` 3칸을 채운다 — 화면 카드·미리보기·
/// 문서가 모두 같은 3칸을 쓰므로 "나열"이 아니라 **정리된 표**가 된다.
/// (요구: "행사비 결산은 일목요연하게 세부항목별로 보여지게 해야 함")
class SettlementBuilder {
  const SettlementBuilder._();

  static Map<SettlementBlock, SettlementBlockData> build({
    required EventSettlement settlement,
    required List<Map<String, dynamic>> fees,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> attendees,
    String Function(int) won = _wonDefault,
    /// (요구) 상세 내역에 **메모**를 넣을지 — 미리보기에서 켜고 끈다.
    bool memo = true,
  }) {
    final out = <SettlementBlock, SettlementBlockData>{};

    // ── ① 참가자 수 (8종 + 합계, 필수) ────────────────────────────────
    //   3번째 칸은 비워 둔다 — 화면 카드가 그 자리에 인원 비율 막대를 그린다.
    final bd = settlement.attendeeCount;
    final attRows = <List<String>>[
      for (final e in bd.ordered) [e.key, '${e.value}명', ''],
      ['합계', '${bd.total}명', bd.total == 0 ? '명단 없음' : ''],
    ];
    out[SettlementBlock.attendees] = SettlementBlockData(
      block: SettlementBlock.attendees,
      rows: attRows,
      note: bd.summaryLine,
      empty: attendees.isEmpty,
      details: [
        for (final a in attendees)
          [
            '${a['name'] ?? ''}'.trim(),
            '${a['role'] ?? a['unit'] ?? ''}'.trim(),
            '${a['number'] ?? ''}'.trim().isEmpty ? '' : '인가 ${a['number']}',
          ].where((e) => e.isNotEmpty).join(' · '),
      ],
    );

    // ── ② 수입 (참가비 + 후원금만 수입) ───────────────────────────────
    final payers = settlement.fees.where((e) => e.amount > 0).length;
    final cashDonors = settlement.fees
        .where(
          (e) =>
              DonationKind.parse(e.category) == DonationKind.cash &&
              e.amount > 0,
        )
        .length;
    final incRows = <List<String>>[
      ['참가비', won(settlement.feeTotal), payers == 0 ? '납부자 없음' : '$payers명 납부'],
      [
        '후원금',
        won(settlement.cashDonationTotal),
        cashDonors == 0 ? '현금 후원 없음' : '$cashDonors건',
      ],
      [
        '기타수입',
        won(settlement.otherIncome),
        settlement.otherIncome == 0 ? '-' : '참가비·후원금 외',
      ],
      ['수입 합계', won(settlement.incomeTotal), ''],
    ];
    out[SettlementBlock.income] = SettlementBlockData(
      block: SettlementBlock.income,
      rows: incRows,
      note: '수입 = 참가비 + 후원금 + 기타수입 (후원 현물은 수입에 넣지 않음)',
      empty: settlement.incomeTotal == 0,
      details: [
        for (final f in fees)
          if (DonationKind.parse(f['category'] as String? ?? '').isIncome ||
              '${f['category'] ?? ''}'.trim() == '참가비' ||
              '${f['category'] ?? ''}'.trim() == '기타수입')
            _moneyLine(f, won, memo: memo),
      ],
    );

    // ── ③ 후원 내역 (현물·서비스, 수입 미포함) ────────────────────────
    final donations = DonationSummary(fees.map(DonationRow.fromMap).toList());
    final spRows = <List<String>>[];
    if (donations.sponsorRows.isEmpty) {
      spRows.add(['후원 내역', '없음', '']);
    } else {
      for (final e in donations.byKind.entries) {
        if (e.value.$1 == 0 && e.value.$2 == 0) continue;
        final cnt = donations.sponsorRows
            .where((r) => r.kind.label == e.key)
            .length;
        spRows.add([e.key, _cashValue(e.value.$1, e.value.$2, won), '$cnt건']);
      }
      spRows.add([
        '후원 합계',
        _cashValue(
          donations.sponsorCashTotal,
          donations.sponsorValueTotal,
          won,
        ),
        '${donations.sponsorCount}건 · 수입 미포함',
      ]);
    }
    out[SettlementBlock.sponsor] = SettlementBlockData(
      block: SettlementBlock.sponsor,
      rows: spRows,
      note:
          '후원 ${donations.sponsorCount}건 · 참고 합계 '
          '${_cashValue(donations.sponsorCashTotal, donations.sponsorValueTotal, won)}',
      empty: donations.sponsorRows.isEmpty,
      details: [
        for (final r in donations.sponsorRows)
          [
            r.name.isEmpty ? '(후원자 미입력)' : r.name,
            r.kind.label,
            if (r.item.isNotEmpty) r.item,
            r.displayAmount,
            // (요구) 후원자·후원금·후원물품의 **메모**도 상세에 함께.
            if (memo) _memoPart(r.memo),
          ].where((e) => e.isNotEmpty).join(' · '),
      ],
    );

    // ── ④ 지출 (분류별) ──────────────────────────────────────────────
    final byCat = settlement.expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final catRows = <List<String>>[
      if (byCat.isEmpty)
        ['지출', '없음', '']
      else
        for (final e in byCat)
          [
            e.key,
            won(e.value),
            '${expenses.where((x) => '${x['category'] ?? ''}'.trim() == e.key).length}건',
          ],
      if (byCat.isNotEmpty) ['지출 합계', won(settlement.expenseTotal), ''],
    ];
    out[SettlementBlock.expenseCategory] = SettlementBlockData(
      block: SettlementBlock.expenseCategory,
      rows: catRows,
      note: '지출 ${expenses.length}건 · 분류 ${byCat.length}종',
      empty: byCat.isEmpty,
      details: [for (final e in expenses) _moneyLine(e, won, memo: memo)],
    );

    // ── ⑤ 지출 (계좌별) ──────────────────────────────────────────────
    final byAcct = settlement.expenseByAccount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final acctRows = <List<String>>[
      if (byAcct.isEmpty)
        ['출금계좌', '없음', '']
      else
        for (final e in byAcct)
          [
            e.key,
            won(e.value),
            '${expenses.where((x) => '${x['account'] ?? ''}'.trim() == e.key || (e.key == '(계좌 미지정)' && '${x['account'] ?? ''}'.trim().isEmpty)).length}건',
          ],
    ];
    out[SettlementBlock.expenseAccount] = SettlementBlockData(
      block: SettlementBlock.expenseAccount,
      rows: acctRows,
      note: '출금계좌를 지정하지 않은 지출은 (계좌 미지정)으로 묶입니다',
      empty: byAcct.isEmpty,
      details: [for (final e in expenses) _moneyLine(e, won, memo: memo)],
    );

    // ── ⑥ 잔액 ───────────────────────────────────────────────────────
    final bal = settlement.balance;
    out[SettlementBlock.balance] = SettlementBlockData(
      block: SettlementBlock.balance,
      rows: [
        ['수입 합계', won(settlement.incomeTotal), ''],
        ['지출 합계', won(settlement.expenseTotal), ''],
        [
          bal >= 0 ? '잔액' : '초과',
          won(bal.abs()),
          bal >= 0 ? '잔액 발생' : '수입 초과 지출',
        ],
      ],
      note: bal >= 0 ? '잔액이 남았습니다' : '지출이 수입을 초과했습니다',
      empty: false,
    );

    return out;
  }

  /// 원본 재무 행 1건 → `'2026-05-12 · 김철수 · 점심식사 12,000원 · 행사비'`.
  ///
  /// (요구) "결산시에도 메모 내역을 추가해서 보여주고, 항목을 선택할 수 있도록"
  /// → [memo] 가 켜져 있고 그 행에 메모가 있으면 끝에 `· 메모: …` 를 붙인다.
  ///   메모는 여러 줄일 수 있으므로 한 줄로 눌러 담는다(표 안에서 안 터지게).
  static String _moneyLine(
    Map<String, dynamic> r,
    String Function(int) won, {
    bool memo = true,
  }) {
    final amount =
        int.tryParse(
          '${r['amount'] ?? 0}'.replaceAll(RegExp(r'[^0-9-]'), ''),
        ) ??
        0;
    final val =
        int.tryParse('${r['value'] ?? 0}'.replaceAll(RegExp(r'[^0-9-]'), '')) ??
        0;
    final parts = <String>[
      '${r['date'] ?? ''}'.trim(),
      '${r['name'] ?? ''}'.trim(),
      '${r['item'] ?? ''}'.trim().isEmpty
          ? '${r['category'] ?? ''}'.trim()
          : '${r['category'] ?? ''}'.trim() == ''
          ? '${r['item']}'.trim()
          : '${r['category']} · ${r['item']}'.trim(),
      amount > 0 ? won(amount) : '',
      val > 0 ? '${won(val)} 상당' : '',
      if (memo) _memoPart(r['memo']),
    ];
    return parts.where((e) => e.isNotEmpty).join(' · ');
  }

  /// 메모 한 조각 — 비어 있으면 빈 문자열(목록에서 자동 생략).
  static String _memoPart(Object? raw) {
    final t = '${raw ?? ''}'.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
    return t.isEmpty ? '' : '메모: $t';
  }

  /// `100,000원 + 100,000원 상당` 형태 — 0 인 쪽은 생략.
  static String _cashValue(int cash, int value, String Function(int) won) {
    final parts = <String>[
      if (cash > 0) won(cash),
      if (value > 0) '${won(value)} 상당',
    ];
    return parts.isEmpty ? '-' : parts.join(' + ');
  }

  static String _wonDefault(int v) => '${EventSettlement.comma(v)}원';
}

/// 결산 블록 → **보고서형 PDF 블록** 변환.
///
/// ## 요구사항 (그대로)
/// "pdf 출력물의 형태는 결산의 경우 기존 무인양품 스타일을 버리고, 미리보기
///  항목의 내용을 참조해서 항목별로 보기좋게 출력 … 계산서처럼 보여지기보다는
///  보고서처럼"
///
/// ## 규칙
///  · 블록 색은 미리보기(`SettlementPaperView._blockColor`)와 **같은 값**을 쓴다.
///  · 표 아래에 [SettlementLayout.showsDetail] 이 켜진 블록만 상세 내역을 붙인다.
///  · 메모는 [SettlementLayout.showMemo] 가 켜져 있을 때만 상세 줄에 이미
///    포함되어 있다(빌더가 이미 걸러 넣는다) — 여기서 또 거르지 않는다.
///  · [SettlementLayout.showNotes] 가 꺼져 있으면 note 를 비운다.
class SettlementReportBuilder {
  const SettlementReportBuilder._();

  /// 블록 강조색 — `SettlementPaperView._blockColor` 와 1:1 (hex).
  static String accentOf(SettlementBlock b) => switch (b) {
    SettlementBlock.attendees => '#2E5F8A', // taegeukBlue
    SettlementBlock.income => '#4E7A4B', // scoutGreen
    SettlementBlock.sponsor => '#A6763C', // tigerGold
    SettlementBlock.expenseCategory => '#A63A3A', // taegeukRed
    SettlementBlock.expenseAccount => '#7C6A9C', // purple
    SettlementBlock.balance => '#3A3A3A', // masterInk
  };

  /// 결산 데이터 → 보고서 블록 목록(포함된 블록만, 고른 순서대로).
  static List<DocReportBlock> build({
    required SettlementLayout layout,
    required Map<SettlementBlock, SettlementBlockData> data,
    int detailMax = 40,
  }) {
    final out = <DocReportBlock>[];
    for (final b in layout.included) {
      final d = data[b];
      if (d == null) continue;
      // 상세 내역이 꺼져 있으면 표(합계)만 — '요약 보고서'.
      final rows = <List<String>>[...d.rows];
      if (layout.showsDetail(b)) {
        rows.addAll(d.detailRows(max: detailMax));
      }
      out.add(
        DocReportBlock(
          title: b.label,
          subtitle: rows.length == 1 ? '' : '${rows.length}행',
          rows: rows,
          accent: accentOf(b),
          note: layout.showNotes ? d.note : '',
        ),
      );
    }
    return out;
  }
}
