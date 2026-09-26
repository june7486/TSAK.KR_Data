import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/donation_accounts.dart';
import 'roster_screen.dart';

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

  List<Map<String, dynamic>> _plan = [];
  List<Map<String, dynamic>> _media = [];
  List<Map<String, dynamic>> _attendees = [];
  Map<String, dynamic> _access = {};
  List<Map<String, dynamic>> _fees = [];
  List<Map<String, dynamic>> _expenses = [];
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
      final e = await _nas.eventGet(widget.year, widget.title);
      final plan = await _nas.eventFiles(widget.year, widget.title, 'plan');
      final media = await _nas.eventFiles(
        widget.year,
        widget.title,
        'media',
        sub: _mediaSub,
      );
      final access = await _nas.eventAccessMap(widget.year, widget.title);
      final fin = await _nas.eventFinance(widget.year, widget.title);
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
      setState(() {
        _event = e;
        _plan = plan;
        _media = media;
        _access = access;
        _attendees = atts;
        _fees = fees;
        _expenses = exps;
        _loading = false;
        final len = widget.canManage ? 5 : 1; // 참가자는 사진탭만
        _tab = TabController(length: len, vsync: this);
        if (!widget.canManage) _tab!.index = 0;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('불러오기 실패: $err')),
      );
    }
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.canManage
        ? const [
            Tab(text: '계획서'),
            Tab(text: '참석자'),
            Tab(text: '사진+동영상'),
            Tab(text: '참가비·후원금'),
            Tab(text: '행사비지출'),
          ]
        : const [Tab(text: '사진+동영상')];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 16)),
            Text(
              '${widget.year}'
              '${'${_event['place'] ?? ''}'.isNotEmpty ? ' · ${_event['place']}' : ''}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        bottom: _tab == null
            ? null
            : TabBar(
                controller: _tab,
                isScrollable: true,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: tabs,
              ),
        actions: [
          const AppHomeEmblem(size: 22),
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
                    _download(context.read<NasApi>().eventZipUrl(
                      widget.year,
                      widget.title,
                      'media',
                    ));
                    break;
                  case 'request':
                    _requestPhoto();
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'zip', child: Text('사진 전체 ZIP 다운로드')),
                PopupMenuItem(value: 'request', child: Text('전체 참가자 사진 업로드 요청')),
              ],
            ),
        ],
      ),
      body: _loading || _tab == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 참가자(개인 접근): 참가비·후원 납부 계좌 3개 + 송금 버튼
                if (!widget.canManage)
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
                    children: widget.canManage
                        ? [
                            _planTab(),
                            _attendeeTab(),
                            _mediaTab(),
                            _financeTab('fee'),
                            _financeTab('expense'),
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
                onPressed: () => _download(_nas.eventZipUrl(
                  widget.year,
                  widget.title,
                  key,
                )),
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
                            _download(_nas.eventFile2Url(
                              widget.year,
                              widget.title,
                              key,
                              name,
                            ));
                          } else if (v == 'dl') {
                            _download(_nas.eventFile2Url(
                              widget.year,
                              widget.title,
                              key,
                              name,
                              download: true,
                            ));
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
                      onTap: () => _download(_nas.eventFile2Url(
                        widget.year,
                        widget.title,
                        key,
                        name,
                      )),
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
    final upName = uploader ??
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
    for (final p in picked) {
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('업로드 중... (${done + 1}/${picked.length})'),
                  Text(p.name, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
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
        if (mounted) Navigator.pop(context);
        done++;
      } catch (e) {
        if (mounted) Navigator.pop(context);
        _snack('업로드 실패: ${p.name} ($e)');
      }
    }
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

  Future<void> _renameFile(String key, String name, {String sub = ''}) async {
    final ctrl = TextEditingController(text: name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.taegeukRed),
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

  // ============================ 참석자 ============================
  Widget _attendeeTab() {
    return Column(
      children: [
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _rosterButton(
                Icons.table_chart,
                '명단 출력',
                () => _openRoster(),
              ),
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
    final ident = '${a['number'] ?? a['phone'] ?? ''}'
        .replaceAll(RegExp(r'[^0-9]'), '');
    final visited = ident.isNotEmpty && _access.containsKey(ident);
    final roles = (a['roles'] as List?) ?? [];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: visited
                    ? AppColors.scoutGreen
                    : Colors.transparent,
                border: Border.all(
                  color: visited
                      ? AppColors.scoutGreen
                      : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(5),
              ),
              child: visited
                  ? const Text(
                      'V',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 2),
            Text(
              '접속',
              style: TextStyle(
                fontSize: 9,
                color: visited
                    ? AppColors.scoutGreen
                    : AppColors.textGray,
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Text(
              '${a['name'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (ident.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                '#$ident',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                if ('${a['unit'] ?? ''}'.isNotEmpty) '${a['unit']}',
                if ('${a['phone'] ?? ''}'.isNotEmpty) '${a['phone']}',
                if ('${a['gender'] ?? ''}'.isNotEmpty) '${a['gender']}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12),
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
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              await _manualAddAttendee(editIndex: i);
            } else if (v == 'del') {
              setState(() => _attendees.removeAt(i));
              await _saveAttendees();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('수정')),
            PopupMenuItem(value: 'del', child: Text('삭제')),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAttendees() async {
    await _nas.eventSetAttendees(widget.year, widget.title, _attendees);
    await _load();
  }

  Future<void> _searchAndAddAttendee() async {
    final ctrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('인가자 검색'),
          content: SizedBox(
            width: 340,
            height: 420,
            child: Column(
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '인가번호 / 이름 / 소속',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () async {
                        results = await _nas.eventSearchMember(ctrl.text.trim());
                        setD(() {});
                      },
                    ),
                  ),
                  onSubmitted: (_) async {
                    results = await _nas.eventSearchMember(ctrl.text.trim());
                    setD(() {});
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final r in results)
                        ListTile(
                          dense: true,
                          title: Text('${r['name']} · #${r['number']}'),
                          subtitle: Text('${r['unit']}'),
                          trailing: const Icon(Icons.add, color: AppColors.purple),
                          onTap: () {
                            Navigator.pop(ctx, r);
                          },
                        ),
                    ],
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
        ),
      ),
    ).then((r) async {
      if (r is! Map) return;
      // 검색으로 선택 → 항목 선택 후 추가
      final roles = await _pickRoles();
      if (roles == null) return;
      setState(() {
        _attendees.add({
          'number': '${r['number']}',
          'name': '${r['name']}',
          'unit': '${r['unit']}',
          'league': '${r['league']}',
          'phone': '${r['phone']}',
          'roles': roles,
        });
      });
      await _saveAttendees();
    });
  }

  Future<List<String>?> _pickRoles() async {
    const all = [
      '지도자',
      '멘토지도자',
      '비버',
      '스카우트',
      '벤처',
      '로버',
      '본부',
      '학부모',
      '기타',
    ];
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
                  onSelected: (v) =>
                      setD(() => v ? sel.add(r) : sel.remove(r)),
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
    const all = [
      '지도자',
      '멘토지도자',
      '비버',
      '스카우트',
      '벤처',
      '로버',
      '본부',
      '학부모',
      '기타',
    ];
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
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
                    decoration: const InputDecoration(
                      labelText: '인가번호 (인가자만)',
                    ),
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
                  TextField(
                    controller: addrC,
                    decoration: const InputDecoration(labelText: '주소'),
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _crumb('사진+동영상', () => setState(() {
                        _mediaPath = [];
                        _mediaSel.clear();
                        _load();
                      })),
                  for (var i = 0; i < _mediaPath.length; i++) ...[
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppColors.textGray),
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
              Text('$_cols열',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
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
                      : () => _download(_nas.eventZipUrl(
                            widget.year,
                            widget.title,
                            'media',
                            sub: _mediaSub,
                          )),
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
    _load();
  }

  /// 선택 항목 토큰 ('현재폴더 파일'=name, '하위폴더 파일'=segSub:name)
  void _downloadSelectedMedia() {
    if (_mediaSel.isEmpty) return;
    final tokens = _mediaSel.toList();
    _download(_nas.eventZipUrl(
      widget.year,
      widget.title,
      'media',
      sub: _mediaSub,
      files: tokens,
    ));
  }

  Widget _mediaTile(int i) {
    final m = _media[i];
    final name = '${m['name']}';
    final isDir = m['isdir'] == true;
    final kind = '${m['kind'] ?? 'image'}';
    final uploader = _uploaderLabel('${m['uploader'] ?? ''}');
    final selected = _mediaSel.contains(name);
    final thumbUrl =
        _nas.eventThumb2Url(widget.year, widget.title, name, sub: _mediaSub);
    // 화면 폭/열 수에 맞춰 디코딩 크기를 제한 → 메모리·디코딩 비용 절감(로딩 가속).
    final cacheW = ((MediaQuery.of(context).size.width / _cols) *
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
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.25)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder, size: 40, color: AppColors.purple),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
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
                const SizedBox(height: 2),
                Text(
                  _uploaderLabel('${m['uploader'] ?? ''}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
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
            Text(
              uploader,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textGray,
                fontWeight: FontWeight.w600,
              ),
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
              leading: const Icon(Icons.delete_outline,
                  color: AppColors.taegeukRed),
              title: const Text('폴더 삭제',
                  style: TextStyle(color: AppColors.taegeukRed)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (v == 'zip') {
      _download(_nas.eventZipUrl(
        widget.year,
        widget.title,
        'media',
        sub: _mediaSub.isEmpty ? name : '$_mediaSub/$name',
      ));
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
            child: DonationAccounts(
              title: '참가비·후원 납부 계좌',
              showHolder: true,
            ),
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
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('수정'),
                                ),
                                PopupMenuItem(
                                  value: 'del',
                                  child: Text('삭제'),
                                ),
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
    final dateC = TextEditingController(
      text: '${row?['date'] ?? _today()}',
    );
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
    final attendees = [
      for (final a in _attendees)
        {
          ...a,
          'visited': _isVisited(a),
        },
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

  bool _isVisited(Map<String, dynamic> a) {
    final ident =
        '${a['number'] ?? a['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    return ident.isNotEmpty && _access.containsKey(ident);
  }

  Future<void> _sendSms() async {
    final nums = _participantPhones();
    if (nums.isEmpty) {
      _snack('연락처가 있는 참가자가 없습니다');
      return;
    }
    final body = Uri.encodeComponent(
      '[한국범스카우트] ${widget.title} 관련 안내드립니다.',
    );
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
    final uri = Uri.parse(
      'mailto:${mails.join(',')}?subject=$subject',
    );
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

  @override
  Widget build(BuildContext context) {
    final name = '${_cur['name']}';
    final kind = '${_cur['kind'] ?? 'image'}';
    final uploader = '${_cur['uploader'] ?? ''}';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
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
              final url = kind == 'video'
                  ? _nas.eventFile2Url(
                      widget.year,
                      widget.title,
                      'media',
                      name,
                      download: true,
                      sub: widget.sub,
                    )
                  // 이미지: 원본 화질로 다운로드 (크롭/축소 없음)
                  : _nas.eventFile2Url(
                      widget.year,
                      widget.title,
                      'media',
                      name,
                      download: true,
                      sub: widget.sub,
                    );
              await launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
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
              '$name  ·  업로드: ${uploader.trim().isEmpty ? '415호' : uploader.trim()}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.taegeukRed),
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
            aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          VideoProgressIndicator(c, allowScrubbing: true),
          IconButton(
            icon: Icon(
              c.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () => setState(
              () => c.value.isPlaying ? c.pause() : c.play(),
            ),
          ),
        ],
      ),
    );
  }
}
