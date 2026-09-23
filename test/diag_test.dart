import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/app_state.dart';
import 'package:tsak_credential_manager/services/member_repository.dart';
import 'package:tsak_credential_manager/screens/home_screen.dart';
import 'package:tsak_credential_manager/widgets/member_card.dart';
import 'package:tsak_credential_manager/theme/app_theme.dart';

void main() {
  testWidgets('FULL_DATA_DIAG', (tester) async {
    // 실제 웹 캔버스와 동일한 크기
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final raw =
        File('assets/data/members_seed.json').readAsStringSync();
    final list = json.decode(raw) as List<dynamic>;
    final members = list
        .map((e) => Member.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();

    final repo = MemberRepository.memory();
    await repo.init();
    await repo.replaceAll(members);

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
    await tester.pump();

    final ex1 = tester.takeException();
    debugPrint('DIAG after first pump: members=${state.members.length} ex=$ex1');

    await tester.pump(const Duration(milliseconds: 500));
    final ex2 = tester.takeException();
    debugPrint('DIAG after 500ms: ex=$ex2');

    final cards = tester.widgetList<MemberCard>(find.byType(MemberCard)).length;
    debugPrint('DIAG memberCards=$cards');

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d != null)
        .take(20)
        .toList();
    debugPrint('DIAG texts=$texts');

    // 렌더 예외가 있으면 실패시켜 보고
    expect(ex1, isNull, reason: 'First pump exception');
  });
}
