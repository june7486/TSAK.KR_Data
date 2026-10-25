import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/finance_export.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/finance_attach_panel.dart';
import '../widgets/finance_export_sheet.dart';
import '../widgets/tsak_app_bar.dart';

/// 재무 원장 — 입금/지출 내역을 전체·연도별·월별·항목별로 리스트로 보여주고,
/// 각 항목을 선택/이동(분류변경)/삭제하고, 첨부파일을 관리하며,
/// 항목별로 출력(명단출력과 동일 원칙)할 수 있는 관리 화면.
class FinanceLedgerScreen extends StatefulWidget {
  const FinanceLedgerScreen({super.key});

  @override
  State<FinanceLedgerScreen> createState() => _FinanceLedgerScreenState();
}

class _FinanceLedgerScreenState extends State<FinanceLedgerScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _all = [];
  Map<String, dynamic> _byYear = {};
  Map<String, dynamic> _byMonth = {};
  Map<String, dynamic> _byCategory = {};

  String _typeFilter = '전체'; // 전체 | 입금 | 지출
  String _groupBy = '전체'; // 전체 | 연도별 | 월별 | 항목별
  String _groupKey = '전체'; // 선택된 그룹(전체면 없음)

  final Set<String> _sel = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  bool get _canEdit {
    final s = context.read<AppState>();
    return s.isMaster || s.can('finance');
  }

  bool get _canOutput {
    final s = context.read<AppState>();
    return s.isMaster || s.can('finOutput') || s.can('finance');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await context.read<AppState>().nas.fetchFinanceList();
    if (!mounted) return;
    if (r['ok'] == true) {
      _all = ((r['transactions'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      _byYear = ((r['byYear'] as Map?) ?? {}).cast<String, dynamic>();
      _byMonth = ((r['byMonth'] as Map?) ?? {}).cast<String, dynamic>();
      _byCategory = ((r['byCategory'] as Map?) ?? {}).cast<String, dynamic>();
    }
    setState(() => _loading = false);
  }

  List<String> _groupKeys() {
    if (_groupBy == '연도별') {
      final ks = _byYear.keys.toList()..sort((a, b) => b.compareTo(a));
      return ks;
    }
    if (_groupBy == '월별') {
      final ks = _byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
      return ks;
    }
    if (_groupBy == '항목별') {
      final ks = _byCategory.keys.toList()..sort((a, b) => a.compareTo(b));
      return ks;
    }
    return [];
  }

  bool _matchGroup(Map<String, dynamic> t) {
    if (_groupBy == '전체' || _groupKey == '전체') return true;
    final d = '${t['date'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '-');
    if (_groupBy == '연도별') {
      return d.length >= 4 && d.substring(0, 4) == _groupKey;
    }
    if (_groupBy == '월별') {
      final m = RegExp(r'(20\d{2})-(\d{2})').firstMatch(d);
      return m != null && '${m.group(1)}-${m.group(2)}' == _groupKey;
    }
    if (_groupBy == '항목별') {
      return '${t['category'] ?? '기타'}' == _groupKey;
    }
    return true;
  }

  List<Map<String, dynamic>> _filtered() {
    return _all.where((t) {
      final type = '${t['type'] ?? 'income'}';
      if (_typeFilter == '입금' && type == 'expense') return false;
      if (_typeFilter == '지출' && type != 'expense') return false;
      return _matchGroup(t);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered();
    int income = 0, expense = 0;
    for (final t in list) {
      final a = (t['amount'] as num?)?.toInt() ?? 0;
      if ('${t['type']}' == 'expense') {
        expense += a;
      } else {
        income += a;
      }
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        leadingWidth: 48,
        title: const Text('재무 원장'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          const AppHomeEmblem(size: 26),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _filterBar(),
                _summaryBar(list.length, income, expense),
                if (_sel.isNotEmpty) _selectionBar(),
                Expanded(child: _list(list)),
              ],
            ),
      floatingActionButton: _canOutput
          ? FloatingActionButton.extended(
              onPressed: () => _export(list),
              icon: const Icon(Icons.ios_share),
              label: const Text('출력'),
            )
          : null,
    );
  }

  Widget _filterBar() {
    final keys = _groupKeys();
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '구분',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(width: 8),
              _chip('전체', _typeFilter, (v) => setState(() => _typeFilter = v)),
              _chip('입금', _typeFilter, (v) => setState(() => _typeFilter = v)),
              _chip('지출', _typeFilter, (v) => setState(() => _typeFilter = v)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                '보기',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(width: 8),
              _chip('전체', _groupBy, (v) {
                setState(() {
                  _groupBy = v;
                  _groupKey = '전체';
                });
              }),
              _chip('연도별', _groupBy, (v) {
                setState(() {
                  _groupBy = v;
                  _groupKey = '전체';
                });
              }),
              _chip('월별', _groupBy, (v) {
                setState(() {
                  _groupBy = v;
                  _groupKey = '전체';
                });
              }),
              _chip('항목별', _groupBy, (v) {
                setState(() {
                  _groupBy = v;
                  _groupKey = '전체';
                });
              }),
            ],
          ),
          if (keys.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _groupChip('전체', '전체'),
                  for (final k in keys) _groupChip(k, k),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, String group, ValueChanged<String> onTap) {
    final sel = group == label;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: sel,
        visualDensity: VisualDensity.compact,
        selectedColor: AppColors.purple,
        labelStyle: TextStyle(color: sel ? Colors.white : AppColors.textDark),
        onSelected: (_) => onTap(label),
      ),
    );
  }

  Widget _groupChip(String key, String label) {
    final sel = _groupKey == key;
    final g = _byYear[key] ?? _byMonth[key] ?? _byCategory[key];
    int cnt = 0;
    if (g is Map) cnt = (g['count'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(
          cnt > 0 ? '$label ($cnt)' : label,
          style: TextStyle(
            fontSize: 11.5,
            color: sel ? Colors.white : AppColors.textDark,
          ),
        ),
        backgroundColor: sel
            ? AppColors.purple
            : AppColors.purple.withValues(alpha: 0.08),
        onPressed: () => setState(() => _groupKey = key),
      ),
    );
  }

  Widget _summaryBar(int count, int income, int expense) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          _sumChip('건수', '$count', AppColors.textDark),
          _sumChip('입금', _won(income), AppColors.scoutGreen),
          _sumChip('지출', _won(expense), AppColors.taegeukRed),
          _sumChip('잔액', _won(income - expense), AppColors.purple),
        ],
      ),
    );
  }

  Widget _sumChip(String k, String v, Color c) => Expanded(
    child: Column(
      children: [
        Text(
          k,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textGray),
        ),
        Text(
          v,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c),
        ),
      ],
    ),
  );

  Widget _selectionBar() {
    return Container(
      color: AppColors.purple.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text('${_sel.length}건 선택', style: const TextStyle(fontSize: 12.5)),
          const Spacer(),
          if (_canEdit)
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.taegeukRed,
              ),
              onPressed: _bulkDelete,
              icon: const Icon(Icons.delete_sweep, size: 16),
              label: const Text('선택 삭제'),
            ),
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => setState(_sel.clear),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('해제'),
          ),
        ],
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text(
          '해당 조건의 내역이 없습니다',
          style: TextStyle(color: AppColors.textGray),
        ),
      );
    }
    // 그룹핑 보기면 그룹 헤더를 사이에 넣어 리스트업.
    final children = <Widget>[];
    String? lastGroup;
    for (final t in list) {
      if (_groupBy != '전체') {
        final g = _groupLabel(t);
        if (g != lastGroup) {
          children.add(_groupHeader(g));
          lastGroup = g;
        }
      }
      children.add(_row(t));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
      children: children,
    );
  }

  String _groupLabel(Map<String, dynamic> t) {
    final d = '${t['date'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '-');
    if (_groupBy == '연도별') return d.length >= 4 ? d.substring(0, 4) : '미지정';
    if (_groupBy == '월별') {
      final m = RegExp(r'(20\d{2})-(\d{2})').firstMatch(d);
      return m != null ? '${m.group(1)}-${m.group(2)}' : '미지정';
    }
    if (_groupBy == '항목별') return '${t['category'] ?? '기타'}';
    return '전체';
  }

  Widget _groupHeader(String g) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
    child: Row(
      children: [
        const Icon(Icons.folder_outlined, size: 15, color: AppColors.purple),
        const SizedBox(width: 6),
        Text(
          g,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: AppColors.purple,
          ),
        ),
      ],
    ),
  );

  Widget _row(Map<String, dynamic> t) {
    final id = '${t['id'] ?? ''}';
    final isExp = '${t['type']}' == 'expense';
    final amount = (t['amount'] as num?)?.toInt() ?? 0;
    final attach = (t['attachCount'] as num?)?.toInt() ?? 0;
    final selected = _sel.contains(id);
    final canFinance = _canEdit;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(t),
        onLongPress: canFinance
            ? () => setState(() {
                if (selected) {
                  _sel.remove(id);
                } else {
                  _sel.add(id);
                }
              })
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (canFinance)
                Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                  color: AppColors.purple,
                ),
              if (canFinance) const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (isExp ? AppColors.taegeukRed : AppColors.scoutGreen)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isExp ? Icons.north_east : Icons.south_west,
                  size: 18,
                  color: isExp ? AppColors.taegeukRed : AppColors.scoutGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${t['name'] ?? t['payer'] ?? ''}'
                            '${(t['number'] ?? '').toString().isNotEmpty ? ' (범#${t['number']})' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '${isExp ? '-' : '+'}${_won(amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: isExp
                                ? AppColors.taegeukRed
                                : AppColors.scoutGreen,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          '${t['date'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textGray,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${t['category'] ?? '기타'}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.purple,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (attach > 0) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.attach_file,
                            size: 12,
                            color: AppColors.textGray,
                          ),
                          Text(
                            '$attach',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textGray,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if ((t['event'] ?? '').toString().isNotEmpty)
                          Flexible(
                            child: Text(
                              '${t['event']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textGray,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> t) async {
    final id = '${t['id'] ?? ''}';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: AppColors.purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${t['name'] ?? t['payer'] ?? '내역'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _kv('일자', '${t['date'] ?? ''}'),
            _kv('구분', '${t['type']}' == 'expense' ? '지출' : '입금'),
            _kv('금액', _won((t['amount'] as num?)?.toInt() ?? 0)),
            _kv('분류', '${t['category'] ?? '기타'}'),
            if ((t['number'] ?? '').toString().isNotEmpty)
              _kv('인가번호', '범#${t['number']}'),
            if ((t['event'] ?? '').toString().isNotEmpty)
              _kv('행사', '${t['event']}'),
            if ((t['memo'] ?? '').toString().isNotEmpty)
              _kv('메모', '${t['memo']}'),
            const SizedBox(height: 12),
            // 첨부파일 패널 (업로드·확인·다운로드·공유·이름변경·이동·삭제)
            FinanceAttachPanel(txid: id),
            const SizedBox(height: 14),
            Row(
              children: [
                if (_canOutput)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _export([t], single: true);
                      },
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('이 항목 출력'),
                    ),
                  ),
                if (_canOutput) const SizedBox(width: 8),
                if (_canEdit)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.taegeukRed,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _deleteTx(t);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('삭제'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            k,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textGray),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Future<void> _deleteTx(Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('내역 삭제'),
        content: Text(
          '이 내역을 삭제할까요? (첨부파일도 함께 삭제됩니다)',
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
    if (ok != true) return;
    final id = '${t['id'] ?? ''}';
    final atts = await context.read<AppState>().nas.fetchFinanceAttach(id);
    for (final f in atts) {
      await context.read<AppState>().nas.deleteFinanceAttach(
        id,
        '${f['name']}',
      );
    }
    // 서버 재무 목록에서 제거(전체 저장).
    final r = await context.read<AppState>().nas.fetchFinance();
    if (r['finance'] is Map) {
      final fin = (r['finance'] as Map).cast<String, dynamic>();
      final txs = ((fin['transactions'] as List?) ?? [])
          .where((e) => e is Map && '${e['id']}' != id)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      fin['transactions'] = txs;
      await context.read<AppState>().nas.saveFinance(fin);
    }
    await _load();
    _snack('내역을 삭제했습니다');
  }

  Future<void> _bulkDelete() async {
    final n = _sel.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('선택 내역 삭제'),
        content: Text('선택한 $n건을 삭제할까요?', style: const TextStyle(fontSize: 13)),
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
    if (ok != true) return;
    final r = await context.read<AppState>().nas.fetchFinance();
    if (r['finance'] is Map) {
      final fin = (r['finance'] as Map).cast<String, dynamic>();
      final txs = ((fin['transactions'] as List?) ?? [])
          .where((e) => e is Map && !_sel.contains('${e['id']}'))
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      fin['transactions'] = txs;
      await context.read<AppState>().nas.saveFinance(fin);
    }
    _sel.clear();
    await _load();
    _snack('$n건을 삭제했습니다');
  }

  /// 항목별 출력 — 명단출력과 동일 원칙(다중 포맷 시트) 적용.
  void _export(List<Map<String, dynamic>> list, {bool single = false}) {
    if (!_canOutput) {
      _snack('출력 권한이 없습니다');
      return;
    }
    final gb = _groupBy == '전체' ? '' : '$_groupBy ';
    final title = single
        ? '재무 내역 (개별)'
        : '재무 원장 · $gb'
              '${_groupKey == '전체' ? '전체' : _groupKey} · $_typeFilter';
    final rows = list.map((t) {
      final isExp = '${t['type']}' == 'expense';
      return [
        '${t['date'] ?? ''}',
        isExp ? '지출' : '입금',
        '${t['name'] ?? t['payer'] ?? ''}',
        (t['number'] ?? '').toString().isNotEmpty ? '범#${t['number']}' : '',
        '${t['category'] ?? '기타'}',
        '${t['event'] ?? ''}',
        (isExp ? '-' : '') + ((t['amount'] as num?)?.toInt() ?? 0).toString(),
      ];
    }).toList();
    int income = 0, expense = 0;
    for (final t in list) {
      final a = (t['amount'] as num?)?.toInt() ?? 0;
      if ('${t['type']}' == 'expense') {
        expense += a;
      } else {
        income += a;
      }
    }
    final data = FinanceExportData(
      title: title,
      subtitle: '한국범스카우트중앙회',
      footnote: '출력일 기준 · 재무 원장',
      tables: [
        FinanceTable(
          title: '입금/지출 내역',
          headers: const ['일자', '구분', '성명', '인가번호', '분류', '행사', '금액'],
          rows: rows,
          totals: ['', '', '', '', '', '입금', '$income'],
          note: '지출 합계: $expense · 잔액: ${income - expense}',
        ),
      ],
    );
    showFinanceExportSheet(context, data: data);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  static String _won(int v) {
    final s = v.abs().toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '${v < 0 ? '-' : ''}$s원';
  }
}
