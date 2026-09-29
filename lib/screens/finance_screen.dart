import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/finance_transaction.dart';
import '../models/member.dart';
import '../services/app_state.dart';
import '../services/finance_export.dart';
import '../services/finance_service.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/finance_export_sheet.dart';
import '../widgets/hscroll_menu.dart';
import '../widgets/mini_charts.dart';
import 'bank_import_screen.dart';
import 'finance_transaction_edit_screen.dart';

/// 재무 대시보드 — 후원현황 / 수품구매 / 참가비 / 지출현황 / 행사별 결산
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  String _selectedYear = '전체';
  String _selEvent = '전체';
  String _selType = '전체'; // 전체 | 수입 | 지출
  DateTime? _from;
  DateTime? _to;

  static const _tabs = ['전체현황', '통계', '후원', '수품구매', '참가비', '연회비', '평생회비', '지출', '결산'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, _tabs.length - 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fs = context.read<FinanceService>();
      if (fs.transactions.isEmpty) fs.load();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FinanceService>();
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: TsakAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('재무 관리'),
        titleSpacing: 0,
        actions: [
          const AppHomeEmblem(size: 24),
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () => fs.load(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              switch (v) {
                case 'bank':
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BankImportScreen()),
                  );
                  if (context.mounted) fs.load();
                  break;
                case 'excel':
                  _openExcel(context);
                  break;
                case 'add':
                  _editTransaction(context);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'add', child: Text('입금/지출 직접 입력')),
              PopupMenuItem(value: 'bank', child: Text('은행거래파일 자동분류')),
              PopupMenuItem(value: 'excel', child: Text('통합 엑셀 내려받기')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: HsTabStrip(controller: _tab, labels: _tabs),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.purple,
        onPressed: () => _editTransaction(context),
        icon: const Icon(Icons.add),
        label: const Text('입금 입력'),
      ),
      body: fs.loading && fs.transactions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _yearBar(fs),
                _searchBar(fs),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _overview(fs, state),
                      _statsView(fs),
                      _categoryView(fs, state, '후원', AppColors.taegeukRed),
                      _categoryView(fs, state, '수품구매', AppColors.taegeukBlue),
                      _categoryView(fs, state, '참가비', AppColors.tigerGold),
                      _categoryView(fs, state, '연회비', AppColors.purple),
                      _categoryView(fs, state, '평생회비', AppColors.lifetimeGold),
                      _expenseView(fs),
                      _settlementView(fs),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ---- 연도 선택 바 ----
  Widget _yearBar(FinanceService fs) {
    final years = ['전체', ...fs.years()];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: HScrollMenu(
        height: 42,
        child: Row(
          children: [
            for (final y in years)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(y, style: const TextStyle(fontSize: 12)),
                  selected: _selectedYear == y,
                  selectedColor: AppColors.purple,
                  labelStyle: TextStyle(
                    color: _selectedYear == y ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (_) => setState(() => _selectedYear = y),
                ),
              ),
            const SizedBox(width: 6),
            if (fs.status == 'offline')
              const Chip(
                avatar: Icon(Icons.cloud_off, size: 15),
                label: Text('오프라인', style: TextStyle(fontSize: 11)),
                backgroundColor: Color(0xFFFFE9E9),
              ),
          ],
        ),
      ),
    );
  }

  bool _inYear(FinanceTransaction t) =>
      _selectedYear == '전체' || t.year == _selectedYear;

  // ---- 검색 바 (연도/기간/행사/유형/키워드) ----
  Widget _searchBar(FinanceService fs) {
    final events = ['전체', ...fs.allEvents()];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '이름/입금자/적요/행사 검색',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _periodButton(),
            ],
          ),
          const SizedBox(height: 6),
          HScrollMenu(
            height: 42,
            child: Row(
              children: [
                _miniChip('전체', _selType, (v) => setState(() => _selType = v),
                    AppColors.purple),
                _miniChip('수입', _selType, (v) => setState(() => _selType = v),
                    AppColors.scoutGreen),
                _miniChip('지출', _selType, (v) => setState(() => _selType = v),
                    AppColors.taegeukRed),
                const SizedBox(width: 10),
                const Text('행사:',
                    style: TextStyle(fontSize: 11, color: AppColors.textGray)),
                for (final e in events.take(12))
                  _miniChip(e, _selEvent, (v) => setState(() => _selEvent = v),
                      AppColors.taegeukBlue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String label, String cur, ValueChanged<String> onSel, Color c) {
    final sel = cur == label;
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: GestureDetector(
        onTap: () => onSel(label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: sel ? c : c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : c)),
        ),
      ),
    );
  }

  Widget _periodButton() {
    final has = _from != null || _to != null;
    final label = has
        ? '${_from != null ? _d(_from!) : ''}~${_to != null ? _d(_to!) : ''}'
        : '기간';
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 38),
      ),
      onPressed: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          setState(() {
            _from = picked.start;
            _to = picked.end;
          });
        }
      },
      icon: Icon(has ? Icons.event_available : Icons.date_range, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
    );
  }

  static String _d(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  // ---- 통계 대시보드 ----
  Widget _statsView(FinanceService fs) {
    final st = fs.serverStats.isNotEmpty ? fs.serverStats : fs.localStats();
    final total = (st['total'] as Map?) ?? {};
    final income = (total['income'] as num?)?.toInt() ?? 0;
    final expense = (total['expense'] as num?)?.toInt() ?? 0;
    final count = (total['count'] as num?)?.toInt() ?? 0;
    final byYear = (st['byYear'] as Map?) ?? {};
    final byCat = (st['byCategory'] as Map?) ?? {};
    final byExpCat = (st['byExpenseCategory'] as Map?) ?? {};
    final byEvent = (st['byEvent'] as Map?) ?? {};

    final catMap = <String, int>{};
    byCat.forEach((k, v) => catMap['$k'] = (v is num) ? v.toInt() : 0);
    final expMap = <String, int>{};
    byExpCat.forEach((k, v) => expMap['$k'] = (v is num) ? v.toInt() : 0);
    final yearIncome = <String, int>{};
    byYear.forEach((k, v) {
      if (v is Map) yearIncome['$k'] = ((v['income'] as num?) ?? 0).toInt();
    });
    final eventNet = <String, int>{};
    byEvent.forEach((k, v) {
      if (v is Map) {
        eventNet['$k'] = (((v['income'] as num?) ?? 0) -
                ((v['expense'] as num?) ?? 0))
            .toInt();
      }
    });

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _exportBar(1),
        const Text('DB 자동분석 통계',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.textDark)),
        const SizedBox(height: 2),
        Text('갱신 ${fs.statsUpdated}',
            style: const TextStyle(fontSize: 11, color: AppColors.textGray)),
        const SizedBox(height: 10),
        Row(children: [
          _metricCard('총 수입', income, AppColors.scoutGreen, Icons.savings),
          const SizedBox(width: 8),
          _metricCard('총 지출', expense, AppColors.taegeukRed, Icons.payments),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _metricCard('순액', income - expense, AppColors.purple,
              Icons.account_balance),
          const SizedBox(width: 8),
          _metricCard('거래건수', count, AppColors.taegeukBlue,
              Icons.receipt_long, isMoney: false),
        ]),
        const SizedBox(height: 14),
        _sectionTitle('연도별 수입'),
        _card(child: MiniBarChart(data: yearIncome, color: AppColors.purple)),
        const SizedBox(height: 14),
        _sectionTitle('수입 분류별'),
        _card(child: MiniDonut(data: catMap)),
        const SizedBox(height: 14),
        _sectionTitle('지출 분류별'),
        _card(
          child: expMap.isEmpty
              ? const Text('지출 내역 없음',
                  style: TextStyle(color: AppColors.textGray, fontSize: 12))
              : MiniBarChart(data: expMap, color: AppColors.taegeukRed),
        ),
        const SizedBox(height: 14),
        _sectionTitle('행사별 순액 (수입−지출)'),
        _card(
          child: eventNet.isEmpty
              ? const Text('행사 내역 없음',
                  style: TextStyle(color: AppColors.textGray, fontSize: 12))
              : MiniBarChart(data: eventNet, color: AppColors.scoutGreen),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  // ---- 전체 현황 ----
  Widget _overview(FinanceService fs, AppState state) {
    final tx = fs.transactions.where(_inYear).toList();
    final income = tx.where((t) => !t.isExpense).fold<int>(0, (s, t) => s + t.amount);
    final expense = tx.where((t) => t.isExpense).fold<int>(0, (s, t) => s + t.amount);
    final catTotals = <String, int>{};
    for (final t in tx) {
      if (t.isExpense) continue;
      catTotals[t.category] = (catTotals[t.category] ?? 0) + t.amount;
    }
    final yearMap = <String, int>{};
    for (final t in fs.transactions) {
      if (t.isExpense) continue;
      final y = t.year.isEmpty ? '미지정' : t.year;
      yearMap[y] = (yearMap[y] ?? 0) + t.amount;
    }
    final sortedYears = Map.fromEntries(
        yearMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      children: [
        _exportBar(0),
        Row(
          children: [
            _metricCard('총 수입', income, AppColors.scoutGreen, Icons.savings),
            const SizedBox(width: 8),
            _metricCard('총 지출', expense, AppColors.taegeukRed, Icons.payments),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _metricCard('순액', income - expense, AppColors.purple, Icons.account_balance),
            const SizedBox(width: 8),
            _metricCard('입금건수', tx.where((t) => !t.isExpense).length,
                AppColors.taegeukBlue, Icons.receipt_long, isMoney: false),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle('연도별 입금현황'),
        _card(child: MiniBarChart(data: sortedYears, color: AppColors.purple)),
        const SizedBox(height: 14),
        _sectionTitle('분류별 비중 (수입)'),
        _card(child: MiniDonut(data: catTotals)),
        const SizedBox(height: 14),
        _sectionTitle('미매칭 입금 (인가자 미확인) ${fs.unmatchedCount}건'),
        _txList(tx.where((t) => !t.isExpense && !t.matched).toList(), state),
        const SizedBox(height: 80),
      ],
    );
  }

  // ---- 카테고리별(후원/수품구매/참가비) ----
  Widget _categoryView(
      FinanceService fs, AppState state, String category, Color color) {
    final tx = fs.transactions
        .where(_inYear)
        .where((t) => !t.isExpense && t.category == category)
        .toList();
    final total = tx.fold<int>(0, (s, t) => s + t.amount);
    final yearMap = <String, int>{};
    final byMember = <String, int>{};
    for (final t in tx) {
      final y = t.year.isEmpty ? '미지정' : t.year;
      yearMap[y] = (yearMap[y] ?? 0) + t.amount;
      final no = t.number.replaceAll(RegExp(r'[^0-9]'), '');
      if (no.isNotEmpty) byMember[no] = (byMember[no] ?? 0) + t.amount;
    }
    final top = byMember.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final names = <String, Member>{for (final m in state.repo.all()) m.number: m};
    final maxV = top.isEmpty ? 0 : top.first.value;
    final tabIdx = _tabs.indexOf(category);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (tabIdx >= 0) _exportBar(tabIdx),
        _metricCard('$category 총액', total, color, Icons.volunteer_activism),
        const SizedBox(height: 12),
        _sectionTitle('연도별 $category'),
        _card(child: MiniBarChart(data: yearMap, color: color)),
        const SizedBox(height: 14),
        _sectionTitle('개인별 TOP (${top.length}명)'),
        _card(
          child: top.isEmpty
              ? const Text('내역 없음',
                  style: TextStyle(color: AppColors.textGray, fontSize: 12))
              : Column(
                  children: [
                    for (final e in top.take(15))
                      MiniRankBar(
                        label: names[e.key]?.name ?? '번호 ${e.key}',
                        value: e.value,
                        maxValue: maxV,
                        color: color,
                        trailing: '${_won(e.value)}원',
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        _sectionTitle('$category 입금 내역 (${tx.length}건)'),
        _txList(tx, state),
        const SizedBox(height: 80),
      ],
    );
  }

  // ---- 지출현황 ----
  Widget _expenseView(FinanceService fs) {
    final tx = fs.transactions.where(_inYear).where((t) => t.isExpense).toList();
    final total = tx.fold<int>(0, (s, t) => s + t.amount);
    final catMap = <String, int>{};
    for (final t in tx) {
      catMap[t.category] = (catMap[t.category] ?? 0) + t.amount;
    }
    final byEvent = <String, int>{};
    for (final t in tx) {
      final k = t.event.trim().isEmpty ? '(미지정)' : t.event.trim();
      byEvent[k] = (byEvent[k] ?? 0) + t.amount;
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _exportBar(7),
        _metricCard('총 지출', total, AppColors.taegeukRed, Icons.payments),
        const SizedBox(height: 12),
        _sectionTitle('분류별 지출'),
        _card(child: MiniBarChart(data: catMap, color: AppColors.taegeukRed)),
        const SizedBox(height: 14),
        _sectionTitle('행사별 지출'),
        _card(child: MiniBarChart(data: byEvent, color: AppColors.taegeukBlue)),
        const SizedBox(height: 14),
        _sectionTitle('지출 내역 (${tx.length}건)'),
        if (tx.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('지출 내역이 없습니다',
                style: TextStyle(color: AppColors.textGray)),
          )
        else ...[
          for (final t in tx.take(150)) _txTile(t, null, isExpense: true),
          if (tx.length > 150)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('외 ${tx.length - 150}건 (검색/기간 필터로 좁혀보세요)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textGray)),
            ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  // ---- 행사별 결산 ----
  Widget _settlementView(FinanceService fs) {
    final list = fs.eventSettlements();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _exportBar(8),
        _sectionTitle('행사별 결산 현황 (수입 − 지출)'),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('결산 자료가 없습니다',
                style: TextStyle(color: AppColors.textGray)),
          )
        else
          for (final s in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: (s.net >= 0
                          ? AppColors.scoutGreen
                          : AppColors.taegeukRed)
                      .withValues(alpha: 0.15),
                  child: Icon(
                    s.net >= 0 ? Icons.trending_up : Icons.trending_down,
                    color: s.net >= 0
                        ? AppColors.scoutGreen
                        : AppColors.taegeukRed,
                  ),
                ),
                title: Text(s.event,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '수입 ${_won(s.income)}원 · 지출 ${_won(s.expense)}원',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  '${s.net >= 0 ? '+' : ''}${_won(s.net)}원',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color:
                        s.net >= 0 ? AppColors.scoutGreen : AppColors.taegeukRed,
                  ),
                ),
              ),
            ),
        const SizedBox(height: 80),
      ],
    );
  }

  // ---- 공용 위젯 ----
  Widget _metricCard(String label, int value, Color color, IconData icon,
      {bool isMoney = true}) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 5),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textGray)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isMoney ? '${_won(value)}원' : '$value건',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark)),
      );

  Widget _card({required Widget child}) =>
      Card(child: Padding(padding: const EdgeInsets.all(12), child: child));

  Widget _txList(List<FinanceTransaction> tx, AppState state) {
    if (tx.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('내역이 없습니다',
            style: TextStyle(color: AppColors.textGray, fontSize: 12)),
      );
    }
    // 성능: 다량 거래시 상위 N건만 렌더(무한 스크롤 대신 요약)
    const cap = 150;
    final shown = tx.length > cap ? tx.take(cap).toList() : tx;
    return Column(children: [
      for (final t in shown) _txTile(t, state),
      if (tx.length > cap)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('외 ${tx.length - cap}건 (검색/기간 필터로 좁혀보세요)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray)),
        ),
    ]);
  }

  Widget _txTile(FinanceTransaction t, AppState? state, {bool isExpense = false}) {
    final member =
        t.number.isNotEmpty ? state?.byNumber(t.number) : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: (isExpense ? AppColors.taegeukRed : AppColors.scoutGreen)
              .withValues(alpha: 0.14),
          child: Icon(
            isExpense ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
            color: isExpense ? AppColors.taegeukRed : AppColors.scoutGreen,
          ),
        ),
        title: Text(
          '${member?.name ?? t.name}'
          '${t.number.isNotEmpty ? ' (#${t.number})' : ''}',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${t.date} · ${t.category}'
          '${t.event.isNotEmpty ? ' · ${t.event}' : ''}'
          '${t.payer.isNotEmpty && t.payer != t.name ? '\n원문: ${t.payer}' : ''}'
          '${t.context.isNotEmpty ? '\n인식: ${t.context}' : ''}',
          style: const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        isThreeLine: t.context.isNotEmpty || t.payer != t.name,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${_won(t.amount)}원',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isExpense
                        ? AppColors.taegeukRed
                        : AppColors.textDark)),
            if (!isExpense && !t.matched)
              const Text('미매칭',
                  style: TextStyle(fontSize: 9.5, color: AppColors.taegeukRed)),
          ],
        ),
        onTap: () => _editTransaction(context, existing: t),
      ),
    );
  }

  Future<void> _editTransaction(BuildContext context,
      {FinanceTransaction? existing}) async {
    final fs = context.read<FinanceService>();
    final state = context.read<AppState>();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FinanceTransactionEditScreen(
          finance: fs,
          members: state.repo.all(),
          existing: existing,
        ),
      ),
    );
  }

  void _openExcel(BuildContext context) {
    final nas = context.read<NasApi>();
    final url = nas.financeExcelUrl();
    _showUrl(context, url);
  }

  void _showUrl(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('통합 엑셀 내려받기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('아래 주소를 브라우저에 붙여 넣으면 '
                '거래내역·연도별집계·인가자별요약·분류규칙 시트가 담긴 '
                '엑셀 파일을 내려받습니다.'),
            const SizedBox(height: 10),
            SelectableText(url,
                style: const TextStyle(fontSize: 11, color: AppColors.purple)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  static String _won(int v) {
    final neg = v < 0;
    final s = v.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${neg ? '-' : ''}$buf';
  }

  static String _money(int v) => '${_won(v)}원';

  // ==========================================================================
  //  출력 (다중 포맷) — 각 탭의 데이터를 동일 구성으로 내보낸다
  // ==========================================================================

  /// 각 탭 상단에 놓이는 출력 버튼 (해당 항목만 내보냄)
  Widget _exportBar(int tabIndex) {
    final label = _tabs[tabIndex.clamp(0, _tabs.length - 1)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onPressed: () => _exportTab(tabIndex),
              icon: const Icon(Icons.ios_share, size: 18),
              label: Text('「$label」 출력 (PDF·JPG·엑셀·PPT·워드·CSV·TXT)',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  void _exportTab(int tabIndex) {
    final fs = context.read<FinanceService>();
    final state = context.read<AppState>();
    final data = _buildExportData(fs, state, tabIndex);
    showFinanceExportSheet(context, data: data);
  }

  FinanceExportData _buildExportData(
      FinanceService fs, AppState state, int tabIndex) {
    switch (tabIndex) {
      case 0:
        return _overviewExport(fs, state);
      case 1:
        return _statsExport(fs);
      case 7:
        return _expenseExport(fs);
      case 8:
        return _settlementExport(fs);
      default:
        final cat = (tabIndex >= 2 && tabIndex <= 6) ? _tabs[tabIndex] : '후원';
        return _categoryExport(fs, state, cat);
    }
  }

  String _nameOf(AppState state, FinanceTransaction t) {
    if (t.number.isNotEmpty) {
      final m = state.byNumber(t.number);
      if (m != null && m.name.isNotEmpty) return m.name;
    }
    return t.name.isNotEmpty ? t.name : t.payer;
  }

  FinanceExportData _overviewExport(FinanceService fs, AppState state) {
    final tx = fs.transactions.where(_inYear).toList();
    final income =
        tx.where((t) => !t.isExpense).fold<int>(0, (s, t) => s + t.amount);
    final expense =
        tx.where((t) => t.isExpense).fold<int>(0, (s, t) => s + t.amount);

    final catTotals = <String, int>{};
    for (final t in tx) {
      if (t.isExpense) continue;
      catTotals[t.category] = (catTotals[t.category] ?? 0) + t.amount;
    }
    final catTotalSum = catTotals.values.fold<int>(0, (s, v) => s + v);

    final yearMap = <String, int>{};
    for (final t in fs.transactions) {
      if (t.isExpense) continue;
      final y = t.year.isEmpty ? '미지정' : t.year;
      yearMap[y] = (yearMap[y] ?? 0) + t.amount;
    }
    final sortedYears = Map.fromEntries(
        yearMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));

    final unmatched =
        tx.where((t) => !t.isExpense && !t.matched).toList();

    final tables = <FinanceTable>[
      FinanceTable(
        title: '요약',
        headers: const ['항목', '금액'],
        rows: [
          ['총 수입', _money(income)],
          ['총 지출', _money(expense)],
          ['순액', _money(income - expense)],
          ['입금건수', '${tx.where((t) => !t.isExpense).length}건'],
          ['지출건수', '${tx.where((t) => t.isExpense).length}건'],
        ],
      ),
      FinanceTable(
        title: '연도별 입금현황',
        headers: const ['연도', '입금액'],
        rows: [
          for (final e in sortedYears.entries) [e.key, _money(e.value)],
        ],
        totals: ['합계', _money(sortedYears.values.fold<int>(0, (s, v) => s + v))],
      ),
      FinanceTable(
        title: '분류별 비중 (수입)',
        headers: const ['분류', '금액', '비중'],
        rows: [
          for (final e in (catTotals.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))))
            [
              e.key,
              _money(e.value),
              catTotalSum == 0
                  ? '0%'
                  : '${(e.value * 100 / catTotalSum).toStringAsFixed(1)}%',
            ],
        ],
        totals: ['합계', _money(catTotalSum), '100%'],
      ),
      FinanceTable(
        title: '미매칭 입금 (인가자 미확인)',
        note: '입금자 텍스트에서 인가자를 인식하지 못한 건',
        headers: const ['일자', '입금자(원문)', '인식정보', '금액', '분류'],
        rows: [
          for (final t in unmatched)
            [
              t.date,
              t.payer,
              t.context,
              _money(t.amount),
              t.category,
            ],
        ],
      ),
    ];
    return FinanceExportData(
      title: '전체 재무 현황',
      subtitle: '기간: $_selectedYear',
      tables: tables,
      footnote: '출력일 기준 · 한국범스카우트중앙회 통합 재무',
    );
  }

  FinanceExportData _statsExport(FinanceService fs) {
    final st = fs.serverStats.isNotEmpty ? fs.serverStats : fs.localStats();
    final total = (st['total'] as Map?) ?? {};
    final income = (total['income'] as num?)?.toInt() ?? 0;
    final expense = (total['expense'] as num?)?.toInt() ?? 0;
    final count = (total['count'] as num?)?.toInt() ?? 0;
    final byYear = (st['byYear'] as Map?) ?? {};
    final byCat = (st['byCategory'] as Map?) ?? {};
    final byExpCat = (st['byExpenseCategory'] as Map?) ?? {};
    final byEvent = (st['byEvent'] as Map?) ?? {};

    final yearRows = <List<String>>[];
    final yEntries = byYear.entries.toList()
      ..sort((a, b) => '${b.key}'.compareTo('${a.key}'));
    for (final e in yEntries) {
      final v = e.value;
      if (v is Map) {
        final yi = ((v['income'] as num?) ?? 0).toInt();
        final ye = ((v['expense'] as num?) ?? 0).toInt();
        yearRows.add(['${e.key}', _money(yi), _money(ye), _money(yi - ye)]);
      }
    }

    final catRows = <List<String>>[];
    final cEntries = byCat.entries.toList()
      ..sort((a, b) =>
          (((b.value as num?) ?? 0)).compareTo((a.value as num?) ?? 0));
    for (final e in cEntries) {
      catRows.add(['${e.key}', _money(((e.value as num?) ?? 0).toInt())]);
    }

    final expRows = <List<String>>[];
    final eEntries = byExpCat.entries.toList()
      ..sort((a, b) =>
          (((b.value as num?) ?? 0)).compareTo((a.value as num?) ?? 0));
    for (final e in eEntries) {
      expRows.add(['${e.key}', _money(((e.value as num?) ?? 0).toInt())]);
    }

    final eventRows = <List<String>>[];
    for (final e in byEvent.entries) {
      final v = e.value;
      if (v is Map) {
        final ei = ((v['income'] as num?) ?? 0).toInt();
        final ee = ((v['expense'] as num?) ?? 0).toInt();
        eventRows.add(['${e.key}', _money(ei), _money(ee), _money(ei - ee)]);
      }
    }

    return FinanceExportData(
      title: '재무 통계',
      subtitle: 'DB 자동분석 · 갱신 ${fs.statsUpdated}',
      tables: [
        FinanceTable(
          title: '총계',
          headers: const ['항목', '값'],
          rows: [
            ['총 수입', _money(income)],
            ['총 지출', _money(expense)],
            ['순액', _money(income - expense)],
            ['거래건수', '$count건'],
          ],
        ),
        FinanceTable(
          title: '연도별 수입/지출',
          headers: const ['연도', '수입', '지출', '순액'],
          rows: yearRows,
        ),
        FinanceTable(
          title: '수입 분류별',
          headers: const ['분류', '금액'],
          rows: catRows,
          totals: [
            '합계',
            _money(catRows.fold<int>(
                0, (s, r) => s + _parseWon(r.length > 1 ? r[1] : ''))),
          ],
        ),
        FinanceTable(
          title: '지출 분류별',
          headers: const ['분류', '금액'],
          rows: expRows,
          totals: [
            '합계',
            _money(expRows.fold<int>(
                0, (s, r) => s + _parseWon(r.length > 1 ? r[1] : ''))),
          ],
        ),
        FinanceTable(
          title: '행사별 순액 (수입−지출)',
          headers: const ['행사', '수입', '지출', '순액'],
          rows: eventRows,
        ),
      ],
    );
  }

  static int _parseWon(String s) =>
      int.tryParse(s.replaceAll(RegExp(r'[^0-9\-]'), '')) ?? 0;

  FinanceExportData _categoryExport(
      FinanceService fs, AppState state, String category) {
    final tx = fs.transactions
        .where(_inYear)
        .where((t) => !t.isExpense && t.category == category)
        .toList();
    final total = tx.fold<int>(0, (s, t) => s + t.amount);
    final yearMap = <String, int>{};
    final byMember = <String, int>{};
    for (final t in tx) {
      final y = t.year.isEmpty ? '미지정' : t.year;
      yearMap[y] = (yearMap[y] ?? 0) + t.amount;
      final no = t.number.replaceAll(RegExp(r'[^0-9]'), '');
      if (no.isNotEmpty) byMember[no] = (byMember[no] ?? 0) + t.amount;
    }
    final top = byMember.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final names = <String, Member>{for (final m in state.repo.all()) m.number: m};

    return FinanceExportData(
      title: '$category 현황',
      subtitle: '기간: $_selectedYear',
      tables: [
        FinanceTable(
          title: '요약',
          headers: const ['항목', '값'],
          rows: [
            ['$category 총액', _money(total)],
            ['건수', '${tx.length}건'],
            ['납부 인원', '${top.length}명'],
          ],
        ),
        FinanceTable(
          title: '연도별 $category',
          headers: const ['연도', '금액'],
          rows: [
            for (final e in (yearMap.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
              [e.key, _money(e.value)],
          ],
          totals: ['합계', _money(total)],
        ),
        FinanceTable(
          title: '개인별 TOP (${top.length}명)',
          headers: const ['인가번호', '성명', '금액'],
          rows: [
            for (final e in top.take(100))
              [
                e.key,
                names[e.key]?.name ?? '번호 ${e.key}',
                _money(e.value),
              ],
          ],
        ),
        FinanceTable(
          title: '$category 입금 상세 (${tx.length}건)',
          headers: const ['일자', '인가번호', '성명', '금액', '행사', '메모'],
          rows: [
            for (final t in tx)
              [
                t.date,
                t.number,
                _nameOf(state, t),
                _money(t.amount),
                t.event,
                t.memo,
              ],
          ],
          totals: ['합계', '', '', _money(total), '', ''],
        ),
      ],
    );
  }

  FinanceExportData _expenseExport(FinanceService fs) {
    final tx =
        fs.transactions.where(_inYear).where((t) => t.isExpense).toList();
    final total = tx.fold<int>(0, (s, t) => s + t.amount);
    final catMap = <String, int>{};
    for (final t in tx) {
      catMap[t.category] = (catMap[t.category] ?? 0) + t.amount;
    }
    final byEvent = <String, int>{};
    for (final t in tx) {
      final k = t.event.trim().isEmpty ? '(미지정)' : t.event.trim();
      byEvent[k] = (byEvent[k] ?? 0) + t.amount;
    }

    return FinanceExportData(
      title: '지출 현황',
      subtitle: '기간: $_selectedYear',
      tables: [
        FinanceTable(
          title: '요약',
          headers: const ['항목', '값'],
          rows: [
            ['총 지출', _money(total)],
            ['건수', '${tx.length}건'],
          ],
        ),
        FinanceTable(
          title: '분류별 지출',
          headers: const ['분류', '금액'],
          rows: [
            for (final e in (catMap.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value))))
              [e.key, _money(e.value)],
          ],
          totals: ['합계', _money(total)],
        ),
        FinanceTable(
          title: '행사별 지출',
          headers: const ['행사', '금액'],
          rows: [
            for (final e in (byEvent.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value))))
              [e.key, _money(e.value)],
          ],
        ),
        FinanceTable(
          title: '지출 상세 (${tx.length}건)',
          headers: const ['일자', '분류', '행사', '내용', '금액', '메모'],
          rows: [
            for (final t in tx)
              [
                t.date,
                t.category,
                t.event,
                t.name.isNotEmpty ? t.name : t.payer,
                _money(t.amount),
                t.memo,
              ],
          ],
          totals: ['합계', '', '', '', _money(total), ''],
        ),
      ],
    );
  }

  FinanceExportData _settlementExport(FinanceService fs) {
    final list = fs.eventSettlements();
    return FinanceExportData(
      title: '행사별 결산',
      subtitle: '수입 − 지출',
      tables: [
        FinanceTable(
          title: '행사별 결산 현황',
          headers: const ['행사', '수입', '지출', '순액'],
          rows: [
            for (final s in list)
              [s.event, _money(s.income), _money(s.expense), _money(s.net)],
          ],
          totals: [
            '합계',
            _money(list.fold<int>(0, (a, s) => a + s.income)),
            _money(list.fold<int>(0, (a, s) => a + s.expense)),
            _money(list.fold<int>(0, (a, s) => a + s.net)),
          ],
        ),
      ],
    );
  }
}
