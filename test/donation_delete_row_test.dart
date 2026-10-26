// 후원 항목 '삭제' 동작 회귀 테스트.
//
// 배경(사용자 지적):
//   "행사 관리에서 후원 상세 들어가면 관리 항목 중 삭제 기능이 작동하지 않음"
//
// 원인 2가지:
//  1) 서버: 종전 코드는 `kind == "fee"` 가 아니면 무조건 expenses 배열을
//     뒤졌다. 화면은 후원 탭에서 kind='donation' 을 보내므로 엉뚱한 배열을
//     검색했고, 못 찾아도 {"ok": true} 를 돌려줬다.
//  2) 클라: 삭제 대상을 이름/분류/품목/금액 4개가 **모두 같은** 행으로만
//     찾았다. 같은 후원자가 같은 금액을 두 번 내면 특정 불가 → 메뉴 자체가
//     사라졌다.
//
// 이 테스트는 클라이언트 쪽 2) 를 고정한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/donation_doc.dart';
import 'package:tsak_credential_manager/widgets/donation_list_panel.dart';

// 같은 후원자·같은 분류·같은 금액 2건 (구버전에서 삭제 불가였던 상황)
final List<Map<String, dynamic>> _dupRows = [
  {
    'id': 'a1',
    'name': '이항복',
    'category': '기타후원',
    'item': '현금',
    'amount': 140000,
    'value': 0,
    'date': '2026-10-20',
    'memo': '첫번째',
  },
  {
    'id': 'a2',
    'name': '이항복',
    'category': '기타후원',
    'item': '현금',
    'amount': 140000,
    'value': 0,
    'date': '2026-10-20',
    'memo': '두번째',
  },
];

void main() {
  testWidgets('동일 후원자·동일 금액 2건이어도 각각 삭제 메뉴가 있다', (tester) async {
    final deleted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: DonationListPanel(
                  rows: _dupRows,
                  onAdd: () {},
                  onEdit: (_) {},
                  onDelete: (r) async {
                    deleted.add('${r['id']}');
                    return true;
                  },
                  onOutput: (DonationViewMode v, DonationFocus f) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 후원자 카드를 펼친다.
    final card = find.textContaining('이항복');
    expect(card, findsWidgets);
    await tester.tap(card.first);
    await tester.pumpAndSettle();

    // ⋮ 메뉴가 최소 2개 있어야 한다(각 항목마다 하나).
    final menus = find.byIcon(Icons.more_vert);
    expect(
      menus.evaluate().length,
      greaterThanOrEqualTo(2),
      reason: '중복 건에서도 각 행마다 삭제 메뉴가 있어야 한다',
    );

    // 두 번째 메뉴에서 삭제를 골라 id 'a2' 가 지워지는지 확인.
    await tester.tap(menus.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();

    expect(deleted, contains('a2'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('삭제가 실패하면 false 가 전달된다(조용한 성공 금지)', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: DonationListPanel(
                  rows: [
                    {
                      'id': 'b1',
                      'name': '김철수',
                      'category': '물품후원',
                      'item': '박가스',
                      'amount': 0,
                      'value': 80000,
                      'date': '2026-10-20',
                    },
                  ],
                  onAdd: () {},
                  onEdit: (_) {},
                  onDelete: (_) async {
                    result = false;
                    return false;
                  },
                  onOutput: (DonationViewMode v, DonationFocus f) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('김철수').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
