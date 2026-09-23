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
    this.onTap,
    this.onLongPress,
    this.onCheckToggle,
  });

  final Member member;
  final bool selected;
  final bool selectMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onCheckToggle;

  @override
  Widget build(BuildContext context) {
    final color = leagueColor(member.league);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              if (selectMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: onCheckToggle,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? AppColors.purple : Colors.white,
                        border: Border.all(
                          color: AppColors.purple.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
                ),
              MemberAvatar(
                name: member.name,
                photoPath: member.photoPath,
                league: member.league,
                size: 50,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.name.isEmpty ? '(이름없음)' : member.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.purple, AppColors.purpleLight],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '#${member.number}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (member.lifetimeMember) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.star,
                            size: 16,
                            color: AppColors.tigerGold,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (member.league.isNotEmpty)
                          _badge(member.league, color),
                        if (member.unit.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              member.unit,
                              style: const TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (member.date.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '인가 ${member.date}'
                        '${member.atasNo.isNotEmpty ? '  ·  ATAS ${member.atasNo}' : ''}',
                        style: TextStyle(
                          color: AppColors.textGray.withValues(alpha: 0.85),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!selectMode && member.phone.isNotEmpty)
                Icon(
                  Icons.phone,
                  color: AppColors.scoutGreen.withValues(alpha: 0.8),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
