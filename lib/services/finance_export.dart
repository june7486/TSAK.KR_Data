import 'dart:convert';
import 'print_doc.dart';
import 'doc_pdf.dart';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 재무 출력 포맷 (명단 출력과 동일한 구성 + 재무 전용 CSV)
enum FinanceFormat { excel, pdf, word, txt, jpg, ppt, csv }

extension FinanceFormatX on FinanceFormat {
  String get label {
    switch (this) {
      case FinanceFormat.excel:
        return '엑셀 (XLSX)';
      case FinanceFormat.pdf:
        return 'PDF';
      case FinanceFormat.word:
        return '워드 (DOC)';
      case FinanceFormat.txt:
        return '텍스트 (TXT)';
      case FinanceFormat.jpg:
        return '이미지 (JPG)';
      case FinanceFormat.ppt:
        return '파워포인트 (PPTX)';
      case FinanceFormat.csv:
        return 'CSV (엑셀호환)';
    }
  }

  String get extension {
    switch (this) {
      case FinanceFormat.excel:
        return 'xlsx';
      case FinanceFormat.pdf:
        return 'pdf';
      case FinanceFormat.word:
        return 'doc';
      case FinanceFormat.txt:
        return 'txt';
      case FinanceFormat.jpg:
        return 'jpg';
      case FinanceFormat.ppt:
        return 'pptx';
      case FinanceFormat.csv:
        return 'csv';
    }
  }
}

/// 재무 출력에서 다루는 사람이 읽는 "표" 단위.
/// 한 화면에 여러 표(요약/연도별/개인별/내역)를 담을 수 있다.
class FinanceTable {
  FinanceTable({
    required this.title,
    this.headers = const [],
    List<List<String>>? rows,
    this.totals,
    this.note = '',
  }) : rows = rows ?? [];

  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  /// 합계 행(있으면 마지막에 굵게 표시)
  final List<String>? totals;
  final String note;

  bool get isEmpty => headers.isEmpty && rows.isEmpty;
  int get columnCount => headers.isNotEmpty
      ? headers.length
      : (rows.isNotEmpty ? rows.first.length : (totals?.length ?? 0));

  /// 모든 행(합계 포함) — 출력용
  List<List<String>> get allRows => [
    ...rows,
    if (totals != null && totals!.isNotEmpty) totals!,
  ];
}

/// 재무 출력 묶음 (제목 + 여러 표)
class FinanceExportData {
  FinanceExportData({
    required this.title,
    required this.tables,
    this.subtitle = '',
    this.footnote = '',
  });

  final String title;
  final String subtitle;
  final List<FinanceTable> tables;
  final String footnote;

  bool get isEmpty => tables.every((t) => t.isEmpty);
}

/// 재무 다중포맷 출력 서비스
///
/// 명단 내보내기(ExportService)와 동일한 포맷(엑셀·PDF·워드·TXT·PPT + JPG)에
/// 재무 전용 CSV 를 더해 동일한 데이터를 여러 파일포맷으로 출력한다.
class FinanceExportService {
  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${_p(n.month)}-${_p(n.day)}';
  }

  static String _p(int v) => v.toString().padLeft(2, '0');

  static String _nowStamp() {
    final n = DateTime.now();
    return '${n.year}${_p(n.month)}${_p(n.day)}_${_p(n.hour)}${_p(n.minute)}';
  }

  /// 파일 기본명 (확장자별로 호출측에서 붙임)
  static String fileName(FinanceExportData d, FinanceFormat f) =>
      'TSAK_재무_${_sanitize(d.title)}_${_nowStamp()}';

  static String _sanitize(String s) => s
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .trim();

  // --------------------------------------------------------------------------
  //  엑셀 (XLSX) — 표마다 시트 1개
  // --------------------------------------------------------------------------
  static Uint8List buildExcel(FinanceExportData d) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    var first = true;
    for (final t in d.tables) {
      if (t.isEmpty) continue;
      final name = _sheetName(t.title);
      if (first && defaultSheet != null) {
        excel.rename(defaultSheet, name);
        first = false;
      } else {
        excel[name];
      }
      final sheet = excel[name];
      if (t.note.isNotEmpty) {
        sheet.appendRow([TextCellValue(t.note)]);
        sheet.appendRow([TextCellValue('')]);
      }
      if (t.headers.isNotEmpty) {
        sheet.appendRow(t.headers.map((h) => TextCellValue(h)).toList());
      }
      for (final r in t.rows) {
        sheet.appendRow(r.map((c) => TextCellValue(c)).toList());
      }
      if (t.totals != null && t.totals!.isNotEmpty) {
        sheet.appendRow(t.totals!.map((c) => TextCellValue(c)).toList());
      }
      sheet.appendRow([TextCellValue('')]);
    }
    if (first) {
      // 모든 표가 비어있을 때
      final sheet = excel[defaultSheet ?? 'Sheet1'];
      sheet.appendRow([TextCellValue(d.title)]);
      sheet.appendRow([TextCellValue('출력일 ${_today()}')]);
    }
    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  static String _sheetName(String s) {
    var n = s.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
    if (n.isEmpty) n = '시트';
    return n.length > 28 ? n.substring(0, 28) : n;
  }

  // --------------------------------------------------------------------------
  //  PDF (표 형식, 한글 폰트 임베드)
  // --------------------------------------------------------------------------
  static Future<Uint8List> buildPdf(FinanceExportData d) async {
    pw.Font? base;
    pw.Font? bold;
    try {
      base = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NanumGothic-Regular-s.ttf'),
      );
      bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NanumGothic-Bold-s.ttf'),
      );
    } catch (_) {
      base = null;
      bold = null;
    }
    final theme = (base != null)
        ? pw.ThemeData.withFont(base: base, bold: bold ?? base)
        : null;

    final doc = pw.Document();
    final tables = d.tables.where((t) => !t.isEmpty).toList();
    doc.addPage(
      pw.MultiPage(
        pageTheme: tsakPdfPageTheme(
          format: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(22),
        ).copyWith(theme: theme),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              d.title,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            if (d.subtitle.isNotEmpty)
              pw.Text(d.subtitle, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 2),
            pw.Text(
              '출력일: ${_today()}  |  한국범스카우트중앙회',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Divider(),
          ],
        ),
        footer: (ctx) => tsakPdfFooter(
          pageNumber: ctx.pageNumber,
          pagesCount: ctx.pagesCount,
        ),
        build: (ctx) {
          final out = <pw.Widget>[];
          for (final t in tables) {
            out.add(pw.SizedBox(height: 6));
            out.add(
              pw.Text(
                t.title,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            );
            if (t.note.isNotEmpty) {
              out.add(pw.Text(t.note, style: const pw.TextStyle(fontSize: 8)));
            }
            out.add(pw.SizedBox(height: 3));
            if (t.headers.isNotEmpty && t.allRows.isNotEmpty) {
              out.add(
                pw.TableHelper.fromTextArray(
                  headers: t.headers,
                  data: t.allRows,
                  headerStyle: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  cellStyle: const pw.TextStyle(fontSize: 7.5),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey300,
                  ),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellHeight: 16,
                ),
              );
            } else {
              out.add(
                pw.Text('(자료 없음)', style: const pw.TextStyle(fontSize: 8)),
              );
            }
            out.add(pw.SizedBox(height: 10));
          }
          if (d.footnote.isNotEmpty) {
            out.add(pw.SizedBox(height: 6));
            out.add(
              pw.Text(d.footnote, style: const pw.TextStyle(fontSize: 8)),
            );
          }
          return out;
        },
      ),
    );
    return doc.save();
  }

  // --------------------------------------------------------------------------
  //  워드 (DOC, HTML 기반)
  // --------------------------------------------------------------------------
  static Uint8List buildWord(FinanceExportData d) {
    final buf = StringBuffer();
    buf.write('<html xmlns:w="urn:schemas-microsoft-com:office:word">');
    buf.write('<head><meta charset="utf-8"></head><body>');
    buf.write('<h2 style="font-family:$kDocFontStack">${_esc(d.title)}</h2>');
    if (d.subtitle.isNotEmpty) {
      buf.write('<p>${_esc(d.subtitle)}</p>');
    }
    buf.write('<p>출력일: ${_today()} | 한국범스카우트중앙회</p>');
    for (final t in d.tables) {
      if (t.isEmpty) continue;
      buf.write('<h3 style="font-family:$kDocFontStack">${_esc(t.title)}</h3>');
      if (t.note.isNotEmpty) buf.write('<p>${_esc(t.note)}</p>');
      buf.write(
        '<table border="1" cellspacing="0" cellpadding="4" '
        'style="border-collapse:collapse;font-size:10pt;font-family:$kDocFontStack">',
      );
      // 머리행은 <thead> 로 — 페이지가 넘어가도 구분표가 반복된다.
      if (t.headers.isNotEmpty) {
        buf.write('<thead><tr style="background:#5B2C8D;color:#fff">');
        for (final h in t.headers) {
          buf.write('<th>${_esc(h)}</th>');
        }
        buf.write('</tr></thead>');
      }
      buf.write('<tbody>');
      for (final r in t.rows) {
        buf.write('<tr>');
        for (final c in r) {
          buf.write('<td>${_esc(c)}</td>');
        }
        buf.write('</tr>');
      }
      if (t.totals != null && t.totals!.isNotEmpty) {
        buf.write('<tr style="background:#f0eaf8;font-weight:bold">');
        for (final c in t.totals!) {
          buf.write('<td>${_esc(c)}</td>');
        }
        buf.write('</tr>');
      }
      buf.write('</tbody></table><br>');
    }
    if (d.footnote.isNotEmpty) buf.write('<p>${_esc(d.footnote)}</p>');
    buf.write('</body></html>');
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  // --------------------------------------------------------------------------
  //  텍스트 (TXT)
  // --------------------------------------------------------------------------
  static Uint8List buildTxt(FinanceExportData d) {
    final buf = StringBuffer();
    buf.writeln(d.title);
    if (d.subtitle.isNotEmpty) buf.writeln(d.subtitle);
    buf.writeln('출력일: ${_today()} | 한국범스카우트중앙회');
    buf.writeln('=' * 70);
    for (final t in d.tables) {
      if (t.isEmpty) continue;
      buf.writeln();
      buf.writeln('[${t.title}]');
      if (t.note.isNotEmpty) buf.writeln('  ${t.note}');
      if (t.headers.isNotEmpty) {
        buf.writeln('-' * 70);
        buf.writeln(t.headers.join(' | '));
        buf.writeln('-' * 70);
      }
      for (final r in t.rows) {
        buf.writeln(r.join(' | '));
      }
      if (t.totals != null && t.totals!.isNotEmpty) {
        buf.writeln('- ' * 35);
        buf.writeln(t.totals!.join(' | '));
      }
    }
    if (d.footnote.isNotEmpty) {
      buf.writeln();
      buf.writeln(d.footnote);
    }
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  // --------------------------------------------------------------------------
  //  CSV (엑셀 호환, 표마다 블록)
  // --------------------------------------------------------------------------
  static Uint8List buildCsv(FinanceExportData d) {
    final buf = StringBuffer();
    buf.writeln(_csvRow([d.title]));
    if (d.subtitle.isNotEmpty) buf.writeln(_csvRow([d.subtitle]));
    buf.writeln(_csvRow(['출력일', _today()]));
    for (final t in d.tables) {
      if (t.isEmpty) continue;
      buf.writeln();
      buf.writeln(_csvRow(['[${t.title}]']));
      if (t.note.isNotEmpty) buf.writeln(_csvRow([t.note]));
      if (t.headers.isNotEmpty) buf.writeln(_csvRow(t.headers));
      for (final r in t.rows) {
        buf.writeln(_csvRow(r));
      }
      if (t.totals != null && t.totals!.isNotEmpty) {
        buf.writeln(_csvRow(t.totals!));
      }
    }
    if (d.footnote.isNotEmpty) {
      buf.writeln();
      buf.writeln(_csvRow([d.footnote]));
    }
    // 엑셀 한글 깨짐 방지 BOM
    return Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(buf.toString()),
    ]);
  }

  static String _csvRow(List<String> cells) => cells.map(_csvCell).join(',');

  static String _csvCell(String s) {
    final v = s.replaceAll('"', '""');
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"$v"';
    }
    return v;
  }

  // --------------------------------------------------------------------------
  //  파워포인트 (PPTX) — 표마다 슬라이드 세트
  // --------------------------------------------------------------------------
  static Uint8List buildPpt(FinanceExportData d) {
    // 슬라이드 단위로 분해 (제목 1줄 + 표 최대 12행)
    final slides = <_SlideSpec>[];
    // 표지
    slides.add(_SlideSpec(title: d.title, subtitle: d.subtitle, grid: null));
    for (final t in d.tables) {
      if (t.isEmpty) continue;
      final heads = t.headers.isNotEmpty ? t.headers : <String>[];
      final body = <List<String>>[...t.rows];
      if (t.totals != null && t.totals!.isNotEmpty) body.add(t.totals!);
      const rowsPer = 12;
      if (body.isEmpty) {
        slides.add(_SlideSpec(title: t.title, subtitle: t.note, grid: null));
        continue;
      }
      for (var i = 0; i < body.length; i += rowsPer) {
        final chunk = body.sublist(
          i,
          (i + rowsPer > body.length) ? body.length : i + rowsPer,
        );
        final grid = <List<String>>[if (heads.isNotEmpty) heads, ...chunk];
        slides.add(
          _SlideSpec(
            title: t.title,
            subtitle: i == 0 ? t.note : '${t.title} (계속)',
            grid: grid,
          ),
        );
      }
    }
    return _buildPptx(slides);
  }

  static Uint8List _buildPptx(List<_SlideSpec> slides) {
    if (slides.isEmpty) {
      slides = [_SlideSpec(title: 'TSAK 재무', subtitle: '', grid: null)];
    }
    const slideW = 12192000;
    const slideH = 6858000;
    final buffer = _ZipBuilder();

    // [Content_Types].xml
    final ct = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
      )
      ..write(
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
      )
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write(
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>',
      )
      ..write(
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>',
      )
      ..write(
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>',
      )
      ..write(
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>',
      );
    for (var i = 0; i < slides.length; i++) {
      ct.write(
        '<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
    }
    ct.write('</Types>');
    buffer.add('[Content_Types].xml', ct.toString());

    buffer.add(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
          '</Relationships>',
    );

    final pres = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">',
      )
      ..write(
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>',
      )
      ..write('<p:sldIdLst>');
    for (var i = 0; i < slides.length; i++) {
      pres.write('<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>');
    }
    pres
      ..write('</p:sldIdLst>')
      ..write('<p:sldSz cx="$slideW" cy="$slideH"/>')
      ..write('<p:notesSz cx="6858000" cy="9144000"/>')
      ..write('</p:presentation>');
    buffer.add('ppt/presentation.xml', pres.toString());

    final presRels = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      )
      ..write(
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>',
      );
    for (var i = 0; i < slides.length; i++) {
      presRels.write(
        '<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>',
      );
    }
    presRels.write('</Relationships>');
    buffer.add('ppt/_rels/presentation.xml.rels', presRels.toString());

    buffer.add(
      'ppt/slideMasters/slideMaster1.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
          '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>'
          '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
          '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
          '</p:sldMaster>',
    );
    buffer.add(
      'ppt/slideMasters/_rels/slideMaster1.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>'
          '</Relationships>',
    );
    buffer.add(
      'ppt/slideLayouts/slideLayout1.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank">'
          '<p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>'
          '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
          '</p:sldLayout>',
    );
    buffer.add(
      'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
          '</Relationships>',
    );
    buffer.add(
      'ppt/theme/theme1.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office">'
          '<a:themeElements>'
          '<a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2><a:accent1><a:srgbClr val="5B2C8D"/></a:accent1><a:accent2><a:srgbClr val="D62828"/></a:accent2><a:accent3><a:srgbClr val="2E7D32"/></a:accent3><a:accent4><a:srgbClr val="1B4F9C"/></a:accent4><a:accent5><a:srgbClr val="F2B705"/></a:accent5><a:accent6><a:srgbClr val="7E4FB0"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme>'
          '<a:fontScheme name="Office"><a:majorFont><a:latin typeface="Malgun Gothic"/><a:ea typeface="Malgun Gothic"/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Malgun Gothic"/><a:ea typeface="Malgun Gothic"/><a:cs typeface=""/></a:minorFont></a:fontScheme>'
          '<a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>'
          '</a:themeElements></a:theme>',
    );

    for (var i = 0; i < slides.length; i++) {
      final s = slides[i];
      final spTree = StringBuffer();
      final titleText = s.subtitle.isNotEmpty
          ? '${s.title}  ·  ${s.subtitle}'
          : s.title;
      spTree.write(
        _textShape(
          2,
          titleText,
          500000,
          250000,
          slideW - 1000000,
          600000,
          2000,
        ),
      );
      if (s.grid != null && s.grid!.isNotEmpty) {
        final cols = s.grid!.first.length;
        final tableW = (slideW * 0.94).round();
        final startX = ((slideW - tableW) / 2).round();
        final colW = (tableW / (cols == 0 ? 1 : cols)).round();
        spTree.write(_tableShape(3, startX, 950000, colW, s.grid!));
      }
      buffer.add(
        'ppt/slides/slide${i + 1}.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
            '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
            '$spTree'
            '</p:spTree></p:cSld>'
            '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
            '</p:sld>',
      );
      buffer.add(
        'ppt/slides/_rels/slide${i + 1}.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
            '</Relationships>',
      );
    }
    return buffer.encode();
  }

  static String _textShape(
    int id,
    String text,
    int x,
    int y,
    int cx,
    int cy,
    int fontSize,
  ) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Title $id"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr lang="ko-KR" sz="$fontSize" b="1"><a:solidFill><a:srgbClr val="5B2C8D"/></a:solidFill></a:rPr><a:t>${_esc(text)}</a:t></a:r></a:p>'
        '</p:txBody></p:sp>';
  }

  static String _tableShape(
    int id,
    int x,
    int y,
    int colW,
    List<List<String>> grid,
  ) {
    const rowH = 300000;
    final buf = StringBuffer();
    final cols = grid.isEmpty ? 1 : grid.first.length;
    buf.write(
      '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="$id" name="Table $id"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="$x" y="$y"/><a:ext cx="${colW * cols}" cy="${rowH * grid.length}"/></p:xfrm>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">'
      '<a:tbl><a:tblPr firstRow="1"/><a:tblGrid>',
    );
    for (var c = 0; c < cols; c++) {
      buf.write('<a:gridCol w="$colW"/>');
    }
    buf.write('</a:tblGrid>');
    for (var r = 0; r < grid.length; r++) {
      buf.write('<a:tr h="$rowH">');
      for (var c = 0; c < grid[r].length; c++) {
        final isHead = r == 0;
        buf.write('<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p>');
        buf.write(
          '<a:r><a:rPr lang="ko-KR" sz="900"${isHead ? ' b="1"' : ''}><a:solidFill><a:srgbClr val="${isHead ? 'FFFFFF' : '1F1A2E'}"/></a:solidFill></a:rPr>',
        );
        buf.write('<a:t>${_esc(grid[r][c])}</a:t></a:r></a:p></a:txBody>');
        buf.write(
          '<a:tcPr><a:solidFill><a:srgbClr val="${isHead ? '5B2C8D' : 'FFFFFF'}"/></a:solidFill></a:tcPr></a:tc>',
        );
      }
      buf.write('</a:tr>');
    }
    buf.write('</a:tbl></a:graphicData></a:graphic></p:graphicFrame>');
    return buf.toString();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class _SlideSpec {
  _SlideSpec({required this.title, required this.subtitle, this.grid});
  final String title;
  final String subtitle;
  final List<List<String>>? grid;
}

/// 최소 ZIP(무압축 store) 작성기 — PPTX 패키징용 (재무 전용 복제본)
class _ZipBuilder {
  final List<_ZipEntry> _entries = [];
  final List<int> _out = [];

  void add(String name, String content) {
    _entries.add(_ZipEntry(name, utf8.encode(content)));
  }

  Uint8List encode() {
    final localOffsets = <int>[];
    final nameBytes = <List<int>>[];
    final crcList = <int>[];
    final sizeList = <int>[];

    for (final e in _entries) {
      localOffsets.add(_out.length);
      final nb = utf8.encode(e.name);
      nameBytes.add(nb);
      final crc = _crc32(e.data);
      crcList.add(crc);
      sizeList.add(e.data.length);
      _writeU32(0x04034b50);
      _writeU16(20);
      _writeU16(0x0800);
      _writeU16(0);
      _writeU16(0);
      _writeU16(0);
      _writeU32(crc);
      _writeU32(e.data.length);
      _writeU32(e.data.length);
      _writeU16(nb.length);
      _writeU16(0);
      _out.addAll(nb);
      _out.addAll(e.data);
    }

    final cdStart = _out.length;
    for (var i = 0; i < _entries.length; i++) {
      final nb = nameBytes[i];
      _writeU32(0x02014b50);
      _writeU16(20);
      _writeU16(20);
      _writeU16(0x0800);
      _writeU16(0);
      _writeU16(0);
      _writeU16(0);
      _writeU32(crcList[i]);
      _writeU32(sizeList[i]);
      _writeU32(sizeList[i]);
      _writeU16(nb.length);
      _writeU16(0);
      _writeU16(0);
      _writeU16(0);
      _writeU16(0);
      _writeU32(0);
      _writeU32(localOffsets[i]);
      _out.addAll(nb);
    }
    final cdSize = _out.length - cdStart;

    _writeU32(0x06054b50);
    _writeU16(0);
    _writeU16(0);
    _writeU16(_entries.length);
    _writeU16(_entries.length);
    _writeU32(cdSize);
    _writeU32(cdStart);
    _writeU16(0);

    return Uint8List.fromList(_out);
  }

  void _writeU16(int v) {
    _out.add(v & 0xff);
    _out.add((v >> 8) & 0xff);
  }

  void _writeU32(int v) {
    _out.add(v & 0xff);
    _out.add((v >> 8) & 0xff);
    _out.add((v >> 16) & 0xff);
    _out.add((v >> 24) & 0xff);
  }

  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc ^= b;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

class _ZipEntry {
  _ZipEntry(this.name, this.data);
  final String name;
  final List<int> data;
}
