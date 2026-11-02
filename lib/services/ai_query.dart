/// AI 자연어 검색 파서
///
/// 사용자가 자연어로 입력한 검색어를 의도(Intent)로 해석한다.
///  예) "2026년 연회비 납부자 명단"        → 연회비 납부자 (2026)
///      "현재까지 후원자 명단"             → 후원자 전체
///      "한국잼버리 후원자 명단과 금액 정리" → 한국잼버리 후원자
///      "2025 정기총회 참석자 명단"        → 행사 참석자
///      "평생회원 명단"                   → 평생회원
///      "범415"                          → 인가번호 415 (범스카우트)
///      "은하19호"                        → 인가번호 19 (은하스카우트)
///
/// 서버/외부 API 없이 규칙 기반으로 온디바이스에서 동작한다(오프라인 지원).
///
/// ## [2026-11-02 build #579] 자연어 검색을 **기본기능**으로
///   요구(원문): "자연어 검색을 기본기능으로 하려고 했었는데, 이 부분 업데이트
///               또는 수정 부탁해요."
///
///   ① 인가번호 표기(`범415`·`은하19호`·`G19`)는 **신호어 없이도** 즉시 해석한다.
///      (`SearchQuery` 로 위임 → `AiKind.credential`)
///   ② 신호어 기반 해석은 종전의 `length >= 4` 문턱을 없애고, **신호어가 있으면
///      길이와 무관하게** 동작하게 했다. ("회비" 두 글자도 이제 검색된다.)
library;

import 'search_query.dart';

enum AiKind {
  feePaid,
  donor,
  eventAttend,
  training,
  lifetime,

  /// 인가번호·소속 지목 (예: 범415 / 은하19호 / G19 / 은하 / 영남 12)
  credential,
}

class AiQuery {
  AiQuery({
    required this.kind,
    this.year = '',
    this.keyword = '',
    this.corps = '',
    this.number,
  });

  final AiKind kind;

  /// 회비 연도 (예: "2026")
  final String year;

  /// 행사명/훈련 키워드 등 핵심 키워드
  final String keyword;

  /// [AiKind.credential] 소속 지목 — 'tsak' | 'eunha' | ''
  final String corps;

  /// [AiKind.credential] 인가번호. null = 소속만 지목.
  final int? number;

  /// AI 검색으로 인식되기 위한 신호 단어
  static const _signals = [
    '명단',
    '목록',
    '리스트',
    '납부자',
    '후원자',
    '참가자',
    '참석자',
    '평생회원',
    '납부',
    '연회비',
    '회비',
    '정리',
    '알려',
    '보여',
    '훈련',
    '과정',
    '현재까지',
    '지금까지',
    '총액',
    '합계',
  ];

  /// 키워드 추출 시 제거할 불용어
  static const _stopwords = [
    '명단',
    '목록',
    '리스트',
    '후원자',
    '납부자',
    '참가자',
    '참석자',
    '평생회원',
    '연회비',
    '납부',
    '정리',
    '알려줘',
    '알려',
    '보여줘',
    '보여',
    '현재까지',
    '지금까지',
    '금액',
    '합계',
    '총액',
    '대한',
    '관련',
    '그리고',
    '내역',
    '현황',
    '가져와',
    '줘',
    '의',
    '과',
    '와',
    '년',
    '한',
  ];

  /// 자연어 검색으로 해석 가능하면 [AiQuery] 반환, 아니면 null
  static AiQuery? tryParse(String raw) {
    final q = raw.trim();
    if (q.isEmpty) return null;

    // 인가번호 표기(범415 / 은하19호 / G19) — 신호어 없이도 즉시 해석.
    //  단, 단독 숫자('415')는 표기 해석이 아니라 일반 통합검색에 맡긴다
    //  (지역대명·전화번호 등과 겹치지 않게 하기 위함). 소속이 함께
    //  지목됐거나 '호/번/G' 같은 표기 신호가 있을 때만 AI 로 승격한다.
    final sq = SearchQuery.parse(q);
    if (sq.hasCorps) {
      return AiQuery(
        kind: AiKind.credential,
        keyword: sq.tokens.join(' '),
        corps: sq.corps,
        number: sq.number,
      );
    }
    if (sq.hasNumber && SearchQuery.hasNumberNotation(q)) {
      return AiQuery(
        kind: AiKind.credential,
        keyword: sq.tokens.join(' '),
        corps: '',
        number: sq.number,
      );
    }

    // 신호어 기반 해석 — 신호어가 있으면 길이 제한 없이 동작한다.
    if (!_signals.any(q.contains)) return null;

    final year = RegExp(r'(20\d{2})\s*년').firstMatch(q)?.group(1) ?? '';

    // 의도 판정 (우선순위: 후원 > 참석 > 납부 > 훈련 > 평생회원)
    if (q.contains('후원') || q.contains('찬조') || q.contains('기부')) {
      return AiQuery(kind: AiKind.donor, year: year, keyword: _extract(q));
    }
    if (q.contains('참가') || q.contains('참석') || q.contains('행사')) {
      return AiQuery(
        kind: AiKind.eventAttend,
        year: year,
        keyword: _extract(q),
      );
    }
    if (q.contains('납부') || q.contains('연회비') || q.contains('회비')) {
      return AiQuery(kind: AiKind.feePaid, year: year, keyword: _extract(q));
    }
    if (q.contains('훈련') || q.contains('과정') || q.contains('교수')) {
      return AiQuery(kind: AiKind.training, year: year, keyword: _extract(q));
    }
    if (q.contains('평생회원')) {
      return AiQuery(kind: AiKind.lifetime, year: year, keyword: '');
    }
    return null;
  }

  /// 불용어·연도·공백을 제거한 핵심 키워드
  static String _extract(String q) {
    var s = q.replaceAll(RegExp(r'20\d{2}\s*년'), ' ');
    s = s.replaceAll(RegExp(r'20\d{2}'), ' ');
    for (final w in _stopwords) {
      s = s.replaceAll(w, ' ');
    }
    s = s.replaceAll(RegExp(r'[^\uAC00-\uD7A3a-zA-Z0-9]+'), ' ').trim();
    // 너무 짧은(1글자) 토큰은 무시
    final tokens = s
        .split(RegExp(r'\s+'))
        .where((t) => t.trim().length >= 2)
        .toList();
    return tokens.join(' ');
  }

  /// 사람이 읽을 수 있는 라벨
  String get label {
    switch (kind) {
      case AiKind.feePaid:
        return '$year${year.isEmpty ? '' : '년 '}연회비 납부자';
      case AiKind.donor:
        return '${keyword.isEmpty ? '' : '$keyword '}후원자';
      case AiKind.eventAttend:
        return '${keyword.isEmpty ? '' : '$keyword '}참석자';
      case AiKind.training:
        return '${keyword.isEmpty ? '' : '$keyword '}훈련현황';
      case AiKind.lifetime:
        return '평생회원';
      case AiKind.credential:
        final c = corps == SearchQuery.corpsEunha
            ? '은하'
            : (corps == SearchQuery.corpsTsak ? '범' : '');
        final n = number;
        if (c.isEmpty && n == null) return keyword;
        if (c.isEmpty) return '$n호';
        if (n == null) return '$c스카우트';
        return '$c $n호';
    }
  }
}
