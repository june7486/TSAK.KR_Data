import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/app_config.dart';
import '../services/build_info.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/inquiry_sheet.dart';
import 'admin_screen.dart';
import 'approval_screen.dart';
import 'board_screen.dart';
import 'bulk_screen.dart';
import 'export_screen.dart';
import 'finance_screen.dart';
import 'merch_admin_screen.dart';
import 'regular_members_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

/// 마스터 전용 관리창 (#11 / #13b).
/// 백업·복원·서버 개시/중지, 관리자 권한 선정·관리, 회원관리, 비밀번호 관리,
/// 출력, 로그 확인, 최근 게시글/주문 내역, 재무·재고·행사 확인, 사진관리,
/// 관리자 계정 생성·삭제, 첫 화면 표시글, 버전, 메뉴별 접근권한, 문의 답변 등
/// 모든 마스터 기능을 한 화면에 모은 허브.
class MasterConsoleScreen extends StatefulWidget {
  const MasterConsoleScreen({super.key});

  @override
  State<MasterConsoleScreen> createState() => _MasterConsoleScreenState();
}

class _MasterConsoleScreenState extends State<MasterConsoleScreen> {
  NasApi get _nas => context.read<NasApi>();

  bool _busy = false;
  List<Map<String, dynamic>> _backups = [];
  List<Map<String, dynamic>> _notifies = [];
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final bk = await _nas.backups();
      final nt = await _nas.notifyList();
      if (!mounted) return;
      setState(() {
        _backups = bk;
        _notifies = ((nt['items'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _unread = (nt['unread'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() fn, String label) async {
    setState(() => _busy = true);
    try {
      await fn();
      _snack('$label 완료');
    } catch (e) {
      _snack('$label 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return Scaffold(
        appBar: AppBar(title: const Text('마스터 관리창')),
        body: const Center(child: Text('마스터 권한이 필요합니다')),
      );
    }
    final paused = state.adminState['serverPaused'] == true;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('마스터 관리창'),
        actions: [
          const AppHomeEmblem(size: 22),
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
            children: [
              _statusCard(state, paused),
              const SizedBox(height: 12),
              _section('서버 · 데이터', [
                _tile('백업 만들기', Icons.backup, AppColors.scoutGreen,
                    () => _run(() async {
                          await _nas.createBackup();
                          await _load();
                        }, '백업')),
                _tile('복원 (최근 백업)', Icons.restore, AppColors.taegeukBlue,
                    _restorePicker),
                _tile(
                    paused ? '서버 개시' : '서버 중지',
                    paused ? Icons.play_circle : Icons.pause_circle,
                    paused ? AppColors.scoutGreen : AppColors.taegeukRed,
                    () => _run(
                        () => state.setServerPaused('', !paused),
                        paused ? '서버 개시' : '서버 중지')),
                _tile('백업/복원 상세', Icons.settings_backup_restore,
                    AppColors.purple, () => _push(const SettingsScreen())),
              ]),
              _section('회원 · 권한', [
                _tile('관리자 권한 선정 · 관리', Icons.verified_user,
                    AppColors.taegeukBlue, () => _push(const AdminScreen())),
                _tile('회원관리 (인가자)', Icons.people_alt,
                    AppColors.purple, () => _push(const RegularMembersScreen())),
                _tile('승인 대기 관리', Icons.how_to_reg, AppColors.tigerGold,
                    () => _push(const ApprovalScreen())),
                _tile('일괄작업 (단체문자)', Icons.campaign,
                    AppColors.taegeukBlue, () => _push(const BulkScreen())),
              ]),
              _section('조회 · 확인', [
                _tile('최근 올라온 게시글', Icons.forum_outlined,
                    AppColors.purple, () => _push(const BoardScreen()),
                    badge: _unread > 0 ? '$_unread' : null),
                _tile('최근 주문내역', Icons.receipt_long, AppColors.taegeukBlue,
                    () => _pushTab(const MerchAdminScreen(), 1)),
                _tile('재무 확인', Icons.account_balance_wallet,
                    AppColors.tigerGold, () => _push(const FinanceScreen())),
                _tile('수품 재고 확인', Icons.inventory_2, AppColors.scoutGreen,
                    () => _pushTab(const MerchAdminScreen(), 4)),
                _tile('행사 확인', Icons.event_note, AppColors.purple,
                    () => _pushTab(const MerchAdminScreen(), 7)),
                _tile('사진관리 / 통계', Icons.insights,
                    AppColors.taegeukBlue, () => _push(const StatsScreen())),
              ]),
              _section('출력 · 로그', [
                _tile('출력 (명단·PDF·엑셀)', Icons.print, AppColors.purple,
                    () => _push(ExportScreen(
                        members: context.read<AppState>().members,
                        title: '전체 명단 출력'))),
                _tile('로그 확인', Icons.history, AppColors.textGray,
                    () => _pushTab(const MerchAdminScreen(), 10)),
              ]),
              _section('앱 · 문의', [
                _tile('문의글 확인 · 답변', Icons.help_outline,
                    AppColors.taegeukBlue, () => showInquirySheet(context)),
                _tile('첫 화면 표시글 확인 · 변경', Icons.push_pin_outlined,
                    AppColors.tigerGold, () => _editHomeNotice()),
                _tile('버전 확인', Icons.info_outline, AppColors.textGray,
                    () => _showVersion()),
                _tile('관리자 계정 관리', Icons.vpn_key, AppColors.taegeukRed,
                    () => _push(const AdminScreen())),
                _tile('메뉴별 접근권한 관리', Icons.tune, AppColors.purple,
                    () => _push(const AdminScreen())),
              ]),
              _section('알림', [
                if (_notifies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('최근 알림이 없습니다',
                        style: TextStyle(color: AppColors.textGray)),
                  )
                else
                  for (final n in _notifies.take(8))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.notifications_active,
                          color: AppColors.tigerGold, size: 20),
                      title: Text('${n['title'] ?? ''}',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text('${n['created'] ?? ''}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: n['read'] == true
                          ? null
                          : const Icon(Icons.circle,
                              size: 8, color: AppColors.taegeukRed),
                    ),
              ]),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black.withValues(alpha: 0.35),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text('처리 중입니다...',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusCard(AppState state, bool paused) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Colors.white, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('마스터 관리 콘솔',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  '서버 ${paused ? '중지됨' : '가동 중'} · 백업 ${_backups.length}개'
                  '${_unread > 0 ? ' · 새 알림 $_unread' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textGray)),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: tiles),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _tile(String label, IconData icon, Color color, VoidCallback onTap,
      {String? badge}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: badge != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.taegeukRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(badge,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            )
          : const Icon(Icons.chevron_right, color: AppColors.textGray),
      onTap: onTap,
    );
  }

  Future<void> _restorePicker() async {
    if (_backups.isEmpty) {
      _snack('복원할 백업이 없습니다');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('복원할 백업 선택'),
        children: [
          for (final b in _backups.take(20))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, '${b['name'] ?? ''}'),
              child: Text('${b['name'] ?? ''}'),
            ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    final appState = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('복원 확인'),
        content: Text('$name 으로 복원하시겠습니까?\n현재 데이터는 백업 후 교체됩니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('복원')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _nas.restore(name);
      await appState.refreshFromNas();
      await _load();
    }, '복원');
  }

  void _push(Widget w) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => w));
  }

  void _pushTab(Widget w, int tab) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => w));
  }

  /// 첫 화면 표시글(홈 공지) 확인·변경 — 수품 판매관리 설정 탭의 공지 편집으로 연결.
  void _editHomeNotice() {
    _pushTab(const MerchAdminScreen(), 0);
    _snack('상품관리 탭 상단의 공지 편집기에서 첫 화면 표시글을 변경할 수 있습니다');
  }

  void _showVersion() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('버전 정보'),
        content: Text('앱 버전: v${AppConfig.appVersion}\n'
            '빌드: $kBuildDisplay'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }
}
