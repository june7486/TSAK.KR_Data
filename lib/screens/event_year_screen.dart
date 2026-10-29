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
import 'event_form_dialog.dart';
import 'event_resource_screen.dart';

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

  /// NAS 폴더 동기화 진행 중.
  bool _nasSyncing = false;

  /// 휴지통 펼침 여부 — 실수 삭제 대비, 기본은 접어 둔다.
  bool _trashOpen = false;

  /// true = 최신순 전체 리스트(연도 무관), false = 연도별 탭 보기
  bool _recentMode = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _thumbProgressNotifier.dispose();
    super.dispose();
  }

  /// [요구] 행사 목록 로딩. [silent]=true 이면 로딩 스피너를 띄우지 않고
  ///   기존 목록을 유지한 채 조용히 갱신한다(뒤로가기 복귀 시 깜빡임/지연 제거).
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final state = context.read<AppState>();
      final canTrash = state.isApp || state.isMaster;
      // [요구] 속도 개선 — 목록과 휴지통을 동시에(병렬) 조회한다.
      final results = await Future.wait<Object>([
        context.read<NasApi>().eventList2(),
        if (canTrash)
          context.read<NasApi>().eventTrashList().catchError(
            (_) => const <Map<String, dynamic>>[],
          )
        else
          Future<List<Map<String, dynamic>>>.value(const []),
      ]);
      final ev = results[0] as List<Map<String, dynamic>>;
      final trash = canTrash
          ? results[1] as List<Map<String, dynamic>>
          : const <Map<String, dynamic>>[];
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
      if (!silent) {
        setState(() {
          _error = '행사 목록을 불러오지 못했습니다: $e';
          _loading = false;
        });
      }
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

  /// NAS 폴더 → 행사 자동 등록.
  ///
  /// ## [요구 2026-10-30] "나스에 행사들을 추가했는데, 행사관리에서 자동으로
  ///  추가되지 않았음. 확인 후 업데이트 해줘"
  ///
  /// NAS 탐색기에서 `행사관리/<연도>/<행사명>` 폴더를 만들면 그게 곧 행사다.
  /// 다만 앱은 events.json 을 기준으로 목록을 그리므로, 새 폴더는 **명시적
  /// 동기화**가 필요하다(자동으로 하면 오등록 위험이 크다).
  ///
  /// 절차: ① 미리보기로 무엇이 추가될지 보여준다 → ② 사용자가 확인하면 등록.
  /// 사용자가 목록을 **눈으로 확인한 뒤** 결정하게 하는 것이 핵심이다.
  Future<void> _syncFromNas() async {
    setState(() => _nasSyncing = true);
    Map<String, dynamic> prev;
    try {
      prev = await context.read<NasApi>().eventNasPreview();
    } catch (e) {
      if (!mounted) return;
      setState(() => _nasSyncing = false);
      _snack('NAS 확인 실패: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _nasSyncing = false);
    if (prev['ok'] != true) {
      _snack('NAS 확인 실패');
      return;
    }
    final added = (prev['added'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (added.isEmpty) {
      _snack('NAS 와 앱이 이미 일치합니다 (새 행사 없음)');
      return;
    }

    // ── 미리보기 다이얼로그 ──
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('NAS 에서 행사 ${added.length}건 발견'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '아래 폴더를 행사로 등록할까요?',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final a in added)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${a['year']}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.purple,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${a['title']}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '· 기존 행사는 건드리지 않습니다\n'
                '· 폴더명을 그대로 행사명으로 씁니다\n'
                '· 항목 폴더(01~07)가 없으면 함께 만듭니다',
                style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
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
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('${added.length}건 등록'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _nasSyncing = true);
    try {
      final r = await context.read<NasApi>().eventNasSync();
      if (!mounted) return;
      final n = (r['added'] as List? ?? const []).length;
      setState(() => _nasSyncing = false);
      _snack(n > 0 ? '행사 $n건을 등록했습니다' : '새로 등록할 행사가 없습니다');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _nasSyncing = false);
      _snack('등록 실패: $e');
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
          final images = (job['images'] as num?)?.toInt() ?? 0;
          final videos = (job['videos'] as num?)?.toInt() ?? 0;
          final failed = (job['failed'] as num?)?.toInt() ?? 0;
          final last = '${job['last'] ?? ''}';

          // 진행률이 있으면 **다이얼로그**로 보여준다(스낵바는 계속 사라져
          //  진행 상황을 볼 수 없다). 완료·중단 시 자동으로 닫는다.
          if (running && total > 0) {
            final pct = ((done / total) * 100).clamp(0, 100).toStringAsFixed(1);
            final head = done == 0
                ? '준비 중… (대상 $total건)'
                : '$done / $total  ($pct%)';
            final msg = [
              head,
              if (images + videos > 0) '사진 $images · 동영상 $videos',
              if (failed > 0) '실패 $failed',
              if (last.isNotEmpty) '최근: ${last.split('/').last}',
            ].join('\n');
            _showThumbProgressDialog(msg, done, total);
          } else if (!running) {
            // 진행 중 다이얼로그가 떠 있으면 닫는다.
            if (_thumbDlgOpen && mounted) {
              Navigator.of(context, rootNavigator: true).pop();
              _thumbDlgOpen = false;
            }
          }

          if (running) {
            Future.delayed(const Duration(seconds: 3), _watchThumbBackfill);
          } else {
            if (mounted) setState(() => _backfillBusy = false);
            _snack('썸네일 생성 완료 — 사진 $images · 동영상 $videos'
                '${failed > 0 ? ' · 실패 $failed' : ''}');
          }
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() => _backfillBusy = false);
        });
  }

  /// 썸네일 진행 다이얼로그 — 떠 있는 동안 내용만 갱신한다(깜빡임 없음).
  bool _thumbDlgOpen = false;

  void _showThumbProgressDialog(String msg, int done, int total) {
    if (_thumbDlgOpen) {
      _thumbProgressNotifier.value = msg;
      return;
    }
    _thumbDlgOpen = true;
    _thumbProgressNotifier.value = msg;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.auto_awesome_mosaic,
          color: AppColors.purple,
          size: 30,
        ),
        title: const Text('썸네일 생성 중'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: _thumbProgressNotifier,
              builder: (_, v, __) => Text(
                v,
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: total > 0 ? (done / total).clamp(0.0, 1.0) : null,
            ),
            const SizedBox(height: 10),
            const Text(
              '백그라운드에서 계속 진행되므로 창을 닫아도 됩니다.\n'
              '중단해도 이미 만든 썸네일은 그대로 남습니다.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _thumbDlgOpen = false;
            },
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await context.read<NasApi>().eventThumbsStop();
                _snack('중단 요청했습니다 — 현재 파일 처리 후 멈춥니다');
              } catch (e) {
                _snack('중단 실패: $e');
              }
            },
            child: const Text('중단', style: TextStyle(color: AppColors.taegeukRed)),
          ),
        ],
      ),
    ).then((_) => _thumbDlgOpen = false);
  }

  final ValueNotifier<String> _thumbProgressNotifier = ValueNotifier<String>('');

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
        // [요구 2026-10-29] 아이콘이 한 줄에 몰려 제목과 겹치던 문제 →
        //  1줄 2개(엠블럼·행사자료) + 2줄 4개(게시판·사진·썸네일·NAS·새로고침)
        actionRows: const [2, 4],
        actions: [
          const AppHomeEmblem(size: 22),
          // [요구 2026-10-28] 행사자료(음원·영상·문서) 재생/내려받기.
          //  행사 때마다 반복해서 쓰는 자료라 목록 화면에서 한 번에 닿아야 한다.
          IconButton(
            tooltip: '행사자료 (음원·영상·문서 재생)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const EventResourceScreen(),
              ),
            ),
            icon: const Icon(Icons.library_music_outlined),
          ),
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
          if (_canManage(state))
            IconButton(
              // NAS 탐색기에서 폴더만 만들면 행사가 되어야 한다.
              //  앱이 모르는 폴더를 찾아 등록한다.
              tooltip: 'NAS 폴더에서 행사 가져오기',
              onPressed: _nasSyncing ? null : _syncFromNas,
              icon: _nasSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync),
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
    // [요구] 이 행사를 열람한 '인가자' 수(서버 집계).
    final credViewers = (e['credViewers'] as num?)?.toInt() ?? 0;
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
    final hasHeaderActions = manage && (defined || pending);
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
          // [요구] 뒤로가기 인터벌 단축 — 복귀 시 전체 스피너를 다시 띄우지 않고
          //   조용히(백그라운드) 갱신한다. await 하지 않아 화면 전환이 즉시 끝난다.
          _load(silent: true);
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
                            onTap: () => _editEvent(e),
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
                  // [요구] 이 행사를 열람한 '인가자' 수.
                  if (defined && credViewers > 0)
                    _metaChip(
                      Icons.verified_user_outlined,
                      '인가자 열람 $credViewers명',
                    ),
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
    // ## 버그 수정: 행사 만들기 창이 키보드에 찌그러지던 문제
    //  showDialog(AlertDialog) → showEventFormSheet(바텀시트).
    //  AlertDialog 는 키보드가 올라오면 insetPadding.bottom 이 커지며 창이
    //  줄어 입력칸이 화면 밖으로 밀려났다. 바텀시트는 키보드 위로 올라가고
    //  높이가 고정돼 입력칸이 절대 사라지지 않는다.
    final res = await showEventFormSheet(
      context: context,
      createMode: true,
      initialYear: initialYear,
    );
    if (res == null || !mounted) return;
    // 이중 확인: 연도 필수 (요청 K#4)
    if (!RegExp(r'^\d{4}$').hasMatch(res.year)) {
      _snack('연도를 선택해야 행사를 만들 수 있습니다');
      return;
    }
    if (res.title.isEmpty) return;
    final nas = context.read<NasApi>();
    final state = context.read<AppState>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await nas.eventCreate(
        year: res.year,
        title: res.title,
        period: res.period,
        place: res.place,
        desc: res.desc,
        by: state.who.isNotEmpty ? state.who : (state.isMaster ? '마스터' : '관리자'),
        lat: res.lat,
        lng: res.lng,
      );
      // [요구] 기간(시작/종료일) + 담당자(복수) 저장.
      if (res.startDate.isNotEmpty ||
          res.endDate.isNotEmpty ||
          res.contacts.isNotEmpty) {
        await nas.eventUpdate(
          year: res.year,
          title: res.title,
          startDate: res.startDate,
          endDate: res.endDate,
          contacts: res.contacts
              .map(
                (c) => <String, dynamic>{
                  'name': c['name'],
                  'phone': c['phone'],
                },
              )
              .toList(),
        );
      }
      // [요구] 첨부파일(복수) → '참가신청시 배포용' 폴더로 업로드.
      for (final f in res.newFiles) {
        try {
          await nas.eventDistUpload(
            res.year,
            res.title,
            f.name,
            f.bytes,
            contentType: _contentTypeOf(f.name),
          );
        } catch (e) {
          _snack('자료 업로드 실패: ${f.name} ($e)');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _snack('생성 실패: $e');
      }
      return;
    }
    if (mounted) {
      Navigator.pop(context);
      setState(() => _year = res.year);
      await _load();
    }
  }

  /// [요구] 행사 수정 — 입력했던 내용을 모두 수정한다.
  ///   (연도·행사명·기간(시작/종료일 달력)·장소·소개·담당자(복수)·배포용 자료 첨부/삭제)
  Future<void> _editEvent(Map<String, dynamic> e) async {
    final year = '${e['year']}';
    final title = '${e['title']}';
    // 기존 배포용 자료 목록 조회(관리자·마스터).
    List<Map<String, dynamic>> dist = const [];
    try {
      final full = await context.read<NasApi>().eventGet(year, title);
      dist = ((full['distFiles'] as List?) ?? [])
          .map((x) => (x as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {}
    if (!mounted) return;
    final res = await showEventFormSheet(
      context: context,
      createMode: false,
      initialYear: year,
      initialTitle: title,
      initialPeriod: '${e['period'] ?? ''}',
      initialPlace: '${e['place'] ?? ''}',
      initialDesc: '${e['desc'] ?? ''}',
      initialStart: '${e['startDate'] ?? ''}',
      initialEnd: '${e['endDate'] ?? ''}',
      initialContacts: ((e['contacts'] as List?) ?? [])
          .map((x) => (x as Map).cast<String, dynamic>())
          .toList(),
      initialDist: dist,
      initialLat: '${e['lat'] ?? ''}',
      initialLng: '${e['lng'] ?? ''}',
    );
    if (res == null || !mounted) return;
    final nas = context.read<NasApi>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final ok = await nas.eventUpdate(
        year: year,
        title: title,
        newYear: res.year,
        newTitle: res.title,
        period: res.period,
        place: res.place,
        desc: res.desc,
        startDate: res.startDate,
        endDate: res.endDate,
        lat: res.lat,
        lng: res.lng,
        contacts: res.contacts
            .map(
              (c) => <String, dynamic>{'name': c['name'], 'phone': c['phone']},
            )
            .toList(),
      );
      if (!ok) {
        if (mounted) _snack('저장에 실패했습니다');
        return;
      }
      // 삭제할 배포용 자료
      for (final nm in res.deletedDist) {
        try {
          await nas.eventDistDelete(res.year, res.title, nm);
        } catch (_) {}
      }
      // 새로 첨부한 자료(복수) 업로드
      for (final f in res.newFiles) {
        try {
          await nas.eventDistUpload(
            res.year,
            res.title,
            f.name,
            f.bytes,
            contentType: _contentTypeOf(f.name),
          );
        } catch (err) {
          _snack('자료 업로드 실패: ${f.name} ($err)');
        }
      }
    } catch (err) {
      _snack('수정 실패: $err');
    } finally {
      if (mounted) Navigator.pop(context);
    }
    await _load();
  }

  static String _contentTypeOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.mp4')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.hwp')) return 'application/x-hwp';
    if (n.endsWith('.doc') || n.endsWith('.docx')) {
      return 'application/msword';
    }
    if (n.endsWith('.xls') || n.endsWith('.xlsx')) {
      return 'application/vnd.ms-excel';
    }
    if (n.endsWith('.zip')) return 'application/zip';
    return 'application/octet-stream';
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
              defined
                  ? '“$title” 을(를) 휴지통으로 옮겼습니다 (복구 가능)'
                  : '“$title” 행사명을 삭제했습니다',
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
        border: Border.all(color: AppColors.taegeukRed.withValues(alpha: 0.18)),
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
