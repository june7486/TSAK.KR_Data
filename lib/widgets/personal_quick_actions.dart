import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/member_edit_screen.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// (요구#3) 개인아이디로 접속한 화면에 공통 배치되는 퀵 액션 바.
///  - HOME : 최초(홈) 화면으로 복귀
///  - 본인 정보 편집 : 본인 계정 편집 화면 진입
///
/// 개인 접근(isSelfAccess)이 아니면 아무것도 렌더하지 않으므로,
/// 여러 화면에 안전하게 재사용할 수 있다.
class PersonalQuickActions extends StatelessWidget {
  const PersonalQuickActions({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(12, 10, 12, 2),
  });

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isSelfAccess) return const SizedBox.shrink();
    final me = state.who.isNotEmpty
        ? state.byNumber(state.who)
        : (state.members.isNotEmpty ? state.members.first : null);

    return Padding(
      padding: margin,
      child: Row(
        children: [
          Expanded(
            child: _pill(
              icon: Icons.home_filled,
              label: 'HOME',
              color: AppColors.purple,
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ),
          if (me != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _pill(
                icon: Icons.verified,
                label: '본인 정보 편집',
                color: AppColors.scoutGreen,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MemberEditScreen(memberId: me.id),
                    ),
                  );
                  if (context.mounted) context.read<AppState>().refresh();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
