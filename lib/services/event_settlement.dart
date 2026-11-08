/// 행사 결산 · 항목별 출력 계산 서비스.
///
/// ## 요구사항 정리
/// 1. 참가비/후원금, 후원·기타수입, 행사비지출, 행사결산 4개 탭으로 세분화
/// 2. 각 항목별 출력 — **합산 기능** + **연번·이름 등 정보 선택**(출력 옵션으로 열 선택)
///    + **2줄 방지** + **미리보기** (기존 기본출력 법칙 그대로)
/// 3. 행사결산 — `참가자 수`(인가자·리더·로버·벤처·스카우트·**컵**·비버·일반·기타
///    각 수 및 합산은 필수) + 참가비 + 후원금 + 후원 + 수송지원 등 + 행사비지출
///    (각종 지출·수품제작·기념물제작 등) + **출금계좌(대표 3계좌 선택/직접입력)**
///
/// 이 파일은 계산(집계)과 표 데이터 생성만 담당한다. 출력 실행(PDF/인쇄/미리보기)은
/// 기존 공용 엔진(`table_export.dart`, `tsak_output_sheet.dart`)을 그대로 쓴다.
library;

import 'attendee_roles.dart';
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
    this.cub = 0,
    this.venture = 0,
    this.regular = 0,
    this.etc = 0,
    int? headCount,
    this.leaderLicensed = 0,
  }) : headCount = headCount ?? (ivga + leader + rover + beaver + scout + cub + venture + regular + etc);

  /// 인가자(범/은하 인가 보유자) — **직책과 무관하게** 인가번호를 가진 사람 전부.
  ///
  /// [요구 2026-11-07] "참가자 중 범스카우트 인가자가 리더로 선택할 경우에도
  ///  인가자 항목에 인원을 넣을 것"
  ///
  ///  종전에는 직책이 `리더` 면 그 사람이 인가번호를 갖고 있어도 인가자에
  ///  들어가지 않았다(직책 우선). 그래서 2026 범2호 추모행사 8명 중
  ///  인가번호 보유자 6명인데도 화면에는 **인가자 2명**으로 나왔다.
  ///  이제 인가자 = 인가번호 보유자 전원(리더 4명 포함)이다.
  ///
  ///  ⚠️ 합계([total])는 **사람 수**이지 항목 합이 아니다.
  ///  인가자는 리더·로버 등과 **일부러 겹쳐 세므로**, 항목을 그대로 더하면
  ///  한 사람이 두 번 잡힌다. 그래서 [licensedTotal]·[leaderLicensed] 로
  ///  겹침을 드러내고, total 은 `명단 행 수` 로 따로 계산한다.
  final int ivga;
  final int leader;
  final int rover;
  final int beaver;
  final int scout;

  /// 컵스카우트 — [2026-10-29] 종전 8종 표에 **자리가 없어** 인가자로
  /// 흡수되던 직책. 이제 정식 항목이다.
  final int cub;

  final int venture;

  /// 일반(비인가 참가자).
  final int regular;
  final int etc;

  /// 명단 **행 수**(사람 수). 인가자는 직책과 겹치므로 항목 합으로 구할 수 없다.
  final int headCount;

  /// 인가자 중 **리더로도 잡힌** 사람 수 — 화면에 '리더 4명 포함' 근거로 쓴다.
  final int leaderLicensed;

  /// 인가번호 보유자 총원(= [ivga]). 이름만 다르게 읽기 쉽게 둔다.
  int get licensedTotal => ivga;

  int get total => headCount;

  /// 항목을 그대로 더한 값 — 겹침 검증용(테스트·디버그 전용, 화면 표시 X).
  int get rawItemSum =>
      ivga + leader + rover + venture + scout + cub + beaver + regular + etc;

  /// 인가자 줄에 붙일 근거 문구 — '리더 4명 포함' / 없으면 ''.
  String get ivgaNote =>
      leaderLicensed <= 0 ? '' : '리더 $leaderLicensed명 포함';

  /// 필수 표기 순서(요구 고정). 각 항목을 (라벨, 값) 쌍으로.
  /// 상위 섹션 → 하위 섹션 순(컵·비버는 스카우트 아래).
  List<MapEntry<String, int>> get ordered => [
    MapEntry('인가자', ivga),
    MapEntry(AttendeeRole.leader, leader),
    MapEntry(AttendeeRole.rover, rover),
    MapEntry(AttendeeRole.venture, venture),
    MapEntry(AttendeeRole.scout, scout),
    MapEntry(AttendeeRole.cub, cub),
    MapEntry(AttendeeRole.beaver, beaver),
    MapEntry(AttendeeRole.regular, regular),
    MapEntry(AttendeeRole.etc, etc),
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
  /// ## [2026-11-07 요구] 인가자 = 인가번호 보유자 **전원**
  ///
  /// "참가자 중 범스카우트 인가자가 리더로 선택할 경우에도 인가자 항목에
  ///  인원을 넣을 것"
  ///
  ///  종전에는 ① 직책 우선이라 `roles: ['리더']` 인 사람은 인가번호가 있어도
  ///  리더에만 잡혔다. 2026 범2호 추모행사 8명 기준:
  ///    김종환 #135(리더) · 이승준 #415(리더) · 김병혁 #417(리더)
  ///    양다솜 #1346(리더) → 인가자로 안 세어져 **인가자 2명**으로 표시됐다.
  ///  정우식 #278 · 송영선 #1064 는 직책이 없어 인가자 2명.
  ///  실제 인가번호 보유자는 **6명**이다.
  ///
  ///  이제 두 가지를 **동시에** 기록한다:
  ///    · [ivga]          = 인가번호 보유자 전원 (리더여도 포함)
  ///    · [leader] 등     = 직책별 인원 (종전 그대로)
  ///    · [headCount]     = 명단 행 수 (합계는 이 값 — 겹침 없음)
  ///    · [leaderLicensed]= 인가자이면서 리더인 사람 수
  ///
  /// ## [2026-10-29 "컵" 사고] 는 그대로 지킨다
  ///
  /// 종전 규칙은 **직책이 표에 없으면 마지막 fallback** 으로 흘러가
  /// `number` 가 비어 있지 않으면 인가자로 셌다. 그래서
  ///   · `roles: ['컵']`(어야영) → 인가자
  ///   · `number: '류호준'`(이름이 인가번호 칸에) → 인가자
  /// 처럼 **갈 곳 없는 행이 전부 인가자로 흡수**됐다.
  /// 그래서 인가번호 판정은 [AttendeeRoles.hasLicenseOnRow] 로 **엄격하게**
  /// 한다(이름·전화번호·자유입력은 인가번호로 보지 않는다).
  static EventAttendeeBreakdown fromAttendees(List<Map<String, dynamic>> list) {
    var ivga = 0,
        leader = 0,
        rover = 0,
        venture = 0,
        scout = 0,
        cub = 0,
        beaver = 0,
        regular = 0,
        etc = 0,
        leaderLicensed = 0;

    for (final a in list) {
      // ── ① 인가자 — 직책과 **무관하게** 인가번호 보유자면 센다. ──────
      final licensed = AttendeeRoles.hasLicenseOnRow(a);
      if (licensed) ivga++;

      // ── ② 직책별 인원 (종전 그대로) ────────────────────────────────
      final role = AttendeeRoles.canonicalOfRow(a);
      if (role != null) {
        switch (role) {
          case AttendeeRole.leader:
            leader++;
            if (licensed) leaderLicensed++;
          case AttendeeRole.rover:
            rover++;
          case AttendeeRole.venture:
            venture++;
          case AttendeeRole.scout:
            scout++;
          case AttendeeRole.cub:
            cub++;
          case AttendeeRole.beaver:
            beaver++;
          case AttendeeRole.regular:
            regular++;
          default:
            etc++;
        }
        continue;
      }

      // ── ③ 직책 없음 → 신원으로 판정 ────────────────────────────────
      if (AttendeeRoles.isRegularRow(a)) {
        regular++;
      } else if (!licensed) {
        // 인가자도 일반도 아닌 애매한 행 → 일반으로 센다(인가자 부풀림 금지).
        regular++;
      }
      // licensed == true 면 이미 인가자로 셌다 — 일반으로 또 세지 않는다.
    }
    return EventAttendeeBreakdown(
      ivga: ivga,
      leader: leader,
      rover: rover,
      venture: venture,
      scout: scout,
      cub: cub,
      beaver: beaver,
      regular: regular,
      etc: etc,
      headCount: list.length,
      leaderLicensed: leaderLicensed,
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

  // ── [버그 수정 turn 79] 결산서 '참가비 N명 납부' 의 N 이 틀리던 문제 ──
  //
  // ## 실제 증상 (사용자 스크린샷)
  //   2026 범2호 노경하선배 추모행사 결산서
  //     수입 / 참가비  600,000원   **9명 납부**   ← 실제 참가자는 6명
  //     수입 / 후원금  300,000원   3건
  //     상세 내역                         9건
  //   10만원 × 6명 = 60만원이므로 정답은 **6명**이다.
  //
  // ## 원인
  //   `settlement_layout.dart` 의 payers 계산이
  //       settlement.fees.where((e) => e.amount > 0).length
  //   였다. `fees` 에는 **참가비·후원금·기타수입이 모두** 들어 있으므로
  //   참가비 6건 + 후원금 3건 = 9 가 된 것이다.
  //   (`feeTotal` 은 `category == '참가비'` 만 합산하므로 금액 60만원은
  //    정확했다. 금액과 인원수가 **서로 다른 기준**으로 계산된 것이 원인)
  //
  // ## 수정
  //   금액과 인원이 **같은 조건**을 쓰도록 아래 getter 를 두고
  //   `feeTotal` 과 한 쌍으로 쓴다. 후원금이 몇 건이든 인원수에 영향이 없다.
  //
  // ## 후원금의 귀속
  //   후원금은 아래 [cashDonationTotal] 로 **'후원금' 항목**에만 집계되고
  //   참가비에는 절대 더해지지 않는다(`feeTotal` 은 '참가비'만 본다).
  //   수입 합계는 `참가비 + 후원금 + 기타수입` 이므로 이중 계상도 없다.

  /// 참가비를 낸 **행 수** (= 결제 건수).
  int get feePayCount =>
      fees.where((e) => e.category == '참가비' && e.amount > 0).length;

  /// 참가비를 낸 **사람 수** — 이름/인가번호/행ID 로 중복을 제거한다.
  ///
  /// 한 사람이 두 번 납부했거나(분할 납부·가족 대납) 같은 이름이 둘일 때
  /// 결제 건수를 그대로 '명'으로 표시하면 인원이 부풀려진다.
  /// 식별자가 전혀 없으면 행 수로 되돌아간다(집계가 0이 되는 것 방지).
  int get feePayerCount {
    final ids = <String>{};
    var noIdent = 0;
    for (final e in fees) {
      if (e.category != '참가비' || e.amount <= 0) continue;
      final key = _payerKey(e);
      if (key.isEmpty) {
        noIdent++;
      } else {
        ids.add(key);
      }
    }
    final n = ids.length + noIdent;
    return n == 0 ? feePayCount : n;
  }

  /// 참가비 납부자의 **1인당 금액**. 참가비가 없으면 0.
  ///  10만원 × 6명처럼 금액이 일정하면 결산서에 근거를 함께 보여 준다.
  int get feePerPayer {
    final n = feePayerCount;
    if (n <= 0) return 0;
    final t = feeTotal;
    return t % n == 0 ? t ~/ n : 0;   // 나누어떨어질 때만 의미가 있다
  }

  static String _payerKey(EventMoneyRow e) {
    final no = e.number.replaceAll(RegExp(r'[^0-9]'), '');
    if (no.isNotEmpty) return 'n:$no';
    final nm = e.name.trim();
    if (nm.isNotEmpty) return 'm:$nm';
    return '';
  }

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
