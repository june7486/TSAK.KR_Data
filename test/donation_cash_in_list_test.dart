// ─────────────────────────────────────────────────────────────────────────────
//  turn74 — "후원금 리스트에 후원금이 안 보이던 문제"
//
//  ## 사용자 지적 (스크린숏)
//    요약줄:  후원금(수입) 5건 1,400,009원   ← 정상
//    목록  :  "현물후원 내역이 없습니다"      ← 비어 있음
//    → "후원금 리스트에는 해당행사만 취합할것"
//
//  ## 원인
//    목록 데이터가 `isSponsor`(= **현물만**) 로 필터돼 있어서,
//    후원금(현금) 행은 요약줄에서만 세어지고 **목록에는 한 번도
//    그려지지 않았다.** 데이터는 멀쩡했고 화면이 빠뜨린 것.
//
//  ## 이 파일이 지키는 계약
//   ① 후원금(현금) 행이 실제로 목록 카드로 **렌더링**된다.
//   ② 현물후원도 함께 렌더링된다(둘 다 보인다).
//   ③ 요약줄의 두 숫자(수입 / 수입미포함)는 서로 **섞이지 않는다**.
//   ④ 내역별 보기에 '후원금(현금)' 분류가 있다.
//   ⑤ 다른 행사 자료가 섞이지 않는다(입력 rows 만 그린다).
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tsak_credential_manager/services/donation_kinds.dart';
import 'package:tsak_credential_manager/widgets/donation_list_panel.dart';

/// 이 행사의 실제 후원 행(2026 범2호 노경하 선배 추모행사 기준).
List<Map<String, dynamic>> _rows() => [
  {
    'name': '김승수',
    'number': '326',
    'amount': 100009,
    'date': '2026-11-07',
    'category': '후원금',
    'memo': '대표계좌로 입금',
    'id': 'a1',
  },
  {
    'name': '김원태',
    'number': '305',
    'amount': 1000000,
    'date': '2026-11-07',
    'category': '후원금',
    'id': 'a2',
  },
  {
    'name': '정우식',
    'number': '278',
    'amount': 100000,
    'date': '2026-11-07',
    // 참가비는 후원 목록에서 제외된다(수입이지만 후원이 아님).
    'category': '참가비',
    'id': 'a3',
  },
  {
    'name': '이항복',
    'number': '75',
    'amount': 0,
    'value': 200000,
    'date': '2026-11-07',
    'category': '물품후원',
    'item': '기념품 200개',
    'id': 'a4',
  },
];

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> rows,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DonationListPanel(
          rows: rows,
          onOutput: (_, _) {},
          onEdit: (_) {},
          onDelete: (_) async => true,
          onAdd: () {},
          onOpenMember: (_, _) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('① 후원금(현금)이 목록에 실제로 보인다', () {
    testWidgets('후원금 후원자 이름이 카드로 렌더링된다', (tester) async {
      await _pump(tester, _rows());
      // 종전에는 이 두 이름이 화면 어디에도 없었다(현물만 그렸으므로).
      expect(find.text('김승수'), findsWidgets);
      expect(find.text('김원태'), findsWidgets);
    });

    testWidgets('"현물후원 내역이 없습니다" 가 더 이상 뜨지 않는다', (tester) async {
      await _pump(tester, _rows());
      expect(find.text('현물후원 내역이 없습니다'), findsNothing);
    });

    testWidgets('현물후원도 함께 보인다', (tester) async {
      await _pump(tester, _rows());
      expect(find.text('이항복'), findsWidgets);
    });

    testWidgets('참가비는 후원 목록에 섞이지 않는다', (tester) async {
      await _pump(tester, _rows());
      // 정우식은 참가비만 냈으므로 후원 목록에 나오면 안 된다.
      expect(find.text('정우식'), findsNothing);
    });

    testWidgets('빈 목록이면 안내 문구가 나온다', (tester) async {
      await _pump(tester, const []);
      expect(find.text('이 행사에 등록된 후원 내역이 없습니다'), findsOneWidget);
    });
  });

  group('② 요약줄 — 수입과 현물이 섞이지 않는다', () {
    testWidgets('후원금 줄과 현물후원 줄이 따로 있다', (tester) async {
      await _pump(tester, _rows());
      expect(find.text('후원금(수입)'), findsOneWidget);
      expect(find.text('현물후원'), findsOneWidget);
    });

    testWidgets('후원금은 3건(김승수·김원태 ×2), 참가비 제외', (tester) async {
      await _pump(tester, _rows());
      // 후원금 3건 = 100009 + 1000000 (김원태는 1건만 넣었으므로 2건)
      expect(find.text('2건'), findsWidgets);
    });
  });

  group('③ 내역별 보기에 후원금(현금) 분류가 있다', () {
    testWidgets('내역별로 바꾸면 후원금 분류 카드가 나온다', (tester) async {
      await _pump(tester, _rows());
      await tester.tap(find.text('내역별'));
      await tester.pumpAndSettle();
      // DonationKind.cash 의 label
      expect(find.text('후원금'), findsWidgets);
      expect(find.text('물품후원'), findsWidgets);
    });
  });

  group('④ 순수 로직 — 현금/현물 분류', () {
    test('후원금만 수입(isIncome)이고 나머지는 현물', () {
      expect(DonationKind.parse('후원금').isIncome, isTrue);
      for (final c in ['식사후원', '물품후원', '차량후원', '기타후원']) {
        expect(DonationKind.parse(c).isIncome, isFalse, reason: c);
      }
    });

    test('참가비·기타수입은 후원 분류가 아니다', () {
      expect(DonationKind.isNonDonation('참가비'), isTrue);
      expect(DonationKind.isNonDonation('기타수입'), isTrue);
      expect(DonationKind.isNonDonation('후원금'), isFalse);
      expect(DonationKind.isNonDonation('물품후원'), isFalse);
    });

    test('DonationRow 는 현금/현물을 스스로 판별한다', () {
      final cash = DonationRow.fromMap({
        'name': '김승수',
        'amount': 100009,
        'category': '후원금',
      });
      final kind = DonationRow.fromMap({
        'name': '이항복',
        'amount': 0,
        'value': 200000,
        'category': '물품후원',
      });
      expect(cash.isIncome, isTrue);
      expect(cash.isSponsor, isFalse);
      expect(kind.isSponsor, isTrue);
      expect(kind.isIncome, isFalse);
      expect(kind.value, 200000);
    });
  });
}
