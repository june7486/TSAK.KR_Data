import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 행사 후기 게시판 — 댓글·첨부·비밀번호 보호·임시저장·좋아요(공감).
/// 관리자·마스터는 작성자 기기·IP를 함께 본다.
class EventReviewScreen extends StatefulWidget {
  const EventReviewScreen({
    super.key,
    required this.year,
    required this.title,
  });

  final String year;
  final String title;

  @override
  State<EventReviewScreen> createState() => _EventReviewScreenState();
}

class _EventReviewScreenState extends State<EventReviewScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _posts = [];
  bool _isAdmin = false;
  /// 펼쳐서 내용을 보여줄 후기 id 집합 (기본은 접힌 요약 카드).
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  NasApi get _nas => context.read<NasApi>();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _nas.reviewList(widget.year, widget.title);
      if (!mounted) return;
      setState(() {
        _posts = ((r['posts'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _isAdmin = r['isAdmin'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '후기를 불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  String _deviceLabel() {
    // 웹/모바일 구분 간이 표기 (상세 기기는 서버가 user-agent 축약 저장)
    return '이 기기';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      appBar: TsakAppBar(
        title: const Text('행사 후기'),
        actions: [
          const AppHomeEmblem(size: 22),
          IconButton(
            tooltip: '새로고침',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.purple,
        onPressed: () => _editPost(),
        icon: const Icon(Icons.edit),
        label: const Text('후기 쓰기'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      _headerCard(state),
                      const SizedBox(height: 8),
                      if (_posts.isEmpty)
                        _emptyView()
                      else
                        for (final p in _posts) _postCard(p, state),
                    ],
                  ),
                ),
    );
  }

  Widget _headerCard(AppState state) {
    final visible = _posts.where((p) => p['draft'] != true).length;
    final drafts = _posts.where((p) => p['draft'] == true).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.year}  ·  후기 $visible건'
            '${_isAdmin && drafts > 0 ? '  ·  임시저장 $drafts건' : ''}',
            style: const TextStyle(fontSize: 12, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _emptyView() => Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(Icons.forum_outlined,
                size: 64, color: AppColors.purple.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            const Text('아직 등록된 후기가 없습니다',
                style: TextStyle(color: AppColors.textGray)),
            const SizedBox(height: 6),
            const Text('첫 후기를 남겨보세요!',
                style: TextStyle(color: AppColors.textGray, fontSize: 12)),
          ],
        ),
      );

  Widget _postCard(Map<String, dynamic> p, AppState state) {
    final id = '${p['id']}';
    final bool isOpen = _expanded.contains(id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() {
          if (isOpen) {
            _expanded.remove(id);
          } else {
            _expanded.add(id);
          }
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _reviewSummaryRow(p, isOpen),
            if (isOpen) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: _reviewDetail(p, state),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 목록용 요약 행 — 제목(후기)·글쓴이·날짜·공감·댓글.
  Widget _reviewSummaryRow(Map<String, dynamic> p, bool isOpen) {
    final author = '${p['author'] ?? ''}';
    final number = '${p['number'] ?? ''}';
    final body = '${p['body'] ?? ''}';
    final created = '${p['created'] ?? ''}';
    final updated = '${p['updated'] ?? ''}';
    final draft = p['draft'] == true;
    final locked = p['locked'] == true;
    final likes = (p['likes'] as num?)?.toInt() ?? 0;
    final comments = ((p['comments'] as List?) ?? []).length;
    final attachments = ((p['attachments'] as List?) ?? []).length;
    // 본문 첫 줄을 제목처럼 사용한다.
    final title = body.split('\n').first.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
      child: Row(
        children: [
          Icon(isOpen ? Icons.expand_less : Icons.expand_more,
              size: 18, color: AppColors.textGray),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (draft) ...[
                      _chip('임시저장', AppColors.tigerGold),
                      const SizedBox(width: 5),
                    ],
                    if (locked) ...[
                      _chip('비밀글', AppColors.taegeukBlue),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        title.isEmpty ? '(내용 없음)' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark),
                      ),
                    ),
                    if (attachments > 0) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.attach_file,
                          size: 13, color: AppColors.textGray),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(author.isEmpty ? '익명' : author,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark)),
                    if (number.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text('($number)',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textGray)),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        updated.isNotEmpty && updated != created
                            ? '$created (수정)'
                            : created,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textGray),
                      ),
                    ),
                    Icon(Icons.favorite_border,
                        size: 12, color: AppColors.textGray),
                    const SizedBox(width: 3),
                    Text('$likes',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textGray)),
                    const SizedBox(width: 8),
                    const Icon(Icons.mode_comment_outlined,
                        size: 12, color: AppColors.textGray),
                    const SizedBox(width: 3),
                    Text('$comments',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textGray)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewDetail(Map<String, dynamic> p, AppState state) {
    final author = '${p['author'] ?? ''}';
    final body = '${p['body'] ?? ''}';
    final pwdHint = '${p['pwdHint'] ?? ''}';
    final locked = p['locked'] == true;
    final likes = (p['likes'] as num?)?.toInt() ?? 0;
    final comments = ((p['comments'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final attachments = ((p['attachments'] as List?) ?? [])
        .map((e) => '$e')
        .toList();
    final device = '${p['device'] ?? ''}';
    final ip = '${p['ip'] ?? ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.purple.withValues(alpha: 0.15),
              child: Text(
                author.isNotEmpty ? author.characters.first : '?',
                style: const TextStyle(
                    color: AppColors.purple, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                author.isEmpty ? '익명' : author,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') {
                  _editPost(existing: p);
                } else if (v == 'delete') {
                  _deletePost(p);
                } else if (v == 'copy') {
                  _copyToClipboard(body);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('수정')),
                PopupMenuItem(value: 'delete', child: Text('삭제')),
                PopupMenuItem(value: 'copy', child: Text('본문 복사')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          body,
          style: const TextStyle(
              fontSize: 14, height: 1.5, color: AppColors.textDark),
        ),
            if (locked && pwdHint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.lock_outline,
                      size: 13, color: AppColors.textGray),
                  const SizedBox(width: 4),
                  Text('비밀번호 힌트: $pwdHint',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGray)),
                ],
              ),
            ],
            if (_isAdmin && (device.isNotEmpty || ip.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.taegeukRed.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.devices,
                        size: 12, color: AppColors.taegeukRed),
                    const SizedBox(width: 4),
                    Text(
                      '기기: ${device.isEmpty ? '-' : device}'
                      '   IP: ${ip.isEmpty ? '-' : ip}',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.taegeukRed),
                    ),
                  ],
                ),
              ),
            ],
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in attachments)
                    _attachmentChip(a),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _likeButton(p, likes),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => _addComment(p),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(
                      children: [
                        const Icon(Icons.mode_comment_outlined,
                            size: 16, color: AppColors.textGray),
                        const SizedBox(width: 4),
                        Text('댓글 ${comments.length}',
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textGray)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _addAttachment(p),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(
                      children: [
                        Icon(Icons.attach_file,
                            size: 16, color: AppColors.purple),
                        SizedBox(width: 3),
                        Text('첨부',
                            style: TextStyle(
                                fontSize: 12.5, color: AppColors.purple)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (comments.isNotEmpty) ...[
              const Divider(height: 18),
              for (final c in comments) _commentTile(p, c),
            ],
      ],
    );
  }

  Widget _commentTile(Map<String, dynamic> post, Map<String, dynamic> c) {
    final cid = '${c['id']}';
    final author = '${c['author'] ?? ''}';
    final body = '${c['body'] ?? ''}';
    final created = '${c['created'] ?? ''}';
    final device = '${c['device'] ?? ''}';
    final ip = '${c['ip'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.subdirectory_arrow_right,
              size: 14, color: AppColors.textGray),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      author.isEmpty ? '익명' : author,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                    const SizedBox(width: 6),
                    Text(created,
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.textGray)),
                    if (_isAdmin && (device.isNotEmpty || ip.isNotEmpty)) ...[
                      const SizedBox(width: 6),
                      Text(
                          '· ${device.isEmpty ? ip : device}'
                          '${(device.isNotEmpty && ip.isNotEmpty) ? ' / $ip' : ''}',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.taegeukRed)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                SelectableText(body,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textDark)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            tooltip: '댓글 삭제',
            icon: const Icon(Icons.close, color: AppColors.textGray),
            onPressed: () => _deleteComment(post, cid),
          ),
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(t,
            style: TextStyle(
                fontSize: 10, color: c, fontWeight: FontWeight.w800)),
      );

  Widget _likeButton(Map<String, dynamic> p, int likes) {
    final id = '${p['id']}';
    final liked = _liked.contains(id);
    return InkWell(
      onTap: () => _toggleLike(p),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: 16,
              color: liked ? AppColors.taegeukRed : AppColors.textGray,
            ),
            const SizedBox(width: 4),
            Text('공감 $likes',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: liked ? FontWeight.w800 : FontWeight.w500,
                  color: liked ? AppColors.taegeukRed : AppColors.textGray,
                )),
          ],
        ),
      ),
    );
  }

  final Set<String> _liked = {};

  Widget _attachmentChip(String name) {
    final isImg = RegExp(r'\.(jpg|jpeg|png|gif|webp)$', caseSensitive: false)
        .hasMatch(name);
    return InkWell(
      onTap: () => _openAttachment(name),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.scoutGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.scoutGreen.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isImg ? Icons.image : Icons.attach_file,
                size: 14, color: AppColors.scoutGreen),
            const SizedBox(width: 4),
            Text(name,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.scoutGreen)),
          ],
        ),
      ),
    );
  }

  // ============================ 액션 ============================

  Future<void> _editPost({Map<String, dynamic>? existing}) async {
    final state = context.read<AppState>();
    final bodyCtrl = TextEditingController(text: '${existing?['body'] ?? ''}');
    // 작성자: 로그인 시 이름 자동입력, 비회원이면 저장된 값/빈칸.
    final authorCtrl = TextEditingController(
        text: '${existing?['author'] ?? (state.who.isNotEmpty ? state.who : '')}');
    // 인가번호: 로그인 시 인가번호 자동입력, 비회원은 전화번호 뒷자리(직접 입력).
    final numberCtrl = TextEditingController(
        text: '${existing?['number'] ?? (state.who.isNotEmpty ? state.who : '')}');
    final pwCtrl = TextEditingController();
    final hintCtrl = TextEditingController(text: '${existing?['pwdHint'] ?? ''}');
    final attachments = ((existing?['attachments'] as List?) ?? [])
        .map((e) => '$e')
        .toList();

    // 등록 활성 조건: 후기 내용이 한 글자라도 채워지면 즉시 활성화.
    //  로그인 시 작성자·인가번호는 자동입력되어 별도 입력이 불필요하다.
    bool canSubmit() => bodyCtrl.text.trim().isNotEmpty;

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? '후기 쓰기' : '후기 수정'),
          content: SizedBox(
            width: 420,
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
                          onChanged: (_) => setD(() {}),
                          decoration: const InputDecoration(
                            labelText: '작성자',
                            helperText: '로그인 시 자동입력',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: numberCtrl,
                          onChanged: (_) => setD(() {}),
                          decoration: const InputDecoration(
                            labelText: '인가번호',
                            helperText: '비회원은 전화 뒷자리',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 6,
                    minLines: 3,
                    autofocus: true,
                    onChanged: (_) => setD(() {}),
                    decoration: const InputDecoration(
                      labelText: '후기 내용',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: pwCtrl,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: existing?['locked'] == true
                                ? '비밀번호 (변경 시 입력)'
                                : '비밀번호 (선택)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: hintCtrl,
                          decoration:
                              const InputDecoration(labelText: '힌트'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await pickDataFiles(
                            allowMultiple: true,
                            dialogTitle: '후기 첨부 (사진/동영상/파일)',
                          );
                          if (picked.isEmpty) return;
                          for (final f in picked) {
                            await _nas.eventUpload2(
                              widget.year,
                              widget.title,
                              'review',
                              f.name,
                              f.bytes,
                              uploader: authorCtrl.text.trim(),
                            );
                            attachments.add(f.name);
                          }
                          setD(() {});
                        },
                        icon: const Icon(Icons.attach_file, size: 16),
                        label: const Text('첨부 추가'),
                      ),
                      const SizedBox(width: 8),
                      Text('${attachments.length}개',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textGray)),
                    ],
                  ),
                  if (attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final a in attachments)
                            Chip(
                              label: Text(a,
                                  style: const TextStyle(fontSize: 11)),
                              onDeleted: () => setD(() => attachments.remove(a)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'draft'),
              child: const Text('임시저장'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
              onPressed: canSubmit()
                  ? () => Navigator.pop(ctx, 'publish')
                  : null,
              child: const Text('등록'),
            ),
          ],
        ),
      ),
    );
    if (res == null || res == 'cancel') return;
    if (bodyCtrl.text.trim().isEmpty) return;
    try {
      await _nas.reviewSave(
        year: widget.year,
        title: widget.title,
        id: '${existing?['id'] ?? ''}',
        author: authorCtrl.text.trim(),
        number: numberCtrl.text.trim(),
        body: bodyCtrl.text.trim(),
        draft: res == 'draft',
        password: pwCtrl.text,
        pwdHint: hintCtrl.text.trim(),
        device: _deviceLabel(),
        attachments: attachments,
      );
      _snack(res == 'draft' ? '임시저장했습니다' : '등록했습니다');
      await _load();
    } catch (e) {
      _snack('저장 실패: $e');
    }
  }

  Future<void> _addComment(Map<String, dynamic> post) async {
    final state = context.read<AppState>();
    final ctrl = TextEditingController();
    final authorCtrl = TextEditingController(
        text: state.who.isNotEmpty ? state.who : '');
    final pwCtrl = TextEditingController();
    final locked = post['locked'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('댓글 달기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: authorCtrl,
              decoration: const InputDecoration(labelText: '작성자'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 3,
              minLines: 1,
              autofocus: true,
              decoration: const InputDecoration(labelText: '댓글'),
            ),
            if (locked && !_isAdmin) ...[
              const SizedBox(height: 8),
              TextField(
                controller: pwCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '비밀글 비밀번호',
                  helperText: '비밀글에는 비밀번호가 필요합니다',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('등록'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      final r = await _nas.reviewComment(
        year: widget.year,
        title: widget.title,
        postId: '${post['id']}',
        author: authorCtrl.text.trim(),
        body: ctrl.text.trim(),
        password: pwCtrl.text,
        device: _deviceLabel(),
      );
      if (r['ok'] == true) {
        await _load();
      } else {
        _snack('댓글 실패: ${r['error'] ?? '비밀번호 확인'}');
      }
    } catch (e) {
      _snack('댓글 실패: $e');
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final id = '${post['id']}';
    final on = !_liked.contains(id);
    setState(() {
      if (on) {
        _liked.add(id);
      } else {
        _liked.remove(id);
      }
    });
    try {
      await _nas.reviewLike(
        year: widget.year,
        title: widget.title,
        postId: id,
        on: on,
      );
      await _load();
    } catch (e) {
      _snack('공감 실패: $e');
    }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    String pw = '';
    if (post['locked'] == true && !_isAdmin) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('비밀번호 확인'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: '비밀번호'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('확인')),
          ],
        ),
      );
      if (ok != true) return;
      pw = ctrl.text;
    }
    final done = await _nas.reviewDelete(
      year: widget.year,
      title: widget.title,
      postId: '${post['id']}',
      password: pw,
    );
    _snack(done ? '삭제했습니다' : '삭제 실패 (비밀번호 확인)');
    await _load();
  }

  Future<void> _deleteComment(Map<String, dynamic> post, String cid) async {
    await _nas.reviewDelete(
      year: widget.year,
      title: widget.title,
      postId: '${post['id']}',
      commentId: cid,
    );
    await _load();
  }

  Future<void> _addAttachment(Map<String, dynamic> post) async {
    final picked = await pickDataFiles(
      allowMultiple: true,
      dialogTitle: '후기 첨부 추가',
    );
    if (picked.isEmpty) return;
    final attachments = ((post['attachments'] as List?) ?? [])
        .map((e) => '$e')
        .toList();
    try {
      for (final f in picked) {
        await _nas.eventUpload2(
          widget.year,
          widget.title,
          'review',
          f.name,
          f.bytes,
          uploader: '${post['author'] ?? ''}',
        );
        attachments.add(f.name);
      }
      await _nas.reviewSave(
        year: widget.year,
        title: widget.title,
        id: '${post['id']}',
        author: '${post['author'] ?? ''}',
        number: '${post['number'] ?? ''}',
        body: '${post['body'] ?? ''}',
        draft: post['draft'] == true,
        attachments: attachments,
      );
      _snack('첨부했습니다');
      await _load();
    } catch (e) {
      _snack('첨부 실패: $e');
    }
  }

  void _openAttachment(String name) {
    final url = _nas.eventFile2Url(widget.year, widget.title, 'review', name);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(name, style: const TextStyle(fontSize: 13)),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('미리보기를 열 수 없는 파일입니다'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    // no-op placeholder prevented; simple feedback
    _snack('본문을 길게 눌러 복사하세요');
  }

  Widget _errorView() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.taegeukRed),
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

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }
}
