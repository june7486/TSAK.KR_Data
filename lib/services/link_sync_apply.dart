/// [link_sync.dart] 의 편집 계획을 **실제 회원 카드**에 적용한다.
///
/// 규칙 계산은 `link_sync.dart`(순수 함수)에 있고, 이 파일은 저장만 담당한다.
/// 이렇게 나눠 두면 위젯/다이얼로그 없이도 규칙을 테스트할 수 있다.
library;

import '../models/member.dart';
import 'app_state.dart';
import 'link_sync.dart';

/// 역방향 연동을 **한 건** 카드에 반영한다.
///
/// 성공하면 true. 상대 카드가 없으면(비인가 멘토·페런츠 등) false —
/// 그 사람은 `link_profiles`(인적사항)로만 관리되므로 정상이다.
Future<bool> applyReverseLink(
  AppState state,
  LinkSyncEdit edit, {
  String linkRequestSource = 'direct',
}) async {
  final target = state.byNumber(edit.memberNumber);
  if (target == null) return false;
  if (target.corps == 'eunha') return false; // 은하 명단은 범 연동 규칙 제외
  final current = switch (edit.field) {
    'parents' => target.parents,
    'mentees' => target.mentees,
    'children' => target.children,
    _ => target.mentors,
  };
  final next = applyLinkEdit(current, edit);
  if (next.length == current.length &&
      next.every((c) => current.contains(c))) {
    return false; // 이미 반영됨 — 불필요한 저장/승인요청을 만들지 않는다.
  }
  final updated = switch (edit.field) {
    'parents' => target.copyWith(parents: next),
    'mentees' => target.copyWith(mentees: next),
    'children' => target.copyWith(children: next),
    _ => target.copyWith(mentors: next),
  };
  await state.save(updated, linkRequestSource: linkRequestSource);
  return true;
}

/// 내 카드의 [field] 를 [before] → [after] 로 바꿀 때 필요한
/// **역방향 편집을 모두 적용**한다. 반영된 건수를 돌려준다.
///
/// ## 🐞 이 함수가 고치는 버그 (2026-11-02, build #571)
///  종전에는 `A.mentees += B` 만 저장하고 `B.mentors += A` 를 저장하지 않아
///  "대장 카드에는 대원이 보이는데, 대원 카드에는 대장이 없는" 상태가 됐다.
///  (실측: 현승용 #590 mentees=['2186'] / 현지환 #2186 mentors=[])
Future<int> syncReverseLinks(
  AppState state, {
  required Member self,
  required String field,
  required Iterable<String> before,
  required Iterable<String> after,
  String linkRequestSource = 'direct',
}) async {
  final edits = planReverseLinks(
    selfNumber: self.number,
    field: field,
    before: before,
    after: after,
  );
  var n = 0;
  for (final e in edits) {
    try {
      if (await applyReverseLink(
        state,
        e,
        linkRequestSource: linkRequestSource,
      )) {
        n++;
      }
    } catch (_) {
      // 상대 카드 저장 실패가 내 카드 저장을 막지는 않는다.
      // (다음 저장 때 서버 정합화가 다시 맞춘다)
    }
  }
  return n;
}
