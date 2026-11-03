// [요구 2026-11-04] "차동엽 멘티 등록승인 후에도 계속 승인 요청창이 반복" 회귀 방지
//
// ## 실제 사고
//  mentors 에 **자기 번호**가 들어있는 회원 6명(실측 운영 DB):
//    415 이승준 · 417 김병혁 · 590 현승용
//   1051 차동엽 · 1346 양다솜 · 2229 노현아
//  예) 차동엽 #1051 mentors=['1051'] → "나의 멘토 = 나"
//  승인을 눌러 linkApprovalStatus='approved' 로 바꿔도 mentors 배열은 그대로라
//  목록에서만 사라지고 값은 남아 다시 큐에 올랐다.
//
// ## 수정 원칙
//  · 값을 지우지 않고(실데이터 보존) **요청으로 세지 않는다**.
//  · 승인할 내용이 없는 요청이므로 큐에서 빠지는 것이 맞다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const String _proxyPath = '/home/user/nas_proxy/proxy_server.py';

/// 자기참조 제외 규칙을 Dart 로 재현 — 프록시 로직과 동일해야 한다.
List<String> nonSelf(List<dynamic>? codes, String selfNo) {
  final self = selfNo.replaceAll(RegExp(r'[^0-9]'), '');
  final out = <String>[];
  for (final c in (codes ?? const [])) {
    final d = '${c ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) continue;
    if (self.isNotEmpty && d == self) continue;
    out.add(d);
  }
  return out;
}

void main() {
  group('자기참조 제외 규칙(순수 함수)', () {
    test('자기 번호만 있으면 요청 후보가 0건이다', () {
      expect(nonSelf(['1051'], '1051'), isEmpty);
    });

    test('다른 번호가 섞여 있으면 그 건만 남는다', () {
      expect(nonSelf(['1051', '415'], '1051'), ['415']);
    });

    test('자기 번호가 없으면 그대로 둔다', () {
      expect(nonSelf(['415', '417'], '1051'), ['415', '417']);
    });

    test('공백·구분기호가 섞여도 숫자로 비교한다', () {
      // 프록시 `_clean_no` 는 비숫자를 제거한다. ' 1051 ' → '1051' → 자기참조.
      expect(nonSelf([' 1051 '], '1051'), isEmpty);
      // 앞자리가 붙은 형태(010-1051 → 0101051)는 **다른 번호**로 본다.
      //  (전화번호를 인가번호 칸에 넣은 경우를 자기참조로 오인하지 않기 위함)
      expect(nonSelf(['010-1051'], '1051'), ['0101051']);
    });

    test('빈 배열은 빈 결과', () {
      expect(nonSelf([], '1051'), isEmpty);
      expect(nonSelf(null, '1051'), isEmpty);
    });
  });

  group('프록시 소스 계약', () {
    late String src;
    setUpAll(() {
      final f = File(_proxyPath);
      expect(f.existsSync(), isTrue);
      src = f.readAsStringSync();
    });

    test('_link_pending_members 가 자기참조를 걸러낸다', () {
      final i = src.indexOf('def _link_pending_members():');
      expect(i, greaterThan(0));
      final body = src.substring(i, i + 2600);
      expect(body.contains('_self_no'), isTrue,
          reason: '자기 번호 변수가 없으면 차동엽/양다솜이 계속 큐에 오른다');
      expect(body.contains('!= _self_no'), isTrue);
    });

    test('mentors 와 parents 양쪽 모두 자기참조를 제외한다', () {
      final i = src.indexOf('def _link_pending_members():');
      final body = src.substring(i, i + 2600);
      expect(body.contains('m.get("mentors")'), isTrue);
      expect(body.contains('m.get("parents")'), isTrue);
    });

    test('멘티/자녀대원 자기참조는 reconcile 이 정리한다', () {
      final i = src.indexOf('def _link_reconcile_apply(');
      final body = src.substring(i, i + 7000);
      expect(body.contains('for field in ("mentees", "children")'), isTrue);
      expect(body.contains('changed_selfclean'), isTrue);
    });
  });
}
