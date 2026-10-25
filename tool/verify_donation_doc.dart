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
    options: DonationDocOptions(
      view: DonationViewMode.bySponsor,
      focus: DonationFocus.item,
    ),
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
  check('물품중심 → 금액 상당 열 없음', !sp.columns.contains('금액 상당'));
  check('물품중심 → 세부항목 열 있음', sp.columns.contains('세부항목'), '${sp.columns}');
  check('물품중심 → 후원항목 열 있음', sp.columns.contains('후원항목'), '${sp.columns}');
  // 정렬은 (금액+상당) 내림차순 → B(30만) → A(15만) → C(0).
  check(
    '정렬: B → A → C',
    sp.rows.map((r) => r[1]).join(',') == 'B,A,C',
    sp.rows.map((r) => r[1]).join(','),
  );
  final aItem = sp.rows.firstWhere((r) => r[1] == 'A');
  check(
    'A 세부항목에 두 건 모두',
    aItem[sp.columns.indexOf('세부항목')].contains('김밥 100줄') &&
        aItem[sp.columns.indexOf('세부항목')].contains('기념품 50개'),
    aItem[sp.columns.indexOf('세부항목')],
  );
  check(
    'A 후원항목 = 식사후원, 물품후원',
    aItem[sp.columns.indexOf('후원항목')] == '식사후원, 물품후원',
    aItem[sp.columns.indexOf('후원항목')],
  );

  // ── ② 후원자별 + 금액중심 ─────────────────────────────────────────
  final sm = buildDonationDocData(
    rows: rows,
    options: DonationDocOptions(
      view: DonationViewMode.bySponsor,
      focus: DonationFocus.money,
    ),
    won: won,
  );
  print('=== 후원자별 · 금액중심 ===');
  print('열: ${sm.columns}');
  for (final r in sm.rows) {
    print('  $r');
  }
  print('');

  check('금액중심 → 세부항목 열 없음', !sm.columns.contains('세부항목'), '${sm.columns}');
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
    options: DonationDocOptions(
      view: DonationViewMode.byKind,
      focus: DonationFocus.both,
    ),
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
  final kIdx = kb.columns.indexOf('후원항목');
  check(
    '분류 순서 식사→물품→차량',
    kb.rows.map((r) => r[kIdx]).take(3).join(',') == '식사후원,물품후원,차량후원',
    kb.rows.map((r) => r[kIdx]).join(','),
  );
  check(
    '둘다 → 세부항목·금액 열 모두',
    kb.columns.contains('세부항목') &&
        kb.columns.contains('금액') &&
        kb.columns.contains('금액 상당'),
    '${kb.columns}',
  );
  final goods = kb.rows.firstWhere((r) => r[kIdx] == '물품후원');
  check('물품후원 건수 2', goods[kb.columns.indexOf('건수')] == '2');
  check(
    '물품후원 상당 50,000원',
    goods[kb.columns.indexOf('금액 상당')] == '50,000원',
    goods[kb.columns.indexOf('금액 상당')],
  );
  final sIdx = kb.columns.indexOf('후원자');
  check(
    '물품후원 후원자 칸에 이름',
    goods[sIdx].contains('A') && goods[sIdx].contains('C'),
    goods[sIdx],
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
    options: DonationDocOptions(),
    won: won,
  );
  check('빈 목록 → 행 0', empty.rows.isEmpty);
  check('빈 목록 → 요약 0원', empty.summary[0].contains('0원'), empty.summary[0]);

  // ── ⑥ 후원금만 있는 목록 ──────────────────────────────────────────
  final cashOnly = buildDonationDocData(
    rows: [
      {'name': 'D', 'category': '후원금', 'amount': 200000},
    ],
    options: DonationDocOptions(),
    won: won,
  );
  check('현물 없으면 표 행 0', cashOnly.rows.isEmpty);
  check(
    '현물 없어도 후원금 요약 유지',
    cashOnly.summary[0].contains('200,000원'),
    cashOnly.summary[0],
  );

  // ── ⑦ 노출 필드 선택 (요구: "항목 및 세부항목, 메모, 내용등을 노출할지") ──
  final opt = DonationDocOptions(
    view: DonationViewMode.bySponsor,
    focus: DonationFocus.both,
  );
  // 기본값 — 후원자/후원항목/세부항목/금액/금액상당.
  final d1 = buildDonationDocData(rows: rows, options: opt, won: won);
  check(
    '기본 필드 열 = 후원자·후원항목·세부항목·금액·금액 상당',
    d1.columns.join(',') == '연번,후원자,후원항목,세부항목,금액,금액 상당',
    d1.columns.join(','),
  );

  // 메모·날짜·인가번호·자료를 켜면 열이 늘어난다.
  opt.fields.addAll([
    DonationField.number,
    DonationField.date,
    DonationField.memo,
    DonationField.attach,
  ]);
  final d2 = buildDonationDocData(rows: rows, options: opt, won: won);
  check('필드 추가 → 인가번호 열', d2.columns.contains('인가번호'), '${d2.columns}');
  check('필드 추가 → 날짜 열', d2.columns.contains('날짜'), '${d2.columns}');
  check('필드 추가 → 메모 열', d2.columns.contains('메모'), '${d2.columns}');
  check('필드 추가 → 자료 열', d2.columns.contains('자료'), '${d2.columns}');
  check('필드 추가 후 열 수 9+연번', d2.columns.length == 10, '${d2.columns.length}');

  // 세부항목만 끄기 — 열에서 사라져야 한다.
  final o3 = DonationDocOptions();
  o3.fields.remove(DonationField.detail);
  final d3 = buildDonationDocData(rows: rows, options: o3, won: won);
  check('세부항목 끄면 열에서 제거', !d3.columns.contains('세부항목'), '${d3.columns}');

  // 금액·금액상당 둘 다 끄기(금액 정보 없는 목록).
  final o4 = DonationDocOptions();
  o4.fields.removeWhere(
    (f) => f == DonationField.amount || f == DonationField.value,
  );
  final d4 = buildDonationDocData(rows: rows, options: o4, won: won);
  check(
    '금액 계열 끄면 금액 열 없음',
    !d4.columns.contains('금액') && !d4.columns.contains('금액 상당'),
    '${d4.columns}',
  );

  // 초점 적용 — 물품중심이면 금액이 강제로 빠진다.
  final o5 = DonationDocOptions(focus: DonationFocus.money)..applyFocus();
  check(
    '금액중심 applyFocus → 세부항목 제거',
    !o5.shows(DonationField.detail),
    '${o5.fields}',
  );
  final o6 = DonationDocOptions(focus: DonationFocus.item)..applyFocus();
  check(
    '물품중심 applyFocus → 금액 계열 제거',
    !o6.shows(DonationField.amount) && !o6.shows(DonationField.value),
    '${o6.fields}',
  );

  // 메모 값이 실제로 출력에 실리는지.
  final withMemo = [
    {
      'name': 'F',
      'category': '물품후원',
      'item': '텐트 2동',
      'amount': 0,
      'value': 400000,
      'memo': '설치 지원 포함',
      'date': '2026-05-01',
      'attach': 3,
    },
  ];
  final o7 = DonationDocOptions();
  o7.fields.addAll([
    DonationField.memo,
    DonationField.date,
    DonationField.attach,
  ]);
  final d7 = buildDonationDocData(rows: withMemo, options: o7, won: won);
  final r7 = d7.rows.first;
  check(
    '메모 값 출력',
    r7[d7.columns.indexOf('메모')] == '설치 지원 포함',
    r7[d7.columns.indexOf('메모')],
  );
  check(
    '날짜 값 출력',
    r7[d7.columns.indexOf('날짜')] == '2026-05-01',
    r7[d7.columns.indexOf('날짜')],
  );
  check(
    '자료 건수 출력',
    r7[d7.columns.indexOf('자료')] == '3',
    r7[d7.columns.indexOf('자료')],
  );

  // 내역별 표 — 후원항목을 끄면 건수가 표 끝으로 간다.
  final o8 = DonationDocOptions(view: DonationViewMode.byKind);
  o8.fields.remove(DonationField.category);
  final d8 = buildDonationDocData(rows: rows, options: o8, won: won);
  check('내역별·후원항목 끔 → 건수는 마지막 열', d8.columns.last == '건수', '${d8.columns}');
  check(
    '건수 셀이 행 길이와 맞음',
    d8.rows.every((r) => r.length == d8.columns.length),
    '${d8.rows.map((e) => e.length).toList()} vs ${d8.columns.length}',
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
