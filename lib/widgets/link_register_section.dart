import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// 멘토 대장 / 페런츠 등록정보 창 — **멘티 등록정보와 동일한 형식**으로 노출.
///
/// ## 요구
///  · "멘토 정보도 멘티정보와 같은 형식으로 노출해줘"
///  · "멘토(멘티,페런츠) 이름 아래 소속정보는 현재활동 등록정보를 넣어줘"
///
/// ## 표시 규칙
///  · 각 항목 = **[인가번호 배지] + 이름 + (아래) 소속정보**.
///  · 이름 = 인적사항 프로필(멘토·페런츠) 이름.
///  · 소속정보 = 프로필의 소속연맹·소속단위대(현재활동 등록정보).
///  · 값이 없으면 "미등록"을 항상 노출한다(누락 방지).
///
/// ## 연동
///  · 인적사항은 회원 상세/편집의 **LinkCodeField**(/api/link/profiles)와 동일 저장소를
///    사용한다. 표시 전용이며, 입력·수정은 화면 하단의 입력창에서 한다.
class LinkRegisterSection extends StatelessWidget {
  const LinkRegisterSection({
    super.key,
    required this.kind, // 'mentor'(멘토대장) | 'parent'(페런츠)
    required this.codes,
    this.profiles = const {},
    this.badgeSuffix = '',
  });

  final String kind;
  final List<String> codes;

  /// 인가번호 → 인적사항 맵(회원 상세의 _linkProfilesCache 재사용).
  final Map<String, dynamic> profiles;

  /// 제목 옆에 덧붙일 뱃지(예: '  [승인대기]').
  final String badgeSuffix;

  bool get _isMentor => kind == 'mentor';

  Color get _accent => _isMentor ? AppColors.purple : AppColors.taegeukBlue;
  IconData get _icon =>
      _isMentor ? Icons.supervisor_account : Icons.family_restroom;
  String get _title =>
      _isMentor ? '멘토 등록정보' : '페런츠 등록정보 (범을 배출한 부모님)';
  String get _emptyText =>
      _isMentor
      ? '등록된 멘토(범을 배출한 대장) 없음 (복수 등록 가능)'
      : '등록된 페런츠(범을 배출한 부모님) 없음 (복수 등록 가능)';

  Map<String, dynamic> _profileOf(String code) {
    final key = code.replaceAll(RegExp(r'[^0-9]'), '');
    return (profiles[key] as Map?)?.cast<String, dynamic>() ??
        (profiles[code] as Map?)?.cast<String, dynamic>() ??
        {};
  }

  /// 인가번호 배지 라벨 — 소속(은하/범) 접두어를 인가번호 앞에 붙인다.
  ///  · 회원 명단에서 조회되면 그 소속으로, 아니면 '범' 기본.
  ///  · 멘토는 저장 코드가 **멘티(본인) 번호**이므로 '멘티 범#N' 로 표기한다.
  String _badgeLabel(BuildContext context, String code) {
    final d = code.replaceAll(RegExp(r'[^0-9]'), '');
    final shown = d.isEmpty ? code : d;
    Member? m;
    try {
      m = context.watch<AppState>().byNumber(d);
    } catch (_) {
      m = null;
    }
    final prefix = (m?.corps == 'eunha') ? '은하' : '범';
    return _isMentor ? '멘티(본인) $prefix#$shown' : '$prefix#$shown';
  }

  /// 이름 바로 아래 소속정보 = 인적사항의 소속연맹·소속단위대(현재활동 등록정보).
  String _infoOf(String code) {
    final p = _profileOf(code);
    final parts = <String>[];
    final lg = '${p['league'] ?? ''}'.trim();
    final un = '${p['unit'] ?? ''}'.trim();
    if (lg.isNotEmpty) parts.add(lg);
    if (un.isNotEmpty) parts.add(un);
    return parts.join(' · ');
  }

  String _nameOf(String code) => '${_profileOf(code)['name'] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_icon, size: 15, color: _accent),
            const SizedBox(width: 5),
            Text(
              _title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _accent,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                badgeSuffix.isEmpty
                    ? (_isMentor
                          ? '(이 회원을 배출한 지도 대장 · 이름 · 소속)'
                          : '(범을 배출한 부모님 · 이름 · 소속)')
                    : badgeSuffix.trim(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: badgeSuffix.isEmpty
                      ? FontWeight.normal
                      : FontWeight.w800,
                  color: badgeSuffix.isEmpty ? AppColors.textGray : _accent,
                ),
              ),
            ),
          ],
        ),
        if (codes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
            child: Text(
              _emptyText,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final code in codes) _row(context, code)],
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, String code) {
    final nm = _nameOf(code);
    final info = _infoOf(code);
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              _badgeLabel(context, code),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _accent,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nm.isEmpty ? '(이름 미확인)' : nm,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: nm.isEmpty ? AppColors.textGray : AppColors.textDark,
                    fontStyle: nm.isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                if (info.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      info,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textGray,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
