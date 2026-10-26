import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/member.dart';
import 'app_config.dart';

/// 인증(세션·권한) 실패를 '데이터 없음'과 구분하기 위한 예외.
///
/// ## 왜 필요한가
/// 종전에는 세션 만료나 등급 부족으로 온 401 응답이 **정상 JSON 으로 파싱**돼
/// 화면이 조용히 "0건"이 됐다. 사용자는 데이터가 삭제된 것으로 오해했고,
/// 오류 안내가 전혀 없어 원인을 알 수 없었다.
/// 이 예외를 던져 호출부가 "다시 로그인해 주세요"를 보여줄 수 있게 한다.
class NasAuthException implements Exception {
  NasAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

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

  /// 현재 발급된 **서버 세션의 등급** ('master' | 'app' | 'personal' | 'guest').
  ///  ── [버그 수정 2026-10-26] 앱 등급과 서버 등급이 어긋나던 문제 ──────────
  ///   개인 탭에서 415(영구 마스터)로 로그인하면 앱은 `_tier='master'` 로
  ///   승격되지만, 서버 세션은 `personal` 로 발급된다. 그래서 앱이 마스터
  ///   전용 API(`/api/member/password`, `/api/member/access-log` …)를 부르면
  ///   서버가 401 을 돌려줬다. "앱은 마스터인데 서버는 아니라고 하는" 상태를
  ///   감지하려면 서버가 알려준 등급을 기억해야 한다.
  String serverTier = '';

  /// 서버 세션이 마스터 등급인지.
  bool get serverIsMaster => serverTier == 'master';

  String get baseUrl => _base;

  /// 모든 요청에 공통으로 붙는 인증 헤더.
  Map<String, String> get _authHeaders =>
      sessionId.isEmpty ? const {} : {'X-TSAK-Session': sessionId};

  /// 외부 위젯(Image.network 등)에서 인증 헤더가 필요할 때 공개 접근자.
  Map<String, String> get authHeaderMap => _authHeaders;

  set baseUrl(String v) => _base = v.replaceAll(RegExp(r'/+$'), '');

  Uri _uri(String path) => Uri.parse('$_base$path');

  /// 행사 화면 등에서 쓰는 '견고한 JSON GET'.
  ///  · 인증 헤더를 항상 실어(쿠키 의존 제거) 보낸다.
  ///  · 응답이 JSON 이 아니면(예: 앞단 게이트웨이가 폭주 시 HTML 오류 반환)
  ///    명확한 예외를 던져 재시도를 유발한다.
  ///  · 일시적 오류(연결 끊김·HTML 오류·5xx)면 짧게 쉬고 1회 재시도한다.
  ///  → 서버가 잠깐 몰려도 '불러오기 실패' 창이 뜨지 않게 하는 안전망.
  ///
  /// ## [버그 수정 2026-10-25] 401 을 '정상 응답'으로 삼키던 문제
  ///  증상: 행사 상세에서 **참가자는 보이는데** 참가비·후원금 / 후원내역 /
  ///   지출내역 / 결산이 **전부 0건**으로 표시되고, 새로 입력한 값도 사라졌다.
  ///
  ///  원인: 종전에는 `statusCode >= 500` 만 예외로 걸렀다. 그래서 세션 만료나
  ///   등급 부족으로 온 **401 JSON**(`{"ok":false,"error":"unauthorized"}`)이
  ///   그대로 파싱되어 `j['fees']` 가 null → 호출부에서 조용히 빈 목록이 됐다.
  ///   → 화면에는 "0건"만 남고 **오류 안내조차 없었다**(사용자 입장에선
  ///     데이터가 사라진 것으로 보임).
  ///
  ///  해결: 401/403 과 `ok:false` 를 **반드시 예외**로 승격한다.
  ///   · 401 인증 실패는 재시도해도 결과가 같으므로 즉시 던진다.
  ///   · 호출부(`_load`)는 예외를 받아 재로그인 안내를 띄울 수 있다.
  ///     "데이터 없음"과 "권한/세션 문제"를 사용자가 구분할 수 있게 된다.
  Future<Map<String, dynamic>> _robustJson(
    Uri uri, {
    Duration timeout = const Duration(seconds: 30),
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    Object? lastErr;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final isPost = method.toUpperCase() == 'POST';
        final payload = isPost ? json.encode(body ?? const {}) : null;
        final r = await (isPost
                ? http.post(
                    uri,
                    headers: {
                      ..._authHeaders,
                      'Content-Type': 'application/json',
                      'Accept': 'application/json',
                    },
                    body: payload,
                  )
                : http.get(uri,
                    headers: {..._authHeaders, 'Accept': 'application/json'}))
            .timeout(timeout);
        final respBody = utf8.decode(r.bodyBytes);
        final t = respBody.trimLeft();
        // [수정] 인증 실패는 '데이터 없음'이 아니다 — 조용히 넘기지 않는다.
        if (r.statusCode == 401 || r.statusCode == 403) {
          throw NasAuthException(
            '로그인 세션이 만료되었거나 이 항목의 열람 권한이 없습니다. '
            '다시 로그인해 주세요. (HTTP ${r.statusCode})',
          );
        }
        if (r.statusCode >= 500 || t.startsWith('<')) {
          throw FormatException('gateway non-JSON (HTTP ${r.statusCode})');
        }
        final decoded = json.decode(respBody) as Map<String, dynamic>;
        // [수정] 서버가 200 으로 `ok:false` 를 주는 경우도 실패로 본다.
        //  (라우팅 폴백·권한 오류가 200 으로 새어 나오는 경로 차단)
        if (decoded['ok'] == false) {
          final msg = '${decoded['error'] ?? 'unknown'}';
          if (msg.contains('unauthorized') || msg.contains('forbidden')) {
            throw NasAuthException(
              '로그인 세션이 만료되었거나 이 항목의 열람 권한이 없습니다. '
              '다시 로그인해 주세요. ($msg)',
            );
          }
          throw Exception('서버 응답 오류: $msg');
        }
        return decoded;
      } on NasAuthException {
        // 인증 실패는 재시도 무의미 → 즉시 중단(불필요한 30초 대기 방지).
        rethrow;
      } catch (e) {
        lastErr = e;
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    throw Exception('연결이 불안정합니다. 잠시 후 다시 시도해 주세요. ($lastErr)');
  }

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
    if (j['ok'] == true && sid.isNotEmpty) {
      sessionId = sid;
      // 서버가 알려준 **실제 세션 등급**을 기억한다(개인 로그인은 personal).
      serverTier = tier;
    }
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
    String via = '',
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
              if (via.isNotEmpty) 'via': via,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final sid = '${j['sid'] ?? ''}';
      if (j['ok'] == true && sid.isNotEmpty) {
        sessionId = sid;
        serverTier = '${j['tier'] ?? tier}';
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

  // ---- 홈 오버플로 메뉴 노출 설정 (마스터 전용) ----
  /// 홈 메뉴별 노출 설정 조회.
  /// 반환: { menuKey: { label, icon, master: bool, admin: bool }, ... }
  Future<Map<String, Map<String, dynamic>>> fetchHomeMenus() async {
    try {
      final r = await http
          .get(_uri('/api/home/menus'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      final raw = (j['menus'] as Map?) ?? {};
      final out = <String, Map<String, dynamic>>{};
      raw.forEach((k, v) {
        if (v is Map) {
          out['$k'] = {
            'label': '${v['label'] ?? ''}',
            'icon': '${v['icon'] ?? ''}',
            'master': v['master'] == true,
            'admin': v['admin'] == true,
          };
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// 홈 메뉴 노출 설정 변경 (마스터 전용).
  /// [updates] = { menuKey: { 'master': bool, 'admin': bool } }
  Future<Map<String, Map<String, dynamic>>> setHomeMenus(
    Map<String, Map<String, bool>> updates,
  ) async {
    try {
      final r = await http
          .post(
            _uri('/api/home/menus/set'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: json.encode({'updates': updates}),
          )
          .timeout(const Duration(seconds: 20));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      final raw = (j['menus'] as Map?) ?? {};
      final out = <String, Map<String, dynamic>>{};
      raw.forEach((k, v) {
        if (v is Map) {
          out['$k'] = {
            'label': '${v['label'] ?? ''}',
            'icon': '${v['icon'] ?? ''}',
            'master': v['master'] == true,
            'admin': v['admin'] == true,
          };
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  // ---- 회원 등록요청 (평생회원·연회비·자격) ----
  /// 등록요청 제출. type: lifetime | fee | qualification | event | donation | supply
  ///  · lifetime/fee 등록요청은 [payer](납부자 이름)·[timing](납부시점)·
  ///    [payerIsSelf]('인가자와 동일')를 함께 보낸다.
  Future<Map<String, dynamic>> memberRequestSubmit({
    required String type,
    String ident = '',
    String year = '',
    String date = '',
    String note = '',
    String newNumber = '',
    String event = '',
    String item = '',
    int amount = 0,
    String payer = '',
    String timing = '',
    bool payerIsSelf = false,
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
            if (item.isNotEmpty) 'item': item,
            if (amount != 0) 'amount': amount,
            if (payer.isNotEmpty) 'payer': payer,
            if (timing.isNotEmpty) 'timing': timing,
            if (payerIsSelf) 'payerIsSelf': true,
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
  /// [self=true] 이면 서버에 `?self=1` 을 보내 **로그인 본인 1건만** 받는다.
  ///  개인정보 수정 진입(개인 세션)에서 전 회원(4.5MB)을 파싱하느라 웹이
  ///  멈추던 문제를 막는다(응답 수 KB → 즉시 로딩).
  Future<List<Member>> fetchMembers({bool self = false}) async {
    final path = self ? '/api/members?self=1' : '/api/members';
    final r = await http
        .get(_uri(path), headers: _authHeaders)
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    final list = (j['members'] as List?) ?? [];
    return list.map((e) => Member.fromMap(e as Map)).toList();
  }

  /// [raw] 회원 맵 목록 그대로 조회 — 대량(전체 명단)일 때 Member 변환(수 초 소요)
  ///  없이 즉시 반환한다. 저장소가 raw 맵을 보관하므로 화면 렌더도 빨라진다.
  Future<List<Map<String, dynamic>>> fetchMembersRaw({
    bool self = false,
  }) async {
    final path = self ? '/api/members?self=1' : '/api/members';
    final r = await http
        .get(_uri(path), headers: _authHeaders)
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    final list = (j['members'] as List?) ?? [];
    return list
        .map((e) => (e as Map).cast<String, dynamic>())
        .where((m) => '${m['id'] ?? ''}'.isNotEmpty)
        .toList();
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
  ///   [corps] 를 넘기면 서버가 그 소속 명단(은하 등)으로 저장한다.
  Future<Map<String, dynamic>> saveMember(
    Member member, {
    String by = 'app',
    String linkRequestSource = '',
    String corps = '',
  }) async {
    final body = <String, dynamic>{'member': member.toMap(), 'by': by};
    if (linkRequestSource.isNotEmpty) {
      body['linkRequestSource'] = linkRequestSource;
    }
    if (corps.isNotEmpty) {
      body['corps'] = corps;
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

  /// 인가자 개인정보 히스토리 항목 삭제 (마스터 또는 본인만).
  Future<Map<String, dynamic>> deleteInfoHistory(String id, int index) async {
    final r = await http
        .post(
          _uri('/api/member/info-history/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id, 'index': index}),
        )
        .timeout(const Duration(seconds: 60));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// [요구] 행사기획 지도 위치 검색 — 검색어로 장소/주소를 찾아 좌표를 얻는다.
  ///   서버가 Photon(OSM)·도로명주소로 지오코딩한 결과를 돌려준다.
  Future<List<Map<String, dynamic>>> geoSearch(
    String query, {
    int limit = 8,
  }) async {
    if (query.trim().length < 2) return const [];
    final r = await http
        .get(
          _uri(
            '/api/geo/search?q=${Uri.encodeComponent(query.trim())}'
            '&limit=$limit',
          ),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 20));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['items'] as List?) ?? [])
        .map((x) => (x as Map).cast<String, dynamic>())
        .toList();
  }

  /// [요구] 검색 위치 미리보기 정적지도 이미지 URL (OSM 타일 스티칭).
  String geoStaticMapUrl(
    String lat,
    String lng, {
    int zoom = 15,
    int w = 640,
    int h = 320,
  }) =>
      '$_base/api/geo/staticmap?lat=${Uri.encodeComponent(lat)}'
      '&lng=${Uri.encodeComponent(lng)}&z=$zoom&w=$w&h=$h';

  /// [요구] 카카오 지도 정적 이미지 URL (JavaScript 키 필요).
  ///   앱에서 바로 표시할 수 있는 <img> 용 URL.
  String geoKakaoMapUrl(
    String lat,
    String lng, {
    int level = 3,
    int w = 640,
    int h = 320,
  }) =>
      '$_base/api/geo/kakaomap?lat=${Uri.encodeComponent(lat)}'
      '&lng=${Uri.encodeComponent(lng)}&level=$level&w=$w&h=$h';

  /// [요구] 지도 임베드용 공개 설정(카카오 JS 키). QR/참가신청 페이지에서 사용.
  Future<Map<String, dynamic>> geoConfig() async {
    final r = await http
        .get(_uri('/api/geo/config'), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// [요구] 카카오 REST 키 유효성 진단 — 실제 카카오 응답을 그대로 반환.
  ///   (401 이면 카카오가 키를 인식하지 못하는 것: 활성화 전/오타)
  Future<Map<String, dynamic>> geoKakaoTest() async {
    try {
      final r = await http
          .get(_uri('/api/geo/kakao-test'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
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

  // ---- 후원 안내 (계좌 목록 · 예금주) ----
  /// 후원계좌 목록 + 예금주 조회.
  Future<Map<String, dynamic>> fetchDonationAccounts() async {
    try {
      final r = await http
          .get(_uri('/api/donation/accounts'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false};
    }
  }

  /// 후원 안내 저장 (마스터 전용).
  /// [action]: set(목록 전체) | save(단일 추가·수정) | delete(삭제) | holder(예금주)
  Future<Map<String, dynamic>> saveDonationAccounts({
    required String action,
    List<Map<String, dynamic>>? donations,
    Map<String, dynamic>? account,
    int? index,
    String? holder,
  }) async {
    final body = <String, dynamic>{'action': action};
    if (donations != null) body['donations'] = donations;
    if (account != null) body['account'] = account;
    if (index != null) body['index'] = index;
    if (holder != null) body['donationHolder'] = holder;
    final r = await http
        .post(
          _uri('/api/donation/accounts/set'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode(body),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
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

  /// 서버(photos/ 폴더)에 **실제 사진 파일이 있는 인가번호** 목록.
  ///
  /// 요구: DB 의 photoPath 가 비어 있어도 서버에 사진이 있으면 화면에 뜨게 한다
  ///  (예: 1346 양다솜 — 파일은 있으나 photoPath 가 빈 값이던 문제).
  /// 반환: {번호: 확장자} 맵. 실패 시 빈 맵.
  Future<Map<String, String>> fetchPhotoHave() async {
    try {
      final r = await http
          .get(_uri('/api/photo/have'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return const {};
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      if (j['ok'] != true) return const {};
      final have = (j['have'] as Map?) ?? const {};
      return have.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return const {};
    }
  }

  /// 사진/동영상/첨부 파일의 실제 바이트를 프록시에서 받아온다.
  ///   · 인증 쿠키가 유지되므로 launchUrl(externalApplication) 없이
  ///     파일을 **직접 저장**(저장 위치 선택창 연동)할 수 있다.
  ///   · 반환: (bytes, contentType) — 실패 시 예외.
  Future<(Uint8List, String)> fetchBytes(String url) async {
    final r = await http
        .get(Uri.parse(url), headers: _authHeaders)
        .timeout(const Duration(seconds: 120));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
      throw '다운로드 실패 (HTTP ${r.statusCode})';
    }
    var ct = r.headers['content-type'] ?? '';
    if (ct.isEmpty) ct = 'application/octet-stream';
    return (r.bodyBytes, ct);
  }

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

  // ---- 재무 그룹핑 목록 (전체/연도/월/항목) + 첨부 개수 ----
  Future<Map<String, dynamic>> fetchFinanceList() async {
    final r = await http
        .get(_uri('/api/finance/list'), headers: _authHeaders)
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- 재무 거래별 첨부파일 ----
  Future<List<Map<String, dynamic>>> fetchFinanceAttach(String txid) async {
    try {
      final r = await http
          .get(
            _uri('/api/finance/attach?txid=${Uri.encodeComponent(txid)}'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 20));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      final list = j['files'];
      if (list is List) {
        return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 첨부 업로드(스트리밍 바디). 모든 포맷 허용.
  Future<List<Map<String, dynamic>>> uploadFinanceAttach(
    String txid,
    String name,
    List<int> bytes,
  ) async {
    final q =
        'txid=${Uri.encodeComponent(txid)}&name=${Uri.encodeComponent(name)}';
    final r = await http
        .post(
          _uri('/api/finance/attach/upload?$q'),
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/octet-stream',
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 180));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    final list = j['files'];
    if (list is List) {
      return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> renameFinanceAttach(
    String txid,
    String name,
    String newName,
  ) async {
    final r = await http
        .post(
          _uri('/api/finance/attach/rename'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'txid': txid, 'name': name, 'newName': newName}),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    final list = j['files'];
    if (list is List) {
      return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> deleteFinanceAttach(
    String txid,
    String name,
  ) async {
    final r = await http
        .post(
          _uri('/api/finance/attach/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'txid': txid, 'name': name}),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    final list = j['files'];
    if (list is List) {
      return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  /// 첨부 다운로드/공유용 URL(직접 열기).
  String financeAttachUrl(String txid, String name) =>
      '$_base/api/finance/attach/download?txid=${Uri.encodeComponent(txid)}'
      '&name=${Uri.encodeComponent(name)}';

  // ---- 자료 저장공간 (마스터) ----
  Future<Map<String, dynamic>> fetchStorage() async {
    try {
      final r = await http
          .get(_uri('/api/storage'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false};
    }
  }

  Future<Map<String, dynamic>> saveStorage(Map<String, dynamic> payload) async {
    final r = await http
        .post(
          _uri('/api/storage/set'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode(payload),
        )
        .timeout(const Duration(seconds: 30));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 저장공간 이관(자료 복사) 또는 통계(sweep).
  Future<Map<String, dynamic>> migrateStorage(
    String target, {
    bool sweep = false,
    bool deleteOld = false,
  }) async {
    final r = await http
        .post(
          _uri('/api/storage/migrate'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'target': target,
            'sweep': sweep,
            'deleteOld': deleteOld,
          }),
        )
        .timeout(const Duration(seconds: 300));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> purgeOldStorage([String which = 'nas']) async {
    final r = await http
        .post(
          _uri('/api/storage/purge-old'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'which': which}),
        )
        .timeout(const Duration(seconds: 120));
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

  // ---- 자료 가져오기 (AI 인식) — 등록/업데이트 · 감사로그 · 복원 ----
  /// 인식 자료를 NAS에 적용(등록/업데이트).
  ///  [rows] 각 항목: {number, name, league, unit, ..., action('add'|'update'|'skip'),
  ///                  fields('쉼표로 구분한 반영 허용 필드', 없으면 전체)}
  ///  dry=true 면 비교/미리보기만.
  ///  반환: {ok, added, updated, skipped, changes:[{number,name,diffs:[...]}]}
  Future<Map<String, dynamic>> importApply(
    List<Map<String, dynamic>> rows, {
    String source = '',
    bool dry = false,
    String id = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/import/apply'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'rows': rows,
            'source': source,
            'dry': dry,
            if (id.isNotEmpty) 'id': id,
          }),
        )
        .timeout(const Duration(seconds: 180));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 자료 가져오기(업데이트) 감사로그 — 관리자·마스터.
  Future<Map<String, dynamic>> importLog() async {
    try {
      final r = await http
          .get(_uri('/api/import/log'), headers: _authHeaders)
          .timeout(const Duration(seconds: 30));
      return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false, 'items': []};
    }
  }

  /// (마스터) 감사로그의 이전값으로 복원.
  ///  [restoreItems] 지정 시 그 회원 id 들만, 미지정 시 해당 항목 전체 복원.
  Future<Map<String, dynamic>> importRestore(
    String id, {
    List<String>? restoreItems,
  }) async {
    final r = await http
        .post(
          _uri('/api/import/restore'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'id': id,
            if (restoreItems != null && restoreItems.isNotEmpty)
              'restoreItems': restoreItems,
          }),
        )
        .timeout(const Duration(seconds: 120));
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
    final j = await _robustJson(
      _uri(
        '/api/event/get?year=${Uri.encodeComponent(year)}&title=${Uri.encodeComponent(title)}',
      ),
    );
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
    bool fresh = false,
    bool deep = false,
  }) async {
    // [안정] 인증 헤더 포함 + HTML/오류 응답 시 1회 재시도(_robustJson).
    //
    // [fresh] 서버의 파일목록 캐시를 **버리고** NAS 에서 다시 읽는다.
    //  (요구: "직접 업로드 한 폴더가 보여지지 않는 버그" — PC 에서 올린
    //   파일은 서버 캐시가 모르므로 사용자가 새로고침할 수 있어야 한다)
    //
    // [deep] 미디어 폴더를 **재귀 평탄화**해서 가져온다. 사진이
    //  '00 사진+동영상' 처럼 한 겹 안쪽 폴더에 있어도 한 번에 보인다.
    //  (요구: "나스 내에 있는 폴더내 사진이 보여지지 않음")
    final j = await _robustJson(
      _uri(
        '/api/event/files?year=${Uri.encodeComponent(year)}'
        '&title=${Uri.encodeComponent(title)}&key=$key'
        '&sub=${Uri.encodeComponent(sub)}'
        '${fresh ? '&fresh=1' : ''}'
        '${deep ? '&deep=1' : ''}',
      ),
      timeout: const Duration(seconds: 60),
    );
    _lastFolderAlias = (j['folderAlias'] as Map?)?.cast<String, dynamic>();
    _lastMediaDirs = ((j['mediaDirs'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    return ((j['files'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 마지막 eventFiles 응답에 실린 폴더명 불일치 정보
  /// {app: '앱 제목', nas: '나스 실제 폴더명'} — null 이면 일치.
  Map<String, dynamic>? _lastFolderAlias;
  Map<String, dynamic>? get lastFolderAlias => _lastFolderAlias;

  /// 마지막 eventFiles 응답에서 '사진이 실제로 들어있는' 하위 폴더들.
  List<Map<String, dynamic>> _lastMediaDirs = const [];
  List<Map<String, dynamic>> get lastMediaDirs => _lastMediaDirs;

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
  /// 행사 폴더 파일의 썸네일 URL.
  ///
  /// ── [개선 2026-10-26] 지출·영수증 화면에 썸네일이 안 뜨던 문제 ─────────
  ///  서버(`/api/event/thumb2`)는 `key` 로 **어느 하위폴더인지** 판단한다
  ///  (`media | expense | plan | review | attendees`, 미지정이면 `media`).
  ///  그런데 이 함수가 `key` 를 **보내지 않아** 지출(expense)·계획서(plan)
  ///  썸네일 요청이 전부 media 폴더를 뒤졌고, 못 찾아 빈 응답이 왔다.
  ///  → 파일 목록이 아이콘만 보이고 미리보기가 없었다.
  ///  [key] 를 넘기면 해당 폴더에서 찾는다.
  String eventThumb2Url(
    String year,
    String title,
    String name, {
    String size = 'normal',
    String sub = '',
    String key = 'media',
  }) =>
      '$_base/api/event/thumb2?year=${Uri.encodeComponent(year)}'
      '&title=${Uri.encodeComponent(title)}&name=${Uri.encodeComponent(name)}'
      '&sub=${Uri.encodeComponent(sub)}&size=$size'
      '&key=${Uri.encodeComponent(key)}';

  /// 썸네일 URL 에 인증 헤더를 붙일 때 쓰는 공개 접근자(Image.network 용).
  Map<String, String> get imageAuthHeaders => _authHeaders;

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
    String lat = '',
    String lng = '',
    String mapQuery = '',
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
            'lat': lat,
            'lng': lng,
            'mapQuery': mapQuery,
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

  /// 행사 수정 — 입력했던 모든 내용(연도·행사명·기간·시작/종료일·장소·소개·
  /// 담당자 연락처)을 한 번에 갱신한다. 이름/연도가 바뀌면 rename 을 먼저
  /// 수행해 폴더까지 함께 이동한다.
  Future<bool> eventUpdate({
    required String year,
    required String title,
    String? newYear,
    String? newTitle,
    String? period,
    String? place,
    String? desc,
    String? startDate,
    String? endDate,
    String? lat,
    String? lng,
    String? mapQuery,
    List<Map<String, dynamic>>? contacts,
  }) async {
    var curYear = year;
    var curTitle = title;
    final ny = newYear ?? year;
    final nt = newTitle ?? title;
    if (ny != year || nt != title) {
      final r = await eventRename(
        year: year,
        title: title,
        newYear: ny,
        newTitle: nt,
      );
      if (r['ok'] != true) return false;
      curYear = ny;
      curTitle = nt;
    }
    final r = await http
        .post(
          _uri('/api/event/meta'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'year': curYear,
            'title': curTitle,
            if (period != null) 'period': period,
            if (place != null) 'place': place,
            if (desc != null) 'desc': desc,
            if (startDate != null) 'startDate': startDate,
            if (endDate != null) 'endDate': endDate,
            if (lat != null) 'lat': lat,
            if (lng != null) 'lng': lng,
            if (mapQuery != null) 'mapQuery': mapQuery,
            if (contacts != null) 'contacts': contacts,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// [요구] 참가신청 페이지 '배포용' 자료 목록 — 기획서/참가신청시 배포용 폴더.
  Future<List<Map<String, dynamic>>> eventDistFiles(
    String year,
    String title,
  ) async {
    final e = await eventGet(year, title);
    return ((e['distFiles'] as List?) ?? [])
        .map((x) => (x as Map).cast<String, dynamic>())
        .toList();
  }

  /// [요구] 행사 첨부파일(복수)을 '참가신청시 배포용' 폴더로 업로드.
  Future<Map<String, dynamic>> eventDistUpload(
    String year,
    String title,
    String name,
    List<int> bytes, {
    String contentType = 'application/octet-stream',
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = Uri.parse(
      '$_base/api/event/dist/upload?year=${Uri.encodeComponent(year)}'
      '&title=${Uri.encodeComponent(title)}&name=${Uri.encodeComponent(name)}',
    );
    final req = http.StreamedRequest('POST', uri);
    req.headers['Content-Type'] = contentType;
    req.headers['Content-Length'] = '${bytes.length}';
    const chunk = 262144;
    Future<void> pump() async {
      var sent = 0;
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

  /// [요구] 배포용 자료 삭제.
  Future<bool> eventDistDelete(String year, String title, String name) async {
    final r = await http
        .post(
          _uri('/api/event/dist/delete'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'year': year, 'title': title, 'name': name}),
        )
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// [요구] 이 행사를 열람한 '인가자' 수 + 이름 목록.
  Future<Map<String, dynamic>> eventCredentialViewers(
    String year,
    String title,
  ) async {
    final e = await eventGet(year, title);
    return {
      'count': (e['credViewers'] as num?)?.toInt() ?? 0,
      'names': ((e['credViewerNames'] as List?) ?? [])
          .map((x) => '$x')
          .toList(),
    };
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

  /// 행사 소프트 삭제 — 휴지통으로 이동(파일 보존, 복구 가능).
  /// [by] 삭제자 표기(예: 마스터/관리자 인가번호).
  Future<bool> eventArchive(String year, String title, {String by = ''}) async {
    final r = await http
        .post(
          _uri('/api/event/archive'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'year': year, 'title': title, 'by': by}),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 휴지통에서 행사 복구 — 활성 목록으로 되돌린다.
  Future<bool> eventRestore(String id) async {
    final r = await http
        .post(
          _uri('/api/event/restore'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'id': id}),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 휴지통(삭제한 행사) 목록.
  Future<List<Map<String, dynamic>>> eventTrashList() async {
    final r = await http
        .post(
          _uri('/api/event/trash/list'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({}),
        )
        .timeout(const Duration(seconds: 40));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['trash'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 휴지통에서 완전 삭제 — NAS 파일/썸네일/개인프로필까지 제거(되돌릴 수 없음).
  Future<bool> eventPurge(List<String> ids) async {
    final r = await http
        .post(
          _uri('/api/event/purge'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'ids': ids}),
        )
        .timeout(const Duration(seconds: 90));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 참석자 목록 저장 (+회원 프로필 자동 반영)
  /// 참가자 명단 저장 — 서버가 회원 프로필(eventAttend)에 **양방향** 연동한다.
  ///
  /// ## 버그 수정: "참가자 삭제시 개인정보카드와 연계해서 참가행사에서도 삭제"
  ///  종전 서버는 추가(True)만 연동해서, 명단에서 지워도 개인정보카드의
  ///  '행사참가 이력'에 그대로 남았다.
  ///
  /// 이제 서버 응답에 `linkedAdded` / `linkedRemoved` 가 실려 온다.
  ///  · linkedAdded  : 프로필에 '참가'로 새로 기록된 인원
  ///  · linkedRemoved: 명단에서 빠져 '참가'가 해제된 인원
  ///
  /// 반환: `{'ok': bool, 'linkedAdded': int, 'linkedRemoved': int}`
  Future<Map<String, dynamic>> eventSetAttendeesDetailed(
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
    return {
      'ok': j['ok'] == true,
      'linkedAdded': int.tryParse('${j['linkedAdded'] ?? 0}') ?? 0,
      'linkedRemoved': int.tryParse('${j['linkedRemoved'] ?? 0}') ?? 0,
    };
  }

  /// 참가자 명단 저장 (성공 여부만).
  ///
  /// 프로필 연동은 서버가 함께 처리한다. 연동 인원까지 알고 싶으면
  /// [eventSetAttendeesDetailed] 를 쓴다.
  Future<bool> eventSetAttendees(
    String year,
    String title,
    List<Map<String, dynamic>> attendees,
  ) async {
    final res = await eventSetAttendeesDetailed(year, title, attendees);
    return res['ok'] == true;
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

  /// (요구) 인가번호/전화번호/이름으로 **개인정보 1건**을 조회한다.
  ///
  /// 행사 참가자 수동 입력에서 인가번호만 넣으면 이름·소속·성별·연락처·메일·
  /// 주소를 자동으로 채우기 위한 조회. 범/은하 양쪽 명단을 서버가 함께 본다.
  /// 반환: `{ok, found, member:{...}}` — 없으면 found=false.
  Future<Map<String, dynamic>> memberLookup(String query) async {
    final r = await http
        .post(
          _uri('/api/member/lookup'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'q': query}),
        )
        .timeout(const Duration(seconds: 20));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j.cast<String, dynamic>();
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
    return _robustJson(
      _uri(
        '/api/event/finance?year=${Uri.encodeComponent(year)}'
        '&title=${Uri.encodeComponent(title)}',
      ),
    );
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
    final j = await _robustJson(
      _uri(
        '/api/event/access?year=${Uri.encodeComponent(year)}'
        '&title=${Uri.encodeComponent(title)}',
      ),
    );
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
  ///
  /// ── [버그 수정 2026-10-26] 마스터인데 '조회 실패'가 뜨던 문제 ─────────────
  ///  원인: 이 함수만 `_robustJson` 을 쓰지 않고 **생 HTTP 응답을 그대로
  ///   json.decode** 했다. 서버가 401 `{"ok":false,"error":"unauthorized"}`
  ///   를 돌려주면 디코딩은 성공하고, 상위(`fetchMemberPassword`)에서
  ///   `r['ok'] == true` 가 아니므로 **null 을 반환** → 화면은 "조회 실패".
  ///   401 이 예외로 승격되지 않아 재인증·재시도 기회도 없었다.
  ///  해결: `_robustJson` 경유 → 401/403 은 `NasAuthException` 으로 승격.
  Future<Map<String, dynamic>> memberPassword(String number) async {
    return _robustJson(
      _uri('/api/member/password?number=${Uri.encodeComponent(number)}'),
      timeout: const Duration(seconds: 15),
    );
  }

  /// 회원 접속 로그 조회 (마스터 전용) — 최신 100건.
  ///  위와 같은 이유로 `_robustJson` 경유(401 → NasAuthException).
  Future<List<Map<String, dynamic>>> memberAccessLog(String number) async {
    final j = await _robustJson(
      _uri('/api/member/access-log?number=${Uri.encodeComponent(number)}'),
      timeout: const Duration(seconds: 15),
    );
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
  ///  action: 'approve' | 'hold' | 'pending' | 'reject' | 'delete'
  ///  ※ 마스터에게 위임된 항목은 마스터만 처리 가능(서버가 403 master_only).
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

  /// 마스터에게 위임 / 위임 취소 (관리자·마스터).
  ///  source: 'regular'(비인가회원) | 'request'(등록요청) | 'link'(멘토·페런츠)
  ///  action: 'delegate'(위임) | 'cancel'(해제)
  ///  위임된 항목은 마스터만 선택·처리할 수 있다.
  Future<Map<String, dynamic>> approvalDelegate({
    required String source,
    required String ident,
    String action = 'delegate',
    String note = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/approval/delegate'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({
            'source': source,
            'ident': ident,
            'action': action,
            'note': note,
          }),
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

  /// 멘토장부 · 페런츠장부 · 멘티장부 — 관리자·마스터 전용.
  ///   각 항목: 번호·이름·연락처·소속 + 멘토/페런츠메달 구매여부·시점 +
  ///   중앙회 항건 구매여부·시점 + 연차등록 여부 (+ 파생 연결 수/배출 멘토).
  Future<Map<String, dynamic>> linkLedger({String kind = ''}) async {
    try {
      final q = kind.isNotEmpty ? '?kind=${Uri.encodeComponent(kind)}' : '';
      final r = await http
          .get(_uri('/api/link/ledger$q'), headers: _authHeaders)
          .timeout(const Duration(seconds: 30));
      return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false, 'mentor': [], 'parent': [], 'mentee': []};
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
  ///   [kind] 를 함께 보내 멘토/페런츠 번호가 같아도 해당 종류만 수정되게 한다.
  Future<Map<String, dynamic>> linkProfileSetReceiver({
    required String number,
    required String receiverNo,
    String kind = '',
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
              if (kind.isNotEmpty) 'kind': kind,
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

  /// [요구] 정보 수정요청 메모 — 비인가회원(본인)이 관리자·마스터에게 정보 수정을
  ///  요청한다. 등록되면 통합승인 '정보 수정요청' 큐에 노출된다.
  Future<Map<String, dynamic>> linkNote({
    String ident = '',
    required String note,
    String scope = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/link/note'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'ident': ident, 'note': note, 'scope': scope}),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// [요구] 정보 수정요청(메모) 처리 — 관리자·마스터가 확인 후 해제.
  Future<Map<String, dynamic>> approvalNoteClear({
    String ident = '',
    String id = '',
  }) async {
    final r = await http
        .post(
          _uri('/api/approval/note/clear'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'ident': ident, 'id': id}),
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

  // ================= 행사 커스텀 게시판 (메뉴추가 → 게시판형) =================
  //  [요구 2026-10-26] "메뉴 추가"로 만든 탭 = 게시판.
  //   · 글쓰기 / 첨부 업로드 / 다운로드 / 열람권한(3단계) / 게시글 비밀번호
  //   · 마스터는 읽은 사람 명단을 본다.
  //
  //  ⚠️ 서버 엔드포인트가 **do_GET 에 잘못 들어가 있어서** POST 가 전부
  //     404 HTML 을 받아 `FormatException: Unexpected token '<'` 로 터졌다.
  //     (빌드 495 까지의 증상) → 프록시에서 do_POST 로 이동 완료.
  //     여기서는 방어적으로 `_robustJson` 을 써서 HTML/401 을 예외로 승격한다.

  /// 게시판 목록 — 현재 세션 기준 `visible` 플래그가 함께 온다.
  Future<Map<String, dynamic>> customBoards(String year, String title) async {
    return _robustJson(
      _uri('/api/event/cboard/list?year=${Uri.encodeComponent(year)}'
          '&title=${Uri.encodeComponent(title)}'),
      timeout: const Duration(seconds: 40),
    );
  }

  /// 게시판 하나의 글 목록(첨부·비번 노출여부·읽음수 포함) — 권한 없으면 403.
  Future<Map<String, dynamic>> customBoardGet(
    String year,
    String title,
    String id,
  ) async {
    return _robustJson(
      _uri('/api/event/cboard/get?year=${Uri.encodeComponent(year)}'
          '&title=${Uri.encodeComponent(title)}&id=${Uri.encodeComponent(id)}'),
      timeout: const Duration(seconds: 40),
    );
  }

  /// 게시판 생성/수정(관리자·마스터). `id` 없으면 새로 만든다. 반환: {ok, id}
  Future<Map<String, dynamic>> customBoardCreate({
    required String year,
    required String title,
    String id = '',
    required String name,
    String note = '',
    String visibility = 'admin',
  }) async {
    return _robustJson(
      _uri('/api/event/cboard/create'),
      method: 'POST',
      body: {
        'year': year,
        'title': title,
        'id': id,
        'name': name,
        'note': note,
        'visibility': visibility,
      },
      timeout: const Duration(seconds: 40),
    );
  }

  /// 노출권한 지정(관리자·마스터). visibility: all | staff | admin
  Future<Map<String, dynamic>> customBoardVisibility({
    required String year,
    required String title,
    required String id,
    required String visibility,
  }) async {
    return _robustJson(
      _uri('/api/event/cboard/visibility'),
      method: 'POST',
      body: {
        'year': year,
        'title': title,
        'id': id,
        'visibility': visibility,
      },
      timeout: const Duration(seconds: 40),
    );
  }

  /// 게시판 삭제(글·첨부목록 포함). 관리자·마스터 전용.
  Future<Map<String, dynamic>> customBoardDeleteBoard({
    required String year,
    required String title,
    required String id,
  }) async {
    return _robustJson(
      _uri('/api/event/cboard/board/delete'),
      method: 'POST',
      body: {'year': year, 'title': title, 'id': id},
      timeout: const Duration(seconds: 40),
    );
  }

  /// 게시판 글 작성/수정. 반환: {ok, id}
  ///  `password` 를 넘기면 그 글이 잠긴다(글쓴이·마스터만 열람 가능).
  ///  빈 문자열을 넘기면 잠금 해제.
  Future<Map<String, dynamic>> customBoardPost({
    required String year,
    required String title,
    required String boardId,
    String id = '',
    String author = '',
    String number = '',
    required String body,
    List<String>? attachments,
    String? password,
  }) async {
    return _robustJson(
      _uri('/api/event/cboard/post'),
      method: 'POST',
      body: {
        'year': year,
        'title': title,
        'boardId': boardId,
        'id': id,
        'author': author,
        'number': number,
        'body': body,
        'attachments': attachments ?? const <String>[],
        if (password != null) 'password': password,
      },
      timeout: const Duration(seconds: 40),
    );
  }

  /// 게시판 글 삭제(관리자·마스터 또는 작성자 본인).
  Future<bool> customBoardDelete({
    required String year,
    required String title,
    required String boardId,
    required String postId,
    String author = '',
    String number = '',
  }) async {
    try {
      final d = await _robustJson(
        _uri('/api/event/cboard/delete'),
        method: 'POST',
        body: {
          'year': year,
          'title': title,
          'boardId': boardId,
          'postId': postId,
          'author': author,
          'number': number,
        },
        timeout: const Duration(seconds: 40),
      );
      return d['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 게시글 비밀번호 초기화 → 글쓴이 인가번호 + '!@@' 로 조용히 재설정.
  Future<Map<String, dynamic>> customBoardPasswordReset({
    required String year,
    required String title,
    required String boardId,
    required String postId,
  }) async {
    return _robustJson(
      _uri('/api/event/cboard/password/reset'),
      method: 'POST',
      body: {
        'year': year,
        'title': title,
        'boardId': boardId,
        'postId': postId,
      },
      timeout: const Duration(seconds: 40),
    );
  }

  /// 읽음 기록 — 글을 실제로 열었을 때 1회 기록.
  Future<Map<String, dynamic>> customBoardMarkRead({
    required String year,
    required String title,
    required String boardId,
    required String postId,
    String name = '',
  }) async {
    try {
      return await _robustJson(
        _uri('/api/event/cboard/read'),
        method: 'POST',
        body: {
          'year': year,
          'title': title,
          'boardId': boardId,
          'postId': postId,
          'name': name,
        },
        timeout: const Duration(seconds: 30),
      );
    } catch (_) {
      return {'ok': false};
    }
  }

  /// ── [요구 2026-10-26] "자료를 읽고 **공감**하고, 다운받을 수 있도록"
  /// 글에 공감(좋아요)을 남기거나 취소한다. `on` 을 주지 않으면 토글.
  /// 반환: {ok, liked, likeCount}
  Future<Map<String, dynamic>> customBoardReact({
    required String year,
    required String title,
    required String boardId,
    required String postId,
    String name = '',
    bool? on,
  }) async {
    try {
      return await _robustJson(
        _uri('/api/event/cboard/react'),
        method: 'POST',
        body: {
          'year': year,
          'title': title,
          'boardId': boardId,
          'postId': postId,
          'name': name,
          if (on != null) 'on': on,
        },
        timeout: const Duration(seconds: 30),
      );
    } catch (_) {
      return {'ok': false};
    }
  }

  /// 비밀번호가 걸린 글의 본문 열람 시도.
  ///  글쓴이·마스터는 비번 없이 통과, 그 외는 값을 맞춰야 한다.
  Future<Map<String, dynamic>> customBoardUnlock({
    required String year,
    required String title,
    required String boardId,
    required String postId,
    String password = '',
  }) async {
    return _robustJson(
      _uri('/api/event/cboard/post/unlock'),
      method: 'POST',
      body: {
        'year': year,
        'title': title,
        'boardId': boardId,
        'postId': postId,
        'password': password,
      },
      timeout: const Duration(seconds: 30),
    );
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
    // 판매가능재고 — 수품구매(쇼핑몰)에 노출되는 판매 가능 수량(기본 999).
    int sellableStock = 999,
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
    bool forSale = true,
    String soldStart = '',
    int soldBase = 0,
    String category = '',
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
            'sellableStock': sellableStock,
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
            'forSale': forSale,
            'soldStart': soldStart,
            'soldBase': soldBase,
            'category': category,
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
    String category = '',
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
            'category': category,
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

  /// 마스터: 관리자별(인가번호) 개별 메뉴권한 + 기본 권한표 조회.
  /// 반환: { ok, defaults:{menuKey:bool}, adminPerms:{ '번호':{menuKey:bool} }, perms:{...} }
  Future<Map<String, dynamic>> fetchAdminPerms() async {
    try {
      final r = await http
          .get(_uri('/api/admin/perms'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return j.cast<String, dynamic>();
    } catch (_) {
      return {'ok': false};
    }
  }

  /// 마스터: 특정 관리자(인가번호)의 개별 메뉴권한 일부 변경.
  Future<bool> setAdminPerms(String number, Map<String, bool> updates) async {
    final r = await http
        .post(
          _uri('/api/admin/perms/set'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'number': number, 'updates': updates}),
        )
        .timeout(const Duration(seconds: 20));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 마스터: 특정 관리자의 개별 메뉴권한을 기본값(역할 app)으로 되돌린다.
  Future<bool> resetAdminPerms(String number) async {
    final r = await http
        .post(
          _uri('/api/admin/perms/reset'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: json.encode({'number': number}),
        )
        .timeout(const Duration(seconds: 20));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  /// 마스터: 아이디/암호 기반 관리자 계정 목록.
  /// 반환: { ok, accounts:[{username,password,note,created}] }
  Future<Map<String, dynamic>> fetchAdminAccounts() async {
    try {
      final r = await http
          .get(_uri('/api/admin/accounts'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return j.cast<String, dynamic>();
    } catch (_) {
      return {'ok': false};
    }
  }

  /// 마스터: 아이디/암호 관리자 계정 생성·수정·삭제.
  /// action = 'create' | 'update' | 'delete'.
  /// 반환: 서버 응답 전체({ok, accounts, error}) — UI에서 오류 메시지 표시용.
  Future<Map<String, dynamic>> saveAdminAccount({
    required String action,
    required String username,
    String? password,
    String? note,
  }) async {
    try {
      final r = await http
          .post(
            _uri('/api/admin/accounts'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: json.encode({
              'action': action,
              'username': username,
              if (password != null) 'password': password,
              if (note != null) 'note': note,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return j.cast<String, dynamic>();
    } catch (_) {
      return {'ok': false, 'error': '네트워크 오류'};
    }
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
    bool? costVisibleToMaster,
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
            if (costVisibleToMaster != null)
              'costVisibleToMaster': costVisibleToMaster,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }
}
