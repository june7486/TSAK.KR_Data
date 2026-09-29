/// 실제 **PDF 파일 바이트** 생성기 (규칙: 기본 출력 = PDF).
///
/// ## 왜 필요한가 (요구 p.28: "파일 생성 자체가 안 됨")
/// 그동안 "PDF 저장"은 새 창에 **인쇄 대화상자**를 띄우는 방식이었다.
/// 브라우저·OS 환경에 따라 인쇄창이 막히거나, 사용자가 "PDF로 저장"을 못 찾아
/// **실제 파일이 만들어지지 않았다.** 이 파일은 `pdf` 패키지로 **진짜 .pdf 바이트**를
/// 만들어 사용자 폴더에 **다운로드**시킨다(인쇄창 불필요).
///
/// `print_doc.dart` 의 [DocMeta]·[DocCell] 표 데이터를 그대로 받아, 인쇄용 HTML
/// (`buildMujiDoc`)과 **동일한 무인양품 스타일**의 PDF를 생성한다.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'print_doc.dart';

class DocPdf {
  static pw.Font? _regular;
  static pw.Font? _bold;

  /// 한글 폰트(나눔고딕) — 최초 1회 로드 후 캐시.
  static Future<void> _ensureFonts() async {
    _regular ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Regular-s.ttf'),
    );
    _bold ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Bold-s.ttf'),
    );
  }

  // MUJI 저채도 팔레트 (print_doc 과 일치)
  static const _ink = PdfColor.fromInt(0xFF3A3A3A);
  static const _title = PdfColor.fromInt(0xFF4A4A48);
  static const _gray = PdfColor.fromInt(0xFF8C877E);
  static const _line = PdfColor.fromInt(0xFFEDEAE3);
  static const _strong = PdfColor.fromInt(0xFF4A4A48);

  static PdfColor _hex(String h) {
    var s = h.replaceAll('#', '').trim();
    if (s.length == 6) s = 'FF$s';
    final v = int.tryParse(s, radix: 16) ?? 0xFF7C6A9C;
    return PdfColor.fromInt(v);
  }

  static String _stamp() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${p(d.month)}.${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  /// 표 데이터로 **실제 PDF 바이트**를 만든다. (A4 세로 기본)
  static Future<Uint8List> build({
    required DocMeta meta,
    List<String> columns = const [],
    List<List<DocCell>> rows = const [],
    List<String> summary = const [],
    String footerLeft = '한국범스카우트중앙회',
    bool landscape = false,
  }) async {
    await _ensureFonts();
    final reg = _regular!;
    final bold = _bold!;
    final now = meta.createdAt.isNotEmpty ? meta.createdAt : _stamp();

    final base = pw.TextStyle(font: reg, fontSize: 9, color: _ink);
    final baseBold = pw.TextStyle(font: bold, fontSize: 9, color: _ink);

    final doc = pw.Document();

    // ── 헤더 메타(작은 글씨) ──
    final facts = <MapEntry<String, String>>[
      if (meta.author.trim().isNotEmpty) MapEntry('생성자', meta.author),
      MapEntry('생성일', now),
      ...meta.extra.entries,
    ];

    final header = <pw.Widget>[
      pw.Text(
        '한국범스카우트중앙회 · TSAK',
        style: pw.TextStyle(font: reg, fontSize: 8, color: _gray),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        meta.title,
        style: pw.TextStyle(font: bold, fontSize: 17, color: _title),
      ),
      if (meta.subtitle.trim().isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(
            meta.subtitle,
            style: pw.TextStyle(font: reg, fontSize: 10, color: _gray),
          ),
        ),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 7),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: _line),
            bottom: pw.BorderSide(color: _line),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (meta.description.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Text(
                  meta.description,
                  style: pw.TextStyle(font: reg, fontSize: 9.5, color: _ink),
                ),
              ),
            pw.Wrap(
              spacing: 22,
              runSpacing: 2,
              children: facts
                  .map(
                    (e) => pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: '${e.key} ',
                            style: pw.TextStyle(
                              font: bold,
                              fontSize: 8.5,
                              color: _gray,
                            ),
                          ),
                          pw.TextSpan(
                            text: e.value,
                            style: pw.TextStyle(
                              font: reg,
                              fontSize: 8.5,
                              color: _gray,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 10),
    ];

    // ── 표 ──
    pw.Widget? table;
    if (columns.isNotEmpty || rows.isNotEmpty) {
      table = pw.Table(
        border: pw.TableBorder(
          horizontalInside: const pw.BorderSide(color: _line, width: 0.6),
        ),
        columnWidths: _defaultCols(columns.length),
        children: [
          if (columns.isNotEmpty)
            pw.TableRow(
              children: columns
                  .map(
                    (c) => pw.Padding(
                      padding: const pw.EdgeInsets.fromLTRB(6, 6, 6, 6),
                      child: pw.Text(
                        c,
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 9,
                          color: _strong,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          for (final r in rows)
            pw.TableRow(
              children: r
                  .map(
                    (c) => pw.Container(
                      padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
                      decoration: c.accent != null
                          ? pw.BoxDecoration(
                              border: pw.Border(
                                left: pw.BorderSide(
                                  color: _hex(c.accent!),
                                  width: 2.4,
                                ),
                              ),
                            )
                          : null,
                      child: pw.Column(
                        crossAxisAlignment: _cross(c.align),
                        children: [
                          pw.Text(
                            c.text,
                            style: c.bold ? baseBold : base,
                            textAlign: _align(c.align),
                          ),
                          if (c.sub != null && c.sub!.trim().isNotEmpty)
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(top: 1.5),
                              child: pw.Text(
                                c.sub!,
                                style: pw.TextStyle(
                                  font: reg,
                                  fontSize: 7.5,
                                  color: _gray,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      );
    }

    // ── 합계 ──
    pw.Widget? sumWidget;
    if (summary.isNotEmpty) {
      sumWidget = pw.Container(
        margin: const pw.EdgeInsets.only(top: 14),
        padding: const pw.EdgeInsets.only(top: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _strong, width: 1.4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: summary
              .map(
                (s) => pw.Text(
                  s,
                  style: pw.TextStyle(font: bold, fontSize: 10, color: _ink),
                ),
              )
              .toList(),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: (landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4),
        margin: const pw.EdgeInsets.fromLTRB(34, 36, 34, 34),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                footerLeft,
                style: pw.TextStyle(font: reg, fontSize: 7.5, color: _gray),
              ),
              pw.Text(
                '${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(font: reg, fontSize: 7.5, color: _gray),
              ),
            ],
          ),
        ),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                alignment: pw.Alignment.centerRight,
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  '${meta.title} (계속)',
                  style: pw.TextStyle(font: reg, fontSize: 8, color: _gray),
                ),
              ),
        build: (ctx) => [
          ...header,
          if (table != null) table,
          if (sumWidget != null) sumWidget,
        ],
      ),
    );

    return doc.save();
  }

  static Map<int, pw.TableColumnWidth> _defaultCols(int n) {
    if (n <= 0) return const {};
    final m = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < n; i++) {
      m[i] = i == 0 ? const pw.FlexColumnWidth(2.0) : pw.FlexColumnWidth(1);
    }
    return m;
  }

  static pw.TextAlign _align(String a) {
    switch (a) {
      case 'center':
        return pw.TextAlign.center;
      case 'right':
        return pw.TextAlign.right;
      default:
        return pw.TextAlign.left;
    }
  }

  static pw.CrossAxisAlignment _cross(String a) {
    switch (a) {
      case 'center':
        return pw.CrossAxisAlignment.center;
      case 'right':
        return pw.CrossAxisAlignment.end;
      default:
        return pw.CrossAxisAlignment.start;
    }
  }

  /// 표 없이 제목·본문(줄 목록)만 있는 간단 PDF.
  static Future<Uint8List> buildText({
    required DocMeta meta,
    required List<String> lines,
    String footerLeft = '한국범스카우트중앙회',
  }) => build(meta: meta, summary: lines, footerLeft: footerLeft);

  /// 문자열 표(헤더/행)로 **실제 PDF**를 만든다.
  ///
  /// 여러 화면(판매대장·재고·공여 등)이 표 데이터를 `List<List<String>>`
  /// 형태로 이미 갖고 있어, 이를 그대로 받아 MUJI 스타일 PDF로 변환한다.
  /// 첫 열에 좌측 컬러 바를 자동 적용한다.
  static Future<Uint8List> buildSimple({
    required DocMeta meta,
    List<String> columns = const [],
    List<List<String>> rows = const [],
    List<String> summary = const [],
    String footerLeft = '한국범스카우트중앙회',
    bool landscape = false,
    String align = 'left',
  }) {
    final docRows = rows.asMap().entries.map((e) {
      final ac = kMujiAccents[e.key % kMujiAccents.length];
      return e.value.asMap().entries.map((c) {
        return DocCell(
          c.value,
          accent: c.key == 0 ? ac : null,
          align: c.key == 0 ? 'left' : align,
        );
      }).toList();
    }).toList();
    return build(
      meta: meta,
      columns: columns,
      rows: docRows,
      summary: summary,
      footerLeft: footerLeft,
      landscape: landscape,
    );
  }

  /// 줄바꿈 텍스트([text])를 문단 목록으로 렌더한 **실제 PDF**를 만든다.
  ///
  /// 표 구조가 없는 리포트(요약 텍스트)를 빠르게 PDF 파일로 저장할 때 사용한다.
  static Future<Uint8List> buildFromText({
    required DocMeta meta,
    required String text,
    String footerLeft = '한국범스카우트중앙회',
  }) {
    final lines = text.split('\n').map((l) => l.trimRight()).toList();
    return build(meta: meta, summary: lines, footerLeft: footerLeft);
  }
}
