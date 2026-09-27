import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/scroll_arrows.dart';
import 'all_photos_screen.dart';
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
  bool _loading = true;
  String? _error;
  String _year = '';
  bool _backfillBusy = false;

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
      final state = context.read<AppState>();
      // 참가자(개인/일반)는 본인이 참석한 행사만 노출
      final visible = _canManage(state)
          ? ev
          : ev.where((e) => _isMyEvent(state, e)).toList();
      setState(() {
        _events = visible;
        _loading = false;
        final years = _yearsOf(visible);
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
        icon: const Icon(Icons.auto_awesome_mosaic,
            color: AppColors.purple, size: 32),
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
    context.read<NasApi>().eventThumbsStatus().then((r) {
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
    }).catchError((_) {
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
    for (final a in (e['attendees'] as List?) ?? []) {
      final id = '${a['number'] ?? a['phone'] ?? ''}'
          .replaceAll(RegExp(r'[^0-9]'), '');
      if (id == who) return true;
    }
    // 개인 프로필(eventAttend)에 본인 행사명이 있으면 참가 이력으로 간주
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
    final inYear =
        _events.where((e) => '${e['year']}' == _year).toList();
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
      appBar: AppBar(
        title: const Text('행사관리'),
        actions: [
          const AppHomeEmblem(size: 22),
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
              onPressed: _backfillBusy ? null : () => _startThumbBackfill(state),
              icon: _backfillBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
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
      body: _loading
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
                                padding:
                                    const EdgeInsets.fromLTRB(14, 10, 14, 90),
                                itemCount: recent.length,
                                itemBuilder: (_, i) =>
                                    _eventCard(state, recent[i]),
                              ))
                        : (inYear.isEmpty
                            ? _emptyView()
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 10, 14, 90),
                                itemCount: inYear.length,
                                itemBuilder: (_, i) =>
                                    _eventCard(state, inYear[i]),
                              )),
                  ),
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
          Text('${_events.length}개',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textGray)),
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
      child: ScrollArrows(
        step: 180,
        color: AppColors.purple,
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
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
                canManage: _canManage(state),
              ),
            ),
          );
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: defined
                          ? AppColors.purple.withValues(alpha: 0.1)
                          : AppColors.textGray.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      defined && year.isNotEmpty ? year : '연도미정',
                      style: TextStyle(
                        color: defined ? AppColors.purple : AppColors.textGray,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (!defined)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.tigerGold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.tigerGold.withValues(alpha: 0.6),
                        ),
                      ),
                      child: const Text(
                        '(관리목록누락)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.lifetimeGold,
                        ),
                      ),
                    ),
                  if (defined && !_canManage(state) && mine)
                    const Icon(
                      Icons.photo_library,
                      size: 18,
                      color: AppColors.scoutGreen,
                    ),
                ],
              ),
              if (period.isNotEmpty || place.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (period.isNotEmpty) '🗓 $period',
                    if (place.isNotEmpty) '📍 $place',
                  ].join('   '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _metaChip(Icons.people_alt_outlined, '참가인원 $count명'),
                  _metaChip(Icons.photo_camera_outlined, '사진 $photos장'),
                  _metaChip(Icons.videocam_outlined, '동영상 $videos개'),
                  if (place.isNotEmpty)
                    _metaChip(Icons.place_outlined, place),
                ],
              ),
              if (createdBy.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '생성자: $createdBy',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  const Spacer(),
                  if (_canManage(state) && defined)
                    IconButton(
                      tooltip: '이름/연도 변경',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _renameEvent(e),
                    ),
                  if (_canManage(state))
                    IconButton(
                      tooltip: defined ? '삭제 (행사 + 개인프로필)' : '삭제 (개인프로필 행사명)',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: AppColors.taegeukRed,
                      ),
                      onPressed: () => _deleteEvent(e),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
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
                            errorText: yearCtrl.text.trim().isEmpty ||
                                    yearOk
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
                style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연도를 선택해야 행사를 만들 수 있습니다')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('생성 실패: $e')),
        );
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

  Future<void> _deleteEvent(Map<String, dynamic> e) async {
    final defined = e['defined'] != false;
    final title = '${e['title']}';
    final msg = defined
        ? '“$title” 행사와 모든 파일을 삭제할까요?\n'
          '개인 프로필(행사참가)에 등록된 같은 행사명도 함께 삭제됩니다.\n'
          '이 작업은 되돌릴 수 없습니다.'
        : '“$title” 은(는) 행사관리 목록에 없는 행사입니다.\n'
          '개인 프로필(행사참가)에서 이 행사명을 삭제할까요?';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(defined ? '행사 삭제' : '행사명 삭제 (관리목록누락)'),
        content: Text(msg),
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
    final nas = context.read<NasApi>();
    try {
      if (defined) {
        await nas.eventDelete('${e['year']}', title);
      } else {
        await nas.eventNameDelete([title]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('“$title” 삭제했습니다')),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $err')),
        );
      }
    }
    await _load();
  }
}
