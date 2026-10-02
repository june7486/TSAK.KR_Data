import 'dart:async';

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
import '../widgets/scroll_down_hint.dart';
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
import 'board_screen.dart';
import 'event_detail_screen.dart';
import 'finance_screen.dart';
import 'import_screen.dart';
import 'member_detail_screen.dart';
import 'member_edit_screen.dart';
import 'qr_screen.dart';
import 'regular_members_screen.dart';
import 'roster_admin_screen.dart';import 'member_request_screen.dart';
import 'settings_screen.dart';
import 'master_console_screen.dart';
import 'source_folder_screen.dart';
import 'stats_screen.dart';
import 'eunha_roster_screen.dart';
import 'atas_roster_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.openMemberNo = '',
    this.openEventYear = '',
    this.openEventTitle = '',
    this.openBoardId = '',
  });

  /// 로그인 직후 자동으로 열 개인정보 편집 인가번호 (QR 딥링크)
  final String openMemberNo;

  /// 로그인 직후 자동으로 열 행사 QR 딥링크 (연도/행사명)
  final String openEventYear;
  final String openEventTitle;

  /// 게시판 글 딥링크 — 로그인 후 해당 게시글 화면을 바로 연다.
  final String openBoardId;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();

  /// 개인 로그인(본인) 창 스크롤 컨트롤러 — 하단 스크롤 유도 화살표용.
  final _personalScroll = ScrollController();
  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _deepLinkHandled = false;

  /// 범스카우트/개인 접근에서 HOME 버튼을 눌러 메인 홈을 볼 때 true.
  /// (권한이 허용하는 범위까지만 노출된다.)
  bool _showMainHome = false;
  // 게시판/주문 등 관리자 이상 알림 배지
  int _boardUnread = 0;
  // 승인관리 대기 배지(비인가회원·행사·연회비·평생 등 통합)
  int _approvalUnread = 0;

  /// 승인 대기 **총 건수** — 요구: "승인대기중인 사람들이 있을 경우 원형단추 숫자".
  /// 이미 승인화면을 열어 확인했더라도, 대기자가 남아 있으면 숫자를 유지한다.
  int _approvalTotal = 0;

  /// 승인요청 실시간 감시 타이머 — 승인 요청이 오면 원형 숫자 배지를
  /// 자동 갱신한다(관리자·마스터). (요구: "승인 요청이 오면 원형단추 숫자로 표시")
  Timer? _approvalTimer;
  int _prevApprovalUnread = 0;

  @override
  void initState() {
    super.initState();
    if (widget.openMemberNo.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openDeepLinkMember(),
      );
    } else if (widget.openEventTitle.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDeepLinkEvent());
    } else if (widget.openBoardId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDeepLinkBoard());
    }
    // 로그인 직후 미승인 일반회원이 있으면 관리자·마스터에게 알림 팝업.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkPendingApprovals(),
    );
    // 게시판 새 글 알림 배지 로드(관리자 이상).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoardUnread());
    // 승인관리 대기 배지 로드(관리자 이상) + 실시간 감시 시작.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startApprovalWatch());
    // 은하스카우트 명단을 미리 로드 — 통합검색(범+은하)에 노출하기 위함(관리자·마스터).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().ensureEunhaForSearch();
    });
  }

  /// 승인요청을 주기적으로 감시해 배지(원형 숫자)를 자동 갱신한다.
  ///  · 8초마다 서버의 미확인 승인요청 건수를 폴링한다.
  ///  · 건수가 늘면 새 요청이 들어온 것이므로 스낵바로 안내한다.
  void _startApprovalWatch() {
    _loadApprovalBadge();
    _approvalTimer?.cancel();
    _approvalTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadApprovalBadge(poll: true),
    );
  }

  /// 승인관리 대기 총 건수 배지 로드(관리자·마스터).
  /// 배지 숫자 = **대기 총건수**(미확인 건수가 있으면 그 값 우선).
  ///  · 요구: "승인대기중인 사람들이 있을 경우 원형단추 숫자" → 대기자가 있으면 유지.
  ///  · 새 요청 도착 감지는 미확인(unread) 증가로 판단해 스낵바로 안내한다.
  Future<void> _loadApprovalBadge({bool poll = false}) async {
    final state = context.read<AppState>();
    if (!(state.isApp || state.isMaster)) return;
    try {
      final n = await state.fetchApprovalUnread();
      final total = await state.fetchApprovalPendingTotal();
      if (!mounted) return;
      // 새 승인요청 도착 → 조용히 안내(팝업 대신 스낵바).
      if (poll && n > _prevApprovalUnread && _prevApprovalUnread >= 0) {
        final diff = n - _prevApprovalUnread;
        if (diff > 0) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('새 승인요청 $diff건이 도착했습니다.'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
      setState(() {
        _approvalUnread = n;
        _approvalTotal = total;
        _prevApprovalUnread = n;
      });
    } catch (_) {}
  }

  /// 배지에 표시할 숫자 — 대기 총건수(미확인 우선).
  int get _approvalBadgeCount =>
      _approvalUnread > 0 ? _approvalUnread : _approvalTotal;

  /// 관리자 이상 알림(게시판 새 글 등) 미확인 건수 로드.
  Future<void> _loadBoardUnread() async {
    final state = context.read<AppState>();
    if (!(state.isApp || state.isMaster)) return;
    try {
      final r = await context.read<NasApi>().notifyList();
      if (!mounted) return;
      setState(() => _boardUnread = (r['unread'] as num?)?.toInt() ?? 0);
    } catch (_) {}
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
        icon: const Icon(
          Icons.how_to_reg,
          color: AppColors.tigerGold,
          size: 40,
        ),
        title: const Text(
          '미승인 회원 안내',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '승인 대기 중인 일반회원이 $n명 있습니다.',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '미승인 회원들에 대한 안내 : 관리자에게 승인 요청을 해주십시요.\n'
              '지금 바로 승인/보류를 처리할 수 있습니다.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textGray,
                height: 1.4,
              ),
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
              backgroundColor: AppColors.taegeukBlue,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('지금 승인하기'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await _openApproval();
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

  /// 게시판 글 딥링크 — 로그인 후 해당 게시글 화면을 바로 연다.
  Future<void> _openDeepLinkBoard() async {
    if (_deepLinkHandled) return;
    _deepLinkHandled = true;
    final id = widget.openBoardId.trim();
    if (id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BoardScreen(openId: id)),
    );
    if (mounted) context.read<AppState>().refresh();
  }

  @override
  void dispose() {
    _approvalTimer?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    _personalScroll.dispose();
    super.dispose();
  }

  /// 상단바 액션 아이콘 — (요구) 2행(아랫줄)에 우측 정렬로 배치.
  List<Widget> _buildAppBarActions(AppState state) {
    final members = state.members;
    return [
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
              // 권한이 허용하는 메뉴만 아이콘으로 노출한다.
              if (state.can('bulk'))
                IconButton(
                  tooltip: '단체 소식/문자',
                  icon: const Icon(Icons.campaign),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BulkScreen()),
                  ),
                ),
              if (state.can('stats'))
                IconButton(
                  tooltip: '통계',
                  icon: const Icon(Icons.insights),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StatsScreen()),
                  ),
                ),
              // 은하스카우트 명단 — 별도 관리 · 관리자 이상
              if (state.isApp || state.isMaster)
                IconButton(
                  tooltip: '은하스카우트 명단',
                  icon: const Icon(Icons.list_alt),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EunhaRosterScreen()),
                  ),
                ),
              // 명단 선택 (일괄작업) — 관리자 이상
              if (state.can('bulk'))
                IconButton(
                  tooltip: '명단 선택 (일괄작업)',
                  icon: const Icon(Icons.checklist),
                  onPressed: () => setState(() => _selectMode = true),
                ),
              // 게시판 — 새 글 알림 배지 표시
              if (state.can('board'))
                IconButton(
                  tooltip: '게시판',
                  icon: Badge(
                    isLabelVisible: _boardUnread > 0,
                    label: Text('$_boardUnread'),
                    child: const Icon(Icons.forum_outlined),
                  ),
                  onPressed: () async {
                    final st = context.read<AppState>();
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BoardScreen()),
                    );
                    // 게시판을 확인했으므로 해당 아이디 기준 읽음 처리 → 배지 차감.
                    await st.markBadgeSeen(kind: 'board');
                    _loadBoardUnread();
                  },
                ),
              // 통합승인관리 — 대기 항목 배지(붉은 원형 숫자, 관리자·마스터 전용)
              if (state.isApp || state.isMaster) _approvalAppbarIcon(),
              if (personaForPersonal(state) && !_showMainHome)
                IconButton(
                  tooltip: '메인 홈으로',
                  icon: const Icon(Icons.home_filled),
                  onPressed: () {
                    state.setPersonalBrowse(true);
                    setState(() => _showMainHome = true);
                  },
                ),
              if (state.isSelfAccess && !_showMainHome)
                IconButton(
                  tooltip: '본인 정보 편집',
                  // 흰색 연필 — 보라 앱바 배경에 자연스럽게 어울리도록 복원.
                  icon: const Icon(Icons.edit, color: Colors.white),
                  onPressed: () => _openMyEdit(state),
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
                    case 'master_console':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MasterConsoleScreen(),
                        ),
                      );
                      break;
                    case 'member_request':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MemberRequestScreen(),
                        ),
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
                    case 'myqr':
                      final me = state.who.isNotEmpty
                          ? state.byNumber(state.who)
                          : (members.isNotEmpty ? members.first : null);
                      if (me != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => QrScreen(member: me)),
                        );
                      }
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
                        role: '마스터',
                      ),
                    ),
                  if (state.isMaster)
                    const PopupMenuItem(
                      value: 'master_console',
                      child: _MenuItem(
                        icon: Icons.workspace_premium,
                        label: '마스터 관리창 — 백업/회원/권한/로그/재무',
                        color: AppColors.taegeukRed,
                        role: '마스터',
                      ),
                    ),
                  if (state.isApp || state.isMaster)
                    const PopupMenuItem(
                      value: 'member_request',
                      child: _MenuItem(
                        icon: Icons.app_registration,
                        label: '등록요청 승인 — 평생회원·연회비·자격',
                        color: AppColors.lifetimeGold,
                        role: '관리자',
                      ),
                    ),
                  if (!state.isSelfAccess) ...[
                    const PopupMenuItem(
                      value: 'finance',
                      child: _MenuItem(
                        icon: Icons.account_balance_wallet,
                        label: '재무 관리 (후원·수품·참가비)',
                        color: AppColors.taegeukBlue,
                        role: '관리자',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: _MenuItem(
                        icon: Icons.auto_awesome,
                        label: '자료 가져오기 (AI 인식)',
                        color: AppColors.taegeukBlue,
                        role: '관리자',
                      ),
                    ),
                  ],
                  // 기본자료 폴더 — 마스터 전용(요구: "기본자료 항목은 마스터만 볼 수 있음")
                  if (state.isMaster)
                    const PopupMenuItem(
                      value: 'source',
                      child: _MenuItem(
                        icon: Icons.folder_special,
                        label: '기본자료 폴더 (첨부·자동분석)',
                        color: AppColors.taegeukRed,
                        role: '마스터',
                      ),
                    ),
                  if (state.isMaster)
                    const PopupMenuItem(
                      value: 'settings',
                      child: _MenuItem(
                        icon: Icons.settings,
                        label: '설정 · 백업/복원',
                        color: AppColors.taegeukRed,
                        role: '마스터',
                      ),
                    ),
                  if (!state.isSelfAccess) ...[
                    const PopupMenuItem(
                      value: 'refresh',
                      child: _MenuItem(
                        icon: Icons.cloud_download,
                        label: 'NAS 최신 데이터 불러오기',
                        color: AppColors.taegeukBlue,
                        role: '관리자',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'select',
                      child: _MenuItem(
                        icon: Icons.checklist,
                        label: '명단 선택 (일괄작업)',
                        color: AppColors.taegeukBlue,
                        role: '관리자',
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
                  // 내 QR 표시 (본인 인가자) — QR 아이콘을 삼점(⋮) 위치로 옮기며
                  //  메뉴로도 접근 가능하게 한다(요구).
                  if (state.isSelfAccess)
                    const PopupMenuItem(
                      value: 'myqr',
                      child: _MenuItem(
                        icon: Icons.qr_code_2,
                        label: '내 QR 표시',
                        color: AppColors.taegeukBlue,
                      ),
                    ),
                  // 개발자 후원 (모든 접근 등급)
                  const PopupMenuItem(
                    value: 'donate',
                    child: _MenuItem(
                      icon: Icons.favorite,
                      label: '개발자 후원',
                      color: AppColors.lifetimeGold,
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final members = state.members;
    // 개인/비인가(본인) 화면을 첫 화면으로 보여준다. HOME 버튼을 누르면
    //  _showMainHome=true 가 되어 권한 허용 범위의 메인 홈이 나타난다.
    final selfView = state.isSelfAccess && !_showMainHome;
    final personalMain = state.isSelfAccess && _showMainHome;
    // 개인 첫 화면에서는 '본인' 1건만 노출(나머지는 HOME 후 권한 범위로).
    final selfMembers = selfView
        ? members.where((m) => state.isSelfNumber(m.number)).toList()
        : members;

    return Scaffold(
      appBar: AppBar(
        // 엠블럼+텍스트를 좌측 열에 배치하고, 아래 검색창(좌우 16px)과 좌측 라인을 맞춘다.
        //  leading 폭을 0으로 두고 title 좌측 여백 12 + 엠블럼 내부 패딩 4 = 16px 정렬.
        leadingWidth: 0,
        titleSpacing: 0,
        // (요구) 2행 앱바 — 상하 여백을 줄여 화면을 효율적으로 사용(목표 이미지).
        toolbarHeight: 76,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // (요구) 1행: 로고·브랜드(좌) · 버전/시각(가운데) · QR(우) — 여백 최소화.
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  AppHomeEmblem(
                    size: 26,
                    onHome: () {
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
                    },
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AppAccessScreen(),
                      ),
                    ),
                    child: Text(
                      state.isEunha
                          ? '한국은하스카우트중앙회'
                          : '한국 범스카우트중앙회',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '통합 앱 · v${AppConfig.appVersion} · $kBuildShort',
                      // (요구) 버전 표시를 우측 정렬하되, 우측 끝(QR/삼점)과 일정거리
                      //  유지 — 트레일링 여백으로 이격한다.
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  // (요구) 버전 텍스트 ↔ QR 사이 일정거리 유지.
                  const SizedBox(width: 10),
                  // (요구) QR 아이콘은 상단(1행)에 그대로 두되, 오른쪽 끝에서
                  //  좌측으로 이격시킨다(2행 삼점 위치로 내리지 않음).
                  //  본인 인가자면 내 QR, 아니면 범스카우트 접근 QR 화면.
                  IconButton(
                    tooltip: 'QR',
                    icon: const Icon(Icons.qr_code_2),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final me = state.who.isNotEmpty
                          ? state.byNumber(state.who)
                          : null;
                      if (me != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => QrScreen(member: me)),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AppAccessScreen(),
                          ),
                        );
                      }
                    },
                  ),
                  // (요구) QR 을 화면 오른쪽 끝에서 좌측으로 이격 — 우측 끝과
                  //  충분히 띄워 '좌측으로 당긴' 배치가 되도록 한다.
                  const SizedBox(width: 28),
                ],
              ),
            ),
            const SizedBox(height: 2),
            // (요구) 2행: 액션 아이콘 — 여백을 줄여 우측 정렬.
            //   아이콘 버튼 자체를 조밀(compact)하게 만들어 한 줄에 더 많이 노출한다.
            IconButtonTheme(
              data: IconButtonThemeData(
                style: ButtonStyle(
                  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                  minimumSize: const WidgetStatePropertyAll(Size(38, 36)),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: _buildAppBarActions(state),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!selfView) _header(state, personalMain: personalMain),
          // 검색·필터는 명단검색 권한이 있을 때만 노출(개인정보 보호)
          if (!selfView && state.can('memberSearch')) _filterBar(state),
          const SizedBox(height: 2),
          Expanded(
            child: selfView
                // 개인 페이지: 헤더(개인정보·바로가기)를 함께 스크롤에 포함해
                // 화면이 잘리지 않고 아래로 스크롤되도록 한다.
                ? ScrollDownHint(
                    controller: _personalScroll,
                    bottomInset: 78,
                    child: CustomScrollView(
                      controller: _personalScroll,
                      slivers: [
                        SliverToBoxAdapter(child: _personalHeader(state)),
                        const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        if (selfMembers.isEmpty)
                          const SliverToBoxAdapter(child: SizedBox(height: 8))
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate((context, i) {
                              final m = selfMembers[i];
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
                            }, childCount: selfMembers.length),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                      ],
                    ),
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
                        canSeeRealName:
                            state.isApp ||
                            state.isMaster ||
                            state.can('memberSearch') ||
                            state.who.replaceAll(RegExp(r'[^0-9]'), '') ==
                                m.number.replaceAll(RegExp(r'[^0-9]'), ''),
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
          if (selfView) _personalActionBar(state),
          _bottomBar(context, state),
        ],
      ),
      floatingActionButton: (selfView || !state.can('memberAdd'))
          ? null
          : (_selectMode
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 마스터 전용 — 선택 계정 완전 삭제
                      if (state.isMaster)
                        FloatingActionButton.extended(
                          heroTag: 'delSel',
                          backgroundColor: AppColors.taegeukRed,
                          onPressed: _selected.isEmpty
                              ? null
                              : () => _deleteSelected(state, members),
                          icon: const Icon(Icons.delete_forever),
                          label: Text('삭제 (${_selected.length})'),
                        ),
                      if (state.isMaster) const SizedBox(width: 10),
                      FloatingActionButton.extended(
                        heroTag: 'expSel',
                        backgroundColor: AppColors.purple,
                        onPressed: _selected.isEmpty
                            ? null
                            : () => _openExport(state, members),
                        icon: const Icon(Icons.ios_share),
                        label: Text('내보내기 (${_selected.length})'),
                      ),
                    ],
                  )
                : FloatingActionButton.small(
                    backgroundColor: AppColors.taegeukRed,
                    tooltip: '인가자 추가',
                    onPressed: () => _addNew(state),
                    child: const Icon(Icons.person_add_alt_1, size: 20),
                  )),
    );
  }

  /// 개인 접근(personal/guest) 여부 — 메뉴 노출 판정용.
  bool personaForPersonal(AppState state) => state.isSelfAccess;

  /// 개인 접근 전용 — 명단 아래 "개인정보 수정" 액션 바
  Widget _personalActionBar(AppState state) {
    final me = _selfMember(state);
    return Material(
      color: Colors.white,
      elevation: 6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            // (p.29) "비밀번호 변경" 글자가 짤리는 문제 → 가로 배치 대신
            //  세로로 쌓아 좁은 화면에서도 라벨이 잘리지 않게 한다.
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
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
                                builder: (_) =>
                                    MemberEditScreen(memberId: me.id),
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
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.taegeukBlue,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    onPressed: me == null
                        ? null
                        : () => _openPasswordMenuItem(state, me),
                    icon: const Icon(Icons.password, size: 18),
                    label: const Text(
                      '비밀번호 변경',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
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

  /// (요구#1) 개인 로그인 하단 표시용 — 해당 아이디(본인) 계정 라벨.
  ///  본인 1건만 노출되므로 개인정보 보호 요건을 만족한다.
  String _selfAccountLabel(AppState state) {
    final me = state.who.isNotEmpty
        ? state.byNumber(state.who)
        : (state.members.isNotEmpty ? state.members.first : null);
    if (me == null) {
      return state.who.isEmpty ? '본인 계정' : '내 계정 · ${state.who}';
    }
    final no = me.number.isEmpty ? '-' : me.number;
    final name = me.name.isEmpty ? '(이름없음)' : me.name;
    return '내 계정 · $name ($no)';
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
            // (요구#1) 개인 로그인 시 하단에 '해당 아이디 계정만' 노출 + 초소형 버전
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 8, right: 8),
              child: Row(
                children: [
                  if (state.isSelfAccess) ...[
                    const Icon(
                      Icons.account_circle,
                      size: 12,
                      color: AppColors.purple,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        _selfAccountLabel(state),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.purple,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
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

  Widget _header(AppState state, {bool personalMain = false}) {
    // 개인/비인가자(본인) 접근: 본인 정보만 표시하는 간소 헤더
    if (state.isSelfAccess && !personalMain) return _personalHeader(state);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      // (요구) 상하 여백 최소화 — 화면을 효율적으로 사용.
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        children: [
          // 검색창은 명단검색 권한이 있을 때만 (개인정보 보호)
          if (state.can('memberSearch'))
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => state.setQuery(v),
              decoration: InputDecoration(
                hintText: '통합검색 (인가번호, 이름, 전화번호, 범위, 연맹, 지역대 등)',
                hintStyle: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textGray,
                  height: 1.2,
                ),
                hintMaxLines: 1,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
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
          const SizedBox(height: 3),
          // AI 자연어 검색 예시 칩 — 누르면 바로 검색 실행
          if (state.can('memberSearch'))
            HScrollMenu(
              height: 26,
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 13,
                    color: Colors.white70,
                  ),
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
          const SizedBox(height: 3),
          if (state.can('memberSearch'))
            Row(
              children: [
                _statChip('전체', '${state.totalSearchCount}명', Icons.groups),
                const SizedBox(width: 6),
                _statChip(
                  '범인가자수',
                  '${state.tsakCredentialCount}명',
                  Icons.verified_user,
                ),
                const SizedBox(width: 6),
                _statChip('검색결과', '${state.members.length}명', Icons.search),
              ],
            ),
          const SizedBox(height: 3),
          // 연회비 연도별 납부 인원 (작게)
          if (state.can('memberSearch'))
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
          const SizedBox(height: 3),
          // 바로가기 — 행사관리를 맨 앞에 배치(가장 자주 쓰는 진입점).
          // 이어서 재무 바로가기(관리자·마스터 전용: 후원현황/수품구매/참가비/지출/결산/기본자료)
          HScrollMenu(
            height: 42,
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                // (0) 행사+수품판매 게시판 — 행사관리 앞에 배치(요구 #12)
                if (state.can('board')) _boardButton(),
                // (1) 행사관리 — 가장 자주 쓰는 진입점
                if (state.can('events')) _eventButton(),
                if (state.isApp || state.isMaster) ...[
                  // 통합승인관리 — 승인(멘토·페런츠 연결 포함)이 모두 취합되므로
                  // 별도 '연결승인' 버튼은 두지 않는다(요구: 통합승인으로 취합).
                  _approvalButton(),
                  // (3) 일반회원 (관리자·마스터)
                  _regularMembersButton(),
                  // (3-1) 명부관리 (관리자·마스터, 관리자 명부는 마스터 전용) — 별도 창
                  _rosterAdminButton(),
                  // (3-2) 아타스(ATAS) 명부 — 요구: "아타스 은하버튼 추가"
                  _atasRosterButton(),
                  // (3-3) 은하스카우트 명부 — 요구: "아타스 은하버튼 추가"
                  _eunhaRosterButton(),
                ],
                // (4) 수품 구매 — 권한 허용 시 노출
                if (state.can('merchBuy'))
                  _finButton(
                    '수품 구매',
                    Icons.shopping_cart_checkout,
                    const Color(0xFF6D4C41),
                    -4,
                  ),
                if (state.can('merchMgmt')) ...[
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
                ],
                if (state.can('finance')) ...[
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
                  _finButton('결산', Icons.calculate, AppColors.scoutGreen, 5),
                ],
                // (10) 기본자료 — 마스터 전용(요구: "기본자료 항목은 마스터만 볼 수 있음")
                if (state.isMaster)
                  _finButton('기본자료', Icons.folder_open, AppColors.purple, -1),
              ],
            ),
          ),
          const SizedBox(height: 3),
          // 후원계좌 ↔ 아래 둥근 필터버튼 사이 간격(픽셀 분석: 현재 약 10px →
          //  약간 더 확보, 요구).
          if (state.can('memberSearch'))
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: _donationBanner(state),
            ),
          // 개인 접근에서 HOME 으로 들어온 경우 되돌아가는 안내
          if (personalMain)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.white70,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      '마스터가 설정한 권한 범위의 메뉴만 보입니다.',
                      style: TextStyle(color: Colors.white70, fontSize: 10.5),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                    ),
                    onPressed: () {
                      context.read<AppState>().setPersonalBrowse(false);
                      setState(() => _showMainHome = false);
                    },
                    icon: const Icon(Icons.arrow_back, size: 15),
                    label: const Text(
                      '개인 화면으로',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
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
    final me = _selfMember(state);
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
              // (p.29) 좁은 화면에서도 버튼이 잘리지 않도록 라벨은 유연하게 축소.
              const Flexible(
                child: Text(
                  '개인 접근',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              // HOME — 메인 홈(권한 허용 범위)으로 이동
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    context.read<AppState>().setPersonalBrowse(true);
                    setState(() => _showMainHome = true);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.home_filled,
                          color: AppColors.purple,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'HOME',
                          style: TextStyle(
                            color: AppColors.purple,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // V 표시 영역 — 누르면 본인 정보 편집(수정/저장) 시트 열림
              if (me != null)
                Flexible(
                  child: Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(
                        color: AppColors.scoutGreen,
                        width: 2,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _openPersonalEditSheet(state, me),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified,
                              color: AppColors.scoutGreen,
                              size: 18,
                            ),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '본인 정보 편집',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.scoutGreen,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
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
                            : '${me.corpsFullName} ${me.number.isEmpty ? '-' : me.displayNumber}',
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
                            : 'ATAS ${me.atasNo.isEmpty ? '-' : me.atasNo}',
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
                  Icon(
                    Icons.shopping_cart_checkout,
                    size: 18,
                    color: AppColors.purple,
                  ),
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
          // 게시판(행사+수품) — 개인(범스카우트·일반회원)도 모든 글을 열람한다.
          //  개인 첫화면에서 곧바로 진입할 수 있게 한다(요구).
          if (state.can('board'))
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BoardScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.tigerGold, width: 2),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 18,
                      color: AppColors.purple,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '게시판 (행사·수품 소식·후기)',
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
          // 노출순서(고정): 내 행사 관리 → 수품 구매 → 게시판 → 후원 계좌.
          // ※ 수요조사(수요 대기) 진행정보는 개인프로필 첫 화면에 노출하지 않는다.
          //    → 개인 상세 정보창(MemberDetailScreen)에서 '수품 구매'와 함께 노출.
          // 중앙회 계좌 3개 + 바로 송금 (참가비·후원 등)
          _personalDonationBanner(state),
          // (415 전용) 영구 마스터 — 마스터/개인 권한 on/off (제일 하단)
          if (AppConfig.isPermanentMaster(state.who))
            _permanentMasterToggle(state),
        ],
      ),
    );
  }

  /// 영구 마스터(415) 개인정보 하단 — 마스터 권한/개인 권한 선택 토글.
  Widget _permanentMasterToggle(AppState state) {
    final asMaster = state.permanentMasterMode;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: asMaster
            ? AppColors.lifetimeGold.withValues(alpha: 0.12)
            : AppColors.tigerGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (asMaster ? AppColors.lifetimeGold : AppColors.tigerGold)
              .withValues(alpha: 0.55),
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Icon(
            asMaster ? Icons.workspace_premium : Icons.person_outline,
            size: 20,
            color: asMaster ? AppColors.lifetimeGold : AppColors.tigerGold,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asMaster ? '마스터 권한 사용 중' : '개인 권한 사용 중',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  asMaster
                      ? '영구 마스터(415) — 관리·통계·설정 등 모든 기능 사용'
                      : '개인 권한 — 본인 정보·수품구매만 표시(마스터 기능 숨김)',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: asMaster,
            activeThumbColor: AppColors.lifetimeGold,
            onChanged: (v) async {
              await state.setPermanentMasterMode(v);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(v ? '마스터 권한으로 전환했습니다' : '개인 권한으로 전환했습니다'),
                    duration: const Duration(milliseconds: 1100),
                  ),
                );
              }
            },
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
              const Icon(
                Icons.account_balance,
                color: AppColors.purple,
                size: 15,
              ),
              const SizedBox(width: 5),
              Text(
                '한국${state.isEunha ? '은하' : '범'}스카우트중앙회 계좌',
                style: const TextStyle(
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

  /// 행사+수품판매 게시판 진입 버튼 (요구 #12)
  Widget _boardButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BoardScreen()),
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
              Icon(Icons.forum_outlined, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Text(
                '게시판',
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
  /// 통합승인관리 화면을 연 뒤, 해당 아이디 기준으로 확인 처리(배지 차감).
  Future<void> _openApproval() async {
    final st = context.read<AppState>();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MemberRequestScreen()),
    );
    await st.markBadgeSeen(kind: 'approval');
    _loadApprovalBadge();
  }

  /// 승인 대기 총 건수를 아이콘 상단 **붉은색 원형 숫자**로 표시한다.
  /// (관리자·마스터에게만 노출 — 요구: 두 아이콘 상단 붉은 원형 숫자)
  /// 9 이상이면 '9+'. 탭하면 통합승인관리 화면으로 이동한다.
  Widget _approvalBadgeDot({double size = 18}) {
    final state = context.watch<AppState>();
    final n = _approvalBadgeCount > 0
        ? _approvalBadgeCount
        : state.pendingApprovalCount;
    if (n <= 0) return const SizedBox.shrink();
    return Positioned(
      top: -4,
      right: -5,
      child: GestureDetector(
        onTap: _openApproval,
        child: Container(
          constraints: BoxConstraints(minWidth: size, minHeight: size),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.taegeukRed,
            borderRadius: BorderRadius.circular(size),
            border: Border.all(color: Colors.white, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            n > 99 ? '99+' : '$n',
            style: TextStyle(
              fontSize: n > 9 ? 9 : 10.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  /// 승인관리 아이콘(앱바) — 우상단 붉은 원형 숫자 배지 포함.
  Widget _approvalAppbarIcon() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: '통합승인관리',
          icon: const Icon(Icons.how_to_reg),
          onPressed: _openApproval,
        ),
        _approvalBadgeDot(),
      ],
    );
  }

  Widget _approvalButton() {
    final state = context.watch<AppState>();
    final n = _approvalBadgeCount > 0
        ? _approvalBadgeCount
        : state.pendingApprovalCount;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: _openApproval,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.how_to_reg, size: 16, color: Colors.white),
                  SizedBox(width: 5),
                  Text(
                    '통합승인관리',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (n > 0) _approvalBadgeDot(size: 19),
        ],
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

  Widget _rosterAdminButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RosterAdminScreen()),
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
              Icon(
                Icons.assignment_ind_outlined,
                size: 15,
                color: Colors.white,
              ),
              SizedBox(width: 4),
              Text(
                '명부관리',
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

  /// 아타스(ATAS) 명부 진입 버튼 — 관리자·마스터 전용.
  /// (요구: 홈 메인 버튼 행에 "아타스" 버튼 추가)
  Widget _atasRosterButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AtasRosterScreen()),
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
              Icon(Icons.military_tech, size: 15, color: Colors.white),
              SizedBox(width: 4),
              Text(
                '아타스',
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

  /// 은하스카우트 명부 진입 버튼 — 관리자·마스터 전용.
  /// (요구: 홈 메인 버튼 행에 "은하" 버튼 추가)
  Widget _eunhaRosterButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EunhaRosterScreen()),
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
              Icon(Icons.list_alt, size: 15, color: Colors.white),
              SizedBox(width: 4),
              Text(
                '은하',
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
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
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
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ── 소속 필터 — 범스카우트/은하스카우트 통합검색 (요구: 은하도 명단검색) ──
          //   · 은하스카우트는 배출 중단된 별도 명단이지만, 모든 관리규칙은
          //     범스카우트와 동일하게 검색·말머리 노출한다.
          HScrollMenu(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip(
                  label: '전체 소속',
                  selected: state.corpsFilter.isEmpty,
                  color: AppColors.purple,
                  onTap: () => state.setCorpsFilter(''),
                ),
                const SizedBox(width: 5),
                _filterChip(
                  label: '범스카우트 ${state.corpsFilterTsakCount}',
                  selected: state.corpsFilter == 'tsak',
                  color: AppColors.scoutGreen,
                  onTap: () => state.setCorpsFilter(
                    state.corpsFilter == 'tsak' ? '' : 'tsak',
                  ),
                ),
                const SizedBox(width: 5),
                _filterChip(
                  label: '은하스카우트 ${state.corpsFilterEunhaCount}',
                  selected: state.corpsFilter == 'eunha',
                  color: AppColors.taegeukBlue,
                  onTap: () => state.setCorpsFilter(
                    state.corpsFilter == 'eunha' ? '' : 'eunha',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 1),
          HScrollMenu(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip(
                  label: '전체 회원',
                  selected: state.kindFilter.isEmpty,
                  color: AppColors.purple,
                  onTap: () => state.setKind(''),
                ),
                const SizedBox(width: 5),
                _filterChip(
                  label: '인가자',
                  selected: state.kindFilter == 'credential',
                  color: AppColors.taegeukBlue,
                  onTap: () => state.setKind(
                    state.kindFilter == 'credential' ? '' : 'credential',
                  ),
                ),
                const SizedBox(width: 5),
                _filterChip(
                  label: '일반회원',
                  selected: state.kindFilter == 'regular',
                  color: AppColors.textGray,
                  onTap: () => state.setKind(
                    state.kindFilter == 'regular' ? '' : 'regular',
                  ),
                ),
                const SizedBox(width: 5),
                _filterChip(
                  label: '멘토',
                  selected: state.kindFilter == 'mentor',
                  color: AppColors.scoutGreen,
                  onTap: () => state.setKind(
                    state.kindFilter == 'mentor' ? '' : 'mentor',
                  ),
                ),
                const SizedBox(width: 5),
                _filterChip(
                  label: '페런츠',
                  selected: state.kindFilter == 'parent',
                  color: AppColors.lifetimeGold,
                  onTap: () => state.setKind(
                    state.kindFilter == 'parent' ? '' : 'parent',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 1),
          HScrollMenu(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip(
                  label: '평생회원',
                  selected: state.onlyLifetime,
                  color: AppColors.lifetimeGold,
                  onTap: () => state.setOnlyLifetime(!state.onlyLifetime),
                ),
                const SizedBox(width: 5),
                for (final y in state.feeYears.take(4))
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
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
          const SizedBox(height: 1),
          HScrollMenu(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip(
                  label: '전체 연맹',
                  selected: state.leagueFilter.isEmpty,
                  color: AppColors.purple,
                  onTap: () => state.setLeague(''),
                ),
                const SizedBox(width: 5),
                for (final entry in state.leagues.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
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
            '${m.numberLabel} ${m.name} 님의 정보는 본인만 열람할 수 있습니다.',
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

  /// (마스터) 명단선택 창에서 선택한 계정을 **완전 삭제**.
  ///  · 범스카우트(스포츠): 로컬 목록에서 제거 → 전체 저장 시 NAS 에서도 삭제.
  ///  · 은하스카우트: 서버 별도 명단(/api/member/delete)에서 삭제.
  ///  삭제는 되돌릴 수 없으므로 삭제 대상을 명시한 확인창을 거친다.
  Future<void> _deleteSelected(AppState state, List<Member> all) async {
    final selected = all.where((m) => _selected.contains(m.id)).toList();
    if (selected.isEmpty) return;
    final preview = StringBuffer();
    for (final m in selected.take(10)) {
      final label = m.corps == 'eunha' ? '은하${m.number}' : '인가 ${m.number}';
      preview.writeln('· $label ${m.name}');
    }
    if (selected.length > 10) {
      preview.writeln('… 외 ${selected.length - 10}명');
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('선택한 ${selected.length}명 계정 삭제'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('아래 계정을 완전히 삭제합니다.',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(preview.toString(),
                style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 12),
            const Text(
              '※ 삭제한 계정은 복구할 수 없습니다 (서버 백업은 자동 생성).',
              style: TextStyle(fontSize: 12, color: AppColors.taegeukRed),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = await state.deleteMembers(selected);
    if (!mounted) return;
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    _snack(n > 0 ? '$n명 계정을 삭제했습니다' : '삭제에 실패했습니다');
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

  /// 개인 접근 시 '본인' 회원을 최대한 견고하게 찾는다.
  ///
  /// (p.29) "본인정보편집 클릭해도 링크가 작동하지 않는 문제" 대응:
  ///  · who(인가번호/전화번호)로 조회 → 실패 시 loginId(전화) 로 재조회
  ///  · 그래도 없으면 개인 접근으로 제한된 명단의 첫 건을 사용
  Member? _selfMember(AppState state) {
    final who = state.who.trim();
    if (who.isNotEmpty) {
      final byNo = state.byNumber(who);
      if (byNo != null) return byNo;
      final digits = who.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) {
        for (final m in state.members) {
          if (m.loginId.replaceAll(RegExp(r'[^0-9]'), '') == digits ||
              m.number.replaceAll(RegExp(r'[^0-9]'), '') == digits) {
            return m;
          }
        }
      }
    }
    return state.members.isNotEmpty ? state.members.first : null;
  }

  /// (p.29) 개인정보 편집 화면으로 바로 진입 — 상단 녹색 버튼 전용.
  Future<void> _openMyEdit(AppState state) async {
    final me = _selfMember(state);
    if (me == null) {
      _snack('본인 정보를 불러오는 중입니다. 잠시 후 다시 시도해 주세요.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberEditScreen(memberId: me.id)),
    );
    if (mounted) context.read<AppState>().refresh();
  }

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
          '· 변경하면 다음 접속부터 새 비밀번호를 사용해야 합니다.\n'
          '· 비밀번호를 분실한 경우 관리자·마스터에게 초기화를 요청하세요.',
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
              '비밀번호를 분실한 경우 관리자·마스터에게 초기화를 요청하세요.\n\n'
              '· 관리자(마스터)가 회원 아이디 기준으로\n'
              '  비밀번호를 초기화하거나 재설정할 수 있습니다.\n'
              '· 아래 「초기화 요청」 버튼을 눌러 바로 요청할 수도 있습니다.',
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.tigerGold),
            onPressed: () {
              Navigator.pop(ctx);
              _requestPasswordReset();
            },
            icon: const Icon(Icons.send, size: 16),
            label: const Text('초기화 요청'),
          ),
        ],
      ),
    );
  }

  /// 본인 — 관리자·마스터에게 비밀번호 초기화 요청 (요구).
  Future<void> _requestPasswordReset() async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_reset, color: AppColors.tigerGold, size: 32),
        title: const Text('비밀번호 초기화 요청'),
        content: const Text(
          '관리자·마스터에게 비밀번호 초기화를 요청하시겠습니까?\n\n'
          '· 요청은 통합승인관리에 접수되어 승인 후 초기화됩니다.\n'
          '· 초기화되면 기본 비밀번호로 다시 로그인할 수 있습니다.',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('요청'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await state.requestPasswordReset();
    if (!mounted) return;
    _snack(
      err == null
          ? '초기화 요청을 접수했습니다. 관리자·마스터 승인 후 초기화됩니다.'
          : '요청 실패: $err',
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
                  '인가번호 ${me.numberLabel} (${me.name})',
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
                  '본인 정보 — ${me.numberLabel} ${me.name}',
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
    this.role,
  });

  final IconData icon;
  final String label;
  final Color color;

  /// 권한 배지 — '관리자' 또는 '마스터'. null이면 배지 없음.
  final String? role;

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
        if (role != null) ...[
          const SizedBox(width: 6),
          _RoleBadge(role: role!),
        ],
      ],
    );
  }
}

/// 권한 구분용 작은 원형 배지 — 관리자(파랑) / 마스터(빨강).
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final isMaster = role == '마스터';
    final bg = isMaster ? AppColors.taegeukRed : AppColors.taegeukBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.35),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        role,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          height: 1.25,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}
