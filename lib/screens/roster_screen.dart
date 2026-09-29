import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../services/file_save.dart';
import '../services/roster_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/scroll_arrows.dart';

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

  /// 파일명 규칙: {행사명}_참가자명부
  String get fileNameBase => '${title}_참가자명부';

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  bool _busy = false;

  // ---- 인쇄 항목 선택(항상: 인가번호·이름·연락처) ----
  bool _showEventFee = false; // 참가비 납부 여부
  bool _showLifetime = false; // 평생회원 여부
  bool _showYearFee = false; // 행사년도 연회비 납부 여부

  String get _period =>
      widget.period.isNotEmpty ? widget.period : widget.year;

  Future<Uint8List> _pdfBytes() => RosterService.buildPdf(
        title: widget.title,
        period: _period,
        place: widget.place,
        desc: widget.desc,
        attendees: widget.attendees,
        year: widget.year,
        showEventFee: _showEventFee,
        showLifetime: _showLifetime,
        showYearFee: _showYearFee,
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
            name: '${widget.fileNameBase}.pdf',
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
            _fmtTile(ctx, 'jpg', Icons.image_outlined, '이미지 (JPG)', '사진처럼 저장·공유'),
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
      final name = widget.fileNameBase; // {행사명}_참가자명부
      Uint8List bytes;
      String ext;
      MimeType mime;
      if (fmt == 'jpg') {
        // (요구 #17) 명단출력 JPG — PDF 첫 페이지를 이미지로 변환.
        bytes = await _jpgBytes();
        ext = 'jpg';
        mime = MimeType.jpeg;
      } else if (fmt == 'pdf') {
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
              year: widget.year,
              showEventFee: _showEventFee,
              showLifetime: _showLifetime,
              showYearFee: _showYearFee,
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
          year: widget.year,
          showEventFee: _showEventFee,
          showLifetime: _showLifetime,
          showYearFee: _showYearFee,
        );
        bytes = Uint8List.fromList(content.codeUnits);
        ext = fmt == 'excel' ? 'xls' : 'doc';
        mime = fmt == 'excel' ? MimeType.microsoftExcel : MimeType.microsoftWord;
      }
      // (요구 #17) 저장위치 확인 창 — 기본값 안내 후 확인 시 저장.
      final proceed = await _confirmSaveLocation(fmt);
      if (proceed != true) return;
      await saveBytes(
        bytes: bytes,
        name: name,
        ext: ext,
        mime: ext == 'xls'
            ? 'application/vnd.ms-excel'
            : (ext == 'doc' ? 'application/msword' : 'image/jpeg'),
        mimeType: mime,
      );
      _snack('저장했습니다 ($name.$ext)');
    } catch (e) {
      _snack('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// (요구 #17) 저장 위치 확인 창.
  ///  · 스마트폰: 사진(갤러리) 폴더  · PC: 다운로드 폴더 (기본값).
  ///  사용자가 [위치 선택]을 누르면 OS 저장 대화상자가 열린다.
  Future<bool?> _confirmSaveLocation(String fmt) {
    final isImage = fmt == 'jpg';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.save_alt, color: AppColors.purple, size: 30),
        title: const Text('저장 위치'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isImage
                  ? '스마트폰: 사진(갤러리) 폴더\nPC: 다운로드(Downloads) 폴더'
                  : '스마트폰·PC: 다운로드(Downloads) 폴더',
              style: const TextStyle(fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              '* 기본 저장 위치는 기기 기본 위치입니다. '
              '[위치 선택]을 누르면 저장 대화상자가 열려 위치를 고를 수 있습니다.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.folder_open, size: 17),
            label: const Text('위치 선택'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save, size: 17),
            label: const Text('저장'),
          ),
        ],
      ),
    );
  }

  /// 명단 PDF 첫 페이지를 JPG 바이트로 변환 (요구 #17).
  Future<Uint8List> _jpgBytes() async {
    final pdf = await _pdfBytes();
    final raster = await Printing.raster(pdf, dpi: 150).first;
    final rgba = raster.pixels; // RGBA8888
    final im = img.Image.fromBytes(
      width: raster.width,
      height: raster.height,
      bytes: rgba.buffer,
      numChannels: 4,
    );
    return img.encodeJpg(im, quality: 88);
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
            tooltip: '인쇄 항목 선택',
            icon: const Icon(Icons.checklist),
            onPressed: _busy ? null : _optionsSheet,
          ),
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
              const SizedBox(height: 12),
              _optionSummary(),
              const SizedBox(height: 12),
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
          _metaRow('파일', '${widget.fileNameBase}.pdf'),
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

  /// 인쇄 항목 요약 — 어떤 항목이 함께 인쇄되는지 한 줄로 표시.
  Widget _optionSummary() {
    final extras = <String>[
      if (_showEventFee) '참가비',
      if (_showLifetime) '평생회원',
      if (_showYearFee) '${widget.year.isNotEmpty ? '${widget.year}년 ' : ''}연회비',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.purple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '인가번호·이름·연락처는 항상 인쇄'
              '${extras.isEmpty ? ' (선택 항목 없음)' : ' · 추가: ${extras.join(', ')}'}',
              style: const TextStyle(fontSize: 12, color: AppColors.textDark),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
            ),
            onPressed: _optionsSheet,
            child: const Text('항목', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 항목 체크 패널(작게) — 열리는 바텀시트.
  void _optionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 2, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('인쇄 항목 선택',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '인가번호 · 이름 · 연락처는 항상 인쇄됩니다.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
                  ),
                ),
              ),
              _optTile(
                '참가비 납부 여부',
                _showEventFee,
                (v) {
                  setD(() => _showEventFee = v);
                  setState(() => _showEventFee = v);
                },
              ),
              _optTile(
                '평생회원 여부',
                _showLifetime,
                (v) {
                  setD(() => _showLifetime = v);
                  setState(() => _showLifetime = v);
                },
              ),
              _optTile(
                '${widget.year.isNotEmpty ? '${widget.year}년 ' : ''}연회비 납부 여부',
                _showYearFee,
                (v) {
                  setD(() => _showYearFee = v);
                  setState(() => _showYearFee = v);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optTile(String label, bool val, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      controlAffinity: ListTileControlAffinity.leading,
      value: val,
      onChanged: (v) => onChanged(v == true),
      title: Text(label, style: const TextStyle(fontSize: 13)),
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
    // 항상: 인가번호·이름·연락처 + 선택 컬럼
    final columns = <DataColumn>[
      const DataColumn(label: Text('#')),
      const DataColumn(label: Text('접속')),
      const DataColumn(label: Text('인가번호')),
      const DataColumn(label: Text('이름')),
      const DataColumn(label: Text('소속')),
      const DataColumn(label: Text('성별')),
      const DataColumn(label: Text('연락처')),
      const DataColumn(label: Text('메일')),
      const DataColumn(label: Text('항목')),
      if (_showEventFee) const DataColumn(label: Text('참가비')),
      if (_showLifetime) const DataColumn(label: Text('평생')),
      if (_showYearFee)
        DataColumn(
            label: Text('${widget.year.isNotEmpty ? '${widget.year}년 ' : ''}연회비')),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      clipBehavior: Clip.antiAlias,
      // PC 사용자를 위한 좌우 스크롤 화살표
      child: ScrollArrows(
        step: 220,
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
          columnSpacing: 14,
          columns: columns,
          rows: [
            for (var i = 0; i < widget.attendees.length; i++)
              DataRow(cells: [
                DataCell(Text('${i + 1}',
                    style: const TextStyle(color: AppColors.textGray))),
                DataCell(_accessCell(widget.attendees[i])),
                DataCell(Text(_num(widget.attendees[i]),
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('${widget.attendees[i]['name'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text('${widget.attendees[i]['unit'] ?? ''}',
                    style: const TextStyle(color: AppColors.textGray))),
                DataCell(Text('${widget.attendees[i]['gender'] ?? ''}')),
                DataCell(Text('${widget.attendees[i]['phone'] ?? ''}')),
                DataCell(Text('${widget.attendees[i]['email'] ?? ''}',
                    style: const TextStyle(color: AppColors.textGray))),
                DataCell(Text(_rolesText(widget.attendees[i]))),
                if (_showEventFee)
                  DataCell(_ynCell(widget.attendees[i]['eventFee'] == true)),
                if (_showLifetime)
                  DataCell(_ynCell(widget.attendees[i]['lifetime'] == true)),
                if (_showYearFee)
                  DataCell(_ynCell(widget.attendees[i]['yearFee'] == true)),
              ]),
          ],
        ),
      ),
    );
  }

  String _num(Map<String, dynamic> a) {
    final n = '${a['number'] ?? ''}'.trim();
    return n;
  }

  Widget _ynCell(bool v) {
    return Text(
      v ? 'O' : '',
      style: TextStyle(
        fontWeight: FontWeight.w800,
        color: v ? AppColors.purple : AppColors.textGray,
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
