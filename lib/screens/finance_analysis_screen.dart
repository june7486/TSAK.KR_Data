import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../widgets/marquee_text.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';

import '../services/app_state.dart';
import '../services/file_save.dart';
import '../services/finance_export.dart';
import '../services/finance_report.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/finance_export_sheet.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/hscroll_menu.dart';
import '../widgets/mini_charts.dart';

/// Phase 4 — 기본자료 폴더 은행거래내역 종합분석 보고서 화면.
///
/// · 2013년 ~ 전체 기간, 연도/월/행사별 분석
/// · 후원·수품·지출·행사 카테고리 자동 분류
/// · MUJI 스타일 A4 세로 전문가 보고서(PDF) 생성 + 미리보기/인쇄/공유
/// · 분석 중 "작업중" 화면 표시
class FinanceAnalysisScreen extends StatefulWidget {
  const FinanceAnalysisScreen({super.key});

  @override
  State<FinanceAnalysisScreen> createState() => _FinanceAnalysisScreenState();
}

class _FinanceAnalysisScreenState extends State<FinanceAnalysisScreen> {
  bool _loading = true;
  bool _working = false;
  String _workingMsg = '';
  bool _building = false;
  String? _error;
  Map<String, dynamic> _a = {};
  String _yearFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(cached: true));
  }

  Future<void> _load({required bool cached}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final state = context.read<AppState>();
    final a = cached
        ? await state.loadFinanceAnalysis()
        : await state.analyzeFinanceFresh();
    if (!mounted) return;
    setState(() {
      _a = a;
      _loading = false;
      if (a.isEmpty) _error = '분석 데이터를 불러오지 못했습니다.';
    });
  }

  /// 작업중 화면을 띄우고 최신 폴더 기준 재분석.
  Future<void> _reanalyze() async {
    setState(() {
      _working = true;
      _workingMsg = '은행거래내역 폴더를 확인하는 중…';
    });
    // 단계 메시지 애니메이션
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted && _working) {
        setState(() => _workingMsg = '엑셀 시트를 읽고 거래를 분류하는 중…');
      }
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _working) {
        setState(() => _workingMsg = '연도·월·행사별로 집계하는 중…');
      }
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _working) {
        setState(() => _workingMsg = '보고서 데이터를 정리하는 중…');
      }
    });
    final state = context.read<AppState>();
    final a = await state.analyzeFinanceFresh();
    if (!mounted) return;
    setState(() {
      _a = a;
      _working = false;
      _loading = false;
      if (a.isEmpty) _error = '재분석에 실패했습니다.';
    });
  }

  Future<void> _buildPdf({bool preview = true}) async {
    if (_a.isEmpty) return;
    setState(() => _building = true);
    try {
      final bytes = await FinanceReportService.build(_a);
      if (!mounted) return;
      setState(() => _building = false);
      if (preview) {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: '${FinanceReportService.fileName()}.pdf',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _building = false);
      _snack('보고서 생성 실패: $e');
    }
  }

  Future<void> _share() async {
    if (_a.isEmpty) return;
    setState(() => _building = true);
    try {
      final bytes = await FinanceReportService.build(_a);
      if (!mounted) return;
      setState(() => _building = false);
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: '${FinanceReportService.fileName()}.pdf',
          mimeType: 'application/pdf',
        ),
      ], subject: '한국범스카우트중앙회 은행거래 종합분석 보고서');
    } catch (e) {
      if (!mounted) return;
      setState(() => _building = false);
      _snack('공유 실패: $e');
    }
  }

  Future<void> _save() async {
    if (_a.isEmpty) return;
    final choose = await askSaveLocation(context, info: '재무 보고서 (PDF)');
    if (choose == null) return; // 취소
    setState(() => _building = true);
    try {
      final bytes = await FinanceReportService.build(_a);
      if (!mounted) return;
      setState(() => _building = false);
      final ok = await saveFileNamed(
        bytes: Uint8List.fromList(bytes),
        filename: '${FinanceReportService.fileName()}.pdf',
        mime: 'application/pdf',
        mimeType: MimeType.pdf,
        choose: choose,
      );
      _snack(ok ? '보고서를 저장했습니다.' : '저장이 취소되었습니다.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _building = false);
      _snack('저장 실패: $e');
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }

  // ==========================================================================
  //  다중 포맷 내보내기 — 분석 데이터를 명단출력과 동일한 구성(요약·연도별·분류별·
  //  행사별·원본파일)으로 엑셀·PDF·워드·TXT·PPT·CSV·JPG 로 출력한다.
  // ==========================================================================
  void _openExportSheet() {
    if (_a.isEmpty) {
      _snack('분석 데이터가 없습니다');
      return;
    }
    showFinanceExportSheet(context, data: _buildAnalysisExportData());
  }

  /// 분석 결과(_a) → FinanceExportData(표 묶음).
  FinanceExportData _buildAnalysisExportData() {
    final t = (_a['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    final years = (_a['years'] as Map?)?.cast<String, dynamic>() ?? {};
    final files = (_a['files'] as List?) ?? [];
    final events = (_a['events'] as Map?)?.cast<String, dynamic>() ?? {};
    final yearKeys = years.keys.toList()..sort((x, y) => y.compareTo(x));

    final tables = <FinanceTable>[];

    // 1) 요약
    final income = (t['income'] ?? 0) as num;
    final expense = (t['expense'] ?? 0) as num;
    final net = (t['net'] ?? (income - expense)) as num;
    tables.add(
      FinanceTable(
        title: '요약',
        headers: const ['항목', '값'],
        rows: [
          [
            '기간',
            '${t['from'] ?? ''} – ${t['to'] ?? ''}년 (${t['yearCount'] ?? 0}개 연도)',
          ],
          ['총 수입', _money(income)],
          ['총 지출', _money(expense)],
          ['순액', _money(net)],
          ['분석 건수', '${t['rows'] ?? 0}건'],
        ],
      ),
    );

    // 2) 연도별 요약
    final yearRows = <List<String>>[];
    for (final y in yearKeys) {
      final b = (years[y] as Map).cast<String, dynamic>();
      yearRows.add([
        '$y년',
        _money((b['income'] ?? 0) as num),
        _money((b['expense'] ?? 0) as num),
        _money((b['net'] ?? 0) as num),
        '${b['count'] ?? 0}건',
      ]);
    }
    tables.add(
      FinanceTable(
        title: '연도별 요약',
        headers: const ['연도', '수입', '지출', '순액', '건수'],
        rows: yearRows,
      ),
    );

    // 3) 연도별 분류 상세
    final catRows = <List<String>>[];
    for (final y in yearKeys) {
      final b = (years[y] as Map).cast<String, dynamic>();
      final cats = (b['byCategory'] as Map?)?.cast<String, dynamic>() ?? {};
      final entries = cats.entries.toList()
        ..sort((x, yy) => (yy.value as num).compareTo(x.value as num));
      for (final e in entries) {
        final isExp = e.key.startsWith('지출:');
        catRows.add([
          '$y년',
          isExp ? '지출' : '수입',
          e.key.split(':').last,
          _money(e.value as num),
        ]);
      }
    }
    if (catRows.isNotEmpty) {
      tables.add(
        FinanceTable(
          title: '연도별 분류 상세',
          headers: const ['연도', '구분', '분류', '금액'],
          rows: catRows,
        ),
      );
    }

    // 4) 행사별 분석
    final evList = events.values.toList();
    evList.sort(
      (x, y) => (((y['income'] as num) + (y['expense'] as num))).compareTo(
        ((x['income'] as num) + (x['expense'] as num)),
      ),
    );
    if (evList.isNotEmpty) {
      tables.add(
        FinanceTable(
          title: '행사별 분석',
          headers: const ['행사', '수입', '지출', '순액'],
          rows: [
            for (final e in evList)
              [
                '${e['title'] ?? e['name'] ?? ''}',
                _money((e['income'] ?? 0) as num),
                _money((e['expense'] ?? 0) as num),
                _money(
                  ((e['income'] ?? 0) as num) - ((e['expense'] ?? 0) as num),
                ),
              ],
          ],
        ),
      );
    }

    // 5) 분석 원본 파일
    if (files.isNotEmpty) {
      tables.add(
        FinanceTable(
          title: '분석 원본 파일',
          headers: const ['파일', '건수', '상태'],
          rows: [
            for (final f in files)
              if (f is Map)
                [
                  '${f['name'] ?? f['file'] ?? ''}',
                  '${f['count'] ?? f['rows'] ?? ''}',
                  '${f['status'] ?? ''}',
                ],
          ],
        ),
      );
    }

    return FinanceExportData(
      title: '은행거래 종합분석 보고서',
      subtitle: '한국범스카우트중앙회 · ${t['from'] ?? ''} – ${t['to'] ?? ''}년',
      tables: tables,
      footnote: '출력일 기준 · 기본자료 폴더 분석 결과 (마스터 전용)',
    );
  }

  static String _money(num v) {
    final neg = v < 0;
    final n = v.abs().round().toString();
    final b = StringBuffer();
    for (int i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) b.write(',');
      b.write(n[i]);
    }
    return '${neg ? '-' : ''}$b원';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // 기본자료 폴더 소속 분석 — 마스터 전용(요구: "기본자료 항목은 마스터만 볼 수 있음").
    if (!state.isMaster) {
      return Scaffold(
        appBar: TsakAppBar(
          leading: const AppBackButton(label: '뒤로'),
          leadingWidth: 84,
          title: const Text('은행거래 종합분석'),
        ),
        body: const Center(child: Text('기본자료는 마스터만 볼 수 있습니다')),
      );
    }
    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('은행거래 종합분석'),
        actions: [
          IconButton(
            tooltip: '최신자료 재분석',
            onPressed: (_loading || _working) ? null : _reanalyze,
            icon: const Icon(Icons.refresh),
          ),
          const AppHomeEmblem(size: 24),
        ],
      ),
      body: Stack(
        children: [
          _body(),
          BusyOverlay(
            visible: _loading || _working || _building,
            title: _building ? '보고서를 생성하는 중입니다' : '재무 데이터를 분석하는 중입니다',
            lines: [
              if (_building) '선택한 조건으로 출력물을 만들고 있습니다...',
              if (!_building && _workingMsg.isNotEmpty) _workingMsg,
              '잠시만 기다려 주세요...',
            ],
          ),
        ],
      ),
      bottomNavigationBar: (_a.isEmpty || _loading) ? null : _bottomBar(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.taegeukRed,
            ),
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.textGray)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _load(cached: false),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    final t = (_a['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    final years = (_a['years'] as Map?)?.cast<String, dynamic>() ?? {};
    final yearKeys = years.keys.toList()..sort((x, y) => y.compareTo(x));
    final files = (_a['files'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        _periodBanner(t),
        const SizedBox(height: 12),
        _summaryCards(t),
        const SizedBox(height: 16),
        _sectionTitle('연도별 재무 추이'),
        const SizedBox(height: 8),
        _yearBarChart(yearKeys, years),
        const SizedBox(height: 16),
        _sectionTitle('연도별 요약'),
        const SizedBox(height: 6),
        _yearFilterChips(yearKeys),
        const SizedBox(height: 6),
        _yearList(yearKeys, years),
        const SizedBox(height: 16),
        _sectionTitle('행사별 분석'),
        const SizedBox(height: 6),
        _eventsCard(),
        const SizedBox(height: 16),
        _sectionTitle('분석 원본 파일'),
        const SizedBox(height: 6),
        _filesCard(files),
        const SizedBox(height: 10),
        _footnote(),
      ],
    );
  }

  Widget _periodBanner(Map<String, dynamic> t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '은행거래내역 종합분석',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${t['from'] ?? ''} – ${t['to'] ?? ''}년 (${t['yearCount'] ?? 0}개 연도) · 후원·수품·지출·행사',
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCards(Map<String, dynamic> t) {
    Widget card(String label, num value, Color color, IconData icon) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 5),
                Text(
                  _shortWon(value),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
        );
    final net = (t['net'] ?? 0) as num;
    return Column(
      children: [
        Row(
          children: [
            card(
              '총 수입',
              (t['income'] ?? 0) as num,
              AppColors.scoutGreen,
              Icons.trending_up,
            ),
            const SizedBox(width: 8),
            card(
              '총 지출',
              (t['expense'] ?? 0) as num,
              AppColors.tigerGold,
              Icons.trending_down,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            card(
              '순액',
              net,
              net >= 0 ? AppColors.taegeukBlue : AppColors.taegeukRed,
              Icons.account_balance_wallet,
            ),
            const SizedBox(width: 8),
            card(
              '분석 건수',
              (t['rows'] ?? 0) as num,
              AppColors.purple,
              Icons.receipt_long,
            ),
          ],
        ),
      ],
    );
  }

  Widget _yearBarChart(List<String> yearKeys, Map<String, dynamic> years) {
    final data = <String, int>{};
    for (final y in yearKeys.take(14)) {
      final b = (years[y] as Map).cast<String, dynamic>();
      data[y] = (((b['income'] ?? 0) as num) + ((b['expense'] ?? 0) as num))
          .round();
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '수입+지출 규모 (연도별)',
            style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: MiniBarChart(
              data: data,
              height: 120,
              valueFormatter: (v) => _shortWon(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _yearFilterChips(List<String> yearKeys) {
    return HScrollMenu(
      height: 36,
      child: Row(
        children: [_chip('전체', 'all'), ...yearKeys.map((y) => _chip(y, y))],
      ),
    );
  }

  Widget _chip(String label, String key) {
    final sel = _yearFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: sel,
        onSelected: (_) => setState(() => _yearFilter = key),
        selectedColor: AppColors.purple.withValues(alpha: 0.18),
      ),
    );
  }

  Widget _yearList(List<String> yearKeys, Map<String, dynamic> years) {
    final keys = _yearFilter == 'all' ? yearKeys : [_yearFilter];
    return Column(
      children: keys.where((y) => years[y] is Map).map((y) {
        final b = (years[y] as Map).cast<String, dynamic>();
        final cats = (b['byCategory'] as Map?)?.cast<String, dynamic>() ?? {};
        final entries = cats.entries.toList()
          ..sort((x, yy) => (yy.value as num).compareTo(x.value as num));
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: Row(
              children: [
                Text(
                  '$y년',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '순액 ${_shortWon((b['net'] ?? 0) as num)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: ((b['net'] ?? 0) as num) >= 0
                        ? AppColors.scoutGreen
                        : AppColors.taegeukRed,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '수입 ${_shortWon((b['income'] ?? 0) as num)} · 지출 ${_shortWon((b['expense'] ?? 0) as num)} · ${b['count'] ?? 0}건',
              style: const TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
            children: [
              ...entries.map((e) {
                final isExp = e.key.startsWith('지출:');
                final label = e.key.split(':').last;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isExp
                                      ? AppColors.tigerGold
                                      : AppColors.scoutGreen)
                                  .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isExp ? '지출' : '수입',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isExp
                                ? AppColors.tigerGold
                                : AppColors.scoutGreen,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      Text(
                        '${_wonComma(e.value as num)}원',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              _monthsChart(b),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 연도 월별 수입/지출 막대 (byMonth 활용).
  Widget _monthsChart(Map<String, dynamic> b) {
    final byMonth = (b['byMonth'] as Map?)?.cast<String, dynamic>() ?? {};
    num maxV = 1;
    for (int i = 1; i <= 12; i++) {
      final m = (byMonth['$i'] as Map?)?.cast<String, dynamic>() ?? {};
      final inc = (m['income'] ?? 0) as num;
      final exp = (m['expense'] ?? 0) as num;
      if (inc > maxV) maxV = inc;
      if (exp > maxV) maxV = exp;
    }
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '월별 수입/지출',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              Container(width: 8, height: 8, color: AppColors.scoutGreen),
              const SizedBox(width: 3),
              const Text(
                '수입',
                style: TextStyle(fontSize: 9.5, color: AppColors.textGray),
              ),
              const SizedBox(width: 8),
              Container(width: 8, height: 8, color: AppColors.tigerGold),
              const SizedBox(width: 3),
              const Text(
                '지출',
                style: TextStyle(fontSize: 9.5, color: AppColors.textGray),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 1; i <= 12; i++)
                  Expanded(child: _monthBar(byMonth, i, maxV)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthBar(Map<String, dynamic> byMonth, int month, num maxV) {
    final m = (byMonth['$month'] as Map?)?.cast<String, dynamic>() ?? {};
    final inc = (m['income'] ?? 0) as num;
    final exp = (m['expense'] ?? 0) as num;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 4,
              height: (inc / maxV * 48).clamp(0, 48).toDouble(),
              color: AppColors.scoutGreen,
            ),
            const SizedBox(width: 1),
            Container(
              width: 4,
              height: (exp / maxV * 48).clamp(0, 48).toDouble(),
              color: AppColors.tigerGold,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$month',
          style: const TextStyle(fontSize: 7.5, color: AppColors.textGray),
        ),
      ],
    );
  }

  Widget _eventsCard() {
    final events = (_a['events'] as Map?)?.cast<String, dynamic>() ?? {};
    final list = events.values.toList();
    list.sort(
      (x, y) => ((y['income'] as num) + (y['expense'] as num)).compareTo(
        (x['income'] as num) + (x['expense'] as num),
      ),
    );
    if (list.isEmpty) {
      return const Text(
        '행사로 분류된 거래가 없습니다.',
        style: TextStyle(fontSize: 12, color: AppColors.textGray),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: list.take(15).map((e) {
            final inc = (e['income'] as num?) ?? 0;
            final exp = (e['expense'] as num?) ?? 0;
            final yrs = (e['years'] as Map?)?.cast<String, dynamic>() ?? {};
            final yrKeys = yrs.keys.toList()..sort((x, y) => y.compareTo(x));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.celebration,
                        size: 15,
                        color: AppColors.purple,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: MarqueeText(
                          '${e['event'] ?? '미분류'}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      Text(
                        '+${_shortWon(inc)} / -${_shortWon(exp)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
                if (yrKeys.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 21, bottom: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: yrKeys.map((yy) {
                        final amt = (yrs[yy] ?? 0) as num;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.purple.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            '$yy ${_shortWon(amt)}',
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: AppColors.textGray,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _filesCard(List files) {
    if (files.isEmpty) {
      return const Text(
        '분석된 파일이 없습니다.',
        style: TextStyle(fontSize: 12, color: AppColors.textGray),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: files.map((f) {
            final m = (f as Map).cast<String, dynamic>();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file,
                    size: 15,
                    color: AppColors.scoutGreen,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: MarqueeText(
                      '${m['name']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  Text(
                    '${m['rows']}건',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _footnote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.10)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: AppColors.textGray),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              '※ 항상 가장 최신의 은행거래내역 파일을 기준으로 분석합니다. '
              '우측 상단 새로고침으로 원본 폴더를 다시 스캔할 수 있습니다. '
              '미분류 거래는 분류규칙(별칭) 등록 후 재분석하면 정확도가 올라갑니다.',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textGray,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: AppColors.purple.withValues(alpha: 0.15)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: _building ? null : () => _buildPdf(),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('A4 보고서 보기', style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '내보내기 (엑셀·PDF·워드·PPT·CSV·TXT·JPG)',
              onPressed: _building ? null : _openExportSheet,
              icon: const Icon(Icons.ios_share),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: '공유',
              onPressed: _building ? null : _share,
              icon: const Icon(Icons.share_outlined),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: '저장',
              onPressed: _building ? null : _save,
              icon: const Icon(Icons.download),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String s) => Row(
    children: [
      Container(width: 4, height: 16, color: AppColors.tigerGold),
      const SizedBox(width: 8),
      Text(
        s,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          color: AppColors.textDark,
        ),
      ),
    ],
  );

  // ---- helpers ----
  String _wonComma(num v) {
    final neg = v < 0;
    final s = v.abs().round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${neg ? '-' : ''}$b';
  }

  String _shortWon(num v) {
    final n = v.abs();
    final sign = v < 0 ? '-' : '';
    if (n >= 100000000) return '$sign${(n / 100000000).toStringAsFixed(1)}억원';
    if (n >= 10000) return '$sign${(n / 10000).round()}만원';
    return '$sign${_wonComma(n)}원';
  }
}
