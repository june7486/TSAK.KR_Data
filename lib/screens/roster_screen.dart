import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../services/roster_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';

/// 행사 참가자 명단 — 앱 내부에서 열리는 MUJI풍 미리보기 + 출력/공유.
/// (외부 브라우저로 튕기지 않아 뒤로가기가 정상 동작한다)
class RosterScreen extends StatefulWidget {
  const RosterScreen({
    super.key,
    required this.title,
    required this.year,
    required this.period,
    required this.place,
    required this.desc,
    required this.attendees,
  });

  final String title;
  final String year;
  final String period;
  final String place;
  final String desc;
  final List<Map<String, dynamic>> attendees;

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  bool _busy = false;

  String get _period =>
      widget.period.isNotEmpty ? widget.period : widget.year;

  Future<Uint8List> _pdfBytes() => RosterService.buildPdf(
        title: widget.title,
        period: _period,
        place: widget.place,
        desc: widget.desc,
        attendees: widget.attendees,
      );

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }

  // ---- 실제 인쇄 ----
  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdfBytes();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      _snack('인쇄를 열 수 없습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- 공유 ----
  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdfBytes();
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: '${widget.title}_참가자명단.pdf',
          ),
        ],
        subject: '${widget.title} 참가자 명단',
        text: '${widget.title} 참가자 명단 (${widget.attendees.length}명)',
      );
    } catch (e) {
      _snack('공유할 수 없습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- 파일 저장 (포맷 선택) ----
  Future<void> _saveAs() async {
    final fmt = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('출력 파일 형식 선택',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
            _fmtTile(ctx, 'pdf', Icons.picture_as_pdf, 'PDF 문서', '인쇄·보관용 (권장)'),
            _fmtTile(ctx, 'word', Icons.description, 'Word 문서', '.doc (편집 가능)'),
            _fmtTile(ctx, 'excel', Icons.table_chart, 'Excel 문서', '.xls (표 데이터)'),
            _fmtTile(ctx, 'txt', Icons.notes, '텍스트', '.txt (간단 목록)'),
          ],
        ),
      ),
    );
    if (fmt == null) return;
    await _doSave(fmt);
  }

  Widget _fmtTile(
      BuildContext ctx, String val, IconData icon, String t, String sub) {
    return ListTile(
      leading: Icon(icon, color: AppColors.purple),
      title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 11.5)),
      onTap: () => Navigator.pop(ctx, val),
    );
  }

  Future<void> _doSave(String fmt) async {
    setState(() => _busy = true);
    try {
      final name = '${widget.title}_참가자명단';
      Uint8List bytes;
      String ext;
      MimeType mime;
      if (fmt == 'pdf') {
        bytes = await _pdfBytes();
        ext = 'pdf';
        mime = MimeType.pdf;
      } else if (fmt == 'txt') {
        bytes = Uint8List.fromList(
            RosterService.buildText(
              title: widget.title,
              period: _period,
              place: widget.place,
              desc: widget.desc,
              attendees: widget.attendees,
            ).codeUnits);
        ext = 'txt';
        mime = MimeType.text;
      } else {
        final content = RosterService.buildWord(
          title: widget.title,
          period: _period,
          place: widget.place,
          desc: widget.desc,
          attendees: widget.attendees,
        );
        bytes = Uint8List.fromList(content.codeUnits);
        ext = fmt == 'excel' ? 'xls' : 'doc';
        mime = fmt == 'excel' ? MimeType.microsoftExcel : MimeType.microsoftWord;
      }
      await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        ext: ext,
        mimeType: mime,
      );
      _snack('저장했습니다 ($ext)');
    } catch (e) {
      _snack('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '뒤로',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('참가자 명단'),
        actions: [
          IconButton(
            tooltip: '인쇄',
            icon: const Icon(Icons.print),
            onPressed: _busy ? null : _print,
          ),
          IconButton(
            tooltip: '공유',
            icon: const Icon(Icons.ios_share),
            onPressed: _busy ? null : _share,
          ),
          const AppHomeEmblem(size: 24, adminHomeOnly: true),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _header(),
              const SizedBox(height: 20),
              _table(),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  '· 접속 V = 사진폴더 접근 이력',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  /// MUJI풍 헤더 — 큰 제목 + 얇은 액센트 바 + 정보
  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Image.asset(
                'assets/images/tsak_emblem.png',
                width: 44,
                height: 44,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(width: 46, height: 3, color: AppColors.purple),
          const SizedBox(height: 16),
          _metaRow('기간', _period),
          if (widget.place.isNotEmpty) _metaRow('장소', widget.place),
          _metaRow('참가', '${widget.attendees.length}명'),
          if (widget.desc.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.desc,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textGray),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textGray)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
          ),
        ],
      ),
    );
  }

  Widget _table() {
    if (widget.attendees.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(30),
        alignment: Alignment.center,
        child: const Text('참가자가 없습니다',
            style: TextStyle(color: AppColors.textGray)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(const Color(0xFFF6F4F1)),
          headingTextStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.purple,
          ),
          dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textDark),
          horizontalMargin: 12,
          columnSpacing: 18,
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('접속')),
            DataColumn(label: Text('이름')),
            DataColumn(label: Text('소속')),
            DataColumn(label: Text('성별')),
            DataColumn(label: Text('연락처')),
            DataColumn(label: Text('메일')),
            DataColumn(label: Text('항목')),
          ],
          rows: [
            for (var i = 0; i < widget.attendees.length; i++)
              DataRow(cells: [
                DataCell(Text('${i + 1}',
                    style: const TextStyle(color: AppColors.textGray))),
                DataCell(_accessCell(widget.attendees[i])),
                DataCell(Text('${widget.attendees[i]['name'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text('${widget.attendees[i]['unit'] ?? ''}',
                    style: const TextStyle(color: AppColors.textGray))),
                DataCell(Text('${widget.attendees[i]['gender'] ?? ''}')),
                DataCell(Text('${widget.attendees[i]['phone'] ?? ''}')),
                DataCell(Text('${widget.attendees[i]['email'] ?? ''}',
                    style: const TextStyle(color: AppColors.textGray))),
                DataCell(Text(_rolesText(widget.attendees[i]))),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _accessCell(Map<String, dynamic> a) {
    final v = a['visited'] == true;
    if (!v) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCCCCCC)),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.scoutGreen,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('V',
          style: TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }

  String _rolesText(Map<String, dynamic> a) {
    final roles = (a['roles'] as List?)?.map((e) => '$e').toList() ?? [];
    return roles.join(', ');
  }

  Widget _bottomBar() {
    return Material(
      color: Colors.white,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _busy ? null : _print,
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('인쇄',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.taegeukBlue,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('공유',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.taegeukBlue,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _busy ? null : _saveAs,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('출력/저장'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
