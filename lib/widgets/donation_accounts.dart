import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'marquee_text.dart';
import 'transfer_sheet.dart';

/// 중앙회 계좌 목록(3개) — 각 계좌에 「송금」·「복사」 버튼.
///
/// 홈 배너 · 행사 화면 등 어디서나 재사용한다.
/// - 좌측 라벨(한 줄, 넘치면 말줄임)
/// - 우측 계좌번호
/// - 송금(토스/카카오/은행앱 딥링크 시트) · 복사
///
/// ## 규칙 (요구: "모든 회원 창에서 계좌창에서 접기 펼치기 버튼 넣어주고")
/// 제목이 있는 계좌 박스([title] 지정)는 헤더 우측에 **접기/펼치기 버튼**을
/// 자동으로 넣는다(기본값: 펼침). 제목 없는 순수 목록(홈 대형 배너)은
/// 호출부가 자체 토글을 관리하므로 이 위젯은 헤더·토글을 그리지 않는다.
class DonationAccounts extends StatefulWidget {
  const DonationAccounts({
    super.key,
    this.fontSize = 11,
    this.title,
    this.showHolder = false,
    this.labels,
  });

  final double fontSize;

  /// 지정 시 상단에 제목 줄을 함께 표시 (예: '참가비·후원 납부 계좌').
  final String? title;
  final bool showHolder;

  /// 지정 시 해당 라벨의 계좌만 표시 (예: ['수품구매계좌']). null이면 전체.
  final List<String>? labels;

  @override
  State<DonationAccounts> createState() => _DonationAccountsState();
}

class _DonationAccountsState extends State<DonationAccounts> {
  /// 접힘 상태 — 기본값 펼침(false).
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accounts = widget.labels == null
        ? state.donations
        : state.donations
              .where((a) => widget.labels!.contains('${a['label']}'))
              .toList();
    final rows = <Widget>[
      for (var index = 0; index < accounts.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              // 좌측 묶음: 계좌 이름 + 계좌번호를 나란히 붙여서 표시.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      // 넘치면 좌우로 흐르는 마퀴(요구: "글자가 짤리면 슬라이딩").
                      child: MarqueeText(
                        '${accounts[index]['label']}',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: widget.fontSize,
                          fontWeight: FontWeight.w800,
                          color: AppColors.lifetimeGold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      flex: 2,
                      child: MarqueeText(
                        '${accounts[index]['bank']} ${accounts[index]['account']}',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: widget.fontSize,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _chip(
                icon: Icons.send_rounded,
                label: '송금',
                color: AppColors.scoutGreen,
                onTap: () => showTransferSheet(
                  context,
                  label: '${accounts[index]['label']}',
                  bank: '${accounts[index]['bank']}',
                  account: '${accounts[index]['account']}',
                  holder: state.donationHolder,
                  accounts: accounts,
                  initialIndex: index,
                  memo: '${accounts[index]['label']}',
                ),
              ),
              const SizedBox(width: 4),
              _chip(
                icon: Icons.copy,
                label: '복사',
                color: AppColors.purple,
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: '${accounts[index]['account']}'),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${accounts[index]['label']} ${accounts[index]['account']} 복사됨',
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

    if (widget.title == null) {
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
                widget.title!,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppColors.textDark,
                ),
              ),
              if (widget.showHolder) ...[
                const Spacer(),
                Flexible(
                  child: MarqueeText(
                    state.donationHolder,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AppColors.textGray,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              const SizedBox(width: 4),
              // 접기/펼치기 토글 — 모든 회원 창의 계좌 박스에 자동 제공.
              _toggleBtn(),
            ],
          ),
          // 접힘 상태가 아닐 때만 계좌 목록 노출 (기본값: 펼침).
          if (!_collapsed) ...[const SizedBox(height: 6), ...rows],
        ],
      ),
    );
  }

  /// 접기/펼치기 버튼 — 아이콘 + 라벨. 상태에 따라 문구·방향 전환.
  Widget _toggleBtn() {
    return Material(
      color: AppColors.purple.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _collapsed = !_collapsed),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _collapsed
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up,
                color: AppColors.purple,
                size: 16,
              ),
              const SizedBox(width: 2),
              Text(
                _collapsed ? '펼치기' : '접어두기',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
            ],
          ),
        ),
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
