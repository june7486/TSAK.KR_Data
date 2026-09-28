import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';

/// 멘토·페런츠(보호자) 연결 승인 관리 — (관리자·마스터 전용)
///
/// 회원이 멘토/페런츠를 지정하면 관리자·마스터의 승인을 받도록 한다.
/// 승인 여부가 로그인/권한을 제한하지는 않고, 연결의 정합성 확인·알림용이다.
///
/// 상태:
///   · pending  — 승인 요청
///   · held     — 보류
///   · approved — 승인됨
class LinkApprovalScreen extends StatefulWidget {
  const LinkApprovalScreen({super.key});

  @override
  State<LinkApprovalScreen> createState() => _LinkApprovalScreenState();
}

class _LinkApprovalScreenState extends State<LinkApprovalScreen> {
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  final Set<String> _selected = <String>{};

  NasApi get _nas => context.read<NasApi>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _nas.linkPending();
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

  Future<void> _act(String action, List<String> idents, {String note = ''}) async {
    if (idents.isEmpty) {
      _snack('대상을 선택하세요');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await _nas.linkSet(action: action, idents: idents, note: note);
      if (!mounted) return;
      if (r['ok'] == true) {
        _snack('처리했습니다 (${r['done'] ?? 0}건)');
        await _refresh();
      } else {
        _snack('처리 실패');
      }
    } catch (e) {
      if (mounted) _snack('오류: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveWithNote(Map<String, dynamic> m) async {
    final ctrl = TextEditingController(text: '${m['note'] ?? ''}');
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('연결 승인 메모 (선택)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
              hintText: '예) 405단 담당 확인 완료', isDense: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('승인')),
        ],
      ),
    );
    if (note == null) return;
    await _act('approve', ['${m['id']}'], note: note);
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

  String _nameOf(String number) {
    final state = context.read<AppState>();
    final m = state.byNumber(number);
    if (m != null && m.name.isNotEmpty) return '${m.name} (#$number)';
    return '#$number';
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
        appBar: AppBar(
          leading: const AppBackButton(label: '뒤로'),
          leadingWidth: 84,
          title: const Text('멘토·페런츠 연결 승인'),
        ),
        body: const Center(child: Text('관리자 권한이 필요합니다')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('멘토·페런츠 연결 승인'),
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
          if (_pending.isNotEmpty) _bulkBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _errorBox()
                    : _pending.isEmpty
                        ? _empty()
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: _pending.length,
                            itemBuilder: (_, i) => _card(_pending[i]),
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
          const Icon(Icons.family_restroom, size: 20, color: AppColors.purple),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('연결 승인 대기',
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

  Widget _bulkBar() {
    return Container(
      color: AppColors.purple.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => setState(() {
              if (_selected.length == _pending.length) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(_pending.map((e) => '${e['id']}'));
              }
            }),
            icon: Icon(
              _selected.length == _pending.length
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              size: 18,
            ),
            label: Text('전체 선택 (${_selected.length}/${_pending.length})',
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
    final mentors = ((m['mentors'] as List?) ?? []).map((e) => '$e').toList();
    final parents = ((m['parents'] as List?) ?? []).map((e) => '$e').toList();
    final note = '${m['note'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: sel
              ? AppColors.scoutGreen
              : AppColors.purple.withValues(alpha: 0.15),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.tigerGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('승인대기',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.tigerGold)),
                  ),
                ],
              ),
              if ('${m['league'] ?? ''}'.isNotEmpty ||
                  '${m['unit'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    if ('${m['league'] ?? ''}'.isNotEmpty) '${m['league']}',
                    if ('${m['unit'] ?? ''}'.isNotEmpty) '${m['unit']}',
                  ].join(' · '),
                  style:
                      const TextStyle(fontSize: 11.5, color: AppColors.textGray),
                ),
              ],
              const SizedBox(height: 8),
              if (mentors.isNotEmpty) _linkRow('멘토', mentors, AppColors.purple),
              if (parents.isNotEmpty)
                _linkRow('페런츠', parents, AppColors.taegeukBlue),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
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
                    onPressed: _busy ? null : () => _approveWithNote(m),
                    icon: const Icon(Icons.check, size: 15),
                    label: const Text('승인'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.tigerGold,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _busy ? null : () => _act('hold', [id]),
                    icon: const Icon(Icons.pause, size: 15),
                    label: const Text('보류'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _busy ? null : () => _act('pending', [id]),
                    icon: const Icon(Icons.hourglass_empty, size: 15),
                    label: const Text('대기 유지'),
                  ),
                ],
              ),
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
            width: 48,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textGray)),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final c in codes)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _nameOf(c),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline,
              size: 48, color: AppColors.scoutGreen.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text('승인 대기 중인 멘토·페런츠 연결이 없습니다',
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
