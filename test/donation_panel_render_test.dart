// 후원 패널이 실제로 내역을 그리는지 검증하는 회귀 테스트.
//
// 배경: 후원 탭에서 '현물후원 5건 440,000원' 요약은 보이는데
//       그 아래 **상세 목록이 통째로 비어 있던** 버그가 있었다.
//       원인은 DonationListPanel 내부의 Expanded/ListView 가
//       높이 제약이 없는(unbounded) 부모에 들어가 높이 0 이 된 것.
//
// 이 테스트는 두 가지를 고정한다.
//  1) 높이가 무한인 곳(unbounded)에 넣어도 후원자 이름이 그려진다.
//  2) 높이가 유한한 곳(Expanded)에 넣어도 후원자 이름이 그려진다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/donation_doc.dart';
import 'package:tsak_credential_manager/widgets/donation_list_panel.dart';

// NAS 미러에 실제로 있는 5건과 동일한 형태.
final List<Map<String, dynamic>> _rows = [
  {
    'id': 'f1',
    'name': '이항복',
    'category': '기타',
    'amount': 140000,
    'method': '계좌이체',
    'date': '2026-10-20',
  },
  {
    'id': 'f2',
    'name': '이항복',
    'category': '후원',
    'amount': 80000,
    'method': '계좌이체',
    'date': '2026-10-20',
  },
  {
    'id': 'f3',
    'name': '이승준',
    'category': '기타',
    'amount': 0,
    'method': '',
    'date': '2026-10-20',
  },
  {
    'id': 'f4',
    'name': '이항복',
    'category': '식사후원',
    'amount': 140000,
    'method': '현물',
    'date': '2026-10-20',
  },
  {
    'id': 'f5',
    'name': '이항복',
    'category': '물품후원',
    'amount': 80000,
    'method': '현물',
    'date': '2026-10-20',
  },
];

Widget _panel() => DonationListPanel(
  rows: _rows,
  onAdd: () {},
  onEdit: (_) {},
  onDelete: (_) async {},
  onOutput: (DonationViewMode v, DonationFocus f) {},
);

void main() {
  testWidgets('높이 제약이 없는 곳에서도 후원 내역이 그려진다', (tester) async {
    // 높이를 주지 않는 부모 = 종전 버그 상황 재현.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: _panel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 후원자 이름이 실제로 렌더되어야 한다.
    expect(find.textContaining('이항복'), findsWidgets);
    // 요약도 살아 있어야 한다.
    expect(find.textContaining('440,000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('높이가 유한한 곳(Expanded)에서도 후원 내역이 그려진다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [Expanded(child: _panel())],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('이항복'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('내역별 보기로 전환해도 분류가 그려진다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [Expanded(child: _panel())],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // '내역별' 칩 탭
    final chip = find.text('내역별');
    expect(chip, findsWidgets);
    await tester.tap(chip.first);
    await tester.pumpAndSettle();

    // 분류명이 보여야 한다(현물후원 등).
    expect(find.textContaining('후원'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
