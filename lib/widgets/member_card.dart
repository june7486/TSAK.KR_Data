import 'package:flutter/material.dart';

import '../models/member.dart';
import '../theme/app_theme.dart';
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
  });

  final Member member;
  final bool selected;
  final bool selectMode;
  final double scale;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onCheckToggle;

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
              MemberAvatar(
                name: member.name,
                photoPath: member.photoPath,
                league: member.league,
                size: 25 * s,
                number: member.number,
                showNumber: false,
              ),
              SizedBox(width: 10 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.name.isEmpty ? '(이름없음)' : member.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              // 인가번호(원형)와 비슷한 크기로 확대
                              fontSize: 19 * s,
                              color: AppColors.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 6 * s),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * s,
                            vertical: 2 * s,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.purple, AppColors.purpleLight],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '#${member.number}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12 * s,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
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
                    SizedBox(height: 4 * s),
                    Row(
                      children: [
                        if (member.league.isNotEmpty)
                          _badge(member.league, color, s),
                        if (member.unit.isNotEmpty) ...[
                          SizedBox(width: 5 * s),
                          Flexible(
                            child: Text(
                              member.unit,
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12.5 * s,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (member.date.isNotEmpty ||
                        member.atasNo.isNotEmpty) ...[
                      SizedBox(height: 3 * s),
                      Row(
                        children: [
                          if (member.date.isNotEmpty)
                            Text(
                              '인가 ${member.date}',
                              style: TextStyle(
                                color:
                                    AppColors.textGray.withValues(alpha: 0.85),
                                fontSize: 11.5 * s,
                              ),
                            ),
                          if (member.date.isNotEmpty &&
                              member.atasNo.isNotEmpty)
                            Text(
                              '   ·   ',
                              style: TextStyle(
                                color:
                                    AppColors.textGray.withValues(alpha: 0.85),
                                fontSize: 11.5 * s,
                              ),
                            ),
                          // ATAS 번호가 있으면 인가번호를 초록색으로 함께 표시
                          if (member.atasNo.isNotEmpty)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 6 * s,
                                vertical: 1 * s,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.scoutGreen
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ATAS ${member.atasNo} · #${member.number}',
                                style: TextStyle(
                                  color: AppColors.scoutGreen,
                                  fontSize: 11.5 * s,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
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
}
