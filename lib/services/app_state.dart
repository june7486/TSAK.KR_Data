import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async' show unawaited;

import '../models/member.dart';
import 'ai_query.dart';
import 'app_config.dart';
import 'finance_service.dart';
import 'league_names.dart';
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
    loadPermanentMasterMode();
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

  // ---------- 역할 / 메뉴 접근권한 ----------
  /// 서포터즈(일반회원 로그인) 여부 — 서버 로그인 응답으로 설정.
  bool _isSupporter = false;
  bool get isSupporter => _isSupporter;

  /// 실효 역할 키 — master | app | personal | supporter | guest
  /// (관리자 부여 계정은 app, 일반회원 개인로그인은 supporter 로 본다)
  String get roleKey {
    if (isMaster) return 'master';
    if (isApp) return 'app';
    if (_isSupporter) return 'supporter';
    if (_tier == 'guest') return 'guest';
    return 'personal';
  }

  /// 서버가 내려준 역할별 메뉴권한 (없으면 빈 맵 → 기본 허용 로직 사용).
  Map<String, Map<String, bool>> _perms = {};
  Map<String, Map<String, bool>> get perms => _perms;

  /// 현재 역할의 메뉴 접근 가능 여부.
  ///  서버 권한표가 있으면 그것을, 없으면 기존 티어 규칙으로 판정한다.
  bool can(String menu) {
    final table = _perms[roleKey];
    if (table != null && table.containsKey(menu)) {
      return table[menu] == true;
    }
    // 서버 권한표 미수신 시 폴백(기존 동작 보존).
    switch (menu) {
      case 'bulk':
      case 'stats':
        return isApp || isMaster;
      case 'finance':
      case 'merchMgmt':
      case 'memberAdd':
        return isApp || isMaster;
      case 'memberDetail':
        return !(_tier == 'personal' || _tier == 'guest' || _isSupporter) ||
            isMaster ||
            isApp;
      case 'memberSearch':
        return !(_tier == 'guest' || _isSupporter) || isMaster || isApp;
      case 'board':
      case 'events':
      case 'merchBuy':
        return true;
      default:
        return false;
    }
  }

  /// 서버 역할별 권한표 로드.
  Future<void> loadRolePermissions() async {
    if (!repo.isNasMode) return;
    try {
      final p = await nas.fetchPerms();
      if (p.isNotEmpty) {
        _perms = p;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 마스터가 역할 권한을 변경(서버 저장 후 로컬 반영).
  Future<bool> setRolePermission(String role, Map<String, bool> updates) async {
    if (!isMaster || !repo.isNasMode) return false;
    try {
      final ok = await nas.setPerms(role, updates);
      if (ok) await loadRolePermissions();
      return ok;
    } catch (_) {
      return false;
    }
  }

  bool get isPersonal => _tier == 'personal';

  /// 관리자(app) 등급 — 마스터는 관리자의 모든 권한을 상속한다.
  /// 또한 마스터가 '관리자 지정'을 부여한 인가번호도 app 세션을 받으므로
  /// 서버가 내려준 admin 플래그와 함께 관리자로 취급한다.
  bool get isApp => _tier == 'app' || _tier == 'master' || _grantedAdmin;
  bool get isGuest => _tier == 'guest';

  /// 마스터가 부여한 관리자 권한(개인 로그인 시 서버가 알려줌).
  bool _grantedAdmin = false;
  bool get isGrantedAdmin => _grantedAdmin;

  // ---------- 데이터 로딩 상태 ----------
  /// 서버(또는 로컬)에서 명단을 불러오는 중인지 — 첫 화면 로딩 문구에 사용.
  bool _membersLoading = false;
  bool get membersLoading => _membersLoading;

  /// 명단을 최초 1회 이상 로드 완료했는지(빈 목록과 로딩 중을 구분).
  bool _membersLoaded = false;
  bool get membersLoaded => _membersLoaded;

  /// 현재 명단 로딩 상태를 갱신하고 UI에 알린다.
  void _setMembersLoading(bool v) {
    if (_membersLoading == v) return;
    _membersLoading = v;
    notifyListeners();
  }

  /// 이 세션이 영구 마스터 인가번호(예: 415)로 로그인됐는지.
  bool get isPermanentMaster => isMaster && AppConfig.isPermanentMaster(_who);

  /// 영구 마스터(415)의 권한 선택 모드.
  ///  true = 마스터 권한 사용(기본), false = 개인 권한만 사용.
  bool _permanentMasterMode = true;
  bool get permanentMasterMode => _permanentMasterMode;

  /// 영구 마스터가 '개인 권한'을 선택했는지 — 이 경우 마스터 기능 UI를 숨긴다.
  bool get isPermanentMasterAsPersonal =>
      AppConfig.isPermanentMaster(_who) && !_permanentMasterMode;

  /// 영구 마스터 권한 모드 불러오기.
  Future<void> loadPermanentMasterMode() async {
    try {
      final p = await SharedPreferences.getInstance();
      _permanentMasterMode = p.getBool(AppConfig.kPermanentMasterMode) ?? true;
    } catch (_) {}
    notifyListeners();
  }

  /// 영구 마스터 권한 모드 설정·저장. 즉시 UI에 반영된다.
  Future<void> setPermanentMasterMode(bool master) async {
    _permanentMasterMode = master;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(AppConfig.kPermanentMasterMode, master);
    } catch (_) {}
    notifyListeners();
  }

  /// 실효 티어 — 영구 마스터가 개인권한을 선택하면 personal 로 취급(마스터 UI 숨김).
  String get effectiveTier {
    if (isMaster && isPermanentMasterAsPersonal) return 'personal';
    return _tier;
  }

  /// UI 노출용 — 마스터 기능(관리창·통계 등)을 화면에 표시할지.
  /// 영구 마스터가 개인권한을 선택하면 false(단, 서버 인증용 isMaster 는 유지).
  bool get showMasterUi => isMaster && !isPermanentMasterAsPersonal;

  /// UI 노출용 — 관리자 이상 기능을 화면에 표시할지.
  bool get showAdminUi => isApp && !isPermanentMasterAsPersonal;

  /// 서버 마스터 작업용 값.
  /// 영구 마스터는 마스터 비번 없이 'PM:<인가번호>' 토큰으로 인가된다.
  String masterToken() => isPermanentMaster ? 'PM:$_who' : '';

  /// 본인 1인 열람(개인 접근) 모드 여부.
  /// 영구 마스터(415)가 '개인 권한'을 선택한 경우도 본인 화면으로 취급한다.
  bool get isSelfAccess =>
      _tier == 'personal' || _tier == 'guest' || isPermanentMasterAsPersonal;

  /// 개인 접근 시 본인 정보만 열람·수정 가능하도록 저장소 제한을 갱신
  void _applyAccessScope() {
    // 개인 접근이라도 HOME(메인 홈)으로 들어가 권한 범위 열람 중이면
    //  제한을 풀어 서버가 내려준(권한 범위) 명단을 보여준다.
    if (isSelfAccess && _who.isNotEmpty && !_personalBrowse) {
      repo.restrictedNumber = _who;
    } else {
      repo.restrictedNumber = null;
    }
  }

  /// 개인 접근에서 HOME(메인 홈)을 눌러 권한 범위를 열람 중인지.
  bool _personalBrowse = false;
  bool get personalBrowse => _personalBrowse;

  /// HOME / 개인 화면 전환 — 저장소 접근 범위를 즉시 갱신한다.
  void setPersonalBrowse(bool v) {
    if (_personalBrowse == v) return;
    _personalBrowse = v;
    _applyAccessScope();
    refresh();
    notifyListeners();
    // HOME(권한 범위) 진입 시 서버에서 권한 범위 명단을 다시 받아 채운다.
    if (v && repo.isNasMode) {
      unawaited(repo.syncFromNas().then((_) => refresh()));
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
          // 세션 복원 시에도 최신 명단을 백그라운드로 재조회(로딩 문구 표시).
          if (repo.isNasMode) {
            _setMembersLoading(true);
            unawaited(_reloadAfterLogin());
          }
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
            if (mid == phone ||
                m.phone.replaceAll(RegExp(r'[^0-9]'), '') == phone) {
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
            final r = await nas.login('personal', c, id: personalNo);
            if (r['ok'] == true) {
              ok = true;
              break;
            }
          } catch (_) {}
        }
      }
      // 서버 검증으로 성공한 경우엔 이미 세션이 발급됐고(관리자 부여 플래그),
      //  로컬 검증만 성공한 경우 세션을 별도로 확보한다(아래에서 처리).
      if (ok && repo.isNasMode && nas.sessionId.isNotEmpty) {
        _grantedAdmin = nas.lastLoginAdmin;
        _isSupporter = nas.lastLoginSupporter;
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
            await nas.grantSession(
              'master',
              id: personalNo,
              master: AppConfig.masterPassword,
              log: true,
            );
          } else if (finalTier == 'app') {
            await nas.grantSession(
              'app',
              master: AppConfig.masterPassword,
              log: true,
            );
          } else if (tier == 'personal' || tier == 'guest') {
            await nas.grantSession(
              tier,
              id: personalNo.isNotEmpty ? personalNo : id,
              log: true,
            );
          }
        } catch (_) {}
      }
      _unlocked = true;
      _tier = finalTier;
      // 영구 마스터는 본인 인가번호를 유지(내 QR·내 정보 기능 유지)
      _who = (tier == 'personal' || tier == 'guest') ? personalNo : '';
      _sessionStart = DateTime.now();
      _personalBrowse = false;
      _applyAccessScope();
      _persistSession();
      notifyListeners();
      // 역할별 메뉴권한표 로드(마스터가 설정한 값 반영).
      if (repo.isNasMode) unawaited(loadRolePermissions());
      // [보안] 로그인 전에는 서버가 데이터를 주지 않는다(401). 로그인 직후
      //  세션이 붙은 상태에서 서버 데이터를 다시 불러온다.
      if (repo.isNasMode) {
        // 화면이 즉시 "불러오는 중" 문구를 표시하도록 로딩 플래그를 켠다.
        _setMembersLoading(true);
        unawaited(_reloadAfterLogin());
      }
    }
    return ok;
  }

  /// 로그인 직후 서버에서 (권한 범위의) 데이터를 재조회한다.
  Future<void> _reloadAfterLogin() async {
    _setMembersLoading(true);
    try {
      await repo.syncFromNas();
      _membersLoaded = true;
    } catch (_) {}
    //  서버 동기화가 끝나면 먼저 명단을 화면에 반영(체감 로딩 단축).
    refresh();
    _setMembersLoading(false);
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
    _grantedAdmin = false;
    _isSupporter = false;
    _personalBrowse = false;
    _perms = {};
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

  // ---------- 회원정보 항목별 노출 설정 (마스터) ----------
  /// 민감정보로 취급되는 필드 키 — 설정이 없으면 기본 **비노출**.
  ///   · 스카우트 고유번호(scoutNo)·주민등록번호(residentNo)는 비노출이 기본값.
  static const Set<String> sensitiveFields = {
    'scoutNo',
    'residentNo',
    'tel',
    'phone',
    'email',
    'address',
    'zipCode',
    'birthday',
  };

  Map<String, dynamic> get fieldVisibility {
    final raw = _config['fieldVisibility'];
    if (raw is Map) return raw.map((k, v) => MapEntry('$k', v == true));
    return const {};
  }

  /// 항목 노출 여부. 서버/로컬 설정에 값이 있으면 그 값을,
  /// 없으면 민감정보는 비노출(기본 안전)로 판단한다.
  bool fieldVisible(String key) {
    final fv = _config['fieldVisibility'];
    if (fv is Map && fv.containsKey(key)) {
      final v = fv[key];
      return v == true || v == 1 || v == 'true';
    }
    return !sensitiveFields.contains(key);
  }

  Future<void> setFieldVisibility(String key, bool visible) async {
    // 로컬·서버 모두 안전하도록 기존 설정 위에 병합해 전송한다.
    final next = {...fieldVisibility, key: visible};
    await setConfig({'fieldVisibility': next});
  }

  // ---------- 회원별 항목 노출 권한 (마스터가 개인 페이지에서 지정) ----------
  //  값: 'public'(노출) | 'admin'(관리자노출) | 'hidden'(비노출)
  //  지정이 없으면 전역 기본 노출(fieldVisibility)을 따른다.
  static const String permPublic = 'public';
  static const String permAdmin = 'admin';
  static const String permHidden = 'hidden';

  /// 특정 회원(member) 항목의 유효 노출 권한을 반환한다.
  String permFor(Member m, String key) {
    final v = m.fieldPerms[key];
    if (v == permPublic) return permPublic;
    if (v == permAdmin) return permAdmin;
    if (v == permHidden) return permHidden;
    return fieldVisible(key) ? permPublic : permHidden;
  }

  /// 개인 프로필에서 그 항목이 **[보는 사람]에게** 보이는지 판정.
  ///  · 관리자/마스터/본인: 'hidden' 이어도 보인다(관리 목적).
  ///  · 그 외(타인·비인가자): 'public' 일 때만 보인다.
  bool canViewField(
    Member m,
    String key, {
    required bool isAdminViewer,
    bool isSelf = false,
  }) {
    final p = permFor(m, key);
    if (isAdminViewer || isSelf) return true;
    return p == permPublic;
  }

  /// 표시할 값(문자열) — 권한 없으면 빈 문자열. 비노출(민감)은 마스킹.
  String visibleFieldValue(
    Member m,
    String key,
    String rawValue, {
    required bool isAdminViewer,
    bool isSelf = false,
  }) {
    if (canViewField(m, key, isAdminViewer: isAdminViewer, isSelf: isSelf)) {
      return rawValue;
    }
    return '';
  }

  /// 마스터: 회원의 특정 항목 노출 권한을 저장한다.
  Future<void> setMemberFieldPerm(Member m, String key, String? value) async {
    final next = Map<String, String>.from(m.fieldPerms);
    if (value == null || value.isEmpty) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    await save(m.copyWith(fieldPerms: next));
  }

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
    final q =
        '/qr.html'
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

  /// 프로필 열람 로그 기록 — 마스터/관리자/타 회원이 개인 프로필을 열람한 이력.
  /// (본인 로그인 열람은 서버에서 중복 기록을 생략한다.)
  Future<void> logProfileView(String number) async {
    if (!repo.isNasMode) return;
    if (number.trim().isEmpty) return;
    try {
      await nas.logProfileView(number);
    } catch (_) {}
  }

  /// 회원 접속 로그 조회 (마스터 전용, 최신 100건).
  Future<List<Map<String, dynamic>>> fetchMemberAccessLog(String number) async {
    if (!repo.isNasMode || !isMaster) return [];
    try {
      return await nas.memberAccessLog(number);
    } catch (_) {
      return [];
    }
  }

  /// 전체 회원 접속·열람 로그 조회 (마스터 전용, 최신 limit건).
  Future<List<Map<String, dynamic>>> fetchAllAccessLogs({
    int limit = 200,
  }) async {
    if (!repo.isNasMode || !isMaster) return [];
    try {
      return await nas.allAccessLogs(limit: limit);
    } catch (_) {
      return [];
    }
  }

  /// 접속 로그 삭제 (마스터 전용).
  Future<bool> deleteMemberAccessLog({
    String mode = 'one',
    String? ts,
    String? number,
    List<Map<String, dynamic>>? items,
  }) async {
    if (!repo.isNasMode || !isMaster) return false;
    try {
      return await nas.deleteAccessLog(
        mode: mode,
        ts: ts,
        number: number,
        items: items,
      );
    } catch (_) {
      return false;
    }
  }

  // ---------- 회원 등록요청 (평생회원·연회비·자격) ----------
  /// 등록요청 제출 (로그인 회원 누구나). 성공 시 null, 실패 시 메시지.
  Future<String?> submitMemberRequest({
    required String type,
    String year = '',
    String date = '',
    String note = '',
    String newNumber = '',
    String event = '',
  }) async {
    if (!repo.isNasMode) return '서버 연결이 필요합니다';
    try {
      final r = await nas.memberRequestSubmit(
        type: type,
        ident: who,
        year: year,
        date: date,
        note: note,
        newNumber: newNumber,
        event: event,
      );
      if (r['ok'] == true) return null;
      return '${r['error'] ?? '요청 실패'}';
    } catch (e) {
      return '$e';
    }
  }

  /// 등록요청 대기 목록 조회(관리자·마스터).
  Future<List<Map<String, dynamic>>> fetchMemberRequests() async {
    if (!repo.isNasMode || !(isApp || isMaster)) return [];
    try {
      return await nas.memberRequestList();
    } catch (_) {
      return [];
    }
  }

  /// 본인(개인 프로필)의 등록요청 이력 조회 — 로그인 회원 누구나.
  /// [ident] 미지정 시 로그인 세션의 who 를 사용한다.
  Future<List<Map<String, dynamic>>> fetchMyMemberRequests({
    String ident = '',
  }) async {
    if (!repo.isNasMode) return [];
    final id = ident.trim().isNotEmpty ? ident : who;
    if (id.trim().isEmpty) return [];
    try {
      return await nas.myMemberRequests(ident: id);
    } catch (_) {
      return [];
    }
  }

  /// 통합 승인 대시보드(관리자·마스터) — 승인 대기 큐 목록.
  Future<List<Map<String, dynamic>>> fetchApprovalOverview() async {
    if (!repo.isNasMode || !(isApp || isMaster)) return [];
    try {
      final j = await nas.approvalOverview();
      return ((j['queues'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 승인 대기 총 건수(배지용, 관리자·마스터).
  Future<int> fetchApprovalPendingTotal() async {
    if (!repo.isNasMode || !(isApp || isMaster)) return 0;
    try {
      return await nas.approvalPendingTotal();
    } catch (_) {
      return 0;
    }
  }

  /// 해당 아이디가 아직 '확인'하지 않은 승인 대기 건수(배지 표시용).
  /// 승인화면을 열어 확인하면 0 으로 차감된다.
  Future<int> fetchApprovalUnread() async {
    if (!repo.isNasMode || !(isApp || isMaster)) return 0;
    try {
      return await nas.approvalUnread();
    } catch (_) {
      return 0;
    }
  }

  /// 배지 '확인(읽음)' 처리 — 해당 아이디 기준으로 지금까지 항목을 확인 처리.
  /// [kind] = 'approval' | 'board' | 'all'
  Future<bool> markBadgeSeen({String kind = 'all'}) async {
    if (!repo.isNasMode || !(isApp || isMaster)) return false;
    try {
      return await nas.badgeSeen(kind: kind);
    } catch (_) {
      return false;
    }
  }

  /// 등록 가능한 행사명 목록(선택용) — 서버 events + 개인 프로필 참가행사.
  Future<List<String>> getAllEvents() async {
    final set = <String>{};
    try {
      if (repo.isNasMode) {
        final ev = await nas.eventList2(media: false);
        for (final e in ev) {
          if (e['defined'] == false) continue;
          final t = '${e['title'] ?? ''}'.trim();
          if (t.isNotEmpty) set.add(t);
        }
      }
    } catch (_) {}
    for (final m in repo.allUnscoped()) {
      set.addAll(m.eventAttend.keys.where((e) => e.trim().isNotEmpty));
    }
    final list = set.toList()
      ..sort((a, b) {
        final ya = RegExp(r'\d{4}').firstMatch(a)?.group(0) ?? '0000';
        final yb = RegExp(r'\d{4}').firstMatch(b)?.group(0) ?? '0000';
        if (ya != yb) return yb.compareTo(ya);
        return b.compareTo(a);
      });
    return list;
  }

  /// 등록요청 승인/반려 처리 후 로컬 캐시 갱신.
  Future<bool> setMemberRequest(String id, String action) async {
    if (!repo.isNasMode || !(isApp || isMaster)) return false;
    try {
      final ok = await nas.memberRequestSet(id: id, action: action);
      if (ok) await repo.syncFromNas();
      return ok;
    } catch (_) {
      return false;
    }
  }

  // ---------- 일반회원 승인 시스템 ----------
  /// 미승인(승인 대기) 일반회원 목록.
  List<Member> get pendingMembers =>
      repo.all().where((m) => m.isPendingOnly).toList();

  /// 전체 일반회원 중 미승인 수.
  int get pendingApprovalCount => pendingMembers.length;

  /// 서버 승인 대기 목록 조회(관리자·마스터).
  Future<List<Map<String, dynamic>>> fetchApprovalPending() async {
    if (!repo.isNasMode || !(isApp || isMaster)) return [];
    try {
      return await nas.approvalPending();
    } catch (_) {
      return [];
    }
  }

  // ---------- 승인 히스토리 (통합승인관리 하단) ----------
  /// 승인 히스토리 목록(관리자·마스터).
  /// [source] = ''(전체) | 'regular' | 'request' | 'link'
  Future<List<Map<String, dynamic>>> fetchApprovalHistory({
    int limit = 200,
    String source = '',
  }) async {
    if (!repo.isNasMode || !(isApp || isMaster)) return [];
    try {
      return await nas.approvalHistory(limit: limit, source: source);
    } catch (_) {
      return [];
    }
  }

  /// 히스토리 항목 복원 → 다시 승인창(대기 큐)으로 올린다(관리자·마스터).
  Future<bool> restoreApprovalHistory(String id) async {
    if (!repo.isNasMode || !(isApp || isMaster)) return false;
    try {
      final ok = await nas.approvalHistoryRestore(id: id);
      if (ok) await repo.syncFromNas();
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// 히스토리 항목 삭제(관리자·마스터).
  Future<bool> deleteApprovalHistory(List<String> ids) async {
    if (!repo.isNasMode || !(isApp || isMaster) || ids.isEmpty) return false;
    try {
      return await nas.approvalHistoryDelete(ids: ids);
    } catch (_) {
      return false;
    }
  }

  /// 승인/보류/미승인/삭제 일괄 처리 후 로컬 캐시 갱신.
  Future<int> setApproval(String action, List<String> idents) async {
    if (!repo.isNasMode || !(isApp || isMaster) || idents.isEmpty) return 0;
    try {
      final r = await nas.approvalSet(action: action, idents: idents);
      if (r['ok'] == true) {
        if (action == 'delete') {
          for (final id in idents) {
            final m = repo.byId(id);
            if (m != null) await repo.delete(m.id);
          }
        } else {
          final status = {
            'approve': 'approved',
            'hold': 'held',
            'pending': 'pending',
          }[action];
          if (status != null) {
            for (final id in idents) {
              final m = repo.byId(id);
              if (m != null) {
                await repo.save(m.copyWith(approvalStatus: status));
              }
            }
          }
        }
        await repo.syncFromNas();
        return (r['done'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// 은행거래 종합분석 — 캐시 우선(force=재분석).
  Map<String, dynamic> _financeAnalysis = {};

  Map<String, dynamic> get financeAnalysis => _financeAnalysis;
  bool get hasFinanceAnalysis => _financeAnalysis.isNotEmpty;

  /// 은행거래 종합분석 로드(캐시). 성공 시 데이터 반환.
  Future<Map<String, dynamic>> loadFinanceAnalysis({bool force = false}) async {
    if (!repo.isNasMode || !(isApp || isMaster)) return {};
    try {
      final a = await nas.financeAnalysis(force: force);
      _financeAnalysis = a;
      notifyListeners();
      return a;
    } catch (_) {
      return {};
    }
  }

  /// 은행거래 종합분석 — 항상 최신 폴더 기준 재분석(작업중 화면용).
  Future<Map<String, dynamic>> analyzeFinanceFresh() async {
    if (!repo.isNasMode || !(isApp || isMaster)) return {};
    try {
      final a = await nas.financeAnalysisFresh();
      _financeAnalysis = a;
      notifyListeners();
      return a;
    } catch (_) {
      return {};
    }
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

  /// 필터와 무관한 전체 회원 목록(통계 산출용).
  List<Member> get allMembers => repo.all();

  String get query => _query;
  String get leagueFilter => _leagueFilter;
  String get yearFilter => _yearFilter;
  bool get onlyLifetime => _onlyLifetime;
  String get kindFilter => _kindFilter;

  Map<String, int> get leagues => repo.leaguesWithCount();

  /// 현재활동(재적) 소속연맹 기준 연맹별 인가자 수.
  ///   regLeague(현재활동 연맹)가 없으면 인가시 연맹(league)으로 폴백한다.
  Map<String, int> get leaguesCurrentActivity =>
      repo.leaguesWithCount(currentActivity: true);

  /// 현재활동 항목(연맹/단위대/직위) 데이터가 하나라도 있는지.
  bool get hasCurrentActivity => repo.hasCurrentActivityData();

  /// 직위(현재활동) 분포.
  Map<String, int> get positions => repo.positionsWithCount();

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
        list = list.where((m) => sameLeague(m.league, _leagueFilter)).toList();
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
  Member? byName(String name) => repo.byName(name);

  /// 이름 공개/비공개 로컬 반영 (서버 저장은 호출부에서 완료 후 호출).
  void setNameVisible(String id, bool visible) {
    final m = repo.rawById(id) ?? repo.byId(id);
    if (m == null) return;
    repo.saveLocalOnly(m.copyWith(nameVisible: visible));
    notifyListeners();
  }

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
        ? (m.isRegular
              ? m.phoneLast4
              : '${m.number}${AppConfig.personalSuffix}')
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

  /// 멘토·페런츠 연결 승인 현황 (요구: 통계에 포함 — 승인 워크플로)
  ///   · approved : 승인된 연결
  ///   · pending  : 미승인(승인요청됨)
  ///   · held     : 보류
  int _linkStatusCount(String status) => repo
      .all()
      .where(
        (m) =>
            (m.mentors.isNotEmpty || m.parents.isNotEmpty) &&
            m.linkApprovalStatus == status,
      )
      .length;
  int get linkApprovedCount => _linkStatusCount('approved');
  int get linkPendingCount => _linkStatusCount('pending');
  int get linkHeldCount => _linkStatusCount('held');

  /// 연결은 있으나 승인 상태가 없는(레거시) 회원 수.
  int get linkUnsetCount => repo
      .all()
      .where(
        (m) =>
            (m.mentors.isNotEmpty || m.parents.isNotEmpty) &&
            m.linkApprovalStatus.isEmpty,
      )
      .length;

  int get regularCount => repo.all().where((m) => m.isRegular).length;
  int get credentialCount => repo.all().where((m) => !m.isRegular).length;

  /// 일반회원(비인가자) 목록 — 관리 화면용 (이름 가나다순)
  List<Member> get regularMembers {
    final list = repo.all().where((m) => m.isRegular).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// 개인정보 동의 현황
  int get privacyAgreedCount => repo.all().where((m) => m.privacyAgreed).length;
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
      if (x.id != m.id && x.number.replaceAll(RegExp(r'[^0-9]'), '') == n) {
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
