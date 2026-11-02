/// 인가 연도 정규화 · 연도 검색 회귀 테스트
///
/// ## [요구 2026-11-03]
///   "19980년 인가자 / 19710년 인가자 / 1927년 인가자 / 1957년 인가자"
///   "통합검색추가: 2000년인가자 -> 2000년 인가자 처럼 해당연도 인가자 검색"
///
/// 통계 화면에 `19980년` `19710년` 이 찍히던 원인은 **입력 오타**였고,
/// 코드가 그 오타를 연도로 그대로 읽고 있었다. 두 가지를 함께 고정한다.
///   ① `Member.credYear` — 4자리 정규화 + 2자리 연도 + 5자리 오타 흡수
///   ② `AiQuery.parseCredYear` — '2000년인가자' → '2000'
///   ③ `AppState` — 통계(`yearDistribution`)와 검색이 같은 함수를 쓰는지
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/ai_query.dart';

/// 테스트용 최소 회원 — date 만 바꿔가며 쓴다.
Member _m(String date, {String number = '1', String corps = 'tsak'}) {
  return Member.fromMap({
    'corps': corps,
    'number': number,
    'name': '테스트$number',
    'date': date,
  });
}

void main() {
  group('Member.credYear — 오타 흡수 (요구 원문의 4개 연도)', () {
    // ── 실제 NAS 데이터에서 발견된 오타 5건 ────────────────────────────
    test('#658 김영훈  \'19980-6-30\'  → 1998 (19980년 아님)', () {
      expect(_m('19980-6-30', number: '658').credYear, 1998);
      expect(_m('19980-6-30', number: '658').credYearLabel, '1998년');
    });

    test('#69 이한진  \'19710-9-13\'  → 1971 (19710년 아님)', () {
      expect(_m('19710-9-13', number: '69').credYear, 1971);
    });

    test('#875 전명호  \'03.3.11\'  → 2003 (2자리 연도)', () {
      expect(_m('03.3.11', number: '875').credYear, 2003);
    });

    test('#1290 정은진  \'09-12-28-\'  → 2009 (2자리 + 뒤 하이픈)', () {
      expect(_m('09-12-28-', number: '1290').credYear, 2009);
    });

    test('#1291 정혜옥  \'09-12-28-\'  → 2009', () {
      expect(_m('09-12-28-', number: '1291').credYear, 2009);
    });
  });

  group('Member.credYear — 정상 데이터', () {
    test('#1 김용우 \'1927-09-01\' → 1927', () {
      expect(_m('1927-09-01', number: '1').credYear, 1927);
    });

    test('#2 노경하 \'1957-05-10\' → 1957', () {
      expect(_m('1957-05-10', number: '2').credYear, 1957);
    });

    test('#3 서인식 \'1957-05-12\' → 1957', () {
      expect(_m('1957-05-12', number: '3').credYear, 1957);
    });

    test('점 표기 \'1994.03.15\' → 1994', () {
      expect(_m('1994.03.15').credYear, 1994);
    });

    test('슬래시 표기 \'2000/05/20\' → 2000', () {
      expect(_m('2000/05/20').credYear, 2000);
    });

    test('2026 경계 → 2026', () {
      expect(_m('2026-01-05').credYear, 2026);
    });
  });

  group('Member.credYear — 2자리 연도 세기 판정 (30 기준)', () {
    test('\'29.12.31\' → 2029 (00~29 는 2000년대)', () {
      expect(_m('29.12.31').credYear, 2029);
    });

    test('\'30.01.01\' → 1930 (30~99 는 1900년대)', () {
      expect(_m('30.01.01').credYear, 1930);
    });

    test('\'99.5.5\' → 1999', () {
      expect(_m('99.5.5').credYear, 1999);
    });
  });

  group('Member.credYear — 읽을 수 없으면 0', () {
    test('빈 문자열 → 0', () {
      expect(_m('').credYear, 0);
      expect(_m('').credYearLabel, '');
    });

    test('공백만 → 0', () {
      expect(_m('   ').credYear, 0);
    });

    test('\'미상\' → 0', () {
      expect(_m('미상').credYear, 0);
    });
  });

  group('Member.searchText — 연도 토큰 포함', () {
    test('\'2000년\' 부분문자열로 찾을 수 있다', () {
      final m = _m('2000-05-20');
      expect(m.searchText.contains('2000년'), isTrue);
      // '2000' 만 쳐도 걸린다.
      expect(m.searchText.contains('2000'), isTrue);
    });

    test('오타 데이터도 정규화된 연도로 검색된다 (\'1998년\')', () {
      final m = _m('19980-6-30', number: '658');
      expect(m.searchText.contains('1998년'), isTrue);
      // 깨진 표기 '19980년' 으로는 걸리지 않아야 한다.
      expect(m.searchText.contains('19980년'), isFalse);
    });
  });

  group('AiQuery.parseCredYear — 연도 표기 해석', () {
    test('\'2000년인가자\' → 2000', () {
      expect(AiQuery.parseCredYear('2000년인가자'), '2000');
    });

    test('\'2000년 인가자\' → 2000', () {
      expect(AiQuery.parseCredYear('2000년 인가자'), '2000');
    });

    test('\'2000년\' → 2000', () {
      expect(AiQuery.parseCredYear('2000년'), '2000');
    });

    test('\'2000년도 인가자\' → 2000', () {
      expect(AiQuery.parseCredYear('2000년도 인가자'), '2000');
    });

    test('맨숫자 \'2000\' → 2000', () {
      expect(AiQuery.parseCredYear('2000'), '2000');
    });

    test('\'1927년 인가자\' → 1927', () {
      expect(AiQuery.parseCredYear('1927년 인가자'), '1927');
    });

    test('\'1957년 인가자\' → 1957', () {
      expect(AiQuery.parseCredYear('1957년 인가자'), '1957');
    });

    test('오타 \'19980년 인가자\' → 1998 (앞 4자리)', () {
      expect(AiQuery.parseCredYear('19980년 인가자'), '1998');
    });

    test('오타 \'19710년 인가자\' → 1971 (앞 4자리)', () {
      expect(AiQuery.parseCredYear('19710년 인가자'), '1971');
    });

    test('범위검색 \'1990-2000\' 은 연도검색이 아니다 → null', () {
      expect(AiQuery.parseCredYear('1990-2000'), isNull);
    });

    test('연도 없음 \'김철수\' → null', () {
      expect(AiQuery.parseCredYear('김철수'), isNull);
    });

    test('전화번호 \'01012345678\' → 연도로 오인하지 않는다', () {
      final y = AiQuery.parseCredYear('01012345678');
      // 8자리 연속 숫자 안에 든 4자리를 연도로 뽑지 않는다(?<!\d)(?!\d)).
      expect(y, isNull);
    });
  });

  group('AiQuery.tryParse — 연도 인가 의도 승격', () {
    test('\'2000년인가자\' → AiKind.credYear', () {
      final ai = AiQuery.tryParse('2000년인가자');
      expect(ai, isNotNull);
      expect(ai!.kind, AiKind.credYear);
      expect(ai.year, '2000');
    });

    test('\'19710년 인가자\' → credYear 1971', () {
      final ai = AiQuery.tryParse('19710년 인가자');
      expect(ai, isNotNull);
      expect(ai!.kind, AiKind.credYear);
      expect(ai.year, '1971');
    });

    test('\'2026년 연회비 납부자\' 는 연도검색으로 뺏지 않는다 (연회비 우선)', () {
      final ai = AiQuery.tryParse('2026년 연회비 납부자');
      expect(ai, isNotNull);
      expect(ai!.kind, AiKind.feePaid);
      expect(ai.year, '2026');
    });

    test('label \'2000년 인가자\'', () {
      expect(AiQuery.tryParse('2000년인가자')!.label, '2000년 인가자');
    });
  });

  group('소스 계약 — 통계와 검색이 같은 정규화 함수를 쓰는지', () {
    final appState = File('lib/services/app_state.dart').readAsStringSync();
    final stats = File('lib/screens/stats_screen.dart').readAsStringSync();

    test('yearDistribution 이 m.credYear 를 쓴다 (19980년 버그 재발 방지)', () {
      expect(appState.contains('final y = m.credYear;'), isTrue);
      // 종전 버그 패턴이 남아 있으면 안 된다.
      expect(
        appState.contains(
          "int.tryParse(m.date.replaceAll('.', '-').split('-').first)",
        ),
        isFalse,
      );
    });

    test('_applyAiQuery 에 AiKind.credYear 케이스가 있다', () {
      expect(appState.contains('case AiKind.credYear:'), isTrue);
    });

    test('은하 연도 통계도 m.credYear 를 쓴다', () {
      expect(stats.contains('final y = m.credYear;'), isTrue);
    });

    test('통계 섹션 제목에 하드코딩된 (2004~2025) 가 없다', () {
      expect(stats.contains('연도별 인가 현황 (2004~2025)'), isFalse);
      expect(stats.contains('연도별 인가 현황'), isTrue);
    });
  });
}
