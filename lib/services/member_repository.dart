import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';

import '../models/member.dart';
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
  final ValueNotifier<String> syncStatus =
      ValueNotifier<String>(''); // '', 'saving', 'saved', 'error', 'offline'

  /// Hive 기반 (프로덕션, 오프라인 전용)
  MemberRepository({this.nas})
      : _mem = nas != null ? <String, Map<String, dynamic>>{} : null;

  /// 인메모리 기반 (테스트/미리보기)
  MemberRepository.memory({this.nas})
      : _mem = <String, Map<String, dynamic>>{};

  bool get isMemory => _mem != null;
  bool get isNasMode => nas != null;

  /// NAS 최신 데이터 로드. 성공 시 true.
  Future<bool> syncFromNas() async {
    final api = nas;
    if (api == null) return false;
    try {
      syncStatus.value = 'saving';
      final members = await api.fetchMembers();
      if (members.isEmpty) {
        syncStatus.value = 'error';
        return false;
      }
      final batch = {for (final m in members) m.id: m.toMap()};
      final mem = _mem;
      if (mem != null) {
        mem.clear();
        mem.addAll(batch);
      } else {
        await _box!.clear();
        await _box!.putAll(batch);
      }
      try {
        final meta = await api.fetchMeta();
        serverMeta.value = meta;
      } catch (_) {}
      syncStatus.value = 'saved';
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
      // NAS 실패 시 로컬/시드로 폴백
    }

    if (!isMemory) {
      final seeded = _meta!.get('seeded_v2', defaultValue: false) as bool;
      if (!seeded || _box!.isEmpty) {
        await _seedFromAssets();
        await _meta!.put('seeded_v2', true);
      }
    } else if (_mem!.isEmpty && !isNasMode) {
      await _seedFromAssets();
    }
    revision.value++;
  }

  Future<void> _seedFromAssets() async {
    try {
      final raw = await rootBundle.loadString('assets/data/members_seed.json');
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      final batch = <String, Map<String, dynamic>>{};
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final member = Member(
          id: '${m['id']}',
          number: '${m['number'] ?? ''}',
          name: '${m['name'] ?? ''}',
          league: '${m['league'] ?? ''}',
          unit: '${m['unit'] ?? ''}',
          address: '${m['address'] ?? ''}',
          phone: '${m['phone'] ?? ''}',
          email: '${m['email'] ?? ''}',
          date: '${m['date'] ?? ''}',
          atasNo: '${m['atasNo'] ?? ''}',
          activity: '${m['activity'] ?? ''}',
          memo: '${m['memo'] ?? ''}',
        );
        batch[member.id] = member.toMap();
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

  int get count => isRestricted ? all().length : (isMemory ? _mem!.length : _box!.length);

  Future<void> _put(String id, Map<String, dynamic> map) async {
    if (isMemory) {
      _mem![id] = map;
    } else {
      await _box!.put(id, map);
    }
  }

  Future<void> _putAll(Map<String, Map<String, dynamic>> batch) async {
    if (isMemory) {
      _mem!.addAll(batch);
    } else {
      await _box!.putAll(batch);
    }
  }

  Future<void> _deleteKey(String id) async {
    if (isMemory) {
      _mem!.remove(id);
    } else {
      await _box!.delete(id);
    }
  }

  Future<void> _clearAll() async {
    if (isMemory) {
      _mem!.clear();
    } else {
      await _box!.clear();
    }
  }

  // ---- 공개 API ----
  List<Member> all() {
    final list = _values.map((v) => Member.fromMap(v)).toList()
      ..sort((a, b) => a.numberInt.compareTo(b.numberInt));
    if (isRestricted) {
      final r = restrictedNumber!.replaceAll(RegExp(r'[^0-9]'), '');
      return list
          .where((m) => m.number.replaceAll(RegExp(r'[^0-9]'), '') == r)
          .toList();
    }
    return list;
  }

  /// 제한 없이 전체 목록(관리자/마스터 전용)
  List<Member> allUnscoped() => _values.map((v) => Member.fromMap(v)).toList()
    ..sort((a, b) => a.numberInt.compareTo(b.numberInt));

  Member? byId(String id) {
    if (isRestricted) {
      final m = _rawById(id);
      if (m == null) return null;
      final r = restrictedNumber!.replaceAll(RegExp(r'[^0-9]'), '');
      return m.number.replaceAll(RegExp(r'[^0-9]'), '') == r ? m : null;
    }
    return _rawById(id);
  }

  Member? _rawById(String id) {
    if (isMemory) {
      final v = _mem![id];
      return v == null ? null : Member.fromMap(v);
    }
    final v = _box!.get(id);
    if (v == null) return null;
    return Member.fromMap(v as Map);
  }

  Member? byNumber(String number) {
    final n = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (n.isEmpty) return null;
    if (isRestricted &&
        n != restrictedNumber!.replaceAll(RegExp(r'[^0-9]'), '')) {
      return null; // 개인 접근: 본인 외 접근 차단
    }
    for (final m in all()) {
      if (m.number.replaceAll(RegExp(r'[^0-9]'), '') == n) return m;
    }
    return null;
  }

  List<Member> search(String query, {String? league, String? year}) {
    final q = query.trim().toLowerCase();
    var list = all();
    if (league != null && league.isNotEmpty) {
      list = list.where((m) => m.league == league).toList();
    }
    if (year != null && year.isNotEmpty) {
      list = list.where((m) => m.feeYears[year] == true).toList();
    }
    if (q.isNotEmpty) {
      list = list.where((m) => m.searchText.contains(q)).toList();
    }
    return list;
  }

  Map<String, int> leaguesWithCount() {
    final map = <String, int>{};
    for (final m in all()) {
      final key = m.league.trim().isEmpty ? '(미지정)' : m.league.trim();
      map[key] = (map[key] ?? 0) + 1;
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

  Future<void> save(Member member, {bool syncing = true}) async {
    final updated = member.copyWith(updatedAt: DateTime.now());
    await _put(updated.id, updated.toMap());
    revision.value++;
    if (syncing && isNasMode) {
      if (isRestricted) {
        unawaited(_saveOne(updated)); // 개인 접근: 본인 1건만 부분 저장
      } else {
        unawaited(syncToNas(by: 'app'));
      }
    }
  }

  /// 단일 인가자만 NAS에 부분 저장 (전체 DB 덮어쓰기 방지)
  Future<bool> _saveOne(Member member) async {
    final api = nas;
    if (api == null) return false;
    try {
      syncStatus.value = 'saving';
      final res = await api.saveMember(member, by: 'personal');
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
