// 행사 커스텀 게시판 — '메뉴 추가'로 만든 탭이 **게시판**으로 동작한다.
//
// [요구 2026-10-26]
//   "행사관리 메뉴 중 메뉴를 추가할 경우 게시판 기능을 활성화시켜주고,
//    첨부파일을 올릴 수 있는 게시판도 생성해줘. 후기 게시판처럼 글쓰기
//    기능을 추가하고 첨부파일을 올리고 다운받고 확인할 수 있도록.
//    추가 게시판의 열람권한은 관리자는 기본이지만, 모든 회원에게 노출할지
//    여부를 해당 게시판 상단에 선택 버튼을 넣어줘."
//
// [추가 요구 2026-10-26 — 2차]
//   · "메뉴추가 기능은 있는데, 메뉴 삭제 및 관리 기능이 없음
//      관리자/마스터는 생성·삭제·변경 등의 관리 기능을 할 수 있음"
//   · "노출권한을 관리자/마스터가 정할 수 있음 (게시판 상단에 버튼 노출),
//      노출/관리자/마스터"  → 3단계(all / staff / admin)
//   · "글을 쓰고 파일을 업로드할 수 있도록, 자료를 읽고 공감하고,
//      다운받을 수 있도록"
//   · "마스터는 읽은 사람을 기록하고 볼 수 있도록 관리"
//   · "게시글의 비밀번호는 글쓴 사람은 비밀번호를 넣을 수 있고,
//      글쓴 사람과 마스터한테는 비밀번호가 노출됨(마스터권한)"
//   · "비밀번호를 잃어버렸을 경우 초기화할 수 있음
//      (초기화는 'id'+'!@@', 예) 415!@@ — 별도 안내하지 않음)"
//   · "상부 버튼은 모두에게 노출되지만, 게시물은 권한이 있는 사람에게만 노출됨"
//
// 설계 원칙(기존 코드 재사용 — 새 업로드 경로를 만들지 않는다):
//   · 첨부 업로드  : `nas.eventUpload2(year,title,'review',name,bytes)`
//                    → NAS 의 `06_후기첨부_(업로드가능)` 폴더(후기 게시판과 동일)
//   · 첨부 다운로드: `nas.eventFile2Url(year,title,'review',name)`
//   · 글/권한 저장 : `/api/event/cboard/*` (프록시 · do_POST)
//
// 권한 모델:
//   · 관리자(app/master)  : 항상 열람·작성·관리(생성/수정/삭제/권한)
//   · 노출 등급
//       all   → 인가자 누구나
//       staff → 해당 행사 스탭 + 관리자·마스터
//       admin → 관리자·마스터만
//   · 상단 버튼(노출권한)은 **모두에게 보이지만** 값 변경은 관리자·마스터만.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';

/// 게시판 노출 등급 — 서버(`visibility`)와 1:1 대응.
enum BoardVisibility { all, staff, admin }

extension BoardVisibilityX on BoardVisibility {
  String get key => switch (this) {
        BoardVisibility.all => 'all',
        BoardVisibility.staff => 'staff',
        BoardVisibility.admin => 'admin',
      };

  String get label => switch (this) {
        BoardVisibility.all => '전체 노출',
        BoardVisibility.staff => '스탭 이상',
        BoardVisibility.admin => '관리자·마스터',
      };

  String get hint => switch (this) {
        BoardVisibility.all => '인가자 누구나 열람·작성',
        BoardVisibility.staff => '이 행사 스탭 + 관리자·마스터',
        BoardVisibility.admin => '관리자·마스터만',
      };

  IconData get icon => switch (this) {
        BoardVisibility.all => Icons.groups_outlined,
        BoardVisibility.staff => Icons.shield_outlined,
        BoardVisibility.admin => Icons.lock_outline,
      };

  static BoardVisibility parse(String? s) => switch (s ?? '') {
        'all' => BoardVisibility.all,
        'staff' => BoardVisibility.staff,
        _ => BoardVisibility.admin,
      };
}

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
  BoardVisibility _visibility = BoardVisibility.admin;
  bool _isAdmin = false;
  bool _isMaster = false;
  List<Map<String, dynamic>> _posts = [];
  bool _busy = false;
  String _bid = '';

  /// 본문을 펼쳐서 읽은 글 id 집합(비밀번호 통과 후).
  final Set<String> _opened = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureBoard();
    });
  }

  /// 게시판 id 확보 → 글 목록 로드.
  ///
  ///  ⚠️ [버그 수정 2026-10-26] 종전에는 게시판이 없으면 여기서 **자동 생성**을
  ///   시도했다. 그런데 서버의 create 가 do_GET 에 잘못 들어가 404 HTML 을
  ///   돌려주는 바람에 `FormatException: Unexpected token '<'` 로 화면 전체가
  ///   오류 패널이 됐다. 이제는
  ///     · 관리자·마스터면 자동 생성(정상 동작)
  ///     · 일반 회원이면 "아직 개설되지 않음" 안내만
  ///   로 나눈다. 또 HTML/401 은 `_robustJson` 이 예외로 올려 준다.
  Future<void> _ensureBoard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var bid = _bid.isNotEmpty ? _bid : widget.boardId;
      if (bid.isEmpty) {
        final ls = await _nas.customBoards(widget.year, widget.title);
        final admin = ls['canManage'] == true || ls['isAdmin'] == true;
        for (final b in ((ls['boards'] as List?) ?? [])) {
          final m = (b as Map).cast<String, dynamic>();
          if ('${m['name'] ?? ''}' == widget.boardName) {
            bid = '${m['id'] ?? ''}';
            break;
          }
        }
        if (bid.isEmpty) {
          if (!admin) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _isAdmin = false;
              _error = '이 게시판은 아직 개설되지 않았습니다.\n'
                  '관리자·마스터가 [메뉴 관리]에서 개설할 수 있습니다.';
            });
            return;
          }
          final cr = await _nas.customBoardCreate(
            year: widget.year,
            title: widget.title,
            name: widget.boardName,
            note: widget.note,
            visibility: 'admin',
          );
          bid = '${cr['id'] ?? ''}';
        }
        _bid = bid;
      }
      await _loadPosts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '게시판을 불러오지 못했습니다.\n${_niceErr(e)}';
      });
    }
  }

  /// 사용자에게 보여줄 오류 문구 — HTML/게이트웨이 오류를 그대로 노출하지 않는다.
  static String _niceErr(Object e) {
    final s = '$e';
    if (s.contains('<') || s.contains('FormatException')) {
      return '서버가 올바른 응답을 주지 않았습니다. 잠시 후 다시 시도해 주세요.';
    }
    return s;
  }

  Future<void> _loadPosts() async {
    final bid = _bid.isNotEmpty ? _bid : widget.boardId;
    if (bid.isEmpty) return;
    try {
      final d = await _nas.customBoardGet(widget.year, widget.title, bid);
      if (!mounted) return;
      final board = (d['board'] as Map?)?.cast<String, dynamic>() ?? {};
      setState(() {
        _bid = bid;
        _visibility = BoardVisibilityX.parse('${board['visibility'] ?? ''}');
        _isAdmin = d['isAdmin'] == true;
        _isMaster = d['isMaster'] == true;
        _posts = ((d['posts'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      setState(() {
        _loading = false;
        _error = msg.contains('권한')
            ? '이 게시판을 볼 권한이 없습니다.'
            : '게시판을 불러오지 못했습니다.\n${_niceErr(e)}';
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ───────────────────────── 노출권한 (관리자·마스터) ─────────────────────────
  Future<void> _changeVisibility(BoardVisibility v) async {
    if (!_isAdmin) {
      _snack('노출권한은 관리자·마스터만 바꿀 수 있습니다');
      return;
    }
    final prev = _visibility;
    setState(() {
      _visibility = v;
      _busy = true;
    });
    try {
      final r = await _nas.customBoardVisibility(
        year: widget.year,
        title: widget.title,
        id: _bid.isNotEmpty ? _bid : widget.boardId,
        visibility: v.key,
      );
      if (!mounted) return;
      if (r['ok'] == true) {
        _snack('노출권한: ${v.label}');
      } else {
        setState(() => _visibility = prev);
        _snack('권한을 바꾸지 못했습니다');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _visibility = prev);
      _snack('권한을 바꾸지 못했습니다');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────────── 글 작성/수정 ─────────────────────────
  /// 글 작성/수정 — 첨부 추가·삭제, **비밀번호 설정**, 다운로드까지 한 화면에서.
  Future<void> _editPost([Map<String, dynamic>? post]) async {
    final bodyCtrl = TextEditingController(text: '${post?['body'] ?? ''}');
    final authorCtrl = TextEditingController(text: '${post?['author'] ?? ''}');
    final numberCtrl = TextEditingController(text: '${post?['number'] ?? ''}');
    // 기존 글에 비번이 걸려 있고 **내가 볼 수 있는** 경우에만 값을 채운다.
    final canSeePw = post?['canSeePassword'] == true;
    final pwCtrl = TextEditingController(
      text: canSeePw ? '${post?['password'] ?? ''}' : '',
    );
    final attachments = <String>[
      ...(((post?['attachments'] as List?) ?? []).map((e) => '$e')),
    ];
    var uploading = false;
    var hidePw = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(
            post == null ? '글쓰기 · ${widget.boardName}' : '글 수정',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 480,
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
                  // ── 게시글 비밀번호 (글쓴이가 설정) ─────────────────────
                  TextField(
                    controller: pwCtrl,
                    obscureText: hidePw,
                    decoration: InputDecoration(
                      labelText: '게시글 비밀번호 (선택)',
                      helperText: '설정하면 글쓴이와 마스터만 본문을 봅니다',
                      helperMaxLines: 2,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          hidePw ? Icons.visibility_off : Icons.visibility,
                          size: 19,
                        ),
                        onPressed: () => setD(() => hidePw = !hidePw),
                      ),
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
        boardId: _bid.isNotEmpty ? _bid : widget.boardId,
        id: '${post?['id'] ?? ''}',
        author: authorCtrl.text.trim(),
        number: numberCtrl.text.trim(),
        body: bodyCtrl.text,
        attachments: attachments,
        // 비번은 항상 명시 전송 — 빈 값이면 잠금 해제로 처리된다.
        password: pwCtrl.text,
      );
      if (!mounted) return;
      if (r['ok'] == true) {
        _snack(post == null ? '글을 등록했습니다' : '글을 저장했습니다');
        await _loadPosts();
      } else {
        _snack('저장하지 못했습니다 (${r['error'] ?? '오류'})');
      }
    } catch (e) {
      if (mounted) _snack('저장하지 못했습니다: ${_niceErr(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────────── 글 삭제 ─────────────────────────
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
    final ok = await _nas.customBoardDelete(
      year: widget.year,
      title: widget.title,
      boardId: _bid.isNotEmpty ? _bid : widget.boardId,
      postId: '${post['id'] ?? ''}',
      author: '${post['author'] ?? ''}',
      number: '${post['number'] ?? ''}',
    );
    if (!mounted) return;
    if (ok) {
      _snack('삭제했습니다');
      await _loadPosts();
    } else {
      _snack('삭제하지 못했습니다 (권한 확인)');
    }
  }

  // ───────────────────────── 비밀번호 초기화 ─────────────────────────
  /// 비밀번호 분실 시 초기화 — 새 값은 **글쓴이 인가번호 + '!@@'**.
  ///  [요구] "별도 안내하지 않음" → 초기화 후 값를 화면에 띄우지 않는다.
  Future<void> _resetPostPassword(Map<String, dynamic> post) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비밀번호 초기화'),
        content: const Text('이 글의 비밀번호를 초기화할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      final r = await _nas.customBoardPasswordReset(
        year: widget.year,
        title: widget.title,
        boardId: _bid.isNotEmpty ? _bid : widget.boardId,
        postId: '${post['id'] ?? ''}',
      );
      if (!mounted) return;
      if (r['ok'] == true) {
        _snack('비밀번호를 초기화했습니다');
        await _loadPosts();
      } else {
        _snack('초기화하지 못했습니다 (${r['error'] ?? '권한 확인'})');
      }
    } catch (e) {
      if (mounted) _snack('초기화하지 못했습니다: ${_niceErr(e)}');
    }
  }

  // ───────────────────────── 읽기 (비번 통과 + 읽음 기록) ─────────────────────────
  /// 글 본문 펼치기. 비밀번호가 걸려 있으면 입력받아 통과 후 열고,
  /// 통과하면 **읽음 기록**을 1회 남긴다.
  ///
  ///  ⚠️ 서버는 잠긴 글의 `body` 를 아예 내려주지 않는다(`locked:true`).
  ///     그래서 통과 후에는 `/post/unlock` 응답의 `post` 로 본문을 받아
  ///     그 글만 화면에서 갱신한다.
  Future<void> _openPost(Map<String, dynamic> post) async {
    final pid = '${post['id'] ?? ''}';
    if (_opened.contains(pid)) {
      setState(() => _opened.remove(pid));
      return;
    }
    Map<String, dynamic>? revealed;
    if (post['locked'] == true) {
      final ctrl = TextEditingController();
      String? err;
      final okPw = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('비밀번호가 걸린 글'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    errorText: err,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    final r = await _nas.customBoardUnlock(
                      year: widget.year,
                      title: widget.title,
                      boardId: _bid.isNotEmpty ? _bid : widget.boardId,
                      postId: pid,
                      password: ctrl.text,
                    );
                    if (!ctx.mounted) return;
                    if (r['ok'] == true) {
                      Navigator.pop(ctx, ctrl.text);
                    } else {
                      setD(() => err = '비밀번호가 다릅니다');
                    }
                  } catch (_) {
                    setD(() => err = '비밀번호가 다릅니다');
                  }
                },
                child: const Text('열기'),
              ),
            ],
          ),
        ),
      );
      if (okPw == null || !mounted) return;
      // 통과한 본문을 받아온다(서버가 이때만 body 를 내려준다).
      try {
        final r = await _nas.customBoardUnlock(
          year: widget.year,
          title: widget.title,
          boardId: _bid.isNotEmpty ? _bid : widget.boardId,
          postId: pid,
          password: okPw,
        );
        final rp = (r['post'] as Map?)?.cast<String, dynamic>();
        if (rp != null) revealed = rp;
      } catch (_) {}
    }
    final revealedFinal = revealed;
    setState(() {
      _opened.add(pid);
      if (revealedFinal != null) {
        final i = _posts.indexWhere((e) => '${e['id']}' == pid);
        if (i >= 0) {
          _posts[i] = {..._posts[i], ...revealedFinal};
        }
      }
    });
    // 읽음 기록 — 실패해도 화면 동작에는 지장이 없도록 조용히 넘긴다.
    if (!mounted) return;
    try {
      final nm = context.read<AppState>();
      await _nas.customBoardMarkRead(
        year: widget.year,
        title: widget.title,
        boardId: _bid.isNotEmpty ? _bid : widget.boardId,
        postId: pid,
        name: nm.who,
      );
    } catch (_) {}
  }

  // ───────────────────────── 첨부 보기 / 다운로드 ─────────────────────────
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
    // 서버는 "YYYY.MM.DD HH:MM:SS" 형식으로 준다.
    if (s.length >= 16) return s.substring(0, 16);
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
              onRefresh: _loadPosts,
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

  /// 상단 바 — 게시판 이름 + [글쓰기] + **노출권한 선택 버튼**.
  ///  요구: "상부 버튼은 모두에게 노출되지만" → 버튼 자체는 항상 보이고,
  ///       값 변경만 관리자·마스터에게 허용한다.
  Widget _header() {
    final canManage = _isAdmin;
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
              const Icon(Icons.forum_outlined,
                  size: 18, color: AppColors.purple),
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
                    style:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          const SizedBox(height: 8),
          // ── 노출권한 버튼 (요구: "게시판 상단에 버튼 노출") ──────────
          //   버튼은 **모두에게** 보인다. 관리자가 아니면 눌러도 안내만.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final v in BoardVisibility.values)
                _visChip(v, selected: _visibility == v, canManage: canManage),
              if (!canManage)
                const Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Text(
                    '(변경은 관리자·마스터)',
                    style:
                        TextStyle(fontSize: 10.5, color: AppColors.textGray),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _visChip(
    BoardVisibility v, {
    required bool selected,
    required bool canManage,
  }) {
    final color = v == BoardVisibility.all
        ? AppColors.scoutGreen
        : (v == BoardVisibility.staff
            ? AppColors.tigerGold
            : AppColors.purple);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _busy ? null : () => _changeVisibility(v),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.55) : const Color(0xFFD9D3C6),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(v.icon,
                size: 14,
                color: selected ? color : AppColors.textGray),
            const SizedBox(width: 4),
            Text(
              v.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? color : AppColors.textGray,
              ),
            ),
          ],
        ),
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
              onPressed: () {
                _bid = '';
                _ensureBoard();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _postCard(Map<String, dynamic> p) {
    final pid = '${p['id'] ?? ''}';
    final atts = ((p['attachments'] as List?) ?? []).map((e) => '$e').toList();
    final who = '${p['author'] ?? ''}'.trim();
    final num = '${p['number'] ?? ''}'.trim();
    final hasPw = p['hasPassword'] == true;
    final canSeePw = p['canSeePassword'] == true;
    final pwValue = '${p['password'] ?? ''}';
    // 서버가 실제로 본문을 지워 보낸 글 = 잠김. (앱은 화면만 가리는 게 아니다)
    final locked = p['locked'] == true && !_opened.contains(pid);
    final isMine = _isAdmin;

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
              const Icon(Icons.person_outline,
                  size: 15, color: AppColors.purple),
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
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ],
              // 읽음 수 — 마스터·관리자에게만 의미 있게 보인다.
              if (_isAdmin && (p['readCount'] ?? 0) > 0) ...[
                const SizedBox(width: 6),
                const Icon(Icons.visibility_outlined,
                    size: 12, color: AppColors.textGray),
                const SizedBox(width: 2),
                Text(
                  '${p['readCount']}',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textGray),
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
                  if (v == 'pwreset') _resetPostPassword(p);
                  if (v == 'reads') _showReads(p);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('수정')),
                  const PopupMenuItem(value: 'del', child: Text('삭제')),
                  if (hasPw)
                    PopupMenuItem(
                      value: 'pwreset',
                      child: Text(
                        '비밀번호 초기화',
                        style: TextStyle(
                          fontSize: 13,
                          color: canSeePw || _isAdmin
                              ? AppColors.textDark
                              : AppColors.textGray,
                        ),
                      ),
                    ),
                  if (_isMaster)
                    const PopupMenuItem(
                      value: 'reads',
                      child: Text('읽은 사람'),
                    ),
                ],
              ),
            ],
          ),
          // ── 잠긴 글 ────────────────────────────────────────────────
          if (locked)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openPost(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.purple.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline,
                          size: 16, color: AppColors.purple),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '비밀번호가 걸린 글입니다. 눌러서 열기',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.purple,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 18, color: AppColors.purple),
                    ],
                  ),
                ),
              ),
            ),
          // ── 본문 ────────────────────────────────────────────────────
          if (!locked && '${p['body'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${p['body'] ?? ''}',
              style: const TextStyle(fontSize: 13.5, height: 1.55),
            ),
          ],
          // ── 비밀번호 표시 (글쓴이·마스터) ──────────────────────────
          if (hasPw && canSeePw) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.key_outlined,
                    size: 13, color: AppColors.tigerGold),
                const SizedBox(width: 4),
                Text(
                  '게시글 비밀번호: $pwValue',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.tigerGold,
                  ),
                ),
              ],
            ),
          ],
          // ── 첨부 ────────────────────────────────────────────────────
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
          // ── 잠긴 글 다시 접기 ───────────────────────────────────────
          if (!locked && hasPw && !canSeePw) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _openPost(p),
                child: const Text('접기', style: TextStyle(fontSize: 11.5)),
              ),
            ),
          ],
          if (isMine && (p['reads'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showReads(p),
                icon: const Icon(Icons.people_outline, size: 14),
                label: Text(
                  '읽은 사람 ${p['readCount'] ?? 0}명',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 읽은 사람 명단 — **마스터 전용**.
  ///
  /// ⚠️ `/api/event/cboard/password/reset` 로 비번을 되찾은 뒤에는
  ///    화면에 새 값을 띄우지 않는다(요구: "별도 안내하지 않음").
  Future<void> _showReads(Map<String, dynamic> post) async {
    final reads = ((post['reads'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('읽은 사람', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 380,
          child: reads.isEmpty
              ? const Text('아직 읽은 사람이 없습니다.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final r in reads)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline, size: 18),
                        title: Text(
                          '${r['name'] ?? ''}'.trim().isEmpty
                              ? '범#${r['number'] ?? ''}'
                              : '${r['name']} (범#${r['number'] ?? ''})',
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: Text(
                          '${r['at'] ?? ''}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textGray),
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
    );
  }
}
