import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_state.dart';
import '../services/doc_pdf.dart';
import '../services/file_save.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';

/// 로그 확인 — 전체 회원 접속·열람 기록 (마스터 전용).
///
/// 요구사항(p.11): 회원접속기록은 마스터만 열람 가능.
///  · 로그인/열람 이벤트를 최신순으로 통합 표시
///  · 역할(마스터/관리자/인가자/비인가자)·구분(본인/타인)·기기·IP 표시
///  · 이벤트/역할/검색 필터 + 출력(PDF)·공유·CSV 내보내기
///  · 개별 삭제 / 선택 삭제 / 전체 삭제(마스터 전용)
class AccessLogScreen extends StatefulWidget {
  const AccessLogScreen({super.key});

  @override
  State<AccessLogScreen> createState() => _AccessLogScreenState();
}

class _AccessLogScreenState extends State<AccessLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _busy = false;

  /// 이벤트 필터: '' 전체 | 'login' 로그인 | 'view' 열람.
  String _eventFilter = '';

  /// 역할 필터: '' 전체 | master/app/personal/guest.
  String _tierFilter = '';

  /// 검색어(이름·신원·기기·IP).
  final TextEditingController _qCtl = TextEditingController();

  /// 선택 삭제 모드.
  bool _selectMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _qCtl.dispose();
    super.dispose();
  }

  String _key(Map<String, dynamic> l) =>
      '${l['ts'] ?? ''}\u0000${l['ident'] ?? ''}\u0000${l['event'] ?? ''}';

  List<Map<String, dynamic>> get _filtered {
    final q = _qCtl.text.trim().toLowerCase();
    return _logs.where((l) {
      final ev = '${l['event'] ?? ''}';
      if (_eventFilter.isNotEmpty && ev != _eventFilter) return false;
      final tier = '${l['tier'] ?? ''}';
      if (_tierFilter.isNotEmpty && tier != _tierFilter) return false;
      if (q.isNotEmpty) {
        final hay = [
          l['name'],
          l['who'],
          l['ident'],
          l['viewer'],
          l['device'],
          l['ip'],
          l['role'],
        ].map((e) => '${e ?? ''}').join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (!state.isMaster) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final logs = await state.fetchAllAccessLogs(limit: 500);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
      _selected.clear();
    });
  }

  // ---------------- 삭제 ----------------
  Future<void> _deleteOne(Map<String, dynamic> log) async {
    final ok = await _confirm('이 기록 1건을 삭제할까요?');
    if (ok != true) return;
    final done = await context.read<AppState>().deleteMemberAccessLog(
      mode: 'one',
      ts: '${log['ts'] ?? ''}',
      number: '${log['ident'] ?? ''}',
    );
    if (!mounted) return;
    _snack(done ? '삭제했습니다' : '삭제 실패');
    if (done) await _load();
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await _confirm('선택한 기록 ${_selected.length}건을 삭제할까요?');
    if (ok != true) return;
    final items = <Map<String, dynamic>>[];
    for (final l in _logs) {
      if (_selected.contains(_key(l))) {
        items.add({'ts': '${l['ts'] ?? ''}', 'ident': '${l['ident'] ?? ''}'});
      }
    }
    final done = await context.read<AppState>().deleteMemberAccessLog(
      mode: 'bulk',
      items: items,
    );
    if (!mounted) return;
    _snack(done ? '선택한 ${items.length}건을 삭제했습니다' : '삭제 실패');
    if (done) {
      setState(() {
        _selectMode = false;
        _selected.clear();
      });
      await _load();
    }
  }

  Future<void> _deleteAll() async {
    final ok = await _confirm('전체 접속 기록을 모두 삭제할까요? 이 작업은 되돌릴 수 없습니다.');
    if (ok != true) return;
    final done = await context.read<AppState>().deleteMemberAccessLog(
      mode: 'all',
    );
    if (!mounted) return;
    _snack(done ? '전체 접속 기록을 삭제했습니다' : '삭제 실패');
    if (done) await _load();
  }

  Future<bool?> _confirm(String msg) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('접속 기록 삭제'),
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.taegeukRed),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------- 출력 / 공유 / 내보내기 ----------------
  static pw.Font? _reg;
  static pw.Font? _bold;

  Future<void> _ensureFonts() async {
    _reg ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Regular-s.ttf'),
    );
    _bold ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Bold-s.ttf'),
    );
  }

  List<List<String>> _rows() => [
    for (final l in _filtered)
      [
        '${l['ts'] ?? ''}',
        l['self'] == true ? '본인' : '타인',
        '${l['event'] ?? ''}' == 'view' ? '열람' : '로그인',
        '${l['role'] ?? l['tier'] ?? ''}',
        '${l['name'] ?? ''}',
        '${l['viewer'] ?? ''}',
        '${l['device'] ?? ''}',
        '${l['ip'] ?? ''}',
      ],
  ];

  Future<Uint8List> _pdf() async {
    await _ensureFonts();
    final reg = _reg!;
    final bold = _bold!;
    final doc = pw.Document();
    final ink = PdfColor.fromInt(0xFF2A2A2A);
    final gray = PdfColor.fromInt(0xFF7A7A7A);
    final accent = PdfColor.fromInt(0xFF5B2C8D);
    final rows = _rows();
    doc.addPage(
      pw.MultiPage(
        pageTheme: tsakPdfPageTheme(
          format: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
        ),
        footer: (ctx) => tsakPdfFooter(
          pageNumber: ctx.pageNumber,
          pagesCount: ctx.pagesCount,
          left: '한국범스카우트중앙회 · 마스터 전용',
          font: reg,
        ),
        build: (ctx) => [
          pw.Text(
            'TSAK 회원 접속·열람 기록',
            style: pw.TextStyle(font: bold, fontSize: 16, color: accent),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '한국범스카우트중앙회 · 마스터 전용',
            style: pw.TextStyle(font: reg, fontSize: 8, color: gray),
          ),
          pw.SizedBox(height: 10),
          pw.Container(height: 0.8, color: accent),
          pw.SizedBox(height: 8),
          pw.Text(
            '총 ${rows.length}건 · 출력일 '
            '${DateTime.now().toString().substring(0, 16)}',
            style: pw.TextStyle(font: reg, fontSize: 8, color: gray),
          ),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headers: const ['일시', '구분', '이벤트', '역할', '대상', '열람자', '기기', 'IP'],
            data: rows,
            headerStyle: pw.TextStyle(
              font: bold,
              fontSize: 8,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(color: accent),
            cellStyle: pw.TextStyle(font: reg, fontSize: 7.5, color: ink),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3),
              ),
            ),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 3,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            '※ 본 기록은 마스터만 열람할 수 있으며, 개인정보 보호를 위해 관리하십시오.',
            style: pw.TextStyle(font: reg, fontSize: 7.5, color: gray),
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdf();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      _snack('인쇄를 열 수 없습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdf();
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          mimeType: 'application/pdf',
          name: 'TSAK_접속기록.pdf',
        ),
      ], subject: 'TSAK 회원 접속·열람 기록');
    } catch (e) {
      _snack('공유를 열 수 없습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final b = StringBuffer();
      b.writeln('일시,구분,이벤트,역할,대상,열람자,기기,IP');
      for (final r in _rows()) {
        String q(Object? v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
        b.writeln(r.map(q).join(','));
      }
      final name = '회원접속기록_${DateTime.now().toString().substring(0, 10)}';
      final bytes = utf8.encode('\uFEFF${b.toString()}');
      final choose = await askSaveLocation(context, info: '접속기록 (CSV)');
      if (choose == null) return;
      final ok = await saveFileNamed(
        bytes: Uint8List.fromList(bytes),
        filename: '$name.csv',
        mime: 'text/csv;charset=utf-8',
        mimeType: MimeType.csv,
        choose: choose,
      );
      if (mounted) _snack(ok ? 'CSV 파일로 내보냈습니다' : '저장이 취소되었습니다');
    } catch (e) {
      _snack('내보내기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return Scaffold(
        appBar: TsakAppBar(title: const Text('로그 확인')),
        body: const Center(child: Text('마스터 권한이 필요합니다')),
      );
    }
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('로그 확인'),
        actions: [
          const AppHomeEmblem(size: 22),
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _header(),
              _filters(),
              if (_selectMode) _selectBar(filtered),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? const Center(
                        child: Text(
                          '접속 기록이 없습니다',
                          style: TextStyle(color: AppColors.textGray),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _logTile(filtered[i], i),
                        ),
                      ),
              ),
            ],
          ),
          BusyOverlay(
            visible: _loading || _busy,
            title: _busy ? '문서를 만드는 중입니다' : '접속기록을 불러오는 중입니다',
            lines: _busy
                ? const [
                    '선택한 접속기록으로 문서를 생성하고 있습니다...',
                    'PDF·엑셀 파일로 만드는 중...',
                    '저장·공유 준비 중...',
                  ]
                : const [
                    'NAS 서버에서 접속 기록을 가져오는 중...',
                    '최신 기록으로 정리하는 중...',
                    '잠시만 기다려 주세요...',
                  ],
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: AppColors.purple.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                size: 15,
                color: AppColors.lifetimeGold,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '접속·열람 기록은 마스터만 열람할 수 있습니다. 기기·시각·IP가 기록됩니다.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.lifetimeGold,
                  ),
                ),
              ),
              Text(
                '총 ${_logs.length}건',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy || _filtered.isEmpty ? null : _print,
                icon: const Icon(Icons.print, size: 16),
                label: const Text('출력'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || _filtered.isEmpty ? null : _share,
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('공유'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || _filtered.isEmpty ? null : _exportCsv,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('CSV'),
              ),
              if (_filtered.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _selectMode
                        ? Colors.white
                        : AppColors.purple,
                    backgroundColor: _selectMode ? AppColors.purple : null,
                    side: BorderSide(
                      color: AppColors.purple.withValues(alpha: 0.6),
                    ),
                  ),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _selectMode = !_selectMode;
                          _selected.clear();
                        }),
                  icon: Icon(
                    _selectMode ? Icons.close : Icons.checklist,
                    size: 16,
                  ),
                  label: Text(_selectMode ? '선택 취소' : '선택 삭제'),
                ),
              if (_logs.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.taegeukRed,
                  ),
                  onPressed: _busy ? null : _deleteAll,
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text('전체 삭제'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qCtl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '이름 · 신원 · 기기 · IP 검색',
                    hintStyle: const TextStyle(fontSize: 12.5),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  '전체',
                  _eventFilter.isEmpty,
                  () => setState(() => _eventFilter = ''),
                ),
                _chip(
                  '로그인',
                  _eventFilter == 'login',
                  () => setState(() => _eventFilter = 'login'),
                ),
                _chip(
                  '열람',
                  _eventFilter == 'view',
                  () => setState(() => _eventFilter = 'view'),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 1,
                  height: 20,
                  color: AppColors.textGray.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 10),
                _chip(
                  '전체 역할',
                  _tierFilter.isEmpty,
                  () => setState(() => _tierFilter = ''),
                ),
                _chip(
                  '마스터',
                  _tierFilter == 'master',
                  () => setState(() => _tierFilter = 'master'),
                ),
                _chip(
                  '관리자',
                  _tierFilter == 'app',
                  () => setState(() => _tierFilter = 'app'),
                ),
                _chip(
                  '인가자',
                  _tierFilter == 'personal',
                  () => setState(() => _tierFilter = 'personal'),
                ),
                _chip(
                  '비인가자',
                  _tierFilter == 'guest',
                  () => setState(() => _tierFilter = 'guest'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.purple : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.purple
                  : AppColors.purple.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.purpleDark,
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectBar(List<Map<String, dynamic>> filtered) {
    final allSel =
        filtered.isNotEmpty &&
        filtered.every((l) => _selected.contains(_key(l)));
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '선택 ${_selected.length}건 / 표시 ${filtered.length}건',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.purple,
              ),
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    if (allSel) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(filtered.map(_key));
                    }
                  }),
            child: Text(
              allSel ? '전체 해제' : '전체 선택',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _busy || _selected.isEmpty ? null : _deleteSelected,
            icon: const Icon(Icons.delete, size: 15),
            label: Text('선택 ${_selected.length}건 삭제'),
          ),
        ],
      ),
    );
  }

  Widget _logTile(Map<String, dynamic> l, int i) {
    final role = '${l['role'] ?? l['tier'] ?? ''}';
    final device = '${l['device'] ?? ''}';
    final ts = '${l['ts'] ?? ''}';
    final ip = '${l['ip'] ?? ''}';
    final tier = '${l['tier'] ?? ''}';
    final name = '${l['name'] ?? ''}';
    final isSelf = l['self'] == true;
    final isView = '${l['event'] ?? ''}' == 'view';
    final viewer = '${l['viewer'] ?? ''}'.trim();
    Color c = AppColors.purple;
    if (tier == 'master') c = AppColors.lifetimeGold;
    if (tier == 'app') c = AppColors.taegeukBlue;
    if (tier == 'guest') c = AppColors.scoutGreen;
    final Color rowColor = isSelf ? AppColors.taegeukRed : c;
    final bool selected = _selectMode && _selected.contains(_key(l));
    final Widget tile = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.purple.withValues(alpha: 0.10)
            : (isSelf
                  ? rowColor.withValues(alpha: 0.07)
                  : (i.isEven ? const Color(0xFFF8F6FC) : Colors.white)),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected
              ? AppColors.purple
              : (isSelf
                    ? rowColor.withValues(alpha: 0.45)
                    : AppColors.purple.withValues(alpha: 0.12)),
          width: selected ? 1.6 : (isSelf ? 1.4 : 1),
        ),
      ),
      child: Row(
        children: [
          if (_selectMode)
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              activeColor: AppColors.purple,
              onChanged: (_) => setState(() {
                if (selected) {
                  _selected.remove(_key(l));
                } else {
                  _selected.add(_key(l));
                }
              }),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: rowColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              role.isEmpty ? '-' : role,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: rowColor,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: (isView ? AppColors.purple : AppColors.scoutGreen)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isView ? '열람' : '로그인',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isView ? AppColors.purple : AppColors.scoutGreen,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 12,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      ts,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelf ? FontWeight.w900 : FontWeight.w700,
                        color: isSelf
                            ? AppColors.taegeukRed
                            : AppColors.textDark,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.taegeukRed,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          '본인 접속',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (name.isNotEmpty || (isView && viewer.isNotEmpty)) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        isView ? Icons.visibility : Icons.person,
                        size: 12,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          isView
                              ? '대상 ${name.isEmpty ? '(${l['ident'] ?? ''})' : name}'
                                    '${viewer.isNotEmpty ? '  ·  열람자 $viewer' : ''}'
                              : (name.isEmpty
                                    ? '(${l['who'] ?? l['ident'] ?? ''})'
                                    : name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelf
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelf
                                ? AppColors.taegeukRed
                                : AppColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.devices_other,
                      size: 12,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        device,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelf
                              ? FontWeight.w800
                              : FontWeight.w400,
                          color: isSelf
                              ? AppColors.taegeukRed
                              : AppColors.textDark,
                        ),
                      ),
                    ),
                    if (ip.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.public,
                        size: 11,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        ip,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '이 기록 삭제',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: AppColors.taegeukRed,
            ),
            onPressed: () => _deleteOne(l),
          ),
        ],
      ),
    );
    if (!_selectMode) return tile;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() {
        if (selected) {
          _selected.remove(_key(l));
        } else {
          _selected.add(_key(l));
        }
      }),
      child: tile,
    );
  }
}
