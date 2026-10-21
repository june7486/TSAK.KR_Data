// 개인상세 화면의 **중복 노출 정리** 회귀 테스트.
//
// 요구: "멘토/멘티/페런츠 연동 정보 및 방식을 그대로 유지함. 화면만 중복된 내용 정리"
//  · 문제: 같은 3항목이 ① LinkPeopleTiles ② MenteeRegisterSection ③ _linkEditor
//    세 곳에서 반복 노출됐다.
//  · 정리: 멘티/멘토/페런츠는 LinkPeopleTiles 한 곳에서만, 자녀대원만 별도.
//  → 검증: 화면을 실제로 렌더링해 '멘토'·'멘티'·'페런츠' 제목이 각각 1회만
//    등장하는지 센다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/screens/member_detail_screen.dart';
import 'package:tsak_credential_manager/services/app_state.dart';
import 'package:tsak_credential_manager/theme/app_theme.dart';
import 'package:tsak_credential_manager/services/member_repository.dart';

/// 섹션 제목 등장 횟수 — '멘토'처럼 부분 문자열이 겹치는 단어는
///  앞 2글자 기준으로 ' (범을' / ' (내가' 등 실제 제목 패턴으로 판별한다.
int countTitle(String all, String needle) {
  var n = 0;
  var i = all.indexOf(needle);
  while (i >= 0) {
    n++;
    i = all.indexOf(needle, i + needle.length);
  }
  return n;
}

void main() {
  testWidgets('개인상세 — 멘토/멘티/페런츠가 한 번씩만 노출된다', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final m = Member(
      id: 'm1',
      number: '415',
      name: '이승준',
      league: '인천',
      unit: '제1234단 인천연맹 직할대',
      date: '1990-03-21',
      atasNo: '13702',
      nameEn: 'Seung Jun LEE',
      mentors: const ['100'],
      parents: const ['200'],
      mentees: const ['300'],
    );

    final repo = MemberRepository.memory();
    await repo.init();
    await repo.replaceAll([m]);
    final state = AppState(repo);
    state.refresh();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MemberDetailScreen(memberId: 'm1'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');

    // 섹션 제목은 '멘티 (내가 배출한 범 대원)' 처럼 '(' 앞부분이 제목이다.
    expect(
      countTitle(texts, '멘티 (내가 배출한'),
      1,
      reason: '멘티 섹션이 여러 번 노출되면 중복',
    );
    expect(
      countTitle(texts, '멘토 (범을 배출한'),
      1,
      reason: '멘토 섹션이 여러 번 노출되면 중복',
    );
    expect(
      countTitle(texts, '페런츠 (범을 배출한'),
      1,
      reason: '페런츠 섹션이 여러 번 노출되면 중복',
    );

    // 범인가 / ATAS 카드가 분리되어 각각 1회.
    expect(countTitle(texts, '인가 정보 (인가 당시 정보)'), 2);
    expect(countTitle(texts, 'ATAS 인가 정보'), 1);
  });
}
