// _applyQuery **행동** 계약 테스트 (build #579)
//
// 요구(원문 2026-11-02):
//   "검색기능: 범스카우 번호, 예를들면 범415 로 검색해도 검색결과가 안나옴,
//    은하19호 같이 검색해도 은하스카우트가 안 나옴
//    / 자연어 검색을 기본기능으로 하려고 했었는데, 이 부분 업데이트 또는 수정
//      부탁해요."
//
// search_notation_test.dart 는 파서(SearchQuery/AiQuery)와 소스 계약을 본다.
// 이 파일은 그 위에서 **실제 필터 결과**를 검증한다.
//
// ## 위젯 테스트를 쓰지 않은 이유
//   이 샌드박스에서는 MemberDetailScreen 을 pump 하는 테스트가 **완결되지
//   않는다**(기존 member_detail_no_duplicate_test.dart 도 동일하게 멈춘다).
//   그래서 화면을 띄우지 않고 AppState 의 **필터 결과**를 직접 본다.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/app_state.dart';
import 'package:tsak_credential_manager/services/member_repository.dart';

Member mk(
  String id,
  String number,
  String name, {
  String corps = 'tsak',
  bool isRegular = false,
}) => Member(
  id: id,
  number: number,
  name: name,
  corps: corps,
  isRegular: isRegular,
);

void main() {
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final repo = MemberRepository.memory();
    await repo.saveLocalOnlyAll([
      // 범 19호 · 범 415호 — '415' 와 '19' 를 **범**에서 찾을 대상
      mk('t19', '19', '황용규'),
      mk('t415', '415', '이승준'),
      // 은하 19호 — 번호는 같지만 **다른 사람**
      mk('e19', 'G19', '은하대원', corps: 'eunha'),
      // 일반회원(인가번호 없음)
      mk('reg', '01099998888', '서포터', isRegular: true),
    ]);
    state = AppState(repo);
  });

  List<String> names(String q) {
    state.setQuery(q);
    return state.members.map((m) => m.name).toList();
  }

  test('범415 → 범 415호 1명', () {
    expect(names('범415'), ['이승준']);
  });

  test('범 415 (공백) → 범 415호 1명', () {
    expect(names('범 415'), ['이승준']);
  });

  test('범415호 → 범 415호 1명', () {
    expect(names('범415호'), ['이승준']);
  });

  test('은하19호 → **은하** 19호 (범 19호가 아니다)', () {
    final r = names('은하19호');
    expect(r, ['은하대원']);
    expect(r.contains('황용규'), isFalse);
  });

  test('은하19 / G19 / g-19 모두 같은 결과', () {
    for (final q in ['은하19', 'G19', 'g-19', '갤럭시19']) {
      expect(names(q), ['은하대원'], reason: q);
    }
  });

  test('범19 → 은하가 아닌 19호', () {
    final r = names('범19');
    expect(r, ['황용규']);
    expect(r.contains('은하대원'), isFalse);
  });

  test("'은하' 단독 → 은하 인원 전체", () {
    final r = names('은하');
    expect(r, contains('은하대원'));
    expect(r.contains('황용규'), isFalse);
    expect(r.contains('이승준'), isFalse);
  });

  test('맨숫자 415 → 기존 통합검색 그대로 동작(회귀 방지)', () {
    expect(names('415'), contains('이승준'));
  });

  test('이름 검색은 그대로 동작', () {
    expect(names('황용규'), ['황용규']);
    expect(names('이승'), contains('이승준'));
  });

  test('없는 번호를 지목하면 빈 결과(다른 사람으로 새지 않음)', () {
    expect(names('범9999'), isEmpty);
    expect(names('은하9999'), isEmpty);
  });

  test('소속 + 이름 좁히기 — 은하 이승 → 은하에 이승 없음', () {
    expect(names('은하 이승'), isEmpty);
  });

  test('범위 검색은 그대로 동작 + 은하도 포함(numberInt 정규화)', () {
    final r = names('10-20');
    expect(r, contains('황용규')); // 범 19
    expect(r, contains('은하대원')); // 은하 G19 → 19
    expect(r.contains('이승준'), isFalse); // 415
  });

  tearDown(() {
    state.dispose();
  });
}
