import 'package:flutter/material.dart';
import '../widgets/marquee_text.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/file_save.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/address_field.dart';
import '../widgets/donation_accounts.dart';
import '../widgets/confirm.dart';
import '../widgets/hscroll_menu.dart';
import 'roster_screen.dart';
import 'event_review_screen.dart';
import 'member_detail_screen.dart';
import 'member_edit_screen.dart';

/// 행사 상세 — 항목(계획서/참석자/사진+동영상/참가비·후원금/행사비지출)
///
/// 관리자·마스터는 모든 항목 관리. 참가자는 사진+동영상 폴더만 접근한다.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.year,
    required this.title,
    required this.canManage,
  });

  final String year;
  final String title;
  final bool canManage;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic> _event = {};
  bool _loading = true;
  TabController? _tab;

  /// (요구 #14) 행사 스텝(STAFF) 여부 — 지정자는 해당 행사 전체 게시판이 노출된다.
  bool _isStaff = false;
  List<Map<String, dynamic>> _staff = [];

  /// (요구 #14) 스텝 포함 전체 게시판 노출 여부.
  bool get _fullView => widget.canManage || _isStaff;

  List<Map<String, dynamic>> _plan = [];
  List<Map<String, dynamic>> _media = [];
  List<Map<String, dynamic>> _attendees = [];
  Map<String, dynamic> _access = {};
  List<Map<String, dynamic>> _fees = [];
  List<Map<String, dynamic>> _expenses = [];

  /// 사용자 정의 '메뉴추가' 탭 목록 [{name, note}] (PDF page9 최종 결정).
  List<Map<String, dynamic>> _customTabs = [];
  int _cols = 5;
  int _pinchBaseCols = 3;

  /// 사진+동영상 하위폴더 탐색 스택 (예: ['봄행사','1팀'])
  List<String> _mediaPath = [];
  bool _mediaSelect = false;
  final Set<String> _mediaSel = {};

  String get _mediaSub => _mediaPath.join('/');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // [요구] 행사 폴더 열기 속도 개선 — 접근 이력 기록(로그)과 본문 로딩을
      //   직렬로 기다리지 않고 동시에 시작한다(로그 실패는 무시).
      _logMediaAccess();
      _load();
    });
  }

  /// 참가자가 접속하면 사진+동영상 접근 이력 기록
  Future<void> _logMediaAccess() async {
    if (widget.canManage) return;
    final s = context.read<AppState>();
    if (!s.isPersonal && !s.isGuest) return;
    try {
      await context.read<NasApi>().eventAccessLog(
        widget.year,
        widget.title,
        id: s.who,
        role: s.isGuest ? '일반회원' : '범인가자',
      );
    } catch (_) {}
  }

  NasApi get _nas => context.read<NasApi>();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // [요구] 행사 폴더 열기 속도 개선 — 5개 API(행사·기획서·미디어·접근·재무)를
      //   순차(약 5×RTT)로 기다리던 것을 '동시 병렬' 호출로 바꾼다.
      //   가장 느린 1개 응답 시간에 수렴 → 체감 로딩 대폭 단축.
      final results = await Future.wait<Object>([
        _nas.eventGet(widget.year, widget.title),
        _nas.eventFiles(widget.year, widget.title, 'plan'),
        _nas.eventFiles(widget.year, widget.title, 'media', sub: _mediaSub),
        _nas.eventAccessMap(widget.year, widget.title),
        widget.canManage
            ? _nas.eventFinance(widget.year, widget.title)
            : Future<Map<String, dynamic>>.value(const {}),
      ]);
      final e = results[0] as Map<String, dynamic>;
      final plan = results[1] as List<Map<String, dynamic>>;
      final media = results[2] as List<Map<String, dynamic>>;
      final access = results[3] as Map<String, dynamic>;
      final fin = results[4] as Map<String, dynamic>;
      final atts = ((e['attendees'] as List?) ?? [])
          .map((x) => (x as Map).cast<String, dynamic>())
          .toList();
      List<Map<String, dynamic>> fees = [];
      List<Map<String, dynamic>> exps = [];
      if (widget.canManage) {
        fees = ((fin['fees'] as List?) ?? [])
            .map((x) => (x as Map).cast<String, dynamic>())
            .toList();
        exps = ((fin['expenses'] as List?) ?? [])
            .map((x) => (x as Map).cast<String, dynamic>())
            .toList();
      }
      if (!mounted) return;
      // (요구 #14) 스텝 여부 판정 — 지정자는 전체 게시판 노출.
      final s = context.read<AppState>();
      final staffList = ((e['staff'] as List?) ?? [])
          .map((x) => (x as Map).cast<String, dynamic>())
          .toList();
      final myIdent = s.who.replaceAll(RegExp(r'[^0-9]'), '');
      bool isStaff = false;
      if (myIdent.isNotEmpty) {
        for (final a in staffList) {
          final id =
              '${a['number'] ?? a['ident'] ?? a['loginId'] ?? a['phone'] ?? ''}'
                  .replaceAll(RegExp(r'[^0-9]'), '');
          if (id.isNotEmpty && id == myIdent) {
            isStaff = true;
            break;
          }
        }
      }
      final fullView = widget.canManage || isStaff;
      setState(() {
        _event = e;
        _plan = plan;
        _media = media;
        _access = access;
        _attendees = atts;
        _isStaff = isStaff;
        _staff = staffList;
        _fees = fees;
        _expenses = exps;
        _customTabs = ((e['customTabs'] as List?) ?? [])
            .map((x) => (x as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
        // 기본 탭(고정) + 사용자 정의 '메뉴추가' 탭(PDF page9 최종 결정).
        final customCount = _customTabs.length;
        // [요구] 상단 탭: 참가자·사진+동영상·후기·기획서·참가비·후원금·행사비지출 = 6.
        final len = (fullView ? 6 : 1) + (fullView ? customCount : 0);
        // ⚠️ 버그 수정: _load() 마다 TabController 를 새로 만들면 index 가 0
        // (참가자 탭)으로 되돌아가, 사진+동영상 하위폴더에 진입해도 다시
        // 사진 탭으로 돌아가 버렸다. 현재 탭 인덱스를 보존한다.
        final prevIndex = _tab?.index ?? 0;
        if (_tab == null || _tab!.length != len) {
          _tab?.dispose();
          _tab = TabController(
            length: len,
            vsync: this,
            initialIndex: prevIndex.clamp(0, len - 1),
          );
        }
        if (!fullView) _tab!.index = 0;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('불러오기 실패: $err')));
    }
    if (mounted) hideBusy();
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // [요구] 상단 탭 순서 — 참가자 → 사진+동영상 → 후기 → 기획서 → 참가비·후원금 → 행사비지출.
    //   '후기'는 별도 탭 화면(_reviewTab)이며, 기존 우측 상단 아이콘도 유지한다.
    final baseTabs = const [
      '참가자',
      '사진+동영상',
      '후기',
      '기획서',
      '참가비·후원금',
      '행사비지출',
    ];
    final tabs = _fullView
        ? <String>[...baseTabs, ..._customTabs.map((e) => '${e['name'] ?? ''}')]
        : const <String>['사진+동영상'];
    return Scaffold(
      appBar: TsakAppBar(
        title: Row(
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarqueeText(
                    widget.title,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    '${widget.year}'
                    '${'${_event['place'] ?? ''}'.isNotEmpty ? ' · ${_event['place']}' : ''}'
                    '${((_event['credViewers'] as num?)?.toInt() ?? 0) > 0 ? ' · 👁 인가자 ${(_event['credViewers'] as num).toInt()}명 열람' : ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
            // [turn9-6] 행사명 옆 QR 아이콘 (PDF page9 최종 결정) — 참가 등록 QR.
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '행사 QR 코드 (참가 등록)',
              onPressed: _showEventQr,
              icon: const Icon(Icons.qr_code_2, size: 20),
            ),
          ],
        ),
        bottom: _tab == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: HsTabStrip(controller: _tab!, labels: tabs),
              ),
        actions: [
          const AppHomeEmblem(size: 22),
          // 후기 게시판 — 개인(범스카우트·일반회원)도 행사 후기를 열람/작성한다.
          IconButton(
            tooltip: '행사 후기 게시판',
            icon: const Icon(Icons.forum_outlined),
            onPressed: _openReview,
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.canManage)
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'zip':
                    _download(
                      context.read<NasApi>().eventZipUrl(
                        widget.year,
                        widget.title,
                        'media',
                      ),
                    );
                    break;
                  case 'request':
                    _requestPhoto();
                    break;
                  case 'qr':
                    _showEventQr();
                    break;
                  case 'staff':
                    _manageStaff();
                    break;
                  case 'addmenu':
                    _addCustomTab();
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'qr', child: Text('행사 QR 코드 (참가 등록)')),
                PopupMenuItem(value: 'zip', child: Text('사진 전체 ZIP 다운로드')),
                PopupMenuItem(
                  value: 'request',
                  child: Text('전체 참가자 사진 업로드 요청'),
                ),
                PopupMenuItem(value: 'staff', child: Text('행사 스텝(STAFF) 등록')),
                PopupMenuItem(
                  value: 'addmenu',
                  child: Text('메뉴 추가 (사용자 정의 탭)'),
                ),
              ],
            ),
        ],
      ),
      body: _loading || _tab == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // (요구#3) 후기 — 위치를 본문 상단으로 옮겨 **모든 회원**이
                //  관리자 여부와 무관하게 바로 열람·작성할 수 있게 한다.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.scoutGreen,
                        side: BorderSide(
                          color: AppColors.scoutGreen.withValues(alpha: 0.5),
                        ),
                        backgroundColor: AppColors.scoutGreen.withValues(
                          alpha: 0.06,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: _openReview,
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      label: const Text(
                        '행사 후기 (모든 회원 열람·작성)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
                // 참가자(개인 접근): 참가비·후원 납부 계좌 3개 + 송금 버튼
                if (!_fullView)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: DonationAccounts(
                      title: '참가비·후원 납부 계좌',
                      showHolder: true,
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: _fullView
                        ? [
                            _attendeeTab(),
                            _mediaTab(),
                            // [요구] 후기 탭 — 참가자→사진+동영상→후기→기획서→…
                            EventReviewScreen(
                              year: widget.year,
                              title: widget.title,
                              embedded: true,
                            ),
                            _planTab(),
                            _financeTab('fee'),
                            _financeTab('expense'),
                            for (final t in _customTabs) _customTabView(t),
                          ]
                        : [_mediaTab()],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _download(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      _snack('다운로드 실패: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ============================ 계획서 ============================
  Widget _planTab() {
    return _fileListPane(
      key: 'plan',
      files: _plan,
      emptyText: '계획서를 업로드하세요 (엑셀·워드·PDF 등)',
      allowedExts: const ['xlsx', 'xls', 'docx', 'doc', 'pdf', 'hwp', 'txt'],
    );
  }

  Widget _fileListPane({
    required String key,
    required List<Map<String, dynamic>> files,
    required String emptyText,
    List<String> allowedExts = const [],
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _uploadFiles(key, allowedExts: allowedExts),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('파일 업로드'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    _download(_nas.eventZipUrl(widget.year, widget.title, key)),
                icon: const Icon(Icons.download),
                label: const Text('ZIP'),
              ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? Center(
                  child: Text(
                    emptyText,
                    style: const TextStyle(color: AppColors.textGray),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = files[i];
                    final name = '${f['name']}';
                    final size = (f['size'] as num?)?.toInt() ?? 0;
                    final kind = '${f['kind'] ?? 'other'}';
                    final up = '${f['uploader'] ?? ''}';
                    return ListTile(
                      leading: Icon(
                        kind == 'image'
                            ? Icons.image_outlined
                            : kind == 'video'
                            ? Icons.videocam_outlined
                            : Icons.description_outlined,
                        color: AppColors.purple,
                      ),
                      title: Text(name),
                      subtitle: Text(
                        '${_fmtSize(size)}'
                        '${up.isNotEmpty ? ' · $up' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'open') {
                            _download(
                              _nas.eventFile2Url(
                                widget.year,
                                widget.title,
                                key,
                                name,
                              ),
                            );
                          } else if (v == 'dl') {
                            _download(
                              _nas.eventFile2Url(
                                widget.year,
                                widget.title,
                                key,
                                name,
                                download: true,
                              ),
                            );
                          } else if (v == 'rename') {
                            await _renameFile(key, name);
                          } else if (v == 'del') {
                            await _deleteFile(key, name);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'open', child: Text('열기')),
                          PopupMenuItem(value: 'dl', child: Text('다운로드')),
                          PopupMenuItem(value: 'rename', child: Text('이름 변경')),
                          PopupMenuItem(value: 'del', child: Text('삭제')),
                        ],
                      ),
                      onTap: () => _download(
                        _nas.eventFile2Url(
                          widget.year,
                          widget.title,
                          key,
                          name,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _uploadFiles(
    String key, {
    List<String> allowedExts = const [],
    String? uploader,
    String sub = '',
    VoidCallback? onDone,
  }) async {
    final state = context.read<AppState>();
    // 사진·동영상(초상 포함) 업로드 시에는 초상 활용 동의를 먼저 확인한다.
    if (key == 'media') {
      final ok = await _confirmPhotoConsent();
      if (ok != true) return;
    }
    final upName =
        uploader ??
        (state.isMaster
            ? '마스터'
            : state.isApp
            ? '관리자'
            : state.who);
    final picked = await pickDataFiles(
      allowedExtensions: allowedExts,
      allowMultiple: true,
      dialogTitle: '파일 선택',
    );
    if (picked.isEmpty) return;
    var done = 0;
    // 공통 "작업중" 오버레이 — 멈춘 것이 아님을 보여준다(업로드 진행률 포함).
    showBusy(
      context,
      title: '사진·동영상 업로드 중입니다',
      lines: [
        'NAS 서버로 파일을 전송하고 있습니다...',
        '총 ${picked.length}개 중 0개 완료',
        '창을 닫지 마세요. 잠시만 기다려 주세요...',
      ],
    );
    for (final p in picked) {
      try {
        updateBusy(
          lines: [
            '전송 중: ${p.name}',
            '총 ${picked.length}개 중 ${done + 1}개 진행 중',
            '완료 $done개 · 남은 ${picked.length - done - 1}개',
          ],
          progress: picked.isEmpty ? null : (done / picked.length),
        );
        await _nas.eventUpload2(
          widget.year,
          widget.title,
          key,
          p.name,
          p.bytes,
          contentType: _contentType(p.name),
          uploader: upName,
          sub: sub,
        );
        done++;
      } catch (e) {
        _snack('업로드 실패: ${p.name} ($e)');
      }
    }
    hideBusy();
    onDone?.call();
    await _load();
  }

  String _contentType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.mp4')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  /// 사진·동영상 업로드 전 초상(사진) 활용 동의 확인 다이얼로그.
  /// (청소년 얼굴이 포함될 수 있어 행사 사진 게시 전 동의를 받는다)
  Future<bool?> _confirmPhotoConsent() {
    bool agreed = false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          icon: const Icon(Icons.photo_camera_front, color: AppColors.purple),
          title: const Text('사진·영상 게시 동의 확인'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '행사 사진·영상에는 참가자(청소년 포함)의 얼굴(초상)이 담길 수 '
                    '있습니다. 게시 전 아래 내용을 확인하고 동의해 주세요.',
                    style: TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.purple.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Text(
                      '· 촬영·게시 목적: 행사 기록·결과 보고·중앙회 홍보\n'
                      '· 게시 범위: 중앙회 앱(인가자 열람)·홈페이지·네이버 카페·소식지\n'
                      '· 동의 철회: 게시 후 삭제 요청 가능(담당자에게 연락)\n'
                      '· 업로드 권한은 인가자(관리자)에게 있으며, 게시 책임은 업로드한 사람에게 있습니다.',
                      style: TextStyle(fontSize: 11.5, height: 1.55),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => setLocal(() => agreed = !agreed),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Checkbox(
                            value: agreed,
                            onChanged: (v) =>
                                setLocal(() => agreed = v ?? false),
                          ),
                          const Expanded(
                            child: Text(
                              '참가자(페런츠 포함)의 초상 활용에 동의하며 게시합니다',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Text(
                    '※ 동의 없이 게시할 수 없습니다. 원하지 않는 참가자는 게시 전 담당자에게 알릴 수 있습니다.',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: agreed ? AppColors.purple : Colors.grey,
              ),
              onPressed: agreed ? () => Navigator.pop(ctx, true) : null,
              child: const Text('동의하고 업로드'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameFile(String key, String name, {String sub = ''}) async {
    final ctrl = TextEditingController(text: name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
        scrollable: true,
        title: const Text('이름 변경'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: '새 이름'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await _nas.eventFileRename(
      widget.year,
      widget.title,
      key,
      name,
      ctrl.text.trim(),
      sub: sub,
    );
    await _load();
  }

  Future<void> _deleteFile(
    String key,
    String name, {
    String sub = '',
    bool isdir = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제'),
        content: Text(isdir ? '“$name” 폴더를 삭제할까요?' : '“$name”을(를) 삭제할까요?'),
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
    if (ok != true) return;
    await _nas.eventFileDelete(
      widget.year,
      widget.title,
      key,
      name,
      sub: sub,
      isdir: isdir,
    );
    await _load();
  }

  /// 행사 QR 코드 표시 — 회원/비회원이 스캔하면 이 행사로 바로 들어온다.
  ///
  /// · 기존 회원: 로그인 후 행사 화면으로 이동
  /// · 비회원: 아이디(신규회원 가입) 후 행사 화면으로 이동
  /// (행사 생성/관리는 관리자만 — 이 메뉴도 canManage 에서만 노출)
  void _showEventQr() {
    final state = context.read<AppState>();
    final payload = state.eventQrLink(widget.year, widget.title);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('행사 QR 코드'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.year} · ${widget.title}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.purple.withValues(alpha: 0.2),
                  ),
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppColors.purple,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: AppColors.purpleDark,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                payload,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.purple,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              if (!state.hasQrBase) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.taegeukRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.taegeukRed.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    '⚠ 공개 접속 주소가 설정되지 않아 QR이 상대경로입니다.\n'
                    '스캔해도 앱이 열리지 않습니다.\n'
                    '설정 → “QR 공개 주소”에서 배포 주소를 입력하세요.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppColors.taegeukRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '회원은 로그인 후, 비회원은 가입 후 이 행사 화면으로 바로 이동합니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: payload));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('행사 QR 링크가 복사되었습니다')),
              );
            },
            child: const Text('링크 복사'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  // ============================ 참석자 ============================
  Widget _attendeeTab() {
    return Column(
      children: [
        // (요구 #13) 참가자 등록은 관리자·마스터만 가능하다.
        if (widget.canManage)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                    ),
                    onPressed: _searchAndAddAttendee,
                    icon: const Icon(Icons.search),
                    label: const Text('인가자 검색'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _manualAddAttendee,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('수동 입력'),
                  ),
                ),
              ],
            ),
          ),
        if (_isStaff && !widget.canManage)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Text(
              '행사 스텝으로 등록되어 참가자 명단을 열람합니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _rosterButton(Icons.table_chart, '명단 출력', () => _openRoster()),
              const SizedBox(width: 6),
              _rosterButton(Icons.sms, '문자', _sendSms),
              const SizedBox(width: 6),
              _rosterButton(Icons.mail, '메일', _sendMail),
              const Spacer(),
              Text(
                '${_attendees.length}명',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: AppColors.textGray),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  '접속 V = 해당 참가자가 사진폴더에 접근한 이력',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _attendees.isEmpty
              ? const Center(
                  child: Text(
                    '참석자를 추가하세요',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                )
              : ListView.builder(
                  itemCount: _attendees.length,
                  itemBuilder: (_, i) => _attendeeTile(i),
                ),
        ),
      ],
    );
  }

  Widget _rosterButton(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _attendeeTile(int i) {
    final a = _attendees[i];
    final ident = '${a['number'] ?? a['phone'] ?? ''}'.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final visited = ident.isNotEmpty && _access.containsKey(ident);
    final roles = (a['roles'] as List?) ?? [];
    // (요구) 소속 구분 뱃지 — 범/은하/일반. 서버가 내려준 corps/linkable 기반.
    final isRegularRow = a['linkable'] != true && '${a['corps'] ?? ''}'.isEmpty;
    final corpLabel = '${a['corps'] ?? ''}' == 'eunha'
        ? '은하'
        : ('${a['corps'] ?? ''}' == 'tsak'
              ? '범'
              : (isRegularRow ? '일반' : '범'));
    final corpColor = '${a['corps'] ?? ''}' == 'eunha'
        ? AppColors.taegeukBlue
        : (isRegularRow ? AppColors.textGray : AppColors.taegeukRed);
    // (요구) 역할 코드 — L(리더)/B(비버)/S(스카우트)/V(벤처)/R(로버)/본부/학부모/기타
    final roleCode = '${a['roleCode'] ?? ''}'.trim();
    final roleLabel = '${a['roleLabel'] ?? ''}'.trim();
    // (요구) 인가번호 우선 노출 — 서버가 준 numberLabel(범#415/은하#43).
    final numLabel = '${a['numberLabel'] ?? ''}'.trim();
    // (요구 #15) STAFF 여부 — 인가번호 옆 STAFF 단추.
    final isStaff = _staff.any(
      (s) =>
          '${s['number'] ?? s['ident'] ?? s['phone'] ?? ''}'.replaceAll(
                RegExp(r'[^0-9]'),
                '',
              ) ==
              ident &&
          ident.isNotEmpty,
    );
    final canManage = widget.canManage;
    // [요구] 회원 등록정보(개인카드) 유무 — 없으면 클릭 시 신규 등록을 유도한다.
    //   서버가 내려준 registered 를 우선하고, 없으면 로컬 저장소로 보정한다.
    final hasCard =
        a['registered'] == true ||
        (canManage && ident.isNotEmpty && context.read<AppState>().byNumber(ident) != null);
    // (요구) 이름 클릭 → 개인카드 연결(관리자·마스터만). 등록정보가 없으면
    //   신규 등록 창을 연다.
    final canOpenCard = canManage && (a['linkable'] == true || hasCard);
    // [요구] 개인카드가 없어도 클릭은 가능해야 한다(신규 등록 유도).
    final canTap = canManage;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: canTap ? () => _openOrRegister(a) : null,
        child: ListTile(
          leading: _attendeeLeading(a, ident, visited, isStaff),
          title: Row(
            children: [
              // 소속 구분 뱃지(범/은하/일반)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: corpColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: corpColor.withValues(alpha: 0.45)),
                ),
                child: Text(
                  corpLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: corpColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // [요구] 이름이 길면 흐르는 글자(마퀴)로 표시 — 폭을 확정(Expanded)
              //   해야 MarqueeText 가 넘침을 감지해 애니메이션을 시작한다.
              Expanded(
                child: InkWell(
                  onTap: canTap ? () => _openOrRegister(a) : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: MarqueeText(
                          '${a['name'] ?? ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            decoration: canOpenCard
                                ? TextDecoration.underline
                                : null,
                          ),
                        ),
                      ),
                      if (canOpenCard) ...[
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.open_in_new,
                          size: 12,
                          color: AppColors.textGray,
                        ),
                      ] else if (canManage) ...[
                        // 등록정보 없음 → 신규 등록 유도 아이콘.
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.person_add_alt_1,
                          size: 12,
                          color: AppColors.tigerGold,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // (요구) 인가번호 우선 노출
              if (numLabel.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  numLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGray,
                  ),
                ),
              ] else if (ident.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  Member.numLabelOf(ident, '${a['corps'] ?? 'tsak'}'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGray,
                  ),
                ),
              ],
              // (요구) 역할 코드(L/B/S/V/R 등) 뱃지
              if (roleCode.isNotEmpty) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    roleLabel.isEmpty || roleLabel == roleCode
                        ? roleCode
                        : '$roleCode $roleLabel',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.purple,
                    ),
                  ),
                ),
              ],
              // STAFF로 지정된 사람만 '스텝' 단추를 부여한다(색상 단추).
              if (isStaff) ...[
                const SizedBox(width: 6),
                _staffButton(a, ident, isStaff),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  // [요구] 활동등록대(unitText)를 우선 표시 — 없으면 인가시 단위대.
                  if ('${a['unitText'] ?? ''}'.trim().isNotEmpty)
                    '${a['unitText']}'
                  else if ('${a['unit'] ?? ''}'.trim().isNotEmpty)
                    '${a['unit']}',
                  // [요구] 개인카드 정보 우선 — 전화·성별(카드가 있으면 카드값).
                  if ('${a['phoneText'] ?? ''}'.trim().isNotEmpty)
                    '${a['phoneText']}'
                  else if ('${a['phone'] ?? ''}'.trim().isNotEmpty)
                    '${a['phone']}',
                  if ('${a['genderText'] ?? ''}'.trim().isNotEmpty)
                    '${a['genderText']}'
                  else if ('${a['gender'] ?? ''}'.trim().isNotEmpty)
                    '${a['gender']}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12),
              ),
              // (요구) 메일주소 — 개인카드(회원 프로필)에서 가져와 작게 병기.
              Builder(
                builder: (_) {
                  final em = '${a['emailText'] ?? ''}'.trim().isNotEmpty
                      ? '${a['emailText']}'
                      : '${a['email'] ?? ''}'.trim();
                  if (em.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      em,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textGray.withValues(alpha: 0.9),
                      ),
                    ),
                  );
                },
              ),
              // (요구) 참가신청 상세정보를 '아주 작은 글씨'로 병기 —
              //   도착예정시간·숙박·이동방법·동행자·전달사항. 없으면 숨김.
              Builder(
                builder: (_) {
                  final bits = <String>[];
                  final arrive = '${a['arriveNote'] ?? ''}'.trim().isNotEmpty
                      ? '${a['arriveNote']}'
                      : '${a['arrive'] ?? ''}'.trim();
                  if (arrive.isNotEmpty) bits.add('⏰ $arrive');
                  final lodge = '${a['lodging'] ?? ''}'.trim();
                  if (lodge.isNotEmpty) bits.add('🛏 $lodge');
                  final tp = '${a['transportNote'] ?? ''}'.trim().isNotEmpty
                      ? '${a['transportNote']}'
                      : '${a['transport'] ?? ''}'.trim();
                  if (tp.isNotEmpty) bits.add('🚗 $tp');
                  final comp = '${a['companion'] ?? ''}'.trim();
                  if (comp.isNotEmpty) bits.add('👥 $comp');
                  final msg = '${a['message'] ?? ''}'.trim();
                  if (msg.isNotEmpty) bits.add('💬 $msg');
                  if (bits.isEmpty) return const SizedBox.shrink();
                  // 넘칠 경우 마퀴(흐리는 글자)로 표시 — 폭을 확정해야 감지된다.
                  return Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: SizedBox(
                      height: 13,
                      child: MarqueeText(
                        bits.join('  ·  '),
                        style: TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textGray.withValues(alpha: 0.95),
                        ),
                        velocity: 18,
                        height: 13,
                      ),
                    ),
                  );
                },
              ),
              // [요구] 회원 등록정보 없음 → 클릭 시 신규 등록을 유도한다.
              if (canManage && !hasCard)
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Text(
                    '미등록 — 클릭하여 신규 회원 등록',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.tigerGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (roles.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: [
                    for (final r in roles)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$r',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.purple,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          trailing: widget.canManage
              ? PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await _manualAddAttendee(editIndex: i);
                    } else if (v == 'del') {
                      // (요구) 삭제 전 한 번 더 확인.
                      final ok = await confirmDialog(
                        context,
                        title: '참가자 삭제',
                        message: '${a['name'] ?? ''} 님을 참가자 명단에서 삭제할까요?',
                      );
                      if (!ok) return;
                      setState(() => _attendees.removeAt(i));
                      await _saveAttendees();
                    } else if (v == 'top') {
                      await _moveAttendee(i, 0);
                    } else if (v == 'up') {
                      if (i > 0) await _moveAttendee(i, i - 1);
                    } else if (v == 'down') {
                      if (i < _attendees.length - 1) {
                        await _moveAttendee(i, i + 1);
                      }
                    } else if (v == 'role') {
                      await _editAttendeeRole(i);
                    } else if (v == 'card') {
                      await _openOrRegister(a);
                    } else if (v == 'register') {
                      await _openOrRegister(a);
                    }
                  },
                  itemBuilder: (_) => [
                    if (hasCard)
                      const PopupMenuItem(
                        value: 'card',
                        child: Text('개인카드 열기'),
                      )
                    else
                      // [요구] 등록정보가 없으면 신규 회원 등록을 유도한다.
                      const PopupMenuItem(
                        value: 'register',
                        child: Text('신규 회원 등록'),
                      ),
                    const PopupMenuItem(value: 'edit', child: Text('정보 수정')),
                    const PopupMenuItem(value: 'role', child: Text('항목(역할) 변경')),
                    const PopupMenuItem(value: 'top', child: Text('맨 위로')),
                    const PopupMenuItem(value: 'up', child: Text('위로 이동')),
                    const PopupMenuItem(value: 'down', child: Text('아래로 이동')),
                    const PopupMenuItem(value: 'del', child: Text('삭제')),
                  ],
                )
              : const Icon(Icons.chevron_right, color: AppColors.textGray),
        ),
      ),
    );
  }

  /// (요구) 명단 관리 — 위치 변경(로컬 순서 조정 후 저장).
  Future<void> _moveAttendee(int from, int to) async {
    if (from < 0 || from >= _attendees.length) return;
    final item = _attendees.removeAt(from);
    _attendees.insert(to.clamp(0, _attendees.length), item);
    setState(() {});
    await _saveAttendees();
  }

  /// (요구) 명단 관리 — 항목(역할) 변경. L/B/S/V/R 등 코드로 표시된다.
  Future<void> _editAttendeeRole(int i) async {
    if (i < 0 || i >= _attendees.length) return;
    final cur = ((_attendees[i]['rawRoles'] as List?) ??
            (_attendees[i]['roles'] as List?) ??
            [])
        .map((e) => '$e')
        .toSet();
    const all = [
      '지도자',
      '비버',
      '스카우트',
      '벤처',
      '로버',
      '본부',
      '학부모',
      '기타',
    ];
    final sel = {...cur};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('항목(역할) 변경'),
          content: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in all)
                FilterChip(
                  label: Text(r),
                  selected: sel.contains(r),
                  selectedColor: AppColors.purple,
                  labelStyle: TextStyle(
                    color: sel.contains(r) ? Colors.white : AppColors.purple,
                  ),
                  onSelected: (v) =>
                      setD(() => v ? sel.add(r) : sel.remove(r)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    _attendees[i]['roles'] = sel.toList();
    // 표시용 코드도 즉시 갱신(서버 재조회 전 화면 반영)
    bool has(List<String> ks) => ks.any((k) => sel.any((s) => s.contains(k)));
    String code = '';
    if (has(['지도자', '멘토', '리더'])) {
      code = 'L';
    } else if (has(['비버'])) {
      code = 'B';
    } else if (has(['벤처'])) {
      code = 'V';
    } else if (has(['로버'])) {
      code = 'R';
    } else if (has(['스카우트'])) {
      code = 'S';
    } else if (has(['본부'])) {
      code = '본부';
    } else if (has(['학부모'])) {
      code = '학부모';
    } else if (sel.isNotEmpty) {
      code = '기타';
    }
    _attendees[i]['roleCode'] = code;
    setState(() {});
    await _saveAttendees();
  }

  /// 참가자 타일 좌측(leading).
  ///  - 접속 여부(V)는 항상 표시(접속기록 유지).
  ///  - 관리자·마스터에게는 그 위에 STAFF 지정 체크박스를 추가로 노출한다.
  Widget _attendeeLeading(
    Map<String, dynamic> a,
    String ident,
    bool visited,
    bool isStaff,
  ) {
    final canStaff = widget.canManage && ident.isNotEmpty;
    return SizedBox(
      width: 34,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (canStaff) ...[
            // STAFF 지정 체크박스 (마스터·관리자 전용) — 보라색 마크
            GestureDetector(
              onTap: () => _toggleStaff(a, ident, isStaff),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isStaff ? AppColors.purple : Colors.white,
                  border: Border.all(
                    color: isStaff ? AppColors.purple : Colors.grey.shade400,
                    width: isStaff ? 2 : 1.4,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: isStaff
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(height: 1),
          ],
          // 접속 여부(V) — 삭제하지 않고 항상 유지
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: visited ? AppColors.scoutGreen : Colors.transparent,
              border: Border.all(
                color: visited ? AppColors.scoutGreen : Colors.grey.shade300,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: visited
                ? const Text(
                    'V',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 1),
          Text(
            '접속',
            style: TextStyle(
              fontSize: 8.5,
              color: visited ? AppColors.scoutGreen : AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }

  /// STAFF(스텝)로 지정된 사람에게 부여되는 색상 단추(작게).
  ///  - 관리자·마스터: 눌러서 해제 가능.
  ///  - 그 외: 지정 사실만 표시(비활성).
  Widget _staffButton(Map<String, dynamic> a, String ident, bool isStaff) {
    final canToggle = widget.canManage && ident.isNotEmpty;
    return GestureDetector(
      onTap: canToggle ? () => _toggleStaff(a, ident, isStaff) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.purple, AppColors.purpleDark],
          ),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.purpleDark),
        ),
        child: const Text(
          '스텝',
          style: TextStyle(
            fontSize: 8.5,
            height: 1.1,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleStaff(
    Map<String, dynamic> a,
    String ident,
    bool isStaff,
  ) async {
    if (!widget.canManage) return;
    try {
      final list = isStaff
          ? await _nas.eventStaffRemove(
              year: widget.year,
              title: widget.title,
              number: ident,
            )
          : await _nas.eventStaffAdd(
              year: widget.year,
              title: widget.title,
              number: ident,
            );
      if (!mounted) return;
      setState(() => _staff = list);
      _snack(isStaff ? '스텝에서 해제했습니다' : '행사 스텝(STAFF)으로 등록했습니다');
    } catch (e) {
      _snack('처리 실패: $e');
    }
  }

  /// 참가자 항목 → 회원(개인카드) 조회. 인가번호/전화번호/이름 순으로 시도한다.
  Member? _resolveMember(AppState s, Map<String, dynamic> a, String ident) {
    Member? m = ident.isNotEmpty ? s.byNumber(ident) : null;
    if (m == null) {
      final ph = '${a['phone'] ?? a['loginId'] ?? ''}'.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      if (ph.isNotEmpty) m = s.byNumber(ph);
    }
    final nm = '${a['name'] ?? ''}'.trim();
    if (m == null && nm.isNotEmpty) m = s.byName(nm);
    return m;
  }

  /// [요구] 참가자 이름 클릭:
  ///  · 개인카드(등록정보)가 있으면 → 개인카드 열기.
  ///  · 등록정보가 없으면 → '신규 회원 등록할까요?' 확인 후, 등록 창을 열어
  ///    이름·전화번호를 미리 채운다. (일반회원 신규 등록)
  Future<void> _openOrRegister(Map<String, dynamic> a) async {
    if (!widget.canManage) return;
    final s = context.read<AppState>();
    final ident = '${a['number'] ?? a['phone'] ?? a['loginId'] ?? ''}'
        .replaceAll(RegExp(r'[^0-9]'), '');
    final m = _resolveMember(s, a, ident);
    if (m != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MemberDetailScreen(memberId: m.id)),
      );
      if (mounted) _load();
      return;
    }
    // ---- 등록정보 없음 → 신규 회원 등록 유도 ----
    final nm = '${a['name'] ?? ''}'.trim();
    final ph = '${a['phone'] ?? a['loginId'] ?? a['number'] ?? ''}'.trim();
    // 인가자(범/은하)면 인가자로, 그 외(일반)면 일반회원으로 등록한다.
    final isRegular = '${a['corps'] ?? ''}'.isEmpty && a['linkable'] != true;
    final ok = await confirmDialog(
      context,
      title: '신규 회원 등록',
      message:
          '${nm.isEmpty ? '이 참가자' : nm}'
          '${ph.isNotEmpty ? ' ($ph)' : ''} 님은 등록된 회원 정보가 없습니다.\n\n'
          '${isRegular ? '일반회원(비인가)' : '인가자'}로 신규 등록할까요?',
      confirmLabel: '신규 등록',
      cancelLabel: '취소',
      danger: false,
    );
    if (!ok || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberEditScreen(
          registerAsRegular: isRegular,
          prefillName: nm,
          prefillPhone: ph,
          prefillUnit: '${a['unitText'] ?? a['unit'] ?? ''}'.trim(),
          prefillEmail: '${a['emailText'] ?? a['email'] ?? ''}'.trim(),
        ),
      ),
    );
    if (mounted) _load();
  }

  /// (요구 #14) 행사 스텝(STAFF) 등록 — 관리자·마스터만. 인가자 검색 후 스텝 등록.
  Future<void> _manageStaff() async {
    if (!widget.canManage) return;
    final ctrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = false;
    String errMsg = '';
    List<Map<String, dynamic>> staff = List.from(_staff);

    Future<void> doSearch(StateSetter setD) async {
      setD(() => loading = true);
      try {
        results = await _nas.eventSearchMember(ctrl.text.trim(), limit: 60);
        errMsg = '';
      } catch (e) {
        errMsg = '검색 실패: $e';
      }
      setD(() => loading = false);
    }

    if (mounted) setState(() => _loading); // no-op 유지
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) {
            doSearch(setD);
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.engineering, color: AppColors.purple),
                  SizedBox(width: 8),
                  Text('행사 스텝(STAFF) 등록'),
                ],
              ),
              content: SizedBox(
                width: 400,
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '스텝으로 등록하면 해당 행사의 모든 게시판이 노출됩니다.',
                      style: TextStyle(fontSize: 12, color: AppColors.textGray),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        labelText: '인가번호 / 이름 / 소속',
                        isDense: true,
                      ),
                      onSubmitted: (_) => doSearch(setD),
                    ),
                    const SizedBox(height: 6),
                    if (staff.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in staff)
                            Chip(
                              avatar: const Icon(Icons.engineering, size: 15),
                              label: Text(
                                '${s['name'] ?? ''} ${Member.numLabelOf('${s['number'] ?? s['ident'] ?? ''}', '${s['corps'] ?? 'tsak'}')}',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              onDeleted: () async {
                                final list = await _nas.eventStaffRemove(
                                  year: widget.year,
                                  title: widget.title,
                                  number: '${s['number'] ?? s['ident'] ?? ''}',
                                );
                                setD(() => staff = List.from(list));
                                if (mounted) setState(() => _staff = list);
                              },
                            ),
                        ],
                      ),
                    const Divider(height: 16),
                    if (errMsg.isNotEmpty)
                      Text(
                        errMsg,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (_, i) {
                                final r = results[i];
                                final num = '${r['number'] ?? ''}'.replaceAll(
                                  RegExp(r'[^0-9]'),
                                  '',
                                );
                                final already = staff.any(
                                  (s) =>
                                      '${s['number'] ?? s['ident'] ?? ''}'
                                          .replaceAll(RegExp(r'[^0-9]'), '') ==
                                      num,
                                );
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.person_outline),
                                  title: Text(
                                    '${r['name']} · ${Member.numLabelOf('${r['number'] ?? ''}', '${r['corps'] ?? 'tsak'}')}',
                                  ),
                                  subtitle: Text(
                                    '${r['unit'] ?? ''}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: already
                                      ? const Text(
                                          '등록됨',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.scoutGreen,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add_circle_outline,
                                          color: AppColors.purple,
                                        ),
                                  onTap: already
                                      ? null
                                      : () async {
                                          final list = await _nas.eventStaffAdd(
                                            year: widget.year,
                                            title: widget.title,
                                            number: '${r['number']}',
                                          );
                                          setD(() => staff = List.from(list));
                                          if (mounted) {
                                            setState(() => _staff = list);
                                          }
                                        },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        ),
      );
      if (mounted) _load();
    }
  }

  Future<void> _saveAttendees() async {
    await _nas.eventSetAttendees(widget.year, widget.title, _attendees);
    await _load();
  }

  /// 인가자 다중 검색 & 일괄 추가.
  /// - 한 번에 여러 명을 체크해 추가(반복 입력 불필요).
  /// - 검색어가 비어 있으면 최근/전체 목록을 보여주고, 항목 선택 시 일괄 적용.
  Future<void> _searchAndAddAttendee() async {
    final ctrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    final checked = <String, Map<String, dynamic>>{}; // number -> member
    bool loading = false;
    String errMsg = '';

    Future<void> doSearch(StateSetter setD) async {
      loading = true;
      errMsg = '';
      setD(() {});
      try {
        final q = ctrl.text.trim();
        results = await _nas.eventSearchMember(q.isEmpty ? '' : q, limit: 60);
        // 이미 명단에 있는 사람 표시용 집합
      } catch (e) {
        errMsg = '검색 실패: $e';
      }
      loading = false;
      setD(() {});
    }

    final existing = <String>{
      for (final a in _attendees)
        '${a['number'] ?? ''}${a['phone'] ?? ''}${a['loginId'] ?? ''}'
            .replaceAll(RegExp(r'[^0-9]'), ''),
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(
            children: [
              const Text('인가자 검색 · 일괄추가'),
              const Spacer(),
              Text(
                '${checked.length}명 선택',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.purple,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 380,
            height: 480,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: '인가번호 / 이름 / 소속 (비우면 전체)',
                          isDense: true,
                        ),
                        onSubmitted: (_) => doSearch(setD),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: () => doSearch(setD),
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
                if (errMsg.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      errMsg,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 6),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : results.isEmpty
                      ? const Center(
                          child: Text(
                            '검색어를 입력하고 검색하세요',
                            style: TextStyle(color: AppColors.textGray),
                          ),
                        )
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final r = results[i];
                            final num = '${r['number'] ?? ''}'.replaceAll(
                              RegExp(r'[^0-9]'),
                              '',
                            );
                            final already =
                                existing.contains(num) ||
                                checked.containsKey(num);
                            return CheckboxListTile(
                              dense: true,
                              value: checked.containsKey(num),
                              onChanged: already && !checked.containsKey(num)
                                  ? null
                                  : (v) {
                                      setD(() {
                                        if (v == true) {
                                          checked[num] = r;
                                        } else {
                                          checked.remove(num);
                                        }
                                      });
                                    },
                              title: Text(
                                '${r['name']} · ${Member.numLabelOf('${r['number'] ?? ''}', '${r['corps'] ?? 'tsak'}')}',
                              ),
                              subtitle: Text(
                                '${already ? '이미 등록됨 · ' : ''}${r['unit'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: already ? AppColors.textGray : null,
                                ),
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                checked.clear();
                await doSearch(setD);
              },
              child: const Text('전체 보기'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton.icon(
              onPressed: checked.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.playlist_add_check),
              label: Text('선택 ${checked.length}명 추가'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || checked.isEmpty) return;

    // 일괄 항목(roles) 선택
    final roles = await _pickRoles();
    if (roles == null) return;

    final picks = checked.values.map((r) {
      return {
        'number': '${r['number']}',
        'name': '${r['name']}',
        'unit': '${r['unit']}',
        'league': '${r['league']}',
        'phone': '${r['phone']}',
        'roles': roles,
      };
    }).toList();

    try {
      final res = await _nas.eventAttendeesAdd(
        widget.year,
        widget.title,
        picks,
      );
      final added = res['added'] ?? 0;
      final skipped = res['skipped'] ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped > 0 ? '$added명 추가 완료 (중복 $skipped명 건너뜀)' : '$added명 추가 완료',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('추가 실패: $e')));
    }
  }

  Future<List<String>?> _pickRoles() async {
    const all = ['지도자', '멘토지도자', '비버', '스카우트', '벤처', '로버', '본부', '학부모', '기타'];
    final sel = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('항목 선택 (복수 가능)'),
          content: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in all)
                FilterChip(
                  label: Text(r),
                  selected: sel.contains(r),
                  selectedColor: AppColors.purple,
                  labelStyle: TextStyle(
                    color: sel.contains(r) ? Colors.white : AppColors.purple,
                  ),
                  onSelected: (v) => setD(() => v ? sel.add(r) : sel.remove(r)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, sel.toList()),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manualAddAttendee({int? editIndex}) async {
    final cur = editIndex != null ? _attendees[editIndex] : null;
    final nameC = TextEditingController(text: '${cur?['name'] ?? ''}');
    final unitC = TextEditingController(text: '${cur?['unit'] ?? ''}');
    final genderC = TextEditingController(text: '${cur?['gender'] ?? ''}');
    final phoneC = TextEditingController(text: '${cur?['phone'] ?? ''}');
    final emailC = TextEditingController(text: '${cur?['email'] ?? ''}');
    final addrC = TextEditingController(text: '${cur?['address'] ?? ''}');
    final numC = TextEditingController(text: '${cur?['number'] ?? ''}');
    final roles = <String>{
      ...((cur?['roles'] as List?)?.map((e) => '$e') ?? []),
    };
    const all = ['지도자', '멘토지도자', '비버', '스카우트', '벤처', '로버', '본부', '학부모', '기타'];
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
          scrollable: true,
          title: Text(editIndex != null ? '참석자 수정' : '참석자 수동 입력'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameC,
                    decoration: const InputDecoration(labelText: '이름 *'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: unitC,
                    decoration: const InputDecoration(labelText: '소속'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: numC,
                    decoration: const InputDecoration(labelText: '인가번호 (인가자만)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: genderC,
                    decoration: const InputDecoration(labelText: '성별'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneC,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: '연락처'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailC,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '메일주소'),
                  ),
                  const SizedBox(height: 8),
                  AddressField(
                    controller: addrC,
                    label: '주소',
                    hint: '주소검색 버튼으로 검색하세요',
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '항목 (복수 선택)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in all)
                        FilterChip(
                          label: Text(r),
                          selected: roles.contains(r),
                          selectedColor: AppColors.purple,
                          labelStyle: TextStyle(
                            color: roles.contains(r)
                                ? Colors.white
                                : AppColors.purple,
                          ),
                          onSelected: (v) =>
                              setD(() => v ? roles.add(r) : roles.remove(r)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    if (nameC.text.trim().isEmpty) {
      _snack('이름을 입력하세요');
      return;
    }
    final row = {
      'number': numC.text.trim(),
      'name': nameC.text.trim(),
      'unit': unitC.text.trim(),
      'gender': genderC.text.trim(),
      'phone': phoneC.text.trim(),
      'email': emailC.text.trim(),
      'address': addrC.text.trim(),
      'roles': roles.toList(),
    };
    setState(() {
      if (editIndex != null) {
        _attendees[editIndex] = row;
      } else {
        _attendees.add(row);
      }
    });
    await _saveAttendees();
  }

  // ============================ 사진+동영상 ============================
  static const List<String> _mediaExts = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'mp4',
    'mov',
    'webm',
  ];

  Widget _mediaTab() {
    final folders = _media.where((m) => m['isdir'] == true).toList();
    final files = _media.where((m) => m['isdir'] != true).toList();
    return Column(
      children: [
        // ---- 브레드크럼 (하위폴더 탐색) ----
        if (_mediaPath.isNotEmpty)
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: HScrollMenu(
              height: 30,
              child: Row(
                children: [
                  _crumb(
                    '사진+동영상',
                    () => setState(() {
                      _mediaPath = [];
                      _mediaSel.clear();
                      _load();
                    }),
                  ),
                  for (var i = 0; i < _mediaPath.length; i++) ...[
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.textGray,
                    ),
                    _crumb(
                      _mediaPath[i],
                      i == _mediaPath.length - 1
                          ? null
                          : () => setState(() {
                              _mediaPath = _mediaPath.sublist(0, i + 1);
                              _mediaSel.clear();
                              _load();
                            }),
                    ),
                  ],
                ],
              ),
            ),
          ),
        // ---- 업로드 / 폴더 / 선택 툴바 ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                  ),
                  onPressed: () => _uploadFiles(
                    'media',
                    allowedExts: _mediaExts,
                    sub: _mediaSub,
                  ),
                  icon: const Icon(Icons.add_photo_alternate),
                  label: Text(_mediaPath.isEmpty ? '사진/동영상 올리기' : '이 폴더에 올리기'),
                ),
              ),
              const SizedBox(width: 8),
              // 새 폴더 만들기
              IconButton(
                tooltip: '새 폴더 만들기',
                onPressed: _createMediaFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              // 열 수 조절 (−/열수/+): 핀치 줌이 안 되는 PC·마우스 환경 지원
              IconButton(
                tooltip: '열 줄이기 (사진 확대)',
                visualDensity: VisualDensity.compact,
                onPressed: _cols > 1
                    ? () => setState(() => _cols = (_cols - 1).clamp(1, 10))
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$_cols열',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                tooltip: '열 늘리기 (사진 축소)',
                visualDensity: VisualDensity.compact,
                onPressed: _cols < 10
                    ? () => setState(() => _cols = (_cols + 1).clamp(1, 10))
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              // 선택 모드 토글 (항목 있을 때만)
              if (files.isNotEmpty || folders.isNotEmpty)
                IconButton(
                  tooltip: _mediaSelect ? '선택 취소' : '선택',
                  onPressed: () => setState(() {
                    _mediaSelect = !_mediaSelect;
                    if (!_mediaSelect) _mediaSel.clear();
                  }),
                  icon: Icon(
                    _mediaSelect ? Icons.close : Icons.check_circle_outline,
                    color: _mediaSelect ? AppColors.taegeukRed : null,
                  ),
                ),
              // 그리드 열 선택 (1~5열)
              PopupMenuButton<int>(
                tooltip: '그리드',
                icon: const Icon(Icons.grid_view),
                onSelected: (v) => setState(() => _cols = v),
                itemBuilder: (_) => [
                  for (var i = 1; i <= 10; i++)
                    PopupMenuItem(
                      value: i,
                      child: Row(
                        children: [
                          if (_cols == i)
                            const Icon(
                              Icons.check,
                              size: 16,
                              color: AppColors.purple,
                            ),
                          Text('$i열'),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // ---- 다운로드 바 ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _media.isEmpty
                      ? null
                      : () => _download(
                          _nas.eventZipUrl(
                            widget.year,
                            widget.title,
                            'media',
                            sub: _mediaSub,
                          ),
                        ),
                  icon: const Icon(Icons.download),
                  label: const Text('전체 다운로드'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _mediaSel.isEmpty
                        ? Colors.grey
                        : AppColors.scoutGreen,
                  ),
                  onPressed: _mediaSelect && _mediaSel.isNotEmpty
                      ? _downloadSelectedMedia
                      : null,
                  icon: const Icon(Icons.check_circle),
                  label: Text('선택 다운로드 (${_mediaSel.length})'),
                ),
              ),
              if (_mediaSelect && _mediaSel.isNotEmpty && widget.canManage) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.taegeukRed,
                    ),
                    onPressed: _deleteSelectedMedia,
                    icon: const Icon(Icons.delete_outline),
                    label: Text('선택 삭제 (${_mediaSel.length})'),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _media.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '사진·동영상을 올려주세요',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: _createMediaFolder,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('새 폴더 만들기'),
                      ),
                    ],
                  ),
                )
              : GestureDetector(
                  // 핀치(두 손가락) 확대/축소 → 이미지 열 수 조절 (1~10열, 아이폰식)
                  onScaleStart: (_) => _pinchBaseCols = _cols,
                  onScaleUpdate: (d) {
                    if (d.pointerCount < 2 || d.scale == 0) return;
                    // 확대(scale>1)하면 열이 줄어 이미지가 커지고, 축소하면 열이 늘어남
                    final target = (_pinchBaseCols / d.scale).round();
                    final clamped = target.clamp(1, 10);
                    if (clamped != _cols) setState(() => _cols = clamped);
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _cols,
                      mainAxisSpacing: _cols > 5 ? 3 : 6,
                      crossAxisSpacing: _cols > 5 ? 3 : 6,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: _media.length,
                    itemBuilder: (_, i) => _mediaTile(i),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _crumb(String label, VoidCallback? onTap) {
    final isLast = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isLast ? FontWeight.w800 : FontWeight.w600,
          color: isLast ? AppColors.purple : AppColors.textGray,
        ),
      ),
    );
  }

  Future<void> _createMediaFolder() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
        scrollable: true,
        title: const Text('새 폴더 만들기'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '폴더 이름',
            hintText: _mediaPath.isEmpty ? '예: 1일차, 단체사진' : '하위 폴더',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('만들기'),
          ),
        ],
      ),
    );
    final name = ctrl.text.trim();
    if (ok != true || name.isEmpty) return;
    final done = await _nas.eventMediaMkdir(
      widget.year,
      widget.title,
      'media',
      name,
      sub: _mediaSub,
    );
    if (!done) _snack('폴더 생성 실패');
    await _load();
  }

  void _enterFolder(String name) {
    setState(() {
      _mediaPath = [..._mediaPath, name];
      _mediaSel.clear();
    });
    // 폴더 진입: 썸네일·최적화본을 미리 만들며 불러오는 중임을 안내.
    _showMediaBusy('사진 폴더를 여는 중입니다');
    _load();
  }

  /// 사진/동영상 목록 로딩 중 공통 오버레이(멈춤 아님 안내).
  void _showMediaBusy(String title) {
    if (!mounted) return;
    showBusy(
      context,
      title: title,
      lines: [
        'NAS 서버에서 목록을 불러오고 있습니다...',
        '썸네일·최적화 이미지를 준비하는 중...',
        '잠시만 기다려 주세요...',
      ],
    );
  }

  /// 선택 항목 토큰 ('현재폴더 파일'=name, '하위폴더 파일'=segSub:name)
  void _downloadSelectedMedia() {
    if (_mediaSel.isEmpty) return;
    final tokens = _mediaSel.toList();
    _download(
      _nas.eventZipUrl(
        widget.year,
        widget.title,
        'media',
        sub: _mediaSub,
        files: tokens,
      ),
    );
  }

  /// 선택한 사진/동영상 일괄 삭제 (선택 모드)
  Future<void> _deleteSelectedMedia() async {
    if (_mediaSel.isEmpty) return;
    final items = _media
        .where((m) => _mediaSel.contains('${m['name']}'))
        .toList();
    final hasDir = items.any((m) => m['isdir'] == true);
    final n = _mediaSel.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('선택 삭제'),
        content: Text(
          hasDir
              ? '선택한 $n개 항목(폴더 포함)을 삭제할까요?\n폴더는 안의 내용까지 모두 삭제됩니다.'
              : '선택한 $n개 항목을 삭제할까요?',
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
    if (ok != true) return;

    var fail = 0;
    for (final m in items) {
      final name = '${m['name']}';
      final isdir = m['isdir'] == true;
      try {
        final done = await _nas.eventFileDelete(
          widget.year,
          widget.title,
          'media',
          name,
          sub: _mediaSub,
          isdir: isdir,
        );
        if (done != true) fail++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() {
      _mediaSel.clear();
      _mediaSelect = false;
    });
    await _load();
    _snack(fail == 0 ? '선택한 항목을 삭제했습니다' : '$fail개 삭제 실패');
  }

  Widget _mediaTile(int i) {
    final m = _media[i];
    final name = '${m['name']}';
    final isDir = m['isdir'] == true;
    final kind = '${m['kind'] ?? 'image'}';
    final uploader = _uploaderLabel('${m['uploader'] ?? ''}');
    final selected = _mediaSel.contains(name);
    final thumbUrl = _nas.eventThumb2Url(
      widget.year,
      widget.title,
      name,
      sub: _mediaSub,
    );
    // 화면 폭/열 수에 맞춰 디코딩 크기를 제한 → 메모리·디코딩 비용 절감(로딩 가속).
    final cacheW =
        ((MediaQuery.of(context).size.width / _cols) *
                MediaQuery.of(context).devicePixelRatio)
            .round()
            .clamp(60, 2048);

    if (isDir) {
      final cnt = m['count'] ?? 0;
      return RepaintBoundary(
        child: GestureDetector(
          onTap: () => _enterFolder(name),
          onLongPress: () => _mediaFolderMenu(name),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3EEFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder, size: 40, color: AppColors.purple),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: MarqueeText(
                    name,
                    maxLines: 1,
                    align: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$cnt개',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textGray,
                  ),
                ),
                if (((m['sizeTotal'] as num?)?.toInt() ?? 0) > 0)
                  Text(
                    _fmtSize((m['sizeTotal'] as num).toInt()),
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.purple.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 2),
                MarqueeText(
                  _uploaderLabel('${m['uploader'] ?? ''}'),
                  maxLines: 1,
                  align: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          if (_mediaSelect) {
            setState(() {
              if (selected) {
                _mediaSel.remove(name);
              } else {
                _mediaSel.add(name);
              }
            });
          } else {
            _openViewer(i);
          }
        },
        onLongPress: () {
          setState(() {
            _mediaSelect = true;
            _mediaSel.add(name);
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (kind == 'video')
                      Image.network(
                        thumbUrl,
                        fit: BoxFit.cover,
                        cacheWidth: cacheW,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.black87,
                          child: const Icon(
                            Icons.videocam,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      )
                    else
                      Image.network(
                        thumbUrl,
                        fit: BoxFit.cover,
                        cacheWidth: cacheW,
                        loadingBuilder: (_, child, prog) => prog == null
                            ? child
                            : Container(
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image, size: 28),
                        ),
                      ),
                    if (kind == 'video')
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    // 선택 표시
                    if (_mediaSelect)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.scoutGreen
                                : Colors.black38,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            selected ? Icons.check : Icons.circle_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 업로더 이름 (사진 아래, 구글포토식)
            const SizedBox(height: 2),
            MarqueeText(
              uploader,
              maxLines: 1,
              align: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textGray,
                fontWeight: FontWeight.w600,
              ),
            ),
            // 사진·동영상 용량(사용자가 열어볼지 결정하는 데 도움)
            Builder(
              builder: (_) {
                final sz = (m['size'] as num?)?.toInt() ?? 0;
                if (sz <= 0) return const SizedBox.shrink();
                return Text(
                  _fmtSize(sz),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: AppColors.purple.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mediaFolderMenu(String name) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('이 폴더 전체 다운로드 (ZIP)'),
              onTap: () => Navigator.pop(ctx, 'zip'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('이름 변경'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.taegeukRed,
              ),
              title: const Text(
                '폴더 삭제',
                style: TextStyle(color: AppColors.taegeukRed),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (v == 'zip') {
      _download(
        _nas.eventZipUrl(
          widget.year,
          widget.title,
          'media',
          sub: _mediaSub.isEmpty ? name : '$_mediaSub/$name',
        ),
      );
    } else if (v == 'rename') {
      await _renameFile('media', name, sub: _mediaSub);
    } else if (v == 'delete') {
      await _deleteFile('media', name, sub: _mediaSub, isdir: true);
    }
  }

  void _openViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MediaViewer(
          year: widget.year,
          title: widget.title,
          sub: _mediaSub,
          items: _media.where((m) => m['isdir'] != true).toList(),
          initialIndex: index,
          canDeleteAll: widget.canManage,
          myName: _uploaderName(),
        ),
      ),
    ).then((_) => _load());
  }

  String _uploaderName() {
    final s = context.read<AppState>();
    if (s.isMaster) return '마스터';
    if (s.isApp) return '관리자';
    if (s.who.isNotEmpty) {
      // 인가번호가 아닌 '이름'으로 기록 (사진 올린 사람 이름 표시)
      final m = s.repo.byNumber(s.who);
      if (m != null && m.name.isNotEmpty) return m.name;
      return s.who;
    }
    return '참가자';
  }

  /// 사진/폴더에 표시할 업로더 라벨.
  ///
  /// - 개별 파일 메타에 업로더가 있으면 → 이름으로 변환(인가번호면 회원명)
  /// - 업로더 정보가 없으면(예: 폴더째 올린 사진) → '415호' 로 일괄 표시
  String _uploaderLabel(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '415호';
    if (v == '마스터' || v == '관리자' || v == '참가자') return v;
    final m = context.read<AppState>().repo.byNumber(v);
    if (m != null && m.name.isNotEmpty) return m.name;
    return v;
  }

  // ============================ 재무(참가비/후원금·지출) ============================
  Widget _financeTab(String kind) {
    final rows = kind == 'fee' ? _fees : _expenses;
    final title = kind == 'fee' ? '참가비 / 후원금 납부자' : '행사비 지출내역';
    return Column(
      children: [
        // 참가비·후원금 항목 상단: 납부 계좌 3개 + 송금 버튼
        if (kind == 'fee')
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: DonationAccounts(title: '참가비·후원 납부 계좌', showHolder: true),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kind == 'fee'
                        ? AppColors.scoutGreen
                        : AppColors.taegeukRed,
                  ),
                  onPressed: () => _financeEdit(kind),
                  icon: const Icon(Icons.add),
                  label: Text('$title 추가'),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.sync, size: 13, color: AppColors.scoutGreen),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  '재무관리와 자동 연동됩니다 (입력·수정·삭제 시 함께 반영)',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text(
                    '내역이 없습니다',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final amt = (r['amount'] as num?)?.toInt() ?? 0;
                    final isFee = kind == 'fee';
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: ListTile(
                        leading: Icon(
                          isFee ? Icons.volunteer_activism : Icons.payments,
                          color: isFee
                              ? AppColors.scoutGreen
                              : AppColors.taegeukRed,
                        ),
                        title: Text('${r['name'] ?? ''}'),
                        subtitle: Text(
                          '${r['date'] ?? ''}'
                          '${'${r['category'] ?? ''}'.isNotEmpty ? ' · ${r['category']}' : ''}'
                          '${'${r['memo'] ?? ''}'.isNotEmpty ? ' · ${r['memo']}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _won(amt),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  await _financeEdit(kind, row: r);
                                } else if (v == 'del') {
                                  await _nas.eventFinanceDelete(
                                    widget.year,
                                    widget.title,
                                    kind,
                                    '${r['id']}',
                                  );
                                  await _load();
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('수정')),
                                PopupMenuItem(value: 'del', child: Text('삭제')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _financeEdit(String kind, {Map<String, dynamic>? row}) async {
    final nameC = TextEditingController(text: '${row?['name'] ?? ''}');
    final numC = TextEditingController(text: '${row?['number'] ?? ''}');
    final amtC = TextEditingController(
      text: row != null ? '${row['amount'] ?? ''}' : '',
    );
    final dateC = TextEditingController(text: '${row?['date'] ?? _today()}');
    final memoC = TextEditingController(text: '${row?['memo'] ?? ''}');
    String category = '${row?['category'] ?? (kind == 'fee' ? '참가비' : '행사비')}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(kind == 'fee' ? '참가비/후원금 입력' : '행사비 지출 입력'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: '이름/납부자 *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: numC,
                  decoration: const InputDecoration(labelText: '인가번호(선택)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amtC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '금액 *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: dateC,
                  decoration: const InputDecoration(
                    labelText: '날짜 (예: 2026-03-14)',
                  ),
                ),
                if (kind == 'fee') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: '구분'),
                    items: const [
                      DropdownMenuItem(value: '참가비', child: Text('참가비')),
                      DropdownMenuItem(value: '후원', child: Text('후원')),
                      DropdownMenuItem(value: '후원금', child: Text('후원금')),
                      DropdownMenuItem(value: '기타', child: Text('기타')),
                    ],
                    onChanged: (v) => setD(() => category = v ?? category),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: memoC,
                  decoration: const InputDecoration(labelText: '메모'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (nameC.text.trim().isEmpty || amtC.text.trim().isEmpty) {
      _snack('이름과 금액을 입력하세요');
      return;
    }
    final data = {
      'name': nameC.text.trim(),
      'number': numC.text.trim(),
      'amount': int.tryParse(amtC.text.trim()) ?? 0,
      'date': dateC.text.trim(),
      'category': kind == 'fee' ? category : '행사비',
      'memo': memoC.text.trim(),
    };
    final isNew = row == null || '${row['id']}'.isEmpty;
    if (isNew) {
      await _nas.eventFinanceAdd(widget.year, widget.title, kind, data);
    } else {
      await _nas.eventFinanceUpdate(
        widget.year,
        widget.title,
        kind,
        '${row['id']}',
        data,
      );
    }
    await _load();
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  // ============================ 부가 기능 ============================
  Future<void> _requestPhoto() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('사진 업로드 요청'),
        content: const Text(
          '모든 참가자에게 이 행사의 사진 업로드를 요청합니다.\n'
          '(명단 연락처로 문자/메일 발송 시 안내 문구가 포함됩니다)',
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
    if (ok != true) return;
    final s = context.read<AppState>();
    await _nas.eventRequestPhoto(
      widget.year,
      widget.title,
      by: s.who,
      message: '${widget.title} 사진을 올려주세요',
    );
    _snack('참가자에게 사진 업로드 요청을 등록했습니다');
  }

  Future<void> _openRoster() async {
    // 외부 브라우저 대신 앱 내부 화면으로 열어 뒤로가기·출력·공유가 정상 동작
    final e = _event;
    final s = context.read<AppState>();

    // 참가비 납부자 이름/인가번호 집합 (선택 항목: 참가비 납부 여부)
    final feeKeys = <String>{};
    for (final r in _fees) {
      final k1 = '${r['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
      final k2 = '${r['name'] ?? ''}'.trim();
      if (k1.isNotEmpty) feeKeys.add(k1);
      if (k2.isNotEmpty) feeKeys.add(k2);
    }

    final attendees = [
      for (final a in _attendees)
        {...a, 'visited': _isVisited(a), ..._rosterExtraFlags(a, feeKeys, s)},
    ];
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RosterScreen(
          title: widget.title,
          year: widget.year,
          period: '${e['period'] ?? e['date'] ?? ''}',
          place: '${e['place'] ?? ''}',
          desc: '${e['desc'] ?? ''}',
          attendees: attendees,
        ),
      ),
    );
  }

  /// 행사 후기 게시판 화면으로 이동
  void _openReview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EventReviewScreen(year: widget.year, title: widget.title),
      ),
    );
  }

  // ======================== 메뉴추가(사용자 정의 탭) ========================
  /// 커스텀 탭 하나의 뷰 — 제목 + 관리자 편집 가능한 메모(내용).
  Widget _customTabView(Map<String, dynamic> t) {
    final note = '${t['note'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        Row(
          children: [
            const Icon(Icons.tab, size: 18, color: AppColors.purple),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${t['name'] ?? '메뉴'}',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _editCustomTab(t),
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('편집', style: TextStyle(fontSize: 12.5)),
            ),
            TextButton.icon(
              onPressed: () => _removeCustomTab(t),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('삭제', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE6E1D6)),
          ),
          child: Text(
            note.trim().isEmpty ? '내용을 입력하려면 우측 상단 "편집"을 눌러주세요.' : note,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: note.trim().isEmpty
                  ? AppColors.textGray
                  : AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }

  /// 커스텀 탭 추가(메뉴추가).
  Future<void> _addCustomTab() async {
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
        scrollable: true,
        title: const Text('메뉴 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: '메뉴 이름 (예: 준비물 체크)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '내용/메모 (선택)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final next = <Map<String, dynamic>>[
      ..._customTabs.map(
        (e) => {'name': '${e['name'] ?? ''}', 'note': '${e['note'] ?? ''}'},
      ),
      {'name': name, 'note': noteCtrl.text.trim()},
    ];
    await _saveCustomTabs(next);
  }

  /// 커스텀 탭 편집(이름/내용).
  Future<void> _editCustomTab(Map<String, dynamic> t) async {
    final nameCtrl = TextEditingController(text: '${t['name'] ?? ''}');
    final noteCtrl = TextEditingController(text: '${t['note'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
        scrollable: true,
        title: const Text('메뉴 편집'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(hintText: '메뉴 이름'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '내용/메모',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final next = _customTabs.map((e) {
      final same =
          identical(e, t) ||
          ('${e['name'] ?? ''}' == '${t['name'] ?? ''}' &&
              '${e['note'] ?? ''}' == '${t['note'] ?? ''}');
      return same
          ? {'name': name, 'note': noteCtrl.text.trim()}
          : {'name': '${e['name'] ?? ''}', 'note': '${e['note'] ?? ''}'};
    }).toList();
    await _saveCustomTabs(next);
  }

  /// 커스텀 탭 삭제.
  Future<void> _removeCustomTab(Map<String, dynamic> t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('메뉴 삭제'),
        content: Text('"${t['name'] ?? ''}" 메뉴를 삭제할까요?'),
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
    if (yes != true || !mounted) return;
    final next = _customTabs
        .where(
          (e) =>
              !('${e['name'] ?? ''}' == '${t['name'] ?? ''}' &&
                  '${e['note'] ?? ''}' == '${t['note'] ?? ''}'),
        )
        .map(
          (e) => {'name': '${e['name'] ?? ''}', 'note': '${e['note'] ?? ''}'},
        )
        .toList();
    await _saveCustomTabs(next);
  }

  Future<void> _saveCustomTabs(List<Map<String, dynamic>> tabs) async {
    final r = await _nas.eventTabsSave(
      year: widget.year,
      title: widget.title,
      tabs: tabs,
    );
    if (!mounted) return;
    if (r) {
      _snack('메뉴를 저장했습니다');
      await _load();
    } else {
      _snack('메뉴 저장에 실패했습니다');
    }
  }

  bool _isVisited(Map<String, dynamic> a) {
    final ident = '${a['number'] ?? a['phone'] ?? ''}'.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return ident.isNotEmpty && _access.containsKey(ident);
  }

  /// 명단 선택항목용 플래그: 참가비 납부(eventFee) · 평생회원(lifetime) ·
  /// 행사년도 연회비 납부(yearFee).
  Map<String, dynamic> _rosterExtraFlags(
    Map<String, dynamic> a,
    Set<String> feeKeys,
    AppState s,
  ) {
    final num = '${a['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final name = '${a['name'] ?? ''}'.trim();
    final eventFee =
        (num.isNotEmpty && feeKeys.contains(num)) ||
        (name.isNotEmpty && feeKeys.contains(name));

    // 회원 원본 조회 → 평생회원 여부 + 해당 행사년도 연회비 납부 여부
    Member? m;
    if (num.isNotEmpty) m = s.byNumber(num);
    m ??= (name.isNotEmpty ? s.byName(name) : null);

    final lifetime = a['lifetime'] == true || (m?.lifetimeMember ?? false);
    var yearFee = a['yearFee'] == true;
    if (!yearFee && m != null && widget.year.isNotEmpty) {
      final y = widget.year.replaceAll(RegExp(r'[^0-9]'), '');
      yearFee =
          m.feeYears[y] == true ||
          m.feeYears['$y년'] == true ||
          m.paidYears.any((p) => p.replaceAll(RegExp(r'[^0-9]'), '') == y);
    }
    return {'eventFee': eventFee, 'lifetime': lifetime, 'yearFee': yearFee};
  }

  Future<void> _sendSms() async {
    final nums = _participantPhones();
    if (nums.isEmpty) {
      _snack('연락처가 있는 참가자가 없습니다');
      return;
    }
    final body = Uri.encodeComponent('[한국범스카우트] ${widget.title} 관련 안내드립니다.');
    final uri = Uri.parse('sms:${nums.join(',')}?body=$body');
    try {
      await launchUrl(uri);
    } catch (_) {
      _snack('문자 앱을 열 수 없습니다 (${nums.length}명)');
    }
  }

  Future<void> _sendMail() async {
    final mails = _participantEmails();
    if (mails.isEmpty) {
      _snack('메일주소가 있는 참가자가 없습니다');
      return;
    }
    final subject = Uri.encodeComponent('[한국범스카우트] ${widget.title} 안내');
    final uri = Uri.parse('mailto:${mails.join(',')}?subject=$subject');
    try {
      await launchUrl(uri);
    } catch (_) {
      _snack('메일 앱을 열 수 없습니다 (${mails.length}명)');
    }
  }

  List<String> _participantPhones() => [
    for (final a in _attendees)
      if ('${a['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '').isNotEmpty)
        '${a['phone']}'.replaceAll(RegExp(r'[^0-9]'), ''),
  ];

  List<String> _participantEmails() => [
    for (final a in _attendees)
      if ('${a['email'] ?? ''}'.contains('@')) '${a['email']}',
  ];

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  String _won(int v) {
    final s = v.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}${buf.toString()}원';
  }
}

/// 사진/동영상 뷰어 — 최적 크기 보기 + 원본보기/다운로드, 업로더만 삭제
class _MediaViewer extends StatefulWidget {
  const _MediaViewer({
    required this.year,
    required this.title,
    required this.items,
    required this.initialIndex,
    required this.canDeleteAll,
    required this.myName,
    this.sub = '',
  });

  final String year;
  final String title;
  final String sub;
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  final bool canDeleteAll;
  final String myName;

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late final PageController _pc;
  late int _index;
  bool _original = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pc = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  NasApi get _nas => context.read<NasApi>();

  Map<String, dynamic> get _cur => widget.items[_index];

  bool get _canDelete {
    if (widget.canDeleteAll) return true;
    return '${_cur['uploader'] ?? ''}' == widget.myName;
  }

  /// 사진/동영상 원본을 **저장 위치를 골라** 저장한다(요구).
  ///
  /// · [askSaveLocation] 로 위치 선택창을 먼저 띄우고,
  /// · 파일 바이트를 직접 받아 [saveFileNamed] 로 저장한다.
  /// · 바이트 수신·저장이 실패하면 기존 방식(외부 앱으로 열기)으로 폴백한다.
  Future<void> _saveMediaToChoosen(String url, String name, String kind) async {
    final ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : (kind == 'video' ? 'mp4' : 'jpg');
    final mime = kind == 'video'
        ? 'video/$ext'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');
    final opt = await askSaveOption(context, info: name);
    if (opt == null) return; // 사용자 취소
    try {
      final (bytes, ct) = await _nas.fetchBytes(url);
      if (!mounted) return;
      final ok = await saveFileOption(
        bytes: bytes,
        filename: name,
        mime: ct.startsWith('image/') || ct.startsWith('video/') ? ct : mime,
        option: opt,
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name 저장을 시작했습니다')));
      }
    } catch (e) {
      // 폴백: 프록시가 외부 다운로드를 처리하도록 기존 방식으로 연다.
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('다운로드 실패: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${_cur['name']}';
    final kind = '${_cur['kind'] ?? 'image'}';
    final uploader = '${_cur['uploader'] ?? ''}';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: TsakAppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.items.length}',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          if (kind == 'image')
            TextButton(
              onPressed: () => setState(() => _original = !_original),
              child: Text(
                _original ? '최적화 보기' : '원본 보기',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          IconButton(
            tooltip: '다운로드',
            icon: const Icon(Icons.download),
            onPressed: () async {
              // 이미지·동영상 원본 화질로 다운로드 (크롭/축소 없음).
              final url = _nas.eventFile2Url(
                widget.year,
                widget.title,
                'media',
                name,
                download: true,
                sub: widget.sub,
              );
              // 요구: "사진 저장위치 선택창이 안나오니 이것도 조정해줘요".
              //  · 위치 선택창을 띄운 뒤, 바이트를 직접 받아 지정 위치/기본 폴더에 저장.
              //  · 실패하면 기존 방식(외부 앱 다운로드)으로 폴백.
              await _saveMediaToChoosen(url, name, kind);
            },
          ),
          if (_canDelete)
            IconButton(
              tooltip: '삭제',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _original = false;
              }),
              itemBuilder: (_, i) {
                final m = widget.items[i];
                final n = '${m['name']}';
                final k = '${m['kind'] ?? 'image'}';
                if (k == 'video') {
                  return _VideoBox(
                    url: _nas.eventFile2Url(
                      widget.year,
                      widget.title,
                      'media',
                      n,
                      sub: widget.sub,
                    ),
                  );
                }
                final isOrig = i == _index && _original;
                // 최적화 보기: 지연 생성 1600px 캐시본 (빠름).
                // 원본 보기: 실제 원본 파일 (크롭 없이 전체가 보이고 확대 가능).
                final url = _nas.eventThumb2Url(
                  widget.year,
                  widget.title,
                  n,
                  size: isOrig ? 'orig' : 'view',
                  sub: widget.sub,
                );
                // 최적화·원본 모두 확대(핀치/더블탭) 가능.
                // 원본은 화면을 가득 채우되 잘리지 않게(contain) 전체가 보인다.
                return SizedBox.expand(
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: isOrig ? 12 : 6,
                    panEnabled: true,
                    scaleEnabled: true,
                    clipBehavior: Clip.none,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      loadingBuilder: (_, child, prog) => prog == null
                          ? child
                          : const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 60,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '$name  ·  ${_fmtSizeV((_cur['size'] as num?)?.toInt() ?? 0)}업로드: ${uploader.trim().isEmpty ? '415호' : uploader.trim()}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 표시용 용량 문자열(0이면 빈 문자열).
  String _fmtSizeV(int b) {
    if (b <= 0) return '';
    if (b < 1024) return '$b B  ·  ';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB  ·  ';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024).toStringAsFixed(1)} MB  ·  ';
    }
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB  ·  ';
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제'),
        content: const Text('이 사진을 삭제할까요?'),
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
    if (ok != true) return;
    await _nas.eventFileDelete(
      widget.year,
      widget.title,
      'media',
      '${_cur['name']}',
      sub: widget.sub,
    );
    if (mounted) Navigator.pop(context);
  }
}

class _VideoBox extends StatefulWidget {
  const _VideoBox({required this.url});
  final String url;
  @override
  State<_VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<_VideoBox> {
  VideoPlayerController? _c;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _c = c);
      c.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio == 0
                ? 16 / 9
                : c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          VideoProgressIndicator(c, allowScrubbing: true),
          IconButton(
            icon: Icon(
              c.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () =>
                setState(() => c.value.isPlaying ? c.pause() : c.play()),
          ),
        ],
      ),
    );
  }
}
