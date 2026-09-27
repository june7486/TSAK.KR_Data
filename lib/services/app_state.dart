import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async' show unawaited;

import '../models/member.dart';
import 'ai_query.dart';
import 'app_config.dart';
import 'finance_service.dart';
import 'member_repository.dart';
import 'nas_api.dart';
import 'web_nav.dart';

/// 전역 앱 상태 (Provider)
class AppState extends ChangeNotifier {
  AppState(this.repo, {NasApi? nas}) : nas = nas ?? NasApi() {
    repo.revision.addListener(_onRepoChanged);
    repo.serverMeta.addListener(_onMeta);
    repo.syncStatus.addListener(_onSync);
    _loadFontScale();
    _loadServerBase();
    refresh();
    if (repo.isNasMode) {
      loadConfig();
    }
  }

  final MemberRepository repo;
  final NasApi nas;

  /// 재무 서비스 참조 (AI 검색에서 후원자 명단 조회에 사용)
  FinanceService? finance;

  // ---------- 인증 / 세션 ----------
  bool _unlocked = false;
  String _tier = ''; // master | app | personal | guest
  String _who = ''; // 개인 로그인 시 식별자(인가번호 또는 전화번호)
  DateTime? _sessionStart;

  bool get unlocked => _unlocked;
  String get tier => _tier;
  String get who => _who;
  bool get isMaster => _tier == 'master';
  bool get isPersonal => _tier == 'personal';
  bool get isApp => _tier == 'app';
  bool get isGuest => _tier == 'guest';

  /// 이 세션이 영구 마스터 인가번호(예: 415)로 로그인됐는지.
  bool get isPermanentMaster => isMaster && AppConfig.isPermanentMaster(_who);

  /// 서버 마스터 작업용 값.
  /// 영구 마스터는 마스터 비번 없이 'PM:<인가번호>' 토큰으로 인가된다.
  String masterToken() => isPermanentMaster ? 'PM:$_who' : '';

  /// 본인 1인 열람(개인 접근) 모드 여부
  bool get isSelfAccess => _tier == 'personal' || _tier == 'guest';

  /// 개인 접근 시 본인 정보만 열람·수정 가능하도록 저장소 제한을 갱신
  void _applyAccessScope() {
    if (isSelfAccess && _who.isNotEmpty) {
      repo.restrictedNumber = _who;
    } else {
      repo.restrictedNumber = null;
    }
  }

  /// 세션 유효성 검사 (1시간)
  bool get sessionValid {
    if (!_unlocked || _sessionStart == null) return false;
    return DateTime.now().difference(_sessionStart!) < AppConfig.sessionTimeout;
  }

  Future<void> restoreSession() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ts = p.getInt(AppConfig.kSessionTs);
      final tier = p.getString(AppConfig.kAuthTier) ?? '';
      final who = p.getString(AppConfig.kAuthWho) ?? '';
      final sid = p.getString(AppConfig.kSessionSid) ?? '';
      if (ts != null && tier.isNotEmpty) {
        final start = DateTime.fromMillisecondsSinceEpoch(ts);
        if (DateTime.now().difference(start) < AppConfig.sessionTimeout) {
          // [보안] 저장된 세션토큰 복원 → 이후 API 요청이 인증된다.
          if (sid.isNotEmpty) {
            nas.sessionId = sid;
          } else if (repo.isNasMode) {
            // 토큰이 없으면 서버에서 재발급 시도(개인 QR 세션 등).
            try {
              await nas.grantSession(tier, id: who);
            } catch (_) {}
          }
          _unlocked = true;
          _tier = tier;
          _who = who;
          _sessionStart = start;
          _applyAccessScope();
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> login(String tier, String value, {String id = ''}) async {
    bool ok;
    // 개인 접근에서 입력된 인가번호 (ID 필드)
    String personalNo = '';
    if (tier == 'master') {
      // 마스터는 서버 검증(있으면) 우선, 없으면 로컬 상수
      ok = value == AppConfig.masterPassword;
      if (!ok && repo.isNasMode) {
        try {
          final r = await nas.login('master', value);
          ok = r['ok'] == true;
        } catch (_) {}
      }
    } else if (tier == 'app') {
      // 앱 접근: ID 는 "TSAK" (대문자, 고정) + 앱 비밀번호
      final idOk = id.trim().toUpperCase() == 'TSAK';
      ok = false;
      if (idOk) {
        // NAS 모드에서는 서버에 설정된 (마스터가 변경한) 비번으로 검증
        if (repo.isNasMode) {
          try {
            final r = await nas.login('app', value);
            ok = r['ok'] == true;
          } catch (_) {}
        }
        // 서버 미연결/오프라인이면 로컬 상수로 폴백
        if (!ok) ok = value == AppConfig.appPassword;
      }
    } else if (tier == 'guest') {
      // 비인가자(일반회원) 접근: ID = 휴대폰 전화번호, PW = 전화번호 뒤 4자리
      final phone = id.replaceAll(RegExp(r'[^0-9]'), '');
      ok = false;
      if (phone.length >= 4) {
        Member? reg;
        if (repo.isNasMode && phone.isNotEmpty) {
          try {
            final r = await nas.login('guest', value, id: phone);
            if (r['ok'] == true) {
              ok = true;
              final no = '${r['number'] ?? ''}';
              reg = no.isNotEmpty ? repo.byNumber(no) : null;
            }
          } catch (_) {}
        }
        if (!ok) {
          for (final m in repo.allUnscoped()) {
            final mid = m.loginId.replaceAll(RegExp(r'[^0-9]'), '');
            if (mid == phone || m.phone.replaceAll(RegExp(r'[^0-9]'), '') == phone) {
              final pw = m.personalPassword.trim().isNotEmpty
                  ? m.personalPassword.trim()
                  : m.phoneLast4;
              if (value == pw ||
                  value == '$phone$pw' ||
                  value == m.phoneLast4) {
                ok = true;
                reg = m;
              }
              break;
            }
          }
        }
        personalNo = reg?.number ?? '';
        if (ok && personalNo.isEmpty) personalNo = phone; // 번호 미상 시 전화로 식별
      }
    } else {
      // 개인 접근: ID=인가번호, 비밀번호=개인비밀번호
      //  - ID(인가번호)로 번호를 확정하고, 비밀번호는 다음 중 하나로 인정:
      //    ① 번호 + !@@ (예: 415!@@)   ② 접미사만 (예: !@@)
      //    ③ 관리자가 지정한 개인 비밀번호 / 마스터 비밀번호
      personalNo = id.replaceAll(RegExp(r'[^0-9]'), '');
      if (personalNo.isEmpty) {
        personalNo = value.replaceAll(RegExp(r'[^0-9]'), '');
      }
      final expected = '$personalNo${AppConfig.personalSuffix}';
      final candidates = <String>{value};
      if (personalNo.isNotEmpty) {
        candidates.add('$personalNo$value'); // 번호 + 입력값
      }
      // 로컬 검증 (기본값/마스터)
      ok = candidates.any(
        (c) =>
            c == expected ||
            c == AppConfig.masterPassword ||
            c == '$personalNo${AppConfig.personalSuffix}',
      );
      // 인가번호 존재 확인
      if (ok) {
        ok = repo.byNumber(personalNo) != null;
      }
      // 서버(개인별 지정 비번) 검증 (오프라인/로컬 실패 시)
      if (!ok && repo.isNasMode && personalNo.isNotEmpty) {
        for (final c in candidates) {
          try {
            final r = await nas.login('personal', c);
            if (r['ok'] == true) {
              ok = true;
              break;
            }
          } catch (_) {}
        }
      }
    }
    if (ok) {
      // 영구 마스터(예: 415)는 개인/비인가 로그인이라도 master 로 승격 →
      // 모든 관리 기능 + 본인 정보 접근을 동시에 가진다.
      var finalTier = tier;
      if ((tier == 'personal' || tier == 'guest') &&
          AppConfig.isPermanentMaster(personalNo)) {
        finalTier = 'master';
      }
      // [보안] 서버측 세션이 없으면 반드시 확보한다.
      //  앱은 일부 자격(예: 개인 415!@@)을 로컬에서 검증하므로 서버 세션이
      //  비어 있을 수 있다. 세션 없으면 이후 민감 API 가 전부 401 이 된다.
      if (repo.isNasMode && nas.sessionId.isEmpty) {
        try {
          if (finalTier == 'master') {
            await nas.grantSession('master', id: personalNo,
                master: AppConfig.masterPassword);
          } else if (finalTier == 'app') {
            await nas.grantSession('app'
                , master: AppConfig.masterPassword);
          } else if (tier == 'personal' || tier == 'guest') {
            await nas.grantSession(
                tier, id: personalNo.isNotEmpty ? personalNo : id);
          }
        } catch (_) {}
      }
      _unlocked = true;
      _tier = finalTier;
      // 영구 마스터는 본인 인가번호를 유지(내 QR·내 정보 기능 유지)
      _who = (tier == 'personal' || tier == 'guest') ? personalNo : '';
      _sessionStart = DateTime.now();
      _applyAccessScope();
      _persistSession();
      notifyListeners();
      // [보안] 로그인 전에는 서버가 데이터를 주지 않는다(401). 로그인 직후
      //  세션이 붙은 상태에서 서버 데이터를 다시 불러온다.
      if (repo.isNasMode) {
        unawaited(_reloadAfterLogin());
      }
    }
    return ok;
  }

  /// 로그인 직후 서버에서 (권한 범위의) 데이터를 재조회한다.
  Future<void> _reloadAfterLogin() async {
    try {
      await repo.syncFromNas();
    } catch (_) {}
    try {
      await loadConfig();
    } catch (_) {}
    // 재무는 관리자·마스터만 서버 응답을 받는다(그 외 401).
    if (isApp || isMaster) {
      try {
        await finance?.load();
      } catch (_) {}
    }
    refresh();
    notifyListeners();
  }

  Future<void> lock() async {
    _unlocked = false;
    _tier = '';
    _who = '';
    _sessionStart = null;
    repo.restrictedNumber = null;
    // [보안] 서버측 세션도 폐기 (세션토큰 탈취 재사용 방지)
    try {
      await nas.logout();
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(AppConfig.kSessionTs);
      await p.remove(AppConfig.kAuthTier);
      await p.remove(AppConfig.kAuthWho);
      await p.remove(AppConfig.kSessionSid);
    } catch (_) {}
    notifyListeners();
  }

  /// QR 스캔 = 개인 로그인으로 간주 (비밀번호 없이).
  ///
  /// 개인 QR에는 인가번호가 담겨 있고, 그 QR 자체가 자격증명이다.
  /// 권한은 **기존 개인 로그인과 완전히 동일** (추가 권한 없음).
  /// → 본인 정보만 열람·수정 가능.
  Future<bool> qrPersonalLogin(String number) async {
    final no = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (no.isEmpty) return false;

    // [보안] 서버에서 세션을 먼저 발급받는다 (QR 자체가 자격증명).
    //  · 세션 발급에 실패하면 다른 회원 정보가 노출되지 않도록 즉시 중단.
    //  · 개인 QR 이므로 항상 personal 등급(영구 마스터라 해도 승격하지 않음).
    var granted = false;
    if (repo.isNasMode) {
      try {
        granted = await nas.grantSession('personal', id: no);
      } catch (_) {}
      if (!granted) return false;
    }

    var m = repo.byNumber(no);
    // 세션 발급 직후에는 서버가 본인 1건을 반환하므로, 로컬에 없으면 서버에서
    //  본인 정보를 다시 받아 채운다(웹 memory 모드/시드 미포함 대응).
    if (m == null && granted) {
      try {
        await repo.syncFromNas();
      } catch (_) {}
      m = repo.byNumber(no);
    }
    if (m == null) return false;

    _unlocked = true;
    _tier = AppConfig.isPermanentMaster(no) ? 'master' : 'personal';
    _who = no;
    _sessionStart = DateTime.now();
    _applyAccessScope();
    _persistSession();
    notifyListeners();
    // 로그인 후 권한 범위 데이터 재조회.
    //  단, 개인 QR 로 발급된 personal 세션으로는 전체 목록을 받을 수 없으므로
    //  영구 마스터(415 등)는 시드 목록을 그대로 유지한다(권한 축소 방지).
    if (repo.isNasMode && !isMaster) {
      unawaited(_reloadAfterLogin());
    }
    return true;
  }

  Future<void> _persistSession() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(
        AppConfig.kSessionTs,
        _sessionStart!.millisecondsSinceEpoch,
      );
      await p.setString(AppConfig.kAuthTier, _tier);
      await p.setString(AppConfig.kAuthWho, _who);
      await p.setString(AppConfig.kSessionSid, nas.sessionId);
    } catch (_) {}
  }

  /// 주기적으로 세션 만료 확인 (잠금 화면 전환용)
  bool checkSessionExpiry() {
    if (_unlocked && !sessionValid) {
      lock();
      return true;
    }
    return false;
  }

  // ---------- 서버 설정 ----------
  Future<void> _loadServerBase() async {
    try {
      final p = await SharedPreferences.getInstance();
      final base = p.getString(AppConfig.kServerBase);
      if (base != null) nas.baseUrl = base;
    } catch (_) {}
  }

  Future<void> setServerBase(String base) async {
    nas.baseUrl = base;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(AppConfig.kServerBase, base);
    } catch (_) {}
    notifyListeners();
  }

  // ---------- 서버 메타 / 동기화 ----------
  Map<String, dynamic> _meta = {};
  Map<String, dynamic> get serverMeta => _meta;
  String get versionText {
    final u = _meta['updated'];
    final v = _meta['version'];
    if (u == null) return 'NAS 연결 대기';
    return 'v$v · $u';
  }

  String _sync = '';
  String get syncStatus => _sync;

  void _onMeta() {
    _meta = repo.serverMeta.value;
    notifyListeners();
  }

  void _onSync() {
    _sync = repo.syncStatus.value;
    notifyListeners();
  }

  Future<bool> refreshFromNas() async {
    final ok = await repo.syncFromNas();
    refresh();
    notifyListeners();
    return ok;
  }

  Future<bool> pushToNas() async => repo.syncToNas();

  // ---------- 설정(관리자 이메일, 후원, 개발자) ----------
  Map<String, dynamic> _config = {};
  Map<String, dynamic> get config => _config;
  String get adminEmail => '${_config['adminEmail'] ?? 'june7558@gmail.com'}';
  List<Map<String, dynamic>> get donations {
    final raw = _config['donations'];
    if (raw is List) {
      return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return const [
      {'label': '대표 (참가비·후원 등)', 'bank': '우리은행', 'account': '1005-202-281140'},
      {'label': '수품구매계좌', 'bank': '우리은행', 'account': '1005-102-281143'},
      {'label': '행사비계좌', 'bank': '우리은행', 'account': '1005-003-886274'},
    ];
  }

  String get donationHolder => '${_config['donationHolder'] ?? '한국범스카우트중앙회'}';
  Map<String, dynamic> get developer {
    final d = _config['developer'];
    if (d is Map) return d.cast<String, dynamic>();
    return {'name': '이승준', 'unit': '범스카우트415', 'email': 'june7558@gmail.com'};
  }

  String get appAccessUrl => '${_config['appAccessUrl'] ?? ''}';
  /// QR에 담을 **절대 접속 URL의 origin** 을 구한다.
  ///
  /// QR은 카메라/스캐너로 열리므로 반드시 http(s) 절대 주소여야 한다.
  /// 규칙(우선순위):
  ///   1) 마스터가 설정한 공개 주소(appAccessUrl) — 서버 저장
  ///   2) 웹에서 실행 중이면 현재 origin (배포 주소)
  ///   3) 빌드 시 지정한 공개 주소(--dart-define=APP_BASE_URL)
  /// ❌ NAS DSM 주소(:5001, 39.123.241.4)는 앱 주소가 아니므로 **절대 사용하지 않는다.**
  ///    (QR에 넣으면 스캔 시 DSM 로그인 페이지가 열려 앱이 뜨지 않음)
  String get qrBaseUrl {
    String norm(String s) => s.trim().replaceAll(RegExp(r'/+$'), '');

    // 1) 서버 설정(마스터 지정 공개 주소)
    final configured = norm(appAccessUrl);
    if (configured.startsWith('http') &&
        !AppConfig.isUnusableQrBase(configured)) {
      return configured;
    }
    // 2) 웹에서 실행 중이면 현재 origin 이 곧 배포 주소.
    final origin = norm(webOrigin());
    if (origin.startsWith('http') && !AppConfig.isUnusableQrBase(origin)) {
      return origin;
    }
    // 3) 빌드 시 지정한 공개 주소(--dart-define=APP_BASE_URL)
    final baked = norm(AppConfig.defaultAppBase);
    if (baked.startsWith('http') && !AppConfig.isUnusableQrBase(baked)) {
      return baked;
    }
    // 4) 공개 주소를 못 찾음 → 빈값 (QR 생성부에서 경고 표시)
    return '';
  }

  /// QR 생성이 가능한 상태인지(공개 접속 주소가 준비됨).
  bool get hasQrBase => qrBaseUrl.isNotEmpty;

  /// 개인 QR 딥링크 (절대 URL). 없으면 스킴 없는 상대경로.
  String personalQrLink(String number) {
    final base = qrBaseUrl;
    final q = '/?access=personal&no=${Uri.encodeComponent(number)}';
    return base.isEmpty ? q : '$base$q';
  }

  /// 행사 QR 딥링크 (절대 URL).
  /// 전용 경량 착지 페이지(/qr.html)로 연결한다 — 앱(5MB) 로딩 없이 즉시 뜬다.
  String eventQrLink(String year, String title) {
    final base = qrBaseUrl;
    final q = '/qr.html'
        '?year=${Uri.encodeComponent(year)}'
        '&title=${Uri.encodeComponent(title)}';
    return base.isEmpty ? q : '$base$q';
  }

  Future<void> loadConfig() async {
    try {
      if (repo.isNasMode) {
        final r = await nas.fetchConfig();
        if (r['ok'] == true && r['config'] is Map) {
          _config = (r['config'] as Map).cast<String, dynamic>();
          _meta = {..._meta, ...(repo.serverMeta.value)};
        }
      }
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      final e = p.getString(AppConfig.kAdminEmail);
      if (e != null && e.isNotEmpty) {
        _config['adminEmail'] = e;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> setAdminEmail(String email, String password) async {
    if (password != AppConfig.appPassword) return false;
    _config['adminEmail'] = email;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(AppConfig.kAdminEmail, email);
    } catch (_) {}
    if (repo.isNasMode) {
      try {
        await nas.saveConfig({'adminEmail': email});
      } catch (_) {}
    }
    notifyListeners();
    return true;
  }

  Future<bool> setConfig(Map<String, dynamic> patch) async {
    _config = {..._config, ...patch};
    notifyListeners();
    if (repo.isNasMode) {
      try {
        final r = await nas.saveConfig(patch);
        if (r['config'] is Map) {
          _config = (r['config'] as Map).cast<String, dynamic>();
        }
      } catch (_) {}
    }
    return true;
  }

  // ---------- 마스터 앱관리 ----------
  Map<String, dynamic> _admin = {};
  Map<String, dynamic> get adminState => _admin;
  bool get serverPaused => _admin['serverPaused'] == true;

  Future<void> loadAdmin() async {
    if (!repo.isNasMode) return;
    try {
      final r = await nas.adminState();
      if (r['ok'] == true) {
        _admin = r;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<String?> changeAppPassword(String master, String newPw) async {
    try {
      final r = await nas.changeAppPassword(master, newPw);
      if (r['ok'] == true) return null;
      return '${r['error'] ?? '실패'}';
    } catch (e) {
      return '$e';
    }
  }

  /// 접속 비밀번호 현재값 조회 (마스터 전용).
  /// 반환: {'password','defaultPassword','isDefault','isRegular'} 또는 null.
  Future<Map<String, dynamic>?> fetchMemberPassword(String number) async {
    if (!repo.isNasMode) return null;
    try {
      final r = await nas.memberPassword(number);
      if (r['ok'] == true) return r;
    } catch (_) {}
    return null;
  }

  /// 개인비번 초기화(reset=true) 또는 지정 변경
  Future<String?> setPersonalPassword(
    String master,
    String number, {
    String? value,
    bool reset = false,
  }) async {
    try {
      final r = await nas.setPersonalPassword(
        master,
        number,
        value: value,
        reset: reset,
      );
      if (r['ok'] == true) {
        _admin = {
          ..._admin,
          'personalPasswords': {
            ...((_admin['personalPasswords'] as Map?) ?? {}),
          },
        };
        await loadAdmin();
        return null;
      }
      return '${r['error'] ?? '실패'}';
    } catch (e) {
      return '$e';
    }
  }

  /// 개인 셀프 비밀번호 변경 (본인) — 성공 시 null, 실패 시 오류 메시지
  Future<String?> changePersonalPassword(String current, String newPw) async {
    if (who.isEmpty) return '본인 인가번호를 확인할 수 없습니다';
    try {
      final r = await nas.changePersonalPassword(who, current, newPw);
      if (r['ok'] == true) return null;
      return '${r['error'] ?? '실패'}';
    } catch (e) {
      return '$e';
    }
  }

  Future<bool> setServerPaused(String master, bool paused) async {
    try {
      final r = await nas.setServerPaused(master, paused);
      if (r['ok'] == true) {
        _admin = {..._admin, 'serverPaused': paused};
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// 서버 정지 여부만 조회 (health)
  Future<bool> refreshServerPaused() async {
    if (!repo.isNasMode) return false;
    final h = await nas.healthState();
    final p = h['paused'] == true;
    _admin = {..._admin, 'serverPaused': p};
    notifyListeners();
    return p;
  }

  // ---------- 리스트 크기 ----------
  double _listScale = 0.85;
  static const double listScaleMin = 0.7;
  static const double listScaleMax = 1.3;
  double get listScale => _listScale;

  Future<void> _loadFontScale() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getDouble('listScale');
      if (v != null) {
        _listScale = v.clamp(listScaleMin, listScaleMax);
        notifyListeners();
      }
    } catch (_) {}
  }

  void setListScale(double v) {
    _listScale = double.parse(
      v.clamp(listScaleMin, listScaleMax).toStringAsFixed(2),
    );
    notifyListeners();
    _persistFontScale();
  }

  Future<void> _persistFontScale() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('listScale', _listScale);
    } catch (_) {}
  }

  // ---------- 필터 ----------
  List<Member> _members = [];
  String _query = '';
  String _leagueFilter = '';
  String _yearFilter = '';
  bool _onlyLifetime = false;

  /// 회원 구분 필터: '' (전체) | 'credential' (인가자) | 'regular' (일반회원)
  ///                    | 'mentor' (멘토 지정) | 'parent' (보호자 지정)
  String _kindFilter = '';

  List<Member> get members => _members;
  String get query => _query;
  String get leagueFilter => _leagueFilter;
  String get yearFilter => _yearFilter;
  bool get onlyLifetime => _onlyLifetime;
  String get kindFilter => _kindFilter;

  Map<String, int> get leagues => repo.leaguesWithCount();
  List<String> get feeYears => repo.feeYearOptions();
  List<String> get events => repo.eventOptions();
  List<MapEntry<String, int>> get feeCounts => repo.feeCountsByYear();

  int get total => repo.count;
  int get lifetimeCount => _filterBase().where((m) => m.lifetimeMember).length;
  Map<String, int> get feeCountMap => {
    for (final e in repo.feeCountsByYear()) e.key: e.value,
  };

  void _onRepoChanged() {
    refresh();
  }

  void refresh() {
    var list = _filterBase();
    if (_leagueFilter.isNotEmpty) {
      if (_leagueFilter == '(미지정)') {
        list = list.where((m) => m.league.trim().isEmpty).toList();
      } else {
        list = list.where((m) => m.league == _leagueFilter).toList();
      }
    }
    if (_yearFilter.isNotEmpty) {
      list = list.where((m) => m.feeYears[_yearFilter] == true).toList();
    }
    if (_onlyLifetime) {
      list = list.where((m) => m.lifetimeMember).toList();
    }
    switch (_kindFilter) {
      case 'credential':
        list = list.where((m) => !m.isRegular).toList();
        break;
      case 'regular':
        list = list.where((m) => m.isRegular).toList();
        break;
      case 'mentor':
        list = list.where((m) => m.mentors.isNotEmpty).toList();
        break;
      case 'parent':
        list = list.where((m) => m.parents.isNotEmpty).toList();
        break;
    }
    if (_query.trim().isNotEmpty) {
      list = _applyQuery(list, _query.trim());
    }
    _members = list;
    notifyListeners();
  }

  /// 검색 질의 적용 — 범위 검색(1-100) / 하이픈 무관 전화 / 일반 통합검색 / AI 자연어
  List<Member> _applyQuery(List<Member> list, String rawQuery) {
    // 1) AI 자연어 검색 (복합 의도: "... 명단", "...납부자" 등)
    final ai = AiQuery.tryParse(rawQuery);
    if (ai != null) {
      return _applyAiQuery(list, ai);
    }

    // 2) 인가번호 범위 검색: "1-100", "500 - 1000"
    final range = RegExp(
      r'^\s*(\d{1,5})\s*[-~]\s*(\d{1,5})\s*$',
    ).firstMatch(rawQuery);
    if (range != null) {
      final a = int.parse(range.group(1)!);
      final b = int.parse(range.group(2)!);
      final lo = a <= b ? a : b;
      final hi = a <= b ? b : a;
      return list.where((m) => m.numberInt >= lo && m.numberInt <= hi).toList();
    }

    // 3) 일반 통합검색 — 하이픈 무관 전화번호 매칭 포함
    final q = rawQuery.toLowerCase();
    final parts = q.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final qDigits = rawQuery.replaceAll(RegExp(r'[^0-9]'), '');
    final qLooksLikePhone = qDigits.length >= 4;

    return list.where((m) {
      // 모든 토큰이 통합 텍스트에 포함되어야 함
      if (parts.every((p) => m.searchText.contains(p))) return true;
      // 하이픈을 제거한 숫자열이 전화번호에 포함되면 매칭 (예: 01012345678)
      if (qLooksLikePhone && m.phoneDigits.contains(qDigits)) return true;
      // 행사명(참석한 행사)으로 검색 — 행사 참가자 명단
      if (m.eventAttend.keys.any((e) => e.toLowerCase().contains(q))) {
        return true;
      }
      return false;
    }).toList();
  }

  // 개인 접근 시에는 본인 정보만 노출한다(all()이 restrictedNumber로 제한).
  List<Member> _filterBase() => repo.all();

  /// AI 자연어 검색 결과 적용
  List<Member> _applyAiQuery(List<Member> list, AiQuery ai) {
    switch (ai.kind) {
      case AiKind.feePaid:
        final y = ai.year;
        return list
            .where(
              (m) => y.isEmpty
                  ? m.feeYears.values.any((v) => v)
                  : m.feeYears[y] == true,
            )
            .toList();
      case AiKind.lifetime:
        return list.where((m) => m.lifetimeMember).toList();
      case AiKind.training:
        final kw = ai.keyword.trim();
        if (kw.isEmpty) {
          return list.where((m) => m.trainingStatus.trim().isNotEmpty).toList();
        }
        return list
            .where(
              (m) => m.trainingStatus.contains(kw) || m.searchText.contains(kw),
            )
            .toList();
      case AiKind.eventAttend:
        final kw = ai.keyword.trim().toLowerCase();
        if (kw.isEmpty) {
          return list.where((m) => m.eventAttend.values.any((v) => v)).toList();
        }
        return list.where((m) {
          // 행사명 키워드가 참석 행사명에 포함되면 매칭
          return m.eventAttend.keys.any(
            (e) => e.toLowerCase().contains(kw) && m.eventAttend[e] == true,
          );
        }).toList();
      case AiKind.donor:
        final fs = finance;
        if (fs == null) return [];
        final kw = ai.keyword.trim().toLowerCase();
        // 후원 카테고리 + (선택)키워드/연도로 매칭된 인가번호 집합
        final numbers = <String>{};
        for (final t in fs.transactions) {
          if (t.isExpense) continue;
          final isDonation =
              t.category == '후원' ||
              t.category == '찬조' ||
              t.category == '기부' ||
              t.category.contains('후원');
          if (!isDonation) continue;
          if (ai.year.isNotEmpty && t.year != ai.year) continue;
          if (kw.isNotEmpty) {
            final hay = '${t.event} ${t.memo} ${t.context} ${t.payer}'
                .toLowerCase();
            if (!hay.contains(kw)) continue;
          }
          final no = t.number.replaceAll(RegExp(r'[^0-9]'), '');
          if (no.isNotEmpty) numbers.add(no);
        }
        return list
            .where(
              (m) =>
                  numbers.contains(m.number.replaceAll(RegExp(r'[^0-9]'), '')),
            )
            .toList();
    }
  }

  void setQuery(String q) {
    _query = q;
    refresh();
  }

  void setLeague(String l) {
    _leagueFilter = l;
    refresh();
  }

  void setYear(String y) {
    _yearFilter = y;
    refresh();
  }

  void setOnlyLifetime(bool v) {
    _onlyLifetime = v;
    refresh();
  }

  void setKind(String k) {
    _kindFilter = k;
    refresh();
  }

  void clearFilters() {
    _query = '';
    _leagueFilter = '';
    _yearFilter = '';
    _onlyLifetime = false;
    _kindFilter = '';
    refresh();
  }

  Member? byId(String id) => repo.byId(id);
  Member? byNumber(String number) => repo.byNumber(number);

  /// 개인/비인가자 접근에서 특정 회원이 본인인지 여부
  bool isSelfNumber(String number) {
    if (!isSelfAccess || who.isEmpty) return true;
    final a = who.replaceAll(RegExp(r'[^0-9]'), '');
    final b = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (a == b) return true;
    // 전화번호 기반(일반회원) 매칭
    for (final m in repo.all()) {
      final n = m.number.replaceAll(RegExp(r'[^0-9]'), '');
      final l = m.loginId.replaceAll(RegExp(r'[^0-9]'), '');
      if (n == b && l == a) return true;
    }
    return false;
  }

  Future<void> save(Member m) async {
    await repo.save(m);
  }

  /// 신규 일반회원(비인가자) 생성.
  /// id = 휴대폰 전화번호, pw = 전화번호 뒤 4자리 자동 설정.
  /// 반환: 성공 시 생성된 Member, 실패 시 null.
  Future<Member?> createRegularMember(
    String name,
    String phone, {
    bool privacyAgreed = true,
    String privacyAgreedAt = '',
  }) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (name.trim().isEmpty || digits.length < 4) return null;
    // 개인정보 동의 없이는 가입 불가
    if (!privacyAgreed) return null;
    // 중복 번호 방지 (인가자/일반회원 모두)
    for (final m in repo.allUnscoped()) {
      final pid = m.loginId.replaceAll(RegExp(r'[^0-9]'), '');
      final pph = m.phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (pid == digits || pph == digits) return null;
    }
    final last4 = digits.length >= 4
        ? digits.substring(digits.length - 4)
        : digits;
    final id = 'reg_${digits}_${DateTime.now().millisecondsSinceEpoch}';
    final m = Member(
      id: id,
      number: '', // 인가번호 없음(비인가자)
      name: name.trim(),
      phone: phone.trim(),
      accessPhone: digits,
      isRegular: true,
      personalPassword: last4,
      privacyAgreed: true,
      privacyAgreedAt: privacyAgreedAt.isNotEmpty ? privacyAgreedAt : _stamp(),
    );
    await repo.save(m);
    return m;
  }

  /// 현재 시각 문자열 (예: "2025.09.24 10:30")
  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}.${two(n.month)}.${two(n.day)} ${two(n.hour)}:${two(n.minute)}';
  }

  /// 특정 회원(인가자/일반회원) 비밀번호 강제 변경/초기화 (마스터·관리자 전용)
  Future<String?> setMemberPassword(
    Member m, {
    String? value,
    bool reset = false,
  }) async {
    final newPw = reset
        ? (m.isRegular ? m.phoneLast4 : '${m.number}${AppConfig.personalSuffix}')
        : (value ?? '').trim();
    if (newPw.isEmpty) return '비밀번호가 비어 있습니다';
    await repo.save(m.copyWith(personalPassword: newPw));
    if (repo.isNasMode) {
      try {
        await nas.setAdminPassword(
          tier: isMaster ? 'master' : 'app',
          id: m.loginId,
          value: newPw,
          reset: reset,
          master: isPermanentMaster ? masterToken() : null,
        );
      } catch (_) {}
    }
    return null;
  }

  /// 멘토/페런츠로 지정된(연결된) 회원 수 등 파생 통계
  int get mentorLinkedCount =>
      repo.all().where((m) => m.mentors.isNotEmpty).length;
  int get parentLinkedCount =>
      repo.all().where((m) => m.parents.isNotEmpty).length;
  int get regularCount => repo.all().where((m) => m.isRegular).length;
  int get credentialCount => repo.all().where((m) => !m.isRegular).length;

  /// 일반회원(비인가자) 목록 — 관리 화면용 (이름 가나다순)
  List<Member> get regularMembers {
    final list = repo.all().where((m) => m.isRegular).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// 개인정보 동의 현황
  int get privacyAgreedCount =>
      repo.all().where((m) => m.privacyAgreed).length;
  int get privacyPendingCount =>
      repo.all().where((m) => !m.privacyAgreed).length;

  /// 비인가자(일반회원) → 인가자 승격
  ///  - number: 부여할 인가번호, league/unit: 소속 정보
  ///  - 성공 시 갱신된 Member, 실패 시 null
  Future<Member?> promoteToCredential(
    Member m, {
    required String number,
    String league = '',
    String unit = '',
  }) async {
    if (!(isApp || isMaster)) return null;
    final n = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (n.isEmpty) return null;
    // 인가번호 중복 방지
    for (final x in repo.allUnscoped()) {
      if (x.id != m.id &&
          x.number.replaceAll(RegExp(r'[^0-9]'), '') == n) {
        return null;
      }
    }
    final updated = m.copyWith(
      number: n,
      isRegular: false,
      league: league.trim().isEmpty ? m.league : league.trim(),
      unit: unit.trim().isEmpty ? m.unit : unit.trim(),
    );
    await repo.save(updated);
    return updated;
  }

  /// 인가자 → 일반회원(비인가자) 강등 (잘못 등록된 경우)
  Future<Member?> demoteToRegular(Member m) async {
    if (!(isApp || isMaster)) return null;
    final updated = m.copyWith(isRegular: true, number: '');
    await repo.save(updated);
    return updated;
  }

  Future<void> delete(String id) async {
    await repo.delete(id);
  }

  Future<int> nextNumber() => repo.nextNumber();

  Map<int, int> get yearDistribution {
    final map = <int, int>{};
    for (final m in repo.all()) {
      final y = int.tryParse(m.date.replaceAll('.', '-').split('-').first);
      if (y != null && y > 1900) map[y] = (map[y] ?? 0) + 1;
    }
    return map;
  }

  @override
  void dispose() {
    repo.revision.removeListener(_onRepoChanged);
    repo.serverMeta.removeListener(_onMeta);
    repo.syncStatus.removeListener(_onSync);
    super.dispose();
  }
}
