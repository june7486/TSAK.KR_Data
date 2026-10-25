import 'package:flutter/material.dart';

import '../services/build_info.dart';
import '../theme/app_theme.dart';

/// 새 APK 가 있을 때 띄우는 업데이트 배너.
///
/// [update] 가 null 이면 아무것도 그리지 않는다(SizedBox.shrink).
/// 다운로드/설치 진행 상황은 [busy] 와 [progress](0~1, -1=미상)로 표시한다.
class ApkUpdateBanner extends StatelessWidget {
  const ApkUpdateBanner({
    super.key,
    required this.update,
    required this.onUpdate,
    this.busy = false,
    this.progress = -1,
    this.compact = false,
  });

  /// 서버가 알린 최신 APK. null 이면 미표시.
  final ApkUpdate? update;

  /// '지금 업데이트' 콜백.
  final VoidCallback onUpdate;

  /// 다운로드/설치 진행 중 여부.
  final bool busy;

  /// 진행률 0.0~1.0 (음수=미상 → 인디터미넌트 표시).
  final double progress;

  /// 좁은 공간용(로그인 화면) 축약형.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final u = update;
    if (u == null) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.purple.withValues(alpha: 0.35),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.purple.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.system_update_alt,
                  size: 18,
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '새 버전이 있습니다 · ${u.version}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purple,
                      ),
                    ),
                    if (!compact)
                      Text(
                        '현재 v1.0.0+$kBuildNumber  →  최신 ${u.version}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textGray,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (u.notes.isNotEmpty && !compact) ...[
            const SizedBox(height: 6),
            Text(
              u.notes,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textGray,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (busy) ...[
            Row(
              children: [
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  progress >= 0
                      ? '다운로드 중… ${(progress * 100).toStringAsFixed(0)}%'
                      : '다운로드 준비 중…',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress >= 0 ? progress : null,
                minHeight: 6,
                backgroundColor: AppColors.purple.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation(AppColors.purple),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpdate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                label: Text(
                  '지금 업데이트',
                  style: TextStyle(
                    fontSize: compact ? 12.5 : 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
