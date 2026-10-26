// 커스텀 게시판 — 공감(reaction) 규칙 고정 테스트.
//
// [요구 2026-10-26]
//   "자료를 읽고 **공감**하고, 다운받을 수 있도록 하고"
//
//  ## 읽음(read) vs 공감(like)
//   · 읽음  : 글을 열면 **자동**으로 기록된다. 읽은 사람 수만 센다.
//   · 공감  : 사용자가 **누르는 행동**이다. 같은 사람이 여러 번 눌러도 1.
//            → 건수(likeCount) + 내가 눌렀는지(iLiked)를 함께 내려준다.
//
//  ## 왜 이 테스트가 필요한가
//   서버(`/api/event/cboard/react`)는 **인가번호로 중복을 막는다**.
//   앱은 낙관적 갱신을 하므로, 실패 시 되돌리지 않으면 화면에 없는 공감이
//   남는다(눈속임). 여기서는 집계 규칙과 토글 계산을 고정한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/widgets/event_custom_board.dart';

void main() {
  group('공감 집계 — 같은 사람은 1로 센다', () {
    test('처음 누르면 1건', () {
      expect(LikeMath.nextCount(prev: 0, wasLiked: false), 1);
    });

    test('다시 누르면 0건 (토글 취소)', () {
      expect(LikeMath.nextCount(prev: 1, wasLiked: true), 0);
    });

    test('다른 사람이 이미 누른 상태에서 내가 누르면 +1', () {
      expect(LikeMath.nextCount(prev: 7, wasLiked: false), 8);
    });

    test('0 에서 취소해도 음수가 되지 않는다', () {
      expect(LikeMath.nextCount(prev: 0, wasLiked: true), 0);
    });
  });

  group('서버 응답을 화면 상태로 옮길 때', () {
    test('likeCount 가 없으면 기존 값을 유지한다', () {
      // 서버가 likeCount 를 빠뜨려도 화면이 0으로 튀지 않아야 한다.
      expect(
        LikeMath.applyResponse(current: 5, resp: const {'ok': true}),
        5,
      );
    });

    test('likeCount 를 주면 그 값을 쓴다', () {
      expect(
        LikeMath.applyResponse(current: 5, resp: const {'ok': true, 'likeCount': 3}),
        3,
      );
    });

    test('ok=false 면 되돌릴 값을 따로 돌려준다', () {
      // 낙관적 갱신을 되돌리기 위한 판정 — 실패하면 원래 값으로.
      expect(LikeMath.shouldRollback(const {'ok': false}), isTrue);
      expect(LikeMath.shouldRollback(const {'ok': true}), isFalse);
    });
  });

  group('iLiked 판정', () {
    test('내 인가번호가 명단에 있으면 true', () {
      final likes = [
        {'number': '415', 'name': '이승준'},
        {'number': '75', 'name': '이항복'},
      ];
      expect(LikeMath.iLiked(likes, '415'), isTrue);
    });

    test('명단에 없으면 false', () {
      final likes = [
        {'number': '75', 'name': '이항복'},
      ];
      expect(LikeMath.iLiked(likes, '415'), isFalse);
    });

    test('빈 인가번호(비로그인)는 false — 익명 공감은 만들지 않는다', () {
      final likes = [
        {'number': '', 'name': '익명'},
      ];
      expect(LikeMath.iLiked(likes, ''), isFalse);
    });

    test('명단이 null 이어도 터지지 않는다', () {
      expect(LikeMath.iLiked(null, '415'), isFalse);
    });
  });
}
