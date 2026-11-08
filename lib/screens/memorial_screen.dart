// 추모관 화면 — "故 노경하 선배님을 기리는 자리".
//
// ── 요구 (원문, 2026-11-04) ────────────────────────────────────────────
//  "선배님과의 추억 사진을 올려달라는 글과 파일을 첨부 및 아카이빙 할 수
//   있도록 하며, 올라온 글과 사진들은 다른 사람들도 모두 확인할 수 있도록
//   추모글 및 사진 및 자료를 한번에 모아서 볼 수 있도록 구성해줘.
//   즉 올린글 게시판은 별도로 운영하지만 올렸던 글은 다른 창(첫창)에서
//   직관적으로 모두 볼 수 있도록 설계하고, 상부에 추모글 쓰기나 자료 올리기
//   등을 노출해서 자발적 참여를 할 수 있도록 해줘. 관리자나 마스터 혹은
//   글 쓴이는 그 글을 가리거나 삭제 이동 편집 할 수 있도록 해줘.
//   공감버튼 댓글기능도 넣도록 해줘."
//  "게시판에 故 범2호 노경하 선배님 추모관련 페이지를 만들어주고 누구든
//   글을 쓸 수 있도록 하고 인가자는 자기 번호를 함께 쓸 수 있도록 해줘"
//
// ── 이 화면이 지키는 것 ────────────────────────────────────────────────
//  ① 상부 CTA 3종(추모글·사진·자료)을 **가장 먼저** 노출 → 자발적 참여.
//  ② 글·사진·자료를 **한 피드에 섞어서** 보여준다(= 첫창 통합 타임라인).
//     탭으로 종류를 골라 볼 수 있되 기본값은 '전체'.
//  ③ 글쓴이(editKey 보유)·관리자·마스터에게만 편집/가리기/삭제 버튼 노출.
//     단, **실제 차단은 서버**가 한다(앱은 편의상 숨길 뿐).
//  ④ 공감(토글) + 댓글.
//
// ── 로그인 없이도 동작해야 한다 ────────────────────────────────────────
//  서버가 `/api/memorial/*` 을 전역 인증 게이트에서 제외했으므로 세션이
//  없어도 호출된다. 앱은 이미 로그인한 상태가 대부분이라 세션 헤더를
//  함께 보내고, 관리자면 서버가 '가려진 글'까지 내려준다.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/memorial_api.dart';
import '../theme/app_theme.dart';
import '../widgets/tsak_app_bar.dart';

// ════════════════════════════════════════════════════════════════════════
//  파일 종류 판정 — 서버(proxy_server.py)의 IMAGE_EXT / VIDEO_EXT 와 동일
// ════════════════════════════════════════════════════════════════════════
//
// ## 왜 화면 밖(최상위)에 두는가
//  편집 시트(_MemorialEditorSheetState)와 본문 화면(_MemorialScreenState)
//  **양쪽에서 같은 규칙**을 써야 한다. 한쪽에만 두면 "업로드할 때는 사진,
//  목록에서는 자료"처럼 어긋나 사용자가 사진을 잃어버린 것처럼 느낀다.
//
// ## 왜 확장자로 판정하는가
//  서버의 `isImage` 응답만 믿으면, '자료 올리기' 경로로 들어온 사진이
//  자료로 굳는다([요구 2026-11-04] "사진폴더에 노출시켜줘"). 업로드 응답과
//  저장된 URL 어느 쪽이든 확장자는 남아 있으므로, 확장자로 한 번 더
//  확인하는 것이 가장 확실하다.
const List<String> _kMemImageExt = [
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.bmp',
  '.heic',
];
const List<String> _kMemVideoExt = [
  '.mp4',
  '.mov',
  '.webm',
  '.m4v',
  '.avi',
  '.mkv',
  '.3gp',
];

bool _memExtIn(String s, List<String> exts) {
  final t = s.toLowerCase().split('?').first;
  return exts.any(t.endsWith);
}

bool _memIsImage(String s) => _memExtIn(s, _kMemImageExt);
bool _memIsVideo(String s) => _memExtIn(s, _kMemVideoExt);

/// 사진 앨범 한 칸 — 사진 1장 + **올린 사람**.
///
/// [요구 2026-11-04] "사진 밑에 올린 사람 이름을 써주면 돼 / 만약에 범 Scout
///  인가자의 경우 이름의 괄호 안에 번호를 써주면 돼"
///
///  인가번호는 **있을 때만** 괄호로 붙인다. 비인가자(일반 참배객)가 쓴 글은
///  번호가 비어 있는데, 그때 `홍길동 ()` 처럼 빈 괄호가 나오면 지저분하다.
class _MemPhotoItem {
  const _MemPhotoItem({
    required this.postId,
    required this.url,
    required this.thumb,
    required this.name,
    required this.number,
  });

  final String postId;

  /// 원본 주소 — 크게 볼 때만 쓴다.
  final String url;

  /// 격자용 축소본(480px JPEG). 없으면 [url] 과 같다.
  final String thumb;

  final String name;
  final String number;

  /// 영상인가 — 칸에 ▶ 배지를 붙이고, 누르면 재생기를 띄운다.
  bool get isVideo => MemorialPost.isVideoUrl(url);

  /// 화면에 쓸 이름 — `이승준 (415)` / 번호 없으면 `이승준`.
  String get label {
    final n = name.trim().isEmpty ? '익명' : name.trim();
    final num = number.trim();
    if (num.isEmpty) return n;
    return '$n ($num)';
  }
}

class MemorialScreen extends StatefulWidget {
  const MemorialScreen({
    super.key,
    this.memorialId = MemorialApi.defaultMemorialId,
    this.embedded = false,
  });

  final String memorialId;

  /// true 면 AppBar 없이 본문만 (다른 화면 탭에 넣을 때).
  final bool embedded;

  @override
  State<MemorialScreen> createState() => _MemorialScreenState();
}

class _MemorialScreenState extends State<MemorialScreen> {
  late MemorialApi _api;

  bool _loading = true;
  String? _error;
  MemorialData? _data;

  /// '전체' | '글' | '사진' | '자료'
  String _filter = '전체';

  /// 내가 고칠 수 있는 글 id (로컬 editKey 보유).
  final Set<String> _mine = {};

  /// 이 기기의 공감 식별키 — 브라우저/기기당 1회만 공감되게 한다.
  String _likeKey = '';

  /// 후원계좌 3종 + 예금주 (서버에서 받아온다 — 하드코딩 금지).
  List<Map<String, String>> _accounts = const [];
  String _holder = '';

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _api = MemorialApi(context.read<AppState>().nas);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await _ensureLikeKey();
    await _load();
  }

  /// 공감 식별키 — 없으면 만들어 기기에 저장한다.
  Future<void> _ensureLikeKey() async {
    final auth = await _api.recallAuthor();
    // 이름/번호 저장소와 같은 SharedPreferences 를 쓰되 키는 별도.
    _likeKey =
        'lk${auth['name']?.hashCode ?? 0}${DateTime.now().millisecondsSinceEpoch}';
    if (_likeKey.length > 40) _likeKey = _likeKey.substring(0, 40);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.load(id: widget.memorialId);
      // 내가 쓴 글 표시 — editKey 가 기기에 남아 있는 글.
      final mine = <String>{};
      for (final p in d.posts) {
        if (await _api.canEdit(widget.memorialId, p.id)) mine.add(p.id);
      }
      if (!mounted) return;
      setState(() {
        _data = d;
        _mine
          ..clear()
          ..addAll(mine);
        _loading = false;
      });
      // 계좌는 부가 정보 — 본문 표시를 막지 않도록 따로 받아 뒤늦게 채운다.
      final acc = await _api.loadAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = acc.accounts;
        _holder = acc.holder;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<MemorialPost> get _visible {
    final all = _data?.posts ?? const <MemorialPost>[];
    // [요구 2026-11-04] "사진, 추모글 이렇게 구분하지 말고 게시글로 통합"
    //  → '전체'는 종류와 상관없이 **모든 게시글**이다.
    if (_filter == '전체') return all;
    // '사진+영상'은 글 단위가 아니라 앨범(_photoAlbum)으로 그리므로 여기서는
    // 쓰이지 않지만, 안전하게 미디어 보유 글을 돌려준다.
    if (_filter == '사진+영상') return all.where((p) => p.hasMedia).toList();
    if (_filter == '자료') return all.where((p) => p.hasOtherFile).toList();
    return all;
  }

  /// 사진 탭에 뿌릴 **낱장 사진** 목록.
  ///
  /// [요구 2026-11-04] "사진 폴더를 클릭하면 사진이 포함된 게시글을 보여 주는
  ///  것이 아니라 첨부된 사진만 보여 주면 돼 / 그리고 사진 밑에 올린 사람
  ///  이름을 써주면 돼 / 만약에 범 Scout 인가자의 경우 이름의 괄호 안에
  ///  번호를 써주면 돼"
  ///
  /// ## 왜 글 단위가 아니라 사진 단위인가
  ///  종전 사진 탭은 `kind == '사진'` 인 **글 카드**를 그대로 나열했다.
  ///  사진을 보려는 사람에게 긴 추모 문구와 댓글창이 먼저 보여서, 정작
  ///  찾던 사진은 스크롤을 내려야 나왔다. 앨범처럼 **사진만** 늘어놓는다.
  ///
  /// ## 순서
  ///  최신 글이 위로 오도록 `_data.posts` 순서를 그대로 따르고, 한 글 안의
  ///  사진은 올린 순서를 유지한다(대표 사진이 먼저).
  List<_MemPhotoItem> get _photoItems {
    final all = _data?.posts ?? const <MemorialPost>[];
    final out = <_MemPhotoItem>[];
    for (final p in all) {
      if (p.hidden) continue; // 가린 글의 사진은 앨범에도 넣지 않는다
      for (final u in p.photos) {
        if (u.isEmpty) continue;
        out.add(
          _MemPhotoItem(
            postId: p.id,
            url: u,
            thumb: p.thumbOf(u),
            name: p.name,
            number: p.number,
          ),
        );
      }
    }
    return out;
  }

  // ── 작성/수정 시트 ───────────────────────────────────────────────────
  Future<void> _openEditor({
    MemorialPost? edit,
    bool photoFirst = false,
    bool fileFirst = false,
  }) async {
    // ⚠️ editKey 는 **시트를 띄우기 전에** 읽어야 한다.
    //  `showModalBottomSheet` 의 builder 는 동기 함수라, 그 안에서 await 를
    //  쓰면 "await_in_wrong_context" 컴파일 오류가 난다.
    final key = edit == null
        ? ''
        : await _api.editKeyOf(widget.memorialId, edit.id);
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemorialEditorSheet(
        api: _api,
        memorialId: widget.memorialId,
        edit: edit,
        photoFirst: photoFirst,
        fileFirst: fileFirst,
        editKey: key,
      ),
    );
    if (saved == true) await _load();
  }

  // ── 글 관리(가리기/삭제/이동) ────────────────────────────────────────
  Future<void> _manage(MemorialPost p) async {
    final isAdmin = _data?.isAdmin == true;
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('편집'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                p.hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              title: Text(p.hidden ? '다시 보이기' : '가리기'),
              onTap: () => Navigator.pop(context, p.hidden ? 'unhide' : 'hide'),
            ),
            if (isAdmin)
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('다른 추모관으로 이동'),
                onTap: () => Navigator.pop(context, 'move'),
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.taegeukRed,
              ),
              title: const Text(
                '삭제',
                style: TextStyle(color: AppColors.taegeukRed),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (act == null || !mounted) return;

    if (act == 'edit') {
      await _openEditor(edit: p);
      return;
    }
    if (act == 'move') {
      // 추모관이 하나뿐이면 이동할 곳이 없다 — 솔직하게 알린다.
      _snack('아직 다른 추모관이 없어 이동할 곳이 없습니다.');
      return;
    }
    if (act == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('글을 삭제할까요?'),
          content: const Text('삭제한 글은 되돌릴 수 없습니다.\n가리기로 두면 남겨둘 수 있습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.taegeukRed,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      await _api.delete(
        id: widget.memorialId,
        postId: p.id,
        action: act,
        editKey: await _api.editKeyOf(widget.memorialId, p.id),
      );
      await _load();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleLike(MemorialPost p) async {
    try {
      final r = await _api.toggleLike(
        id: widget.memorialId,
        postId: p.id,
        likeKey: _likeKey,
      );
      if (!mounted) return;
      // 서버가 최종값을 준다 — 그대로 반영(낙관적 갱신 안 함 = 불일치 없음).
      setState(() {
        final list = _data?.posts;
        if (list != null) {
          final i = list.indexWhere((x) => x.id == p.id);
          if (i >= 0) {
            final old = list[i];
            list[i] = MemorialPost(
              id: old.id,
              name: old.name,
              number: old.number,
              body: old.body,
              created: old.created,
              updated: old.updated,
              hidden: old.hidden,
              kind: old.kind,
              photos: old.photos,
              media: old.media,
              mediaItems: old.mediaItems,
              hasOtherFile: old.hasOtherFile,
              attachments: old.attachments,
              likeCount: r.count,
              comments: old.comments,
            );
          }
        }
      });
    } catch (e) {
      _snack('$e');
    }
  }

  /// 댓글 남기기 — **이름·인가번호를 요구하지 않는다**.
  ///
  /// [구조 변경 2026-11-08 / turn56]
  ///  지적: *"댓글 등록하려고 하니 글쓴이 정보가 뜸 /
  ///         댓글은 글쓴이 글에 대한 다른 사람의 피드백임 구조 변경 필요함"*
  ///
  ///  ## 종전 구조의 문제
  ///   글쓰기와 댓글이 같은 '신원 입력'을 요구했다. 댓글 대화상자에
  ///   이름·인가번호 칸이 나와서, 한 줄 인사를 남기려는 사람에게
  ///   명부 등록 같은 부담을 지웠다. 심지어 웹은 이름이 없으면
  ///   **글쓰기 시트를 통째로** 띄웠다.
  ///
  ///  ## 새 구조 — '글 = 신원 필요 / 댓글 = 신원 불필요'
  ///   · 글쓰기 : 종전대로 이름(필수)·인가번호(선택). 추모글의 주인은
  ///              남겨야 하므로 유지한다.
  ///   · 댓글   : **본문 한 칸만** 받는다. 이름은 기기에 적어둔 값이 있으면
  ///              조용히 그대로 쓰고, 없으면 '익명'으로 보낸다.
  ///              (서버는 name 이 빈 값이어도 받고, 목록은 '익명'으로 그린다)
  ///  → 댓글 등록이 '탭 → 입력 → 등록' 세 동작으로 끝난다.
  Future<void> _addComment(MemorialPost p) async {
    final auth = await _api.recallAuthor();
    if (!mounted) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('댓글 남기기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(hintText: '따뜻한 말 한마디 남겨주세요'),
            ),
            const SizedBox(height: 10),
            Text(
              '댓글은 글에 대한 짧은 인사말입니다.\n'
              '이름은 따로 묻지 않으며, 비우면 익명으로 남습니다.',
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: AppColors.textGray,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('남기기'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (ctrl.text.trim().isEmpty) return;
    // 이름은 기억해 둔 값이 있으면 그대로, 없으면 '익명'.
    final nmSaved = (auth['name'] ?? '').trim();
    final nm = nmSaved.isEmpty ? '익명' : nmSaved;
    // 익명 댓글에는 인가번호를 붙이지 않는다(남의 번호로 오인될 수 있음).
    final no = nm == '익명' ? '' : (auth['number'] ?? '').trim();
    try {
      await _api.addComment(
        id: widget.memorialId,
        postId: p.id,
        name: nm,
        number: no,
        body: ctrl.text.trim(),
      );
      // 기억해 둔 이름은 **덮어쓰지 않는다**. 익명으로 남긴 댓글이
      //  다음 글쓰기의 기본 이름을 '익명'으로 바꿔버리면 안 되기 때문.
      if (nmSaved.isNotEmpty) {
        await _api.rememberAuthor(nmSaved, no);
      }
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _openWeb() {
    final base = context.read<AppState>().nas.baseUrl.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    launchUrl(
      Uri.parse('$base/memorial?id=${widget.memorialId}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        title: const Text('추모관'),
        actions: [
          IconButton(
            tooltip: '공유 링크 열기 (로그인 없이 참여)',
            onPressed: _openWeb,
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.purple,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('추모글 쓰기'),
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: AppColors.textGray),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }
    final d = _data!;
    return RefreshIndicator(
      onRefresh: _load,
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _hero(d),
              _ctaBar(),
              _videoCard(d),
              _stats(d),
              _tabs(),
              // ── 사진 탭은 **앨범**이다 ────────────────────────────────
              //  [요구 2026-11-04] "사진 폴더를 클릭하면 사진이 포함된 게시글을
              //   보여 주는 것이 아니라 첨부된 사진만 보여 주면 돼"
              //  글 카드 대신 사진 낱장만 격자로 깐다. 사진을 누르면 크게
              //  보이고, 아래 이름표를 누르면 그 글로 이동한다.
              if (_filter == '사진+영상')
                _photoAlbum()
              else if (_visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 44),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.local_florist_outlined,
                        size: 36,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _filter == '전체'
                            ? '아직 남겨진 기억이 없습니다.\n첫 마음을 남겨주세요.'
                            : '이 종류의 기록이 아직 없습니다.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textGray,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ..._visible.map(_postCard),
              // ── 후원계좌 3종 (하단) ──────────────────────────────────
              //  [요구 2026-11-04] "추모페이지에 후원계좌 3종 하단에 넣어줘"
              //  · 서버가 준 계좌만 그린다(하드코딩 없음 → 중앙회 설정 변경 시
              //    웹/앱 동시 반영). 계좌가 없으면 섹션 자체를 숨긴다.
              if (_accounts.isNotEmpty) _donationSection(),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black.withValues(alpha: 0.06),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  // ── 상단 영정(hero) ─────────────────────────────────────────────────
  Widget _hero(MemorialData d) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.purpleDark, AppColors.purple, Color(0xFF5E3D9A)],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 106,
            height: 106,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE8D9B0), width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: d.photoUrl.isEmpty
                  ? const Icon(Icons.person, size: 52, color: Colors.white70)
                  : Image.network(
                      _api.fileUrl('/${d.photoUrl}'),
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.15),
                      color: Colors.white.withValues(alpha: 0.08),
                      colorBlendMode: BlendMode.saturation,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person,
                        size: 52,
                        color: Colors.white70,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            d.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            d.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Container(width: 52, height: 2.5, color: const Color(0xFFB8964F)),
          const SizedBox(height: 10),
          Text(
            d.years,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── 상부 참여 버튼 2종 ───────────────────────────────────────────────
  //
  // [요구 2026-11-06 / turn66]
  //   "자료 버튼을 삭제하고 첨부한 파일의 디자인으로 통일하고 /
  //    사진-> 사진+영상 으로 변경"
  //
  //  · '자료' CTA 삭제 — 게시글 작성 시 첨부로만 받는다. 탭에는 남겨 둔다
  //    (이미 올라온 문서를 골라 보는 길은 필요하다).
  //  · '사진' → '사진+영상' — 바로 아래 탭 이름과 낱말을 맞춘다. 버튼 이름이
  //    '사진'인데 폴더에는 영상도 들어 있으면 사용자는 영상이 빠진 줄 안다.
  //  · 2개가 되었으므로 `Expanded` 가 남는 폭을 정확히 반반 나눈다(줄바꿈 없음).
  //  · 웹(memorial.html `.cta-bar`)도 같은 구성·같은 문구로 맞췄다.
  Widget _ctaBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Row(
        children: [
          _cta('✍️', '추모글', '기억 남기기', () => _openEditor()),
          const SizedBox(width: 8),
          _cta('📷', '사진+영상', '추억 올리기', () => _openEditor(photoFirst: true)),
        ],
      ),
    );
  }

  Widget _cta(String ico, String label, String sub, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.purple.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.16)),
          ),
          child: Column(
            children: [
              Text(ico, style: const TextStyle(fontSize: 19)),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                sub,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 대표 추모영상 (이찬희 총재) — 스트리밍 카드 ────────────────────────
  //
  // [요구 2026-11-06 / turn65~66]
  //   "한국스카우트 이찬희 총재 추모영상을 업로드 후 스트리밍 재생해줘"
  //   "…총재님 영상 스트리밍만 추가해줘"
  //
  // ## 자료 버튼을 지운 자리에 영상만 남긴다
  //  CTA 2개 아래에 카드 하나. 웹(memorial.html `.vidcard`)과 같은 자리·
  //  같은 모양이다. 어느 추모관에 어떤 영상이 붙는지는 **서버가 정한다**
  //  (`MemorialData.video`). 앱에 파일명을 적지 않으므로, NAS 에서 영상을
  //  교체해도 앱과 웹이 동시에 새 영상을 가리킨다.
  Widget _videoCard(MemorialData d) {
    final list = d.videos;
    if (list.isEmpty) return const SizedBox.shrink();

    // 카드가 여럿이면 9px 간격으로 위에서 아래로 쌓는다.
    //  순서는 서버 `videos` 배열 순서 그대로 — 화면에서 정렬하지 않는다.
    //  웹(memorial.html `.vidlist`)과 같은 간격·같은 순서다.
    final cards = <Widget>[];
    for (var i = 0; i < list.length; i++) {
      final v = list[i];
      if (i > 0) cards.add(const SizedBox(height: 9));
      cards.add(_MemorialHeroVideoCard(
        url: _api.fileUrl('${v['url'] ?? ''}'),
        posterUrl: _api.fileUrl('${v['posterUrl'] ?? ''}'),
        title: '${v['title'] ?? '추모영상'}',
        subtitle: '${v['subtitle'] ?? ''}',
        durationLabel: '${v['durationLabel'] ?? ''}',
      ));
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Column(children: cards),
    );
  }

  // ── 통계 4종 ────────────────────────────────────────────────────────
  Widget _stats(MemorialData d) {
    Widget one(String label, int v) => Expanded(
      child: Column(
        children: [
          Text(
            '$v',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.purple,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textGray),
          ),
        ],
      ),
    );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          one('게시글', d.posts.where((p) => !p.hidden).length),
          one('사진+영상', d.mediaTotal),
          one('자료', d.docPostTotal),
          one('공감', d.likeTotal),
        ],
      ),
    );
  }

  // ── 종류 필터 ───────────────────────────────────────────────────────
  Widget _tabs() {
    // [요구 2026-11-04] "사진 폴더 이름을 사진+영상 으로 변경하고 사진과
    //  영상 자료는 그 폴더에서 통합해서 보여 줘"
    //  · '전체' = 게시글 (사진·글 구분 없이 전부)
    //  · '사진+영상' = 첨부된 사진과 영상을 한 폴더에서
    //  · '자료' = PDF·문서 등 미디어가 아닌 첨부
    const items = ['전체', '사진+영상', '자료'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: items.map((f) {
          final on = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: ChoiceChip(
              label: Text(f == '전체' ? '게시글' : f),
              selected: on,
              onSelected: (_) => setState(() => _filter = f),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                color: on ? Colors.white : AppColors.textGray,
              ),
              selectedColor: AppColors.purple,
              backgroundColor: AppColors.bg,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 사진 앨범 (사진 탭) ─────────────────────────────────────────────
  //
  // [요구 2026-11-04]
  //   "사진 폴더를 클릭하면 사진이 포함된 게시글을 보여 주는 것이 아니라
  //    첨부된 사진만 보여 주면 돼
  //    그리고 사진 밑에 올린 사람 이름을 써주면 돼
  //    만약에 범 Scout 인가자의 경우 이름의 괄호 안에 번호를 써주면 돼"
  //
  // ## 왜 글 카드를 그대로 쓰면 안 되는가
  //  사진을 보러 온 사람에게 긴 추모 문구·공감 버튼·댓글창이 먼저 보이면
  //  정작 사진은 한참 스크롤해야 나온다. 앨범은 **사진이 주인공**이어야 한다.
  //
  // ## 배치
  //  3열 격자. 사진만 늘어놓고, 각 칸 **아래**에 올린 사람을 작게 적는다
  //  (`이승준 (415)`). 이름표를 누르면 그 사진이 실린 글로 내려간다 —
  //  사진을 보고 "누가, 어떤 글에" 올렸는지 궁금해지는 흐름을 막지 않는다.
  //
  // ## 성능
  //  `GridView` 를 `shrinkWrap` 으로 ListView 안에 넣으면 사진이 많을 때
  //  전부 레이아웃해 버린다. 여기서는 한 줄씩 `Row` 로 직접 깔아 **보이는
  //  만큼만** 만들고, 이미지는 `cacheWidth` 로 디코딩 크기를 줄인다
  //  (고해상도 원본 20장을 그대로 디코딩하면 메모리가 급증한다).
  Widget _photoAlbum() {
    final items = _photoItems;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 44),
        child: Column(
          children: const [
            Icon(
              Icons.photo_library_outlined,
              size: 36,
              color: AppColors.textGray,
            ),
            SizedBox(height: 10),
            Text(
              '아직 올려진 사진이 없습니다.\n사진 올리기로 첫 사진을 남겨주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textGray, height: 1.6),
            ),
          ],
        ),
      );
    }

    const int cols = 3;
    const double gap = 8;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += cols) {
      final slice = items.sublist(i, (i + cols).clamp(0, items.length));
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < cols; c++)
                Expanded(
                  child: c < slice.length
                      ? Padding(
                          padding: EdgeInsets.only(left: c == 0 ? 0 : gap),
                          child: _photoCell(slice[c]),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 사진이 몇 장인지 한 줄로 알려준다(숫자와 화면이 어긋나지 않게).
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              '사진+영상 ${items.length}개',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textGray,
              ),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }

  /// 앨범 한 칸 — 사진 또는 영상 1건 + 그 아래 올린 사람.
  ///
  /// [요구 2026-11-04] "사진과 영상 자료는 그 폴더에서 통합해서 보여 줘"
  ///  · 사진  : 정사각 썸네일, 누르면 크게 보기
  ///  · 영상  : 같은 크기의 칸에 ▶ 배지를 얹고, 누르면 앱 안에서 재생
  ///  (영상 썸네일을 만들려면 서버에서 프레임을 추출해야 하므로, 지금은
  ///   어두운 카드 + ▶ 로 "영상"임을 즉시 알 수 있게 한다.)
  Widget _photoCell(_MemPhotoItem it) {
    // 격자에는 **축소본**을 쓴다(원본 4~5MB → 25KB). 크게 볼 때만 원본.
    final url = _api.fileUrl(it.thumb);
    final full = _api.fileUrl(it.url);
    if (it.isVideo) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => _viewVideo(full, it.url),
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3D1B63), Color(0xFF5B2C8D)],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 34,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _whoLabel(it),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => _viewImage(full),
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                // 원본을 화면 크기로 축소해 디코딩한다(메모리 절약).
                cacheWidth: 480,
                loadingBuilder: (_, child, prog) => prog == null
                    ? child
                    : Container(
                        color: AppColors.bg,
                        child: const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.bg,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    size: 22,
                    color: AppColors.textGray,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _whoLabel(it),
      ],
    );
  }

  /// 앨범 칸 아래 이름표 — `이승준 (415)` / 비인가자는 `홍길동`.
  Widget _whoLabel(_MemPhotoItem it) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
      child: Text(
        it.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  // ── 게시글 카드 ─────────────────────────────────────────────────────
  Widget _postCard(MemorialPost p) {
    final isAdmin = _data?.isAdmin == true;
    final canManage = isAdmin || _mine.contains(p.id);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 작성자 + 종류 배지
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name.isEmpty ? '익명의 범스카우트' : p.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        if (p.number.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.tigerGold.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '범 ${p.number}',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.lifetimeGold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${p.created}${p.hidden ? ' · 가려짐' : ''}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
              // [요구 2026-11-04] "사진, 추모글 이렇게 구분하지 말고
              //  게시글로 통합해 주고" → 종류 배지를 없앤다.
              //  사진이든 글이든 모두 '게시글'로 본다.
              if (canManage)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: '관리',
                  icon: const Icon(Icons.more_vert, size: 18),
                  onPressed: () => _manage(p),
                ),
            ],
          ),
          if (p.body.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(p.body, style: const TextStyle(fontSize: 13.5, height: 1.62)),
          ],
          if (p.photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            _photoStrip(p),
          ],
          if (p.attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...p.attachments.map(_fileRow),
          ],
          const Divider(height: 20),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _toggleLike(p),
                icon: const Icon(
                  Icons.favorite,
                  size: 16,
                  color: Color(0xFFD64550),
                ),
                label: Text(
                  '공감 ${p.likeCount}',
                  style: const TextStyle(fontSize: 11.5, height: 1),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textGray,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              TextButton.icon(
                onPressed: () => _addComment(p),
                icon: const Icon(Icons.chat_bubble_outline, size: 15),
                label: Text(
                  '댓글 ${p.comments.length}',
                  style: const TextStyle(fontSize: 11.5, height: 1),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textGray,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (p.comments.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: p.comments.map((c) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDark,
                          height: 1.55,
                        ),
                        children: [
                          TextSpan(
                            text:
                                '${c.name.isEmpty ? '익명' : c.name}'
                                '${c.number.isNotEmpty ? '(${c.number})' : ''}  ',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                              color: AppColors.purple,
                            ),
                          ),
                          TextSpan(text: c.body),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _photoStrip(MemorialPost p) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: p.photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          // 목록의 작은 띠에도 축소본을 쓴다(스크롤이 즉시 반응).
          final url = _api.fileUrl(p.thumbOf(p.photos[i]));
          final full = _api.fileUrl(p.photos[i]);
          return GestureDetector(
            onTap: () => _viewImage(full),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.network(
                url,
                width: 104,
                height: 104,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 104,
                  height: 104,
                  color: AppColors.bg,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    size: 22,
                    color: AppColors.textGray,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 후원계좌 3종 (하단) ─────────────────────────────────────────────
  //
  // [요구 2026-11-04]  "추모페이지에 후원계좌 3종 하단에 넣어줘
  //                     문의: 이승준 (010-6322-7558)"
  //
  // ## 계좌를 앱에 적어두지 않은 이유
  //  같은 내용을 웹(memorial.html)과 앱이 각각 들고 있으면, 중앙회가 계좌를
  //  바꿀 때 한쪽만 고쳐져 서로 다른 번호가 안내된다. 그래서 **서버 설정
  //  (config.json 의 donations)** 을 유일한 출처로 삼고, 앱은
  //  `/api/memorial/accounts` 로 받아 그리기만 한다.
  //
  // ## 이 구역이 하는 일
  //  ① 계좌마다 [이름 · 은행 · 계좌번호] 를 한 줄로 보여주고,
  //  ② 줄을 누르면 계좌번호가 **클립보드에 복사**된다(입금할 때 오타 방지),
  //  ③ 예금주를 명시하고,
  //  ④ 마지막에 문의처(이승준 010-6322-7558)를 **눌러서 전화** 로 붙인다.
  Widget _donationSection() {
    Widget row(Map<String, String> a) {
      final label = (a['label'] ?? '').trim();
      final bank = (a['bank'] ?? '').trim();
      final no = (a['account'] ?? '').trim();
      return InkWell(
        // 계좌번호가 비어 있으면 복사할 것이 없다 → 눌러도 아무 일 없게.
        onTap: no.isEmpty
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: no));
                _snack('계좌번호를 복사했습니다 : $no');
              },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label.isNotEmpty)
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          no,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.purple,
                            letterSpacing: 0.2,
                          ),
                        ),
                        if (bank.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              bank,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textGray,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.copy_rounded,
                size: 15,
                color: AppColors.textGray,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.purple.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🌼', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '후원 계좌 안내',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        '선배님을 기리는 자리에 마음을 보태주시는 분들을 위하여',
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.4,
                          color: AppColors.textGray.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._accounts.map(row),
            if (_holder.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Text(
                  '예금주 : $_holder',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              '입금자명에 성함을 남겨주시면 감사히 기록하겠습니다.',
              style: TextStyle(
                fontSize: 9.5,
                height: 1.5,
                color: AppColors.textGray.withValues(alpha: 0.95),
              ),
            ),
            const Divider(height: 18),
            // 문의 — [요구] "문의: 이승준 (010-6322-7558)"
            //  번호를 눌러 바로 전화할 수 있게 tel: 로 연결한다.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '문의 : ',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                ),
                InkWell(
                  onTap: () => launchUrl(Uri.parse('tel:01063227558')),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                    child: Text(
                      '이승준 010-6322-7558',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.taegeukBlue,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.taegeukBlue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(Map<String, dynamic> a) {
    final name = '${a['name'] ?? '자료'}';
    final url = _api.fileUrl('${a['url'] ?? ''}');
    final isVideo = _isVideoName(name) || _isVideoName('${a['url'] ?? ''}');

    // ── 영상은 "다운로드 링크"가 아니라 **재생 카드**로 보여준다 ─────────
    //  [turn53] 500MB 상한으로 영상이 실제로 올라오게 되면서, 링크만 던져
    //  주면 사용자는 내려받아야만 볼 수 있었다. 서버가 Range(206)를 지원
    //  하므로 앱 안에서 바로 재생·되감기가 된다.
    if (isVideo && url.isNotEmpty) {
      return _MemorialVideoTile(url: url, name: name);
    }

    return InkWell(
      onTap: url.isEmpty ? null : () => launchUrl(Uri.parse(url)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(
              isVideo ? Icons.videocam_outlined : Icons.attach_file,
              size: 15,
              color: AppColors.textGray,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.taegeukBlue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 파일명/URL 이 영상인가. 서버의 `VIDEO_EXT` 와 같은 목록을 쓴다.
  bool _isVideoName(String s) => _memIsVideo(s);

  /// 앨범에서 영상을 눌렀을 때 — 앱 안에서 바로 재생한다.
  ///
  /// [요구 2026-11-04] "사진과 영상 자료는 그 폴더에서 통합해서 보여 줘"
  ///  폴더에서 영상을 눌렀는데 새 탭/다운로드로 튕기면 통합의 의미가 없다.
  ///  서버가 Range(206)를 지원하므로 재생기에 URL 만 넘기면 된다.
  void _viewVideo(String url, String rawName) {
    final name = rawName.split('/').last;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: _MemorialVideoTile(url: url, name: name),
        ),
      ),
    );
  }

  void _viewImage(String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(40),
              child: Icon(Icons.broken_image_outlined, color: Colors.white54),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  대표 추모영상 카드 — 누르면 그 자리에서 스트리밍 재생
// ════════════════════════════════════════════════════════════════════════
//
// ## 왜 카드 + 다이얼로그인가
//  목록 최상단에서 영상이 곧바로 자동 로드되면, 추모관을 열기만 해도
//  37MB 영상의 첫 구간을 받기 시작한다. 조용히 추모글을 읽으러 온
//  분들께도 트래픽이 나간다. → **포스터만 먼저** 보여주고, 누를 때
//  재생기를 만든다. 재생기는 기존 `_MemorialVideoTile` 을 그대로 쓴다
//  (Range 스트리밍·일시정지·되감기·dispose 정리까지 이미 검증된 코드).
//
// ## 포스터
//  영상 오프닝 타이틀 카드(0~5초)를 쓴다. 살아 계신 총재님의 얼굴을
//  추모 화면 첫 이미지로 크게 걸지 않기 위한 선택이다(얼굴은 8초 이후).
class _MemorialHeroVideoCard extends StatelessWidget {
  const _MemorialHeroVideoCard({
    required this.url,
    required this.posterUrl,
    required this.title,
    required this.subtitle,
    required this.durationLabel,
  });

  final String url;
  final String posterUrl;
  final String title;
  final String subtitle;
  final String durationLabel;

  void _open(BuildContext context) {
    if (url.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: _MemorialVideoTile(url: url, name: title),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.16)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 썸네일 (16:9) ──────────────────────────────────────
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (posterUrl.isNotEmpty)
                        Image.network(
                          posterUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: const Color(0xFF0F1724)),
                        )
                      else
                        Container(color: const Color(0xFF0F1724)),
                      // ▶ 는 **좌측 하단**. 포스터(타이틀 카드)의 글자가
                      //  화면 가운데 있어서, 가운데 버튼을 얹으면 제목을 가린다.
                      const Positioned(
                        left: 10,
                        bottom: 10,
                        child: _HeroPlayButton(),
                      ),
                      if (durationLabel.isNotEmpty)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              durationLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // ── 제목·설명 ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: AppColors.purple,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 카드 위의 둥근 재생 버튼(장식 — 실제 탭은 카드 전체가 받는다).
class _HeroPlayButton extends StatelessWidget {
  const _HeroPlayButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 6)),
        ],
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: AppColors.purpleDark,
        size: 28,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  영상 재생 카드 — 올린 영상을 앱 안에서 바로 본다
// ════════════════════════════════════════════════════════════════════════
//
// ## 배경 (turn53)
//  업로드 상한을 500MB 로 올려 영상이 실제로 올라오게 되자, 목록에서는
//  "링크를 눌러 내려받기"만 가능했다. 추모 영상을 보려는 어르신들께
//  다운로드는 너무 높은 문턱이다. 서버에 Range(206) 지원을 넣었으므로
//  앱에서 바로 재생·되감기가 가능해졌다.
//
// ## 메모리
//  `VideoPlayerController.networkUrl` 은 플랫폼 재생기(ExoPlayer/AVPlayer/
//  <video>)에 URL 을 넘긴다. 앱이 파일을 통째로 들고 있지 않고, 재생기가
//  필요한 구간만 Range 로 요청한다. 500MB 영상도 앱 메모리를 먹지 않는다.
//
// ## 화면을 떠날 때
//  dispose 에서 반드시 컨트롤러를 정리한다. 안 하면 재생이 계속되어
//  배터리와 트래픽을 축낸다.
class _MemorialVideoTile extends StatefulWidget {
  const _MemorialVideoTile({required this.url, required this.name});

  final String url;
  final String name;

  @override
  State<_MemorialVideoTile> createState() => _MemorialVideoTileState();
}

class _MemorialVideoTileState extends State<_MemorialVideoTile> {
  VideoPlayerController? _c;
  bool _failed = false;

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
        await c.dispose();
        return;
      }
      setState(() => _c = c);
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;

    // 재생기를 열 수 없을 때(코덱 미지원·회선 문제) — 링크는 남겨 둔다.
    if (_failed) {
      return InkWell(
        onTap: () => launchUrl(Uri.parse(widget.url)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                size: 15,
                color: AppColors.textGray,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${widget.name} (재생할 수 없어 새 창에서 엽니다)',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.taegeukBlue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (c == null) {
      return Container(
        height: 84,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final v = c.value;
    final pos = v.position;
    final dur = v.duration;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(c),
                // 큰 재생/일시정지 버튼 — 작은 화면에서도 누르기 쉽게.
                Material(
                  color: Colors.black.withValues(alpha: 0.32),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      setState(() {
                        v.isPlaying ? c.pause() : c.play();
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: Icon(
                        v.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 되감기 — Range 서빙 덕분에 원하는 지점으로 바로 이동한다.
          VideoProgressIndicator(
            c,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: AppColors.tigerGold,
              bufferedColor: Colors.white24,
              backgroundColor: Colors.white10,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Row(
              children: [
                Text(
                  '${_fmt(pos)} / ${_fmt(dur)}',
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  작성/수정 시트 — 글·사진·자료를 한 곳에서
// ════════════════════════════════════════════════════════════════════════
class _MemorialEditorSheet extends StatefulWidget {
  const _MemorialEditorSheet({
    required this.api,
    required this.memorialId,
    this.edit,
    this.editKey = '',
    this.photoFirst = false,
    this.fileFirst = false,
  });

  final MemorialApi api;
  final String memorialId;
  final MemorialPost? edit;
  final String editKey;

  /// 열리자마자 사진/자료 선택 창을 띄울지(상부 CTA 구분용).
  final bool photoFirst;
  final bool fileFirst;

  @override
  State<_MemorialEditorSheet> createState() => _MemorialEditorSheetState();
}

class _MemorialEditorSheetState extends State<_MemorialEditorSheet> {
  final _name = TextEditingController();
  final _num = TextEditingController();
  final _body = TextEditingController();

  /// 업로드 완료된 사진 URL
  final List<String> _photos = [];

  /// 업로드 완료된 자료 {name,url,size}
  final List<Map<String, dynamic>> _files = [];

  bool _saving = false;
  bool _uploading = false;
  String? _err;

  /// 업로드 진행률 (진행 중인 파일의 전송 바이트 / 전체 바이트).
  ///  500MB 영상은 회선에 따라 몇 분이 걸린다. 아무 표시가 없으면 사용자는
  ///  앱이 멈춘 줄 알고 창을 닫아 버린다 → 반드시 숫자로 보여준다.
  int _upSent = 0;
  int _upTotal = 0;
  String _upName = '';

  /// 여러 파일을 한 번에 올릴 때의 진행 위치 (예: 2/5).
  int _upIndex = 0;
  int _upCount = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      _name.text = e.name;
      _num.text = e.number;
      _body.text = e.body;
      _photos.addAll(e.photos);
      _files.addAll(e.attachments);
    } else {
      // 이전에 쓴 이름·번호를 자동으로 채운다(반복 입력 부담 제거).
      widget.api.recallAuthor().then((a) {
        if (!mounted) return;
        setState(() {
          if (_name.text.isEmpty) _name.text = a['name'] ?? '';
          if (_num.text.isEmpty) _num.text = a['number'] ?? '';
        });
      });
    }
    if (widget.photoFirst) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _pick(imagesOnly: true),
      );
    } else if (widget.fileFirst) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _pick(imagesOnly: false),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _num.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool imagesOnly}) async {
    setState(() => _err = null);
    final picked = await pickDataFiles(
      allowedExtensions: imagesOnly
          ? const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic']
          // 500MB 상한에 맞춰 **영상(mp4/mov/webm/m4v/avi/mkv/3gp)** 도 받는다.
          //  [요구 2026-11-04] "용량 500메가로 늘리고" — 추모 영상이 주 목적.
          : const [
              'jpg',
              'jpeg',
              'png',
              'gif',
              'webp',
              'heic',
              'pdf',
              'doc',
              'docx',
              'hwp',
              'hwpx',
              'txt',
              'ppt',
              'pptx',
              'xls',
              'xlsx',
              'mp4',
              'mov',
              'webm',
              'm4v',
              'avi',
              'mkv',
              '3gp',
            ],
      allowMultiple: true,
      dialogTitle: imagesOnly ? '추억 사진 선택' : '자료 선택',
    );
    if (picked.isEmpty || !mounted) return;

    // ── [요구 2026-11-04] "여러 파일을 선택해서 올릴 수 있도록" ──────────
    //  ① 이미 담긴 개수 + 새로 고른 개수가 서버 상한(50)을 넘으면
    //     **보내기 전에** 알린다(올리고 나서 거절당하면 헛수고).
    //  ② 초과분을 조용히 버리지 않고 몇 개가 빠졌는지 명시한다.
    //
    // ── [요구 2026-11-06] 상한 20 → **50** ────────────────────────────
    //  요구(원문): "한번에 올릴 수 있는 사진수 제한을 50장으로 늘릴 것"
    //  ⚠️ proxy_server.py 의 MEM_MAX_MEDIA 와 **반드시 같은 값**.
    //     서버가 20 인데 앱이 50 이면 21장째부터 400 으로 거절당한다.
    const int maxMedia = 50;
    var list = picked.toList();
    final already = _photos.length + _files.length;
    if (already + list.length > maxMedia) {
      final room = maxMedia - already;
      if (room <= 0) {
        setState(() => _err = '사진·자료는 한 글에 $maxMedia개까지 담을 수 있습니다');
        return;
      }
      final dropped = list.length - room;
      list = list.sublist(0, room);
      setState(
        () => _err =
            '$maxMedia개까지만 담을 수 있어 $dropped개는 제외했습니다'
            ' (이미 $already개 있음)',
      );
    }

    setState(() => _uploading = true);
    try {
      var idx = 0;
      for (final f in list) {
        idx++;
        // 여러 개를 올릴 때 "몇 번째인지"가 보여야 진행이 체감된다.
        _upIndex = idx;
        _upCount = list.length;
        // 서버 상한은 **500MB** 다(사진·문서·영상 포함).
        //  [요구 2026-11-04] "용량 500메가로 늘리고"
        //  서버가 거절할 크기를 먼저 알려 헛수고를 막는다.
        if (f.bytes.length > 500 * 1024 * 1024) {
          setState(() => _err = '${f.name}: 500MB 를 넘어 올릴 수 없습니다');
          continue;
        }
        if (mounted) {
          setState(() {
            _upName = f.name;
            _upSent = 0;
            _upTotal = f.bytes.length;
            // 파일마다 속도 측정을 새로 시작한다.
            _upStart = null;
            _upMark = null;
            _upMarkSent = 0;
            _upBps = 0;
          });
        }
        final j = await widget.api.upload(
          id: widget.memorialId,
          name: f.name,
          bytes: Uint8List.fromList(f.bytes),
          // 500MB 는 몇 분이 걸린다 — 멈춘 것처럼 보이지 않게 진행률을 그린다.
          onProgress: (sent, total) {
            if (!mounted) return;
            setState(() {
              _upSent = sent;
              _upTotal = total;
              _upTick(sent, total);
            });
          },
        );
        final url = '${j['url'] ?? ''}';
        if (url.isEmpty) continue;
        // ── [요구 2026-11-04] "첨부파일로 올린 자료도 사진, 영상일 경우
        //      사진폴더에 노출시켜줘"
        //
        //  종전에는 서버의 `isImage` 만 보고 갈랐다. 그래서 '자료 올리기'로
        //  들어온 사진·영상은 (isImage=false 이므로) 곧장 자료 목록으로
        //  들어갔고, 저장 시 kind='자료' 가 되어 **사진 폴더에서 사라졌다**.
        //
        //  → 올린 파일의 **실물 종류**를 기준으로 가른다.
        //     · 이미지  → 사진 목록 (사진 탭에 노출)
        //     · 영상    → 자료 목록 (재생 카드로 표시)
        //     · 그 외   → 자료 목록
        //  서버도 읽을 때 같은 규칙으로 다시 판정하므로 이중으로 안전하다.
        final fname = '${j['name'] ?? f.name}';
        final isImg = j['isImage'] == true || _memIsImage(fname);
        if (isImg) {
          _photos.add(url);
        } else {
          _files.add({
            'name': fname,
            'url': url,
            'size': j['size'] ?? f.bytes.length,
          });
        }
      }
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _upSent = 0;
          _upTotal = 0;
          _upName = '';
        });
      }
    }
  }

  /// 바이트 → "12.3" 형태의 MB 문자열 (진행률 표시용).
  String _mb(int bytes) {
    if (bytes <= 0) return '0';
    final m = bytes / (1024 * 1024);
    return m >= 100 ? m.toStringAsFixed(0) : m.toStringAsFixed(1);
  }

  /// 남은 예상 시간 — 최근 3초 구간의 전송 속도로 계산한다.
  ///
  /// 전체 평균을 쓰면 회선이 잠깐 느려졌을 때 남은 시간이 크게 튄다.
  /// 최근 구간 속도로 계산하면 숫자가 훨씬 덜 흔들린다.
  DateTime? _upStart;
  DateTime? _upMark;
  int _upMarkSent = 0;
  double _upBps = 0;

  void _upTick(int sent, int total) {
    final now = DateTime.now();
    _upStart ??= now;
    _upMark ??= now;
    final dt = now.difference(_upMark!).inMilliseconds / 1000.0;
    if (dt >= 1.0) {
      final inst = (sent - _upMarkSent) / dt;
      // 지수 평활 — 급격한 흔들림 완화.
      _upBps = _upBps == 0 ? inst : (_upBps * 0.6 + inst * 0.4);
      _upMark = now;
      _upMarkSent = sent;
    }
  }

  String _etaText() {
    if (_upBps < 1024 || _upTotal <= 0) return '';
    final remain = (_upTotal - _upSent) / _upBps;
    if (!remain.isFinite || remain <= 0) return '';
    if (remain < 60) return '약 ${remain.ceil()}초 남음';
    final m = (remain / 60).ceil();
    if (m < 60) return '약 $m분 남음';
    return '약 ${(m / 60).round()}시간 남음';
  }

  Future<void> _save() async {
    if (_body.text.trim().isEmpty && _photos.isEmpty && _files.isEmpty) {
      setState(() => _err = '글이나 사진·자료를 하나는 넣어주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await widget.api.savePost(
        id: widget.memorialId,
        postId: widget.edit?.id ?? '',
        name: _name.text.trim(),
        number: _num.text.trim(),
        body: _body.text.trim(),
        photos: _photos,
        attachments: _files,
        editKey: widget.editKey,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _err = '$e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.edit != null;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  isEdit ? '기억 다듬기' : '故 노경하 선배님을 기억하며',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: '이름',
                          isDense: true,
                          hintText: '익명도 좋습니다',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 108,
                      child: TextField(
                        controller: _num,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '인가번호',
                          isDense: true,
                          hintText: '선택',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '인가자는 자기 번호를 함께 남길 수 있습니다 (선택).',
                  style: TextStyle(fontSize: 10, color: AppColors.textGray),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _body,
                  maxLines: 6,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    hintText: '선배님과의 추억, 배운 점, 전하고 싶은 마음을 적어주세요.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _uploading
                          ? null
                          : () => _pick(imagesOnly: true),
                      icon: const Icon(Icons.photo_camera_outlined, size: 17),
                      label: const Text('사진', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 7),
                    OutlinedButton.icon(
                      onPressed: _uploading
                          ? null
                          : () => _pick(imagesOnly: false),
                      icon: const Icon(Icons.attach_file, size: 17),
                      label: const Text('자료', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 9),
                    if (_uploading)
                      const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (_photos.isNotEmpty || _files.isNotEmpty)
                      Text(
                        '사진 ${_photos.length} · 자료 ${_files.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.scoutGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                // 500MB 영상은 몇 분 걸린다 — 진행률을 숫자로 보여준다.
                if (_uploading && _upTotal > 0) ...[
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _upTotal == 0 ? null : _upSent / _upTotal,
                          minHeight: 6,
                          backgroundColor: AppColors.bg,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.purple,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_upName.isEmpty ? '업로드' : _upName} · '
                              '${_mb(_upSent)} / ${_mb(_upTotal)} MB'
                              '${_upCount > 1 ? '  ($_upIndex/$_upCount)' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textGray,
                              ),
                            ),
                          ),
                          // 남은 시간 안내 — "멈춘 건가?" 하는 불안을 없앤다.
                          if (_upTotal > 0 && _upSent < _upTotal)
                            Text(
                              _etaText(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.purple,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
                // 상한 안내 — [요구 2026-11-04] 25MB → 500MB, 여러 개 선택
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '사진·문서·영상 1건당 최대 500MB, 한 글에 50개까지 올릴 수 있습니다.\n'
                    '위 버튼을 누르면 여러 개를 한 번에 선택할 수 있습니다.',
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.5,
                      color: AppColors.textGray,
                    ),
                  ),
                ),
                if (_photos.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  SizedBox(
                    height: 62,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.network(
                              widget.api.fileUrl(_photos[i]),
                              width: 62,
                              height: 62,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 62,
                                height: 62,
                                color: AppColors.bg,
                                child: const Icon(Icons.image, size: 18),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: InkWell(
                              onTap: () => setState(() => _photos.removeAt(i)),
                              child: Container(
                                padding: const EdgeInsets.all(1.5),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_files.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...List.generate(_files.length, (i) {
                    return Row(
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          size: 14,
                          color: AppColors.textGray,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${_files[i]['name'] ?? '자료'}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _files.removeAt(i)),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 13,
                              color: AppColors.textGray,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
                if (_err != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _err!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.taegeukRed,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: _saving || _uploading ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isEdit ? '수정 저장' : '남기기',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '로그인 없이 남길 수 있습니다. 남긴 글은 이 기기에서 수정·삭제할 수 있어요.',
                  style: TextStyle(fontSize: 10, color: AppColors.textGray),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
