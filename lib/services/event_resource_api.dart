import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'nas_api.dart';

/// 행사자료 한 건 — 음원·영상·이미지·문서.
///
/// ## [요구 2026-10-28]
/// "행사때 항상 반복적으로 필요한 자료들을 재생하고, 다운로드 받을 수
///  있으면 좋겠어"
///
/// NAS 의 `행사관리/01 행사자료 (업로드가능)` 폴더를 그대로 비춘다.
/// 파일은 **NAS 가 원본**이다. 앱은 목록만 받아오고, 재생은 Range
/// 스트리밍 URL 로 흘려보낸다(곡을 끝까지 받지 않고 즉시 재생·탐색).
class EventResource {
  const EventResource({
    required this.name,
    required this.size,
    required this.mtime,
    required this.kind,
    required this.ext,
    required this.sub,
  });

  final String name;
  final int size;
  final int mtime;

  /// `audio` | `video` | `image` | `doc`
  final String kind;
  final String ext;

  /// 하위 폴더(루트면 빈 문자열).
  final String sub;

  bool get isAudio => kind == 'audio';
  bool get isVideo => kind == 'video';
  bool get isImage => kind == 'image';
  bool get isDoc => kind == 'doc';

  /// 재생 가능한가(음원·영상).
  bool get playable => isAudio || isVideo;

  /// 확장자를 뺀 표시용 이름.
  String get title {
    final i = name.lastIndexOf('.');
    return i <= 0 ? name : name.substring(0, i);
  }

  String get sizeLabel {
    if (size <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = size.toDouble();
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}${units[u]}';
  }

  static EventResource fromMap(Map<String, dynamic> m) => EventResource(
    name: '${m['name'] ?? ''}',
    size: int.tryParse('${m['size'] ?? 0}') ?? 0,
    mtime: int.tryParse('${m['mtime'] ?? 0}') ?? 0,
    kind: '${m['kind'] ?? 'doc'}',
    ext: '${m['ext'] ?? ''}',
    sub: '${m['sub'] ?? ''}',
  );
}

/// 행사자료 목록 결과.
class EventResourceList {
  const EventResourceList({
    required this.files,
    required this.folders,
    required this.sub,
  });
  final List<EventResource> files;
  final List<String> folders;
  final String sub;

  List<EventResource> byKind(String kind) =>
      files.where((e) => e.kind == kind).toList();

  static const empty = EventResourceList(
    files: <EventResource>[],
    folders: <String>[],
    sub: '',
  );
}

/// 행사자료 API — 목록·스트리밍·업로드·삭제.
class EventResourceApi {
  EventResourceApi(this.api);
  final NasApi api;

  /// 재생·내려받기 URL.
  ///
  /// ## ⚠️ 왜 세션을 URL 에 붙이는가 (2026-10-29 실측)
  /// 브라우저의 `<audio>` / `<video>` 엘리먼트는 **커스텀 헤더를 보낼 수
  /// 없다**. `X-TSAK-Session` 이 없으면 프록시가 401 을 돌려주고, 화면에는
  /// 아무 일도 일어나지 않는다(실제로 이 상태로 배포될 뻔했다).
  /// 프록시는 쿼리 `sid` 도 세션으로 인정하므로(정책 by design) 그 경로를
  /// 쓴다. 쿠키(`tsak_sid`)는 HttpOnly 라 JS 로 못 넣고, 안드로이드
  /// WebView 에서는 쿠키가 아예 없을 수 있다.
  String streamUrl(EventResource r, {bool download = false}) {
    final q = <String, String>{
      if (r.sub.isNotEmpty) 'sub': r.sub,
      'name': r.name,
      if (download) 'dl': '1',
      // <audio>/<video> 는 헤더 불가 → 쿼리로 세션 전달.
      // 세션은 서버 메모리에만 있고 로그아웃/재시작 시 즉시 무효.
      if (api.sessionId.isNotEmpty) 'sid': api.sessionId,
    };
    return Uri.parse(
      '${api.baseUrl}/api/event/res/stream',
    ).replace(queryParameters: q).toString();
  }

  /// [요구] `deep=true` 면 **하위 폴더까지 한 번에** 모아 온다.
  ///
  /// 행사 게시판은 "전체 자료"가 먼저 보여야 쓸모가 있다. 폴더를 하나씩
  /// 들어가며 찾게 만들면 현장에서 못 쓴다. 다만 폴더를 직접 탐색하고
  /// 싶을 때를 위해 `deep=false` 도 남겨 둔다.
  Future<EventResourceList> list({String sub = '', bool deep = true}) async {
    final uri = Uri.parse('${api.baseUrl}/api/event/res/list').replace(
      queryParameters: {
        if (sub.isNotEmpty) 'sub': sub,
        if (deep) 'deep': '1',
      },
    );
    final j = await api.robustGetJson(uri);
    final files = (j['files'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => EventResource.fromMap(e.cast<String, dynamic>()))
        .toList();
    final folders = (j['folders'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    return EventResourceList(
      files: files,
      folders: folders,
      sub: '${j['sub'] ?? sub}',
    );
  }

  /// 업로드 — 바이트를 **스트리밍**으로 보낸다(멀티파트 없음).
  ///
  /// ## 왜 스트리밍인가
  /// 행사 영상은 수백 MB 가 예사다. `http.post(body: bytes)` 는 본문 전체를
  /// 한 덩어리로 만들어 Content-Length 를 요구하는데, 큰 파일에서 메모리와
  /// 브라우저 전송 모두 불안정해진다. 이미 검증된 `uploadEventMedia` 와
  /// 같은 StreamedRequest 패턴을 쓴다(청크 256KB, 진행률 콜백).
  ///
  /// ## 왜 멀티파트가 아닌가
  /// 멀티파트 헤더 안의 **한글 파일명** 인코딩이 브라우저마다 다르다
  /// (RFC 2231/5987). 파일명은 쿼리로 따로 보내고 본문은 순수 바이트로
  /// 보내면 그 문제가 원천적으로 사라진다.
  Future<Map<String, dynamic>> upload({
    required String name,
    required Uint8List bytes,
    String sub = '',
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/event/res/upload').replace(
      queryParameters: {if (sub.isNotEmpty) 'sub': sub, 'name': name},
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
    //   전송되므로 대용량에서도 메모리가 부풀지 않는다. (검증된 패턴)
    pump();
    final streamed = await req.send().timeout(const Duration(minutes: 20));
    final r = await http.Response.fromStream(streamed);
    final t = utf8.decode(r.bodyBytes).trimLeft();
    if (t.startsWith('{')) {
      return (json.decode(t) as Map).cast<String, dynamic>();
    }
    return {'ok': false, 'error': 'HTTP ${r.statusCode}'};
  }

  Future<bool> delete(EventResource r) async {
    final uri = Uri.parse('${api.baseUrl}/api/event/res/delete').replace(
      queryParameters: {
        if (r.sub.isNotEmpty) 'sub': r.sub,
        'name': r.name,
      },
    );
    final j = await api.robustGetJson(uri);
    return j['ok'] == true;
  }
}
