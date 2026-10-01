import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'transfer_sheet.dart';

/// 중앙회 계좌 목록(3개) — 각 계좌에 「송금」·「복사」 버튼.
///
/// 홈 배너 · 행사 화면 등 어디서나 재사용한다.
/// - 좌측 라벨(한 줄, 넘치면 말줄임)
/// - 우측 계좌번호
/// - 송금(토스/카카오/은행앱 딥링크 시트) · 복사
class DonationAccounts extends StatelessWidget {
  const DonationAccounts({
    super.key,
    this.fontSize = 11,
    this.title,
    this.showHolder = false,
  });

  final double fontSize;

  /// 지정 시 상단에 제목 줄을 함께 표시 (예: '참가비·후원 납부 계좌').
  final String? title;
  final bool showHolder;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rows = <Widget>[
      for (var index = 0; index < state.donations.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${state.donations[index]['label']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    color: AppColors.lifetimeGold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${state.donations[index]['bank']} ${state.donations[index]['account']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _chip(
                icon: Icons.send_rounded,
                label: '송금',
                color: AppColors.scoutGreen,
                onTap: () => showTransferSheet(
                  context,
                  label: '${state.donations[index]['label']}',
                  bank: '${state.donations[index]['bank']}',
                  account: '${state.donations[index]['account']}',
                  holder: state.donationHolder,
                  accounts: state.donations,
                  initialIndex: index,
                  memo: '${state.donations[index]['label']}',
                ),
              ),
              const SizedBox(width: 4),
              _chip(
                icon: Icons.copy,
                label: '복사',
                color: AppColors.purple,
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: '${state.donations[index]['account']}'),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${state.donations[index]['label']} ${state.donations[index]['account']} 복사됨',
                        ),
                        duration: const Duration(milliseconds: 900),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
    ];

    if (title == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tigerGold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance,
                color: AppColors.purple,
                size: 15,
              ),
              const SizedBox(width: 5),
              Text(
                title!,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppColors.textDark,
                ),
              ),
              if (showHolder) ...[
                const Spacer(),
                Text(
                  state.donationHolder,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
