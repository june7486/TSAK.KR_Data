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
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/memorial_api.dart';
import '../theme/app_theme.dart';
import '../widgets/tsak_app_bar.dart';

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
    _likeKey = 'lk${auth['name']?.hashCode ?? 0}${DateTime.now().millisecondsSinceEpoch}';
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
    if (_filter == '전체') return all;
    return all.where((p) => p.kind == _filter).toList();
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
                p.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
              leading: const Icon(Icons.delete_outline, color: AppColors.taegeukRed),
              title: const Text('삭제', style: TextStyle(color: AppColors.taegeukRed)),
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
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.taegeukRed),
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

  Future<void> _addComment(MemorialPost p) async {
    final auth = await _api.recallAuthor();
    if (!mounted) return;
    final ctrl = TextEditingController();
    final nm = TextEditingController(text: auth['name'] ?? '');
    final no = TextEditingController(text: auth['number'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('댓글 남기기'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: nm,
                      decoration: const InputDecoration(labelText: '이름'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: no,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '인가번호'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '따뜻한 말 한마디 남겨주세요'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('남기기')),
        ],
      ),
    );
    if (ok != true) return;
    if (ctrl.text.trim().isEmpty) return;
    try {
      await _api.addComment(
        id: widget.memorialId,
        postId: p.id,
        name: nm.text.trim(),
        number: no.text.trim(),
        body: ctrl.text.trim(),
      );
      await _api.rememberAuthor(nm.text.trim(), no.text.trim());
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
    final base = context.read<AppState>().nas.baseUrl.replaceAll(RegExp(r'/+$'), '');
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
              _stats(d),
              _tabs(),
              if (_visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 44),
                  child: Column(
                    children: [
                      const Icon(Icons.local_florist_outlined,
                          size: 36, color: AppColors.textGray),
                      const SizedBox(height: 10),
                      Text(
                        _filter == '전체'
                            ? '아직 남겨진 기억이 없습니다.\n첫 마음을 남겨주세요.'
                            : '이 종류의 기록이 아직 없습니다.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textGray, height: 1.6),
                      ),
                    ],
                  ),
                )
              else
                ..._visible.map(_postCard),
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
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.person, size: 52, color: Colors.white70),
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

  // ── 상부 참여 버튼 3종 ───────────────────────────────────────────────
  Widget _ctaBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Row(
        children: [
          _cta('✍️', '추모글', '기억 남기기', () => _openEditor()),
          const SizedBox(width: 8),
          _cta('📷', '사진', '추억 올리기', () => _openEditor(photoFirst: true)),
          const SizedBox(width: 8),
          _cta('📎', '자료', '기록 보태기', () => _openEditor(fileFirst: true)),
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
                style: const TextStyle(fontSize: 9.5, color: AppColors.textGray),
              ),
            ],
          ),
        ),
      ),
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
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textGray)),
            ],
          ),
        );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          one('추모글', d.countOf('글')),
          one('사진', d.countOf('사진')),
          one('자료', d.countOf('자료')),
          one('공감', d.likeTotal),
        ],
      ),
    );
  }

  // ── 종류 필터 ───────────────────────────────────────────────────────
  Widget _tabs() {
    const items = ['전체', '글', '사진', '자료'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: items.map((f) {
          final on = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: ChoiceChip(
              label: Text(f == '글' ? '추모글' : f),
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
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                      style: const TextStyle(fontSize: 10, color: AppColors.textGray),
                    ),
                  ],
                ),
              ),
              _kindBadge(p.kind),
              if (canManage)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                icon: const Icon(Icons.favorite, size: 16, color: Color(0xFFD64550)),
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
                            text: '${c.name.isEmpty ? '익명' : c.name}'
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

  Widget _kindBadge(String kind) {
    final (bg, fg) = switch (kind) {
      '사진' => (const Color(0xFFE8F1FB), const Color(0xFF1B4F9C)),
      '자료' => (const Color(0xFFF3EDE1), const Color(0xFF8A6B27)),
      _ => (const Color(0xFFEDE8F7), AppColors.purple),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(
        kind,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
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
          final url = _api.fileUrl(p.photos[i]);
          return GestureDetector(
            onTap: () => _viewImage(url),
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
                  child: const Icon(Icons.broken_image_outlined,
                      size: 22, color: AppColors.textGray),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fileRow(Map<String, dynamic> a) {
    final name = '${a['name'] ?? '자료'}';
    final url = _api.fileUrl('${a['url'] ?? ''}');
    return InkWell(
      onTap: url.isEmpty ? null : () => launchUrl(Uri.parse(url)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            const Icon(Icons.attach_file, size: 15, color: AppColors.textGray),
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _pick(imagesOnly: true));
    } else if (widget.fileFirst) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pick(imagesOnly: false));
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
          : const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'pdf', 'doc',
              'docx', 'hwp', 'hwpx', 'txt', 'ppt', 'pptx', 'xls', 'xlsx'],
      allowMultiple: true,
      dialogTitle: imagesOnly ? '추억 사진 선택' : '자료 선택',
    );
    if (picked.isEmpty || !mounted) return;

    setState(() => _uploading = true);
    try {
      for (final f in picked) {
        // 25MB 초과는 서버가 거절한다 — 먼저 알려 헛수고를 막는다.
        if (f.bytes.length > 25 * 1024 * 1024) {
          setState(() => _err = '${f.name}: 25MB 를 넘어 올릴 수 없습니다');
          continue;
        }
        final j = await widget.api.upload(
          id: widget.memorialId,
          name: f.name,
          bytes: Uint8List.fromList(f.bytes),
        );
        final url = '${j['url'] ?? ''}';
        if (url.isEmpty) continue;
        if (j['isImage'] == true) {
          _photos.add(url);
        } else {
          _files.add({
            'name': '${j['name'] ?? f.name}',
            'url': url,
            'size': j['size'] ?? f.bytes.length,
          });
        }
      }
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
                      onPressed: _uploading ? null : () => _pick(imagesOnly: true),
                      icon: const Icon(Icons.photo_camera_outlined, size: 17),
                      label: const Text('사진', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),
                    const SizedBox(width: 7),
                    OutlinedButton.icon(
                      onPressed: _uploading ? null : () => _pick(imagesOnly: false),
                      icon: const Icon(Icons.attach_file, size: 17),
                      label: const Text('자료', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
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
                                child: const Icon(Icons.close, size: 11, color: Colors.white),
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
                        const Icon(Icons.description_outlined,
                            size: 14, color: AppColors.textGray),
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
                            child: Icon(Icons.close, size: 13, color: AppColors.textGray),
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
                    style: const TextStyle(fontSize: 11.5, color: AppColors.taegeukRed),
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
