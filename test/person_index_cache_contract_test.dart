// turn78 — 인물 색인 캐시 회귀 테스트 (소스 계약 검사)
//
// ## 배경 (실측)
//   행사·관리자 화면 로딩이 5~18초 걸렸다.
//     /api/health              139 B   3.98 / 6.92 / 7.42 초
//     /api/meta                145 B   4.28 / 5.04 / 6.72 초
//     /api/approval/pending     39 B   4.73 / 6.57 / 6.93 초
//     /api/members           7.6 MB    11 ~ 22 초
//     스레드 168개 · CPU 102%(1코어 포화) · RSS 1.1 GB
//
// ## 원인
//   `_link_pending_members()` 가 **회원 한 명마다** `_link_person_index()`
//   를 호출했다 → O(n²). 2,244명이면 색인을 수천 번 재생성.
//
// ## 수정
//   (1) 인물 색인 메모화 — 캐시 키에 객체 id + 길이 + JSON 세대번호를 넣어
//       저장/갱신을 100% 감지한다.
//   (2) `_json_refresh_bg` 의 무제한 스레드 → 고정 2-worker 풀.
//
// ## 이 테스트가 지키는 것
//   위 두 수정이 **되돌려지면** 실패한다. 특히 아래 항목은 실제로 사고를
//   냈거나 낼 수 있는 지점이라 반드시 남긴다:
//     · `_save_json` 이 무효화하는가 (제자리 수정 후 같은 객체를 저장하는
//       호출부가 있어 id 만으로는 감지되지 않는다)
//     · `_link_reconcile_apply` 가 무효화하는가 (save:false 경로가 있다)
//     · 캐시 키에 세대번호가 들어 있는가
//
// 검증 대상: /home/user/nas_proxy/proxy_server.py (없으면 gabia 미러)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _proxySource() {
  const cands = [
    '/home/user/nas_proxy/proxy_server.py',
    '/home/user/gabia_deploy/api/proxy_server.py',
  ];
  for (final p in cands) {
    final f = File(p);
    if (f.existsSync()) return f.readAsStringSync();
  }
  fail('proxy_server.py 를 찾지 못했습니다: $cands');
}

/// [signature] 로 시작하는 함수 본문을 잘라낸다.
///
/// ⚠️ Python 에는 중괄호 본문이 없다. 소스에는 dict 리터럴(`{...}`)과
///    독스트링 예시(`{canon, name, ...}`)가 흔하므로 중괄호로 자르면
///    엉뚱한 조각이 나온다(실제로 이 실수를 했다).
///    → **줄 단위**로 잘라서, 시그니처 줄부터 다음 최상위 `def`/`class`/
///      모듈 구분선 전까지를 본문으로 본다.
String _funcBody(String src, String signature) {
  final lines = src.split('\n');
  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith(signature)) {
      start = i;
      break;
    }
  }
  expect(start, greaterThanOrEqualTo(0), reason: '함수를 찾지 못함: $signature');

  final buf = <String>[lines[start]];
  for (var i = start + 1; i < lines.length; i++) {
    final l = lines[i];
    // 최상위(들여쓰기 없음) 선언 또는 모듈 구분선에서 끝난다.
    final isTopLevel = l.isNotEmpty &&
        !l.startsWith(' ') &&
        !l.startsWith('\t') &&
        !l.startsWith(')') &&
        !l.startsWith(']') &&
        !l.startsWith('}') &&
        !l.startsWith('#');
    if (isTopLevel &&
        (l.startsWith('def ') ||
            l.startsWith('class ') ||
            l.startsWith('@') ||
            l.startsWith('_') ||
            l.startsWith('if ') ||
            l.startsWith('try:') ||
            l.startsWith('else') ||
            l.startsWith('for ') ||
            l.startsWith('while '))) {
      break;
    }
    buf.add(l);
  }
  return buf.join('\n');
}

void main() {
  group('turn78 · 인물 색인 캐시', () {
    late String src;

    setUpAll(() {
      src = _proxySource();
    });

    test('캐시 저장소 3종이 정의되어 있다', () {
      expect(src.contains('_LPI_CACHE'), isTrue);
      expect(src.contains('_LPI_INFLIGHT'), isTrue);
      expect(src.contains('_LPI_LOCK'), isTrue);
    });

    test('_link_person_index 는 색인을 매번 새로 만들지 않는다', () {
      final body = _funcBody(src, 'def _link_person_index():');
      // 캐시 조회를 먼저 하고
      expect(body.contains('_lpi_peek'), isTrue,
          reason: '캐시 조회(_lpi_peek)가 없으면 O(n²) 로 되돌아간다');
      // 실체는 별도 함수에 위임해야 한다
      expect(body.contains('_link_person_index_uncached'), isTrue);
      // 캐시에 저장해야 한다
      expect(body.contains('_LPI_CACHE["key"]'), isTrue);
      expect(body.contains('_LPI_CACHE["idx"]'), isTrue);
    });

    test('캐시 키에 객체 id 와 세대번호가 모두 들어 있다', () {
      final body = _funcBody(src, 'def _link_person_index():');
      // 제자리 수정 후 같은 객체를 저장하는 경우를 잡으려면 세대번호가 필수다.
      expect(body.contains('_json_gen_get'), isTrue,
          reason: '세대번호가 키에 없으면 저장 후에도 낡은 색인을 쓴다');
      expect(body.contains('id(members)'), isTrue);
      expect(body.contains('id(profs)'), isTrue);
    });

    test('_save_json 이 색인 캐시를 무효화한다', () {
      final body = _funcBody(src, 'def _save_json(path, obj, force=False):');
      expect(body.contains('_lpi_invalidate'), isTrue,
          reason: '저장해도 색인이 갱신되지 않으면 승인 큐가 낡은 값을 보여준다');
    });

    test('_invalidate_json 이 색인 캐시를 무효화한다', () {
      final body = _funcBody(src, 'def _invalidate_json(path):');
      expect(body.contains('_lpi_invalidate'), isTrue);
    });

    test('_link_reconcile_apply 는 save:false 여도 무효화한다', () {
      final body = _funcBody(src, 'def _link_reconcile_apply(members, *, save=True):');
      // 이 함수는 members 를 제자리에서 고치므로 id 도 세대번호도 그대로다.
      expect(body.contains('_lpi_invalidate'), isTrue,
          reason: 'reconcile 후 무효화가 없으면 낡은 색인이 남는다');
    });

    test('색인 실체는 입력을 복사해 보관하지 않는다(읽기 전용 계약)', () {
      final body =
          _funcBody(src, 'def _link_person_index_uncached(members, profs):');
      // 실체는 순수해야 한다 — 인자를 수정하면 캐시가 오염된다.
      expect(body.contains('members.append('), isFalse);
      expect(body.contains('members.sort('), isFalse);
      expect(body.contains('members.remove('), isFalse);
      expect(body.contains('profs.pop('), isFalse);
    });
  });

  group('turn78 · 백그라운드 갱신 스레드 상한', () {
    late String src;

    setUpAll(() {
      src = _proxySource();
    });

    test('_json_refresh_bg 는 스레드를 무제한 생성하지 않는다', () {
      final body = _funcBody(src, 'def _json_refresh_bg(path):');
      expect(body.contains('threading.Thread('), isFalse,
          reason: '갱신 1회당 스레드를 만들면 스레드가 168개까지 늘어난다');
      expect(body.contains('_JSON_REFRESH_POOL'), isTrue);
    });

    test('갱신 풀은 고정 크기(2)로 정의되어 있다', () {
      expect(src.contains('_JSON_REFRESH_POOL = ThreadPoolExecutor('), isTrue);
      final i = src.indexOf('_JSON_REFRESH_POOL = ThreadPoolExecutor(');
      final seg = src.substring(i, i + 260);
      expect(seg.contains('max_workers=2'), isTrue,
          reason: '작업자 수를 늘리면 다시 GIL 경합이 생긴다');
    });

    test('중복 갱신 방지 장치는 그대로 유지된다', () {
      final body = _funcBody(src, 'def _json_refresh_bg(path):');
      expect(body.contains('_JSON_REFRESHING'), isTrue);
      expect(body.contains('discard(path)'), isTrue);
    });
  });
}
