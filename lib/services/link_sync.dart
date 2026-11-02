/// 멘토 · 페런츠 ↔ 멘티 · 자녀대원 **양방향 연동** 계산기.
///
/// ## 🐞 왜 이 파일이 생겼나 (2026-11-02, build #571)
///
/// 보고(원문):
/// > "현승용 개인카드에서 현지환을 멘티로 등록했는데도 현지환 개인카드에
/// >  연동되어 현승용이 멘토로 등록되지 않고 있음 (혹시 버그인지 수정해줘),
/// >  같은 검증을 페런츠에서도 해봐"
///
/// 실측(운영 DB, 2,242명):
/// ```
/// 현승용 #590  mentees = ['2186']   ← 대장이 대원을 등록함
/// 현지환 #2186 mentors = []         ← 대원 쪽에 대장이 없음  🐞
/// ```
///
/// ## 원인
///  회원 모델의 네 목록은 **서로 반대 방향의 시점**이다.
///
///  | 필드 | 의미 | 담기는 값 |
///  |---|---|---|
///  | `mentees`  | 내가 **멘토**로서 등록한 대원 | 대원의 인가번호 |
///  | `mentors`  | 나를 배출한 **대장**          | 대장의 인가번호 |
///  | `children` | 내가 **페런츠**로서 등록한 자녀 | 자녀의 인가번호 |
///  | `parents`  | 나의 **부모(보호자)**          | 부모의 인가번호 |
///
///  그래서 `A.mentees += B` 는 반드시 `B.mentors += A` 를 동반해야 하고,
///  `A.children += C` 는 반드시 `C.parents += A` 를 동반해야 한다.
///  그런데 저장 경로가 **자기 카드 한 장만** 고쳤다(`_saveMentees`).
///
/// ## 이 파일의 역할
///  "무엇을 어느 카드에 넣고/빼야 하는가"를 **화면·서버와 무관한 순수 함수**로
///  뽑아낸다. 위젯 테스트에서 다이얼로그를 띄우지 않고도 규칙을 검증할 수 있고,
///  서버(`_link_reconcile_apply`)도 같은 규칙을 쓴다.
library;

/// 역방향으로 손봐야 할 **한 건**의 편집.
///
/// 예: 현승용(#590)이 현지환(#2186)을 멘티로 추가
/// → `LinkSyncEdit(memberNumber: '2186', field: 'mentors', code: '590', add: true)`
///   = "현지환 카드의 mentors 에 590 을 넣어라".
class LinkSyncEdit {
  const LinkSyncEdit({
    required this.memberNumber,
    required this.field,
    required this.code,
    required this.add,
  });

  /// 고칠 **상대** 회원의 인가번호(카드가 있는 회원).
  final String memberNumber;

  /// 고칠 필드 — `'mentors'` 또는 `'parents'`.
  final String field;

  /// 넣거나 뺄 값 — **나(편집자)의 인가번호**.
  final String code;

  /// true = 추가, false = 제거.
  final bool add;

  @override
  String toString() =>
      'LinkSyncEdit($memberNumber.$field ${add ? '+' : '-'}$code)';

  @override
  bool operator ==(Object other) =>
      other is LinkSyncEdit &&
      other.memberNumber == memberNumber &&
      other.field == field &&
      other.code == code &&
      other.add == add;

  @override
  int get hashCode => Object.hash(memberNumber, field, code, add);
}

/// 인가번호 정규화 — **`G` 접두어를 보존**한다.
///
/// 은하 `G75` 와 범 `75` 는 서로 다른 사람이다. 공백·`#`·`범`/`은하` 표기는
/// 떼어내고 숫자와 `G` 만 남긴다.
String linkNormCode(String raw) {
  var s = raw.trim().toUpperCase();
  if (s.isEmpty) return '';
  s = s.replaceAll('은하', 'G').replaceAll('범', '');
  s = s.replaceAll(RegExp(r'[^0-9G]'), '');
  if (s.isEmpty) return '';
  final isG = s.startsWith('G');
  final d = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return '';
  return isG ? 'G$d' : d;
}

/// 코드 목록 정규화 — 정규화 + 중복제거 + 빈값/자기참조 제거(순서 보존).
///
/// [selfNumber] 를 주면 그 번호는 목록에서 뺀다 — "내가 나를 배출한 대장"
/// 같은 모순을 막는다.
List<String> linkNormList(Iterable<String> raw, {String selfNumber = ''}) {
  final self = linkNormCode(selfNumber);
  final seen = <String>{};
  final out = <String>[];
  for (final x in raw) {
    final c = linkNormCode(x);
    if (c.isEmpty) continue;
    if (c == self) continue;
    if (!seen.add(c)) continue;
    out.add(c);
  }
  return out;
}

/// 내가 고치는 필드 → **상대 카드에서 고칠** 필드.
///
/// 네 목록은 서로 **반대 시점**이므로 짝이 네 쌍이다.
///
/// | 내가 고치는 것 | 상대 카드에서 고칠 것 |
/// |---|---|
/// | `mentees` (내가 멘토) | `mentors` (그 대원의 대장 = 나) |
/// | `children` (내가 페런츠) | `parents` (그 자녀의 부모 = 나) |
/// | `mentors` (그분이 내 대장) | `mentees` (그 대장이 배출한 대원 = 나) |
/// | `parents` (그분이 내 부모) | `children` (그 부모의 자녀 = 나) |
String linkPeerField(String selfField) {
  switch (selfField) {
    case 'mentees':
      return 'mentors';
    case 'children':
      return 'parents';
    case 'mentors':
      return 'mentees';
    case 'parents':
      return 'children';
    default:
      return 'mentors';
  }
}

/// 내 카드의 [field] 를 [before] → [after] 로 바꿀 때,
/// **상대 카드에 반영해야 할 편집 목록**을 계산한다.
///
/// · 새로 추가된 코드 → 상대 `mentors`/`parents` 에 **나**를 넣는다.
/// · 빠진 코드 → 상대 `mentors`/`parents` 에서 **나**를 뺀다.
/// · 자기 자신은 제외한다(자기참조 방지).
///
/// 상대가 아직 카드가 없으면(비인가 멘토 등) 결과에 그대로 담긴다 —
/// 호출부가 `byNumber` 로 찾아 없으면 조용히 건너뛴다.
List<LinkSyncEdit> planReverseLinks({
  required String selfNumber,
  required String field,
  required Iterable<String> before,
  required Iterable<String> after,
}) {
  final self = linkNormCode(selfNumber);
  if (self.isEmpty) return const <LinkSyncEdit>[];
  final peer = linkPeerField(field);
  final b = linkNormList(before);
  final a = linkNormList(after);
  final bs = b.toSet();
  final as = a.toSet();
  final out = <LinkSyncEdit>[];
  for (final c in a) {
    if (bs.contains(c)) continue;
    if (c == self) continue;
    out.add(
      LinkSyncEdit(memberNumber: c, field: peer, code: self, add: true),
    );
  }
  for (final c in b) {
    if (as.contains(c)) continue;
    if (c == self) continue;
    out.add(
      LinkSyncEdit(memberNumber: c, field: peer, code: self, add: false),
    );
  }
  return out;
}

/// 편집 1건을 코드 목록에 적용한다(추가/제거 + 중복 방지).
List<String> applyLinkEdit(Iterable<String> current, LinkSyncEdit e) {
  final cur = linkNormList(current);
  if (e.add) {
    if (cur.contains(e.code)) return cur;
    return <String>[...cur, e.code];
  }
  return <String>[
    for (final c in cur)
      if (c != e.code) c,
  ];
}
