// [요구 2026-11-04] "멘토 등록하고 이름+전화번호 기입하면 자동으로 회원가입이
//                   되어야 하는데, 오류가 나고 있음" 회귀 방지
//
// ## 실제 사고
//  시트는 "아이디: 01046236587 / 비밀번호: 6587!@@" 를 안내했지만
//  계정은 link_profiles.json 에만 기록되고 members 명단에는 아무 것도 생기지 않았다.
//  로그인 검증(_guest_verify)은 members 중 isRegular 인 사람만 찾으므로
//  **안내한 아이디로 로그인 자체가 불가능**했다. 화면상 "오류"의 정체다.
//
// ## 수정
//  /api/link/profiles 저장 시 비인가자(전화번호 있음)면 members 에
//  일반회원 카드를 만들고 approvalStatus='pending' + 관리자 알림까지 적재한다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const String _proxyPath = '/home/user/nas_proxy/proxy_server.py';

void main() {
  late String src;
  setUpAll(() {
    final f = File(_proxyPath);
    expect(f.existsSync(), isTrue);
    src = f.readAsStringSync();
  });

  group('계정 생성기(_link_profile_ensure_member)', () {
    test('정의가 존재한다', () {
      expect(src.contains('def _link_profile_ensure_member('), isTrue);
    });

    test('members 명단에 isRegular 카드를 만든다', () {
      final i = src.indexOf('def _link_profile_ensure_member(');
      final body = src.substring(i, i + 4200);
      expect(body.contains('"isRegular": True'), isTrue,
          reason: 'isRegular 가 없으면 _guest_verify 가 찾지 못해 로그인 불가');
      expect(body.contains('"accessPhone": ph'), isTrue);
    });

    test('id 규칙은 reg_<전화번호> 다', () {
      expect(src.contains('"id": "reg_" + ph'), isTrue);
    });

    test('승인 대기(pending)로 시작한다', () {
      final i = src.indexOf('def _link_profile_ensure_member(');
      final body = src.substring(i, i + 4200);
      expect(body.contains('"approvalStatus": "pending"'), isTrue);
      expect(body.contains('"approvalAt": now'), isTrue);
    });

    test('같은 전화번호가 이미 있으면 새로 만들지 않는다', () {
      final i = src.indexOf('def _link_profile_ensure_member(');
      final body = src.substring(i, i + 4200);
      expect(body.contains('"existing": True'), isTrue,
          reason: '중복 신원 방지 — 같은 사람이 두 계정을 갖게 하면 안 된다');
    });

    test('로그인 비번 저장소에도 등록한다', () {
      final i = src.indexOf('def _link_profile_ensure_member(');
      final body = src.substring(i, i + 4200);
      expect(body.contains('_ev_save_regular_pw(pws)'), isTrue);
    });
  });

  group('저장 엔드포인트 연결', () {
    test('/api/link/profiles 가 계정 생성기를 호출한다', () {
      expect(src.contains('_created = _link_profile_ensure_member('), isTrue);
    });

    test('응답에 memberCreated 를 싣는다', () {
      expect(src.contains('"memberCreated": bool(_created)'), isTrue);
    });

    test('실패해도 프로필 저장은 막지 않는다(try/except)', () {
      final i = src.indexOf('_created = _link_profile_ensure_member(');
      final before = src.substring(i - 1400, i);
      expect(before.contains('try:'), isTrue);
    });

    test('인가자는 계정을 만들지 않는다', () {
      final i = src.indexOf('_created = _link_profile_ensure_member(');
      final before = src.substring(i - 900, i);
      expect(before.contains('_is_cred'), isTrue,
          reason: 'isScouter/scoutNo 인 사람은 카드+계정이 이미 있다');
    });
  });

  group('로그인 검증과의 정합', () {
    test('_guest_verify 가 isRegular 회원을 찾는다', () {
      final i = src.indexOf('def _guest_verify(');
      final body = src.substring(i, i + 1200);
      expect(body.contains('m.get("isRegular")'), isTrue);
      expect(body.contains('accessPhone'), isTrue);
    });
  });
}
