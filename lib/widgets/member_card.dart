import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'marquee_text.dart';
import 'member_avatar.dart';

/// 컬러풀 리스트용 인가자 카드
class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.member,
    this.selected = false,
    this.selectMode = false,
    this.scale = 1.0,
    this.onTap,
    this.onLongPress,
    this.onCheckToggle,
    this.onEdit,
    this.canSeeRealName = true,
  });

  final Member member;
  final bool selected;
  final bool selectMode;
  final double scale;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onCheckToggle;

  /// 이름 좌측 편집창 — 실명/개인정보 입력 화면으로 이동
  final VoidCallback? onEdit;

  /// 관리자·마스터·본인이면 true(실명 표시). false면 nameVisible=false 회원을 마스킹.
  final bool canSeeRealName;

  @override
  Widget build(BuildContext context) {
    final color = leagueColor(member.league);
    final s = scale;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 5 * s),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? const BorderSide(color: AppColors.purple, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12 * s),
          child: Row(
            children: [
              if (selectMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: onCheckToggle,
                    child: Container(
                      width: 26 * s,
                      height: 26 * s,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? AppColors.purple : Colors.white,
                        border: Border.all(
                          color: AppColors.purple.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? Icon(Icons.check, color: Colors.white, size: 16 * s)
                          : null,
                    ),
                  ),
                ),
              // 이름 좌측 편집창 — 실명/개인정보를 바로 입력·수정
              if (!selectMode && onEdit != null)
                Padding(
                  padding: EdgeInsets.only(right: 8 * s),
                  child: Tooltip(
                    message: '개인정보 편집 (실명·연락처 등)',
                    child: InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 7 * s,
                          vertical: 8 * s,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.purple.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_note,
                              size: 18 * s,
                              color: AppColors.purple,
                            ),
                            SizedBox(height: 1 * s),
                            Text(
                              '편집',
                              style: TextStyle(
                                fontSize: 9.5 * s,
                                fontWeight: FontWeight.w800,
                                color: AppColors.purple,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              MemberAvatar(
                name: member.name,
                photoPath: member.photoPath,
                fallbackPhotoUrl:
                    context.watch<AppState>().serverPhotoUrlFor(
                      member.number,
                    ) ??
                    '',
                league: member.league,
                // 편집 박스 높이에 맞춰 원형 사진을 확대해 균형·식별성 향상
                size: 52 * s,
                number: member.number,
                showNumber: false,
                // 비회원(일반회원)은 기본 호랑이 대신 사람 실루엣 사용
                useTigerDefault: !member.isRegular,
              ),
              SizedBox(width: 10 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: MarqueeText(
                            member.displayName(canSeeRealName: canSeeRealName),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 19 * s,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        SizedBox(width: 6 * s),
                        // 말머리(소속 배지) — 범스카우트 '범' / 은하스카우트 '은하'
                        _corpsMark(member, s),
                        // 인가번호 박스 — **인가번호가 있을 때만** 노출한다.
                        //  (요구) 일반회원은 "일반 + 전화번호"로 표시하지 않는다.
                        //   역할은 아래 '역할 단추(일반·멘토·페런츠·멘티)'로 중복 표시.
                        if (member.number.trim().isNotEmpty) ...[
                          SizedBox(width: 4 * s),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 9 * s,
                              vertical: 3 * s,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.purple,
                                  AppColors.purpleLight,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              // 소속 접두어 — 은하 회원은 인가번호 앞에 '은하'를 붙인다
                              //  (예: '은하46호'). 범스카우트는 기존 '305호' 유지.
                              '${member.corps == 'eunha' ? '은하' : ''}${member.number}호',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15 * s,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                        // 아타스 인가번호 — 범 인가번호 뒤에 표시
                        if (member.atasNo.isNotEmpty) ...[
                          SizedBox(width: 4 * s),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 7 * s,
                              vertical: 2 * s,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.scoutGreen.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.scoutGreen.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Text(
                              'ATAS ${member.atasNo}',
                              style: TextStyle(
                                color: AppColors.scoutGreen,
                                fontSize: 13 * s,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                        if (member.lifetimeMember) ...[
                          SizedBox(width: 4 * s),
                          Icon(
                            Icons.star,
                            size: 16 * s,
                            color: AppColors.tigerGold,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 5 * s),
                    // 2번째 줄 — 역할 단추(일반·멘토·페런츠·멘티) + 연맹/단위대 + 인가일
                    Row(
                      children: [
                        // (요구) 일반회원은 "일반 010-xxxx"가 아니라 **'일반' 단추**로,
                        //  거기에 (멘토)(페런츠)(멘티) 역할 단추를 중복해서 함께 표시.
                        ..._roleChips(member, s),
                        if (member.league.isNotEmpty) ...[
                          SizedBox(width: 5 * s),
                          _badge(member.league, color, s),
                        ],
                        if (member.unit.isNotEmpty) ...[
                          SizedBox(width: 5 * s),
                          Flexible(
                            child: MarqueeText(
                              member.unit,
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12.5 * s,
                              ),
                            ),
                          ),
                        ],
                        // 현재 등록 연맹/단위대가 부여값과 다르면 함께 표시
                        if (member.regLeague.isNotEmpty &&
                            member.regLeague != member.league) ...[
                          SizedBox(width: 6 * s),
                          _badge(
                            '현재 ${member.regLeague}',
                            AppColors.taegeukBlue,
                            s,
                          ),
                        ],
                        if (member.regUnit.isNotEmpty &&
                            member.regUnit != member.unit) ...[
                          SizedBox(width: 5 * s),
                          Flexible(
                            child: MarqueeText(
                              member.regUnit,
                              style: TextStyle(
                                color: AppColors.taegeukBlue,
                                fontSize: 12 * s,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        if (member.date.isNotEmpty) ...[
                          SizedBox(width: 8 * s),
                          Flexible(
                            child: MarqueeText(
                              '인가 ${member.date}',
                              style: TextStyle(
                                color: AppColors.textGray.withValues(
                                  alpha: 0.85,
                                ),
                                fontSize: 11 * s,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!selectMode && member.phone.isNotEmpty)
                Icon(
                  Icons.phone,
                  color: AppColors.scoutGreen.withValues(alpha: 0.8),
                  size: 20 * s,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 말머리 — 소속(corps) 배지. 범스카우트 '범'(청록) / 은하스카우트 '은하'(청색).
  ///   요구: "은하 스카우트도 명단검색되도록 하고 아래와 유사하게 말머리 만들어 노출".
  Widget _corpsMark(Member m, double s) {
    final isEunha = m.corps == 'eunha';
    final label = isEunha ? '은하' : '범';
    final color = isEunha ? AppColors.taegeukBlue : AppColors.scoutGreen;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7 * s, vertical: 3 * s),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13 * s,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _badge(String text, Color color, double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5 * s,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// (요구) 역할 단추 — (일반)(멘토)(페런츠)(멘티)를 **중복해서** 표시한다.
  ///   · 일반   : 비인가(일반)회원.
  ///   · 멘토   : 이 회원을 배출한 지도 대장이 있음(mentors).
  ///   · 페런츠 : 범을 배출한 부모님이 있음(parents).
  ///   · 멘티   : 이 회원이 배출한 대원이 있음(mentees) / 자녀대원(children).
  ///   한 사람이 여러 역할을 겸하면 단추를 나란히 모두 보여준다.
  List<Widget> _roleChips(Member m, double s) {
    final out = <Widget>[];
    void add(String label, Color color) {
      if (out.isNotEmpty) out.add(SizedBox(width: 4 * s));
      out.add(
        Container(
          padding: EdgeInsets.symmetric(horizontal: 7 * s, vertical: 2 * s),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5 * s,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    if (m.isRegular) add('일반', AppColors.textGray);
    if (m.mentors.isNotEmpty) add('멘토', AppColors.purple);
    if (m.parents.isNotEmpty) add('페런츠', AppColors.taegeukBlue);
    if (m.mentees.isNotEmpty || m.children.isNotEmpty) {
      add('멘티', AppColors.scoutGreen);
    }
    return out;
  }
}
