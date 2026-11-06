// 추모관 API 클라이언트 — "故 노경하 선배님 추모관".
//
// ## 왜 별도 서비스인가
//  추모관은 **로그인 없이도** 쓰고 볼 수 있어야 한다(사용자 원문:
//  "바로가기 링크와 qr 생성 해서 로그인 없이도 글 쓰고 확인 및 수장할 수
//   있도록 해줘"). 그래서 서버는 `/api/memorial/*` 을 전역 인증 게이트에서
//  제외했다. 앱에서도 **로그인 전**에 열릴 수 있으므로 세션 헤더 없이
//  호출해도 정상 동작해야 한다.
//
//  다만 앱 안에서는 이미 로그인한 상태인 경우가 대부분이므로, 세션 헤더가
//  있으면 함께 보낸다(관리자면 서버가 숨김 글까지 내려준다).
//
// ## 서버 계약 (proxy_server.py)
//   GET  /api/memorial/get?id=<id>
//        → {ok, memorial:{...}, posts:[{id,name,number,body,created,updated,
//           hidden,kind,photos[],attachments[],likeCount,likeKey?,
//           comments:[{id,name,number,body,created}],commentCount}],
//           count, isAdmin}
//   POST /api/memorial/post                 {id,name,number,body,photos,
//                                            attachments,postId?,editKey?}
//        → {ok, id, editKey}  ← editKey 는 **신규 작성 때만** 돌아온다.
//   POST /api/memorial/delete               {id,postId,action,editKey?,targetId?}
//   POST /api/memorial/like                 {id,postId,likeKey} → {ok,liked,likeCount}
//   POST /api/memorial/comment              {id,postId,name,number,body} → {ok,cid}
//   POST /api/memorial/comment/delete       {id,postId,commentId,editKey?}
//   POST /api/memorial/upload?id&name       본문=원시 바이트
//        → {ok,name,size,isImage,url}
//
// ## 권한 모델 (서버가 강제)
//   · 글쓰기·공감·댓글     = 누구나(로그인 불필요)
//   · 수정·가리기·삭제      = 글쓴이(editKey 보유자) 또는 관리자·마스터
//   · 이동                 = 관리자·마스터만
//  앱은 화면에서 "내가 쓴 글"에만 편집 버튼을 노출하지만, **실제 차단은
//  서버가 한다**. editKey 는 이 기기의 로컬 저장소에 보관한다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'nas_api.dart';

/// 추모관 게시글 한 건.
class MemorialPost {
  MemorialPost({
    required this.id,
    required this.name,
    required this.number,
    required this.body,
    required this.created,
    required this.updated,
    required this.hidden,
    required this.kind,
    required this.photos,
    required this.attachments,
    required this.likeCount,
    required this.comments,
  });

  final String id;
  final String name;
  final String number;
  final String body;
  final String created;
  final String updated;
  final bool hidden;

  /// '글' | '사진' | '자료' — 첫 화면 필터에 쓴다.
  final String kind;

  /// 사진 URL 목록(서버 상대경로 `/memorial-file/...`).
  final List<String> photos;

  /// 자료 목록 — `{name, url, size}`.
  final List<Map<String, dynamic>> attachments;

  final int likeCount;
  final List<MemorialComment> comments;

  factory MemorialPost.fromMap(Map<String, dynamic> m) {
    return MemorialPost(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      number: '${m['number'] ?? ''}',
      body: '${m['body'] ?? ''}',
      created: '${m['created'] ?? ''}',
      updated: '${m['updated'] ?? ''}',
      hidden: m['hidden'] == true,
      kind: '${m['kind'] ?? '글'}',
      photos: (m['photos'] as List? ?? const [])
          .map((e) => '$e')
          .where((e) => e.isNotEmpty)
          .toList(),
      attachments: (m['attachments'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(),
      likeCount: (m['likeCount'] as num? ?? 0).toInt(),
      comments: (m['comments'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => MemorialComment.fromMap(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  bool get hasPhoto => photos.isNotEmpty;
  bool get hasFile => attachments.isNotEmpty;
}

/// 추모관 댓글 한 건.
class MemorialComment {
  MemorialComment({
    required this.id,
    required this.name,
    required this.number,
    required this.body,
    required this.created,
  });

  final String id;
  final String name;
  final String number;
  final String body;
  final String created;

  factory MemorialComment.fromMap(Map<String, dynamic> m) => MemorialComment(
    id: '${m['id'] ?? ''}',
    name: '${m['name'] ?? ''}',
    number: '${m['number'] ?? ''}',
    body: '${m['body'] ?? ''}',
    created: '${m['created'] ?? ''}',
  );
}

/// 추모관 전체 응답.
class MemorialData {
  MemorialData({
    required this.memorial,
    required this.posts,
    required this.isAdmin,
  });

  final Map<String, dynamic> memorial;
  final List<MemorialPost> posts;
  final bool isAdmin;

  String get title => '${memorial['title'] ?? '추모관'}';
  String get subtitle => '${memorial['subtitle'] ?? ''}';
  String get years => '${memorial['years'] ?? ''}';
  String get photoUrl => '${memorial['photoUrl'] ?? ''}';

  int countOf(String kind) =>
      posts.where((p) => !p.hidden && p.kind == kind).length;

  int get likeTotal =>
      posts.fold<int>(0, (a, p) => a + (p.hidden ? 0 : p.likeCount));
}

/// 추모관 REST 클라이언트.
class MemorialApi {
  MemorialApi(this.api);

  final NasApi api;

  static const String defaultMemorialId = 'noh-kyungha';

  /// 같은 기기에서 '내가 쓴 글'을 식별하기 위한 키 저장소 접두어.
  static const String _lsKeyPrefix = 'tsak_memorial_keys_';
  static const String _lsName = 'tsak_memorial_name';
  static const String _lsNum = 'tsak_memorial_num';

  /// 서버 상대경로(`/memorial-file/...`) → 절대 URL.
  String fileUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final b = api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return b + (path.startsWith('/') ? path : '/$path');
  }

  Map<String, String> get _headers => {
    ...api.authHeaderMap,
    'Content-Type': 'application/json; charset=utf-8',
  };

  // ── editKey(수정키) 로컬 보관 ────────────────────────────────────────
  //  서버는 editKey 해시만 저장하고 원문은 발급 순간에만 준다. 잃어버리면
  //  그 글을 다시는 고칠 수 없으므로(관리자 제외) 기기에 보관한다.
  Future<Map<String, String>> _keys(String mid) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('$_lsKeyPrefix$mid');
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = json.decode(raw);
      if (m is Map) {
        return m.map((k, v) => MapEntry('$k', '$v'));
      }
    } catch (_) {
      // 손상된 값은 버린다(재발급 불가 — 관리자만 삭제 가능).
    }
    return {};
  }

  Future<void> _saveKey(String mid, String postId, String key) async {
    if (postId.isEmpty || key.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final m = await _keys(mid);
    m[postId] = key;
    await sp.setString('$_lsKeyPrefix$mid', json.encode(m));
  }

  /// 이 글을 내가 고칠 수 있는가(로컬 editKey 보유 여부).
  Future<bool> canEdit(String mid, String postId) async {
    final k = (await _keys(mid))[postId];
    return k != null && k.isNotEmpty;
  }

  Future<String> editKeyOf(String mid, String postId) async =>
      (await _keys(mid))[postId] ?? '';

  /// 작성자 이름·인가번호 기억(다음 글쓰기 때 자동 채움).
  Future<void> rememberAuthor(String name, String number) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_lsName, name);
    await sp.setString(_lsNum, number);
  }

  Future<Map<String, String>> recallAuthor() async {
    final sp = await SharedPreferences.getInstance();
    return {
      'name': sp.getString(_lsName) ?? '',
      'number': sp.getString(_lsNum) ?? '',
    };
  }

  // ── 읽기 ────────────────────────────────────────────────────────────
  /// 후원계좌 3종 — `/api/memorial/accounts` (공개).
  ///
  /// [요구 2026-11-04] "추모페이지에 후원계좌 3종 하단에 넣어줘"
  ///  · 계좌를 앱에 하드코딩하지 않는다. 중앙회가 설정에서 계좌를 바꾸면
  ///    웹 추모 페이지와 앱이 **동시에** 따라간다.
  ///  · 이 엔드포인트는 로그인 없이 열린다(페이지 자체가 공개이므로).
  ///  · 실패해도 추모글은 보여야 하므로 호출부에서 빈 목록으로 처리한다.
  Future<({String holder, List<Map<String, String>> accounts})>
  loadAccounts() async {
    try {
      final uri = Uri.parse('${api.baseUrl}/api/memorial/accounts');
      final r = await http
          .get(uri, headers: api.authHeaderMap)
          .timeout(const Duration(seconds: 30));
      final j = _decode(r);
      final rows = (j['accounts'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (e) => {
              'label': '${e['label'] ?? ''}',
              'bank': '${e['bank'] ?? ''}',
              'account': '${e['account'] ?? ''}',
            },
          )
          .where((m) => (m['account'] ?? '').isNotEmpty)
          .toList();
      return (holder: '${j['holder'] ?? ''}', accounts: rows);
    } catch (_) {
      // 부가 정보 — 실패는 조용히 무시한다.
      return (holder: '', accounts: const <Map<String, String>>[]);
    }
  }

  Future<MemorialData> load({String id = defaultMemorialId}) async {
    final uri = Uri.parse('${api.baseUrl}/api/memorial/get?id=$id');
    final r = await http
        .get(uri, headers: api.authHeaderMap)
        .timeout(const Duration(seconds: 60));
    final j = _decode(r);
    if (j['ok'] != true) {
      throw Exception('${j['error'] ?? '추모관을 불러오지 못했습니다'}');
    }
    return MemorialData(
      memorial: (j['memorial'] as Map?)?.cast<String, dynamic>() ?? const {},
      posts: (j['posts'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => MemorialPost.fromMap(e.cast<String, dynamic>()))
          .toList(),
      isAdmin: j['isAdmin'] == true,
    );
  }

  // ── 쓰기 ────────────────────────────────────────────────────────────
  /// 글 작성/수정. 신규면 발급된 editKey 를 기기에 저장하고 함께 돌려준다.
  Future<Map<String, dynamic>> savePost({
    String id = defaultMemorialId,
    String postId = '',
    required String name,
    required String number,
    required String body,
    List<String> photos = const [],
    List<Map<String, dynamic>> attachments = const [],
    String editKey = '',
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/memorial/post');
    final payload = <String, dynamic>{
      'id': id,
      'name': name,
      'number': number,
      'body': body,
      'photos': photos,
      'attachments': attachments,
      if (postId.isNotEmpty) 'postId': postId,
      if (editKey.isNotEmpty) 'editKey': editKey,
    };
    final r = await http
        .post(uri, headers: _headers, body: json.encode(payload))
        .timeout(const Duration(seconds: 120));
    final j = _decode(r);
    if (j['ok'] != true) {
      throw Exception('${j['error'] ?? '저장하지 못했습니다'}');
    }
    final newKey = '${j['editKey'] ?? ''}';
    final pid = '${j['id'] ?? postId}';
    if (newKey.isNotEmpty) await _saveKey(id, pid, newKey);
    await rememberAuthor(name, number);
    return j;
  }

  Future<void> delete({
    String id = defaultMemorialId,
    required String postId,
    required String action, // delete | hide | unhide | move
    String editKey = '',
    String targetId = '',
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/memorial/delete');
    final r = await http
        .post(
          uri,
          headers: _headers,
          body: json.encode({
            'id': id,
            'postId': postId,
            'action': action,
            if (editKey.isNotEmpty) 'editKey': editKey,
            if (targetId.isNotEmpty) 'targetId': targetId,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final j = _decode(r);
    if (j['ok'] != true) {
      throw Exception('${j['error'] ?? '처리하지 못했습니다'}');
    }
  }

  /// 공감 토글. 취소까지 서버가 판단한다(likeKey 기준).
  Future<({bool liked, int count})> toggleLike({
    String id = defaultMemorialId,
    required String postId,
    required String likeKey,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/memorial/like');
    final r = await http
        .post(
          uri,
          headers: _headers,
          body: json.encode({
            'id': id,
            'postId': postId,
            'likeKey': likeKey,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final j = _decode(r);
    if (j['ok'] != true) {
      throw Exception('${j['error'] ?? '공감을 남기지 못했습니다'}');
    }
    return (
      liked: j['liked'] == true,
      count: (j['likeCount'] as num? ?? 0).toInt(),
    );
  }

  Future<void> addComment({
    String id = defaultMemorialId,
    required String postId,
    required String name,
    required String number,
    required String body,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/memorial/comment');
    final r = await http
        .post(
          uri,
          headers: _headers,
          body: json.encode({
            'id': id,
            'postId': postId,
            'name': name,
            'number': number,
            'body': body,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final j = _decode(r);
    if (j['ok'] != true) {
      throw Exception('${j['error'] ?? '댓글을 남기지 못했습니다'}');
    }
  }

  Future<void> deleteComment({
    String id = defaultMemorialId,
    required String postId,
    required String commentId,
    String editKey = '',
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/memorial/comment/delete');
    final r = await http
        .post(
          uri,
          headers: _headers,
          body: json.encode({
            'id': id,
            'postId': postId,
            'commentId': commentId,
            if (editKey.isNotEmpty) 'editKey': editKey,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final j = _decode(r);
    if (j['ok'] != true) {
      throw Exception('${j['error'] ?? '댓글을 삭제하지 못했습니다'}');
    }
  }

  /// 사진·자료 업로드 — 본문은 **원시 바이트**, 파일명은 쿼리로 보낸다.
  ///
  /// 멀티파트를 쓰지 않는 이유: 헤더 안의 한글 파일명 인코딩이 브라우저·
  /// 플랫폼마다 달라(RFC 2231/5987) 이름이 깨진다. 쿼리로 분리하면 사라진다.
  ///
  /// ## [변경 2026-11-04] `http.post(body:)` → **StreamedRequest**
  ///  사용자가 상한을 25MB → **500MB** 로 올렸다("용량 500메가로 늘리고").
  ///  `http.post(body: bytes)` 는 본문 전체를 한 덩어리로 만들어 보내므로
  ///  브라우저에서는 바이트 사본이 한 벌 더 생기고, 모바일에서는 500MB
  ///  할당이 실패해 앱이 죽는다(OOM). 이미 행사자료 업로드에서 검증된
  ///  `StreamedRequest` + 256KB 청크 방식으로 바꿔 메모리 사용을 일정하게
  ///  유지한다. (서버도 256KB씩 디스크 임시파일로 받는다 — 양쪽 다 스트리밍)
  ///
  ///  · 타임아웃 180초 → **20분**: 500MB 를 느린 회선(10Mbps)으로 올리면
  ///    약 7분이 걸린다. 중간에 끊기면 처음부터 다시 올려야 하므로 넉넉히.
  Future<Map<String, dynamic>> upload({
    String id = defaultMemorialId,
    required String name,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/memorial/upload').replace(
      queryParameters: {'id': id, 'name': name},
    );
    final req = http.StreamedRequest('POST', uri);
    req.headers.addAll(api.authHeaderMap);
    req.headers['Content-Type'] = 'application/octet-stream';
    req.headers['Content-Length'] = '${bytes.length}';

    const chunk = 262144; // 256KB
    var sent = 0;
    Future<void> pump() async {
      for (var i = 0; i < bytes.length; i += chunk) {
        final end = (i + chunk < bytes.length) ? i + chunk : bytes.length;
        req.sink.add(bytes.sublist(i, end));
        sent = end;
        onProgress?.call(sent, bytes.length);
      }
      await req.sink.close();
    }

    // pump() 를 기다리지 않고 동시에 흘려보낸다 — sink 버퍼가 소비되는 대로
    //  전송되므로 대용량에서도 메모리가 부풀지 않는다.
    pump();
    final streamed = await req.send().timeout(const Duration(minutes: 20));
    final r = await http.Response.fromStream(streamed);
    final j = _decode(r);
    if (j['ok'] != true) {
      throw Exception('${j['error'] ?? '업로드하지 못했습니다'}');
    }
    return j;
  }

  /// 응답 본문 → JSON. HTML 오류페이지(게이트웨이)도 사람이 읽을 수 있게 바꾼다.
  Map<String, dynamic> _decode(http.Response r) {
    final text = utf8.decode(r.bodyBytes, allowMalformed: true);
    try {
      final j = json.decode(text);
      if (j is Map<String, dynamic>) return j;
      if (j is Map) return j.cast<String, dynamic>();
    } catch (_) {
      // 아래 공통 메시지로.
    }
    if (r.statusCode == 401) {
      throw NasAuthException('세션이 만료되었습니다. 다시 로그인해 주세요.');
    }
    throw Exception('서버 응답을 이해할 수 없습니다 (HTTP ${r.statusCode})');
  }
}
