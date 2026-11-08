// turn80 — 결산 '인가자' 인원이 직책 때문에 빠지던 문제 회귀 테스트
//
// ## 요구 (2026-11-07, 사용자)
//   "참가자 중 범스카우트 인가자가 리더로 선택할 경우에도
//    인가자 항목에 인원을 넣을 것"
//
// ## 실제 증상 (결산서 스크린샷 — 2026 범2호 노경하선배 추모행사, 8명)
//   인가자      2명   ← 실제 인가번호 보유자는 6명
//   리더        4명
//   컵          1명
//   기타        1명
//   합계        8명
//
//   명단 8행의 실제 구성:
//     김해온  (컵,  인가번호 없음)
//     노승현  (기타, 인가번호 없음)
//     김종환  #135  리더   ← 인가자로 안 세어졌다
//     정우식  #278  (직책 없음)
//     이승준  #415  리더   ← 인가자로 안 세어졌다
//     김병혁  #417  리더   ← 인가자로 안 세어졌다
//     송영선  #1064 (직책 없음)
//     양다솜  #1346 리더   ← 인가자로 안 세어졌다
//
// ## 원인
//   fromAttendees 가 **직책 우선**이라, roles 에 '리더' 가 있으면
//   인가번호를 갖고 있어도 리더로만 세고 continue 했다.
//
// ## 이 테스트가 지키는 것
//   · 인가자 = 인가번호 보유자 **전원** (리더여도 포함)
//   · 리더 등 직책별 인원은 종전 그대로 유지
//   · 한 사람이 인가자 + 일반으로 **두 번** 세어지지 않는다
//   · 합계는 항목 합이 아니라 **명단 행 수** (겹침 때문에 합으로 구하면 안 됨)
//   · 이름·전화번호가 인가번호 칸에 있어도 인가자로 세지 않는다(2026-10-29 규칙 유지)
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/attendee_roles.dart';
import 'package:tsak_credential_manager/services/event_settlement.dart';
import 'package:tsak_credential_manager/services/settlement_layout.dart';

Map<String, dynamic> _row(
  String name, {
  String? number,
  List<String> roles = const [],
  bool licensed = false,
  String identityType = '',
  String corps = '',
  String identityKey = '',
}) => {
  'name': name,
  'number': number,
  'roles': roles,
  'licensed': licensed,
  'identityType': identityType,
  'corps': corps,
  'identityKey': identityKey,
};

/// 스크린샷의 실제 8명 — 이 구성이 회귀의 기준이다.
List<Map<String, dynamic>> _screenshotRoster() => [
  _row('김해온', number: null, roles: ['컵'],
      identityType: 'regular', identityKey: 'reg:01098530114'),
  _row('노승현', number: '', roles: ['기타'],
      identityType: 'regular', identityKey: 'reg:01053045139'),
  _row('김종환', number: '135', roles: ['리더'], licensed: true,
      identityType: 'licensed', corps: 'tsak', identityKey: 'tsak:135'),
  _row('정우식', number: '278', licensed: true,
      identityType: 'licensed', corps: 'tsak', identityKey: 'tsak:278'),
  _row('이승준', number: '415', roles: ['리더'], licensed: true,
      identityType: 'licensed', corps: 'tsak', identityKey: 'tsak:415'),
  _row('김병혁', number: '417', roles: ['리더'], licensed: true,
      identityType: 'licensed', corps: 'tsak', identityKey: 'tsak:417'),
  _row('송영선', number: '1064', licensed: true,
      identityType: 'licensed', corps: 'tsak', identityKey: 'tsak:1064'),
  _row('양다솜', number: '1346', roles: ['리더'], licensed: true,
      identityType: 'licensed', corps: 'tsak', identityKey: 'tsak:1346'),
];

EventSettlement _settle(List<Map<String, dynamic>> atts) => EventSettlement(
  title: '2026 범2호 노경하선배 추모행사',
  year: '2026',
  attendees: atts,
  fees: const [],
  expenses: const [],
  attendeeCount: EventAttendeeBreakdown.fromAttendees(atts),
);

void main() {
  group('인가자 — 리더로 선택해도 인가자에 넣는다', () {
    test('실데이터 8명: 인가자 2명 → 6명', () {
      final bd = EventAttendeeBreakdown.fromAttendees(_screenshotRoster());
      expect(bd.ivga, 6, reason: '인가번호 보유자 전원 (종전 2명)');
    });

    test('리더 인원은 종전 그대로 4명', () {
      final bd = EventAttendeeBreakdown.fromAttendees(_screenshotRoster());
      expect(bd.leader, 4, reason: '직책별 집계는 바뀌지 않아야 한다');
    });

    test('리더 4명 전원이 인가자이므로 leaderLicensed == 4', () {
      final bd = EventAttendeeBreakdown.fromAttendees(_screenshotRoster());
      expect(bd.leaderLicensed, 4);
      expect(bd.ivgaNote, contains('리더 4명'));
    });

    test('합계는 항목 합이 아니라 명단 행 수 (8명)', () {
      final bd = EventAttendeeBreakdown.fromAttendees(_screenshotRoster());
      expect(bd.total, 8);
      // 인가자가 리더와 겹치므로 항목을 그대로 더하면 부풀려진다.
      expect(bd.rawItemSum, 12);
      expect(bd.rawItemSum, isNot(bd.total));
    });

    test('직책 없는 인가자도 그대로 인가자다 (정우식·송영선)', () {
      final bd = EventAttendeeBreakdown.fromAttendees([
        _row('정우식', number: '278', licensed: true, corps: 'tsak'),
        _row('송영선', number: '1064', licensed: true, corps: 'tsak'),
      ]);
      expect(bd.ivga, 2);
      expect(bd.total, 2);
    });

    test('인가자가 일반으로 두 번 세어지지 않는다', () {
      final bd = EventAttendeeBreakdown.fromAttendees(_screenshotRoster());
      expect(bd.regular, 0, reason: '인가자를 일반으로 또 세면 안 된다');
      // 일반·기타에는 인가번호 없는 두 사람만.
      expect(bd.cub + bd.etc, 2);
    });
  });

  group('직책별 인원은 그대로 (회귀 방지)', () {
    test('로버·벤처·스카우트·컵·비버는 각자 자리에만', () {
      final bd = EventAttendeeBreakdown.fromAttendees([
        _row('로버1', roles: ['로버']),
        _row('벤처1', roles: ['벤처']),
        _row('스카우트1', roles: ['스카우트']),
        _row('컵1', roles: ['컵']),
        _row('비버1', roles: ['비버']),
      ]);
      expect(bd.rover, 1);
      expect(bd.venture, 1);
      expect(bd.scout, 1);
      expect(bd.cub, 1);
      expect(bd.beaver, 1);
      expect(bd.total, 5);
    });

    test('인가번호 없는 리더는 인가자에 들어가지 않는다', () {
      final bd = EventAttendeeBreakdown.fromAttendees([
        _row('김해온', roles: ['리더'], identityType: 'regular',
            identityKey: 'reg:01098530114'),
      ]);
      expect(bd.leader, 1);
      expect(bd.ivga, 0, reason: '인가번호가 없으면 인가자가 아니다');
      expect(bd.total, 1);
    });
  });

  group('인가번호 판정 — 이름·전화번호는 인가번호가 아니다', () {
    test('number 칸에 이름이 들어온 행은 인가자가 아니다', () {
      // 2026-10-29 '컵' 사고의 재발 방지.
      final bd = EventAttendeeBreakdown.fromAttendees([
        _row('류호준', number: '류호준'),
      ]);
      expect(bd.ivga, 0);
      expect(bd.regular, 1);
    });

    test('number 칸이 휴대폰 번호면 인가자가 아니다', () {
      final bd = EventAttendeeBreakdown.fromAttendees([
        _row('홍길동', number: '010-2702-1126'),
      ]);
      expect(bd.ivga, 0);
      expect(bd.regular, 1);
    });

    test('명시적으로 일반(reg:)인 행은 인가자가 아니다', () {
      final bd = EventAttendeeBreakdown.fromAttendees([
        _row('노승현', number: '1234', identityKey: 'reg:01053045139'),
      ]);
      expect(bd.ivga, 0, reason: 'reg: 접두어가 있으면 일반이다');
    });

    test('은하 인가번호도 인가자로 센다', () {
      expect(
        AttendeeRoles.hasLicenseOnRow(_row('은하1', number: 'G12')),
        isTrue,
      );
      final bd = EventAttendeeBreakdown.fromAttendees([
        _row('은하1', number: 'G12', roles: ['리더']),
      ]);
      expect(bd.ivga, 1);
      expect(bd.leader, 1);
    });

    test('hasLicenseOnRow — licensed/identityKey/corps 신호를 모두 인정', () {
      expect(AttendeeRoles.hasLicenseOnRow({'licensed': true}), isTrue);
      expect(AttendeeRoles.hasLicenseOnRow({'identityKey': 'tsak:415'}), isTrue);
      expect(
        AttendeeRoles.hasLicenseOnRow({'identityKey': 'eunha:G7'}),
        isTrue,
      );
      expect(AttendeeRoles.hasLicenseOnRow({'corps': 'tsak'}), isTrue);
      expect(AttendeeRoles.hasLicenseOnRow({'corps': 'eunha'}), isTrue);
      expect(AttendeeRoles.hasLicenseOnRow({'number': '415'}), isTrue);
      expect(AttendeeRoles.hasLicenseOnRow({'number': ''}), isFalse);
    });
  });

  group('화면 표 — 인가자 줄에 겹침 근거를 보여 준다', () {
    test('인가자 6명 · 리더 4명 포함 / 합계 8명', () {
      final s = _settle(_screenshotRoster());
      final b = SettlementBuilder.build(
        settlement: s,
        fees: const [],
        expenses: const [],
        attendees: _screenshotRoster(),
        memo: false,
      );
      final att = b[SettlementBlock.attendees]!;

      final ivga = att.rows.firstWhere((r) => r[0] == '인가자');
      expect(ivga[1], '6명');
      expect(ivga[2], contains('리더 4명'), reason: '겹침을 숨기지 않는다');

      final leader = att.rows.firstWhere((r) => r[0] == '리더');
      expect(leader[1], '4명');

      final total = att.rows.firstWhere((r) => r[0] == '합계');
      expect(total[1], '8명');
    });

    test('리더가 인가자가 아니면 근거 문구를 붙이지 않는다', () {
      final atts = [
        _row('김해온', roles: ['리더'], identityType: 'regular',
            identityKey: 'reg:01098530114'),
      ];
      final b = SettlementBuilder.build(
        settlement: _settle(atts),
        fees: const [],
        expenses: const [],
        attendees: atts,
        memo: false,
      );
      final ivga = b[SettlementBlock.attendees]!.rows
          .firstWhere((r) => r[0] == '인가자');
      expect(ivga[1], '0명');
      expect(ivga[2], isEmpty, reason: '겹침이 없으면 문구도 없다');
    });

    test('명단이 비면 합계 0명', () {
      final b = SettlementBuilder.build(
        settlement: _settle(const []),
        fees: const [],
        expenses: const [],
        attendees: const [],
        memo: false,
      );
      final total = b[SettlementBlock.attendees]!.rows
          .firstWhere((r) => r[0] == '합계');
      expect(total[1], '0명');
    });
  });

  group('summaryLine', () {
    test('인가자 6 · 리더 4 … · 합계 8', () {
      final bd = EventAttendeeBreakdown.fromAttendees(_screenshotRoster());
      final line = bd.summaryLine;
      expect(line, contains('인가자 6'));
      expect(line, contains('리더 4'));
      expect(line, endsWith('합계 8'));
    });
  });
}
