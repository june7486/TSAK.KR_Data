import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
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

  bool _isMyEvent(AppState s, Map<String, dynamic> e) {
    final who = s.who.replaceAll(RegExp(r'[^0-9]'), '');
    if (who.isEmpty) return false;
    for (final a in (e['attendees'] as List?) ?? []) {
      final id = '${a['number'] ?? a['phone'] ?? ''}'
          .replaceAll(RegExp(r'[^0-9]'), '');
      if (id == who) return true;
    }
    return false;
  }

  List<String> _yearsOf(List<Map<String, dynamic>> ev) {
    final ys = <String>{};
    for (final e in ev) {
      ys.add('${e['year'] ?? ''}');
    }
    ys.remove('');
    final list = ys.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final years = _yearsOf(_events);
    final inYear =
        _events.where((e) => '${e['year']}' == _year).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('행사관리'),
        actions: [
          const AppHomeEmblem(size: 22),
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
                _yearTabs(years),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: inYear.isEmpty
                        ? _emptyView()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
                            itemCount: inYear.length,
                            itemBuilder: (_, i) => _eventCard(state, inYear[i]),
                          ),
                  ),
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
    final list = all.toList()..sort((a, b) => b.compareTo(a));
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final y in list)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('$y년'),
                  selected: _year == y,
                  selectedColor: AppColors.purple,
                  labelStyle: TextStyle(
                    color: _year == y ? Colors.white : AppColors.purple,
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
    final count = (e['attendees'] as List?)?.length ?? 0;
    final period = '${e['period'] ?? ''}';
    final place = '${e['place'] ?? ''}';
    final mine = _isMyEvent(state, e);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
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
                      color: AppColors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      year,
                      style: const TextStyle(
                        color: AppColors.purple,
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
                  if (!_canManage(state) && mine)
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
              Row(
                children: [
                  const Icon(
                    Icons.people_alt_outlined,
                    size: 15,
                    color: AppColors.textGray,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '참가자 $count명',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGray,
                    ),
                  ),
                  const Spacer(),
                  if (_canManage(state))
                    IconButton(
                      tooltip: '이름/연도 변경',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _renameEvent(e),
                    ),
                  if (_canManage(state))
                    IconButton(
                      tooltip: '삭제',
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

  Future<void> _createEvent() async {
    final yearCtrl = TextEditingController(text: _year.isEmpty
        ? '${DateTime.now().year}'
        : _year);
    final titleCtrl = TextEditingController();
    final periodCtrl = TextEditingController();
    final placeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 행사 만들기'),
        content: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 10),
              TextField(
                controller: periodCtrl,
                decoration: const InputDecoration(labelText: '행사기간 (예: 2026.03.14~15)'),
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('생성'),
          ),
        ],
      ),
    );
    if (ok != true) return;
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
        by: state.who.isNotEmpty ? state.who : 'admin',
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('행사 삭제'),
        content: Text('“${e['title']}” 행사와 모든 파일을 삭제할까요?\n이 작업은 되돌릴 수 없습니다.'),
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
    await nas.eventDelete('${e['year']}', '${e['title']}');
    await _load();
  }
}
