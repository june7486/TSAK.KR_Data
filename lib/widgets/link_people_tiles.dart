import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../screens/member_detail_screen.dart';
import '../screens/member_edit_screen.dart';
import '../services/app_state.dart';
import '../services/link_sync.dart';
import '../services/link_sync_apply.dart';
import '../theme/app_theme.dart';
import 'confirm.dart';
import 'link_profile_sheet.dart';
import 'mentee_add_sheet.dart';

/// 인가자 개인화면(인가정보 카드)의 **[멘티 · 멘토 · 페런츠] 3개 항목** 타일.
///
/// ## 요구 (원문)
///  · "멘티 / 멘토 / 페런츠 3개 항목을 노출해주고, 멘티로 등록된 인가자 정보를
///     노출시켜주고, 그 이름을 클릭하면 그 인가자 개인페이지로 이동"
///  · "반대로, 멘토 / 페런츠에 있는 이름도 클릭하면 그 회원의 개인 카드로
///     연결시켜줘. 만일 카드가 없을 경우 바로 등록가능한 페이지 열어주고
///     등록 여부를 물어봐줘"
///  · "**멘토·페런츠는 인가자가 아니므로 인가번호가 자동 등록되면 안 됨**"
///    → 멘토·페런츠는 `link_profiles`(인적사항)로 등록한다. 카드(인가자/일반회원)
///      가 없으면 **인적사항 등록 페이지(시트)**를 열어 작성하게 한다.
///  · "멘토·멘티·페런츠 데이터를 관리하기 위해서는 등록되어 있는 분들의 카드가
///     작성되어야 함 → 작성되어 있지 않으면 작성항목을 노출, 작성되어 있으면
///     그 개인카드를 열어 정보가 맞는지 물어보도록"
///
/// ## 이름 클릭 동작
///   · 멘티   : 연결된 인가자 회원의 **개인페이지**로 이동(없으면 등록 유도).
///   · 멘토/페런츠 : 인적사항이 없으면 **인적사항 등록 시트**, 있으면 그 사람의
///      **개인카드**로 이동(카드가 없으면 카드 등록 유도).
class LinkPeopleTiles extends StatelessWidget {
  const LinkPeopleTiles({
    super.key,
    required this.member,
    required this.profiles,
    this.canEdit = false,
    this.onChanged,
  });

  final Member member;

  /// 인가번호/복합키 → 인적사항 맵(개인상세의 _linkProfilesCache 재사용).
  final Map<String, dynamic> profiles;

  /// 편집 권한자(관리자·마스터·본인) — 등록/안내 노출에 사용.
  final bool canEdit;

  /// 인적사항 등록/수정 후 부모(개인상세)를 새로고침하기 위한 콜백.
  final VoidCallback? onChanged;

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  // ------------------------------------------------------------------ 조회
  /// 코드 → 인적사항 프로필.
  ///
  /// ## [요구 2026-11-04] **키 체계가 바뀌었다**
  /// 서버가 표준 저장키를 `person:<대표번호>` 로 전환했다. 그런데 이 함수가
  /// `'멘토:<번호>'` / 무접두어만 찾고 있어서, 서버가 정상적으로 준 데이터를
  /// 화면이 **하나도 못 찾았다.** 그 결과
  ///   · 멘토 이름이 안 보이고 (`범#01046236587` 처럼 코드만 노출)
  ///   · 시트를 열면 이름·전화번호가 **빈칸**
  ///   · 저장할 때마다 새 임시코드가 생겨 이름이 계속 사라짐
  /// 이 되었다. 이제 세 가지를 모두 본다:
  ///   ① `person:<대표번호>`  ② `<종류>:<번호>`  ③ 무접두어 `<번호>`
  /// 또한 프로필이 담고 있는 **전화번호·로그인ID·scoutNo** 로도 같은 사람을
  /// 찾는다(멘토 관계 값이 전화번호로 저장되는 새 표준 때문).
  Map<String, dynamic> _profileOf(String code, String kind) {
    final d = _digits(code);
    if (d.isEmpty) return {};
    final prefix = kind == 'parent' ? '페런츠' : '멘토';
    final keys = <String>[
      'person:$d',
      '$prefix:$d',
      d,
    ];
    for (final k in keys) {
      final v = profiles[k];
      if (v is! Map || v.isEmpty) continue;
      final vk = '${v['kind'] ?? ''}'.trim();
      // 구(무접두어) 키 폴백 시 종류가 다르면 오염 방지를 위해 건너뛴다.
      if (vk.isEmpty || vk == kind) return v.cast<String, dynamic>();
      // kinds 목록에 이 역할이 들어 있으면 정상 매칭(겸임자).
      final ks = v['kinds'];
      if (ks is List && ks.map((e) => '$e').contains(kind)) {
        return v.cast<String, dynamic>();
      }
    }
    // 키가 안 맞으면 **사람 기준**으로 훑는다 — 전화·로그인ID·scoutNo.
    for (final entry in profiles.entries) {
      final v = entry.value;
      if (v is! Map || v.isEmpty) continue;
      final vk = '${v['kind'] ?? ''}'.trim();
      final ks = v['kinds'];
      final kindOk = vk.isEmpty ||
          vk == kind ||
          (ks is List && ks.map((e) => '$e').contains(kind));
      if (!kindOk) continue;
      final codes = <String>{
        _digits('${v['phone'] ?? ''}'),
        _digits('${v['loginId'] ?? ''}'),
        _digits('${v['scoutNo'] ?? ''}'),
        _digits('${v['personKey'] ?? ''}'),
      };
      if (codes.contains(d)) return v.cast<String, dynamic>();
    }
    return {};
  }

  String _profileInfo(Map<String, dynamic> p) => [
    '${p['league'] ?? ''}'.trim(),
    '${p['unit'] ?? ''}'.trim(),
  ].where((s) => s.isNotEmpty).join(' · ');

  /// 인적사항 프로필(전화번호)로 **회원 카드** 매칭 — 멘토/페런츠가 실제
  /// 인가자인 경우 그 개인페이지로 연결하기 위함.
  Member? _byPhone(AppState state, String phone) {
    final ph = _digits(phone);
    if (ph.length < 7) return null;
    for (final m in state.allMembers) {
      if (_digits(m.phone) == ph) return m;
    }
    return null;
  }

  /// 코드 → 회원 카드. **인가번호 우선, 없으면 계정 아이디·전화번호로** 찾는다.
  ///
  /// [요구 2026-11-04] 멘토 자동가입 계정(`reg_<전화번호>`)은 **인가번호가 없다.**
  /// 그래서 `state.byNumber()`(number 필드만 조회)로는 절대 찾지 못했고,
  /// 데이터는 연동됐는데도 멘토 이름이 **빈칸**으로 보여 "연동 안 됨"으로
  /// 오해하게 만들었다. (실사고: 양다솜 #1346 카드의 멘토 선영진)
  Member? _byCodeOrPhone(AppState state, String code) {
    final d = _digits(code);
    if (d.isEmpty) return null;
    final byNo = state.byNumber(d);
    if (byNo != null) return byNo;
    for (final m in state.allMembers) {
      if (_digits(m.loginId) == d) return m;
      if (_digits(m.phone) == d) return m;
    }
    return null;
  }

  /// 이 코드가 **나 자신**을 가리키는가 — 번호 문자열이 아니라 사람으로 판단.
  ///
  /// [요구 2026-11-04] 종전에는 `d == self`(문자열 비교)라서, 전화번호로
  /// 저장된 자기참조(양다솜 mentors=['1346'] 사고)를 걸러내지 못했다.
  /// 이제 상대를 해석해 **같은 카드/같은 전화번호**면 자기 자신으로 본다.
  bool _isSamePerson(AppState state, String code) {
    final d = _digits(code);
    if (d.isEmpty) return false;
    if (d == _digits(member.number)) return true;
    final mine = _digits(member.phone);
    if (mine.isNotEmpty && d == mine) return true;
    final t = _byCodeOrPhone(state, d);
    if (t == null) return false;
    if (t.id == member.id) return true;
    final tp = _digits(t.phone);
    return tp.isNotEmpty && mine.isNotEmpty && tp == mine;
  }

  /// 소속정보 = **현재활동 등록정보**(없으면 인가 당시로 폴백).
  String _activity(Member? m) {
    if (m == null) return '';
    final l = m.regLeague.trim().isNotEmpty
        ? m.regLeague.trim()
        : m.league.trim();
    final u = m.regUnit.trim().isNotEmpty ? m.regUnit.trim() : m.unit.trim();
    return [l, u].where((s) => s.isNotEmpty).join(' · ');
  }

  // ------------------------------------------------------------------ 구성
  List<_Ref> _mentees(AppState state) {
    final self = _digits(member.number);
    final out = <_Ref>[];
    for (final c in member.mentees) {
      final d = _digits(c);
      if (d.isEmpty || d == self) continue; // 자기참조 제외
      final m = _byCodeOrPhone(state, d);
      out.add(
        _Ref(
          code: d,
          name: (m?.name ?? '').trim(),
          info: _activity(m),
          target: m,
        ),
      );
    }
    return out;
  }

  List<_Ref> _links(AppState state, {required bool parent}) {
    final codes = parent ? member.parents : member.mentors;
    final out = <_Ref>[];
    for (final c in codes) {
      final d = _digits(c);
      if (d.isEmpty) continue;
      final p = _profileOf(d, parent ? 'parent' : 'mentor');
      final pName = '${p['name'] ?? ''}'.trim();
      final pInfo = _profileInfo(p);
      Member? target;
      // [요구 2026-11-04] 저장값은 이제 **상대 인물의 표준코드**다
      //   (인가자=인가번호 / 일반회원·비인가=전화번호).
      //   인가번호 우선, 없으면 loginId·전화번호로 찾는다.
      target = _byCodeOrPhone(state, d);
      if (target == null && pName.isNotEmpty) {
        target = _byPhone(state, '${p['phone'] ?? ''}');
      }
      final isSelf = _isSamePerson(state, d);
      out.add(
        _Ref(
          code: d,
          name: pName.isNotEmpty ? pName : (target?.name ?? '').trim(),
          info: pInfo.isNotEmpty ? pInfo : _activity(target),
          target: target,
          isSelf: isSelf,
          hasProfile: pName.isNotEmpty,
          kind: parent ? 'parent' : 'mentor',
        ),
      );
    }
    return out;
  }

  // ------------------------------------------------------------------ 동작
  /// 이름 클릭 — 연결된 회원 카드가 있으면 개인페이지로, 없으면 등록 유도.
  Future<void> _tapName(
    BuildContext context,
    _Ref r,
    String kindLabel,
    Color accent,
  ) async {
    if (r.target != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MemberDetailScreen(memberId: r.target!.id),
        ),
      );
      return;
    }
    // 카드 없음 — 등록 권한이 없으면 안내만 한다.
    if (!canEdit) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${r.name.isEmpty ? '범#${r.code}' : r.name} — 아직 등록된 카드가 없습니다. '
              '(등록은 관리자·마스터·본인만 가능합니다)',
            ),
          ),
        );
      }
      return;
    }
    // 멘토·페런츠는 인가자가 아니므로 **인적사항(카드) 등록 시트**를 먼저 연다.
    if (r.kind == 'mentor' || r.kind == 'parent') {
      await _addProfile(context, r.kind!, r.code);
      return;
    }
    // 멘티(인가자) — 카드 없음 → 등록 여부 확인 후 등록 페이지로.
    final label = r.name.isEmpty ? '범#${r.code}' : '${r.name} (범#${r.code})';
    final ok = await confirmDialog(
      context,
      title: '인가자 카드 없음 · $kindLabel',
      message:
          '$label 은(는) 아직 등록된 인가자 카드가 없습니다.\n\n'
          '지금 등록할까요? (인가번호가 자동 입력된 등록 페이지가 열립니다)',
      confirmLabel: '등록하기',
      danger: false,
    );
    if (!ok || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberEditScreen(suggestedNumber: r.code),
      ),
    );
  }

  /// 멘티 **추가** — 직접입력 + 인가정보 연동(멘토 체계와 동일).
  ///
  /// (요구) "멘티 등록도 직접입력 가능 및 기존 인가자 정보와 연계시키고
  ///  연동 되도록 할 것 (멘토체계와 동일)"
  ///  멘토·페런츠는 인적사항(link_profiles)으로 등록하지만, 멘티는 **반드시
  ///  범 인가자**이므로 인가번호를 받아 회원 카드에 직접 연결한다.
  Future<void> _addMentee(BuildContext context) async {
    final code = await showMenteeAddSheet(
      context,
      member: member,
      existing: member.mentees,
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    await _saveMentees(context, <String>[...member.mentees, code]);
  }

  /// 멘티 목록 저장 — 나(멘토)의 mentees 갱신 **+ 상대 카드의 mentors 역방향 갱신**.
  ///
  /// ## 🐞 버그 수정 (2026-11-02, build #571)
  /// 보고(원문): *"현승용 개인카드에서 현지환을 멘티로 등록했는데도 현지환
  /// 개인카드에 연동되어 현승용이 멘토로 등록되지 않고 있음"*
  ///
  /// 종전에는 `member.copyWith(mentees: ...)` **한 장만** 저장했다. 그래서
  /// 대장 카드에는 대원이 보이는데 대원 카드에는 대장이 없는 반쪽 상태가 됐다.
  /// 실측(운영 DB): 현승용 #590 `mentees=['2186']` / 현지환 #2186 `mentors=[]`.
  ///
  /// 이제 `syncReverseLinks` 가 `mentees ↔ mentors` / `children ↔ parents`
  /// 를 **양쪽 모두** 맞춘다. 상대가 카드 없는 비인가자면 조용히 건너뛴다
  /// (그분들은 `link_profiles` 인적사항으로만 관리된다).
  Future<void> _saveMentees(
    BuildContext context,
    List<String> next, {
    String field = 'mentees',
  }) async {
    final state = context.read<AppState>();
    // 중복·자기참조 제거 (`G` 접두어 보존 — 은하 G75 ≠ 범 75).
    final self = _digits(member.number);
    final seen = <String>{};
    final cleaned = <String>[];
    for (final c in next) {
      final norm = linkNormCode(c);
      if (norm.isEmpty) continue;
      if (norm == self && !c.trim().toUpperCase().startsWith('G')) continue;
      if (seen.add(norm)) cleaned.add(norm);
    }
    final before = field == 'children' ? member.children : member.mentees;
    final updated = field == 'children'
        ? member.copyWith(children: cleaned)
        : member.copyWith(mentees: cleaned);
    await state.save(updated, linkRequestSource: 'direct');
    // ★ 역방향(상대 카드) — 이 한 줄이 이번 버그의 핵심 수정이다.
    final mirrored = await syncReverseLinks(
      state,
      self: member,
      field: field,
      before: before,
      after: cleaned,
    );
    if (!context.mounted) return;
    onChanged?.call();
    final who = field == 'children' ? '자녀대원' : '멘티';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mirrored > 0
              ? '$who 를 등록했습니다 (상대 카드 $mirrored건에 역으로도 연동됨)'
              : '$who 를 등록했습니다',
        ),
      ),
    );
  }

  /// 멘티 **해제** — 연결만 끊는다(회원 카드는 그대로).
  Future<void> _removeMentee(BuildContext context, _Ref r) async {
    final label = r.name.isEmpty ? '범#${r.code}' : r.name;
    final ok = await confirmDialog(
      context,
      title: '멘티 해제',
      message:
          '$label 을(를) 내 멘티 목록에서 해제할까요?\n\n'
          '인가자 카드와 정보는 그대로 남습니다.',
      confirmLabel: '해제',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final next = <String>[
      for (final c in member.mentees)
        if (linkNormCode(c) != linkNormCode(r.code)) c,
    ];
    await _saveMentees(context, next);
  }

  /// 멘토 · 페런츠 **해제** — 내 목록에서 빼고 **상대 카드의 역방향도** 지운다.
  ///
  /// ## 🐞 왜 추가했나 (2026-11-02, build #571)
  /// 보고(원문): *"멘티, 멘토, 페런츠 모두 본인 및 관리자/마스터가 해당 이름을
  /// 삭제할 수 있도록 오른쪽에 삭제아이콘 추가해줘 그리고 삭제시 꼭 한번더
  /// 물어봐줘"*
  ///
  /// 종전에는 `onRemove` 가 **멘티 섹션에만** 배선돼 있었다. 그래서 멘토·페런츠는
  /// 한 번 등록하면 화면에서 되돌릴 방법이 없었다.
  /// (편집 화면에 숨어 있는 삭제 버튼을 찾아가야 했다.)
  Future<void> _removeLink(
    BuildContext context,
    _Ref r, {
    required bool parent,
  }) async {
    final label = r.name.isEmpty ? '범#${r.code}' : r.name;
    final who = parent ? '페런츠' : '멘토';
    final ok = await confirmDialog(
      context,
      title: '$who 해제',
      message:
          '$label 을(를) 내 $who 목록에서 삭제할까요?\n\n'
          '· 인가자 카드와 인적사항은 그대로 남습니다.\n'
          '· 상대 카드에 역으로 연결된 항목도 함께 해제됩니다.',
      confirmLabel: '삭제',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final state = context.read<AppState>();
    final before = parent ? member.parents : member.mentors;
    final next = <String>[
      for (final c in before)
        if (linkNormCode(c) != linkNormCode(r.code)) c,
    ];
    final hasAnyLink =
        next.isNotEmpty ||
        (parent ? member.mentors : member.parents).isNotEmpty ||
        member.mentees.isNotEmpty ||
        member.children.isNotEmpty;
    final updated = parent
        ? member.copyWith(
            parents: next,
            linkApprovalStatus: hasAnyLink ? member.linkApprovalStatus : '',
          )
        : member.copyWith(
            mentors: next,
            linkApprovalStatus: hasAnyLink ? member.linkApprovalStatus : '',
          );
    await state.save(updated, linkRequestSource: 'direct');
    // ★ 역방향 해제 — 상대 카드에서 '나'를 뺀다.
    final mirrored = await syncReverseLinks(
      state,
      self: member,
      field: parent ? 'parents' : 'mentors',
      before: before,
      after: next,
    );
    if (!context.mounted) return;
    onChanged?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mirrored > 0
              ? '$who 를 삭제했습니다 (상대 카드 $mirrored건도 함께 해제)'
              : '$who 를 삭제했습니다',
        ),
      ),
    );
  }

  /// 멘토·페런츠 **등록/수정** — 저장 후 **내 카드의 mentors/parents 반영 +
  /// 상대 카드 역방향 연동**까지 한 번에 처리한다.
  ///
  /// ## 🐞 버그 수정 (2026-11-02, build #571)
  /// 보고(원문):
  ///  · *"같은 검증을 페런츠에서도 해봐"* — 종전에는 시트를 닫기만 하고
  ///    `member.mentors` / `member.parents` 에 **아무것도 쓰지 않았다**.
  ///    그래서 등록해도 목록에 나타나지 않았다.
  ///  · *"범인가자가 페런츠, 또는 멘토일때는 아이디를 전화번호로 생성하지 않고,
  ///    범인가자 개인카드에 연동해서 멘토, 페런츠, 멘티 정보를 넣으면 됨"*
  ///    → 인가자면 그분의 **인가번호**를 내 mentors/parents 에 넣고,
  ///      반대로 그분 카드의 mentees/children 에 **나**를 넣는다.
  Future<void> _addProfile(
    BuildContext context,
    String kind,
    String code,
  ) async {
    final state = context.read<AppState>();
    final p = _profileOf(code, kind);
    final res = await showLinkProfileSheet(
      context,
      kind: kind,
      code: code,
      profile: p,
      defaultLeague: member.regLeague.trim().isNotEmpty
          ? member.regLeague.trim()
          : member.league.trim(),
      defaultUnit: member.regUnit.trim().isNotEmpty
          ? member.regUnit.trim()
          : member.unit.trim(),
      selfNumber: _digits(member.number),
      codeEditable: kind == 'mentor' ? false : p.isEmpty,
    );
    if (!res.saved) return;

    final field = kind == 'mentor' ? 'mentors' : 'parents';
    final before = kind == 'mentor' ? member.mentors : member.parents;
    // [요구 2026-11-04] **내 관계 값은 '상대 인물'을 가리킨다.**
    //  종전에는 시트가 돌려준 저장코드(`res.code` = 내 번호!)를 그대로
    //  mentors 에 넣어 **자기참조를 매번 새로 만들었다.** 그래서 저장할
    //  때마다 승인요청이 되살아나고 이름이 사라졌다.
    //  이제 상대를 실제로 해석해 그 사람의 코드를 넣는다.
    //    ① 인가자(시트에서 인가정보 입력) → 그분의 인가번호
    //    ② 카드가 있으면 → 그 카드의 인가번호(또는 전화번호)
    //    ③ 카드도 없고 인가자도 아니면 인적사항의 전화번호(= 그분 계정 ID)
    var linkCode = '';
    if (res.isScouter && res.scoutNo.isNotEmpty) {
      linkCode = res.scoutNo;
    }
    // ★ ② 비인가 멘토·페런츠 → **그 사람의 전화번호**(= 계정 아이디).
    //   (`code` 는 멘토 추가 시 '내 번호'라 절대 쓰면 안 된다.)
    if (linkCode.isEmpty) {
      linkCode = _digits(res.phone);
    }
    if (linkCode.isEmpty) {
      final saved = _profileOf(code, kind);
      linkCode = _digits('${saved['phone'] ?? ''}');
      if (linkCode.isEmpty) linkCode = _digits('${saved['scoutNo'] ?? ''}');
    }
    if (linkCode.isEmpty) {
      // 기존 행(코드가 곧 그 사람)에서 등록한 경우에만 카드 조회로 보완한다.
      final byCode = _byCodeOrPhone(state, code);
      if (byCode != null && !_isSamePerson(state, _digits(byCode.number))) {
        linkCode = _digits(byCode.number).isNotEmpty
            ? _digits(byCode.number)
            : _digits(byCode.phone);
      }
    }
    // ⑤ 끝까지 못 찾으면 종전 규칙(시트 저장코드)으로 폴백.
    if (linkCode.isEmpty) linkCode = res.code;
    // 그래도 **나 자신**과 같으면 넣지 않는다(자기참조 원천 차단).
    if (linkCode.isEmpty || _isSamePerson(state, linkCode)) {
      onChanged?.call();
      return;
    }
    final enumerated = linkNormList(<String>[...before, linkCode]);
    // 실제로 목록이 바뀐 경우에만 승인상태를 'pending' 으로 되돌린다.
    //  (이미 승인된 연결을 건드리지 않고 시트만 열었다 닫은 경우 보호)
    final changed =
        enumerated.length != linkNormList(before).length ||
        !enumerated.every(linkNormList(before).contains);
    final hasAnyLink =
        enumerated.isNotEmpty ||
        (kind == 'mentor' ? member.parents : member.mentors).isNotEmpty;
    final nextStatus = changed && hasAnyLink
        ? 'pending'
        : member.linkApprovalStatus;
    final updated = kind == 'mentor'
        ? member.copyWith(mentors: enumerated, linkApprovalStatus: nextStatus)
        : member.copyWith(parents: enumerated, linkApprovalStatus: nextStatus);
    await state.save(updated, linkRequestSource: 'direct');
    // ★ 역방향 — 인가자면 그분 카드에 '나'를 기록한다(멘토→멘티 / 페런츠→자녀).
    final mirrored = await syncReverseLinks(
      state,
      self: member,
      field: field,
      before: before,
      after: enumerated,
    );
    if (!context.mounted) return;
    onChanged?.call();
    if (res.isScouter && mirrored > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${kind == 'mentor' ? '멘토' : '페런츠'} 범#${res.scoutNo} 카드에 '
            '역으로도 연동했습니다',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------------ 빌드
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final selfNumber = member.regLeague.isNotEmpty
        ? member.number
        : member.number;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          context,
          title: '멘티 (내가 배출한 범 대원)',
          icon: Icons.supervisor_account,
          accent: AppColors.purple,
          refs: _mentees(state),
          empty: '본인이 배출한(만든) 범 대원 없음 (복수 등록 가능)',
          addLabel: '멘티 추가',
          onAdd: canEdit ? () => _addMentee(context) : null,
          onRemove: canEdit
              ? (r) => _removeMentee(context, r)
              : null,
        ),
        const SizedBox(height: 8),
        _section(
          context,
          title: '멘토 (범을 배출한 대장)',
          icon: Icons.school,
          accent: AppColors.purple,
          refs: _links(state, parent: false),
          empty: '등록된 멘토(범을 배출한 대장) 없음',
          addLabel: '멘토 추가',
          onAdd: canEdit
              ? () => _addProfile(context, 'mentor', selfNumber)
              : null,
          // (요구 2026-11-02) 멘토도 화면에서 바로 삭제할 수 있어야 한다.
          onRemove: canEdit
              ? (r) => _removeLink(context, r, parent: false)
              : null,
        ),
        const SizedBox(height: 8),
        _section(
          context,
          title: '페런츠 (범을 배출한 부모님)',
          icon: Icons.family_restroom,
          accent: AppColors.taegeukBlue,
          refs: _links(state, parent: true),
          empty: '등록된 페런츠(범을 배출한 부모님) 없음',
          addLabel: '페런츠 추가',
          onAdd: canEdit ? () => _addProfile(context, 'parent', '') : null,
          // (요구 2026-11-02) 페런츠도 화면에서 바로 삭제할 수 있어야 한다.
          onRemove: canEdit
              ? (r) => _removeLink(context, r, parent: true)
              : null,
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color accent,
    required List<_Ref> refs,
    required String empty,
    String? addLabel,
    VoidCallback? onAdd,
    /// 행별 **삭제(해제)** 버튼 — 멘티·멘토·페런츠 **모두** 해당.
    ///  (요구 2026-11-02: 본인·관리자·마스터가 화면에서 바로 지울 수 있게)
    void Function(_Ref)? onRemove,
  }) {
    final kindLabel = title.split(' ').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '(이름을 누르면 개인페이지)',
                style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
              ),
            ),
            if (onAdd != null && addLabel != null)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onAdd,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 13, color: accent),
                      const SizedBox(width: 2),
                      Text(
                        addLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (refs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
            child: Text(
              empty,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in refs)
                  _row(
                    context,
                    r,
                    kindLabel,
                    accent,
                    onRemove: onRemove,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    _Ref r,
    String kindLabel,
    Color accent, {
    void Function(_Ref)? onRemove,
  }) {
    final hasCard = r.target != null;
    final isLinkKind = r.kind == 'mentor' || r.kind == 'parent';
    // 멘토·페런츠는 '인적사항 등록' 상태를 별도로 표시한다.
    final needsProfile = isLinkKind && !r.hasProfile;
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              r.isSelf && isLinkKind ? '본인' : '범#${r.code}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => needsProfile
                  ? _addProfile(context, r.kind!, r.code)
                  : _tapName(context, r, kindLabel, accent),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.name.isEmpty
                                ? (needsProfile
                                      ? '(인적사항 미등록 · 눌러서 등록)'
                                      : '(이름 미확인 · 눌러서 등록)')
                                : r.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: r.name.isEmpty
                                  ? AppColors.textGray
                                  : AppColors.taegeukBlue,
                              fontStyle: r.name.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              decoration: (hasCard || isLinkKind)
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              decorationColor: AppColors.taegeukBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          needsProfile
                              ? Icons.person_add_alt_1
                              : (hasCard
                                    ? Icons.open_in_new
                                    : Icons.person_add_alt_1),
                          size: 13,
                          color: hasCard || isLinkKind
                              ? AppColors.taegeukBlue
                              : AppColors.tigerGold,
                        ),
                      ],
                    ),
                    if (r.info.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          r.info,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textGray,
                            height: 1.3,
                          ),
                        ),
                      ),
                    if (needsProfile)
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Text(
                          '인적사항 미등록 — 눌러서 작성 (인가자 자동등록 아님)',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.tigerGold,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else if (!hasCard && !isLinkKind)
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Text(
                          '미등록 — 눌러서 인가자 카드 등록',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.tigerGold,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // 삭제(해제) — 연결만 끊는다. 카드·인적사항은 유지된다.
          //  (요구 2026-11-02) 멘티·멘토·페런츠 **셋 다** 오른쪽에 삭제아이콘을 둔다.
          if (onRemove != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              tooltip: r.kind == 'parent'
                  ? '페런츠 삭제'
                  : (r.kind == 'mentor' ? '멘토 삭제' : '멘티 해제'),
              icon: Icon(
                // 멘티는 '연결 해제(link_off)', 멘토·페런츠는 '삭제(close)' —
                //  사용자가 스크린샷에서 요청한 오른쪽 삭제아이콘.
                isLinkKind ? Icons.close : Icons.link_off,
                size: 16,
                color: AppColors.textGray,
              ),
              onPressed: () => onRemove(r),
            ),
        ],
      ),
    );
  }
}

/// 표시 1행 데이터 — 인가번호·이름·소속·연결 회원카드.
class _Ref {
  _Ref({
    required this.code,
    required this.name,
    required this.info,
    required this.target,
    this.isSelf = false,
    this.hasProfile = false,
    this.kind,
  });

  final String code;
  final String name;
  final String info;
  final Member? target;
  final bool isSelf;

  /// 멘토·페런츠 인적사항(link_profiles) 등록 여부.
  final bool hasProfile;

  /// 'mentor' | 'parent' (멘티는 null).
  final String? kind;
}
