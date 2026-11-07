// turn79 — 결산서 '참가비 N명 납부' 인원 계산 회귀 테스트
//
// ## 실제 증상 (사용자 스크린샷)
//   2026 범2호 노경하선배 추모행사 결산서
//     수입 / 참가비   600,000원   **9명 납부**   ← 실제 참가자는 6명
//     수입 / 후원금   300,000원   3건
//     상세 내역                             9건
//   10만원 × 6명 = 60만원이므로 정답은 **6명**.
//
// ## 원인
//   payers = settlement.fees.where((e) => e.amount > 0).length
//   `fees` 에는 참가비·후원금·기타수입이 모두 들어 있어 6 + 3 = 9 가 됐다.
//   금액은 '참가비'만 합산했으므로 **금액과 인원이 다른 기준**이었다.
//
// ## 이 테스트가 지키는 것
//   · 인원수는 참가비 행만 센다 (후원금 건수와 무관)
//   · 후원금은 후원 항목에 집계되고 참가비에는 절대 더해지지 않는다
//   · 수입 합계에 이중 계상이 없다
//   · 같은 사람이 두 번 내도 '명'이 부풀지 않는다
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/donation_kinds.dart';
import 'package:tsak_credential_manager/services/event_settlement.dart';
import 'package:tsak_credential_manager/services/settlement_layout.dart';

EventMoneyRow _row(
  String category,
  int amount, {
  String name = '',
  String number = '',
  int? value,
  String item = '',
}) => EventMoneyRow(
  date: '2026-11-07',
  category: category,
  name: name,
  number: number,
  memo: '',
  account: '',
  amount: amount,
  valueAmount: value,
  item: item,
);

EventSettlement _settle(List<EventMoneyRow> fees) => EventSettlement(
  title: '2026 범2호 노경하선배 추모행사',
  year: '2026',
  attendees: const [],
  fees: fees,
  expenses: const [],
  attendeeCount: const EventAttendeeBreakdown(),
);

/// 화면에 실제로 나가는 사례 — 참가비 6명(10만원씩) + 후원금 3건(10만원씩).
EventSettlement _screenshotCase() => _settle([
  for (var i = 1; i <= 6; i++)
    _row('참가비', 100000, name: '참가자$i', number: '${400 + i}'),
  for (var i = 1; i <= 3; i++)
    _row('후원금', 100000, name: '후원자$i', number: '${500 + i}'),
]);

void main() {
  group('참가비 인원 — 참가비 행만 센다', () {
    test('후원금이 섞여도 인원이 9가 아니라 6이다', () {
      final s = _screenshotCase();
      expect(s.feeTotal, 600000, reason: '참가비 합계는 6명 × 10만원');
      expect(s.feePayCount, 6, reason: '결제 건수 = 6');
      expect(s.feePayerCount, 6, reason: '납부자 수 = 6  (종전 9 였다)');
    });

    test('후원금은 참가비에 절대 더해지지 않는다', () {
      final s = _screenshotCase();
      expect(s.cashDonationTotal, 300000);
      // 참가비 합계는 후원금과 무관하게 60만원이어야 한다.
      expect(s.feeTotal, 600000);
      expect(s.feeTotal, isNot(900000));
    });

    test('수입 합계에 이중 계상이 없다 (60만 + 30만 = 90만)', () {
      final s = _screenshotCase();
      expect(s.incomeTotal, 900000);
    });

    test('후원금만 있고 참가비가 없으면 인원은 0명', () {
      final s = _settle([
        _row('후원금', 100000, name: '후원자1', number: '501'),
        _row('후원금', 100000, name: '후원자2', number: '502'),
      ]);
      expect(s.feeTotal, 0);
      expect(s.feePayerCount, 0);
      expect(s.cashDonationTotal, 200000);
    });

    test('기타수입도 인원에서 제외된다', () {
      final s = _settle([
        _row('참가비', 100000, name: 'A', number: '1'),
        _row('참가비', 100000, name: 'B', number: '2'),
        _row('기타수입', 50000, name: 'C', number: '3'),
      ]);
      expect(s.feePayerCount, 2, reason: '기타수입 1건은 인원이 아니다');
      expect(s.feePayCount, 2);
    });

    test('0원 참가비 행은 인원으로 세지 않는다', () {
      final s = _settle([
        _row('참가비', 100000, name: 'A', number: '1'),
        _row('참가비', 0, name: 'B', number: '2'),
      ]);
      expect(s.feePayerCount, 1);
      expect(s.feePayCount, 1);
    });
  });

  group('같은 사람이 두 번 내도 명이 부풀지 않는다', () {
    test('같은 인가번호로 2건 → 1명', () {
      final s = _settle([
        _row('참가비', 50000, name: '이승준', number: '415'),
        _row('참가비', 50000, name: '이승준', number: '415'),
      ]);
      expect(s.feePayCount, 2, reason: '결제 건수는 2건');
      expect(s.feePayerCount, 1, reason: '사람 수는 1명');
      expect(s.feeTotal, 100000);
    });

    test('번호가 없으면 이름으로 묶는다', () {
      final s = _settle([
        _row('참가비', 50000, name: '김철수'),
        _row('참가비', 50000, name: '김철수'),
      ]);
      expect(s.feePayerCount, 1);
    });

    test('식별자가 전혀 없으면 행 수로 되돌아간다(0명 방지)', () {
      final s = _settle([
        _row('참가비', 50000),
        _row('참가비', 50000),
      ]);
      expect(s.feePayerCount, 2);
    });
  });

  group('1인당 금액 표시', () {
    test('나누어떨어지면 1인 금액을 보여 준다', () {
      expect(_screenshotCase().feePerPayer, 100000);
    });

    test('나누어떨어지지 않으면 0(표시 생략)', () {
      // 100,000 + 100,000 + 50,000 = 250,000원 / 3명 = 83,333.33… → 나누어떨어지지 않음
      final s = _settle([
        _row('참가비', 100000, name: 'A', number: '1'),
        _row('참가비', 100000, name: 'B', number: '2'),
        _row('참가비', 50000, name: 'C', number: '3'),
      ]);
      expect(s.feeTotal, 250000);
      expect(s.feePayerCount, 3);
      expect(s.feePerPayer, 0,
          reason: '250,000 / 3 은 나누어떨어지지 않으므로 1인 금액을 표시하지 않는다');
    });

    test('납부자가 없으면 0', () {
      expect(_settle(const []).feePerPayer, 0);
    });
  });

  group('결산서 화면 문구', () {
    test('참가비 줄에 6명이 표시되고 9명이 아니다', () {
      final out = SettlementBuilder.build(
        settlement: _screenshotCase(),
        fees: const [],
        expenses: const [],
        attendees: const [],
      );
      final inc = out[SettlementBlock.income]!;
      final feeRow = inc.rows.firstWhere((r) => r[0] == '참가비');
      expect(feeRow[1], '600,000원');
      expect(feeRow[2], contains('6명'));
      expect(feeRow[2], isNot(contains('9명')));
      expect(feeRow[2], contains('1인 100,000원'));
    });

    test('후원금 줄은 3건으로 참가비와 분리 표시된다', () {
      final out = SettlementBuilder.build(
        settlement: _screenshotCase(),
        fees: const [],
        expenses: const [],
        attendees: const [],
      );
      final inc = out[SettlementBlock.income]!;
      final donRow = inc.rows.firstWhere((r) => r[0] == '후원금');
      expect(donRow[1], '300,000원');
      expect(donRow[2], '3건');
    });

    test('수입 합계는 90만원', () {
      final out = SettlementBuilder.build(
        settlement: _screenshotCase(),
        fees: const [],
        expenses: const [],
        attendees: const [],
      );
      final row = out[SettlementBlock.income]!.rows
          .firstWhere((r) => r[0] == '수입 합계');
      expect(row[1], '900,000원');
    });
  });

  group('후원금은 후원 항목에도 집계된다', () {
    Map<String, dynamic> raw(
      String cat,
      int amt, {
      String name = '',
      int value = 0,
    }) => {
      'date': '2026-11-07',
      'category': cat,
      'name': name,
      'number': '',
      'memo': '',
      'account': '',
      'amount': amt,
      'value': value,
      'item': '',
    };

    test('후원 블록 첫 줄에 후원금(현금)이 나온다', () {
      final out = SettlementBuilder.build(
        settlement: _screenshotCase(),
        fees: [
          for (var i = 1; i <= 6; i++) raw('참가비', 100000, name: '참가자$i'),
          for (var i = 1; i <= 3; i++) raw('후원금', 100000, name: '후원자$i'),
        ],
        expenses: const [],
        attendees: const [],
      );
      final sp = out[SettlementBlock.sponsor]!;
      final cash = sp.rows.firstWhere((r) => r[0] == DonationKind.cash.label);
      expect(cash[1], '300,000원', reason: '후원금 30만원이 후원 항목에 집계');
      expect(cash[2], contains('수입 포함'));
      expect(sp.empty, isFalse);
    });

    test('참가비는 후원 블록에 절대 섞이지 않는다', () {
      final out = SettlementBuilder.build(
        settlement: _screenshotCase(),
        fees: [
          for (var i = 1; i <= 6; i++) raw('참가비', 100000, name: '참가자$i'),
          for (var i = 1; i <= 3; i++) raw('후원금', 100000, name: '후원자$i'),
        ],
        expenses: const [],
        attendees: const [],
      );
      final sp = out[SettlementBlock.sponsor]!;
      // 어떤 줄에도 참가비 60만원이 나타나면 안 된다.
      for (final r in sp.rows) {
        expect(r[1], isNot('600,000원'),
            reason: '후원 블록에 참가비가 새어 들어갔다: ${r[0]}');
      }
      // 상세에도 참가비 항목이 없어야 한다.
      for (final d in sp.details) {
        expect(d.contains('참가비'), isFalse,
            reason: '후원 상세에 참가비가 섞였다: $d');
      }
    });

    test('후원금과 현물이 모두 있으면 두 줄이 나온다', () {
      final out = SettlementBuilder.build(
        settlement: _screenshotCase(),
        fees: [
          raw('후원금', 100000, name: '현금후원'),
          raw('식사후원', 0, name: '김밥후원', value: 200000),
        ],
        expenses: const [],
        attendees: const [],
      );
      final sp = out[SettlementBlock.sponsor]!;
      expect(sp.rows.any((r) => r[0] == DonationKind.cash.label), isTrue);
      expect(sp.rows.any((r) => r[0] == DonationKind.meal.label), isTrue);
      expect(sp.rows.any((r) => r[0] == '현물 후원 합계'), isTrue);
    });

    test('후원이 전혀 없으면 empty 이고 "없음" 한 줄', () {
      final out = SettlementBuilder.build(
        settlement: _screenshotCase(),
        fees: const [],
        expenses: const [],
        attendees: const [],
      );
      final sp = out[SettlementBlock.sponsor]!;
      expect(sp.empty, isTrue);
      expect(sp.rows.first[0], '후원 내역');
      expect(sp.rows.first[1], '없음');
    });
  });
}
