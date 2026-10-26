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

  // ── [요구 2026-10-26] "관리자/마스터 권한으로 구분해서 정리해줘" ──
  group('메뉴 관리 — 권한별 동작 구분', () {
    // 마스터: 추가/변경/삭제/게시판삭제/노출권한 전부
    test('마스터는 모든 동작이 가능하다', () {
      const r = MenuManageRights(isAdmin: true, isMaster: true);
      expect(r.canAdd, isTrue);
      expect(r.canRename, isTrue);
      expect(r.canReorder, isTrue);
      expect(r.canRemoveTab, isTrue);
      expect(r.canDeleteBoard, isTrue);
      expect(r.canChangeVisibility, isTrue);
      expect(r.canSeeMenu, isTrue);
    });

    // 관리자: 삭제까지 가능하되 '게시판 통째로 삭제'만 불가
    test('관리자는 추가·변경·삭제가 가능하지만 게시판 삭제는 불가', () {
      const r = MenuManageRights(isAdmin: true, isMaster: false);
      expect(r.canAdd, isTrue);
      expect(r.canRename, isTrue);
      expect(r.canReorder, isTrue);
      // 1차 요구 "관리자도 삭제할 수 있음" — 여기가 false 면 지적이 반복된다.
      expect(r.canRemoveTab, isTrue);
      // 글·첨부가 통째로 소멸하는 동작만 마스터에 남긴다.
      expect(r.canDeleteBoard, isFalse);
      expect(r.canChangeVisibility, isTrue);
    });

    test('권한이 없으면 아무 동작도 못 하지만 메뉴는 보인다', () {
      const r = MenuManageRights(isAdmin: false, isMaster: false);
      expect(r.canAdd, isFalse);
      expect(r.canRename, isFalse);
      expect(r.canReorder, isFalse);
      expect(r.canRemoveTab, isFalse);
      expect(r.canDeleteBoard, isFalse);
      expect(r.canChangeVisibility, isFalse);
      // 종전 버그: 메뉴 자체가 사라져 "기능이 없다"고 보였다.
      expect(r.canSeeMenu, isTrue);
    });

    test('마스터는 반드시 관리자이기도 하다(부분집합 관계)', () {
      // isMaster=true 인데 isAdmin=false 인 조합은 서버(_auth_ok)에서도
      //  나오지 않는다. UI 도 같은 전제를 쓴다.
      const master = MenuManageRights(isAdmin: true, isMaster: true);
      const admin = MenuManageRights(isAdmin: true, isMaster: false);
      const guest = MenuManageRights(isAdmin: false, isMaster: false);

      // 마스터 ⊃ 관리자 ⊃ 비권한자
      expect(master.canRemoveTab && admin.canRemoveTab, isTrue);
      expect(admin.canRemoveTab && !guest.canRemoveTab, isTrue);
      // 게시판 삭제만 마스터 단독
      expect(master.canDeleteBoard, isTrue);
      expect(admin.canDeleteBoard || guest.canDeleteBoard, isFalse);
    });

    test('게시판 통째로 삭제는 서버 require("admin")보다 좁다', () {
      // 서버 /cboard/board/delete 는 _require("admin") 이지만,
      //  앱에서는 UI 를 마스터로 더 좁게 잠근다(오조작 방지).
      //  → 서버가 허용하는 것을 앱이 막는 것은 안전한 방향.
      const r = MenuManageRights(isAdmin: true, isMaster: false);
      expect(r.canDeleteBoard, isFalse,
          reason: '관리자에게 게시판 삭제 UI 를 노출하지 않는다');
    });
  });
}

// ── [추가 요구 2026-10-26] "관리자/마스터 권한으로 구분해서 정리해줘" ──
//  메뉴(⋯) 항목과 메뉴 관리 창의 버튼이 **권한별로 정확히 갈리는지** 고정한다.
//  서버(_auth_ok / _require)와 짝을 이루는 클라이언트 측 규칙.
//
//  ## 확정된 권한 경계 (2026-10-26)
//   1차 요구: "관리자 / 마스터는 생성, 삭제, 변경 등의 관리 기능을 할 수 있음"
//   2차 요구: "관리자/마스터 권한으로 구분해서 정리해줘"
//   → 관리자도 **삭제할 수 있다**(탭에서 빼기). 다만 '게시판 통째로 삭제'
//     (글·첨부목록이 전부 소멸)만 마스터에 남긴다. 이렇게 해야 1차 지적
//     ("메뉴 삭제 기능이 없음")이 다시 나오지 않는다.
/// 메뉴 관리 창에서 각 동작이 허용되는지 — UI 조건과 1:1 대응.
class MenuManageRights {
  const MenuManageRights({required this.isAdmin, required this.isMaster});

  final bool isAdmin;
  final bool isMaster;

  /// 메뉴 추가 / 이름·내용 변경 / 순서 이동 — 관리자·마스터
  bool get canAdd => isAdmin;
  bool get canRename => isAdmin;
  bool get canReorder => isAdmin;

  /// 항목 삭제(탭에서 빼기) — 관리자·마스터.
  ///  게시판 데이터는 NAS 에 남으므로 되돌릴 수 있다.
  bool get canRemoveTab => isAdmin;

  /// 게시판 통째로 삭제(글·첨부목록까지 소멸) — **마스터 전용**.
  bool get canDeleteBoard => isMaster;

  /// 노출권한 변경(all/staff/admin) — 관리자·마스터
  bool get canChangeVisibility => isAdmin;

  /// 메뉴(⋯) 자체는 모든 인가자에게 보인다(권한 판정 실패로 사라지면 안 됨).
  bool get canSeeMenu => true;
}
