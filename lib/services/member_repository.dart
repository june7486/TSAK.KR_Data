import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';

import '../models/member.dart';

/// 인가자 데이터 저장소 (Hive 기반, Map 저장 방식으로 최대 호환성 확보)
///
/// - 앱 첫 실행 시 assets/data/members_seed.json (2,186명) 자동 로드
/// - 이후 사용자가 추가/수정한 내용은 로컬에 영구 저장
class MemberRepository {
  static const String boxName = 'members_box';
  static const String metaBoxName = 'meta_box';

  late Box _box;
  late Box _meta;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(boxName);
    _meta = await Hive.openBox(metaBoxName);

    final seeded = _meta.get('seeded_v1', defaultValue: false) as bool;
    if (!seeded || _box.isEmpty) {
      await _seedFromAssets();
      await _meta.put('seeded_v1', true);
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
          date: '${m['date'] ?? ''}',
          phone: '${m['phone'] ?? ''}',
          memo: '${m['memo'] ?? ''}',
        );
        batch[member.id] = member.toMap();
      }
      await _box.putAll(batch);
      if (kDebugMode) debugPrint('Seeded ${batch.length} members');
    } catch (e) {
      if (kDebugMode) debugPrint('Seeding failed: $e');
    }
  }

  /// 전체 목록 (인가번호 순 정렬)
  List<Member> all() {
    final list = _box.values.map((v) => Member.fromMap(v as Map)).toList();
    list.sort((a, b) => a.numberInt.compareTo(b.numberInt));
    return list;
  }

  int get count => _box.length;

  Member? byId(String id) {
    final v = _box.get(id);
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

  /// 전체 연맹 목록 (인원순)
  Map<String, int> leaguesWithCount() {
    final map = <String, int>{};
    for (final v in _box.values) {
      final m = Member.fromMap(v as Map);
      final key = m.league.trim().isEmpty ? '(미지정)' : m.league.trim();
      map[key] = (map[key] ?? 0) + 1;
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in entries) e.key: e.value};
  }

  /// 전체 회비 납부 연도 목록 (내림차순)
  List<String> feeYearOptions() {
    final years = <String>{'2024', '2025', '2026', '2027'};
    for (final v in _box.values) {
      final m = Member.fromMap(v as Map);
      years.addAll(m.feeYears.keys);
    }
    final list = years.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// 전체 행사 목록
  List<String> eventOptions() {
    final events = <String>{};
    for (final v in _box.values) {
      final m = Member.fromMap(v as Map);
      events.addAll(m.eventAttend.keys);
    }
    final list = events.toList()..sort();
    return list;
  }

  Future<void> save(Member member) async {
    final updated = member.copyWith(updatedAt: DateTime.now());
    await _box.put(updated.id, updated.toMap());
    revision.value++;
  }

  Future<void> addNew(Member member) async {
    await save(member);
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
    revision.value++;
  }

  Future<int> nextNumber() async {
    int max = 0;
    for (final v in _box.values) {
      final n = Member.fromMap(v as Map).numberInt;
      if (n > max) max = n;
    }
    return max + 1;
  }

  /// 외부 데이터 일괄 반영 (복원/가져오기)
  Future<void> replaceAll(List<Member> members) async {
    await _box.clear();
    final batch = {for (final m in members) m.id: m.toMap()};
    await _box.putAll(batch);
    await _meta.put('seeded_v1', true);
    revision.value++;
  }
}
