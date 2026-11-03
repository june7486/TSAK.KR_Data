// 2026-11-02 (build #571) — **양방향 연동 + 인가자 계정 생성 규칙** 회귀 테스트.
//
// ## 사용자 보고 (원문)
//  · "현승용 개인카드에서 현지환을 멘티로 등록했는데도 현지환 개인카드에
//     연동되어 현승용이 멘토로 등록되지 않고 있음 (혹시 버그인지 수정해줘),
//     같은 검증을 페런츠에서도 해봐"
//  · "범인가자가 페런츠, 또는 멘토일때는 아이디를 전화번호로 생성하지 않고,
//     범인가자 개인카드에 연동해서 멘토, 페런츠, 멘티 정보를 넣으면 됨"
//  · "현재는 범인가자들의 정보를 넣으면 전화번호로 아이디를 생성하고 있는 것 같음"
//
// ## 실측 근거 (운영 DB 2,242명)
//   현승용 #590  mentees=['2186']   ← 대장이 대원을 등록함
//   현지환 #2186 mentors=[]         ← 대원 쪽에 대장이 없음 🐞
//
// → 규칙은 순수 함수(`link_sync.dart`)로 뽑아 다이얼로그 없이 검증한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/link_sync.dart';

void main() {
  // ─────────────────────────────────────────────── 버그 1 · 2 (양방향 연동)
  group('① 멘티 등록 → 멘티 카드의 mentors 역방향', () {
    test('현승용(#590)이 현지환(#2186)을 멘티로 추가하면 현지환에 590이 들어간다', () {
      // 보고된 바로 그 상황.
      final edits = planReverseLinks(
        selfNumber: '590',
        field: 'mentees',
        before: const <String>[],
        after: const <String>['2186'],
      );
      expect(edits.length, 1);
      expect(edits.first.memberNumber, '2186', reason: '현지환 카드를 고쳐야 한다');
      expect(edits.first.field, 'mentors', reason: 'mentees 의 짝은 mentors');
      expect(edits.first.code, '590', reason: '값은 나(대장)의 인가번호');
      expect(edits.first.add, isTrue);
    });

    test('멘티 해제하면 멘티 카드에서 나를 뺀다', () {
      final edits = planReverseLinks(
        selfNumber: '590',
        field: 'mentees',
        before: const <String>['2186'],
        after: const <String>[],
      );
      expect(edits.length, 1);
      expect(edits.first.add, isFalse);
      expect(edits.first.field, 'mentors');
      expect(edits.first.code, '590');
    });

    test('이미 양쪽에 있으면 아무 편집도 없다(불필요한 승인요청 방지)', () {
      final edits = planReverseLinks(
        selfNumber: '590',
        field: 'mentees',
        before: const <String>['2186'],
        after: const <String>['2186'],
      );
      expect(edits, isEmpty);
    });

    test('자기 자신은 역방향 대상이 아니다(자기참조 방지)', () {
      final edits = planReverseLinks(
        selfNumber: '590',
        field: 'mentees',
        before: const <String>[],
        after: const <String>['590'],
      );
      expect(edits, isEmpty);
    });

    test('여러 명을 한 번에 추가해도 각각 계산된다', () {
      final edits = planReverseLinks(
        selfNumber: '590',
        field: 'mentees',
        before: const <String>['2186'],
        after: const <String>['2186', '143', '415'],
      );
      expect(edits.length, 2);
      expect(edits.map((e) => e.memberNumber).toSet(), {'143', '415'});
      expect(edits.every((e) => e.field == 'mentors'), isTrue);
    });
  });

  group('② 페런츠(자녀) 등록 → 자녀 카드의 parents 역방향 — "같은 검증"', () {
    test('A(#415)가 C(#2186)를 자녀로 등록하면 C.parents 에 415', () {
      final edits = planReverseLinks(
        selfNumber: '415',
        field: 'children',
        before: const <String>[],
        after: const <String>['2186'],
      );
      expect(edits.length, 1);
      expect(edits.first.memberNumber, '2186');
      expect(edits.first.field, 'parents', reason: 'children 의 짝은 parents');
      expect(edits.first.code, '415');
      expect(edits.first.add, isTrue);
    });

    test('자녀 해제하면 자녀 카드에서 부모를 뺀다', () {
      final edits = planReverseLinks(
        selfNumber: '415',
        field: 'children',
        before: const <String>['2186'],
        after: const <String>[],
      );
      expect(edits.single.field, 'parents');
      expect(edits.single.add, isFalse);
    });
  });

  group('③ 네 필드의 짝이 모두 맞다(반대 시점)', () {
    test('mentees ↔ mentors / children ↔ parents / mentors ↔ mentees / parents ↔ children', () {
      expect(linkPeerField('mentees'), 'mentors');
      expect(linkPeerField('children'), 'parents');
      expect(linkPeerField('mentors'), 'mentees');
      expect(linkPeerField('parents'), 'children');
    });

    test('왕복이 대칭이다(A가 B를 넣으면 B에 A, 그 반대도 같다)', () {
      final fwd = planReverseLinks(
        selfNumber: '590',
        field: 'mentees',
        before: const <String>[],
        after: const <String>['2186'],
      );
      final rev = planReverseLinks(
        selfNumber: '2186',
        field: 'mentors',
        before: const <String>[],
        after: const <String>['590'],
      );
      // 두 방향 모두 "상대 카드에 나를 넣는다" 로 수렴해야 한다.
      expect(fwd.single.memberNumber, '2186');
      expect(fwd.single.field, 'mentors');
      expect(rev.single.memberNumber, '590');
      expect(rev.single.field, 'mentees');
    });
  });

  group('④ 코드 정규화 — 은하 G 접두어 보존', () {
    test('G75 와 75 는 다른 사람이다', () {
      expect(linkNormCode('G75'), 'G75');
      expect(linkNormCode('75'), '75');
      expect(linkNormCode('G75') == linkNormCode('75'), isFalse);
    });

    test('표기 흔들림을 흡수한다', () {
      expect(linkNormCode(' 범#2186 '), '2186');
      expect(linkNormCode('은하75'), 'G75');
      expect(linkNormCode('2186'), '2186');
      expect(linkNormCode(''), '');
    });

    test('목록 정규화 — 중복·빈값·자기참조 제거', () {
      final out = linkNormList(
        const <String>['590', '590', '', ' 2186 ', 'G75'],
        selfNumber: '999',
      );
      expect(out, <String>['590', '2186', 'G75']);
      expect(linkNormList(const <String>['590'], selfNumber: '590'), isEmpty);
    });
  });

  group('⑤ applyLinkEdit — 편집 적용', () {
    test('추가', () {
      final e = const LinkSyncEdit(
        memberNumber: '2186',
        field: 'mentors',
        code: '590',
        add: true,
      );
      expect(applyLinkEdit(const <String>[], e), <String>['590']);
      expect(applyLinkEdit(const <String>['143'], e), <String>['143', '590']);
    });

    test('중복 추가는 그대로', () {
      final e = const LinkSyncEdit(
        memberNumber: '2186',
        field: 'mentors',
        code: '590',
        add: true,
      );
      expect(applyLinkEdit(const <String>['590'], e), <String>['590']);
    });

    test('제거', () {
      final e = const LinkSyncEdit(
        memberNumber: '2186',
        field: 'mentors',
        code: '590',
        add: false,
      );
      expect(applyLinkEdit(const <String>['590', '143'], e), <String>['143']);
      expect(applyLinkEdit(const <String>['143'], e), <String>['143']);
    });
  });

  // ─────────────────────────────────────────────── 버그 3 (계정 생성 규칙)
  group('⑥ 범인가자는 전화번호 아이디를 만들지 않는다', () {
    late String sheet;
    late String field;
    late String server;

    setUpAll(() {
      sheet = File('lib/widgets/link_profile_sheet.dart').readAsStringSync();
      field = File('lib/widgets/link_code_field.dart').readAsStringSync();
      server = File('/home/user/nas_proxy/proxy_server.py').readAsStringSync();
    });

    test('시트가 인가자일 때 전화번호 계정 블록을 감춘다', () {
      // isScouter 분기 안에서 인가자 안내를, else 에서 전화번호 계정을 보여준다.
      expect(sheet.contains('if (isScouter)'), isTrue);
      expect(sheet.contains('인가자 카드에 연동 — 별도 아이디를 만들지 않습니다'), isTrue);
      expect(sheet.contains("자동 생성 계정 (\${isMentor ? '멘토' : '페런츠'} · 전화번호 기반)"),
          isTrue);
    });

    test('편집화면 구현(link_code_field)도 같은 규칙을 쓴다', () {
      expect(field.contains('if (isScouter) ...['), isTrue);
      expect(field.contains('인가자 카드에 연동 — 별도 아이디를 만들지 않습니다'), isTrue);
    });

    test('인가자인데 인가번호가 비면 저장을 막는다', () {
      expect(sheet.contains('범인가자이면 인가번호를 입력해야 개인카드에 연동됩니다'), isTrue);
    });

    test('페런츠 인가자의 저장키는 본인 인가번호로 맞춘다', () {
      // 카드 조회가 되려면 profiles 키와 members 번호가 같아야 한다.
      expect(sheet.contains('if (isScouter && scoutNo.isNotEmpty) c = scoutNo;'),
          isTrue);
    });

    test('서버가 인가자면 아이디 생성을 건너뛴다', () {
      expect(server.contains('def _profile_creds_or_blank(p):'), isTrue);
      expect(server.contains('if bool(p.get("isScouter")):'), isTrue);
      expect(server.contains('if re.sub(r"[^0-9]", "", str(p.get("scoutNo", "") or "")):'),
          isTrue);
    });

    test('프로필 저장 핸들러가 그 함수를 쓴다(무조건 생성 금지)', () {
      expect(server.contains('login_id, pw = _profile_creds_or_blank(p)'), isTrue);
      // 종전의 무조건 생성 호출이 남아 있으면 안 된다.
      expect(
        server.contains(
          'login_id, pw = _gen_profile_credentials(p.get("phone"), p.get("name"))',
        ),
        isFalse,
        reason: '인가자에게도 전화번호 아이디를 만드는 옛 호출이 남아 있다',
      );
    });
  });

  group('⑦ 서버 정합화가 양방향 4개 규칙을 모두 갖는다', () {
    late String server;
    setUpAll(() {
      server = File('/home/user/nas_proxy/proxy_server.py').readAsStringSync();
    });

    /// 모듈 레벨 함수 1개 본문만(다음 top-level `def ` 직전까지).
    /// 주석·docstring 을 걷어내 **실행 코드**만 검사한다.
    String _reconcileBody(String s) {
      final start = s.indexOf('def _link_reconcile_apply(');
      if (start < 0) return '';
      final rest = s.substring(start + 4);
      final mt = RegExp(r'\ndef (?! )').firstMatch(rest);
      var body = mt == null ? rest : rest.substring(0, mt.start);
      body = body.replaceAll(RegExp(r'"""[\s\S]*?"""'), '');
      return body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
    }

    test('대원이 대장·부모를 등록하는 방향(기존)', () {
      // [요구 2026-11-04] 인가자 한정 조건(`c in cred_no`)을 없애고 사람 기준
      // 으로 판정하도록 바꿨다. 그래서 키가 tno(int 인덱스) 로 달라졌지만
      // **규칙 자체(자녀→부모 / 멘티→멘토)** 는 그대로다.
      final body = _reconcileBody(server);
      expect(body.contains('to_add.setdefault((ti, "children"), set())'), isTrue);
      expect(body.contains('to_add.setdefault((ti, "mentees"), set())'), isTrue);
    });

    test('대장·부모가 대원·자녀를 등록하는 방향(2026-11-02 추가)', () {
      expect(server.contains('to_add.setdefault((c, "mentors"), set())'), isTrue,
          reason: 'A.mentees → B.mentors 규칙이 없다(현승용/현지환 버그)');
      expect(server.contains('to_add.setdefault((c, "parents"), set())'), isTrue,
          reason: 'A.children → C.parents 규칙이 없다');
    });

    test('reconcile 이 회원 단건저장 경로에서 호출된다', () {
      expect(server.contains('_link_reconcile_apply(members, save=False)'), isTrue);
    });
  });

  mainDeleteIcons(); // ⑨ 삭제 아이콘 검증

  group('⑧ 화면이 역방향 동기화를 실제로 호출한다', () {
    late String tiles;
    late String apply;
    setUpAll(() {
      tiles = File('lib/widgets/link_people_tiles.dart').readAsStringSync();
      apply = File('lib/services/link_sync_apply.dart').readAsStringSync();
    });

    test('멘티 저장이 syncReverseLinks 를 부른다', () {
      expect(tiles.contains('syncReverseLinks('), isTrue);
      // 실제 저장 경로(_saveMentees) 안에 있어야 한다.
      final i = tiles.indexOf('Future<void> _saveMentees(');
      expect(i >= 0, isTrue);
      final tail = tiles.substring(i, (i + 2500).clamp(0, tiles.length));
      expect(tail.contains('syncReverseLinks('), isTrue);
    });

    test('멘토·페런츠 저장도 역방향을 부른다', () {
      final i = tiles.indexOf('Future<void> _addProfile(');
      expect(i >= 0, isTrue);
      // 창을 넉넉히(6000자) 잡는다. turn 51 에 관계값 해석 로직이 본문 앞부분에
      // 추가되어 3000자 창이 `syncReverseLinks(` 호출을 놓쳤다(동작은 정상).
      final tail = tiles.substring(i, (i + 6000).clamp(0, tiles.length));
      expect(tail.contains('syncReverseLinks('), isTrue);
      expect(tail.contains('res.isScouter'), isTrue);
    });

    test('적용 레이어가 카드 없음/이미반영을 안전하게 건너뛴다', () {
      expect(apply.contains('if (target == null) return false;'), isTrue);
      expect(apply.contains("if (target.corps == 'eunha') return false;"), isTrue);
      expect(apply.contains('return false; // 이미 반영됨'), isTrue);
    });

    test('은하는 범 연동 규칙에서 제외한다', () {
      expect(apply.contains("target.corps == 'eunha'"), isTrue);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────
// 2026-11-02 (build #571) 추가 — **삭제 아이콘** 요구.
//
// 보고(원문): "멘티, 멘토, 페런츠 모두 본인 및 관리자/마스터가 해당 이름을
//  삭제할 수 있도록 오른쪽에 삭제아이콘 추가해줘 그리고 삭제시 꼭 한번더
//  물어봐줘"
//
// 종전에는 `onRemove` 가 **멘티 섹션에만** 배선돼 있어, 멘토·페런츠는
// 한 번 등록하면 화면에서 되돌릴 수 없었다.
void mainDeleteIcons() {
  group('⑨ 세 항목 모두 삭제 아이콘 + 확인 다이얼로그', () {
    late String tiles;
    setUpAll(() {
      tiles = File('lib/widgets/link_people_tiles.dart').readAsStringSync();
    });

    test('멘티 섹션에 onRemove 가 배선돼 있다', () {
      final i = tiles.indexOf("title: '멘티 (내가 배출한 범 대원)'");
      expect(i >= 0, isTrue);
      final tail = tiles.substring(i, (i + 500).clamp(0, tiles.length));
      expect(tail.contains('onRemove:'), isTrue);
      expect(tail.contains('_removeMentee('), isTrue);
    });

    test('멘토 섹션에도 onRemove 가 배선돼 있다', () {
      final i = tiles.indexOf("title: '멘토 (범을 배출한 대장)'");
      expect(i >= 0, isTrue);
      final tail = tiles.substring(i, (i + 600).clamp(0, tiles.length));
      expect(tail.contains('onRemove:'), isTrue,
          reason: '멘토는 삭제 아이콘이 없어 되돌릴 수 없었다');
      expect(tail.contains("_removeLink(context, r, parent: false)"), isTrue);
    });

    test('페런츠 섹션에도 onRemove 가 배선돼 있다', () {
      final i = tiles.indexOf("title: '페런츠 (범을 배출한 부모님)'");
      expect(i >= 0, isTrue);
      final tail = tiles.substring(i, (i + 600).clamp(0, tiles.length));
      expect(tail.contains('onRemove:'), isTrue,
          reason: '페런츠는 삭제 아이콘이 없어 되돌릴 수 없었다');
      expect(tail.contains("_removeLink(context, r, parent: true)"), isTrue);
    });

    test('삭제 전에 반드시 한 번 더 묻는다', () {
      final i = tiles.indexOf('Future<void> _removeLink(');
      expect(i >= 0, isTrue);
      final tail = tiles.substring(i, (i + 1600).clamp(0, tiles.length));
      expect(tail.contains('confirmDialog('), isTrue, reason: '확인 없이 삭제하면 안 된다');
      expect(tail.contains('danger: true'), isTrue);
      expect(tail.contains('confirmLabel:'), isTrue);
      // 확인 전에는 아무것도 저장하지 않는다.
      final okIdx = tail.indexOf('if (!ok');
      final saveIdx = tail.indexOf('state.save(');
      expect(okIdx >= 0 && saveIdx > okIdx, isTrue,
          reason: '확인(false)보다 저장이 먼저 일어나면 안 된다');
    });

    test('멘티 해제도 확인을 거친다', () {
      final i = tiles.indexOf('Future<void> _removeMentee(');
      expect(i >= 0, isTrue);
      final tail = tiles.substring(i, (i + 900).clamp(0, tiles.length));
      expect(tail.contains('confirmDialog('), isTrue);
      expect(tail.contains('danger: true'), isTrue);
    });

    test('삭제 아이콘은 오른쪽(행 끝)이고 종류별 툴팁이 다르다', () {
      expect(tiles.contains("'페런츠 삭제'"), isTrue);
      expect(tiles.contains("'멘토 삭제'"), isTrue);
      expect(tiles.contains("'멘티 해제'"), isTrue);
      // 멘토·페런츠는 close(삭제), 멘티는 link_off(연결 해제).
      expect(tiles.contains('isLinkKind ? Icons.close : Icons.link_off'), isTrue);
    });

    test('삭제가 역방향도 함께 해제한다', () {
      final i = tiles.indexOf('Future<void> _removeLink(');
      final tail = tiles.substring(i, (i + 1800).clamp(0, tiles.length));
      expect(tail.contains('syncReverseLinks('), isTrue,
          reason: '내 목록만 지우면 상대 카드에 유령 연결이 남는다');
    });

    test('삭제 권한은 canEdit(본인·관리자·마스터)로 제한된다', () {
      // 세 섹션 모두 `canEdit ? ... : null` 형태여야 한다.
      expect(RegExp(r'onRemove: canEdit\s*\n?\s*\?').allMatches(tiles).length, 3,
          reason: '삭제 버튼이 권한 게이트 없이 노출되면 안 된다');
    });
  });
}
