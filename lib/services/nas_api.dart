import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/member.dart';
import 'app_config.dart';

/// NAS 프록시 REST API 클라이언트
///
/// baseUrl 이 비어 있으면 웹앱과 동일 origin(상대경로)으로 호출한다.
///
/// [보안] 서버가 로그인 시 발급하는 세션토큰(sid)을 모든 요청에 실어 보낸다.
///  - 웹: 같은 출처라 쿠키(tsak_sid)가 자동 전송되지만, 방어적으로 헤더도 함께 전송.
///  - 비웹(모바일): 쿠키 jar 가 없으므로 X-TSAK-Session 헤더로 전송.
class NasApi {
  NasApi({String? baseUrl})
    : _base = (baseUrl ?? AppConfig.defaultServerBase).replaceAll(
        RegExp(r'/+$'),
        '',
      );

  String _base;

  /// 서버 발급 세션토큰 (로그인 시 설정, 로그아웃/만료 시 비움).
  String sessionId = '';

  /// 마지막 로그인이 '마스터가 지정한 관리자'였는지 여부(서버 응답).
  bool lastLoginAdmin = false;

  /// 마지막 로그인이 '서포터즈'(일반회원)였는지 여부(서버 응답).
  /// 서포터즈는 개인접근 화면은 보되 타인 개인정보는 열람할 수 없다.
  bool lastLoginSupporter = false;

  String get baseUrl => _base;

  /// 모든 요청에 공통으로 붙는 인증 헤더.
  Map<String, String> get _authHeaders =>
      sessionId.isEmpty ? const {} : {'X-TSAK-Session': sessionId};

  set baseUrl(String v) => _base = v.replaceAll(RegExp(r'/+$'), '');

  Uri _uri(String path) => Uri.parse('$_base$path');

  /// 수품 이미지 URL (로컬 파일명 또는 외부 URL → 프록시 경유, 같은 출처).
  /// [crop] 이 true 이면 상·하단 텍스트를 자동 제거한 순수 수품 이미지를 받는다.
  String merchImageUrl(String image, {bool crop = false}) {
    final s = image.trim();
    if (s.isEmpty) return '';
    final c = crop ? '&crop=1' : '';
    if (s.startsWith('http')) {
      return '$_base/api/merch/img?src=${Uri.encodeComponent(s)}$c';
    }
    return '$_base/api/merch/img?name=${Uri.encodeComponent(s)}$c';
  }

  /// 도로명주소 검색 (행정안전부 JUSO, 프록시 경유·무인증).
  Future<List<Map<String, dynamic>>> addrSearch(
    String q, {
    int page = 1,
  }) async {
    if (q.trim().isEmpty) return [];
    try {
      final r = await http
          .get(
            _uri(
              '/api/address/search?q=${Uri.encodeComponent(q)}'
              '&page=$page',
            ),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return ((j['items'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---- Health ----
  Future<bool> health() async {
    try {
      final r = await http
          .get(_uri('/api/health'), headers: _authHeaders)
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
          .get(_uri('/api/health'), headers: _authHeaders)
          .timeout(const Duration(seconds: 12));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return j.cast<String, dynamic>();
    } catch (_) {
      return {'ok': false};
    }
  }

  // ---- Auth ----
  /// tier: master | app | personal | guest
  ///
  /// [보안] 서버가 발급한 세션토큰(sid)을 자동 저장한다. 이후 모든 요청에
  /// X-TSAK-Session 헤더로 실려 나간다(웹은 동일출처 쿠키도 함께).
  /// [corps] = 'tsak'(범스카우트, 기본) | 'eunha'(은하스카우트).
  ///  은하스카우트는 별도 명단/로그인 규칙으로 검증된다.
  Future<Map<String, dynamic>> login(
    String tier,
    String value, {
    String id = '',
    String corps = 'tsak',
  }) async {
    final r = await http
        .post(
          _uri('/api/login'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'tier': tier,
            'value': value,
            'id': id,
            'corps': corps,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final sid = '${j['sid'] ?? ''}';
    lastLoginAdmin = j['admin'] == true;
    lastLoginSupporter = j['supporter'] == true;
    if (j['ok'] == true && sid.isNotEmpty) sessionId = sid;
    return j;
  }

  /// QR/세션복원용 세션 발급 (비번 입력 없이 열리는 개인 QR 전용).
  /// master 등급은 마스터 비번 확인값이 없으면 서버가 거부한다.
  Future<bool> grantSession(
    String tier, {
    String id = '',
    String? master,
    String? app,
    String corps = 'tsak',
    bool log = false,
  }) async {
    try {
      final r = await http
          .post(
            _uri('/api/session/grant'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: json.encode({
              'tier': tier,
              'id': id,
              'corps': corps,
              if (master != null) 'master': master,
              if (app != null) 'app': app,
              if (log) 'log': true,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final sid = '${j['sid'] ?? ''}';
      if (j['ok'] == true && sid.isNotEmpty) {
        sessionId = sid;
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// 세션 종료(서버측 세션 폐기)
  Future<void> logout() async {
    final old = sessionId;
    sessionId = '';
    if (old.isEmpty) return;
    try {
      await http
          .post(_uri('/api/logout'), headers: {'X-TSAK-Session': old})
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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

  // ---- 역할별 권한 (Role Permissions) ----
  /// 역할별 메뉴 접근권한 맵 조회.
  /// 반환: { roleKey: { menuKey: bool, ... }, ... }
  Future<Map<String, Map<String, bool>>> fetchPerms() async {
    try {
      final r = await http
          .get(_uri('/api/perms'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      final raw = (j['perms'] as Map?) ?? {};
      final out = <String, Map<String, bool>>{};
      raw.forEach((k, v) {
        if (v is Map) {
          out['$k'] = {for (final e in v.entries) '${e.key}': e.value == true};
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// 특정 역할의 권한 일부를 변경 (마스터 전용).
  /// [role] = master|app|personal|supporter|guest, [updates] = { menuKey: bool }
  Future<bool> setPerms(String role, Map<String, bool> updates) async {
    final r = await http
        .post(
          _uri('/api/perms/set'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'role': role, 'updates': updates}),
        )
        .timeout(const Duration(seconds: 20));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  // ---- 회원 등록요청 (평생회원·연회비·자격) ----
  /// 등록요청 제출. type: lifetime | fee | qualification
  Future<Map<String, dynamic>> memberRequestSubmit({
    required String type,
    String ident = '',
    String year = '',
    String date = '',
    String note = '',
    String newNumber = '',
    String event = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/member/request'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'type': type,
            if (ident.isNotEmpty) 'ident': ident,
            if (year.isNotEmpty) 'year': year,
            if (date.isNotEmpty) 'date': date,
            if (note.isNotEmpty) 'note': note,
            if (newNumber.isNotEmpty) 'newNumber': newNumber,
            if (event.isNotEmpty) 'event': event,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 등록요청 대기 목록(관리자·마스터).
  Future<List<Map<String, dynamic>>> memberRequestList() async {
    final r = await http
        .get(_uri('/api/member/request/list'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['pending'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 본인(로그인 세션)의 등록요청 이력 조회 — 개인 프로필의 '등록요청'
  /// 상태 표시용. 로그인 회원이면 누구나 조회 가능하다.
  /// [ident] 지정 시(관리자·마스터만) 해당 회원의 이력을 조회한다.
  Future<List<Map<String, dynamic>>> myMemberRequests({
    String ident = '',
  }) async {
    final q = ident.trim().isEmpty
        ? ''
        : '?ident=${Uri.encodeComponent(ident.trim())}';
    final r = await http
        .get(_uri('/api/member/request/mine$q'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['items'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 통합 승인 대시보드(관리자·마스터) — 승인 대기 큐 목록.
  /// 반환: {'ok':true,'queues':[...],'total':N,'unread':M}
  Future<Map<String, dynamic>> approvalOverview() async {
    final r = await http
        .get(_uri('/api/approval/overview'), headers: _authHeaders)
        .timeout(const Duration(seconds: 25));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 승인 대기 총 건수 배지용(관리자·마스터).
  Future<int> approvalPendingTotal() async {
    try {
      final j = await approvalOverview();
      return (j['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 해당 아이디가 아직 확인하지 않은 승인 대기 건수(배지용, 관리자·마스터).
  /// = 전체 대기 건수 − 이미 열어 '확인'한 워터마크 이전 건수.
  Future<int> approvalUnread() async {
    try {
      final j = await approvalOverview();
      return (j['unread'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 배지 '확인(읽음)' 처리(관리자·마스터).
  /// [kind] = 'approval'(통합 승인) | 'board'(게시판) | 'all'.
  /// 해당 아이디 기준으로 지금까지의 항목을 '확인함'으로 기록한다.
  Future<bool> badgeSeen({String kind = 'all'}) async {
    try {
      final r = await http
          .post(
            _uri('/api/badge/seen'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: json.encode({'kind': kind}),
          )
          .timeout(const Duration(seconds: 20));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return j['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 등록요청 승인/반려(관리자·마스터). action: approve | reject
  Future<bool> memberRequestSet({
    required String id,
    required String action,
  }) async {
    final r = await http
        .post(
          _uri('/api/member/request/set'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id, 'action': action}),
        )
        .timeout(const Duration(seconds: 25));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 등록요청 삭제(관리자·마스터) — 내역 목록에서 제거.
  Future<bool> memberRequestDelete(String id) =>
      memberRequestSet(id: id, action: 'delete');

  // ---- 개인 제안 행사(심사중) ----
  /// 개인프로필에서 새 행사를 제안(관리자·마스터 승인 전 '심사중').
  Future<Map<String, dynamic>> eventPrivateCreate({
    required String year,
    required String title,
    String period = '',
    String place = '',
    String desc = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/event/private/create'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'period': period,
            'place': place,
            'desc': desc,
          }),
        )
        .timeout(const Duration(seconds: 25));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 본인이 제안한 심사중 행사 목록.
  Future<List<Map<String, dynamic>>> eventPrivateMine() async {
    try {
      final r = await http
          .get(_uri('/api/event/private/mine'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return ((j['items'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 심사중 제안 행사 승인/반려/삭제(관리자·마스터).
  Future<bool> eventPrivateSet({
    required String id,
    required String action,
  }) async {
    try {
      final r = await http
          .post(
            _uri('/api/event/private/set'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: json.encode({'id': id, 'action': action}),
          )
          .timeout(const Duration(seconds: 25));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return j['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // ---- 행사 스텝(STAFF) ----
  /// 행사 스텝 등록(관리자·마스터) — 지정자는 행사 전체 게시판 노출.
  Future<List<Map<String, dynamic>>> eventStaffAdd({
    required String year,
    required String title,
    required String number,
  }) async {
    final r = await http
        .post(
          _uri('/api/event/staff/add'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'year': year, 'title': title, 'number': number}),
        )
        .timeout(const Duration(seconds: 25));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['staff'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 행사 스텝 해제(관리자·마스터).
  Future<List<Map<String, dynamic>>> eventStaffRemove({
    required String year,
    required String title,
    required String number,
  }) async {
    final r = await http
        .post(
          _uri('/api/event/staff/remove'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'year': year, 'title': title, 'number': number}),
        )
        .timeout(const Duration(seconds: 25));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['staff'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  // ---- Members ----
  Future<List<Member>> fetchMembers() async {
    final r = await http
        .get(_uri('/api/members'), headers: _authHeaders)
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    final list = (j['members'] as List?) ?? [];
    return list.map((e) => Member.fromMap(e as Map)).toList();
  }

  /// 은하스카우트 별도 명단 조회(관리자·마스터 전용).
  Future<List<Member>> fetchEunhaMembers() async {
    final r = await http
        .get(_uri('/api/eunha/members'), headers: _authHeaders)
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'members': members.map((m) => m.toMap()).toList(),
            'by': by,
          }),
        )
        .timeout(const Duration(seconds: 90));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 단일 인가자 부분 저장 (전체 DB 덮어쓰기 없이 안전하게 갱신)
  ///   [linkRequestSource] = 'merch'(수품신청시) | 'direct'(직접입력) | ''
  Future<Map<String, dynamic>> saveMember(
    Member member, {
    String by = 'app',
    String linkRequestSource = '',
  }) async {
    final body = <String, dynamic>{'member': member.toMap(), 'by': by};
    if (linkRequestSource.isNotEmpty) {
      body['linkRequestSource'] = linkRequestSource;
    }
    final r = await http
        .post(
          _uri('/api/member'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode(body),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 선택 계정 완전 삭제(마스터 전용). [corps] 로 소속 명단을 지정한다.
  Future<Map<String, dynamic>> deleteMembers(
    List<String> ids, {
    String corps = 'tsak',
  }) async {
    final r = await http
        .post(
          _uri('/api/member/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'ids': ids, 'corps': corps}),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- Meta / Config ----
  Future<Map<String, dynamic>> fetchMeta() async {
    final r = await http
        .get(_uri('/api/meta'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchConfig() async {
    final r = await http
        .get(_uri('/api/config'), headers: _authHeaders)
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode(body),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- Backups ----
  Future<List<Map<String, dynamic>>> backups() async {
    final r = await http
        .get(_uri('/api/backups'), headers: _authHeaders)
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
          headers: {..._authHeaders, 'Content-Type': 'image/$ext'},
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
        .get(_uri('/api/finance'), headers: _authHeaders)
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveFinance(Map<String, dynamic> finance) async {
    final r = await http
        .post(
          _uri('/api/finance'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode(finance),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchRules() async {
    final r = await http
        .get(_uri('/api/finance/rules'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveRules(Map<String, dynamic> rules) async {
    final r = await http
        .post(
          _uri('/api/finance/rules'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode(rules),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchHistory() async {
    final r = await http
        .get(_uri('/api/finance/history'), headers: _authHeaders)
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
        .get(_uri('/api/finance/stats'), headers: _authHeaders)
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return (j['stats'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// 기본자료 폴더 파일 목록
  Future<List<Map<String, dynamic>>> listFiles(String folder) async {
    final r = await http
        .get(_uri('/api/files?folder=$folder'), headers: _authHeaders)
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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

  /// (요구#2) 명단 주소록(엑셀) → 회원정보 반영.
  ///  기본은 **비파괴**: 빈 필드만 채우고 기존 값은 보존한다.
  ///  dry=true 면 실제 저장 없이 미리보기(매칭/갱신 예정 건수)만 돌려준다.
  Future<Map<String, dynamic>> mergeAddressbook(
    String filename,
    List<int> bytes, {
    bool overwrite = false,
    bool dry = false,
  }) async {
    final r = await http
        .post(
          _uri('/api/members/merge-addressbook'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'filename': filename,
            'data': base64.encode(bytes),
            'overwrite': overwrite,
            'dry': dry,
          }),
        )
        .timeout(const Duration(seconds: 180));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- 행사관리 (행사 사진·동영상 갤러리) ----
  /// 행사관리 폴더의 미디어 목록 (사진/동영상)
  Future<List<Map<String, dynamic>>> eventList() async {
    final r = await http
        .get(_uri('/api/event/list'), headers: _authHeaders)
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'name': name}),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  // ==================== 행사관리 v2 (연도/행사/항목 폴더) ====================
  /// 행사 목록 (행사관리 정의 + 개인프로필 행사명 합집합, 참가인원/장소/
  /// 사진·동영상 개수/생성자 포함)
  Future<List<Map<String, dynamic>>> eventList2({bool media = true}) async {
    final r = await http
        .get(
          _uri('/api/event/list2${media ? '?media=1' : ''}'),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['events'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 행사명만 제거 — events.json(있으면) + 모든 개인 프로필(eventAttend).
  /// 관리목록누락(프로필에만 있는) 행사 정리에 사용.
  Future<bool> eventNameDelete(List<String> names) async {
    final r = await http
        .post(
          _uri('/api/event/name/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'names': names}),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 행사 상세
  Future<Map<String, dynamic>> eventGet(String year, String title) async {
    final r = await http
        .get(
          _uri(
            '/api/event/get?year=${Uri.encodeComponent(year)}&title=${Uri.encodeComponent(title)}',
          ),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return (j['event'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// 모든 행사의 사진을 행사 순서대로 모아 반환(행사별 구분용 그룹).
  Future<Map<String, dynamic>> eventAllPhotos() async {
    final r = await http
        .get(_uri('/api/event/photos/all'), headers: _authHeaders)
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
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
          _uri(
            '/api/event/files?year=${Uri.encodeComponent(year)}'
            '&title=${Uri.encodeComponent(title)}&key=$key'
            '&sub=${Uri.encodeComponent(sub)}',
          ),
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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

  /// 행사 썸네일 일괄 생성(백필) 시작 — 관리자·마스터 전용.
  Future<Map<String, dynamic>> eventThumbsBackfill({
    bool force = false,
    int maxSide = 480,
  }) async {
    final r = await http
        .post(
          _uri('/api/event/thumbs/backfill'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'force': force, 'maxSide': maxSide}),
        )
        .timeout(const Duration(seconds: 30));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 행사 썸네일 백필 진행상황 조회.
  Future<Map<String, dynamic>> eventThumbsStatus() async {
    final r = await http
        .get(_uri('/api/event/thumbs/status'), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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

  /// 행사 사용자 정의 '메뉴추가' 탭 저장 (PDF page9 최종 결정).
  /// [tabs] = [{'name': '...', 'note': '...'}]
  Future<bool> eventTabsSave({
    required String year,
    required String title,
    required List<Map<String, dynamic>> tabs,
  }) async {
    final r = await http
        .post(
          _uri('/api/event/meta'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'year': year, 'title': title, 'customTabs': tabs}),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
  Future<List<Map<String, dynamic>>> eventSearchMember(
    String q, {
    int limit = 30,
  }) async {
    final r = await http
        .post(
          _uri('/api/event/search-member'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'q': q, 'limit': limit}),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['results'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 행사 참가자 일괄 추가(다중 선택) — 서버가 중복 제거 후 병합한다.
  Future<Map<String, dynamic>> eventAttendeesAdd(
    String year,
    String title,
    List<Map<String, dynamic>> attendees,
  ) async {
    final r = await http
        .post(
          _uri('/api/event/attendees/add'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'attendees': attendees,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j.cast<String, dynamic>();
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
          _uri(
            '/api/event/finance?year=${Uri.encodeComponent(year)}'
            '&title=${Uri.encodeComponent(title)}',
          ),
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
  Future<Map<String, dynamic>> eventAccessMap(String year, String title) async {
    final r = await http
        .get(
          _uri(
            '/api/event/access?year=${Uri.encodeComponent(year)}'
            '&title=${Uri.encodeComponent(title)}',
          ),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return (j['access'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// 모든 참가자에게 사진 업로드 요청 기록
  Future<bool> eventRequestPhoto(
    String year,
    String title, {
    String by = '',
    String message = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/event/request-photo'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'by': by,
            'message': message,
          }),
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
        .get(_uri('/api/admin/state'), headers: _authHeaders)
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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

  /// 현재 접속 비밀번호 조회 (마스터 전용) — 실제 지정 비번값 반환
  Future<Map<String, dynamic>> memberPassword(String number) async {
    final r = await http
        .get(
          _uri('/api/member/password?number=${Uri.encodeComponent(number)}'),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 15));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 회원 접속 로그 조회 (마스터 전용) — 최신 100건.
  Future<List<Map<String, dynamic>>> memberAccessLog(String number) async {
    final r = await http
        .get(
          _uri('/api/member/access-log?number=${Uri.encodeComponent(number)}'),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 15));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return ((j['logs'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 전체 회원 접속·열람 로그 조회 (마스터 전용, 대시보드용).
  ///  limit: 최대 조회 건수(기본 200).
  Future<List<Map<String, dynamic>>> allAccessLogs({int limit = 200}) async {
    final r = await http
        .get(_uri('/api/access/logs?limit=$limit'), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return ((j['logs'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 프로필 열람 로그 기록 (마스터/관리자/타 회원이 개인 프로필을 열람한 이력).
  Future<void> logProfileView(String number) async {
    try {
      await http
          .post(
            _uri('/api/member/access-log/view'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: json.encode({'number': number}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// 접속 로그 삭제 (마스터 전용).
  ///  mode: 'one'(ts+number 1건) | 'member'(해당 회원 전체) | 'all'(전체)
  ///        | 'bulk'(선택 삭제 — items: [{ts, ident}, ...])
  Future<bool> deleteAccessLog({
    String mode = 'one',
    String? ts,
    String? number,
    List<Map<String, dynamic>>? items,
  }) async {
    final r = await http
        .post(
          _uri('/api/member/access-log/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'mode': mode,
            if (ts != null) 'ts': ts,
            if (number != null) 'number': number,
            if (items != null) 'items': items,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return j['ok'] == true;
  }

  /// 일반회원 승인 대기 목록 (관리자·마스터).
  Future<List<Map<String, dynamic>>> approvalPending() async {
    final r = await http
        .get(_uri('/api/approval/pending'), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return ((j['pending'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 일반회원 승인 처리 (관리자·마스터).
  ///  action: 'approve' | 'hold' | 'pending' | 'delete'
  Future<Map<String, dynamic>> approvalSet({
    required String action,
    required List<String> idents,
  }) async {
    final r = await http
        .post(
          _uri('/api/approval/set'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'action': action, 'idents': idents}),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 승인 히스토리 목록 (관리자·마스터) — 통합승인관리 하단 히스토리.
  ///  [source] = ''(전체) | 'regular' | 'request' | 'link'
  Future<List<Map<String, dynamic>>> approvalHistory({
    int limit = 200,
    String source = '',
  }) async {
    final q = <String, String>{'limit': '$limit'};
    if (source.isNotEmpty) q['source'] = source;
    final uri = _uri('/api/approval/history').replace(queryParameters: q);
    final r = await http
        .get(uri, headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return ((j['items'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 히스토리 항목 복원 — 다시 승인창(대기 큐)으로 올린다 (관리자·마스터).
  Future<bool> approvalHistoryRestore({required String id}) async {
    final r = await http
        .post(
          _uri('/api/approval/history/restore'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id}),
        )
        .timeout(const Duration(seconds: 25));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 히스토리 항목 삭제 (관리자·마스터).
  Future<bool> approvalHistoryDelete({required List<String> ids}) async {
    final r = await http
        .post(
          _uri('/api/approval/history/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'ids': ids}),
        )
        .timeout(const Duration(seconds: 25));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 회원 이름 공개/비공개 토글 (관리자·마스터). 개인 프로필 좌우 버튼.
  Future<Map<String, dynamic>> setMemberNameVisible({
    required String ident,
    required bool visible,
  }) async {
    final r = await http
        .post(
          _uri('/api/member/name-visible'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'ident': ident, 'visible': visible}),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 멘토·페런츠 연결 승인 대기 목록 (관리자·마스터).
  Future<List<Map<String, dynamic>>> linkPending() async {
    final r = await http
        .get(_uri('/api/link/pending'), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return ((j['pending'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 멘토·페런츠 연결 승인 처리 (관리자·마스터).
  ///  action: 'approve' | 'hold' | 'pending'
  Future<Map<String, dynamic>> linkSet({
    required String action,
    required List<String> idents,
    String note = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/link/set'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'action': action, 'idents': idents, 'note': note}),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// '범스카우트 인가정보 연동' 검색 — 멘토·페런츠 인적사항을 수동 입력할 때
  ///   기존 범스카우트 인가자의 정보(번호·이름·연맹·단위대·전화·스카우트번호)를
  ///   불러와 자동 채우기 위한 검색. q: 인가번호/이름/전화.
  Future<List<Map<String, dynamic>>> linkSearchMembers(
    String q, {
    int limit = 20,
  }) async {
    try {
      final r = await http
          .get(
            _uri('/api/link/search?q=${Uri.encodeComponent(q)}&limit=$limit'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final list = (j['members'] as List?) ?? [];
      return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return [];
    }
  }

  /// 멘토·페런츠(수동 등록) 인적사항 조회.
  ///   관리자·마스터: 전체, 개인(로그인): 본인 연결만.
  Future<Map<String, dynamic>> linkProfiles() async {
    try {
      final r = await http
          .get(_uri('/api/link/profiles'), headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      return (j['profiles'] as Map?)?.cast<String, dynamic>() ?? {};
    } catch (_) {
      return {};
    }
  }

  /// 멘토·페런츠(수동 등록) 인적사항 저장/삭제 —
  ///   전화번호 기반 아이디/비번을 서버가 생성해 돌려준다.
  ///   action: 'save'(기본) | 'delete'
  Future<Map<String, dynamic>> linkProfileSave({
    required Map<String, dynamic> profile,
    String action = 'save',
  }) async {
    final r = await http
        .post(
          _uri('/api/link/profiles'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'action': action, 'profile': profile}),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> linkProfileDelete(String number) async {
    final r = await http
        .post(
          _uri('/api/link/profiles'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'action': 'delete', 'number': number}),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 명부관리: 멘토/페런츠 프로필의 '받는분의 범인가번호'만 저장(관리자·마스터).
  Future<Map<String, dynamic>> linkProfileSetReceiver({
    required String number,
    required String receiverNo,
  }) async {
    try {
      final r = await http
          .post(
            _uri('/api/link/profiles'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: json.encode({
              'action': 'receiver',
              'number': number,
              'receiverNo': receiverNo,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false};
    }
  }

  /// 개인프로필 연동 — 해당 인가번호의 각인 메달 수상(받은)/수여(해준) 기록.
  Future<Map<String, dynamic>> memberMedals({String number = ''}) async {
    try {
      final q = number.isNotEmpty
          ? '?number=${Uri.encodeComponent(number)}'
          : '';
      final r = await http
          .get(_uri('/api/member/medals$q'), headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false, 'awards': [], 'granted': []};
    }
  }

  /// 멘토·페런츠 연결 승인요청 — 회원(본인) 또는 관리자·마스터.
  ///   성공 시 관리자·마스터의 승인관리 배지에 반영된다.
  Future<Map<String, dynamic>> linkRequest({
    String number = '',
    String note = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/member/link-request'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'number': number, 'note': note}),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 은행거래 종합분석 (캐시) — 관리자·마스터.
  Future<Map<String, dynamic>> financeAnalysis({bool force = false}) async {
    final r = await http
        .get(
          _uri('/api/finance/analysis?force=${force ? 1 : 0}'),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 90));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return (j['analysis'] as Map?)?.cast<String, dynamic>() ?? j;
  }

  /// 은행거래 종합분석 — 항상 최신 폴더 기준 재분석(작업중 화면용).
  Future<Map<String, dynamic>> financeAnalysisFresh() async {
    final r = await http
        .get(_uri('/api/finance/analysis/fresh'), headers: _authHeaders)
        .timeout(const Duration(minutes: 5));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return (j['analysis'] as Map?)?.cast<String, dynamic>() ?? j;
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'number': number,
            'current': current,
            'new': newPw,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 비밀번호 초기화 요청 (본인) — 분실 시 관리자·마스터에게 초기화 요청.
  /// 요구: "비밀번호 분실 변경시 관리자나 마스터에게 초기화 요청하십시요."
  Future<Map<String, dynamic>> requestPasswordReset(String number) async {
    final r = await http
        .post(
          _uri('/api/personal/password-request'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'number': number}),
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
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

  // ============================ 행사 후기 게시판 ============================

  /// 행사 후기 목록 조회.
  Future<Map<String, dynamic>> reviewList(String year, String title) async {
    final r = await http
        .get(
          _uri(
            '/api/event/review/list?year=${Uri.encodeComponent(year)}'
            '&title=${Uri.encodeComponent(title)}',
          ),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 후기 글 작성/수정(임시저장 draft 지원). 반환: {ok, id}
  Future<Map<String, dynamic>> reviewSave({
    required String year,
    required String title,
    String id = '',
    String author = '',
    String number = '',
    required String body,
    bool draft = false,
    String password = '',
    String pwdHint = '',
    String device = '',
    List<String> attachments = const [],
  }) async {
    final r = await http
        .post(
          _uri('/api/event/review/post'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'id': id,
            'author': author,
            'number': number,
            'body': body,
            'draft': draft,
            'password': password,
            'pwdHint': pwdHint,
            'device': device,
            'attachments': attachments,
          }),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 후기 댓글 추가.
  Future<Map<String, dynamic>> reviewComment({
    required String year,
    required String title,
    required String postId,
    String author = '',
    String number = '',
    required String body,
    String password = '',
    String device = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/event/review/comment'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'postId': postId,
            'author': author,
            'number': number,
            'body': body,
            'password': password,
            'device': device,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 좋아요/공감 토글. 반환: {ok, likes}
  Future<Map<String, dynamic>> reviewLike({
    required String year,
    required String title,
    required String postId,
    required bool on,
  }) async {
    final r = await http
        .post(
          _uri('/api/event/review/like'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'postId': postId,
            'on': on,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 후기 글/댓글 삭제 (글은 비밀번호 보호 시 password 필요).
  Future<bool> reviewDelete({
    required String year,
    required String title,
    String postId = '',
    String commentId = '',
    String password = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/event/review/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'year': year,
            'title': title,
            'postId': postId,
            'commentId': commentId,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  // ==================== 행사 + 수품판매 게시판 (#12) ====================
  /// 게시판 글 목록. 반환: {ok, posts, isAdmin}
  Future<Map<String, dynamic>> boardList() async {
    final r = await http
        .get(_uri('/api/board/list'), headers: _authHeaders)
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 게시판 글 상세.
  Future<Map<String, dynamic>> boardGet(String id) async {
    final r = await http
        .get(
          _uri('/api/board/get?id=${Uri.encodeComponent(id)}'),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 게시판 글 작성/수정. 반환: {ok, id}
  Future<Map<String, dynamic>> boardSave({
    String id = '',
    String category = '일반',
    required String title,
    required String body,
    String author = '',
    String number = '',
    bool hidden = false,
    String password = '',
    String pwdHint = '',
    String device = '',
    List<String> attachments = const [],
    List<String> media = const [],
    List<String> links = const [],
  }) async {
    final r = await http
        .post(
          _uri('/api/board/post'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'id': id,
            'category': category,
            'title': title,
            'body': body,
            'author': author,
            'number': number,
            'hidden': hidden,
            'password': password,
            'pwdHint': pwdHint,
            'device': device,
            'attachments': attachments,
            'media': media,
            'links': links,
          }),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 게시판 댓글 추가.
  Future<Map<String, dynamic>> boardComment({
    required String postId,
    String author = '',
    String number = '',
    required String body,
    String password = '',
    String device = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/board/comment'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'postId': postId,
            'author': author,
            'number': number,
            'body': body,
            'password': password,
            'device': device,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 게시판 좋아요 토글. 반환: {ok, likes}
  Future<Map<String, dynamic>> boardLike({
    required String postId,
    required bool on,
  }) async {
    final r = await http
        .post(
          _uri('/api/board/like'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'postId': postId, 'on': on}),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 게시판 글/댓글 삭제.
  Future<bool> boardDelete({
    String postId = '',
    String commentId = '',
    String password = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/board/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'postId': postId,
            'commentId': commentId,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 게시판 글 비노출 토글(관리자 이상).
  Future<Map<String, dynamic>> boardHide({
    required String postId,
    required bool hidden,
  }) async {
    final r = await http
        .post(
          _uri('/api/board/hide'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'postId': postId, 'hidden': hidden}),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 게시판 조회수 증가.
  Future<void> boardView(String postId) async {
    try {
      await http
          .post(
            _uri('/api/board/view'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: json.encode({'postId': postId}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
  }

  /// 알림 목록(관리자 이상). 반환: {ok, items, unread}
  Future<Map<String, dynamic>> notifyList() async {
    final r = await http
        .get(_uri('/api/notify/list'), headers: _authHeaders)
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ==================== 수품구매 (굿즈) ====================
  /// 공개 상품목록/설정/연회비 납부여부 조회. 로그인 불필요.
  /// [ident] = 인가번호 또는 전화번호(연회비 판단용, 선택)
  Future<Map<String, dynamic>> merch({
    String ident = '',
    String year = '',
  }) async {
    final q = <String>[];
    if (ident.isNotEmpty) q.add('ident=${Uri.encodeComponent(ident)}');
    if (year.isNotEmpty) q.add('year=${Uri.encodeComponent(year)}');
    final qs = q.isEmpty ? '' : '?${q.join('&')}';
    final r = await http
        .get(_uri('/api/merch$qs'), headers: _authHeaders)
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자용: 상품/주문/설정 전체 조회.
  Future<Map<String, dynamic>> merchAdmin({String year = ''}) async {
    final qs = year.isEmpty ? '' : '?year=${Uri.encodeComponent(year)}';
    final r = await http
        .get(_uri('/api/merch/admin$qs'), headers: _authHeaders)
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 주문 생성 (무인증 가능). 반환: {ok, order, contactId, contactType, account}
  Future<Map<String, dynamic>> merchOrder({
    required String productId,
    required String buyerName,
    required String buyerNumber,
    int qty = 1,
    String option = '',
    String size = '',
    String phone = '',
    String email = '',
    String address = '',
    String shipMethod = '현장구매',
    String shipNote = '',
    String memo = '',
    int? unitPrice,
    bool addAnnualFee = false,
    String year = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/order'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'productId': productId,
            'buyerName': buyerName,
            'buyerNumber': buyerNumber,
            'qty': qty,
            'option': option,
            'size': size,
            'phone': phone,
            'email': email,
            'address': address,
            'shipMethod': shipMethod,
            'shipNote': shipNote,
            'memo': memo,
            if (addAnnualFee) 'addAnnualFee': true,
            if (unitPrice != null) 'unitPrice': unitPrice,
            if (year.isNotEmpty) 'year': year,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 예약/수요조사 접수 (무인증 가능). 구매의사만 기록.
  Future<Map<String, dynamic>> merchReserve({
    required String productId,
    required String buyerName,
    required String buyerNumber,
    int qty = 1,
    String option = '',
    String size = '',
    String phone = '',
    String email = '',
    String note = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/reserve'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'productId': productId,
            'buyerName': buyerName,
            'buyerNumber': buyerNumber,
            'qty': qty,
            'option': option,
            'size': size,
            'phone': phone,
            'email': email,
            'note': note,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 장바구니 일괄 주문 — 모든 품목이 **하나의 주문번호(orderNo)** 를 공유한다.
  /// [lines]: [{productId, qty, option, size, unitPrice}] 형태의 목록.
  Future<Map<String, dynamic>> merchOrderBatch({
    required List<Map<String, dynamic>> lines,
    required String buyerName,
    required String buyerNumber,
    String phone = '',
    String email = '',
    String address = '',
    String shipMethod = '현장구매',
    String shipNote = '',
    String memo = '',
    String option = '',
    bool addAnnualFee = false,
    String year = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/order'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'lines': lines,
            'buyerName': buyerName,
            'buyerNumber': buyerNumber,
            'phone': phone,
            'email': email,
            'address': address,
            'shipMethod': shipMethod,
            'shipNote': shipNote,
            'memo': memo,
            'option': option,
            if (addAnnualFee) 'addAnnualFee': true,
            if (year.isNotEmpty) 'year': year,
          }),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 내 수품 주문/예약 내역(상태 파이프라인 포함).
  Future<Map<String, dynamic>> merchMine({required String ident}) async {
    final qs = '?ident=${Uri.encodeComponent(ident)}';
    final r = await http
        .get(_uri('/api/merch/mine$qs'), headers: _authHeaders)
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 연회비 단독 납부 주문 생성.
  Future<Map<String, dynamic>> merchEnrollFee({
    required String ident,
    String phone = '',
  }) async {
    final q = <String>['ident=${Uri.encodeComponent(ident)}'];
    if (phone.isNotEmpty) q.add('phone=${Uri.encodeComponent(phone)}');
    final r = await http
        .get(
          _uri('/api/merch/enroll-fee?${q.join('&')}'),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 누적판매/재고/예약 통계.
  Future<Map<String, dynamic>> merchReports() async {
    final r = await http
        .get(_uri('/api/merch/reports'), headers: _authHeaders)
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 수품판매대장(주문+예약 통합). {ok, rows, summary}
  Future<Map<String, dynamic>> merchLedger({
    String year = '',
    String month = '',
    String kind = '',
  }) async {
    final q = <String>[];
    if (year.isNotEmpty) q.add('year=${Uri.encodeComponent(year)}');
    if (month.isNotEmpty) q.add('month=${Uri.encodeComponent(month)}');
    if (kind.isNotEmpty) q.add('kind=${Uri.encodeComponent(kind)}');
    final qs = q.isEmpty ? '' : '?${q.join('&')}';
    final r = await http
        .get(_uri('/api/merch/ledger$qs'), headers: _authHeaders)
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 수품판매대장 CSV 다운로드 URL.
  String merchLedgerCsvUrl({String year = '', String month = ''}) {
    final q = <String>[];
    if (year.isNotEmpty) q.add('year=${Uri.encodeComponent(year)}');
    if (month.isNotEmpty) q.add('month=${Uri.encodeComponent(month)}');
    final qs = q.isEmpty ? '' : '?${q.join('&')}';
    return '$_base/api/merch/ledger/csv$qs';
  }

  /// 관리자: 예약 상태/메모/수량 수정.
  Future<Map<String, dynamic>> merchUpdateReserve({
    required String id,
    String? status,
    String? memo,
    int? qty,
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/reserve/update'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'id': id,
            if (status != null) 'status': status,
            if (memo != null) 'memo': memo,
            if (qty != null) 'qty': qty,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<bool> merchDeleteReserve(String id) async {
    final r = await http
        .post(
          _uri('/api/merch/reserve/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 관리자: 수품 제작자 등록/수정.
  Future<Map<String, dynamic>> merchSaveMaker(Map<String, dynamic> data) async {
    final r = await http
        .post(
          _uri('/api/merch/maker'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode(data),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<bool> merchDeleteMaker(String id) async {
    final r = await http
        .post(
          _uri('/api/merch/maker/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 관리자: 제작자 첨부파일 업로드(base64). 반환: {ok, file, url}
  Future<Map<String, dynamic>> merchMakerUpload(
    String filename,
    String dataB64,
  ) async {
    final r = await http
        .post(
          _uri('/api/merch/maker/upload'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'filename': filename, 'data': dataB64}),
        )
        .timeout(const Duration(seconds: 120));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  String merchFileUrl(String name) =>
      '$_base/api/merch/file?name=${Uri.encodeComponent(name)}';

  /// 관리자: 상품 이미지 업로드 (base64). 반환: {ok, file, url}
  Future<Map<String, dynamic>> merchImageUpload(
    String filename,
    String dataB64,
  ) async {
    final r = await http
        .post(
          _uri('/api/merch/img/upload'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'filename': filename, 'data': dataB64}),
        )
        .timeout(const Duration(seconds: 120));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 수품 공여(행사/홍보) 기록.
  Future<Map<String, dynamic>> merchSaveDonation(
    Map<String, dynamic> data,
  ) async {
    final r = await http
        .post(
          _uri('/api/merch/donation'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode(data),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 재고 입출고(+/-).
  Future<Map<String, dynamic>> merchStock(
    String productId,
    int delta, {
    String note = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/stock'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'productId': productId,
            'delta': delta,
            'note': note,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> merchSaveProduct({
    String id = '',
    required String name,
    String kind = '',
    int price = 0,
    int stock = 0,
    List<String> options = const [],
    String image = '',
    String desc = '',
    String size = '',
    String makerId = '',
    int cost = 0,
    String madeDate = '',
    List<Map<String, String>> specList = const [],
    String quoteFile = '',
    String quoteFileName = '',
    bool active = true,
    bool credentialOnly = false,
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/product'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'id': id,
            'name': name,
            'kind': kind,
            'price': price,
            'stock': stock,
            'options': options,
            'image': image,
            'desc': desc,
            'size': size,
            'makerId': makerId,
            'cost': cost,
            'madeDate': madeDate,
            'specList': specList,
            'quoteFile': quoteFile,
            'quoteFileName': quoteFileName,
            'active': active,
            'credentialOnly': credentialOnly,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<bool> merchDeleteProduct(String id) async {
    final r = await http
        .post(
          _uri('/api/merch/product/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 관리자: 상품 표시 순서 저장(좌측 드래그 정렬).
  Future<bool> merchProductsOrder(List<String> ids) async {
    final r = await http
        .post(
          _uri('/api/merch/products/order'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'ids': ids}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 관리자: 중앙회 비품(재고 리스트) 등록/수정.
  ///
  /// [id] 가 비면 신규, 있으면 수정. [whoName] 은 확인자 이름 표기용.
  Future<Map<String, dynamic>> merchSaveSupply({
    String id = '',
    required String name,
    int qty = 0,
    String note = '',
    String checkedAt = '',
    String whoName = '',
    String photo = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/supplies'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'id': id,
            'name': name,
            'qty': qty,
            'note': note,
            if (checkedAt.isNotEmpty) 'checkedAt': checkedAt,
            if (whoName.isNotEmpty) 'whoName': whoName,
            'photo': photo,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 비품 삭제.
  Future<bool> merchDeleteSupply(String id) async {
    final r = await http
        .post(
          _uri('/api/merch/supplies/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 관리자: 물건 결제 항목 등록/수정.
  Future<Map<String, dynamic>> merchSavePurchase({
    String id = '',
    String group = '',
    String category = '',
    String size = '',
    int qty = 0,
    int unitPrice = 0,
    int amount = 0,
    String note = '',
    String photo = '',
    String date = '',
    String makerId = '',
    int cost = 0,
    String madeDate = '',
    String whoName = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/purchase'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'id': id,
            'group': group,
            'category': category,
            'size': size,
            'qty': qty,
            'unitPrice': unitPrice,
            'amount': amount,
            'note': note,
            'photo': photo,
            'date': date,
            'makerId': makerId,
            'cost': cost,
            'madeDate': madeDate,
            if (whoName.isNotEmpty) 'whoName': whoName,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 물건 결제 항목 삭제.
  Future<bool> merchDeletePurchase(String id) async {
    final r = await http
        .post(
          _uri('/api/merch/purchase/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 관리자: 비품 표시 순서 저장(좌측 드래그 정렬).
  Future<bool> merchSuppliesOrder(List<String> ids) async {
    final r = await http
        .post(
          _uri('/api/merch/supplies/order'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'ids': ids}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 관리자: 기획실 아이템 등록/수정.
  Future<Map<String, dynamic>> merchSavePlan({
    String id = '',
    required String name,
    String photo = '',
    String video = '',
    String desc = '',
    String memo = '',
    int price = 0,
    String maker = '',
    String submittedAt = '',
    String progress = '',
    int minQty = 0,
    bool? surveyOpen,
    String whoName = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/plan'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'id': id,
            'name': name,
            'photo': photo,
            'video': video,
            'desc': desc,
            'memo': memo,
            'price': price,
            'maker': maker,
            'submittedAt': submittedAt,
            'progress': progress,
            'minQty': minQty,
            if (surveyOpen != null) 'surveyOpen': surveyOpen,
            if (whoName.isNotEmpty) 'whoName': whoName,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 기획 아이템 삭제.
  Future<bool> merchDeletePlan(String id) async {
    final r = await http
        .post(
          _uri('/api/merch/plan/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 관리자: 기획실 표시 순서 저장.
  Future<bool> merchPlansOrder(List<String> ids) async {
    final r = await http
        .post(
          _uri('/api/merch/plan/order'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'ids': ids}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 수요조사 사전신청 (누구나 가능 — 로그인 불필요).
  Future<Map<String, dynamic>> merchSurveyApply({
    required String planId,
    required String name,
    String number = '',
    String phone = '',
    String email = '',
    String memo = '',
    int quantity = 1,
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/survey/apply'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'planId': planId,
            'name': name,
            'number': number,
            'phone': phone,
            'email': email,
            'memo': memo,
            'quantity': quantity,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 수요조사 신청자 명단 조회.
  Future<Map<String, dynamic>> merchSurveyApplicants(String planId) async {
    final r = await http
        .post(
          _uri('/api/merch/survey/applicants'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'planId': planId}),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 주문 상태/메모/수량 수정.
  Future<Map<String, dynamic>> merchUpdateOrder({
    required String id,
    bool? paid,
    String? status,
    String? memo,
    String? shipMethod,
    String? shipNote,
    int? qty,
    int? annualFeeAdded,
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/order/update'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'id': id,
            if (paid != null) 'paid': paid,
            if (status != null) 'status': status,
            if (memo != null) 'memo': memo,
            if (shipMethod != null) 'shipMethod': shipMethod,
            if (shipNote != null) 'shipNote': shipNote,
            if (qty != null) 'qty': qty,
            if (annualFeeAdded != null) 'annualFeeAdded': annualFeeAdded,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<bool> merchDeleteOrder(String id) async {
    final r = await http
        .post(
          _uri('/api/merch/order/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 관리자: 주문 임의 필드 수정(상품명/단가/금액/주문자/연락처/주소/상태 등).
  Future<Map<String, dynamic>> merchUpdateOrderRaw({
    required String id,
    required Map<String, dynamic> fields,
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/order/update'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id, ...fields}),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 예약 임의 필드 수정(상품명/수량/주문자/메모/상태 등).
  Future<Map<String, dynamic>> merchUpdateReserveRaw({
    required String id,
    required Map<String, dynamic> fields,
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/reserve/update'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id, ...fields}),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 같은 주문번호(orderNo)의 모든 품목을 한 번에 삭제(관리자·마스터).
  Future<Map<String, dynamic>> merchDeleteOrderGroup(String orderNo) async {
    final r = await http
        .post(
          _uri('/api/merch/order/delete-group'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'orderNo': orderNo}),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 구매자 수령확인 — 본인(세션) 또는 관리자가 주문번호를 '수령완료' 처리.
  Future<Map<String, dynamic>> merchReceiveOrder({
    String orderNo = '',
    String id = '',
    bool received = true,
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/order/receive'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            if (orderNo.isNotEmpty) 'orderNo': orderNo,
            if (id.isNotEmpty) 'id': id,
            'received': received,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---------- 주문 일괄편집 (소프트삭제/복원/순서/합치기/보관) ----------
  Future<Map<String, dynamic>> _merchPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final r = await http
        .post(
          _uri(path),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode(body),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 선택한 그룹키들(주문번호/번들키)을 소프트 삭제.
  Future<Map<String, dynamic>> merchOrdersDelete(List<String> keys) =>
      _merchPost('/api/merch/orders/delete', {'keys': keys});

  /// 삭제된 주문 복원(30일 이내).
  Future<Map<String, dynamic>> merchOrdersRestore(List<String> keys) =>
      _merchPost('/api/merch/orders/restore', {'keys': keys});

  /// 삭제된 주문 즉시 영구 삭제.
  Future<Map<String, dynamic>> merchOrdersHardDelete(List<String> keys) =>
      _merchPost('/api/merch/orders/hard-delete', {'keys': keys});

  /// 표시 순서 저장(드래그 재정렬).
  Future<Map<String, dynamic>> merchOrdersOrder(List<String> keys) =>
      _merchPost('/api/merch/orders/order', {'keys': keys});

  /// 선택한 주문들을 하나로 합치기(주문번호는 개별 유지).
  Future<Map<String, dynamic>> merchOrdersMerge(
    List<String> keys, {
    String name = '',
  }) => _merchPost('/api/merch/orders/merge', {
    'keys': keys,
    if (name.isNotEmpty) 'name': name,
  });

  /// 합친 묶음 해제.
  Future<Map<String, dynamic>> merchOrdersUnmerge(String bundleId) =>
      _merchPost('/api/merch/orders/unmerge', {'bundleId': bundleId});

  /// 30일 초과로 아카이브된(보관) 주문 내역 조회.
  Future<Map<String, dynamic>> merchArchive() async {
    try {
      final r = await http
          .get(_uri('/api/merch/orders/archive'), headers: _authHeaders)
          .timeout(const Duration(seconds: 30));
      return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false};
    }
  }

  /// 마스터: 지정된 관리자(권한 부여 인가번호) 목록.
  Future<Map<String, dynamic>> merchantAdmins() async {
    try {
      final r = await http
          .get(_uri('/api/admin/admins'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return j.cast<String, dynamic>();
    } catch (_) {
      return {'ok': false};
    }
  }

  /// 마스터: 특정 인가번호에 관리자 권한 부여.
  Future<Map<String, dynamic>> grantAdmin(String master, String number) async {
    final r = await http
        .post(
          _uri('/api/admin/grant'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'master': master, 'number': number}),
        )
        .timeout(const Duration(seconds: 30));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 마스터: 특정 인가번호의 관리자 권한 회수.
  Future<Map<String, dynamic>> revokeAdmin(String master, String number) async {
    final r = await http
        .post(
          _uri('/api/admin/revoke'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'master': master, 'number': number}),
        )
        .timeout(const Duration(seconds: 30));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 관리자: 연회비 금액 / 판매창 오픈 / 수품계좌 설정.
  Future<Map<String, dynamic>> merchSaveConfig({
    int? annualFee,
    bool? salesOpen,
    bool? annualFeeRequired,
    bool? reserveMode,
    String? notices,
    List<String>? statuses,
    List<String>? reserveStatuses,
    Map<String, dynamic>? account,
    Map<String, dynamic>? guide,
    bool? makerFileAdminAllowed,
    bool? quoteSpecAdminAllowed,
  }) async {
    final r = await http
        .post(
          _uri('/api/merch/config'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            if (annualFee != null) 'annualFee': annualFee,
            if (salesOpen != null) 'salesOpen': salesOpen,
            if (annualFeeRequired != null)
              'annualFeeRequired': annualFeeRequired,
            if (reserveMode != null) 'reserveMode': reserveMode,
            if (notices != null) 'notices': notices,
            if (statuses != null) 'statuses': statuses,
            if (reserveStatuses != null) 'reserveStatuses': reserveStatuses,
            if (account != null) 'account': account,
            if (guide != null) 'guide': guide,
            if (makerFileAdminAllowed != null)
              'makerFileAdminAllowed': makerFileAdminAllowed,
            if (quoteSpecAdminAllowed != null)
              'quoteSpecAdminAllowed': quoteSpecAdminAllowed,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }
}
