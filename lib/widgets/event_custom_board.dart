// 행사 커스텀 게시판 — '메뉴 추가'로 만든 탭이 **게시판**으로 동작한다.
//
// [요구 2026-10-26]
//   "행사관리 메뉴 중 메뉴를 추가할 경우 게시판 기능을 활성화시켜주고,
//    첨부파일을 올릴 수 있는 게시판도 생성해줘. 즉, 후기 게시판처럼 글쓰기
//    기능을 추가하고 첨부파일을 올리고 다운받고 확인할 수 있도록 해줘.
//    추가 게시판의 열람권한은 관리자는 기본이지만, 모든 회원에게 노출할지
//    여부를 해당 게시판 상단에 선택 버튼을 넣어줘."
//
// 설계 원칙(기존 코드 재사용 — 새 업로드 경로를 만들지 않는다):
//   · 첨부 업로드  : `nas.eventUpload2(year,title,'review',name,bytes)`
//                    → NAS 의 `06_후기첨부_(업로드가능)` 폴더(후기 게시판과 동일)
//   · 첨부 다운로드: `nas.eventFile2Url(year,title,'review',name)`
//   · 글/권한 저장 : `/api/event/cboard/*` (프록시)
//   · 이미지 미리보기: `nas.eventThumb2Url(...)` — 실패 시 아이콘으로 폴백
//
// 권한 모델:
//   · 관리자(app/master) 는 항상 열람·작성.
//   · 일반 회원은 게시판의 `openToAll` 이 true 일 때만 열람·작성.
//   · 상단의 스위치(관리자에게만 보임)로 즉시 토글된다.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';

class EventCustomBoard extends StatefulWidget {
  const EventCustomBoard({
    super.key,
    required this.year,
    required this.title,
    this.boardId = '',
    required this.boardName,
    this.note = '',
    this.embedded = true,
  });

  final String year;
  final String title;
  final String boardId;
  final String boardName;
  final String note;
  final bool embedded;

  @override
  State<EventCustomBoard> createState() => _EventCustomBoardState();
}

class _EventCustomBoardState extends State<EventCustomBoard> {
  NasApi get _nas => context.read<AppState>().nas;

  bool _loading = true;
  String? _error;
  bool _openToAll = false;
  bool _isAdmin = false;
  List<Map<String, dynamic>> _posts = [];
  bool _busy = false;
  String _bid = '';

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
      var bid = widget.boardId;
      if (bid.isEmpty) {
        // 이름만 넘어온 경우: 서버 목록에서 찾고, 없으면 새로 만든다.
        final ls = await _nas.customBoards(widget.year, widget.title);
        for (final b in ((ls['boards'] as List?) ?? [])) {
          final m = (b as Map).cast<String, dynamic>();
          if ('${m['name'] ?? ''}' == widget.boardName) {
            bid = '${m['id'] ?? ''}';
            break;
          }
        }
        if (bid.isEmpty) {
          final cr = await _nas.customBoardCreate(
            year: widget.year,
            title: widget.title,
            name: widget.boardName,
            note: widget.note,
          );
          bid = '${cr['id'] ?? ''}';
        }
        _bid = bid;
      }
      final d = await _nas.customBoardGet(
        widget.year,
        widget.title,
        bid,
      );
      if (!mounted) return;
      if (d['ok'] != true) {
        setState(() {
          _loading = false;
          _error = d['error'] == 'forbidden'
              ? '이 게시판은 아직 모든 회원에게 공개되지 않았습니다.'
              : '게시판을 불러오지 못했습니다.';
        });
        return;
      }
      final board = (d['board'] as Map?)?.cast<String, dynamic>() ?? {};
      setState(() {
        _openToAll = board['openToAll'] == true;
        _isAdmin = d['isAdmin'] == true;
        _posts = ((d['posts'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '게시판을 불러오지 못했습니다.\n$e';
      });
    }
  }

  Future<void> _toggleOpenToAll() async {
    setState(() => _busy = true);
    try {
      final r = await _nas.customBoardToggle(
        year: widget.year,
        title: widget.title,
        id: _bid.isEmpty ? widget.boardId : _bid,
      );
      if (!mounted) return;
      if (r['ok'] == true) {
        setState(() => _openToAll = r['openToAll'] == true);
        _snack(_openToAll ? '모든 회원에게 공개했습니다' : '관리자만 볼 수 있게 했습니다');
      } else {
        _snack('권한을 바꾸지 못했습니다');
      }
    } catch (_) {
      if (mounted) _snack('권한을 바꾸지 못했습니다');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// 글 작성/수정 — 첨부 추가·삭제, 다운로드까지 한 화면에서.
  Future<void> _editPost([Map<String, dynamic>? post]) async {
    final bodyCtrl = TextEditingController(text: '${post?['body'] ?? ''}');
    final authorCtrl = TextEditingController(text: '${post?['author'] ?? ''}');
    final numberCtrl = TextEditingController(text: '${post?['number'] ?? ''}');
    final attachments = <String>[
      ...(((post?['attachments'] as List?) ?? []).map((e) => '$e')),
    ];
    var uploading = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(
            post == null ? '글쓰기 · ${widget.boardName}' : '글 수정',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: authorCtrl,
                          decoration: const InputDecoration(labelText: '작성자'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: numberCtrl,
                          decoration: const InputDecoration(labelText: '인가번호'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bodyCtrl,
                    autofocus: post == null,
                    minLines: 5,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: '내용',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: uploading
                            ? null
                            : () async {
                                final picked = await pickDataFiles(
                                  allowMultiple: true,
                                  dialogTitle: '${widget.boardName} 첨부',
                                );
                                if (picked.isEmpty) return;
                                setD(() => uploading = true);
                                for (final f in picked) {
                                  try {
                                    await _nas.eventUpload2(
                                      widget.year,
                                      widget.title,
                                      'review',
                                      f.name,
                                      f.bytes,
                                      uploader: authorCtrl.text.trim(),
                                    );
                                    attachments.add(f.name);
                                  } catch (_) {
                                    // 개별 실패는 건너뛰고 나머지를 계속 올린다.
                                  }
                                }
                                setD(() => uploading = false);
                              },
                        icon: const Icon(Icons.attach_file, size: 16),
                        label: const Text('첨부 추가'),
                      ),
                      const SizedBox(width: 10),
                      if (uploading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Text(
                          '${attachments.length}개',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textGray,
                          ),
                        ),
                    ],
                  ),
                  if (attachments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final a in attachments)
                          Chip(
                            label: Text(
                              a,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 15),
                            onDeleted: () => setD(() => attachments.remove(a)),
                          ),
                      ],
                    ),
                  ],
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
              onPressed: uploading ? null : () => Navigator.pop(ctx, true),
              child: Text(post == null ? '등록' : '저장'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final r = await _nas.customBoardPost(
        year: widget.year,
        title: widget.title,
        boardId: _bid.isEmpty ? widget.boardId : _bid,
        id: '${post?['id'] ?? ''}',
        author: authorCtrl.text.trim(),
        number: numberCtrl.text.trim(),
        body: bodyCtrl.text,
        attachments: attachments,
      );
      if (!mounted) return;
      if (r['ok'] == true) {
        _snack(post == null ? '글을 등록했습니다' : '글을 저장했습니다');
        await _load();
      } else {
        _snack('저장하지 못했습니다 (${r['error'] ?? '오류'})');
      }
    } catch (e) {
      if (mounted) _snack('저장하지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('글 삭제'),
        content: const Text('이 글을 삭제할까요? 첨부파일은 NAS에 그대로 남습니다.'),
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
    if (yes != true || !mounted) return;
    // 작성자 본인 확인용 값은 글에 저장된 값을 그대로 되돌려 보낸다.
    // (관리자는 서버가 tier 로 판단하므로 이 값과 무관하게 삭제 가능)
    final ok = await _nas.customBoardDelete(
      year: widget.year,
      title: widget.title,
      boardId: _bid.isEmpty ? widget.boardId : _bid,
      postId: '${post['id'] ?? ''}',
      author: '${post['author'] ?? ''}',
      number: '${post['number'] ?? ''}',
    );
    if (!mounted) return;
    if (ok) {
      _snack('삭제했습니다');
      await _load();
    } else {
      _snack('삭제하지 못했습니다 (권한 확인)');
    }
  }

  Future<void> _openAttachment(String name) async {
    final url = _nas.eventFile2Url(widget.year, widget.title, 'review', name);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: SizedBox(
          width: 520,
          height: 420,
          child: _isImage(name)
              ? InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text('이미지를 불러오지 못했습니다'),
                    ),
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.description_outlined, size: 56),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '미리보기를 지원하지 않는 형식입니다.\n[저장]을 눌러 내려받으세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await launchUrl(
                Uri.parse(_nas.eventFile2Url(
                  widget.year,
                  widget.title,
                  'review',
                  name,
                  download: true,
                )),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('저장'),
          ),
        ],
      ),
    );
  }

  static bool _isImage(String n) {
    final e = n.toLowerCase();
    return e.endsWith('.jpg') ||
        e.endsWith('.jpeg') ||
        e.endsWith('.png') ||
        e.endsWith('.gif') ||
        e.endsWith('.webp') ||
        e.endsWith('.bmp');
  }

  String _fmtWhen(String s) {
    if (s.length >= 12) {
      return '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)} '
          '${s.substring(8, 10)}:${s.substring(10, 12)}';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: _errorPane())
        else if (_posts.isEmpty)
          Expanded(child: _emptyPane())
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
                itemCount: _posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _postCard(_posts[i]),
              ),
            ),
          ),
      ],
    );
  }

  /// 상단 바 — 게시판 이름 + **열람 권한 선택 버튼**(관리자에게만 보임).
  Widget _header() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6E1D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.forum_outlined, size: 18,
                  color: AppColors.purple),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.boardName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!_loading && _error == null)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _editPost(),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text(
                    '글쓰기',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                ),
            ],
          ),
          if (widget.note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.note,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textGray,
              ),
            ),
          ],
          // ── 열람 권한 선택 버튼 (요구: "게시판 상단에 선택 버튼") ──────
          if (_isAdmin) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
              decoration: BoxDecoration(
                color: _openToAll
                    ? AppColors.scoutGreen.withValues(alpha: 0.08)
                    : AppColors.purple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _openToAll
                      ? AppColors.scoutGreen.withValues(alpha: 0.40)
                      : AppColors.purple.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _openToAll
                        ? Icons.groups_outlined
                        : Icons.lock_outline,
                    size: 16,
                    color: _openToAll
                        ? AppColors.scoutGreen
                        : AppColors.purple,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _openToAll
                          ? '모든 회원 열람·작성 가능'
                          : '관리자만 열람 (기본)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _openToAll
                            ? AppColors.scoutGreen
                            : AppColors.purple,
                      ),
                    ),
                  ),
                  Switch(
                    value: _openToAll,
                    onChanged: _busy ? null : (_) => _toggleOpenToAll(),
                    activeThumbColor: AppColors.scoutGreen,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyPane() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forum_outlined, size: 44, color: AppColors.textGray),
          const SizedBox(height: 10),
          const Text(
            '아직 글이 없습니다',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '오른쪽 위 [글쓰기]로 첫 글을 남겨보세요.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _errorPane() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 44, color: AppColors.textGray),
            const SizedBox(height: 10),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _postCard(Map<String, dynamic> p) {
    final atts = ((p['attachments'] as List?) ?? []).map((e) => '$e').toList();
    final who = '${p['author'] ?? ''}'.trim();
    final num = '${p['number'] ?? ''}'.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6E1D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 15,
                  color: AppColors.purple),
              const SizedBox(width: 4),
              Text(
                who.isEmpty ? '익명' : who,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (num.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  '범#$num',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGray,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                _fmtWhen('${p['updated'] ?? p['created'] ?? ''}'),
                style: const TextStyle(fontSize: 11, color: AppColors.textGray),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                onSelected: (v) {
                  if (v == 'edit') _editPost(p);
                  if (v == 'del') _deletePost(p);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('수정')),
                  PopupMenuItem(value: 'del', child: Text('삭제')),
                ],
              ),
            ],
          ),
          if ('${p['body'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${p['body'] ?? ''}',
              style: const TextStyle(fontSize: 13.5, height: 1.55),
            ),
          ],
          if (atts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in atts)
                  ActionChip(
                    avatar: Icon(
                      _isImage(a) ? Icons.image_outlined : Icons.attach_file,
                      size: 14,
                      color: AppColors.purple,
                    ),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: Text(
                        a,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    onPressed: () => _openAttachment(a),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
