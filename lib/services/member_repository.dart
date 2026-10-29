import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';

import '../models/member.dart';
import 'league_names.dart';
import 'nas_api.dart';

/// 인가자 데이터 저장소
///
/// 모드:
///  - NAS 모드 ([nas] 주입): NAS의 최신 DB를 메모리 캐시로 로드하고,
///    변경 시 NAS에 저장(서버가 자동 백업). "항상 최신 서버 파일" 보장.
///  - Hive 모드: 앱 첫 실행 시 assets 시드 후 로컬 영구 저장(오프라인)
///  - 인메모리: 테스트용
class MemberRepository {
  static const String boxName = 'members_box';
  static const String metaBoxName = 'meta_box';

  Box? _box;
  Box? _meta;

  /// 메모리 캐시 (NAS 모드 또는 테스트)
  final Map<String, Map<String, dynamic>>? _mem;

  final NasApi? nas;

  /// 개인 접근 시 본인 인가번호 — 설정되면 이 번호 외 데이터 접근을 차단한다.
  String? restrictedNumber;

  bool get isRestricted =>
      restrictedNumber != null && restrictedNumber!.trim().isNotEmpty;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final ValueNotifier<Map<String, dynamic>> serverMeta =
      ValueNotifier<Map<String, dynamic>>({});
  final ValueNotifier<String> syncStatus = ValueNotifier<String>(
    '',
  ); // '', 'saving', 'saved', 'error', 'offline'

  /// [성능] 전체 목록 캐시 — 2233건을 매 호출마다 재구성하면(웹 dart2js 수 초)
  ///  UI가 멈춘다. 한 번 만들어 재사용한다. 데이터 변경(_put/_putAll/…) 시 무효화.
  List<Member>? _unscopedCache;
  final Map<String, Member> _byIdCache = {};

  void _invalidateCaches() {
    _unscopedCache = null;
    _byIdCache.clear();
  }

  // ══════════════════════════════════════════════════════════════════
  // [2026-10-29] 마지막으로 만들어진 리포지토리 — **읽기 전용 조회용**.
  //
  //  결산 상세에서 참석자 행에 없는 연맹/단위대를 명부에서 보충하려면
  //  서비스 계층이 리포지토리에 접근해야 한다. 화면 위젯 트리 밖에서도
  //  동작해야 하므로(AppState 없이도) 정적 참조를 하나 둔다.
  //  ⚠️ **쓰기에는 절대 쓰지 않는다** — 조회 전용 편의 접근자다.
  // ══════════════════════════════════════════════════════════════════
  static MemberRepository? _last;
  static MemberRepository? get instanceOrNull => _last;

  /// Hive 기반 (프로덕션, 오프라인 전용)
  MemberRepository({this.nas})
    : _mem = nas != null ? <String, Map<String, dynamic>>{} : null {
    _last = this;
  }

  /// 인메모리 기반 (테스트/미리보기)
  MemberRepository.memory({this.nas})
    : _mem = <String, Map<String, dynamic>>{} {
    _last = this;
  }

  bool get isMemory => _mem != null;
  bool get isNasMode => nas != null;

  /// NAS 최신 데이터 로드. 성공 시 true.
  ///  · [self=true] → 서버에서 **본인 1건만** 조회(개인정보 수정 화면 전용).
  ///  · 회원 맵(raw) 그대로 받아 저장한다 — 2233건을 Member 로 변환(수 초)하고
  ///    다시 toMap 으로 되돌리는 **이중 변환을 제거**해 로딩이 즉시 끝난다.
  Future<bool> syncFromNas({bool self = false}) async {
    final api = nas;
    if (api == null) return false;
    try {
      syncStatus.value = 'saving';
      final maps = await api.fetchMembersRaw(self: self);
      if (maps.isEmpty) {
        syncStatus.value = 'error';
        return false;
      }
      final batch = {for (final m in maps) '${m['id']}': m};
      final merge = isRestricted || self;
      final mem = _mem;
      if (mem != null) {
        if (merge) {
          // 개인/게스트(본인 1건) 접근: 전체 목록을 덮어쓰지 않고 병합한다.
          //  (시드 폴백으로 채운 목록을 보존하여 QR 자동로그인/본인 조회가
          //   관리자 데이터를 다시 받아온 뒤에도 계속 동작하게 함)
          mem.addAll(batch);
        } else {
          mem.clear();
          mem.addAll(batch);
        }
      } else {
        if (merge) {
          await _box!.putAll(batch);
        } else {
          await _box!.clear();
          await _box!.putAll(batch);
        }
      }
      try {
        final meta = await api.fetchMeta();
        serverMeta.value = meta;
      } catch (_) {}
      syncStatus.value = 'saved';
      _invalidateCaches();
      revision.value++;
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('syncFromNas failed: $e');
      syncStatus.value = 'error';
      return false;
    }
  }

  /// 전체 DB를 NAS에 저장(서버가 이전 버전 자동 백업)
  Future<bool> syncToNas({String by = 'app'}) async {
    final api = nas;
    if (api == null) return false;
    try {
      syncStatus.value = 'saving';
      final res = await api.saveAll(all(), by: by);
      if (res['ok'] == true) {
        final meta = (res['meta'] as Map?)?.cast<String, dynamic>();
        if (meta != null) serverMeta.value = meta;
        syncStatus.value = 'saved';
        return true;
      }
      syncStatus.value = 'error';
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('syncToNas failed: $e');
      syncStatus.value = 'error';
      return false;
    }
  }

  Future<void> init() async {
    if (!isMemory) {
      await Hive.initFlutter();
      _box = await Hive.openBox(boxName);
      _meta = await Hive.openBox(metaBoxName);
    }

    // NAS 모드: 서버 최신 데이터 우선
    if (isNasMode) {
      final ok = await syncFromNas();
      if (ok) {
        revision.value++;
        return;
      }
      // NAS 실패(로그인 전 401 등) 시 로컬/시드로 폴백
    }

    // 웹(memory) 모드: 로그인 전에는 서버가 401 이라 목록이 비어 있다.
    //  시드(합성) 목록을 채워 잠금화면 목록/QR 자동로그인(byNumber)이 동작하게
    //  한다. 로그인 후에는 _reloadAfterLogin → syncFromNas 로 실데이터를 채운다.
    if (isMemory) {
      if (_mem!.isEmpty) {
        await _seedFromAssets();
      }
      revision.value++;
      return;
    }

    if (!isMemory) {
      final seeded = _meta!.get('seeded_v2', defaultValue: false) as bool;
      if (!seeded || _box!.isEmpty) {
        await _seedFromAssets();
        await _meta!.put('seeded_v2', true);
      }
    }
    revision.value++;
  }

  Future<void> _seedFromAssets() async {
    try {
      final raw = await rootBundle.loadString('assets/data/members_seed.json');
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      // [성능] 시드 원본 맵을 **그대로** 저장한다(Member 변환→toMap 이중 변환 제거).
      //  저장소는 raw 맵을 다루므로 화면 렌더도 즉시 가능하다.
      final batch = <String, Map<String, dynamic>>{};
      for (final item in list) {
        if (item is! Map) continue;
        final m = item.cast<String, dynamic>();
        final id = '${m['id'] ?? m['number'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        m['id'] = id;
        batch[id] = m;
      }
      await _putAll(batch);
      if (kDebugMode) debugPrint('Seeded ${batch.length} members');
    } catch (e) {
      if (kDebugMode) debugPrint('Seeding failed: $e');
    }
  }

  // ---- 내부 저장소 접근 추상화 ----
  Iterable<Map> get _values sync* {
    if (isMemory) {
      yield* _mem!.values;
    } else {
      for (final v in _box!.values) {
        yield v as Map;
      }
    }
  }

  int get count =>
      isRestricted ? all().length : (isMemory ? _mem!.length : _box!.length);

  Future<void> _put(String id, Map<String, dynamic> map) async {
    _invalidateCaches();
    if (isMemory) {
      _mem![id] = map;
    } else {
      await _box!.put(id, map);
    }
  }

  Future<void> _putAll(Map<String, Map<String, dynamic>> batch) async {
    _invalidateCaches();
    if (isMemory) {
      _mem!.addAll(batch);
    } else {
      await _box!.putAll(batch);
    }
  }

  Future<void> _deleteKey(String id) async {
    _invalidateCaches();
    if (isMemory) {
      _mem!.remove(id);
    } else {
      await _box!.delete(id);
    }
  }

  Future<void> _clearAll() async {
    _invalidateCaches();
    if (isMemory) {
      _mem!.clear();
    } else {
      await _box!.clear();
    }
  }

  /// 로컬 캐시만 비운다(NAS 저장은 하지 않음).
  ///  소속(corps) 전환 시 이전 소속 데이터가 섞이지 않도록 초기화하는 용도.
  Future<void> clearLocalCache() async {
    await _clearAll();
    revision.value++;
  }

  // ---- 공개 API ----
  bool _matchesRestricted(Member m) {
    if (!isRestricted) return true;
    final r = restrictedNumber!.replaceAll(RegExp(r'[^0-9]'), '');
    if (r.isEmpty) return false;
    final num = m.number.replaceAll(RegExp(r'[^0-9]'), '');
    final login = m.loginId.replaceAll(RegExp(r'[^0-9]'), '');
    final phone = m.phone.replaceAll(RegExp(r'[^0-9]'), '');
    return num == r || login == r || phone == r;
  }

  /// 인가자 정렬 규칙: 인가자(비일반회원)를 먼저, 일반회원(isRegular)을 항상
  /// 목록의 가장 뒤에 배치한다. 같은 그룹 내에서는 인가번호 오름차순.
  static int compareMembers(Member a, Member b) {
    if (a.isRegular != b.isRegular) {
      // 일반회원이면 +1, 인가자면 -1 → 일반회원이 뒤로.
      return a.isRegular ? 1 : -1;
    }
    return a.numberInt.compareTo(b.numberInt);
  }

  List<Member> all() {
    final base = allUnscoped();
    if (isRestricted) {
      return base.where(_matchesRestricted).toList();
    }
    return base;
  }

  /// 제한 없이 전체 목록(관리자/마스터 전용) — 캐시된 목록을 재사용한다.
  List<Member> allUnscoped() {
    final cached = _unscopedCache;
    if (cached != null) return cached;
    final list = _values.map((v) => Member.fromMap(v)).toList()
      ..sort(compareMembers);
    _unscopedCache = list;
    return list;
  }

  Member? byId(String id) {
    final m = _rawById(id);
    if (m == null) return null;
    if (isRestricted) return _matchesRestricted(m) ? m : null;
    return m;
  }

  Member? _rawById(String id) {
    final cached = _byIdCache[id];
    if (cached != null) return cached;
    dynamic v;
    if (isMemory) {
      v = _mem![id];
    } else {
      v = _box!.get(id);
    }
    if (v == null) return null;
    final m = Member.fromMap(v as Map);
    _byIdCache[id] = m;
    return m;
  }

  /// raw 맵 1건이 제한(본인) 조건에 맞는지.
  bool _matchesRestrictedRaw(Map m) {
    if (!isRestricted) return true;
    final r = restrictedNumber!.replaceAll(RegExp(r'[^0-9]'), '');
    if (r.isEmpty) return false;
    final num = '${m['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final login = '${m['loginId'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final phone = '${m['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    return num == r || login == r || phone == r;
  }

  /// [성능] raw 맵을 훑어 **일치하는 1건만** Member 로 변환한다(전체 변환 배제).
  ///  byNumber/byName 는 로그인·딥링크의 첫 관문이라 2233건 변환으로 막히면
  ///  화면이 멈춘다. 매칭 1건만 변환해 즉시 반환한다.
  Member? byNumber(String number) {
    final n = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (n.isEmpty) return null;
    final restricted = isRestricted;
    final r = restricted
        ? restrictedNumber!.replaceAll(RegExp(r'[^0-9]'), '')
        : '';
    for (final v in _values) {
      final m = v;
      final num = '${m['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
      final lid = '${m['loginId'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
      if (restricted) {
        final ph = '${m['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
        if (r.isEmpty || (num != r && lid != r && ph != r)) continue;
        if (lid == n || num == n) return Member.fromMap(m);
      } else {
        if (num == n) return Member.fromMap(m);
      }
    }
    return null;
  }

  /// 이름으로 회원 조회 (동명이인은 첫 번째 반환).
  ///
  /// ⚠️ **카드 연결에 쓰지 말 것** — 동명이인 사고의 원인이었다.
  ///    카드 연결은 [lookupIdentity] / `Member.identityKey` 를 쓴다.
  ///    이 함수는 "표시용 첫 번째"가 정말 필요한 곳(자동완성 등)에만 쓴다.
  Member? byName(String name) {
    final q = name.trim();
    if (q.isEmpty) return null;
    for (final v in _values) {
      final m = v;
      if ('${m['name'] ?? ''}'.trim() != q) continue;
      if (!_matchesRestrictedRaw(m)) continue;
      return Member.fromMap(m);
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════
  // [신원 조회 2026-10-29] 이름 → 회원 단정 금지
  //
  //  `byName()` 은 동명이인이어도 **조용히 첫 번째**를 돌려준다. 카드 연결에
  //  쓰면 비인가자 '김순철' 이 인가자 '김순철' 카드로 열린다(실제 사고).
  //
  //  그래서 "이름으로 찾을 때는 **반드시 결과 개수를 함께** 돌려준다"는
  //  규칙으로 API 를 바꾼다. 호출자는 n==1 일 때만 그 회원을 쓸 수 있다.
  // ══════════════════════════════════════════════════════════════════════

  /// 이름으로 **후보 전부** 조회 — 동명이인 판정용.
  List<Member> allByName(String name) {
    final q = name.trim();
    if (q.isEmpty) return const [];
    final out = <Member>[];
    for (final v in _values) {
      if ('${v['name'] ?? ''}'.trim() != q) continue;
      if (!_matchesRestrictedRaw(v)) continue;
      out.add(Member.fromMap(v));
    }
    return out;
  }

  /// ID 문자열(문자 포함 가능)로 회원 조회 — loginId/전화번호/인가번호 순으로 대조.
  /// (요구) ID는 숫자뿐 아니라 영문·한글·특수문자도 허용하므로, 문자열이
  /// 등록된 로그인아이디와 일치하면 우선 반환하고, 아니면 숫자를 추출해
  /// 전화번호·인가번호와 대조한다.
  Member? byLoginId(String id) {
    final q = id.trim();
    if (q.isEmpty) return null;
    final low = q.toLowerCase();
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    for (final v in _values) {
      final m = v;
      final lid = '${m['loginId'] ?? ''}'.trim();
      if (lid.isNotEmpty && lid.toLowerCase() == low) return Member.fromMap(m);
      if (digits.isNotEmpty) {
        if (lid.replaceAll(RegExp(r'[^0-9]'), '') == digits) {
          return Member.fromMap(m);
        }
        if ('${m['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '') == digits) {
          return Member.fromMap(m);
        }
        if ('${m['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '') ==
            digits) {
          return Member.fromMap(m);
        }
      }
    }
    return null;
  }

  List<Member> search(String query, {String? league, String? year}) {
    final q = query.trim().toLowerCase();
    var list = all();
    if (league != null && league.isNotEmpty) {
      list = list.where((m) => sameLeague(m.league, league)).toList();
    }
    if (year != null && year.isNotEmpty) {
      list = list.where((m) => m.feeYears[year] == true).toList();
    }
    if (q.isNotEmpty) {
      list = list.where((m) => m.searchText.contains(q)).toList();
    }
    return list;
  }

  /// 연맹별 인가자 수.
  ///   [currentActivity] 가 true 이면 **현재활동 소속연맹**(regLeague, 없으면
  ///   인가시 연맹 league 로 폴백) 기준으로 집계한다.
  ///   false(기본)이면 **범인가시 소속연맹**(league) 기준.
  Map<String, int> leaguesWithCount({bool currentActivity = false}) {
    final map = <String, int>{};
    for (final m in all()) {
      final raw = currentActivity
          ? (m.regLeague.trim().isNotEmpty ? m.regLeague : m.league)
          : m.league;
      final key = normalizeLeague(raw);
      final k = key.isEmpty ? '(미지정)' : key;
      map[k] = (map[k] ?? 0) + 1;
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // "미지정"은 항상 마지막
    final fixed = <String, int>{};
    for (final e in entries) {
      if (e.key != '(미지정)') fixed[e.key] = e.value;
    }
    if (map.containsKey('(미지정)')) fixed['(미지정)'] = map['(미지정)']!;
    return fixed;
  }

  /// 현재활동 기준으로 별도 통계 산출 가능한지(= 현재활동 연맹/단위대·직위 중
  /// 하나라도 입력된 회원이 있는지) 여부.
  bool hasCurrentActivityData() => all().any(
    (m) =>
        m.regLeague.trim().isNotEmpty ||
        m.regUnit.trim().isNotEmpty ||
        m.position.trim().isNotEmpty,
  );

  /// 직위(현재활동) 분포.
  Map<String, int> positionsWithCount() {
    final map = <String, int>{};
    for (final m in all()) {
      final p = m.position.trim();
      if (p.isEmpty) continue;
      map[p] = (map[p] ?? 0) + 1;
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in entries) e.key: e.value};
  }

  List<String> feeYearOptions() {
    final years = <String>{'2024', '2025', '2026', '2027'};
    for (final v in _values) {
      years.addAll(Member.fromMap(v).feeYears.keys);
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  List<String> eventOptions() {
    final events = <String>{};
    for (final v in _values) {
      events.addAll(Member.fromMap(v).eventAttend.keys);
    }
    return events.toList()..sort();
  }

  /// 연도별 납부 인원 (2027/2026/… 등)
  List<MapEntry<String, int>> feeCountsByYear() {
    final counts = <String, int>{};
    final years = feeYearOptions();
    for (final y in years) {
      counts[y] = 0;
    }
    for (final v in _values) {
      final m = Member.fromMap(v);
      for (final e in m.feeYears.entries) {
        if (e.value) counts[e.key] = (counts[e.key] ?? 0) + 1;
      }
    }
    return counts.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
  }

  Future<void> save(
    Member member, {
    bool syncing = true,
    String linkRequestSource = '',
  }) async {
    final updated = member.copyWith(updatedAt: DateTime.now());
    await _put(updated.id, updated.toMap());
    revision.value++;
    if (syncing && isNasMode) {
      if (updated.corps == 'eunha') {
        // 은하스카우트 회원: 범스카우트 DB 오염 방지를 위해 **단건 부분 저장**만
        //  수행한다(서버가 corps='eunha' 를 보고 은하 DB로 라우팅).
        unawaited(
          _saveOne(
            updated,
            linkRequestSource: linkRequestSource,
            corps: 'eunha',
            by: 'app',
          ),
        );
      } else if (isRestricted) {
        // 개인 접근: 본인 1건만 부분 저장 (연결 승인요청방법 전달).
        unawaited(_saveOne(updated, linkRequestSource: linkRequestSource));
      } else {
        unawaited(syncToNas(by: 'app'));
      }
    }
  }

  /// 의도한 소속(corps)으로 **단건만** NAS에 부분 저장한다.
  ///  · 은하스카우트 편집 저장이 범스카우트 DB를 오염시키지 않도록 라우팅.
  ///  · 로컬 캐시는 호출부(AppState)가 은하 캐시(_eunhaMembers)로 별도 관리하므로
  ///    이 메서드는 박스에 쓰지 않는다(범스카우트 목록 오염 방지).
  Future<bool> saveOneNas(
    Member member, {
    String corps = '',
    String by = 'app',
    String linkRequestSource = '',
  }) async {
    if (!isNasMode) return false;
    final updated = member.copyWith(updatedAt: DateTime.now());
    return _saveOne(
      updated,
      linkRequestSource: linkRequestSource,
      corps: corps,
      by: by,
    );
  }

  /// 제한 없이 원본 1건 조회(관리자 토글용).
  Member? rawById(String id) => _rawById(id);

  /// 로컬 캐시만 갱신(서버 반영은 별도). revision 증가로 UI 갱신.
  void saveLocalOnly(Member member) {
    final updated = member.copyWith(updatedAt: DateTime.now());
    if (isMemory) {
      _mem![updated.id] = updated.toMap();
    } else {
      _box!.put(updated.id, updated.toMap());
    }
    revision.value++;
  }

  /// 여러 회원을 **로컬 캐시에만** 일괄 반영한다(서버 저장 없음).
  ///  · `saveLocalOnly` 를 반복 호출하면 `_unscopedCache` 무효화가 누락돼
  ///    목록·개인정보 화면이 옛 값을 계속 보여준다. `_putAll` 은 캐시를
  ///    무효화하므로 일괄 반영은 반드시 이 경로를 쓴다.
  ///  · revision 은 1회만 올려 불필요한 리빌드를 막는다.
  Future<void> saveLocalOnlyAll(List<Member> members) async {
    if (members.isEmpty) return;
    final batch = <String, Map<String, dynamic>>{
      for (final m in members) m.id: m.toMap(),
    };
    await _putAll(batch);
    revision.value++;
  }

  /// 단일 인가자만 NAS에 부분 저장 (전체 DB 덮어쓰기 방지)
  Future<bool> _saveOne(
    Member member, {
    String linkRequestSource = '',
    String corps = '',
    String by = 'personal',
  }) async {
    final api = nas;
    if (api == null) return false;
    try {
      syncStatus.value = 'saving';
      final res = await api.saveMember(
        member,
        by: by,
        linkRequestSource: linkRequestSource,
        corps: corps,
      );
      if (res['ok'] == true) {
        final meta = (res['meta'] as Map?)?.cast<String, dynamic>();
        if (meta != null) serverMeta.value = meta;
        syncStatus.value = 'saved';
        return true;
      }
      syncStatus.value = 'error';
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('saveOne failed: $e');
      syncStatus.value = 'error';
      return false;
    }
  }

  Future<void> addNew(Member member) => save(member);

  Future<void> delete(String id) async {
    await _deleteKey(id);
    revision.value++;
    // 개인 접근에서는 전체 DB 덮어쓰기를 유발하는 일괄 동기화 금지
    if (isNasMode && !isRestricted) unawaited(syncToNas(by: 'app'));
  }

  Future<int> nextNumber() async {
    int max = 0;
    for (final v in _values) {
      final n = Member.fromMap(v).numberInt;
      if (n > max) max = n;
    }
    return max + 1;
  }

  Future<void> replaceAll(List<Member> members) async {
    await _clearAll();
    final batch = {for (final m in members) m.id: m.toMap()};
    await _putAll(batch);
    if (!isMemory) {
      await _meta!.put('seeded_v1', true);
    }
    revision.value++;
    if (isNasMode && !isRestricted) unawaited(syncToNas(by: 'restore'));
  }
}
