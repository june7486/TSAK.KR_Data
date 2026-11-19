import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/build_info.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/inquiry_sheet.dart';
import 'access_log_screen.dart';
import 'admin_screen.dart';
import 'board_screen.dart';
import 'bulk_screen.dart';
import 'eunha_roster_screen.dart';
import 'event_year_screen.dart';
import 'export_screen.dart';
import 'finance_screen.dart';
import 'finance_ledger_screen.dart';
import 'home_menu_perm_screen.dart';
import 'import_log_screen.dart';
import 'merch_admin_screen.dart';
import 'member_request_screen.dart';
import 'member_field_visibility_screen.dart';
import 'regular_members_screen.dart';
import 'role_permissions_screen.dart';
import 'settings_screen.dart';
import 'storage_screen.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/master_password_dialog.dart';
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

  /// [turn69] 마스터 비번이 **기본값 그대로**인지 / 언제 바꿨는지.
  ///  기본값이면 화면에 경고 띠를 띄운다 — 초기 비번은 문서·git 이력에
  ///  남아 있을 수 있어 그대로 두는 것이 가장 위험하다.
  bool _masterCustom = true;
  String _masterChangedAt = '';

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
      // [turn69] 마스터 비번 상태는 실패해도 화면을 막지 않는다(부가 정보).
      try {
        final ms = await _nas.masterState();
        if (!mounted) return;
        setState(() {
          _masterCustom = ms['custom'] == true;
          _masterChangedAt = (ms['changedAt'] ?? '').toString();
        });
      } catch (_) {}
    } catch (_) {}
  }

  /// [turn69] 마스터 비밀번호 변경 — **새 비번 3회 확인** 후에만 저장.
  Future<void> _changeMasterPw() async {
    final done = await showMasterPasswordDialog(context, _nas);
    if (done == true) {
      _snack('마스터 비밀번호를 변경했습니다. 다른 기기의 마스터 세션은 정리됩니다.');
      await _load();
    }
  }

  /// 기본 비번을 아직 쓰고 있으면 경고 띠를 보여준다.
  Widget _masterPwBanner() {
    if (_masterCustom) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.verified_user,
            size: 18, color: AppColors.scoutGreen),
        title: Text(
          _masterChangedAt.isEmpty
              ? '비밀번호 변경됨'
              : '비밀번호 변경됨 · $_masterChangedAt',
          style: const TextStyle(fontSize: 12, color: AppColors.textGray),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppColors.taegeukRed.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppColors.taegeukRed.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.gpp_maybe, size: 17, color: AppColors.taegeukRed),
          SizedBox(width: 7),
          Expanded(
            child: Text(
              '아직 초기 비밀번호를 쓰고 있습니다. 지금 바꾸는 것을 권합니다.',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.taegeukRed,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
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
        appBar: TsakAppBar(title: const Text('마스터 관리창')),
        body: const Center(child: Text('마스터 권한이 필요합니다')),
      );
    }
    final paused = state.adminState['serverPaused'] == true;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
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
                _tile(
                  '백업 만들기',
                  Icons.backup,
                  AppColors.scoutGreen,
                  () => _run(() async {
                    await _nas.createBackup();
                    await _load();
                  }, '백업'),
                ),
                _tile(
                  '복원 (최근 백업)',
                  Icons.restore,
                  AppColors.taegeukBlue,
                  _restorePicker,
                ),
                _tile(
                  paused ? '서버 개시' : '서버 중지',
                  paused ? Icons.play_circle : Icons.pause_circle,
                  paused ? AppColors.scoutGreen : AppColors.taegeukRed,
                  () => _run(
                    () => state.setServerPaused('', !paused),
                    paused ? '서버 개시' : '서버 중지',
                  ),
                ),
                _tile(
                  '백업/복원 상세',
                  Icons.settings_backup_restore,
                  AppColors.purple,
                  () => _push(const SettingsScreen()),
                ),
              ]),
              _section('회원 · 권한', [
                _tile(
                  '메뉴별 접근권한 관리',
                  Icons.tune,
                  AppColors.purple,
                  () => _push(const RolePermissionsScreen()),
                ),
                _tile(
                  '홈 메뉴 노출권한 (마스터/관리자)',
                  Icons.visibility_outlined,
                  AppColors.taegeukBlue,
                  () => _push(const HomeMenuPermScreen()),
                ),
                _tile(
                  '개인정보 기본 노출 설정',
                  Icons.visibility_outlined,
                  AppColors.scoutGreen,
                  () => _push(const MemberFieldVisibilityScreen()),
                ),
                _tile(
                  '관리자 권한 선정 · 관리',
                  Icons.verified_user,
                  AppColors.taegeukBlue,
                  () => _push(const AdminScreen()),
                ),
                _tile(
                  '회원관리 (인가자)',
                  Icons.people_alt,
                  AppColors.purple,
                  () => _push(const RegularMembersScreen()),
                ),
                _tile(
                  '승인관리 (비인가·행사·연회비·평생 통합)',
                  Icons.how_to_reg,
                  AppColors.tigerGold,
                  () => _push(const MemberRequestScreen()),
                ),
                _tile(
                  '일괄작업 (단체문자)',
                  Icons.campaign,
                  AppColors.taegeukBlue,
                  () => _push(const BulkScreen()),
                ),
              ]),
              _section('조회 · 확인', [
                _tile(
                  '최근 올라온 게시글',
                  Icons.forum_outlined,
                  AppColors.purple,
                  () => _push(const BoardScreen()),
                  badge: _unread > 0 ? '$_unread' : null,
                ),
                _tile(
                  '최근 주문내역',
                  Icons.receipt_long,
                  AppColors.taegeukBlue,
                  () => _pushTab(1),
                ),
                _tile(
                  '재무 확인',
                  Icons.account_balance_wallet,
                  AppColors.tigerGold,
                  () => _push(const FinanceScreen()),
                ),
                _tile(
                  '재무 원장 (입금·지출 · 첨부 관리)',
                  Icons.receipt_long_outlined,
                  AppColors.tigerGold,
                  () => _push(const FinanceLedgerScreen()),
                ),
                _tile(
                  '자료 저장공간 (NAS · 구글드라이브)',
                  Icons.cloud_sync,
                  AppColors.taegeukBlue,
                  () => _push(const StorageScreen()),
                ),
                _tile(
                  '자료 가져오기 로그 · 복원',
                  Icons.restore_page,
                  AppColors.taegeukRed,
                  () => _push(const ImportLogScreen()),
                ),
                _tile(
                  '수품 재고 확인',
                  Icons.inventory_2,
                  AppColors.scoutGreen,
                  () => _pushTab(5),
                ),
                _tile(
                  '행사 확인',
                  Icons.event_note,
                  AppColors.purple,
                  () => _push(const EventYearScreen()),
                ),
                _tile(
                  '사진관리 / 통계',
                  Icons.insights,
                  AppColors.taegeukBlue,
                  () => _push(const StatsScreen()),
                ),
              ]),
              _section('은하스카우트 (별도 관리)', [
                _tile(
                  '은하스카우트 명단',
                  Icons.groups_2,
                  AppColors.taegeukBlue,
                  () => _push(const EunhaRosterScreen()),
                ),
                _tile(
                  '은하스카우트 통계',
                  Icons.insights,
                  AppColors.tigerGold,
                  () => _push(const StatsScreen(initialScope: 1)),
                ),
              ]),
              // ── [turn69] 마스터 계정 보안 ─────────────────────────────
              //  요구: "마스터비번 변경 … 마스터창에 비번 변경 창 추가로 넣음"
              //  해시로만 보관하므로 **되찾기 불가** → 화면에서 3회 확인.
              _section('마스터 계정 보안', [
                _masterPwBanner(),
                _tile(
                  '마스터 비밀번호 변경',
                  Icons.key_rounded,
                  AppColors.taegeukRed,
                  _changeMasterPw,
                  badge: _masterCustom ? null : '기본값',
                ),
              ]),
              _section('출력 · 로그', [
                _tile(
                  '출력 (명단·PDF·엑셀)',
                  Icons.print,
                  AppColors.purple,
                  () => _push(
                    ExportScreen(
                      members: context.read<AppState>().members,
                      title: '전체 명단 출력',
                    ),
                  ),
                ),
                _tile(
                  '로그 확인',
                  Icons.history,
                  AppColors.textGray,
                  () => _push(const AccessLogScreen()),
                ),
              ]),
              _section('앱 · 문의', [
                _tile(
                  '지도 검색 키 (카카오)',
                  Icons.map_outlined,
                  AppColors.scoutGreen,
                  () => _editMapKeys(),
                ),
                _tile(
                  '문의글 확인 · 답변',
                  Icons.help_outline,
                  AppColors.taegeukBlue,
                  () => showInquirySheet(context),
                ),
                _tile(
                  '첫 화면 표시글 확인 · 변경',
                  Icons.push_pin_outlined,
                  AppColors.tigerGold,
                  () => _editHomeNotice(),
                ),
                _tile(
                  '버전 확인',
                  Icons.info_outline,
                  AppColors.textGray,
                  () => _showVersion(),
                ),
                _tile(
                  '관리자 계정 관리',
                  Icons.vpn_key,
                  AppColors.taegeukRed,
                  () => _push(const AdminScreen()),
                ),
              ]),
              _section('알림', [
                if (_notifies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '최근 알림이 없습니다',
                      style: TextStyle(color: AppColors.textGray),
                    ),
                  )
                else
                  for (final n in _notifies.take(8))
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.notifications_active,
                        color: AppColors.tigerGold,
                        size: 20,
                      ),
                      title: Text(
                        '${n['title'] ?? ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${n['created'] ?? ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: n['read'] == true
                          ? null
                          : const Icon(
                              Icons.circle,
                              size: 8,
                              color: AppColors.taegeukRed,
                            ),
                    ),
              ]),
            ],
          ),
          BusyOverlay(
            visible: _busy,
            title: '작업을 처리하는 중입니다',
            lines: const [
              'NAS 서버에 요청을 전달하고 있습니다...',
              '결과를 반영하는 중...',
              '잠시만 기다려 주세요...',
            ],
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
                const Text(
                  '마스터 관리 콘솔',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
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
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textGray,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: tiles),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _tile(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    String? badge,
  }) {
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
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('복원'),
          ),
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

  /// 특정 탭으로 수품 판매관리 화면을 연다.
  /// (탭 번호는 MerchAdminScreen(initialTab:)로 전달되어 실제로 그 탭이 열린다.)
  void _pushTab(int tab) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MerchAdminScreen(initialTab: tab)),
    );
  }

  /// 첫 화면 표시글(홈 공지) 확인·변경 — 수품 판매관리 설정 탭의 공지 편집으로 연결.
  void _editHomeNotice() {
    _pushTab(0);
    _snack('상품관리 탭 상단의 공지 편집기에서 첫 화면 표시글을 변경할 수 있습니다');
  }

  /// (요구) 지도 위치검색에 쓰는 카카오 REST API 키를 등록·시험한다.
  ///
  ///  · 카카오 developers > 내 애플리케이션 > [앱 키] 에는 3종류가 있다:
  ///    REST API 키 / JavaScript 키 / 네이티브 앱 키.
  ///  · 서버에서 '장소 검색(좌표 얻기)'을 하려면 **REST API 키** 하나만 있으면 된다.
  ///    (JavaScript 키는 웹 지도 임베드, 네이티브 앱 키는 안드로이드/iOS SDK용)
  ///  · 키를 넣고 [저장+시험] 을 누르면 곧바로 검색을 시험해 결과 개수를 보여준다.
  Future<void> _editMapKeys() async {
    final nas = _nas;
    Map<String, dynamic> cfg = {};
    try {
      cfg = await nas.fetchConfig();
    } catch (_) {}
    final cur = '${cfg['kakaoRestKey'] ?? ''}';
    final curJs = '${cfg['kakaoJsKey'] ?? ''}';
    final ctrl = TextEditingController(text: cur);
    final jsCtrl = TextEditingController(text: curJs);
    final qCtrl = TextEditingController(text: '부산 송정해수욕장');
    bool busy = false;
    String? testMsg;
    String? mapMsg;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.map_outlined, size: 20, color: AppColors.scoutGreen),
              SizedBox(width: 6),
              Text('지도 검색 키 (카카오)', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F7F3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '• [REST API 키] — 서버가 장소를 검색해 좌표를 얻습니다(필수).\n'
                      '   → 카카오 콘솔 > 제품 설정 > 카카오맵 에서\n'
                      "      '카카오맵(로컬)' 서비스를 반드시 활성화(ON)해야 검색됩니다.\n"
                      '• [JavaScript 키] — 실제 카카오 지도를 화면에 띄웁니다(선택).\n'
                      '   → 카카오 콘솔 > 플랫폼 키 > JavaScript SDK 도메인에\n'
                      '      이 앱 주소(예: *.sandbox.novita.ai)를 등록해야 지도가 뜹니다.\n'
                      '• 둘 다 비워도 무료 지도(OpenStreetMap)로 자동 동작합니다.',
                      style: TextStyle(fontSize: 11.5, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      labelText: '카카오 REST API 키 (좌표 검색)',
                      hintText: '카카오 콘솔의 REST API 키 (32자리)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: jsCtrl,
                    decoration: const InputDecoration(
                      labelText: '카카오 JavaScript 키 (지도 표시)',
                      hintText: '예) 8c75a4f4f9510dd70bf5ba132995cd81',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qCtrl,
                          decoration: const InputDecoration(
                            labelText: '시험 검색어',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                setSt(() {
                                  busy = true;
                                  testMsg = null;
                                });
                                try {
                                  final saved = await nas.saveConfig({
                                    'kakaoRestKey': ctrl.text.trim(),
                                    'kakaoJsKey': jsCtrl.text.trim(),
                                  });
                                  // 실제 카카오 응답으로 키 유효성 진단.
                                  final diag = await nas.geoKakaoTest();
                                  final items = await nas.geoSearch(
                                    qCtrl.text.trim(),
                                    limit: 5,
                                  );
                                  final hasJs = jsCtrl.text.trim().isNotEmpty;
                                  String diagMsg;
                                  if (diag['ok'] == true) {
                                    diagMsg = '카카오 키 정상 ✓';
                                  } else {
                                    final hint = '${diag['hint'] ?? ''}'.trim();
                                    if (hint.isNotEmpty) {
                                      diagMsg = '⚠ $hint';
                                    } else if (diag['status'] != null) {
                                      final kk = diag['kakao'];
                                      final em = (kk is Map)
                                          ? '${kk['message'] ?? kk['errorType'] ?? ''}'
                                          : '${diag['error'] ?? ''}';
                                      diagMsg =
                                          '⚠ 카카오 오류(${diag['status']}): $em';
                                    } else {
                                      diagMsg = '⚠ ${diag['error'] ?? '진단 실패'}';
                                    }
                                  }
                                  setSt(() {
                                    busy = false;
                                    testMsg =
                                        '저장됨 ${saved['ok'] == true ? '✓' : '?'}\n'
                                        '$diagMsg\n'
                                        '${hasJs ? 'JavaScript 키 ✓ (지도 표시)' : '⚠ JavaScript 키가 비어 카카오맵이 안 뜹니다'}\n'
                                        '좌표검색 ${items.length}건'
                                        '${items.isNotEmpty ? ' · ${items.first['label']}' : ''}';
                                  });
                                } catch (e) {
                                  setSt(() {
                                    busy = false;
                                    testMsg = '오류: $e';
                                  });
                                }
                              },
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text(
                          '저장 + 시험',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (testMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        testMsg!,
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await nas.saveConfig({
                            'kakaoJsKey': jsCtrl.text.trim(),
                          });
                          setSt(() {
                            mapMsg = jsCtrl.text.trim().isEmpty
                                ? 'JS 키가 비어 있어 지도는 OSM 미리보기로 표시됩니다.'
                                : 'JS 키 저장됨 — 지도 이미지를 불러옵니다…';
                          });
                        },
                        icon: const Icon(Icons.map, size: 16),
                        label: const Text(
                          'JS 키 저장 + 지도 확인',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (jsCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        nas.geoKakaoMapUrl(
                          '35.1798',
                          '129.0750',
                          w: 480,
                          h: 200,
                        ),
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '지도 이미지를 불러올 수 없습니다. '
                            '(JavaScript SDK 도메인에 이 앱 주소를 등록했는지 확인)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.taegeukRed,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (mapMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        mapMsg!,
                        style: const TextStyle(fontSize: 11.5, height: 1.4),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () async {
                await nas.saveConfig({
                  'kakaoRestKey': ctrl.text.trim(),
                  'kakaoJsKey': jsCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('지도 검색 키가 저장되었습니다');
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    jsCtrl.dispose();
    qCtrl.dispose();
  }

  void _showVersion() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('버전 정보'),
        content: Text(
          '앱 버전: $versionName\n'
          '커밋: $kCommit\n'
          '빌드: $kBuildDisplay',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
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
