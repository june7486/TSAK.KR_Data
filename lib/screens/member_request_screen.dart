import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/tsak_detail_sheet.dart';
import '../widgets/member_registration_request_section.dart'
    show MemberRequestLabels;

/// 통합승인관리 — (관리자·마스터 전용)
///
/// 관리자/마스터의 승인이 필요한 **모든** 요청을 한 화면에서 통합 처리한다.
///   · 일반회원(비인가회원) 승인
///   · 행사참가 승인
///   · 연회비납부 승인
///   · 평생회원 승인
///   · 참가비납부 승인
///   · 멘토 등록 승인
///   · 페런츠 등록 승인
///   · (향후 새 항목이 추가되어도 서버가 큐로 내려주면 자동 노출)
///
/// 서버 `/api/approval/overview` 가 큐(dict) 목록을 내려주고,
/// 각 큐는 kind='member'(일반회원) | 'request'(등록요청) | 'link'(연결) 로 나뉜다.
///
/// 승인 버튼을 누르면 해당 항목은 대기 큐에서 사라지고,
/// 화면 하단의 **승인 히스토리**(승인요청일·승인자·복원·삭제)로 이동한다.
///   · 복원 = 다시 승인창(대기 큐)으로 올림
///   · 삭제 = 히스토리에서 완전 제거
class MemberRequestScreen extends StatefulWidget {
  const MemberRequestScreen({super.key});

  @override
  State<MemberRequestScreen> createState() => _MemberRequestScreenState();
}

class _MemberRequestScreenState extends State<MemberRequestScreen> {
  List<Map<String, dynamic>> _queues = [];
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  /// 히스토리 영역 펼침 여부
  bool _showHistory = true;

  /// 히스토리 소스 필터: ''(전체) | 'regular' | 'request' | 'link'
  String _histFilter = '';

  /// 큐 key → 선택된 항목 id 집합
  final Map<String, Set<String>> _selected = {};

  /// 펼쳐서 상세를 보여줄 히스토리 id
  String? _expandedHistory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await state.fetchApprovalOverview();
      final hist = await state.fetchApprovalHistory(limit: 200);
      if (!mounted) return;
      setState(() {
        _queues = list;
        _history = hist;
        _selected.clear();
        _loading = false;
      });
      // 목록을 열어 확인했으므로 '해당 아이디 기준'으로 확인 처리한다.
      //  → 홈 화면 배지에서 확인한 만큼 차감된다(이후 새 항목만 다시 표시).
      await state.markBadgeSeen(kind: 'approval');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  /// 히스토리만 다시 로드(승인/복원/삭제 후).
  Future<void> _reloadHistory() async {
    final state = context.read<AppState>();
    try {
      final hist = await state.fetchApprovalHistory(limit: 200);
      if (!mounted) return;
      setState(() => _history = hist);
    } catch (_) {}
  }

  int get _total =>
      _queues.fold<int>(0, (p, q) => p + ((q['count'] as num?)?.toInt() ?? 0));

  Set<String> _selOf(String key) =>
      _selected.putIfAbsent(key, () => <String>{});

  void _toggle(String key, String id) {
    setState(() {
      final s = _selOf(key);
      if (s.contains(id)) {
        s.remove(id);
      } else {
        s.add(id);
      }
    });
  }

  /// 큐 항목 일괄 처리.
  /// kind='member' → [action]: approve|hold|pending|delete
  /// kind='request' → [action]: approve|reject
  /// kind='link'    → [action]: approve|hold|pending
  Future<void> _act(
    String kind,
    String action,
    List<String> ids,
    String identFallback,
  ) async {
    if (ids.isEmpty) {
      _snack('대상을 선택하세요');
      return;
    }
    final state = context.read<AppState>();
    setState(() => _busy = true);
    var done = 0;
    if (kind == 'member') {
      done = await state.setApproval(action, ids);
    } else if (kind == 'link') {
      for (final id in ids) {
        try {
          final r = await state.nas.linkSet(action: action, idents: [id]);
          if (r['ok'] == true) done++;
        } catch (_) {}
      }
    } else {
      for (final id in ids) {
        final ok = await state.setMemberRequest(id, action);
        if (ok) done++;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final label = action == 'approve'
        ? '승인'
        : action == 'reject'
        ? '반려'
        : action == 'hold'
        ? '보류'
        : action == 'delete'
        ? '삭제'
        : '대기';
    _snack('$label 처리: $done/${ids.length}건');
    await _refresh();
    // 승인 후 명단/배지 갱신
    if (mounted) context.read<AppState>().refresh();
  }

  Future<void> _restoreHistory(Map<String, dynamic> it) async {
    final state = context.read<AppState>();
    final id = '${it['id'] ?? ''}';
    if (id.isEmpty) return;
    setState(() => _busy = true);
    final ok = await state.restoreApprovalHistory(id);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(ok ? '복원했습니다 — 승인창(대기)으로 올렸습니다' : '복원하지 못했습니다');
    if (ok) {
      await _refresh();
      if (mounted) context.read<AppState>().refresh();
    }
  }

  Future<void> _deleteHistory(Map<String, dynamic> it) async {
    final state = context.read<AppState>();
    final id = '${it['id'] ?? ''}';
    if (id.isEmpty) return;
    final ok = await _confirm(
      '히스토리 삭제',
      '이 승인 기록을 히스토리에서 완전히 삭제할까요?\n\n'
          '삭제하면 복원할 수 없습니다.',
      danger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final done = await state.deleteApprovalHistory([id]);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(done ? '히스토리에서 삭제했습니다' : '삭제하지 못했습니다');
    if (done) await _reloadHistory();
  }

  Future<bool?> _confirm(String title, String body, {bool danger = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          title,
          style: TextStyle(
            color: danger ? AppColors.taegeukRed : AppColors.textDark,
          ),
        ),
        content: Text(body, style: const TextStyle(fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger
                  ? AppColors.taegeukRed
                  : AppColors.taegeukBlue,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(danger ? '삭제' : '확인'),
          ),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!(state.isApp || state.isMaster)) {
      return Scaffold(
        appBar: TsakAppBar(
          leading: const AppBackButton(label: '뒤로'),
          leadingWidth: 84,
          title: const Text('통합승인관리'),
        ),
        body: const Center(child: Text('관리자 권한이 필요합니다')),
      );
    }
    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('통합승인관리'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const AppHomeEmblem(size: 24),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _summary(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? _errorBox()
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 90),
                          children: [
                            if (_queues.isEmpty)
                              _empty()
                            else
                              for (final q in _queues) _queueSection(q),
                            _historySection(),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          BusyOverlay(
            visible: _loading || _busy,
            title: _busy ? '요청을 처리하는 중입니다' : '승인 요청을 불러오는 중입니다',
            lines: _busy
                ? const [
                    'NAS 서버에 처리 결과를 반영하고 있습니다...',
                    '요청 목록을 갱신하는 중...',
                    '잠시만 기다려 주세요...',
                  ]
                : const [
                    'NAS 서버에서 승인 요청을 가져오는 중...',
                    '회원 요청을 정리하는 중...',
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
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          const Icon(Icons.verified_user, size: 20, color: AppColors.tigerGold),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '승인 대기 (전체 항목)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: (_total == 0 ? AppColors.scoutGreen : AppColors.tigerGold)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$_total건',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: _total == 0 ? AppColors.scoutGreen : AppColors.tigerGold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _queueSection(Map<String, dynamic> q) {
    final key = '${q['key'] ?? ''}';
    final title = '${q['title'] ?? '승인 항목'}';
    final kind = '${q['kind'] ?? 'request'}';
    final items = ((q['items'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final sel = _selOf(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            children: [
              Icon(_queueIcon(key), size: 18, color: _queueColor(key)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: _queueColor(key).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${items.length}건',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: _queueColor(key),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (items.isNotEmpty) _bulkBar(key, kind, items, sel),
        for (final it in items)
          _itemCard(key, kind, it, sel.contains('${it['id'] ?? it['number']}')),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Text(
              '대기 중인 항목이 없습니다',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
          ),
      ],
    );
  }

  IconData _queueIcon(String key) {
    if (key == 'regular') return Icons.person_add;
    if (key.contains('lifetime')) return Icons.star;
    if (key.contains('fee')) return Icons.card_membership;
    if (key.contains('event')) return Icons.event_available;
    if (key.contains('link')) return Icons.family_restroom;
    return Icons.rule;
  }

  Color _queueColor(String key) {
    if (key == 'regular') return AppColors.purple;
    if (key.contains('lifetime')) return AppColors.lifetimeGold;
    if (key.contains('fee')) return AppColors.scoutGreen;
    if (key.contains('event')) return AppColors.taegeukBlue;
    if (key.contains('link')) return AppColors.purple;
    return AppColors.textGray;
  }

  String _idOf(Map<String, dynamic> it) {
    final id = '${it['id'] ?? ''}'.trim();
    if (id.isNotEmpty) return id;
    return '${it['number'] ?? it['ident'] ?? ''}';
  }

  /// 연결 승인 대상 종류 라벨 — 멘토 / 페런츠 / 멘토·페런츠 (요구: 구분).
  String _linkKindLabel(Map<String, dynamic> m) {
    final s = '${m['linkKind'] ?? ''}'.trim();
    if (s.isNotEmpty) return s;
    final hm =
        m['hasMentor'] == true || ((m['mentors'] as List?) ?? []).isNotEmpty;
    final hp =
        m['hasParent'] == true || ((m['parents'] as List?) ?? []).isNotEmpty;
    if (hm && hp) return '멘토·페런츠';
    if (hm) return '멘토';
    if (hp) return '페런츠';
    return '연결';
  }

  Color _linkKindColor(Map<String, dynamic> m) {
    final hm =
        m['hasMentor'] == true || ((m['mentors'] as List?) ?? []).isNotEmpty;
    final hp =
        m['hasParent'] == true || ((m['parents'] as List?) ?? []).isNotEmpty;
    if (hm && hp) return AppColors.tigerGold;
    if (hp) return AppColors.taegeukBlue;
    return AppColors.purple;
  }

  /// 승인요청방법 라벨 — 수품신청시 / 직접입력 (요구).
  String _reqSourceLabel(Map<String, dynamic> it) {
    final lbl = '${it['reqSourceLabel'] ?? ''}'.trim();
    if (lbl.isNotEmpty) return lbl;
    final s = '${it['reqSource'] ?? ''}'.trim();
    switch (s) {
      case 'merch':
        return '수품신청시';
      case 'direct':
        return '직접입력';
      case 'bulk':
        return '일괄등록';
      case 'import':
        return '이관';
      default:
        return '직접입력';
    }
  }

  Widget _bulkBar(
    String key,
    String kind,
    List<Map<String, dynamic>> items,
    Set<String> sel,
  ) {
    final ids = items.map(_idOf).toList();
    final allSel = sel.length == ids.length && ids.isNotEmpty;
    return Container(
      color: AppColors.purple.withValues(alpha: 0.04),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => setState(() {
              if (allSel) {
                sel.clear();
              } else {
                sel
                  ..clear()
                  ..addAll(ids);
              }
            }),
            icon: Icon(
              allSel ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
            ),
            label: Text(
              '전체 선택 (${sel.length}/${ids.length})',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.scoutGreen,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _busy || sel.isEmpty
                ? null
                : () => _act(kind, 'approve', sel.toList(), ''),
            icon: const Icon(Icons.check, size: 15),
            label: Text(
              '선택 승인 (${sel.length})',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 승인요청/연결요청 항목의 상세를 시트로 표시(카드 클릭).
  void _showRequestDetail(
    String key,
    String kind,
    Map<String, dynamic> m,
  ) {
    final color = _queueColor(key);
    final name = '${m['name'] ?? '(이름없음)'}';
    final number = '${m['number'] ?? m['ident'] ?? ''}';
    final numLabel = Member.numLabelOf(number, '${m['corps'] ?? 'tsak'}');
    final type = '${m['type'] ?? ''}';
    final mentors =
        ((m['mentorLabels'] as List?) ?? (m['mentors'] as List?) ?? [])
            .map((e) => '$e')
            .toList();
    final parents =
        ((m['parentLabels'] as List?) ?? (m['parents'] as List?) ?? [])
            .map((e) => '$e')
            .toList();
    final children =
        ((m['childLabels'] as List?) ?? (m['children'] as List?) ?? [])
            .map((e) => '$e')
            .toList();
    showTsakDetailSheet(
      context,
      title: name,
      subtitle: kind == 'link'
          ? '연결 요청 · ${_linkKindLabel(m)}'
          : '승인 요청 · ${MemberRequestLabels.label(type)}',
      icon: kind == 'link'
          ? Icons.link
          : (type.isNotEmpty
                ? MemberRequestLabels.icon(type)
                : Icons.how_to_reg),
      accent: color,
      entries: tsakEntries([
        TsakDetailEntry(
          label: '구분',
          value: kind == 'link' ? '연결 요청 (${_linkKindLabel(m)})' : '승인 요청',
          icon: Icons.category_outlined,
          color: color,
          copyable: false,
        ),
        TsakDetailEntry(
          label: '요청유형',
          value: MemberRequestLabels.label(type),
          icon: Icons.label_outline,
          emphasize: type.isNotEmpty,
        ),
        TsakDetailEntry(
          label: '인가번호',
          value: numLabel.isEmpty ? number : numLabel,
          icon: Icons.confirmation_number_outlined,
          mono: true,
        ),
        TsakDetailEntry(
          label: '연맹',
          value: '${m['league'] ?? ''}',
          icon: Icons.flag_outlined,
        ),
        TsakDetailEntry(
          label: '소속대',
          value: '${m['unit'] ?? ''}',
          icon: Icons.groups_outlined,
        ),
        TsakDetailEntry(
          label: '핸드폰',
          value: '${m['phone'] ?? m['loginId'] ?? ''}',
          icon: Icons.phone_outlined,
          mono: true,
        ),
        TsakDetailEntry(
          label: '아이디',
          value: '${m['loginId'] ?? ''}',
          icon: Icons.badge_outlined,
          mono: true,
        ),
        TsakDetailEntry(label: '연도', value: '${m['year'] ?? ''}'),
        TsakDetailEntry(label: '날짜', value: '${m['date'] ?? ''}'),
        TsakDetailEntry(
          label: '행사',
          value: '${m['event'] ?? ''}',
          icon: Icons.event_outlined,
        ),
        TsakDetailEntry(label: '메모', value: '${m['note'] ?? ''}'),
        if (mentors.isNotEmpty)
          TsakDetailEntry(
            label: '지도자',
            value: mentors.join(', '),
            icon: Icons.school_outlined,
          ),
        if (parents.isNotEmpty)
          TsakDetailEntry(
            label: '부모',
            value: parents.join(', '),
            icon: Icons.family_restroom,
          ),
        if (children.isNotEmpty)
          TsakDetailEntry(
            label: '자녀',
            value: children.join(', '),
            icon: Icons.child_care_outlined,
          ),
        TsakDetailEntry(
          label: '요청시각',
          value: '${m['requestedAt'] ?? ''}',
          icon: Icons.schedule,
          mono: true,
        ),
        TsakDetailEntry(
          label: '요청경로',
          value: _reqSourceLabel(m),
          icon: Icons.call_split,
        ),
        TsakDetailEntry(
          label: '요청자',
          value: (m['by'] is Map) ? _byLabel(m['by']) : '',
          icon: Icons.person_outline,
        ),
        TsakDetailEntry(
          label: '등록일',
          value: '${m['created'] ?? ''}',
          icon: Icons.calendar_today_outlined,
          mono: true,
        ),
      ]),
    );
  }

  Widget _itemCard(String key, String kind, Map<String, dynamic> m, bool sel) {
    final id = _idOf(m);
    final color = _queueColor(key);
    final name = '${m['name'] ?? '(이름없음)'}';
    final number = '${m['number'] ?? m['ident'] ?? ''}';
    final numLabel =
        Member.numLabelOf(number, '${m['corps'] ?? 'tsak'}');
    final phone = '${m['phone'] ?? m['loginId'] ?? ''}';
    final type = '${m['type'] ?? ''}';
    final year = '${m['year'] ?? ''}'.trim();
    final date = '${m['date'] ?? ''}'.trim();
    final event = '${m['event'] ?? ''}'.trim();
    final note = '${m['note'] ?? ''}'.trim();
    final created = '${m['created'] ?? ''}';
    final by = (m['by'] is Map) ? _byLabel(m['by']) : '';
    final mentors =
        ((m['mentorLabels'] as List?) ?? (m['mentors'] as List?) ?? [])
            .map((e) => '$e')
            .toList();
    final parents =
        ((m['parentLabels'] as List?) ?? (m['parents'] as List?) ?? [])
            .map((e) => '$e')
            .toList();
    final reqAt = '${m['requestedAt'] ?? ''}'.trim();
    final reqSrc = _reqSourceLabel(m);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: sel ? AppColors.scoutGreen : color.withValues(alpha: 0.25),
          width: sel ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showRequestDetail(key, kind, m),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 좌측 선택박스 — 상시 노출(체크 시 선택).
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _toggle(key, id),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        sel ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 20,
                        color: sel ? AppColors.scoutGreen : AppColors.textGray,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$name${numLabel.isNotEmpty ? '  $numLabel' : ''}',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (kind == 'link')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _linkKindColor(m).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _linkKindLabel(m),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _linkKindColor(m),
                        ),
                      ),
                    ),
                  if (kind == 'request' && type.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            MemberRequestLabels.icon(type),
                            size: 12,
                            color: color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            MemberRequestLabels.label(type),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (kind == 'member') ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (phone.isNotEmpty) _meta(Icons.phone, phone),
                    if ('${m['league'] ?? ''}'.isNotEmpty)
                      _meta(Icons.groups, '${m['league']}'),
                    if ('${m['unit'] ?? ''}'.isNotEmpty)
                      _meta(Icons.flag, '${m['unit']}'),
                    if (created.isNotEmpty)
                      _meta(Icons.schedule, '가입 $created'),
                  ],
                ),
              ] else if (kind == 'link') ...[
                const SizedBox(height: 6),
                if ('${m['league'] ?? ''}'.isNotEmpty ||
                    '${m['unit'] ?? ''}'.isNotEmpty)
                  _meta(
                    Icons.groups,
                    [
                      '${m['league'] ?? ''}',
                      '${m['unit'] ?? ''}',
                    ].where((e) => e.isNotEmpty).join(' · '),
                  ),
                // 승인요청시간 + 승인요청방법(수품신청시/직접입력) — 요구.
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (reqAt.isNotEmpty) _meta(Icons.schedule, '승인요청 $reqAt'),
                    _meta(Icons.input, '승인요청방법: $reqSrc'),
                  ],
                ),
                // 승인대기중 안내 — 관리자·마스터 승인 전 상태 설명(요구).
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.hourglass_top,
                        size: 14,
                        color: AppColors.tigerGold,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '승인대기중 — 관리자·마스터가 승인하면 정식 등록됩니다.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: AppColors.tigerGold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (mentors.isNotEmpty)
                  _linkRow('멘토', mentors, AppColors.purple),
                if (parents.isNotEmpty)
                  _linkRow('페런츠', parents, AppColors.taegeukBlue),
                // (요구 #3) 멘티·자녀대원 등록정보 — 본인이 멘토/페런츠로서 등록.
                if ((((m['menteeLabels'] as List?) ??
                        (m['mentees'] as List?) ??
                        [])
                    .map((e) => '$e')
                    .toList())
                    .isNotEmpty)
                  _linkRow(
                    '멘티대원',
                    ((m['menteeLabels'] as List?) ?? (m['mentees'] as List?) ?? [])
                        .map((e) => '$e')
                        .toList(),
                    AppColors.purple,
                  ),
                if ((((m['childLabels'] as List?) ??
                        (m['children'] as List?) ??
                        [])
                    .map((e) => '$e')
                    .toList())
                    .isNotEmpty)
                  _linkRow(
                    '자녀대원',
                    ((m['childLabels'] as List?) ?? (m['children'] as List?) ?? [])
                        .map((e) => '$e')
                        .toList(),
                    AppColors.taegeukBlue,
                  ),
              ] else ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (type == 'fee' && year.isNotEmpty)
                      _meta(Icons.event, '$year년 연회비'),
                    if (type == 'lifetime' && date.isNotEmpty)
                      _meta(Icons.event_available, '납부일자 $date'),
                    if (type == 'event' && event.isNotEmpty)
                      _meta(Icons.celebration, event),
                    if (created.isNotEmpty)
                      _meta(Icons.schedule, '요청 $created'),
                    if (by.isNotEmpty) _meta(Icons.person, '$by 요청'),
                  ],
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.sticky_note_2_outlined,
                        size: 13,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          note,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: _buttons(kind, id)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkRow(String label, List<String> codes, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textGray,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final c in codes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buttons(String kind, String id) {
    if (kind == 'member') {
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.scoutGreen,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _busy ? null : () => _act(kind, 'approve', [id], ''),
          icon: const Icon(Icons.check, size: 15),
          label: const Text('승인'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.tigerGold,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _busy ? null : () => _act(kind, 'hold', [id], ''),
          icon: const Icon(Icons.pause, size: 15),
          label: const Text('보류'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: _busy ? null : () => _act(kind, 'pending', [id], ''),
          icon: const Icon(Icons.hourglass_empty, size: 15),
          label: const Text('대기'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.taegeukRed,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _busy ? null : () => _act(kind, 'delete', [id], ''),
          icon: const Icon(Icons.delete_outline, size: 15),
          label: const Text('삭제'),
        ),
      ];
    }
    if (kind == 'link') {
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.scoutGreen,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _busy ? null : () => _act(kind, 'approve', [id], ''),
          icon: const Icon(Icons.check, size: 15),
          label: const Text('승인'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.tigerGold,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _busy ? null : () => _act(kind, 'hold', [id], ''),
          icon: const Icon(Icons.pause, size: 15),
          label: const Text('보류'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: _busy ? null : () => _act(kind, 'pending', [id], ''),
          icon: const Icon(Icons.hourglass_empty, size: 15),
          label: const Text('대기'),
        ),
      ];
    }
    return [
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.scoutGreen,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: _busy ? null : () => _act(kind, 'approve', [id], ''),
        icon: const Icon(Icons.check, size: 15),
        label: const Text('승인'),
      ),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.taegeukRed,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: _busy ? null : () => _act(kind, 'reject', [id], ''),
        icon: const Icon(Icons.close, size: 15),
        label: const Text('반려'),
      ),
    ];
  }

  String _byLabel(dynamic by) {
    if (by is! Map) return '';
    for (final v in by.values) {
      final s = '$v'.trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// 인적사항 라벨 목록 추출 — *Labels(이름·소속·전화 보강) 우선, 없으면 번호.
  /// 요구: "멘토·멘티·페런츠 모든 사람의 정보를 보여줘".
  List<String> _labelsOf(
    Map<String, dynamic> ms,
    String rawKey,
    String labelKey,
  ) {
    final labels = (ms[labelKey] as List?) ?? [];
    if (labels.isNotEmpty) return labels.map((e) => '$e').toList();
    return ((ms[rawKey] as List?) ?? []).map((e) => '범#$e').toList();
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12.5, color: AppColors.textGray),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
        ),
      ],
    );
  }

  // ======================================================================
  //  승인 히스토리 (하단) — 관리자·마스터 전용
  //   · 승인요청일, 승인자 표시
  //   · 복원(다시 승인창으로) · 삭제(히스토리에서 제거) 소형 버튼
  //   · 행 선택 시 해당 내용(payload) 상세 표시
  // ======================================================================
  Widget _historySection() {
    final list = _histFilter.isEmpty
        ? _history
        : _history
              .where((it) => '${it['source'] ?? ''}' == _histFilter)
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Container(
          color: AppColors.textDark.withValues(alpha: 0.05),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.history, size: 18, color: AppColors.textDark),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '승인 히스토리',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.textDark.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${list.length}건',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              IconButton(
                tooltip: _showHistory ? '접기' : '펼치기',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _showHistory = !_showHistory),
                icon: Icon(
                  _showHistory ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        if (_showHistory) ...[
          _histFilterBar(),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: Text(
                '아직 처리한 승인 기록이 없습니다',
                style: TextStyle(fontSize: 12.5, color: AppColors.textGray),
              ),
            )
          else
            for (final it in list) _historyItem(it),
        ],
      ],
    );
  }

  Widget _histFilterBar() {
    Widget chip(String label, String key) {
      final on = _histFilter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () => setState(() => _histFilter = key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: on
                  ? AppColors.taegeukBlue.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: on
                    ? AppColors.taegeukBlue
                    : AppColors.textGray.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: on ? AppColors.taegeukBlue : AppColors.textGray,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          chip('전체', ''),
          chip('일반회원', 'regular'),
          chip('등록요청', 'request'),
          chip('연결', 'link'),
        ],
      ),
    );
  }

  Color _histStatusColor(String s) {
    switch (s) {
      case 'approved':
        return AppColors.scoutGreen;
      case 'held':
        return AppColors.tigerGold;
      case 'rejected':
        return AppColors.taegeukRed;
      case 'deleted':
        return AppColors.textGray;
      case 'restored':
        return AppColors.taegeukBlue;
      default:
        return AppColors.textDark;
    }
  }

  String _histStatusLabel(String s) {
    switch (s) {
      case 'approved':
        return '승인';
      case 'held':
        return '보류';
      case 'rejected':
        return '반려';
      case 'deleted':
        return '삭제';
      case 'restored':
        return '복원됨';
      default:
        return s;
    }
  }

  Widget _historyItem(Map<String, dynamic> it) {
    final id = '${it['id'] ?? ''}';
    final expanded = _expandedHistory == id;
    final status = '${it['status'] ?? 'approved'}';
    final sc = _histStatusColor(status);
    final name = '${it['name'] ?? ''}';
    final number = '${it['number'] ?? it['ident'] ?? ''}';
    final numLabel = Member.numLabelOf(number, '${it['corps'] ?? 'tsak'}');
    final title = '${it['title'] ?? ''}';
    final handledAt = '${it['handledAt'] ?? ''}'.trim();
    final handledBy = '${it['handledBy'] ?? ''}'.trim();
    // 승인 히스토리 — 멘토/페런츠 구분 + 승인요청시간·요청방법(요구).
    final source = '${it['source'] ?? ''}';
    final payload = (it['payload'] is Map)
        ? (it['payload'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final pm = (payload['member'] is Map)
        ? (payload['member'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final isLink = source == 'link';
    final kindLabel = '${pm['linkKind'] ?? ''}'.trim();
    // 승인요청시간: payload.requestedAt 우선, 없으면 최상위 requestedAt.
    final reqAt = (('${pm['requestedAt'] ?? ''}'.trim().isNotEmpty)
        ? '${pm['requestedAt']}'.trim()
        : '${it['requestedAt'] ?? ''}'.trim());
    final reqSrcLabel = isLink
        ? _reqSourceLabel(pm.isNotEmpty ? pm : it)
        : _reqSourceLabel(it);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sc.withValues(alpha: 0.28)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expandedHistory = expanded ? null : id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: sc.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _histStatusLabel(status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: sc,
                      ),
                    ),
                  ),
                  if (isLink && kindLabel.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _linkKindColor(pm).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        kindLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: _linkKindColor(pm),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$title  $name${numLabel.isNotEmpty ? ' $numLabel' : ''}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.textGray,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                runSpacing: 3,
                children: [
                  if (reqAt.isNotEmpty) _meta(Icons.event_note, '승인요청 $reqAt'),
                  if (isLink) _meta(Icons.input, '승인요청방법: $reqSrcLabel'),
                  if (handledAt.isNotEmpty)
                    _meta(Icons.check_circle_outline, '처리 $handledAt'),
                  if (handledBy.isNotEmpty)
                    _meta(Icons.person, '승인자 $handledBy'),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.textDark.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _historyDetail(it),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.taegeukBlue,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                    ),
                    onPressed: _busy ? null : () => _restoreHistory(it),
                    icon: const Icon(Icons.restore, size: 14),
                    label: const Text('복원', style: TextStyle(fontSize: 11.5)),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.taegeukRed,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                    ),
                    onPressed: _busy ? null : () => _deleteHistory(it),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('삭제', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyDetail(Map<String, dynamic> it) {
    final payload = (it['payload'] is Map)
        ? (it['payload'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final source = '${it['source'] ?? ''}';
    final rows = <Widget>[];
    void kv(String k, String v) {
      if (v.trim().isEmpty) return;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 74,
                child: Text(
                  k,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGray,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  v,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    kv(
      '구분',
      source == 'regular'
          ? '일반회원'
          : source == 'request'
          ? '등록요청'
          : source == 'link'
          ? '멘토·페런츠 연결'
          : source,
    );
    kv('유형', '${it['title'] ?? ''}');
    kv('인가번호', '${it['number'] ?? it['ident'] ?? ''}');
    kv('요약', '${it['summary'] ?? ''}');
    kv('복원일', '${it['restoredAt'] ?? ''}');
    kv('복원자', '${it['restoredBy'] ?? ''}');

    // payload 안의 세부 항목 표시(멘토/페런츠, 연회비 연도 등).
    final m = payload['member'];
    final req = payload['request'];
    if (m is Map) {
      final ms = m.cast<String, dynamic>();
      kv(
        '소속',
        [
          '${ms['league'] ?? ''}',
          '${ms['unit'] ?? ''}',
        ].where((e) => e.trim().isNotEmpty).join(' · '),
      );
      kv('연락처', '${ms['phone'] ?? ''}');
      // 멘토/페런츠 구분 + 승인요청정보(요구).
      if (source == 'link') {
        final kind = '${ms['linkKind'] ?? ''}'.trim();
        kv('구분', kind.isNotEmpty ? kind : _linkKindLabel(ms));
        kv('승인요청시간', '${ms['requestedAt'] ?? it['requestedAt'] ?? ''}');
        kv(
          '승인요청방법',
          '${ms['reqSourceLabel'] ?? ''}'.trim().isNotEmpty
              ? '${ms['reqSourceLabel']}'
              : _reqSourceLabel(ms),
        );
      }
      final mentors = _labelsOf(ms, 'mentors', 'mentorLabels');
      final parents = _labelsOf(ms, 'parents', 'parentLabels');
      final mentees = _labelsOf(ms, 'mentees', 'menteeLabels');
      final children = _labelsOf(ms, 'children', 'childLabels');
      // 멘토·멘티·페런츠·자녀대원 **모든 사람의 정보**(이름·소속·전화)를 노출.
      kv('멘토', mentors.join('\n'));
      kv('멘티대원', mentees.join('\n'));
      kv('페런츠', parents.join('\n'));
      kv('자녀대원', children.join('\n'));
      kv('메모', '${ms['note'] ?? ''}');
    }
    if (req is Map) {
      final rs = req.cast<String, dynamic>();
      kv('연도', '${rs['year'] ?? ''}');
      kv('납부일', '${rs['date'] ?? ''}');
      kv('행사', '${rs['event'] ?? ''}');
      kv('비고', '${rs['note'] ?? ''}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows.isEmpty
          ? const [
              Text(
                '세부 정보가 없습니다',
                style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
              ),
            ]
          : rows,
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
      child: Column(
        children: [
          Icon(
            Icons.task_alt,
            size: 48,
            color: AppColors.scoutGreen.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          const Text(
            '승인 대기 중인 항목이 없습니다',
            style: TextStyle(color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _errorBox() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.taegeukRed,
          ),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _refresh, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
