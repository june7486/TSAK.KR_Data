// 범스카우트 인가정보 카드의 **인가일 노출** 회귀 테스트.
//
// 요구(2026-11-02, build #574): "범스카우트 인가일을 인가정보에 노출해줘"
//  · 보고 화면: #893 이소라 카드에 범인가번호/소속 연맹/등록 단위대만 보이고
//    '인가일' 항목이 **아예 없었다**.
//  · 원인: `_credentialCard` 가 인가일에 `_plainRow` 를 썼는데, 그 헬퍼는
//      if (value.trim().isEmpty) return const SizedBox.shrink();
//    로 **빈 값이면 행을 통째로 지운다**. 인가일이 공란인 회원(실측 44명)은
//    항목 자체가 사라져 "없는 항목"처럼 보였다.
//  · 수정: `_blankRow(..., placeholder: '미등록')` 로 바꿔 **자리를 지킨다**.
//
// 이 테스트가 지키는 것
//  ① 인가일이 **있으면** 그 값이 그대로 보인다 (예: 1990-03-21)
//  ② 인가일이 **비어도** '인가일' 라벨이 사라지지 않고 '미등록' 이 보인다
//  ③ 서포터즈(비인가 일반회원)는 인가 자체가 없으므로 인가일 행을 만들지 않는다
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/screens/member_detail_screen.dart';
import 'package:tsak_credential_manager/services/app_state.dart';
import 'package:tsak_credential_manager/services/member_repository.dart';
import 'package:tsak_credential_manager/theme/app_theme.dart';

/// '인가일' 라벨과 **같은 Row** 안에 있는 값 텍스트를 모은다.
///
/// 라벨/값은 [_blankRow]·[_plainRow] 모두 `Row(children:[SizedBox(Text label),
/// Expanded(Text value)])` 구조이므로, 라벨 Text 의 부모 Row 의 후손 Text 중
/// 라벨 자신을 뺀 것이 값이다. ('미등록' 같은 문자열은 화면 다른 곳에도 쓰여서
/// 단순 문자열 카운트로는 오탐이 난다 — 그래서 구조로 판별한다.)
List<String> valuesForLabel(WidgetTester tester, String label) {
  final out = <String>[];
  for (final e in find.text(label).evaluate()) {
    final rowEl = _ancestorRow(e);
    if (rowEl == null) continue;
    for (final t in find
        .descendant(of: find.byWidget(rowEl.widget), matching: find.byType(Text))
        .evaluate()) {
      final w = t.widget as Text;
      final s = w.data ?? '';
      if (s == label) continue;
      if (s.trim().isEmpty) continue;
      out.add(s);
    }
  }
  return out;
}

Element? _ancestorRow(Element e) {
  Element? found;
  e.visitAncestorElements((a) {
    if (a.widget is Row) {
      found = a;
      return false; // 가장 가까운 Row 에서 멈춘다
    }
    return true;
  });
  return found;
}

Future<void> _pump(WidgetTester tester, Member m) async {
  tester.view.physicalSize = const Size(900, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
        home: MemberDetailScreen(memberId: m.id),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('인가일이 있으면 인가정보 카드에 그대로 노출된다', (tester) async {
    final m = Member(
      id: 'm_date',
      number: '415',
      name: '이승준',
      league: '인천',
      unit: '제1234단 인천연맹 직할대',
      date: '1990-03-21',
    );

    await _pump(tester, m);

    expect(find.text('인가일'), findsWidgets,
        reason: '인가정보 카드에 인가일 라벨이 있어야 한다');
    expect(valuesForLabel(tester, '인가일'), contains('1990-03-21'),
        reason: '입력된 인가일이 그대로 보여야 한다');

    // 카드 자체가 사라지지 않았는지(제목 존재) 확인 — 회귀 방어.
    expect(find.textContaining('인가 정보 (인가 당시 정보)'), findsWidgets);
  });

  testWidgets('인가일이 비어 있어도 행이 사라지지 않고 미등록으로 남는다', (tester) async {
    // 실측 재현: #893 이소라 — 연맹·단위대는 있는데 date 만 공란.
    final m = Member(
      id: 'm_893',
      number: '893',
      name: '이소라',
      league: '경남',
      unit: '제4004대 김해푸르미지역대',
      date: '',
    );

    await _pump(tester, m);

    // ① 라벨이 존재해야 한다(수정 전에는 _plainRow 의 조기 return 으로 사라졌다).
    expect(find.text('인가일'), findsWidgets,
        reason: '인가일이 비어도 라벨은 남아 "항목이 없다"와 구별되어야 한다');
    // ② 값 자리에는 미등록이 표시된다.
    expect(valuesForLabel(tester, '인가일'), contains('미등록'),
        reason: '빈 인가일은 미등록으로 안내해야 한다');
    // ③ 다른 근거 항목은 그대로 보인다.
    expect(valuesForLabel(tester, '소속 연맹'), contains('경남'));
    expect(valuesForLabel(tester, '등록 단위대'),
        contains('제4004대 김해푸르미지역대'));
  });

  testWidgets('서포터즈(비인가 일반회원)는 인가일 행을 만들지 않는다', (tester) async {
    final m = Member(
      id: 'm_sup',
      number: 'S1',
      name: '서포터',
      isRegular: true,
      league: '',
      unit: '',
      date: '',
      phone: '010-1111-2222',
    );

    await _pump(tester, m);

    expect(find.text('인가일'), findsNothing,
        reason: '인가 자체가 없는 회원에게 인가일 항목을 띄우면 오해를 준다');
  });
}
