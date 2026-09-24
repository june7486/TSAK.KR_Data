import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/member_card.dart';
import 'app_access_screen.dart';
import 'bulk_screen.dart';
import 'export_screen.dart';
import 'finance_screen.dart';
import 'import_screen.dart';
import 'member_detail_screen.dart';
import 'member_edit_screen.dart';
import 'settings_screen.dart';
import 'source_folder_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _selectMode = false;
  final Set<String> _selected = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final members = state.members;

    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox(width: 4),
        titleSpacing: 0,
        title: _selectMode
            ? Text('${_selected.length}명 선택됨')
            : Row(
                children: [
                  // 엠블럼 — 누르면 초기 화면(필터 초기화 + 맨 위로)
                  AppHomeEmblem(
                    size: 30,
                    onHome: () {
                      _searchCtrl.clear();
                      state.clearFilters();
                      if (_scroll.hasClients) {
                        _scroll.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('초기 화면으로 이동했습니다'),
                          duration: Duration(milliseconds: 900),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  // 앱 접근 안내(주소+QR) — 제목 버튼
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AppAccessScreen(),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Text('TSAK 인가자 관리'),
                    ),
                  ),
                  const SizedBox(width: 2),
                  // 상단 QR 링크 픽토그램
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AppAccessScreen(),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.qr_code_2,
                          size: 20, color: Colors.white),
                    ),
                  ),
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
              tooltip: '단체 소식/문자',
              icon: const Icon(Icons.campaign),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BulkScreen()),
              ),
            ),
            IconButton(
              tooltip: '통계',
              icon: const Icon(Icons.insights),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StatsScreen()),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'settings':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                    break;
                  case 'import':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ImportScreen()),
                    );
                    break;
                  case 'finance':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const FinanceScreen()),
                    );
                    break;
                  case 'source':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SourceFolderScreen()),
                    );
                    break;
                  case 'select':
                    setState(() => _selectMode = true);
                    break;
                  case 'refresh':
                    context.read<AppState>().refreshFromNas();
                    break;
                  case 'lock':
                    context.read<AppState>().lock();
                    break;
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'finance', child: Text('재무 관리 (후원·수품·참가비)')),
                PopupMenuItem(value: 'source', child: Text('기본자료 폴더 (첨부·자동분석)')),
                PopupMenuItem(value: 'import', child: Text('자료 가져오기 (AI 인식)')),
                PopupMenuItem(value: 'settings', child: Text('설정 · 백업/복원')),
                PopupMenuItem(value: 'refresh', child: Text('NAS 최신 데이터 불러오기')),
                PopupMenuItem(value: 'select', child: Text('명단 선택 (일괄작업)')),
                PopupMenuItem(value: 'lock', child: Text('잠금')),
              ],
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
                    controller: _scroll,
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
          _bottomBar(context, state),
        ],
      ),
      floatingActionButton: _selectMode
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.purple,
              onPressed: _selected.isEmpty
                  ? null
                  : () => _openExport(state, members),
              icon: const Icon(Icons.ios_share),
              label: Text('내보내기 (${_selected.length})'),
            )
          : FloatingActionButton.small(
              backgroundColor: AppColors.taegeukRed,
              tooltip: '인가자 추가',
              onPressed: () => _addNew(state),
              child: const Icon(Icons.person_add_alt_1, size: 20),
            ),
    );
  }

  /// 하단: 명단 크기 조절 + 초소형 버전(최종 수정 일시)
  Widget _bottomBar(BuildContext context, AppState state) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  IconButton(
                    tooltip: '작게',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 34, minHeight: 34),
                    icon: const Icon(Icons.remove_circle_outline,
                        size: 19, color: AppColors.purple),
                    onPressed: () =>
                        state.setListScale(state.listScale - 0.05),
                  ),
                  const Text(
                    '명단 크기',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        activeTrackColor: AppColors.purple,
                        inactiveTrackColor:
                            AppColors.purple.withValues(alpha: 0.15),
                        thumbColor: AppColors.purple,
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 13),
                      ),
                      child: Slider(
                        value: state.listScale,
                        min: AppState.listScaleMin,
                        max: AppState.listScaleMax,
                        divisions:
                            ((AppState.listScaleMax - AppState.listScaleMin) /
                                    0.05)
                                .round(),
                        onChanged: (v) => state.setListScale(v),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '크게',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 34, minHeight: 34),
                    icon: const Icon(Icons.add_circle_outline,
                        size: 19, color: AppColors.purple),
                    onPressed: () =>
                        state.setListScale(state.listScale + 0.05),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 38),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(state.listScale * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            // 초소형 버전(최종 업데이트 일시) — 서버 동기화 상태
            Padding(
              padding: const EdgeInsets.only(bottom: 3, right: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _syncDot(state),
                  const SizedBox(width: 4),
                  Text(
                    '${state.versionText} · ${state.total}명',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: AppColors.textGray.withValues(alpha: 0.85),
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

  Widget _syncDot(AppState state) {
    Color c = AppColors.textGray;
    switch (state.syncStatus) {
      case 'saving':
        c = AppColors.tigerGold;
        break;
      case 'saved':
        c = AppColors.scoutGreen;
        break;
      case 'error':
        c = AppColors.taegeukRed;
        break;
    }
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
          const SizedBox(height: 8),
          Row(
            children: [
              _statChip('전체', '${state.total}명', Icons.groups),
              const SizedBox(width: 6),
              _statChip('검색결과', '${state.members.length}명', Icons.search),
              const SizedBox(width: 6),
              _statChip('평생회원', '${state.lifetimeCount}명', Icons.star),
            ],
          ),
          const SizedBox(height: 6),
          // 연회비 연도별 납부 인원 (작게)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Icon(Icons.card_membership,
                    size: 13, color: Colors.white70),
                const SizedBox(width: 4),
                const Text(
                  '평생회원수',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
                const SizedBox(width: 6),
                for (final e in state.feeCounts.take(4))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${e.key} ${e.value}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 재무 바로가기 — 후원현황 / 수품구매 / 참가비 / 지출 / 결산
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _finButton('후원현황', Icons.volunteer_activism, AppColors.taegeukRed, 1),
                _finButton('수품구매', Icons.shopping_bag, AppColors.taegeukBlue, 2),
                _finButton('참가비', Icons.event_available, AppColors.tigerGold, 3),
                _finButton('지출현황', Icons.payments, Color(0xFF00838F), 4),
                _finButton('결산', Icons.calculate, AppColors.scoutGreen, 5),
                _finButton('기본자료', Icons.folder_open, AppColors.purple, -1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _finButton(String label, IconData icon, Color color, int tab) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          if (tab < 0) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SourceFolderScreen()),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FinanceScreen(initialTab: tab)),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 4),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white70, fontSize: 9.5),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
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
