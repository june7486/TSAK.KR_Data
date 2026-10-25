/// 행사 결산 · 항목별 출력 계산 서비스.
///
/// ## 요구사항 정리
/// 1. 참가비/후원금, 후원·기타수입, 행사비지출, 행사결산 4개 탭으로 세분화
/// 2. 각 항목별 출력 — **합산 기능** + **연번·이름 등 정보 선택**(출력 옵션으로 열 선택)
///    + **2줄 방지** + **미리보기** (기존 기본출력 법칙 그대로)
/// 3. 행사결산 — `참가자 수`(인가자·리더·로버·비버·스카우트·벤처·일반·기타 각 수
///    및 합산은 필수) + 참가비 + 후원금 + 후원 + 수송지원 등 + 행사비지출
///    (각종 지출·수품제작·기념물제작 등) + **출금계좌(대표 3계좌 선택/직접입력)**
///
/// 이 파일은 계산(집계)과 표 데이터 생성만 담당한다. 출력 실행(PDF/인쇄/미리보기)은
/// 기존 공용 엔진(`table_export.dart`, `tsak_output_sheet.dart`)을 그대로 쓴다.
library;

import '../models/member.dart';
import 'donation_kinds.dart';

/// 대표 계좌 1개 — 지출 시 어느 계좌에서 나갔는지 기록/선택한다.
class EventAccount {
  const EventAccount({
    required this.label,
    required this.bank,
    required this.account,
  });

  /// '대표' · '수품구매' · '행사비' 등 구분 이름.
  final String label;
  final String bank;
  final String account;

  /// '우리은행 1005-202-281140' 형태.
  String get display =>
      [bank.trim(), account.trim()].where((e) => e.isNotEmpty).join(' ');

  /// 선택지 라벨 — '행사비 · 우리은행 1005-003-886274'.
  String get pickLabel => display.isEmpty ? label : '$label · $display';

  bool get isValid => account.trim().isNotEmpty;
}

/// 참가자 수 집계 결과.
///
/// (요구) "인가자, 리더, 로버, 비버, 스카우트, 벤처, 일반, 기타의 각 참가자 수
/// 및 합산은 필수" — 이 순서를 그대로 유지한다.
class EventAttendeeBreakdown {
  const EventAttendeeBreakdown({
    this.ivga = 0,
    this.leader = 0,
    this.rover = 0,
    this.beaver = 0,
    this.scout = 0,
    this.venture = 0,
    this.regular = 0,
    this.etc = 0,
  });

  /// 인가자(범/은하 인가 보유자) — 다른 직책 분류가 없으면 여기로 센다.
  final int ivga;
  final int leader;
  final int rover;
  final int beaver;
  final int scout;
  final int venture;

  /// 일반(비인가 참가자).
  final int regular;
  final int etc;

  int get total =>
      ivga + leader + rover + beaver + scout + venture + regular + etc;

  /// 필수 표기 순서(요구 고정). 각 항목을 (라벨, 값) 쌍으로.
  List<MapEntry<String, int>> get ordered => [
    MapEntry('인가자', ivga),
    MapEntry('리더', leader),
    MapEntry('로버', rover),
    MapEntry('비버', beaver),
    MapEntry('스카우트', scout),
    MapEntry('벤처', venture),
    MapEntry('일반', regular),
    MapEntry('기타', etc),
  ];

  /// '인가자 5 · 리더 2 · … · 합계 12' 한 줄 요약.
  String get summaryLine =>
      '${ordered.map((e) => '${e.key} ${e.value}').join(' · ')} · 합계 $total';

  /// 결산 표에 넣을 행 목록(항목/인원 2열).
  List<List<String>> get rows => [
    for (final e in ordered) [e.key, '${e.value}명'],
    ['합계', '$total명'],
  ];

  /// 참가자 배열 → 직책별 집계.
  ///
  /// 판정 규칙(서버 `_ev_attendee_view` 와 동일한 우선순위):
  ///  · `corps` 가 있고 인가자면 → 인가자. 단 직책(roles)에 리더/로버/비버/
  ///    스카우트/벤처가 있으면 그 직책으로 센다(직책이 더 구체적).
  ///  · `corps` 가 비어 있으면 → 일반(비인가).
  ///  · 직책 문자열은 한글/영문 코드(L/B/S/V/R) 모두 인식한다.
  static EventAttendeeBreakdown fromAttendees(List<Map<String, dynamic>> list) {
    var ivga = 0, leader = 0, rover = 0, beaver = 0, scout = 0, venture = 0;
    var regular = 0, etc = 0;
    for (final a in list) {
      final roles = <String>[
        ...((a['roles'] as List?) ?? const []).map(
          (e) => e.trim().toLowerCase(),
        ),
        if ('${a['roleCode'] ?? ''}'.trim().isNotEmpty)
          '${a['roleCode']}'.trim().toLowerCase(),
        if ('${a['roleLabel'] ?? ''}'.trim().isNotEmpty)
          '${a['roleLabel']}'.trim().toLowerCase(),
      ];
      bool has(List<String> keys) =>
          roles.any((r) => keys.any((k) => r == k || r.contains(k)));

      final isRegular =
          a['isRegular'] == true ||
          '${a['corps'] ?? ''}'.trim().isEmpty &&
              !Member.numLabelOf('${a['number'] ?? ''}').contains('범');

      // 직책이 명시되어 있으면 직책 우선.
      if (has(const ['리더', 'leader', '지도자', 'l'])) {
        leader++;
      } else if (has(const ['로버', 'rover', '로버스카우트', 'r'])) {
        rover++;
      } else if (has(const ['비버', 'beaver', 'b'])) {
        beaver++;
      } else if (has(const ['벤처', 'venture', '벤쳐', 'v'])) {
        venture++;
      } else if (has(const ['스카우트', 'scout', 's']) &&
          !has(const ['로버', '벤처'])) {
        scout++;
      } else if (isRegular) {
        regular++;
      } else if ('${a['corps'] ?? ''}'.trim().isNotEmpty) {
        ivga++;
      } else if (has(const ['기타', 'etc'])) {
        etc++;
      } else {
        // 인가번호(number)가 있으면 인가자, 없으면 일반으로 본다.
        if ('${a['number'] ?? ''}'.trim().isEmpty) {
          regular++;
        } else {
          ivga++;
        }
      }
    }
    return EventAttendeeBreakdown(
      ivga: ivga,
      leader: leader,
      rover: rover,
      beaver: beaver,
      scout: scout,
      venture: venture,
      regular: regular,
      etc: etc,
    );
  }
}

/// 수입/지출 한 줄 — 표·합산 공용 정규화 형태.
class EventMoneyRow {
  const EventMoneyRow({
    required this.date,
    required this.category,
    required this.name,
    required this.number,
    required this.memo,
    required this.account,
    required this.amount,
    this.valueAmount,
    this.item = '',
    this.isExpense = false,
  });

  final String date;
  final String category;
  final String name;
  final String number;
  final String memo;

  /// 출금/입금 계좌 표기('행사비 · 우리은행 …'). 지출에서 주로 쓴다.
  final String account;
  final int amount;

  /// '금액 상당'(원) — 후원 현물처럼 정확한 현금이 아닌 항목.
  final int? valueAmount;

  /// 후원 내역('김밥 100줄', '버스 1대').
  final String item;

  final bool isExpense;

  /// 결산·출력 공통 표기 금액('1,234,000원').
  String get amountText => '${_comma(amount)}원';

  static String _comma(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}$b';
  }

  /// 재무 항목(fees/expenses) → 정규화 행.
  static EventMoneyRow fromMap(Map<String, dynamic> r, {bool expense = false}) {
    return EventMoneyRow(
      date: '${r['date'] ?? ''}'.trim(),
      category: '${r['category'] ?? (expense ? '행사비' : '참가비')}'.trim(),
      name: '${r['name'] ?? ''}'.trim(),
      number: '${r['number'] ?? ''}'.trim(),
      memo: '${r['memo'] ?? ''}'.trim(),
      account: '${r['account'] ?? ''}'.trim(),
      amount: (r['amount'] as num?)?.toInt() ?? 0,
      valueAmount: (r['value'] as num?)?.toInt(),
      item: '${r['item'] ?? ''}'.trim(),
      isExpense: expense,
    );
  }
}

/// 행사 결산 전체 결과.
class EventSettlement {
  const EventSettlement({
    required this.title,
    required this.year,
    required this.attendees,
    required this.fees,
    required this.expenses,
    required this.attendeeCount,
  });

  final String title;
  final String year;

  /// 참가비·후원금(수입).
  final List<EventMoneyRow> fees;

  /// 행사비지출.
  final List<EventMoneyRow> expenses;

  /// 참가자 원본(표 출력 시 이름·인가번호 열 선택용).
  final List<Map<String, dynamic>> attendees;

  /// 직책별 집계.
  final EventAttendeeBreakdown attendeeCount;

  /// 참가비 합계.
  int get feeTotal =>
      fees.where((e) => e.category == '참가비').fold(0, (s, e) => s + e.amount);

  /// 후원금 합계 — **현금 수입**. (요구: "후원금만 수입으로 잡을 것")
  int get donationFund => cashDonationTotal;

  /// 후원(현물·서비스)의 **현금** 합계 — 수입에 넣지 않는다.
  int get donation => sponsorCashTotal;

  /// 후원(현물·서비스)의 **상당액** 합계 — 수입에 넣지 않는다.
  int get donationValue => sponsorValueTotal;

  /// 참가비·후원금 외 현금 수입(기타수입).
  int get otherIncome =>
      fees.where((e) => e.category == '기타수입').fold(0, (s, e) => s + e.amount);

  /// 후원금(현금) 합계 — 수입 산정의 유일한 후원 항목.
  int get cashDonationTotal => fees
      .where((e) => DonationKind.parse(e.category) == DonationKind.cash)
      .fold(0, (s, e) => s + e.amount);

  /// 후원 관련 행만 — 참가비·기타수입 제외.
  ///  (버그 수정: parse() 가 모르는 분류를 '기타후원'으로 떨어뜨려
  ///   참가비·기타수입이 후원 합계에 섞이던 문제)
  Iterable<EventMoneyRow> get _sponsorRows => fees.where(
    (e) =>
        !DonationKind.isNonDonation(e.category) &&
        DonationKind.parse(e.category).isSponsor,
  );

  /// 후원(현물) 현금 합계.
  int get sponsorCashTotal => _sponsorRows.fold(0, (s, e) => s + e.amount);

  /// 후원(현물) 상당액 합계.
  int get sponsorValueTotal =>
      _sponsorRows.fold(0, (s, e) => s + (e.valueAmount ?? 0));

  /// 수입 합계 — (요구) **수입은 참가비 + 후원금만**.
  ///  후원(현물)·기타후원은 수입에 넣지 않는다. 기타수입(현금)은 참고로 더한다.
  int get incomeTotal => feeTotal + cashDonationTotal + otherIncome;

  /// 참고 표기용 — 후원(현물)의 가치(현금+상당). 수입에는 미포함.
  int get sponsorReferenceTotal => sponsorCashTotal + sponsorValueTotal;

  /// 지출 합계.
  int get expenseTotal => expenses.fold(0, (s, e) => s + e.amount);

  /// 잔액(수입 − 지출).
  int get balance => incomeTotal - expenseTotal;

  /// 지출을 계좌별로 묶은 합계 — '행사비 · 우리은행 …' → 금액.
  Map<String, int> get expenseByAccount {
    final map = <String, int>{};
    for (final e in expenses) {
      final key = e.account.trim().isEmpty ? '(계좌 미지정)' : e.account.trim();
      map[key] = (map[key] ?? 0) + e.amount;
    }
    return map;
  }

  /// 지출을 분류별(각종 지출·수품제작·기념품제작 등)로 묶은 합계.
  Map<String, int> get expenseByCategory {
    final map = <String, int>{};
    for (final e in expenses) {
      final key = e.category.trim().isEmpty ? '(미분류)' : e.category.trim();
      map[key] = (map[key] ?? 0) + e.amount;
    }
    return map;
  }

  static String comma(int v) => EventMoneyRow._comma(v);

  /// 수입/지출/잔액 3행 요약(모든 결산 출력 공통).
  List<List<String>> get summaryRows => [
    ['구분', '금액', '비고'],
    ['수입 계', '${comma(incomeTotal)}원', '참가비·후원·기타'],
    ['지출 계', '${comma(expenseTotal)}원', '행사비·제작비 등'],
    ['잔액', '${comma(balance)}원', balance >= 0 ? '잔액 발생' : '초과 지출'],
  ];
}
