import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/doc_pdf.dart';
import '../services/file_save.dart';
import '../services/output_formats.dart';
import '../services/pdf_to_jpg.dart';
import '../services/table_export.dart';
import '../theme/app_theme.dart';

/// 모든 출력 화면 공용 **실시간 출력 미리보기** 창.
///
/// ## 요구
/// "모든 창에서 출력시 첨부파일과 같이 줄간격 폰트 크기를 볼수 있도록 미리보기
///  창을 띄워서 결과물을 실시간으로 확인 후 출력내보낼 수 있도록 해줘"
///
/// 표 문서([TsakTableDoc])를 받아 MUJI PDF를 만들고, **첫 페이지를 이미지로
/// 렌더**해 보여준다. `줄간격 · 글자 크기 · 2줄 방지 · 가로 모드`를 바꾸면
/// **즉시 다시 그린다**(라이브). 확정하면 **PDF · 이미지(JPG) · 인쇄**로
/// 내보낸다. 아이폰 등은 저장 옵션 창([askSaveOption])을 거쳐 사진앱에 저장된다.
Future<void> showTsakOutputPreview(
  BuildContext context, {
  required TsakTableDoc doc,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _TsakOutputPreview(doc: doc),
  );
}

class _TsakOutputPreview extends StatefulWidget {
  const _TsakOutputPreview({required this.doc});

  final TsakTableDoc doc;

  @override
  State<_TsakOutputPreview> createState() => _TsakOutputPreviewState();
}

class _TsakOutputPreviewState extends State<_TsakOutputPreview> {
  /// 2줄 방지 — 켜면 모든 열이 줄바꿈하지 않고 한 줄로 나온다.
  bool _noWrap = false;

  /// 가로 모드 — 문서 기본 방향으로 시작.
  late bool _landscape = widget.doc.effectiveLandscape;

  /// 줄 간격(밀도) 배율.
  double _lineSpace = 1.1;

  /// 글자 크기 배율(1.0 = 기본).
  double _fontScale = 1.0;

  Future<Uint8List>? _previewFuture;
  String _previewKey = '';
  bool _busy = false;

  /// 옵션 서명 — 값이 바뀔 때만 미리보기를 다시 만든다.
  String get _key =>
      '$_landscape|$_noWrap|${_lineSpace.toStringAsFixed(2)}|'
      '${_fontScale.toStringAsFixed(2)}';

  String get _base => widget.doc.baseName(); // 예: TSAK_출력_게시판 출력

  /// 현재 옵션으로 PDF를 만든다.
  Future<Uint8List> _buildPdf() {
    final n = widget.doc.viewColumns.length;
    return DocPdf.buildSimple(
      meta: widget.doc.meta,
      columns: widget.doc.viewColumns,
      rows: widget.doc.viewRows,
      summary: widget.doc.summary,
      footerLeft: widget.doc.footerLeft,
      landscape: _landscape,
      scale: _fontScale,
      rowSpaceMul: _lineSpace,
      // 문서가 지정한 항목별 두줄방지(effectiveNoWrapCols)를 존중하고,
      //  전역 토글(_noWrap)이 켜지면 모든 열을 한 줄로 출력한다.
      noWrapCols: _noWrap
          ? {for (var i = 0; i < n; i++) i}
          : widget.doc.effectiveNoWrapCols,
    );
  }

  /// 미리보기용 — PDF 첫 페이지를 JPG로 래스터화한 바이트.
  Future<Uint8List> _makePreview() async {
    final pdf = await _buildPdf();
    return pdfToJpg(pdf, dpi: 110, quality: 82);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 1500)),
    );
  }

  /// PDF·이미지 내보내기(아이폰 등은 저장 옵션 창을 거친다).
  Future<void> _save(TsakOutputFormat fmt) async {
    if (_busy) return;
    final opt = await askSaveOption(
      context,
      info: '${widget.doc.title} (${fmt.label})',
    );
    if (opt == null) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      if (fmt == TsakOutputFormat.jpg) {
        final jpg = await pdfToJpg(pdf, dpi: 150, quality: 90);
        await saveFileOption(
          bytes: jpg,
          filename: '$_base.jpg',
          mime: 'image/jpeg',
          option: opt,
        );
      } else {
        await saveFileOption(
          bytes: pdf,
          filename: '$_base.pdf',
          mime: 'application/pdf',
          option: opt,
        );
      }
      _snack('${widget.doc.title} ${fmt.label} 내보내기를 시작했습니다');
    } catch (e) {
      _snack('내보내기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 인쇄 — OS 인쇄 대화상자(웹 포함).
  Future<void> _print() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      await Printing.layoutPdf(onLayout: (_) async => pdf);
    } catch (e) {
      _snack('인쇄 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 옵션이 바뀌면 미리보기를 다시 만든다(값이 그대로면 캐시 재사용).
    if (_key != _previewKey) {
      _previewKey = _key;
      _previewFuture = _makePreview();
    }

    final previewHeight = MediaQuery.of(context).size.height * 0.44;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: const Color(0xFFF3F1EC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    color: AppColors.purple,
                    size: 20,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      widget.doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purpleDark,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(left: 27),
                child: Text(
                  '출력 미리보기 · 줄간격·글자 크기를 바꾸면 즉시 반영됩니다',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ),
              const SizedBox(height: 8),
              // ── 미리보기 화면(첫 페이지) ──
              Container(
                width: double.infinity,
                height: previewHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD8D3CA)),
                ),
                clipBehavior: Clip.antiAlias,
                child: FutureBuilder<Uint8List>(
                  future: _previewFuture,
                  builder: (c, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      );
                    }
                    if (snap.hasError || snap.data == null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '미리보기를 만들 수 없습니다\n${snap.error ?? ''}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textGray,
                            ),
                          ),
                        ),
                      );
                    }
                    return InteractiveViewer(
                      maxScale: 5,
                      child: Image.memory(
                        snap.data!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // ── 옵션: 2줄 방지 · 가로 모드 ──
              Row(
                children: [
                  Expanded(
                    child: _switchCell(
                      '2줄 방지',
                      _noWrap,
                      (v) => setState(() => _noWrap = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _switchCell(
                      '가로 모드',
                      _landscape,
                      (v) => setState(() => _landscape = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              _sliderCell(
                '줄간격',
                _lineSpace,
                0.7,
                1.6,
                _lineSpace.toStringAsFixed(1),
                (v) => setState(() => _lineSpace = v),
              ),
              _sliderCell(
                '글자 크기',
                _fontScale,
                0.8,
                1.5,
                '${(_fontScale * 10).round()} pt',
                (v) => setState(() => _fontScale = v),
              ),
              const SizedBox(height: 8),
              // ── 내보내기: PDF · 이미지 · 인쇄 ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _save(TsakOutputFormat.pdf),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                      label: const Text('PDF'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _save(TsakOutputFormat.jpg),
                      icon: const Icon(Icons.image_outlined, size: 17),
                      label: const Text('이미지'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                      ),
                      onPressed: _busy ? null : _print,
                      icon: const Icon(Icons.print_outlined, size: 17),
                      label: const Text('인쇄'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchCell(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8D3CA)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            thumbColor: const WidgetStatePropertyAll(Colors.white),
            trackColor: WidgetStatePropertyAll(
              value ? AppColors.purple : const Color(0xFFCFC9C0),
            ),
            trackOutlineColor: WidgetStatePropertyAll(
              value ? AppColors.purple : const Color(0xFFCFC9C0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliderCell(
    String label,
    double v,
    double min,
    double max,
    String val,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textGray,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: v.clamp(min, max),
            min: min,
            max: max,
            activeColor: AppColors.purple,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            val,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.purpleDark,
            ),
          ),
        ),
      ],
    );
  }
}
