import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/league_names.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 은하스카우트 통계 — 범스카우트와 **분리 관리**되는 별도 통계.
///
/// 레이아웃은 범스카우트 통계(StatsScreen)와 동일하게 맞춘다.
///  · 연맹별 인가자 분포 (인가자순 / 광역통합 / 광역대통합 / 가나다)
///  · 연도별 인가 현황
class EunhaStatsScreen extends StatefulWidget {
  const EunhaStatsScreen({super.key});

  @override
  State<EunhaStatsScreen> createState() => _EunhaStatsScreenState();
}

class _EunhaStatsScreenState extends State<EunhaStatsScreen> {
  /// 정렬 모드 — 0=인가자순, 1=광역통합, 2=광역대통합, 3=가나다.
  int _sortMode = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AppState>().loadEunhaMembers(),
    );
  }

  int _yearOf(String? s) {
    final m = RegExp(r'(19|20)\d{2}').firstMatch(s ?? '');
    return m == null ? 0 : int.parse(m.group(0)!);
  }

  Map<String, int> _finalize(Map<String, int> map) {
    final e = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final out = <String, int>{};
    for (final x in e) {
      if (x.key != '(미지정)') out[x.key] = x.value;
    }
    if (map.containsKey('(미지정)')) out['(미지정)'] = map['(미지정)']!;
    return out;
  }

  /// 연맹별 분포 — 은하스카우트 명단(league) 기준.
  Map<String, int> _leagueCounts(List<Member> ms) {
    final map = <String, int>{};
    for (final m in ms) {
      final k = normalizeLeague(m.league);
      final key = k.isEmpty ? '(미지정)' : k;
      map[key] = (map[key] ?? 0) + 1;
    }
    return _finalize(map);
  }

  Map<String, int> _sortDist(Map<String, int> src) {
    switch (_sortMode) {
      case 1:
        return _groupByRegion(src, RegionScope.integrated);
      case 2:
        return _groupByRegion(src, RegionScope.grand);
      case 3:
        return _sortByName(src);
      default:
        return src;
    }
  }

  Map<String, int> _sortByName(Map<String, int> src) {
    final entries = src.entries.toList()
      ..sort((a, b) => compareLeagueName(a.key, b.key));
    return {for (final e in entries) e.key: e.value};
  }

  Map<String, int> _groupByRegion(Map<String, int> src, RegionScope scope) {
    final sums = <String, int>{};
    final parts = <String, List<String>>{};
    for (final e in src.entries) {
      if (e.key == '(미지정)') continue;
      final region = leagueRegion(e.key, scope: scope);
      final r = region.isEmpty ? e.key : region;
      sums[r] = (sums[r] ?? 0) + e.value;
      final list = parts.putIfAbsent(r, () => []);
      if (!list.contains(e.key)) list.add(e.key);
    }
    for (final list in parts.values) {
      list.sort((a, b) => (src[b] ?? 0).compareTo(src[a] ?? 0));
    }
    final hasUnassigned = src.containsKey('(미지정)');
    final ordered = sums.keys.toList()
      ..sort((a, b) {
        final ia = regionOrderIndex(a, scope);
        final ib = regionOrderIndex(b, scope);
        if (ia != ib) return ia.compareTo(ib);
        final ca = sums[a] ?? 0, cb = sums[b] ?? 0;
        if (ca != cb) return cb.compareTo(ca);
        return a.compareTo(b);
      });
    final out = <String, int>{};
    for (final region in ordered) {
      final ps = parts[region] ?? const [];
      final sub = ps.length > 1 ? '(${ps.join(' + ')})' : null;
      out[sub == null ? region : '$region\n$sub'] = sums[region]!;
    }
    if (hasUnassigned) out['(미지정)'] = src['(미지정)']!;
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ms = state.eunhaMembers;
    final mainSrc = _sortDist(_leagueCounts(ms));

    // 연도별 인가 현황
    final years = <int, int>{};
    for (final m in ms) {
      final y = _yearOf(m.date);
      if (y > 0) years[y] = (years[y] ?? 0) + 1;
    }
    final sortedYears = years.keys.toList()..sort();

    return Scaffold(
      appBar: TsakAppBar(
        title: const Text('은하스카우트 통계'),
        actions: const [AppHomeEmblem(size: 26)],
      ),
      body: state.eunhaLoading && ms.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _statBox(
                          '은하 인가자',
                          '${ms.length}',
                          Icons.groups,
                          AppColors.taegeukBlue,
                        ),
                        _divider(),
                        _statBox(
                          '연맹 수',
                          '${_leagueCounts(ms).length}',
                          Icons.public,
                          AppColors.purple,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionTitle('연맹별 인가자 분포'),
                _distTabs(),
                _distRows(mainSrc),
                const SizedBox(height: 16),
                _sectionTitle('연도별 인가 현황'),
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

  Widget _distTabs() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              label: Text('인가자순', style: TextStyle(fontSize: 11.5)),
            ),
            ButtonSegment(
              value: 1,
              label: Text('광역통합', style: TextStyle(fontSize: 11.5)),
            ),
            ButtonSegment(
              value: 2,
              label: Text('광역대통합', style: TextStyle(fontSize: 11.5)),
            ),
            ButtonSegment(
              value: 3,
              label: Text('가나다', style: TextStyle(fontSize: 11.5)),
            ),
          ],
          selected: {_sortMode},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -3, vertical: -2),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 2),
            ),
          ),
          onSelectionChanged: (s) => setState(() => _sortMode = s.first),
        ),
      ),
    );
  }

  Widget _distRows(Map<String, int> src) {
    if (src.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          '은하스카우트 명단이 없습니다.',
          style: TextStyle(color: AppColors.textGray),
        ),
      );
    }
    final maxVal = src.values.reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in src.entries)
          _barRow(
            context: context,
            label: e.key.split('\n').first,
            subLabel: e.key.contains('\n') ? e.key.split('\n')[1] : null,
            value: e.value,
            max: maxVal,
            color: leagueColor(e.key.split('\n').first),
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

  static const double _labelW = 100;

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
}
