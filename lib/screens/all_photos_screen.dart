import 'package:flutter/material.dart';
import '../widgets/marquee_text.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/personal_quick_actions.dart';
import '../widgets/tsak_app_bar.dart';
import 'package:provider/provider.dart';

/// 모든 사진 보기 — 행사 순서(최신순)대로 사진을 모아 보여준다.
/// 각 행사마다 머리글 + 사진 그리드 + 구분선(horizontal divider)으로 명확히 분리한다.
class AllPhotosScreen extends StatefulWidget {
  const AllPhotosScreen({super.key});

  @override
  State<AllPhotosScreen> createState() => _AllPhotosScreenState();
}

class _AllPhotosScreenState extends State<AllPhotosScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];
  int _total = 0;
  int _cols = 3;

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
      final r = await context.read<NasApi>().eventAllPhotos();
      final evs = ((r['events'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _events = evs;
        _total = (r['total'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '사진을 불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      appBar: TsakAppBar(
        title: const Text('모든 사진 보기'),
        actions: [
          IconButton(
            tooltip: '열 줄이기 (사진 확대)',
            onPressed: _cols > 1
                ? () => setState(() => _cols = _cols - 1)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            tooltip: '열 늘리기 (사진 축소)',
            onPressed: _cols < 8
                ? () => setState(() => _cols = _cols + 1)
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
          const AppHomeEmblem(size: 22),
          const SizedBox(width: 4),
        ],
      ),
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
                    : _events.isEmpty
                    ? _emptyView()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 60),
                          children: [
                            _summary(),
                            for (var i = 0; i < _events.length; i++) ...[
                              _eventGroupHeader(_events[i]),
                              _eventGrid(_events[i]),
                              // ---- 행사별 구분선(다음 행사와 명확히 분리) ----
                              if (i != _events.length - 1)
                                const _EventDivider()
                              else
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
          // 모든 사진 불러오기 대기 — 멈춘 것이 아님을 안내.
          BusyOverlay(
            visible: _loading,
            title: '사진을 불러오는 중입니다',
            lines: const [
              'NAS 서버에서 행사별 사진 목록을 가져오는 중...',
              '썸네일을 준비하는 중...',
              '잠시만 기다려 주세요...',
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.photo_library, size: 16, color: AppColors.purple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '행사 ${_events.length}개 · 사진 $_total장 (최신순)',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventGroupHeader(Map<String, dynamic> e) {
    final year = '${e['year'] ?? ''}';
    final title = '${e['title'] ?? ''}';
    final period = '${e['period'] ?? ''}';
    final place = '${e['place'] ?? ''}';
    final count = (e['count'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              year.isEmpty ? '연도미정' : year,
              style: const TextStyle(
                color: AppColors.purple,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarqueeText(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                if (period.isNotEmpty || place.isNotEmpty)
                  MarqueeText(
                    [
                      if (period.isNotEmpty) period,
                      if (place.isNotEmpty) place,
                    ].join('  '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count장',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.scoutGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventGrid(Map<String, dynamic> e) {
    final year = '${e['year'] ?? ''}';
    final title = '${e['title'] ?? ''}';
    final photos = ((e['photos'] as List?) ?? [])
        .map((p) => (p as Map).cast<String, dynamic>())
        .toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _cols,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: photos.length,
      itemBuilder: (_, i) => _photoTile(year, title, photos, i),
    );
  }

  Widget _photoTile(
    String year,
    String title,
    List<Map<String, dynamic>> photos,
    int i,
  ) {
    final p = photos[i];
    final name = '${p['name']}';
    final sub = '${p['sub'] ?? ''}';
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _openViewer(year, title, photos, i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            context.read<NasApi>().eventThumb2Url(year, title, name, sub: sub),
            fit: BoxFit.cover,
            loadingBuilder: (_, child, prog) => prog == null
                ? child
                : Container(
                    color: const Color(0xFFF0EDE9),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFFF0EDE9),
              child: const Icon(
                Icons.broken_image,
                color: AppColors.textGray,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openViewer(
    String year,
    String title,
    List<Map<String, dynamic>> photos,
    int index,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AllPhotosViewer(
          nas: context.read<NasApi>(),
          year: year,
          title: title,
          photos: photos,
          index: index,
        ),
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
        Icons.photo_library_outlined,
        size: 64,
        color: AppColors.purple.withValues(alpha: 0.3),
      ),
      const SizedBox(height: 12),
      const Center(
        child: Text(
          '등록된 행사 사진이 없습니다',
          style: TextStyle(color: AppColors.textGray),
        ),
      ),
    ],
  );
}

/// 행사 사이 구분선 — 명확한 분리를 위해 라벨 포함.
class _EventDivider extends StatelessWidget {
  const _EventDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          const Expanded(child: Divider(thickness: 1.2, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.arrow_upward, size: 12, color: AppColors.textGray),
                SizedBox(width: 3),
                Text(
                  '위 행사',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textGray,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_downward, size: 12, color: AppColors.textGray),
                SizedBox(width: 3),
                Text(
                  '아래 행사',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textGray,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: Divider(thickness: 1.2, height: 1)),
        ],
      ),
    );
  }
}

/// 전체화면 사진 뷰어 (좌우 스와이프 + 핀치 확대).
class _AllPhotosViewer extends StatefulWidget {
  const _AllPhotosViewer({
    required this.nas,
    required this.year,
    required this.title,
    required this.photos,
    required this.index,
  });

  final NasApi nas;
  final String year;
  final String title;
  final List<Map<String, dynamic>> photos;
  final int index;

  @override
  State<_AllPhotosViewer> createState() => _AllPhotosViewerState();
}

class _AllPhotosViewerState extends State<_AllPhotosViewer> {
  late PageController _pc;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    _pc = PageController(initialPage: widget.index);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photos[_index];
    final name = '${p['name']}';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: TsakAppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: MarqueeText(
          '${widget.title}  (${_index + 1}/${widget.photos.length})',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          final ph = widget.photos[i];
          final u = widget.nas.eventThumb2Url(
            widget.year,
            widget.title,
            '${ph['name']}',
            size: 'view',
            sub: '${ph['sub'] ?? ''}',
          );
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 6,
            child: Image.network(
              u,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              loadingBuilder: (_, child, prog) => prog == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 60,
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            name,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
