import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';

/// 행사관리 — 행사 사진·동영상 갤러리
///
/// - 무제한 용량 업로드 (사진/동영상, 스트리밍)
/// - 상단에서 1열·2열·3열·4열·5열(바둑판) 보기 비율 선택
/// - 사진 클릭 → 크게 보기(줌) + 다운로드 / 동영상 클릭 → 재생 + 다운로드
/// - 서버가 썸네일을 만들어 로딩 시간을 단축
class EventGalleryScreen extends StatefulWidget {
  const EventGalleryScreen({super.key});

  @override
  State<EventGalleryScreen> createState() => _EventGalleryScreenState();
}

class _EventGalleryScreenState extends State<EventGalleryScreen> {
  int _cols = 3;
  List<Map<String, dynamic>> _files = [];
  bool _loading = false;
  bool _busy = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  NasApi get _nas => context.read<NasApi>();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final files = await _nas.eventList();
      if (mounted) setState(() => _files = files);
    } catch (_) {
      if (mounted) setState(() => _files = []);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('행사관리 (사진·동영상)'),
        actions: [
          const AppHomeEmblem(size: 24),
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.purple,
        onPressed: _busy ? null : _pickAndUpload,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add_photo_alternate),
        label: const Text('사진·동영상 올리기'),
      ),
      body: Column(
        children: [
          _toolbar(),
          if (_busy) _progressBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                ? _empty()
                : GridView.builder(
                    padding: const EdgeInsets.all(6),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _cols,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: _files.length,
                    itemBuilder: (_, i) => _tile(_files[i]),
                  ),
          ),
        ],
      ),
    );
  }

  /// 상단 보기 비율(열 수) 선택 — 글자 크기 조절처럼 1~5열
  Widget _toolbar() {
    const options = [1, 2, 3, 4, 5];
    return Material(
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          children: [
            const Icon(
              Icons.grid_view_rounded,
              size: 16,
              color: AppColors.purple,
            ),
            const SizedBox(width: 6),
            const Text(
              '보기',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in options)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _cols = c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _cols == c
                                  ? AppColors.purple
                                  : AppColors.purple.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.purple.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '$c열',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _cols == c
                                    ? Colors.white
                                    : AppColors.purple,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${_files.length}개',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '업로드 중… ${(_progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 11.5, color: AppColors.purple),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              minHeight: 6,
              backgroundColor: AppColors.purple.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.photo_library_outlined,
          size: 56,
          color: AppColors.textGray.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 10),
        const Text(
          '행사 사진·동영상이 없습니다',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
        const SizedBox(height: 4),
        const Text(
          '아래 버튼으로 올리면 갤러리에 표시됩니다',
          style: TextStyle(color: AppColors.textGray, fontSize: 11.5),
        ),
      ],
    ),
  );

  Widget _tile(Map<String, dynamic> f) {
    final name = '${f['name']}';
    final kind = '${f['kind']}';
    final isVideo = kind == 'video';
    final thumbUrl = _nas.eventThumbUrl(name);
    final fileUrl = _nas.eventFileUrl(name);

    Widget img = Image.network(
      thumbUrl,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) {
        // 썸네일이 없으면: 사진은 원본, 동영상은 아이콘
        if (isVideo) {
          return Container(
            color: Colors.black87,
            alignment: Alignment.center,
            child: const Icon(Icons.movie, color: Colors.white54, size: 30),
          );
        }
        return Image.network(
          fileUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: AppColors.purple.withValues(alpha: 0.08),
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image, color: AppColors.textGray),
          ),
        );
      },
    );

    return GestureDetector(
      onTap: () => _open(name, kind),
      onLongPress: () => _confirmDelete(name),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 고스트 이미지/캐시 이슈 방지
            RepaintBoundary(child: img),
            if (isVideo)
              const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            if (isVideo)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _dur(f['duration']),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _dur(dynamic d) {
    final s = (d is num) ? d.toInt() : 0;
    if (s <= 0) return '동영상';
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _pickAndUpload() async {
    final res = await pickDataFiles(
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'heic',
        'mp4',
        'mov',
        'webm',
        'm4v',
        'avi',
        'mkv',
      ],
      allowMultiple: true,
      dialogTitle: '행사 사진·동영상 선택',
    );
    if (res.isEmpty) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    var okCount = 0;
    for (final f in res) {
      try {
        final ct = _contentType(f.name);
        final r = await _nas.uploadEventMedia(
          f.name,
          f.bytes,
          contentType: ct,
          onProgress: (sent, total) {
            if (mounted && total > 0) {
              setState(() => _progress = sent / total);
            }
          },
        );
        if (r['ok'] == true) okCount++;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _progress = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('업로드 완료: $okCount/${res.length}개'),
          backgroundColor: AppColors.scoutGreen,
        ),
      );
      await _load();
    }
  }

  static String _contentType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.mp4') || n.endsWith('.m4v')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.webm')) return 'video/webm';
    return 'application/octet-stream';
  }

  Future<void> _confirmDelete(String name) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('"$name" 을(를) 삭제하시겠습니까?\n삭제 후 복구할 수 없습니다.'),
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
    if (yes != true) return;
    final ok = await _nas.deleteEventMedia(name);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? '삭제되었습니다' : '삭제 실패')));
    if (ok) await _load();
  }

  void _open(String name, String kind) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _MediaViewer(name: name, kind: kind, nas: _nas, onChanged: _load),
      ),
    );
  }
}

/// 사진 확대(줌) + 다운로드 / 동영상 재생 + 다운로드 뷰어
class _MediaViewer extends StatefulWidget {
  const _MediaViewer({
    required this.name,
    required this.kind,
    required this.nas,
    required this.onChanged,
  });

  final String name;
  final String kind;
  final NasApi nas;
  final Future<void> Function() onChanged;

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    if (widget.kind == 'video') {
      final url = Uri.parse(widget.nas.eventFileUrl(widget.name));
      final c = VideoPlayerController.networkUrl(url);
      _video = c;
      c
          .initialize()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.kind == 'video';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: Text(
          widget.name,
          style: const TextStyle(fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '다운로드',
            icon: const Icon(Icons.download),
            onPressed: _download,
          ),
          IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: Center(child: isVideo ? _videoView() : _imageView()),
      bottomNavigationBar: isVideo && (_video?.value.isInitialized ?? false)
          ? _videoControls()
          : null,
    );
  }

  Widget _imageView() {
    final url = widget.nas.eventFileUrl(widget.name);
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 5,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, p) => p == null
            ? child
            : const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, __, ___) => const Text(
          '이미지를 불러올 수 없습니다',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _videoView() {
    final v = _video;
    if (v == null) return const SizedBox();
    if (!v.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v));
  }

  Widget _videoControls() {
    final v = _video!;
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              color: Colors.white,
              icon: Icon(v.value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () =>
                  setState(() => v.value.isPlaying ? v.pause() : v.play()),
            ),
            Expanded(child: VideoProgressIndicator(v, allowScrubbing: true)),
            Text(
              _fmt(v.value.position),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            const Text(' / ', style: TextStyle(color: Colors.white38)),
            Text(
              _fmt(v.value.duration),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _download() async {
    final url = Uri.parse(widget.nas.eventFileUrl(widget.name, download: true));
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('다운로드를 시작할 수 없습니다')));
      }
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('"${widget.name}" 을(를) 삭제하시겠습니까?'),
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
    if (yes != true) return;
    final ok = await widget.nas.deleteEventMedia(widget.name);
    if (!mounted) return;
    if (ok) {
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    }
  }
}
