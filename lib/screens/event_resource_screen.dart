import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../services/app_state.dart';
import '../services/event_resource_api.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';

/// 행사자료 — 음원·영상·문서를 **재생하고 내려받는** 화면.
///
/// ## [요구 2026-10-28] (그대로)
/// "행사 관리 우측에 버튼을 만들어서 행사관련 음원 파일들을 재생할 수 있도록
///  해줘 / 음원재생 페이지를 만들어주고, 폴더 위치는 01 행사음원(업로드가능)
///  위치에 mp3파일을 넣을 수 있도록 해주고, 게시판에서 직접 업로드도
///  가능하도록 해줘, 음악 및 영상, 기타 자료등도 관리 및 활용 가능하도록
///  해서, 행사때 항상 반복적으로 필요한 자료들을 재생하고, 다운로드 받을 수
///  있으면 좋겠어"
///
/// ## 설계 메모
///  · **파일은 NAS 가 원본**이다. 앱은 목록만 받고 재생은 Range 스트리밍
///    URL 로 흘려보낸다 → 곡을 끝까지 받지 않고 즉시 재생·중간이동(seek).
///  · 재생 엔진은 이미 설치된 `video_player` 를 쓴다(웹=HTML audio,
///    안드로이드=ExoPlayer). 새 의존성을 늘리지 않는다.
///  · `0000 폴더정리법(폴더샘플)` 은 **PC 전용** — 서버가 목록에서 아예
///    빼므로 이 화면에 나타나지 않는다.
class EventResourceScreen extends StatefulWidget {
  const EventResourceScreen({super.key, this.initialSub = ''});

  final String initialSub;

  @override
  State<EventResourceScreen> createState() => _EventResourceScreenState();
}

class _EventResourceScreenState extends State<EventResourceScreen> {
  late final EventResourceApi _api;
  EventResourceList _data = EventResourceList.empty;
  bool _loading = true;
  String? _error;
  String _sub = '';

  /// 재생 중인 항목.
  EventResource? _nowPlaying;
  VideoPlayerController? _player;
  String? _playError;

  /// `audio` | `video` | `doc`  (image 는 doc 탭에 함께)
  String _tab = 'audio';

  /// 폴더 칩 필터 — null 이면 전체.
  String? _folderFilter;

  /// 순서 편집 모드 — 켜면 드래그 손잡이 목록으로 교체된다.
  bool _editMode = false;

  /// 순서 저장 요청 진행 중.
  bool _savingOrder = false;

  @override
  void initState() {
    super.initState();
    _api = EventResourceApi(context.read<NasApi>());
    _sub = widget.initialSub;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _load({String? sub, bool silent = false}) async {
    final target = sub ?? _sub;
    setState(() {
      if (!silent) _loading = true;
      _error = null;
      _sub = target;
    });
    try {
      final r = await _api.list(sub: target);
      if (!mounted) return;
      setState(() {
        _data = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '자료를 불러오지 못했습니다.\n$e';
        _loading = false;
      });
    }
  }

  // ── 재생 ───────────────────────────────────────────────────────────
  Future<void> _play(EventResource r) async {
    await _player?.dispose();
    _player = null;
    setState(() {
      _nowPlaying = r;
      _playError = null;
    });
    final url = _api.streamUrl(r);
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _player = c;
    try {
      await c.initialize();
      await c.play();
      if (!mounted) return;
      setState(() {});
      // 재생이 끝나면 다음 곡이 없어도 최소한 '정지'로 보이게 한다.
      c.addListener(() {
        if (!mounted) return;
        if (c.value.position >= c.value.duration &&
            c.value.duration > Duration.zero &&
            !c.value.isPlaying) {
          setState(() {});
        } else {
          setState(() {}); // 진행 막대 갱신
        }
      });
    } catch (e) {
      if (!mounted) return;
      // <audio> 는 헤더를 못 넣는다 → 쿠키 인증이 안 되는 환경(안드로이드
      // WebView 등)에서는 401 이 날 수 있다. 조용히 멈추지 않고 알린다.
      setState(() {
        _playError =
            '재생할 수 없습니다.\n'
            '· 브라우저에서 로그인 세션이 만료되지 않았는지 확인해 주세요.\n'
            '· 아래 [내려받기]로 저장한 뒤 기기 음악 앱으로 열 수 있습니다.\n\n$e';
      });
    }
  }

  // ── 업로드 ─────────────────────────────────────────────────────────
  /// 업로드 진행률(0.0~1.0). null 이면 업로드 중이 아님.
  double? _upProgress;
  String? _upName;

  Future<void> _upload() async {
    // [수정] 예전에 쓰던 _WebFilePicker(자체 <input type=file> 브리지)는
    //  file_picker 8.x 가 웹을 정식 지원하면서 필요 없어졌다. 지금은
    //  _pickFileBytes() 하나로 웹·안드로이드 모두 같은 경로를 탄다.
    final picked = await _pickFileBytes();
    if (picked == null) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _upName = picked.name;
      _upProgress = 0;
    });
    try {
      final r = await _api.upload(
        name: picked.name,
        bytes: picked.bytes,
        sub: _sub,
        onProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() => _upProgress = (sent / total).clamp(0.0, 1.0));
        },
      );
      if (!mounted) return;
      setState(() {
        _upProgress = null;
        _upName = null;
      });
      if (r['ok'] == true) {
        messenger.showSnackBar(
          SnackBar(content: Text('업로드 완료: ${r['name']}')),
        );
        await _load();
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('업로드 실패: ${r['error'] ?? '알 수 없음'}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _upProgress = null;
        _upName = null;
      });
      messenger.showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
    }
  }

  Future<void> _download(EventResource r) async {
    final uri = Uri.parse(_api.streamUrl(r, download: true));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내려받기를 열 수 없습니다.')),
      );
    }
  }

  Future<void> _delete(EventResource r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('삭제'),
        content: Text('${r.name}\n\nNAS에서 완전히 삭제됩니다. 계속할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.taegeukRed),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final ok = await _api.delete(r);
      if (!mounted) return;
      if (ok) {
        if (_nowPlaying?.name == r.name) {
          await _player?.dispose();
          _player = null;
          _nowPlaying = null;
        }
        await _load();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('삭제하지 못했습니다.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  // ── 화면 ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // [요구] 폴더 칩으로 좁힌다. null = 전체.
    List<EventResource> narrowed(List<EventResource> src) =>
        _folderFilter == null
        ? src
        : src.where((e) => e.sub == _folderFilter).toList();

    final audio = narrowed(_data.byKind('audio'));
    final video = narrowed(_data.byKind('video'));
    final docs = narrowed([..._data.byKind('doc'), ..._data.byKind('image')]);
    final list = switch (_tab) {
      'audio' => audio,
      'video' => video,
      _ => docs,
    };

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '행사자료',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            Text(
              _sub.isEmpty
                  ? '01 행사자료 (업로드가능)'
                  : '01 행사자료 / $_sub',
              style: const TextStyle(fontSize: 10.5),
            ),
          ],
        ),
        actions: [
          // [요구 2026-10-30] "행사자료 관리 할 수 있도록, 특히 순서를 바꿀 수
          //  있도록" — 편집 모드 토글. 켜면 드래그 손잡이가 나타난다.
          IconButton(
            tooltip: _editMode ? '순서 편집 끝내기' : '순서 변경 (드래그)',
            icon: Icon(
              _editMode ? Icons.check_circle : Icons.swap_vert,
              color: _editMode ? AppColors.tigerGold : Colors.white,
            ),
            onPressed: _editMode
                ? _endEdit
                : () => setState(() => _editMode = true),
          ),
          IconButton(
            tooltip: '업로드 (음원·영상·문서)',
            icon: const Icon(Icons.upload_file),
            onPressed: _upload,
          ),
          // 관리 메뉴 — 정렬 초기화 / 외부 공유(QR) / 새로고침
          PopupMenuButton<String>(
            tooltip: '관리',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'reset':
                  _resetOrder();
                  break;
                case 'share':
                  _openShareSheet();
                  break;
                case 'refresh':
                  _load();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.restart_alt, size: 18),
                  title: Text('순서 초기화 (최신순)'),
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.qr_code_2, size: 18),
                  title: Text('음원 외부 공유 (QR)'),
                ),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh, size: 18),
                  title: Text('새로고침'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_upProgress != null) _uploadBar(),
          if (_nowPlaying != null) _playerBar(),
          _tabs(audio.length, video.length, docs.length),
          // [요구] 폴더 칩 — NAS 폴더 구조를 그대로 눌러서 좁힐 수 있게 한다.
          _folderChips(),
          if (_sub.isNotEmpty) _subBar(),
          if (_editMode && list.length > 1) _editBannerList(list),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _errorView()
                : list.isEmpty
                ? _emptyView()
                : RefreshIndicator(
                    onRefresh: () => _load(),
                    child: _editMode
                        ? _reorderList(list)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 6, 10, 24),
                            itemCount: list.length,
                            itemBuilder: (_, i) => _row(list[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 편집 모드 안내 막대.
  Widget _editBannerList(List<EventResource> list) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.tigerGold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.tigerGold.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator, size: 16, color: AppColors.hermesInk),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '손잡이를 끌어 순서를 바꾸세요 · 저장 중이 아니면 즉시 저장됩니다',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.hermesInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: _endEdit,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('완료', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  /// 드래그로 순서를 바꾸는 목록.
  ///
  /// [ReorderableListView] 를 쓰면 핸들 없이 길게 눌러 끌 수 있는데, 음원
  /// 행은 탭으로 재생되므로 **탭과 드래그가 충돌**한다. 그래서 편집 모드에서만
  /// 이 목록으로 교체하고, 행 오른쪽에 명시적 손잡이를 둔다.
  Widget _reorderList(List<EventResource> list) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 24),
      itemCount: list.length,
      onReorder: (oldIndex, newIndex) => _onReorder(list, oldIndex, newIndex),
      buildDefaultDragHandles: false,
      itemBuilder: (_, i) {
        final r = list[i];
        return ReorderableDragStartListener(
          key: ValueKey('${r.orderKey}#$i'),
          index: i,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
            ),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.purple.withValues(alpha: 0.10),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.purple,
                  ),
                ),
              ),
              title: Text(
                r.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${r.sub.isEmpty ? '음원' : r.sub} · ${r.ext.toUpperCase()}'
                '${r.sizeLabel.isEmpty ? '' : ' · ${r.sizeLabel}'}',
                style: const TextStyle(fontSize: 10, color: AppColors.textGray),
              ),
              trailing: const Icon(
                Icons.drag_handle,
                size: 20,
                color: AppColors.textGray,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onReorder(
    List<EventResource> list,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;
    final moved = List<EventResource>.from(list);
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    final item = moved.removeAt(oldIndex);
    moved.insert(target, item);
    setState(() => _savingOrder = true);
    final ok = await _api.reorder(moved);
    if (!mounted) return;
    setState(() => _savingOrder = false);
    if (ok) {
      // 서버가 저장한 순서를 그대로 다시 받아 화면과 일치시킨다.
      await _load(silent: true);
      _snack('순서를 저장했습니다');
    } else {
      _snack('순서 저장에 실패했습니다');
      await _load(silent: true);
    }
  }

  Future<void> _resetOrder() async {
    setState(() => _savingOrder = true);
    final ok = await _api.reorderReset(sub: '');
    if (!mounted) return;
    setState(() => _savingOrder = false);
    if (ok) {
      await _load(silent: true);
      _snack('순서를 최신순으로 초기화했습니다');
    } else {
      _snack('초기화에 실패했습니다');
    }
  }

  void _endEdit() {
    if (_savingOrder) {
      _snack('저장 중입니다. 잠시만 기다려 주세요');
      return;
    }
    setState(() => _editMode = false);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// 음원 외부 공유(QR) 시트.
  ///
  /// ## [요구 2026-10-30] "음원 폴더만 외부로 QR을 보내서 재생,
  ///  불특정 다수가 들어올 수 있으니 각별히 보안에 신경"
  ///
  /// 이 시트에서 발급하는 토큰은 **음원 읽기 전용**이며 세션과 무관하다.
  /// 만료일·폐기·사용횟수가 모두 보이고, 폐기하면 즉시 죽는다.
  Future<void> _openShareSheet() async {
    if (!context.read<AppState>().isApp) {
      _snack('관리자만 공유할 수 있습니다');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(
        api: _api,
        baseUrl: context.read<NasApi>().baseUrl,
        initialSub: _folderFilter ?? _sub,
        onChanged: () => _load(silent: true),
      ),
    );
  }

  /// 업로드 진행 막대 — 큰 영상은 수십 초 걸린다. 진행률이 없으면
  /// 앱이 멈춘 것처럼 보이므로 반드시 보여 준다.
  Widget _uploadBar() {
    final p = _upProgress ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_upload, size: 15, color: AppColors.purple),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _upName ?? '업로드 중…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text(
                '${(p * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 5,
              backgroundColor: AppColors.purple.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(AppColors.purple),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs(int a, int v, int d) {
    Widget chip(String key, String label, int n, IconData icon) {
      final on = _tab == key;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = key),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? AppColors.purple : Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: on ? 1 : 0.25),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: on ? Colors.white : AppColors.purple,
                ),
                const SizedBox(height: 2),
                Text(
                  '$label $n',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: on ? Colors.white : AppColors.purple,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(7, 8, 7, 4),
      child: Row(
        children: [
          chip('audio', '음원', a, Icons.music_note),
          chip('video', '영상', v, Icons.movie_outlined),
          chip('doc', '문서·기타', d, Icons.description_outlined),
        ],
      ),
    );
  }

  /// 폴더 칩 — `전체` + 실제 NAS 하위 폴더들.
  ///
  /// 폴더가 하나도 없으면 아무것도 그리지 않는다(빈 줄로 공간 낭비 금지).
  Widget _folderChips() {
    final folders = _data.folders;
    if (folders.isEmpty) return const SizedBox.shrink();
    // 폴더가 여러 개일 때만 '전체' 칩을 보여 준다.
    final showAll = folders.length > 1;
    Widget chip(String? key, String label, int count) {
      final on = _folderFilter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: () => setState(() {
            _folderFilter = key;
            _sub = key ?? '';
          }),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: on
                  ? AppColors.purple.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: on ? 0.9 : 0.25),
                width: on ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  on ? Icons.folder_open : Icons.folder_outlined,
                  size: 13,
                  color: AppColors.purple,
                ),
                const SizedBox(width: 4),
                Text(
                  count > 0 ? '$label ($count)' : label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: on ? FontWeight.w900 : FontWeight.w600,
                    color: AppColors.purple,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 폴더별 파일 수 — 마지막 조각 이름으로 묶는다.
    int countOf(String sub) =>
        _data.files.where((e) => e.sub == sub).length;

    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (showAll)
            chip(null, '전체', _data.files.length),
          for (final f in folders)
            chip(f, f.contains('/') ? f.split('/').last : f, countOf(f)),
        ],
      ),
    );
  }

  Widget _subBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _load(sub: ''),
            icon: const Icon(Icons.arrow_upward, size: 15),
            label: const Text('상위 폴더', style: TextStyle(fontSize: 11.5)),
          ),
          Expanded(
            child: Text(
              _data.folders.isEmpty ? '' : '하위 폴더 ${_data.folders.length}개',
              style: const TextStyle(fontSize: 10.5, color: AppColors.textGray),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 44, color: AppColors.taegeukRed),
          const SizedBox(height: 10),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _load(),
            child: const Text('다시 시도'),
          ),
        ],
      ),
    ),
  );

  Widget _emptyView() => ListView(
    children: [
      const SizedBox(height: 60),
      const Icon(Icons.library_music_outlined, size: 48, color: AppColors.textGray),
      const SizedBox(height: 10),
      const Center(
        child: Text(
          '자료가 없습니다.',
          style: TextStyle(fontSize: 13, color: AppColors.textGray),
        ),
      ),
      const SizedBox(height: 6),
      const Center(
        child: Text(
          '오른쪽 위 ⬆ 버튼으로 mp3·mp4·pdf 를 올리거나\n'
          'PC에서 NAS 의 "01 행사자료 (업로드가능)" 폴더에 넣으면\n'
          '여기에 그대로 나타납니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.textGray, height: 1.5),
        ),
      ),
    ],
  );

  Widget _row(EventResource r) {
    final playing = _nowPlaying?.name == r.name && _nowPlaying?.sub == r.sub;
    final icon = r.isAudio
        ? Icons.music_note
        : r.isVideo
        ? Icons.movie_outlined
        : r.isImage
        ? Icons.image_outlined
        : Icons.description_outlined;
    final color = r.isAudio
        ? AppColors.hermesInk
        : r.isVideo
        ? AppColors.taegeukBlue
        : AppColors.purple;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: r.playable ? () => _play(r) : () => _download(r),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      [
                        if (r.sub.isNotEmpty) r.sub,
                        r.ext.toUpperCase(),
                        if (r.sizeLabel.isNotEmpty) r.sizeLabel,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
              if (playing)
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.graphic_eq,
                    size: 17,
                    color: AppColors.scoutGreen,
                  ),
                ),
              IconButton(
                tooltip: '내려받기',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.download, size: 18),
                onPressed: () => _download(r),
              ),
              IconButton(
                tooltip: '삭제',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.taegeukRed,
                ),
                onPressed: () => _delete(r),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 하단 재생 바 — 진행 막대·재생/정지·닫기.
  Widget _playerBar() {
    final c = _player;
    final ready = c != null && c.value.isInitialized;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _nowPlaying!.isVideo
                    ? Icons.movie_outlined
                    : Icons.music_note,
                size: 17,
                color: AppColors.hermesInk,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _nowPlaying!.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (ready)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 22,
                  ),
                  onPressed: () {
                    if (c.value.isPlaying) {
                      c.pause();
                    } else {
                      c.play();
                    }
                    setState(() {});
                  },
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '닫기',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () async {
                  await _player?.dispose();
                  setState(() {
                    _player = null;
                    _nowPlaying = null;
                  });
                },
              ),
            ],
          ),
          // VideoPlayerValue 에는 isVideo 가 없다(오디오도 같은 컨트롤러를 쓴다).
          // 화면 표시 여부는 **파일 종류**로 판단한다 — mp3 에 검은 네모가
          // 생기지 않도록 하는 게 목적.
          if (ready && (_nowPlaying?.isVideo ?? false))
            AspectRatio(
              aspectRatio: c.value.aspectRatio == 0
                  ? 16 / 9
                  : c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          if (ready)
            VideoProgressIndicator(
              c,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: AppColors.purple,
                bufferedColor: Color(0x335B2C8D),
                backgroundColor: Color(0x11000000),
              ),
              padding: const EdgeInsets.only(top: 4),
            ),
          if (_playError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: Text(
                _playError!,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.taegeukRed,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 파일 선택 — `file_picker` 를 **바이트로** 받아온다.
///
/// ## 왜 multipart 가 아니라 바이트인가
/// 멀티파트는 헤더 안의 **한글 파일명** 인코딩이 브라우저마다 달라
/// (RFC 2231/5987) 프록시 파서가 깨지기 쉽다. 파일명은 쿼리로 따로 보내고
/// 본문은 순수 바이트로 보내면 인코딩 문제가 원천적으로 사라진다.
class _PickedFile {
  const _PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

Future<_PickedFile?> _pickFileBytes() async {
  final res = await FilePicker.platform.pickFiles(
    withData: true, // 웹/모바일 모두 바이트를 즉시 받는다
    allowMultiple: false,
    type: FileType.any,
  );
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.first;
  final bytes = f.bytes;
  if (bytes == null || bytes.isEmpty) return null;
  return _PickedFile(f.name, bytes);
}

/// ── 음원 외부 공유(QR) 시트 ────────────────────────────────────────────
///
/// ## 보안 요약 (사용자에게 이 화면에서 그대로 보여 준다)
///  · 이 링크로 할 수 있는 일은 **음원 듣기 하나뿐**이다.
///    회원명단·재정·업로드·삭제는 서버에서 코드 경로 자체가 열리지 않는다.
///  · 만료일이 지나면 자동으로 죽고, [폐기] 를 누르면 즉시 죽는다.
///  · 로그인 정보(세션)는 링크에 **한 글자도** 담기지 않는다.
class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.api,
    required this.baseUrl,
    required this.initialSub,
    required this.onChanged,
  });

  final EventResourceApi api;
  final String baseUrl;
  final String initialSub;
  final VoidCallback onChanged;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  int _days = 30;
  bool _busy = false;
  ShareToken? _made;
  List<Map<String, dynamic>> _items = const [];
  bool _loadingList = true;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    try {
      final items = await widget.api.listShares();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loadingList = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingList = false);
    }
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    final t = await widget.api.createShare(
      sub: widget.initialSub,
      days: _days,
      label: widget.initialSub.isEmpty ? '행사자료 전체 음원' : widget.initialSub,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _made = t;
    });
    if (t == null) {
      _msg('공유 링크 발급에 실패했습니다');
    } else {
      await _loadList();
      widget.onChanged();
    }
  }

  Future<void> _revoke(String id) async {
    final ok = await widget.api.revokeShare(id);
    if (!mounted) return;
    _msg(ok ? '공유를 중지했습니다 (즉시 무효)' : '중지에 실패했습니다');
    await _loadList();
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _msg('링크를 복사했습니다');
  }

  String _fmtDate(int sec) {
    if (sec <= 0) return '-';
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.'
        '${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.initialSub.isEmpty ? '전체 (01 행사자료)' : widget.initialSub;
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
            14,
            10,
            14,
            18 + MediaQuery.of(context).viewInsets.bottom,
          ),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.textGray.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Row(
              children: [
                Icon(Icons.qr_code_2, size: 20, color: AppColors.purple),
                SizedBox(width: 7),
                Text(
                  '음원 외부 공유 (QR)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '대상: $scope',
              style: const TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            _securityBox(),
            const SizedBox(height: 12),
            // ── 기간 선택 ──
            Row(
              children: [
                const Text(
                  '공유 기간',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                for (final d in const [7, 30, 90])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$d일', style: const TextStyle(fontSize: 11)),
                      selected: _days == d,
                      onSelected: (_) => setState(() => _days = d),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 42,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                ),
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_link, size: 18),
                label: Text(_busy ? '발급 중…' : '공유 링크 발급'),
              ),
            ),
            if (_made != null) ...[
              const SizedBox(height: 12),
              _madeCard(_made!),
            ],
            const SizedBox(height: 18),
            const Text(
              '발급된 링크',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            if (_loadingList)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  '아직 발급한 링크가 없습니다',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
                ),
              )
            else
              for (final it in _items) _itemTile(it),
          ],
        ),
      ),
    );
  }

  Widget _securityBox() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: AppColors.scoutGreen.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.scoutGreen.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined,
                  size: 15, color: AppColors.scoutGreen),
              const SizedBox(width: 5),
              const Text(
                '이 링크로 할 수 있는 일은 음원 듣기 뿐입니다',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.scoutGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            '· 회원 명단·재정·업로드·삭제는 서버에서 차단됩니다\n'
            '· 만료일이 지나면 자동 폐기, [중지] 누르면 즉시 폐기\n'
            '· 로그인 정보는 링크에 담기지 않습니다\n'
            '· 사용 횟수와 마지막 접속이 기록됩니다',
            style: TextStyle(fontSize: 10, height: 1.55, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }

  Widget _madeCard(ShareToken t) {
    final url = t.playUrl(widget.baseUrl);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '새 링크가 만들어졌습니다',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          SelectableText(
            url,
            style: const TextStyle(fontSize: 10, color: AppColors.purple),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _copy(url),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: AppColors.purple,
                ),
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('링크 복사', style: TextStyle(fontSize: 10.5)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: AppColors.textGray,
                ),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('미리보기', style: TextStyle(fontSize: 10.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemTile(Map<String, dynamic> it) {
    final revoked = it['revoked'] == true;
    final expired = it['expired'] == true;
    final dead = revoked || expired;
    final id = '${it['id'] ?? ''}';
    final hits = (it['hits'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dead
              ? AppColors.textGray.withValues(alpha: 0.3)
              : AppColors.purple.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${it['label'] ?? ''}'.isEmpty
                      ? '${it['sub'] ?? '전체'}'
                      : '${it['label']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: dead ? AppColors.textGray : AppColors.textDark,
                  ),
                ),
                Text(
                  '만료 ${_fmtDate((it['exp'] as num?)?.toInt() ?? 0)}'
                  ' · 사용 $hits회'
                  '${dead ? (revoked ? ' · 중지됨' : ' · 만료됨') : ''}',
                  style: const TextStyle(
                      fontSize: 9.5, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          if (!dead)
            TextButton(
              onPressed: () => _revoke(id),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: AppColors.taegeukRed,
              ),
              child: const Text('중지', style: TextStyle(fontSize: 10.5)),
            ),
        ],
      ),
    );
  }
}
