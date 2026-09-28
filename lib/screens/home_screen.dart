import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_config.dart';
import '../services/app_state.dart';
import '../services/nas_api.dart';
import '../services/build_info.g.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/donation_accounts.dart';
import '../widgets/member_card.dart';
import '../widgets/hscroll_menu.dart';
import '../widgets/donate_sheet.dart';
import '../widgets/inquiry_sheet.dart';
import 'app_access_screen.dart';
import 'admin_screen.dart';
import 'merch_admin_screen.dart';
import 'merch_shop_screen.dart';
import 'merch_stats_screen.dart';
import 'bulk_screen.dart';
import 'export_screen.dart';
import 'event_year_screen.dart';
import 'event_detail_screen.dart';
import 'finance_screen.dart';
import 'import_screen.dart';
import 'member_detail_screen.dart';
import 'member_edit_screen.dart';
import 'qr_screen.dart';
import 'regular_members_screen.dart';
import 'approval_screen.dart';
import 'settings_screen.dart';
import 'source_folder_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.openMemberNo = '',
    this.openEventYear = '',
    this.openEventTitle = '',
  });

  /// 로그인 직후 자동으로 열 개인정보 편집 인가번호 (QR 딥링크)
  final String openMemberNo;

  /// 로그인 직후 자동으로 열 행사 QR 딥링크 (연도/행사명)
  final String openEventYear;
  final String openEventTitle;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _deepLinkHandled = false;

  // 수요조사 진행중 목록(개인 페이지 수품구매 하단 대기자 명단/순번 표기용).
  List<Map<String, dynamic>> _surveys = [];
  String _myNo = '';

  @override
  void initState() {
    super.initState();
    if (widget.openMemberNo.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDeepLinkMember());
    } else if (widget.openEventTitle.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDeepLinkEvent());
    }
    // 로그인 직후 미승인 일반회원이 있으면 관리자·마스터에게 알림 팝업.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingApprovals());
    // 수요조사 진행중 목록 로드(개인 페이지 대기자 명단용).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSurveys());
  }

  Future<void> _loadSurveys() async {
    try {
      final r = await context.read<NasApi>().merch();
      if (!mounted) return;
      final who = context.read<AppState>().who;
      setState(() {
        _surveys = ((r['surveys'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _myNo = who;
      });
    } catch (_) {
      // 무시 — 목록 없으면 미표시
    }
  }

  bool _pendingChecked = false;

  /// 미승인 일반회원 알림 — 관리자·마스터 로그인 시 1회.
  /// "다음에 할께요" 옵션으로 놓치지 않고 언제든 처리할 수 있게 한다.
  Future<void> _checkPendingApprovals() async {
    if (_pendingChecked) return;
    _pendingChecked = true;
    final state = context.read<AppState>();
    if (!(state.isApp || state.isMaster)) return;
    // 서버 승인 대기 목록 갱신
    await state.fetchApprovalPending();
    if (!mounted) return;
    final n = state.pendingApprovalCount;
    if (n <= 0) return;
    await _showPendingApprovalDialog(state, n);
  }

  Future<void> _showPendingApprovalDialog(AppState state, int n) async {
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.how_to_reg,
            color: AppColors.tigerGold, size: 40),
        title: const Text('미승인 회원 안내',
            style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '승인 대기 중인 일반회원이 $n명 있습니다.',
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '미승인 회원들에 대한 안내 : 관리자에게 승인 요청을 해주십시요.\n'
              '지금 바로 승인/보류를 처리할 수 있습니다.',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.textGray, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('다음에 할께요'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.taegeukBlue),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('지금 승인하기'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ApprovalScreen()),
      );
      if (mounted) setState(() {});
    }
  }

  /// 행사 QR 딥링크 — 로그인 후 해당 행사 상세 화면을 바로 연다.
  Future<void> _openDeepLinkEvent() async {
    if (_deepLinkHandled) return;
    _deepLinkHandled = true;
    final state = context.read<AppState>();
    final year = widget.openEventYear.trim();
    final title = widget.openEventTitle.trim();
    if (title.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          year: year,
          title: title,
          canManage: state.isApp || state.isMaster,
        ),
      ),
    );
    if (mounted) context.read<AppState>().refresh();
  }

  /// QR 딥링크 — 로그인 후 해당 인가자 정보 편집 페이지를 바로 연다.
  Future<void> _openDeepLinkMember() async {
    if (_deepLinkHandled) return;
    _deepLinkHandled = true;
    final no = widget.openMemberNo.replaceAll(RegExp(r'[^0-9]'), '');
    if (no.isEmpty) return;
    final state = context.read<AppState>();
    final m = state.byNumber(no);
    if (m == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberEditScreen(memberId: m.id)),
    );
    if (mounted) context.read<AppState>().refresh();
  }

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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '한국 범스카우트중앙회',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '통합 앱 · v${AppConfig.appVersion} · $kBuildShort',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
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
            // 개인/비인가자(본인) 접근: 본인 정보만 → 단체문자/통계/재무 메뉴 숨김
            if (!state.isSelfAccess) ...[
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
            if (state.isSelfAccess)
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
                  case 'donate':
                    showDonateSheet(context);
                    break;
                  case 'inquiry':
                    showInquirySheet(context);
                    break;
                  case 'lock':
                    context.read<AppState>().lock();
                    break;
                  case 'home':
                    _searchCtrl.clear();
                    context.read<AppState>().clearFilters();
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
                    break;
                }
              },
              itemBuilder: (ctx) => [
                if (state.isMaster)
                  const PopupMenuItem(
                    value: 'admin',
                    child: _MenuItem(
                      icon: Icons.admin_panel_settings,
                      label: '앱 관리 — 앱접근 비번 변경/정지/복구',
                      color: AppColors.taegeukRed,
                    ),
                  ),
                if (!state.isSelfAccess) ...[
                  const PopupMenuItem(
                    value: 'finance',
                    child: _MenuItem(
                      icon: Icons.account_balance_wallet,
                      label: '재무 관리 (후원·수품·참가비)',
                      color: AppColors.taegeukBlue,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'source',
                    child: _MenuItem(
                      icon: Icons.folder_special,
                      label: '기본자료 폴더 (첨부·자동분석)',
                      color: AppColors.taegeukBlue,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'import',
                    child: _MenuItem(
                      icon: Icons.auto_awesome,
                      label: '자료 가져오기 (AI 인식)',
                      color: AppColors.taegeukBlue,
                    ),
                  ),
                ],
                const PopupMenuItem(
                  value: 'settings',
                  child: _MenuItem(
                    icon: Icons.settings,
                    label: '설정 · 백업/복원',
                    color: AppColors.purple,
                  ),
                ),
                if (!state.isSelfAccess) ...[
                  const PopupMenuItem(
                    value: 'refresh',
                    child: _MenuItem(
                      icon: Icons.cloud_download,
                      label: 'NAS 최신 데이터 불러오기',
                      color: AppColors.taegeukBlue,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'select',
                    child: _MenuItem(
                      icon: Icons.checklist,
                      label: '명단 선택 (일괄작업)',
                      color: AppColors.taegeukBlue,
                    ),
                  ),
                ],
                // 첫 화면으로 이동 (모든 접근 등급)
                const PopupMenuItem(
                  value: 'home',
                  child: _MenuItem(
                    icon: Icons.home_outlined,
                    label: '첫 화면으로 이동',
                    color: AppColors.textDark,
                  ),
                ),
                // 개발자 후원 (모든 접근 등급)
                const PopupMenuItem(
                  value: 'donate',
                  child: _MenuItem(
                    icon: Icons.favorite,
                    label: '개발자 후원',
                    color: AppColors.tigerGold,
                  ),
                ),
                // 문의 (모든 접근 등급)
                const PopupMenuItem(
                  value: 'inquiry',
                  child: _MenuItem(
                    icon: Icons.mail_outline,
                    label: '문의하기',
                    color: AppColors.textDark,
                  ),
                ),
                const PopupMenuItem(
                  value: 'lock',
                  child: _MenuItem(
                    icon: Icons.lock_outline,
                    label: '로그아웃',
                    color: AppColors.taegeukRed,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (!state.isSelfAccess) _header(state),
          // 개인/비인가자(본인 1인) 접근에서는 검색·필터를 숨겨 다른 회원 열람 차단
          if (!state.isSelfAccess) _filterBar(state),
          const SizedBox(height: 4),
          Expanded(
            child: state.isSelfAccess
                // 개인 페이지: 헤더(개인정보·바로가기)를 함께 스크롤에 포함해
                // 화면이 잘리지 않고 아래로 스크롤되도록 한다.
                ? CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _personalHeader(state)),
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      if (members.isEmpty)
                        const SliverToBoxAdapter(child: SizedBox(height: 8))
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final m = members[i];
                              return MemberCard(
                                member: m,
                                scale: state.listScale,
                                selectMode: _selectMode,
                                selected: _selected.contains(m.id),
                                canSeeRealName: true,
                                onTap: () => _openDetail(m),
                                onLongPress: null,
                                onCheckToggle: () => _toggle(m.id),
                                onEdit: () => _openEdit(m),
                              );
                            },
                            childCount: members.length,
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    ],
                  )
                : (state.membersLoading && !state.membersLoaded)
                    ? _loadingList(loaded: members.length)
                    : members.isEmpty
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
                                canSeeRealName: state.isApp ||
                                    state.isMaster ||
                                    state.who.replaceAll(
                                            RegExp(r'[^0-9]'), '') ==
                                        m.number
                                            .replaceAll(RegExp(r'[^0-9]'), ''),
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
                                onEdit: () => _openEdit(m),
                              );
                            },
                          ),
          ),
          if (state.isSelfAccess) _personalActionBar(state),
          _bottomBar(context, state),
        ],
      ),
      floatingActionButton: state.isSelfAccess
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

  /// 개인 접근 전용 — 명단 아래 "개인정보 수정" 액션 바
  Widget _personalActionBar(AppState state) {
    final me = state.who.isNotEmpty
        ? state.byNumber(state.who)
        : (state.members.isNotEmpty ? state.members.first : null);
    return Material(
      color: Colors.white,
      elevation: 6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: me == null
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MemberEditScreen(memberId: me.id),
                              ),
                            );
                            if (mounted) context.read<AppState>().refresh();
                          },
                    icon: const Icon(Icons.edit_note, size: 19),
                    label: const Text(
                      '개인정보 수정',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.taegeukBlue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                  ),
                  onPressed: me == null
                      ? null
                      : () => _openPasswordMenuItem(state, me),
                  icon: const Icon(Icons.password, size: 18),
                  label: const Text('비밀번호 변경',
                      style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          // 개인 접근 하단 바로가기 — 홈페이지 / 네이버 카페 (새창)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: _homeShortcutButton(
                    icon: Icons.public,
                    label: 'Homepage',
                    url: 'https://www.tigerscout.kr',
                    color: AppColors.taegeukBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _homeShortcutButton(
                    icon: Icons.forum_outlined,
                    label: 'Naver Cafe',
                    url: 'https://cafe.naver.com/tigerscoutkr',
                    color: AppColors.scoutGreen,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 홈 화면 하단 바로가기 버튼 (새창으로 외부 링크)
  Widget _homeShortcutButton({
    required IconData icon,
    required String label,
    required String url,
    required Color color,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        backgroundColor: color.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      onPressed: () => openUrlInNewTab(url),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
    // 개인/비인가자(본인) 접근: 본인 정보만 표시하는 간소 헤더
    if (state.isSelfAccess) return _personalHeader(state);
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
              hintText: '통합검색 (인가번호, 이름, 전화번호, 범위(1-100), 연맹, 지역대, 성별, 평생회원 등)',
              hintStyle: const TextStyle(
                  fontSize: 11.5, color: AppColors.textGray, height: 1.2),
              hintMaxLines: 2,
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
          HScrollMenu(
            height: 30,
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
          HScrollMenu(
            height: 18,
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
          // 바로가기 — 행사관리를 맨 앞에 배치(가장 자주 쓰는 진입점).
          // 이어서 재무 바로가기(관리자·마스터 전용: 후원현황/수품구매/참가비/지출/결산/기본자료)
          HScrollMenu(
            height: 48,
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                // (1) 행사관리 — 가장 자주 쓰는 진입점
                _eventButton(),
                if (state.isApp || state.isMaster) ...[
                  // (2) 승인관리 (관리자·마스터)
                  _approvalButton(),
                  // (3) 일반회원 (관리자·마스터)
                  _regularMembersButton(),
                ],
                // (4) 수품 구매 — 모든 사용자에게 노출
                _finButton(
                  '수품 구매',
                  Icons.shopping_cart_checkout,
                  const Color(0xFF6D4C41),
                  -4,
                ),
                if (state.isApp || state.isMaster) ...[
                  // (5) 수품판매관리
                  _finButton(
                    '수품판매관리',
                    Icons.shopping_bag,
                    AppColors.taegeukBlue,
                    -2,
                  ),
                  // (6) 수품통계
                  _finButton(
                    '수품통계',
                    Icons.insights,
                    const Color(0xFF6A1B9A),
                    -3,
                  ),
                  // (7) 참가비
                  _finButton(
                    '참가비',
                    Icons.event_available,
                    AppColors.tigerGold,
                    3,
                  ),
                  // (8) 지출현황
                  _finButton(
                    '지출현황',
                    Icons.payments,
                    const Color(0xFF00838F),
                    4,
                  ),
                  // (9) 결산
                  _finButton(
                    '결산',
                    Icons.calculate,
                    AppColors.scoutGreen,
                    5,
                  ),
                  // (10) 기본자료
                  _finButton(
                    '기본자료',
                    Icons.folder_open,
                    AppColors.purple,
                    -1,
                  ),
                ],
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
          const DonationAccounts(fontSize: 11),
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
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(
                        color: AppColors.scoutGreen, width: 2),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openPersonalEditSheet(state, me),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified,
                              color: AppColors.scoutGreen, size: 18),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        me.isRegular
                            ? '서포터즈'
                            : '범스카우트 #${me.number.isEmpty ? '-' : me.number}',
                        style: const TextStyle(
                          color: AppColors.purple,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        me.isRegular
                            ? '일반회원 (비인가)'
                            : 'ATAS #${me.atasNo.isEmpty ? '-' : me.atasNo}',
                        style: const TextStyle(
                          color: AppColors.taegeukBlue,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    me.name.isEmpty ? '(이름없음)' : me.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
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
          const SizedBox(height: 10),
          // 본인이 참석한 행사 폴더 접근 — 사진 업로드 / 참가비·후원금 납부 안내
          //  행사관리를 맨 처음에 배치(가장 자주 쓰는 진입점)
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EventYearScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.tigerGold, width: 2),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library, size: 18, color: AppColors.purple),
                  SizedBox(width: 6),
                  Text(
                    '내 행사 관리 (사진 업로드·참가비·후원)',
                    style: TextStyle(
                      color: AppColors.purple,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '※ 본인이 참석자로 등록된 행사만 보입니다.',
            style: TextStyle(color: Colors.white70, fontSize: 10),
          ),
          const SizedBox(height: 10),
          // 수품 구매 — 개인 페이지에서도 소품 구매창으로 진입(주문·결제 연동).
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MerchShopScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.tigerGold, width: 2),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_checkout,
                      size: 18, color: AppColors.purple),
                  SizedBox(width: 6),
                  Text(
                    '수품 구매 (소품 주문·결제)',
                    style: TextStyle(
                      color: AppColors.purple,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 수요조사 진행중인 수품이 있을 때만 개인 프로필 내부에 노출.
          //  (진행중 항목이 없으면 아무것도 표시하지 않아 첫 화면을 깔끔하게 유지)
          if (_surveys.isNotEmpty) ...[
            _personalSurveyWaitlist(),
            const SizedBox(height: 10),
          ],
          // 노출순서: 내 행사 관리 → 수품 구매 → (수요조사 진행중) → 후원 계좌.
          // 중앙회 계좌 3개 + 바로 송금 (참가비·후원 등)
          _personalDonationBanner(state),
        ],
      ),
    );
  }

  /// 개인 페이지 수품구매 하단 — 수요조사 대기자 명단/순번 + 최소주문 대비 신청자 수.
  /// 예) "11번째 신청자 / 50명(최소제작신청수량)"
  Widget _personalSurveyWaitlist() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_outlined, size: 17, color: AppColors.purple),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('수요조사 진행중 (내 신청 순번)',
                    style: TextStyle(
                        color: AppColors.purpleDark,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800)),
              ),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MerchShopScreen())),
                child: const Text('신청하기 ›',
                    style: TextStyle(
                        color: AppColors.taegeukRed,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final s in _surveys) _surveyWaitRow(s),
        ],
      ),
    );
  }

  Widget _surveyWaitRow(Map<String, dynamic> s) {
    final name = '${s['name'] ?? ''}';
    final minQty = (s['minQty'] as num?)?.toInt() ?? 0;
    final apps = (s['applicants'] as List?) ?? [];
    final count = (s['count'] as num?)?.toInt() ?? apps.length;
    // 내 신청 순번 찾기 (인가번호 우선, 없으면 세션 who).
    int mySeq = 0;
    final myNo = _myNo.replaceAll(RegExp(r'[^0-9]'), '');
    if (myNo.isNotEmpty) {
      for (final a in apps) {
        final n = '${(a as Map)['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
        if (n.isNotEmpty && n == myNo) {
          mySeq = ((a['no'] as num?)?.toInt()) ?? 0;
          break;
        }
      }
    }
    final ratio = minQty > 0 ? (count / minQty).clamp(0.0, 1.0) : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          const SizedBox(height: 5),
          Row(
            children: [
              if (mySeq > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.tigerGold.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$mySeq번째 신청자',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.purpleDark)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.textGray.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('아직 미신청',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray)),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '/ $count명 신청 (최소 제작 $minQty명)',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.purple),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.purpleLight.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(AppColors.purple),
            ),
          ),
        ],
      ),
    );
  }

  /// 개인 접근 전용 — 범스카우트 중앙회 계좌 3개 노출 (참가비·후원 납부 안내)
  Widget _personalDonationBanner(AppState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tigerGold, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance,
                  color: AppColors.purple, size: 15),
              const SizedBox(width: 5),
              const Text(
                '한국범스카우트중앙회 계좌',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
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
          const SizedBox(height: 6),
          const DonationAccounts(fontSize: 11.5),
          const SizedBox(height: 2),
          const Text(
            '※ 참가비·후원금은 위 계좌로 납부해 주세요.',
            style: TextStyle(fontSize: 9.5, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  /// 행사관리(연도별 행사 목록) 진입 버튼
  Widget _eventButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EventYearScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: const Row(
            children: [
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

  /// 일반회원(비인가자) 관리 진입 버튼 — 관리자·마스터 전용
  /// 일반회원 승인 관리 진입 버튼 — 관리자·마스터 전용, 미승인 건수 배지 표시
  Widget _approvalButton() {
    final state = context.watch<AppState>();
    final n = state.pendingApprovalCount;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ApprovalScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: n > 0 ? AppColors.tigerGold : Colors.white.withValues(alpha: 0.5),
              width: n > 0 ? 1.8 : 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.how_to_reg, size: 16, color: Colors.white),
              const SizedBox(width: 5),
              const Text('승인관리',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              if (n > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.tigerGold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$n',
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _regularMembersButton() {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RegularMembersScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                '일반회원 ${state.regularCount}',
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

  Widget _finButton(String label, IconData icon, Color color, int tab) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          if (tab == -2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MerchAdminScreen()),
            );
          } else if (tab == -3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MerchStatsScreen()),
            );
          } else if (tab == -4) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MerchShopScreen()),
            );
          } else if (tab < 0) {
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
          HScrollMenu(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip(
                  label: '전체 회원',
                  selected: state.kindFilter.isEmpty,
                  color: AppColors.purple,
                  onTap: () => state.setKind(''),
                ),
                const SizedBox(width: 6),
                _filterChip(
                  label: '인가자',
                  selected: state.kindFilter == 'credential',
                  color: AppColors.taegeukBlue,
                  onTap: () => state.setKind(
                    state.kindFilter == 'credential' ? '' : 'credential',
                  ),
                ),
                const SizedBox(width: 6),
                _filterChip(
                  label: '일반회원',
                  selected: state.kindFilter == 'regular',
                  color: AppColors.textGray,
                  onTap: () => state.setKind(
                    state.kindFilter == 'regular' ? '' : 'regular',
                  ),
                ),
                const SizedBox(width: 6),
                _filterChip(
                  label: '멘토',
                  selected: state.kindFilter == 'mentor',
                  color: AppColors.scoutGreen,
                  onTap: () => state.setKind(
                    state.kindFilter == 'mentor' ? '' : 'mentor',
                  ),
                ),
                const SizedBox(width: 6),
                _filterChip(
                  label: '보호자',
                  selected: state.kindFilter == 'parent',
                  color: AppColors.lifetimeGold,
                  onTap: () => state.setKind(
                    state.kindFilter == 'parent' ? '' : 'parent',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          HScrollMenu(
            height: 34,
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
                    state.onlyLifetime ||
                    state.kindFilter.isNotEmpty)
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
          HScrollMenu(
            height: 34,
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
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

  /// 초기 로딩 — 명단을 서버에서 불러오는 동안 표시(빈 화면 방지).
  Widget _loadingList({int loaded = 0}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.purple,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '자료를 불러오는 중입니다…',
            style: TextStyle(
              color: AppColors.purpleDark,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '인가자 명단${loaded > 0 ? ' $loaded' : ''} '
            '데이터를 준비하고 있어요. 잠시만 기다려 주세요.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textGray, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  void _openDetail(Member m) async {
    final state = context.read<AppState>();
    // 개인/비인가자 접근: 본인 외 인가자 클릭 시 경고 후 차단 (개인정보 보호)
    if (state.isSelfAccess && !state.isSelfNumber(m.number)) {
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

  /// 이름 좌측 편집창 → 실명/개인정보 편집 화면
  void _openEdit(Member m) async {
    final state = context.read<AppState>();
    // 개인/비인가자 접근에서도 본인은 편집 가능(저장소가 본인으로 제한됨)
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberEditScreen(memberId: m.id)),
    );
    if (mounted) state.refresh();
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
    final adminEmail = context.read<AppState>().adminEmail;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.help_outline, color: AppColors.purple, size: 32),
        title: const Text('비밀번호를 분실하셨나요?', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '비밀번호를 분실한 경우 관리자에게 문의하세요.\n\n'
              '· 관리자(마스터)가 인가번호 기준으로\n'
              '  비밀번호를 초기화하거나 재설정할 수 있습니다.\n'
              '· 초기화 시 기본값은 「본인 인가번호!@@」 입니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.mail_outline,
                    size: 16,
                    color: AppColors.purple,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '관리자: ',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    adminEmail,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.purple,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: adminEmail));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('관리자 이메일이 복사되었습니다'),
                    duration: Duration(milliseconds: 900),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('이메일 복사'),
            ),
          ],
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
                    hintText: '예: 000!@@',
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

/// 팝업 메뉴 항목 — 관리자 전용/일반 항목을 색·아이콘으로 구분.
class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }
}
