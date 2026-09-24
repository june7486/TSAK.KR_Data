import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/member.dart';
import 'ai_query.dart';
import 'app_config.dart';
import 'finance_service.dart';
import 'member_repository.dart';
import 'nas_api.dart';

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
  String _tier = ''; // master | app | personal
  String _who = ''; // 개인 로그인 시 인가번호
  DateTime? _sessionStart;

  bool get unlocked => _unlocked;
  String get tier => _tier;
  String get who => _who;
  bool get isMaster => _tier == 'master';
  bool get isPersonal => _tier == 'personal';
  bool get isApp => _tier == 'app';

  /// 개인 접근 시 본인 정보만 열람·수정 가능하도록 저장소 제한을 갱신
  void _applyAccessScope() {
    if (_tier == 'personal' && _who.isNotEmpty) {
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
      if (ts != null && tier.isNotEmpty) {
        final start = DateTime.fromMillisecondsSinceEpoch(ts);
        if (DateTime.now().difference(start) < AppConfig.sessionTimeout) {
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

  Future<bool> login(String tier, String value) async {
    bool ok;
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
      // 앱 접근: NAS 모드에서는 서버에 설정된 (마스터가 변경한) 비번으로 검증
      ok = false;
      if (repo.isNasMode) {
        try {
          final r = await nas.login('app', value);
          ok = r['ok'] == true;
        } catch (_) {}
      }
      // 서버 미연결/오프라인이면 로컬 상수로 폴백
      if (!ok) ok = value == AppConfig.appPassword;
    } else {
      // 개인: 인가번호 + !@@  (오프라인이면 로컬에서도 검증)
      final no = value.replaceAll(RegExp(r'[^0-9]'), '');
      final expected = '$no${AppConfig.personalSuffix}';
      if (value != expected) {
        ok = false;
      } else {
        ok = repo.byNumber(no) != null;
        if (!ok && repo.isNasMode) {
          try {
            final r = await nas.login('personal', value);
            ok = r['ok'] == true;
          } catch (_) {}
        }
      }
    }
    if (ok) {
      _unlocked = true;
      _tier = tier;
      _who = tier == 'personal' ? value.replaceAll(RegExp(r'[^0-9]'), '') : '';
      _sessionStart = DateTime.now();
      _applyAccessScope();
      _persistSession();
      notifyListeners();
    }
    return ok;
  }

  Future<void> lock() async {
    _unlocked = false;
    _tier = '';
    _who = '';
    _sessionStart = null;
    repo.restrictedNumber = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(AppConfig.kSessionTs);
      await p.remove(AppConfig.kAuthTier);
      await p.remove(AppConfig.kAuthWho);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _persistSession() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(
          AppConfig.kSessionTs, _sessionStart!.millisecondsSinceEpoch);
      await p.setString(AppConfig.kAuthTier, _tier);
      await p.setString(AppConfig.kAuthWho, _who);
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
      {'label': '후원계좌', 'bank': '기업은행', 'account': '1005-202-281140'},
      {'label': '수품구매계좌', 'bank': '기업은행', 'account': '1005-102-281143'},
      {'label': '행사비계좌', 'bank': '기업은행', 'account': '1005-003-886274'},
    ];
  }

  String get donationHolder => '${_config['donationHolder'] ?? '한국범스카우트중앙회'}';
  Map<String, dynamic> get developer {
    final d = _config['developer'];
    if (d is Map) return d.cast<String, dynamic>();
    return {'name': '이승준', 'unit': '범스카우트415', 'email': 'june7558@gmail.com'};
  }

  String get appAccessUrl => '${_config['appAccessUrl'] ?? ''}';

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

  /// 개인비번 초기화(reset=true) 또는 지정 변경
  Future<String?> setPersonalPassword(
    String master,
    String number, {
    String? value,
    bool reset = false,
  }) async {
    try {
      final r = await nas.setPersonalPassword(master, number,
          value: value, reset: reset);
      if (r['ok'] == true) {
        _admin = {
          ..._admin,
          'personalPasswords': {
            ...((_admin['personalPasswords'] as Map?) ?? {}),
          }
        };
        await loadAdmin();
        return null;
      }
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

  List<Member> get members => _members;
  String get query => _query;
  String get leagueFilter => _leagueFilter;
  String get yearFilter => _yearFilter;
  bool get onlyLifetime => _onlyLifetime;

  Map<String, int> get leagues => repo.leaguesWithCount();
  List<String> get feeYears => repo.feeYearOptions();
  List<String> get events => repo.eventOptions();
  List<MapEntry<String, int>> get feeCounts => repo.feeCountsByYear();

  int get total => repo.count;
  int get lifetimeCount => _filterBase().where((m) => m.lifetimeMember).length;
  Map<String, int> get feeCountMap =>
      {for (final e in repo.feeCountsByYear()) e.key: e.value};

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
    final range = RegExp(r'^\s*(\d{1,5})\s*[-~]\s*(\d{1,5})\s*$')
        .firstMatch(rawQuery);
    if (range != null) {
      final a = int.parse(range.group(1)!);
      final b = int.parse(range.group(2)!);
      final lo = a <= b ? a : b;
      final hi = a <= b ? b : a;
      return list
          .where((m) => m.numberInt >= lo && m.numberInt <= hi)
          .toList();
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
      if (m.eventAttend.keys
          .any((e) => e.toLowerCase().contains(q))) {
        return true;
      }
      return false;
    }).toList();
  }

  List<Member> _filterBase() => repo.all();

  /// AI 자연어 검색 결과 적용
  List<Member> _applyAiQuery(List<Member> list, AiQuery ai) {
    switch (ai.kind) {
      case AiKind.feePaid:
        final y = ai.year;
        return list
            .where((m) => y.isEmpty
                ? m.feeYears.values.any((v) => v)
                : m.feeYears[y] == true)
            .toList();
      case AiKind.lifetime:
        return list.where((m) => m.lifetimeMember).toList();
      case AiKind.training:
        final kw = ai.keyword.trim();
        if (kw.isEmpty) {
          return list.where((m) => m.trainingStatus.trim().isNotEmpty).toList();
        }
        return list
            .where((m) =>
                m.trainingStatus.contains(kw) || m.searchText.contains(kw))
            .toList();
      case AiKind.eventAttend:
        final kw = ai.keyword.trim().toLowerCase();
        if (kw.isEmpty) {
          return list
              .where((m) => m.eventAttend.values.any((v) => v))
              .toList();
        }
        return list.where((m) {
          // 행사명 키워드가 참석 행사명에 포함되면 매칭
          return m.eventAttend.keys
              .any((e) => e.toLowerCase().contains(kw) && m.eventAttend[e] == true);
        }).toList();
      case AiKind.donor:
        final fs = finance;
        if (fs == null) return [];
        final kw = ai.keyword.trim().toLowerCase();
        // 후원 카테고리 + (선택)키워드/연도로 매칭된 인가번호 집합
        final numbers = <String>{};
        for (final t in fs.transactions) {
          if (t.isExpense) continue;
          final isDonation = t.category == '후원' ||
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
            .where((m) =>
                numbers.contains(m.number.replaceAll(RegExp(r'[^0-9]'), '')))
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

  void clearFilters() {
    _query = '';
    _leagueFilter = '';
    _yearFilter = '';
    _onlyLifetime = false;
    refresh();
  }

  Member? byId(String id) => repo.byId(id);
  Member? byNumber(String number) => repo.byNumber(number);

  Future<void> save(Member m) async {
    await repo.save(m);
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
