import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/build_info.g.dart';

/// 상단 엠블럼 버튼 — 누르면 초기(홈) 화면으로 이동.
///
/// [onHome] 이 주어지면 그 동작을 수행하고, 없으면 첫 라우트까지 pop 한다.
/// [adminHomeOnly] 가 true 이면 관리자/마스터만 동작(그 외에는 아무 반응 없음).
/// 엠블럼 옆에 빌드 버전 라벨을 함께 표시한다 (모든 페이지 버전 확인용).
class AppHomeEmblem extends StatelessWidget {
  const AppHomeEmblem({
    super.key,
    this.size = 30,
    this.onHome,
    this.showLabel = false,
    this.adminHomeOnly = false,
  });

  final double size;
  final VoidCallback? onHome;
  final bool showLabel;

  /// 관리자·마스터 전용 홈 복귀 (개인/일반 접근에서는 비활성)
  final bool adminHomeOnly;

  void _goHome(BuildContext context) {
    if (adminHomeOnly) {
      final s = context.read<AppState>();
      if (!(s.isApp || s.isMaster)) return;
    }
    if (onHome != null) {
      onHome!();
      return;
    }
    // 첫 화면(홈)까지 되돌아간다
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final emblem = Image.asset(
      'assets/images/tsak_emblem.png',
      width: size,
      height: size,
      errorBuilder: (_, __, ___) => Icon(
        Icons.shield,
        size: size * 0.9,
        color: Colors.white,
      ),
    );

    final verText = Text(
      kBuildShort,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.82),
        fontSize: 8.5,
        fontWeight: FontWeight.w600,
        height: 1.0,
      ),
    );

    return InkWell(
      onTap: () => _goHome(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: showLabel
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  emblem,
                  const SizedBox(width: 6),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('한국 범스카우트중앙회 통합 앱'),
                      verText,
                    ],
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  emblem,
                  const SizedBox(height: 1),
                  verText,
                ],
              ),
      ),
    );
  }
}
