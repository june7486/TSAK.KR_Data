import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/league_names.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 통계 대시보드 — 연맹별 인가자/멘토/페런츠/서포터즈 분포, 회비 현황
///
/// ## 연맹별 분포 (신분 탭)
///   상단 버튼으로 신분 전환: (범스카우트) / (멘토) / (멘티) / (서포터즈-일반)
///   모든 분포는 **동일한 정렬 기준**을 사용한다:
///     ① 인가자순  ② 권역통합  ③ 가나다
///   가나다 정렬은 종교 연맹(가톨릭 → 원불교 → 기독교)을 지정 순서대로 맨 뒤에 둔다.
///
/// ## 집계 기준
///   · (인가시 기준)  : 범인가시 소속연맹(league)
///   · (현재활동 기준): 현재 소속연맹(regLeague, 없으면 league 로 폴백)
///
/// ## 추가 분포 (2026년 이후 집계)
///   · 연맹별 멘토 대장 분포   (멘토 인적사항의 소속연맹)
///   · 연맹별 페런츠 분포
///   · 연맹별 서포터즈-일반 분포
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  /// 신분 탭 — 0=범스카우트(인가자), 1=멘토, 2=멘티, 3=서포터즈-일반.
  int _gap = 0;

  /// 집계 기준 — 0=인가시(범인가 정보), 1=현재활동.
  ///   현재활동 데이터가 없으면 인가시 정보로 자동 폴백한다.
  int _basis = 0;

  /// 분포별 정렬 모드: 0=인가자순, 1=권역통합, 2=가나다.
  ///   key: gap0..gap3(신분 탭), mentor, parent, supporter.
  final Map<String, int> _sortMode = {
    'gap0': 0,
    'gap1': 0,
    'gap2': 0,
    'gap3': 0,
    'mentor': 0,
    'parent': 0,
    'supporter': 0,
  };

  /// 멘토·페런츠 인적사항(소속연맹) — 통계용. 인가번호 → 프로필.
  Map<String, dynamic> _linkProfiles = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfiles());
  }

  Future<void> _loadProfiles() async {
    try {
      final p = await context.read<NasApi>().linkProfiles();
      if (!mounted) return;
      setState(() => _linkProfiles = p);
    } catch (_) {
      // 통계는 프로필 없이도 동작(멘토 연맹 섹션만 비게 된다).
    }
  }

  /// 문자열에서 4자리 연도를 추출(없으면 0). '2025.12.19' / '1991-03-21' / '2026.09.30 13:30'.
  int _yearOf(String? s) {
    final m = RegExp(r'(19|20)\d{2}').firstMatch(s ?? '');
    return m == null ? 0 : int.parse(m.group(0)!);
  }

  /// 카운트 맵 마무리 — 인원 내림차순 정렬, '(미지정)'은 항상 마지막.
  Map<String, int> _finalize(Map<String, int> map) {
    final e = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final out = <String, int>{};
    for (final x in e) {
      if (x.key != '(미지정)') out[x.key] = x.value;
    }
    if (map.containsKey('(미지정)')) out['(미지정)'] = map['(미지정)']!;
    return out;
  }

  /// 신분(gap)별 연맹 분포.
  ///  · gap 0(범스카우트): 전체 회원 — currentOnly 면 regLeague(폴백 league)
  ///  · gap 1(멘토)      : 멘토 인적사항의 소속연맹
  ///  · gap 2(멘티)      : 멘토가 연결된 회원
  ///  · gap 3(서포터즈-일반): 일반회원(isRegular)
  Map<String, int> _gapCounts(
    AppState state,
    int gap, {
    required bool currentOnly,
  }) {
    final map = <String, int>{};
    void add(String raw) {
      final k = normalizeLeague(raw);
      final key = k.isEmpty ? '(미지정)' : k;
      map[key] = (map[key] ?? 0) + 1;
    }

    if (gap == 1) {
      for (final prof in _linkProfiles.values) {
        final p = (prof as Map?)?.cast<String, dynamic>();
        if (p == null) continue;
        if ('${p['kind'] ?? ''}' != 'mentor') continue;
        add('${p['league'] ?? ''}');
      }
      return _finalize(map);
    }

    for (final m in state.allMembers) {
      switch (gap) {
        case 2:
          if (m.mentors.isEmpty) continue;
          break;
        case 3:
          if (!m.isRegular) continue;
          break;
        default:
          break;
      }
      final raw = currentOnly && m.regLeague.trim().isNotEmpty
          ? m.regLeague
          : m.league;
      add(raw);
    }
    return _finalize(map);
  }

  /// 연맹별 페런츠(보호자) 분포. [cutoff2026] 이면 인가일 2026년 이후만 집계.
  Map<String, int> _parentCounts(AppState state, {bool cutoff2026 = false}) {
    final map = <String, int>{};
    for (final m in state.allMembers) {
      if (cutoff2026 && _yearOf(m.date) < 2026) continue;
      if (m.parents.isEmpty) continue;
      final k = normalizeLeague(m.league);
      final key = k.isEmpty ? '(미지정)' : k;
      map[key] = (map[key] ?? 0) + 1;
    }
    return _finalize(map);
  }

  /// 멘토 대장 분포. [cutoff2026] 이면 프로필 등록연도 2026년 이후만.
  Map<String, int> _mentorCounts(AppState state, {bool cutoff2026 = false}) {
    final map = <String, int>{};
    for (final prof in _linkProfiles.values) {
      final p = (prof as Map?)?.cast<String, dynamic>();
      if (p == null) continue;
      if ('${p['kind'] ?? ''}' != 'mentor') continue;
      if (cutoff2026 && _yearOf('${p['updatedAt'] ?? ''}') < 2026) continue;
      final k = normalizeLeague('${p['league'] ?? ''}');
      final key = k.isEmpty ? '(미지정)' : k;
      map[key] = (map[key] ?? 0) + 1;
    }
    return _finalize(map);
  }

  /// 서포터즈-일반(일반회원) 분포. [cutoff2026] 이면 인가일 2026년 이후만.
  Map<String, int> _supporterCounts(AppState state, {bool cutoff2026 = false}) {
    final map = <String, int>{};
    for (final m in state.allMembers) {
      if (!m.isRegular) continue;
      if (cutoff2026 && _yearOf(m.date) < 2026) continue;
      final k = normalizeLeague(m.league);
      final key = k.isEmpty ? '(미지정)' : k;
      map[key] = (map[key] ?? 0) + 1;
    }
    return _finalize(map);
  }

  /// 정렬 적용 — 0=인가자순(그대로) / 1=권역통합 / 2=가나다(종교연맹 후순위).
  Map<String, int> _sortDist(Map<String, int> src, int mode) {
    switch (mode) {
      case 1:
        return _groupByRegion(src);
      case 2:
        return _sortByName(src);
      default:
        return src;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentOnly = _basis == 1;

    // ① 연맹별 인가자 분포 (신분 탭)
    final mainSrc = _sortDist(
      _gapCounts(state, _gap, currentOnly: currentOnly),
      _sortMode['gap$_gap'] ?? 0,
    );

    // 추가 분포 (2026년 이후 집계)
    final mentorSrc = _sortDist(
      _mentorCounts(state, cutoff2026: true),
      _sortMode['mentor'] ?? 0,
    );
    final parentSrc = _sortDist(
      _parentCounts(state, cutoff2026: true),
      _sortMode['parent'] ?? 0,
    );
    final supporterSrc = _sortDist(
      _supporterCounts(state, cutoff2026: true),
      _sortMode['supporter'] ?? 0,
    );

    final years = state.yearDistribution;
    final feeYears = state.feeYears;
    final sortedYears = years.keys.toList()..sort();

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

          // ---- ① 연맹별 인가자 분포 (신분 탭) ----
          _sectionTitle('연맹별 인가자 분포'),
          _gapTabs(),
          const SizedBox(height: 4),
          _basisTabs(state),
          _distTabs('gap$_gap'),
          _distRows(mainSrc),

          // ---- 추가: 멘토 대장 / 페런츠 / 서포터즈-일반 (2026년 이후) ----
          const SizedBox(height: 16),
          _sectionTitle('연맹별 멘토 대장 분포 (2026년 이후 집계)'),
          _distTabs('mentor'),
          _distRows(mentorSrc),
          const SizedBox(height: 16),
          _sectionTitle('연맹별 페런츠 분포 (2026년 이후 집계)'),
          _distTabs('parent'),
          _distRows(parentSrc),
          const SizedBox(height: 16),
          _sectionTitle('연맹별 서포터즈-일반 분포 (2026년 이후 집계)'),
          _distTabs('supporter'),
          _distRows(supporterSrc),

          const SizedBox(height: 16),
          if (state.positions.isNotEmpty) ...[
            _sectionTitle('직위 분포 (현재활동)'),
            ...state.positions.entries.map(
              (e) => _barRow(
                context: context,
                label: e.key,
                value: e.value,
                max: state.positions.values.reduce((a, b) => a > b ? a : b),
                color: AppColors.purple,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _sectionTitle('연간회비 납부 현황'),
          ...feeYears.map((y) {
            final paid =
                state.members.where((m) => m.feeYears[y] == true).length;
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

  /// 가나다순 정렬 — '(미지정)' 및 종교 연맹은 [compareLeagueName] 규칙을 따른다.
  Map<String, int> _sortByName(Map<String, int> src) {
    final entries = src.entries.toList()
      ..sort((a, b) => compareLeagueName(a.key, b.key));
    return {for (final e in entries) e.key: e.value};
  }

  /// 권역(광역) 통합 → 인원 많은 순.
  ///   라벨은 "권역명\n(구성 연맹 나열)" 형식. '(미지정)'은 항상 마지막.
  Map<String, int> _groupByRegion(Map<String, int> src) {
    final sums = <String, int>{};
    final parts = <String, List<String>>{};
    for (final e in src.entries) {
      if (e.key == '(미지정)') continue;
      final region = leagueRegion(e.key).isEmpty ? e.key : leagueRegion(e.key);
      sums[region] = (sums[region] ?? 0) + e.value;
      final list = parts.putIfAbsent(region, () => []);
      if (!list.contains(e.key)) list.add(e.key);
    }
    final hasUnassigned = src.containsKey('(미지정)');
    final ordered = sums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final out = <String, int>{};
    for (final e in ordered) {
      final ps = parts[e.key] ?? const [];
      final sub = ps.length > 1 ? '(${ps.join(' + ')})' : null;
      out[sub == null ? e.key : '${e.key}\n$sub'] = e.value;
    }
    if (hasUnassigned) out['(미지정)'] = src['(미지정)']!;
    return out;
  }

  /// 신분 전환 탭 — (범스카우트) / (멘토) / (멘티) / (서포터즈-일반).
  Widget _gapTabs() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              label: Text('범스카우트', style: TextStyle(fontSize: 11.5)),
            ),
            ButtonSegment(
              value: 1,
              label: Text('멘토', style: TextStyle(fontSize: 11.5)),
            ),
            ButtonSegment(
              value: 2,
              label: Text('멘티', style: TextStyle(fontSize: 11.5)),
            ),
            ButtonSegment(
              value: 3,
              label: Text('서포터즈-일반', style: TextStyle(fontSize: 11.5)),
            ),
          ],
          selected: {_gap},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -3, vertical: -2),
            padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 2)),
          ),
          onSelectionChanged: (s) => setState(() => _gap = s.first),
        ),
      ),
    );
  }

  /// 집계 기준 전환 탭 — 인가시(범인가 정보) / 현재활동.
  Widget _basisTabs(AppState state) {
    final noCurrent = !state.hasCurrentActivity;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.badge_outlined, size: 15),
                  label: Text('인가시 기준', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.play_circle_outline, size: 15),
                  label: Text('현재활동 기준', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: {_basis},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity(horizontal: -3, vertical: -2),
              ),
              onSelectionChanged: (s) => setState(() => _basis = s.first),
            ),
          ),
          if (_basis == 1 && noCurrent)
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 4),
              child: Text(
                '※ 현재활동 데이터가 없어 인가시 정보를 기준으로 집계했습니다.',
                style: TextStyle(fontSize: 11, color: AppColors.textGray),
              ),
            ),
        ],
      ),
    );
  }

  /// 정렬 탭 — 인가자순 / 권역통합 / 가나다. [key]별로 독립적으로 유지된다.
  Widget _distTabs(String key) {
    final cur = _sortMode[key] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              label: Text('인가자순', style: TextStyle(fontSize: 12.5)),
            ),
            ButtonSegment(
              value: 1,
              label: Text('권역통합', style: TextStyle(fontSize: 12.5)),
            ),
            ButtonSegment(
              value: 2,
              label: Text('가나다', style: TextStyle(fontSize: 12.5)),
            ),
          ],
          selected: {cur},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -3, vertical: -2),
          ),
          onSelectionChanged: (s) =>
              setState(() => _sortMode[key] = s.first),
        ),
      ),
    );
  }

  /// 분포 막대 목록 — 라벨칸 고정폭으로 정렬이 바뀌어도 차트 위치가 동일하다.
  Widget _distRows(Map<String, int> src) {
    if (src.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          '연맹 데이터가 없습니다.',
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
                    const Icon(Icons.privacy_tip,
                        color: AppColors.purple, size: 18),
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
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.scoutGreen),
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
            const Divider(height: 24),
            const Row(
              children: [
                Icon(Icons.verified_user, size: 16, color: AppColors.scoutGreen),
                SizedBox(width: 6),
                Text(
                  '연결 승인 현황',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 승인 상태별 요약 칩 — 승인/미승인(승인요청)/보류/미설정
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _statusChip('승인', state.linkApprovedCount, AppColors.scoutGreen),
                _statusChip('미승인', state.linkPendingCount, AppColors.taegeukRed),
                _statusChip('보류', state.linkHeldCount, AppColors.tigerGold),
                _statusChip('미설정', state.linkUnsetCount, AppColors.textGray),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 승인 상태 요약 칩.
  Widget _statusChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 라벨 + 막대 + 수치 한 줄 (비율 바)
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
  ///   정렬(인가자순·권역통합·가나다) 전환 시에도 막대 시작 x좌표가 동일해진다.
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
