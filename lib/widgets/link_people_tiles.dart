import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../screens/member_detail_screen.dart';
import '../screens/member_edit_screen.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'confirm.dart';

/// 인가자 개인화면(인가정보 카드)의 **[멘티 · 멘토 · 페런츠] 3개 항목** 타일.
///
/// ## 요구
///  · "멘티 / 멘토 / 페런츠 3개 항목을 노출해주고"
///  · "멘티로 등록된 인가자 정보를 노출시켜주고, 그 이름을 클릭하면
///     그 인가자 개인페이지로 이동시켜줘"
///  · "반대로, 멘토 / 페런츠에 있는 이름도 클릭하면 그 회원의 개인 카드로
///     연결시켜줘. 만일 카드가 없을 경우 바로 등록가능한 페이지 열어주고
///     등록 여부를 물어봐줘"
///
/// ## 데이터 의미(중요)
///  · 멘티   : `member.mentees` — 본인이 멘토(배출 대장)로서 만든 범 대원 인가번호.
///  · 멘토   : `member.mentors` — 저장 코드는 **멘티(본인) 번호**, 이름은
///             `link_profiles` 의 '멘토:<번호>' 프로필(실제 대장) 이름.
///  · 페런츠 : `member.parents` — 저장 코드는 페런츠 인가번호, 이름은
///             '페런츠:<번호>' 프로필(부모님) 이름.
///
/// ## 이름 클릭 동작
///  1) 연결된 **회원 카드(인가자)** 가 있으면 → 그 회원의 **개인페이지**로 이동.
///  2) 카드가 없으면 → "등록할까요?" 확인 후 → **회원 등록 페이지**로 이동.
class LinkPeopleTiles extends StatelessWidget {
  const LinkPeopleTiles({
    super.key,
    required this.member,
    required this.profiles,
    this.canEdit = false,
  });

  final Member member;

  /// 인가번호/복합키 → 인적사항 맵(개인상세의 _linkProfilesCache 재사용).
  final Map<String, dynamic> profiles;

  /// 편집 권한자(관리자·마스터·본인) — 안내 문구 노출에 사용.
  final bool canEdit;

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  // ------------------------------------------------------------------ 조회
  Map<String, dynamic> _profileOf(String code, String kind) {
    final d = _digits(code);
    final prefix = kind == 'parent' ? '페런츠' : '멘토';
    for (final k in ['$prefix:$d', d]) {
      final v = profiles[k];
      if (v is Map && v.isNotEmpty) {
        final vk = '${v['kind'] ?? ''}'.trim();
        // 구(무접두어) 키 폴백 시 종류가 다르면 오염 방지를 위해 건너뛴다.
        if (vk.isEmpty || vk == kind) return v.cast<String, dynamic>();
      }
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
      final m = state.byNumber(d);
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
    final self = _digits(member.number);
    final codes = parent ? member.parents : member.mentors;
    final out = <_Ref>[];
    for (final c in codes) {
      final d = _digits(c);
      if (d.isEmpty) continue;
      final p = _profileOf(d, parent ? 'parent' : 'mentor');
      final pName = '${p['name'] ?? ''}'.trim();
      final pInfo = _profileInfo(p);
      Member? target;
      // 멘토 저장코드(=멘티=본인 번호)가 본인이면 카드로 연결하지 않는다.
      if (d != self) target = state.byNumber(d);
      if (target == null && pName.isNotEmpty) {
        target = _byPhone(state, '${p['phone'] ?? ''}');
      }
      out.add(
        _Ref(
          code: d,
          name: pName.isNotEmpty ? pName : (target?.name ?? '').trim(),
          info: pInfo.isNotEmpty ? pInfo : _activity(target),
          target: target,
          isSelf: d == self,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${r.name.isEmpty ? '범#${r.code}' : r.name} — 아직 등록된 인가자 카드가 없습니다. '
            '(등록은 관리자·마스터·본인만 가능합니다)',
          ),
        ),
      );
      return;
    }
    // 카드 없음 → 등록 여부 확인 후 등록 페이지로.
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

  // ------------------------------------------------------------------ 빌드
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
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
        ),
        const SizedBox(height: 8),
        _section(
          context,
          title: '멘토 (범을 배출한 대장)',
          icon: Icons.school,
          accent: AppColors.purple,
          refs: _links(state, parent: false),
          empty: '등록된 멘토(범을 배출한 대장) 없음 (복수 등록 가능)',
        ),
        const SizedBox(height: 8),
        _section(
          context,
          title: '페런츠 (범을 배출한 부모님)',
          icon: Icons.family_restroom,
          accent: AppColors.taegeukBlue,
          refs: _links(state, parent: true),
          empty: '등록된 페런츠(범을 배출한 부모님) 없음 (복수 등록 가능)',
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
                '(이름을 누르면 개인페이지로 이동)',
                style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
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
                for (final r in refs) _row(context, r, kindLabel, accent),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, _Ref r, String kindLabel, Color accent) {
    final hasCard = r.target != null;
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
              '범#${r.code}',
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
              onTap: () => _tapName(context, r, kindLabel, accent),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.name.isEmpty ? '(이름 미확인 · 눌러서 등록)' : r.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: r.name.isEmpty
                                  ? AppColors.textGray
                                  : AppColors.taegeukBlue,
                              fontStyle: r.name.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              decoration: hasCard
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              decorationColor: AppColors.taegeukBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          hasCard ? Icons.open_in_new : Icons.person_add_alt_1,
                          size: 13,
                          color: hasCard
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
                    if (!hasCard)
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
  });

  final String code;
  final String name;
  final String info;
  final Member? target;
  final bool isSelf;
}
