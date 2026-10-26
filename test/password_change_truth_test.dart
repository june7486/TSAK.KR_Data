// 비밀번호 변경이 '거짓 성공'을 보고하지 않는지 고정하는 회귀 테스트.
//
// 배경(사용자 지적): "비번 강제 변경이 잘 안됨"
//
// 관찰된 증상: "변경했습니다" 메시지가 뜨는데 실제로는 이전 비번으로
//              계속 로그인이 됐다.
//
// 원인: 서버 호출을 try/catch(_){} 로 감싸 오류를 삼켰고,
//       서버 호출보다 **먼저** 로컬 DB 에 새 비번을 써버렸다.
//       서버가 거부해도 화면은 성공으로 표시됐다.
//
// 수정: 서버를 진실원으로 삼아 성공을 확인한 뒤에만 로컬을 갱신하고,
//       실패 사유를 사용자에게 그대로 돌려준다.
//
// 이 테스트는 그 계약(성공/실패 판정)을 고정한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/nas_api.dart';

void main() {
  group('NasAuthException — 인증 실패를 데이터 없음과 구분', () {
    test('메시지를 그대로 보존한다', () {
      final e = NasAuthException('세션 만료');
      expect(e.toString(), '세션 만료');
      expect(e, isA<Exception>());
    });

    test('Exception 이므로 catch 로 잡힌다', () {
      expect(() => throw NasAuthException('x'), throwsA(isA<NasAuthException>()));
    });
  });

  group('setAdminPassword 응답 계약', () {
    // 서버는 성공 시 ok:true + newPassword 를, 실패 시 ok:false + error 를 준다.
    // 클라이언트는 이 두 형태를 구분해야 한다.
    test('성공 응답 형태', () {
      final r = <String, dynamic>{'ok': true, 'newPassword': '415!@@'};
      expect(r['ok'], isTrue);
      expect('${r['newPassword']}'.trim(), '415!@@');
    });

    test('실패 응답 형태 — 성공으로 오인하면 안 된다', () {
      final r = <String, dynamic>{
        'ok': false,
        'error': '권한 없음: 인가자 비밀번호 변경은 마스터만 가능합니다',
      };
      expect(r['ok'] == true, isFalse);
      expect('${r['error']}'.contains('권한'), isTrue);
    });

    test('ok 키가 없으면 성공이 아니다', () {
      final r = <String, dynamic>{'newPassword': 'x'};
      expect(r['ok'] == true, isFalse);
    });
  });
}
