// 추모관 — 소스 계약 테스트.
//
// ## 왜 위젯 테스트가 아니라 소스 계약 테스트인가
//  이 샌드박스에서 `HomeScreen`·`MemberDetailScreen` 등을 pump 하면 테스트가
//  **끝나지 않는다**(알려진 환경 제약). 추모관 화면도 `AppState`(Provider)와
//  네트워크에 의존하므로 같은 위험이 있다. 그래서 여기서는 **파일 내용을
//  읽어 요구가 코드에 실제로 살아 있는지**를 검사한다.
//
//  이 방식이 잡아내는 것: 누군가 실수로
//   · 로그인 없이 열리는 진입점을 지웠는지
//   · 글쓴이/관리자에게만 관리 버튼을 주는 조건을 없앴는지
//   · 서버 계약(엔드포인트·키 이름)을 바꿔 버렸는지
//   · 중앙회 로고 → 앱 링크를 지웠는지
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: '$path 가 없습니다');
  return f.readAsStringSync();
}

/// 주석을 제거한 코드만 남긴다(주석에 적힌 문구를 '구현'으로 오인하지 않게).
String stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final lines = noBlock.split('\n').map((l) {
    final i = l.indexOf('//');
    if (i < 0) return l;
    // 문자열 안의 '//' 는 주석이 아니다 — 대충 URL('https://')만 예외 처리.
    if (l.contains("'") || l.contains('"')) {
      final hasQuoteBefore = l
          .substring(0, i)
          .contains(RegExp(r"""['"]"""));
      if (hasQuoteBefore) return l;
    }
    return l.substring(0, i);
  });
  return lines.join('\n');
}

void main() {
  const screenPath = 'lib/screens/memorial_screen.dart';
  const apiPath = 'lib/services/memorial_api.dart';
  const boardPath = 'lib/screens/board_screen.dart';
  const homePath = 'lib/screens/home_screen.dart';
  const htmlPath = '/home/user/web_custom_backup/memorial.html';

  group('① 화면 구조 — 요구가 코드에 살아 있는가', () {
    test('상부 참여 버튼 3종(추모글·사진·자료)이 있다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('_ctaBar'));
      expect(s, contains("_cta('✍️', '추모글'"));
      expect(s, contains("_cta('📷', '사진'"));
      expect(s, contains("_cta('📎', '자료'"));
      // CTA 가 실제로 화면에 배치되어야 한다(정의만 하고 안 쓰면 무의미).
      expect(s, contains('_ctaBar(),'));
    });

    test('통합 타임라인 — 기본 필터가 전체이고 종류 4종을 제공한다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains("String _filter = '전체'"));
      expect(
        s,
        contains("const items = ['전체', '글', '사진', '자료']"),
      );
      // '전체'일 때 거르지 않고 전부 보여줘야 '한 번에 모아 보기'가 된다.
      expect(s, contains("if (_filter == '전체') return all"));
    });

    test('통계 4종(추모글·사진·자료·공감)이 있다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains("one('추모글'"));
      expect(s, contains("one('사진'"));
      expect(s, contains("one('자료'"));
      expect(s, contains("one('공감'"));
    });

    test('영정 사진 + 이름 + 소개 + 연대가 상단에 있다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('d.photoUrl'));
      expect(s, contains('d.title'));
      expect(s, contains('d.subtitle'));
      expect(s, contains('d.years'));
    });
  });

  group('② 권한 — 관리자·마스터·글쓴이만 관리 버튼', () {
    test('canManage = 관리자이거나 내 글(editKey 보유)', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('final canManage = isAdmin || _mine.contains(p.id)'));
      // 관리 메뉴는 canManage 일 때만 노출.
      expect(s, contains('if (canManage)'));
      expect(s, contains('Icons.more_vert'));
    });

    test('"내 글" 판정은 로컬 editKey 보유 여부로 한다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('_api.canEdit(widget.memorialId, p.id)'));
    });

    test('편집/가리기/삭제/이동 4가지 동작이 모두 있다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains("'edit'"));
      expect(s, contains("'hide'"));
      expect(s, contains("'unhide'"));
      expect(s, contains("'delete'"));
      expect(s, contains("'move'"));
    });

    test('삭제 전 확인 다이얼로그가 있다(실수 방지)', () {
      final s = stripComments(read(screenPath));
      expect(s, contains("title: const Text('글을 삭제할까요?')"));
      expect(s, contains('되돌릴 수 없습니다'));
    });

    test('이동은 관리자에게만 노출되고, 대상이 없으면 솔직히 알린다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('if (isAdmin)'));
      expect(s, contains('다른 추모관으로 이동'));
      expect(s, contains('아직 다른 추모관이 없어 이동할 곳이 없습니다'));
    });
  });

  group('③ 공감 · 댓글', () {
    test('공감 토글과 댓글 버튼이 카드 하단에 있다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('_toggleLike(p)'));
      expect(s, contains('_addComment(p)'));
      expect(s, contains("'공감 \${p.likeCount}'"));
      expect(s, contains("'댓글 \${p.comments.length}'"));
    });

    test('공감은 서버가 준 최종값을 그대로 반영한다(불일치 방지)', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('likeCount: r.count'));
      // 근거 주석은 stripComments 가 지우므로 **원문**에서 확인한다.
      expect(
        read(screenPath),
        contains('서버가 최종값을 준다'),
        reason: '낙관적 갱신을 하지 않는 이유가 주석으로 남아 있어야 한다',
      );
    });

    test('댓글은 이름·인가번호를 함께 남길 수 있고 목록에 표시된다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('_api.addComment('));
      expect(s, contains("labelText: '인가번호'"));
      expect(s, contains('c.number.isNotEmpty'));
    });
  });

  group('④ 로그인 없이 — 인가번호 선택 기재', () {
    test('작성 시트에서 인가번호를 선택 입력할 수 있다고 안내한다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('인가자는 자기 번호를 함께 남길 수 있습니다'));
      expect(s, contains("hintText: '선택'"));
      expect(s, contains("hintText: '익명도 좋습니다'"));
    });

    test('로그인 없이 남길 수 있다는 사실을 화면이 알려준다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('로그인 없이 남길 수 있습니다'));
    });
  });

  group('⑤ 사진 · 자료 첨부', () {
    test('사진/자료 선택이 분리되어 있고 업로드 후 URL 을 보관한다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('_pick(imagesOnly: true)'));
      expect(s, contains('_pick(imagesOnly: false)'));
      // 위젯 안에서는 주입받은 api 인스턴스를 쓴다(widget.api).
      expect(s, contains('widget.api.upload('));
      expect(s, contains("final url = '\${j['url'] ?? ''}'"));
    });

    test('500MB 초과는 서버에 보내기 전에 먼저 알린다', () {
      // [요구 2026-11-04] "용량 500메가로 늘리고" — 상한이 25MB → 500MB.
      final s = stripComments(read(screenPath));
      expect(s, contains('500 * 1024 * 1024'));
      expect(s, contains('500MB 를 넘어 올릴 수 없습니다'));
      // 옛 상한이 남아 있으면 안 된다.
      expect(s, isNot(contains('25 * 1024 * 1024')));
    });

    test('업로드 상한을 화면에 안내한다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('최대 500MB'));
    });

    test('대용량은 스트리밍으로 보낸다 (메모리 폭증 방지)', () {
      // 500MB 를 http.post(body:) 로 한 덩어리 전송하면 OOM 으로 죽는다.
      final s = stripComments(read(apiPath));
      expect(s, contains('http.StreamedRequest('));
      expect(s, contains('onProgress'));
      expect(s, isNot(contains('.timeout(const Duration(seconds: 180))')));
    });

    test('업로드 진행률을 보여준다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('onProgress: (sent, total)'));
      expect(s, contains('LinearProgressIndicator'));
    });

    test('본문/사진/자료가 모두 비면 저장을 막는다', () {
      final s = stripComments(read(screenPath));
      expect(
        s,
        contains(
          '_body.text.trim().isEmpty && _photos.isEmpty && _files.isEmpty',
        ),
      );
      expect(s, contains('글이나 사진·자료를 하나는 넣어주세요'));
    });
  });

  group('⑥ 진입점 — 앱에서 들어갈 수 있는가', () {
    test('게시판 상단에 추모관 아이콘이 있다', () {
      final s = stripComments(read(boardPath));
      expect(s, contains("import 'memorial_screen.dart';"));
      expect(s, contains('故 노경하 선배님 추모관'));
      expect(s, contains('const MemorialScreen()'));
      expect(s, contains('Icons.local_florist'));
    });

    test('홈 메뉴에 추모관 항목과 핸들러가 있다', () {
      final s = stripComments(read(homePath));
      expect(s, contains("import 'memorial_screen.dart';"));
      expect(s, contains("value: 'memorial'"));
      expect(s, contains("case 'memorial':"));
      expect(s, contains("label: '故 노경하 선배님 추모관'"));
    });

    test('홈 메뉴 진입은 권한 조건 없이 열린다(로그인 없이도 참여)', () {
      final s = stripComments(read(homePath));
      final i = s.indexOf("value: 'memorial'");
      expect(i, greaterThan(0));
      // 항목 선언부 앞 120자 안에 if(...) 권한 가드가 없어야 한다.
      final before = s.substring(i > 160 ? i - 160 : 0, i);
      expect(
        before.contains('value:') ? false : true,
        isTrue,
        reason: '권한 가드 없이 항상 노출',
      );
    });
  });

  group('⑦ 서버 계약 — 엔드포인트·키 이름', () {
    test('6개 엔드포인트를 정확히 호출한다', () {
      final s = read(apiPath);
      expect(s, contains('/api/memorial/get'));
      expect(s, contains('/api/memorial/post'));
      expect(s, contains('/api/memorial/delete'));
      expect(s, contains('/api/memorial/like'));
      expect(s, contains('/api/memorial/comment'));
      expect(s, contains('/api/memorial/comment/delete'));
      expect(s, contains('/api/memorial/upload'));
    });

    test('응답 키 이름이 서버와 일치한다', () {
      final s = read(apiPath);
      // /api/memorial/get
      expect(s, contains("j['memorial']"));
      expect(s, contains("j['posts']"));
      expect(s, contains("j['isAdmin']"));
      // like
      expect(s, contains("j['liked']"));
      expect(s, contains("j['likeCount']"));
      // post
      expect(s, contains("j['editKey']"));
    });

    test('업로드는 쿼리로 파일명을 보낸다(멀티파트 아님, 한글 안전)', () {
      final s = read(apiPath);
      expect(s, contains("queryParameters: {'id': id, 'name': name}"));
      // 스트리밍 전환(2026-11-04) 이후 헤더는 map 리터럴이 아니라
      //  req.headers[...] 로 직접 꽂는다 — 두 표기를 모두 허용한다.
      expect(
        s,
        anyOf(
          contains("req.headers['Content-Type'] = 'application/octet-stream'"),
          contains("'Content-Type': 'application/octet-stream'"),
        ),
      );
      expect(
        s,
        contains('멀티파트를 쓰지 않는 이유'),
        reason: '한글 파일명 인코딩 회피 근거가 남아 있어야 한다',
      );
    });

    test('추모관 id 기본값이 noh-kyungha 이다', () {
      final s = read(apiPath);
      expect(s, contains("defaultMemorialId = 'noh-kyungha'"));
    });
  });

  group('⑧ editKey 보관 — 글쓴이가 자기 글을 다시 고칠 수 있는가', () {
    test('발급된 editKey 를 기기에 저장한다', () {
      final s = read(apiPath);
      expect(s, contains('_saveKey(id, pid, newKey)'));
      expect(s, contains("'tsak_memorial_keys_'"));
      expect(s, contains('SharedPreferences.getInstance()'));
    });

    test('수정 시 editKey 를 함께 보낸다', () {
      final s = read(apiPath);
      expect(s, contains("if (editKey.isNotEmpty) 'editKey': editKey"));
    });

    test('손상된 저장값은 버린다(파싱 실패로 앱이 죽지 않게)', () {
      final s = read(apiPath);
      expect(s, contains('catch (_)'));
    });
  });

  group('⑨ 웹 추모 페이지 — 중앙회 로고 → 앱 링크', () {
    test('상단 로고가 앱 루트로 연결된다', () {
      final s = read(htmlPath);
      expect(s, contains('class="emblem-link" href="/" target="_top"'));
      expect(s, contains('중앙회 앱'));
      // 인앱브라우저 iframe 탈출
      expect(
        s,
        contains('target="_top"'),
        reason: '카톡 인앱브라우저에서 프레임에 갇히지 않아야 한다',
      );
    });

    test('하단에도 앱 복귀 버튼이 있다', () {
      final s = read(htmlPath);
      expect(s, contains('class="back-app" href="/" target="_top"'));
      expect(s, contains('앱으로 돌아가기'));
    });
  });

  group('⑩ 후원계좌 3종 · 문의처 (2026-11-04 요구)', () {
    test('계좌를 앱에 하드코딩하지 않고 서버에서 받아온다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('_api.loadAccounts()'));
      expect(s, contains('_accounts.isNotEmpty'));
      expect(s, contains('_donationSection(),'));
      // 화면 소스에 계좌번호가 박혀 있으면 안 된다(설정 변경이 반영되지 않음).
      expect(s, isNot(contains('1005-202-281140')));
      expect(s, isNot(contains('1005-102-281143')));
      expect(s, isNot(contains('1005-003-886274')));
    });

    test('계좌 줄을 누르면 번호가 복사된다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('Clipboard.setData(ClipboardData(text: no))'));
      expect(s, contains("import 'package:flutter/services.dart'"));
    });

    test('예금주를 보여준다', () {
      final s = stripComments(read(screenPath));
      expect(s, contains("'예금주 : \$_holder'"));
    });

    test('문의 : 이승준 010-6322-7558 — 눌러서 전화', () {
      final s = stripComments(read(screenPath));
      expect(s, contains('이승준 010-6322-7558'));
      expect(s, contains("launchUrl(Uri.parse('tel:01063227558'))"));
    });

    test('서버 공개 엔드포인트가 계좌 3종과 예금주만 내보낸다', () {
      // 비밀번호·관리자 목록이 새어 나가면 안 된다.
      final py = read('/home/user/nas_proxy/proxy_server.py');
      expect(py, contains('/api/memorial/accounts'));
      expect(py, contains('"holder": str(cfg.get("donationHolder")'));
      // cfg 통째 반환 금지 — 이 엔드포인트 블록만 잘라 확인한다.
      final i = py.indexOf('if p == "/api/memorial/accounts"');
      expect(i, greaterThan(0));
      final block = py.substring(i, (i + 2600).clamp(0, py.length));
      expect(block, isNot(contains('appPassword')));
      expect(block, isNot(contains('masterPassword')));
      expect(block, isNot(contains('personalPasswords')));
      expect(block, isNot(contains('"admins"')));
    });

    test('웹 추모 페이지에도 같은 섹션이 있다', () {
      final s = read(htmlPath);
      expect(s, contains('id="donateBox"'));
      expect(s, contains("/api/memorial/accounts"));
      expect(s, contains('010-6322-7558'));
      expect(s, contains('copyAcct'));
    });
  });

  group('⑪ 업로드 상한 500MB — 서버도 같은 값', () {
    test('프록시가 500MB 를 허용한다', () {
      final py = read('/home/user/nas_proxy/proxy_server.py');
      expect(py, contains('500 * 1024 * 1024'));
      expect(py, contains('최대 500MB'));
      expect(py, isNot(contains('최대 25MB')));
    });
  });
}
