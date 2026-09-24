import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/finance_transaction.dart';
import '../models/member.dart';
import '../services/app_state.dart';
import '../services/finance_service.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
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
  String _selectedYear = '전체';

  static const _tabs = ['전체현황', '후원', '수품구매', '참가비', '지출', '결산'];

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FinanceService>();
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
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
        bottom: TabBar(
          isScrollable: true,
          controller: _tab,
          indicatorColor: AppColors.tigerGold,
          tabs: [for (final t in _tabs) Tab(text: t)],
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
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _overview(fs, state),
                      _categoryView(fs, state, '후원', AppColors.taegeukRed),
                      _categoryView(fs, state, '수품구매', AppColors.taegeukBlue),
                      _categoryView(fs, state, '참가비', AppColors.tigerGold),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
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
        else
          for (final t in tx)
            _txTile(t, null, isExpense: true),
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
    return Column(children: [for (final t in tx) _txTile(t, state)]);
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
}
