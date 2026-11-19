import 'package:flutter/material.dart';
import '../widgets/marquee_text.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/league_names.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';
import 'unit_stats_screen.dart';

/// 통계 대시보드 — 연맹별 인가자/멘토/페런츠/서포터즈 분포, 회비 현황
///
/// ## 연맹별 분포 (신분 탭)
///   상단 버튼으로 신분 전환: (범스카우트) / (멘토) / (멘티) / (서포터즈-일반)
///   모든 분포는 **동일한 정렬 기준**을 사용한다:
///     ① 인가자순  ② 광역통합  ③ 광역대통합  ④ 가나다
///   광역통합   = 도·광역시 단위(서울/광주/전남/부산/울산/경남/인천/경기/…)
///   광역대통합 = 인접 광역 통합(서울/경기/인천/부산·울산·경남/대구·경북/…)
///   가나다 정렬은 종교 연맹(가톨릭 → 원불교 → 기독교)을 지정 순서대로 맨 뒤에 둔다.
///
/// ## 집계 기준
///   · (인가시 기준)  : 범인가시 소속연맹(league)
///   · (현재활동 기준): 현재 소속연맹(regLeague, 없으면 league 로 폴백)
///
/// ## 추가 분포 (2026년 이후 집계, **인가일 기준**)
///   · 연맹별 멘토 대장 분포   (멘토 **본인 소속연맹** 기준 / 2026년 이후 = 멘티 인가일)
///   · 연맹별 페런츠 분포      (인가일 2026년 이후)
///   · 연맹별 서포터즈-일반 분포 (인가일 2026년 이후)
///   → 세 분포 모두 "인가일 2026년 이후" 로 통일한다.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.initialScope = 0});

  /// 처음 열 때의 소속 탭 — 0=범스카우트, 1=은하스카우트.
  final int initialScope;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  /// 신분 탭 — 0=범스카우트(인가자), 1=멘토, 2=멘티, 3=서포터즈-일반.
  int _gap = 0;

  /// 집계 기준 — 0=인가시(범인가 정보), 1=현재활동.
  ///   현재활동 데이터가 없으면 인가시 정보로 자동 폴백한다.
  int _basis = 0;

  /// 소속 — 0=범스카우트, 1=은하스카우트(별도 관리).
  late int _scope = widget.initialScope;

  /// 분포별 정렬 모드: 0=인가자순, 1=광역통합, 2=광역대통합, 3=가나다.
  ///   key: gap0..gap3(신분 탭), mentor, parent, supporter.
  final Map<String, int> _sortMode = {
    'gap0': 0,
    'gap1': 0,
    'gap2': 0,
    'gap3': 0,
    'mentor': 0,
    'parent': 0,
    'supporter': 0,
    'eunha': 0,
  };

  /// 멘토·페런츠 인적사항(소속연맹) — 통계용. 인가번호 → 프로필.
  Map<String, dynamic> _linkProfiles = {};

  /// 연령 통계 대상 — 0=전체, 1=인가자만, 2=일반회원만.
  int _ageScope = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfiles();
      context.read<AppState>().loadEunhaMembers();
    });
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

  /// 생년월일 문자열 → (연,월,일). 4자리 연도가 없으면 null.
  ///   '1980.05.14' / '2010.10.06.' / '1991-03-21' / '20260729'(콤팩트) 등 모두 허용.
  List<int>? _ymdOf(String? s) {
    final raw = (s ?? '').trim();
    if (raw.isEmpty) return null;
    // ① 콤팩트 8자리(YYYYMMDD) — 구분자가 없는 경우.
    final only = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (RegExp(r'^(19|20)\d{6}$').hasMatch(only)) {
      return [
        int.parse(only.substring(0, 4)),
        int.parse(only.substring(4, 6)),
        int.parse(only.substring(6, 8)),
      ];
    }
    // ② 구분자 있는 형식('1991-03-21', '2026.09.30 13:30' 등).
    final digits = RegExp(
      r'[0-9]+',
    ).allMatches(raw).map((m) => m.group(0)!).toList();
    if (digits.isEmpty) return null;
    final year = _yearOf(raw);
    if (year <= 0) return null;
    final rest = <int>[];
    for (final d in digits) {
      if (d.length == 4) continue; // 연도
      rest.add(int.parse(d));
      if (rest.length == 2) break;
    }
    final mo = rest.isNotEmpty ? rest[0] : 0;
    final da = rest.length >= 2 ? rest[1] : 0;
    return [year, mo, da];
  }

  /// 생년월일 + 기준일 → **만 나이**. 월·일 정보가 없으면 연도 차이로 근사한다.
  int _ageOf(String? birthday, DateTime on) {
    final b = _ymdOf(birthday);
    if (b == null) return -1;
    var age = on.year - b[0];
    if (b[1] > 0 && b[2] > 0) {
      if (on.month < b[1] || (on.month == b[1] && on.day < b[2])) age -= 1;
    }
    return age;
  }

  /// 생년별(출생연도) 분포 — 라벨은 'YYYY년(만 N세)'.
  Map<String, int> _birthYearDist(AppState state) {
    final now = DateTime.now();
    final map = <String, int>{};
    for (final m in _ageBaseMembers(state, gaps: null)) {
      final y = _ymdOf(m.birthday)?[0] ?? 0;
      if (y <= 0) continue;
      final age = now.year - y;
      final key = '$y년 (만 $age세)';
      map[key] = (map[key] ?? 0) + 1;
    }
    return _finalizeKeepLabel(map);
  }

  /// 연령별(현재 나이) 분포 — 10세 구간.
  static const List<String> _brackets = [
    '10대 이하',
    '20대',
    '30대',
    '40대',
    '50대',
    '60대',
    '70대 이상',
  ];

  String _bracketOf(int age) {
    if (age < 0) return '(미지정)';
    if (age < 20) return '10대 이하';
    if (age < 30) return '20대';
    if (age < 40) return '30대';
    if (age < 50) return '40대';
    if (age < 60) return '50대';
    if (age < 70) return '60대';
    return '70대 이상';
  }

  static const List<Color> _ageColors = [
    AppColors.taegeukBlue,
    AppColors.purple,
    AppColors.scoutGreen,
    AppColors.tigerGold,
    AppColors.taegeukRed,
    Color(0xFF26A69A),
    Color(0xFF8D6E63),
  ];

  Color _ageColor(String label) {
    final i = _brackets.indexOf(label);
    return i >= 0 ? _ageColors[i % _ageColors.length] : AppColors.textGray;
  }

  /// 현재 나이 분포(10세 구간) — 고정 순서(10대→70대)로, 미지정은 맨 뒤.
  Map<String, int> _currentAgeDist(AppState state) {
    final now = DateTime.now();
    final map = <String, int>{};
    var unknown = 0;
    for (final m in _ageBaseMembers(state, gaps: null)) {
      final age = _ageOf(m.birthday, now);
      if (age < 0) {
        unknown++;
        continue;
      }
      final b = _bracketOf(age);
      map[b] = (map[b] ?? 0) + 1;
    }
    final out = <String, int>{};
    for (final b in _brackets) {
      if ((map[b] ?? 0) > 0) out[b] = map[b]!;
    }
    if (unknown > 0) out['(미지정)'] = unknown;
    return out;
  }

  /// 인가시 나이 분포(10세 구간) — 인가일(date) 기준. 데이터가 없으면 (미지정).
  Map<String, int> _inductionAgeDist(AppState state) {
    final map = <String, int>{};
    var unknown = 0;
    var any = false;
    for (final m in _ageBaseMembers(state, gaps: null)) {
      final ind = _parseDate(m.date);
      if (ind == null) {
        unknown++;
        continue;
      }
      final age = _ageOf(m.birthday, ind);
      if (age < 0) {
        unknown++;
        continue;
      }
      any = true;
      final b = _bracketOf(age);
      map[b] = (map[b] ?? 0) + 1;
    }
    final out = <String, int>{};
    if (any) {
      for (final b in _brackets) {
        if ((map[b] ?? 0) > 0) out[b] = map[b]!;
      }
    }
    if (unknown > 0) out['(미지정)'] = unknown;
    if (out.isEmpty) return const {};
    return out;
  }

  /// 연도별 평균 인가 나이 — 인가연도 → 평균 (만)나이.
  Map<String, double> _inductionAvgByYear(AppState state) {
    final sum = <int, int>{};
    final cnt = <int, int>{};
    for (final m in _ageBaseMembers(state, gaps: null)) {
      final ind = _parseDate(m.date);
      if (ind == null) continue;
      final age = _ageOf(m.birthday, ind);
      if (age < 0) continue;
      sum[ind.year] = (sum[ind.year] ?? 0) + age;
      cnt[ind.year] = (cnt[ind.year] ?? 0) + 1;
    }
    final out = <String, double>{};
    for (final y in sum.keys) {
      out['$y년'] = sum[y]! / cnt[y]!;
    }
    return out;
  }

  /// 인가일 문자열 → DateTime. '2026-07-29' / '2026.07.29' / '20260729' 등 허용.
  DateTime? _parseDate(String? s) {
    final b = _ymdOf(s);
    if (b == null) return null;
    final mo = b[1] == 0 ? 1 : b[1];
    final da = b[2] == 0 ? 1 : b[2];
    if (mo < 1 || mo > 12 || da < 1 || da > 31) return null;
    return DateTime(b[0], mo, da);
  }

  /// 연령 통계 대상 회원 — [gaps] 지정 시 해당 신분만(0=범,3=일반), null이면 전체.
  ///   · 은하스카우트 소속은 범 통계와 무관하므로 제외한다.
  ///   · _ageScope(0=전체/1=인가자/2=일반) 필터를 적용한다.
  List<Member> _ageBaseMembers(AppState state, {required List<int>? gaps}) {
    final out = <Member>[];
    for (final m in state.allMembers) {
      if (m.corps == 'eunha') continue;
      if (gaps != null) {
        final g = m.isRegular ? 3 : 0;
        if (!gaps.contains(g)) continue;
      }
      if (_ageScope == 1 && m.isRegular) continue;
      if (_ageScope == 2 && !m.isRegular) continue;
      out.add(m);
    }
    return out;
  }

  /// 라벨을 유지한 채 정렬(생년 등) — 값이 0이면 버리고, 라벨 문자열 오름차순.
  Map<String, int> _finalizeKeepLabel(Map<String, int> map) {
    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
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

  /// 멘토 대장 분포 — **멘토 본인 소속연맹** 기준(소속연맹 기준 확정).
  ///   · [cutoff2026] 이면 **멘티(연결 회원)의 인가일** 2026년 이후만 집계.
  ///     (페런츠·서포터즈와 동일하게 "인가일 기준"으로 통일)
  ///   · 멘토 프로필의 number = 멘티(연결 회원) 범인가자번호.
  Map<String, int> _mentorCounts(AppState state, {bool cutoff2026 = false}) {
    final map = <String, int>{};
    for (final prof in _linkProfiles.values) {
      final p = (prof as Map?)?.cast<String, dynamic>();
      if (p == null) continue;
      if ('${p['kind'] ?? ''}' != 'mentor') continue;
      if (cutoff2026) {
        // 멘티(연결 회원)의 인가일 기준 — 멘티를 찾을 수 없으면 제외.
        final mentee = state.byNumber('${p['number'] ?? ''}');
        if (mentee == null) continue;
        if (_yearOf(mentee.date) < 2026) continue;
      }
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

  /// 은하스카우트 연맹 분포 — 별도 명단(state.eunhaMembers) 기준.
  Map<String, int> _eunhaLeagueCounts(List<Member> ms) {
    final map = <String, int>{};
    for (final m in ms) {
      final k = normalizeLeague(m.league);
      final key = k.isEmpty ? '(미지정)' : k;
      map[key] = (map[key] ?? 0) + 1;
    }
    return _finalize(map);
  }

  /// 정렬 적용 — 0=인가자순(그대로) / 1=광역통합 / 2=광역대통합 / 3=가나다.
  Map<String, int> _sortDist(Map<String, int> src, int mode) {
    switch (mode) {
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

    final eunhaOnly = _scope == 1;
    final eunhaList = state.eunhaMembers;
    final eunhaSrc = _sortDist(
      _eunhaLeagueCounts(eunhaList),
      _sortMode['eunha'] ?? 0,
    );
    final eunhaYears = <int, int>{};
    for (final m in eunhaList) {
      // [수정 2026-11-03] 범스카우트와 **같은 정규화 함수**를 쓴다.
      //  (종전 `_yearOf` 는 정규식만 봐서 `19980-6-30` 같은 오타에 안전했지만,
      //   2자리 연도 `03.3.11` 은 못 읽었다 → 양쪽 다 `credYear` 로 통일)
      final y = m.credYear;
      if (y > 0) eunhaYears[y] = (eunhaYears[y] ?? 0) + 1;
    }
    final sortedEunhaYears = eunhaYears.keys.toList()..sort();

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
          // ── 단위대별 상세내역 배너 ────────────────────────────────
          //  [요구 2026-11-11] "이 페이지는 통계 페이지 내에 배너를 하나 만들고
          //   단위대별 연맹별 상세내역 이렇게 넣어서 그 안에다가 다양한
          //   옵션들을 선택할 출력할 수 있게 해 주면 좋겠어"
          _unitStatsBanner(),
          const SizedBox(height: 12),
          // 소속 전환 — 범스카우트 / 은하스카우트(별도 관리)
          _scopeTabs(),
          const SizedBox(height: 6),
          if (eunhaOnly) ...[
            // ---- 은하스카우트(별도 관리) 통계 ----
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _statBox(
                      '은하 인가자',
                      '${eunhaList.length}',
                      Icons.groups_2_outlined,
                      AppColors.taegeukBlue,
                    ),
                    _divider(),
                    _statBox(
                      '연맹 수',
                      '${_eunhaLeagueCounts(eunhaList).length}',
                      Icons.public,
                      AppColors.purple,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _sectionTitle('연맹별 인가자 분포 (은하스카우트)'),
            _distTabs('eunha'),
            _distRows(eunhaSrc),
            const SizedBox(height: 16),
            _sectionTitle('연도별 인가 현황 (은하스카우트)'),
            if (sortedEunhaYears.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '연도 데이터가 없습니다.',
                  style: TextStyle(color: AppColors.textGray),
                ),
              )
            else
              ...sortedEunhaYears.reversed.map((y) {
                final v = eunhaYears[y]!;
                final maxYear = eunhaYears.values.reduce(
                  (a, b) => a > b ? a : b,
                );
                return _barRow(
                  context: context,
                  label: '$y년',
                  value: v,
                  max: maxYear,
                  color: AppColors.taegeukBlue,
                );
              }),
          ] else ...[
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
            _sectionTitle('연맹별 멘토 대장 분포 (2026년 이후 인가 기준)'),
            _distTabs('mentor'),
            _distRows(mentorSrc),
            const SizedBox(height: 16),
            _sectionTitle('연맹별 페런츠 분포 (2026년 이후 인가 기준)'),
            _distTabs('parent'),
            _distRows(parentSrc),
            const SizedBox(height: 16),
            _sectionTitle('연맹별 서포터즈-일반 분포 (2026년 이후 인가 기준)'),
            _distTabs('supporter'),
            _distRows(supporterSrc),
          ],

          const SizedBox(height: 16),
          if (!eunhaOnly)
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
          if (!eunhaOnly) _sectionTitle('연간회비 납부 현황'),
          if (!eunhaOnly)
            ...feeYears.map((y) {
              final paid = state.members
                  .where((m) => m.feeYears[y] == true)
                  .length;
              final total = state.total;
              return _feeRow(y, paid, total);
            }),
          const SizedBox(height: 16),
          // ## [수정 2026-11-03] 종전 제목은 '(2004~2025)' 로 범위를 못박았지만
          //  실제 데이터는 1927년(초대 김용우)~2026년까지 걸쳐 있다.
          //  범위를 제목에 굳히지 않고, 실제 집계 연도를 부제로 보여준다.
          if (!eunhaOnly)
            _sectionTitle(
              sortedYears.isEmpty
                  ? '연도별 인가 현황'
                  : '연도별 인가 현황 '
                        '(${sortedYears.first}~${sortedYears.last})',
            ),
          if (!eunhaOnly)
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
          if (!eunhaOnly) ...[const SizedBox(height: 24), _ageSection(state)],
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  /// 연령 통계 — 인가시 나이 · 현재 나이 · 생년별 · 연령별(요구).
  ///   · 대상 범위 탭: 전체 / 인가자 / 일반회원.
  ///   · 모든 집계는 회원 생년월일(birthday) 기반, 인가시 나이는 인가일(date) 기준.
  Widget _ageSection(AppState state) {
    final now = DateTime.now();
    final base = _ageBaseMembers(state, gaps: null);
    final withBirth = base.where((m) => _ymdOf(m.birthday) != null).toList();
    final missing = base.length - withBirth.length;

    var sumCur = 0, nCur = 0, sumInd = 0, nInd = 0;
    for (final m in withBirth) {
      final ca = _ageOf(m.birthday, now);
      if (ca >= 0) {
        sumCur += ca;
        nCur++;
      }
      final ind = _parseDate(m.date);
      if (ind != null) {
        final ia = _ageOf(m.birthday, ind);
        if (ia >= 0) {
          sumInd += ia;
          nInd++;
        }
      }
    }
    final avgCur = nCur == 0 ? '-' : (sumCur / nCur).toStringAsFixed(1);
    final avgInd = nInd == 0 ? '-' : (sumInd / nInd).toStringAsFixed(1);

    final curDist = _currentAgeDist(state);
    final indDist = _inductionAgeDist(state);
    final birthDist = _birthYearDist(state);
    final avgByYear = _inductionAvgByYear(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('연령 통계 (인가시 나이 · 현재 나이 · 생년별 · 연령별)'),
        // 대상 범위 탭
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('전체', style: TextStyle(fontSize: 11.5)),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('인가자', style: TextStyle(fontSize: 11.5)),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('일반회원', style: TextStyle(fontSize: 11.5)),
                ),
              ],
              selected: {_ageScope},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity(horizontal: -3, vertical: -2),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 2),
                ),
              ),
              onSelectionChanged: (s) => setState(() => _ageScope = s.first),
            ),
          ),
        ),
        // 요약
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _statBox(
                  '평균 현재 나이',
                  '$avgCur세',
                  Icons.cake_outlined,
                  AppColors.purple,
                ),
                _divider(),
                _statBox(
                  '평균 인가 나이',
                  '$avgInd세',
                  Icons.emoji_events_outlined,
                  AppColors.tigerGold,
                ),
                _divider(),
                _statBox(
                  '생년 기재',
                  '${withBirth.length}명',
                  Icons.event_available,
                  AppColors.taegeukBlue,
                ),
              ],
            ),
          ),
        ),
        if (missing > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              '· 생년월일 미기재 $missing명은 연령 집계에서 제외되었습니다.',
              style: const TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
          ),
        const SizedBox(height: 14),
        // 연령별(현재 나이)
        _sectionTitle('연령별 분포 (현재 나이 · 10세 구간)'),
        if (curDist.isEmpty)
          _emptyRow('연령 데이터가 없습니다 (생년월일 미기재).')
        else
          ..._ageRows(curDist, '명'),
        const SizedBox(height: 16),
        // 인가시 나이 구간
        _sectionTitle('인가시 나이 분포 (인가 당시 연령 · 10세 구간)'),
        if (indDist.isEmpty)
          _emptyRow('인가시 나이 데이터가 없습니다 (생년월일 또는 인가일 미기재).')
        else
          ..._ageRows(indDist, '명'),
        const SizedBox(height: 16),
        // 생년별
        _sectionTitle('생년별 분포 (출생연도별)'),
        if (birthDist.isEmpty)
          _emptyRow('생년 데이터가 없습니다.')
        else
          ..._birthYearRows(birthDist),
        const SizedBox(height: 16),
        // 연도별 평균 인가 나이
        _sectionTitle('연도별 평균 인가 나이 (추세)'),
        if (avgByYear.isEmpty)
          _emptyRow('연도별 평균 인가 나이 데이터가 없습니다.')
        else
          ..._avgYearRows(avgByYear),
      ],
    );
  }

  Widget _emptyRow(String text) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(text, style: const TextStyle(color: AppColors.textGray)),
  );

  /// 연령 구간(10대~70대) 막대 — 고정 순서 색상.
  Iterable<Widget> _ageRows(Map<String, int> src, String unit) {
    final maxVal = src.values.reduce((a, b) => a > b ? a : b);
    return src.entries.map(
      (e) => _barRow(
        context: context,
        label: e.key,
        value: e.value,
        max: maxVal,
        color: _ageColor(e.key),
      ),
    );
  }

  /// 생년별 막대 — 라벨 'YYYY년 (만 N세)', 인원 많은 순 상위 25개만 노출(가독성).
  Iterable<Widget> _birthYearRows(Map<String, int> src) {
    final entries = src.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final shown = entries.length > 25 ? entries.sublist(0, 25) : entries;
    return [
      ...shown.map(
        (e) => _barRow(
          context: context,
          label: e.key,
          value: e.value,
          max: maxVal,
          color: AppColors.scoutGreen,
        ),
      ),
      if (entries.length > 25)
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: Text(
            '· 인원 상위 25개 생년만 표시 (전체 ${entries.length}개)',
            style: const TextStyle(fontSize: 10.5, color: AppColors.textGray),
          ),
        ),
    ];
  }

  /// 연도별 평균 인가 나이 — 얇은 카드 행.
  Iterable<Widget> _avgYearRows(Map<String, double> src) {
    final keys = src.keys.toList()..sort();
    final maxAvg = src.values.reduce((a, b) => a > b ? a : b);
    return keys.map(
      (k) => _barRow(
        context: context,
        label: k,
        value: (src[k]! * 10).round(),
        max: (maxAvg * 10).round(),
        color: AppColors.tigerGold,
        display: '${src[k]!.toStringAsFixed(1)}세',
      ),
    );
  }

  /// 가나다순 정렬 — '(미지정)' 및 종교 연맹은 [compareLeagueName] 규칙을 따른다.
  Map<String, int> _sortByName(Map<String, int> src) {
    final entries = src.entries.toList()
      ..sort((a, b) => compareLeagueName(a.key, b.key));
    return {for (final e in entries) e.key: e.value};
  }

  /// 광역(권역) 통합 — 요구 표기 순서(지리 권역 먼저, 종교 연맹은 맨 뒤).
  ///   라벨은 "권역명\n(구성 연맹 나열)" 형식. '(미지정)'은 항상 마지막.
  ///   [scope] = integrated(도·광역시 단위) | grand(인접 광역 통합).
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
    // 구성 연맹명도 인원 많은 순으로 정렬해 라벨 가독성 확보.
    for (final list in parts.values) {
      list.sort((a, b) => (src[b] ?? 0).compareTo(src[a] ?? 0));
    }
    final hasUnassigned = src.containsKey('(미지정)');
    // 요구 표기 순서 기준 정렬(순서 목록에 없으면 인원 많은 순 → 이름순).
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
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 2),
            ),
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

  /// 소속 전환 탭 — 범스카우트 / 은하스카우트(별도 관리).
  /// 단위대별 · 연맹별 상세내역으로 들어가는 배너.
  ///
  /// [요구] "통계 페이지 내에 배너를 하나 만들고 단위대별 연맹별 상세내역"
  ///  · 이 화면(연맹 분포)은 '몇 명인가' 를 보여주고,
  ///    저 화면은 '어느 단위대가 배출했나' 를 보여준다. 역할이 다르므로
  ///    배너로 분리해 두고 눌러서 들어가게 한다.
  Widget _unitStatsBanner() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const UnitStatsScreen())),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3B2470), Color(0xFF4B2E83), Color(0xFF1F6F6B)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.purple.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.account_tree_outlined,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '단위대별 · 연맹별 상세내역',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '어느 단위대가 몇 명을 배출·보유했는지, 표기 변형 확인과 명부까지',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.white, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scopeTabs() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.groups, size: 15),
              label: Text('범스카우트', style: TextStyle(fontSize: 12)),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.groups_2_outlined, size: 15),
              label: Text('은하스카우트', style: TextStyle(fontSize: 12)),
            ),
          ],
          selected: {_scope},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -3, vertical: -2),
          ),
          onSelectionChanged: (s) => setState(() => _scope = s.first),
        ),
      ),
    );
  }

  /// 정렬 탭 — 인가자순 / 광역통합 / 광역대통합 / 가나다.
  /// [key]별로 독립적으로 유지된다.
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
          selected: {cur},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -3, vertical: -2),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 2),
            ),
          ),
          onSelectionChanged: (s) => setState(() => _sortMode[key] = s.first),
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
                    const Icon(
                      Icons.privacy_tip,
                      color: AppColors.purple,
                      size: 18,
                    ),
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
                  valueColor: const AlwaysStoppedAnimation(
                    AppColors.scoutGreen,
                  ),
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
                Icon(
                  Icons.verified_user,
                  size: 16,
                  color: AppColors.scoutGreen,
                ),
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
                _statusChip(
                  '승인',
                  state.linkApprovedCount,
                  AppColors.scoutGreen,
                ),
                _statusChip(
                  '미승인',
                  state.linkPendingCount,
                  AppColors.taegeukRed,
                ),
                // [turn71] _statusChip 은 색을 **글자**에 쓴다 → goldInk.
                _statusChip('보류', state.linkHeldCount, AppColors.goldInk),
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
    String? display,
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
                child: MarqueeText(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
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
                  display ?? '$value명',
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
              child: MarqueeText(
                subLabel,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textGray,
                  height: 1.15,
                ),
                maxLines: 2,
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
