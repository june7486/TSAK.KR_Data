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
  List<String> _incomeCats = ['후원', '수품구매', '참가비', '연회비', '기타'];
  List<String> _expenseCats = ['행사비', '운영비', '수품구매', '후원금집행', '기타'];
  Map<String, String> _aliases = {}; // 입금자 별칭 → 인가번호
  Map<String, String> _eventRules = {}; // 행사명 키워드 → 분류
  String? _updated;
  int _version = 0;
  bool _loading = false;
  String _status = ''; // '', 'loading', 'saved', 'error', 'offline'

  List<FinanceTransaction> get transactions => _tx;
  List<String> get incomeCategories => _incomeCats;
  List<String> get expenseCategories => _expenseCats;
  Map<String, String> get aliases => _aliases;
  Map<String, String> get eventRules => _eventRules;
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
      final fin = await nas.fetchFinance();
      _apply(fin);
      try {
        final r = await nas.fetchRules();
        final rr = r['rules'];
        if (rr is Map) {
          _aliases = _asStringMap(rr['aliases']);
          _eventRules = _asStringMap(rr['events']);
        }
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
      _tx = list
          .map((e) => FinanceTransaction.fromMap(e as Map))
          .toList();
    }
    if (fin['income_categories'] is List) {
      _incomeCats = (fin['income_categories'] as List).map((e) => '$e').toList();
    }
    if (fin['expense_categories'] is List) {
      _expenseCats = (fin['expense_categories'] as List).map((e) => '$e').toList();
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
      });
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
        final residue =
            payer.replaceAll(matchedName, '').replaceAll(RegExp(r'^[\s\-·,_/()\[\]]+|[\s\-·,_/()\[\]]+$'), '');
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
      '후원': '후원', '찬조': '후원', '기부': '후원',
      '수품': '수품구매', '구매': '수품구매', '물품': '수품구매',
      '참가비': '참가비', '참가': '참가비', '행사비': '참가비',
      '연회비': '연회비', '회비': '연회비',
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
        type: 'income',
        payer: r.payer,
        name: r.name,
        number: r.number,
        memberId: r.memberId,
        amount: r.amount,
        category: r.category,
        event: r.event,
        context: r.context,
        memo: r.memo,
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
      .where((t) => !t.isExpense &&
          (category == null || t.category == category))
      .toList();

  List<FinanceTransaction> expenseList() =>
      _tx.where((t) => t.isExpense).toList();

  /// 인가번호별 입금 집계
  Map<String, MemberDepositSummary> memberSummaries(
      Map<String, Member> byNumber) {
    final map = <String, MemberDepositSummary>{};
    for (final t in _tx) {
      if (t.isExpense) continue;
      final no = t.number.replaceAll(RegExp(r'[^0-9]'), '');
      if (no.isEmpty) continue;
      final s = map.putIfAbsent(
        no,
        () => MemberDepositSummary(
            number: no, name: byNumber[no]?.name ?? t.name),
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

  /// 특정 인가번호의 입금 내역
  List<FinanceTransaction> depositsOf(String number) {
    final no = number.replaceAll(RegExp(r'[^0-9]'), '');
    return _tx
        .where((t) =>
            !t.isExpense &&
            t.number.replaceAll(RegExp(r'[^0-9]'), '') == no)
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
      final mo = RegExp(r'20\d{2}[.\-/]?(\d{1,2})')
          .firstMatch(t.date)
          ?.group(1)
          ?.padLeft(2, '0');
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
}

/// 분류 결과 행 (미리보기용)
class ClassifiedRow {
  ClassifiedRow({
    this.date = '',
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
  });

  String date;
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

  bool get matched => status == 'matched';

  Map<String, dynamic> toMap() => {
        'date': date,
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
      };

  factory ClassifiedRow.fromMap(Map<dynamic, dynamic> m) => ClassifiedRow(
        date: '${m['date'] ?? ''}',
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
  })  : byCategory = byCategory ?? {},
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
