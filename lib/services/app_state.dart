import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async' show unawaited;

import '../models/member.dart';
import 'ai_query.dart';
import 'app_config.dart';
import 'donation_kinds.dart';
import 'finance_service.dart';
import 'league_names.dart';
import 'member_repository.dart';
import 'nas_api.dart';
import 'search_query.dart';
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

  // ---------- 소속(corps) ----------
  /// 로그인 소속 — 'tsak'(범스카우트, 기본) | 'eunha'(은하스카우트).
  /// 은하스카우트는 범스카우트와 **별도 관리**(통계·명단·로그인 분리)한다.
  String _corps = 'tsak';
  String get corps => _corps;

  /// 은하스카우트 세션 여부(개인 로그인 '은하#N').
  bool get isEunha => _corps == 'eunha';

  /// 로그인 전에 소속을 미리 지정한다(QR 딥링크 등).
  ///   [버그수정] 은하스카우트 QR이 같은 숫자의 범스카우트 회원으로 열리던
  ///   문제를 막기 위해, 딥링크가 소속을 알려 주면 세션 복원/로그인 전에
  ///   먼저 반영한다.
  void presetCorps(String corps) {
    final c = corps.trim().toLowerCase();
    _corps = (c == 'eunha') ? 'eunha' : 'tsak';
  }

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
      case 'supplies':
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

  // ---------- 홈 오버플로 메뉴 노출 설정 ----------
  /// 홈(⋮) 메뉴별 노출 설정. 메뉴 키 → { label, icon, master, admin }.
  Map<String, Map<String, dynamic>> _homeMenus = {};
  Map<String, Map<String, dynamic>> get homeMenus => _homeMenus;

  /// 서버 홈 메뉴 노출 설정 로드.
  Future<void> loadHomeMenus() async {
    if (!repo.isNasMode) return;
    try {
      final m = await nas.fetchHomeMenus();
      if (m.isNotEmpty) {
        _homeMenus = m;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 마스터가 홈 메뉴 노출 설정을 변경(서버 저장 후 로컬 반영).
  Future<bool> setHomeMenus(Map<String, Map<String, bool>> updates) async {
    if (!isMaster || !repo.isNasMode) return false;
    try {
      final m = await nas.setHomeMenus(updates);
      if (m.isNotEmpty) {
        _homeMenus = m;
        notifyListeners();
      }
      return m.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 홈 메뉴 노출 여부 — 홈 오버플로 메뉴가 이 항목을 표시해야 하는가?
  ///  · 마스터  → master 플래그가 켜진 항목만 표시.
  ///  · 관리자  → admin 플래그가 켜진 항목만 표시.
  ///  (배치 위치는 메뉴 구역(마스터/관리자)이 고정한다.)
  ///  설정 미수신 시 [fallback] 으로 기존 동작을 보존한다.
  bool canSeeMenu(String key, {bool fallback = true}) {
    final m = _homeMenus[key];
    if (m == null) return fallback;
    return isMaster ? m['master'] == true : m['admin'] == true;
  }

  // ---------- 자료 저장공간 (마스터) ----------
  Map<String, dynamic> _storage = {};
  Map<String, dynamic> get storage => _storage;
  String get storageActive => '${_storage['active'] ?? 'nas'}';
  Map<String, dynamic> get storageSpaces =>
      (_storage['spaces'] as Map?)?.cast<String, dynamic>() ?? {};

  Future<void> loadStorage() async {
    if (!repo.isNasMode) return;
    try {
      final r = await nas.fetchStorage();
      if (r['ok'] == true && r['storage'] is Map) {
        _storage = (r['storage'] as Map).cast<String, dynamic>();
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 저장공간 설정 저장(아이디/비번/폴더URL/라벨 등).
  Future<String?> saveStorage(Map<String, dynamic> payload) async {
    try {
      final r = await nas.saveStorage(payload);
      if (r['ok'] == true && r['storage'] is Map) {
        _storage = (r['storage'] as Map).cast<String, dynamic>();
        notifyListeners();
        return null;
      }
      return '${r['error'] ?? '실패'}';
    } catch (e) {
      return '$e';
    }
  }

  /// 저장공간 전환(자료 이관). 반환: 서버 응답(복사/보류/실패 통계 포함).
  Future<Map<String, dynamic>> migrateStorage(
    String target, {
    bool sweep = false,
    bool deleteOld = false,
  }) async {
    try {
      final r = await nas.migrateStorage(
        target,
        sweep: sweep,
        deleteOld: deleteOld,
      );
      if (r['ok'] == true && r['active'] != null) {
        _storage['active'] = r['active'];
        notifyListeners();
      }
      return r;
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  /// 이관 후 기존 저장공간 자료 삭제(선택).
  Future<int> purgeOldStorage([String which = 'nas']) async {
    try {
      final r = await nas.purgeOldStorage(which);
      return (r['deleted'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
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

  // ---------- [로딩 진행률] ----------
  /// 로딩 단계 진행률(0~100) — "정지된 것처럼 보임"을 막기 위해 % 를 노출한다.
  double _loadProgress = 0;
  double get loadProgress => _loadProgress;

  /// 현재 로딩 단계 설명(사용자 안내 문구).
  String _loadStage = '';
  String get loadStage => _loadStage;

  /// 진행률/단계를 갱신한다(0~100, 단조 증가).
  void _setLoadProgress(double p, String stage) {
    final v = p.clamp(0.0, 100.0);
    if (v < _loadProgress) return; // 역행 방지
    _loadProgress = v;
    _loadStage = stage;
    notifyListeners();
  }

  /// 로딩 시작 — 0% 로 초기화.
  void _beginLoad([String stage = '준비 중']) {
    _loadProgress = 0;
    _loadStage = stage;
  }

  /// 로딩 종료 — 100% 후 상태 초기화.
  void _endLoad() {
    _loadProgress = 100;
    _loadStage = '완료';
    notifyListeners();
  }

  /// AuthGate 최초 부팅 진행률 — 로딩 화면(스피너)에 % 를 표시하기 위한 값.
  double _bootProgress = 5;
  double get bootProgress => _bootProgress;
  String _bootStage = '앱을 준비하는 중…';
  String get bootStage => _bootStage;

  /// 부팅 진행률 갱신(_AuthGateState 에서 호출).
  void setBootProgress(double p, [String? stage]) {
    final v = p.clamp(0.0, 100.0);
    if (v < _bootProgress) return;
    _bootProgress = v;
    if (stage != null) _bootStage = stage;
    notifyListeners();
  }

  /// 개인정보 수정(개인 세션) 진입 시 **본인 1건만** 빠르게 조회한다.
  ///  (서버 ?self=1 → 응답 수 KB → 즉시 표시). 무거운 전체 명단 로딩을 피한다.
  Future<void> loadSelfOnly() async {
    if (!repo.isNasMode) return;
    try {
      await repo.syncFromNas(self: true);
    } catch (_) {}
    refresh();
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

  /// [self] true → 개인정보 수정(딥링크) 진입: 본인 1건만 받아 즉시 표시한다.
  ///  (개인 세션이 전 회원을 내려받아 웹이 멈추던 문제 방지)
  Future<void> restoreSession({bool self = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final ts = p.getInt(AppConfig.kSessionTs);
      final tier = p.getString(AppConfig.kAuthTier) ?? '';
      final who = p.getString(AppConfig.kAuthWho) ?? '';
      final corps = p.getString(AppConfig.kAuthCorps) ?? 'tsak';
      final sid = p.getString(AppConfig.kSessionSid) ?? '';
      if (ts != null && tier.isNotEmpty) {
        final start = DateTime.fromMillisecondsSinceEpoch(ts);
        if (DateTime.now().difference(start) < AppConfig.sessionTimeout) {
          // [보안] 저장된 세션토큰 복원 → 이후 API 요청이 인증된다.
          if (sid.isNotEmpty) {
            nas.sessionId = sid;
            // 저장된 앱 등급(_tier)은 '앱이 마지막으로 승격한 값'이지 **서버 세션
            // 등급이 아니다**. (개인 탭 415 로그인은 앱=master / 서버=personal)
            //  여기서 serverTier 를 낙관적으로 채우면 401 복구가 무력화되므로
            //  비워 두고, 실제 마스터 API 가 401 을 받으면 그때 재발급한다.
            nas.serverTier = '';
          } else if (repo.isNasMode) {
            // 토큰이 없으면 서버에서 재발급 시도(개인 QR 세션 등).
            try {
              final g = await nas.grantSession(tier, id: who);
              // grantSession 이 서버 응답의 tier 로 serverTier 를 채운다.
              if (!g) nas.serverTier = '';
            } catch (_) {}
          }
          _unlocked = true;
          _tier = tier;
          _who = who;
          _corps = (corps == 'eunha') ? 'eunha' : 'tsak';
          _sessionStart = start;
          _applyAccessScope();
          if (self) {
            // 개인정보 수정 딥링크: 무거운 전체 명단 로딩을 **아예 건너뛰고**
            //  **본인 1건**만 즉시 받아 화면을 연다(체감 즉시 로딩).
            _setMembersLoading(true);
            await loadSelfOnly();
            _setMembersLoading(false);
          } else if (repo.isNasMode) {
            // 세션 복원 시에도 최신 명단을 백그라운드로 재조회(로딩 문구 표시).
            _setMembersLoading(true);
            unawaited(_reloadAfterLogin());
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> login(
    String tier,
    String value, {
    String id = '',
    String corps = 'tsak',
  }) async {
    bool ok;
    // 로그인 소속(범스카우트/은하스카우트) — 별도 관리.
    //  · 명시 corps 우선. 단, ID 가 '은하N' 형식이면 항상 은하스카우트.
    //    (요구: id='은하43' → 은하 43호 방재호. 범 43호 전종찬과 명확히 구분)
    final idSaysEunha = id.contains('은하');
    _corps = (corps == 'eunha' || idSaysEunha) ? 'eunha' : 'tsak';
    // 개인 접근에서 입력된 인가번호 (ID 필드)
    String personalNo = '';
    // 아이디/암호 관리자 계정명 (app 로그인 및 통합 로그인 시 계정별 권한 적용용)
    String adminIdent = '';
    // 범스카우트 탭에서 관리자 계정으로 인증된 경우(통합 로그인) 표시.
    bool asAdmin = false;
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
      // 앱 접근: (1) 공용 관리자 ID "TSAK" + 앱 비밀번호, 또는
      //          (2) 마스터가 만든 아이디/암호 관리자 계정(예: task / tsak437).
      // 두 경우 모두 서버(/api/login)에 위임해 검증한다. 서버는 앱 공용
      // 비번과 아이디/암호 계정을 모두 처리한다.
      final idTrim = id.trim();
      final isShared = idTrim.toUpperCase() == 'TSAK';
      adminIdent = isShared ? '' : idTrim;
      ok = false;
      if (repo.isNasMode) {
        try {
          final r = await nas.login(
            'app',
            value,
            id: idTrim.isEmpty ? 'TSAK' : idTrim,
          );
          ok = r['ok'] == true;
        } catch (_) {}
      }
      // 서버 미연결/오프라인이면 공용 ID일 때만 로컬 상수로 폴백
      //  (아이디/암호 계정은 서버 없이는 검증 불가 → 통과시키지 않음).
      if (!ok && isShared) ok = value == AppConfig.appPassword;
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
      // 개인 접근: ID=인가번호(문자 허용), 비밀번호=개인비밀번호
      //  - ID(인가번호)로 번호를 확정하고, 비밀번호는 다음 중 하나로 인정:
      //    ① 번호 + !@@ (예: 415!@@)   ② 접미사만 (예: !@@)
      //    ③ 관리자가 지정한 개인 비밀번호 / 마스터 비밀번호
      //  (요구) ID는 숫자뿐 아니라 영문·한글·특수문자도 가능 → 먼저 ID 문자열로
      //         회원을 찾아 실제 인가번호로 정규화하고, 못 찾으면 숫자 추출 폴백.
      final idRaw = id.trim();
      Member? idMatched;
      if (idRaw.isNotEmpty) {
        idMatched = repo.byLoginId(idRaw) ?? repo.byNumber(idRaw);
      }
      personalNo = idMatched != null
          ? idMatched.number.replaceAll(RegExp(r'[^0-9]'), '')
          : idRaw.replaceAll(RegExp(r'[^0-9]'), '');
      if (personalNo.isEmpty) {
        personalNo = value.replaceAll(RegExp(r'[^0-9]'), '');
      }
      if (_corps == 'eunha') {
        // 은하스카우트 — 별도 규칙(서버 전용 검증). 범스카우트의 '{번호}!@@'
        //  로컬 규칙은 적용하지 않는다(규칙 비노출·교차 로그인 방지).
        ok = false;
        if (repo.isNasMode && (value.isNotEmpty || id.isNotEmpty)) {
          try {
            final r = await nas.login(
              'personal',
              value,
              id: id,
              corps: 'eunha',
            );
            if (r['ok'] == true) ok = true;
          } catch (_) {}
        }
        if (ok && nas.sessionId.isNotEmpty) {
          _grantedAdmin = false;
          _isSupporter = false;
        }
      } else {
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
        // ── [표준 ID 체계 확립 2026-10-26] ────────────────────────────────
        //
        // ## 무엇이 문제였나
        //  1) 아래 서버 폴백이 사용자가 넣지 않은 **'tiger' 접두어를 자동으로
        //     붙여**(`'tiger$personalNo'`) 시도했다. 그래서 사용자가 구(舊)
        //     체계인 `415 / 415!@@` 를 입력해도 내부적으로 `tiger415` 로 승격돼
        //     **통과**했다 → "ID 체계가 예전으로 돌아간" 것처럼 보였다.
        //  2) 위쪽 로컬 차단은 `value == expected` 일 때만 걸려서, 접두어 없는
        //     ID 로 커스텀 비번을 쓰는 경우까지는 막지 못했다.
        //
        // ## 확정 규칙
        //   · 인가자 표준 로그인 = **`tiger<인가번호>` + `{번호}!@@`**
        //     (예: tiger415 / 415!@@) — 이 조합만 정상 통과.
        //   · 접두어 없는 구(舊) ID(`415`)는 **어떤 경우에도 통과시키지 않는다**
        //     (자동 접두어 부착 금지).
        //   · 예외 2가지만 허용:
        //       ① 마스터 비밀번호 — 관리자 복구 경로(항상 유지)
        //       ② 관리자(마스터)가 지정한 **커스텀 개인비번** + `tiger` 접두어 ID
        //   · 은하스카우트는 위 `_corps == 'eunha'` 분기에서 서버 전용 규칙으로
        //     이미 처리되므로 이 규칙의 영향을 받지 않는다(번호 혼동 방지).
        final idLower = idRaw.toLowerCase();
        final idIsStandard = idLower.startsWith('tiger') && idLower.length > 5;
        final isMasterPw = value == AppConfig.masterPassword;
        final isDefaultPw = value == expected; // '{번호}!@@'
        final hasCustomPw = value.trim().isNotEmpty && !isDefaultPw;
        // 표준 ID 가 아니면(= 접두어 없음 또는 비어 있음) 기본 개인비번 로그인 금지.
        if (!isMasterPw && isDefaultPw && !idIsStandard) {
          ok = false;
        }
        // 서버 폴백 허용 조건 — 표준 ID 이거나 마스터 비번일 때만.
        final allowServerVerify = isMasterPw || idIsStandard || hasCustomPw;
        if (!ok && repo.isNasMode && personalNo.isNotEmpty && allowServerVerify) {
          // 서버로 보내는 ID 는 **사용자가 입력한 그대로**만 시도한다.
          //  ⚠️ 종전에는 'tiger$personalNo' 를 자동으로 덧붙여 시도했는데,
          //     그것이 구(舊) 체계 로그인을 되살리는 원인이었다. 절대 되살리지 말 것.
          //  · 표준 ID('tiger416')가 그대로 서버에 도착하면 서버가 접두어를
          //    정규화해 회원을 찾는다.
          final idTries = <String>{
            if (idIsStandard) idRaw,
          };
          outer:
          for (final tryId in idTries) {
            for (final c in candidates) {
              try {
                final r = await nas.login(
                  'personal',
                  c,
                  id: tryId,
                  corps: 'tsak',
                );
                if (r['ok'] == true) {
                  ok = true;
                  break outer;
                }
              } catch (_) {}
            }
          }
          // 표준 ID 로 서버 검증이 실패했고, **커스텀 개인비번**을 쓰는 경우에 한해
          //  서버가 개인비번을 직접 검증하도록 ID 를 그대로 넘겨 1회 더 시도한다.
          //  (접두어 없는 구 ID 로는 이 경로도 열리지 않는다 — 아래 조합 조건)
          if (!ok && idIsStandard && hasCustomPw) {
            try {
              final r = await nas.login(
                'personal',
                value,
                id: idRaw,
                corps: 'tsak',
              );
              if (r['ok'] == true) ok = true;
            } catch (_) {}
          }
        }
        // 서버 검증으로 성공한 경우엔 이미 세션이 발급됐고(관리자 부여 플래그),
        //  로컬 검증만 성공한 경우 세션을 별도로 확보한다(아래에서 처리).
        if (ok && repo.isNasMode && nas.sessionId.isNotEmpty) {
          _grantedAdmin = nas.lastLoginAdmin;
          _isSupporter = nas.lastLoginSupporter;
        }
        // (요구) 관리자 로그인 창을 없애고 범스카우트 인가자 ID칸 하나로 통합.
        //  아이디/암호 관리자 계정(예: task/tsak437)은 순수 숫자 인가번호가
        //  아니므로, 인가번호 규칙으로 실패하면 관리자 계정으로 재검증한다.
        if (!ok &&
            idRaw.isNotEmpty &&
            repo.isNasMode &&
            !RegExp(r'^\d+$').hasMatch(idRaw)) {
          try {
            final ar = await nas.login('app', value, id: idRaw);
            if (ar['ok'] == true) {
              ok = true;
              asAdmin = true;
              adminIdent = idRaw;
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
      // 범스카우트 탭에서 관리자 계정으로 인증된 경우 app 등급으로 승격.
      if (asAdmin) finalTier = 'app';
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
            corps: _corps,
            log: true,
          );
        }
      } catch (_) {}
    }
    // ── [버그 수정 2026-10-26] 앱 등급은 master 인데 서버 세션이 personal ──
    //  개인 탭에서 415(영구 마스터)로 로그인하면 서버는 personal 세션을
    //  발급한다. 앱은 로컬에서 master 로 승격하므로 화면은 마스터 기능을
    //  보여주는데, 서버는 계속 401(unauthorized)을 돌려줬다.
    //  → 대표 증상: '접속 비밀번호 관리' 카드에 **현재 비밀번호 조회 실패**,
    //    '회원 접속·열람 기록'이 비어 있음.
    //
    //  해결: 승격된 등급이 서버 세션 등급보다 높으면 **세션을 다시 발급**한다.
    //   · 최초 로그인에서 이미 받은 세션이면 재사용한다(personal → personal).
    //   · master 승격인데 서버가 personal 이면 마스터 비번으로 재발급.
    //  ⚠️ 세션 **복원(restoreSession)** 경로는 여기를 거치지 않는다(login() 밖).
    //    복원 시에는 자동 승격하지 않고, 실제 마스터 API 가 401 을 받을 때
    //    `ensureServerSession()` 이 그때서야 재발급한다 — 저장된 세션만으로
    //    조용히 권한이 올라가는 통로를 만들지 않기 위해서다.
    if (repo.isNasMode && nas.sessionId.isNotEmpty) {
      final bool needUpgrade =
          (finalTier == 'master' && !nas.serverIsMaster) ||
          (finalTier == 'app' &&
              (nas.serverTier == 'personal' || nas.serverTier.isEmpty));
      if (needUpgrade) {
        try {
          if (finalTier == 'master') {
            await nas.grantSession(
              'master',
              id: personalNo,
              master: AppConfig.masterPassword,
              log: false,
            );
          } else if (finalTier == 'app') {
            await nas.grantSession(
              'app',
              master: AppConfig.masterPassword,
              log: false,
            );
          }
        } catch (_) {}
      }
    }
      _unlocked = true;
      _tier = finalTier;
      // 영구 마스터는 본인 인가번호를 유지(내 QR·내 정보 기능 유지)
      //  · 관리자 계정(통합 로그인 포함)은 계정명을 who 로 두어 계정별 권한 적용.
      _who = (tier == 'personal' || tier == 'guest')
          ? (asAdmin ? adminIdent : personalNo)
          : (tier == 'app' && adminIdent.isNotEmpty ? adminIdent : '');
      _sessionStart = DateTime.now();
      _personalBrowse = false;
      _applyAccessScope();
      _persistSession();
      notifyListeners();
      // 역할별 메뉴권한표 로드(마스터가 설정한 값 반영).
      if (repo.isNasMode) unawaited(loadRolePermissions());
      // 홈 오버플로 메뉴 노출 설정 로드.
      if (repo.isNasMode) unawaited(loadHomeMenus());
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
    _beginLoad('데이터를 준비하는 중…');
    try {
      // 소속 분리 — 은하스카우트 세션은 이전(범스카우트) 캐시를 비워
      //  은하 명단만 남긴다(범스카우트 데이터 혼입 방지).
      if (_corps == 'eunha') {
        try {
          await repo.clearLocalCache();
        } catch (_) {}
      }
      // 개인 로그인 세션은 서버가 권한 범위(본인+이름·번호 축약)를 내려준다.
      _setLoadProgress(20, '명단을 불러오는 중…');
      await repo.syncFromNas();
      _membersLoaded = true;
      _setLoadProgress(75, '화면을 준비하는 중…');
    } catch (_) {}
    //  서버 동기화가 끝나면 먼저 명단을 화면에 반영(체감 로딩 단축).
    refresh();
    _setMembersLoading(false);
    _endLoad();
    try {
      await loadConfig();
    } catch (_) {}
    // 재무는 관리자·마스터만 서버 응답을 받는다(그 외 401).
    if (isApp || isMaster) {
      try {
        await finance?.load();
      } catch (_) {}
    }
    // 세션이 확실히 붙은 시점에 은하 명단도 함께 로드(콜드 스타트 401 방지).
    if ((isApp || isMaster) && _eunhaMembers.isEmpty) {
      unawaited(loadEunhaMembers());
    }
    // 서버 photos/ 파일이 있는데 photoPath 가 빈 회원(예: 1346)의 사진을 채운다.
    if (isApp || isMaster) {
      unawaited(syncPhotos());
    }
    refresh();
    notifyListeners();
  }

  Future<void> lock() async {
    _unlocked = false;
    _tier = '';
    _who = '';
    _corps = 'tsak';
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
    nas.serverTier = '';
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(AppConfig.kSessionTs);
      await p.remove(AppConfig.kAuthTier);
      await p.remove(AppConfig.kAuthWho);
      await p.remove(AppConfig.kAuthCorps);
      await p.remove(AppConfig.kSessionSid);
    } catch (_) {}
    notifyListeners();
  }

  /// QR 스캔 = 개인 로그인으로 간주 (비밀번호 없이).
  ///
  /// 개인 QR에는 인가번호가 담겨 있고, 그 QR 자체가 자격증명이다.
  /// 권한은 **기존 개인 로그인과 완전히 동일** (추가 권한 없음).
  /// → 본인 정보만 열람·수정 가능.
  ///
  /// **[버그수정]** [corps] 를 받는다. 은하스카우트 QR은 인가번호가 범스카우트와
  ///  숫자가 겹치므로(은하 43 ↔ 범 43), 소속을 함께 넘겨 은하 명단에서 찾아야
  ///  한다. 넘기지 않으면 은하 QR이 **범스카우트 회원**으로 열린다.
  Future<bool> qrPersonalLogin(String number, {String corps = 'tsak'}) async {
    final no = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (no.isEmpty) return false;
    final isEunha = corps.trim().toLowerCase() == 'eunha';

    // [보안] 서버에서 세션을 먼저 발급받는다 (QR 자체가 자격증명).
    //  · 세션 발급에 실패하면 다른 회원 정보가 노출되지 않도록 즉시 중단.
    //  · 개인 QR 이므로 항상 personal 등급(영구 마스터라 해도 승격하지 않음).
    //  · [접속기록] QR로 직접 들어온 경우도 접속기록에 포함되도록
    //    log:true 로 서버에 로그인 이력을 남긴다(비번 없이 세션만 받는 경우
    //    로그가 누락되던 문제 해결).
    var granted = false;
    if (repo.isNasMode) {
      try {
        granted = await nas.grantSession(
          'personal',
          id: isEunha ? '은하$no' : no,
          corps: isEunha ? 'eunha' : 'tsak',
          log: true,
          via: 'qr',
        );
      } catch (_) {}
      if (!granted) return false;
    }

    // [로딩 가속] 서버에서 **본인 1건만** 즉시 받는다(응답 수 KB → 즉시 표시).
    //  · 전체 명단(2233건)을 받으면 웹이 파싱으로 멈춘다.
    //  · 시드 폴백(우서하 등)이 아니라 **서버 실데이터**로 본인을 확정한다.
    if (granted) {
      try {
        await repo.syncFromNas(self: true);
      } catch (_) {}
    }

    // ── [표준 ID 체계·은하 혼동 방지 2026-10-26] ──────────────────────────
    //  QR 은 "개인정보 수정" 화면으로 **본인 1명**을 특정하는 자격증명이다.
    //  숫자만으로 명단을 넘나들면 엉뚱한 사람의 개인정보가 열린다.
    //
    //  ① 범스카우트 QR(`?access=personal&no=43`)이 은하 명단까지 뒤지지 않게 한다.
    //     종전: `repo.byNumber(no) ?? _eunhaByNumber(no)` — 범 명단에 없으면
    //     **은하 43호**가 열렸다(범 43 ↔ 은하 43 숫자 충돌).
    //     이제: 범 QR 은 범 명단 **안에서만** 찾는다.
    //  ② 소속 파라미터가 없던 시절의 구 QR 로도 은하 회원이 열리지 않게,
    //     결과 회원의 소속이 요청 소속과 **일치할 때만** 통과시킨다.
    //  ③ 은하 세션에 영구 마스터(master) 등급을 승격하지 않는다.
    //     (범스카우트 마스터 번호가 은하 번호와 겹칠 수 있다)
    final m = isEunha ? _eunhaByNumber(no) : repo.byNumber(no);
    if (m == null) return false;
    final memberCorps = (m.corps == 'eunha') ? 'eunha' : 'tsak';
    if (memberCorps != (isEunha ? 'eunha' : 'tsak')) return false;

    _unlocked = true;
    _tier = (!isEunha && AppConfig.isPermanentMaster(no))
        ? 'master'
        : 'personal';
    _corps = memberCorps;
    _who = no;
    _sessionStart = DateTime.now();
    _membersLoaded = true;
    _applyAccessScope();
    _persistSession();
    refresh();
    notifyListeners();
    selfOnlyRefresh();
    return true;
  }

  /// 본인 1건만 서버에서 다시 받아 목록에 반영(은하 QR 복구용).
  void selfOnlyRefresh() {
    if (!repo.isNasMode) return;
    unawaited(
      repo.syncFromNas(self: true).then((_) {
        // 세션 corp 가 은하이면 은하 명단도 함께 갱신 시도.
        if (_corps == 'eunha') unawaited(loadEunhaMembers());
        refresh();
        notifyListeners();
      }),
    );
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
      await p.setString(AppConfig.kAuthCorps, _corps);
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
  /// 별도 지정이 없을 때 **관리자·마스터에게 기본 노출**되는 항목.
  ///  요구: "스카우트등록번호(스카우트 고유번호)는 관리자가 볼 수 있도록".
  ///  → 전역/개인 설정이 전혀 없으면 '관리자 노출(admin)'로 판정한다.
  static const Set<String> adminDefaultFields = {'scoutNo'};

  String permFor(Member m, String key) {
    final v = m.fieldPerms[key];
    if (v == permPublic) return permPublic;
    if (v == permAdmin) return permAdmin;
    if (v == permHidden) return permHidden;
    // 전역 항목노출 설정이 명시돼 있으면 그 값을 최우선으로 따른다.
    final fv = _config['fieldVisibility'];
    if (fv is Map && fv.containsKey(key)) {
      return fieldVisible(key) ? permPublic : permHidden;
    }
    // 아무 지정도 없을 때: 관리자 기본노출 항목은 관리자 노출로.
    if (adminDefaultFields.contains(key)) return permAdmin;
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
  ///
  /// **[버그수정] 은하스카우트 QR이 범스카우트 인가번호로 열리던 문제**
  ///  은하스카우트 인가번호(1~165)는 범스카우트 인가번호와 **같은 숫자**를 쓴다.
  ///  종전에는 QR에 숫자만 담아서, 스캔/딥링크 시 서버·앱이 그 번호를
  ///  무조건 **범스카우트**로 해석했다(예: 은하 43호 → 범 43호 전종찬?).
  ///  → 소속을 `corps=eunha` 로 함께 담고, 소비 측(딥링크·스캔·세션발급)이
  ///    그 값을 우선 사용하도록 바꾼다. 범스카우트는 기존과 동일(파라미터 없음).
  String personalQrLink(String number, {String corps = 'tsak'}) {
    final base = qrBaseUrl;
    final c = corps.trim().toLowerCase();
    final corpsParam = (c == 'eunha') ? '&corps=eunha' : '';
    final q = '/?access=personal&no=${Uri.encodeComponent(number)}$corpsParam';
    return base.isEmpty ? q : '$base$q';
  }

  /// 인가번호 + 소속으로 딥링크를 만든다(호출부 편의).
  String personalQrLinkOf(Member m) => personalQrLink(m.number, corps: m.corps);

  /// 행사 QR 딥링크 (절대 URL).
  /// 전용 경량 착지 페이지(/qr.html)로 연결한다 — 앱(5MB) 로딩 없이 즉시 뜬다.
  ///
  /// (요구) 행사별 QR은 **두 종류**다. 이 함수는 그중 **참가 신청**용이다.
  ///  ① 참가 신청 → `/qr.html`  (가벼운 신청/등록 페이지, [eventApplyQrLink])
  ///  ② 행사 게시판 → `/?access=event` (앱을 열어 행사 상세로 직행,
  ///     [eventBoardQrLink])
  String eventQrLink(String year, String title) {
    final base = qrBaseUrl;
    final q =
        '/qr.html'
        '?year=${Uri.encodeComponent(year)}'
        '&title=${Uri.encodeComponent(title)}';
    return base.isEmpty ? q : '$base$q';
  }

  /// ① **행사 참가 신청** QR — 경량 착지 페이지(`/qr.html`).
  ///
  /// 스캔하면 앱(수 MB)을 받지 않고 바로 신청 화면이 뜬다. 비회원·외부인이
  /// 행사 참가를 신청할 때 쓰는 QR이다.
  String eventApplyQrLink(String year, String title) => eventQrLink(year, title);

  /// ② **행사 게시판** QR — 앱을 열어 그 행사의 상세 화면으로 직행한다.
  ///
  /// `/?access=event&year=…&title=…` 딥링크는 [main.dart] 의 `_readDeepLink`
  /// → `HomeScreen.openEventYear/openEventTitle` → `EventDetailScreen` 으로
  /// 이미 연결돼 있다. 로그인한 회원이 행사 자료·사진·후기 게시판을 바로
  /// 여는 QR이다.
  String eventBoardQrLink(String year, String title) {
    final base = qrBaseUrl;
    final q =
        '/?access=event'
        '&year=${Uri.encodeComponent(year)}'
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

  // ---------- 후원 안내 편집 (마스터) ----------
  /// 후원계좌 목록을 서버에 저장하고 로컬 설정에 반영한다.
  Future<bool> saveDonationAccounts({
    required String action,
    List<Map<String, dynamic>>? donations,
    Map<String, dynamic>? account,
    int? index,
    String? holder,
  }) async {
    if (!repo.isNasMode) return false;
    try {
      final r = await nas.saveDonationAccounts(
        action: action,
        donations: donations,
        account: account,
        index: index,
        holder: holder,
      );
      if (r['ok'] != true) return false;
      final next = Map<String, dynamic>.from(_config);
      if (r['donations'] is List) {
        next['donations'] = (r['donations'] as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
      }
      if (r.containsKey('donationHolder')) {
        next['donationHolder'] = r['donationHolder'];
      }
      _config = next;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- 아이디/암호 관리자 계정 (마스터) ----------
  /// 관리자 계정 목록 조회. 반환: [{username,password,note,created}]
  Future<List<Map<String, dynamic>>> fetchAdminAccounts() async {
    if (!repo.isNasMode) return [];
    try {
      final r = await nas.fetchAdminAccounts();
      final list = r['accounts'];
      if (list is List) {
        return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 관리자 계정 생성/수정/삭제. 성공 시 null, 실패 시 오류 메시지 반환.
  Future<String?> saveAdminAccount({
    required String action,
    required String username,
    String? password,
    String? note,
  }) async {
    if (!repo.isNasMode) return 'NAS 모드가 아닙니다';
    try {
      final r = await nas.saveAdminAccount(
        action: action,
        username: username,
        password: password,
        note: note,
      );
      if (r['ok'] == true) return null;
      return '${r['error'] ?? '실패'}';
    } catch (e) {
      return '$e';
    }
  }

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

  /// 마지막 [fetchMemberPassword] 실패 사유.
  ///  ── 화면이 "조회 실패"만 띄우면 사용자가 원인을 알 수 없다(요구 2026-10-26).
  String _lastPasswordError = '';
  String get lastPasswordError => _lastPasswordError;

  /// 접속 비밀번호 현재값 조회 (마스터 전용).
  /// 반환: {'password','defaultPassword','isDefault','isRegular'} 또는 null.
  ///
  /// ── [버그 수정 2026-10-26] "마스터권한으로 접속시 패스워드 조회가 안됨" ──
  ///  증상: 개인 탭에서 415(영구 마스터) 로 로그인한 뒤 회원 편집 화면의
  ///        '접속 비밀번호 관리' 카드에 **현재 비밀번호 조회 실패**가 떴다.
  ///
  ///  원인(서버 로그로 확정):
  ///   ① 개인 탭 로그인(tier=personal)은 서버 세션도 `personal` 로 발급된다.
  ///      앱은 로컬에서 `_tier='master'` 로 승격하지만 **서버 세션은 personal**.
  ///   ② `/api/member/password` 는 `_require("master")` → 세션 tier 가
  ///      personal 이면 **401 unauthorized**.
  ///   ③ nas.memberPassword 가 401 을 예외로 올리지 않고 응답을 그대로 파싱해
  ///      `ok:false` → 여기서 null 반환 → 화면 "조회 실패".
  ///      (게다가 `catch (_) {}` 로 사유까지 삼켰다.)
  ///   → 같은 이유로 '회원 접속·열람 기록'(/api/member/access-log)도 401.
  ///
  ///  해결: 호출 전에 **서버 세션을 마스터 등급으로 재확인**하고(ensureServerSession),
  ///        그래도 401 이면 1회 재시도, 최종 실패는 **사유를 남긴다**.
  Future<Map<String, dynamic>?> fetchMemberPassword(String number) async {
    _lastPasswordError = '';
    if (!repo.isNasMode) {
      _lastPasswordError = '로컬 모드에서는 비밀번호를 조회할 수 없습니다';
      return null;
    }
    if (!isMaster) {
      _lastPasswordError = '마스터만 비밀번호를 열람할 수 있습니다';
      return null;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await nas.memberPassword(number);
        if (r['ok'] == true) return r;
        _lastPasswordError = '${r['error'] ?? '알 수 없는 오류'}';
      } on NasAuthException catch (e) {
        // 세션이 personal 등급이면 여기로 온다 → 마스터 세션으로 재발급 후 재시도.
        _lastPasswordError = '$e';
        if (attempt == 0) {
          final renewed = await ensureServerSession(needAdmin: true);
          if (renewed) continue;
          _lastPasswordError = '서버 세션을 마스터 등급으로 갱신하지 못했습니다';
        }
      } catch (e) {
        _lastPasswordError = '서버에 연결하지 못했습니다: $e';
      }
      if (attempt == 0) break;
    }
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
  ///  ── [버그 수정 2026-10-26] 위 fetchMemberPassword 와 **같은 원인**으로
  ///    개인 탭 마스터 로그인 시 기록이 비어 보였다(401 → catch(_) → []).
  Future<List<Map<String, dynamic>>> fetchMemberAccessLog(String number) async {
    if (!repo.isNasMode || !isMaster) return [];
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await nas.memberAccessLog(number);
      } on NasAuthException {
        if (attempt == 0) {
          final renewed = await ensureServerSession(needAdmin: true);
          if (renewed) continue;
        }
        return [];
      } catch (_) {
        return [];
      }
    }
    return [];
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
  ///  · [ident] 미지정 시 로그인 세션(who)을 사용한다. 관리자·마스터가 다른
  ///    회원 대신 요청할 때는 대상 인가번호를 넘긴다.
  ///  · 평생회비·연회비 등록요청은 [payer]·[timing]·[payerIsSelf]를 함께 보낸다.
  Future<String?> submitMemberRequest({
    required String type,
    String ident = '',
    String year = '',
    String date = '',
    String note = '',
    String newNumber = '',
    String event = '',
    String payer = '',
    String timing = '',
    bool payerIsSelf = false,
  }) async {
    if (!repo.isNasMode) return '서버 연결이 필요합니다';
    try {
      final r = await nas.memberRequestSubmit(
        type: type,
        ident: ident.trim().isNotEmpty ? ident.trim() : who,
        year: year,
        date: date,
        note: note,
        newNumber: newNumber,
        event: event,
        payer: payer,
        timing: timing,
        payerIsSelf: payerIsSelf,
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
            'reject': 'rejected',
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

  /// 마스터에게 위임 / 위임 취소(관리자·마스터).
  ///  source: 'regular' | 'request' | 'link', action: 'delegate' | 'cancel'.
  ///  위임된 항목은 마스터만 선택·처리할 수 있다(서버가 강제).
  Future<bool> delegateApproval({
    required String source,
    required String ident,
    String action = 'delegate',
  }) async {
    if (!repo.isNasMode || !(isApp || isMaster) || ident.trim().isEmpty) {
      return false;
    }
    try {
      final r = await nas.approvalDelegate(
        source: source,
        ident: ident,
        action: action,
      );
      return r['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// [요구] 정보 수정요청 메모 전송 — 비인가회원(본인)이 관리자·마스터에게
  ///  정보 수정을 요청한다. 성공 시 통합승인 '정보 수정요청' 큐에 반영된다.
  Future<bool> sendLinkFixNote({
    String ident = '',
    required String note,
    String scope = '',
  }) async {
    if (!repo.isNasMode || note.trim().isEmpty) return false;
    try {
      final r = await nas.linkNote(ident: ident, note: note, scope: scope);
      return r['ok'] == true;
    } catch (_) {
      return false;
    }
  }

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
  ///
  /// ── [버그 수정 2026-10-26] 성공으로 표시됐지만 실제로는 안 바뀌던 문제 ──
  ///  서버가 `ok:false`(예: 현재 비번 불일치 401)를 돌려줘도 화면에는
  ///  '변경되었습니다' 가 떴다. → 응답의 `ok` 를 반드시 확인하고,
  ///  실패 사유를 그대로 사용자에게 전달한다.
  Future<String?> changePersonalPassword(String current, String newPw) async {
    if (who.isEmpty) return '본인 인가번호를 확인할 수 없습니다';
    try {
      final r = await nas.changePersonalPassword(who, current, newPw);
      if (r['ok'] == true) return null;
      final why = '${r['error'] ?? '실패'}';
      if (why.contains('현재 비밀번호')) {
        return '현재 비밀번호가 올바르지 않습니다';
      }
      return why;
    } on NasAuthException catch (e) {
      return '$e';
    } catch (e) {
      return '서버에 연결하지 못했습니다: $e';
    }
  }

  /// 비밀번호 초기화 요청 (본인) — 분실 시 관리자·마스터에게 초기화 요청.
  /// 요구: "비밀번호 분실 변경시 관리자나 마스터에게 초기화 요청하십시요."
  Future<String?> requestPasswordReset() async {
    if (who.isEmpty) return '본인 인가번호를 확인할 수 없습니다';
    try {
      final r = await nas.requestPasswordReset(who);
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

  // ---------- 은하스카우트 별도 명단 ----------
  /// 은하스카우트 명단(별도 관리) — 관리자·마스터 전용 조회 캐시.
  List<Member> _eunhaMembers = [];
  List<Member> get eunhaMembers => List.unmodifiable(_eunhaMembers);
  bool _eunhaLoading = false;
  bool get eunhaLoading => _eunhaLoading;
  int get eunhaTotal => _eunhaMembers.length;

  /// 은하스카우트 명단을 서버에서 불러온다(관리자·마스터 전용).
  ///
  /// [원인 진단] 종전에는 오류를 조용히 삼키고 빈 목록([])으로 고정했다.
  ///  · 앱 시작 시 `restoreSession()` 이 세션토큰(nas.sessionId)을 복원하기
  ///    *전에* 홈 화면의 `ensureEunhaForSearch()` 가 먼저 실행되면,
  ///    인증헤더가 비어 있는 채로 요청이 나가 **401** 이 되고,그 결과가
  ///    `catch (_) { _eunhaMembers = []; }` 로 굳어 '은하 0명'이 되었다.
  ///
  /// [자동 복구] 세션을 최대 [waitSec] 초까지 대기한 뒤 요청하고, 실패하면
  ///  몇 차례 재시도한다. 실패 시에는 캐시를 **비워** 이후 호출에서 재시도되게
  ///  한다(=0으로 고정하지 않는다).
  Future<void> loadEunhaMembers({int retries = 3, int waitSec = 12}) async {
    if (!repo.isNasMode || !(isApp || isMaster)) return;
    _eunhaLoading = true;
    notifyListeners();
    List<Member>? loaded;
    for (var i = 0; i < retries && loaded == null; i++) {
      try {
        // 세션토큰이 복원될 때까지 잠깐 대기(콜드 스타트 경쟁 방지).
        if (nas.sessionId.trim().isEmpty) {
          await _waitForSession(waitSec);
        }
        loaded = await nas.fetchEunhaMembers();
      } catch (_) {
        loaded = null;
      }
      if (loaded == null && i < retries - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }
    if (loaded != null) {
      _eunhaMembers = loaded;
    } else {
      // 실패 → 0으로 고정하지 않는다(캐시 비움 = 다음 호출에서 자동 재시도).
      _eunhaMembers = [];
    }
    _eunhaLoading = false;
    // 은하(느린 네트워크) 로드 후 조건이 걸려 있으면 목록에 반영한다.
    if (_corpsFilter == 'eunha') refresh();
    notifyListeners();
  }

  /// 세션토큰이 채워질 때까지(최대 [secs] 초) 폴링 대기한다.
  ///  restoreSession()/login() 이 진행 중일 때 401 로 굳는 것을 방지.
  Future<void> _waitForSession(int secs) async {
    for (var i = 0; i < secs * 4; i++) {
      if (nas.sessionId.trim().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// **화면 권한등급과 서버 세션등급의 불일치를 바로잡는다.**
  ///
  /// ## 왜 필요한가 (버그 수정 2026-10-25)
  /// 사용자가 개인 인가번호(`tiger415` + `415!@@`)로 로그인하면, 앱은 그 사람이
  /// 영구 마스터이거나 관리자 지정을 받은 경우 `isApp`/`isMaster` 를 true 로
  /// 만들어 **관리 화면을 모두 열어 준다**. 그런데 그때 발급된 서버 세션은
  /// `tier='personal'` 이다.
  ///
  /// 서버의 `_require("admin")` 는 personal 을 거부했기 때문에, 행사 상세에서
  /// **참가자(6명)는 정상으로 보이는데 재무 4개 탭(참가비·후원금 / 후원 /
  /// 지출 / 결산)만 전부 0건**이 되는 기묘한 증상이 생겼다(참가자는
  /// `_require()` = 세션 존재만 요구). 새로 입력한 값도 401 로 사라졌다.
  ///
  /// 이 함수는 "관리 권한이 필요한 요청이 인증오류로 실패했을 때" 호출되어
  /// **지금 화면이 요구하는 등급으로 세션을 다시 발급**받는다.
  /// (서버 쪽 `_auth_ok` 도 personal 을 허용하도록 함께 고쳤으므로 이중 안전망)
  ///
  /// 반환: 세션이 (재)발급되면 true.
  Future<bool> ensureServerSession({bool needAdmin = false}) async {
    if (!repo.isNasMode) return false;
    if (needAdmin && !(isApp || isMaster)) return false;
    try {
      if (isMaster) {
        // 이미 마스터 세션이면 서버를 다시 부르지 않는다(불필요한 왕복·세션 churn 방지).
        if (nas.serverIsMaster) return true;
        final ok = await nas.grantSession(
          'master',
          id: _who,
          // 영구 마스터(PM:번호)든 일반 마스터 비번이든 서버가 판정한다.
          master: AppConfig.masterPassword,
          corps: _corps,
          log: false,
        );
        if (ok) await _persistSession();
        return ok;
      }
      if (isApp) {
        final ok = await nas.grantSession(
          'app',
          id: _who,
          app: AppConfig.appPassword,
          corps: _corps,
          log: false,
        );
        if (ok) await _persistSession();
        return ok;
      }
    } catch (_) {}
    return false;
  }

  /// 소속 필터: '' (전체 = 범+은하) | 'tsak' (범스카우트) | 'eunha' (은하스카우트).
  ///   요구: "은하 스카우트도 명단검색되도록 하고 아래와 유사하게 말머리(소속 배지)를
  ///         만들어 노출할 것 / 상부노출 수정: 전체·범인가자수·검색결과"
  String _corpsFilter = '';
  String get corpsFilter => _corpsFilter;

  /// 관리자·마스터이고 은하 명단을 아직 불러오지 않았으면 로드(검색 통합용).
  void ensureEunhaForSearch() {
    if ((isApp || isMaster) && _eunhaMembers.isEmpty && !_eunhaLoading) {
      unawaited(loadEunhaMembers());
    }
  }

  /// 은하 명단이 비어 있으면 다시 불러온다(은하 화면 진입·새로고침용).
  void reloadEunhaMembers() {
    if (isApp || isMaster) unawaited(loadEunhaMembers());
  }

  // ---------- 사진 복원 (서버 photos/ 파일 → photoPath 폴백) ----------
  /// 서버(photos/ 폴더)에 실제 파일이 있는 인가번호 집합.
  ///
  /// [원인 진단] 1346 양다솜처럼 DB 의 `photoPath` 가 빈 값인데도 NAS
  ///  `photos/<번호>.jpg` 파일은 존재하는 경우가 있다. 앱은 photoPath 만 보고
  ///  그리므로 사진이 안 뜬다. 서버에 파일이 있으면 `/api/photo/<번호>` 로
  ///  불러오게 하기 위해 보유 목록을 미리 받아 둔다.
  Set<String> _photoHave = <String>{};
  Set<String> get photoHave => _photoHave;
  bool _photoHaveLoaded = false;
  bool get photoHaveLoaded => _photoHaveLoaded;
  bool _photoSyncStarted = false;

  /// 서버 사진 보유 목록을 불러온다(관리자·마스터). 위젯이
  /// [serverPhotoUrlFor] 로 photoPath 가 빈 회원의 사진을 찾아 표시한다.
  Future<void> syncPhotos({bool force = false}) async {
    if (!repo.isNasMode || !(isApp || isMaster)) return;
    if (_photoHaveLoaded && !force) return;
    try {
      if (nas.sessionId.trim().isEmpty) await _waitForSession(12);
      final have = await nas.fetchPhotoHave();
      if (have.isEmpty && !force) return;
      _photoHaveLoaded = true;
      _photoHave = have.keys.toSet();
      // 서버 사진 유무가 화면에 반영되도록 목록을 다시 그린다.
      refresh();
      notifyListeners();
    } catch (_) {}
  }

  /// 사진이 비어 있지만 서버에 파일이 있으면 즉시 URL 을 돌려준다(위젯 폴백용).
  ///  syncPhotos() 를 기다리지 않고도 화면에서 바로 사진을 찾을 수 있게 한다.
  ///
  /// ── [버그 수정 2026-10-26] 은하 사진에 범 사진이 뜨던 문제(앱 쪽 원인) ────
  ///  요구(원문): "은하스카우트 사진에 범스카우트 동일인가번호의 사진이
  ///              표시되고 있음"
  ///
  ///  ## 종전 코드 (문제)
  ///    final n = number.replaceAll(RegExp(r'[^0-9]'), '');
  ///  은하 번호 'G43' 이 **'43'** 으로 깎여, 보유목록에서 '43'(범 43호)을
  ///  찾아 `/api/photo/43` 을 요청했다 → **범 43호 사진**이 표시됐다.
  ///  서버를 고쳐도 앱이 이렇게 깎으면 그대로 재현되므로 반드시 함께 고쳐야 한다.
  ///
  ///  ## 수정
  ///   은하 접두어(G)를 **보존**해 키를 만든다.
  ///     범 43호  → '43'  → `/api/photo/43`
  ///     은하 43호 → 'G43' → `/api/photo/G43`
  ///   접두어 표기 변형('g43','은하43','갤럭시43')도 모두 'G43' 으로 통일한다.
  String? serverPhotoUrlFor(String number) {
    // 아직 보유목록을 안 받았고 로그인 상태면, 화면 프레임 이후 1회 지연 로드.
    //  (빌드 중 notifyListeners 를 피하려 Future 로 미룬다.)
    if (!_photoHaveLoaded && !_photoSyncStarted && (isApp || isMaster)) {
      _photoSyncStarted = true;
      Future<void>(() => syncPhotos());
    }
    final n = eunhaAwareKey(number);
    if (n.isEmpty) return null;
    if (_photoHave.isNotEmpty && _photoHave.contains(n)) {
      return nas.photoUrl(n);
    }
    return null;
  }

  /// ── [번호체계 2026-10-26] 은하 G접두어를 보존하는 번호 정규화 ──────────
  ///  서버의 `_ck()` 와 **반드시 같은 규칙**이어야 한다(앱↔서버 키 불일치 =
  ///  사진·개인카드가 서로 다른 사람을 가리키는 사고).
  ///    'G43' / 'g43' / 'G-43' / '은하43' / '갤럭시43' / 'galaxy43' → 'G43'
  ///    '43' / 'tiger43'                                          → '43'
  static String eunhaAwareKey(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final low = s.toLowerCase();
    var isEunha = low.startsWith('g') && low.length > 1;
    if (!isEunha) {
      for (final mk in const ['은하', '갤럭시', 'galaxy', 'eunha']) {
        if (low.contains(mk)) {
          isEunha = true;
          break;
        }
      }
    }
    final d = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return '';
    return isEunha ? 'G$d' : d;
  }

  void setCorpsFilter(String v) {
    _corpsFilter = (v == 'eunha' || v == 'tsak') ? v : '';
    if (_corpsFilter == 'eunha') ensureEunhaForSearch();
    refresh();
  }

  /// 전역 검색 기준 목록 — 소속 필터에 따라 범/은하/전체를 합친다.
  ///  은하는 개인 로그인(소속 eunha) 세션에서는 repo 캐시가 곧 은하 명단이다.
  List<Member> _searchBase() {
    final base = repo.all();
    List<Member> eunha;
    if (_corps == 'eunha') {
      eunha = base.where((m) => m.corps == 'eunha').toList();
      if (eunha.isEmpty) eunha = base;
      return _corpsFilter == 'tsak' ? const [] : eunha;
    }
    eunha = _eunhaMembers;
    switch (_corpsFilter) {
      case 'eunha':
        return eunha;
      case 'tsak':
        return base.where((m) => m.corps != 'eunha').toList();
      default:
        // 전체 — 범(in-memory) + 은하(별도 명단)를 합친다.
        final seen = base.map((m) => m.id).toSet();
        final merged = [...base];
        for (final e in eunha) {
          if (seen.add(e.id)) merged.add(e);
        }
        return merged;
    }
  }

  /// 은하 포함 전역 **전체** 회원수 — 상부 '전체' 노출용(소속 필터 반영).
  int get totalSearchCount {
    if (_corps == 'eunha') return repo.all().length;
    switch (_corpsFilter) {
      case 'eunha':
        return _eunhaMembers.length;
      case 'tsak':
        return repo.all().where((m) => m.corps != 'eunha').length;
      default:
        return repo.all().length + _eunhaMembers.length;
    }
  }

  /// 은하 포함 전역 **인가자**(비일반회원) 수 — (소속 필터 반영, 보조용).
  int get credentialSearchCount {
    if (_corps == 'eunha') {
      return repo.all().where((m) => !m.isRegular).length;
    }
    switch (_corpsFilter) {
      case 'eunha':
        return _eunhaMembers.where((m) => !m.isRegular).length;
      case 'tsak':
        return repo
            .all()
            .where((m) => m.corps != 'eunha' && !m.isRegular)
            .length;
      default:
        return repo.all().where((m) => !m.isRegular).length +
            _eunhaMembers.where((m) => !m.isRegular).length;
    }
  }

  /// 상부노출 **'범인가자수'** — 범스카우트 인가자(비일반회원) 수.
  ///   (은하스카우트는 별도 · 소속 필터와 무관한 고정 참조값)
  int get tsakCredentialCount =>
      repo.all().where((m) => m.corps != 'eunha' && !m.isRegular).length;

  int get corpsFilterTsakCount =>
      repo.all().where((m) => m.corps != 'eunha').length;
  int get corpsFilterEunhaCount =>
      (_corps == 'eunha') ? repo.all().length : _eunhaMembers.length;

  /// 아타스(ATAS) 인가번호 보유자 수 — 현재 검색 기준 목록(range)에서 센다.
  int get atasCount => _searchBase().where((m) => m.hasAtas).length;

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
  ///                    | 'mentor' (멘토) | 'mentee' (멘티) | 'parent' (보호자 지정)
  ///                    | 'atas' (아타스 = ATAS 인가번호 보유자)
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
  int get lifetimeCount => _searchBase().where((m) => m.lifetimeMember).length;
  Map<String, int> get feeCountMap => {
    for (final e in repo.feeCountsByYear()) e.key: e.value,
  };

  void _onRepoChanged() {
    refresh();
  }

  void refresh() {
    _members = _applyFilters(_searchBase());
    notifyListeners();
  }

  /// 목록 필터(연맹·연도·평생·구분·검색)를 순수 함수로 적용 — 범/은하 공용.
  List<Member> _applyFilters(List<Member> input) {
    var list = input;
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
        // 멘토 = 멘티대원을 둔(지도하는) 회원.
        list = list.where((m) => m.mentees.isNotEmpty).toList();
        break;
      case 'mentee':
        // 멘티 = 멘토를 가진(지도받는) 회원.
        list = list.where((m) => m.mentors.isNotEmpty).toList();
        break;
      case 'parent':
        list = list.where((m) => m.parents.isNotEmpty).toList();
        break;
      case 'atas':
        // 아타스 = ATAS 인가번호를 보유한 대원.
        list = list.where((m) => m.hasAtas).toList();
        break;
    }
    if (_query.trim().isNotEmpty) {
      list = _applyQuery(list, _query.trim());
    }
    return list;
  }

  /// 검색 질의 적용 —
  ///   ① 인가번호 **표기 해석**(범415 · 은하19호 · G19)
  ///   ② AI 자연어(복합 의도: "... 명단", "...납부자" 등)
  ///   ③ 범위 검색(1-100)
  ///   ④ 하이픈 무관 전화 / 일반 통합검색
  ///
  /// ## [2026-11-02 build #579] 표기 해석 계층 추가
  ///   요구(원문): "검색기능: 범스카우 번호, 예를들면 범415 로 검색해도 검색결과가
  ///               안나옴, 은하19호 같이 검색해도 은하스카우트가 안 나옴"
  ///
  ///   종전 ④ 는 `m.searchText.contains(p)` **부분 문자열** 비교였다.
  ///   `searchText` 에는 `'415'` 와 `'범'` 이 따로 있어 `'범415'` 라는 연속
  ///   문자열이 존재하지 않는다 → 구조적으로 절대 매칭될 수 없었다.
  ///   그래서 문자열 비교 **앞에** 의미 해석([SearchQuery]) 을 둔다.
  List<Member> _applyQuery(List<Member> list, String rawQuery) {
    // 1) 인가번호 표기 해석 — '범415' / '은하19호' / 'G19' / '은하'
    //    소속이 지목되면 그 소속의 **해당 번호**만 남긴다.
    //    (은하 19호 ≠ 범 19호 — 번호만 같고 사람이 다르다.)
    final sq = SearchQuery.parse(rawQuery);
    if (sq.isNotation &&
        (sq.hasCorps || SearchQuery.hasNumberNotation(rawQuery))) {
      var hit = list
          .where(
            (m) =>
                SearchQuery.corpsMatches(sq.corps, m.corps) &&
                (sq.number == null || m.numberInt == sq.number),
          )
          .toList();
      // 나머지 키워드(예: '은하 영남')가 있으면 그 안에서 한 번 더 좁힌다.
      //  좁힌 결과가 0건이면 **정직하게 0건**을 돌려준다(소속 지목은 지켜야 하므로
      //  '은하 이승' 이 범 '이승준' 으로 새면 안 된다).
      if (sq.tokens.isNotEmpty) {
        hit = hit
            .where((m) => sq.tokens.every((t) => m.searchText.contains(t)))
            .toList();
      }
      // 번호까지 지목됐는데 0건이면 아래 일반 검색으로 흘려보내지 않는다.
      // (예: 아직 은하 명단을 못 불러온 상태에서 '은하19호' → 0건이 정직하다.
      //  '415' 같은 맨숫자는 이 분기에 오지 않으므로 영향 없음.)
      if (sq.number != null || hit.isNotEmpty) return hit;
    }

    // 2) AI 자연어 검색 (복합 의도: "... 명단", "...납부자" 등)
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
    // ATAS 검색 신호 — 'atas' / '아타스' 를 포함하면 ATAS 보유자까지 후보로 넓힌다.
    final qAtas = q.contains('atas') || q.contains('아타스');

    return list.where((m) {
      // 모든 토큰이 통합 텍스트에 포함되어야 함
      if (parts.every((p) => m.searchText.contains(p))) return true;
      // 하이픈을 제거한 숫자열이 전화번호에 포함되면 매칭 (예: 01012345678)
      if (qLooksLikePhone && m.phoneDigits.contains(qDigits)) return true;
      // 행사명(참석한 행사)으로 검색 — 행사 참가자 명단
      if (m.eventAttend.keys.any((e) => e.toLowerCase().contains(q))) {
        return true;
      }
      // ATAS 키워드 검색 — 'atas'/'아타스' 를 치면 ATAS 인가번호 보유자를 모아준다.
      //  (요구: "검색창에 atas 치면 ATAS 명부 대상자가 나오게 해줘")
      if (qAtas && m.hasAtas) return true;
      // ATAS 번호로 검색 — 'atas 358' / '아타스358' 처럼 번호를 함께 쓴 경우.
      if (qAtas &&
          qDigits.isNotEmpty &&
          m.atasNo.replaceAll(RegExp(r'[^0-9]'), '').contains(qDigits)) {
        return true;
      }
      return false;
    }).toList();
  }

  // 개인 접근 시에는 본인 정보만 노출한다(all()이 restrictedNumber로 제한).

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
      case AiKind.credential:
        // 인가번호 · 소속 지목 — '범415' / '은하19호' / 'G19' / '은하'
        //  소속이 지목되면 **그 소속의** 해당 번호만 남긴다.
        //  (은하 19호와 범 19호는 번호만 같고 사람이 다르다 → 절대 섞지 않는다.)
        var hit = list
            .where(
              (m) =>
                  SearchQuery.corpsMatches(ai.corps, m.corps) &&
                  (ai.number == null || m.numberInt == ai.number),
            )
            .toList();
        final kw = ai.keyword.trim();
        if (kw.isNotEmpty) {
          hit = hit
              .where((m) => m.searchText.contains(kw.toLowerCase()))
              .toList();
        }
        return hit;
      case AiKind.donor:
        final fs = finance;
        if (fs == null) return [];
        final kw = ai.keyword.trim().toLowerCase();
        // 후원 카테고리 + (선택)키워드/연도로 매칭된 **(소속, 번호)** 집합
        //
        // ## [버그 수정 2026-10-30] 은하 G75 가 범 75호 후원자로 잡히던 문제
        //  · ① 종전에는 `category == '후원'` 만 봤는데 실제 데이터는
        //       '물품후원'·'식사후원'·'차량후원'·'기타후원'·'후원금' 이다.
        //       → `contains('후원')` 로 넓히고, 참가비/기타수입은
        //         `DonationKind.isNonDonation` 으로 먼저 배제한다.
        //  · ② **번호에서 숫자만 뽑아 비교**(`G75` → `75`)해서 은하 G75 가
        //       범 75호와 같은 사람이 됐다. → 소속까지 함께 본다.
        final donors = <String>{};
        for (final t in fs.transactions) {
          if (t.isExpense) continue;
          final cat = t.category.trim();
          if (DonationKind.isNonDonation(cat)) continue;
          if (!cat.contains('후원') &&
              cat != '찬조' &&
              cat != '기부' &&
              cat != '기타' &&
              cat != '기타수입') {
            continue;
          }
          if (ai.year.isNotEmpty && t.year != ai.year) continue;
          if (kw.isNotEmpty) {
            final hay = '${t.event} ${t.memo} ${t.context} ${t.payer}'
                .toLowerCase();
            if (!hay.contains(kw)) continue;
          }
          final key = _donorKey(t.number, t.corps);
          if (key.isNotEmpty) donors.add(key);
        }
        return list.where((m) => donors.contains(_donorKey(m.number, m.corps)))
            .toList();
    }
  }

  /// 후원자 식별 키 — **(소속, 번호)**. 은하 `G75` 와 범 `75` 는 다른 키.
  ///
  /// ## [버그 수정 2026-10-30] 숫자만 비교하면 은하 G75 = 범 75 가 된다.
  /// 접두어 `G`/`은하` 를 보존하고, 소속 문자열이 있으면 그것을 우선한다.
  static String _donorKey(String number, String corps) {
    final s = number.trim();
    final c = corps.trim().toLowerCase();
    final isEunha = c == 'eunha' ||
        s.toLowerCase().startsWith('g') ||
        s.startsWith('은하') ||
        s.startsWith('갤럭시');
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return '${isEunha ? 'eunha' : 'tsak'}:$digits';
  }

  /// 검색 질의 설정.
  ///
  /// ## [2026-11-02 build #579] 은하 명단 지연 로드
  ///   `은하19호` 를 쳤는데 은하 명단을 아직 안 불러와 0건이 나오는 일을 막는다.
  ///   소속 해석 결과가 '은하' 이고 아직 로드 전이면 백그라운드로 채우고,
  ///   도착하면 [_eunhaChanged] 가 refresh 를 다시 걸어 결과가 스스로 나타난다.
  void setQuery(String q) {
    _query = q;
    if (SearchQuery.parse(q).corps == SearchQuery.corpsEunha) {
      ensureEunhaForSearch();
    }
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
    // [2026-11-02 build #577] 소속 필터가 빠져 있었다.
    //  화면의 '초기화' 칩은 소속 줄에 있는데, 정작 소속(범스카우트/은하스카우트)
    //  선택은 지워지지 않았다. '은하스카우트'를 골라 143명이 보이는 상태에서
    //  초기화를 누르면 목록이 그대로여서 "초기화가 안 된다"로 보였다.
    //  → 누르면 보이는 모든 필터를 실제로 되돌린다.
    _corpsFilter = '';
    refresh();
  }

  Member? byId(String id) => repo.byId(id) ?? _eunhaById(id);
  Member? byNumber(String number) =>
      repo.byNumber(number) ?? _eunhaByNumber(number);
  Member? byName(String name) => repo.byName(name) ?? _eunhaByName(name);

  // ══════════════════════════════════════════════════════════════════════
  // [신원 해석 2026-10-29] 카드 연결은 **이 함수 하나만** 통과한다.
  //
  //  ## 사고 배경
  //   행사 참석자에 비인가자 '김순철' 을 수동 입력했는데, 예전 코드가
  //   "번호가 없네 → 이름으로 찾자" 로 폴백해서 **범인가자 동명이인**의
  //   개인카드를 열었다. 남의 후원·연회비·참가이력이 보이는 심각한 문제.
  //
  //  ## 규칙 (구조적으로 재발 불가)
  //   ① 이름은 **절대** 회원을 단정하지 않는다.
  //   ② 믿을 수 있는 키(인가번호/전화번호)로 정확히 1명일 때만 연다.
  //   ③ 이름은 "후보가 정확히 1명"일 때만 **보조**로 쓴다(그마저도 근거 표시).
  //   ④ 애매하면 **열지 않고** 후보 목록을 돌려준다 → 사용자가 고른다.
  // ══════════════════════════════════════════════════════════════════════

  /// 신원 조회 결과 — "누구로 열 것인가"를 **명시적으로** 표현한다.
  ///
  /// `member != null` 이면 열어도 안전하다. `candidates` 가 2명 이상이면
  /// **열면 안 되고** 사용자에게 선택을 받아야 한다.
  MemberIdentity resolveIdentity({
    String? number,
    String? phone,
    String? name,
    String? corps,
    bool allowNameFallback = true,
    /// 저장된 `licensed` 값. **false 이면 비인가자로 확정**되어 회원 조회를
    /// 아예 하지 않는다(이름 폴백 포함). null 이면 미지정(추론).
    bool? licensed,
  }) {
    final rawNum = (number ?? '').trim();
    final rawPhone = (phone ?? '').trim();
    final nm = (name ?? '').trim();

    // ══════════════════════════════════════════════════════════════════
    // [수정 2026-10-29] `licensed == false` 를 **"회원 아님"** 으로 해석하면 틀린다.
    //
    //  `licensed` 의 참뜻은 **"인가자(범/은하)인가"** 이지 "회원인가" 가 아니다.
    //  일반회원(비인가)도 우리 회원 명부에 존재한다 → 반드시 찾아야 한다.
    //
    //  ## 실제 사고
    //   참석자 김종선(licensed:false, 010-6269-1740) 을 클릭했더니
    //   "신규 등록" 만 반복 제안되고, 등록할 때마다 reg_<타임스탬프> 로
    //   **새 레코드가 쌓였다.** 이미 guest_900001(같은 전화) 이 있었는데도
    //   licensed:false 라서 조회를 아예 건너뛴 것이 원인.
    //
    //  ## 고친 규칙
    //   · licensed == false → **일반회원만** 대상으로 조회(인가자 카드로는 절대
    //     가지 않는다 = 첫 사고 방지). phone → 이름 순.
    //   · licensed == true  → 인가자만 대상(이름 폴백 금지).
    //   · null(구데이터)     → 전체 대상(기존 규칙).
    // ══════════════════════════════════════════════════════════════════
    final regularOnly = licensed == false;
    final strongOnly = licensed == true; // 인가 확정 → 이름 폴백 금지

    // ── 후보 풀 구성 (신원 조건을 **한 곳에서** 적용) ────────────────────
    //  regularOnly → 일반회원(isRegular)만. 인가자 카드로는 절대 가지 않는다.
    //  strongOnly  → 인가자만. 일반회원 계정으로 새지 않게.
    //  둘 다 아님(구데이터) → 전체.
    final all = <Member>[
      ...repo.allUnscoped(),
      ..._eunhaMembers,
    ];
    // ══════════════════════════════════════════════════════════════════════
    // [소속 분리 2026-10-29] **접두어가 곧 신원이다.**
    //
    // ## 실제 사고 (요구: "수동입력시 은하10 을 입력하면 또 범10이 검색됨")
    //  범과 은하는 번호 공간이 겹친다(둘 다 1~165). 입력 '은하10' 에서
    //  숫자만 뽑아 후보 풀 전체를 뒤지면 범10(이순욱)이 먼저 걸린다.
    //  서버도 같은 버그가 있어 양쪽에서 남의 카드가 열렸다.
    //
    // ## 규칙 (클라이언트도 서버와 동일)
    //  · 입력에 은하 표기(은하/갤럭시/G/g/galaxy) → **은하만** 후보.
    //  · 범 소속 세션 → 은하 제외.
    //  · 표기가 없고 소속도 없으면 → 전체(기존 규칙).
    //  이 필터를 **모든 단계(번호·전화·이름) 앞에** 두어 한 곳에서 끝낸다.
    // ══════════════════════════════════════════════════════════════════════
    final eunhaPrefix = _hasEunhaPrefix(rawNum);
    final forceEunha = eunhaPrefix || corps == 'eunha';
    final forceTsak = !eunhaPrefix && corps == 'tsak';
    final pool = all.where((m) {
      if (forceEunha && m.corps != 'eunha') return false;
      if (forceTsak && m.corps == 'eunha') return false;
      if (regularOnly) return m.isRegular;
      if (strongOnly) return !m.isRegular;
      return true;
    }).toList();

    // ── ① 인가번호 ─────────────────────────────────────────────────────
    //  은하 G75 와 범 75 는 접두어가 다르므로 여기서 절대 섞이지 않는다.
    final numKey = rawNum.replaceAll(RegExp(r'[^0-9]'), '');
    if (numKey.isNotEmpty) {
      final hits = pool.where((m) {
        if (m.isRegular) return false;   // 일반회원은 인가번호로 찾지 않는다
        // pool 이 이미 소속(은하/범)을 걸러 놓았다 — 여기선 번호만 대조.
        return m.number.replaceAll(RegExp(r'[^0-9]'), '') == numKey;
      }).toList();
      if (hits.length == 1) {
        return MemberIdentity.single(hits.first, via: 'number');
      }
      if (hits.length > 1) {
        return MemberIdentity.ambiguous(hits, via: 'number');
      }
    }

    // ── ② 전화번호 — **가장 강한 키**. 소속/인가 여부로 거르지 않는다. ──
    //  ══════════════════════════════════════════════════════════════════
    // [2026-10-29 무한루프 사고] 왜 `pool` 대신 `all` 을 쓰는가
    //
    //  참석자 행의 `licensed` 값은 **믿을 수 없다**. 서버가 저장할 때마다
    //  `number` 칸의 전화번호를 인가번호로 오인해 `licensed=true` 로
    //  덮어썼기 때문이다(이지원 사고). 그래서 licensed=true 라고 해서
    //  후보를 인가자로만 좁히면, 정작 명부에 있는 일반회원 레코드
    //  (reg_1793253833650 / reg:01027021126)를 **영원히 못 찾는다**
    //  → 이름을 누를 때마다 "신규 등록" 창이 다시 뜬다.
    //
    //  휴대폰 번호 11자리는 **정확 일치**라 오매칭 위험이 없다.
    //  그러므로 소속(은하/범)·인가 여부 필터를 **걸지 않고** 전체에서 찾는다.
    //  인가번호(①)는 여전히 소속 필터를 통과한 pool 에서만 찾는다 —
    //  은하10/범10 충돌 방지는 그대로 유지된다.
    //  ══════════════════════════════════════════════════════════════════
    final phKey = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phKey.length >= 7) {
      final hits = all.where((m) => m.phoneDigits == phKey).toList();
      if (hits.length == 1) {
        return MemberIdentity.single(hits.first, via: 'phone');
      }
      if (hits.length > 1) {
        // 같은 번호의 중복 레코드(예: reg_… 와 guest_…) → 가장 최근 것 하나로
        //  수렴시키지 않고, 사람에게 보여 준다(엉뚱한 카드 방지).
        return MemberIdentity.ambiguous(hits, via: 'phone');
      }
    }

    // ── ③ 이름 — **보조**. 후보가 정확히 1명일 때만 쓴다. ───────────────
    //   신원이 '인가자'로 확정된(stored licensed=true) 경우에는 이름을
    //   쓰지 않는다. 확정된 사람은 정확한 키로만 연결해야 한다.
    //   ⚠️ `strongOnly`(licensed=true) 여도 **일반회원 풀에서는** 이름을 본다.
    //     인가 확정 참석자의 이름이 명부의 일반회원과 일치한다면, 그건
    //     (a) 실제로 일반회원이거나 (b) 서버가 licensed 를 잘못 써 둔 경우다.
    //     둘 다 틀리면 후보 목록으로 물어보면 되므로 인가자 카드로 새지 않는다.
    final namePool = strongOnly
        ? all.where((m) => m.isRegular).toList()
        : pool;
    if (allowNameFallback && nm.isNotEmpty) {
      final hits = namePool.where((m) => m.name.trim() == nm).toList();
      // 같은 사람이 양쪽 저장소에 있으면 중복 제거(identityKey 기준).
      final uniq = <String, Member>{};
      for (final m in hits) {
        uniq.putIfAbsent(m.identityKey.isEmpty ? m.id : m.identityKey, () => m);
      }
      final list = uniq.values.toList();
      if (list.length == 1) {
        // 이름만으로 1명 — 열 수는 있지만 근거가 약하다는 사실을 남긴다.
        return MemberIdentity.single(list.first, via: 'name');
      }
      if (list.length > 1) {
        // 동명이인 → **절대 단정하지 않는다**. 후보만 제시.
        return MemberIdentity.ambiguous(list, via: 'name');
      }
    }
    return MemberIdentity.none();
  }

  /// 입력에 **은하 표기**가 있는지 — 소속과 무관하게 문자열만 본다.
  ///  '은하10' / '갤럭시10' / 'G10' / 'g10' / 'galaxy10' / 'eunha10' → true
  bool _hasEunhaPrefix(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s.startsWith('g') && s.length > 1) return true;
    return s.startsWith('은하') ||
        s.startsWith('갤럭시') ||
        s.startsWith('galaxy') ||
        s.startsWith('eunha');
  }

  /// 은하스카우트 캐시에서 조회(통합 검색 목록에 노출되는 은하 회원 해석용).
  Member? _eunhaById(String id) {
    for (final m in _eunhaMembers) {
      if (m.id == id) return m;
    }
    return null;
  }

  Member? _eunhaByNumber(String number) {
    final n = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (n.isEmpty) return null;
    for (final m in _eunhaMembers) {
      if (m.number.replaceAll(RegExp(r'[^0-9]'), '') == n) return m;
    }
    return null;
  }

  Member? _eunhaByName(String name) {
    final q = name.trim();
    if (q.isEmpty) return null;
    for (final m in _eunhaMembers) {
      if (m.name == q) return m;
    }
    return null;
  }

  /// 통합 검색 목록에 노출된 은하 회원인지(상세/편집 화면 라우팅 판정용).
  bool isEunhaMember(Member m) => m.corps == 'eunha';

  /// 이름 공개/비공개 로컬 반영 (서버 저장은 호출부에서 완료 후 호출).
  void setNameVisible(String id, bool visible) {
    final m = repo.rawById(id) ?? repo.byId(id);
    if (m == null) return;
    repo.saveLocalOnly(m.copyWith(nameVisible: visible));
    notifyListeners();
  }

  /// (요구) 행사 참가자 연동을 **로컬 캐시에 즉시** 반영한다.
  ///
  /// 서버(`/api/event/attendee/set`)는 저장 직후 `eventAttend[행사명]=true` 를
  /// members.json 에 기록하지만, 앱의 메모리 캐시는 그대로라 개인정보 화면의
  /// "행사참가 이력"에 즉시 보이지 않는다(앱 재시작/새로고침 후에야 반영).
  /// 행사 상세에서 참가자를 저장할 때 이 메서드로 캐시를 먼저 갱신해
  /// 개인정보 창을 열었을 때 바로 참여 행사가 보이게 한다.
  ///
  /// 반환: 실제로 갱신된 회원 수.
  Future<int> linkEventToMembers(
    String eventName,
    Iterable<String> idents,
  ) async {
    final name = eventName.trim();
    if (name.isEmpty) return 0;
    final digits = <String>{
      for (final i in idents)
        if (i.replaceAll(RegExp(r'[^0-9]'), '').isNotEmpty)
          i.replaceAll(RegExp(r'[^0-9]'), ''),
    };
    if (digits.isEmpty) return 0;
    var hit = 0;
    bool matched(Member m) {
      final no = m.number.replaceAll(RegExp(r'[^0-9]'), '');
      final ph = m.phone.replaceAll(RegExp(r'[^0-9]'), '');
      final lid = m.loginId.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.contains(no) ||
          (ph.isNotEmpty && digits.contains(ph)) ||
          (lid.isNotEmpty && digits.contains(lid));
    }

    // ── 범스카우트(로컬 캐시) ──
    final touched = <Member>[];
    for (final m in repo.allUnscoped()) {
      if (!matched(m) || m.eventAttend[name] == true) continue;
      final map = Map<String, bool>.from(m.eventAttend)..[name] = true;
      touched.add(m.copyWith(eventAttend: map));
    }
    if (touched.isNotEmpty) {
      await repo.saveLocalOnlyAll(touched);
      hit += touched.length;
    }
    // ── 은하스카우트(별도 캐시) ──
    for (var i = 0; i < _eunhaMembers.length; i++) {
      final m = _eunhaMembers[i];
      if (!matched(m) || m.eventAttend[name] == true) continue;
      final map = Map<String, bool>.from(m.eventAttend)..[name] = true;
      _eunhaMembers[i] = m.copyWith(eventAttend: map);
      hit++;
    }
    if (hit > 0) {
      refresh();
      notifyListeners();
    }
    return hit;
  }

  /// (요구) 행사 참가자 **삭제**를 로컬 캐시에 즉시 반영한다.
  ///
  /// ## 배경 (사용자 지적)
  ///  "참가자 삭제시 개인정보카드와 연계해서 참가행사에서도 삭제하도록 해줘"
  ///
  ///  서버는 이제 `/api/event/attendee/set` 에서 명단에 없는 회원의
  ///  `eventAttend[행사명]` 을 False 로 되돌린다. 그런데 앱의 메모리 캐시는
  ///  그대로라, 개인정보카드를 열면 여전히 '참가' 로 보인다
  ///  (앱을 새로고침해야 반영됨).
  ///
  ///  그래서 [linkEventToMembers] 의 반대 동작을 여기서 수행한다.
  ///  **키를 지우지 않고 False 로** 둔다 — 서버와 동일한 규칙이며,
  ///  개인정보카드는 `attend == true` 만 노출하므로 목록에서는 사라진다.
  ///
  /// [keepIdents] 는 화면에 **남아 있는** 참가자 식별자들이다.
  ///  그 목록에 없는 회원만 해제한다(다른 행사 기록은 건드리지 않는다).
  ///
  /// 반환: 실제로 해제된 회원 수.
  Future<int> unlinkEventFromMembers(
    String eventName, {
    required Iterable<String> keepIdents,
  }) async {
    final name = eventName.trim();
    if (name.isEmpty) return 0;
    final keep = <String>{
      for (final i in keepIdents)
        if (i.replaceAll(RegExp(r'[^0-9]'), '').isNotEmpty)
          i.replaceAll(RegExp(r'[^0-9]'), ''),
    };

    bool stayed(Member m) {
      final no = m.number.replaceAll(RegExp(r'[^0-9]'), '');
      final ph = m.phone.replaceAll(RegExp(r'[^0-9]'), '');
      final lid = m.loginId.replaceAll(RegExp(r'[^0-9]'), '');
      // 이 행사에 참가(True) 기록이 있고, 현재 명단에 남아 있으면 유지.
      return m.eventAttend[name] == true &&
          (keep.contains(no) ||
              (ph.isNotEmpty && keep.contains(ph)) ||
              (lid.isNotEmpty && keep.contains(lid)));
    }

    var hit = 0;

    // ── 범스카우트(로컬 캐시) ──
    final touched = <Member>[];
    for (final m in repo.allUnscoped()) {
      if (m.eventAttend[name] != true) continue; // 참가 기록 없음
      if (stayed(m)) continue; // 아직 명단에 있음
      final map = Map<String, bool>.from(m.eventAttend)..[name] = false;
      final updated = m.copyWith(eventAttend: map);
      // 개인 프로필 '참가행사' 목록도 함께 정리(있으면).
      touched.add(updated);
    }
    if (touched.isNotEmpty) {
      await repo.saveLocalOnlyAll(touched);
      hit += touched.length;
    }

    // ── 은하스카우트(별도 캐시) ──
    for (var i = 0; i < _eunhaMembers.length; i++) {
      final m = _eunhaMembers[i];
      if (m.eventAttend[name] != true) continue;
      if (stayed(m)) continue;
      final map = Map<String, bool>.from(m.eventAttend)..[name] = false;
      _eunhaMembers[i] = m.copyWith(eventAttend: map);
      hit++;
    }

    if (hit > 0) {
      refresh();
      notifyListeners();
    }
    return hit;
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

  Future<void> save(Member m, {String linkRequestSource = ''}) async {
    if (m.corps == 'eunha') {
      // 은하스카우트 — 범스카우트 DB 오염 방지를 위해 은하 명단으로 단건 저장.
      //  (관리자·마스터 편집 저장 경로)
      await repo.saveOneNas(
        m,
        corps: 'eunha',
        by: (isEunha && !(isApp || isMaster)) ? 'personal' : 'app',
        linkRequestSource: linkRequestSource,
      );
      // 은하 캐시도 최신 상태로 반영(검색 목록/말머리 즉시 갱신).
      if (_eunhaMembers.isNotEmpty) {
        final i = _eunhaMembers.indexWhere((x) => x.id == m.id);
        if (i >= 0) {
          _eunhaMembers[i] = m;
        } else {
          _eunhaMembers.add(m);
        }
      }
      refresh();
      return;
    }
    await repo.save(m, linkRequestSource: linkRequestSource);
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
  ///
  /// ── [버그 수정 2026-10-26] '비번 강제 변경'이 안 되던 문제 ──────────────
  ///
  ///  증상: 강제 변경을 실행하면 "변경했습니다" 라고 뜨는데, 실제로는
  ///        이전 비밀번호로 계속 로그인됐다.
  ///
  ///  원인 1(클라): 서버 호출을 `try { ... } catch (_) {}` 로 감싸 **오류를
  ///    통째로 삼켰다.** 서버가 400/401 을 돌려줘도 화면은 성공으로 표시됐다.
  ///  원인 2(클라): 서버 호출보다 **먼저** 로컬 DB(repo.save)에 새 비번을
  ///    써버렸다. 서버가 거부해도 로컬에는 남아 화면·DB 가 어긋났다.
  ///  원인 3(서버): stale 캐시 백그라운드 갱신이 방금 저장한 값을 옛 값으로
  ///    덮어쓰는 경쟁 상태(lost update) — proxy `_save_json`/`_json_refresh_bg`
  ///    에 세대(generation) 가드를 넣어 수정.
  ///
  ///  수정: **서버를 진실원으로 삼는다.** 서버를 먼저 호출해 성공을 확인한
  ///        뒤에만 로컬을 갱신하고, 실패하면 서버가 준 사유를 그대로 돌려준다.
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

    if (repo.isNasMode) {
      // ⓪ 마스터라면 서버 세션 등급을 먼저 마스터로 맞춘다.
      //    개인 탭 로그인(tiger415)은 서버 세션이 personal 이라, 종전에는
      //    마스터 전용 변경이 서버에서 거부됐다(화면만 성공처럼 보임).
      if (isMaster) await ensureServerSession(needAdmin: true);
      // ① 서버가 권위 저장소 — 먼저 적용하고 결과를 확인한다.
      Map<String, dynamic> r;
      try {
        r = await nas.setAdminPassword(
          tier: isMaster ? 'master' : 'app',
          id: m.loginId,
          value: newPw,
          reset: reset,
          master: isPermanentMaster ? masterToken() : null,
        );
      } catch (e) {
        return '서버에 연결하지 못했습니다: $e';
      }
      if (r['ok'] != true) {
        final why = '${r['error'] ?? '알 수 없는 오류'}';
        // 서버가 실제로 적용한 값을 알려주면 그 값으로 맞춘다(불일치 방지).
        final applied = '${r['newPassword'] ?? ''}'.trim();
        if (applied.isNotEmpty && applied != newPw) {
          await repo.save(m.copyWith(personalPassword: applied));
          return '서버가 다른 값을 적용했습니다 ($why) — 화면을 새로고침합니다';
        }
        return why;
      }
      // ② 서버 성공 확인 후에만 로컬 반영.
      final applied = '${r['newPassword'] ?? ''}'.trim();
      await repo.save(
        m.copyWith(personalPassword: applied.isNotEmpty ? applied : newPw),
      );
      return null;
    }

    // NAS 모드가 아니면(로컬 단독) 로컬 저장이 곧 진실원.
    await repo.save(m.copyWith(personalPassword: newPw));
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

  /// 선택 계정 완전 삭제(마스터 전용). 삭제 성공 건수를 반환한다.
  ///  · 스포츠(범스카우트): 전체 저장 시 고아 삭제가 함께 반영된다.
  ///  · 은하스카우트: 서버 별도 명단에서 삭제 후 재조회한다.
  Future<int> deleteMembers(List<Member> members) async {
    if (members.isEmpty) return 0;
    final isE = members.first.corps == 'eunha';
    final ids = members.map((m) => m.id).toList();
    if (repo.isNasMode) {
      try {
        final res = await nas.deleteMembers(ids, corps: isE ? 'eunha' : 'tsak');
        if (res['ok'] != true) return 0;
      } catch (_) {
        return 0;
      }
    }
    if (isE) {
      await loadEunhaMembers();
    } else {
      for (final m in members) {
        await repo.delete(m.id);
      }
    }
    refresh();
    return ids.length;
  }

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

// ══════════════════════════════════════════════════════════════════════════
// 신원 해석 결과 — "이 참가자를 어떤 회원으로 열 것인가"
//
//  ## 왜 별도 타입인가
//   예전에는 `Member?` 하나로 "찾음/못 찾음"만 표현했다. 그래서
//   "동명이인 3명 중 하나를 **찍었다**" 와 "정확히 1명을 **찾았다**" 를
//   구분할 수 없었고, 찍은 결과가 그대로 카드로 열렸다(사고의 근본 원인).
//
//  이제는 3-상태를 **타입으로 강제**한다:
//    · single     → member != null, candidates.length == 1  → 열어도 됨
//    · ambiguous  → member == null, candidates.length >= 2  → **열면 안 됨**
//    · none       → 아무것도 못 찾음                        → 신규 등록 유도
// ══════════════════════════════════════════════════════════════════════════
class MemberIdentity {
  const MemberIdentity._(this.member, this.candidates, this.via);

  /// 열어도 안전한 단일 회원(없으면 null).
  final Member? member;

  /// 후보 전부(단일이면 1개, 없으면 0개).
  final List<Member> candidates;

  /// 어떤 근거로 찾았는가 — 'number' | 'phone' | 'name' | ''.
  final String via;

  factory MemberIdentity.single(Member m, {required String via}) =>
      MemberIdentity._(m, [m], via);

  factory MemberIdentity.ambiguous(List<Member> list, {required String via}) =>
      MemberIdentity._(null, List.unmodifiable(list), via);

  factory MemberIdentity.none() =>
      const MemberIdentity._(null, [], '');

  /// 카드를 열어도 되는가 — **단일** 후보이고 근거가 있을 때만.
  bool get isResolved => member != null && candidates.length == 1;

  /// 동명이인 등으로 사람이 직접 골라야 하는가.
  bool get needsChoice => member == null && candidates.length > 1;

  /// 근거가 이름뿐인가(약한 근거) — UI 에서 경고 배지를 띄우는 데 쓴다.
  bool get viaNameOnly => isResolved && via == 'name';

  /// 사용자 안내 문구.
  String get message {
    if (isResolved) {
      final m = member!;
      final label = m.isRegular ? '일반' : m.corpsMarkLabel;
      return '${m.name} ($label ${m.number.isEmpty ? m.phone : m.number})';
    }
    if (needsChoice) {
      return '동명이인 ${candidates.length}명 — 이름으로는 열 수 없습니다. '
          '인가번호나 연락처로 구분해 주세요.';
    }
    return '일치하는 회원이 없습니다';
  }
}
