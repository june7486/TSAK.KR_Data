import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/app_state.dart';
import 'package:tsak_credential_manager/services/member_repository.dart';
import 'package:tsak_credential_manager/screens/home_screen.dart';
import 'package:tsak_credential_manager/theme/app_theme.dart';
import 'package:tsak_credential_manager/widgets/member_card.dart';

void main() {
  testWidgets('HomeScreen renders member list with non-zero height',
      (tester) async {
    final repo = MemberRepository.memory();
    await repo.init();
    await repo.replaceAll([
      Member(id: 'm1', number: '1', name: '김용우'),
      Member(id: 'm2', number: '2', name: '노경하', phone: '011-276-6139'),
      Member(id: 'm3', number: '3', name: '서인식', league: '부산'),
    ]);
    final state = AppState(repo);
    state.refresh();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 리스트가 실제 높이를 가져야 함 (0이면 버그)
    expect(tester.getSize(find.byType(ListView)).height, greaterThan(100));
    expect(find.byType(MemberCard).evaluate().length, 3);
    expect(find.text('김용우'), findsWidgets);
    expect(find.text('노경하'), findsWidgets);
    expect(find.text('명단 크기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('명단 크기 슬라이더가 카드 배율을 변경', (tester) async {
    final repo = MemberRepository.memory();
    await repo.init();
    await repo.replaceAll([Member(id: 'm1', number: '1', name: '김용우')]);
    final state = AppState(repo);
    state.refresh();
    final before = state.listScale;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // '+' 버튼 탭 → 배율 증가
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(state.listScale, greaterThan(before));
    expect(tester.takeException(), isNull);
  });
}
