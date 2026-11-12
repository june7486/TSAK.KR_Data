import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../services/unit_stats_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 연맹별 · 단위대별 상세내역 — 2026-11-11 / turn58
///
/// ## [요구] 사용자 원문
///  "범스카우트 인가자들의 인가시 정보를 활용하여 통계란에 연맹별 단위대별
///   인가자 리스트를 출력할 수 있도록 할거야, 또 동일하게 현재 활동정보를
///   활용하는 것도 할꺼야. 대신 단위대 이름을 다르게 쓴 경우가 많아서 출력시
///   체크박스로 선택 가능하도록 하고 전체 명부의 통계 및 상세내역까지
///   출력가능(연맹별 단위대별 선택 가능)하도록 해줘."
///
///  "목표는 각 연맹별 인가자 통계를 내는데 세부적으로 어떤 단위대가 몇 명의
///   범스카우트를 배출했고 현재 어떤 단위대가 몇 명의 범스카우트 인가자들을
///   보유하고 있는지 확인 후 명부를 출력하기 위함이야."
///
///  "예를 들어 많은 범스카우트가 배출된 단위대에는 대장님을 불러 감사장을
///   드리고, 단위대가 배출되지 않은 시점이 너무 오래된 단위대일 경우
///   범스카우트에서 지원책을 마련할 수 있도록 하기 위함이야. 따라서 통계는
///   세부적으로도 표현되어야 되며 다른 대조군과 비교할 수 있게끔 함께
///   출력이 가능해야 돼."
///
///  "그러나 너무 많은 출력 내용이 나오기 때문에 체크박스를 넣어서 출력 여부를
///   결정할 수 있어야 되고, 또한 단위대별로 단위대 이름을 클릭하면 범스카우트
///   인가자의 명부가 함부로 노출되어 그들의 이름을 포함해서 출력할지 말지를
///   결정할 수 있으면 될 거 같애."
///
/// ## 설계 요점
///  ① **기준 전환** — 인가시(league/unit) / 현재활동(regLeague/regUnit)
///  ② **출력 열 선택** — 체크박스로 9개 열을 켜고 끈다(과다 출력 방지)
///  ③ **연맹 선택** — 체크박스 목록(복수). 선택 없으면 전체
///  ④ **단위대 선택 + 비교** — 체크한 단위대만 표에 남겨 나란히 대조
///  ⑤ **이름 노출은 명시적 동의** — 단위대 이름을 누르면 상세 시트가 열리고,
///     그 안에서 '이름 포함' 스위치를 켜야만 이름이 보인다.
///     (서버도 names=1 을 주지 않으면 이름을 지우고 내려준다 — 이중 방어)
///  ⑥ **표기 변형 병합** — 같은 단위대가 다르게 적힌 것을 한 묶음으로 보여주고,
///     체크 후 '같은 단위대로 묶기' 로 확정한다(관리자).
class UnitStatsScreen extends StatefulWidget {
  const UnitStatsScreen({super.key});

  @override
  State<UnitStatsScreen> createState() => _UnitStatsScreenState();
}

class _UnitStatsScreenState extends State<UnitStatsScreen> {
  // ── 기준 ─────────────────────────────────────────────────────────
  String _basis = 'issue'; // issue | active

  // ── 데이터 ───────────────────────────────────────────────────────
  UnitStatsResult? _data;
  UnitStatsResult? _dataNamed; // 이름 포함본(필요할 때만 따로 받는다)
  bool _loading = false;
  String? _error;

  // ── 출력 옵션 (체크박스) ─────────────────────────────────────────
  /// 켜고 끄는 열 — 과다 출력을 막기 위한 핵심 장치.
  final Map<String, bool> _col = {
    'count': true, // 인원
    'share': true, // 비중(%)
    'years': true, // 배출 연도 범위
    'gap': true, // 마지막 배출 이후
    'num': false, // 제N대/제N단 숫자
    'league': true, // 대표 연맹
    'mixed': true, // 연맹 혼재 표시
    'variants': true, // 표기 변형 수
    'peak': false, // 최다 배출 연도
  };

  bool _groupByLeague = true; // 연맹별로 묶어서 보기
  bool _onlyVariants = false; // 표기 변형이 있는 단위대만
  bool _sortByCount = true; // true=인원순, false=이름순

  // ── 연맹 선택 (체크박스) ────────────────────────────────────────
  final Set<String> _selLeagues = {};

  // ── 단위대 비교 선택 ────────────────────────────────────────────
  final Set<String> _cmpKeys = {};

  // ── [turn61] 병합 진행 상태 ──────────────────────────────────────
  /// 서버에 병합을 쓰는 동안 버튼을 잠근다(중복 클릭 방지).
  bool _busy = false;

  /// 화면 어디서나 쓰는 API — NasApi 를 매번 새로 감싼다(상태가 없다).
  UnitStatsApi get _api => UnitStatsApi(context.read<NasApi>());

  /// 짧은 안내 — 스낵바.
  void _snack(String m) {
    final sc = ScaffoldMessenger.maybeOf(context);
    if (sc == null) return;
    sc.showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(fontSize: 12)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool keepNames = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = UnitStatsApi(context.read<NasApi>());
      final r = await api.load(basis: _basis);
      if (!mounted) return;
      setState(() {
        _data = r;
        _loading = false;
        if (!keepNames) _dataNamed = null;
        //  선택해 둔 연맹이 사라졌으면 정리한다.
        final valid = r.leagues.map((e) => e.league).toSet();
        _selLeagues.removeWhere((e) => !valid.contains(e));
        final keys = r.units.map((e) => e.key).toSet();
        _cmpKeys.removeWhere((e) => !keys.contains(e));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 이름이 포함된 상세를 가져온다 — 사용자가 명시적으로 요청할 때만.
  Future<UnitStatsResult> _loadNamed() async {
    if (_dataNamed != null) return _dataNamed!;
    final api = UnitStatsApi(context.read<NasApi>());
    final r = await api.load(basis: _basis, includeNames: true);
    if (mounted) setState(() => _dataNamed = r);
    return r;
  }

  // ══════════════════════════════════════════════════════════════════
  //  필터링
  // ══════════════════════════════════════════════════════════════════

  /// 모든 연맹이 선택된 상태(= '전체'와 같음).
  bool get _allLeaguesSelected {
    final d = _data;
    if (d == null) return false;
    return d.leagues.isNotEmpty && _selLeagues.length >= d.leagues.length;
  }

  /// '인원 상위 5개' 칩이 지금 그 상태인지.
  bool _top5Selected(UnitStatsResult d) {
    final top = d.leagues.take(5).map((e) => e.league).toSet();
    if (top.isEmpty || _selLeagues.length != top.length) return false;
    return _selLeagues.containsAll(top);
  }

  List<UnitRow> get _visibleUnits {
    final d = _data;
    if (d == null) return const [];
    var list = d.units;
    //  연맹을 하나도 안 골랐거나 **전부** 골랐으면 거르지 않는다.
    //  (전부 골랐을 때 거르면 연맹이 비어 있는 단위대가 사라져 '전체'와 달라진다)
    if (_selLeagues.isNotEmpty && !_allLeaguesSelected) {
      list = list.where((u) => _selLeagues.contains(u.league)).toList();
    }
    if (_cmpKeys.isNotEmpty) {
      list = list.where((u) => _cmpKeys.contains(u.key)).toList();
    }
    if (_onlyVariants) {
      list = list.where((u) => u.hasVariants).toList();
    }
    if (!_sortByCount) {
      final c = [...list];
      c.sort((a, b) => a.name.compareTo(b.name));
      return c;
    }
    return list;
  }

  int get _visibleTotal => _visibleUnits.fold(0, (s, u) => s + u.count);

  /// 최다 배출 연도 — people 의 year 를 세어 최빈값.
  int? _peakYear(UnitRow u) {
    final m = <int, int>{};
    for (final p in u.people) {
      if (p.year > 0) m[p.year] = (m[p.year] ?? 0) + 1;
    }
    if (m.isEmpty) return null;
    final e = m.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return e.key;
  }

  // ══════════════════════════════════════════════════════════════════
  //  UI
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: TsakAppBar(
        title: const Text('연맹별 · 단위대별 상세내역'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
          const AppHomeEmblem(size: 26),
        ],
      ),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                    children: [
                      _basisCard(d!),
                      const SizedBox(height: 10),
                      _optionCard(d),
                      const SizedBox(height: 10),
                      _leagueCard(d),
                      const SizedBox(height: 10),
                      _summaryCard(d),
                      const SizedBox(height: 10),
                      if (_cmpKeys.isNotEmpty) _compareCard(d),
                      const SizedBox(height: 6),
                      ..._tableSections(d),
                      if (d.groups.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _variantCard(d),
                      ],
                      const SizedBox(height: 16),
                      _footNote(d),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => _load(), child: const Text('다시 시도')),
            ],
          ),
        ),
      );

  // ── ① 기준 ──────────────────────────────────────────────────────
  Widget _basisCard(UnitStatsResult d) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 18, color: AppColors.purple),
                const SizedBox(width: 6),
                const Text(
                  '집계 기준',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'issue',
                  label: Text('인가시 정보'),
                  icon: Icon(Icons.assignment_ind_outlined, size: 16),
                ),
                ButtonSegment(
                  value: 'active',
                  label: Text('현재 활동정보'),
                  icon: Icon(Icons.place_outlined, size: 16),
                ),
              ],
              selected: {_basis},
              onSelectionChanged: (s) {
                final v = s.first;
                if (v == _basis) return;
                setState(() {
                  _basis = v;
                  _cmpKeys.clear();
                  _dataNamed = null;
                });
                _load();
              },
            ),
            const SizedBox(height: 10),
            Text(
              d.isActiveBasis
                  ? '현재 소속(regLeague/regUnit) 기준입니다. '
                      '명부에 현재활동 정보가 입력된 인원만 집계됩니다.'
                  : '인가 당시 소속(league/unit) 기준입니다. '
                      '명부 전체 ${_fmt(d.members)}명 중 '
                      '${_fmt(d.withUnit)}명에게 소속이 기록되어 있습니다.',
              style: const TextStyle(fontSize: 11.5, height: 1.55, color: Colors.black54),
            ),
            //  현재활동 데이터가 거의 없을 때 — 정직하게 알린다.
            if (d.isActiveBasis && d.withUnit < d.members * 0.1) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE8C98A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 15, color: Color(0xFFB7791F)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '현재활동 정보가 ${_fmt(d.withUnit)}건만 입력되어 있습니다. '
                        '명부 편집에서 소속을 채우면 이 통계가 채워집니다.',
                        style: const TextStyle(
                            fontSize: 11, height: 1.5, color: Color(0xFF8A6116)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── ② 출력 옵션 (체크박스) ──────────────────────────────────────
  Widget _optionCard(UnitStatsResult d) {
    const labels = {
      'count': '인원',
      'share': '비중(%)',
      'years': '배출 연도',
      'gap': '마지막 배출 후',
      'num': '번호(제N대)',
      'league': '대표 연맹',
      'mixed': '연맹 혼재',
      'variants': '표기 변형',
      'peak': '최다 배출연도',
    };
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: const Icon(Icons.checklist, size: 18, color: AppColors.purple),
        title: const Text(
          '출력 항목 · 옵션',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
        ),
        subtitle: Text(
          '필요한 항목만 켜세요 — 항목이 많으면 표가 길어집니다.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 0,
            children: labels.entries.map((e) {
              return SizedBox(
                width: 148,
                child: CheckboxListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _col[e.key] ?? false,
                  title: Text(e.value, style: const TextStyle(fontSize: 12)),
                  onChanged: (v) =>
                      setState(() => _col[e.key] = v ?? false),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 18),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            controlAffinity: ListTileControlAffinity.leading,
            value: _groupByLeague,
            title: const Text('연맹별로 묶어서 보기',
                style: TextStyle(fontSize: 12)),
            onChanged: (v) => setState(() => _groupByLeague = v ?? true),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            controlAffinity: ListTileControlAffinity.leading,
            value: _onlyVariants,
            title: Text('표기 변형이 있는 단위대만 (${d.groups.length}곳)',
                style: const TextStyle(fontSize: 12)),
            onChanged: (v) => setState(() => _onlyVariants = v ?? false),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            controlAffinity: ListTileControlAffinity.leading,
            value: _sortByCount,
            title: const Text('인원 많은 순 (해제하면 이름순)',
                style: TextStyle(fontSize: 12)),
            onChanged: (v) => setState(() => _sortByCount = v ?? true),
          ),
          if (_cmpKeys.isNotEmpty || _selLeagues.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _cmpKeys.clear();
                  _selLeagues.clear();
                }),
                icon: const Icon(Icons.filter_alt_off, size: 16),
                label: const Text('선택 해제', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  // ── ③ 연맹 선택 ─────────────────────────────────────────────────
  Widget _leagueCard(UnitStatsResult d) {
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: const Icon(Icons.public, size: 18, color: AppColors.purple),
        title: const Text(
          '연맹 선택',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
        ),
        subtitle: Text(
          _selLeagues.isEmpty || _allLeaguesSelected
              ? '전체 ${d.leagues.length}개 연맹 · ${_fmt(d.units.length)}개 단위대'
              : '${_selLeagues.length}개 연맹 선택됨',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              children: [
                //  '전체' = 연맹 **전부 선택**. (예전엔 clear() 였는데 라벨과
                //  반대 동작이라 '눌러도 반응이 없다'로 보였다)
                ChoiceChip(
                  label: const Text('전체', style: TextStyle(fontSize: 11.5)),
                  selected: _selLeagues.isEmpty || _allLeaguesSelected,
                  onSelected: (_) => setState(() {
                    _selLeagues
                      ..clear()
                      ..addAll(d.leagues.map((e) => e.league));
                  }),
                ),
                //  인원 상위 5개 — 이미 그 5개만 골라져 있으면 다시 눌러 해제.
                ChoiceChip(
                  label:
                      const Text('인원 상위 5개', style: TextStyle(fontSize: 11.5)),
                  selected: _top5Selected(d),
                  onSelected: (_) => setState(() {
                    if (_top5Selected(d)) {
                      _selLeagues.clear();
                    } else {
                      _selLeagues
                        ..clear()
                        ..addAll(d.leagues.take(5).map((e) => e.league));
                    }
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...d.leagues.map((L) {
            final on = _allLeaguesSelected || _selLeagues.contains(L.league);
            return CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              controlAffinity: ListTileControlAffinity.leading,
              value: on,
              title: Row(
                children: [
                  Expanded(
                    child: Text(L.league, style: const TextStyle(fontSize: 12.5)),
                  ),
                  Text(
                    '${_fmt(L.total)}명',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${L.unitCount}곳',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selLeagues.add(L.league);
                } else {
                  _selLeagues.remove(L.league);
                }
              }),
            );
          }),
        ],
      ),
    );
  }

  // ── ④ 요약 ──────────────────────────────────────────────────────
  Widget _summaryCard(UnitStatsResult d) {
    final sel = _visibleUnits;
    return Card(
      color: AppColors.purple.withValues(alpha: 0.045),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, size: 18, color: AppColors.purple),
                const SizedBox(width: 6),
                const Text('지금 보이는 범위',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13.5)),
                const Spacer(),
                if (_selLeagues.isNotEmpty || _cmpKeys.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.purple,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('필터 적용',
                        style: TextStyle(fontSize: 9.5, color: Colors.white)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _kpi('단위대', '${_fmt(sel.length)}곳'),
                _kpi('인원', '${_fmt(_visibleTotal)}명'),
                _kpi('연맹', '${_selLeagues.isEmpty ? d.leagues.length : _selLeagues.length}개'),
              ],
            ),
            if (_cmpKeys.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '체크한 ${_cmpKeys.length}곳만 표시 중입니다(대조군 비교).',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpi(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.purple)),
            const SizedBox(height: 2),
            Text(label,
                style:
                    const TextStyle(fontSize: 10.5, color: Colors.black54)),
          ],
        ),
      );

  // ── ⑤ 대조군 비교 카드 ──────────────────────────────────────────
  Widget _compareCard(UnitStatsResult d) {
    final list = _visibleUnits;
    if (list.isEmpty) return const SizedBox.shrink();
    final maxCount =
        list.map((e) => e.count).reduce((a, b) => a > b ? a : b).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows,
                    size: 18, color: AppColors.purple),
                const SizedBox(width: 6),
                Text('대조군 비교 (${list.length}곳)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13.5)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '막대는 이 묶음 안에서의 상대 인원입니다. 60% 선을 넘으면 배출이 많은 편입니다.',
              style: TextStyle(fontSize: 10.5, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 10),
            ...list.take(12).map((u) {
              final ratio = maxCount == 0 ? 0.0 : u.count / maxCount;
              final hot = ratio >= 0.6;
              final stale = (u.gapYears ?? 0) >= 15;
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        u.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          backgroundColor: Colors.black.withValues(alpha: 0.06),
                          valueColor: AlwaysStoppedAnimation(
                            hot ? const Color(0xFF1E7A46) : AppColors.purple,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 34,
                      child: Text('${u.count}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                    if (stale)
                      const Padding(
                        padding: EdgeInsets.only(left: 3),
                        child: Icon(Icons.hourglass_bottom,
                            size: 13, color: Color(0xFFC0392B)),
                      ),
                  ],
                ),
              );
            }),
            if (list.length > 12)
              Text('외 ${list.length - 12}곳은 아래 표에서 보세요.',
                  style:
                      const TextStyle(fontSize: 10.5, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  // ── ⑥ 표 ────────────────────────────────────────────────────────
  List<Widget> _tableSections(UnitStatsResult d) {
    final list = _visibleUnits;
    if (list.isEmpty) {
      return [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: Text('조건에 맞는 단위대가 없습니다.',
                    style: TextStyle(fontSize: 12.5))),
          ),
        ),
      ];
    }
    if (!_groupByLeague) {
      return [
        _sectionHeader('전체 단위대 (${list.length}곳)', null),
        _unitTable(list),
      ];
    }
    // 연맹별로 묶기 — 이미 d.leagues 순서(인원순)를 유지한다.
    final out = <Widget>[];
    for (final L in d.leagues) {
      final rows = list.where((u) => u.league == L.league).toList();
      if (rows.isEmpty) continue;
      final tot = rows.fold(0, (s, u) => s + u.count);
      out.add(_sectionHeader(
        L.league,
        '${rows.length}곳 · ${_fmt(tot)}명',
      ));
      out.add(_unitTable(rows));
      out.add(const SizedBox(height: 6));
    }
    return out;
  }

  Widget _sectionHeader(String title, String? sub) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.purple,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
            Text(title,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800)),
            if (sub != null) ...[
              const SizedBox(width: 8),
              Text(sub,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ],
        ),
      );

  Widget _unitTable(List<UnitRow> rows) {
    //  어떤 열이든 켜져 있어야 표가 의미가 있다.
    final any = _col.values.any((v) => v);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppColors.purple.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                const SizedBox(width: 26),
                const SizedBox(
                  width: 3,
                ),
                const Expanded(
                  flex: 3,
                  child: Text('단위대 (누르면 상세)',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
                if (_col['count'] == true)
                  _hCell('인원', 34),
                if (_col['share'] == true) _hCell('비중', 38),
                if (_col['years'] == true) _hCell('연도', 62),
                if (_col['gap'] == true) _hCell('최근', 40),
                if (_col['num'] == true) _hCell('번호', 38),
                if (_col['peak'] == true) _hCell('최다', 38),
                if (_col['variants'] == true) _hCell('표기', 30),
              ],
            ),
          ),
          if (!any)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('출력 항목을 하나 이상 켜 주세요.',
                  style: TextStyle(fontSize: 12)),
            ),
          ...rows.map(_unitCell),
        ],
      ),
    );
  }

  Widget _hCell(String text, double w) => SizedBox(
        width: w,
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 9.5, fontWeight: FontWeight.w800)),
      );

  Widget _unitCell(UnitRow u) {
    final sel = _cmpKeys.contains(u.key);
    final share = _visibleTotal == 0
        ? 0.0
        : (u.count * 100 / _visibleTotal);
    final stale = (u.gapYears ?? 0) >= 15;
    return InkWell(
      onTap: () => _openUnitDetail(u),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
          color: sel ? AppColors.purple.withValues(alpha: 0.05) : null,
        ),
        child: Row(
          children: [
            //  비교 선택 체크박스 — 여기서 체크하면 위 '대조군 비교' 에 나타난다.
            SizedBox(
              width: 26,
              height: 24,
              child: Checkbox(
                value: sel,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _cmpKeys.add(u.key);
                  } else {
                    _cmpKeys.remove(u.key);
                  }
                }),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: sel ? AppColors.purple : null,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted,
                    ),
                  ),
                  if (_col['league'] == true || _col['mixed'] == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Wrap(
                        spacing: 4,
                        children: [
                          if (_col['league'] == true)
                            Text(u.league,
                                style: TextStyle(
                                    fontSize: 9.5,
                                    color: Colors.grey.shade600)),
                          if (_col['mixed'] == true && u.mixedLeague)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF0E0),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '연맹혼재 ${u.leagues.length}',
                                style: const TextStyle(
                                    fontSize: 8.5,
                                    color: Color(0xFFB7791F),
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_col['count'] == true)
              SizedBox(
                width: 34,
                child: Text('${u.count}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            if (_col['share'] == true)
              SizedBox(
                width: 38,
                child: Text('${share.toStringAsFixed(1)}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 9.5, color: Colors.grey.shade700)),
              ),
            if (_col['years'] == true)
              SizedBox(
                width: 62,
                child: Text(
                  u.firstYear == null
                      ? '—'
                      : '${u.firstYear}\n~${u.lastYear}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 8.5, height: 1.35, color: Colors.grey.shade700),
                ),
              ),
            if (_col['gap'] == true)
              SizedBox(
                width: 40,
                child: Text(
                  u.gapYears == null
                      ? '—'
                      : (u.gapYears == 0 ? '올해' : '${u.gapYears}년'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: stale ? FontWeight.w900 : FontWeight.w500,
                    color: stale ? const Color(0xFFC0392B) : Colors.grey.shade700,
                  ),
                ),
              ),
            if (_col['num'] == true)
              SizedBox(
                width: 38,
                child: Text(
                  u.unitNum == 0 ? '—' : '${u.unitNum}${u.kind}',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 9.5, color: Colors.grey.shade700),
                ),
              ),
            if (_col['peak'] == true)
              SizedBox(
                width: 38,
                child: Text(
                  '${_peakYear(u) ?? '—'}',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 9.5, color: Colors.grey.shade700),
                ),
              ),
            if (_col['variants'] == true)
              SizedBox(
                width: 30,
                child: u.hasVariants
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE4F2F1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text('${u.names.length}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 9,
                                color: Color(0xFF1F6F6B),
                                fontWeight: FontWeight.w800)),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  // ── ⑦ 표기 변형 병합 ────────────────────────────────────────────
  Widget _variantCard(UnitStatsResult d) {
    //  isRisky 는 kindMix 를 이미 포함한다 — 중복 합산하면 두 배로 보인다.
    final riskyN = d.groups.where((g) => g.isRisky).length;
    final kindN = d.groups.where((g) => g.isKindMix).length;
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: const Icon(Icons.merge_type, size: 18, color: Color(0xFF1F6F6B)),
        title: const Text(
          '표기 변형 (같은 단위대일 수 있음)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
        ),
        subtitle: Text(
          '${d.groups.length}곳 · 추가 후보 ${d.extra.length}곳'
          '${riskyN > 0 ? ' · 확인필요 $riskyN' : ''}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        children: [
          // ── 일괄 묶기 ─────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF7F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBEDFDB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('한 번에 묶기',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                  '표기만 살짝 다른 것들을 모두 합칩니다. 연맹이 다르거나 '
                  '소년대·연장대가 섞인 조합은 서버가 알아서 건너뜁니다.',
                  style: TextStyle(
                      fontSize: 10.5, height: 1.55, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                //  ⚠️ [turn61 정직 고지] '표기 변형 61곳'은 **이미 같은 키**로
                //  묶여 있어 alias 로 저장할 대상이 없다. 버튼을 눌러도
                //  아무 일도 일어나지 않으므로(no-op) 숨기고 설명만 남긴다.
                //  실제로 유효한 일괄 병합은 '추가 후보'(키가 갈라진 것)뿐이다.
                if (riskyN >= 0)
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEEDDA8)),
                    ),
                    child: Text(
                      '표기 변형 ${d.groups.length}곳은 이미 한 칸으로 계산되어 있습니다'
                      '(인원·연도가 합산됨). 따로 묶을 필요가 없습니다.',
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.55,
                          color: Colors.brown.shade700),
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _busy || d.extra.isEmpty
                          ? null
                          : () => _mergeAll('extra',
                              '추가 후보 ${d.extra.length}곳'),
                      icon: const Icon(Icons.auto_fix_high, size: 15),
                      label: Text(
                          '추가 후보 ${d.extra.length}곳 모두 묶기',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (riskyN > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 15, color: Color(0xFFD9822B)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      [
                        if (kindN > 0)
                          '소년대·연장대 혼합 $kindN곳 — 같은 번호여도 별개 조직입니다.',
                        if (riskyN - kindN > 0)
                          '번호·이름이 다른 조합 ${riskyN - kindN}곳 — 확인이 필요합니다.',
                        '이 조합들은 [한 번에 묶기]에서 자동으로 제외됩니다.',
                      ].join(' '),
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.5,
                          color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ...d.groups.take(40).map((g) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: g.isRisky ? const Color(0xFFFFF6EC) : const Color(0xFFFAF9FC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: g.isRisky
                        ? const Color(0xFFF0C89A)
                        : const Color(0xFFE7E3EE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(g.name,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                      if (g.isRisky)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFBEFDF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(g.gradeLabel,
                              style: const TextStyle(
                                  fontSize: 9, color: Color(0xFFB5651D))),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ...g.names.map((e) => Padding(
                        padding: const EdgeInsets.only(left: 4, top: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('· ${e.key}',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                            Text('${e.value}명',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.grey.shade700)),
                          ],
                        ),
                      )),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _mergeGroup(g),
                      icon: const Icon(Icons.call_merge, size: 14),
                      label: const Text('같은 단위대로 묶기',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (d.groups.length > 40)
            Text('외 ${d.groups.length - 40}곳은 상단 옵션의 [표기 변형만]으로 확인하세요.',
                style: const TextStyle(fontSize: 10.5, color: Colors.black54)),

          // ── [turn61] 같은 연맹 · 같은 번호/이름으로 추가 발견된 곳 ──
          if (d.extra.isNotEmpty) ...[
            const Divider(height: 22),
            Row(
              children: [
                const Icon(Icons.travel_explore,
                    size: 15, color: Color(0xFF3B2470)),
                const SizedBox(width: 5),
                Text('추가로 발견된 곳 (${d.extra.length})',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '글자가 달라 따로 잡혔지만, 같은 연맹 안에서 번호나 이름이 겹치는 '
              '단위대입니다. 같은 번호라면 같은 단위대일 가능성이 높습니다.',
              style: TextStyle(
                  fontSize: 10.5, height: 1.55, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            ...d.extra.take(30).map((g) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F4FC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDCD2EE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE6F8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(g.reasonLabel,
                              style: const TextStyle(
                                  fontSize: 9, color: Color(0xFF3B2470))),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(g.label,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Text('${g.count}명',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...g.names.take(8).map((e) => Padding(
                          padding: const EdgeInsets.only(left: 4, top: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('· ${e.key}',
                                    style: const TextStyle(fontSize: 11)),
                              ),
                              Text('${e.value}명',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.grey.shade700)),
                            ],
                          ),
                        )),
                    if (g.names.length > 8)
                      Text('외 ${g.names.length - 8}개 표기',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black45)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _mergeExtra(g),
                        icon: const Icon(Icons.call_merge, size: 14),
                        label: const Text('같은 단위대로 묶기',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (d.extra.length > 30)
              Text('외 ${d.extra.length - 30}곳은 [추가 후보 모두 묶기]로 처리하세요.',
                  style:
                      const TextStyle(fontSize: 10.5, color: Colors.black54)),
          ],
        ],
      ),
    );
  }

  /// [turn61] 일괄 병합 — 확인 대화상자를 거쳐 서버 mergeAll 호출.
  Future<void> _mergeAll(String scope, String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('한 번에 묶을까요?', style: TextStyle(fontSize: 15)),
        content: Text(
          '$what을 모두 같은 단위대로 묶습니다.\n\n'
          '· 연맹이 다른 조합은 건너뜁니다\n'
          '· 단위대 번호가 다른 조합도 건너뜁니다\n'
          '· 소년대·연장대가 섞인 조합도 건너뜁니다\n\n'
          '나중에 [선택 해제]로 되돌릴 수 있습니다.',
          style: const TextStyle(fontSize: 12.5, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('묶기')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await _api.mergeAll(scope: scope, basis: _basis);
      if (!mounted) return;
      setState(() {
        if (r.stats != null) {
          _data = r.stats;
          _dataNamed = null;
        }
        _busy = false;
      });
      _snack('${r.mergedGroups}곳 · ${r.mergedPeople}명을 묶었습니다'
          '${r.skipped > 0 ? ' (${r.skipped}곳은 위험해 건너뜀)' : ''}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('묶지 못했습니다: $e');
    }
  }

  /// [turn61] 추가 후보 1건 묶기.
  Future<void> _mergeExtra(ExtraGroup g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('같은 단위대로 묶을까요?', style: TextStyle(fontSize: 15)),
        content: Text(
          '${g.label}\n\n대표: ${g.intoName}\n'
          '합계 ${g.count}명으로 합쳐집니다.',
          style: const TextStyle(fontSize: 12.5, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('묶기')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _api.alias(
        action: 'merge',
        into: g.into,
        from: g.fromKeys,
        basis: _basis,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _load(keepNames: _dataNamed != null);
      _snack('묶었습니다 — ${g.label}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('묶지 못했습니다: $e');
    }
  }

  Future<void> _mergeGroup(VariantGroup g) async {
    final keys = g.names.map((e) => e.key).toList();
    if (keys.length < 2) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('같은 단위대로 묶을까요?', style: TextStyle(fontSize: 15)),
        content: Text(
          '${g.name} 의 ${keys.length}가지 표기를 하나로 합칩니다.\n\n'
          '${keys.map((e) => '· $e').join('\n')}',
          style: const TextStyle(fontSize: 12, height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('묶기')),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;   // async gap 뒤 context 사용 경고 방지
    final api = UnitStatsApi(context.read<NasApi>());
    try {
      await api.alias(
        action: 'merge',
        into: g.key,
        from: keys.where((e) => e != g.key).toList(),
        basis: _basis,
      );
      if (!mounted) return;
      setState(() => _dataNamed = null);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('표기를 하나로 묶었습니다.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  // ── ⑧ 단위대 상세 (이름 노출은 여기서 동의) ─────────────────────
  Future<void> _openUnitDetail(UnitRow row) async {
    bool showNames = false;
    bool loadingNames = false;
    String? err;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c2, setS) {
          Future<void> loadNames() async {
            setS(() {
              loadingNames = true;
              err = null;
            });
            try {
              final named = await _loadNamed();
              setS(() => loadingNames = false);
              //  같은 key 의 상세를 다시 찾아 보여준다.
              final fresh = named.units.where((e) => e.key == row.key);
              if (fresh.isEmpty) {
                setS(() => err = '상세를 찾지 못했습니다.');
              }
            } catch (e) {
              setS(() {
                loadingNames = false;
                err = '$e';
              });
            }
          }

          final src = showNames && _dataNamed != null
              ? _dataNamed!.units.where((e) => e.key == row.key)
              : const <UnitRow>[];
          final u = src.isNotEmpty ? src.first : row;

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            maxChildSize: 0.95,
            builder: (c3, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                Text(u.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  '${u.league} · 인원 ${u.count}명'
                  '${u.mixedLeague ? ' · 연맹혼재 ${u.leagues.length}개' : ''}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                // 요약 4칸
                Row(
                  children: [
                    _dKpi('배출 인원', '${u.count}명'),
                    _dKpi('첫 배출', u.firstYear?.toString() ?? '—'),
                    _dKpi('마지막', u.lastYear?.toString() ?? '—'),
                    _dKpi('경과', u.gapYears == null
                        ? '—'
                        : (u.gapYears == 0 ? '올해' : '${u.gapYears}년')),
                  ],
                ),
                if (u.years.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('연도별 배출',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  ..._yearBars(u),
                ],
                if (u.leagues.length > 1) ...[
                  const SizedBox(height: 14),
                  const Text('연맹별 분포',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  ...u.leagues.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          Expanded(
                              child: Text('· ${e.key}',
                                  style: const TextStyle(fontSize: 11.5))),
                          Text('${e.value}명',
                              style: const TextStyle(fontSize: 11)),
                        ]),
                      )),
                ],
                if (u.names.length > 1) ...[
                  const SizedBox(height: 14),
                  const Text('입력된 표기',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  ...u.names.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          Expanded(
                              child: Text('· ${e.key}',
                                  style: const TextStyle(fontSize: 11.5))),
                          Text('${e.value}명',
                              style: const TextStyle(fontSize: 11)),
                        ]),
                      )),
                ],
                const SizedBox(height: 16),
                // ── 이름 노출 동의 ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: showNames
                        ? const Color(0xFFE4F2F1)
                        : const Color(0xFFFFF6E5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: showNames
                          ? const Color(0xFF1F6F6B).withValues(alpha: 0.35)
                          : const Color(0xFFE8C98A),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            showNames ? Icons.visibility : Icons.visibility_off,
                            size: 16,
                            color: showNames
                                ? const Color(0xFF1F6F6B)
                                : const Color(0xFFB7791F),
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              '인가자 명부 (이름 포함)',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          Switch(
                            value: showNames,
                            onChanged: (v) async {
                              setS(() => showNames = v);
                              if (v) await loadNames();
                            },
                          ),
                        ],
                      ),
                      Text(
                        showNames
                            ? '이름이 포함되어 있습니다. 화면 캡처·공유에 주의하세요.'
                            : '이름은 기본적으로 가려집니다. 켜야만 서버에서 이름을 받아옵니다.',
                        style: const TextStyle(fontSize: 10.5, height: 1.5),
                      ),
                      if (loadingNames)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (err != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(err!,
                              style: const TextStyle(
                                  fontSize: 10.5, color: Colors.red)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 명부 표
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE7E3EE)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Container(
                        color: Colors.black.withValues(alpha: 0.03),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: const Row(children: [
                          SizedBox(width: 44, child: Text('인가번호', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800))),
                          Expanded(child: Text('이름', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800))),
                          SizedBox(width: 76, child: Text('인가일', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800))),
                        ]),
                      ),
                      ...u.people.map((p) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.05)),
                              ),
                            ),
                            child: Row(children: [
                              SizedBox(
                                width: 44,
                                child: Text(p.number,
                                    style: const TextStyle(fontSize: 10.5)),
                              ),
                              Expanded(
                                child: Text(
                                  showNames
                                      ? (p.name.isEmpty ? '(미기재)' : p.name)
                                      : '●●●',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: showNames
                                        ? null
                                        : Colors.grey.shade500,
                                    letterSpacing: showNames ? 0 : 2,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 76,
                                child: Text(
                                  p.date.isEmpty ? '—' : p.date,
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      color: Colors.grey.shade700),
                                ),
                              ),
                            ]),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            if (_cmpKeys.contains(u.key)) {
                              _cmpKeys.remove(u.key);
                            } else {
                              _cmpKeys.add(u.key);
                            }
                          });
                          Navigator.pop(c2);
                        },
                        icon: const Icon(Icons.compare_arrows, size: 16),
                        label: Text(
                          _cmpKeys.contains(u.key) ? '비교에서 빼기' : '비교에 추가',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _dKpi(String label, String v) => Expanded(
        child: Column(
          children: [
            Text(v,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.purple)),
            Text(label,
                style: const TextStyle(fontSize: 9.5, color: Colors.black54)),
          ],
        ),
      );

  List<Widget> _yearBars(UnitRow u) {
    final keys = u.years.keys.map(int.parse).toList()..sort();
    if (keys.isEmpty) return const [];
    final maxV = u.years.values.reduce((a, b) => a > b ? a : b);
    return keys.map((y) {
      final v = u.years['$y'] ?? 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          SizedBox(
              width: 34,
              child: Text('$y',
                  style: TextStyle(
                      fontSize: 9.5, color: Colors.grey.shade700))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: maxV == 0 ? 0 : v / maxV,
                minHeight: 6,
                backgroundColor: Colors.black.withValues(alpha: 0.05),
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.purple),
              ),
            ),
          ),
          SizedBox(
              width: 26,
              child: Text('$v',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 9.5, fontWeight: FontWeight.w700))),
        ]),
      );
    }).toList();
  }

  Widget _footNote(UnitStatsResult d) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('읽는 법',
              style:
                  TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
            '· 인원이 많은 단위대 = 배출이 많은 곳 → 대장께 감사장을 고려할 수 있습니다.\n'
            '· [최근] 이 15년 이상이면 배출이 끊긴 곳 → 지원책을 검토할 대상입니다.\n'
            '· [연맹혼재] 는 같은 단위대가 여러 연맹으로 기록된 경우입니다(정정 필요).\n'
            '· 표의 단위대 이름을 누르면 상세가 열리고, 거기서 이름을 켜야 명부가 보입니다.\n'
            '· 체크박스로 단위대를 고르면 위 [대조군 비교] 에 나란히 표시됩니다.',
            style: const TextStyle(fontSize: 10.5, height: 1.7),
          ),
          const SizedBox(height: 8),
          Text(
            '기준: ${d.isActiveBasis ? "현재 활동정보" : "인가시 정보"} · '
            '총 ${_fmt(d.members)}명 중 소속 있음 ${_fmt(d.withUnit)}명, '
            '없음 ${_fmt(d.noUnit)}명 · 병합 설정 ${d.aliasCount}건',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    final s = '$n';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
