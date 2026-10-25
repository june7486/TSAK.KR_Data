/// 후원 목록 출력 문서 — **후원자별 / 내역별** 분리 + **물품중심 / 금액중심**.
///
/// ## 요구사항 (그대로)
/// "대신 후원리스트에는 후원자와 후원내역을 별도로 정리할 것,
///  후원항목만 출력시 후원물품 혹은 금액에 대한 선택할 수 있도록 할 것."
///
/// ## 정리
/// · 보기 방식([DonationViewMode])
///   - [DonationViewMode.bySponsor] : 후원자 1명 = 1행 (여러 건은 한 줄로 묶음)
///   - [DonationViewMode.byKind]    : 후원분류(식사/물품/차량/기타) 1개 = 1행
/// · 출력 초점([DonationFocus])
///   - [DonationFocus.item]  : **후원물품(내역) 중심** — 금액 열을 뺀다
///   - [DonationFocus.money] : **금액 중심** — 내역 열을 뺀다
///   - [DonationFocus.both]  : 둘 다
/// · 후원금(현금)은 수입이므로 현물후원과 **합계를 섞지 않는다**.
///   (`DonationKind.isIncome`)
///
/// Flutter 의존 없음 → `dart run tool/verify_donation_doc.dart` 로 검증.
library;

import 'donation_kinds.dart';

/// 후원 목록 보기 방식.
enum DonationViewMode {
  bySponsor('후원자별', '후원자 한 명을 한 줄로 묶어 정리합니다'),
  byKind('내역별', '후원 분류(식사·물품·차량·기타)별로 묶어 정리합니다');

  const DonationViewMode(this.label, this.hint);

  final String label;
  final String hint;
}

/// 출력 초점 — 물품(내역) 중심 / 금액 중심.
enum DonationFocus {
  item('물품중심', '무엇을 후원했는지(내역)를 앞세웁니다'),
  money('금액중심', '금액·금액상당을 앞세웁니다'),
  both('둘 다', '내역과 금액을 함께 표기합니다');

  const DonationFocus(this.label, this.hint);

  final String label;
  final String hint;
}

/// 문서 본문(열 / 행 / 요약 / 부제) — 화면에서 `TsakTableDoc` 으로 감싼다.
class DonationDocData {
  const DonationDocData({
    required this.columns,
    required this.rows,
    required this.summary,
    required this.subtitle,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final List<String> summary;
  final String subtitle;
}

/// 후원 행 목록(서버 원본 map) → 출력 문서 데이터.
///
/// [rows] 는 '후원·기타수입' 탭의 행 그대로(참가비 제외). 필터링하지 않는다.
DonationDocData buildDonationDocData({
  required List<Map<String, dynamic>> rows,
  required DonationViewMode view,
  required DonationFocus focus,
  required String Function(int) won,
}) {
  final all = rows.map(DonationRow.fromMap).toList();
  // (버그 방지) `parse()` 는 모르는 문자열을 '기타후원'으로 떨어뜨린다.
  //  참가비·기타수입처럼 **후원과 무관한 행**을 먼저 걸러내지 않으면
  //  후원 합계에 섞인다. `DonationSummary` 와 같은 술어를 쓴다.
  final donations = all
      .where((e) => !DonationKind.isNonDonation(e.category))
      .toList();
  final cash = donations.where((e) => e.isIncome).toList();
  final sponsors = donations.where((e) => e.isSponsor).toList();

  final columns = <String>['연번'];
  final body = <List<String>>[];

  switch (view) {
    case DonationViewMode.bySponsor:
      columns.addAll(['후원자', '인가번호', '후원분류']);
      if (focus != DonationFocus.money) columns.add('후원내역');
      if (focus != DonationFocus.item) columns.addAll(['금액', '금액 상당']);
      columns.add('비고');

      final map = <String, _Group>{};
      for (final e in sponsors) {
        final key = '${e.name}|${e.number}';
        map.putIfAbsent(key, () => _Group(e.name, e.number)).add(e);
      }
      final groups = map.values.toList()
        ..sort((a, b) {
          final c = (b.cash + b.value).compareTo(a.cash + a.value);
          return c != 0 ? c : a.name.compareTo(b.name);
        });

      for (var i = 0; i < groups.length; i++) {
        final g = groups[i];
        final row = <String>['${i + 1}', g.name, g.number, g.kindSummary];
        if (focus != DonationFocus.money) row.add(g.itemSummary);
        if (focus != DonationFocus.item) {
          row.add(g.cash > 0 ? won(g.cash) : '-');
          row.add(g.value > 0 ? won(g.value) : '-');
        }
        row.add('${g.items.length}건');
        body.add(row);
      }

    case DonationViewMode.byKind:
      columns.addAll(['후원분류', '건수']);
      if (focus != DonationFocus.money) columns.add('후원내역');
      if (focus != DonationFocus.item) columns.addAll(['금액', '금액 상당']);
      columns.add('비고');

      final kinds = <DonationKind, _Group>{};
      for (final e in sponsors) {
        kinds.putIfAbsent(e.kind, () => _Group(e.kind.label, '')).add(e);
      }
      // 분류 순서는 enum 순서(식사→물품→차량→기타) 고정.
      final ordered = <DonationKind>[
        DonationKind.meal,
        DonationKind.goods,
        DonationKind.vehicle,
        DonationKind.etc,
      ].where(kinds.containsKey).toList();

      for (var i = 0; i < ordered.length; i++) {
        final k = ordered[i];
        final g = kinds[k]!;
        final row = <String>['${i + 1}', k.label, '${g.items.length}'];
        if (focus != DonationFocus.money) row.add(g.itemSummary);
        if (focus != DonationFocus.item) {
          row.add(g.cash > 0 ? won(g.cash) : '-');
          row.add(g.value > 0 ? won(g.value) : '-');
        }
        final names = g.items.map((e) => e.name).where((e) => e.isNotEmpty);
        row.add(names.isEmpty ? '' : names.join(', '));
        body.add(row);
      }
  }

  // ── 요약 — 후원금(수입)과 현물후원을 **절대 섞지 않는다**.
  final cashSum = cash.fold<int>(0, (s, e) => s + e.amount);
  final sponsorCash = sponsors.fold<int>(0, (s, e) => s + e.amount);
  final sponsorValue = sponsors.fold<int>(0, (s, e) => s + e.value);
  final summary = <String>[
    '후원금(수입) ${cash.length}건 · ${won(cashSum)}',
    '현물후원 ${sponsors.length}건 · 금액 ${won(sponsorCash)}'
        ' + 상당 ${won(sponsorValue)}',
  ];

  final focusText = switch (focus) {
    DonationFocus.item => '물품중심',
    DonationFocus.money => '금액중심',
    DonationFocus.both => '내역+금액',
  };

  return DonationDocData(
    columns: columns,
    rows: body,
    summary: summary,
    subtitle:
        '후원 ${view.label} · $focusText · '
        '현물 ${sponsors.length}건 / 후원금 ${cash.length}건',
  );
}

/// 후원자 또는 분류 1묶음.
class _Group {
  _Group(this.name, this.number);

  final String name;
  final String number;
  final List<DonationRow> items = [];

  void add(DonationRow r) => items.add(r);

  int get cash => items.fold(0, (s, e) => s + e.amount);
  int get value => items.fold(0, (s, e) => s + e.value);

  /// '식사후원, 물품후원' — 중복 제거.
  String get kindSummary {
    final set = <String>{};
    for (final e in items) {
      set.add(e.kind.label);
    }
    return set.join(', ');
  }

  /// '김밥 100줄, 기념품 50개' — 내역이 없으면 분류명으로 대체, 중복 제거.
  String get itemSummary {
    final out = <String>[];
    for (final e in items) {
      final t = e.itemText;
      final v = t == '-' ? e.kind.label : t;
      if (!out.contains(v)) out.add(v);
    }
    return out.isEmpty ? '-' : out.join(', ');
  }
}
