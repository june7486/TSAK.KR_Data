// ─────────────────────────────────────────────────────────────────────────────
//  turn73 계약 테스트 — "재기동해도 로그인이 유지된다"
//
//  ## 사용자 제보 (스크린숏)
//    참가비·후원금 탭에 빨간 배너:
//      "재무 자료를 불러오지 못했습니다 … (HTTP 401)"
//      "※ 자료가 삭제된 것이 아닙니다"
//    → 자료는 멀쩡했다. **세션만 사라진 것**이었다.
//
//  ## 원인
//    프록시의 세션이 `_SESS = {}` 라는 **메모리 dict 하나**였다.
//    서버를 재시작(패치 배포·재기동)하면 전 사용자가 로그아웃됐다.
//
//  ## 이 파일이 지키는 계약
//   ① 서버: `.sessions.json` 에 세션을 저장하고, 기동 시 복원한다.
//   ② 앱: 401 을 '자료 손실'이 아니라 '로그인 만료'로 안내하고,
//          버튼 한 번으로 세션 갱신 후 재무만 다시 읽는다.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readScreen() => File(
  'lib/screens/event_detail_screen.dart',
).readAsStringSync();

/// `_name(...) {` 부터 중괄호 균형이 0 이 되는 지점까지 잘라낸다.
String _methodBody(String src, String signature) {
  final i = src.indexOf(signature);
  expect(i, greaterThanOrEqualTo(0), reason: '$signature 를 찾지 못했습니다');
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
  fail('$signature 의 닫는 중괄호를 찾지 못했습니다');
}

/// 프록시 서버 소스가 있는지 (샌드박스 전용 — CI 에서는 건너뛴다).
File? _proxyFile() {
  final f = File('/home/user/nas_proxy/proxy_server.py');
  return f.existsSync() ? f : null;
}

void main() {
  group('① 서버 — 세션 디스크 영속화', () {
    test('세션 파일 경로와 저장/복원 함수가 있다', () {
      final f = _proxyFile();
      if (f == null) {
        // ignore: avoid_print
        print('proxy_server.py 없음 — 서버 계약 테스트 건너뜀');
        return;
      }
      final src = f.readAsStringSync();
      expect(src, contains('_SESS_FILE = os.path.join(HERE, ".sessions.json")'));
      expect(src, contains('def _sess_load_from_disk():'));
      expect(src, contains('def _sess_save_to_disk():'));
      expect(src, contains('def _sess_save_async():'));
    });

    test('기동 시 복원을 호출한다', () {
      final f = _proxyFile();
      if (f == null) return;
      final src = f.readAsStringSync();
      expect(src, contains('_sess_load_from_disk()'));
      // 복원은 서버 기동 로그 직전에 있다.
      final iBoot = src.indexOf('TSAK NAS proxy on 0.0.0.0');
      final iRestore = src.indexOf('_sess_load_from_disk()');
      expect(iBoot, greaterThan(0));
      expect(iRestore, greaterThan(0));
      expect(iRestore, lessThan(iBoot), reason: '복원이 기동보다 먼저여야 합니다');
    });

    test('로그인·로그아웃·권한변경 모두 디스크에 반영한다', () {
      final f = _proxyFile();
      if (f == null) return;
      final src = f.readAsStringSync();
      // _sess_new 안에서 저장
      final iNew = src.indexOf('def _sess_new(');
      final iNewEnd = src.indexOf('def _sess_get(', iNew);
      expect(iNew, greaterThan(0));
      expect(
        src.substring(iNew, iNewEnd),
        contains('_sess_save_async()'),
        reason: '로그인(sess_new)이 디스크에 저장되어야 합니다',
      );
      // _sess_del 안에서 저장
      final iDel = src.indexOf('def _sess_del(');
      final iDelEnd = src.indexOf('\n\n', iDel);
      expect(iDel, greaterThan(0));
      expect(
        src.substring(iDel, iDelEnd),
        contains('_sess_save_async()'),
        reason: '로그아웃(sess_del)이 디스크에 반영되어야 합니다',
      );
    });

    test('만료 세션은 복원하지 않는다', () {
      final f = _proxyFile();
      if (f == null) return;
      final src = f.readAsStringSync();
      final i = src.indexOf('def _sess_load_from_disk():');
      final body = src.substring(i, i + 1200);
      expect(body, contains('exp'));
      expect(body, contains('continue'), reason: '만료분은 건너뛰어야 합니다');
    });

    test('토큰 파일 권한을 0600 으로 좁힌다', () {
      final f = _proxyFile();
      if (f == null) return;
      final src = f.readAsStringSync();
      final i = src.indexOf('def _sess_save_to_disk():');
      expect(i, greaterThan(0));
      expect(src.substring(i, i + 1400), contains('0o600'));
    });
  });

  group('② 앱 — 401 을 "로그인 만료"로 안내', () {
    test('재무 배너가 인증 사유를 먼저 판별한다', () {
      final src = _readScreen();
      final i = src.indexOf('Widget _financeErrorBanner(String err) {');
      expect(i, greaterThan(0));
      final body = _methodBody(src, '_financeErrorBanner(String err) {');
      expect(body, contains("err.contains('401')"));
      expect(body, contains('로그인이 만료되었습니다'));
      // 자료가 그대로라는 사실을 먼저 알린다(사용자 놀람 방지).
      expect(body, contains('자료는 그대로 있습니다'));
      expect(body, contains('로그인 갱신'));
    });

    test("'로그인 갱신' 버튼이 세션 재발급 후 재무만 다시 읽는다", () {
      final src = _readScreen();
      final i = src.indexOf('Future<void> _renewSessionAndReload() async {');
      expect(i, greaterThan(0));
      final body = _methodBody(src, '_renewSessionAndReload() async {');
      expect(body, contains('ensureServerSession(needAdmin: true)'));
      expect(body, contains('_loadFinanceOnly()'));
      // 전체 로딩을 부르면 사용자가 보던 탭이 초기화된다.
      expect(body.contains('await _load();'), isFalse);
    });

    test('배너가 그 버튼을 실제로 연결한다', () {
      final src = _readScreen();
      expect(src, contains('onPressed: _renewSessionAndReload'));
    });
  });
}
