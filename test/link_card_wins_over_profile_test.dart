// 회원 카드가 있으면 이름 탭은 **개인정보 창**으로 가야 한다 (build #603).
//
// ## 실제 사고 (turn 50, 사용자 보고 원문)
//  *"김종선 카드에서 멘티를 등록하면 박도현카드에서 김종선 이름은 보이는데,
//    김종선 이름을 클릭하면 개인정보 창으로 넘어가지 않고,
//    이름, 전화번호 입력하라는 창이 나옴"*
//
// ## 원인
//  `link_people_tiles.dart` 의 `_row()` 가
//      final needsProfile = isLinkKind && !r.hasProfile;
//  로 판단했는데, `hasProfile` 은 이름이 채워졌는지만 보는 값이었다.
//  그래서 **회원 카드는 있는데 인적사항(link_profiles)만 없는** 분
//  (실측: 일반회원 #900001 김종선)에게도 needsProfile=true 가 되어,
//  이름을 눌러도 `_tapName`(→ MemberDetailScreen) 이 아니라
//  인적사항 입력 시트가 열렸다.
//
// ## 수정 계약
//  ① `needsProfile` 에 `r.target == null` 조건이 **반드시** 있어야 한다.
//  ② 이름 InkWell 의 onTap 은 needsProfile 일 때만 `_addProfile`.
//  ③ 인적사항 시트는 행 오른쪽 배지 버튼(`canProfile`)으로 **분리 보존**된다.
//  ④ 서버 색인은 인가자 카드와 같은 전화번호의 일반회원 카드를
//     별도 인물로 세우지 않는다(`_cred_by_phone` 흡수).
//
// 위젯 테스트(HomeScreen 등 pump)는 이 샌드박스에서 멈추므로,
// 소스 계약 + 순수 함수 테스트로만 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 주석(`//`, `///`)을 제거한 실제 코드만 남긴다.
/// 주석에 적힌 문구가 테스트를 거짓 통과시키는 것을 막는다.
String stripComments(String src) => src
    .split('\n')
    .map((ln) => ln.replaceFirst(RegExp(r'^\s*//.*$'), ''))
    .where((ln) => ln.trim().isNotEmpty)
    .join('\n');

/// `_row(` 함수 본문만 뽑는다 (중괄호 균형으로 끝을 찾는다).
///
/// ⚠ 함정: `Color accent, {` 처럼 **named parameter 여는 중괄호**가 본문보다
///   먼저 나온다. 그걸 본문 시작으로 착각하면 `}`(named param 닫기)에서 바로
///   끝나 버려 빈 문자열이 나온다. 그래서 `}) {`(파라미터 목록 종료 + 본문 시작)
///   를 먼저 찾는다.
String rowBody(String src) {
  final start = src.indexOf('Widget _row(');
  expect(start, greaterThan(-1), reason: '_row 함수를 찾지 못했습니다');
  final sig = src.indexOf('}) {', start);
  expect(sig, greaterThan(-1), reason: '_row 시그니처를 찾지 못했습니다');
  var i = sig + 3; // '}) {' 의 '{' 위치
  var depth = 0;
  final buf = StringBuffer();
  for (; i < src.length; i++) {
    final ch = src[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        buf.write(ch);
        break;
      }
    }
    buf.write(ch);
  }
  return stripComments(buf.toString());
}

void main() {
  late String raw;
  late String code;
  late String proxy;

  setUpAll(() {
    raw = File('lib/widgets/link_people_tiles.dart').readAsStringSync();
    code = stripComments(raw);
    proxy = File('/home/user/nas_proxy/proxy_server.py').readAsStringSync();
  });

  group('① needsProfile — 카드가 이긴다', () {
    test('needsProfile 조건에 r.target == null 이 포함된다', () {
      final body = rowBody(raw);
      final line = body
          .split('\n')
          .firstWhere((l) => l.contains('needsProfile ='), orElse: () => '');
      expect(line, isNotEmpty, reason: 'needsProfile 대입문을 찾지 못했습니다');
      expect(
        line.replaceAll(' ', ''),
        contains('r.target==null'),
        reason: '회원 카드가 있는데도 needsProfile=true 가 되면 '
            '이름 탭이 인적사항 시트로 새어나간다 (turn 50 사고)',
      );
    });

    test('needsProfile 은 isLinkKind 조건을 그대로 유지한다 (멘티는 제외)', () {
      final body = rowBody(raw);
      final line = body.split('\n').firstWhere(
        (l) => l.contains('needsProfile ='),
        orElse: () => '',
      );
      expect(line.replaceAll(' ', ''), contains('isLinkKind'));
    });

    test('needsProfile 은 !r.hasProfile 조건도 유지한다', () {
      final body = rowBody(raw);
      final line = body.split('\n').firstWhere(
        (l) => l.contains('needsProfile ='),
        orElse: () => '',
      );
      expect(line.replaceAll(' ', ''), contains('!r.hasProfile'));
    });
  });

  group('② 이름 탭 분기 — 카드 있으면 _tapName', () {
    test('onTap 은 needsProfile 일 때만 _addProfile 을 부른다', () {
      final body = rowBody(raw);
      final idx = body.indexOf('_addProfile(context, r.kind!, r.code)');
      expect(idx, greaterThan(-1), reason: '_addProfile 호출을 찾지 못했습니다');
      // 호출 바로 앞 30자 안에 needsProfile 삼항 분기가 있어야 한다.
      final before = body.substring(
        idx - 40 < 0 ? 0 : idx - 40,
        idx,
      );
      expect(before, contains('needsProfile'));
    });

    test('_tapName 은 카드가 있으면 MemberDetailScreen 으로 push 한다', () {
      final start = code.indexOf('Future<void> _tapName(');
      expect(start, greaterThan(-1));
      final seg = code.substring(start, start + 900);
      expect(seg, contains('r.target != null'));
      expect(seg, contains('MemberDetailScreen(memberId: r.target!.id)'));
    });

    test('_tapName 의 카드-우선 분기가 인적사항 분기보다 **앞**에 있다', () {
      final start = code.indexOf('Future<void> _tapName(');
      final seg = code.substring(start, start + 1600);
      final cardIdx = seg.indexOf('MemberDetailScreen');
      final profileIdx = seg.indexOf("r.kind == 'mentor'");
      expect(cardIdx, greaterThan(-1));
      if (profileIdx > -1) {
        expect(
          cardIdx,
          lessThan(profileIdx),
          reason: '카드 분기가 인적사항 분기보다 뒤에 있으면 시트가 먼저 열린다',
        );
      }
    });
  });

  group('③ 인적사항 시트는 배지 버튼으로 보존', () {
    test('canProfile 플래그가 멘토·페런츠 행에만 선언된다', () {
      final body = rowBody(raw);
      expect(body, contains('canProfile'));
      final line = body
          .split('\n')
          .firstWhere((l) => l.contains('canProfile ='), orElse: () => '');
      expect(line.replaceAll(' ', ''), contains('isLinkKind'));
    });

    test('배지 버튼이 _addProfile 을 호출한다 (기능 보존)', () {
      final body = rowBody(raw);
      // 배지 아이콘 + _addProfile 호출이 같은 블록에 있어야 한다.
      final badgeIdx = body.indexOf('Icons.badge_outlined');
      expect(badgeIdx, greaterThan(-1), reason: '인적사항 배지 버튼이 사라졌습니다');
      final after = body.substring(badgeIdx);
      expect(after, contains('_addProfile(context, r.kind!, r.code)'));
    });

    test('배지 버튼은 카드가 이미 있을 때(needsProfile=false) 노출된다', () {
      final body = rowBody(raw);
      final idx = body.indexOf('Icons.badge_outlined');
      final before = body.substring(idx - 420 < 0 ? 0 : idx - 420, idx);
      expect(before, contains('canProfile'));
      expect(before, contains('!needsProfile'));
    });

    test('카드 있고 인적사항 없는 경우의 안내 문구가 개인페이지 안내가 아니다', () {
      expect(
        code,
        contains('인적사항 미등록 — 오른쪽 배지 아이콘으로 작성'),
        reason: '카드가 있는 분에게 "눌러서 작성" 이라고 하면 '
            '이름 탭이 시트를 연다는 잘못된 안내가 된다',
      );
    });
  });

  group('④ 서버 색인 — 중복 신원 흡수', () {
    test('_cred_by_phone 이 인가자 카드(전화번호 있는)를 모은다', () {
      expect(proxy, contains('_cred_by_phone'));
      final idx = proxy.indexOf('_cred_by_phone = {}');
      expect(idx, greaterThan(-1));
      final seg = proxy.substring(idx, idx + 500);
      expect(seg, contains('isRegular'));
    });

    test('일반회원 카드가 인가자와 같은 전화면 별도 인물을 만들지 않는다', () {
      final idx = proxy.indexOf('_cred_by_phone = {}');
      final seg = proxy.substring(idx, idx + 2600);
      final guard = seg.indexOf('if is_reg and ph and ph in _cred_by_phone:');
      expect(guard, greaterThan(-1), reason: '흡수 가드가 없습니다');
      // 가드 안에서 continue 로 persons 추가를 건너뛰어야 한다.
      final after = seg.substring(guard, guard + 420);
      expect(after, contains('continue'));
    });

    test('흡수된 카드의 코드는 인가자 인물의 alias 로 등록된다', () {
      final idx = proxy.indexOf('_cred_by_phone = {}');
      final seg = proxy.substring(idx, idx + 2600);
      final guard = seg.indexOf('if is_reg and ph and ph in _cred_by_phone:');
      final after = seg.substring(guard, guard + 420);
      expect(after, contains('_add_codes'));
    });

    test('_cred_by_phone 의 값은 **인가번호**다 (byCanon 키가 인가번호이므로)', () {
      final idx = proxy.indexOf('_cred_by_phone = {}');
      final seg = proxy.substring(idx, idx + 700);
      expect(
        seg.replaceAll(' ', ''),
        contains('_cred_by_phone[_ph]=_no'),
        reason: '전화번호를 값으로 저장하면 byCanon(키=인가번호) 조회에 실패해 '
            '중복 신원 흡수가 조용히 동작하지 않는다 (turn 50에 실제로 겪음)',
      );
      expect(seg.replaceAll(' ', ''), isNot(contains('_cred_by_phone[_ph]=m')));
    });
  });

  group('⑤ 서버 — 인가자 카드에 전화번호 채워 중복 생성 방지', () {
    /// 파이썬 함수의 **본문 전체**를 인덴트 기준으로 뽑아 주석·공백을 제거한다.
    /// docstring(`"""`)도 함께 포함되므로 문자열 검색이 안전하다.
    String job() {
      final start = proxy.indexOf('def _ev_guest_ensure_account_async(');
      expect(start, greaterThan(-1));
      final lines = proxy.substring(start).split('\n');
      final buf = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final ln = lines[i];
        if (i > 0) {
          if (ln.trim().isEmpty) {
            buf.add('');
            continue;
          }
          // 인덴트 4칸 미만이면 함수 종료
          if (!ln.startsWith('    ')) break;
        }
        // 줄 앞쪽 주석만 제거(문자열 속 '#' 은 보존)
        buf.add(ln.replaceFirst(RegExp(r'^\s*#.*$'), ''));
      }
      return buf.join('\n').replaceAll(RegExp(r'\s+'), '');
    }

    test('(3차) 동명 인가자 카드 매칭 단계가 존재한다', () {
      final body = job();
      // 주석은 job() 이 제거하므로 **실제 코드 특징**으로 검증한다.
      expect(body, contains('_blank=[]'));
      expect(body, contains('_any_phone=False'));
      expect(body, contains('found=_hit'));
      expect(body, contains('_hit["phone"]=d'), reason: '인가자 카드에 전화번호를 채우지 않는다');
    });

    test('동명 인가자 카드가 정확히 1장이고 전화번호가 모두 비었을 때만 채운다', () {
      final body = job();
      expect(
        body,
        contains('len(_blank)==1'),
        reason: '동명이인이 여러 명이면 전화번호를 채우면 안 된다',
      );
      expect(body, contains('not_any_phone'));
    });

    test('인가자 카드를 일반회원으로 승격시키지 않는다', () {
      final body = job();
      expect(body, contains('_is_cred_card'));
      expect(
        body,
        contains('andnot_is_cred_card:'),
        reason: '인가자 카드를 isRegular=True 로 바꾸면 명부·통계가 틀어진다',
      );
    });

    test('인가자 카드 경로에서는 personalPassword/loginId 를 쓰지 않는다', () {
      final body = job();
      final idx = body.indexOf('if_is_cred_card:');
      expect(idx, greaterThan(-1));
      final seg = body.substring(idx, (idx + 700).clamp(0, body.length));
      final elseIdx = seg.indexOf('else:');
      final credBranch = elseIdx > -1 ? seg.substring(0, elseIdx) : seg;
      expect(credBranch, isNot(contains('personalPassword')));
      expect(credBranch, isNot(contains('loginId')));
    });
  });
}
