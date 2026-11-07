// ── [버그 수정 turn76] 서비스워커 영구 비활성 계약 테스트 ──────────────────
//
//  ## 왜 이 테스트가 필요한가
//   사용자 제보: "명부 상세 내역 표시가 안되고 있음"
//   데이터는 실시간으로 최신(요약줄 7건 1,600,009원)인데 **목록 UI만 옛것**
//   이었다. 서버의 main.dart.js 에는 새 문구가 들어 있는 것을 확인했으므로
//   (NEW `True` / OLD `False`) 범인은 **브라우저가 물고 있는 낡은 JS**.
//
//  1) Flutter 는 flutter_bootstrap.js 안에서
//     `navigator.serviceWorker.register(...)` 로 워커를 등록한다.
//  2) index.html 의 해제 코드는 `localStorage['tsak_sw_off']` 플래그 때문에
//     **딱 한 번만** 실행됐다.
//  3) 그런데 바로 그 페이지 로드에서 bootstrap 이 워커를 **다시 등록**한다.
//     → 두 번째 방문부터 해제도 안 하고, 워커가 캐시의 옛 main.dart.js 를
//       계속 내려준다. 아무리 새로 빌드해도 화면 일부가 그대로.
//
//  ## 수정
//   · bootstrap 보다 **먼저** 실행되는 인라인 스크립트에서
//     `navigator.serviceWorker.register` 를 거부하는 스텁으로 덮어쓴다.
//   · 해제 코드는 매 방문 실행 + 워커 캐시까지 삭제.
//   · 빌드도 `--pwa-strategy none` 으로 워커 파일을 비운다(0 바이트).
//
//  ⚠️ 이 파일은 **소스 계약**만 검사한다(위젯을 pump 하지 않는다).
//     index.html 은 브라우저 문서라 위젯 테스트로 검증할 수 없다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String rel) {
  final f = File(rel);
  expect(f.existsSync(), isTrue, reason: '파일이 없습니다: $rel');
  return f.readAsStringSync();
}

void main() {
  group('web/index.html — 서비스워커 영구 비활성', () {
    late String html;

    setUpAll(() {
      html = _read('web/index.html');
    });

    test('register 를 거부 스텁으로 덮어쓴다', () {
      expect(
        html.contains('navigator.serviceWorker.register = function'),
        isTrue,
        reason: 'register 오버라이드가 사라졌습니다. '
            'flutter_bootstrap.js 가 워커를 다시 등록해 옛 JS 를 서빙합니다.',
      );
    });

    test('오버라이드가 bootstrap 태그보다 위에 있다', () {
      final overrideAt = html.indexOf('serviceWorker.register = function');
      final bootstrapAt = html.indexOf('<script src="flutter_bootstrap.js"');
      expect(overrideAt, greaterThanOrEqualTo(0));
      expect(bootstrapAt, greaterThanOrEqualTo(0));
      expect(
        overrideAt < bootstrapAt,
        isTrue,
        reason: '오버라이드는 bootstrap 보다 먼저 실행되어야 합니다 '
            '(async 스크립트가 먼저 돌면 소용없음).',
      );
    });

    test('localStorage 1회성 게이트가 코드에 남아 있지 않다', () {
      // 주석에는 역사 설명으로 남아 있을 수 있으므로 **코드 형태**만 본다.
      expect(
        html.contains("getItem('tsak_sw_off')"),
        isFalse,
        reason: '한 번만 해제하는 게이트가 되살아나면 '
            '두 번째 방문부터 옛 JS 가 다시 서빙됩니다.',
      );
      expect(html.contains("setItem('tsak_sw_off'"), isFalse);
    });

    test('매 방문 해제 + 워커 캐시 삭제', () {
      expect(html.contains('getRegistrations()'), isTrue);
      expect(html.contains('unregister()'), isTrue);
      expect(
        html.contains('caches.delete(k)'),
        isTrue,
        reason: '워커를 해제해도 Cache Storage 가 남으면 '
            '옛 main.dart.js 가 그대로 살아 있습니다.',
      );
    });

    test('register 스텁은 Promise.reject 를 돌려준다', () {
      // Flutter 쪽 코드가 `.then(...)` 체인을 걸기 때문에
      // 던지지 않고 reject 하는 편이 안전하다(부트스트랩이 죽지 않음).
      expect(html.contains('Promise.reject'), isTrue);
    });
  });

  group('빌드 산출물 — 워커가 되살아나지 않았는지', () {
    test('flutter_service_worker.js 는 0 바이트(또는 없음)', () {
      final f = File('build/web/flutter_service_worker.js');
      if (!f.existsSync()) {
        // --pwa-strategy none 이 파일을 아예 만들지 않는 경우도 정상.
        return;
      }
      expect(
        f.lengthSync(),
        0,
        reason: '워커 파일이 비어 있지 않습니다. '
            '--pwa-strategy none 없이 빌드했는지 확인하세요.',
      );
    });

    test('빌드된 index.html 에도 오버라이드가 살아 있다', () {
      final f = File('build/web/index.html');
      if (!f.existsSync()) return; // 빌드 전에는 건너뛴다.
      expect(
        f.readAsStringSync().contains('serviceWorker.register = function'),
        isTrue,
        reason: 'web/index.html 을 고쳤는데 빌드 산출물에 반영되지 않았습니다. '
            '재빌드가 필요합니다.',
      );
    });
  });
}
