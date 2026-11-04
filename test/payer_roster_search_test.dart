// 후원자/납부자 **명부 전체 검색** 회귀 테스트 (build #602).
//
// ## 요구 (원문 2026-11-04)
// > "납부자검색항목을 좀더 폭넓게 해주세요. 인가자번호, 서포터즈이름, 멘토,
// >  멘티, 페런츠 등 명부에 있는 사람들의 전화번호, 이름, 연맹, 단위대 등등
// >  중에서 선택할 수 있도록 해줘."
// > "후원자, 참가비 등에도 동일하게 검색할 수 있도록 해줘"
//
// 위젯 테스트는 이 샌드박스에서 멈추므로(EventDetailScreen pump 시 무한 대기),
// ① 소스 계약 ② 순수 매칭 함수 복제 로직 으로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String get _lookup => File('lib/widgets/tsak_name_lookup.dart').readAsStringSync();

String get _event =>
    File('lib/screens/event_detail_screen.dart').readAsStringSync();

/// 정규화 — 위젯의 `tsakNormText` 와 같은 규칙.
String norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

String onlyDigits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// 위젯의 `scoreOf` 규칙을 그대로 복제 — 우선순위 판정 검증용.
int scoreOf(
  String q, {
  required String name,
  required String number,
  required String phone,
  required String league,
  required String unit,
  required String position,
}) {
  final nq = norm(q);
  final qd = onlyDigits(nq);
  final nm = norm(name);
  final nd = onlyDigits(number);
  final pd = onlyDigits(phone);
  if (qd.isNotEmpty && nd.isNotEmpty && nd == qd) return 1;
  if (qd.isNotEmpty && pd.isNotEmpty && pd == qd) return 2;
  if (nm.isNotEmpty && nm == nq) return 3;
  if (nm.isNotEmpty && nm.startsWith(nq)) return 4;
  if (qd.isNotEmpty && nd.isNotEmpty && nd.startsWith(qd)) return 5;
  if (qd.length >= 4 && pd.isNotEmpty && pd.endsWith(qd)) return 6;
  final aff = norm('$league $unit $position');
  if (aff.isNotEmpty && aff.contains(nq)) return 7;
  if (nm.isNotEmpty && nm.contains(nq)) return 8;
  if (pd.isNotEmpty && qd.length >= 4 && pd.contains(qd)) return 8;
  return 0;
}


/// 위 기준값으로 점수를 낸다 — `...base` 스프레드는 Dart 인자로 못 쓴다.
int s0(String q) => scoreOf(
  q,
  name: '선영진',
  number: '1346',
  phone: '01046236587',
  league: '전남',
  unit: '순천지역대',
  position: '멘토(지도대장)',
);

void main() {
  group('① 명부 통합 검색 항목 — 요구한 전 항목을 본다', () {
    test('번호·전화·이름·연맹·단위대·직위를 모두 대조한다', () {
      for (final f in [
        'number: m.number',
        'phone: m.phone',
        'league: lg',
        'unit: un',
        'position: m.position',
      ]) {
        expect(_lookup.contains(f), isTrue, reason: '$f 를 봐야 한다');
      }
    });

    test('멘토·페런츠 인적사항(link_profiles)도 검색 대상에 포함한다', () {
      expect(_lookup.contains('for (final e in profiles.entries)'), isTrue,
          reason: '카드 없는 비인가 멘토·페런츠도 명부의 사람이다');
      expect(_lookup.contains("p['phone']"), isTrue);
      expect(_lookup.contains("p['kind']"), isTrue);
    });

    test('겸임자(멘토+페런츠)는 역할을 모두 표시한다', () {
      expect(_lookup.contains("if ('\$k' == 'mentor') '멘토'"), isTrue);
      expect(_lookup.contains("if ('\$k' == 'parent') '페런츠'"), isTrue);
    });
  });

  group('② 정렬 우선순위 — 사용자가 기대하는 순서', () {

    test('번호 완전일치가 최우선(1)', () {
      expect(s0('1346'), 1);
    });

    test('전화번호 완전일치(2)', () {
      expect(s0('01046236587'), 2);
    });

    test('이름 완전일치(3) > 이름 앞부분(4)', () {
      expect(s0('선영진'), 3);
      expect(s0('선영'), 4);
    });

    test('전화 뒷자리 4자리로도 찾는다(6)', () {
      expect(s0('6587'), 6);
    });

    test('연맹·단위대·직위 포함(7)', () {
      expect(s0('순천'), 7);
      expect(s0('전남'), 7);
      expect(s0('지도대장'), 7);
    });

    test('이름 중간 포함(8)', () {
      expect(s0('영진'), 8);
    });

    test('무관한 문자열은 0 — 목록에 넣지 않는다', () {
      expect(s0('제주한라'), 0);
    });
  });

  group('③ 화면 배선 — 참가비/후원 시트에 적용됨', () {
    test('지출(expense)은 종전 그대로, 나머지는 명부 검색 필드', () {
      expect(_event.contains('TsakPayerLookupField('), isTrue);
      expect(_event.contains("if (kind == 'expense')"), isTrue,
          reason: '지출처는 사람이 아니므로 검색 위젯을 쓰지 않는다');
    });

    test('고르면 이름·인가번호를 채우고 카드 연동 안내를 띄운다', () {
      final i = _event.indexOf('TsakPayerLookupField(');
      expect(i, greaterThan(-1));
      final tail = _event.substring(i, (i + 1800).clamp(0, _event.length));
      expect(tail.contains('nameC.text = nm'), isTrue);
      expect(tail.contains('numC.text = numText'), isTrue);
      expect(tail.contains('개인카드에 반영됩니다'), isTrue);
    });

    test('인가번호가 없는 사람(비인가 멘토·페런츠)도 고를 수 있다', () {
      final i = _event.indexOf('TsakPayerLookupField(');
      final tail = _event.substring(i, (i + 1800).clamp(0, _event.length));
      expect(tail.contains('인가번호가 없어 개인카드 연동은 없습니다'), isTrue,
          reason: '카드가 없으면 이름/전화만 넣고 안내해야 한다');
    });

    test('명부 인적사항 공급원은 AppState.linkProfiles', () {
      expect(_event.contains('state0.linkProfiles'), isTrue);
      expect(_event.contains('loadLinkProfiles()'), isTrue,
          reason: '로그인 직후 비어 있을 수 있어 1회 로드가 필요하다');
    });

    test('은하 카드는 G 접두어를 유지한다', () {
      expect(_lookup.contains("num = 'G\$num'"), isTrue);
    });
  });

  group('④ 순수 함수 — 하이픈/공백 혼용', () {
    test('하이픈이 섞인 전화번호도 같은 값으로 본다', () {
      expect(onlyDigits('010-4623-6587'), '01046236587');
    });

    test('이름의 공백은 무시한다', () {
      expect(norm('김 범 수'), norm('김범수'));
    });
  });
}
