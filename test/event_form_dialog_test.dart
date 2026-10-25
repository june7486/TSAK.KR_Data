// 행사 만들기 창 렌더 회귀 테스트.
//
// ## 왜 이 테스트가 필요한가
// "새 행사 만들기" 다이얼로그가 **완전히 빈 화면**으로 뜨는 심각한 버그가
// 있었다. 원인은 레이아웃 제약(Row 확장 + loose)과 초기 포커스 설정이었다.
// 같은 문제가 다시 생기지 않도록 **필드가 실제로 그려지는지**를 고정한다.
//
// 실행: cd /home/user/flutter_app && flutter test test/event_form_dialog_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/screens/event_form_dialog.dart';

Widget _host({Size size = const Size(390, 844)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: const Scaffold(
        body: Center(child: EventFormDialog(createMode: true)),
      ),
    ),
  );
}

void main() {
  testWidgets('새 행사 만들기: 필드가 실제로 그려진다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // 다이얼로그 제목
    expect(find.text('새 행사 만들기'), findsOneWidget);

    // 반드시 보여야 하는 핵심 입력칸들
    expect(find.text('연도 * (필수)'), findsOneWidget);
    expect(find.text('행사명 *'), findsOneWidget);
    expect(find.text('행사기간'), findsOneWidget);
    expect(find.text('장소'), findsOneWidget);
    expect(find.text('행사 소개/개요'), findsOneWidget);

    // 취소 / 생성 버튼
    expect(find.text('취소'), findsOneWidget);
    expect(find.text('생성'), findsOneWidget);
  });

  testWidgets('새 행사 만들기: 본문 스크롤이 실제로 그려진다(빈 화면 아님)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // 본문 SingleChildScrollView 가 존재하고 0 보다 큰 크기로 그려져야 한다.
    final scroller = find.byType(SingleChildScrollView);
    expect(scroller, findsWidgets);
    final boxes = tester.widgetList<SingleChildScrollView>(scroller);
    expect(boxes.isNotEmpty, isTrue);

    // 첫 번째 스크롤 영역의 렌더 크기가 0 이 아니어야 한다(빈 화면 방지).
    final size = tester.getSize(scroller.first);
    expect(size.height, greaterThan(100));
    expect(size.width, greaterThan(100));

    // TextField 가 여러 개 그려져야 한다.
    expect(find.byType(TextField), findsAtLeastNWidgets(3));
  });

  testWidgets('새 행사 만들기: 첫 입력칸이 화면 안(맨 위)에 있다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // '연도' 라벨이 화면 영역 안에 있어야 한다(중간부터 열리던 버그 방지).
    final year = find.text('연도 * (필수)');
    expect(year, findsOneWidget);
    final r = tester.getRect(year);
    expect(r.top, greaterThan(0));
    expect(r.bottom, lessThan(844));
  });

  testWidgets('새 행사 만들기: 키보드가 올라와도 필드가 남아 있다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('연도 * (필수)'), findsOneWidget);

    // 키보드가 올라온 상황을 흉내낸다.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    // 여전히 필드가 존재해야 한다(빈 화면이 되면 실패).
    expect(find.text('연도 * (필수)'), findsOneWidget);
    expect(find.byType(TextField), findsAtLeastNWidgets(1));
  });
}
