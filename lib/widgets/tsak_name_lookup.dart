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
