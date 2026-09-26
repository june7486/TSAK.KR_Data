import 'package:flutter/material.dart';

import '../services/build_info.dart';

/// 앱바용 컴팩트 버전 라벨 — 좁은 공간에 빌드 버전을 표시.
/// 모든 페이지에서 버전을 확인할 수 있도록 한다.
class VersionBadge extends StatelessWidget {
  const VersionBadge({super.key, this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          compact ? kBuildShort : versionShortLabel,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
