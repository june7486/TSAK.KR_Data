import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/league_names.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 통계 대시보드 — 연맹별/연도별 인가자 분포, 회비 현황
///
/// 연맹 분포 상단 탭 (3종):
///   1) 인원수별 — 개별 연맹, 인가자 많은 순 (★ 당초 기본 뷰)
///   2) 가나다  — 연맹명 가나다순 (명부 느낌)
///   3) 권역통합 — 광역 권역으로 묶어 인가자 많은 순
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  /// 0 = 인원수별(당초 기본), 1 = 가나다순, 2 = 권역통합(인원순)
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final baseLeagues = state.leagues; // 정규화 + 인원 내림차순 (미지정 마지막)
    final leagues = switch (_tab) {
      1 => _sortByName(baseLeagues),
      2 => _groupByRegion(baseLeagues),
      _ => baseLeagues, // 0: 인원수별(기본) — 정규화 + 인원 내림차순
    };
    final years = state.yearDistribution;
    final feeYears = state.feeYears;

    final sortedYears = years.keys.toList()..sort();
    final maxLeague = leagues.values.isEmpty
        ? 1
        : leagues.values.reduce((a, b) => a > b ? a : b);

    return Scaffold(
      appBar: TsakAppBar(
        title: const Text('통계 / 현황'),
        actions: const [AppHomeEmblem(size: 26)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _summary(state),
          const SizedBox(height: 12),
          _sectionTitle('회원 유형 분포'),
          _typeDistribution(state),
          const SizedBox(height: 12),
          _sectionTitle('멘토 · 페런츠 연결 현황'),
          _linkStatus(state),
          const SizedBox(height: 12),
          _sectionTitle('연맹별 인가자 분포'),
          _leagueTabs(),
          const SizedBox(height: 4),
          if (leagues.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('연맹 데이터가 없습니다.',
                  style: TextStyle(color: AppColors.textGray)),
            )
          else
            ...leagues.entries.map(
              (e) {
                final parts = e.key.split('\n');
                final name = parts.first;
                final sub = parts.length > 1 ? parts[1] : null;
                return _barRow(
                  context: context,
                  label: name,
                  subLabel: sub,
                  value: e.value,
                  max: maxLeague,
                  color: leagueColor(name),
                );
              },
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

  /// 가나다순 정렬 ('(미지정)'은 항상 마지막).
  Map<String, int> _sortByName(Map<String, int> src) {
    final entries = src.entries.toList()
      ..sort((a, b) => compareLeagueName(a.key, b.key));
    return {for (final e in entries) e.key: e.value};
  }

  /// 권역(광역) 통합 → 인가자 많은 순.
  ///   라벨은 "권역명\n(구성 연맹 나열)" 형식. '(미지정)'은 항상 마지막.
  Map<String, int> _groupByRegion(Map<String, int> src) {
    final sums = <String, int>{};
    final members = <String, List<String>>{};
    for (final e in src.entries) {
      if (e.key == '(미지정)') continue;
      final region = leagueRegion(e.key).isEmpty ? e.key : leagueRegion(e.key);
      sums[region] = (sums[region] ?? 0) + e.value;
      final list = members.putIfAbsent(region, () => []);
      if (!list.contains(e.key)) list.add(e.key);
    }
    final hasUnassigned = src.containsKey('(미지정)');
    final ordered = sums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final out = <String, int>{};
    for (final e in ordered) {
      final parts = members[e.key] ?? const [];
      // 구성 연맹이 2개 이상일 때만 요약 라벨을 붙인다.
      final sub = parts.length > 1 ? '(${parts.join(' + ')})' : null;
      out[sub == null ? e.key : '${e.key}\n$sub'] = e.value;
    }
    if (hasUnassigned) out['(미지정)'] = src['(미지정)']!;
    return out;
  }

  /// 인원수별 / 가나다 / 권역통합 전환 탭 (3종).
  ///   당초 기본 뷰(개별 연맹 인원수별)를 유지하고, 가나다·권역통합을 추가한다.
  Widget _leagueTabs() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.leaderboard, size: 16),
              label: Text('인원수별', style: TextStyle(fontSize: 12.5)),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.sort_by_alpha, size: 16),
              label: Text('가나다', style: TextStyle(fontSize: 12.5)),
            ),
            ButtonSegment(
              value: 2,
              icon: Icon(Icons.apartment, size: 16),
              label: Text('권역통합', style: TextStyle(fontSize: 12.5)),
            ),
          ],
          selected: {_tab},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -3, vertical: -2),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
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

  /// 회원 유형 분포 — 인가자 vs 일반회원(비인가자) 비율
  Widget _typeDistribution(AppState state) {
    final cred = state.credentialCount;
    final regular = state.regularCount;
    final total = state.total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _progressLine(
              '범 인가자',
              cred,
              total,
              AppColors.taegeukBlue,
              Icons.verified_user,
            ),
            const SizedBox(height: 12),
            _progressLine(
              '일반회원(비인가자)',
              regular,
              total,
              AppColors.textGray,
              Icons.person_outline,
            ),
          ],
        ),
      ),
    );
  }

  /// 멘토·페런츠 연결 현황
  Widget _linkStatus(AppState state) {
    final total = state.total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _progressLine(
              '멘토 지정',
              state.mentorLinkedCount,
              total,
              AppColors.purple,
              Icons.supervisor_account,
            ),
            const SizedBox(height: 12),
            _progressLine(
              '페런츠 지정',
              state.parentLinkedCount,
              total,
              AppColors.taegeukRed,
              Icons.family_restroom,
            ),
            const SizedBox(height: 12),
            _progressLine(
              '평생회원',
              state.lifetimeCount,
              total,
              AppColors.tigerGold,
              Icons.star,
            ),
          ],
        ),
      ),
    );
  }

  /// 라벨 + 막대 + 수치 한 줄
  Widget _progressLine(
    String label,
    int value,
    int total,
    Color color,
    IconData icon,
  ) {
    final ratio = total == 0 ? 0.0 : value / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ),
            Text(
              '$value명 (${(ratio * 100).toStringAsFixed(1)}%)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
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

  /// 라벨 칸 너비 — **탭/행과 무관하게 항상 고정**.
  ///   가나다·권역통합 어느 쪽이든 막대(차트) 시작 x좌표가 동일해진다.
  static const double _labelW = 100;

  /// 라벨 + 막대 + 수치 한 줄.
  ///   - 라벨은 [_labelW] 고정 폭 → 탭 전환 시 차트 위치 불변.
  ///   - 구성 연맹 등 작은 글씨(subLabel)는 막대 **아래**에 표기 → 차트 폭에 영향 없음.
  Widget _barRow({
    required BuildContext context,
    required String label,
    String? subLabel,
    required int value,
    required int max,
    required Color color,
  }) {
    final ratio = max == 0 ? 0.0 : value / max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: _labelW,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
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
                width: 48,
                child: Text(
                  '$value명',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          if (subLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: _labelW - 8, top: 2),
              child: Text(
                subLabel,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textGray,
                  height: 1.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
