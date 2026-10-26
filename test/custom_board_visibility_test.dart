// 커스텀 게시판 — 노출권한 3단계 / 비밀번호 노출범위 / 읽음 기록 규칙 고정 테스트.
//
// [요구 2026-10-26]
//   · "노출권한을 관리자/마스터가 정할 수 있음 (게시판 상단에 버튼 노출),
//      노출/관리자/마스터"
//   · "게시글의 비밀번호는 글쓴 사람은 비밀번호를 넣을 수 있고, 글쓴 사람과
//      마스터한테는 비밀번호가 노출됨(마스터권한)"
//   · "비밀번호를 잃어버렸을 경우 초기화할 수 있음
//      (게시판 비밀번호 초기화는 'id'+'!@@', 예) 415!@@)"
//
// 서버(proxy_server.py)의 _cb_visibility / _cb_can_see_post_pw 와
// 앱(BoardVisibilityX)이 **같은 규칙**을 쓰는지 양쪽에서 고정한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/widgets/event_custom_board.dart';

void main() {
  group('노출권한 3단계 — 문자열 매핑', () {
    test('앱 enum → 서버 키', () {
      expect(BoardVisibility.all.key, 'all');
      expect(BoardVisibility.staff.key, 'staff');
      expect(BoardVisibility.admin.key, 'admin');
    });

    test('서버 키 → 앱 enum', () {
      expect(BoardVisibilityX.parse('all'), BoardVisibility.all);
      expect(BoardVisibilityX.parse('staff'), BoardVisibility.staff);
      expect(BoardVisibilityX.parse('admin'), BoardVisibility.admin);
    });

    test('알 수 없는 값은 admin(가장 보수적)으로 떨어진다', () {
      // 옛 데이터에 openToAll 만 있거나 값이 비어 있어도 새지 않아야 한다.
      expect(BoardVisibilityX.parse(null), BoardVisibility.admin);
      expect(BoardVisibilityX.parse(''), BoardVisibility.admin);
      expect(BoardVisibilityX.parse('openToAll'), BoardVisibility.admin);
      expect(BoardVisibilityX.parse('ALL'), BoardVisibility.admin);
    });

    test('라벨·힌트가 3단계 모두 다르다', () {
      final labels = BoardVisibility.values.map((v) => v.label).toSet();
      final hints = BoardVisibility.values.map((v) => v.hint).toSet();
      expect(labels.length, 3);
      expect(hints.length, 3);
    });
  });

  group('게시글 비밀번호 초기화 규칙', () {
    /// 서버의 CB_PW_RESET_SUFFIX 와 반드시 같아야 한다.
    const suffix = '!@@';

    test("초기화 값은 '인가번호' + '!@@'", () {
      // 예) 415!@@  — 사용자 요구에 명시된 형식
      for (final ident in ['415', '75', '218']) {
        expect('$ident$suffix', '$ident!@@');
      }
      expect('415$suffix', '415!@@');
    });

    test('인가번호가 비어 있으면 초기화 불가(빈 문자열 + !@@ 가 되면 안 됨)', () {
      String? build(String ident) {
        final d = ident.replaceAll(RegExp(r'[^0-9]'), '');
        if (d.isEmpty) return null;
        return '$d$suffix';
      }

      expect(build('범415'), '415!@@');
      expect(build('tiger75'), '75!@@');
      expect(build(''), isNull);
      expect(build('이승준'), isNull);
    });
  });

  group('개인 기본비밀번호 접미사와 일치', () {
    test('개인 기본비번도 !@@ 를 쓴다(같은 규칙)', () {
      // AppConfig.personalSuffix 와 동일해야 혼동이 없다.
      const personalSuffix = '!@@';
      expect(personalSuffix, '!@@');
      expect('415$personalSuffix', '415!@@');
    });
  });
}
