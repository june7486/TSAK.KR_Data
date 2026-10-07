import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/personal_quick_actions.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/hscroll_menu.dart';
import '../widgets/busy_overlay.dart';
import 'all_photos_screen.dart';
import 'board_screen.dart';
import 'event_detail_screen.dart';

/// 행사관리 — 연도별 탭 + 행사 목록/생성
///
/// 권한: 관리자·마스터는 모든 행사 관리. 인가자/일반회원은 본인이 참석자로
/// 등록된 행사만(사진+동영상 폴더 한정) 접근한다.
class EventYearScreen extends StatefulWidget {
  const EventYearScreen({super.key});

  @override
  State<EventYearScreen> createState() => _EventYearScreenState();
}

class _EventYearScreenState extends State<EventYearScreen> {
  List<Map<String, dynamic>> _events = [];

  /// 휴지통(삭제한 행사) — 소프트 삭제되어 복구 가능한 목록.
  List<Map<String, dynamic>> _trash = [];
  bool _loading = true;
  String? _error;
  String _year = '';
  bool _backfillBusy = false;

  /// 휴지통 펼침 여부 — 실수 삭제 대비, 기본은 접어 둔다.
  bool _trashOpen = false;

  /// true = 최신순 전체 리스트(연도 무관), false = 연도별 탭 보기
  bool _recentMode = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ev = await context.read<NasApi>().eventList2();
      // (요구 #12) 행사관리창의 행사는 모든 회원에게 노출된다.
      //  — 개인/일반회원도 전체 행사 목록을 열람할 수 있다(관리·편집은 권한별 제한).
      // 휴지통 목록은 관리자·마스터만 조회 가능(실패해도 무시).
      List<Map<String, dynamic>> trash = const [];
      final state = context.read<AppState>();
      if (state.isApp || state.isMaster) {
        try {
          trash = await context.read<NasApi>().eventTrashList();
        } catch (_) {
          trash = const [];
        }
      }
      if (!mounted) return;
      setState(() {
        _events = ev;
        _trash = trash;
        _loading = false;
        final years = _yearsOf(ev);
        if (_year.isEmpty || !years.contains(_year)) {
          _year = years.isNotEmpty ? years.first : '${DateTime.now().year}';
        }
      });
    } catch (e) {
      setState(() {
        _error = '행사 목록을 불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  bool _canManage(AppState s) => s.isApp || s.isMaster;

  /// 사진/동영상 썸네일 일괄 생성(백필) — 기존 업로드분의 로딩 속도를 대폭 개선.
  Future<void> _startThumbBackfill(AppState state) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.auto_awesome_mosaic,
          color: AppColors.purple,
          size: 32,
        ),
        title: const Text('썸네일 일괄 생성'),
        content: const Text(
          '모든 행사의 사진·동영상 썸네일을 미리 만들어 둡니다.\n\n'
          '처음 한 번만 실행하면 이후 사진 로딩이 크게 빨라집니다.\n'
          '자료가 많으면 수 분이 걸릴 수 있으며, 백그라운드에서 진행됩니다.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('생성 시작'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _backfillBusy = true);
    try {
      final r = await context.read<NasApi>().eventThumbsBackfill();
      if (!mounted) return;
      final started = r['started'] == true;
      _snack(started ? '썸네일 생성을 시작했습니다 (백그라운드)' : '이미 생성 작업이 진행 중입니다');
      _watchThumbBackfill();
    } catch (e) {
      if (mounted) _snack('시작 실패: $e');
      if (mounted) setState(() => _backfillBusy = false);
    }
  }

  void _watchThumbBackfill() {
    context
        .read<NasApi>()
        .eventThumbsStatus()
        .then((r) {
          if (!mounted) return;
          final job = (r['job'] as Map?) ?? {};
          final running = job['running'] == true;
          final total = (job['total'] as num?)?.toInt() ?? 0;
          final done = (job['done'] as num?)?.toInt() ?? 0;
          _snack('썸네일 진행: $done / $total');
          if (running) {
            Future.delayed(const Duration(seconds: 3), _watchThumbBackfill);
          } else {
            setState(() => _backfillBusy = false);
            _snack('썸네일 생성 완료 ($done건)');
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _backfillBusy = false);
        });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  bool _isMyEvent(AppState s, Map<String, dynamic> e) {
    final who = s.who.replaceAll(RegExp(r'[^0-9]'), '');
    if (who.isEmpty) return false;
    // ① 행사 참가자 명단에서 본인(인가번호/전화) 매칭
    for (final a in (e['attendees'] as List?) ?? []) {
      final id = '${a['number'] ?? a['loginId'] ?? a['phone'] ?? ''}'
          .replaceAll(RegExp(r'[^0-9]'), '');
      if (id.isNotEmpty && id == who) return true;
    }
    // ② 개인 프로필(eventAttend) 연동 매칭 — 행사관리에서 참가자로 추가하면
    //    인가자/비인가자 모두 프로필에 자동 기록되므로 이를 참가 이력으로 인정한다.
    final title = '${e['title'] ?? ''}'.trim();
    final me = s.who.isNotEmpty ? s.byNumber(s.who) : null;
    if (me != null && title.isNotEmpty && me.eventAttend[title] == true) {
      return true;
    }
    return false;
  }

  /// 연도 집합 — 연도가 비어 있는(관리목록누락) 행사는 '' 키로 두고 '미분류'로 표시.
  List<String> _yearsOf(List<Map<String, dynamic>> ev) {
    final ys = <String>{};
    for (final e in ev) {
      ys.add('${e['year'] ?? ''}');
    }
    final list = ys.toList()
      ..sort((a, b) {
        if (a == '') return 1;
        if (b == '') return -1;
        return b.compareTo(a);
      });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final years = _yearsOf(_events);
    final inYear = _events.where((e) => '${e['year']}' == _year).toList();
    // 최신순 정렬(연도 → 기간/생성일 역순) — 연도 무관 전체 리스트
    final recent = List<Map<String, dynamic>>.from(_events)
      ..sort((a, b) {
        final ya = '${a['year'] ?? ''}';
        final yb = '${b['year'] ?? ''}';
        if (ya != yb) return yb.compareTo(ya);
        final pa = '${a['period'] ?? ''}';
        final pb = '${b['period'] ?? ''}';
        return pb.compareTo(pa);
      });

    return Scaffold(
      appBar: TsakAppBar(
        title: const Text('행사관리'),
        actions: [
          const AppHomeEmblem(size: 22),
          // 행사+수품 게시판 — 개인(범스카우트·일반회원)도 모든 글을 열람한다.
          IconButton(
            tooltip: '게시판 (행사·수품 소식·후기)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BoardScreen()),
            ),
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: '모든 사진 보기 (행사 순서)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AllPhotosScreen()),
            ),
            icon: const Icon(Icons.photo_library_outlined),
          ),
          if (_canManage(state))
            IconButton(
              tooltip: '사진/동영상 썸네일 일괄 생성',
              onPressed: _backfillBusy
                  ? null
                  : () => _startThumbBackfill(state),
              icon: _backfillBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_mosaic),
            ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _canManage(state)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.purple,
              onPressed: _createEvent,
              icon: const Icon(Icons.add),
              label: const Text('행사 만들기'),
            )
          : null,
      body: Stack(
        children: [
          Column(
            children: [
              // (요구#3) 개인아이디 접속 화면에도 HOME·본인정보편집 동일 배치
              const PersonalQuickActions(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? _errorView()
                    : Column(
                        children: [
                          _viewToggle(),
                          if (!_recentMode) _yearTabs(years),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _load,
                              child: _recentMode
                                  ? (recent.isEmpty
                                        ? _emptyView()
                                        : ListView.builder(
                                            padding: const EdgeInsets.fromLTRB(
                                              14,
                                              8,
                                              14,
                                              24,
                                            ),
                                            itemCount: recent.length,
                                            itemBuilder: (_, i) =>
                                                _eventCard(state, recent[i]),
                                          ))
                                  : (inYear.isEmpty
                                        ? _emptyView()
                                        : ListView.builder(
                                            padding: const EdgeInsets.fromLTRB(
                                              14,
                                              8,
                                              14,
                                              24,
                                            ),
                                            itemCount: inYear.length,
                                            itemBuilder: (_, i) =>
                                                _eventCard(state, inYear[i]),
                                          )),
                            ),
                          ),
                          // (요구) 하단 '삭제한 행사' 리스트 — 복구/완전삭제.
                          if (_canManage(state)) _trashPanel(state),
                        ],
                      ),
              ),
            ],
          ),
          // 행사 목록 불러오기 대기 — 멈춘 것이 아님을 안내.
          BusyOverlay(
            visible: _loading,
            title: '행사 목록을 불러오는 중입니다',
            lines: const [
              'NAS 서버에서 행사 정보를 가져오는 중...',
              '연도별로 정리하는 중...',
              '잠시만 기다려 주세요...',
            ],
          ),
        ],
      ),
    );
  }

  /// 보기 전환 — [최신순 전체] / [연도별]
  Widget _viewToggle() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('최신순 전체', style: TextStyle(fontSize: 12.5)),
                  icon: Icon(Icons.sort, size: 16),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('연도별', style: TextStyle(fontSize: 12.5)),
                  icon: Icon(Icons.calendar_today, size: 15),
                ),
              ],
              selected: {_recentMode},
              onSelectionChanged: (s) => setState(() => _recentMode = s.first),
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_events.length}개',
            style: const TextStyle(fontSize: 12, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _errorView() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.taegeukRed),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _load, child: const Text('다시 시도')),
      ],
    ),
  );

  Widget _emptyView() => ListView(
    children: [
      const SizedBox(height: 100),
      Icon(
        Icons.event_busy,
        size: 64,
        color: AppColors.purple.withValues(alpha: 0.3),
      ),
      const SizedBox(height: 12),
      const Center(
        child: Text(
          '이 연도에 등록된 행사가 없습니다',
          style: TextStyle(color: AppColors.textGray),
        ),
      ),
    ],
  );

  Widget _yearTabs(List<String> years) {
    final all = <String>{...years};
    if (all.isEmpty) all.add(_year);
    final list = all.toList()
      ..sort((a, b) {
        if (a == '') return 1;
        if (b == '') return -1;
        return b.compareTo(a);
      });
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: HScrollMenu(
        height: 40,
        child: Row(
          children: [
            for (final y in list)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(y.isEmpty ? '미분류' : '$y년'),
                  selected: _year == y,
                  selectedColor: y.isEmpty
                      ? AppColors.tigerGold
                      : AppColors.purple,
                  labelStyle: TextStyle(
                    color: _year == y
                        ? Colors.white
                        : (y.isEmpty
                              ? AppColors.lifetimeGold
                              : AppColors.purple),
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (_) => setState(() => _year = y),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _eventCard(AppState state, Map<String, dynamic> e) {
    final year = '${e['year']}';
    final title = '${e['title']}';
    final defined = e['defined'] != false;
    final pending = e['pendingPrivate'] == true; // 개인제안 심사중
    final attendeeLen = (e['attendees'] as List?)?.length ?? 0;
    final memberCnt = (e['memberCount'] as num?)?.toInt() ?? 0;
    final count = attendeeLen > 0 ? attendeeLen : memberCnt;
    final period = '${e['period'] ?? ''}';
    final place = '${e['place'] ?? ''}';
    final createdBy = '${e['createdBy'] ?? ''}';
    final media = (e['media'] as Map?)?.cast<String, dynamic>() ?? const {};
    final photos = (media['photo'] as num?)?.toInt() ?? 0;
    final videos = (media['video'] as num?)?.toInt() ?? 0;
    final mine = _isMyEvent(state, e);
    final manage = _canManage(state);
    // (요구) 편집·삭제 버튼을 카드 '상단(제목 줄)' 우측 상단으로 올린다.
    //  · 아이콘을 조밀(compact)하게 만들어 한 줄에 더 많은 행사가 보이도록 한다.
    final hasHeaderActions =
        manage && (defined || pending);
    return Card(
      // 더 많은 행사가 보이도록 카드 여백·하단 간격을 줄인다.
      margin: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          // (요구 #9) 개인제안 심사중 행사 — 관리자·마스터는 승인/반려 처리.
          if (pending && manage) {
            await _reviewPrivate(e);
            return;
          }
          if (!defined) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('행사관리 목록에 없는 행사입니다 — 삭제하거나 새로 만들어 주세요'),
              ),
            );
            return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EventDetailScreen(
                year: year,
                title: title,
                canManage: manage,
              ),
            ),
          );
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- 제목 줄: [연도] 제목 … 배지 … 편집/삭제(상단) ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: defined
                          ? AppColors.purple.withValues(alpha: 0.1)
                          : AppColors.textGray.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      defined && year.isNotEmpty ? year : '연도미정',
                      style: TextStyle(
                        color: defined ? AppColors.purple : AppColors.textGray,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ),
                  if (!manage && defined && mine)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, right: 4),
                      child: Icon(
                        Icons.photo_library,
                        size: 16,
                        color: AppColors.scoutGreen,
                      ),
                    ),
                  if (hasHeaderActions)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (defined)
                          _cardIconBtn(
                            tooltip: '이름/연도 변경',
                            icon: Icons.edit_outlined,
                            color: AppColors.purple,
                            onTap: () => _renameEvent(e),
                          ),
                        if (pending)
                          _cardIconBtn(
                            tooltip: '심사중 제안행사 처리 (승인/반려)',
                            icon: Icons.rule,
                            color: AppColors.purple,
                            onTap: () => _reviewPrivate(e),
                          ),
                        if (!pending)
                          _cardIconBtn(
                            tooltip: defined
                                ? '삭제 (휴지통으로 이동 — 복구 가능)'
                                : '삭제 (개인프로필 행사명)',
                            icon: Icons.delete_outline,
                            color: AppColors.taegeukRed,
                            onTap: () => _deleteEvent(e),
                          ),
                      ],
                    ),
                ],
              ),
              // ---- 배지(심사중/관리목록누락) ----
              if (pending || !defined) ...[
                const SizedBox(height: 3),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.tigerGold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.tigerGold.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      pending ? '관리목록누락행사-심사중' : '(관리목록누락)',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.lifetimeGold,
                      ),
                    ),
                  ),
                ),
              ],
              // ---- 메타: 기간·장소 + 인원/사진/동영상 (한 줄로 조밀하게) ----
              if (period.isNotEmpty || place.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  [
                    if (period.isNotEmpty) '🗓 $period',
                    if (place.isNotEmpty) '📍 $place',
                  ].join('   '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGray,
                  ),
                ),
              ],
              const SizedBox(height: 5),
              Wrap(
                spacing: 10,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _metaChip(Icons.people_alt_outlined, '참가 $count명'),
                  _metaChip(Icons.photo_camera_outlined, '$photos장'),
                  _metaChip(Icons.videocam_outlined, '$videos개'),
                  if (createdBy.isNotEmpty)
                    _metaChip(Icons.person_outline, createdBy),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 카드 상단용 조밀 아이콘 버튼 — 2줄 카드가 되지 않도록 작게 유지.
  Widget _cardIconBtn({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 17, color: color),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      splashRadius: 18,
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.textGray),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppColors.textGray),
        ),
      ],
    );
  }

  Future<void> _createEvent() async {
    final initialYear = _year.isEmpty ? '${DateTime.now().year}' : _year;
    final yearCtrl = TextEditingController(text: initialYear);
    final titleCtrl = TextEditingController();
    final periodCtrl = TextEditingController();
    final placeCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final yearOk = RegExp(r'^\d{4}$').hasMatch(yearCtrl.text.trim());
          return AlertDialog(
            title: const Text('새 행사 만들기'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: yearCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          onChanged: (_) => setSt(() {}),
                          decoration: InputDecoration(
                            labelText: '연도 * (필수)',
                            counterText: '',
                            errorText: yearCtrl.text.trim().isEmpty || yearOk
                                ? null
                                : '4자리 연도를 입력하세요',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final now = DateTime.now().year;
                          final picked = await showDialog<int>(
                            context: ctx,
                            builder: (_) => AlertDialog(
                              title: const Text('연도 선택'),
                              content: SizedBox(
                                width: 300,
                                height: 300,
                                child: YearPicker(
                                  firstDate: DateTime(1980),
                                  lastDate: DateTime(now + 5),
                                  selectedDate: DateTime(
                                    int.tryParse(yearCtrl.text.trim()) ?? now,
                                  ),
                                  onChanged: (d) => Navigator.pop(ctx, d.year),
                                ),
                              ),
                            ),
                          );
                          if (picked != null) {
                            yearCtrl.text = '$picked';
                            setSt(() {});
                          }
                        },
                        child: const Text('선택'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: '행사명 *'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: periodCtrl,
                    decoration: const InputDecoration(
                      labelText: '행사기간 (예: 2026.03.14~15)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: placeCtrl,
                    decoration: const InputDecoration(labelText: '장소'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: '행사 소개/개요'),
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
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                ),
                onPressed: (yearOk && titleCtrl.text.trim().isNotEmpty)
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('생성'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    // 이중 확인: 연도 필수 (요청 K#4)
    if (!RegExp(r'^\d{4}$').hasMatch(yearCtrl.text.trim())) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('연도를 선택해야 행사를 만들 수 있습니다')));
      }
      return;
    }
    if (titleCtrl.text.trim().isEmpty) return;
    final nas = context.read<NasApi>();
    final state = context.read<AppState>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await nas.eventCreate(
        year: yearCtrl.text.trim(),
        title: titleCtrl.text.trim(),
        period: periodCtrl.text.trim(),
        place: placeCtrl.text.trim(),
        desc: descCtrl.text.trim(),
        by: state.who.isNotEmpty ? state.who : (state.isMaster ? '마스터' : '관리자'),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('생성 실패: $e')));
      }
      return;
    }
    if (mounted) {
      Navigator.pop(context);
      setState(() => _year = yearCtrl.text.trim());
      await _load();
    }
  }

  Future<void> _renameEvent(Map<String, dynamic> e) async {
    final titleCtrl = TextEditingController(text: '${e['title']}');
    final yearCtrl = TextEditingController(text: '${e['year']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
        scrollable: true,
        title: const Text('행사 이름/연도 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: yearCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '연도'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: '행사명'),
            ),
          ],
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
    );
    if (ok != true) return;
    final nas = context.read<NasApi>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await nas.eventRename(
        year: '${e['year']}',
        title: '${e['title']}',
        newYear: yearCtrl.text.trim(),
        newTitle: titleCtrl.text.trim(),
      );
    } finally {
      if (mounted) Navigator.pop(context);
    }
    await _load();
  }

  /// (요구 #9) 개인제안 심사중 행사 — 관리자·마스터가 승인/반려.
  Future<void> _reviewPrivate(Map<String, dynamic> e) async {
    final id = '${e['privateId'] ?? e['id'] ?? ''}';
    final title = '${e['title']}';
    if (id.isEmpty) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('심사중 제안행사 — $title'),
        content: Text(
          '${e['year']}년 · ${e['period'] ?? ''} ${e['place'] ?? ''}\n'
          '제안자: ${e['createdBy'] ?? ''}\n\n'
          '승인하면 행사로 등록됩니다. 반려하면 삭제됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.taegeukRed),
            onPressed: () => Navigator.pop(ctx, 'reject'),
            child: const Text('반려'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.scoutGreen,
            ),
            onPressed: () => Navigator.pop(ctx, 'approve'),
            child: const Text('승인'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    final ok = await context.read<NasApi>().eventPrivateSet(
      id: id,
      action: action,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? (action == 'approve' ? '행사로 등록했습니다' : '반려했습니다') : '처리에 실패했습니다',
        ),
      ),
    );
    await _load();
  }

  Future<void> _deleteEvent(Map<String, dynamic> e) async {
    final defined = e['defined'] != false;
    final title = '${e['title']}';
    // (요구) 실수 삭제 방지 — 확인창을 띄우고, 삭제는 '휴지통으로 이동'(복구 가능).
    final msg = defined
        ? '“$title” 행사를 삭제할까요?\n\n'
              '삭제한 행사는 하단 「삭제한 행사」 목록(휴지통)으로 이동합니다. '
              '거기서 복구하거나 완전 삭제할 수 있습니다. '
              '(파일은 완전 삭제 전까지 보존됩니다.)'
        : '“$title” 은(는) 행사관리 목록에 없는 행사입니다.\n\n'
              '개인 프로필(행사참가)에서 이 행사명을 삭제할까요?\n'
              '이 항목은 휴지통으로 이동합니다.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.taegeukRed,
          size: 28,
        ),
        title: Text(
          defined ? '행사 삭제 (휴지통으로 이동)' : '행사명 삭제 (관리목록누락)',
          textAlign: TextAlign.center,
        ),
        content: Text(
          msg,
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actionsAlignment: MainAxisAlignment.center,
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
            child: const Text('삭제 (휴지통)'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final nas = context.read<NasApi>();
    final by = _operatorLabel();
    try {
      if (defined) {
        await nas.eventArchive('${e['year']}', title, by: by);
      } else {
        // 관리목록누락(프로필에만 있는) 행사명 — 프로필에서 제거.
        await nas.eventNameDelete([title]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              defined ? '“$title” 을(를) 휴지통으로 옮겼습니다 (복구 가능)' : '“$title” 행사명을 삭제했습니다',
            ),
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제 실패: $err')));
      }
    }
    await _load();
  }

  /// 삭제자 표기 — 관리자/마스터 로그인 정보.
  String _operatorLabel() {
    final s = context.read<AppState>();
    final who = s.who.trim();
    if (who.isNotEmpty) return who;
    if (s.isMaster) return '마스터';
    return s.isApp ? '관리자' : '';
  }

  // ======================== 하단 '삭제한 행사'(휴지통) ========================

  /// 하단 휴지통 패널 — 관리자·마스터만 노출.
  Widget _trashPanel(AppState state) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE9E4F2), width: 1.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _trashOpen = !_trashOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    _trashOpen ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppColors.taegeukRed,
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.delete_sweep_outlined,
                    size: 18,
                    color: AppColors.taegeukRed,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '삭제한 행사 (휴지통)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.taegeukRed,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.taegeukRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_trash.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.taegeukRed,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '복구 / 완전삭제',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                  ),
                ],
              ),
            ),
          ),
          if (_trashOpen)
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              child: _trash.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '삭제한 행사가 없습니다.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGray,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      itemCount: _trash.length,
                      itemBuilder: (_, i) => _trashRow(state, _trash[i]),
                    ),
            ),
        ],
      ),
    );
  }

  /// 휴지통 한 줄 — 제목/연도/삭제시각 + 복구·완전삭제 버튼.
  Widget _trashRow(AppState state, Map<String, dynamic> t) {
    final title = '${t['title'] ?? ''}';
    final year = '${t['year'] ?? ''}';
    final deletedAt = '${t['deletedAt'] ?? ''}';
    final deletedBy = '${t['deletedBy'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.taegeukRed.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.taegeukRed.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (year.isNotEmpty && year != '무제')
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.textGray.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          year,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textGray,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  ],
                ),
                if (deletedAt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '삭제: $deletedAt${deletedBy.isNotEmpty ? ' · $deletedBy' : ''}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textGray,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _restoreEvent(t),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.scoutGreen,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('복구', style: TextStyle(fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: () => _purgeEvent(t),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.taegeukRed,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('완전삭제', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreEvent(Map<String, dynamic> t) async {
    final id = '${t['id'] ?? ''}';
    final title = '${t['title'] ?? ''}';
    try {
      await context.read<NasApi>().eventRestore(id);
      if (mounted) _snack('“$title” 을(를) 복구했습니다');
    } catch (e) {
      if (mounted) _snack('복구 실패: $e');
    }
    await _load();
  }

  Future<void> _purgeEvent(Map<String, dynamic> t) async {
    final id = '${t['id'] ?? ''}';
    final title = '${t['title'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever,
          color: AppColors.taegeukRed,
          size: 30,
        ),
        title: const Text('완전 삭제', textAlign: TextAlign.center),
        content: Text(
          '“$title” 을(를) 완전히 삭제할까요?\n\n'
          '저장된 사진·동영상 파일과 개인 프로필의 행사 이력까지 모두 지워집니다.\n'
          '이 작업은 되돌릴 수 없습니다.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actionsAlignment: MainAxisAlignment.center,
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
            child: const Text('완전 삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<NasApi>().eventPurge([id]);
      if (mounted) _snack('“$title” 을(를) 완전 삭제했습니다');
    } catch (e) {
      if (mounted) _snack('완전 삭제 실패: $e');
    }
    await _load();
  }
}
