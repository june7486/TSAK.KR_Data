import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';

/// 회원 등록요청 승인 관리 — (관리자·마스터 전용)
///
/// 회원이 개인 프로필에서 '등록요청' 한 항목(평생회원 / 연회비 납부 / 자격 지정)을
/// 관리자·마스터가 승인 또는 반려한다.
///
///   · type    — lifetime(평생회원) | fee(연회비) | qualification(자격 지정)
///   · status  — pending(대기) | approved(승인) | rejected(반려)
///
/// 승인 시 서버가 실제 회원 데이터에 반영한다(lifetimeMember=true, feeYears[y]=true,
/// qualificationStatus='approved').
class MemberRequestScreen extends StatefulWidget {
  const MemberRequestScreen({super.key});

  @override
  State<MemberRequestScreen> createState() => _MemberRequestScreenState();
}

class _MemberRequestScreenState extends State<MemberRequestScreen> {
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  /// 유형 필터: '' | lifetime | fee | qualification
  String _filter = '';
  final Set<String> _selected = <String>{};

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
      final list = await state.fetchMemberRequests();
      if (!mounted) return;
      setState(() {
        _pending = list;
        _selected.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered => _filter.isEmpty
      ? _pending
      : _pending.where((e) => '${e['type']}' == _filter).toList();

  Future<void> _act(String action, List<String> ids) async {
    if (ids.isEmpty) {
      _snack('대상을 선택하세요');
      return;
    }
    final state = context.read<AppState>();
    setState(() => _busy = true);
    var done = 0;
    for (final id in ids) {
      final ok = await state.setMemberRequest(id, action);
      if (ok) done++;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _snack('${action == 'approve' ? '승인' : '반려'} 처리: $done/${ids.length}건');
    await _refresh();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  static String _typeLabel(String t) => switch (t) {
        'lifetime' => '평생회원 등록',
        'fee' => '연회비 납부',
        'qualification' => '자격 지정',
        _ => t,
      };

  static IconData _typeIcon(String t) => switch (t) {
        'lifetime' => Icons.star,
        'fee' => Icons.card_membership,
        'qualification' => Icons.workspace_premium,
        _ => Icons.info,
      };

  static Color _typeColor(String t) => switch (t) {
        'lifetime' => AppColors.lifetimeGold,
        'fee' => AppColors.scoutGreen,
        'qualification' => AppColors.purple,
        _ => AppColors.textGray,
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!(state.isApp || state.isMaster)) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(label: '뒤로'),
          leadingWidth: 84,
          title: const Text('등록요청 승인'),
        ),
        body: const Center(child: Text('관리자 권한이 필요합니다')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('등록요청 승인 (평생·연회비·자격)'),
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
          _filterBar(),
          if (_filtered.isNotEmpty) _bulkBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _errorBox()
                    : _filtered.isEmpty
                        ? _empty()
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _card(_filtered[i]),
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
          const Icon(Icons.app_registration, size: 20, color: AppColors.purple),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('등록요청 승인 대기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: (_pending.isEmpty
                      ? AppColors.scoutGreen
                      : AppColors.tigerGold)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${_pending.length}건',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: _pending.isEmpty
                        ? AppColors.scoutGreen
                        : AppColors.tigerGold)),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    const items = <(String, String)>[
      ('', '전체'),
      ('lifetime', '평생회원'),
      ('fee', '연회비'),
      ('qualification', '자격 지정'),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final it in items) ...[
              ChoiceChip(
                selected: _filter == it.$1,
                onSelected: (_) => setState(() {
                  _filter = it.$1;
                  _selected.clear();
                }),
                label: Text(it.$2),
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _filter == it.$1 ? Colors.white : AppColors.textDark,
                ),
                selectedColor: AppColors.purple,
                backgroundColor: AppColors.purple.withValues(alpha: 0.08),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bulkBar() {
    final list = _filtered;
    return Container(
      color: AppColors.purple.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => setState(() {
              if (_selected.length == list.length) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(list.map((e) => '${e['id']}'));
              }
            }),
            icon: Icon(
              _selected.length == list.length
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              size: 18,
            ),
            label: Text('전체 선택 (${_selected.length}/${list.length})',
                style: const TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.scoutGreen,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _busy || _selected.isEmpty
                ? null
                : () => _act('approve', _selected.toList()),
            icon: const Icon(Icons.check, size: 16),
            label: Text('선택 승인 (${_selected.length})',
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> m) {
    final id = '${m['id']}';
    final sel = _selected.contains(id);
    final type = '${m['type'] ?? ''}';
    final color = _typeColor(type);
    final year = '${m['year'] ?? ''}'.trim();
    final date = '${m['date'] ?? ''}'.trim();
    final note = '${m['note'] ?? ''}'.trim();
    final by = (m['by'] is Map) ? '${(m['by'] as Map)['personal'] ?? ''}' : '';
    final created = '${m['created'] ?? ''}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
        onTap: () => _toggle(id),
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
                      '${m['name'] ?? '(이름없음)'}  #${m['number'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_typeIcon(type), size: 12, color: color),
                        const SizedBox(width: 4),
                        Text(_typeLabel(type),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: color)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  if (type == 'fee' && year.isNotEmpty)
                    _meta(Icons.event, '$year년 연회비'),
                  if (type == 'lifetime' && date.isNotEmpty)
                    _meta(Icons.event_available, '납부일자 $date'),
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
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.scoutGreen,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _busy ? null : () => _act('approve', [id]),
                    icon: const Icon(Icons.check, size: 15),
                    label: const Text('승인'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.taegeukRed,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _busy ? null : () => _act('reject', [id]),
                    icon: const Icon(Icons.close, size: 15),
                    label: const Text('반려'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _busy
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: const Text('회원 정보')),
                                  body: const Center(
                                    child: Text('상세 정보는 명단에서 확인하세요'),
                                  ),
                                ),
                              ),
                            ),
                    icon: const Icon(Icons.info_outline, size: 15),
                    label: const Text('정보'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
          const Text('승인 대기 중인 등록요청이 없습니다',
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
