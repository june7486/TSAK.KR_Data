import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 행사 참가자 명단 — 무인양품(MUJI)풍 미니멀 인쇄 문서 생성.
/// 엑셀/PDF/워드/텍스트 등 다양한 포맷으로 내보낼 수 있다.
class RosterService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  /// 한글 폰트(나눔고딕) 로드 — 최초 1회 캐시.
  static Future<void> _ensureFonts() async {
    _regular ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Regular.ttf'),
    );
    _bold ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Bold.ttf'),
    );
  }

  // 무인양품풍 절제된 색 팔레트
  static const _ink = PdfColor.fromInt(0xFF1F1A2E);
  static const _gray = PdfColor.fromInt(0xFF8A8A8A);
  static const _line = PdfColor.fromInt(0xFFE3E3E3);
  static const _accent = PdfColor.fromInt(0xFF5B2C8D);
  static const _softBg = PdfColor.fromInt(0xFFF6F4F1);

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// 참가자 명단 PDF 바이트 생성 (MUJI풍)
  static Future<Uint8List> buildPdf({
    required String title,
    required String period,
    required String place,
    required String desc,
    required List<Map<String, dynamic>> attendees,
    String org = '한국범스카우트중앙회 (TSAK)',
  }) async {
    await _ensureFonts();
    final reg = _regular!;
    final bold = _bold!;
    final doc = pw.Document();

    final base = pw.TextStyle(font: reg, fontSize: 9, color: _ink);
    final baseBold = pw.TextStyle(font: bold, fontSize: 9, color: _ink);

    pw.Widget metaRow(String label, String value) {
      if (value.trim().isEmpty) return pw.SizedBox();
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 44,
              child: pw.Text(label,
                  style: pw.TextStyle(font: bold, fontSize: 8.5, color: _gray)),
            ),
            pw.Expanded(
                child: pw.Text(value,
                    style: pw.TextStyle(font: reg, fontSize: 9.5, color: _ink))),
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 40),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(org,
                  style: pw.TextStyle(font: reg, fontSize: 7.5, color: _gray)),
              pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                  style: pw.TextStyle(font: reg, fontSize: 7.5, color: _gray)),
            ],
          ),
        ),
        build: (ctx) => [
          // ---- 헤더 (MUJI풍: 큰 제목 + 얇은 구분선) ----
          pw.Text(title,
              style: pw.TextStyle(
                  font: bold,
                  fontSize: 22,
                  color: _ink,
                  letterSpacing: -0.4)),
          pw.SizedBox(height: 6),
          pw.Container(width: 46, height: 3, color: _accent),
          pw.SizedBox(height: 16),
          metaRow('기간', period),
          metaRow('장소', place),
          metaRow('참가', '${attendees.length}명'),
          if (desc.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(desc,
                style: pw.TextStyle(font: reg, fontSize: 9, color: _gray)),
          ],
          pw.SizedBox(height: 20),

          // ---- 참가자 표 ----
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _line, width: 0.5),
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(22),
              1: const pw.FixedColumnWidth(26),
              2: const pw.FixedColumnWidth(66),
              3: const pw.FlexColumnWidth(2.2),
              4: const pw.FixedColumnWidth(30),
              5: const pw.FlexColumnWidth(1.5),
              6: const pw.FlexColumnWidth(1.8),
              7: const pw.FlexColumnWidth(2.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _softBg),
                children: [
                  _th('#', bold),
                  _th('접속', bold),
                  _th('이름', bold),
                  _th('소속', bold),
                  _th('성별', bold),
                  _th('연락처', bold),
                  _th('메일', bold),
                  _th('항목', bold),
                ],
              ),
              for (var i = 0; i < attendees.length; i++)
                pw.TableRow(
                  children: [
                    _td('${i + 1}', base, align: pw.TextAlign.center),
                    _td(_access(attendees[i]) ? 'V' : '', base,
                        align: pw.TextAlign.center,
                        color: _access(attendees[i]) ? _accent : _gray),
                    _td('${attendees[i]['name'] ?? ''}', baseBold),
                    _td('${attendees[i]['unit'] ?? ''}', base, color: _gray),
                    _td('${attendees[i]['gender'] ?? ''}', base,
                        align: pw.TextAlign.center),
                    _td('${attendees[i]['phone'] ?? ''}', base),
                    _td('${attendees[i]['email'] ?? ''}', base, color: _gray),
                    _td(_rolesText(attendees[i]), base),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text('· 접속 V = 해당 참가자가 사진폴더에 접근한 이력',
              style: pw.TextStyle(font: reg, fontSize: 7.5, color: _gray)),
        ],
      ),
    );
    return doc.save();
  }

  static bool _access(Map<String, dynamic> a) => a['visited'] == true;

  static String _rolesText(Map<String, dynamic> a) {
    final roles = (a['roles'] as List?)?.map((e) => '$e').toList() ?? [];
    if (roles.isEmpty) return '';
    return roles.join(', ');
  }

  static pw.Widget _th(String t, pw.Font bold) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: pw.Text(t,
            style: pw.TextStyle(font: bold, fontSize: 8.5, color: _accent)),
      );

  static pw.Widget _td(String t, pw.TextStyle style,
          {pw.TextAlign align = pw.TextAlign.left, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: pw.Text(t,
            textAlign: align,
            style: (color == null)
                ? style
                : pw.TextStyle(
                    font: style.font,
                    fontSize: style.fontSize,
                    fontWeight: style.fontWeight,
                    color: color)),
      );

  /// 명단을 텍스트(TXT)로 변환
  static String buildText({
    required String title,
    required String period,
    required String place,
    required String desc,
    required List<Map<String, dynamic>> attendees,
    String org = '한국범스카우트중앙회 (TSAK)',
  }) {
    final b = StringBuffer();
    b.writeln('■ $title');
    if (period.isNotEmpty) b.writeln('기간 : $period');
    if (place.isNotEmpty) b.writeln('장소 : $place');
    b.writeln('참가 : ${attendees.length}명');
    if (desc.isNotEmpty) b.writeln(desc);
    b.writeln('-' * 60);
    b.writeln('No. 접속  이름      소속                 성별  연락처         메일');
    b.writeln('-' * 60);
    for (var i = 0; i < attendees.length; i++) {
      final a = attendees[i];
      final v = _access(a) ? 'V' : ' ';
      b.writeln(
        '${(i + 1).toString().padRight(3)} ${v.padRight(4)} '
        '${('${a['name'] ?? ''}').padRight(9)} '
        '${('${a['unit'] ?? ''}').padRight(20)} '
        '${('${a['gender'] ?? ''}').padRight(5)} '
        '${('${a['phone'] ?? ''}').padRight(14)} '
        '${a['email'] ?? ''}',
      );
    }
    b.writeln('-' * 60);
    b.writeln('· 접속 V = 사진폴더 접근 이력  |  $org');
    return b.toString();
  }

  /// 명단을 워드(.doc, HTML 기반, MUJI풍)로 변환
  static String buildWord({
    required String title,
    required String period,
    required String place,
    required String desc,
    required List<Map<String, dynamic>> attendees,
    String org = '한국범스카우트중앙회 (TSAK)',
  }) {
    final rows = StringBuffer();
    for (var i = 0; i < attendees.length; i++) {
      final a = attendees[i];
      final v = _access(a) ? 'V' : '';
      final roles = _rolesText(a);
      rows.write('''
    <tr>
      <td class="c">${i + 1}</td>
      <td class="c ${v.isNotEmpty ? 'v' : ''}">$v</td>
      <td class="n">${_esc('${a['name'] ?? ''}')}</td>
      <td class="g">${_esc('${a['unit'] ?? ''}')}</td>
      <td class="c">${_esc('${a['gender'] ?? ''}')}</td>
      <td>${_esc('${a['phone'] ?? ''}')}</td>
      <td class="g">${_esc('${a['email'] ?? ''}')}</td>
      <td>${_esc(roles)}</td>
    </tr>''');
    }
    return '''<html><head><meta charset="utf-8">
<style>
  body { font-family:'Malgun Gothic','Nanum Gothic',sans-serif; color:#1F1A2E; }
  h1 { font-size:22pt; margin:0 0 4px; letter-spacing:-0.5px; }
  .bar { width:46px; height:3px; background:#5B2C8D; margin:6px 0 18px; }
  .meta { font-size:10pt; color:#555; margin-bottom:2px; }
  .meta b { color:#888; font-weight:700; display:inline-block; width:44px; }
  .desc { color:#888; margin-top:8px; }
  table { border-collapse:collapse; width:100%; margin-top:22px; }
  th { background:#F6F4F1; color:#5B2C8D; font-size:9pt; text-align:left;
       padding:7px 5px; border-bottom:1px solid #E3E3E3; }
  td { font-size:9pt; padding:7px 5px; border-bottom:1px solid #E3E3E3; }
  td.c { text-align:center; color:#888; }
  td.n { font-weight:700; }
  td.g { color:#666; }
  td.v { color:#5B2C8D; font-weight:800; }
  .foot { font-size:8pt; color:#999; margin-top:16px; }
</style></head><body>
  <h1>${_esc(title)}</h1>
  <div class="bar"></div>
  ${period.isNotEmpty ? '<div class="meta"><b>기간</b>${_esc(period)}</div>' : ''}
  ${place.isNotEmpty ? '<div class="meta"><b>장소</b>${_esc(place)}</div>' : ''}
  <div class="meta"><b>참가</b>${attendees.length}명</div>
  ${desc.isNotEmpty ? '<div class="desc">${_esc(desc)}</div>' : ''}
  <table>
    <thead><tr><th>#</th><th>접속</th><th>이름</th><th>소속</th><th>성별</th>
    <th>연락처</th><th>메일</th><th>항목</th></tr></thead>
    <tbody>$rows</tbody>
  </table>
  <div class="foot">· 접속 V = 사진폴더 접근 이력 &nbsp;|&nbsp; ${_esc(org)}</div>
</body></html>''';
  }
}
