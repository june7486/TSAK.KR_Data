/// 행사 재무 탭 — 참가비 / 후원·기타수입 / 행사비지출 공용 목록.
///
/// ## 요구사항
/// "행사관리에서, 후원, 수품, 지출 등의 항목에 자료 추가할 수 있도록 해주고,
///  출력시 포함여부를 선택할 수 있도록 해줘"
///
/// ① **자료 추가** — 행마다 자료(영수증·입금표·견적서·사진 등 모든 포맷)를
///    붙이고/보고/지운다. 저장 키는 재무관리 원장과 같은 `ev_<행id>` 라서
///    행사관리에서 올린 자료가 재무관리 화면에서도 그대로 보인다.
/// ② **출력 포함여부** — '선택' 모드에서 체크한 행만 인쇄/저장한다.
///    기본은 전체 포함이고, 합산(건수·금액)도 선택된 행 기준으로 다시 계산한다.
library;

import 'package:flutter/material.dart';

import '../services/event_finance_picks.dart';
import '../services/event_settlement.dart';
import '../theme/app_theme.dart';
import '../widgets/finance_attach_panel.dart';

class EventFinanceTab extends StatefulWidget {
  const EventFinanceTab({
    super.key,
    required this.kind,
    required this.rows,
    required this.color,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onOutput,
    required this.onReload,
    this.header,
    this.won,
  });

  final FinanceKind kind;
  final List<Map<String, dynamic>> rows;
  final Color color;

  final VoidCallback onAdd;
  final void Function(Map<String, dynamic> row) onEdit;
  final Future<void> Function(Map<String, dynamic> row) onDelete;

  /// 선택된(포함) 행만 넘겨준다. 빈 목록이면 출력 버튼 비활성.
  final void Function(List<Map<String, dynamic>> included) onOutput;

  /// 자료 첨부 후 목록 갱신(자료 건수 배지).
  final Future<void> Function() onReload;

  /// 참가비 탭 상단 납부계좌 안내 등.
  final Widget? header;

  /// 금액 표기(콤마+원). 미지정 시 내부 기본 포맷.
  final String Function(int)? won;

  @override
  State<EventFinanceTab> createState() => _EventFinanceTabState();
}

class _EventFinanceTabState extends State<EventFinanceTab> {
  final FinancePickSet _picks = FinancePickSet();
  bool _selectMode = false;

  String _won(int v) => widget.won?.call(v) ?? '${EventSettlement.comma(v)}원';

  List<Map<String, dynamic>> get _included => _picks.filter(widget.rows);

  int _sumOf(List<Map<String, dynamic>> rows) =>
      rows.fold<int>(0, (s, r) => s + ((r['amount'] as num?)?.toInt() ?? 0));

  @override
  void didUpdateWidget(covariant EventFinanceTab old) {
    super.didUpdateWidget(old);
    // 행이 추가/삭제되면 사라진 id 를 정리(선택 상태가 어긋나지 않게).
    if (old.rows.length != widget.rows.length) {
      _picks.prune(FinancePickSet.idsOf(widget.rows));
    }
  }

  // ------------------------------------------------------------ 자료(첨부)
  String _txidOf(Map<String, dynamic> r) {
    final t = '${r['txid'] ?? ''}'.trim();
    if (t.isNotEmpty) return t;
    final id = '${r['id'] ?? ''}'.trim();
    return id.isEmpty ? '' : 'ev_$id';
  }

  Future<void> _openAttach(Map<String, dynamic> r) async {
    final txid = _txidOf(r);
    if (txid.isEmpty) {
      _snack('먼저 저장한 뒤 자료를 올릴 수 있습니다');
      return;
    }
    final amt = (r['amount'] as num?)?.toInt() ?? 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r['name'] ?? '내역'} · ${_won(amt)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${r['date'] ?? ''}'
                  '${'${r['category'] ?? ''}'.isNotEmpty ? ' · ${r['category']}' : ''}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGray,
                  ),
                ),
                const SizedBox(height: 10),
                // 재무관리 원장과 같은 패널·같은 저장키를 쓴다.
                FinanceAttachPanel(txid: txid, title: '자료'),
                const SizedBox(height: 8),
                const Text(
                  '영수증·입금표·견적서·사진 등 모든 포맷을 올릴 수 있습니다. '
                  '여기 올린 자료는 재무관리 화면에서도 그대로 보입니다.',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await widget.onReload();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final color = widget.color;
    final title = widget.kind.title;
    final included = _included;
    final total = _sumOf(included);
    final allTotal = _sumOf(rows);
    final attachCount = rows.fold<int>(
      0,
      (s, r) => s + ((r['attach'] as num?)?.toInt() ?? 0),
    );

    return Column(
      children: [
        if (widget.header != null) widget.header!,
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: widget.onAdd,
                  icon: const Icon(Icons.add),
                  label: Text('$title 추가'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                // (요구) 출력 시 포함여부 — 포함된 행만 넘긴다.
                onPressed: included.isEmpty
                    ? null
                    : () => widget.onOutput(included),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: Text(
                  _picks.isFiltered ? '선택출력(${included.length})' : '출력',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        // 합산 헤더 — 선택 모드에서는 '선택 합계 / 전체'를 같이 보여준다.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.functions, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                _picks.isFiltered
                    ? '${included.length}/${rows.length}건'
                    : '${rows.length}건',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _picks.isFiltered
                      ? '${_won(total)}  (전체 ${_won(allTotal)})'
                      : _won(total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
              if (attachCount > 0)
                Row(
                  children: [
                    const Icon(
                      Icons.attach_file,
                      size: 13,
                      color: AppColors.taegeukBlue,
                    ),
                    Text(
                      '$attachCount',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.taegeukBlue,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // 선택 도구 — 포함여부를 여기서 한 번에 정한다.
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
          child: Row(
            children: [
              _miniToggle(
                label: _selectMode ? '선택 해제' : '출력 선택',
                icon: _selectMode ? Icons.done_all : Icons.checklist,
                active: _selectMode,
                onTap: () => setState(() => _selectMode = !_selectMode),
              ),
              if (_selectMode) ...[
                const SizedBox(width: 6),
                _miniToggle(
                  label: '전체',
                  icon: Icons.select_all,
                  onTap: () => setState(_picks.includeAll),
                ),
                const SizedBox(width: 6),
                _miniToggle(
                  label: '전체해제',
                  icon: Icons.deselect,
                  onTap: () => setState(
                    () => _picks.excludeAll(FinancePickSet.idsOf(rows)),
                  ),
                ),
              ],
              const Spacer(),
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.sync,
                      size: 12,
                      color: AppColors.scoutGreen,
                    ),
                    SizedBox(width: 3),
                    Text(
                      '재무관리 연동',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_selectMode && _picks.isFiltered)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 12,
                  color: AppColors.tigerGold,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${_picks.excludedCount}건 제외됨 — 출력·합산에서 빠집니다',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text(
                    '내역이 없습니다',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _rowCard(rows[i], i + 1),
                ),
        ),
      ],
    );
  }

  Widget _miniToggle({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final c = active ? widget.color : AppColors.textGray;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: active ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: active ? 0.55 : 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowCard(Map<String, dynamic> r, int no) {
    final amt = (r['amount'] as num?)?.toInt() ?? 0;
    final id = FinancePickSet.rowId(r);
    final on = _picks.contains(id);
    final attach = (r['attach'] as num?)?.toInt() ?? 0;
    final account = '${r['account'] ?? ''}'.trim();
    final color = widget.color;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 10, right: 2),
        leading: _selectMode
            ? IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  on ? Icons.check_box : Icons.check_box_outline_blank,
                  color: on ? color : AppColors.textGray,
                ),
                onPressed: () => setState(() => _picks.toggle(id)),
              )
            : Icon(
                widget.kind == FinanceKind.expense
                    ? Icons.payments
                    : Icons.volunteer_activism,
                color: color,
              ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${r['name'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  // 제외된 행은 흐리게 — 한눈에 '빠진 항목'을 알 수 있게.
                  color: on ? AppColors.textDark : AppColors.textGray,
                  decoration: on ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
            if (attach > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: InkWell(
                  onTap: () => _openAttach(r),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.taegeukBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.attach_file,
                          size: 11,
                          color: AppColors.taegeukBlue,
                        ),
                        Text(
                          '$attach',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.taegeukBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${r['date'] ?? ''}'
          '${'${r['category'] ?? ''}'.isNotEmpty ? ' · ${r['category']}' : ''}'
          '${account.isNotEmpty ? ' · $account' : ''}'
          '${'${r['memo'] ?? ''}'.isNotEmpty ? ' · ${r['memo']}' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _won(amt),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: on ? AppColors.textDark : AppColors.textGray,
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) async {
                switch (v) {
                  case 'edit':
                    widget.onEdit(r);
                  case 'attach':
                    await _openAttach(r);
                  case 'del':
                    final ok = await _confirmDelete(r);
                    if (ok) await widget.onDelete(r);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('수정')),
                PopupMenuItem(
                  value: 'attach',
                  child: Text(
                    attach > 0 ? '자료 보기/추가 ($attach)' : '자료 추가',
                  ),
                ),
                const PopupMenuItem(value: 'del', child: Text('삭제')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(Map<String, dynamic> r) async {
    final n = (r['attach'] as num?)?.toInt() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('내역 삭제'),
        content: Text(
          "'${r['name'] ?? ''}' 을(를) 삭제할까요?"
          '${n > 0 ? '\n\n올린 자료 $n건도 함께 삭제됩니다.' : ''}',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
