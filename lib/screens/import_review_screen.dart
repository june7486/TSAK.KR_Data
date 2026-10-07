import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';

/// 자료 가져오기(AI 인식) — 등록/업데이트 병합 검토 화면.
///
/// 요구사항:
///  · 원본 데이터에 내용이 있으면 확인 후 업데이트하거나 기존 데이터를 선택.
///  · 모든 자료를 검색하고, 업로드 전 "등록하시겠습니까? / 업데이트하시겠습니까?" 확인.
///  · 중복은 이전자료 vs 신규내용을 항목별로 비교하여 선택.
///  · "일괄선택" + "같은 규칙으로 모두 적용".
///  · 실수 방지 — 마스터에게 알림 + 누가/무엇을/언제 로그 + 마스터 복원.
class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({
    super.key,
    required this.recognized,
    required this.sourceName,
  });

  final List<Member> recognized;
  final String sourceName;

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

/// 비교 대상 필드 (key, 라벨).
const List<List<String>> _kFields = [
  ['name', '성명'],
  ['league', '연맹'],
  ['unit', '단위대'],
  ['address', '주소'],
  ['phone', '핸드폰'],
  ['tel', '연락처'],
  ['email', '이메일'],
  ['birthday', '생일'],
  ['atasNo', 'ATAS 인가번호'],
  ['date', '인가일'],
  ['activity', '활동'],
  ['position', '직위'],
  ['memo', '메모/비고'],
];

class _Diff {
  final String field;
  final String label;
  final String oldV;
  final String newV;
  bool selected = true;
  _Diff(this.field, this.label, this.oldV, this.newV);
}

class _RevItem {
  _RevItem({
    required this.row,
    required this.prev,
  }) : action = prev == null ? 'add' : 'update',
       selected = true {
    final p = prev;
    if (p != null) {
      _diffs = _computeDiffs(p, row);
    }
  }

  final Map<String, dynamic> row;
  final Member? prev; // 중복(기존) 회원
  String action; // 'add' | 'update' | 'skip'
  bool selected; // 일괄선택용 체크
  List<_Diff> _diffs = [];

  bool get isNew => prev == null;
  List<_Diff> get diffs => _diffs;

  /// 선택된 항목만 반영하도록 'fields' 문자열 생성(없으면 전체).
  String selectedFields() =>
      _diffs.where((d) => d.selected).map((d) => d.field).join(',');

  static List<_Diff> _computeDiffs(Member prev, Map<String, dynamic> row) {
    final out = <_Diff>[];
    for (final f in _kFields) {
      final key = f[0];
      final old = _prevVal(prev, key);
      final nw = '${row[key] ?? ''}'.trim();
      if (nw.isNotEmpty && nw != old) {
        out.add(_Diff(key, f[1], old, nw));
      }
    }
    return out;
  }

  static String _prevVal(Member m, String key) {
    switch (key) {
      case 'name':
        return m.name;
      case 'league':
        return m.league;
      case 'unit':
        return m.unit;
      case 'address':
        return m.address;
      case 'phone':
        return m.phone;
      case 'tel':
        return m.tel;
      case 'email':
        return m.email;
      case 'birthday':
        return m.birthday;
      case 'atasNo':
        return m.atasNo;
      case 'date':
        return m.date;
      case 'activity':
        return m.activity;
      case 'position':
        return m.position;
      case 'memo':
        return m.memo;
    }
    return '';
  }
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  late List<_RevItem> _items;
  bool _busy = false;

  // 일괄 규칙
  String _bulkNewRule = 'add'; // add | skip
  String _bulkDupRule = 'update'; // update | add | skip

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _items = widget.recognized.map((m) {
      final row = _memberToRow(m);
      Member? prev;
      final no = m.number.trim();
      if (no.isNotEmpty) prev = state.byNumber(no);
      if (prev != null && prev.name.trim().isNotEmpty &&
          m.name.trim().isNotEmpty &&
          prev.name.trim() != m.name.trim()) {
        // 이름이 다르면 동일 번호라도 '신규'로 보지 않도록 중복 유지(수동 판단).
      }
      return _RevItem(row: row, prev: prev);
    }).toList();
  }

  Map<String, dynamic> _memberToRow(Member m) => {
    'number': m.number.trim(),
    'name': m.name.trim(),
    'league': m.league.trim(),
    'unit': m.unit.trim(),
    'address': m.address.trim(),
    'phone': m.phone.trim(),
    'tel': m.tel.trim(),
    'email': m.email.trim(),
    'birthday': m.birthday.trim(),
    'atasNo': m.atasNo.trim(),
    'date': m.date.trim(),
    'activity': m.activity.trim(),
    'position': m.position.trim(),
    'memo': m.memo.trim(),
  };

  int get _newCount => _items.where((e) => e.isNew).length;
  int get _dupCount => _items.where((e) => !e.isNew).length;

  int get _addCount =>
      _items.where((e) => e.action == 'add').length;
  int get _updateCount =>
      _items.where((e) => e.action == 'update').length;
  int get _skipCount =>
      _items.where((e) => e.action == 'skip').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TsakAppBar(
        leading: AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: Text('자료 병합 검토'),
        actions: [AppHomeEmblem(size: 26)],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _summaryBar(),
              _bulkBar(),
              const Divider(height: 1),
              Expanded(child: _list()),
              _saveBar(),
            ],
          ),
          BusyOverlay(
            visible: _busy,
            title: '자료를 반영하는 중입니다',
            lines: const [
              '기존 자료와 비교·검색하고 있습니다...',
              '선택한 항목을 반영하는 중...',
              '마스터에게 알림을 보내는 중...',
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: AppColors.purple.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '인식 ${_items.length}건 · ${widget.sourceName}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip('신규 $_newCount', AppColors.scoutGreen),
              _chip('기존(중복) $_dupCount', AppColors.tigerGold),
              _chip('등록 예정 $_addCount', AppColors.taegeukBlue),
              _chip('업데이트 예정 $_updateCount', AppColors.purple),
              _chip('건너뜀 $_skipCount', AppColors.textGray),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );

  Widget _bulkBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: _allSelected,
                onChanged: (v) => setState(() {
                  final sel = v == true;
                  for (final e in _items) {
                    e.selected = sel;
                  }
                }),
              ),
              const Text(
                '일괄선택',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${_items.where((e) => e.selected).length}건 선택',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
              ),
            ],
          ),
          Row(
            children: [
              const Text('신규:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              _miniDrop(
                value: _bulkNewRule,
                items: const {'add': '등록', 'skip': '건너뜀'},
                onChanged: (v) => setState(() => _bulkNewRule = v),
              ),
              const SizedBox(width: 8),
              const Text('중복:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              _miniDrop(
                value: _bulkDupRule,
                items: const {'update': '업데이트', 'add': '신규등록', 'skip': '건너뜀'},
                onChanged: (v) => setState(() => _bulkDupRule = v),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _applyBulkRule,
                icon: const Icon(Icons.done_all, size: 16),
                label: const Text(
                  '같은 규칙으로 모두 적용',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _allSelected => _items.isNotEmpty && _items.every((e) => e.selected);

  Widget _miniDrop({
    required String value,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButton<String>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: const TextStyle(fontSize: 12, color: AppColors.textGray),
      items: items.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  /// "같은 규칙으로 모두 적용" — 선택된 항목에 일괄 규칙 적용.
  void _applyBulkRule() {
    var n = 0;
    for (final e in _items) {
      if (!e.selected) continue;
      e.action = e.isNew ? _bulkNewRule : _bulkDupRule;
      if (e.isNew && _bulkNewRule == 'add') {
        // 신규 등록
      }
      n++;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('선택 $n건에 규칙을 적용했습니다')),
    );
  }

  Widget _list() {
    if (_items.isEmpty) {
      return const Center(child: Text('인식된 항목이 없습니다'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _items.length,
      itemBuilder: (c, i) => _itemCard(i),
    );
  }

  Widget _itemCard(int i) {
    final it = _items[i];
    final m = it.row;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: it.selected,
                onChanged: (v) => setState(() => it.selected = v == true),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${m['number']} ${m['name']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _badge(
                          it.isNew ? '신규' : '중복',
                          it.isNew ? AppColors.scoutGreen : AppColors.tigerGold,
                        ),
                      ],
                    ),
                    if (it.isNew)
                      Text(
                        [m['league'], m['unit'], m['phone']]
                            .where((x) => '${x ?? ''}'.isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textGray,
                        ),
                      )
                    else
                      Text(
                        '기존: ${it.prev!.number} ${it.prev!.name}'
                        '${it.diffs.isEmpty ? ' · 변경 없음' : ' · 변경 ${it.diffs.length}항목'}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textGray,
                        ),
                      ),
                  ],
                ),
              ),
              _actionPicker(it),
            ],
          ),
          if (!it.isNew && it.action == 'update') _diffTable(it),
        ],
      ),
    );
  }

  Widget _actionPicker(_RevItem it) {
    return PopupMenuButton<String>(
      tooltip: '처리 선택',
      initialValue: it.action,
      onSelected: (v) => setState(() => it.action = v),
      itemBuilder: (c) => [
        if (it.isNew)
          const PopupMenuItem(value: 'add', child: Text('신규 등록')),
        if (!it.isNew) ...[
          const PopupMenuItem(value: 'update', child: Text('업데이트 (기존 갱신)')),
          const PopupMenuItem(value: 'add', child: Text('새 항목으로 등록')),
        ],
        const PopupMenuItem(value: 'skip', child: Text('건너뜀')),
      ],
      child: _badge(
        it.action == 'add'
            ? '등록'
            : it.action == 'update'
                ? '업데이트'
                : '건너뜀',
        it.action == 'add'
            ? AppColors.taegeukBlue
            : it.action == 'update'
                ? AppColors.purple
                : AppColors.textGray,
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  );

  Widget _diffTable(_RevItem it) {
    if (it.diffs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Text(
          '기존 자료와 동일합니다 (변경 항목 없음)',
          style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.tigerGold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.tigerGold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '이전자료 ↔ 신규내용 비교',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  for (final d in it.diffs) {
                    d.selected = true;
                  }
                }),
                child: const Text('모두', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () => setState(() {
                  for (final d in it.diffs) {
                    d.selected = false;
                  }
                }),
                child: const Text('없음', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          for (final d in it.diffs)
            InkWell(
              onTap: () => setState(() => d.selected = !d.selected),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Checkbox(
                      value: d.selected,
                      onChanged: (v) => setState(() => d.selected = v == true),
                      visualDensity: VisualDensity.compact,
                    ),
                    SizedBox(
                      width: 76,
                      child: Text(
                        d.label,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        d.oldV.isEmpty ? '(없음)' : d.oldV,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textGray,
                          decoration: TextDecoration.lineThrough,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.arrow_forward, size: 13),
                    ),
                    Expanded(
                      child: Text(
                        d.newV,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.taegeukBlue,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _saveBar() {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '등록 $_addCount건 · 업데이트 $_updateCount건 · 건너뜀 $_skipCount건',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.scoutGreen,
                ),
                onPressed: _busy ? null : _confirmApply,
                icon: const Icon(Icons.check),
                label: const Text('확인 후 반영'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmApply() async {
    final adds = _items.where((e) => e.action == 'add').toList();
    final ups = _items.where((e) => e.action == 'update').toList();
    final skips = _items.where((e) => e.action == 'skip').length;
    if (adds.isEmpty && ups.isEmpty) {
      _snack('반영할 항목이 없습니다');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('업로드 전 확인'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '선택한 자료를 NAS에 반영합니다.\n'
              '회원정보를 등록하시겠습니까? 혹은 업데이트하시겠습니까?',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text('· 신규 등록 : ${adds.length}건'),
            Text('· 기존 업데이트 : ${ups.length}건'),
            Text('· 건너뜀 : $skips건'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.tigerGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notifications_active,
                      size: 16, color: AppColors.tigerGold),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '업데이트 내역은 마스터에게 알림으로 전달되며,\n'
                      '누가·무엇을·언제 기록되고 마스터가 복원할 수 있습니다.',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('반영'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _apply();
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final nas = context.read<AppState>().nas;

    final rows = <Map<String, dynamic>>[];
    for (final it in _items) {
      if (it.action == 'skip') {
        rows.add({...it.row, 'action': 'skip'});
        continue;
      }
      final r = Map<String, dynamic>.from(it.row);
      r['action'] = it.action;
      if (it.action == 'update') {
        final f = it.selectedFields();
        if (f.isNotEmpty) r['fields'] = f;
      }
      rows.add(r);
    }

    Map<String, dynamic>? res;
    try {
      res = await nas.importApply(rows, source: widget.sourceName);
    } catch (e) {
      res = {'ok': false, 'error': '$e'};
    }

    if (res['ok'] == true) {
      await state.refreshFromNas();
      final added = (res['added'] as num?)?.toInt() ?? 0;
      final updated = (res['updated'] as num?)?.toInt() ?? 0;
      if (mounted) {
        setState(() => _busy = false);
        _doneDialog(added: added, updated: updated);
      }
      return;
    }

    // 서버 미연결(NAS 모드 아님) 폴백 — 신규 등록만 로컬 반영.
    var local = 0;
    try {
      for (final it in _items) {
        if (it.action != 'add') continue;
        var member = Member.fromMap(Map<String, dynamic>.from(it.row));
        if (member.number.trim().isEmpty ||
            state.byNumber(member.number) != null) {
          final next = await state.nextNumber();
          member = member.copyWith(number: '$next');
        }
        await state.save(member);
        local++;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _busy = false);
      if (local > 0) {
        _snack('서버 미연결 — 신규 $local건만 로컬 반영했습니다');
      } else {
        _snack('반영에 실패했습니다: ${res['error'] ?? '서버 오류'}');
      }
    }
  }

  void _doneDialog({required int added, required int updated}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.scoutGreen),
            SizedBox(width: 8),
            Text('반영 완료'),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('신규 등록 $added건 · 기존 업데이트 $updated건을 반영했습니다.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.taegeukBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notifications_active,
                      size: 16, color: AppColors.taegeukBlue),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '마스터에게 알림이 전송되었습니다.\n'
                      '업데이트 내역은 로그로 기록되며 마스터가 복원할 수 있습니다.',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
