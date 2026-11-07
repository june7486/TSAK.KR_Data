// ─────────────────────────────────────────────────────────────────────────────
//  turn73 계약 테스트 — "참가자 저장 후 가벼운 재조회"
//
//  ## 배경 (사용자 보고: "참가지 및 후원금 등록하면 느리고 버그남")
//   참가자 저장 3곳이 모두 `_load()` 를 불렀다. 그 함수는 5개 API 를 다시
//   받고 **전체 화면 스피너**를 켰다. 그래서 참가자 1명 추가에도 화면이
//   몇 초씩 하얗게 되고, 탭·스크롤이 흔들렸다.
//
//  ## 이 파일이 지키는 계약
//   ① `_loadAttendeesOnly()` 가 존재하고, `/api/event/get` **한 개만** 쓴다.
//   ② 그 안에서 `_loading` 을 켜지 않는다(전체 스피너 금지).
//   ③ 저장 3곳이 `_load()` 대신 `_loadAttendeesOnly()` 를 부른다.
//   ④ `_loadSeq` 토큰으로 낡은 응답을 버린다.
//
//  ## 왜 위젯 테스트가 아니라 소스 계약 테스트인가
//   이 샌드박스에서는 EventDetailScreen 을 pump 하는 위젯 테스트가
//   **완료되지 않는다**(무한 대기). 그래서 소스 계약으로 검증한다.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readScreen() => File(
  'lib/screens/event_detail_screen.dart',
).readAsStringSync();

/// `_loadAttendeesOnly()` 본문만 잘라낸다.
String _lightReloadBody(String src) {
  const start = 'Future<void> _loadAttendeesOnly() async {';
  final i = src.indexOf(start);
  expect(i, greaterThan(0), reason: '_loadAttendeesOnly() 가 없습니다');
  // 메서드 종료: 다음 '  }\n\n' 이 아니라, 중괄호 균형으로 찾는다.
  var depth = 0;
  var began = false;
  for (var k = i; k < src.length; k++) {
    final c = src[k];
    if (c == '{') {
      depth++;
      began = true;
    } else if (c == '}') {
      depth--;
      if (began && depth == 0) return src.substring(i, k + 1);
    }
  }
  fail('_loadAttendeesOnly() 본문을 닫는 중괄호를 찾지 못했습니다');
}

void main() {
  group('① _loadAttendeesOnly() 존재와 단일 API 사용', () {
    test('메서드가 정의되어 있다', () {
      expect(_readScreen(), contains('Future<void> _loadAttendeesOnly() async {'));
    });

    test('/api/event/get 만 쓴다 (eventGet 1~2회, 나머지 API 없음)', () {
      final body = _lightReloadBody(_readScreen());
      final gets = 'eventGet('.allMatches(body).length;
      expect(gets, greaterThanOrEqualTo(1), reason: 'eventGet 호출이 없습니다');
      expect(gets, lessThanOrEqualTo(2), reason: '재시도 1회까지만 허용');
      // 다른 API 는 절대 부르면 안 된다 — 이게 속도의 핵심.
      for (final bad in const [
        'eventFiles(',
        'eventFinance(',
        'eventAccessMap(',
        "'plan'",
      ]) {
        expect(
          body.contains(bad),
          isFalse,
          reason: '가벼운 재조회가 $bad 를 부르면 안 됩니다',
        );
      }
    });

    test('12초 타임아웃을 건다 (무한 대기 금지)', () {
      final body = _lightReloadBody(_readScreen());
      expect(body, contains('const Duration(seconds: 12)'));
      expect(body, contains('.timeout('));
    });
  });

  group('② 전체 스피너를 켜지 않는다', () {
    test('_loading = true 가 없다', () {
      final body = _lightReloadBody(_readScreen());
      expect(body.contains('_loading = true'), isFalse);
      expect(body.contains('_loading = false'), isFalse);
    });

    test('진행 토큰(_loadSeq)으로 낡은 응답을 버린다', () {
      final body = _lightReloadBody(_readScreen());
      expect(body, contains('++_loadSeq'));
      expect(body, contains('bool isStale() => mySeq != _loadSeq;'));
      expect(body, contains('if (isStale() || !mounted) return;'));
    });

    test('실패는 화면을 덮지 않고 스낵바로만 알린다', () {
      final body = _lightReloadBody(_readScreen());
      expect(body, contains('_snack('));
      // 저장은 이미 성공했으므로 사용자를 놀라게 하는 실패 문구는 금지.
      expect(body.contains('불러오기 실패'), isFalse);
    });
  });

  group('③ 참가자 저장 3곳이 가벼운 재조회를 쓴다', () {
    test('_saveAttendees 는 _loadAttendeesOnly 를 쓴다', () {
      final src = _readScreen();
      final i = src.indexOf('Future<void> _saveAttendees() async {');
      expect(i, greaterThan(0));
      final body = src.substring(i, i + 420);
      expect(body, contains('_loadAttendeesOnly()'));
      expect(body.contains('await _load();'), isFalse);
    });

    test('_saveAttendeesLinked 는 _loadAttendeesOnly 를 쓴다', () {
      final src = _readScreen();
      final i = src.indexOf('Future<Map<String, dynamic>> _saveAttendeesLinked()');
      expect(i, greaterThan(0));
      final body = src.substring(i, i + 620);
      expect(body, contains('_loadAttendeesOnly()'));
      expect(body.contains('await _load();'), isFalse);
    });

    test('참가자 일괄 추가(eventAttendeesAdd) 뒤에도 가벼운 재조회', () {
      final src = _readScreen();
      final i = src.indexOf('eventAttendeesAdd(');
      expect(i, greaterThan(0));
      final body = src.substring(i, i + 1400);
      expect(body, contains('_loadAttendeesOnly()'));
      expect(body.contains('await _load();'), isFalse);
    });
  });

  group('④ 기존 재조회 경로는 그대로 유지 (회귀 방지)', () {
    test('_loadFinanceOnly 는 여전히 존재하고 전체 스피너를 켜지 않는다', () {
      final src = _readScreen();
      final i = src.indexOf('Future<void> _loadFinanceOnly() async {');
      expect(i, greaterThan(0));
      final body = src.substring(i, i + 1400);
      expect(body.contains('_loading = true'), isFalse);
    });

    test('전체 _load() 는 그대로 남아 있다 (최초 진입·새로고침용)', () {
      expect(_readScreen(), contains('Future<void> _load({bool fresh = false}) async {'));
    });
  });
}
