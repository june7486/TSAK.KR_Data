import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/member_card.dart';
import 'app_access_screen.dart';
import 'admin_screen.dart';
import 'bulk_screen.dart';
import 'export_screen.dart';
import 'event_gallery_screen.dart';
import 'finance_screen.dart';
import 'import_screen.dart';
import 'member_detail_screen.dart';
import 'member_edit_screen.dart';
import 'qr_screen.dart';
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
                      child: const Icon(
                        Icons.qr_code_2,
                        size: 20,
                        color: Colors.white,
                      ),
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
            // 개인 접근: 본인 정보만 → 단체/통계/재무 메뉴 숨김
            if (!state.isPersonal) ...[
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
            ],
            if (state.isPersonal)
              IconButton(
                tooltip: '내 QR',
                icon: const Icon(Icons.qr_code_2),
                onPressed: () {
                  final me = state.who.isNotEmpty
                      ? state.byNumber(state.who)
                      : (members.isNotEmpty ? members.first : null);
                  if (me != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => QrScreen(member: me)),
                    );
                  }
                },
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
                  case 'admin':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminScreen()),
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
                        builder: (_) => const SourceFolderScreen(),
                      ),
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
              itemBuilder: (ctx) => [
                if (state.isMaster)
                  const PopupMenuItem(
                    value: 'admin',
                    child: Text('앱 관리 — 앱접근 비번 변경/정지/복구'),
                  ),
                if (!state.isPersonal) ...[
                  const PopupMenuItem(
                    value: 'finance',
                    child: Text('재무 관리 (후원·수품·참가비)'),
                  ),
                  const PopupMenuItem(
                    value: 'source',
                    child: Text('기본자료 폴더 (첨부·자동분석)'),
                  ),
                  const PopupMenuItem(
                    value: 'import',
                    child: Text('자료 가져오기 (AI 인식)'),
                  ),
                ],
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('설정 · 백업/복원'),
                ),
                if (!state.isPersonal) ...[
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Text('NAS 최신 데이터 불러오기'),
                  ),
                  const PopupMenuItem(
                    value: 'select',
                    child: Text('명단 선택 (일괄작업)'),
                  ),
                ],
                const PopupMenuItem(value: 'lock', child: Text('잠금')),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _header(state),
          if (!state.isPersonal) _filterBar(state),
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
                        onLongPress: state.isPersonal
                            ? null
                            : () {
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
          if (state.isPersonal) _personalActionBar(state),
          _bottomBar(context, state),
        ],
      ),
      floatingActionButton: state.isPersonal
          ? null
          : (_selectMode
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
                  )),
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
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      size: 19,
                      color: AppColors.purple,
                    ),
                    onPressed: () => state.setListScale(state.listScale - 0.05),
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
                        inactiveTrackColor: AppColors.purple.withValues(
                          alpha: 0.15,
                        ),
                        thumbColor: AppColors.purple,
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 13,
                        ),
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
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    icon: const Icon(
                      Icons.add_circle_outline,
                      size: 19,
                      color: AppColors.purple,
                    ),
                    onPressed: () => state.setListScale(state.listScale + 0.05),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
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
    // 개인 접근: 본인 정보만 표시하는 간소 헤더
    if (state.isPersonal) return _personalHeader(state);
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
              hintText: '통합검색 · AI 자연어 · 범위(1-100) · 전화번호',
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
          const SizedBox(height: 6),
          // AI 자연어 검색 예시 칩 — 누르면 바로 검색 실행
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 13, color: Colors.white70),
                const SizedBox(width: 4),
                const Text(
                  'AI 검색',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
                const SizedBox(width: 6),
                for (final ex in const [
                  '2026년 연회비 납부자 명단',
                  '현재까지 후원자 명단',
                  '평생회원 명단',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        _searchCtrl.text = ex;
                        state.setQuery(ex);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          ex,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
                const Icon(
                  Icons.card_membership,
                  size: 13,
                  color: Colors.white70,
                ),
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
                _finButton(
                  '후원현황',
                  Icons.volunteer_activism,
                  AppColors.taegeukRed,
                  1,
                ),
                _finButton(
                  '수품구매',
                  Icons.shopping_bag,
                  AppColors.taegeukBlue,
                  2,
                ),
                _finButton(
                  '참가비',
                  Icons.event_available,
                  AppColors.tigerGold,
                  3,
                ),
                _finButton('지출현황', Icons.payments, Color(0xFF00838F), 4),
                _finButton('결산', Icons.calculate, AppColors.scoutGreen, 5),
                _eventButton(),
                _finButton('기본자료', Icons.folder_open, AppColors.purple, -1),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _donationBanner(state),
        ],
      ),
    );
  }

  /// 홈 첫 페이지 후원 안내 — 3개 계좌를 작은 글씨로 한눈에(스크롤 없음) + 복사 버튼
  Widget _donationBanner(AppState state) {
    final donations = state.donations;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.tigerGold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.volunteer_activism,
                color: AppColors.purple,
                size: 14,
              ),
              const SizedBox(width: 4),
              const Text(
                '후원 계좌',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              Text(
                state.donationHolder,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // 3개 계좌를 세로로 동시에 표시 (스크롤 없음)
          for (final d in donations)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${d['label']}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.lifetimeGold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${d['bank']} ${d['account']}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: '${d['account']}'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${d['label']} ${d['account']} 복사됨'),
                          duration: const Duration(milliseconds: 900),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.purple.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.copy, size: 11, color: AppColors.purple),
                          SizedBox(width: 3),
                          Text(
                            '복사',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.purple,
                            ),
                          ),
                        ],
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

  /// 개인 접근 전용 헤더 — 본인 요약만 노출 (타인 정보 접근 불가)
  Widget _personalHeader(AppState state) {
    final me = state.who.isNotEmpty
        ? state.byNumber(state.who)
        : (state.members.isNotEmpty ? state.members.first : null);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              const Text(
                '개인 접근',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // V 표시 영역 — 누르면 본인 정보 편집(수정/저장) 시트 열림
              if (me != null)
                GestureDetector(
                  onTap: () => _openPersonalEditSheet(state, me),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.scoutGreen, width: 2),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified,
                          color: AppColors.scoutGreen,
                          size: 18,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '본인 정보 편집',
                          style: TextStyle(
                            color: AppColors.scoutGreen,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (me != null) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.tigerGold, width: 2),
                  ),
                  child: Text(
                    '#${me.number}',
                    style: const TextStyle(
                      color: AppColors.purple,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  me.name.isEmpty ? '(이름없음)' : me.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (me.lifetimeMember) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.star, color: AppColors.tigerGold, size: 18),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [me.league, me.unit].where((e) => e.isNotEmpty).join(' · '),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ] else
            const Text(
              '본인 정보를 찾을 수 없습니다',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          const SizedBox(height: 4),
          const Text(
            '※ 개인 접근에서는 다른 인가자의 정보를 볼 수 없습니다.',
            style: TextStyle(color: Colors.white70, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  /// 행사관리(사진·동영상 갤러리) 진입 버튼
  Widget _eventButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EventGalleryScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: const [
              Icon(Icons.photo_library, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Text(
                '행사관리',
                style: TextStyle(
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
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9.5,
                    ),
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
                  color: AppColors.lifetimeGold,
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
    final state = context.read<AppState>();
    // 개인 접근: 본인 외 인가자 클릭 시 경고 후 차단 (개인정보 보호)
    if (state.isPersonal && !state.isSelfNumber(m.number)) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.lock_outline,
            color: AppColors.taegeukRed,
            size: 32,
          ),
          title: const Text('열람 제한', textAlign: TextAlign.center),
          content: Text(
            '개인 로그인 시 다른 인가자의 정보를 볼 수 없습니다.\n\n'
            '#${m.number} ${m.name} 님의 정보는 본인만 열람할 수 있습니다.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, height: 1.4),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('돌아가기'),
            ),
          ],
        ),
      );
      return;
    }
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

  // ================= 개인 접근 — 본인 정보 편집 / 비밀번호 관리 =================

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 개인 접근: V 영역에서 여는 "본인 정보 편집" 시트
  void _openPersonalEditSheet(AppState state, Member me) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PersonalEditSheet(
        me: me,
        onEditInfo: () async {
          Navigator.pop(ctx);
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MemberEditScreen(memberId: me.id),
            ),
          );
          if (mounted) context.read<AppState>().refresh();
        },
        onPassword: () {
          Navigator.pop(ctx);
          _openPasswordMenuItem(state, me);
        },
        onLost: () {
          Navigator.pop(ctx);
          _showLostPasswordDialog();
        },
      ),
    );
  }

  /// 비밀번호 변경 경고 후 진행
  Future<void> _openPasswordMenuItem(AppState state, Member me) async {
    final warn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.tigerGold,
          size: 34,
        ),
        title: const Text('개인 비밀번호 변경', textAlign: TextAlign.center),
        content: const Text(
          '개인 비밀번호를 변경하시겠습니까?\n\n'
          '· 비밀번호는 「본인 인가번호!@@」 형식이 기본값입니다.\n'
          '· 변경하면 다음 접속부터 새 비밀번호를 사용해야 합니다.\n'
          '· 분실 시 관리자(마스터)에게 재설정을 요청하세요.',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('나중에'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              _showLostPasswordDialog();
            },
            child: const Text('분실 안내'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('변경하기'),
          ),
        ],
      ),
    );
    if (warn != true) return;
    if (!mounted) return;
    _showPasswordChangeDialog(state, me);
  }

  void _showLostPasswordDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.help_outline, color: AppColors.purple, size: 32),
        title: const Text('비밀번호를 분실하셨나요?', textAlign: TextAlign.center),
        content: const Text(
          '비밀번호를 분실한 경우 관리자에게 문의하세요.\n\n'
          '· 관리자(마스터)가 인가번호 기준으로\n'
          '  비밀번호를 초기화하거나 재설정할 수 있습니다.\n'
          '· 초기화 시 기본값은 「본인 인가번호!@@」 입니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showPasswordChangeDialog(AppState state, Member me) {
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final newCtrl2 = TextEditingController();
    bool busy = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('개인 비밀번호 변경'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '인가번호 #${me.number} (${me.name})',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: curCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '현재 비밀번호',
                    hintText: '예: 0000!@@',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '새 비밀번호'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newCtrl2,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '새 비밀번호 확인'),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '※ 비밀번호를 분실한 경우 관리자에게 문의하세요.',
                    style: TextStyle(fontSize: 11, color: AppColors.textGray),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final cur = curCtrl.text.trim();
                      final nw = newCtrl.text.trim();
                      final nw2 = newCtrl2.text.trim();
                      if (cur.isEmpty || nw.isEmpty) {
                        _snack('모든 항목을 입력하세요');
                        return;
                      }
                      if (nw.length < 4) {
                        _snack('새 비밀번호는 4자 이상이어야 합니다');
                        return;
                      }
                      if (nw != nw2) {
                        _snack('새 비밀번호가 서로 다릅니다');
                        return;
                      }
                      setLocal(() => busy = true);
                      final err = await state.changePersonalPassword(cur, nw);
                      if (!ctx.mounted) return;
                      setLocal(() => busy = false);
                      if (err == null) {
                        Navigator.pop(ctx);
                        _snack('개인 비밀번호가 변경되었습니다');
                      } else {
                        _snack('변경 실패: $err');
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('변경'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 개인 접근 — V 영역 "본인 정보 편집" 바텀시트
class _PersonalEditSheet extends StatelessWidget {
  const _PersonalEditSheet({
    required this.me,
    required this.onEditInfo,
    required this.onPassword,
    required this.onLost,
  });

  final Member me;
  final VoidCallback onEditInfo;
  final VoidCallback onPassword;
  final VoidCallback onLost;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textGray.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.verified,
                  color: AppColors.scoutGreen,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  '본인 정보 — #${me.number} ${me.name}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '개인 접근에서는 본인 정보만 수정할 수 있습니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
            const SizedBox(height: 16),
            _tile(
              icon: Icons.edit_note,
              color: AppColors.purple,
              title: '개인정보 편집 (수정·저장)',
              subtitle: '소속·연락처·주소·사진 등 본인 정보 수정',
              onTap: onEditInfo,
            ),
            const SizedBox(height: 8),
            _tile(
              icon: Icons.password,
              color: AppColors.taegeukBlue,
              title: '개인 비밀번호 변경',
              subtitle: '접속 비밀번호 변경 (경고 안내 후 진행)',
              onTap: onPassword,
            ),
            const SizedBox(height: 8),
            _tile(
              icon: Icons.help_outline,
              color: AppColors.tigerGold,
              title: '비밀번호 분실 안내',
              subtitle: '분실 시 관리자에게 문의하세요',
              onTap: onLost,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textGray),
          ],
        ),
      ),
    );
  }
}
