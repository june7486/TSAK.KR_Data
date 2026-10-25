/// 후원(현물·서비스)과 후원금(현금)의 분리 모델.
///
/// ## 요구사항 (그대로)
/// "후원금을 제외하고 후원 및 기타후원 수입으로 잡지 말고 별도로 구분해서
///  후원금 산출금으로만 합산할 것"
/// "후원항목 세분화할 것: 식사후원, 물품후원, 차량후원, 기타후원(직접입력),
///  후원금만 수입으로 잡을 것, 입력시 금액은 정확치 않는 항목이 있기때문에
///  십만원 상당처럼 별도 입력할 수 있는 항목 추가하고 합산시에만 금액을 합산할
///  것 (즉, 000원, 000원상당 이런식으로 창을 두개 만들 것)."
/// "대신 후원리스트에는 후원자와 후원내역을 별도로 정리할 것, 후원항목만 출력시
///  후원물품 혹은 금액에 대한 선택할 수 있도록 할 것."
///
/// ## 정리된 규칙
/// · **수입(현금) = 참가비 + 후원금** 만. 후원(현물)은 수입에 넣지 않는다.
/// · 후원은 4분류 × (금액 / 금액'상당') 2개의 숫자를 가진다.
///   - 금액(amount)  : 실제로 받은 현금(있을 때만).
///   - 상당액(value) : "10만원 상당" 처럼 환산한 가치.
/// · 후원 총액은 **금액 합계 + 상당액 합계** 를 따로 보여준다(섞지 않는다).
/// · 출력 시 물품(현물) 중심 / 금액 중심 중 선택할 수 있다.
library;

/// 후원 세분류.
enum DonationKind {
  cash('후원금', true, '현금 후원'),
  meal('식사후원', false, '식사·다과'),
  goods('물품후원', false, '물품·기념품'),
  vehicle('차량후원', false, '차량·수송'),
  etc('기타후원', false, '직접입력');

  const DonationKind(this.label, this.isIncome, this.hint);

  /// 화면·출력에 쓰는 이름.
  final String label;

  /// 수입(현금)으로 합산되는가 — **후원금만 true**.
  final bool isIncome;

  /// 입력 화면 보조 설명.
  final String hint;

  /// 저장된 category 문자열 → 분류. 모르는 값은 기타로 본다.
  static DonationKind parse(String raw) {
    final s = raw.trim();
    for (final k in DonationKind.values) {
      if (k.label == s) return k;
    }
    // 옛 데이터 호환 — '후원' 은 현물로 보던 값이었지만 실제로는 후원금과
    //   섞여 있었다. 안전하게 '기타후원'으로 두고, 사용자가 후원금으로
    //   고칠 수 있게 한다(수입이 갑자기 늘어나는 것을 막는다).
    if (s == '후원') return DonationKind.etc;
    if (s == '수송지원') return DonationKind.vehicle;
    if (s == '기타' || s == '기타수입') return DonationKind.etc;
    return DonationKind.etc;
  }

  /// 후원(현물)인가 — 후원금이 아닌 모든 것.
  bool get isSponsor => !isIncome;

  /// 출력 선택지에 노출할 항목.
  static List<DonationKind> get sponsors =>
      values.where((e) => e.isSponsor).toList();
}

/// 후원 1건(정규화).
class DonationRow {
  const DonationRow({
    required this.id,
    required this.date,
    required this.name,
    required this.number,
    required this.category,
    required this.item,
    required this.amount,
    required this.value,
    required this.memo,
  });

  final String id;
  final String date;

  /// 후원자(개인/단체).
  final String name;

  /// 인가번호(범 인가자면).
  final String number;

  /// 분류 원문('식사후원' 등).
  final String category;

  /// 후원 내역 — 무엇을 후원했는지('김밥 100줄', '버스 1대').
  final String item;

  /// 현금 금액(원).
  final int amount;

  /// 금액 상당(원) — "10만원 상당"의 그 금액.
  final int value;

  final String memo;

  DonationKind get kind => DonationKind.parse(category);

  /// 수입으로 잡히는가.
  bool get isIncome => kind.isIncome;

  /// 후원(현물·서비스)인가 — 후원금이 아닌 모든 것.
  bool get isSponsor => kind.isSponsor;

  /// 표시용 금액 — 금액이 있으면 '100,000원', 없고 상당액만 있으면
  /// '100,000원 상당'.
  String get displayAmount {
    final parts = <String>[];
    if (amount > 0) parts.add('${_comma(amount)}원');
    if (value > 0) parts.add('${_comma(value)}원 상당');
    return parts.isEmpty ? '-' : parts.join(' + ');
  }

  /// 출력용 — 물품 중심일 때는 '내역'을 앞세운다.
  String get itemText => item.trim().isEmpty ? '-' : item.trim();

  static String _comma(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}$b';
  }

  static DonationRow fromMap(Map<String, dynamic> r) => DonationRow(
    id: '${r['id'] ?? ''}',
    date: '${r['date'] ?? ''}'.trim(),
    name: '${r['name'] ?? ''}'.trim(),
    number: '${r['number'] ?? ''}'.trim(),
    category: '${r['category'] ?? ''}'.trim(),
    item: '${r['item'] ?? ''}'.trim(),
    amount: _int(r['amount']),
    value: _int(r['value']),
    memo: '${r['memo'] ?? ''}'.trim(),
  );

  static int _int(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  }
}

/// 후원 집계.
class DonationSummary {
  DonationSummary(this.rows);

  final List<DonationRow> rows;

  /// 후원금(현금·수입) 행만.
  List<DonationRow> get cashRows =>
      rows.where((e) => e.isIncome).toList();

  /// 후원(현물) 행만.
  List<DonationRow> get sponsorRows =>
      rows.where((e) => e.isSponsor).toList();

  /// 후원금 합계 — **이것만 수입**.
  int get cashTotal => cashRows.fold(0, (s, e) => s + e.amount);

  /// 후원 현금 합계(현물인데 현금도 낸 경우).
  int get sponsorCashTotal => sponsorRows.fold(0, (s, e) => s + e.amount);

  /// 후원 상당액 합계.
  int get sponsorValueTotal => sponsorRows.fold(0, (s, e) => s + e.value);

  /// 후원 건수.
  int get sponsorCount => sponsorRows.length;

  /// 분류별 합계(현금, 상당) — 출력·결산 공용.
  ///   반환: { '식사후원': (cash, value), ... }
  Map<String, (int, int)> get byKind {
    final map = <String, (int, int)>{};
    for (final k in DonationKind.sponsors) {
      map[k.label] = (0, 0);
    }
    for (final e in sponsorRows) {
      final key = e.kind.label;
      final cur = map[key] ?? (0, 0);
      map[key] = (cur.$1 + e.amount, cur.$2 + e.value);
    }
    return map;
  }

  /// 후원자별 묶음(같은 이름+인가번호) — '후원자 / 후원내역' 분리 출력용.
  List<SponsorGroup> get bySponsor {
    final map = <String, SponsorGroup>{};
    for (final e in sponsorRows) {
      final key = '${e.name}|${e.number}';
      final g = map[key];
      if (g == null) {
        map[key] = SponsorGroup(
          name: e.name,
          number: e.number,
          items: [e],
        );
      } else {
        g.items.add(e);
      }
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final c = (b.valueTotal + b.cashTotal)
            .compareTo(a.valueTotal + a.cashTotal);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return list;
  }

  static String comma(int v) => DonationRow._comma(v);
}

/// 후원자 1명의 후원 묶음.
class SponsorGroup {
  SponsorGroup({
    required this.name,
    required this.number,
    required this.items,
  });

  final String name;
  final String number;
  final List<DonationRow> items;

  int get cashTotal => items.fold(0, (s, e) => s + e.amount);
  int get valueTotal => items.fold(0, (s, e) => s + e.value);

  /// 후원 내역 요약 — '식사후원(김밥 100줄), 물품후원(기념품 50개)'.
  String get itemSummary => items
      .map((e) {
        final i = e.itemText;
        return i == '-' ? e.kind.label : '${e.kind.label}($i)';
      })
      .join(', ');

  /// 분류만 모은 것.
  String get kindSummary {
    final set = <String>{};
    for (final e in items) {
      set.add(e.kind.label);
    }
    return set.join(', ');
  }
}
