import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// 회원 접속 로그 — 마스터 전용.
///
/// 요구사항:
///  · 개인 페이지 하단에 최근 100건까지 표시
///  · 접속기기이름·시각·IP·역할 등 구체 정보 표시
///  · 출력 / 공유 / 파일로 내보내기 버튼
///  · 각 로그마다 삭제 버튼
class MemberAccessLogSection extends StatefulWidget {
  const MemberAccessLogSection({super.key, required this.member});

  final Member member;

  @override
  State<MemberAccessLogSection> createState() => _MemberAccessLogSectionState();
}

class _MemberAccessLogSectionState extends State<MemberAccessLogSection> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (!state.isMaster) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final logs = await state.fetchMemberAccessLog(widget.member.loginId);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  String get _title => '${widget.member.name} (${widget.member.loginId})';

  Future<void> _deleteOne(Map<String, dynamic> log) async {
    final ok = await _confirm('이 접속 기록 1건을 삭제할까요?');
    if (ok != true) return;
    final done = await context.read<AppState>().deleteMemberAccessLog(
          mode: 'one',
          ts: '${log['ts'] ?? ''}',
          number: widget.member.loginId,
        );
    if (!mounted) return;
    _snack(done ? '삭제했습니다' : '삭제 실패');
    if (done) await _load();
  }

  Future<void> _deleteAll() async {
    final ok = await _confirm(
        '${widget.member.name} 님의 접속 기록을 모두(최근 100건 대상) 삭제할까요?');
    if (ok != true) return;
    final done = await context.read<AppState>().deleteMemberAccessLog(
          mode: 'member',
          number: widget.member.loginId,
        );
    if (!mounted) return;
    _snack(done ? '회원 접속 기록을 삭제했습니다' : '삭제 실패');
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
    _reg ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NanumGothic-Regular-s.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NanumGothic-Bold-s.ttf'));
  }

  Future<Uint8List> _pdf() async {
    await _ensureFonts();
    final reg = _reg!;
    final bold = _bold!;
    final doc = pw.Document();
    final ink = PdfColor.fromInt(0xFF2A2A2A);
    final gray = PdfColor.fromInt(0xFF7A7A7A);
    final accent = PdfColor.fromInt(0xFF5B2C8D);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Text('TSAK 회원 접속 기록',
              style: pw.TextStyle(font: bold, fontSize: 16, color: accent)),
          pw.SizedBox(height: 2),
          pw.Text('한국범스카우트중앙회 · 마스터 전용',
              style: pw.TextStyle(font: reg, fontSize: 8, color: gray)),
          pw.SizedBox(height: 10),
          pw.Container(height: 0.8, color: accent),
          pw.SizedBox(height: 8),
          pw.Text(_title, style: pw.TextStyle(font: bold, fontSize: 11, color: ink)),
          pw.Text('총 ${_logs.length}건 · 출력일 '
              '${DateTime.now().toString().substring(0, 16)}',
              style: pw.TextStyle(font: reg, fontSize: 8, color: gray)),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headers: const ['일시', '역할', '기기', 'IP'],
            data: [
              for (final l in _logs)
                [
                  '${l['ts'] ?? ''}',
                  '${l['role'] ?? l['tier'] ?? ''}',
                  '${l['device'] ?? ''}',
                  '${l['ip'] ?? ''}',
                ],
            ],
            headerStyle: pw.TextStyle(font: bold, fontSize: 8.5, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: accent),
            cellStyle: pw.TextStyle(font: reg, fontSize: 8, color: ink),
            rowDecoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3))),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          ),
          pw.SizedBox(height: 12),
          pw.Text('※ 본 기록은 마스터만 열람할 수 있으며, 개인정보 보호를 위해 관리하십시오.',
              style: pw.TextStyle(font: reg, fontSize: 7.5, color: gray)),
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
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'application/pdf', name: '회원접속기록_${widget.member.number.isEmpty ? widget.member.loginId : widget.member.number}.pdf')],
        subject: 'TSAK 회원 접속 기록 — ${widget.member.name}',
      );
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
      b.writeln('일시,역할,기기,IP,UA');
      for (final l in _logs) {
        String q(Object? v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
        b.writeln(
            [q(l['ts']), q(l['role'] ?? l['tier']), q(l['device']), q(l['ip']), q(l['ua'])]
                .join(','));
      }
      final name =
          '회원접속기록_${widget.member.name}_${DateTime.now().toString().substring(0, 10)}';
      // 엑셀 한글 깨짐 방지를 위해 UTF-8 BOM 을 붙인다.
      final bytes = utf8.encode('\uFEFF${b.toString()}');
      await FileSaver.instance.saveFile(
        name: name,
        bytes: Uint8List.fromList(bytes),
        ext: 'csv',
        mimeType: MimeType.csv,
      );
      if (mounted) _snack('CSV 파일로 내보냈습니다');
    } catch (e) {
      _snack('내보내기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 19, color: AppColors.purple),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('회원 접속 기록 (최근 100건)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
                IconButton(
                  tooltip: '새로고침',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.tigerGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: AppColors.lifetimeGold),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '접속 기록은 마스터만 열람할 수 있습니다. 접속기기·시각·IP가 기록됩니다.',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.lifetimeGold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 출력 / 공유 / 내보내기 / 전체삭제
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || _logs.isEmpty ? null : _print,
                  icon: const Icon(Icons.print, size: 17),
                  label: const Text('출력'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _logs.isEmpty ? null : _share,
                  icon: const Icon(Icons.ios_share, size: 17),
                  label: const Text('공유'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _logs.isEmpty ? null : _exportCsv,
                  icon: const Icon(Icons.download, size: 17),
                  label: const Text('파일로 내보내기'),
                ),
                if (_logs.isNotEmpty)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.taegeukRed),
                    onPressed: _busy ? null : _deleteAll,
                    icon: const Icon(Icons.delete_sweep, size: 17),
                    label: const Text('기록 전체 삭제'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text('접속 기록이 없습니다',
                      style: TextStyle(color: AppColors.textGray, fontSize: 12.5)),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _logs.length,
                itemBuilder: (_, i) => _logTile(_logs[i], i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _logTile(Map<String, dynamic> l, int i) {
    final role = '${l['role'] ?? l['tier'] ?? ''}';
    final device = '${l['device'] ?? ''}';
    final ts = '${l['ts'] ?? ''}';
    final ip = '${l['ip'] ?? ''}';
    final tier = '${l['tier'] ?? ''}';
    Color c = AppColors.purple;
    if (tier == 'master') c = AppColors.lifetimeGold;
    if (tier == 'app') c = AppColors.taegeukBlue;
    if (tier == 'guest') c = AppColors.scoutGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: i.isEven ? const Color(0xFFF8F6FC) : Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(role.isEmpty ? '-' : role,
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 12, color: AppColors.textGray),
                    const SizedBox(width: 4),
                    Text(ts,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.devices_other, size: 12, color: AppColors.textGray),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(device,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textDark)),
                    ),
                    if (ip.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.public, size: 11, color: AppColors.textGray),
                      const SizedBox(width: 3),
                      Text(ip,
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.textGray)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '이 기록 삭제',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppColors.taegeukRed),
            onPressed: () => _deleteOne(l),
          ),
        ],
      ),
    );
  }
}
