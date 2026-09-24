import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';

/// 통계 대시보드 — 연맹별/연도별 인가자 분포, 회비 현황
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final leagues = state.leagues;
    final years = state.yearDistribution;
    final feeYears = state.feeYears;

    final sortedYears = years.keys.toList()..sort();
    final maxLeague = leagues.values.isEmpty
        ? 1
        : leagues.values.reduce((a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('통계 / 현황'),
        actions: const [AppHomeEmblem(size: 26)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _summary(state),
          const SizedBox(height: 12),
          _sectionTitle('연맹별 인가자 분포'),
          ...leagues.entries.map(
            (e) => _barRow(
              context: context,
              label: e.key,
              value: e.value,
              max: maxLeague,
              color: leagueColor(e.key),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('연간회비 납부 현황'),
          ...feeYears.map((y) {
            final paid = state.members
                .where((m) => m.feeYears[y] == true)
                .length;
            final total = state.total;
            return _feeRow(y, paid, total);
          }),
          const SizedBox(height: 16),
          _sectionTitle('연도별 인가 현황 (2004~2025)'),
          ...sortedYears.reversed.map((y) {
            final v = years[y]!;
            final maxYear = years.values.reduce((a, b) => a > b ? a : b);
            return _barRow(
              context: context,
              label: '$y년',
              value: v,
              max: maxYear,
              color: AppColors.taegeukBlue,
            );
          }),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _summary(AppState state) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _statBox(
                  '전체',
                  '${state.total}',
                  Icons.groups,
                  AppColors.purple,
                ),
                _divider(),
                _statBox(
                  '범 인가자',
                  '${state.credentialCount}',
                  Icons.verified_user,
                  AppColors.taegeukBlue,
                ),
                _divider(),
                _statBox(
                  '검색결과',
                  '${state.members.length}',
                  Icons.search,
                  AppColors.scoutGreen,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _statBox(
                  '멘토 연결',
                  '${state.mentorLinkedCount}',
                  Icons.supervisor_account,
                  AppColors.purpleLight,
                ),
                _divider(),
                _statBox(
                  '페런츠 연결',
                  '${state.parentLinkedCount}',
                  Icons.family_restroom,
                  AppColors.taegeukRed,
                ),
                _divider(),
                _statBox(
                  '평생회원',
                  '${state.lifetimeCount}',
                  Icons.star,
                  AppColors.tigerGold,
                ),
                _divider(),
                _statBox(
                  '일반회원',
                  '${state.regularCount}',
                  Icons.person_outline,
                  AppColors.textGray,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.privacy_tip, color: AppColors.purple, size: 18),
                    const SizedBox(width: 6),
                    const Text(
                      '개인정보 동의 현황',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statBox(
                      '동의 완료',
                      '${state.privacyAgreedCount}',
                      Icons.verified,
                      AppColors.scoutGreen,
                    ),
                    _divider(),
                    _statBox(
                      '미동의',
                      '${state.privacyPendingCount}',
                      Icons.warning_amber_rounded,
                      AppColors.taegeukRed,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: state.total == 0
                      ? 0
                      : state.privacyAgreedCount / state.total,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(6),
                  backgroundColor: AppColors.taegeukRed.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation(AppColors.scoutGreen),
                ),
                const SizedBox(height: 4),
                Text(
                  '동의율 ${state.total == 0 ? 0 : (state.privacyAgreedCount / state.total * 100).toStringAsFixed(1)}%'
                  ' (${state.privacyAgreedCount}/${state.total})',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGray,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '※ 개인정보 수집·이용 및 제3자 제공 동의는 가입/저장 시 필수입니다.',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 46, color: Colors.grey.shade200);

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Text(
      t,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 15,
        color: AppColors.textDark,
      ),
    ),
  );

  Widget _barRow({
    required BuildContext context,
    required String label,
    required int value,
    required int max,
    required Color color,
  }) {
    final ratio = max == 0 ? 0.0 : value / max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 20,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              '$value명',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _feeRow(String year, int paid, int total) {
    final ratio = total == 0 ? 0.0 : paid / total;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.scoutGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                year,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.scoutGreen,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation(
                      AppColors.scoutGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '납부 $paid명 / 전체 $total명 (${(ratio * 100).toStringAsFixed(1)}%)',
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
      ),
    );
  }
}
