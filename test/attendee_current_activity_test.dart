// ══════════════════════════════════════════════════════════════════════════
// [요구 2026-11-08] 행사 참가자 등록정보는 **현재활동** 정보로 인쇄한다.
//
//   "행사 참가자 명단에서 참가자 등록정보는 현재활동 정보로 넣어줘
//    이승준+김병혁 등은 인가시 정보가 들어가 있음 / 모두 현재 활동정보로 수정"
//
// ## 사고 내용
//  참석자 행(map)에는 **등록 시점(인가시) 소속**이 `league`/`unit` 으로
//  박혀 있다. 종전 `_leagueOf`/`_unitOf` 가 이 스냅샷을 먼저 읽어서
//  이승준(415) `제1234단 인천연맹 직할단`, 김병혁(417) `제1234단 인천연맹 직할대`
//  가 PDF 상세 내역에 그대로 찍혔다. 실제 현재활동은
//  `제5678단 나래지역대` / `두레지역대, 나래지역대, 샘물지역대` 이다.
//
// ## 고친 규칙 (읽는 순서)
//   ① `leagueText` / `unitText`  — 서버가 표시 시점에 주입한 현재활동
//   ② `regLeague`  / `regUnit`   — 회원 맵을 직접 받은 경우
//   ③ `league`     / `unit`      — 행 스냅샷(현재활동 값이 없을 때만 폴백)
//
// 아래 데이터는 2026-11-08 실제 `/api/event/get` · `/api/members` 응답값이다.
// ══════════════════════════════════════════════════════════════════════════
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/attendee_roles.dart';
import 'package:tsak_credential_manager/services/event_settlement.dart';
import 'package:tsak_credential_manager/services/settlement_layout.dart';

/// 실제 API 응답 그대로 — `league`/`unit` = 인가시, `*Text` = 현재활동.
Map<String, dynamic> _row(
  String name,
  String number, {
  String league = '',
  String unit = '',
  String leagueText = '',
  String unitText = '',
  String identityKey = '',
  String identityType = 'licensed',
  bool licensed = true,
}) =>
    {
      'name': name,
      'number': number,
      'identityKey': identityKey,
      'identityType': identityType,
      'licensed': licensed,
      'league': league.isEmpty ? null : league,
      'unit': unit,
      'leagueText': leagueText,
      'unitText': unitText,
    };

/// 2026 범2호 노경하선배 추모행사 — 8명 전원.
List<Map<String, dynamic>> _realRoster() => [
      // 서포터즈(컵스카우트) — 인가번호 없음. 현재활동은 회원카드에서 주입.
      _row('김해온', '', identityKey: 'reg:01098530114',
          identityType: 'regular', licensed: false,
          leagueText: '제주', unitText: '샘물지역대 · 컵스카우트'),
      // 유족 — 회원 명부에 없다. 스냅샷이 유일한 값.
      _row('노승현', '', identityKey: 'reg:01053045139',
          identityType: 'regular', licensed: false,
          unit: '유족 (노경하 선배님 삼남) 송종호텔',
          unitText: '유족 (노경하 선배님 삼남) 송종호텔'),
      // 현재활동(reg*)이 **비어 있음** → 인가시로 폴백해야 한다.
      _row('김종환', '135', league: '부산', unit: '제1378대 연장대',
          leagueText: '부산', unitText: '제1378대 연장대',
          identityKey: 'tsak:135'),
      // 인가시 league 없음, 현재활동 단위대만 다름
      _row('정우식', '278',
          unit: '제1553단 우하 오르카 스카우트 우하범고래지역대',
          leagueText: '부산',
          unitText: '제1553단 우하 오르카 스카우트 우하범고래지역대',
          identityKey: 'tsak:278'),
      // ★ 사고 당사자 ① — 인가시 '인천 / 제1234단 인천연맹 직할단'
      _row('이승준', '415', league: '인천', unit: '제1234단 인천연맹 직할단',
          leagueText: '인천', unitText: '제5678단 나래지역대',
          identityKey: 'tsak:415'),
      // ★ 사고 당사자 ② — 인가시 '인천 / 제1234단 인천연맹 직할대'
      _row('김병혁', '417', league: '인천', unit: '제1234단 인천연맹 직할대',
          leagueText: '서울남부, 인천, 제주',
          unitText: '두레지역대, 나래지역대, 샘물지역대',
          identityKey: 'tsak:417'),
      // 현재활동(reg*)이 비어 있음 → 인가시 폴백
      _row('송영선', '1064', unit: '충덕스카우트',
          leagueText: '전남', unitText: '충덕스카우트',
          identityKey: 'tsak:1064'),
      // 직위(중앙커미셔너)가 단위대에 병기됨
      _row('양다솜', '1346', league: '인천', unit: '제516단 순천지역대 벤처스카우트',
          leagueText: '인천', unitText: '제5678단 나래지역대 · 중앙커미셔너',
          identityKey: 'tsak:1346'),
    ];

void main() {
  group('현재활동 소속 해석 — currentLeague / currentUnit', () {
    test('이승준(415) — 인가시가 아니라 현재활동 단위대를 쓴다', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '이승준');
      expect(SettlementLine.currentLeague(a), '인천');
      expect(SettlementLine.currentUnit(a), '제5678단 나래지역대');
      // 인가시 값이 새어 나오면 안 된다.
      expect(SettlementLine.currentUnit(a), isNot(contains('직할단')));
      expect(SettlementLine.currentUnit(a), isNot(contains('제1234단')));
    });

    test('김병혁(417) — 세 지역대를 모두 유지한다', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '김병혁');
      expect(SettlementLine.currentLeague(a), '서울남부, 인천, 제주');
      expect(SettlementLine.currentUnit(a), '두레지역대, 나래지역대, 샘물지역대');
      expect(SettlementLine.currentUnit(a), isNot(contains('직할대')));
      expect(SettlementLine.currentUnit(a), isNot(contains('제1234단')));
    });

    test('양다솜(1346) — 직위가 단위대에 병기된다', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '양다솜');
      expect(SettlementLine.currentUnit(a), contains('중앙커미셔너'));
      expect(SettlementLine.currentUnit(a), contains('제5678단 나래지역대'));
      expect(SettlementLine.currentUnit(a), isNot(contains('순천지역대 벤처')));
    });

    test('김종환(135) — 현재활동 값이 없으면 인가시로 폴백한다(빈칸 금지)', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '김종환');
      expect(SettlementLine.currentLeague(a), '부산');
      expect(SettlementLine.currentUnit(a), '제1378대 연장대');
    });

    test('송영선(1064) — 현재활동 값이 없으면 인가시로 폴백한다', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '송영선');
      expect(SettlementLine.currentLeague(a), '전남');
      expect(SettlementLine.currentUnit(a), '충덕스카우트');
    });

    test('회원 명부에 없는 유족(노승현)은 스냅샷을 그대로 쓴다', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '노승현');
      expect(SettlementLine.currentUnit(a), '유족 (노경하 선배님 삼남) 송종호텔');
      expect(SettlementLine.currentLeague(a), '');
    });

    test('서버 주입이 없어도 regLeague/regUnit 이 있으면 그걸 쓴다', () {
      final a = {
        'name': '테스트',
        'league': '인천',
        'unit': '옛 직할단',
        'regLeague': '서울남부',
        'regUnit': '새 지역대',
      };
      expect(SettlementLine.currentLeague(a), '서울남부');
      expect(SettlementLine.currentUnit(a), '새 지역대');
    });

    test('아무 값도 없으면 빈 문자열(예외 없음)', () {
      final a = {'name': '무정보'};
      expect(SettlementLine.currentLeague(a), '');
      expect(SettlementLine.currentUnit(a), '');
      expect(SettlementLine.currentActivityText(a), '');
    });
  });

  group('currentActivityText — 연맹 · 단위대 한 줄', () {
    test('연맹과 단위대를 공백으로 잇는다', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '이승준');
      expect(SettlementLine.currentActivityText(a), '인천 제5678단 나래지역대');
    });

    test('단위대가 이미 연맹을 품으면 중복해 붙이지 않는다', () {
      final a = {
        'name': '중복',
        'leagueText': '인천',
        'unitText': '인천 제9999단 나래지역대',
      };
      expect(SettlementLine.currentActivityText(a), '인천 제9999단 나래지역대');
    });

    test('연맹만 있으면 연맹만, 단위대만 있으면 단위대만 나온다', () {
      expect(
        SettlementLine.currentActivityText({'leagueText': '제주'}),
        '제주',
      );
      expect(
        SettlementLine.currentActivityText({'unitText': '샘물지역대'}),
        '샘물지역대',
      );
    });

    test('구분자 `·` 는 `/` 로 정규화된다(줄 구분자 충돌 방지)', () {
      final a = {'name': 'x', 'unitText': '나래지역대 · 중앙커미셔너'};
      // currentUnit 은 원문 유지, 텍스트 조립 시에만 정규화.
      expect(SettlementLine.currentUnit(a), '나래지역대 · 중앙커미셔너');
      expect(
        SettlementLine.currentActivityText(a),
        '나래지역대 / 중앙커미셔너',
      );
    });
  });

  group('SettlementLine.of — 상세 한 줄에 현재활동이 들어간다', () {
    test('이승준 줄에 현재활동 단위대가 찍히고 인가시는 사라진다', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '이승준');
      final line = SettlementLine.of(
        a,
        league: SettlementLine.currentLeague(a),
        unit: SettlementLine.currentUnit(a),
      );
      expect(line, contains('이승준'));
      expect(line, contains('범#415'));
      expect(line, contains('제5678단 나래지역대'));
      expect(line, isNot(contains('제1234단')));
      expect(line, isNot(contains('직할단')));
    });

    test('김병혁 줄도 현재활동 기준', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '김병혁');
      final line = SettlementLine.of(
        a,
        league: SettlementLine.currentLeague(a),
        unit: SettlementLine.currentUnit(a),
      );
      expect(line, contains('범#417'));
      expect(line, contains('두레지역대'));
      expect(line, isNot(contains('직할대')));
    });

    test('인자를 주지 않아도 스스로 현재활동을 복원한다', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '이승준');
      final line = SettlementLine.of(a);
      expect(line, contains('제5678단 나래지역대'));
      expect(line, isNot(contains('제1234단')));
    });

    test('명시 인자가 있으면 그 값이 최우선(호출자 의도 존중)', () {
      final a = _realRoster().firstWhere((e) => e['name'] == '이승준');
      final line = SettlementLine.of(a, league: '강제', unit: '강제단');
      expect(line, contains('강제'));
      expect(line, isNot(contains('나래지역대')));
    });

    test('8명 전원이 빈 줄 없이 만들어진다', () {
      final lines = [
        for (final a in _realRoster())
          SettlementLine.of(
            a,
            league: SettlementLine.currentLeague(a),
            unit: SettlementLine.currentUnit(a),
          ),
      ];
      expect(lines.length, 8);
      for (var i = 0; i < lines.length; i++) {
        expect(lines[i].trim(), isNotEmpty, reason: '$i번째 줄이 비었다');
      }
    });

    test('8명 전원의 상세 줄에 인가시 단위대 문자열이 하나도 없다', () {
      // 인가시 값에만 있는 토큰 — 하나라도 나오면 회귀.
      const atLicensing = ['제1234단', '직할단', '직할대', '제516단'];
      for (final a in _realRoster()) {
        final line = SettlementLine.of(
          a,
          league: SettlementLine.currentLeague(a),
          unit: SettlementLine.currentUnit(a),
        );
        for (final bad in atLicensing) {
          expect(
            line.contains(bad),
            isFalse,
            reason: '${a['name']} 줄에 인가시 값 "$bad" 이 남았다: $line',
          );
        }
      }
    });
  });

  group('회귀 방지 — 코드가 스냅샷을 먼저 읽지 않는지', () {
    test('currentLeague 는 leagueText 를 league 보다 먼저 본다', () {
      final a = {'name': 'x', 'league': '인가시연맹', 'leagueText': '현재연맹'};
      expect(SettlementLine.currentLeague(a), '현재연맹');
    });

    test('currentUnit 은 unitText 를 unit 보다 먼저 본다', () {
      final a = {'name': 'x', 'unit': '인가시단', 'unitText': '현재단'};
      expect(SettlementLine.currentUnit(a), '현재단');
    });

    test('currentLeague 는 빈 leagueText 를 건너뛰고 다음 후보로 간다', () {
      final a = {
        'name': 'x',
        'leagueText': '   ',
        'regLeague': '현재연맹2',
        'league': '인가시연맹',
      };
      expect(SettlementLine.currentLeague(a), '현재연맹2');
    });
  });

  // 통합 경로(SettlementBuilder.build → 화면·미리보기·PDF 공용) 검증.
  _builderGroup();
}

// ══════════════════════════════════════════════════════════════════════════
// [요구 2026-11-08] 결산서 빌더(`SettlementBuilder.build`)의 `details` —
//  즉 **화면 카드·미리보기·PDF 가 공통으로 쓰는 실제 경로**에서 현재활동이
//  찍히는지 확인한다. 위 그룹은 헬퍼 단위였고, 이 그룹은 통합 경로다.
// ══════════════════════════════════════════════════════════════════════════
void _builderGroup() {
  group('SettlementBuilder.build — 상세 내역이 현재활동으로 나온다', () {
    Map<SettlementBlock, SettlementBlockData> run() {
      final attendees = _realRoster();
      return SettlementBuilder.build(
        settlement: EventSettlement(
          title: '2026 범2호 노경하선배 추모행사',
          year: '2026',
          attendeeCount: EventAttendeeBreakdown.fromAttendees(attendees),
          attendees: attendees,
          fees: const [],
          expenses: const [],
        ),
        fees: const [],
        expenses: const [],
        attendees: attendees,
      );
    }

    test('참가자 블록 상세 8줄에 인가시 소속이 없다', () {
      final d = run()[SettlementBlock.attendees]!;
      expect(d.details.length, 8);
      const atLicensing = ['제1234단', '직할단', '직할대', '제516단', '제1334단'];
      for (final line in d.details) {
        for (final bad in atLicensing) {
          expect(line.contains(bad), isFalse,
              reason: '인가시 값 "$bad" 이 상세에 남았다: $line');
        }
      }
    });

    test('이승준은 현재활동 지역대, 김병혁은 세 지역대로 나온다', () {
      final details = run()[SettlementBlock.attendees]!.details;
      final lee = details.firstWhere((l) => l.contains('이승준'));
      final kim = details.firstWhere((l) => l.contains('김병혁'));
      expect(lee, contains('제5678단 나래지역대'));
      expect(kim, contains('두레지역대, 나래지역대, 샘물지역대'));
    });

    test('현재활동 값이 없는 두 사람도 빈 줄이 되지 않는다', () {
      final details = run()[SettlementBlock.attendees]!.details;
      final kimjong = details.firstWhere((l) => l.contains('김종환'));
      final song = details.firstWhere((l) => l.contains('송영선'));
      expect(kimjong, contains('제1378대 연장대'));
      expect(song, contains('충덕스카우트'));
    });

    test('인원 표는 그대로 8명 · 배타 집계 유지(회귀 방지)', () {
      final d = run()[SettlementBlock.attendees]!;
      final bd = EventAttendeeBreakdown.fromAttendees(_realRoster());
      expect(bd.headCount, 8);
      expect(bd.rawItemSum, 8);
      expect(bd.isConsistent, isTrue);
      expect(d.note, contains('합계 8'));
    });
  });
}
