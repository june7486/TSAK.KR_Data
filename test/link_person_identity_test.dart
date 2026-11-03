// [요구 2026-11-04] 링크 구조 표준화 검증
//
// 사용자 지시(원문)
//   1. 채워                        ← 기존 link_profiles 미연동 back-fill
//   2. 구조변경해서 앞으로의 구조를 더 탄탄하게
//   3. 자기참조 6건도 정리해줘
//   4. 멘토0, 이멘토, 01000000001 모두 삭제
//
// ## 무엇이 근본 원인이었나 (운영 DB 실측)
//  ① 코드 한 칸에 **여러 뜻**이 섞여 있었다.
//       멘토 칸  : 값이 '멘티의 링크프로필 번호'  → 멘토 본인 코드가 아님
//       페런츠 칸: 값이 '자녀 인가번호'          → 부모 본인 코드가 아님
//  ② 역방향 연동이 `c in cred_no` 조건 때문에 **인가자에게만** 동작.
//       비인가 멘토(선영진·박인규·노본)는 mentees 를 영영 못 받았다.
//  ③ link_profiles 키가 '종류:자녀번호' 라서, 멘토·페런츠가 같은 번호를 쓰면
//       (노본 2229) 같은 사람이 두 키로 갈라지고 전화번호로는 못 찾았다.
//  ④ 자기참조 판정이 '번호 문자열 비교'뿐이라 전화번호 저장값은 통과했다.
//
// ## 새 기준
//   · 인물(person) : 고유키 canon = 대표 전화번호(없으면 인가번호)
//   · 인물 코드    : 전화번호 · 인가번호 · 로그인ID · scoutNo 를 **같은 사람**으로
//   · 관계 값      : 반드시 **상대 인물의 코드**
//   · 자기참조     : 사람(canon) 비교로 차단
//   · 프로필 키    : 'person:<대표번호>' (옛 키는 읽기 폴백, 쓰기에서만 이관)
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const String _proxyPath = '/home/user/nas_proxy/proxy_server.py';

/// 서버의 `_link_canon_code` 규칙을 Dart 로 재현.
/// 인가자면 인가번호, 일반회원·비인가면 전화번호.
String stdCode({
  required bool isRegular,
  required String number,
  required String phone,
}) {
  String d(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
  if (isRegular) {
    final p = d(phone);
    return p.isNotEmpty ? p : d(number);
  }
  final n = d(number);
  return n.isNotEmpty ? n : d(phone);
}

/// `_link_normalize_codes` 를 재현 — 사람 기준 자기참조 제거 + 중복 제거.
List<String> normalizeCodes(
  List<String> codes, {
  required String selfCanon,
  required Map<String, String> codeToCanon,
}) {
  final out = <String>[];
  for (final c in codes) {
    final d = c.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) continue;
    final ca = codeToCanon[d] ?? d;
    if (ca == selfCanon) continue;
    if (!out.contains(d)) out.add(d);
  }
  return out;
}

void main() {
  group('표준 코드 규칙', () {
    test('인가자는 인가번호로 저장한다', () {
      expect(stdCode(isRegular: false, number: '1346', phone: '01092188514'),
          '1346');
    });

    test('일반회원·비인가는 전화번호로 저장한다', () {
      // 선영진 — 자동가입 계정이라 인가번호가 없다.
      expect(stdCode(isRegular: true, number: '', phone: '01046236587'),
          '01046236587');
    });

    test('인가번호가 비어도 전화번호로 안정적으로 떨어진다', () {
      expect(stdCode(isRegular: false, number: '', phone: '01046236587'),
          '01046236587');
    });
  });

  group('자기참조 차단 — 사람 기준', () {
    const alias = {
      '1346': '1346',
      '01046236587': '01046236587',
      '415': '415',
      '01064407181': '01064407181',
    };

    test('자기 인가번호는 제거된다', () {
      final r = normalizeCodes(['415', '1089'],
          selfCanon: '415', codeToCanon: alias);
      expect(r, ['1089']);
    });

    test('전화번호 표기의 자기참조도 제거된다 (양다솜 사고)', () {
      // 종전: mentors=['1346'] 이 문자열 비교로는 통과해 자기참조가 남았다.
      final r = normalizeCodes(['1346', '01046236587'],
          selfCanon: '1346', codeToCanon: alias);
      expect(r, ['01046236587']);
    });

    test('같은 사람이 두 표기로 있어도 하나만 남는다', () {
      final r = normalizeCodes(['415', 'tiger415', '415'],
          selfCanon: '9999', codeToCanon: alias);
      expect(r, ['415']);
    });

    test('빈 값은 무시한다', () {
      final r = normalizeCodes(['', '  ', '1089'],
          selfCanon: '415', codeToCanon: alias);
      expect(r, ['1089']);
    });
  });

  group('프록시 소스 계약 — 인물 색인', () {
    late String src;
    setUpAll(() {
      final f = File(_proxyPath);
      expect(f.existsSync(), isTrue);
      src = f.readAsStringSync();
    });

    /// 모듈 레벨 함수 1개 본문만(다음 top-level `def ` 직전까지), docstring·주석 제거.
    String codeOf(String fnName) {
      final start = src.indexOf('def $fnName(');
      expect(start, greaterThan(-1), reason: '$fnName 함수를 찾지 못했다');
      final rest = src.substring(start + 4);
      final mt = RegExp(r'\ndef (?! )').firstMatch(rest);
      var body = mt == null ? rest : rest.substring(0, mt.start);
      body = body.replaceAll(RegExp(r'"""[\s\S]*?"""'), '');
      return body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
    }

    test('인물 색인 함수가 존재한다', () {
      expect(src.contains('def _link_person_index('), isTrue);
      expect(src.contains('def _link_canon_of('), isTrue);
      expect(src.contains('def _link_canon_code('), isTrue);
      expect(src.contains('def _link_normalize_codes('), isTrue);
    });

    test('표준 저장키 접두어는 person 이다', () {
      expect(src.contains('_LINK_PERSON_KEY_PREFIX = "person"'), isTrue);
      expect(src.contains('"%s:%s" % (_LINK_PERSON_KEY_PREFIX, c)'), isTrue);
    });

    test('인가자만 역방향을 채우던 cred_no 결함이 사라졌다', () {
      final body = codeOf('_link_reconcile_apply');
      // 종전 조건: `if c in cred_no and c != self_no:`  → 비인가 멘토 누락
      expect(body.contains('if c in cred_no and c != self_no'), isFalse,
          reason: '인가자 한정 조건이 남아 있으면 비인가 멘토 mentees 가 또 비어버린다');
      expect(body.contains('_link_person_index()'), isTrue,
          reason: '사람 기준으로 판정해야 한다');
    });

    test('자기참조 정리가 네 관계 필드를 모두 본다', () {
      final body = codeOf('_link_reconcile_apply');
      expect(
          body.contains(
              'for field in ("mentors", "parents", "mentees", "children")'),
          isTrue,
          reason: 'mentors/parents 를 빼면 승인요청이 계속 되살아난다(차동엽 사고)');
    });

    test('카드 없는 비인가 멘토도 역방향을 기록한다', () {
      final body = codeOf('_link_reconcile_apply');
      expect(body.contains('changed_nocard'), isTrue,
          reason: 'members 카드가 없으면 버리던 동작을 없애야 한다');
      expect(body.contains('_link_profiles_save(_profs)'), isTrue);
    });

    test('읽기(load)는 데이터를 변형하지 않는다', () {
      final body = codeOf('_link_profiles_load');
      expect(body.contains('_link_profile_migrate_keys'), isFalse,
          reason: '읽기에서 이관하면 역할 정보가 소실된다(노본·현승용 사고)');
      expect(body.contains('_save_json'), isFalse);
    });

    test('쓰기(save)에서만 표준 키로 이관한다', () {
      final body = codeOf('_link_profiles_save');
      expect(body.contains('_link_profile_migrate_keys(d)'), isTrue);
    });

    test('역할(kinds)은 키 출처로 판정한다', () {
      final body = codeOf('_link_profile_migrate_keys');
      expect(body.contains('_all_kinds'), isTrue,
          reason: 'dict.kind 만 믿으면 멘토+페런츠 겸임자의 한 역할이 사라진다');
      expect(body.contains('relationNumbers'), isTrue,
          reason: '옛 키가 담고 있던 상대 번호를 보존해야 한다');
    });

    test('개별 저장은 상대 인물 코드를 쓴다', () {
      final body = codeOf('_link_apply_mentor_links');
      expect(body.contains('_link_canon_code(_pdx, mentor_id)'), isTrue);
      expect(body.contains('_link_canon_code(_pdx, mentee_no)'), isTrue);
      expect(body.contains('approvalStatus'), isFalse,
          reason: '승인은 계정 승인에서 한 번만 받는다');
    });
  });
}
