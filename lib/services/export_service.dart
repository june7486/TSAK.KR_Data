import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/member.dart';

enum ExportFormat { excel, pdf, word, txt, jpg }

extension ExportFormatX on ExportFormat {
  String get label {
    switch (this) {
      case ExportFormat.excel:
        return '엑셀 (XLSX)';
      case ExportFormat.pdf:
        return 'PDF';
      case ExportFormat.word:
        return '워드 (DOC)';
      case ExportFormat.txt:
        return '텍스트 (TXT)';
      case ExportFormat.jpg:
        return '이미지 (JPG)';
    }
  }

  String get extension {
    switch (this) {
      case ExportFormat.excel:
        return 'xlsx';
      case ExportFormat.pdf:
        return 'pdf';
      case ExportFormat.word:
        return 'doc';
      case ExportFormat.txt:
        return 'txt';
      case ExportFormat.jpg:
        return 'jpg';
    }
  }

  String get mime {
    switch (this) {
      case ExportFormat.excel:
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case ExportFormat.pdf:
        return 'application/pdf';
      case ExportFormat.word:
        return 'application/msword';
      case ExportFormat.txt:
        return 'text/plain';
      case ExportFormat.jpg:
        return 'image/jpeg';
    }
  }
}

/// 명단 내보내기 서비스
class ExportService {
  static const headers = [
    '인가번호',
    '성명',
    '연맹',
    '소속대',
    '인가일',
    '핸드폰',
    '이메일',
    'ATAS',
    '주소',
    '활동',
    '메모',
    '평생회원',
    '회비연도',
    '행사참가',
  ];

  static List<String> rowOf(Member m) => [
    m.number,
    m.name,
    m.league,
    m.unit,
    m.date,
    m.phone,
    m.email,
    m.atasNo,
    m.address,
    m.activity,
    m.memo,
    m.lifetimeMember ? 'O' : '',
    m.paidYears.join(', '),
    m.attendedEvents.join(', '),
  ];

  /// 엑셀 XLSX 바이트 생성
  static Uint8List buildExcel(List<Member> members) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (final m in members) {
      sheet.appendRow(rowOf(m).map((v) => TextCellValue(v)).toList());
    }
    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// PDF 바이트 생성 (표 형식)
  static Future<Uint8List> buildPdf(
    List<Member> members, {
    String title = '한국범스카우트 중앙회 인가자 명단',
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '총 ${members.length}명  |  출력일: ${_today()}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Divider(),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headers: const ['인가번호', '성명', '연맹', '소속대', '인가일', '핸드폰'],
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            data: members
                .map(
                  (m) => [m.number, m.name, m.league, m.unit, m.date, m.phone],
                )
                .toList(),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// 워드(DOC) — HTML 기반 .doc (Word에서 정상 열림)
  static Uint8List buildWord(
    List<Member> members, {
    String title = '한국범스카우트 중앙회 인가자 명단',
  }) {
    final buf = StringBuffer();
    buf.write('<html xmlns:w="urn:schemas-microsoft-com:office:word">');
    buf.write('<head><meta charset="utf-8"></head><body>');
    buf.write('<h2>$title</h2>');
    buf.write('<p>총 ${members.length}명 | 출력일: ${_today()}</p>');
    buf.write(
      '<table border="1" cellspacing="0" cellpadding="4" '
      'style="border-collapse:collapse;font-size:10pt">',
    );
    buf.write('<tr style="background:#5B2C8D;color:#fff">');
    for (final h in headers) {
      buf.write('<th>$h</th>');
    }
    buf.write('</tr>');
    for (final m in members) {
      buf.write('<tr>');
      for (final v in rowOf(m)) {
        buf.write('<td>${_escape(v)}</td>');
      }
      buf.write('</tr>');
    }
    buf.write('</table></body></html>');
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  /// 텍스트
  static Uint8List buildTxt(
    List<Member> members, {
    String title = '한국범스카우트 중앙회 인가자 명단',
  }) {
    final buf = StringBuffer();
    buf.writeln(title);
    buf.writeln('총 ${members.length}명 | 출력일: ${_today()}');
    buf.writeln('=' * 60);
    for (final m in members) {
      buf.writeln(
        '[${m.number}] ${m.name}  ${m.league}  ${m.unit}  ${m.date}  ${m.phone}',
      );
    }
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${_pad2(now.month)}-${_pad2(now.day)}';
  }

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
