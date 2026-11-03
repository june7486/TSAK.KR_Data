// 멘토 · 페런츠 **인적사항 카드** — 회원카드가 아닌 사람도 표현하기 위한 모델.
//
// ## [요구 2026-11-04] 멘토 필터 인원 누락
//   "멘토 버튼을 클릭하면 멘토로 등록된 네임카드가 나와야 하는데,
//    현재 일부 인원 이름이 누락되고 있음. 박인규, 민병인 등.."
//
// ## 왜 별도 모델인가
//   멘토·페런츠는 **인가자일 수도, 일반회원일 수도** 있다.
//   운영 데이터 실측:
//    · 박인규 — 일반회원(isRegular), `number` 없음, 전화 01064407181
//    · 민병인 — 일반회원, `number` 없음, 전화 01082907590
//   `Member` 로 표현하려면 없는 인가번호를 억지로 만들어야 하고, 그러면
//   명부·검색·출력이 오염된다. 그래서 **읽기 전용 경량 모델**을 따로 둔다.
//
//   회원카드와 연결되는 사람은 [code] 에 인가번호가 들어가고,
//   번호가 없는 일반회원은 [code] 가 빈 문자열이며 [phone] 으로 식별한다.
class LinkPerson {
  const LinkPerson({
    this.code = '',
    required this.name,
    this.phone = '',
    this.league = '',
    this.unit = '',
    this.position = '',
    this.kind = 'mentor',
  });

  /// 인가번호(없으면 빈 문자열 — 일반회원 멘토/페런츠).
  final String code;

  /// 이름 (필수).
  final String name;

  /// 전화번호 — 번호 없는 사람의 **식별 키**.
  final String phone;

  /// 연맹 (표시용).
  final String league;

  /// 소속대 (표시용).
  final String unit;

  /// 직책 — 예: '멘토(지도대장)'.
  final String position;

  /// 'mentor' | 'parent'.
  final String kind;

  bool get isMentor => kind == 'mentor';

  /// 말머리 — '멘토' 또는 '페런츠'.
  String get kindLabel => kind == 'parent' ? '페런츠' : '멘토';

  /// 번호가 있는가(인가자/일반회원 모두 `Member.number` 는 빈 값일 수 있다).
  bool get hasCode => code.replaceAll(RegExp(r'[^0-9]'), '').isNotEmpty;

  /// 이름 옆에 붙일 짧은 식별자 — `범#417` 또는 `010-6440-7181`.
  ///
  ///  인가번호가 없으면 전화번호를 쓴다(일반회원 멘토도 구분 가능해야 한다).
  String get badge {
    if (hasCode) return '범#${code.replaceAll(RegExp(r'[^0-9]'), '')}';
    return phone;
  }

  /// 소속 표기 — `경기남부 · 김포지역대`.
  String get org => [league, unit].where((s) => s.trim().isNotEmpty).join(' · ');

  /// 검색 대응 — 이름·번호·전화·소속·직책을 소문자로 합친 것.
  String get searchText => '$name $code $phone $league $unit $position'
      .toLowerCase();

  @override
  String toString() => '$kindLabel:$name($badge)';
}
