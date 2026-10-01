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
  };

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
