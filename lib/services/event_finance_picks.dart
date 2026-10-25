/// 행사 재무(참가비·후원·지출) 행의 **출력 포함 여부** 관리.
///
/// ## 요구사항
/// "행사관리에서, 후원, 수품, 지출 등의 항목에 자료 추가할 수 있도록 해주고,
///  출력시 포함여부를 선택할 수 있도록 해줘"
///
/// 두 번째 요구 — 출력할 항목만 골라서 인쇄/저장한다.
///  · 기본값은 **전부 포함**(체크 안 된 state 를 따로 두지 않는다).
///  · 사용자가 하나라도 해제하면 그때부터 '선택 출력' 모드로 동작한다.
///  · 순수 Dart(Flutter 의존 없음) → `dart run tool/verify_picks.dart` 로 검증.
library;

/// 재무 탭 종류 — 참가비 / 후원·기타수입 / 행사비지출.
enum FinanceKind {
  fee,
  donation,
  expense;

  /// 서버 저장 kind ('expense' 만 별도, 나머지는 'fee' 로 저장되고 category 로 구분).
  String get saveKind => this == FinanceKind.expense ? 'expense' : 'fee';

  String get apiKey => switch (this) {
    FinanceKind.fee => 'fee',
    FinanceKind.donation => 'donation',
    FinanceKind.expense => 'expense',
  };

  String get title => switch (this) {
    FinanceKind.fee => '참가비 납부자',
    FinanceKind.donation => '후원 · 기타수입',
    FinanceKind.expense => '행사비 지출내역',
  };

  static FinanceKind fromKey(String k) => switch (k) {
    'expense' => FinanceKind.expense,
    'donation' => FinanceKind.donation,
    _ => FinanceKind.fee,
  };
}

/// 한 재무 탭의 행 선택 상태.
class FinancePickSet {
  FinancePickSet();

  /// **제외된** 행 id 집합. (기본 = 비어 있음 = 전부 포함)
  final Set<String> _excluded = {};

  /// 사용자가 선택 UI 를 건드렸는지(안내 문구 노출용).
  bool get isFiltered => _excluded.isNotEmpty;

  bool contains(String id) => !_excluded.contains(id);

  int get excludedCount => _excluded.length;

  /// 포함/제외 뒤집기. 반환값 = 뒤집은 뒤 '포함'인지.
  bool toggle(String id) {
    if (_excluded.contains(id)) {
      _excluded.remove(id);
      return true;
    }
    _excluded.add(id);
    return false;
  }

  void excludeAll(Iterable<String> ids) => _excluded.addAll(ids);

  void includeAll() => _excluded.clear();

  /// 포함된 id 만 골라낸다.
  Set<String> includedOf(Iterable<String> ids) =>
      ids.where((id) => !_excluded.contains(id)).toSet();

  /// 행 목록을 포함된 것만 남긴다. (`'id'` 없는 행은 항상 포함)
  List<Map<String, dynamic>> filter(List<Map<String, dynamic>> rows) => [
    for (final r in rows)
      if (contains(rowId(r))) r,
  ];

  /// 행의 안정적인 식별자. id 가 없으면(구資料) 위치 대신 내용 기반 키를 쓴다.
  static String rowId(Map<String, dynamic> r) {
    final id = '${r['id'] ?? ''}'.trim();
    if (id.isNotEmpty) return id;
    return 'k_${r['date'] ?? ''}_${r['name'] ?? ''}_${r['amount'] ?? ''}';
  }

  /// 목록의 모든 id.
  static List<String> idsOf(List<Map<String, dynamic>> rows) =>
      [for (final r in rows) rowId(r)];

  /// 선택 상태를 다른 목록에도 안전하게 맞춘다(사라진 id 정리).
  void prune(Iterable<String> liveIds) {
    final live = liveIds.toSet();
    _excluded.removeWhere((id) => !live.contains(id));
  }

  /// 복사(출력 시점 스냅샷).
  FinancePickSet copy() => FinancePickSet().._excluded.addAll(_excluded);
}
