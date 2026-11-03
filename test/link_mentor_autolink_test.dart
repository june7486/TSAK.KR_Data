// [요구 2026-11-04] "멘토로 등록되어 신규회원으로 가입되면 멘티회원이 자동으로
//                   등록되어야 하는데 연동이 자동으로 되지 않는 버그"
//
// ## 실제 사고 (선영진 / 양다솜)
//  화면엔 "멘티 양다솜 #1346" 이 보였지만 실제 카드는
//      선영진 mentees=[]  /  양다솜 mentors=['1346']   ← 자기 번호!
//  화면은 link_profiles 키('멘토:1346')로 상대를 '보여주기만' 했고,
//  실제 연결이 아니었다.
//
// ## 원인
//  멘토의 link_profiles 키 번호는 **멘티(본인) 번호**다. 그래서
//  멘토 자신은 누구를 배출했는지 기록할 근거가 없었고,
//  멘티에는 본인 번호가 mentors 로 들어가 자기참조가 됐다.
//
// ## 수정
//  /api/link/profiles 저장 시 _link_apply_mentor_links() 가
//     멘티 카드: mentors ← 멘토의 전화번호(계정 아이디)
//     멘토 카드: mentees ← 멘티의 인가번호
//  를 양방향으로 채운다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const String _proxyPath = '/home/user/nas_proxy/proxy_server.py';

/// 자동 연동 규칙을 Dart 로 재현 — 프록시와 같은 결과여야 한다.
({List<String> menteeMentors, List<String> mentorMentees}) autoLink({
  required String menteeNo,
  required String mentorId,
  required List<String> menteeMentorsBefore,
  required List<String> mentorMenteesBefore,
}) {
  final mNo = menteeNo.replaceAll(RegExp(r'[^0-9]'), '');
  final mId = mentorId.replaceAll(RegExp(r'[^0-9]'), '');
  var a = [...menteeMentorsBefore];
  var b = [...mentorMenteesBefore];
  if (mNo.isEmpty || mId.isEmpty || mNo == mId) {
    return (menteeMentors: a, mentorMentees: b);
  }
  if (!a.contains(mId)) a = [...a, mId];
  if (!b.contains(mNo)) b = [...b, mNo];
  return (menteeMentors: a, mentorMentees: b);
}

void main() {
  group('자동 연동 규칙(순수 함수)', () {
    test('멘티 mentors 에 멘토 계정 아이디가 들어간다', () {
      final r = autoLink(
        menteeNo: '1346',
        mentorId: '01046236587',
        menteeMentorsBefore: [],
        mentorMenteesBefore: [],
      );
      expect(r.menteeMentors, ['01046236587']);
    });

    test('멘토 mentees 에 멘티 인가번호가 들어간다', () {
      final r = autoLink(
        menteeNo: '1346',
        mentorId: '01046236587',
        menteeMentorsBefore: [],
        mentorMenteesBefore: [],
      );
      expect(r.mentorMentees, ['1346']);
    });

    test('같은 번호면 아무것도 넣지 않는다(자기참조 방지)', () {
      final r = autoLink(
        menteeNo: '1346',
        mentorId: '1346',
        menteeMentorsBefore: [],
        mentorMenteesBefore: [],
      );
      expect(r.menteeMentors, isEmpty);
      expect(r.mentorMentees, isEmpty);
    });

    test('이미 있으면 중복 추가하지 않는다', () {
      final r = autoLink(
        menteeNo: '1346',
        mentorId: '01046236587',
        menteeMentorsBefore: ['01046236587'],
        mentorMenteesBefore: ['1346'],
      );
      expect(r.menteeMentors, ['01046236587']);
      expect(r.mentorMentees, ['1346']);
    });

    test('기존 값은 보존한다', () {
      final r = autoLink(
        menteeNo: '1346',
        mentorId: '01046236587',
        menteeMentorsBefore: ['417'],
        mentorMenteesBefore: ['2186'],
      );
      expect(r.menteeMentors, ['417', '01046236587']);
      expect(r.mentorMentees, ['2186', '1346']);
    });
  });

  group('프록시 소스 계약', () {
    late String src;
    setUpAll(() {
      final f = File(_proxyPath);
      expect(f.existsSync(), isTrue);
      src = f.readAsStringSync();
    });

    /// 모듈 레벨 함수 1개 본문만 잘라낸다(다음 top-level `def ` 직전까지).
    /// 문서화 주석(docstring)과 `#` 주석은 제거한 **실행 코드**를 돌려준다.
    /// (docstring 안에 'approvalStatus 는 건드리지 않는다' 같은 설명이 있어
    ///  단순 contains 로 검사하면 오탐이 난다 — 실제로 그렇게 오탐이 났다.)
    String codeOf(String fnName) {
      final start = src.indexOf('def $fnName(');
      expect(start, greaterThan(-1), reason: '$fnName 함수를 찾지 못했다');
      final rest = src.substring(start + 4);
      final m = RegExp(r'\ndef (?! )').firstMatch(rest);
      var body = m == null ? rest : rest.substring(0, m.start);
      // docstring 제거
      final ds = RegExp(r'"""[\s\S]*?"""');
      body = body.replaceAll(ds, '');
      // 주석 줄 제거
      body = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      return body;
    }

    test('_link_apply_mentor_links 가 존재한다', () {
      expect(src.contains('def _link_apply_mentor_links(profile, member_rec)'),
          isTrue);
    });

    test('자기참조를 막는다', () {
      final body = codeOf('_link_apply_mentor_links');
      expect(body.contains('if mentor_id == mentee_no'), isTrue);
      expect(body.contains('return 0'), isTrue);
    });

    test('멘티↔멘토 / 자녀↔페런츠 두 짝을 모두 처리한다', () {
      final body = codeOf('_link_apply_mentor_links');
      expect(body.contains('"mentees" if kind == "mentor" else "children"'),
          isTrue);
      expect(body.contains('"mentors" if kind == "mentor" else "parents"'),
          isTrue);
    });

    test('승인 상태는 건드리지 않는다', () {
      final body = codeOf('_link_apply_mentor_links');
      expect(body.contains('approvalStatus'), isFalse,
          reason: '승인은 계정 승인에서 한 번만 받아야 한다');
    });

    test('저장 엔드포인트가 자동 연동을 호출한다', () {
      expect(src.contains('_linked = _link_apply_mentor_links(p, _created)'),
          isTrue,
          reason: '가입 직후 자동 연동을 호출해야 한다');
      expect(src.contains('"linksApplied": _linked'), isTrue,
          reason: '화면이 연동 건수를 확인할 수 있어야 한다');
    });
  });
}
