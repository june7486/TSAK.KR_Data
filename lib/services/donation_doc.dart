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
  byKind('내역별', '후원 분류(식사·물품·차량·기타)별로 묶어 정리합니다'),
  byYear('연도별', '후원 연도별로 묶어 정리합니다 (연도 → 후원자 순)');

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

/// 출력에 노출할 **세부 항목**.
///
/// ## 요구사항 (그대로)
/// "후원항목에서의 출력시 항목 및 세부항목, 메모, 내용등을 노출할지
///  선택할 수 있도록 해주고"
///
/// ## 정리
/// 후원 1건(donation row)에는 아래 필드가 있다. 출력할 때 **무엇을 보여줄지**
/// 관리자가 직접 켜고 끈다. 최소 1개는 켜져 있어야 한다(빈 표 방지).
enum DonationField {
  sponsor('후원자', '누가 후원했는지(이름)', true, true),
  number('인가번호', '범 인가자면 인가번호', false, false),
  category('후원항목', '식사·물품·차량·기타 분류', true, true),
  detail('세부항목', '후원 내역 — 김밥 100줄, 버스 1대', true, true),
  amount('금액', '실제로 받은 현금', true, true),
  value('금액 상당', '"10만원 상당" 의 그 금액', true, true),
  date('날짜', '후원 접수일', false, false),
  // (요구) "후원내역 출력시 메모내용을 추가해서 출력해줘"
  //  종전엔 기본 OFF 라 실제 출력물에 메모가 거의 보이지 않았다.
  //  후원자별·내역별 **둘 다 기본 ON** 으로 올린다(현장에서 가장 먼저 찾는 항목).
  memo('메모', '비고·특이사항', true, true),
  attach('자료', '붙인 증빙 건수', false, false);

  const DonationField(this.label, this.hint, this.inBySponsor, this.inByKind);

  final String label;
  final String hint;

  /// 후원자별 표에서 기본으로 켜는가.
  final bool inBySponsor;

  /// 내역별 표에서 기본으로 켜는가.
  final bool inByKind;

  /// 후원금(현금) 행에도 의미가 있는가 — 후원금은 세부항목이 없다.
  bool get needsDetail => this == detail;
}

/// 후원 출력 옵션 — 보기 방식 + 초점 + **노출 필드**.
///
/// Flutter 의존 없음(순수 Dart) → `dart run tool/verify_donation_doc.dart`.
class DonationDocOptions {
  DonationDocOptions({
    this.view = DonationViewMode.bySponsor,
    this.focus = DonationFocus.both,
    Set<DonationField>? fields,
  }) : fields = fields ?? _defaults(view);

  final DonationViewMode view;
  final DonationFocus focus;

  /// 노출할 필드 — 비어 있으면 저장 시 기본값으로 되돌린다.
  Set<DonationField> fields;

  /// 보기 방식에 맞는 기본 필드 집합.
  static Set<DonationField> _defaults(DonationViewMode v) => {
    for (final f in DonationField.values)
      if (v == DonationViewMode.bySponsor ? f.inBySponsor : f.inByKind) f,
  };

  /// 초점이 물품중심이면 금액을, 금액중심이면 세부항목을 강제로 끈다.
  /// (서로 모순되는 조합을 만들지 않는다)
  void applyFocus() {
    if (focus == DonationFocus.item) {
      fields.remove(DonationField.amount);
      fields.remove(DonationField.value);
    }
    if (focus == DonationFocus.money) fields.remove(DonationField.detail);
    if (fields.isEmpty) fields = _defaults(view);
  }

  bool shows(DonationField f) => fields.contains(f);

  DonationDocOptions copy() =>
      DonationDocOptions(view: view, focus: focus, fields: {...fields});

  /// 배지 표기 — 예: '후원자별 · 물품중심 · 5항목'.
  String get badge => '${view.label} · ${focus.label} · ${fields.length}항목';
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
  DonationDocOptions? options,
  // 하위 호환 — 옛 호출부(view/focus 만 주는 경우).
  DonationViewMode? view,
  DonationFocus? focus,
  required String Function(int) won,
}) {
  final opt =
      options ??
      DonationDocOptions(
        view: view ?? DonationViewMode.bySponsor,
        focus: focus ?? DonationFocus.both,
      );
  final v = opt.view;
  final f = opt.focus;
  final fields = opt.fields.isEmpty
      ? DonationDocOptions(view: v).fields
      : opt.fields;

  bool on(DonationField x) => fields.contains(x);

  final all = rows.map(DonationRow.fromMap).toList();
  // (버그 방지) `parse()` 는 모르는 문자열을 '기타후원'으로 떨어뜨린다.
  //  참가비·기타수입처럼 **후원과 무관한 행**을 먼저 걸러내지 않으면
  //  후원 합계에 섞인다. `DonationSummary` 와 같은 술어를 쓴다.
  final donations = all
      .where((e) => !DonationKind.isNonDonation(e.category))
      .toList();
  final cash = donations.where((e) => e.isIncome).toList();
  final sponsors = donations.where((e) => e.isSponsor).toList();

  // ── 열 구성 — 켜진 필드만, 정해진 순서대로.
  final columns = <String>['연번'];
  final order = <DonationField>[
    DonationField.sponsor,
    DonationField.number,
    DonationField.category,
    DonationField.detail,
    DonationField.amount,
    DonationField.value,
    DonationField.date,
    DonationField.memo,
    DonationField.attach,
  ];

  // 내역별 표는 '건수'를 항상 넣는다(묶음 크기).
  final showCount = v == DonationViewMode.byKind;
  final fFields = order.where(on).toList();

  // 초점과 모순되는 필드는 열에서도 뺀다.
  final visible = <DonationField>[
    for (final x in fFields)
      if (!(f == DonationFocus.item &&
              (x == DonationField.amount || x == DonationField.value)) &&
          !(f == DonationFocus.money && x == DonationField.detail))
        x,
  ];

  for (var i = 0; i < visible.length; i++) {
    final x = visible[i];
    columns.add(x.label);
    // (버그 수정) 내역별 표의 '건수'는 **후원항목 바로 뒤**에만 넣는다.
    //  종전에는 후원항목 뒤 + 표 끝에 두 번 들어가 열/셀이 어긋났다.
    if (x == DonationField.category && showCount) columns.add('건수');
  }
  // 후원항목을 끈 경우에만 표 끝에 건수를 붙인다(중복 방지).
  final tailCount = showCount && !visible.contains(DonationField.category);
  if (tailCount) columns.add('건수');

  final body = <List<String>>[];

  List<String> cellsFor(_Group g, int no) {
    final out = <String>['$no'];
    for (final x in visible) {
      switch (x) {
        case DonationField.sponsor:
          out.add(
            v == DonationViewMode.bySponsor
                ? (g.name.isEmpty ? '(이름 없음)' : g.name)
                : g.namesText,
          );
        case DonationField.number:
          out.add(g.number);
        case DonationField.category:
          out.add(g.kindSummary);
          if (showCount) out.add('${g.items.length}');
        case DonationField.detail:
          out.add(g.itemSummary);
        case DonationField.amount:
          out.add(g.cash > 0 ? won(g.cash) : '-');
        case DonationField.value:
          out.add(g.value > 0 ? won(g.value) : '-');
        case DonationField.date:
          out.add(g.dateText);
        case DonationField.memo:
          out.add(g.memoText);
        case DonationField.attach:
          out.add('${g.attachCount}');
      }
    }
    if (tailCount) out.add('${g.items.length}');
    return out;
  }

  switch (v) {
    case DonationViewMode.bySponsor:
      // 후원자 1명 = 1 묶음. (이름+인가번호가 같으면 같은 사람)
      final map = <String, _Group>{};
      for (final e in sponsors) {
        map
            .putIfAbsent(
              '${e.name}|${e.number}',
              () => _Group(e.name, e.number),
            )
            .add(e);
      }
      final groups = map.values.toList()
        ..sort((a, b) {
          final c = (b.cash + b.value).compareTo(a.cash + a.value);
          return c != 0 ? c : a.name.compareTo(b.name);
        });
      for (var i = 0; i < groups.length; i++) {
        body.add(cellsFor(groups[i], i + 1));
      }

    case DonationViewMode.byKind:
      // 분류 1개 = 1 묶음. (식사→물품→차량→기타 고정 순서)
      final map = <DonationKind, _Group>{};
      for (final e in sponsors) {
        map.putIfAbsent(e.kind, () => _Group(e.kind.label, '')).add(e);
      }
      final kinds = <DonationKind>[
        DonationKind.meal,
        DonationKind.goods,
        DonationKind.vehicle,
        DonationKind.etc,
      ].where(map.containsKey).toList();
      for (var i = 0; i < kinds.length; i++) {
        body.add(cellsFor(map[kinds[i]]!, i + 1));
      }

    case DonationViewMode.byYear:
      // ## [요구 2026-10-30] "후원자료는 연도별, 이름별, 후원내역별로 구분 및
      //  출력이 가능하도록 폴더가 정리되고 연동되어야 함"
      //
      //  연도 1개 = 1 묶음. 연도는 **날짜(date)의 앞 4자리**에서 뽑는다.
      //  서버가 별도 year 필드를 항상 주지는 않으므로(레거시 행 존재)
      //  날짜가 진실의 원천이다. 날짜가 없으면 '연도미상'.
      //  정렬은 최신 연도부터(2026 → 2025 → …), '연도미상'은 맨 뒤.
      final map = <String, _Group>{};
      for (final e in sponsors) {
        final y = _yearOf(e);
        map.putIfAbsent(y, () => _Group('$y년', '')).add(e);
      }
      final years = map.keys.toList()
        ..sort((a, b) {
          final na = int.tryParse(a);
          final nb = int.tryParse(b);
          if (na == null && nb == null) return a.compareTo(b);
          if (na == null) return 1;   // 연도미상은 뒤로
          if (nb == null) return -1;
          return nb.compareTo(na);    // 최신 연도 먼저
        });
      for (var i = 0; i < years.length; i++) {
        body.add(cellsFor(map[years[i]]!, i + 1));
      }
  }

  // ── 요약 — 후원금(수입)과 현물후원을 **절대 섞지 않는다**.
  final cashSum = cash.fold<int>(0, (s, e) => s + e.amount);
  final sponsorCash = sponsors.fold<int>(0, (s, e) => s + e.amount);
  final sponsorValue = sponsors.fold<int>(0, (s, e) => s + e.value);

  // (요구) 메모가 실제로 몇 건에 붙어 있는지 요약에서 보여준다 —
  //  '메모 3건' 이 보이면 사용자는 출력물에 메모가 실렸음을 바로 안다.
  final memoRows = donations.where((e) => e.memo.trim().isNotEmpty).length;

  final summary = <String>[
    '후원금(수입) ${cash.length}건 · ${won(cashSum)}',
    '현물후원 ${sponsors.length}건 · 금액 ${won(sponsorCash)}'
        ' + 상당 ${won(sponsorValue)}',
    if (on(DonationField.memo))
      memoRows == 0 ? '메모 없음' : '메모 $memoRows건 수록',
  ];

  return DonationDocData(
    columns: columns,
    rows: body,
    summary: summary,
    subtitle:
        '후원 ${v.label} · ${f.label} · ${visible.length}개 항목 · '
        '현물 ${sponsors.length}건 / 후원금 ${cash.length}건',
  );
}

/// 후원 행 1건의 **연도** — 날짜 앞 4자리. 없으면 '연도미상'.
///
/// ## [요구 2026-10-30] 연도별 정리
/// 서버가 별도 year 필드를 항상 내려주지는 않는다(레거시 행). 날짜 문자열이
/// `2026-05-01` / `2026.05.01` / `2026/05/01` 어느 형식이어도 앞 4자리를
/// 숫자로 뽑으면 되므로, 날짜를 진실의 원천으로 삼는다.
String _yearOf(DonationRow r) {
  final m = RegExp(r'(19|20)\d{2}').firstMatch(r.date);
  if (m != null) return m.group(0)!;
  final m2 = RegExp(r'(19|20)\d{2}').firstMatch(r.id);
  if (m2 != null) return m2.group(0)!;
  return '연도미상';
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

  /// 후원자 이름들 — 내역별 표의 '후원자' 칸. 중복 제거.
  String get namesText {
    final out = <String>[];
    for (final e in items) {
      final n = e.name.trim();
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
    }
    return out.isEmpty ? '(이름 없음)' : out.join(', ');
  }

  /// 날짜들 — 여러 건이면 범위 표기('2026-05-01 외 2일').
  String get dateText {
    final ds = <String>[];
    for (final e in items) {
      final d = e.date.trim();
      if (d.isNotEmpty && !ds.contains(d)) ds.add(d);
    }
    if (ds.isEmpty) return '-';
    ds.sort();
    return ds.length == 1 ? ds.first : '${ds.first} 외 ${ds.length - 1}일';
  }

  /// 메모들 — 중복 제거 후 줄바꿈 대신 ' / '.
  ///
  /// (요구) "후원내역 출력시 메모내용을 추가해서 출력해줘"
  /// 메모는 **한 건에 여러 줄**이 들어오는 경우가 많다(예: "현장 전달\n영수증 별첨").
  /// 그대로 이어 붙이면 표 안에서 한 줄이 터무니없이 길어지므로, 줄바꿈을
  /// 공백으로 눌러 **한 줄 요약**으로 만든다. 표에서는 이 값이 쓰이고,
  /// 전문(全文)이 필요하면 [memoLines] 를 쓴다.
  String get memoText {
    final out = <String>[];
    for (final e in items) {
      final m = e.memo.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
      if (m.isNotEmpty && !out.contains(m)) out.add(m);
    }
    return out.isEmpty ? '-' : out.join(' / ');
  }

  /// 메모 원문(줄바꿈 유지) — 상세 내역·보고서형 출력에서 한 줄씩 보여준다.
  List<String> get memoLines {
    final out = <String>[];
    for (final e in items) {
      for (final line in e.memo.split('\n')) {
        final t = line.trim();
        if (t.isNotEmpty && !out.contains(t)) out.add(t);
      }
    }
    return out;
  }

  /// 메모가 있는 후원 건수(요약 줄에 '메모 n건' 표기용).
  int get memoCount => items.where((e) => e.memo.trim().isNotEmpty).length;

  /// 붙인 자료 건수 합.
  int get attachCount => items.fold(0, (sum, e) => sum + e.attach);

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
