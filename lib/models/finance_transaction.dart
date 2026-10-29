/// 재무 거래(입금/지출) 모델
/// 요구사항: 후원/수품구매/참가비 등 수입과 지출을 인가자별·연도별·행사별로
///           집계하고, 입금자 텍스트에서 이름/번호/행사명을 인식해 동일인으로 기록한다.
class FinanceTransaction {
  FinanceTransaction({
    this.id = '',
    this.date = '',
    this.type = 'income', // income | expense
    this.payer = '',
    this.name = '',
    this.number = '',
    this.memberId = '',
    this.amount = 0,
    this.category = '기타',
    this.event = '',
    this.context = '',
    this.memo = '',
    this.status = 'unmatched', // matched | unmatched
    this.year = '',
    this.source = '', // manual | bank | excel
    this.corps = '',
  });

  String id;
  String date;

  /// income(입금) | expense(지출)
  String type;

  /// 입금자 원문 (예: "홍길동 제405단 후원")
  String payer;

  /// 표시 이름
  String name;

  /// 인가번호 (매칭된 경우)
  String number;

  /// 인가자 id (매칭된 경우)
  String memberId;

  int amount;

  /// 분류 (후원/수품구매/참가비/연회비/기타/행사비/운영비 ...)
  String category;

  /// 행사명 (있으면)
  String event;

  /// 이름 앞뒤 잔여 텍스트 등 맥락
  String context;

  String memo;
  String status;
  String year;

  /// 입력 경로: manual(직접입력) | bank(은행파일) | excel
  String source;

  /// 소속 — `tsak`(범스카우트) | `eunha`(은하스카우트) | ''(미지정).
  ///
  /// ## [버그 수정 2026-10-29] 범 75호와 은하 G75 가 같은 사람이 되던 문제
  /// 서버는 처음부터 `corps` 를 내려주고 있었는데 이 모델이 필드를 갖고
  /// 있지 않아 **조용히 버려졌다**. 그래서 번호만 비교할 수밖에 없었고,
  /// `G75` → `75` 로 숫자만 남기는 정규화 탓에 은하 G75(김건우)가
  /// 범 75호(이항복)의 후원 내역을 그대로 받았다.
  /// 이제 신원은 **(corps, 번호)** 두 값으로 판정한다.
  String corps;

  /// 은하스카우트 소속인가.
  bool get isEunha => corps == 'eunha';

  int get numberInt =>
      int.tryParse(number.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  bool get isExpense => type == 'expense';
  bool get matched => status == 'matched';

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date,
    'type': type,
    'payer': payer,
    'name': name,
    'number': number,
    'memberId': memberId,
    'amount': amount,
    'category': category,
    'event': event,
    'context': context,
    'memo': memo,
    'status': status,
    'year': year,
    'source': source,
    'corps': corps,
  };

  /// 소속 추정 — 서버가 corps 를 안 내려준 **레거시 거래**용 보정.
  ///
  ///  · 이미 corps 가 있으면 그대로 쓴다.
  ///  · 번호가 `G…`/`은하…` 로 시작하면 은하, 아니면 범.
  ///  · 번호가 없으면 빈 값 — 어느 쪽에도 귀속하지 않는다(안전).
  static String inferCorps(String number, String corps) {
    final c = corps.trim().toLowerCase();
    if (c == 'eunha' || c == 'tsak') return c;
    final s = number.trim();
    if (s.isEmpty) return '';
    final low = s.toLowerCase();
    if (low.startsWith('g') || s.startsWith('은하') ||
        s.startsWith('갤럭시')) {
      return 'eunha';
    }
    return 'tsak';
  }

  factory FinanceTransaction.fromMap(Map<dynamic, dynamic> m) {
    final date = '${m['date'] ?? ''}';
    final year = '${m['year'] ?? ''}'.isNotEmpty
        ? '${m['year']}'
        : (RegExp(r'(20\d{2})').firstMatch(date)?.group(1) ?? '');
    return FinanceTransaction(
      id: '${m['id'] ?? ''}',
      date: date,
      type: '${m['type'] ?? 'income'}',
      payer: '${m['payer'] ?? ''}',
      name: '${m['name'] ?? ''}',
      number: '${m['number'] ?? ''}',
      memberId: '${m['memberId'] ?? ''}',
      amount: (m['amount'] is num)
          ? (m['amount'] as num).toInt()
          : int.tryParse(
                  '${m['amount'] ?? 0}'.replaceAll(RegExp(r'[^0-9\-]'), ''),
                ) ??
                0,
      category: '${m['category'] ?? '기타'}',
      event: '${m['event'] ?? ''}',
      context: '${m['context'] ?? ''}',
      memo: '${m['memo'] ?? ''}',
      status: '${m['status'] ?? 'unmatched'}',
      year: year,
      source: '${m['source'] ?? ''}',
      corps: FinanceTransaction.inferCorps(
        '${m['number'] ?? ''}',
        '${m['corps'] ?? ''}',
      ),
    );
  }

  FinanceTransaction copyWith({
    String? date,
    String? type,
    String? payer,
    String? name,
    String? number,
    String? memberId,
    int? amount,
    String? category,
    String? event,
    String? context,
    String? memo,
    String? status,
    String? year,
    String? source,
    String? corps,
  }) => FinanceTransaction(
    id: id,
    date: date ?? this.date,
    type: type ?? this.type,
    payer: payer ?? this.payer,
    name: name ?? this.name,
    number: number ?? this.number,
    memberId: memberId ?? this.memberId,
    amount: amount ?? this.amount,
    category: category ?? this.category,
    event: event ?? this.event,
    context: context ?? this.context,
    memo: memo ?? this.memo,
    status: status ?? this.status,
    year: year ?? this.year,
    source: source ?? this.source,
    corps: corps ?? this.corps,
  );
}

/// 인가자별 입금 집계
class MemberDepositSummary {
  MemberDepositSummary({
    required this.number,
    required this.name,
    this.total = 0,
    Map<String, int>? byCategory,
    Map<String, int>? byYear,
    List<FinanceTransaction>? history,
  }) : byCategory = byCategory ?? {},
       byYear = byYear ?? {},
       history = history ?? [];

  String number;
  String name;
  int total;
  Map<String, int> byCategory;
  Map<String, int> byYear;
  List<FinanceTransaction> history;
}
