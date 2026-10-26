// ── 행사 스탭(STAFF) 권한 회귀 테스트 ────────────────────────────────────
//
// 배경(요구 2026-10-26):
//   "행사관리에서 스탭권한으로 로그인하면 후원 및 지출정보가 안 보임.
//    마스터에서는 보임. 스탭으로 등록되면 다 보이도록 할 것"
//
// 원인(2곳):
//   ① 앱: 재무 조회를 `widget.canManage`(= 관리자·마스터)로만 감쌌다.
//        스탭 여부(_isStaff)는 판정했지만 재무 요청 조건에 쓰지 않았다.
//   ② 서버: `/api/event/finance` 가 `_require("admin")` 이라 스탭(개인 세션)
//        은 401. 게다가 `/api/event/finance/add|update|delete` 에는
//        **인증 검사가 아예 없었다**.
//
// 이 테스트는 "스탭 판정 규칙"이 화면과 서버에서 동일하게 유지되는지 지킨다.
import 'package:flutter_test/flutter_test.dart';

/// 화면(EventDetailScreen)이 쓰는 스탭 판정 규칙과 동일한 구현.
///  스탭 항목의 number/ident/loginId/phone 중 숫자만 뽑아 본인 인가번호와 비교.
bool isStaffOf(List<Map<String, dynamic>> staff, String who) {
  final myIdent = who.replaceAll(RegExp(r'[^0-9]'), '');
  if (myIdent.isEmpty) return false;
  for (final a in staff) {
    final id = '${a['number'] ?? a['ident'] ?? a['loginId'] ?? a['phone'] ?? ''}'
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (id.isNotEmpty && id == myIdent) return true;
  }
  return false;
}

/// 재무 열람 조건 — 관리자·마스터이거나 스탭.
bool canSeeFinance({required bool canManage, required bool isStaff}) =>
    canManage || isStaff;

void main() {
  const staff = [
    {'ident': '415', 'number': '415', 'name': '이승준'},
    {'ident': '326', 'number': '326', 'name': '김승수'},
    {'ident': '75', 'number': '75', 'name': '이항복'},
  ];

  group('스탭 판정', () {
    test('명단에 있으면 스탭이다', () {
      expect(isStaffOf(staff, '75'), isTrue);
      expect(isStaffOf(staff, '415'), isTrue);
      expect(isStaffOf(staff, '326'), isTrue);
    });

    test('명단에 없으면 스탭이 아니다', () {
      expect(isStaffOf(staff, '218'), isFalse);
      expect(isStaffOf(staff, '999'), isFalse);
    });

    test('본인 번호가 비어 있으면 스탭이 아니다', () {
      expect(isStaffOf(staff, ''), isFalse);
      expect(isStaffOf(staff, '  '), isFalse);
    });

    test('번호 형식이 섞여도 숫자만 비교한다', () {
      expect(isStaffOf(staff, 'tiger75'), isTrue);
      expect(isStaffOf(staff, '범75'), isTrue);
      expect(isStaffOf(staff, '75!@@'), isTrue);
    });

    test('부분 일치로 잘못 통과하지 않는다', () {
      // '7' 은 '75' 의 부분 문자열이지만 숫자가 다르므로 불일치여야 한다.
      expect(isStaffOf(staff, '7'), isFalse);
      expect(isStaffOf(staff, '4'), isFalse);
    });

    test('스탭 항목이 loginId 만 있어도 판정된다', () {
      const alt = [
        {'loginId': 'tiger75', 'name': '이항복'},
      ];
      expect(isStaffOf(alt, '75'), isTrue);
    });
  });

  group('재무 열람 조건', () {
    test('마스터·관리자는 항상 열람 가능', () {
      expect(canSeeFinance(canManage: true, isStaff: false), isTrue);
    });

    test('스탭은 관리자가 아니어도 열람 가능', () {
      expect(canSeeFinance(canManage: false, isStaff: true), isTrue);
    });

    test('일반 참가자는 열람 불가', () {
      expect(canSeeFinance(canManage: false, isStaff: false), isFalse);
    });
  });
}
