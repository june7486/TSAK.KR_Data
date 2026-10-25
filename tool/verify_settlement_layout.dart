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
  eq('기본 배지', s.styleBadge, '세로');
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
