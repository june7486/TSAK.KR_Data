// 범스카우트 인가정보 카드의 **인가일 노출** 회귀 테스트.
//
// 요구(2026-11-02, build #574): "범스카우트 인가일을 인가정보에 노출해줘"
//  · 보고 화면: #893 이소라 카드에 범인가번호/소속 연맹/등록 단위대만 보이고
//    '인가일' 항목이 **아예 없었다**.
//  · 원인: `_credentialCard` 가 인가일에 `_plainRow` 를 썼는데, 그 헬퍼는
//      if (value.trim().isEmpty) return const SizedBox.shrink();
//    로 **빈 값이면 행을 통째로 지운다**. 인가일이 공란인 회원(실측 44명)은
//    항목 자체가 사라져 "없는 항목"처럼 보였다.
//  · 수정: `_blankRow(..., placeholder: '미등록')` 로 바꿔 **자리를 지킨다**.
//
// ## 왜 위젯 렌더 테스트가 아니라 소스 계약 테스트인가
//  MemberDetailScreen 을 pump 하면 이 환경에서 테스트가 완료되지 않는다
//  (`member_detail_no_duplicate_test.dart` 도 동일하게 멈춘다 — 화면 자체가
//  배경 애니메이션/타이머를 계속 잡고 있어 pumpAndSettle 이 끝나지 않는다).
//  그래서 "빈 값이면 사라지는 헬퍼를 다시 쓰지 않았는가"를 **소스 계약**으로
//  고정한다. 이 방식은 build 이후 리팩터링에도 계속 유효하다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readScreen() => File(
  'lib/screens/member_detail_screen.dart',
).readAsStringSync();

/// [start] 이후 첫 [end] 전까지 잘라낸다(대략적인 함수 본문 추출).
String slice(String src, String start, String end, {int from = 0}) {
  final i = src.indexOf(start, from);
  if (i < 0) return '';
  final j = src.indexOf(end, i + start.length);
  if (j < 0) return '';
  return src.substring(i, j);
}

void main() {
  late String src;
  late String credentialCard;

  setUpAll(() {
    src = readScreen();
    // ① 범인가 카드 본문 — `_credentialCard` 부터 `_linkCard` 안내 주석 전까지.
    credentialCard = slice(
      src,
      'Widget _credentialCard(Member m) {',
      '/// ③ 멘토·페런츠·멘티·자녀대원 **연결 카드**',
    );
  });

  group('① 인가일 노출 — 범인가 정보 카드', () {
    test('인가일을 _plainRow(빈 값이면 사라짐)로 그리지 않는다', () {
      expect(credentialCard, isNotEmpty, reason: '_credentialCard 본문을 찾지 못함');
      expect(
        credentialCard.contains("_plainRow('인가일'"),
        isFalse,
        reason: '_plainRow 는 빈 값이면 SizedBox.shrink() 를 반환해 항목이 통째로 '
            '사라진다 — #893 이소라 카드에서 인가일이 없어 보인 원인',
      );
    });

    test('인가일은 자리를 지키는 _blankRow 로 그리고, 빈 값은 미등록으로 안내한다', () {
      expect(
        credentialCard.contains("_blankRow('인가일', m.date"),
        isTrue,
        reason: '값이 없어도 항목이 남아야 한다',
      );
      expect(
        credentialCard.contains("placeholder: '미등록'"),
        isTrue,
        reason: "빈 인가일은 '—' 가 아니라 '미등록' 으로 안내해야 의미가 분명하다",
      );
    });

    test('서포터즈(비인가 일반회원)에게는 인가일 행을 만들지 않는다', () {
      expect(
        credentialCard.contains('if (!m.isRegular)'),
        isTrue,
        reason: '인가 자체가 없는 회원에게 인가일 항목을 띄우면 오해를 준다',
      );
    });
  });

  group('② _blankRow 헬퍼 확장', () {
    test('placeholder 인자를 받아 기본값 — 를 유지한다(ATAS 기존 동작 보존)', () {
      final helper = slice(src, 'Widget _blankRow(', 'Widget _plainRow(');
      expect(helper, isNotEmpty);
      expect(helper.contains("String placeholder = '—'"), isTrue,
          reason: '기본값이 바뀌면 ATAS 카드의 — 표기가 함께 바뀌어 버린다');
      expect(helper.contains('empty ? placeholder : v'), isTrue,
          reason: '빈 값일 때 placeholder 를 써야 한다');
    });

    test('ATAS 카드는 여전히 기본 — 표기를 쓴다', () {
      final atasIdx = src.indexOf('Widget _atasCard(Member m) {');
      expect(atasIdx, greaterThan(0), reason: '_atasCard 를 찾지 못함');
      final atas = src.substring(atasIdx);
      expect(atas, isNotEmpty);
      // ATAS 인가일 호출 줄만 떼어내 placeholder 를 넘기지 않는지 본다.
      final call = atas
          .split('\n')
          .where((l) => l.contains("_blankRow('인가일', m.atasDate"))
          .join('\n');
      expect(call, isNotEmpty, reason: 'ATAS 인가일 행이 있어야 한다');
      expect(call.contains('placeholder:'), isFalse,
          reason: 'ATAS 인가일은 아직 값이 없을 수 있는 항목이므로 — 가 맞다');
    });
  });

  group('③ 알려진 실데이터 회귀', () {
    test('인가일이 공란인 회원이 44명 있었다 — 이들이 사라지면 안 된다', () {
      // 운영 DB 실측(2026-11-02): 인가자 2,229명 중 2,185명 date 존재,
      //  44명 공란(예: 이소라 #893). 서포터즈 13명은 전원 공란.
      // 이 테스트는 "빈 값 회원이 존재한다"는 사실 자체를 기록해, 나중에
      // 누군가 다시 '빈 값이면 숨김' 으로 되돌리는 것을 막는다.
      expect(credentialCard.contains('미등록'), isTrue);
      expect(credentialCard.contains("_blankRow('인가일'"), isTrue);
    });
  });
}
