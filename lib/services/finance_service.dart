import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/finance_transaction.dart';
import '../models/member.dart';
import 'nas_api.dart';

/// 재무 데이터 서비스
///
/// - NAS에 저장된 finance.json(거래내역)을 로드/저장
/// - 입금자 텍스트에서 이름/인가번호/행사명을 인식해 동일인으로 분류(자동매칭)
/// - 연도별·인가자별·행사별·분류별 집계 및 그래프 데이터 제공
/// - 오프라인/미리보기에서도 동일 로직으로 동작(로컬 매칭 엔진)
class FinanceService extends ChangeNotifier {
  FinanceService(this.nas);

  final NasApi nas;

  List<FinanceTransaction> _tx = [];

  /// 삭제 예약 id — 저장 시 서버에 deletedIds 로 전달(전체 교체 대신).
  final Set<String> _deletedIds = {};
  List<String> _incomeCats = ['후원', '수품구매', '참가비', '연회비', '평생회비', '기타'];
  List<String> _expenseCats = ['행사비', '운영비', '수품구매', '후원금집행', '기타'];
  Map<String, String> _aliases = {}; // 입금자 별칭 → 인가번호
  Map<String, String> _eventRules = {}; // 행사명 키워드 → 분류
  Map<String, dynamic> _stats = {}; // 서버 종합 통계 캐시
  String? _updated;
  int _version = 0;
  bool _loading = false;
  String _status = ''; // '', 'loading', 'saved', 'error', 'offline'

  List<FinanceTransaction> get transactions => _tx;
  List<String> get incomeCategories => _incomeCats;
  List<String> get expenseCategories => _expenseCats;
  Map<String, String> get aliases => _aliases;
  Map<String, String> get eventRules => _eventRules;
  Map<String, dynamic> get serverStats => _stats;
  String? get updated => _updated;
  int get version => _version;
  bool get loading => _loading;
  String get status => _status;

  // ---------------------------------------------------------------------------
  //  로드 / 저장
  // ---------------------------------------------------------------------------
  Future<void> load() async {
    _loading = true;
    _status = 'loading';
    notifyListeners();
    try {
      final raw = await nas.fetchFinance();
      // ⚠️ [버그 수정 2026-10-26] 응답 봉투(envelope)를 풀지 않고 넘기고 있었다.
      //
      //  `/api/finance` 의 응답은 `{"ok":true, "finance":{...}}` 인데
      //  종전 코드는 `_apply(raw)` 로 **봉투째** 넘겼다. `_apply()` 는
      //  `fin['transactions']` 를 찾으므로 항상 null → `_tx` 는 영원히 빈 목록.
      //  결과: 개인카드의 '후원금·후원물품 이력' 이 행사에서 후원을 등록해도
      //  **항상 0건 / 0원** 으로 남았다(실측: 이승준 #415, 이항복 #75).
      //  재무관리 화면은 자체적으로 `r['finance']` 를 풀어 쓰기 때문에 정상으로
      //  보였고, 그래서 이 버그가 오래 숨어 있었다.
      //
      //  `save()` 는 이미 `r['finance']` 로 올바르게 풀고 있다(아래 참조).
      //  load() 만 봉투를 풀지 않았던 것이 원인이므로 동일한 방식으로 맞춘다.
      //  혹시 서버가 봉투 없이 바로 주는 경우(구버전/목업)도 있으므로
      //  `finance` 키가 없으면 원본을 그대로 쓴다(방어적).
      final wrapped = raw['finance'];
      final fin = (wrapped is Map)
          ? wrapped.cast<String, dynamic>()
          : raw;
      _apply(fin);
      try {
        final r = await nas.fetchRules();
        final rr = r['rules'];
        if (rr is Map) {
          _aliases = _asStringMap(rr['aliases']);
          _eventRules = _asStringMap(rr['events']);
        }
      } catch (_) {}
      try {
        _stats = await nas.fetchFinanceStats();
      } catch (_) {}
      _status = 'saved';
    } catch (e) {
      if (kDebugMode) debugPrint('finance load failed: $e');
      _status = 'offline';
    }
    _loading = false;
    notifyListeners();
  }

  void _apply(Map<String, dynamic> fin) {
    final list = fin['transactions'];
    if (list is List) {
      final server = list
          .map((e) => FinanceTransaction.fromMap(e as Map))
          .toList();
      final serverIds = {for (final t in server) t.id};
      // 서버 값 기준으로 병합 — 로컬에만 있고 삭제 예약도 아닌 거래는 보존
      //  (전체 교체/스코핑으로 응답에서 빠져도 소실되지 않게).
      final keepLocal = _tx
          .where(
            (t) =>
                t.id.isNotEmpty &&
                !serverIds.contains(t.id) &&
                !_deletedIds.contains(t.id),
          )
          .toList();
      _tx = [...server, ...keepLocal];
    }
    if (fin['income_categories'] is List) {
      _incomeCats = (fin['income_categories'] as List)
          .map((e) => '$e')
          .toList();
    }
    if (fin['expense_categories'] is List) {
      _expenseCats = (fin['expense_categories'] as List)
          .map((e) => '$e')
          .toList();
    }
    _updated = fin['updated']?.toString();
    _version = (fin['version'] is num) ? (fin['version'] as num).toInt() : 0;
  }

  static Map<String, String> _asStringMap(dynamic v) {
    final out = <String, String>{};
    if (v is Map) v.forEach((k, val) => out['$k'] = '$val');
    return out;
  }

  Future<bool> save() async {
    _status = 'loading';
    notifyListeners();
    try {
      final r = await nas.saveFinance({
        'transactions': _tx.map((t) => t.toMap()).toList(),
        'income_categories': _incomeCats,
        'expense_categories': _expenseCats,
        // 명시적 삭제만 서버에서 제거(빈 덮어쓰기로 인한 소실 방지).
        'deletedIds': _deletedIds.toList(),
      });
      _deletedIds.clear();
      final fin = r['finance'];
      if (fin is Map) _apply(fin.cast<String, dynamic>());
      _status = 'saved';
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('finance save failed: $e');
      _status = 'error';
      notifyListeners();
      return false;
    }
  }

  Future<void> saveRules() async {
    try {
      await nas.saveRules({'aliases': _aliases, 'events': _eventRules});
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  //  거래 CRUD (로컬 조작 후 save() 호출)
  // ---------------------------------------------------------------------------
  void addTransaction(FinanceTransaction t) {
    if (t.id.isEmpty) {
      t.id = 'tx_${DateTime.now().millisecondsSinceEpoch}_${_tx.length}';
    }
    if (t.year.isEmpty) t.year = _yearOf(t.date);
    _tx.insert(0, t);
    notifyListeners();
  }

  void updateTransaction(FinanceTransaction t) {
    final i = _tx.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      _tx[i] = t;
      notifyListeners();
    }
  }

  void removeTransaction(String id) {
    _tx.removeWhere((e) => e.id == id);
    if (id.isNotEmpty) _deletedIds.add(id);
    notifyListeners();
  }

  void clearAll() {
    _tx = [];
    notifyListeners();
  }

  static String _yearOf(String date) =>
      RegExp(r'(20\d{2})').firstMatch(date)?.group(1) ?? '';

  // ---------------------------------------------------------------------------
  //  자동 매칭 엔진 (서버 _classify 와 동일 로직)
  //  입금자 텍스트에서 이름 앞뒤 내용을 무시하고 이름/번호/행사명을 인식한다.
  // ---------------------------------------------------------------------------
  ClassifiedRow classify(
    Map<String, dynamic> raw, {
    required List<Member> members,
  }) {
    final payer = '${raw['payer'] ?? raw['name'] ?? ''}'.trim();
    final memo = '${raw['memo'] ?? ''}'.trim();
    final date = '${raw['date'] ?? ''}'.trim();
    final amount = _parseAmount(raw['amount']);
    var number = '${raw['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final ctx = <String>[];
    var matchedNo = '';
    var matchedName = '';
    var matchedId = '';

    // 1) 별칭 규칙 우선
    for (final entry in _aliases.entries) {
      if (entry.key.isNotEmpty && payer.contains(entry.key)) {
        matchedNo = entry.value.replaceAll(RegExp(r'[^0-9]'), '');
        if (entry.key != raw['name']) ctx.add('별칭:${entry.key}');
        break;
      }
    }

    // 2) 명시 번호
    if (matchedNo.isEmpty && number.isNotEmpty) {
      for (final m in members) {
        if (m.number.replaceAll(RegExp(r'[^0-9]'), '') == number) {
          matchedNo = number;
          matchedName = m.name;
          matchedId = m.id;
          break;
        }
      }
      if (matchedNo.isEmpty) ctx.add('번호:$number(미등록)');
    }

    // 3) 이름 검색 (앞뒤 텍스트 무시)
    if (matchedNo.isEmpty && payer.isNotEmpty) {
      Member? best;
      for (final m in members) {
        final mn = m.name.trim();
        if (mn.length >= 2 && payer.contains(mn)) {
          if (best == null || mn.length > best.name.trim().length) best = m;
        }
      }
      if (best != null) {
        matchedNo = best.number.replaceAll(RegExp(r'[^0-9]'), '');
        matchedName = best.name;
        matchedId = best.id;
        final residue = payer
            .replaceAll(matchedName, '')
            .replaceAll(RegExp(r'^[\s\-·,_/()\[\]]+|[\s\-·,_/()\[\]]+$'), '');
        if (residue.isNotEmpty) ctx.add(residue);
      }
    }

    // 행사명
    final event = '${raw['event'] ?? ''}'.trim();
    if (event.isNotEmpty) ctx.add(event);

    final category = _guessCategory('$memo $payer $event', amount);

    return ClassifiedRow(
      date: date,
      payer: payer,
      name: '${raw['name'] ?? ''}'.isNotEmpty
          ? '${raw['name']}'
          : (matchedName.isNotEmpty ? matchedName : payer),
      number: matchedNo,
      memberId: matchedId,
      matchedName: matchedName,
      amount: amount,
      category: category,
      memo: memo,
      event: event,
      context: ctx.where((e) => e.isNotEmpty).join(' / '),
      status: matchedNo.isNotEmpty ? 'matched' : 'unmatched',
    );
  }

  String _guessCategory(String text, int amount) {
    for (final e in _eventRules.entries) {
      if (e.key.isNotEmpty && text.contains(e.key)) return e.value;
    }
    const table = {
      '후원': '후원',
      '찬조': '후원',
      '기부': '후원',
      '수품': '수품구매',
      '구매': '수품구매',
      '물품': '수품구매',
      '참가비': '참가비',
      '참가': '참가비',
      '행사비': '참가비',
      '연회비': '연회비',
      '회비': '연회비',
    };
    for (final e in table.entries) {
      if (text.contains(e.key)) return e.value;
    }
    return amount >= 0 ? '후원' : '기타';
  }

  int _parseAmount(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.round();
    final s = '$v'.replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(s) ?? 0;
  }

  /// 분류 결과 일괄 → 거래 목록에 추가(저장은 호출측에서)
  List<FinanceTransaction> commitClassified(List<ClassifiedRow> rows) {
    final added = <FinanceTransaction>[];
    for (final r in rows) {
      final t = FinanceTransaction(
        id: 'tx_${DateTime.now().microsecondsSinceEpoch}_${_tx.length}',
        date: r.date,
        type: r.type == 'expense' ? 'expense' : 'income',
        payer: r.payer,
        name: r.name,
        number: r.number,
        memberId: r.memberId,
        amount: r.amount,
        category: r.category,
        event: r.event,
        context: r.context,
        memo: r.sheet.isNotEmpty ? '${r.memo} [탭:${r.sheet}]' : r.memo,
        status: r.status,
        year: _yearOf(r.date),
        source: 'bank',
      );
      _tx.insert(0, t);
      added.add(t);
    }
    notifyListeners();
    return added;
  }

  // ---------------------------------------------------------------------------
  //  집계 / 통계
  // ---------------------------------------------------------------------------
  List<FinanceTransaction> incomeOf([String? category]) => _tx
      .where(
        (t) => !t.isExpense && (category == null || t.category == category),
      )
      .toList();

  List<FinanceTransaction> expenseList() =>
      _tx.where((t) => t.isExpense).toList();

  /// 인가번호별 입금 집계
  Map<String, MemberDepositSummary> memberSummaries(
    Map<String, Member> byNumber,
  ) {
    final map = <String, MemberDepositSummary>{};
    for (final t in _tx) {
      if (t.isExpense) continue;
      final no = t.number.replaceAll(RegExp(r'[^0-9]'), '');
      if (no.isEmpty) continue;
      final s = map.putIfAbsent(
        no,
        () => MemberDepositSummary(
          number: no,
          name: byNumber[no]?.name ?? t.name,
        ),
      );
      s.total += t.amount;
      s.byCategory[t.category] = (s.byCategory[t.category] ?? 0) + t.amount;
      final y = t.year.isEmpty ? '미지정' : t.year;
      s.byYear[y] = (s.byYear[y] ?? 0) + t.amount;
      s.history.add(t);
    }
    for (final s in map.values) {
      s.history.sort((a, b) => b.date.compareTo(a.date));
    }
    return map;
  }

  /// 특정 인가번호의 입금 내역.
  ///
  /// ## [버그 수정 2026-10-29] 범 75호와 은하 G75 가 섞이던 문제
  ///
  /// 종전에는 번호에서 숫자만 뽑아 비교했다(`G75` → `75`). 그래서
  /// 은하 G75(김건우)의 개인카드에 범 75호(이항복)의 후원이 그대로
  /// 표시됐다. 두 번호 공간은 실제로 겹친다(둘 다 1~165).
  ///
  /// 수정: **(소속, 번호)** 두 값으로 판정한다.
  ///   · `corps` 가 채워진 거래 → 소속까지 일치해야 인정.
  ///   · `corps` 가 비어 있는 레거시 거래 → 번호 표기(`G75`)로 소속을 추정해
  ///     비교한다(모르는 채로 남의 내역을 보여 주는 것보다 안전).
  ///
  /// [corps] 를 넘기지 않으면 종전과 같이 숫자만 비교한다(하위호환).
  List<FinanceTransaction> depositsOf(String number, {String? corps}) {
    if (corps == null) {
      final no = number.replaceAll(RegExp(r'[^0-9]'), '');
      return _tx
          .where(
            (t) => !t.isExpense &&
                t.number.replaceAll(RegExp(r'[^0-9]'), '') == no,
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    }
    final wantNo = number.replaceAll(RegExp(r'[^0-9]'), '');
    final wantCorps = corps == 'eunha' ? 'eunha' : 'tsak';
    return _tx
        .where((t) {
          if (t.isExpense) return false;
          if (t.number.replaceAll(RegExp(r'[^0-9]'), '') != wantNo) {
            return false;
          }
          // 소속 판정 — 서버값 우선, 없으면 번호 표기로 추정.
          final c = FinanceTransaction.inferCorps(t.number, t.corps);
          return c == wantCorps;
        })
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// 연도 목록(내림차순)
  List<String> years() {
    final s = <String>{};
    for (final t in _tx) {
      final y = t.year.isEmpty ? _yearOf(t.date) : t.year;
      if (y.isNotEmpty) s.add(y);
    }
    final list = s.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// 연도별 수입/지출 집계
  YearStat yearStat(String year) {
    var income = 0, expense = 0;
    final byCat = <String, int>{};
    final byMember = <String, int>{};
    final byMonth = <String, int>{};
    for (final t in _tx) {
      final y = t.year.isEmpty ? _yearOf(t.date) : t.year;
      if (y != year) continue;
      if (t.isExpense) {
        expense += t.amount;
      } else {
        income += t.amount;
        byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
        final no = t.number.replaceAll(RegExp(r'[^0-9]'), '');
        if (no.isNotEmpty) byMember[no] = (byMember[no] ?? 0) + t.amount;
      }
      final mo = RegExp(
        r'20\d{2}[.\-/]?(\d{1,2})',
      ).firstMatch(t.date)?.group(1)?.padLeft(2, '0');
      if (mo != null) byMonth[mo] = (byMonth[mo] ?? 0) + t.amount;
    }
    return YearStat(
      year: year,
      income: income,
      expense: expense,
      byCategory: byCat,
      byMember: byMember,
      byMonth: byMonth,
    );
  }

  /// 분류별 총액 (수입)
  Map<String, int> categoryTotals() {
    final m = <String, int>{};
    for (final t in _tx) {
      if (t.isExpense) continue;
      m[t.category] = (m[t.category] ?? 0) + t.amount;
    }
    return m;
  }

  Map<String, int> expenseCategoryTotals() {
    final m = <String, int>{};
    for (final t in _tx) {
      if (!t.isExpense) continue;
      m[t.category] = (m[t.category] ?? 0) + t.amount;
    }
    return m;
  }

  /// 행사별 결산 (수입 - 지출)
  List<EventSettlement> eventSettlements() {
    final m = <String, EventSettlement>{};
    for (final t in _tx) {
      final key = t.event.trim().isNotEmpty ? t.event.trim() : '(행사 미지정)';
      final s = m.putIfAbsent(key, () => EventSettlement(event: key));
      if (t.isExpense) {
        s.expense += t.amount;
      } else {
        s.income += t.amount;
      }
    }
    final list = m.values.toList()
      ..sort((a, b) => b.income.compareTo(a.income));
    return list;
  }

  int get totalIncome =>
      _tx.where((t) => !t.isExpense).fold(0, (s, t) => s + t.amount);
  int get totalExpense =>
      _tx.where((t) => t.isExpense).fold(0, (s, t) => s + t.amount);
  int get balance => totalIncome - totalExpense;

  /// 미매칭 건수
  int get unmatchedCount =>
      _tx.where((t) => !t.isExpense && t.status != 'matched').length;

  // ---------------------------------------------------------------------------
  //  검색 · 통계 (연도별 / 기간별 / 행사별 / 분류별)
  // ---------------------------------------------------------------------------

  /// 서버 통계 재조회(백그라운드 갱신)
  Future<void> refreshStats() async {
    try {
      _stats = await nas.fetchFinanceStats();
      notifyListeners();
    } catch (_) {}
  }

  /// 현재 로드된 거래로부터 로컬 종합 통계 계산(서버 미응답 시 폴백)
  Map<String, dynamic> localStats() {
    final byYear = <String, Map<String, int>>{};
    final byCategory = <String, int>{};
    final byExpenseCategory = <String, int>{};
    final byEvent = <String, Map<String, int>>{};
    final byMonth = <String, Map<String, int>>{};
    var income = 0, expense = 0;
    for (final t in _tx) {
      final y = t.year.isEmpty ? _yearOf(t.date) : t.year;
      final yy = byYear.putIfAbsent(
        y,
        () => {'income': 0, 'expense': 0, 'count': 0},
      );
      yy['count'] = (yy['count'] ?? 0) + 1;
      final mo = _monthOf(t.date);
      if (t.isExpense) {
        expense += t.amount;
        yy['expense'] = (yy['expense'] ?? 0) + t.amount;
        byExpenseCategory[t.category] =
            (byExpenseCategory[t.category] ?? 0) + t.amount;
      } else {
        income += t.amount;
        yy['income'] = (yy['income'] ?? 0) + t.amount;
        byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
      }
      if (mo.isNotEmpty) {
        final mk = '$y-$mo';
        final mm = byMonth.putIfAbsent(mk, () => {'income': 0, 'expense': 0});
        mm[t.isExpense ? 'expense' : 'income'] =
            (mm[t.isExpense ? 'expense' : 'income'] ?? 0) + t.amount;
      }
      final ev = t.event.trim().isEmpty ? '(미지정)' : t.event.trim();
      final er = byEvent.putIfAbsent(ev, () => {'income': 0, 'expense': 0});
      er[t.isExpense ? 'expense' : 'income'] =
          (er[t.isExpense ? 'expense' : 'income'] ?? 0) + t.amount;
    }
    return {
      'total': {
        'income': income,
        'expense': expense,
        'net': income - expense,
        'count': _tx.length,
      },
      'byYear': byYear,
      'byMonth': byMonth,
      'byCategory': byCategory,
      'byExpenseCategory': byExpenseCategory,
      'byEvent': byEvent,
    };
  }

  static String _monthOf(String date) =>
      RegExp(
        r'20\d{2}[.\-/]?(\d{1,2})',
      ).firstMatch(date)?.group(1)?.padLeft(2, '0') ??
      '';

  String get statsUpdated => '${_stats['updated'] ?? _updated ?? ''}';

  /// 기간/행사/분류/유형 복합 검색 — 조건에 맞는 거래 반환
  List<FinanceTransaction> search({
    String? year,
    DateTime? from,
    DateTime? to,
    String? event,
    String? category,
    String? type, // 'income' | 'expense' | null(전체)
    String? keyword,
  }) {
    final kw = (keyword ?? '').trim();
    return _tx.where((t) {
      if (year != null && year != '전체') {
        final y = t.year.isEmpty ? _yearOf(t.date) : t.year;
        if (y != year) return false;
      }
      if (from != null || to != null) {
        final d = _dateOf(t.date);
        if (d != null) {
          if (from != null && d.isBefore(from)) return false;
          if (to != null && d.isAfter(to)) return false;
        }
      }
      if (event != null && event.isNotEmpty && event != '전체') {
        final ev = t.event.trim().isEmpty ? '(미지정)' : t.event.trim();
        if (ev != event) return false;
      }
      if (category != null && category.isNotEmpty && category != '전체') {
        if (t.category != category) return false;
      }
      if (type == 'income' && t.isExpense) return false;
      if (type == 'expense' && !t.isExpense) return false;
      if (kw.isNotEmpty) {
        final hay =
            '${t.name} ${t.payer} ${t.memo} ${t.event} '
            '${t.category} ${t.number} ${t.context}';
        if (!hay.contains(kw)) return false;
      }
      return true;
    }).toList();
  }

  /// 전체 행사명 목록(내림차순 집계순)
  List<String> allEvents() {
    final m = <String, int>{};
    for (final t in _tx) {
      final ev = t.event.trim().isEmpty ? '(미지정)' : t.event.trim();
      m[ev] = (m[ev] ?? 0) + 1;
    }
    final list = m.keys.toList()
      ..sort((a, b) => (m[b] ?? 0).compareTo(m[a] ?? 0));
    return list;
  }

  static DateTime? _dateOf(String date) {
    final m = RegExp(
      r'(20\d{2})[.\-/]?(\d{1,2})[.\-/]?(\d{1,2})?',
    ).firstMatch(date);
    if (m == null) return null;
    final y = int.tryParse(m.group(1) ?? '');
    final mo = int.tryParse(m.group(2) ?? '') ?? 1;
    final d = int.tryParse(m.group(3) ?? '') ?? 1;
    if (y == null) return null;
    try {
      return DateTime(y, mo, d);
    } catch (_) {
      return null;
    }
  }
}

/// 분류 결과 행 (미리보기용)
class ClassifiedRow {
  ClassifiedRow({
    this.date = '',
    this.type = 'income',
    this.payer = '',
    this.name = '',
    this.number = '',
    this.memberId = '',
    this.matchedName = '',
    this.amount = 0,
    this.category = '기타',
    this.memo = '',
    this.event = '',
    this.context = '',
    this.status = 'unmatched',
    this.sheet = '',
  });

  String date;
  String type; // 'income' | 'expense'
  String payer;
  String name;
  String number;
  String memberId;
  String matchedName;
  int amount;
  String category;
  String memo;
  String event;
  String context;
  String status;
  String sheet; // 출처 시트명(엑셀 다중탭)

  bool get matched => status == 'matched';
  bool get isExpense => type == 'expense';

  Map<String, dynamic> toMap() => {
    'date': date,
    'type': type,
    'payer': payer,
    'name': name,
    'number': number,
    'memberId': memberId,
    'matchedName': matchedName,
    'amount': amount,
    'category': category,
    'memo': memo,
    'event': event,
    'context': context,
    'status': status,
    'sheet': sheet,
  };

  factory ClassifiedRow.fromMap(Map<dynamic, dynamic> m) => ClassifiedRow(
    date: '${m['date'] ?? ''}',
    type: '${m['type'] ?? 'income'}',
    payer: '${m['payer'] ?? ''}',
    name: '${m['name'] ?? ''}',
    number: '${m['number'] ?? ''}',
    memberId: '${m['memberId'] ?? ''}',
    matchedName: '${m['matchedName'] ?? ''}',
    amount: (m['amount'] is num) ? (m['amount'] as num).toInt() : 0,
    category: '${m['category'] ?? '기타'}',
    memo: '${m['memo'] ?? ''}',
    event: '${m['event'] ?? ''}',
    context: '${m['context'] ?? ''}',
    status: '${m['status'] ?? 'unmatched'}',
    sheet: '${m['sheet'] ?? ''}',
  );
}

/// 연도 통계
class YearStat {
  YearStat({
    required this.year,
    this.income = 0,
    this.expense = 0,
    Map<String, int>? byCategory,
    Map<String, int>? byMember,
    Map<String, int>? byMonth,
  }) : byCategory = byCategory ?? {},
       byMember = byMember ?? {},
       byMonth = byMonth ?? {};

  String year;
  int income;
  int expense;
  Map<String, int> byCategory;
  Map<String, int> byMember;
  Map<String, int> byMonth;

  int get net => income - expense;
}

/// 행사별 결산
class EventSettlement {
  EventSettlement({required this.event, this.income = 0, this.expense = 0});
  String event;
  int income;
  int expense;
  int get net => income - expense;
}
