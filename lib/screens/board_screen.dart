import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/personal_quick_actions.dart';
import '../widgets/tsak_app_bar.dart';

/// 게시판 (#12).
/// - 관리자 이상 알림 대상, 댓글/좋아요, 비밀번호 보호.
/// - 모든 게시글에 첨부파일·사진·동영상·링크(URL) 첨부 가능.
/// - 관리자: 수정/삭제/비노출 지정.
/// - URL 생성: 로그인한 권한자만 열람 가능(서버가 세션 검사).
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, this.openId = ''});

  /// 열 때 바로 펼칠 게시글 ID (URL 딥링크).
  final String openId;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _posts = [];
  bool _isAdmin = false;
  String _filter = '전체';
  final Set<String> _liked = {};

  /// 펼쳐서 내용을 보여줄 게시글 id 집합 (기본은 접힌 요약 카드).
  final Set<String> _expanded = {};

  static const _categories = ['전체', '공지', '행사', '수품', '후기', '일반'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// URL 딥링크(openId)로 열린 경우 해당 글을 상단으로 스크롤·강조.
  bool _deepLinkScrolled = false;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeScrollToDeepLink() {
    if (_deepLinkScrolled) return;
    _deepLinkScrolled = true;
    final id = widget.openId.trim();
    if (id.isEmpty) return;
    final idx = _posts.indexWhere((p) => '${p['id']}' == id);
    if (idx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final approx = 40.0 + idx * 180.0;
      _scroll.animateTo(
        approx.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  NasApi get _nas => context.read<NasApi>();

  Future<void> _load() async {
    final state = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _nas.boardList();
      if (!mounted) return;
      setState(() {
        _posts = ((r['posts'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _isAdmin = r['isAdmin'] == true;
        _loading = false;
      });
      _maybeScrollToDeepLink();
      // 게시판을 열어 확인했으므로 '해당 아이디 기준'으로 읽음 처리한다.
      //  → 홈 화면 게시판 배지에서 확인한 만큼 차감된다.
      try {
        await state.markBadgeSeen(kind: 'board');
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '게시판을 불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  String _deviceLabel() => '이 기기';

  List<Map<String, dynamic>> get _visible {
    if (_filter == '전체') return _posts;
    return _posts.where((p) => '${p['category'] ?? '일반'}' == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      appBar: TsakAppBar(
        title: const Text('게시판'),
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
        label: const Text('글쓰기'),
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
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                          children: [
                            _categoryBar(),
                            const SizedBox(height: 8),
                            if (_visible.isEmpty)
                              _emptyView()
                            else
                              for (final p in _visible) _postCard(p),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          // 게시글 불러오기 대기 — 멈춘 것이 아님을 안내.
          BusyOverlay(
            visible: _loading,
            title: '게시글을 불러오는 중입니다',
            lines: const [
              'NAS 서버에서 게시글을 가져오는 중...',
              '최신 글로 정리하는 중...',
              '잠시만 기다려 주세요...',
            ],
          ),
        ],
      ),
    );
  }

  Widget _categoryBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in _categories)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(c),
                selected: _filter == c,
                selectedColor: AppColors.purple.withValues(alpha: 0.15),
                onSelected: (_) => setState(() => _filter = c),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyView() => Padding(
    padding: const EdgeInsets.only(top: 80),
    child: Column(
      children: [
        Icon(
          Icons.forum_outlined,
          size: 64,
          color: AppColors.purple.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 12),
        const Text(
          '아직 등록된 게시글이 없습니다',
          style: TextStyle(color: AppColors.textGray),
        ),
        const SizedBox(height: 6),
        const Text(
          '첫 소식을 남겨보세요!',
          style: TextStyle(color: AppColors.textGray, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _postCard(Map<String, dynamic> p) {
    final state = context.watch<AppState>();
    final id = '${p['id']}';
    final bool isOpen = _expanded.contains(id);
    // 목록 카드에는 요약(제목/글쓴이/날짜/조회/좋아요/댓글)만 보여주고,
    // 내용은 클릭해 펼쳤을 때만 노출한다.
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
            _postSummaryRow(p, isOpen),
            if (isOpen) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: _postDetail(p, state),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 목록용 요약 행 — 제목 / 인가번호·글쓴이·날짜·조회·좋아요·댓글.
  Widget _postSummaryRow(Map<String, dynamic> p, bool isOpen) {
    final author = '${p['author'] ?? ''}';
    final number = '${p['number'] ?? ''}';
    final title = '${p['title'] ?? ''}';
    final category = '${p['category'] ?? '일반'}';
    final created = '${p['created'] ?? ''}';
    final updated = '${p['updated'] ?? ''}';
    final hasPassword = p['hasPassword'] == true;
    final likes = (p['likes'] as num?)?.toInt() ?? 0;
    final views = (p['views'] as num?)?.toInt() ?? 0;
    final hidden = p['hidden'] == true;
    final comments = ((p['comments'] as List?) ?? []).length;
    final attachments = ((p['attachments'] as List?) ?? []).length;
    final hasMedia = ((p['media'] as List?) ?? []).isNotEmpty;

    Color catColor = AppColors.purple;
    if (category == '공지') catColor = AppColors.taegeukRed;
    if (category == '후기') catColor = AppColors.scoutGreen;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 펼침/접힘 표시
          Icon(
            isOpen ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: AppColors.textGray,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _chip(category, catColor),
                    if (hasPassword) ...[
                      const SizedBox(width: 5),
                      _chip('비밀글', AppColors.taegeukBlue),
                    ],
                    if (hidden && _isAdmin) ...[
                      const SizedBox(width: 5),
                      _chip('비노출', AppColors.taegeukRed),
                    ],
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title.isEmpty ? '(제목 없음)' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    if (attachments > 0 || hasMedia) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.attach_file,
                        size: 13,
                        color: AppColors.textGray,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      author.isEmpty ? '익명' : author,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (number.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        '($number)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray,
                        ),
                      ),
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
                          fontSize: 11,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.visibility,
                      size: 12,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$views',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.favorite_border,
                      size: 12,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$likes',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.mode_comment_outlined,
                      size: 12,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$comments',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 펼친 카드의 상세 내용(본문·첨부·링크·IP·반응·댓글).
  Widget _postDetail(Map<String, dynamic> p, AppState state) {
    final id = '${p['id']}';
    final author = '${p['author'] ?? ''}';
    final title = '${p['title'] ?? ''}';
    final body = '${p['body'] ?? ''}';
    final created = '${p['created'] ?? ''}';
    final updated = '${p['updated'] ?? ''}';
    final hasPassword = p['hasPassword'] == true;
    final pwdHint = '${p['pwdHint'] ?? ''}';
    final likes = (p['likes'] as num?)?.toInt() ?? 0;
    final views = (p['views'] as num?)?.toInt() ?? 0;
    final hidden = p['hidden'] == true;
    final comments = ((p['comments'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final attachments = ((p['attachments'] as List?) ?? [])
        .map((e) => '$e')
        .toList();
    final media = ((p['media'] as List?) ?? []).map((e) => '$e').toList();
    final links = ((p['links'] as List?) ?? []).map((e) => '$e').toList();
    final device = '${p['device'] ?? ''}';
    final ip = '${p['ip'] ?? ''}';
    final mine = state.who.isNotEmpty && author == state.who;

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
                  color: AppColors.purple,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    author.isEmpty ? '익명' : author,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    updated.isNotEmpty && updated != created
                        ? '$created  (수정 $updated)  ·  조회 $views'
                        : '$created  ·  조회 $views',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // URL 생성 — 이 게시글의 전체 주소를 바로 생성/복사 (외부에 노출된 버튼)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.purple,
                    side: BorderSide(
                      color: AppColors.purple.withValues(alpha: 0.5),
                    ),
                  ),
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('URL', style: TextStyle(fontSize: 12.5)),
                  onPressed: () => _shareLink(id),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      _editPost(existing: p);
                    } else if (v == 'delete') {
                      _deletePost(p);
                    } else if (v == 'share') {
                      _shareLink(id);
                    } else if (v == 'hide') {
                      _toggleHide(p, !hidden);
                    }
                  },
                  itemBuilder: (_) => [
                    if (_isAdmin || mine)
                      const PopupMenuItem(value: 'edit', child: Text('수정')),
                    if (_isAdmin || mine)
                      const PopupMenuItem(value: 'delete', child: Text('삭제')),
                    const PopupMenuItem(value: 'share', child: Text('URL 생성')),
                    if (_isAdmin)
                      PopupMenuItem(
                        value: 'hide',
                        child: Text(hidden ? '비노출 해제' : '비노출'),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          body,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textDark,
          ),
        ),
        if (hasPassword && pwdHint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                size: 13,
                color: AppColors.textGray,
              ),
              const SizedBox(width: 4),
              Text(
                '비밀번호 힌트: $pwdHint',
                style: const TextStyle(fontSize: 11, color: AppColors.textGray),
              ),
            ],
          ),
        ],
        if (_isAdmin && (device.isNotEmpty || ip.isNotEmpty)) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.taegeukRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.devices,
                  size: 12,
                  color: AppColors.taegeukRed,
                ),
                const SizedBox(width: 4),
                Text(
                  '기기: ${device.isEmpty ? '-' : device}'
                  '   IP: ${ip.isEmpty ? '-' : ip}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.taegeukRed,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (media.isNotEmpty) ...[
          const SizedBox(height: 8),
          _mediaStrip(media),
        ],
        if (attachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final a in attachments) _attachmentChip(a)],
          ),
        ],
        if (links.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final u in links) _linkChip(u)],
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  children: [
                    const Icon(
                      Icons.mode_comment_outlined,
                      size: 16,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '댓글 ${comments.length}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textGray,
                      ),
                    ),
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
                    Icon(Icons.attach_file, size: 16, color: AppColors.purple),
                    SizedBox(width: 3),
                    Text(
                      '첨부',
                      style: TextStyle(fontSize: 12.5, color: AppColors.purple),
                    ),
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

  Widget _mediaStrip(List<String> media) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: media.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final name = media[i];
          final isVideo = RegExp(
            r'\.(mp4|mov|webm|m4v)$',
            caseSensitive: false,
          ).hasMatch(name);
          final url = _nas.fileDownloadUrl('board', name);
          return GestureDetector(
            onTap: () => _openAttachment(name),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 150,
                color: Colors.black12,
                child: isVideo
                    ? const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          size: 40,
                          color: Colors.white,
                        ),
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image,
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
          const Icon(
            Icons.subdirectory_arrow_right,
            size: 14,
            color: AppColors.textGray,
          ),
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
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      created,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textGray,
                      ),
                    ),
                    if (_isAdmin && (device.isNotEmpty || ip.isNotEmpty)) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· ${device.isEmpty ? ip : device}'
                        '${(device.isNotEmpty && ip.isNotEmpty) ? ' / $ip' : ''}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.taegeukRed,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                SelectableText(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                ),
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
    child: Text(
      t,
      style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w800),
    ),
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
            Text(
              '좋아요 $likes',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: liked ? FontWeight.w800 : FontWeight.w500,
                color: liked ? AppColors.taegeukRed : AppColors.textGray,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentChip(String name) {
    return InkWell(
      onTap: () => _openAttachment(name),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.scoutGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.scoutGreen.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.attach_file,
              size: 14,
              color: AppColors.scoutGreen,
            ),
            const SizedBox(width: 4),
            Text(
              name,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.scoutGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkChip(String url) {
    return InkWell(
      onTap: () => _openLink(url),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: AppColors.taegeukBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.taegeukBlue.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link, size: 14, color: AppColors.taegeukBlue),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                url,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.taegeukBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 링크(URL) 열기 — 외부 브라우저/새 창.
  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _snack('올바른 링크가 아닙니다');
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri);
      } catch (_) {
        _snack('링크를 열 수 없습니다');
      }
    }
  }

  // ============================ 액션 ============================

  Future<void> _editPost({Map<String, dynamic>? existing}) async {
    final state = context.read<AppState>();
    final titleCtrl = TextEditingController(
      text: '${existing?['title'] ?? ''}',
    );
    final bodyCtrl = TextEditingController(text: '${existing?['body'] ?? ''}');
    final authorCtrl = TextEditingController(
      text: '${existing?['author'] ?? (state.who.isNotEmpty ? state.who : '')}',
    );
    final numberCtrl = TextEditingController(
      text: '${existing?['number'] ?? ''}',
    );
    final pwCtrl = TextEditingController();
    final hintCtrl = TextEditingController(
      text: '${existing?['pwdHint'] ?? ''}',
    );
    String category = '${existing?['category'] ?? '공지'}';
    bool hidden = existing?['hidden'] == true;
    // 글 작성 시 함께 올리는 첨부(사진/동영상/파일) + 링크(URL)
    final writeMedia = ((existing?['media'] as List?) ?? [])
        .map((e) => '$e')
        .toList();
    final writeAttacks = ((existing?['attachments'] as List?) ?? [])
        .map((e) => '$e')
        .toList();
    final writeLinks = ((existing?['links'] as List?) ?? [])
        .map((e) => '$e')
        .toList();
    final linkCtrl = TextEditingController();

    // 등록 버튼 활성 조건: 이름 + 제목 + 본문(글자수 제한 없음) + 비밀번호.
    //  · 비노출은 기본값 '노출'의 옵션이므로 활성 조건과 무관하다.
    //  · 수정 시 이미 비밀번호가 있는 글이면 재입력 없이도 통과한다.
    bool canSubmit() =>
        authorCtrl.text.trim().isNotEmpty &&
        titleCtrl.text.trim().isNotEmpty &&
        bodyCtrl.text.trim().isNotEmpty &&
        (pwCtrl.text.isNotEmpty || existing?['hasPassword'] == true);

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? '게시글 쓰기' : '게시글 수정'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: const InputDecoration(labelText: '분류'),
                          items: const [
                            DropdownMenuItem(value: '공지', child: Text('공지')),
                            DropdownMenuItem(value: '행사', child: Text('행사')),
                            DropdownMenuItem(value: '수품', child: Text('수품')),
                            DropdownMenuItem(value: '일반', child: Text('일반')),
                          ],
                          onChanged: (v) => setD(() => category = v ?? '공지'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: authorCtrl,
                          onChanged: (_) => setD(() {}),
                          decoration: const InputDecoration(labelText: '작성자'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: numberCtrl,
                          decoration: const InputDecoration(
                            labelText: '인가번호',
                            hintText: '(선택)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleCtrl,
                    onChanged: (_) => setD(() {}),
                    decoration: const InputDecoration(labelText: '제목'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 6,
                    minLines: 3,
                    onChanged: (_) => setD(() {}),
                    decoration: const InputDecoration(
                      labelText: '내용',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── 첨부(사진·동영상·파일) ──
                  Row(
                    children: [
                      const Icon(
                        Icons.attach_file,
                        size: 16,
                        color: AppColors.purple,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '첨부 (사진 · 동영상 · 파일)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          final picked = await pickDataFiles(
                            allowMultiple: true,
                            dialogTitle: '게시글 첨부 (사진/동영상/파일)',
                          );
                          if (picked.isEmpty) return;
                          for (final f in picked) {
                            await _nas.uploadFile('board', f.name, f.bytes);
                            final isMedia = RegExp(
                              r'\.(jpg|jpeg|png|gif|webp|mp4|mov|webm|m4v)$',
                              caseSensitive: false,
                            ).hasMatch(f.name);
                            if (isMedia) {
                              writeMedia.add(f.name);
                            } else {
                              writeAttacks.add(f.name);
                            }
                          }
                          setD(() {});
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('파일 선택'),
                      ),
                    ],
                  ),
                  if (writeMedia.isEmpty && writeAttacks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(left: 2, bottom: 2),
                      child: Text(
                        '첨부된 파일이 없습니다',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final n in [...writeMedia, ...writeAttacks])
                          InputChip(
                            label: Text(
                              n,
                              style: const TextStyle(fontSize: 11),
                            ),
                            avatar: Icon(
                              writeMedia.contains(n)
                                  ? Icons.image_outlined
                                  : Icons.insert_drive_file_outlined,
                              size: 15,
                              color: AppColors.scoutGreen,
                            ),
                            onDeleted: () => setD(() {
                              writeMedia.remove(n);
                              writeAttacks.remove(n);
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  // ── 링크(URL) ──
                  Row(
                    children: [
                      const Icon(Icons.link, size: 16, color: AppColors.purple),
                      const SizedBox(width: 6),
                      const Text(
                        '링크 (URL)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: linkCtrl,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: '링크 주소',
                            hintText: 'https://...',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          final u = linkCtrl.text.trim();
                          if (u.isEmpty) return;
                          writeLinks.add(u);
                          linkCtrl.clear();
                          setD(() {});
                        },
                        child: const Text('추가'),
                      ),
                    ],
                  ),
                  if (writeLinks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final u in writeLinks)
                            InputChip(
                              label: Text(
                                u,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              avatar: const Icon(
                                Icons.public,
                                size: 15,
                                color: AppColors.taegeukBlue,
                              ),
                              onDeleted: () => setD(() => writeLinks.remove(u)),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: pwCtrl,
                          obscureText: true,
                          onChanged: (_) => setD(() {}),
                          decoration: InputDecoration(
                            labelText: existing?['hasPassword'] == true
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
                          decoration: const InputDecoration(labelText: '힌트'),
                        ),
                      ),
                    ],
                  ),
                  if (_isAdmin) ...[
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: hidden,
                      title: const Text(
                        '비노출(관리자만 보기)',
                        style: TextStyle(fontSize: 13),
                      ),
                      onChanged: (v) => setD(() => hidden = v == true),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('취소'),
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
    if (res != 'publish') return;
    if (titleCtrl.text.trim().isEmpty) return;
    try {
      await _nas.boardSave(
        id: '${existing?['id'] ?? ''}',
        category: category,
        title: titleCtrl.text.trim(),
        body: bodyCtrl.text.trim(),
        author: authorCtrl.text.trim(),
        number: numberCtrl.text.trim(),
        hidden: hidden,
        password: pwCtrl.text,
        pwdHint: hintCtrl.text.trim(),
        device: _deviceLabel(),
        attachments: writeAttacks,
        media: writeMedia,
        links: writeLinks,
      );
      _snack(existing == null ? '등록했습니다' : '수정했습니다');
      await _load();
    } catch (e) {
      _snack('저장 실패: $e');
    }
  }

  Future<void> _addComment(Map<String, dynamic> post) async {
    final state = context.read<AppState>();
    final ctrl = TextEditingController();
    final authorCtrl = TextEditingController(
      text: state.who.isNotEmpty ? state.who : '',
    );
    final pwCtrl = TextEditingController();
    final locked = post['hasPassword'] == true;
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
      final r = await _nas.boardComment(
        postId: '${post['id']}',
        author: authorCtrl.text.trim(),
        number: '${post['number'] ?? ''}',
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
      await _nas.boardLike(postId: id, on: on);
      await _load();
    } catch (e) {
      _snack('좋아요 실패: $e');
    }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    String pw = '';
    if (post['hasPassword'] == true && !_isAdmin) {
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
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      pw = ctrl.text;
    }
    final done = await _nas.boardDelete(postId: '${post['id']}', password: pw);
    _snack(done ? '삭제했습니다' : '삭제 실패 (비밀번호 확인)');
    await _load();
  }

  Future<void> _deleteComment(Map<String, dynamic> post, String cid) async {
    await _nas.boardDelete(postId: '${post['id']}', commentId: cid);
    await _load();
  }

  Future<void> _toggleHide(Map<String, dynamic> post, bool hidden) async {
    await _nas.boardHide(postId: '${post['id']}', hidden: hidden);
    _snack(hidden ? '비노출로 지정했습니다' : '비노출을 해제했습니다');
    await _load();
  }

  Future<void> _addAttachment(Map<String, dynamic> post) async {
    final picked = await pickDataFiles(
      allowMultiple: true,
      dialogTitle: '게시판 첨부 추가 (사진/동영상/파일)',
    );
    if (picked.isEmpty) return;
    final media = ((post['media'] as List?) ?? []).map((e) => '$e').toList();
    final attachments = ((post['attachments'] as List?) ?? [])
        .map((e) => '$e')
        .toList();
    final links = ((post['links'] as List?) ?? []).map((e) => '$e').toList();
    try {
      for (final f in picked) {
        await _nas.uploadFile('board', f.name, f.bytes);
        final isMedia = RegExp(
          r'\.(jpg|jpeg|png|gif|webp|mp4|mov|webm|m4v)$',
          caseSensitive: false,
        ).hasMatch(f.name);
        if (isMedia) {
          media.add(f.name);
        } else {
          attachments.add(f.name);
        }
      }
      await _nas.boardSave(
        id: '${post['id']}',
        category: '${post['category'] ?? '일반'}',
        title: '${post['title'] ?? ''}',
        body: '${post['body'] ?? ''}',
        author: '${post['author'] ?? ''}',
        number: '${post['number'] ?? ''}',
        hidden: post['hidden'] == true,
        attachments: attachments,
        media: media,
        links: links,
      );
      _snack('첨부했습니다');
      await _load();
    } catch (e) {
      _snack('첨부 실패: $e');
    }
  }

  void _openAttachment(String name) {
    final url = _nas.fileDownloadUrl('board', name);
    final isImg = RegExp(
      r'\.(jpg|jpeg|png|gif|webp)$',
      caseSensitive: false,
    ).hasMatch(name);
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
              child: isImg
                  ? InteractiveViewer(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('미리보기를 열 수 없는 파일입니다'),
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.insert_drive_file,
                            size: 48,
                            color: AppColors.textGray,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '첨부파일 (별도 창에서 열람)',
                            style: TextStyle(color: AppColors.textGray),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.download),
                            label: const Text('링크 복사 안내'),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 이 게시글의 "전체 주소"를 만든다.
  ///  · 웹에서는 현재 접속한 실제 origin(예: https://39.123.241.4:5071)을 사용하고,
  ///  · 그 외(네이티브)에서는 서버 baseUrl 에서 origin 을 추출한다.
  String _postFullUrl(String id) {
    String origin = '';
    if (kIsWeb) {
      try {
        origin = Uri.base.origin; // 실제 브라우저 주소창의 origin
      } catch (_) {
        origin = '';
      }
    }
    if (origin.isEmpty || origin == 'null') {
      origin = _nas.baseUrl.split('/api').first.replaceAll(RegExp(r'/+$'), '');
    }
    return '$origin/?access=board&id=${Uri.encodeComponent(id)}';
  }

  Future<void> _shareLink(String id) async {
    final link = _postFullUrl(id);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.link, color: AppColors.purple, size: 34),
        title: const Text('이 게시글 URL 생성'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '아래 URL이 이 게시글의 전체 주소입니다. 그대로 복사해 다른 사람에게 보낼 수 있으며, 외부에서 접속해도 로그인한 권한자만 열람할 수 있습니다.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textGray,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.purple.withValues(alpha: 0.25),
                ),
              ),
              // 전체 주소를 줄바꿈 없이 그대로 노출(길면 자동 스크롤).
              child: SelectableText(
                link,
                maxLines: null,
                style: const TextStyle(fontSize: 12, color: AppColors.purple),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(ctx);
              _snack('이 게시글 전체 주소를 복사했습니다');
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('URL 복사'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
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

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }
}
