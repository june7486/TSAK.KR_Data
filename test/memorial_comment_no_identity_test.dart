// 추모관 댓글 — **글쓴이 신원을 요구하지 않는다** (turn56)
//
// 지적(원문): "댓글 등록하려고 하니 글쓴이 정보가 뜸 /
//              댓글은 글쓴이 글에 대한 다른 사람의 피드백임 구조 변경 필요함"
//
// ## 왜 이 테스트가 필요한가
//  글쓰기와 댓글이 **같은 신원 입력**을 쓰던 구조가 버그의 뿌리였다.
//  누군가 다시 "댓글에도 이름을 받자"고 되돌리면 조용히 재발한다.
//  그래서 소스 계약(contract)으로 못을 박아 둔다.
//
// ## 왜 위젯 테스트가 아니라 소스 계약 테스트인가
//  이 샌드박스에서 HomeScreen·MemberDetailScreen·EventDetailScreen 을
//  pump 하면 테스트가 끝나지 않는다(알려진 hang). MemorialScreen 도 같은
//  계열(네트워크 초기화)이라 pump 대신 **소스 문자열**을 검사한다.
//
// 실행: flutter test test/memorial_comment_no_identity_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 줄 단위 주석을 제거한다.
///
/// 주석에 "이름을 받는다" 같은 **반대 문장**이 들어 있어도 통과/실패가
/// 흔들리지 않게 하려면 주석을 먼저 걷어내야 한다.
String stripComments(String src) => src
    .split('\n')
    .map((ln) => ln.replaceFirst(RegExp(r'^\s*//.*$'), ''))
    .join('\n');

/// `시그니처` 부터 중괄호 균형으로 본문 한 덩어리를 뽑는다.
String fnBody(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, greaterThan(-1), reason: '$signature 를 찾지 못했습니다');
  final closeParen = src.indexOf(')', src.indexOf('(', start));
  expect(closeParen, greaterThan(-1));
  final bodyOpen = src.indexOf('{', closeParen);
  expect(bodyOpen, greaterThan(-1));
  var depth = 0;
  final buf = StringBuffer();
  for (var i = bodyOpen; i < src.length; i++) {
    final ch = src[i];
    buf.write(ch);
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  return stripComments(buf.toString());
}

void main() {
  final dart = File('lib/screens/memorial_screen.dart').readAsStringSync();
  final js = File('../web_custom_backup/memorial.html').readAsStringSync();

  group('① Flutter — 댓글은 신원을 묻지 않는다', () {
    late String body;
    setUpAll(() => body = fnBody(dart, 'Future<void> _addComment('));

    test('이름·인가번호 입력칸을 만들지 않는다', () {
      // 종전 코드: nm/no 두 개의 TextEditingController 를 만들어
      //  대화상자에 '이름'·'인가번호' 칸으로 띄웠다.
      expect(body.contains("labelText: '이름'"), isFalse,
          reason: '댓글 대화상자에 이름 입력칸이 다시 생겼습니다');
      expect(body.contains("labelText: '인가번호'"), isFalse,
          reason: '댓글 대화상자에 인가번호 입력칸이 다시 생겼습니다');
      // 기기에 적어둔 이름을 '읽는' 것은 정상이다(조용히 쓰기 위함).
      //  다만 그것을 **입력칸에 채워 넣지는** 않는다.
      expect(body.contains('TextEditingController(text: auth'), isFalse,
          reason: '글쓴이 정보를 입력칸에 채우면 안 됩니다');
    });

    test('본문 입력칸 하나만 둔다', () {
      expect(RegExp(r'TextField\(').allMatches(body).length, 1,
          reason: '댓글 입력칸은 본문 하나뿐이어야 합니다');
      expect(body.contains('maxLines: 4'), isTrue);
      expect(body.contains('autofocus: true'), isTrue,
          reason: '대화상자가 열리면 바로 타이핑할 수 있어야 합니다');
    });

    test('이름이 없으면 익명으로 보낸다', () {
      expect(body.contains("'익명'"), isTrue);
      expect(body.contains('nmSaved.isEmpty'), isTrue);
    });

    test('익명 댓글에는 인가번호를 붙이지 않는다', () {
      // 남의 인가번호가 익명 글에 붙으면 그 사람이 쓴 것으로 오인된다.
      expect(body.contains("nm == '익명' ? ''"), isTrue);
    });

    test('기억해 둔 이름을 익명으로 덮어쓰지 않는다', () {
      expect(body.contains('nmSaved.isNotEmpty'), isTrue,
          reason: '익명 댓글이 다음 글쓰기의 기본 이름을 익명으로 바꾸면 안 됩니다');
    });

    test('글쓰기 시트/작성 화면을 열지 않는다', () {
      expect(body.contains('openEditor'), isFalse);
      expect(body.contains('MemorialEditScreen'), isFalse);
      expect(body.contains('_openEditor'), isFalse);
    });
  });

  group('② 웹(memorial.html) — 댓글 폼은 이름 한 칸(선택)만', () {
    late String body;
    setUpAll(() => body = stripComments(js));

    test('addComment 가 글쓰기 시트를 띄우지 않는다', () {
      // 종전: if(!name){ toast('먼저 이름을 입력해 주세요'); openEditor('', id); return; }
      final i = body.indexOf('async function addComment(');
      expect(i, greaterThan(-1));
      final chunk = body.substring(i, body.indexOf('\n}', i) + 2);
      expect(chunk.contains('openEditor'), isFalse,
          reason: 'addComment 가 다시 글쓰기 시트를 열면 보고된 증상이 재발합니다');
      expect(chunk.contains('먼저 이름을 입력해 주세요'), isFalse);
    });

    test('이름 칸은 선택이며 비우면 익명', () {
      expect(body.contains("'익명'"), isTrue);
      expect(body.contains("name === '익명'"), isTrue);
    });

    test('댓글 폼에 .who 이름칸과 안내문이 있다', () {
      expect(body.contains('class="who"'), isTrue);
      expect(body.contains('placeholder="익명"'), isTrue);
      expect(body.contains('cmt-hint'), isTrue);
    });

    test('글쓰기 폼은 여전히 이름을 필수로 받는다', () {
      // 댓글만 바꾸고 글쓰기는 그대로여야 한다(추모글의 주인은 남겨야 함).
      expect(body.contains('function savePost('), isTrue);
      expect(body.contains("if(!name){ toast('이름을 입력해 주세요')"), isTrue);
    });
  });
}
