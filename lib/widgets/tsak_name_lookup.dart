/// **인가자 이름·번호 조회 → 선택** 필드 (마스터/관리자 전용).
///
/// ## 요구 (원문 2026-11-01)
/// > "마스터/관리자로 로그인시: 멘토, 페런츠 인적사항 추가란에 범스카우트
/// >  인가자번호 입력란에 인가자 이름, 번호를 조회하면 이름을 선택할 수 있도록
/// >  하고, 그 이름을 선택 후 해당 범인가자의 현재 활동정보가 자동으로
/// >  입력되도록 할 것, 멘토, 페런츠, 멘티 모두 같이 조회 후 그 정보가
/// >  입력되도록 할 것 (마스터, 관리자 로그인이 아닐 경우 개인정보 노출 위험이
/// >  있으므로 현재처럼 각각 입력할 수 있도록 함)"
///
/// ## 왜 권한 게이트인가
///  이름으로 **전체 인가자 명부를 검색**할 수 있다는 것은 곧 개인정보 열람이다.
///  그래서 이 필드는 `state.isMaster || state.isApp` 일 때만 쓴다. 일반(개인)
///  로그인은 기존처럼 번호를 직접 적고 각 칸을 손으로 채운다.
///
/// ## 동작
///  ① 입력란에 이름 또는 번호를 적으면 **초성 무관 부분일치**로 후보를 보여준다.
///  ② 후보(이름 + 인가번호 + 소속)를 누르면 그 사람이 확정되고
///     [onPicked] 로 [Member] 가 넘어간다 — 호출측이 활동정보를 채운다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// 마스터·관리자(전체 인가자 조회 권한)인지.
bool tsakIsAdminViewer(AppState state) => state.isMaster || state.isApp;

/// 조회어 정규화 — 공백 제거 + 소문자(한글은 그대로).
String tsakNormText(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 숫자만 남긴다.
String tsakDigits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// 인가자 조회 — **번호 완전일치 → 번호 앞자리 → 이름 완전일치 → 이름 포함**.
///
///  은하와 범은 번호가 겹치므로(1~165) 둘 다 나오게 두고, 카드에 소속을
///  표시해 사용자가 구분하게 한다. 같은 [Member] 는 한 번만 담는다.
List<Member> tsakSearchMembers(
  AppState state,
  String raw, {
  int limit = 12,
}) {
  final key = tsakNormText(raw);
  if (key.isEmpty) return const <Member>[];
  final digits = tsakDigits(key);
  final out = <Member>[];
  void take(Member m) {
    if (out.length >= limit) return;
    if (out.contains(m)) return;
    out.add(m);
  }

  if (digits.isNotEmpty) {
    for (final m in state.allMembers) {
      if (tsakDigits(m.number) == digits) take(m);
    }
    for (final m in state.allMembers) {
      final d = tsakDigits(m.number);
      if (d.isNotEmpty && d.startsWith(digits)) take(m);
    }
  }
  for (final m in state.allMembers) {
    if (tsakNormText(m.name) == key) take(m);
  }
  for (final m in state.allMembers) {
    final nm = tsakNormText(m.name);
    if (nm.isNotEmpty && nm.contains(key)) take(m);
  }
  return out;
}

/// 조회 결과 한 줄에 표시할 소속 문구 — `연맹 / 단위대`.
String tsakAffiliation(Member m) {
  final lg = m.regLeague.trim().isNotEmpty ? m.regLeague : m.league;
  final un = m.regUnit.trim().isNotEmpty ? m.regUnit : m.unit;
  final parts = [
    if (lg.trim().isNotEmpty) lg.trim(),
    if (un.trim().isNotEmpty) un.trim(),
  ];
  return parts.join(' / ');
}

// ══════════════════════════════════════════════════════════════════════════
// 명부 전체(회원 카드 + 멘토·페런츠 인적사항) 통합 검색
//
// ## 요구 (원문 2026-11-04)
// > "납부자검색항목을 좀더 폭넓게 해주세요. 인가자번호, 서포터즈이름, 멘토,
// >  멘티, 페런츠 등 명부에 있는 사람들의 전화번호, 이름, 연맹, 단위대 등등
// >  중에서 선택할 수 있도록 해줘."
// > "후원자, 참가비 등에도 동일하게 검색할 수 있도록 해줘"
//
// ## 왜 별도 위젯인가
//  기존 [TsakMemberLookupField] 는 **회원 카드만** 찾는다(인가번호/이름).
//  그런데 명부에는 카드가 없는 사람도 있다:
//    · 비인가 멘토·페런츠 → `link_profiles` 인적사항으로만 존재
//    · 전화번호 계정(`reg_<전화>`) → 인가번호가 없음
//  참가비·후원은 그런 분들도 낼 수 있으므로, 두 출처를 **한 목록**으로 합쳐
//  번호·이름·전화·연맹·단위대·직위 **전 항목**으로 찾는다.
// ══════════════════════════════════════════════════════════════════════════

/// 명부 검색 결과 한 건 — 회원 카드든 인적사항이든 같은 모양으로 다룬다.
class TsakRosterHit {
  TsakRosterHit({
    required this.name,
    required this.number,
    required this.phone,
    required this.league,
    required this.unit,
    required this.position,
    required this.corps,
    required this.isCard,
    this.member,
  });

  final String name;

  /// 인가번호(카드) 또는 인적사항의 대표번호.
  final String number;

  /// 전화번호(숫자만).
  final String phone;

  final String league;
  final String unit;
  final String position;

  /// 'tsak' | 'eunha'
  final String corps;

  /// 실제 회원 카드가 있는가(없으면 인적사항뿐인 사람).
  final bool isCard;

  final Member? member;
}

String _d(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// 명부 통합 검색 — **정확도 순**으로 최대 [limit] 건.
///
/// ## 정렬 규칙 (사용자가 기대하는 순서)
///  ① 번호 완전일치  ② 전화 완전일치  ③ 이름 완전일치
///  ④ 이름 앞부분    ⑤ 번호 앞부분    ⑥ 전화 뒷자리
///  ⑦ 연맹/단위대/직위 포함  ⑧ 그 외 부분일치
///
/// 인적사항만 있는 사람은 **뒤에** 붙인다(카드가 있는 사람이 우선).
List<TsakRosterHit> tsakSearchRoster(
  AppState state,
  Map<String, dynamic> profiles,
  String raw, {
  int limit = 20,
}) {
  final q = tsakNormText(raw);
  if (q.isEmpty) return const <TsakRosterHit>[];
  final qd = tsakDigits(q);

  final seen = <String>{};
  final bucket = <int, List<TsakRosterHit>>{};

  void put(int score, TsakRosterHit h) {
    // ── 중복 제거는 **사람** 기준 ──
    //  같은 분이 ① 회원 카드(전화번호 계정, 인가번호 없음)와 ② 멘토·페런츠
    //  인적사항 양쪽에 존재할 수 있다(실측: 선영진 — 카드는 number 가 비어
    //  있고 인적사항은 01046236587). 번호+이름으로만 비교하면 두 번 나온다.
    //  그래서 전화번호가 있으면 전화번호를, 없으면 번호+이름을 키로 쓴다.
    final ph = _d(h.phone);
    final key = ph.isNotEmpty
        ? 'tel:$ph'
        : '${h.corps}:${_d(h.number)}:${tsakNormText(h.name)}';
    if (!seen.add(key)) return;
    bucket.putIfAbsent(score, () => []).add(h);
  }

  int scoreOf({
    required String name,
    required String number,
    required String phone,
    required String league,
    required String unit,
    required String position,
  }) {
    final nm = tsakNormText(name);
    final nd = _d(number);
    final pd = _d(phone);
    if (qd.isNotEmpty && nd.isNotEmpty && nd == qd) return 1;
    if (qd.isNotEmpty && pd.isNotEmpty && pd == qd) return 2;
    if (nm.isNotEmpty && nm == q) return 3;
    if (nm.isNotEmpty && nm.startsWith(q)) return 4;
    if (qd.isNotEmpty && nd.isNotEmpty && nd.startsWith(qd)) return 5;
    if (qd.length >= 4 && pd.isNotEmpty && pd.endsWith(qd)) return 6;
    final aff = tsakNormText('$league $unit $position');
    if (aff.isNotEmpty && aff.contains(q)) return 7;
    if (nm.isNotEmpty && nm.contains(q)) return 8;
    if (pd.isNotEmpty && qd.length >= 4 && pd.contains(qd)) return 8;
    return 0;
  }

  // ── ① 회원 카드 ──
  for (final m in state.allMembers) {
    final lg = m.regLeague.trim().isNotEmpty ? m.regLeague : m.league;
    final un = m.regUnit.trim().isNotEmpty ? m.regUnit : m.unit;
    final s = scoreOf(
      name: m.name,
      number: m.number,
      phone: m.phone,
      league: lg,
      unit: un,
      position: m.position,
    );
    if (s == 0) continue;
    put(
      s,
      TsakRosterHit(
        name: m.name.trim(),
        number: m.number,
        phone: _d(m.phone),
        league: lg.trim(),
        unit: un.trim(),
        position: m.position.trim(),
        corps: m.corps,
        isCard: true,
        member: m,
      ),
    );
  }

  // ── ② 멘토·페런츠 인적사항(카드 없이 명부에만 있는 분들) ──
  for (final e in profiles.entries) {
    final v = e.value;
    if (v is! Map) continue;
    final p = v.cast<String, dynamic>();
    final nm = '${p['name'] ?? ''}'.trim();
    if (nm.isEmpty) continue;
    final phone = '${p['phone'] ?? ''}';
    final num = '${p['number'] ?? ''}';
    final s = scoreOf(
      name: nm,
      number: num,
      phone: phone,
      league: '${p['league'] ?? ''}',
      unit: '${p['unit'] ?? ''}',
      position: '${p['position'] ?? ''}',
    );
    if (s == 0) continue;
    final kind = '${p['kind'] ?? ''}'.trim();
    final kinds = p['kinds'];
    final roles = <String>{
      if (kind == 'mentor') '멘토',
      if (kind == 'parent') '페런츠',
      if (kinds is List)
        for (final k in kinds)
          if ('$k' == 'mentor') '멘토' else if ('$k' == 'parent') '페런츠',
    }.toList();
    put(
      // 카드 없는 분은 뒤로 (같은 점수 안에서 뒤에 쌓임).
      s + 10,
      TsakRosterHit(
        name: nm,
        number: num,
        phone: _d(phone),
        league: '${p['league'] ?? ''}'.trim(),
        unit: '${p['unit'] ?? ''}'.trim(),
        position: roles.isNotEmpty
            ? roles.join('·')
            : '${p['position'] ?? ''}'.trim(),
        corps: 'tsak',
        isCard: false,
      ),
    );
  }

  final out = <TsakRosterHit>[];
  for (var s = 1; s <= 20 && out.length < limit; s++) {
    final b = bucket[s];
    if (b == null) continue;
    for (final h in b) {
      if (out.length >= limit) break;
      out.add(h);
    }
  }
  return out;
}

/// 납부자·후원자 검색 필드 — 명부 전체에서 찾아 고른다.
///
/// 고르면 [onPicked] 로 (표시이름, 인가번호, 전화번호) 를 돌려준다.
class TsakPayerLookupField extends StatefulWidget {
  const TsakPayerLookupField({
    super.key,
    required this.controller,
    required this.profiles,
    required this.onPicked,
    this.label = '후원자 / 납부자',
    this.hint = '이름·인가번호·전화·연맹·단위대',
    this.required = false,
  });

  /// 납부자 이름을 담는 컨트롤러(호출측 소유).
  final TextEditingController controller;

  /// 개인상세의 `_linkProfilesCache` 를 그대로 넘긴다(멘토·페런츠 인적사항).
  final Map<String, dynamic> profiles;

  /// 선택 결과 — 이름 / 인가번호(없으면 빈 칸) / 전화번호(숫자만).
  final void Function(String name, String number, String phone) onPicked;

  final String label;
  final String hint;
  final bool required;

  @override
  State<TsakPayerLookupField> createState() => _TsakPayerLookupFieldState();
}

class _TsakPayerLookupFieldState extends State<TsakPayerLookupField> {
  String _q = '';
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final hits = _open && _q.trim().isNotEmpty
        ? tsakSearchRoster(state, widget.profiles, _q)
        : const <TsakRosterHit>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          decoration: InputDecoration(
            isDense: true,
            labelText: widget.label,
            hintText: widget.hint,
            suffixIcon: IconButton(
              icon: const Icon(Icons.person_search, size: 18),
              tooltip: '명부에서 찾기',
              onPressed: () => setState(() => _open = !_open),
            ),
          ),
          onChanged: (v) => setState(() {
            _q = v;
            _open = true;
          }),
        ),
        if (_open) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.25),
              ),
            ),
            child: _q.trim().isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Text(
                      '이름 · 인가번호 · 전화번호 · 연맹 · 단위대 · 직위로 찾습니다',
                      style: TextStyle(fontSize: 11, color: AppColors.textGray),
                    ),
                  )
                : hits.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Text(
                      '명부에서 찾지 못했습니다 — 이름을 직접 입력하세요',
                      style: TextStyle(fontSize: 11, color: AppColors.textGray),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: hits.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _tile(hits[i]),
                  ),
          ),
        ],
      ],
    );
  }

  void _pick(TsakRosterHit h) {
    widget.controller.text = h.name;
    setState(() {
      _open = false;
      _q = '';
    });
    // 은하 카드는 'G' 접두어를 유지한다(번호 충돌 방지).
    var num = _d(h.number);
    if (num.isNotEmpty && h.corps == 'eunha') num = 'G$num';
    widget.onPicked(h.name, num, h.phone);
  }

  Widget _tile(TsakRosterHit h) {
    final sub = [
      if (h.league.isNotEmpty) h.league,
      if (h.unit.isNotEmpty) h.unit,
      if (h.position.isNotEmpty) h.position,
    ].join(' · ');
    final badge = h.number.trim().isEmpty
        ? (h.phone.isEmpty ? '' : '전화 ${h.phone}')
        : '${h.corps == 'eunha' ? '은하' : '범'}#${h.number}';
    return InkWell(
      onTap: () => _pick(h),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: h.isCard
                  ? AppColors.purple.withValues(alpha: 0.12)
                  : AppColors.tigerGold.withValues(alpha: 0.18),
              child: Text(
                h.name.isEmpty ? '?' : h.name.substring(0, 1),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: h.isCard ? AppColors.purple : AppColors.tigerGold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          h.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      if (badge.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: (h.isCard
                                    ? AppColors.purple
                                    : AppColors.tigerGold)
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: h.isCard
                                  ? AppColors.purple
                                  : AppColors.tigerGold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textGray,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 15,
              color: AppColors.textGray,
            ),
          ],
        ),
      ),
    );
  }
}

/// 인가번호 필드 + 후보 목록.
class TsakMemberLookupField extends StatefulWidget {
  const TsakMemberLookupField({
    super.key,
    required this.controller,
    required this.onPicked,
    this.label = '인가번호 (이름·번호 조회)',
    this.hint = '예: 2186 또는 김범수',
    this.helper = '이름을 선택하면 현재 활동정보가 자동 입력됩니다',
    this.autofocus = false,
    this.overwrite = false,
  });

  /// 인가번호를 담는 컨트롤러(호출측 소유).
  final TextEditingController controller;

  /// 후보를 골랐을 때.
  final void Function(Member m) onPicked;

  final String label;
  final String hint;
  final String helper;
  final bool autofocus;

  /// 이미 적힌 값도 덮어쓸지 — 기본은 빈 칸만 채운다.
  final bool overwrite;

  @override
  State<TsakMemberLookupField> createState() => _TsakMemberLookupFieldState();
}

class _TsakMemberLookupFieldState extends State<TsakMemberLookupField> {
  String _q = '';
  bool _open = true;

  void _onChanged(String v) {
    setState(() {
      _q = v;
      _open = true;
    });
  }

  void _pick(Member m) {
    final d = tsakDigits(m.number);
    widget.controller.text = m.corps == 'eunha' ? 'G$d' : d;
    setState(() {
      _q = '';
      _open = false;
    });
    widget.onPicked(m);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final hits = (_open && _q.trim().isNotEmpty)
        ? tsakSearchMembers(state, _q)
        : const <Member>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            helperText: widget.helper,
            helperMaxLines: 2,
            suffixIcon: const Icon(Icons.search, size: 18),
          ),
          onChanged: _onChanged,
        ),
        if (_open && _q.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 196),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.25)),
            ),
            child: hits.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Text(
                      '일치하는 인가자가 없습니다 — 번호를 직접 입력하세요',
                      style: TextStyle(fontSize: 11, color: AppColors.textGray),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: hits.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _tile(hits[i]),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _tile(Member m) {
    final aff = tsakAffiliation(m);
    final pos = m.position.trim();
    final act = m.activity.trim();
    final sub = [
      if (aff.isNotEmpty) aff,
      if (pos.isNotEmpty) pos,
      if (act.isNotEmpty) act,
    ].join(' · ');
    return InkWell(
      onTap: () => _pick(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.purple.withValues(alpha: 0.12),
              child: Text(
                m.name.trim().isEmpty ? '?' : m.name.trim().substring(0, 1),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.name.trim().isEmpty ? '(이름없음)' : m.name.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          m.displayNumber,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.purple,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textGray,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textGray),
          ],
        ),
      ),
    );
  }
}
