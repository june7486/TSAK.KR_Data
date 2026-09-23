import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';

import '../models/member.dart';

/// 인가자 데이터 저장소
///
/// - 기본(Hive): 앱 첫 실행 시 assets/data/members_seed.json (2,186명) 자동 로드 후 로컬 영구 저장
/// - 인메모리: 테스트용 (Hive 불필요)
class MemberRepository {
  static const String boxName = 'members_box';
  static const String metaBoxName = 'meta_box';

  Box? _box;
  Box? _meta;

  /// 인메모리 저장소 (테스트용)
  final Map<String, Map<String, dynamic>>? _mem;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Hive 기반 (프로덕션)
  MemberRepository() : _mem = null;

  /// 인메모리 기반 (테스트/미리보기)
  MemberRepository.memory() : _mem = <String, Map<String, dynamic>>{};

  bool get isMemory => _mem != null;

  Future<void> init() async {
    if (isMemory) {
      revision.value++;
      return;
    }
    await Hive.initFlutter();
    _box = await Hive.openBox(boxName);
    _meta = await Hive.openBox(metaBoxName);

    // v2: ATAS 인가번호(atASNo) 포함 시드 — 버전을 올려 기존 저장소도 재시딩
    final seeded = _meta!.get('seeded_v2', defaultValue: false) as bool;
    if (!seeded || _box!.isEmpty) {
      await _seedFromAssets();
      await _meta!.put('seeded_v2', true);
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

  int get count => isMemory ? _mem!.length : _box!.length;

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
    final list = _values.map((v) => Member.fromMap(v)).toList();
    list.sort((a, b) => a.numberInt.compareTo(b.numberInt));
    return list;
  }

  Member? byId(String id) {
    if (isMemory) {
      final v = _mem![id];
      return v == null ? null : Member.fromMap(v);
    }
    final v = _box!.get(id);
    if (v == null) return null;
    return Member.fromMap(v as Map);
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
    for (final v in _values) {
      final m = Member.fromMap(v);
      final key = m.league.trim().isEmpty ? '(미지정)' : m.league.trim();
      map[key] = (map[key] ?? 0) + 1;
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

  Future<void> save(Member member) async {
    final updated = member.copyWith(updatedAt: DateTime.now());
    await _put(updated.id, updated.toMap());
    revision.value++;
  }

  Future<void> addNew(Member member) => save(member);

  Future<void> delete(String id) async {
    await _deleteKey(id);
    revision.value++;
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
  }
}
