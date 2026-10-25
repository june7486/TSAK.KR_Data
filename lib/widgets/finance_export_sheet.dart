import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'marquee_text.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:printing/printing.dart';

import '../services/file_save.dart';
import '../services/finance_export.dart';
import '../services/pdf_to_jpg.dart';
import '../theme/app_theme.dart';

/// 재무 데이터를 여러 파일포맷으로 출력하는 공용 시트.
///
/// 사용: `showFinanceExportSheet(context, data: ...)`
Future<void> showFinanceExportSheet(
  BuildContext context, {
  required FinanceExportData data,
  List<FinanceFormat> formats = const [
    // 규칙(#14): PDF → JPG → 엑셀 → PPT → 워드 (이후 CSV·TXT 보조).
    FinanceFormat.pdf,
    FinanceFormat.jpg,
    FinanceFormat.excel,
    FinanceFormat.ppt,
    FinanceFormat.word,
    FinanceFormat.csv,
    FinanceFormat.txt,
  ],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FinanceExportSheet(data: data, formats: formats),
  );
}

class _FinanceExportSheet extends StatefulWidget {
  const _FinanceExportSheet({required this.data, required this.formats});

  final FinanceExportData data;
  final List<FinanceFormat> formats;

  @override
  State<_FinanceExportSheet> createState() => _FinanceExportSheetState();
}

class _FinanceExportSheetState extends State<_FinanceExportSheet> {
  late FinanceFormat _format;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _format = widget.formats.first;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final d = widget.data;
    final tableInfo = d.tables
        .where((t) => !t.isEmpty)
        .map((t) => '${t.title}(${t.rows.length})')
        .join(' · ');
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.9),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.ios_share,
                        color: AppColors.purple,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MarqueeText(
                          d.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (d.subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        d.subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '포함: $tableInfo',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '출력 형식',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in widget.formats)
                        ChoiceChip(
                          label: Text(f.label),
                          selected: _format == f,
                          selectedColor: AppColors.purple,
                          labelStyle: TextStyle(
                            color: _format == f
                                ? Colors.white
                                : AppColors.textDark,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => setState(() => _format = f),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : _doExport,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download),
                    label: Text(_busy ? '생성 중...' : '출력 (파일 내려받기)'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _previewPdf,
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('PDF 미리보기/인쇄'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _copyCsv,
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('CSV 복사'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '※ 모든 형식은 동일한 재무 데이터(요약·연도별·인가자별·상세내역)를 담습니다.',
                    style: TextStyle(fontSize: 11, color: AppColors.textGray),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _doExport() async {
    final opt = await askSaveOption(context, info: '재무 보고서 (${_format.label})');
    if (opt == null) return; // 취소
    setState(() => _busy = true);
    try {
      final d = widget.data;
      final name = FinanceExportService.fileName(d, _format);
      Uint8List bytes;
      switch (_format) {
        case FinanceFormat.excel:
          bytes = FinanceExportService.buildExcel(d);
          break;
        case FinanceFormat.pdf:
          bytes = await FinanceExportService.buildPdf(d);
          break;
        case FinanceFormat.word:
          bytes = FinanceExportService.buildWord(d);
          break;
        case FinanceFormat.txt:
          bytes = FinanceExportService.buildTxt(d);
          break;
        case FinanceFormat.csv:
          bytes = FinanceExportService.buildCsv(d);
          break;
        case FinanceFormat.ppt:
          bytes = FinanceExportService.buildPpt(d);
          break;
        case FinanceFormat.jpg:
          bytes = await FinanceExportService.buildPdf(d);
          break;
      }
      if (_format == FinanceFormat.jpg) {
        // 규칙: 실제 .jpg 파일로 저장(기존 PNG → JPG 통일).
        final jpg = await pdfToJpg(bytes);
        await saveFileOption(
          bytes: jpg,
          filename: '$name.jpg',
          mime: 'image/jpeg',
          mimeType: MimeType.jpeg,
          option: opt,
        );
      } else {
        await saveFileOption(
          bytes: bytes,
          filename: '$name.${_format.extension}',
          mime: _mimeStr(_format),
          mimeType: _mimeOf(_format),
          option: opt,
        );
      }
      _snack('출력 완료: $name.${_format.extension}');
    } catch (e) {
      _snack('출력 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewPdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await FinanceExportService.buildPdf(widget.data);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      _snack('미리보기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyCsv() async {
    try {
      final bytes = FinanceExportService.buildCsv(widget.data);
      // BOM 제거 후 텍스트 복사
      final text = String.fromCharCodes(
        bytes.length >= 3 ? bytes.sublist(3) : bytes,
      );
      await Clipboard.setData(ClipboardData(text: text));
      _snack('CSV 내용을 복사했습니다');
    } catch (e) {
      _snack('복사 실패: $e');
    }
  }

  MimeType _mimeOf(FinanceFormat f) {
    switch (f) {
      case FinanceFormat.excel:
        return MimeType.microsoftExcel;
      case FinanceFormat.pdf:
        return MimeType.pdf;
      case FinanceFormat.word:
        return MimeType.microsoftWord;
      case FinanceFormat.txt:
        return MimeType.text;
      case FinanceFormat.csv:
        return MimeType.csv;
      case FinanceFormat.jpg:
        return MimeType.jpeg;
      case FinanceFormat.ppt:
        return MimeType.microsoftPresentation;
    }
  }

  /// 웹 다운로드용 MIME 문자열.
  String _mimeStr(FinanceFormat f) {
    switch (f) {
      case FinanceFormat.excel:
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case FinanceFormat.pdf:
        return 'application/pdf';
      case FinanceFormat.word:
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case FinanceFormat.txt:
        return 'text/plain;charset=utf-8';
      case FinanceFormat.csv:
        return 'text/csv;charset=utf-8';
      case FinanceFormat.jpg:
        return 'image/jpeg';
      case FinanceFormat.ppt:
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
