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
    this.onEdit,
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
                league: member.league,
                // 편집 박스 높이에 맞춰 원형 사진을 확대해 균형·식별성 향상
                size: 52 * s,
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
                            member.number.trim().isEmpty
                                ? '일반 ${member.loginId}'
                                : member.number,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12 * s,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        // 아타스 인가번호 — 범 인가번호 뒤에 표시
                        if (member.atasNo.isNotEmpty) ...[
                          SizedBox(width: 4 * s),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 7 * s,
                              vertical: 2 * s,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.scoutGreen
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.scoutGreen
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              'ATAS ${member.atasNo}',
                              style: TextStyle(
                                color: AppColors.scoutGreen,
                                fontSize: 11 * s,
                                fontWeight: FontWeight.w800,
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
                    // 2번째 줄 — 연맹/단위대 + (인가일/아타스 보조) 한 줄로 압축
                    Row(
                      children: [
                        if (member.isRegular)
                          _badge('일반회원', AppColors.textGray, s),
                        if (member.isRegular && member.league.isNotEmpty)
                          SizedBox(width: 5 * s),
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
                        if (member.date.isNotEmpty) ...[
                          SizedBox(width: 8 * s),
                          Flexible(
                            child: Text(
                              '인가 ${member.date}',
                              style: TextStyle(
                                color: AppColors.textGray
                                    .withValues(alpha: 0.85),
                                fontSize: 11 * s,
                              ),
                              overflow: TextOverflow.ellipsis,
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
