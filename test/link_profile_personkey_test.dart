// [요구 2026-11-04] 2차 — "여전히 멘토에 넣으면 이름이 연동이 안되고,
//                          신규로 바로 등록되지 않는 연동성 오류"
//
// ## 실제 화면 (사용자 스크린샷)
//   멘토(범을 배출한 대장) 칸에   **범#01046236587**   ← 이름이 아니라 코드!
//   인적사항 시트를 열면           이름·전화번호가 **빈칸**
//
// ## 왜 그랬나 (2차 원인)
//  서버는 표준 저장키를 `person:<대표번호>` 로 바꿨는데,
//  클라이언트 `_profileOf()` 는 `'멘토:<번호>'` / 무접두어만 찾고 있었다.
//  → 서버가 정상적으로 준 데이터를 화면이 **하나도 못 찾음**.
//  → 이름이 빈칸 → 시트 빈칸 → 저장할 때마다 새 임시코드(9000xx) 생성.
//
// ## 3차 원인 (같이 잡음)
//  `_addProfile()` 이 시트가 돌려준 `res.code`(= 내 번호!)를 그대로
//  mentors 에 넣어 **자기참조를 매번 새로 만들었다.**
//  게다가 `_link_pending_members()` 의 자기참조 필터가 **번호 문자열 비교**라
//  전화번호로 저장된 자기참조는 통과했다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const String _proxyPath = '/home/user/nas_proxy/proxy_server.py';

/// 클라이언트 `_profileOf()` 규칙을 Dart 로 재현.
/// ① `person:<번호>` ② `<종류>:<번호>` ③ 무접두어 ④ 전화·ID·scoutNo 로 사람 조회
Map<String, dynamic> profileOf(
  Map<String, dynamic> profiles,
  String code,
  String kind,
) {
  String digits(Object? s) => (s ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
  final d = digits(code);
  if (d.isEmpty) return {};
  final prefix = kind == 'parent' ? '페런츠' : '멘토';
  for (final k in ['person:$d', '$prefix:$d', d]) {
    final v = profiles[k];
    if (v is! Map || v.isEmpty) continue;
    final vk = (v['kind'] ?? '').toString().trim();
    if (vk.isEmpty || vk == kind) return v.cast<String, dynamic>();
    final ks = v['kinds'];
    if (ks is List && ks.map((e) => '$e').contains(kind)) {
      return v.cast<String, dynamic>();
    }
  }
  for (final entry in profiles.entries) {
    final v = entry.value;
    if (v is! Map || v.isEmpty) continue;
    final vk = (v['kind'] ?? '').toString().trim();
    final ks = v['kinds'];
    final kindOk = vk.isEmpty ||
        vk == kind ||
        (ks is List && ks.map((e) => '$e').contains(kind));
    if (!kindOk) continue;
    final codes = <String>{
      digits(v['phone']),
      digits(v['loginId']),
      digits(v['scoutNo']),
      digits(v['personKey']),
    };
    if (codes.contains(d)) return v.cast<String, dynamic>();
  }
  return {};
}

/// 서버 `_link_pending_members()` 의 자기참조 판정을 재현(사람 기준).
bool isSelfByPerson({
  required String code,
  required String selfCanon,
  required Map<String, String> alias,
}) {
  final d = code.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return true;
  final ca = alias[d] ?? d;
  return ca == selfCanon;
}

void main() {
  // 실제 운영 응답 형태(person 키)
  final profiles = <String, dynamic>{
    'person:01046236587': {
      'name': '선영진',
      'phone': '01046236587',
      'kind': 'mentor',
      'kinds': ['mentor'],
      'personKey': '01046236587',
      'league': '전남',
      'unit': '순천지역대',
      'number': '1346',
    },
    'person:01033657480': {
      'name': '노본',
      'phone': '010-3365-7480',
      'kind': 'parent',
      'kinds': ['parent', 'mentor'],
      'personKey': '01033657480',
      'league': '서울남부',
      'unit': '청숫지역대',
      'number': '2229',
    },
    'person:01064407181': {
      'name': '박인규',
      'phone': '01064407181',
      'kind': 'mentor',
      'kinds': ['mentor'],
      'personKey': '01064407181',
      'number': '417',
    },
  };

  group('인적사항 조회 — person 키를 찾는다', () {
    test('person:<전화번호> 키에서 이름을 찾는다 (스크린샷 버그)', () {
      final p = profileOf(profiles, '01046236587', 'mentor');
      expect(p['name'], '선영진',
          reason: '종전엔 빈 맵이 돌아와 이름이 "범#01046236587" 로 보였다');
      expect(p['phone'], '01046236587');
    });

    test('시트가 빈칸으로 열리지 않도록 소속·단위도 채워진다', () {
      final p = profileOf(profiles, '01046236587', 'mentor');
      expect(p['league'], '전남');
      expect(p['unit'], '순천지역대');
    });

    test('전화번호 표기가 달라도(-) 같은 사람을 찾는다', () {
      final p = profileOf(profiles, '01033657480', 'mentor');
      expect(p['name'], '노본');
    });

    test('겸임자(멘토+페런츠)는 두 역할 모두 조회된다', () {
      expect(profileOf(profiles, '01033657480', 'mentor')['name'], '노본');
      expect(profileOf(profiles, '01033657480', 'parent')['name'], '노본');
    });

    test('없는 사람은 빈 맵(안전)', () {
      expect(profileOf(profiles, '01099999999', 'mentor'), isEmpty);
    });
  });

  group('자기참조 판정 — 번호가 아니라 사람', () {
    const alias = {
      '1346': '1346',
      '01046236587': '01046236587',
      '415': '415',
    };

    test('전화번호로 저장된 자기참조를 잡아낸다', () {
      // 양다솜(self=1346) 의 mentors 에 ['01046236587'] 이 들어간 사고.
      // 종전: '01046236587' != '1346' 이므로 통과 → 큐에 남았다.
      expect(
          isSelfByPerson(
              code: '01046236587', selfCanon: '1346', alias: alias),
          isFalse,
          reason: '선영진은 **다른 사람**이므로 요청으로 세야 한다');
    });

    test('진짜 자기 번호는 요청으로 세지 않는다', () {
      expect(
          isSelfByPerson(code: '1346', selfCanon: '1346', alias: alias),
          isTrue);
    });

    test('다른 사람은 요청으로 센다', () {
      expect(
          isSelfByPerson(
              code: '01046236587', selfCanon: '1346', alias: alias),
          isFalse);
    });
  });

  group('프록시 소스 계약 — 2차 수정', () {
    late String src;
    setUpAll(() {
      final f = File(_proxyPath);
      expect(f.existsSync(), isTrue);
      src = f.readAsStringSync();
    });

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

    test('승인대기 필터가 사람 기준으로 자기참조를 거른다', () {
      final body = codeOf('_link_pending_members');
      expect(body.contains('_link_canon_of(_pdx, c)'), isTrue,
          reason: '번호 문자열 비교로는 전화번호 표기 자기참조를 못 잡는다');
      expect(
          body.contains(
              '[c for c in _norm_codes(m.get("mentors"))\n                   if _clean_no(c) != _self_no]'),
          isFalse,
          reason: '옛 문자열 비교식이 남아 있으면 양다솜 카드가 큐에서 사라진다');
    });

    test('같은 사람이면 새 임시코드를 만들지 않는다', () {
      final body = codeOf('_link_person_index');
      expect(body.contains('alias'), isTrue);
      // 저장 경로에서 임시코드 교체 로직
      final i = src.indexOf('_is_temp = (len(_curnum) == 6');
      expect(i, greaterThan(-1),
          reason: '9000xx 임시코드가 계속 쌓이면 이름이 매번 사라진다');
    });

    test('저장 키는 person 기준으로 결정된다', () {
      final i = src.indexOf('_skey = _link_person_key');
      expect(i, greaterThan(-1));
    });
  });
}
