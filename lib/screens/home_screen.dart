import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/member_card.dart';
import 'member_detail_screen.dart';
import 'member_edit_screen.dart';
import 'export_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  bool _selectMode = false;
  final Set<String> _selected = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final members = state.members;

    return Scaffold(
      appBar: AppBar(
        title: _selectMode
            ? Text('${_selected.length}명 선택됨')
            : Row(
                children: [
                  Image.asset(
                    'assets/images/tsak_emblem.png',
                    width: 30,
                    height: 30,
                  ),
                  const SizedBox(width: 8),
                  const Text('TSAK 인가자 관리'),
                ],
              ),
        actions: [
          if (_selectMode) ...[
            IconButton(
              tooltip: '전체 선택',
              icon: const Icon(Icons.select_all),
              onPressed: () {
                setState(() {
                  if (_selected.length == members.length) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(members.map((e) => e.id));
                  }
                });
              },
            ),
            IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectMode = false;
                _selected.clear();
              }),
            ),
          ] else ...[
            IconButton(
              tooltip: '통계',
              icon: const Icon(Icons.insights),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StatsScreen()),
              ),
            ),
            IconButton(
              tooltip: '명단 선택 (일괄작업)',
              icon: const Icon(Icons.checklist),
              onPressed: () => setState(() => _selectMode = true),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _header(state),
          _filterBar(state),
          const SizedBox(height: 4),
          Expanded(
            child: members.isEmpty
                ? _empty()
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: members.length,
                    itemBuilder: (context, i) {
                      final m = members[i];
                      return MemberCard(
                        member: m,
                        scale: state.listScale,
                        selectMode: _selectMode,
                        selected: _selected.contains(m.id),
                        onTap: () {
                          if (_selectMode) {
                            _toggle(m.id);
                          } else {
                            _openDetail(m);
                          }
                        },
                        onLongPress: () {
                          if (!_selectMode) {
                            setState(() {
                              _selectMode = true;
                              _selected.add(m.id);
                            });
                          }
                        },
                        onCheckToggle: () => _toggle(m.id),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectMode
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.purple,
              onPressed: _selected.isEmpty
                  ? null
                  : () => _openExport(state, members),
              icon: const Icon(Icons.ios_share),
              label: Text('내보내기/발송 (${_selected.length})'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _addNew(state),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('인가자 추가'),
            ),
      bottomNavigationBar: _fontSizeBar(state),
    );
  }

  /// 하단 명단 크기 조절 바
  Widget _fontSizeBar(AppState state) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              tooltip: '작게',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.remove_circle_outline,
                size: 20,
                color: AppColors.purple,
              ),
              onPressed: () => state.setListScale(state.listScale - 0.05),
            ),
            const Text(
              '명단 크기',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: AppColors.purple,
                  inactiveTrackColor: AppColors.purple.withValues(alpha: 0.15),
                  thumbColor: AppColors.purple,
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  value: state.listScale,
                  min: AppState.listScaleMin,
                  max: AppState.listScaleMax,
                  divisions:
                      ((AppState.listScaleMax - AppState.listScaleMin) / 0.05)
                          .round(),
                  onChanged: (v) => state.setListScale(v),
                ),
              ),
            ),
            IconButton(
              tooltip: '크게',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.add_circle_outline,
                size: 20,
                color: AppColors.purple,
              ),
              onPressed: () => state.setListScale(state.listScale + 0.05),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40),
              child: Text(
                '${(state.listScale * 100).round()}%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Widget _header(AppState state) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => state.setQuery(v),
            decoration: InputDecoration(
              hintText: '이름 / 인가번호 / 전화번호 / 주소 / 소속대 통합검색',
              prefixIcon: const Icon(Icons.search, color: AppColors.purple),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        state.setQuery('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statChip('전체', '${state.total}명', Icons.groups),
              const SizedBox(width: 8),
              _statChip('검색결과', '${state.members.length}명', Icons.search),
              const SizedBox(width: 8),
              _statChip('평생회원', '${state.lifetimeCount}명', Icons.star),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 5),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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

  Widget _filterBar(AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip(
                  label: '평생회원',
                  selected: state.onlyLifetime,
                  color: AppColors.tigerGold,
                  onTap: () => state.setOnlyLifetime(!state.onlyLifetime),
                ),
                const SizedBox(width: 6),
                for (final y in state.feeYears.take(4))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _filterChip(
                      label: '$y 회비',
                      selected: state.yearFilter == y,
                      color: AppColors.scoutGreen,
                      onTap: () =>
                          state.setYear(state.yearFilter == y ? '' : y),
                    ),
                  ),
                if (state.query.isNotEmpty ||
                    state.leagueFilter.isNotEmpty ||
                    state.yearFilter.isNotEmpty ||
                    state.onlyLifetime)
                  ActionChip(
                    avatar: const Icon(Icons.refresh, size: 16),
                    label: const Text('초기화'),
                    onPressed: () {
                      _searchCtrl.clear();
                      state.clearFilters();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip(
                  label: '전체 연맹',
                  selected: state.leagueFilter.isEmpty,
                  color: AppColors.purple,
                  onTap: () => state.setLeague(''),
                ),
                const SizedBox(width: 6),
                for (final entry in state.leagues.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _filterChip(
                      label: '${entry.key} ${entry.value}',
                      selected: state.leagueFilter == entry.key,
                      color: leagueColor(entry.key),
                      onTap: () => state.setLeague(
                        state.leagueFilter == entry.key ? '' : entry.key,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: AppColors.textGray.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          const Text(
            '검색 결과가 없습니다',
            style: TextStyle(color: AppColors.textGray, fontSize: 15),
          ),
        ],
      ),
    );
  }

  void _openDetail(Member m) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberDetailScreen(memberId: m.id)),
    );
    if (mounted) context.read<AppState>().refresh();
  }

  void _addNew(AppState state) async {
    final next = await state.nextNumber();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberEditScreen(suggestedNumber: '$next'),
      ),
    );
    if (mounted) context.read<AppState>().refresh();
  }

  void _openExport(AppState state, List<Member> all) {
    final selected = all.where((m) => _selected.contains(m.id)).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          members: selected,
          title: '선택한 인가자 명단 (${selected.length}명)',
        ),
      ),
    );
  }
}
