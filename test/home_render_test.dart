import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/app_state.dart';
import 'package:tsak_credential_manager/services/member_repository.dart';
import 'package:tsak_credential_manager/screens/home_screen.dart';
import 'package:tsak_credential_manager/theme/app_theme.dart';

/// 홈 화면이 실제로 명단을 렌더링하는지 검증
void main() {
  testWidgets('HomeScreen renders member list', (tester) async {
    Hive.init('/tmp/tsak_hive_test');
    final box = await Hive.openBox('test_members');
    final meta = await Hive.openBox('test_meta');
    final repo = MemberRepository.withBoxes(box, meta);
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

    // 명단이 표시되어야 함
    expect(find.text('김용우'), findsWidgets);
    expect(find.text('노경하'), findsWidgets);
    expect(find.text('TSAK 인가자 관리'), findsOneWidget);
    expect(find.text('명단 크기'), findsOneWidget);

    // 오류 없이 렌더링됨
    expect(tester.takeException(), isNull);

    await box.deleteFromDisk();
    await meta.deleteFromDisk();
  });
}
