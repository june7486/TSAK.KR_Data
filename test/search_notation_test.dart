// 검색 표기 해석 회귀 테스트 (build #579)
//
// 요구(원문 2026-11-02):
//   "검색기능: 범스카우 번호, 예를들면 범415 로 검색해도 검색결과가 안나옴,
//    은하19호 같이 검색해도 은하스카우트가 안 나옴"
//
// 원인: `_applyQuery` 의 일반 검색이 `m.searchText.contains(p)` **부분 문자열**
//   비교였다. `searchText` 에는 '415' 와 '범' 이 따로 있어 '범415' 연속 문자열이
//   존재하지 않는다 → 구조적으로 매칭 불가.
//
// 이 테스트는 (1) 순수 파서 `SearchQuery` 의 해석 결과와
//            (2) `_applyQuery` 안에 해석 분기가 실제로 심어졌는지(소스 계약)
// 를 함께 고정한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/ai_query.dart';
import 'package:tsak_credential_manager/services/search_query.dart';

void main() {
  group('SearchQuery.parse — 소속+번호 붙여쓰기', () {
    test('범415 → tsak 415', () {
      final s = SearchQuery.parse('범415');
      expect(s.corps, 'tsak');
      expect(s.number, 415);
      expect(s.tokens, isEmpty);
      expect(s.isNotation, isTrue);
    });

    test('범 415 (공백) → tsak 415', () {
      final s = SearchQuery.parse('범 415');
      expect(s.corps, 'tsak');
      expect(s.number, 415);
    });

    test('범415호 → tsak 415', () {
      final s = SearchQuery.parse('범415호');
      expect(s.corps, 'tsak');
      expect(s.number, 415);
    });

    test('은하19호 → eunha 19', () {
      final s = SearchQuery.parse('은하19호');
      expect(s.corps, 'eunha');
      expect(s.number, 19);
      expect(s.isNotation, isTrue);
    });

    test('은하 19 → eunha 19', () {
      final s = SearchQuery.parse('은하 19');
      expect(s.corps, 'eunha');
      expect(s.number, 19);
    });

    test('은하19 (호 없이) → eunha 19', () {
      final s = SearchQuery.parse('은하19');
      expect(s.corps, 'eunha');
      expect(s.number, 19);
    });

    test('은하스카우트 19호 / 범스카우트 415 — 긴 단어 우선', () {
      expect(SearchQuery.parse('은하스카우트 19호').corps, 'eunha');
      expect(SearchQuery.parse('은하스카우트 19호').number, 19);
      expect(SearchQuery.parse('범스카우트 415').corps, 'tsak');
      expect(SearchQuery.parse('범스카우트 415').number, 415);
    });

    test('G19 / g-19 / G#19 → eunha 19', () {
      for (final q in ['G19', 'g19', 'g-19', 'G#19', 'G19호']) {
        final s = SearchQuery.parse(q);
        expect(s.corps, 'eunha', reason: q);
        expect(s.number, 19, reason: q);
      }
    });

    test('갤럭시19 / galaxy19 / eunha19 → eunha 19', () {
      for (final q in ['갤럭시19', 'galaxy19', 'eunha19']) {
        final s = SearchQuery.parse(q);
        expect(s.corps, 'eunha', reason: q);
        expect(s.number, 19, reason: q);
      }
    });

    test('tsak415 → tsak 415', () {
      final s = SearchQuery.parse('tsak415');
      expect(s.corps, 'tsak');
      expect(s.number, 415);
    });
  });

  group('SearchQuery.parse — 소속만 / 번호만', () {
    test("'은하' 단독 → eunha, 번호 없음", () {
      final s = SearchQuery.parse('은하');
      expect(s.corps, 'eunha');
      expect(s.number, isNull);
      expect(s.isNotation, isTrue);
    });

    test("'범' 단독 → tsak, 번호 없음", () {
      final s = SearchQuery.parse('범');
      expect(s.corps, 'tsak');
      expect(s.number, isNull);
    });

    test('맨숫자 415 → 번호만(소속 미지정)', () {
      final s = SearchQuery.parse('415');
      expect(s.corps, isEmpty);
      expect(s.number, 415);
    });

    test('#415 → 번호만', () {
      final s = SearchQuery.parse('#415');
      expect(s.number, 415);
      expect(SearchQuery.hasNumberNotation('#415'), isTrue);
    });

    test('415호 → 번호 + 표기신호', () {
      expect(SearchQuery.parse('415호').number, 415);
      expect(SearchQuery.hasNumberNotation('415호'), isTrue);
    });

    test('맨숫자는 표기신호가 아니다(지역대명·전화번호 보호)', () {
      expect(SearchQuery.hasNumberNotation('415'), isFalse);
    });
  });

  group('SearchQuery.parse — 소속 + 이름 키워드', () {
    test('은하 이승 → eunha, 토큰 [이승]', () {
      final s = SearchQuery.parse('은하 이승');
      expect(s.corps, 'eunha');
      expect(s.number, isNull);
      expect(s.tokens, contains('이승'));
    });

    test('범 영남 12 → tsak 12, 토큰 [영남]', () {
      final s = SearchQuery.parse('범 영남 12');
      expect(s.corps, 'tsak');
      expect(s.number, 12);
      expect(s.tokens, contains('영남'));
    });

    test("'범위' 같은 단어를 소속으로 오인하지 않는다", () {
      final s = SearchQuery.parse('범위');
      expect(s.corps, isEmpty);
    });

    test('잡음 토큰(스카우트/번호/호)은 키워드에서 제거', () {
      final s = SearchQuery.parse('은하 스카우트 번호 19');
      expect(s.tokens, isEmpty);
      expect(s.number, 19);
    });
  });

  group('SearchQuery.parse — 표기 해석 예외', () {
    test('전화번호는 표기 해석 대상이 아니다', () {
      final s = SearchQuery.parse('010-1234-5678');
      expect(s.isNotation, isFalse);
    });

    test('인가번호 범위(1-100)는 표기 해석 대상이 아니다', () {
      final s = SearchQuery.parse('1-100');
      expect(s.isNotation, isFalse);
    });

    test('평범한 이름은 표기 해석 대상이 아니다', () {
      final s = SearchQuery.parse('이승준');
      expect(s.isNotation, isFalse);
      expect(s.number, isNull);
    });

    test('빈 문자열', () {
      final s = SearchQuery.parse('   ');
      expect(s.isNotation, isFalse);
      expect(s.number, isNull);
    });
  });

  group('SearchQuery.corpsMatches — 은하 19호 ≠ 범 19호', () {
    test('소속 미지정은 모두 통과', () {
      expect(SearchQuery.corpsMatches('', 'tsak'), isTrue);
      expect(SearchQuery.corpsMatches('', 'eunha'), isTrue);
    });

    test('eunha 지목 → 은하만', () {
      expect(SearchQuery.corpsMatches('eunha', 'eunha'), isTrue);
      expect(SearchQuery.corpsMatches('eunha', 'tsak'), isFalse);
    });

    test('tsak 지목 → 은하가 아닌 모두(일반회원 포함)', () {
      expect(SearchQuery.corpsMatches('tsak', 'tsak'), isTrue);
      expect(SearchQuery.corpsMatches('tsak', 'eunha'), isFalse);
      expect(SearchQuery.corpsMatches('tsak', ''), isTrue);
    });
  });

  group('SearchQuery.label', () {
    test('범 415호 / 은하 19호 / 은하', () {
      expect(SearchQuery.parse('범415').label, '범 415호');
      expect(SearchQuery.parse('은하19호').label, '은하 19호');
      expect(SearchQuery.parse('은하').label, '은하');
      expect(SearchQuery.parse('415').label, '인가번호 415');
    });
  });

  group('AiQuery — 표기 질의는 신호어 없이도 해석된다', () {
    test('범415 → credential(tsak, 415)', () {
      final ai = AiQuery.tryParse('범415');
      expect(ai, isNotNull);
      expect(ai!.kind, AiKind.credential);
      expect(ai.corps, 'tsak');
      expect(ai.number, 415);
    });

    test('은하19호 → credential(eunha, 19)', () {
      final ai = AiQuery.tryParse('은하19호');
      expect(ai, isNotNull);
      expect(ai!.kind, AiKind.credential);
      expect(ai.corps, 'eunha');
      expect(ai.number, 19);
    });

    test('G19 → credential(eunha, 19)', () {
      final ai = AiQuery.tryParse('G19');
      expect(ai!.kind, AiKind.credential);
      expect(ai.number, 19);
    });

    test('415호 → credential(번호 표기 신호)', () {
      final ai = AiQuery.tryParse('415호');
      expect(ai!.kind, AiKind.credential);
      expect(ai.number, 415);
    });

    test('맨숫자 415 는 일반 검색에 맡긴다(AI 승격 안 함)', () {
      expect(AiQuery.tryParse('415'), isNull);
    });

    test('전화번호는 AI 승격 안 함', () {
      // 010-1234-5678 은 SearchQuery 도 표기 해석을 포기하고,
      // 신호어도 없다 → 일반 통합검색이 처리한다.
      expect(AiQuery.tryParse('010-1234-5678'), isNull);
    });

    test('신호어 질의는 길이 4 미만이어도 동작한다 (기본기능화)', () {
      final ai = AiQuery.tryParse('회비'); // 2글자
      expect(ai, isNotNull);
      expect(ai!.kind, AiKind.feePaid);
    });

    test('기존 신호어 질의는 그대로 동작 (회귀 방지)', () {
      expect(AiQuery.tryParse('2026년 연회비 납부자 명단')!.kind, AiKind.feePaid);
      expect(AiQuery.tryParse('2026년 연회비 납부자 명단')!.year, '2026');
      expect(AiQuery.tryParse('현재까지 후원자 명단')!.kind, AiKind.donor);
      expect(AiQuery.tryParse('평생회원 명단')!.kind, AiKind.lifetime);
      expect(AiQuery.tryParse('2025 정기총회 참석자 명단')!.kind, AiKind.eventAttend);
    });

    test('아무 신호도 없는 이름은 null (일반 검색 담당)', () {
      expect(AiQuery.tryParse('이승준'), isNull);
      expect(AiQuery.tryParse('영남'), isNull);
    });
  });

  group('소스 계약 — _applyQuery 에 해석 분기가 실제로 심어졌는가', () {
    final src = File('lib/services/app_state.dart').readAsStringSync();

    /// 주석을 걷어낸 실제 코드만 본다(주석에 있는 문자열에 속지 않게).
    String stripComments(String s) => s
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    final code = stripComments(src);
    final applyStart = code.indexOf('List<Member> _applyQuery(');
    final applyBody = applyStart < 0
        ? ''
        : code.substring(applyStart, applyStart + 4200);

    test('_applyQuery 본문에 SearchQuery.parse 호출이 있다', () {
      expect(applyBody.contains('SearchQuery.parse(rawQuery)'), isTrue);
    });

    test('표기 해석 분기가 일반 통합검색보다 **앞에** 있다', () {
      final iNotation = applyBody.indexOf('SearchQuery.parse(rawQuery)');
      final iSubstr = applyBody.indexOf('m.searchText.contains(p)');
      expect(iNotation, greaterThanOrEqualTo(0));
      expect(iSubstr, greaterThanOrEqualTo(0));
      expect(iNotation, lessThan(iSubstr));
    });

    test('번호 비교는 numberInt 로 한다(부분 문자열 아님)', () {
      expect(applyBody.contains('m.numberInt == sq.number'), isTrue);
    });

    test('소속까지 함께 본다(은하 19호 ≠ 범 19호)', () {
      expect(applyBody.contains('SearchQuery.corpsMatches'), isTrue);
    });

    test('AiKind.credential 분기가 _applyAiQuery 에 있다', () {
      expect(code.contains('case AiKind.credential:'), isTrue);
      expect(code.contains('m.numberInt == ai.number'), isTrue);
    });

    test('setQuery 가 은하 표기에서 은하 명단 로드를 건다', () {
      final i = code.indexOf('void setQuery(String q)');
      expect(i, greaterThanOrEqualTo(0));
      final body = code.substring(i, i + 400);
      expect(body.contains('ensureEunhaForSearch()'), isTrue);
      expect(body.contains("SearchQuery.corpsEunha"), isTrue);
    });

    test('searchText 는 이제 **사람 표기**까지 담는다(이중 안전장치)', () {
      final m = File('lib/models/member.dart').readAsStringSync();
      // 맨 숫자뿐 아니라 '범415' 같은 연속 표기도 포함되어야 한다.
      expect(m.contains('searchNotation'), isTrue);
      expect(m.contains(r"'$p$d $p#$d $p $d $d호$g'"), isTrue);
      // 표기가 통합검색 텍스트에 실제로 합쳐지는지
      expect(m.contains(r"'$base$atas$notation'"), isTrue);
    });
  });

  group('Member.searchNotation — 표기 생성 규칙', () {
    test('범 415 → 범415 / 범#415 / 415호', () {
      final m = Member(id: 'a', number: '415', name: '이승준', corps: 'tsak');
      final s = m.searchNotation;
      expect(s.contains('범415'), isTrue);
      expect(s.contains('범#415'), isTrue);
      expect(s.contains('415호'), isTrue);
      expect(s.toLowerCase().contains('g415'), isFalse);
    });

    test('은하 19 → 은하19 / 은하#19 / G19', () {
      final m = Member(id: 'b', number: 'G19', name: '황용규', corps: 'eunha');
      final s = m.searchNotation;
      expect(s.contains('은하19'), isTrue);
      expect(s.contains('은하#19'), isTrue);
      expect(s.contains('G19'), isTrue);
      expect(s.contains('g19'), isTrue);
    });

    test('일반회원은 표기 대상이 아니다(인가번호 없음)', () {
      final m = Member(
        id: 'c',
        number: '01012345678',
        name: '서포터',
        corps: 'tsak',
        isRegular: true,
      );
      expect(m.searchNotation, isEmpty);
    });

    test("'범415' 는 searchText 에 연속 문자열로 존재한다", () {
      final m = Member(id: 'a', number: '415', name: '이승준', corps: 'tsak');
      expect(m.searchText.contains('범415'), isTrue);
    });

    test("'은하19' 는 searchText 에 연속 문자열로 존재한다", () {
      final m = Member(id: 'b', number: 'G19', name: '황용규', corps: 'eunha');
      expect(m.searchText.contains('은하19'), isTrue);
    });
  });
}
