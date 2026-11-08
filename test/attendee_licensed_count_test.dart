// turn81 — 결산 '인가자' 집계는 **배타적**이어야 한다 (통계 정합성)
//
// ## 요구 (2026-11-07, 사용자 — 2차)
//   "리더로 등록된 사람을 인가자로 포함할 경우 리더 숫자에는 포함하지 않아야
//    하고 총 합계 숫자가 맞아야 됨. 따라서 범스카우트 인가자들은 무조건
//    인가자 항목에만 넣고 다른 항목의 숫자는 포함하지 말 것.
//    그렇게 해야 통계의 숫자가 맞음"
//
// ## 실제 데이터 (2026 범2호 노경하선배 추모행사 · 명단 8행)
//     김해온  컵       (인가번호 없음)
//     노승현  기타     (인가번호 없음)
//     김종환  #135  리더  ← 인가자로
//     정우식  #278       ← 인가자로
//     이승준  #415  리더  ← 인가자로
//     김병혁  #417  리더  ← 인가자로
//     송영선  #1064      ← 인가자로
//     양다솜  #1346 리더  ← 인가자로
//
//   인가자 6 · 리더 0 · 컵 1 · 기타 1 = **합계 8**  ← 항목 합 == 합계
//
// ## 이 테스트가 지키는 것
//   · 인가번호 보유자는 **인가자에만** 들어간다(리더·로버 등에 못 들어간다)
//   · 항목 합(rawItemSum) == 합계(total) — 통계가 맞아떨어진다
//   · 인가자가 일반으로 두 번 세어지지 않는다
//   · 직책이 없는 인가자는 인가자로 (정우식·송영선)
//   · 이름·전화번호는 인가번호가 아니다 (2026-10-29 '컵' 사고 재발 방지)
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

EventAttendeeBreakdown _bd(List<Map<String, dynamic>> atts) =>
    EventAttendeeBreakdown.fromAttendees(atts);

EventSettlement _settle(List<Map<String, dynamic>> atts) => EventSettlement(
  title: '2026 범2호 노경하선배 추모행사',
  year: '2026',
  attendees: atts,
  fees: const [],
  expenses: const [],
  attendeeCount: _bd(atts),
);

Map<SettlementBlock, SettlementBlockData> _build(
  List<Map<String, dynamic>> atts,
) => SettlementBuilder.build(
  settlement: _settle(atts),
  fees: const [],
  expenses: const [],
  attendees: atts,
  memo: false,
);

void main() {
  group('배타 집계 — 한 사람은 한 항목에만', () {
    test('실데이터 8명: 인가자 6 · 리더 0 · 컵 1 · 기타 1', () {
      final b = _bd(_screenshotRoster());
      expect(b.ivga, 6, reason: '인가번호 보유자 전원');
      expect(b.leader, 0,
          reason: '리더 4명이 모두 인가자로 갔으므로 리더 항목은 0');
      expect(b.cub, 1);
      expect(b.etc, 1);
      expect(b.regular, 0);
    });

    test('항목 합 == 합계 8 (통계가 맞아떨어진다)', () {
      final b = _bd(_screenshotRoster());
      expect(b.total, 8);
      expect(b.rawItemSum, 8, reason: '항목을 더한 값이 합계와 같아야 한다');
      expect(b.isConsistent, isTrue);
    });

    test('인가번호 보유자는 다른 직책 항목에 절대 들어가지 않는다', () {
      // 인가번호를 가진 사람에게 모든 직책을 붙여 봐도 인가자에만 가야 한다.
      final atts = [
        for (final r in ['리더', '로버', '벤처', '스카우트', '컵', '비버', '일반', '기타'])
          _row('인가$r', number: '415', roles: [r], licensed: true,
              corps: 'tsak', identityKey: 'tsak:415'),
      ];
      final b = _bd(atts);
      expect(b.ivga, 8, reason: '전원 인가자');
      expect(b.leader, 0);
      expect(b.rover, 0);
      expect(b.venture, 0);
      expect(b.scout, 0);
      expect(b.cub, 0);
      expect(b.beaver, 0);
      expect(b.regular, 0);
      expect(b.etc, 0);
      expect(b.rawItemSum, 8);
      expect(b.total, 8);
    });

    test('인가번호 없는 사람만 직책 항목에 들어간다', () {
      final atts = [
        _row('리더1', roles: ['리더'], identityType: 'regular',
            identityKey: 'reg:01011112222'),
        _row('리더2', roles: ['리더'], identityType: 'regular',
            identityKey: 'reg:01033334444'),
        _row('인가리더', number: '415', roles: ['리더'], licensed: true,
            corps: 'tsak'),
      ];
      final b = _bd(atts);
      expect(b.leader, 2, reason: '인가번호 없는 리더만 리더로');
      expect(b.ivga, 1, reason: '인가번호 있는 리더는 인가자로');
      expect(b.total, 3);
      expect(b.rawItemSum, 3);
    });

    test('직책 없는 인가자는 인가자로 (정우식·송영선)', () {
      final b = _bd([
        _row('정우식', number: '278', licensed: true, corps: 'tsak'),
        _row('송영선', number: '1064', licensed: true, corps: 'tsak'),
      ]);
      expect(b.ivga, 2);
      expect(b.regular, 0);
      expect(b.total, 2);
    });

    test('인가자가 일반으로 두 번 세어지지 않는다', () {
      final b = _bd(_screenshotRoster());
      expect(b.regular, 0);
      // 일반·기타 항목에는 인가번호 없는 두 사람만.
      expect(b.cub + b.etc, 2);
    });

    test('직책 보유 인가자 수를 따로 기록한다 (설명용)', () {
      final b = _bd(_screenshotRoster());
      expect(b.licensedWithRole, 4, reason: '리더 직책을 갖고 있던 인가자 4명');
      expect(b.licensedLeader, 4);
    });
  });

  group('직책별 인원 — 인가번호 없을 때는 그대로 센다', () {
    test('로버·벤처·스카우트·컵·비버는 각자 자리에만', () {
      final b = _bd([
        _row('로버1', roles: ['로버'], identityKey: 'reg:1'),
        _row('벤처1', roles: ['벤처'], identityKey: 'reg:2'),
        _row('스카우트1', roles: ['스카우트'], identityKey: 'reg:3'),
        _row('컵1', roles: ['컵'], identityKey: 'reg:4'),
        _row('비버1', roles: ['비버'], identityKey: 'reg:5'),
      ]);
      expect(b.rover, 1);
      expect(b.venture, 1);
      expect(b.scout, 1);
      expect(b.cub, 1);
      expect(b.beaver, 1);
      expect(b.ivga, 0);
      expect(b.total, 5);
      expect(b.rawItemSum, 5);
    });

    test('인가번호 없는 리더는 인가자에 들어가지 않는다', () {
      final b = _bd([
        _row('김해온', roles: ['리더'], identityType: 'regular',
            identityKey: 'reg:01098530114'),
      ]);
      expect(b.leader, 1);
      expect(b.ivga, 0, reason: '인가번호가 없으면 인가자가 아니다');
      expect(b.total, 1);
    });
  });

  group('인가번호 판정 — 이름·전화번호는 인가번호가 아니다', () {
    test('number 칸에 이름이 들어온 행은 인가자가 아니다', () {
      // 2026-10-29 '컵' 사고의 재발 방지.
      final b = _bd([_row('류호준', number: '류호준')]);
      expect(b.ivga, 0);
      expect(b.regular, 1);
    });

    test('number 칸이 휴대폰 번호면 인가자가 아니다', () {
      final b = _bd([_row('홍길동', number: '010-2702-1126')]);
      expect(b.ivga, 0);
      expect(b.regular, 1);
    });

    test('명시적으로 일반(reg:)인 행은 인가자가 아니다', () {
      final b = _bd([
        _row('노승현', number: '1234', identityKey: 'reg:01053045139'),
      ]);
      expect(b.ivga, 0, reason: 'reg: 접두어가 있으면 일반이다');
    });

    test('은하 인가번호도 인가자로 센다 (리더여도)', () {
      expect(
        AttendeeRoles.hasLicenseOnRow(_row('은하1', number: 'G12')),
        isTrue,
      );
      final b = _bd([_row('은하1', number: 'G12', roles: ['리더'])]);
      expect(b.ivga, 1);
      expect(b.leader, 0, reason: '인가자로 갔으므로 리더 아님');
      expect(b.total, 1);
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

  group('화면 표 — 숫자가 서로 맞는지 눈으로 검증 가능', () {
    test('인가자 6명·리더 0명·합계 8명, 근거 문구 포함', () {
      final att = _build(_screenshotRoster())[SettlementBlock.attendees]!;

      final ivga = att.rows.firstWhere((r) => r[0] == '인가자');
      expect(ivga[1], '6명');
      expect(ivga[2], contains('직책 보유 4명'), reason: '인가자 안의 근거');

      final leader = att.rows.firstWhere((r) => r[0] == '리더');
      expect(leader[1], '0명');
      expect(leader[2], contains('인가자로 집계'),
          reason: '리더 0명이 사라진 게 아니라 옮겨졌음을 알린다');

      final total = att.rows.firstWhere((r) => r[0] == '합계');
      expect(total[1], '8명');
    });

    test('표의 인원 항목을 모두 더하면 합계와 같다', () {
      final att = _build(_screenshotRoster())[SettlementBlock.attendees]!;
      var sum = 0;
      for (final r in att.rows) {
        if (r[0] == '합계' || r[0] == '인가자') continue;
        sum += int.parse(r[1].replaceAll(RegExp(r'[^0-9]'), ''));
      }
      final ivga = int.parse(
        att.rows.firstWhere((r) => r[0] == '인가자')[1]
            .replaceAll(RegExp(r'[^0-9]'), ''),
      );
      final total = int.parse(
        att.rows.firstWhere((r) => r[0] == '합계')[1]
            .replaceAll(RegExp(r'[^0-9]'), ''),
      );
      expect(ivga + sum, total, reason: '항목 합 == 합계');
    });

    test('리더가 인가자가 아니면 근거 문구를 붙이지 않는다', () {
      final atts = [
        _row('김해온', roles: ['리더'], identityType: 'regular',
            identityKey: 'reg:01098530114'),
      ];
      final att = _build(atts)[SettlementBlock.attendees]!;
      final ivga = att.rows.firstWhere((r) => r[0] == '인가자');
      expect(ivga[1], '0명');
      expect(ivga[2], isEmpty, reason: '겹침이 없으면 문구도 없다');
      final leader = att.rows.firstWhere((r) => r[0] == '리더');
      expect(leader[1], '1명');
      expect(leader[2], isEmpty);
    });

    test('명단이 비면 합계 0명', () {
      final att = _build(const [])[SettlementBlock.attendees]!;
      final total = att.rows.firstWhere((r) => r[0] == '합계');
      expect(total[1], '0명');
    });
  });

  group('summaryLine — 항목 합과 합계가 일치', () {
    test('인가자 6 · 리더 0 … · 합계 8', () {
      final line = _bd(_screenshotRoster()).summaryLine;
      expect(line, contains('인가자 6'));
      expect(line, contains('리더 0'));
      expect(line, endsWith('합계 8'));
    });
  });
}
