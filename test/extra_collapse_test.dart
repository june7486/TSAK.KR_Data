// 참가자 카드 "접어두기" 회귀 검증.
//
// ## 요구 (원문 2026-10-31 5차)
// > "접어두기 버튼 추가"
//
// ## 왜 필요한가 (스크린샷 uaCVpcss)
//  추가입력 8항목이 카드 한 장을 다 먹어, 5명만 넘어도 명부가 안 보였다.
//  → 카드마다 [추가입력 N항목 ▾] 한 줄로 접고, 필요할 때만 편다.
//
// ## 검증 포인트
//  ① 접힘 키는 **인덱스가 아니라 참가자 식별자** — 삭제·새로고침 후에도
//     엉뚱한 사람에게 접힘이 붙지 않는다.
//  ② 전달사항(request)은 접어도 **한 줄은 남는다**(놓치면 현장 사고).
//  ③ '전부 접기/펼치기' 판정이 정확하다.
//  ④ G 접두(은하) 번호가 일반 번호와 섞이지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/extra_fields.dart';

/// [event_detail_screen.dart] 의 `_attendeeKey` 와 **동일한 규칙**.
/// (화면 state 없이 검증하기 위해 같은 로직을 여기에 옮겨 적었다)
String attendeeKey(Map<String, dynamic> a, List<Map<String, dynamic>> all) {
  final raw = '${a['number'] ?? a['ident'] ?? a['phone'] ?? ''}';
  var s = raw.trim().toUpperCase().replaceAll('은하', 'G');
  s = s.replaceAll('범', '').replaceAll(RegExp(r'[^0-9G]'), '');
  if (s.isNotEmpty) {
    final isG = s.startsWith('G');
    final d = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isNotEmpty) return isG ? 'G$d' : d;
  }
  final nm = '${a['name'] ?? ''}'.trim();
  return nm.isEmpty ? 'row-${all.indexOf(a)}' : 'nm:$nm';
}

/// 접힌 카드에 남길 "값 요약" — 비어 있는 값은 빼고 ' · ' 로 잇는다.
String collapsedSummary(Map<String, dynamic> a) => ExtraFields.filled(a)
    .map((f) => f.valueOf(a))
    .where((v) => v.trim().isNotEmpty)
    .join(' · ');

void main() {
  group('① 접힘 키 — 참가자 식별자', () {
    test('번호가 있으면 번호만 남긴다(구분기호 제거)', () {
      expect(attendeeKey({'number': '범#75'}, const []), '75');
      expect(attendeeKey({'number': '010-3590-2280'}, const []), '01035902280');
    });

    test('[중요] 은하(G) 접두가 보존된다 — 범 75 와 은하 75 는 다른 사람', () {
      expect(attendeeKey({'number': 'G75'}, const []), 'G75');
      expect(attendeeKey({'number': '75'}, const []), '75');
      expect(
        attendeeKey({'number': 'G75'}, const []),
        isNot(attendeeKey({'number': '75'}, const [])),
        reason: '번호 공간이 겹치므로 접두를 지우면 접힘이 뒤바뀐다',
      );
      expect(attendeeKey({'number': '은하75'}, const []), 'G75');
    });

    test('번호가 없으면 이름, 이름도 없으면 행 위치로 폴백', () {
      expect(attendeeKey({'name': '홍길동'}, const []), 'nm:홍길동');
      final all = <Map<String, dynamic>>[
        {'name': ''},
        {'name': ''},
      ];
      expect(attendeeKey(all[0], all), 'row-0');
      expect(attendeeKey(all[1], all), 'row-1');
    });

    test('키 충돌이 없다 — 20명이 모두 서로 다른 키를 갖는다', () {
      final rows = <Map<String, dynamic>>[
        for (var i = 1; i <= 10; i++) {'number': '$i', 'name': '범$i'},
        for (var i = 1; i <= 10; i++) {'number': 'G$i', 'name': '은하$i'},
      ];
      final keys = rows.map((r) => attendeeKey(r, rows)).toSet();
      expect(keys.length, 20);
    });
  });

  group('② 접힌 카드의 한 줄 요약', () {
    test('값이 있는 항목만 이어 붙인다', () {
      final a = <String, dynamic>{
        'name': '이항복',
        'transport': '대중교통',
        'lodging': '숙박',
        'arrive': '점심',
        'from': '광주',
        'eta': '5시간',
        'companion': '없음',
        'address': '서울 강남구 언주로 151',
      };
      final s = collapsedSummary(a);
      expect(s, isNotEmpty);
      expect(s, contains('대중교통'));
      expect(s, contains('서울 강남구 언주로 151'));
      // 구분자는 ' · ' 하나로 통일 — 항목 개수 - 1 개.
      expect(ExtraFields.filled(a).length, 7);
      expect(' · '.allMatches(s).length, 6);
    });

    test('전달사항은 접어도 따로 강조해 남긴다', () {
      final a = <String, dynamic>{
        'transport': '자차',
        'message': '견과류 알레르기 있음',
      };
      final req = ExtraFields.filled(
        a,
      ).where((f) => f.group == ExtraGroup.request).toList();
      expect(req.length, 1);
      expect(req.first.valueOf(a), '견과류 알레르기 있음');
      // 요약줄에도 값은 들어간다(정보 손실 0).
      expect(collapsedSummary(a), contains('견과류 알레르기 있음'));
    });

    test('추가입력이 하나도 없으면 요약은 빈 문자열', () {
      expect(collapsedSummary({'name': '김승수'}), '');
    });
  });

  group('③ 전체 접기/펼치기 판정', () {
    final rows = <Map<String, dynamic>>[
      {'number': '1', 'transport': '자차'},
      {'number': '2', 'lodging': '숙박'},
    ];
    final keys = rows.map((r) => attendeeKey(r, rows)).toList();

    test('하나라도 펼쳐져 있으면 → 전부 접기 대상', () {
      final collapsed = <String>{keys[0]}; // 1번만 접힘
      final anyOpen = rows.any((a) {
        if (ExtraFields.filled(a).isEmpty) return false;
        return !collapsed.contains(attendeeKey(a, rows));
      });
      expect(anyOpen, isTrue);
    });

    test('전부 접혀 있으면 → 전부 펼치기 대상', () {
      final collapsed = <String>{...keys};
      final anyOpen = rows.any((a) {
        if (ExtraFields.filled(a).isEmpty) return false;
        return !collapsed.contains(attendeeKey(a, rows));
      });
      expect(anyOpen, isFalse);
    });

    test('추가입력이 없는 참가자는 접기 판정에서 빠진다', () {
      final mixed = <Map<String, dynamic>>[
        {'number': '1', 'transport': '자차'},
        {'number': '2'}, // 추가입력 없음
      ];
      final collapsed = <String>{};
      final anyOpen = mixed.any((a) {
        if (ExtraFields.filled(a).isEmpty) return false;
        return !collapsed.contains(attendeeKey(a, mixed));
      });
      expect(anyOpen, isTrue); // 1번만 열려 있어도 true
      expect(ExtraFields.filled(mixed[1]), isEmpty);
    });
  });

  group('④ 접힘 상태는 삭제 후에도 유효하다', () {
    test('2번을 지워도 1·3번의 접힘 상태가 유지된다', () {
      final before = <Map<String, dynamic>>[
        {'number': '1', 'transport': '자차'},
        {'number': '2', 'transport': '대중교통'},
        {'number': '3', 'transport': '기타'},
      ];
      // 1·3 만 접어 둔 상태
      final collapsed = <String>{
        attendeeKey(before[0], before),
        attendeeKey(before[2], before),
      };
      final after = <Map<String, dynamic>>[before[0], before[2]];
      // 인덱스 기반이었다면 3번이 1번 자리로 밀려 상태가 뒤바뀐다.
      expect(collapsed.contains(attendeeKey(after[0], after)), isTrue);
      expect(collapsed.contains(attendeeKey(after[1], after)), isTrue);
    });
  });
}
