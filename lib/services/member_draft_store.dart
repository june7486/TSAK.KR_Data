import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 회원정보 편집 중인 내용을 자동으로 임시저장(초안)해 두는 로컬 저장소.
///
/// · 저장 위치: 기기 로컬(shared_preferences) — 서버/개인정보와 분리 보관.
/// · 목적: 작성 중 창을 닫거나 저장하지 못한 경우에도 내용을 잃지 않도록.
/// · 관리자·마스터는 [MemberDraftsScreen] 에서 임시저장 항목을 조회·복원할 수 있다.
class MemberDraftStore {
  static const _prefix = 'tsak.member.draft.v1.';
  static const _indexKey = 'tsak.member.draft.v1.index';

  /// 초안 1건 — 폼 스냅샷 + 요약 메타.
  static Future<void> save({
    required String key,
    required Map<String, dynamic> form,
    required String memberId,
    required bool isNew,
    required String name,
    required String number,
    required String savedBy,
  }) async {
    final p = await SharedPreferences.getInstance();
    final rec = <String, dynamic>{
      'key': key,
      'memberId': memberId,
      'isNew': isNew,
      'name': name,
      'number': number,
      'savedBy': savedBy,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'form': form,
    };
    await p.setString('$_prefix$key', json.encode(rec));
    final idx = (p.getStringList(_indexKey) ?? <String>[]).toList();
    if (!idx.contains(key)) idx.add(key);
    await p.setStringList(_indexKey, idx);
  }

  /// 초안 1건 조회. 없으면 null.
  static Future<MemberDraft?> get(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) return null;
    try {
      return MemberDraft.fromMap(json.decode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  /// 초안 존재 여부.
  static Future<bool> exists(String key) async {
    final p = await SharedPreferences.getInstance();
    return (p.getString('$_prefix$key') ?? '').isNotEmpty;
  }

  /// 초안 1건 삭제.
  static Future<void> delete(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('$_prefix$key');
    final idx = (p.getStringList(_indexKey) ?? <String>[]).toList();
    idx.remove(key);
    await p.setStringList(_indexKey, idx);
  }

  /// 모든 초안 목록(최근 저장순).
  static Future<List<MemberDraft>> list() async {
    final p = await SharedPreferences.getInstance();
    final idx = p.getStringList(_indexKey) ?? <String>[];
    final out = <MemberDraft>[];
    final valid = <String>[];
    for (final k in idx) {
      final raw = p.getString('$_prefix$k');
      if (raw == null || raw.isEmpty) continue;
      try {
        out.add(MemberDraft.fromMap(json.decode(raw) as Map));
        valid.add(k);
      } catch (_) {}
    }
    // 끊긴 인덱스 정리.
    if (valid.length != idx.length) {
      await p.setStringList(_indexKey, valid);
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  /// 특정 회원의 초안 키.
  static String keyForMember(String memberId) => 'id:$memberId';

  /// 신규(추가) 초안 키 — 신규는 1건만 유지.
  static const newKey = 'new';
}

/// 임시저장 초안 데이터.
class MemberDraft {
  MemberDraft({
    required this.key,
    required this.memberId,
    required this.isNew,
    required this.name,
    required this.number,
    required this.savedBy,
    required this.savedAt,
    required this.form,
  });

  final String key;
  final String memberId;
  final bool isNew;
  final String name;
  final String number;
  final String savedBy;
  final int savedAt;
  final Map<String, dynamic> form;

  DateTime get savedAtDate => DateTime.fromMillisecondsSinceEpoch(savedAt);

  /// 표시용 이름 — 이름이 없으면 '(이름 없음)'.
  String get displayName => name.trim().isEmpty ? '(이름 없음)' : name.trim();

  /// 표시용 시각 — 'MM-DD HH:MM'.
  String get savedAtLabel {
    final d = savedAtDate;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static MemberDraft fromMap(Map m) {
    return MemberDraft(
      key: '${m['key'] ?? ''}',
      memberId: '${m['memberId'] ?? ''}',
      isNew: m['isNew'] == true,
      name: '${m['name'] ?? ''}',
      number: '${m['number'] ?? ''}',
      savedBy: '${m['savedBy'] ?? ''}',
      savedAt: (m['savedAt'] is int)
          ? m['savedAt'] as int
          : int.tryParse('${m['savedAt']}') ?? 0,
      form: (m['form'] is Map)
          ? (m['form'] as Map).cast<String, dynamic>()
          : <String, dynamic>{},
    );
  }
}
