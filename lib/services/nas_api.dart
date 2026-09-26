import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/member.dart';
import 'app_config.dart';

/// NAS 프록시 REST API 클라이언트
///
/// baseUrl 이 비어 있으면 웹앱과 동일 origin(상대경로)으로 호출한다.
class NasApi {
  NasApi({String? baseUrl})
    : _base = (baseUrl ?? AppConfig.defaultServerBase).replaceAll(
        RegExp(r'/+$'),
        '',
      );

  String _base;

  String get baseUrl => _base;
  set baseUrl(String v) => _base = v.replaceAll(RegExp(r'/+$'), '');

  Uri _uri(String path) => Uri.parse('$_base$path');

  // ---- Health ----
  Future<bool> health() async {
    try {
      final r = await http
          .get(_uri('/api/health'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return false;
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return j['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 서버 정지 여부까지 함께 확인
  Future<Map<String, dynamic>> healthState() async {
    try {
      final r = await http
          .get(_uri('/api/health'))
          .timeout(const Duration(seconds: 12));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return j.cast<String, dynamic>();
    } catch (_) {
      return {'ok': false};
    }
  }

  // ---- Auth ----
  /// tier: master | app | personal | guest
  Future<Map<String, dynamic>> login(
    String tier,
    String value, {
    String id = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/login'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'tier': tier, 'value': value, 'id': id}),
        )
        .timeout(const Duration(seconds: 15));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 마스터/관리자 전용 — 특정 회원 비밀번호 강제 변경(reset=false) 또는 초기화(reset=true)
  Future<Map<String, dynamic>> setAdminPassword({
    required String tier, // master | app
    required String id, // 인가번호 또는 전화번호
    String value = '',
    bool reset = false,
    String? master,
  }) async {
    final r = await http
        .post(
          _uri('/api/admin/set-password'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'tier': tier,
            'id': id,
            'value': value,
            'reset': reset,
            if (master != null) 'master': master,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- Members ----
  Future<List<Member>> fetchMembers() async {
    final r = await http
        .get(_uri('/api/members'))
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    final list = (j['members'] as List?) ?? [];
    return list.map((e) => Member.fromMap(e as Map)).toList();
  }

  /// 전체 DB 저장(서버가 자동 백업 후 교체)
  Future<Map<String, dynamic>> saveAll(
    List<Member> members, {
    String by = 'app',
  }) async {
    final r = await http
        .post(
          _uri('/api/members'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'members': members.map((m) => m.toMap()).toList(),
            'by': by,
          }),
        )
        .timeout(const Duration(seconds: 90));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 단일 인가자 부분 저장 (전체 DB 덮어쓰기 없이 안전하게 갱신)
  Future<Map<String, dynamic>> saveMember(
    Member member, {
    String by = 'app',
  }) async {
    final r = await http
        .post(
          _uri('/api/member'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'member': member.toMap(), 'by': by}),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- Meta / Config ----
  Future<Map<String, dynamic>> fetchMeta() async {
    final r = await http
        .get(_uri('/api/meta'))
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchConfig() async {
    final r = await http
        .get(_uri('/api/config'))
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveConfig(
    Map<String, dynamic> patch, {
    bool requirePw = false,
    String? pw,
  }) async {
    final body = Map<String, dynamic>.from(patch);
    if (requirePw) {
      body['requirePw'] = true;
      body['_pw'] = pw ?? '';
    }
    final r = await http
        .post(
          _uri('/api/config'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(body),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- Backups ----
  Future<List<Map<String, dynamic>>> backups() async {
    final r = await http
        .get(_uri('/api/backups'))
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['backups'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<String?> createBackup([String? name]) async {
    final r = await http
        .post(
          _uri('/api/backup'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'name': name ?? ''}),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true ? j['name'] as String? : null;
  }

  Future<List<Member>?> restore(String name) async {
    final r = await http
        .post(
          _uri('/api/restore'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'name': name}),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    if (j['ok'] != true) return null;
    final list = (j['members'] as List?) ?? [];
    return list.map((e) => Member.fromMap(e as Map)).toList();
  }

  // ---- Photos ----
  Future<bool> uploadPhoto(
    String number,
    List<int> bytes, {
    String ext = 'jpg',
  }) async {
    final r = await http
        .post(
          _uri('/api/photo/$number'),
          headers: {'Content-Type': 'image/$ext'},
          body: bytes,
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  String photoUrl(String number) => '$_base/api/photo/$number';

  // ---- 재무 (Finance) ----
  Future<Map<String, dynamic>> fetchFinance() async {
    final r = await http
        .get(_uri('/api/finance'))
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveFinance(Map<String, dynamic> finance) async {
    final r = await http
        .post(
          _uri('/api/finance'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(finance),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchRules() async {
    final r = await http
        .get(_uri('/api/finance/rules'))
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveRules(Map<String, dynamic> rules) async {
    final r = await http
        .post(
          _uri('/api/finance/rules'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(rules),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchHistory() async {
    final r = await http
        .get(_uri('/api/finance/history'))
        .timeout(const Duration(seconds: 30));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 은행거래파일(엑셀/CSV/이미지/PDF base64) → 서버 자동분류 결과
  ///
  /// 반환: { rows: [...], count: N, engine: 'excel'|'ocr' }
  /// 이미지/PDF는 서버가 OCR로 자동 분석한다.
  Future<Map<String, dynamic>> parseBankFull(
    String filename,
    List<int> bytes,
  ) async {
    final r = await http
        .post(
          _uri('/api/finance/parse-bank'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'filename': filename,
            'data': base64.encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 180));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 은행거래파일 → 서버 자동분류 행 목록 (하위 호환)
  Future<List<Map<String, dynamic>>> parseBank(
    String filename,
    List<int> bytes,
  ) async {
    final j = await parseBankFull(filename, bytes);
    return ((j['rows'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// DB 거래내역 종합 통계 (연도/월/분류/지출분류/행사/인가자별)
  Future<Map<String, dynamic>> fetchFinanceStats() async {
    final r = await http
        .get(_uri('/api/finance/stats'))
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return (j['stats'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// 기본자료 폴더 파일 목록
  Future<List<Map<String, dynamic>>> listFiles(String folder) async {
    final r = await http
        .get(_uri('/api/files?folder=$folder'))
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['files'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 기본자료 폴더에 파일 업로드(+자동분석)
  Future<Map<String, dynamic>> uploadFile(
    String folder,
    String name,
    List<int> bytes,
  ) async {
    final r = await http
        .post(
          _uri('/api/files'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'folder': folder,
            'name': name,
            'data': base64.encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 90));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  String fileDownloadUrl(String folder, String name) =>
      '$_base/api/files/download?folder=${Uri.encodeComponent(folder)}&name=${Uri.encodeComponent(name)}';

  // ---- 행사관리 (행사 사진·동영상 갤러리) ----
  /// 행사관리 폴더의 미디어 목록 (사진/동영상)
  Future<List<Map<String, dynamic>>> eventList() async {
    final r = await http
        .get(_uri('/api/event/list'))
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['files'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 행사 미디어 원본 URL (view=보기, download=다운로드)
  String eventFileUrl(String name, {bool download = false}) =>
      '$_base/api/event/file?name=${Uri.encodeComponent(name)}'
      '${download ? '&dl=1' : ''}';

  /// 행사 썸네일 URL (없으면 404 → 원본 사용)
  String eventThumbUrl(String name) =>
      '$_base/api/event/thumb?name=${Uri.encodeComponent(name)}';

  /// 행사 미디어 업로드 — 대용량 스트리밍(무제한), 진행률 콜백 지원
  Future<Map<String, dynamic>> uploadEventMedia(
    String name,
    List<int> bytes, {
    String contentType = 'application/octet-stream',
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = Uri.parse(
      '$_base/api/event/upload?name=${Uri.encodeComponent(name)}',
    );
    final req = http.StreamedRequest('POST', uri);
    req.headers['Content-Type'] = contentType;
    req.headers['Content-Length'] = '${bytes.length}';
    // 스트리밍 전송 (메모리 청크)
    const chunk = 262144;
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

    pump();
    final streamed = await req.send().timeout(const Duration(seconds: 1200));
    final resp = await http.Response.fromStream(streamed);
    return json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  /// 행사 미디어 삭제
  Future<bool> deleteEventMedia(String name) async {
    final r = await http
        .post(
          _uri('/api/event/media/delete'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'name': name}),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  // ==================== 행사관리 v2 (연도/행사/항목 폴더) ====================
  /// 행사 목록
  Future<List<Map<String, dynamic>>> eventList2() async {
    final r = await http
        .get(_uri('/api/event/list2'))
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['events'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 행사 상세
  Future<Map<String, dynamic>> eventGet(String year, String title) async {
    final r = await http
        .get(_uri('/api/event/get?year=${Uri.encodeComponent(year)}&title=${Uri.encodeComponent(title)}'))
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return (j['event'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// 행사 폴더(항목) 파일 목록 (+하위폴더: isdir=true 항목 포함)
  Future<List<Map<String, dynamic>>> eventFiles(
    String year,
    String title,
    String key, {
    String sub = '',
  }) async {
    final r = await http
        .get(
          _uri('/api/event/files?year=${Uri.encodeComponent(year)}'
              '&title=${Uri.encodeComponent(title)}&key=$key'
              '&sub=${Uri.encodeComponent(sub)}'),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['files'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 행사 항목 하위폴더 생성
  Future<bool> eventMediaMkdir(
    String year,
    String title,
    String key,
    String name, {
    String sub = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/event/mkdir'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'key': key,
            'sub': sub,
            'name': name,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 행사 썸네일 URL (size: normal=480px, view=1600px 최적본, orig=원본)
  String eventThumb2Url(
    String year,
    String title,
    String name, {
    String size = 'normal',
    String sub = '',
  }) =>
      '$_base/api/event/thumb2?year=${Uri.encodeComponent(year)}'
      '&title=${Uri.encodeComponent(title)}&name=${Uri.encodeComponent(name)}'
      '&sub=${Uri.encodeComponent(sub)}&size=$size';

  /// 행사 항목 파일 URL (원본 보기 / 다운로드)
  String eventFile2Url(
    String year,
    String title,
    String key,
    String name, {
    bool download = false,
    String sub = '',
  }) =>
      '$_base/api/event/f2?year=${Uri.encodeComponent(year)}'
      '&title=${Uri.encodeComponent(title)}&key=$key'
      '&name=${Uri.encodeComponent(name)}&sub=${Uri.encodeComponent(sub)}'
      '${download ? '&dl=1' : ''}';

  /// 행사 폴더 ZIP 다운로드 URL (sub=현재 하위폴더, files=선택 다운로드 'sub:name|..')
  String eventZipUrl(
    String year,
    String title,
    String key, {
    String sub = '',
    List<String>? files,
  }) {
    final fb = (files == null || files.isEmpty)
        ? ''
        : '&files=${Uri.encodeComponent(files.join('|'))}';
    return '$_base/api/event/zip?year=${Uri.encodeComponent(year)}'
        '&title=${Uri.encodeComponent(title)}&key=$key'
        '&sub=${Uri.encodeComponent(sub)}$fb';
  }

  /// 참가자 명단 HTML URL (인쇄/저장용)
  String eventRosterUrl(String year, String title) =>
      '$_base/api/event/roster?year=${Uri.encodeComponent(year)}'
      '&title=${Uri.encodeComponent(title)}';

  /// 행사 생성
  Future<Map<String, dynamic>> eventCreate({
    required String year,
    required String title,
    String period = '',
    String place = '',
    String desc = '',
    String by = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/event/create'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'period': period,
            'place': place,
            'desc': desc,
            'by': by,
          }),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 행사 이름/연도 변경
  Future<Map<String, dynamic>> eventRename({
    required String year,
    required String title,
    String? newTitle,
    String? newYear,
  }) async {
    final r = await http
        .post(
          _uri('/api/event/rename'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'newTitle': newTitle ?? title,
            'newYear': newYear ?? year,
          }),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 행사 삭제
  Future<bool> eventDelete(String year, String title) async {
    final r = await http
        .post(
          _uri('/api/event/delete'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'year': year, 'title': title}),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 참석자 목록 저장 (+회원 프로필 자동 반영)
  Future<bool> eventSetAttendees(
    String year,
    String title,
    List<Map<String, dynamic>> attendees,
  ) async {
    final r = await http
        .post(
          _uri('/api/event/attendee/set'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'attendees': attendees,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 인가자/회원 검색 (참석자 선택용)
  Future<List<Map<String, dynamic>>> eventSearchMember(String q) async {
    final r = await http
        .post(
          _uri('/api/event/search-member'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'q': q}),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['results'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 행사 항목 파일 업로드 (스트리밍)
  Future<Map<String, dynamic>> eventUpload2(
    String year,
    String title,
    String key,
    String name,
    List<int> bytes, {
    String contentType = 'application/octet-stream',
    String uploader = '',
    String sub = '',
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = Uri.parse(
      '$_base/api/event/upload2?year=${Uri.encodeComponent(year)}'
      '&title=${Uri.encodeComponent(title)}&key=$key'
      '&name=${Uri.encodeComponent(name)}&uploader=${Uri.encodeComponent(uploader)}'
      '&sub=${Uri.encodeComponent(sub)}',
    );
    final req = http.StreamedRequest('POST', uri);
    req.headers['Content-Type'] = contentType;
    req.headers['Content-Length'] = '${bytes.length}';
    const chunk = 262144;
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

    pump();
    final streamed = await req.send().timeout(const Duration(seconds: 1800));
    final resp = await http.Response.fromStream(streamed);
    return json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  /// 행사 항목 파일 삭제 (isdir=true 이면 하위폴더 삭제)
  Future<bool> eventFileDelete(
    String year,
    String title,
    String key,
    String name, {
    String sub = '',
    bool isdir = false,
  }) async {
    final r = await http
        .post(
          _uri('/api/event/file/delete'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'key': key,
            'name': name,
            'sub': sub,
            'isdir': isdir,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 행사 항목 파일 이름변경
  Future<bool> eventFileRename(
    String year,
    String title,
    String key,
    String name,
    String newName, {
    String sub = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/event/file/rename'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'key': key,
            'name': name,
            'newName': newName,
            'sub': sub,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 행사 재무(참가비/후원금/지출) 조회
  Future<Map<String, dynamic>> eventFinance(String year, String title) async {
    final r = await http
        .get(
          _uri('/api/event/finance?year=${Uri.encodeComponent(year)}'
              '&title=${Uri.encodeComponent(title)}'),
        )
        .timeout(const Duration(seconds: 30));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 행사 재무 항목 추가 (kind: fee | expense) → 재무관리 자동연동
  Future<bool> eventFinanceAdd(
    String year,
    String title,
    String kind,
    Map<String, dynamic> row,
  ) async {
    final r = await http
        .post(
          _uri('/api/event/finance/add'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'kind': kind,
            'row': row,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 행사 재무 항목 수정
  Future<bool> eventFinanceUpdate(
    String year,
    String title,
    String kind,
    String id,
    Map<String, dynamic> row,
  ) async {
    final r = await http
        .post(
          _uri('/api/event/finance/update'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'kind': kind,
            'id': id,
            'row': row,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 행사 재무 항목 삭제 (재무관리 연동 해제 포함)
  Future<bool> eventFinanceDelete(
    String year,
    String title,
    String kind,
    String id,
  ) async {
    final r = await http
        .post(
          _uri('/api/event/finance/delete'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'kind': kind,
            'id': id,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 사진+동영상 폴더 접근 로그 기록
  Future<void> eventAccessLog(
    String year,
    String title, {
    String id = '',
    String name = '',
    String role = '',
  }) async {
    try {
      await http
          .post(
            _uri('/api/event/access/log'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'year': year,
              'title': title,
              'id': id,
              'name': name,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// 참가자 접근 이력 맵 (v표시용)
  Future<Map<String, dynamic>> eventAccessMap(
    String year,
    String title,
  ) async {
    final r = await http
        .get(
          _uri('/api/event/access?year=${Uri.encodeComponent(year)}'
              '&title=${Uri.encodeComponent(title)}'),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return (j['access'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// 모든 참가자에게 사진 업로드 요청 기록
  Future<bool> eventRequestPhoto(String year, String title, {String by = '', String message = ''}) async {
    final r = await http
        .post(
          _uri('/api/event/request-photo'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'year': year, 'title': title, 'by': by, 'message': message}),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 통합 재무 엑셀 다운로드 URL
  String financeExcelUrl([String kind = 'finance']) =>
      '$_base/api/finance/excel?kind=$kind';

  // ---- 마스터 앱관리 ----
  Future<Map<String, dynamic>> adminState() async {
    final r = await http
        .get(_uri('/api/admin/state'))
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> changeAppPassword(
    String master,
    String newPw,
  ) async {
    final r = await http
        .post(
          _uri('/api/admin/app-password'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'master': master, 'new': newPw}),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setPersonalPassword(
    String master,
    String number, {
    String? value,
    bool reset = false,
  }) async {
    final r = await http
        .post(
          _uri('/api/admin/personal'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'master': master,
            'number': number,
            if (reset) 'reset': true,
            if (!reset) 'value': value ?? '',
          }),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 개인 셀프 비밀번호 변경 (본인) — 현재 비번 검증 후 새 비번 저장
  Future<Map<String, dynamic>> changePersonalPassword(
    String number,
    String current,
    String newPw,
  ) async {
    final r = await http
        .post(
          _uri('/api/personal/password'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'number': number,
            'current': current,
            'new': newPw,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setServerPaused(
    String master,
    bool paused,
  ) async {
    final r = await http
        .post(
          _uri('/api/admin/server-pause'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'master': master, 'paused': paused}),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 문의 접수 — 이메일 발송 + 첨부 저장 (개인정보 동의 필수).
  ///
  /// [files] 는 `[{'name': 파일명, 'data': base64문자열}]` 형태.
  /// 보낸사람 이메일 또는 동의가 없으면 서버가 400 을 반환한다.
  Future<Map<String, dynamic>> submitInquiry({
    required String name,
    required String email,
    String phone = '',
    String number = '',
    String subject = '',
    required String message,
    required bool agreed,
    List<Map<String, String>> files = const [],
  }) async {
    final r = await http
        .post(
          _uri('/api/inquiry/submit'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'name': name,
            'email': email,
            'phone': phone,
            'number': number,
            'subject': subject,
            'message': message,
            'agreed': agreed,
            'files': files,
          }),
        )
        .timeout(const Duration(seconds: 90));
    try {
      return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': r.statusCode == 200, 'status': r.statusCode};
    }
  }
}
