// 결산 집계 로직 단위 검증 — eventAttendeeBreakdown / EventSettlement 합산.
// 실행: dart run tool/verify_settlement.dart
import 'package:tsak_credential_manager/services/event_settlement.dart';

void main() {
  // 1) 직책별 집계 — 실제 참가자 형태(서버 _ev_attendee_view 와 동일 키).
  final list = <Map<String, dynamic>>[
    {'number': '415', 'corps': 'tsak', 'roles': []}, // 인가자
    {'number': '43', 'corps': 'eunha', 'roles': []}, // 인가자(은하)
    {'number': '100', 'corps': 'tsak', 'roles': ['리더']}, // 리더
    {'number': '101', 'corps': 'tsak', 'roles': ['로버스카우트']}, // 로버
    {'number': '102', 'corps': 'tsak', 'roles': ['비버']}, // 비버
    {'number': '103', 'corps': 'tsak', 'roles': ['스카우트']}, // 스카우트
    {'number': '104', 'corps': 'tsak', 'roles': ['벤쳐스카우트']}, // 벤처
    {'phone': '01011112222', 'corps': '', 'roles': []}, // 일반(비인가)
    {'number': '', 'phone': '01033334444', 'corps': '', 'roles': ['기타']},
  ];
  final b = EventAttendeeBreakdown.fromAttendees(list);
  print('인가자=${b.ivga} 리더=${b.leader} 로버=${b.rover} 비버=${b.beaver} '
      '스카우트=${b.scout} 벤처=${b.venture} 일반=${b.regular} 기타=${b.etc}');
  print('합계=${b.total} (기대: 9)');
  print('요약: ${b.summaryLine}');

  // 2) 수입/지출/계좌 합산.
  final s = EventSettlement(
    title: '검증행사',
    year: '2026',
    attendees: list,
    attendeeCount: b,
    fees: [
      EventMoneyRow.fromMap({'category': '참가비', 'amount': 50000}),
      EventMoneyRow.fromMap({'category': '참가비', 'amount': 50000}),
      EventMoneyRow.fromMap({'category': '후원금', 'amount': 300000}),
      EventMoneyRow.fromMap({'category': '후원', 'amount': 200000}),
      EventMoneyRow.fromMap({'category': '수송지원', 'amount': 100000}),
    ],
    expenses: [
      EventMoneyRow.fromMap({
        'category': '수품제작',
        'amount': 150000,
        'account': '수품구매 · 우리은행 1005-102-281143',
      }, expense: true),
      EventMoneyRow.fromMap({
        'category': '각종 지출',
        'amount': 50000,
        'account': '행사비 · 우리은행 1005-003-886274',
      }, expense: true),
      EventMoneyRow.fromMap({
        'category': '각종 지출',
        'amount': 30000,
        'account': '행사비 · 우리은행 1005-003-886274',
      }, expense: true),
    ],
  );
  print('참가비=${s.feeTotal} 후원금=${s.donationFund} 후원=${s.donation} '
      '기타수입=${s.otherIncome}');
  print('수입합계=${s.incomeTotal} 지출합계=${s.expenseTotal} 잔액=${s.balance}');
  print('분류별=${s.expenseByCategory}');
  print('계좌별=${s.expenseByAccount}');

  // 3) 검증 단정.
  final ok = <String>[];
  void check(String name, bool cond) {
    ok.add('${cond ? "PASS" : "FAIL"} $name');
  }

  check('직책 합계 9', b.total == 9);
  check('인가자 2', b.ivga == 2);
  check('벤처 1', b.venture == 1);
  check('일반 2', b.regular == 2);
  check('참가비합계 100000', s.feeTotal == 100000);

  // ── 수입 규칙 (요구: "후원금만 수입으로 잡을 것") ──────────────────────
  //  참가비 100,000 + 후원금 300,000 = 수입 400,000.
  //  '후원'(→기타후원) 200,000 과 '수송지원'(→차량후원) 100,000 은
  //  현물후원이므로 **수입에 넣지 않는다**. 대신 sponsorCashTotal 로만 집계.
  check('후원금(현금) 300000', s.donationFund == 300000);
  check('현물후원 현금 300000', s.donation == 300000);
  check('기타수입 0', s.otherIncome == 0);
  check('수입합계 400000 (참가비+후원금만)', s.incomeTotal == 400000);
  check('지출합계 230000', s.expenseTotal == 230000);
  check('잔액 170000', s.balance == 170000);
  check('현물후원 참고합계 300000', s.sponsorReferenceTotal == 300000);
  check('행사비계좌 80000',
      s.expenseByAccount['행사비 · 우리은행 1005-003-886274'] == 80000);
  check('콤마표기', EventSettlement.comma(170000) == '170,000');

  for (final r in ok) {
    print(r);
  }
  final fails = ok.where((e) => e.startsWith('FAIL')).length;
  print(fails == 0 ? '\n전체 ${ok.length}개 통과' : '\n실패 $fails건');
}
