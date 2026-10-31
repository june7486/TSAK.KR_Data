import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/doc_pdf.dart';
import '../services/extra_fields.dart';
import '../services/extra_output.dart';
import '../services/file_save.dart';
import '../services/output_formats.dart';
import '../services/pdf_to_jpg.dart';
import '../services/table_export.dart';
import '../services/table_options.dart';
import '../theme/app_theme.dart';

/// 추가입력 항목을 **미리보기에서 직접 켜고 끌 수 있게** 하기 위한 입력 정보.
///
/// ## 요구 (원문 2026-10-31)
/// > "출력 미리보기시에도 추가항목 선택할 수 있도록 하고 실시간으로 미리보며
/// >  출력 할 수 있도록 해줘"
///
/// [source] 는 문서의 행과 **1:1 로 대응하는** 참석자 원본 행 목록이다.
/// 미리보기 창에서 항목을 체크하면 [extraColumns] 로 열을 즉시 덧붙여 다시
/// 그리므로, "체크 → 바로 화면에 반영"이 된다.
class TsakExtraPick {
  const TsakExtraPick({required this.source, this.initial = const <String>{}});

  /// 참석자 원본 행(events.json attendees 와 동일 구조).
  final List<Map<String, dynamic>> source;

  /// 처음부터 켜 둘 항목 키([ExtraField.key]).
  final Set<String> initial;
}

/// 모든 출력 화면 공용 **실시간 출력 미리보기** 창.
///
/// ## 요구
/// "모든 창에서 출력시 첨부파일과 같이 줄간격 폰트 크기를 볼수 있도록 미리보기
///  창을 띄워서 결과물을 실시간으로 확인 후 출력내보낼 수 있도록 해줘"
///
/// 표 문서([TsakTableDoc])를 받아 MUJI PDF를 만들고, **첫 페이지를 이미지로
/// 렌더**해 보여준다. `줄간격 · 글자 크기 · 2줄 방지 · 가로 모드 · 두 단` 을
/// 바꾸면 **즉시 다시 그린다**(라이브). 확정하면 **PDF · 이미지(JPG) · 인쇄**로
/// 내보낸다. 아이폰 등은 저장 옵션 창([askSaveOption])을 거쳐 사진앱에 저장된다.
///
/// [extra] 를 주면 **추가입력 항목 선택 칩**이 나타나고, 고른 항목이 열로
/// 덧붙은 결과를 실시간으로 보여준다(원문은 그대로 두고 매번 새로 조립).
Future<void> showTsakOutputPreview(
  BuildContext context, {
  required TsakTableDoc doc,
  TsakExtraPick? extra,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _TsakOutputPreview(doc: doc, extra: extra),
  );
}

class _TsakOutputPreview extends StatefulWidget {
  const _TsakOutputPreview({required this.doc, this.extra});

  final TsakTableDoc doc;
  final TsakExtraPick? extra;

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

  /// 두 단(가로줄 추가) — 열을 위/아래로 쌓아 열당 폭을 두 배로.
  bool _twoBands = false;

  /// 셀 한 칸이 가질 수 있는 최대 줄 수 — null 이면 제한 없음.
  /// (요구 2026-10-31 2차) “항목이 너무 길어지면 이름하나당 2줄 이상”
  int? _cellLines;

  /// 추가입력 항목 선택(켜진 항목 키).
  late final Set<String> _extraKeys = <String>{...?widget.extra?.initial};

  Future<Uint8List>? _previewFuture;
  String _previewKey = '';
  bool _busy = false;

  /// 옵션 서명 — 값이 바뀔 때만 미리보기를 다시 만든다.
  String get _key =>
      '$_landscape|$_noWrap|${_lineSpace.toStringAsFixed(2)}|'
      '${_fontScale.toStringAsFixed(2)}|$_twoBands|${_cellLines ?? 0}|'
      '${(_extraKeys.toList()..sort()).join(',')}';

  String get _base => widget.doc.baseName(); // 예: TSAK_출력_게시판 출력

  /// 현재 옵션을 반영한 **최종 문서** — 추가항목 열이 덧붙은 결과.
  ///
  /// 매번 새로 조립하므로 원본 [TsakTableDoc] 은 절대 변하지 않는다
  /// (항목을 껐다 켜도 열이 중복되지 않는다).
  TsakTableDoc get _doc {
    final ex = widget.extra;
    if (ex == null || _extraKeys.isEmpty) return widget.doc;
    return extraColumns(
      widget.doc,
      source: ex.source,
      keys: _extraKeys,
    );
  }

  /// 현재 옵션으로 PDF를 만든다.
  Future<Uint8List> _buildPdf() {
    final d = _doc;
    final n = d.viewColumns.length;
    // 두 단 — 미리보기에서 켜면 옵션과 무관하게 강제로 2단.
    final bands = _twoBands
        ? () {
            final s = splitColumnBands(
              d.viewColumns,
              anchors: d.options?.bandAnchors ?? const <String>{},
            );
            return s.isSplit ? <List<int>>[s.first, s.second] : null;
          }()
        : d.effectiveBands;
    return DocPdf.buildSimple(
      meta: d.meta,
      columns: d.viewColumns,
      rows: d.viewRows,
      summary: d.summary,
      footerLeft: d.footerLeft,
      landscape: _landscape,
      scale: _fontScale,
      rowSpaceMul: _lineSpace,
      // 문서가 지정한 항목별 두줄방지(effectiveNoWrapCols)를 존중하고,
      //  전역 토글(_noWrap)이 켜지면 모든 열을 한 줄로 출력한다.
      noWrapCols: _noWrap
          ? {for (var i = 0; i < n; i++) i}
          : d.effectiveNoWrapCols,
      bands: bands,
      maxCellLines: _cellLines,
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

    final h = MediaQuery.of(context).size.height;
    final previewHeight = h * (widget.extra == null ? 0.40 : 0.32);

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: const Color(0xFFF3F1EC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: h * 0.92),
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
              Padding(
                padding: const EdgeInsets.only(left: 27),
                child: Text(
                  '출력 미리보기 · 항목·줄간격·글자 크기를 바꾸면 즉시 반영됩니다',
                  style: const TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ),
              const SizedBox(height: 6),
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
                          width: 24,
                          height: 24,
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
              const SizedBox(height: 8),
              // ── 옵션: 2줄 방지 · 두 단 · 가로 모드 ──
              Row(
                children: [
                  Expanded(
                    child: _switchCell(
                      '2줄 방지',
                      _noWrap,
                      (v) => setState(() => _noWrap = v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _switchCell(
                      '두 단',
                      _twoBands,
                      (v) => setState(() => _twoBands = v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _switchCell(
                      '가로 모드',
                      _landscape,
                      (v) => setState(() => _landscape = v),
                    ),
                  ),
                ],
              ),
              // ── 셀 줄 수 — 항목이 길 때 이름하나당 2줄 이상 허용 ──
              _linesCell(),
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
              // ── 추가입력 항목 선택 (있을 때만) ──
              if (widget.extra != null) ...[
                const SizedBox(height: 4),
                _extraPickBar(),
              ],
              const SizedBox(height: 6),
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

  /// 추가입력 항목 선택 줄 — 칩을 누르면 그 항목 열이 즉시 붙었다 빠진다.
  Widget _extraPickBar() {
    final src = widget.extra!.source;
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8D3CA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '추가항목',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_extraKeys.length}개 선택',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.purple,
                ),
              ),
              const Spacer(),
              Text(
                '값 있는 항목 ${ExtraFields.filledCount(
                  src.isEmpty ? const <String, dynamic>{} : src.first,
                )}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 30,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in ExtraFields.all) ...[
                    _extraChip(f),
                    const SizedBox(width: 5),
                  ],
                  _miniChip('전체', () {
                    setState(() => _extraKeys.addAll(ExtraFields.all.map((e) => e.key)));
                  }),
                  const SizedBox(width: 5),
                  _miniChip('해제', () => setState(_extraKeys.clear)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _extraChip(ExtraField f) {
    final on = _extraKeys.contains(f.key);
    final c = ExtraFields.colorOf(f.group);
    return InkWell(
      onTap: () => setState(() {
        if (on) {
          _extraKeys.remove(f.key);
        } else {
          _extraKeys.add(f.key);
        }
      }),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: on ? c : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: on ? c : const Color(0xFFD8D3CA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(f.icon, size: 12, color: on ? Colors.white : c),
            const SizedBox(width: 4),
            Text(
              f.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                color: on ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EDE6),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textGray,
        ),
      ),
    ),
  );

  /// 셀 줄 수 선택 — 자동/1줄/2줄/3줄.
  ///
  /// (요구 2026-10-31 2차) "항목이 너무 길어지면 이름하나당 2줄 이상을 넣도록 함"
  ///  · 자동 = 종전대로 폰트·폭을 맞춰 1줄 유지(좁으면 글씨가 작아짐)
  ///  · 2줄/3줄 = 그 줄 수만큼 접히도록 열 폭을 넉넉히 → **글씨가 안 깎인다**
  Widget _linesCell() {
    const opts = <int?>[null, 1, 2, 3];
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          const SizedBox(
            width: 58,
            child: Text(
              '셀 줄 수',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textGray,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (final v in opts) ...[
                  if (v != opts.first) const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _cellLines = v),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _cellLines == v
                              ? AppColors.purple
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _cellLines == v
                                ? AppColors.purple
                                : const Color(0xFFD8D3CA),
                          ),
                        ),
                        child: Text(
                          v == null ? '자동' : '$v줄',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _cellLines == v
                                ? Colors.white
                                : AppColors.textDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchCell(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 0),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
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
