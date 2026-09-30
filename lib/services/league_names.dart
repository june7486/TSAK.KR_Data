/// 연맹명(league) 정규화 — 통계·프로필·필터의 표기 불일치를 근본 해결한다.
///
/// ## 왜 필요한가 (요구: "범스카우트 통계 오류 해결")
/// 기존 홈피·수기 입력·주소록 이관 등에서 같은 연맹이 여러 이름으로 들어와,
/// 통계에서 **별개 연맹으로 쪼개져** 집계되는 문제가 있었다.
///   예) 광주연맹(5) + 광주(233) → 실제로는 '광주' 238명
///       인천연맹(1) + 인천(175) + 인천→서울북부(2) → '인천' 178명
///
/// 이 함수를 데이터 로딩 지점(Member.fromMap)에서 1회 적용하면
/// 통계·프로필·필터·내보내기 등 **모든 화면이 자동으로 정합**된다.
library;

/// 명시적 별칭 → 표준명 (사용자 지정 매핑).
///
/// '연맹' 접미사가 붙은 변형은 아래 [_stripSuffix] 로도 자동 정리되지만,
/// 의도가 명확한 항목은 여기서 고정한다.
const Map<String, String> kLeagueAlias = {
  // 연맹 접미사 변형
  '광주연맹': '광주',
  '경기북부연맹': '경기북부',
  '인천연맹': '인천',
  '부산연맹': '부산',
  '서울남부연맹': '서울남부',
  '경남연맹': '경남',
  '기독교연맹': '기독교',
  // 이동/ 병기 표현 → 실제 소속
  '인천→서울북부': '인천',
  '인천->서울북부': '인천',
  '인천 ∼ 서울북부': '인천',
  '인천~서울북부': '인천',
  '서울북부←인천': '인천',
  // 구분자 통일 후 잔여 표현
  '충남·세종': '충남·세종',
  '충남.세종': '충남·세종',
  '충남 세종': '충남·세종',
};

/// 연맹명에서 흔한 접미사/잡음 제거.
String _stripSuffix(String s) {
  var t = s;
  // '연맹' 접미사 제거 (표준 연맹명에는 '연맹'으로 끝나는 것이 없음)
  if (t.endsWith('연맹') && t.length > 2) {
    t = t.substring(0, t.length - 2).trim();
  }
  return t;
}

/// 원본 연맹 문자열 → 표준 연맹명.
///
/// - 앞뒤 공백·중복 공백 정리
/// - 화살표/물결 등 구분자 통일 후 별칭 매핑
/// - '연맹' 접미사 제거 폴백
String normalizeLeague(String? raw) {
  final s = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return '';
  // 복수 연맹 표기(예: '서울남부연맹, 인천연맹, 제주') → 각 토큰 정규화 후 병기.
  //   콤마/가운뎃점/열거점이 있으면 토큰별로 처리해 통계가 쪼개지지 않게 한다.
  if (RegExp(r'[,、]').hasMatch(s)) {
    final parts = <String>[];
    for (final t in s.split(RegExp(r'[,、]'))) {
      final n = _normalizeSingle(t);
      if (n.isNotEmpty && !parts.contains(n)) parts.add(n);
    }
    return parts.join(', ');
  }
  return _normalizeSingle(s);
}

/// 단일 연맹 문자열 정규화(복수 표기 분해 후 내부에서 사용).
String _normalizeSingle(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return '';
  // 구분자 통일 (→, ->, ∼, ~ 를 '→' 로)
  s = s.replaceAll('->', '→').replaceAll('∼', '→').replaceAll('~', '→');
  s = s.replaceAll(RegExp(r'\s*→\s*'), '→');
  // 명시 별칭
  final alias = kLeagueAlias[s];
  if (alias != null) return alias;
  // 접미사 정리
  final stripped = _stripSuffix(s);
  final alias2 = kLeagueAlias[stripped];
  if (alias2 != null) return alias2;
  return stripped;
}

/// 두 연맹명이 (정규화 기준으로) 같은지.
bool sameLeague(String? a, String? b) =>
    normalizeLeague(a) == normalizeLeague(b);
