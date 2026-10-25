// 결산 탭 로직 검증 — 위치 이동 · 출력 포함/제외 · 서식 왕복 · 블록 취합.
//
// 실행: cd /home/user/flutter_app && dart run tool/verify_settlement_layout.dart
//
// 위젯(UI)은 여기서 검증하지 못한다. 이 스크립트가 보증하는 것은
//  ① SettlementLayout 의 순서 이동/포함 토글/복사/직렬화가 **정확**한가
//  ② 서식(글씨·줄간격·용지·두줄)이 복사·문서옵션 변환에서 **보존**되는가
//  ③ SettlementBuilder 가 수입/후원/지출/잔액을 **요구 규칙대로** 합산하는가
//  ④ SettlementPickSet 이 '출력 선택' 행 집합을 정확히 계산하는가
// 이다. 화면 클릭 동작(스크롤·키보드)은 실기기 확인이 필요하다.

import '../lib/services/donation_kinds.dart';
import '../lib/services/event_finance_picks.dart';
import '../lib/services/event_settlement.dart';
import '../lib/services/settlement_layout.dart';
import '../lib/services/table_options.dart';

var _pass = 0;
var _fail = 0;

void check(String label, bool ok, [String extra = '']) {
  if (ok) {
    _pass++;
    // ignore: avoid_print
    print('  PASS  $label');
  } else {
    _fail++;
    // ignore: avoid_print
    print('  FAIL  $label ${extra.isEmpty ? '' : '($extra)'}');
  }
}

void eq(String label, Object? got, Object? want) =>
    check(label, '$got' == '$want', 'got=$got want=$want');

void main() {
  // ignore: avoid_print
  print('=== 1. SettlementLayout 순서 이동 / 포함 토글 ===');
  final l = SettlementLayout();
  eq('기본 순서 6블록', l.order.length, 6);
  eq('첫 블록 = 참가자 수', l.order.first, SettlementBlock.attendees);

  l.moveDown(SettlementBlock.attendees);
  eq('아래로 → 2번째', l.order[1], SettlementBlock.attendees);
  l.moveUp(SettlementBlock.attendees);
  eq('위로 → 다시 1번째', l.order.first, SettlementBlock.attendees);

  l.moveBottom(SettlementBlock.attendees);
  eq('맨 아래로', l.order.last, SettlementBlock.attendees);
  check('맨 아래에서 moveDown 은 false', l.moveDown(SettlementBlock.attendees) == false);
  l.moveTop(SettlementBlock.attendees);
  eq('맨 위로 복귀', l.order.first, SettlementBlock.attendees);
  check('맨 위에서 moveUp 은 false', l.moveUp(SettlementBlock.attendees) == false);

  // 포함/제외
  eq('처음엔 6개 모두 포함', l.includedCount, 6);
  check('isFiltered=false', l.isFiltered == false);
  l.toggle(SettlementBlock.income);
  eq('수입 제외 → 5개', l.includedCount, 5);
  check('isFiltered=true', l.isFiltered == true);
  check('income 미포함', l.includes(SettlementBlock.income) == false);
  check(
    'included 에 income 없음',
    l.included.contains(SettlementBlock.income) == false,
  );
  l.toggle(SettlementBlock.income);
  check('다시 토글 → 포함', l.includes(SettlementBlock.income));
  l.excludeAll();
  eq('전체 해제 → 0', l.includedCount, 0);
  l.includeAll();
  eq('전체 포함 → 6', l.includedCount, 6);

  // 복사 독립성
  final c = l.copy();
  c.moveBottom(SettlementBlock.attendees);
  c.toggle(SettlementBlock.sponsor);
  eq('복사본을 바꿔도 원본 첫 블록 유지', l.order.first, SettlementBlock.attendees);
  eq('원본 제외 0', l.excluded.length, 0);
  eq('복사본 제외 1', c.excluded.length, 1);

  // 직렬화 왕복
  l.toggle(SettlementBlock.balance);
  l.moveBottom(SettlementBlock.attendees);
  final back = SettlementLayout.fromJson(l.toJson(), l.excludedJson());
  eq('직렬화 후 순서 유지', back.order.join(','), l.order.join(','));
  eq('직렬화 후 제외 유지', back.includedCount, l.includedCount);
  check(
    '신규 블록 자동 편입(부분 순서 입력)',
    SettlementLayout.fromJson(
      ['balance'],
      null,
    ).order.length == SettlementBlock.values.length,
  );

  // ignore: avoid_print
  print('=== 2. 서식(글씨·줄간격·용지·두줄) 보존 ===');
  final s = SettlementLayout();
  check('기본은 isStyled=false', s.isStyled == false);
  // (요구) 배지에 상세 내역 상태도 함께 드러난다 — 기본은 6/6.
  eq('기본 배지', s.styleBadge, '세로 · 상세 6/6 · 보고서형');
  s.fontScale = 1.18;
  s.rowSpace = 0.8;
  s.landscape = true;
  s.noWrap = false;
  check('바꾸면 isStyled=true', s.isStyled);
  final sc = s.copy();
  eq('복사: 글씨', sc.fontScale, 1.18);
  eq('복사: 줄간격', sc.rowSpace, 0.8);
  eq('복사: 가로', sc.landscape, true);
  eq('복사: 두줄허용', sc.noWrap, false);
  final o = sc.toOutputOptions();
  eq('문서옵션: 글씨 크게', o.fontSize, TsakFontSize.large);
  eq('문서옵션: 줄간격 좁게', o.rowSpace, TsakRowSpace.tight);
  eq('문서옵션: 가로', o.landscape, true);
  eq('문서옵션: 두줄방지 해제', o.noWrap.length, 0);
  final o2 = SettlementLayout().toOutputOptions();
  eq('기본 문서옵션: 보통', o2.fontSize, TsakFontSize.normal);
  eq('기본 문서옵션: 두줄방지 3열', o2.noWrap.length, 3);
  s.resetStyle();
  check('서식 초기화', s.isStyled == false);

  // ignore: avoid_print
  print('=== 3. 수입/후원 합산 규칙 (후원금만 수입) ===');
  final fees = <Map<String, dynamic>>[
    {'id': 'a', 'date': '2026-05-01', 'name': '김참가', 'category': '참가비', 'amount': 50000},
    {'id': 'b', 'date': '2026-05-02', 'name': '이후원', 'category': '후원금', 'amount': 100000},
    {'id': 'c', 'date': '2026-05-03', 'name': '박식사', 'category': '식사후원', 'amount': 0, 'value': 80000, 'item': '김밥 100줄'},
    {'id': 'd', 'date': '2026-05-04', 'name': '최물품', 'category': '물품후원', 'amount': 0, 'value': 100000, 'item': '기념품 50개'},
    {'id': 'e', 'date': '2026-05-05', 'name': '정차량', 'category': '차량후원', 'amount': 30000, 'value': 0, 'item': '버스 1대'},
    {'id': 'f', 'date': '2026-05-06', 'name': '한기타', 'category': '기타수입', 'amount': 40000},
  ];
  final expenses = <Map<String, dynamic>>[
    {'id': 'x', 'date': '2026-05-07', 'name': '점심', 'category': '행사비', 'amount': 90000, 'account': '(계좌 미지정)'},
  ];
  final st = EventSettlement(
    title: '테스트',
    year: '2026',
    attendeeCount: const EventAttendeeBreakdown(),
    attendees: const [],
    fees: fees.map((e) => EventMoneyRow.fromMap(e)).toList(),
    expenses:
        expenses.map((e) => EventMoneyRow.fromMap(e, expense: true)).toList(),
  );
  eq('참가비 합계', st.feeTotal, 50000);
  eq('후원금(현금)만 수입', st.cashDonationTotal, 100000);
  eq('기타수입', st.otherIncome, 40000);
  eq('수입 합계 = 50,000+100,000+40,000', st.incomeTotal, 190000);
  eq('후원 현금 합계', st.sponsorCashTotal, 30000);
  eq('후원 상당액 합계', st.sponsorValueTotal, 180000);
  eq('지출 합계', st.expenseTotal, 90000);
  eq('잔액 = 190,000-90,000', st.balance, 100000);

  final data = SettlementBuilder.build(
    settlement: st,
    fees: fees,
    expenses: expenses,
    attendees: const [
      {'name': '김참가', 'role': '스카우트', 'number': '415'},
    ],
  );
  eq('블록 6개 생성', data.length, 6);
  final inc = data[SettlementBlock.income]!;
  check(
    '수입 블록 3칸 이상',
    inc.rows.every((r) => r.length >= 3),
    '${inc.rows}',
  );
  check(
    '수입 블록에 후원(현물) 미포함',
    inc.rows.any((r) => r[0] == '후원금' && r[1] == '100,000원') == true,
  );
  eq('수입 상세 = 참가비+후원금+기타수입 3건', inc.details.length, 3);
  check(
    '수입 상세에 식사후원 없음',
    inc.details.every((d) => !d.contains('식사후원')),
    '${inc.details}',
  );
  final sp = data[SettlementBlock.sponsor]!;
  eq('후원 상세 3건', sp.details.length, 3);
  check('후원 블록은 후원 합계행 포함', sp.rows.any((r) => r[0] == '후원 합계'));
  check(
    '후원 합계 = 현금 30,000 + 상당 180,000',
    sp.rows.last[1].contains('30,000원') && sp.rows.last[1].contains('180,000원 상당'),
    sp.rows.last[1],
  );
  check(
    '후원 합계 비고에 수입 미포함 명시',
    sp.rows.last[2].contains('수입 미포함'),
    sp.rows.last[2],
  );

  final bal = data[SettlementBlock.balance]!;
  eq('잔액 행 수', bal.rows.length, 3);
  eq('잔액 금액', bal.rows[2][1], '100,000원');

  // ignore: avoid_print
  print('=== 4. DonationKind 분류 / 후원자 묶음 ===');
  eq('참가비는 후원 아님', DonationKind.parse('참가비').isIncome, false);
  eq('후원금 isIncome', DonationKind.parse('후원금').isIncome, true);
  eq('식사후원 isSponsor', DonationKind.parse('식사후원').isSponsor, true);
  eq('수송지원 → 차량후원', DonationKind.parse('수송지원').label, '차량후원');
  eq('후원(옛값) → 기타후원', DonationKind.parse('후원').label, '기타후원');
  final ds = DonationSummary(fees.map(DonationRow.fromMap).toList());
  eq('후원금 행 1건', ds.cashRows.length, 1);
  eq('후원(현물) 행 3건', ds.sponsorRows.length, 3);
  eq('후원자별 묶음 3명', ds.bySponsor.length, 3);
  check(
    '후원자 묶음에 후원내역 문자열',
    ds.bySponsor.any((g) => g.itemSummary.contains('김밥 100줄')),
    ds.bySponsor.map((g) => g.itemSummary).join(' | '),
  );
  eq('식사후원 상당액', ds.byKind['식사후원']!.$2, 80000);

  // ignore: avoid_print
  print('=== 4b. 상세 내역 출력 선택(showDetails/detailOff) ===');
  // (요구) "결산에 후원내역 상세 항목, 지출 및 참가비 등도 상세 내역을 결산시
  //  보여주고 미리보기 창에서 출력여부를 상세까지 선택"
  {
    final l = SettlementLayout();
    eq('기본값: 상세 켜짐', l.showDetails, true);
    eq('기본값: 설명 켜짐', l.showNotes, true);
    eq('기본값: 개별 예외 없음', l.detailOff.length, 0);
    eq('블록 6개 모두 상세', l.detailCount, SettlementBlock.values.length);
    check('기본 anyDetail 참', l.anyDetail);

    // 전체 끄기
    l.setAllDetails(false);
    eq('전체 끄면 showDetails=false', l.showDetails, false);
    eq('전체 끄면 detailCount=0', l.detailCount, 0);
    check('전체 끄면 anyDetail 거짓', !l.anyDetail);
    check('블록별도 거짓', !l.showsDetail(SettlementBlock.income));

    // 전체 켜기
    l.setAllDetails(true);
    check('다시 켜면 블록별 참', l.showsDetail(SettlementBlock.income));

    // 한 블록만 끄기 — 나머지는 유지돼야 한다(핵심 회귀 방지).
    l.toggleDetail(SettlementBlock.sponsor);
    check('후원 상세 꺼짐', !l.showsDetail(SettlementBlock.sponsor));
    check('수입 상세 유지', l.showsDetail(SettlementBlock.income));
    eq('detailCount 5', l.detailCount, SettlementBlock.values.length - 1);

    // 전체를 껐다가 개별로 하나만 켜면 — 그 블록만 보여야 한다.
    l.setAllDetails(false);
    eq('전체 끄면 0', l.detailCount, 0);
    l.toggleDetail(SettlementBlock.expenseCategory);
    check('개별 켜면 그 블록 참', l.showsDetail(SettlementBlock.expenseCategory));
    check('수입은 여전히 상세 꺼짐', !l.showsDetail(SettlementBlock.income));
    eq('detailCount 1', l.detailCount, 1);
    check('anyDetail 참', l.anyDetail);

    // 복사본은 값을 그대로 가져야 한다(미리보기 → 출력 문서).
    final cp = l.copy();
    eq('copy showDetails', cp.showDetails, true);
    eq('copy detailOff', cp.detailOff.length, l.detailOff.length);
    check('copy 상세 동일', cp.showsDetail(SettlementBlock.expenseCategory));
    // 원본을 바꿔도 복사본은 영향 없음.
    l.setAllDetails(true);
    eq('copy 독립(detailOff)', cp.detailOff.length, SettlementBlock.values.length - 1);

    // 직렬화 왕복
    final j = SettlementLayout.fromJson(
      l.toJson(),
      l.excludedJson(),
      fontScale: 1.1,
      rowSpace: 0.9,
      landscape: true,
      noWrap: false,
      showDetails: false,
      showNotes: false,
      detailOff: ['income', 'balance'],
    );
    eq('왕복 showDetails', j.showDetails, false);
    eq('왕복 showNotes', j.showNotes, false);
    // 옛 저장값(showDetails=false)은 '전체 상세 끔'으로 복원되므로 6개가 된다.
    //  → 레거시 호환 규칙: showDetails=false + detailOff 2개 = 전체 끔(6).
    eq('왕복 detailOff = 전체(레거시 호환)', j.detailOff.length, 6);
    check('왕복 detailOff 내용', j.detailOff.contains(SettlementBlock.balance));
    check(
      'detailOffJson 직렬화',
      j.detailOffJson().contains('income'),
      j.detailOffJson().join(','),
    );

    // 배지에 상세 상태가 드러나야 한다(사용자가 '왜 표가 짧지?'를 바로 안다).
    final offAll = SettlementLayout();
    offAll.setAllDetails(false);
    final b1 = offAll.styleBadge;
    check('배지: 상세 없음', b1.contains('상세 없음'), b1);
    final b2 = SettlementLayout().styleBadge;
    check('배지: 상세 n/m', b2.contains('상세 6/6'), b2);
  }

  // ignore: avoid_print
  print('=== 4c. 상세 행 펼치기(detailRows) ===');
  {
    const d = SettlementBlockData(
      block: SettlementBlock.sponsor,
      rows: [
        ['식사후원', '100,000원', '1건'],
      ],
      note: '후원 1건',
      details: ['김철수 · 식사후원 · 김밥 100줄 · 100,000원'],
    );
    final rr = d.detailRows();
    eq('상세 1행', rr.length, 1);
    eq('열 4개', rr.first.length, 4);
    eq('1열 표시', rr.first[0], '· 상세');
    check('2열에 원본', rr.first[1].contains('김밥 100줄'), rr.first[1]);
    eq('3열 비움', rr.first[2], '');
    eq('4열 비움', rr.first[3], '');

    // 상한 초과 — '… 외 N건' 안내 행이 붙는다.
    final many = SettlementBlockData(
      block: SettlementBlock.income,
      rows: const [],
      note: '',
      details: [for (var i = 0; i < 12; i++) '행$i'],
    );
    final m5 = many.detailRows(max: 5);
    eq('상한 5 + 안내 1 = 6행', m5.length, 6);
    check('초과 안내', m5.last[1].contains('외 7건'), m5.last[1]);

    // 상세가 없으면 빈 목록(표에 빈 줄이 끼지 않는다).
    const none = SettlementBlockData(
      block: SettlementBlock.balance,
      rows: [],
      note: '',
    );
    eq('상세 없으면 0행', none.detailRows().length, 0);
    check('hasDetails 거짓', !none.hasDetails);
  }

  // ignore: avoid_print
  print('=== 4d. 메모 · 보고서형 블록 ===');
  {
    // (요구) "결산시에도 메모 내역을 추가해서 보여주고, 항목을 선택할 수 있도록"
    final withMemo = SettlementBuilder.build(
      settlement: EventSettlement(
        title: 't',
        year: '2026',
        attendeeCount: EventAttendeeBreakdown.fromAttendees(const []),
        attendees: const [],
        fees: [
          EventMoneyRow.fromMap(const {
            'id': 'm1',
            'date': '2026-05-01',
            'name': '김철수',
            'category': '참가비',
            'amount': 50000,
            'memo': '현장\n현금 수령',
          }),
        ],
        expenses: [
          EventMoneyRow.fromMap(const {
            'id': 'e1',
            'date': '2026-05-02',
            'name': '식당',
            'category': '행사비',
            'amount': 30000,
            'memo': '영수증 별첨',
          }, expense: true),
        ],
      ),
      fees: const [
        {
          'id': 'm1',
          'date': '2026-05-01',
          'name': '김철수',
          'category': '참가비',
          'amount': 50000,
          'memo': '현장\n현금 수령',
        },
      ],
      expenses: const [
        {
          'id': 'e1',
          'date': '2026-05-02',
          'name': '식당',
          'category': '행사비',
          'amount': 30000,
          'memo': '영수증 별첨',
        },
      ],
      attendees: const [],
      memo: true,
    );
    final inc = withMemo[SettlementBlock.income]!;
    check(
      '메모 ON → 수입 상세에 메모 포함',
      inc.details.any((d) => d.contains('메모: 현장 현금 수령')),
      inc.details.join(' | '),
    );
    check('줄바꿈은 공백으로 접힘', !inc.details.any((d) => d.contains('\n')));
    final exp = withMemo[SettlementBlock.expenseCategory]!;
    check(
      '메모 ON → 지출 상세에 메모 포함',
      exp.details.any((d) => d.contains('메모: 영수증 별첨')),
      exp.details.join(' | '),
    );

    // 메모 OFF 면 상세에서 사라져야 한다.
    final noMemo = SettlementBuilder.build(
      settlement: EventSettlement(
        title: 't',
        year: '2026',
        attendeeCount: EventAttendeeBreakdown.fromAttendees(const []),
        attendees: const [],
        fees: const [],
        expenses: const [],
      ),
      fees: const [
        {
          'id': 'm1',
          'date': '2026-05-01',
          'name': '김철수',
          'category': '참가비',
          'amount': 50000,
          'memo': '현장 수령',
        },
      ],
      expenses: const [],
      attendees: const [],
      memo: false,
    );
    final inc2 = noMemo[SettlementBlock.income]!;
    check(
      '메모 OFF → 상세에 메모 없음',
      !inc2.details.any((d) => d.contains('메모')),
      inc2.details.join(' | '),
    );
    check('메모 OFF 여도 행 자체는 남음', inc2.details.isNotEmpty);

    // ── 보고서형 블록 변환
    final lay = SettlementLayout();
    final blocks = SettlementReportBuilder.build(layout: lay, data: withMemo);
    eq('블록 수 = 포함 블록 수', blocks.length, lay.includedCount);
    check(
      '첫 블록 제목은 첫 포함 블록',
      blocks.first.title == lay.included.first.label,
      blocks.first.title,
    );
    check(
      '블록마다 강조색 있음',
      blocks.every((b) => b.accent.startsWith('#') && b.accent.length == 7),
    );
    // 상세 ON 이면 표 행에 '· 상세' 가 붙는다.
    final incBlock = blocks.firstWhere(
      (b) => b.title == SettlementBlock.income.label,
    );
    check(
      '상세 ON → 블록에 상세 행 포함',
      incBlock.rows.any((r) => r[0] == '· 상세'),
      incBlock.rows.map((r) => r[0]).join(','),
    );
    // 상세 OFF 면 사라진다.
    lay.setAllDetails(false);
    final blocks2 = SettlementReportBuilder.build(layout: lay, data: withMemo);
    final incBlock2 = blocks2.firstWhere(
      (b) => b.title == SettlementBlock.income.label,
    );
    check(
      '상세 OFF → 상세 행 없음',
      !incBlock2.rows.any((r) => r[0] == '· 상세'),
      incBlock2.rows.map((r) => r[0]).join(','),
    );

    // 설명 OFF 면 note 가 비워진다.
    lay.setAllDetails(true);
    lay.showNotes = false;
    final blocks3 = SettlementReportBuilder.build(layout: lay, data: withMemo);
    check('설명 OFF → note 비움', blocks3.every((b) => b.note.isEmpty));

    // 블록 색은 미리보기와 동일해야 한다(핵심: 화면=출력).
    eq(
      '참가자 색',
      SettlementReportBuilder.accentOf(SettlementBlock.attendees),
      '#2E5F8A',
    );
    eq(
      '잔액 색',
      SettlementReportBuilder.accentOf(SettlementBlock.balance),
      '#3A3A3A',
    );

    // 기본값 검증
    final d0 = SettlementLayout();
    eq('기본 showMemo', d0.showMemo, true);
    eq('기본 reportStyle', d0.reportStyle, true);
    eq('기본 showNotes', d0.showNotes, true);
  }

  // ignore: avoid_print
  print('=== 5. 출력 선택(FinancePickSet) ===');
  final picks = FinancePickSet();
  final ids = FinancePickSet.idsOf(fees);
  eq('처음엔 필터 없음', picks.isFiltered, false);
  eq('전체 포함', picks.filter(fees).length, fees.length);
  picks.toggle(ids[0]);
  eq('1건 제외', picks.filter(fees).length, fees.length - 1);
  check(
    '제외된 행 미포함',
    picks.filter(fees).every((r) => r['id'] != 'a'),
    '${picks.filter(fees).map((e) => e['id']).toList()}',
  );
  picks.toggle(ids[0]);
  eq('다시 포함', picks.filter(fees).length, fees.length);
  picks.excludeAll(ids);
  eq('전체 해제', picks.filter(fees).length, 0);
  picks.includeAll();
  eq('전체 포함 복귀', picks.isFiltered, false);
  eq('포함 id 집합 크기', picks.includedOf(ids).length, fees.length);

  // ignore: avoid_print
  print('');
  // ignore: avoid_print
  print('결과: PASS $_pass / FAIL $_fail');
  if (_fail > 0) {
    throw StateError('검증 실패 $_fail건');
  }
}
