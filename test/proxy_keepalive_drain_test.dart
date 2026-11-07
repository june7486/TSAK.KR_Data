// ── [버그 수정 turn77] keep-alive 연결 오염(501) 계약 테스트 ─────────────
//
//  ## 실제 증상
//   브라우저에서 로그인 도중 **한 번** 이런 응답을 만났다.
//     HTTP/1.1 501 Unsupported method ('{}GET')
//   메서드 자리에 '{}' 가 들어갔다. 즉 **요청줄이 깨진 것**이다.
//
//  ## 원인 (재현 성공)
//   `_json()` 은 인증 실패(401) 등에서 **요청 바디를 읽지 않고** 응답한다.
//   그런데 클라이언트는 이미 Content-Length 만큼 바디를 보냈다.
//   HTTP/1.1 은 keep-alive 가 기본이라 **같은 소켓으로 다음 요청**이 온다.
//   → 읽히지 않은 바디가 버퍼에 남아 다음 요청줄 앞에 붙는다.
//        '{"x":"AAAA…}GET /api/health …'
//   BaseHTTPRequestHandler 는 이 한 줄을 메서드명으로 해석해 501 을 준다.
//   (바디가 짧으면 '{}GET' 처럼 보인다)
//
//  ## 왜 지금까지 안 터졌나
//   정상 POST 는 인증을 통과해 `_body()` 로 바디를 읽었다.
//   **세션이 만료된 상태에서 저장 요청**을 보낼 때만 남았다.
//   → "로그인이 만료되었습니다" 배너가 뜨는 바로 그 순간과 겹친다.
//
//  ## 수정
//   `handle_one_request` 에서 응답 후 남은 바디를 **반드시 소진**하고,
//   소진할 수 없으면(chunked/끊김) **연결을 닫는다**.
//   연결을 닫으면 다음 요청은 새 소켓으로 와서 오염이 전파되지 않는다.
//
//  ⚠️ 이 테스트는 **프록시 소스 계약**만 검사한다(서버를 띄우지 않는다).
//     실제 소켓 레벨 재현은 /tmp/verify501.py 로 별도 확인했다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _proxySource() {
  for (final p in <String>[
    '/home/user/nas_proxy/proxy_server.py',
    '/home/user/gabia_deploy/api/proxy_server.py',
  ]) {
    final f = File(p);
    if (f.existsSync()) return f.readAsStringSync();
  }
  return '';
}

/// 메서드 본문을 중괄호 균형으로 잘라낸다.
String _methodBody(String src, String signature) {
  final i = src.indexOf(signature);
  if (i < 0) return '';
  final start = src.indexOf('\n', i);
  if (start < 0) return '';
  var depth = 0;
  var seen = false;
  for (var j = start; j < src.length; j++) {
    final c = src[j];
    if (c == '{') {
      depth++;
      seen = true;
    } else if (c == '}') {
      depth--;
      if (seen && depth == 0) return src.substring(start, j + 1);
    }
  }
  return '';
}

void main() {
  group('proxy_server.py — keep-alive 바디 소진', () {
    late String src;

    setUpAll(() {
      src = _proxySource();
    });

    test('프록시 소스를 찾을 수 있다', () {
      expect(src.isNotEmpty, isTrue,
          reason: 'proxy_server.py 를 찾지 못했습니다.');
    });

    test('_rfile_read 헬퍼가 읽은 바이트를 누적한다', () {
      final body = _methodBody(src, '    def _rfile_read(self, n):');
      expect(body.isNotEmpty, isTrue, reason: '_rfile_read 가 없습니다.');
      expect(body.contains('self.rfile.read(n)'), isTrue);
      expect(
        body.contains('_body_read_n'),
        isTrue,
        reason: '읽은 바이트를 누적하지 않으면 남은 양을 계산할 수 없습니다.',
      );
    });

    test('_drain_body 가 Content-Length 기준으로 남은 바디를 읽는다', () {
      final body = _methodBody(src, '    def _drain_body(self):');
      expect(body.isNotEmpty, isTrue, reason: '_drain_body 가 없습니다.');
      expect(body.contains('Content-Length'), isTrue);
      expect(body.contains('_body_read_n'), isTrue,
          reason: '이미 읽은 양을 빼야 정확히 소진됩니다.');
      expect(
        body.contains('min(65536, left)'),
        isTrue,
        reason: '큰 바디를 한 번에 읽으면 메모리를 크게 씁니다.',
      );
    });

    test('chunked 전송은 연결을 닫는다(길이를 알 수 없음)', () {
      final body = _methodBody(src, '    def _drain_body(self):');
      expect(body.contains('chunked'), isTrue);
      expect(
        body.contains('return False'),
        isTrue,
        reason: 'chunked 는 소진 실패로 처리해 연결을 닫아야 합니다.',
      );
    });

    test('handle_one_request 가 응답 후 _drain_body 를 호출한다', () {
      final body = _methodBody(src, '    def handle_one_request(self):');
      expect(body.isNotEmpty, isTrue);
      expect(body.contains('super().handle_one_request()'), isTrue);
      expect(
        body.contains('_drain_body()'),
        isTrue,
        reason: '응답 후 바디를 소진하지 않으면 다음 요청이 오염됩니다(501).',
      );
      expect(
        body.contains('close_connection = True'),
        isTrue,
        reason: '소진 실패 시 연결을 닫아야 오염이 전파되지 않습니다.',
      );
    });

    test('handle_one_request 가 매 요청 카운터를 초기화한다', () {
      final body = _methodBody(src, '    def handle_one_request(self):');
      expect(
        body.contains('self._body_read_n = 0'),
        isTrue,
        reason: '카운터를 초기화하지 않으면 두 번째 요청부터 계산이 틀어집니다.',
      );
    });

    test('_body() 가 카운팅 헬퍼를 쓴다', () {
      final body = _methodBody(src, '    def _body(self):');
      expect(body.isNotEmpty, isTrue);
      expect(
        body.contains('self._rfile_read('),
        isTrue,
        reason: '직접 rfile.read 를 쓰면 읽은 양이 집계되지 않습니다.',
      );
    });

    test('남은 raw rfile.read 는 헬퍼 내부와 drain 내부뿐이다', () {
      final raw = 'self.rfile.read'.allMatches(src).length;
      // 헬퍼 정의 1 + _drain_body 내부 1 = 2
      expect(raw, 2,
          reason: 'raw rfile.read 가 $raw 곳입니다. '
              '새 코드가 카운팅을 우회하면 501 이 재발합니다.');
    });
  });
}
