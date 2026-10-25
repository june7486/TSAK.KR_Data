// FinancePickSet 로직 검증 (Flutter 의존 없는 순수 Dart).
//   dart run tool/verify_picks.dart
import '../lib/services/event_finance_picks.dart';

int _pass = 0;
int _fail = 0;

void check(String label, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  if (ok) {
    _pass++;
    print('  PASS  $label  →  $actual');
  } else {
    _fail++;
    print('  FAIL  $label  →  실제=$actual  기대=$expected');
  }
}

void main() {
  final rows = <Map<String, dynamic>>[
    {'id': 't1', 'name': 'A', 'amount': 10000},
    {'id': 't2', 'name': 'B', 'amount': 20000},
    {'id': 't3', 'name': 'C', 'amount': 30000},
  ];

  final p = FinancePickSet();
  print('[1] 기본 상태 = 전부 포함');
  check('excludedCount', p.excludedCount, 0);
  check('isFiltered', p.isFiltered, false);
  check('filtered.length', p.filter(rows).length, 3);

  print('[2] 한 건 제외');
  final on = p.toggle('t2');
  check('toggle 반환(포함여부)', on, false);
  check('excludedCount', p.excludedCount, 1);
  check('filtered.length', p.filter(rows).length, 2);
  check('includedOf', p.includedOf(FinancePickSet.idsOf(rows)).length, 2);
  check(
    '합계(선택)',
    p
        .filter(rows)
        .fold<int>(0, (s, r) => s + (r['amount'] as int)),
    40000,
  );

  print('[3] 다시 포함');
  check('toggle 재반환', p.toggle('t2'), true);
  check('excludedCount', p.excludedCount, 0);

  print('[4] 전체해제 → 전체');
  p.excludeAll(FinancePickSet.idsOf(rows));
  check('전체해제 count', p.excludedCount, 3);
  check('filtered.length', p.filter(rows).length, 0);
  p.includeAll();
  check('전체선택 후', p.filter(rows).length, 3);

  print('[5] id 없는 옛 행 = 내용 기반 키');
  final legacy = <Map<String, dynamic>>[
    {'date': '2026-01-01', 'name': '옛내역', 'amount': 5000},
  ];
  check(
    'rowId(legacy)',
    FinancePickSet.rowId(legacy.first),
    'k_2026-01-01_옛내역_5000',
  );
  check('rowId(id)', FinancePickSet.rowId(rows.first), 't1');

  print('[6] prune — 사라진 id 정리');
  final q = FinancePickSet()
    ..excludeAll(['t1', 't9']);
  q.prune(['t1', 't2', 't3']);
  check('정리 후 excludedCount', q.excludedCount, 1);
  check('남은 제외 id', q.contains('t1'), false);

  print('[7] copy 는 독립');
  final a = FinancePickSet()..toggle('t1');
  final b = a.copy();
  b.toggle('t2');
  check('원본 유지', a.excludedCount, 1);
  check('복사본', b.excludedCount, 2);

  print('[8] FinanceKind 매핑');
  check('expense.saveKind', FinanceKind.expense.saveKind, 'expense');
  check('donation.saveKind', FinanceKind.donation.saveKind, 'fee');
  check('fee.apiKey', FinanceKind.fee.apiKey, 'fee');
  check(
    'fromKey(donation)',
    FinanceKind.fromKey('donation').title,
    '후원 · 기타수입',
  );

  print('');
  print('전체 ${_pass + _fail}개 중 통과 $_pass, 실패 $_fail');
  if (_fail > 0) throw StateError('검증 실패 $_fail건');
}
