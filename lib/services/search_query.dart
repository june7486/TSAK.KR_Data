/// 검색어 **표기 해석** 계층 — 인가번호 표기를 (소속, 번호, 나머지 키워드)로 분해한다.
///
/// ## 왜 필요한가 (요구 2026-11-02, build #579)
///   요구(원문): "검색기능: 범스카우 번호, 예를들면 범415 로 검색해도 검색결과가
///               안나옴, 은하19호 같이 검색해도 은하스카우트가 안 나옴"
///
///   종전 `_applyQuery` 는 검색어를 **부분 문자열**로만 봤다
///   (`parts.every((p) => m.searchText.contains(p))`). 그런데 `Member.searchText`
///   에는 `'415'` 와 `'범'` 이 **따로** 들어 있어 `'범415'` 라는 연속 문자열은
///   절대 존재하지 않는다 → 사람이 부르는 이름으로는 검색이 안 됐다.
///
///   이 클래스는 그 간극을 메운다. 문자열 매칭이 아니라 **의미**로 읽는다.
///
///     범415      → (tsak,  415)
///     범 415호   → (tsak,  415)
///     은하19호   → (eunha, 19)
///     은하 19    → (eunha, 19)
///     갤럭시19   → (eunha, 19)
///     G19 / g-19 → (eunha, 19)
///     #415       → ('',    415)
///     415        → ('',    415)
///     은하       → (eunha, null)   ← 소속만 지목
///     은하 이승  → (eunha, null, ['이승'])
///
/// ## 소속 판정 규칙
///   · `tsak`  = 범스카우트(범) — `corps != 'eunha'` 인 모든 회원(일반회원 포함)
///   · `eunha` = 은하스카우트(은하 · 갤럭시 · G · galaxy · eunha)
///   · `''`    = 소속 미지정(둘 다 후보)
///
/// 순수 함수만 둔다(모델·상태 의존 없음) → 단위 테스트가 그대로 가능하다.
class SearchQuery {
  const SearchQuery({
    this.corps = '',
    this.number,
    this.tokens = const <String>[],
  });

  /// `'tsak'` | `'eunha'` | `''`(미지정)
  final String corps;

  /// 인가번호 숫자부. null = 번호 미지정(소속만 지목한 경우).
  final int? number;

  /// 소속·번호를 걷어낸 나머지 키워드(이름·지역대 등). 소문자.
  final List<String> tokens;

  static const String corpsTsak = 'tsak';
  static const String corpsEunha = 'eunha';

  bool get hasCorps => corps.isNotEmpty;
  bool get hasNumber => number != null;
  bool get isNotation => hasCorps || hasNumber;

  /// 배지·안내용 사람이 읽는 문구.
  String get label {
    final c = corps == corpsEunha ? '은하' : (corps == corpsTsak ? '범' : '');
    final n = number;
    if (c.isEmpty && n == null) return '';
    if (c.isEmpty) return '인가번호 $n';
    if (n == null) return c;
    return '$c $n호';
  }

  /// 소속 단어 → 소속 코드. 긴 단어부터 검사해야 '은하스카우트' 가
  /// '은하' 로 잘리지 않는다.
  static const Map<String, String> _corpsWords = <String, String>{
    '은하스카우트': corpsEunha,
    '은하스카우': corpsEunha,
    '범스카우트': corpsTsak,
    '범스카우': corpsTsak,
    '범스카웃': corpsTsak,
    '갤럭시': corpsEunha,
    'galaxy': corpsEunha,
    'eunha': corpsEunha,
    'tsak': corpsTsak,
    '은하': corpsEunha,
    '범': corpsTsak,
  };

  /// 소속 판정 — 접두어가 **소속 단어 + (숫자/끝)** 형태일 때만 인정한다.
  ///  ('범위' 같은 단어를 소속으로 오인하지 않기 위한 가드)
  static ({String corps, String rest}) _splitCorps(String token) {
    final low = token.toLowerCase();
    final keys = _corpsWords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      if (!low.startsWith(k)) continue;
      final rest = low.substring(k.length);
      // 남은 부분이 비었거나 숫자(+호/번) 형태여야 한다.
      if (rest.isEmpty || RegExp(r'^[-#]?\d{1,5}(호|번)?$').hasMatch(rest)) {
        return (corps: _corpsWords[k]!, rest: rest);
      }
    }
    return (corps: '', rest: low);
  }

  /// 숫자 토큰 판정 — '415' / '415호' / '#415' / '번호415'
  static final RegExp _numRe = RegExp(r'^[-#]?(\d{1,5})(호|번)?$');

  /// 소속·번호와 무관한 잡음 토큰 — 검색 대상 텍스트에 없는 말들.
  static const Set<String> _noise = <String>{
    '스카우트',
    '스카우',
    'scout',
    '번호',
    '인가번호',
    '인가',
    '호',
    '번',
    'no',
    'no.',
  };

  /// 검색어를 해석한다. 표기 해석이 불가능하면 [isNotation] 이 false 인 객체.
  static SearchQuery parse(String raw) {
    final src = raw.trim();
    if (src.isEmpty) return const SearchQuery();

    // 전화번호 꼴(010-1234-5678)은 표기 해석 대상이 아니다.
    if (RegExp(r'\d{2,4}\s*-\s*\d{3,4}\s*-\s*\d{4}').hasMatch(src)) {
      return const SearchQuery();
    }
    // 인가번호 범위(1-100)도 표기 해석 대상이 아니다(별도 분기에서 처리).
    if (RegExp(r'^\s*\d{1,5}\s*[-~]\s*\d{1,5}\s*$').hasMatch(src)) {
      return const SearchQuery();
    }

    var corps = '';
    int? number;
    final tokens = <String>[];

    for (final rawTok in src.split(RegExp(r'\s+'))) {
      final tok = rawTok.trim();
      if (tok.isEmpty) continue;

      // ① G19 / g-19 / G#19 — 은하 접두어(한 글자 G)
      final g = RegExp(
        r'^g[-#]?(\d{1,5})(호|번)?$',
        caseSensitive: false,
      ).firstMatch(tok);
      if (g != null) {
        if (corps.isEmpty) corps = corpsEunha;
        number ??= int.tryParse(g.group(1)!);
        continue;
      }

      // ② 소속 단어(+번호 붙여쓰기): 범415 / 은하19호 / 범스카우트 12
      final sp = _splitCorps(tok);
      if (sp.corps.isNotEmpty) {
        if (corps.isEmpty) corps = sp.corps;
        if (sp.rest.isEmpty) continue;
        final n = _numRe.firstMatch(sp.rest);
        if (n != null) number ??= int.tryParse(n.group(1)!);
        continue;
      }

      // ③ 숫자 단독: 415 / #415 / 415호
      final n = _numRe.firstMatch(sp.rest);
      if (n != null) {
        number ??= int.tryParse(n.group(1)!);
        continue;
      }

      // ④ 나머지 = 키워드
      final low = tok.toLowerCase();
      if (_noise.contains(low)) continue;
      tokens.add(low);
    }

    return SearchQuery(corps: corps, number: number, tokens: tokens);
  }

  /// 번호에 **표기 신호**가 붙어 있는가 — `415호` / `#415` / `G19` / `번호415`.
  ///  맨숫자(`415`)는 false. (일반 통합검색이 더 넓게 잡아주기 때문 —
  ///  지역대명 '79' · 전화번호 등과 겹치지 않게 하려는 의도적 보수성)
  static bool hasNumberNotation(String q) {
    if (!RegExp(r'\d').hasMatch(q)) return false;
    if (q.contains('#')) return true;
    if (RegExp(r'\d\s*[호번]').hasMatch(q)) return true;
    if (RegExp(r'번호').hasMatch(q)) return true;
    if (RegExp(r'(^|\s)g[-#]?\d', caseSensitive: false).hasMatch(q)) {
      return true;
    }
    return false;
  }

  /// 검색어의 소속 지목과 회원 소속이 맞는가.
  ///  범(tsak)은 은하가 아닌 모든 회원(일반회원 포함)을 뜻한다.
  static bool corpsMatches(String want, String memberCorps) {
    if (want.isEmpty) return true;
    final mc = memberCorps.trim().toLowerCase();
    if (want == corpsEunha) return mc == corpsEunha;
    return mc != corpsEunha;
  }
}
