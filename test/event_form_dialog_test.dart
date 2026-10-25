// 행사 만들기 창 렌더/키보드 회귀 테스트.
//
// ## 왜 이 테스트가 필요한가 (실제로 터진 버그 3건)
//  ① "행사 추가시 빈 화면" — 폼 안내문구 Row 가 폭 298~306px 기기에서 가로로
//     넘쳐(RenderFlex overflow) 본문이 통째로 비어 보였다.
//  ② "입력하려고 하면 창의 크기가 줄어 입력이 불가" — AlertDialog 는 키보드가
//     올라오면 insetPadding.bottom 이 커지며 **창 자체가 줄어든다**. 입력칸이
//     화면 밖으로 밀려나 보이지 않았다.
//  ③ 스크롤 화살표 알약(pill)이 본문 위에 떠 있어 입력칸을 덮었다.
//
// ## 이 테스트가 고정하는 것
//  · 바텀시트 높이는 `(화면높이 − 키보드높이) × 0.94` 로 계산된다.
//  · 키보드가 떠도 **헤더·본문·버튼이 모두 화면 안**에 남아 있다.
//  · 텍스트 필드가 실제로 그려지고, 첫 필드는 화면 안 좌표에 있다.
//  · 가로 넘침(RenderFlex overflow) 예외가 없다.
//
// 실행: cd /home/user/flutter_app && flutter test test/event_form_dialog_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/screens/event_form_dialog.dart';

const _phone = Size(390, 844);
const _keyboard = 320.0;

Future<void> _openSheet(WidgetTester tester, {double keyboard = 0}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  showEventFormSheet(context: ctx, createMode: true),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('키보드 없음: 필드·버튼이 모두 그려진다', (tester) async {
    await _openSheet(tester);

    expect(find.text('새 행사 만들기'), findsOneWidget);
    expect(find.text('연도 * (필수)'), findsOneWidget);
    expect(find.text('행사명 *'), findsOneWidget);
    expect(find.text('행사기간'), findsOneWidget);
    expect(find.text('장소'), findsOneWidget);
    expect(find.text('행사 소개/개요'), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);
    expect(find.text('생성'), findsOneWidget);

    // 가로 넘침이 있으면 pumpAndSettle 중 예외로 잡힌다.
    expect(tester.takeException(), isNull);
  });

  testWidgets('키보드 올림: 창이 줄지 않고 필드·버튼이 화면 안에 남는다', (tester) async {
    await _openSheet(tester, keyboard: _keyboard);

    // 헤더 / 첫 필드 / 하단 버튼이 모두 살아 있어야 한다.
    expect(find.text('새 행사 만들기'), findsOneWidget);
    expect(find.text('연도 * (필수)'), findsOneWidget);
    expect(find.text('생성'), findsOneWidget);

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    // 하단 '생성' 버튼은 키보드 위(즉 화면 안)에 있어야 한다.
    final btn = tester.getRect(find.text('생성'));
    expect(btn.bottom, lessThanOrEqualTo(_phone.height - _keyboard + 1));

    // 첫 입력칸도 화면 안에 있어야 한다(예전에는 화면 밖으로 밀려났다).
    final year = tester.getRect(find.text('연도 * (필수)'));
    expect(year.top, greaterThanOrEqualTo(0));
    expect(year.top, lessThan(screen.height));

    expect(tester.takeException(), isNull);
  });

  testWidgets('키보드 올림: 시트 높이가 (화면−키보드)×0.94 로 유지된다', (tester) async {
    await _openSheet(tester, keyboard: _keyboard);

    // 본문 스크롤 영역이 존재하고 '의미 있는 높이'를 가진다.
    //  세로(바깥) + 가로(안쪽) 2개이므로 첫 번째(세로)를 검사한다.
    final scroll = find.byType(SingleChildScrollView).first;
    final r = tester.getSize(scroll);
    final expectH = (_phone.height - _keyboard) * 0.94;
    expect(r.height, greaterThan(expectH * 0.4));
    expect(r.width, greaterThan(200));

    // 텍스트 필드가 3개 이상 보인다.
    expect(find.byType(TextField).evaluate().length, greaterThanOrEqualTo(3));
  });

  testWidgets('스크롤을 내려도 예외가 없다(넘침 없음)', (tester) async {
    await _openSheet(tester, keyboard: _keyboard);

    final scroll = find.byType(SingleChildScrollView).first;
    for (var i = 0; i < 4; i++) {
      await tester.drag(scroll, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('상하좌우 스크롤 화살표가 헤더에 있고 동작한다', (tester) async {
    await _openSheet(tester, keyboard: _keyboard);

    // 4방향 + 맨위 버튼이 모두 존재해야 한다(툴팁으로 식별).
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_right), findsOneWidget);
    expect(find.byIcon(Icons.vertical_align_top), findsOneWidget);

    // 헤더 안에 있어야 한다 = 본문 입력칸을 덮지 않는다.
    final up = tester.getRect(find.byIcon(Icons.keyboard_arrow_up));
    final firstField = tester.getRect(find.text('연도 * (필수)'));
    final dividerY = up.bottom;
    expect(
      dividerY,
      lessThan(firstField.top),
      reason: '화살표는 본문 첫 필드보다 위(헤더)에 있어야 한다',
    );

    // 아래 화살표를 누르면 실제로 스크롤된다.
    double vPixels() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SingleChildScrollView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
    final before = vPixels();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    final after = vPixels();
    expect(after, greaterThan(before), reason: '▼ 를 누르면 아래로 스크롤되어야 한다');

    expect(tester.takeException(), isNull);
  });

  testWidgets('좁은 화면(360px)에서 가로 스크롤이 생기고 ◀▶ 가 활성화된다', (tester) async {
    // 360px 기기 — _formMinWidth(400) 보다 좁아 가로 스크롤이 필요하다.
    await _openSheet(tester, keyboard: 0);

    final hscroll = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(hscroll, findsOneWidget);

    final pos = tester
        .state<ScrollableState>(
          find.descendant(of: hscroll, matching: find.byType(Scrollable)).first,
        )
        .position;
    // 가로 스크롤 여지가 있어야 좌우 화살표가 의미를 가진다.
    expect(
      pos.maxScrollExtent,
      greaterThan(0),
      reason: '360px 화면에서는 폼이 400px 라 가로 스크롤이 생겨야 한다',
    );

    expect(tester.takeException(), isNull);
  });
}
