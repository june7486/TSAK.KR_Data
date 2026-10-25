// 후원 목록 출력 문서 단위 검증.
// 실행: dart run tool/verify_donation_doc.dart
import 'package:tsak_credential_manager/services/donation_doc.dart';

int _fails = 0;
final List<String> _lines = [];

void check(String name, bool cond, [String? detail]) {
  if (!cond) _fails++;
  _lines.add(
    '${cond ? "PASS" : "FAIL"} $name${detail == null ? "" : "  ($detail)"}',
  );
}

String won(int v) => '${_comma(v)}원';

String _comma(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$b';
}

void main() {
  // 후원자 A: 식사후원 김밥 100줄(현금 10만) + 물품후원 기념품 50개(상당 5만)
  // 후원자 B: 차량후원 버스 1대(상당 30만)
  // 후원자 C: 물품후원 (금액·상당 없음 — 내역만)
  // 후원금 D: 현금 후원금 20만 → **수입**, 현물 집계에서 제외
  // 기타수입 E: 5만 → 후원과 무관, 집계에서 제외
  final rows = <Map<String, dynamic>>[
    {
      'name': 'A',
      'number': '415',
      'category': '식사후원',
      'item': '김밥 100줄',
      'amount': 100000,
      'value': 0,
    },
    {
      'name': 'A',
      'number': '415',
      'category': '물품후원',
      'item': '기념품 50개',
      'amount': 0,
      'value': 50000,
    },
    {
      'name': 'B',
      'number': '416',
      'category': '차량후원',
      'item': '버스 1대',
      'amount': 0,
      'value': 300000,
    },
    {
      'name': 'C',
      'number': '',
      'category': '물품후원',
      'item': '',
      'amount': 0,
      'value': 0,
    },
    {
      'name': 'D',
      'number': '417',
      'category': '후원금',
      'item': '',
      'amount': 200000,
      'value': 0,
    },
    {
      'name': 'E',
      'number': '',
      'category': '기타수입',
      'item': '',
      'amount': 50000,
      'value': 0,
    },
  ];

  // ── ① 후원자별 + 물품중심 ─────────────────────────────────────────
  final sp = buildDonationDocData(
    rows: rows,
    view: DonationViewMode.bySponsor,
    focus: DonationFocus.item,
    won: won,
  );
  print('=== 후원자별 · 물품중심 ===');
  print('열: ${sp.columns}');
  for (final r in sp.rows) {
    print('  $r');
  }
  print('요약: ${sp.summary}');
  print('부제: ${sp.subtitle}\n');

  check('후원자별 행 수 = 현물후원자 3명(A,B,C)', sp.rows.length == 3, '${sp.rows.length}');
  check(
    '후원금·기타수입은 현물 표에서 제외',
    !sp.rows.any((r) => r.contains('D') || r.contains('E')),
  );
  check('물품중심 → 금액 열 없음', !sp.columns.contains('금액'));
  check('물품중심 → 내역 열 있음', sp.columns.contains('후원내역'));
  // 정렬은 (금액+상당) 내림차순 → B(30만) → A(15만) → C(0).
  check(
    '정렬: B → A → C',
    sp.rows.map((r) => r[1]).join(',') == 'B,A,C',
    sp.rows.map((r) => r[1]).join(','),
  );
  final aItem = sp.rows.firstWhere((r) => r[1] == 'A');
  check(
    'A 내역에 두 건 모두',
    aItem[sp.columns.indexOf('후원내역')].contains('김밥 100줄') &&
        aItem[sp.columns.indexOf('후원내역')].contains('기념품 50개'),
    aItem[sp.columns.indexOf('후원내역')],
  );
  check(
    'A 분류 = 식사후원, 물품후원',
    aItem[sp.columns.indexOf('후원분류')] == '식사후원, 물품후원',
    aItem[sp.columns.indexOf('후원분류')],
  );
  check('A 건수 2건', aItem[sp.columns.indexOf('비고')] == '2건');

  // ── ② 후원자별 + 금액중심 ─────────────────────────────────────────
  final sm = buildDonationDocData(
    rows: rows,
    view: DonationViewMode.bySponsor,
    focus: DonationFocus.money,
    won: won,
  );
  print('=== 후원자별 · 금액중심 ===');
  print('열: ${sm.columns}');
  for (final r in sm.rows) {
    print('  $r');
  }
  print('');

  check('금액중심 → 내역 열 없음', !sm.columns.contains('후원내역'));
  check('금액중심 → 금액 열 있음', sm.columns.contains('금액'));
  final aRow = sm.rows.firstWhere((r) => r[1] == 'A');
  check(
    'A 금액 = 100,000원',
    aRow[sm.columns.indexOf('금액')] == '100,000원',
    aRow[sm.columns.indexOf('금액')],
  );
  check(
    'A 상당 = 50,000원',
    aRow[sm.columns.indexOf('금액 상당')] == '50,000원',
    aRow[sm.columns.indexOf('금액 상당')],
  );
  final bRow = sm.rows.firstWhere((r) => r[1] == 'B');
  check('B 금액 없음 → -', bRow[sm.columns.indexOf('금액')] == '-');
  check('B 상당 = 300,000원', bRow[sm.columns.indexOf('금액 상당')] == '300,000원');

  // ── ③ 내역별 + 둘 다 ──────────────────────────────────────────────
  final kb = buildDonationDocData(
    rows: rows,
    view: DonationViewMode.byKind,
    focus: DonationFocus.both,
    won: won,
  );
  print('=== 내역별 · 둘다 ===');
  print('열: ${kb.columns}');
  for (final r in kb.rows) {
    print('  $r');
  }
  print('요약: ${kb.summary}\n');

  check(
    '내역별 행 수 = 현물 분류 3종(식사·물품·차량)',
    kb.rows.length == 3,
    '${kb.rows.length}',
  );
  check(
    '분류 순서 식사→물품→차량',
    kb.rows.map((r) => r[1]).take(3).join(',') == '식사후원,물품후원,차량후원',
    kb.rows.map((r) => r[1]).join(','),
  );
  check(
    '둘다 → 내역·금액 열 모두',
    kb.columns.contains('후원내역') &&
        kb.columns.contains('금액') &&
        kb.columns.contains('금액 상당'),
  );
  final goods = kb.rows.firstWhere((r) => r[1] == '물품후원');
  check('물품후원 건수 2', goods[kb.columns.indexOf('건수')] == '2');
  check(
    '물품후원 상당 50,000원',
    goods[kb.columns.indexOf('금액 상당')] == '50,000원',
    goods[kb.columns.indexOf('금액 상당')],
  );
  check(
    '물품후원 비고에 후원자 이름',
    goods[kb.columns.indexOf('비고')].contains('A') &&
        goods[kb.columns.indexOf('비고')].contains('C'),
    goods[kb.columns.indexOf('비고')],
  );

  // ── ④ 요약 — 후원금(수입)과 현물을 섞지 않는다 ────────────────────
  check('요약 2줄', kb.summary.length == 2, '${kb.summary.length}');
  check('후원금(수입) 200,000원', kb.summary[0].contains('200,000원'), kb.summary[0]);
  check('후원금 건수 1건', kb.summary[0].contains('1건'), kb.summary[0]);
  check('현물 금액 100,000원', kb.summary[1].contains('금액 100,000원'), kb.summary[1]);
  check('현물 상당 350,000원', kb.summary[1].contains('상당 350,000원'), kb.summary[1]);
  check('현물 건수 4건', kb.summary[1].contains('4건'), kb.summary[1]);

  // ── ⑤ 빈 목록 ─────────────────────────────────────────────────────
  final empty = buildDonationDocData(
    rows: const [],
    view: DonationViewMode.bySponsor,
    focus: DonationFocus.both,
    won: won,
  );
  check('빈 목록 → 행 0', empty.rows.isEmpty);
  check('빈 목록 → 요약 0원', empty.summary[0].contains('0원'), empty.summary[0]);

  // ── ⑥ 후원금만 있는 목록 ──────────────────────────────────────────
  final cashOnly = buildDonationDocData(
    rows: [
      {'name': 'D', 'category': '후원금', 'amount': 200000},
    ],
    view: DonationViewMode.bySponsor,
    focus: DonationFocus.both,
    won: won,
  );
  check('현물 없으면 표 행 0', cashOnly.rows.isEmpty);
  check(
    '현물 없어도 후원금 요약 유지',
    cashOnly.summary[0].contains('200,000원'),
    cashOnly.summary[0],
  );

  for (final l in _lines) {
    print(l);
  }
  print(
    _fails == 0
        ? '\n전체 ${_lines.length}개 통과'
        : '\n실패 $_fails건 / ${_lines.length}',
  );
}
