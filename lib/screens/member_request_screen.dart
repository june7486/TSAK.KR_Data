import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/member_registration_request_section.dart' show MemberRequestLabels;

/// 통합 승인 관리 — (관리자·마스터 전용)
///
/// 개인 프로필에서 올라온 모든 승인요청을 한 화면에서 처리한다.
///   · 비인가회원 등록
///   · 행사 참가자 등록
///   · 연회비 납부 등록
///   · 평생회원 납부 등록
///   · (향후 새 항목이 추가되어도 서버가 큐로 내려주면 자동 노출)
///
/// 서버 `/api/approval/overview` 가 큐(dict) 목록을 내려주고,
/// 각 큐는 kind='member'(일반회원 승인) | 'request'(등록요청) 로 처리 방식이 나뉜다.
class MemberRequestScreen extends StatefulWidget {
  const MemberRequestScreen({super.key});

  @override
  State<MemberRequestScreen> createState() => _MemberRequestScreenState();
}

class _MemberRequestScreenState extends State<MemberRequestScreen> {
  List<Map<String, dynamic>> _queues = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  /// 큐 key → 선택된 항목 id 집합
  final Map<String, Set<String>> _selected = {};

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
      if (!mounted) return;
      setState(() {
        _queues = list;
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

  int get _total =>
      _queues.fold<int>(0, (p, q) => p + ((q['count'] as num?)?.toInt() ?? 0));

  Set<String> _selOf(String key) => _selected.putIfAbsent(key, () => <String>{});

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
  Future<void> _act(String kind, String action, List<String> ids,
      String identFallback) async {
    if (ids.isEmpty) {
      _snack('대상을 선택하세요');
      return;
    }
    final state = context.read<AppState>();
    setState(() => _busy = true);
    var done = 0;
    if (kind == 'member') {
      done = await state.setApproval(action, ids);
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
    if (done == 0 && kind == 'request' && ids.length == 1) {
      _snack('$label 처리 결과를 확인하세요');
    } else {
      _snack('$label 처리: $done/${ids.length}건');
    }
    await _refresh();
    // 승인 후 명단/배지 갱신
    if (mounted) context.read<AppState>().refresh();
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
          title: const Text('승인 관리'),
        ),
        body: const Center(child: Text('관리자 권한이 필요합니다')),
      );
    }
    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('승인 관리 (통합)'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const AppHomeEmblem(size: 24),
        ],
      ),
      body: Column(
        children: [
          _summary(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _errorBox()
                    : _queues.isEmpty
                        ? _empty()
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 90),
                              children: [
                                for (final q in _queues) _queueSection(q),
                              ],
                            ),
                          ),
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
            child: Text('승인 대기 (전체 항목)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: (_total == 0 ? AppColors.scoutGreen : AppColors.tigerGold)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$_total건',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: _total == 0
                        ? AppColors.scoutGreen
                        : AppColors.tigerGold)),
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
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w900)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: _queueColor(key).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${items.length}건',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: _queueColor(key))),
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
            child: Text('대기 중인 항목이 없습니다',
                style: TextStyle(fontSize: 12, color: AppColors.textGray)),
          ),
      ],
    );
  }

  IconData _queueIcon(String key) {
    if (key == 'regular') return Icons.person_add;
    if (key.contains('lifetime')) return Icons.star;
    if (key.contains('fee')) return Icons.card_membership;
    if (key.contains('event')) return Icons.event_available;
    return Icons.rule;
  }

  Color _queueColor(String key) {
    if (key == 'regular') return AppColors.purple;
    if (key.contains('lifetime')) return AppColors.lifetimeGold;
    if (key.contains('fee')) return AppColors.scoutGreen;
    if (key.contains('event')) return AppColors.taegeukBlue;
    return AppColors.textGray;
  }

  String _idOf(Map<String, dynamic> it) {
    final id = '${it['id'] ?? ''}'.trim();
    if (id.isNotEmpty) return id;
    return '${it['number'] ?? it['ident'] ?? ''}';
  }

  Widget _bulkBar(String key, String kind, List<Map<String, dynamic>> items,
      Set<String> sel) {
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
                size: 18),
            label: Text('전체 선택 (${sel.length}/${ids.length})',
                style: const TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          if (kind == 'member') ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.scoutGreen,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _busy || sel.isEmpty
                  ? null
                  : () => _act(kind, 'approve', sel.toList(), ''),
              icon: const Icon(Icons.check, size: 15),
              label: Text('선택 승인 (${sel.length})',
                  style: const TextStyle(fontSize: 12)),
            ),
          ] else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.scoutGreen,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _busy || sel.isEmpty
                  ? null
                  : () => _act(kind, 'approve', sel.toList(), ''),
              icon: const Icon(Icons.check, size: 15),
              label: Text('선택 승인 (${sel.length})',
                  style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _itemCard(String key, String kind, Map<String, dynamic> m, bool sel) {
    final id = _idOf(m);
    final color = _queueColor(key);
    final name = '${m['name'] ?? '(이름없음)'}';
    final number = '${m['number'] ?? m['ident'] ?? ''}';
    final phone = '${m['phone'] ?? m['loginId'] ?? ''}';
    final type = '${m['type'] ?? ''}';
    final year = '${m['year'] ?? ''}'.trim();
    final date = '${m['date'] ?? ''}'.trim();
    final event = '${m['event'] ?? ''}'.trim();
    final note = '${m['note'] ?? ''}'.trim();
    final created = '${m['created'] ?? ''}';
    final by = (m['by'] is Map) ? _byLabel(m['by']) : '';

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
        onTap: () => _toggle(key, id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    sel ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: sel ? AppColors.scoutGreen : AppColors.textGray,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$name${number.isNotEmpty ? '  #$number' : ''}',
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (kind == 'request' && type.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(MemberRequestLabels.icon(type),
                              size: 12, color: color),
                          const SizedBox(width: 4),
                          Text(MemberRequestLabels.label(type),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: color)),
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
                    if (created.isNotEmpty) _meta(Icons.schedule, '가입 $created'),
                  ],
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
                    if (created.isNotEmpty) _meta(Icons.schedule, '요청 $created'),
                    if (by.isNotEmpty) _meta(Icons.person, '$by 요청'),
                  ],
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sticky_note_2_outlined,
                          size: 13, color: AppColors.textGray),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(note,
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.textDark)),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _buttons(kind, id),
              ),
            ],
          ),
        ),
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
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
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

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12.5, color: AppColors.textGray),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textGray)),
      ],
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt,
              size: 48, color: AppColors.scoutGreen.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text('승인 대기 중인 항목이 없습니다',
              style: TextStyle(color: AppColors.textGray)),
        ],
      ),
    );
  }

  Widget _errorBox() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 48, color: AppColors.taegeukRed),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _refresh, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
