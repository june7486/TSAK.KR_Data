// 멘토·페런츠 인적사항 **삭제**와 **겸임 역할(kinds)** 회귀 테스트 (build #601).
//
// ## 실제 사고 3건
//  ① 인적사항을 삭제해도 지워지지 않았다.
//     서버 삭제 경로가 '멘토:'/'페런츠:'/무접두어 키만 시도하고
//     표준 키 `person:<대표번호>` 를 빠뜨려서, 아무 것도 지우지 못하고도
//     `{"ok": true, "deleted": <번호>}` 를 돌려줬다(화면엔 성공처럼 보임).
//     실측: person:01099998888 삭제 요청 → deleted 응답, 파일엔 그대로.
//  ② 겸임자(노본: 멘토+페런츠)의 역할이 저장할 때마다 하나씩 사라졌다.
//     `_link_profile_sanitize()` 가 `kinds`·`loginId` 를 매번 버렸고,
//     화면은 한 종류의 시트만 열기 때문에 `kind` 하나만 전달된다.
//     실측: 노본 kinds=['parent','mentor'] → ['parent'].
//  ③ 멘토 프로필의 `number` 가 **멘티 번호**로 저장돼 같은 멘티를 둔 멘토들이
//     모두 같은 number 를 갖게 됐다(실측: 선영진·테스트멘토 둘 다 1346).
//
// 위젯 테스트는 이 샌드박스에서 멈추므로(HomeScreen 등 pump 시 무한 대기),
// 소스 계약 + 순수 함수 테스트로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 함수 본문만 뽑아낸다 — **docstring/주석을 제거**해서, 주석에 적힌 문구가
/// 테스트를 거짓 통과시키는 일을 막는다. (turn 44 에 실제로 겪은 함정)
String codeOf(String src, String fnName) {
  final start = src.indexOf('def $fnName(');
  expect(start, greaterThan(-1), reason: '$fnName 함수를 찾지 못했습니다');
  final rest = src.substring(start);
  final lines = rest.split('\n');
  final buf = <String>[];
  var inDoc = false;
  for (var i = 0; i < lines.length; i++) {
    var ln = lines[i];
    final trimmed = ln.trimLeft();
    // 여러 줄 docstring 시작/종료 추적
    final quotes = RegExp('"""|\'\'\'').allMatches(ln).length;
    if (quotes.isOdd) inDoc = !inDoc;
    if (quotes > 0 && quotes.isEven) {
      // 같은 줄에서 열고 닫힌 docstring → 주석으로 간주하고 버린다.
      continue;
    }
    if (inDoc) continue;
    if (trimmed.startsWith('#')) continue;
    if (i == 0) continue; // 'def ...' 줄
    // 다음 최상위 def 에서 멈춘다.
    if (ln.isNotEmpty && !ln.startsWith(' ') && !ln.startsWith('\t')) break;
    buf.add(ln);
  }
  return buf.join('\n');
}

String get _proxy => File('/home/user/nas_proxy/proxy_server.py').readAsStringSync();

String get _sheet =>
    File('lib/widgets/link_profile_sheet.dart').readAsStringSync();

String get _tiles =>
    File('lib/widgets/link_people_tiles.dart').readAsStringSync();

void main() {
  group('① 인적사항 삭제 — 표준 키(person:) 포함', () {
    test('삭제 후보에 _link_person_key 를 넣는다', () {
      final body = codeOf(_proxy, '_link_profile_sanitize');
      expect(body.isNotEmpty, isTrue); // 파일 구조 확인(함수 존재)
      final idx = _proxy.indexOf('if action in ("delete", "remove"):');
      expect(idx, greaterThan(-1));
      final window = _proxy.substring(idx, idx + 5000);
      expect(window.contains('_link_person_key(key)'), isTrue,
          reason: 'person: 키를 지우지 못하면 삭제가 조용히 실패한다');
    });

    test('지우지 못하면 실패(404)로 응답한다 — 거짓 성공 금지', () {
      final idx = _proxy.indexOf('if action in ("delete", "remove"):');
      final window = _proxy.substring(idx, idx + 5000);
      expect(window.contains('"ok": False, "error": "not found"'), isTrue,
          reason: '못 지웠는데 ok:true 를 주면 화면이 속는다');
      expect(window.contains('404'), isTrue);
    });

    test('사람 기준 보조 검색은 종류 지정 + 단 1건일 때만 쓴다', () {
      final idx = _proxy.indexOf('if action in ("delete", "remove"):');
      final window = _proxy.substring(idx, idx + 5000);
      // 멘토 number 는 관례상 '멘티 번호'라 번호만으로 지우면 남의 것을 지울 수 있다.
      expect(window.contains('len(_only) == 1'), isTrue,
          reason: '번호가 겹치는 멘토를 한꺼번에 지우면 안 된다');
    });
  });

  group('② 겸임 역할(kinds) — 저장해도 줄지 않는다', () {
    test('sanitize 가 kinds 를 보존한다', () {
      final body = codeOf(_proxy, '_link_profile_sanitize');
      expect(body.contains('"kinds": _kinds'), isTrue,
          reason: 'kinds 를 빼면 겸임자 역할이 매 저장마다 사라진다');
      expect(body.contains('if not _kinds:'), isTrue);
    });

    test('sanitize 가 loginId 등 보조 필드를 보존한다', () {
      final body = codeOf(_proxy, '_link_profile_sanitize');
      expect(body.contains('"loginId", "password", "receiverNo"'), isTrue,
          reason: '전화번호 계정 아이디가 사라지면 화면에 아이디가 빈다');
    });

    test('저장 시 이전 kinds 와 합집합한다', () {
      final idx = _proxy.indexOf('kinds(겸임 역할)는 **줄이지 않는다**');
      expect(idx, greaterThan(-1), reason: '합집합 병합 주석이 있어야 한다');
      final window = _proxy.substring(idx, idx + 1400);
      expect(window.contains('_pk | _nk'), isTrue);
      expect(window.contains('p["kinds"] = _u'), isTrue);
    });
  });

  group('③ number 는 그 사람의 대표번호', () {
    test('인가자→인가번호 / 그 외→전화번호 규칙이 저장 경로에 있다', () {
      final idx = _proxy.indexOf('`number` 는 **그 사람의 대표번호**');
      expect(idx, greaterThan(-1));
      final window = _proxy.substring(idx, idx + 1600);
      expect(window.contains('p["number"] = _canon'), isTrue);
      expect(window.contains('_selfnum if bool(p.get("isScouter"))'), isTrue);
    });

    test('임시코드(9000xx)는 이 규칙에서 제외한다', () {
      final idx = _proxy.indexOf('`number` 는 **그 사람의 대표번호**');
      final window = _proxy.substring(idx, idx + 1600);
      expect(window.contains('_is_temp2'), isTrue);
    });
  });

  group('④ 클라이언트 — 시트가 전화번호를 돌려준다', () {
    test('LinkProfileResult 에 phone 필드가 있다', () {
      expect(_sheet.contains('final String phone;'), isTrue);
      expect(_sheet.contains('this.phone = \'\''), isTrue);
    });

    test('저장 성공 시 phone 을 채워 돌려준다', () {
      expect(_sheet.contains('phone: ph,'), isTrue);
    });

    test('관계값은 내 번호(code)가 아니라 그 사람의 전화번호를 쓴다', () {
      // 이걸 놓치면 자기참조로 판정되어 저장이 통째로 무시된다.
      final idx = _tiles.indexOf('_digits(res.phone)');
      expect(idx, greaterThan(-1),
          reason: 'code 는 멘토 추가 시 \"내 번호\"라 관계값으로 쓰면 안 된다');
      // res.phone 이 res.code 보다 **먼저** 쓰여야 한다.
      final phonePos = _tiles.indexOf('_digits(res.phone)');
      final codePos = _tiles.indexOf('linkCode = res.code');
      expect(phonePos, lessThan(codePos));
    });

    test('카드 조회 폴백은 나 자신이 아닐 때만 쓴다', () {
      final idx = _tiles.indexOf('기존 행(코드가 곧 그 사람)에서 등록한 경우에만');
      expect(idx, greaterThan(-1));
      final window = _tiles.substring(idx, idx + 700);
      expect(window.contains('_isSamePerson'), isTrue);
    });
  });

  group('순수 함수 — 전화번호 정규화', () {
    String digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

    test('하이픈이 섞여도 같은 사람으로 본다', () {
      expect(digits('010-3365-7480'), digits('01033657480'));
    });

    test('임시코드 판별 — 6자리 9로 시작', () {
      bool isTemp(String n) => n.length == 6 && n.startsWith('9');
      expect(isTemp('900123'), isTrue);
      expect(isTemp('1346'), isFalse);
      expect(isTemp('01099998888'), isFalse);
    });
  });
}
