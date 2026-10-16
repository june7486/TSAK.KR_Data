import 'dart:typed_data';
import 'print_doc.dart';
import 'doc_pdf.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 행사 참가자 명단 — 무인양품(MUJI)풍 미니멀 인쇄 문서 생성.
/// 엑셀/PDF/워드/텍스트 등 다양한 포맷으로 내보낼 수 있다.
///
/// 인쇄 옵션(선택항목):
///  - 참가비 납부 여부 / 평생회원 여부 / 행사년도 연회비 납부 여부
///  - 인가번호 · 이름 · 연락처는 항상 출력한다.
class RosterService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  /// 한글 폰트(나눔고딕) 로드 — 최초 1회 캐시.
  static Future<void> _ensureFonts() async {
    _regular ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Regular-s.ttf'),
    );
    _bold ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Bold-s.ttf'),
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

  // ---- 참가자 데이터 접근 헬퍼 ----
  //  [요구] 표시용 필드(서버 주입)를 우선 사용한다:
  //   · 소속   — 활동등록대(unitText)를 먼저 노출(인가시 소속은 폴백).
  //   · 메일/성별/연락처 — 개인카드(회원 프로필) 값을 먼저 사용.
  //   · 인가번호 — numberLabel('범#415'/'은하#43'/'일반#010…').
  static String _first(Map<String, dynamic> a, List<String> keys) {
    for (final k in keys) {
      final v = '${a[k] ?? ''}'.trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String _name(Map<String, dynamic> a) => '${a['name'] ?? ''}';
  static String _phone(Map<String, dynamic> a) =>
      _first(a, const ['phoneText', 'phone']);
  static String _number(Map<String, dynamic> a) =>
      _first(a, const ['numberLabel', 'number']);
  static String _unit(Map<String, dynamic> a) =>
      _first(a, const ['unitText', 'unit']);
  static String _gender(Map<String, dynamic> a) =>
      _first(a, const ['genderText', 'gender']);
  static String _email(Map<String, dynamic> a) =>
      _first(a, const ['emailText', 'email']);
  static bool _bool(Map<String, dynamic> a, String k) => a[k] == true;
  static bool _access(Map<String, dynamic> a) => a['visited'] == true;

  static String _rolesText(Map<String, dynamic> a) {
    // 서버가 준 표시용 rawRoles(원본 roles) 우선.
    // (요구) 출력(명부)에는 자격을 함께 노출 — 코드가 있으면 '코드(자격)'.
    final raw = a['rawRoles'];
    final roles = (raw is List ? raw : (a['roles'] as List?) ?? [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (roles.isEmpty) return '';
    return roles.join(', ');
  }

  static String _yn(bool v) => v ? 'O' : '';

  /// 참가자 명단 PDF 바이트 생성 (MUJI풍)
  static Future<Uint8List> buildPdf({
    required String title,
    required String period,
    required String place,
    required String desc,
    required List<Map<String, dynamic>> attendees,
    String org = '한국범스카우트중앙회 (TSAK)',
    String year = '',
    bool showEventFee = false,
    bool showLifetime = false,
    bool showYearFee = false,
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
              child: pw.Text(
                label,
                style: pw.TextStyle(font: bold, fontSize: 8.5, color: _gray),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: pw.TextStyle(font: reg, fontSize: 9.5, color: _ink),
              ),
            ),
          ],
        ),
      );
    }

    // ---- 동적 컬럼 정의 ----
    // 항상 출력: # · 접속 · 인가번호 · 이름 · 소속 · 성별 · 연락처 · 메일 · 항목
    // 선택 출력: 참가비 · 평생회원 · (연도)연회비
    final widthMap = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(18), // #
      1: const pw.FixedColumnWidth(22), // 접속
      2: const pw.FixedColumnWidth(42), // 인가번호
      3: const pw.FixedColumnWidth(56), // 이름
      4: const pw.FlexColumnWidth(2.0), // 소속
      5: const pw.FixedColumnWidth(24), // 성별
      6: const pw.FixedColumnWidth(94), // 연락처 ← 확대(전화번호 끝자리 줄바꿈 방지, p.11)
      7: const pw.FlexColumnWidth(1.7), // 메일
      8: const pw.FlexColumnWidth(1.6), // 항목
    };
    final headers = <pw.Widget>[
      _th('#', bold),
      _th('접속', bold),
      _th('인가번호', bold),
      _th('이름', bold),
      // [요구] 소속은 '현재 활동하는 곳(활동등록대)'을 먼저 노출한다.
      _th('소속(활동)', bold),
      _th('성별', bold),
      _th('연락처', bold),
      _th('메일', bold),
      _th('항목', bold),
    ];
    var ci = 9;
    if (showEventFee) {
      widthMap[ci] = const pw.FixedColumnWidth(38);
      headers.add(_th('참가비', bold));
      ci++;
    }
    if (showLifetime) {
      widthMap[ci] = const pw.FixedColumnWidth(38);
      headers.add(_th('평생', bold));
      ci++;
    }
    if (showYearFee) {
      widthMap[ci] = const pw.FixedColumnWidth(44);
      headers.add(_th('${year.isNotEmpty ? '$year년 ' : ''}연회비', bold));
      ci++;
    }

    pw.TableRow buildRow(int i) {
      final a = attendees[i];
      final cells = <pw.Widget>[
        _td('${i + 1}', base, align: pw.TextAlign.center, color: _gray),
        _td(
          _access(a) ? 'V' : '',
          base,
          align: pw.TextAlign.center,
          color: _access(a) ? _accent : _gray,
        ),
        _td(_number(a), base, align: pw.TextAlign.center),
        _td(_name(a), baseBold),
        _td(_unit(a), base, color: _gray),
        _td(_gender(a), base, align: pw.TextAlign.center),
        _td(_phone(a), base), // 고정폭 80 → 줄바꿈 없음
        _td(_email(a), base, color: _gray),
        _td(_rolesText(a), base),
      ];
      if (showEventFee) {
        cells.add(
          _td(
            _yn(_bool(a, 'eventFee')),
            base,
            align: pw.TextAlign.center,
            color: _bool(a, 'eventFee') ? _accent : _gray,
          ),
        );
      }
      if (showLifetime) {
        cells.add(
          _td(
            _yn(_bool(a, 'lifetime')),
            base,
            align: pw.TextAlign.center,
            color: _bool(a, 'lifetime') ? _accent : _gray,
          ),
        );
      }
      if (showYearFee) {
        cells.add(
          _td(
            _yn(_bool(a, 'yearFee')),
            base,
            align: pw.TextAlign.center,
            color: _bool(a, 'yearFee') ? _accent : _gray,
          ),
        );
      }
      return pw.TableRow(children: cells);
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: tsakPdfPageTheme(
          format: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 40),
        ),
        footer: (ctx) => tsakPdfFooter(
          pageNumber: ctx.pageNumber,
          pagesCount: ctx.pagesCount,
          left: org,
          font: reg,
        ),
        build: (ctx) => [
          // ---- 헤더 (MUJI풍: 큰 제목 + 얇은 구분선) ----
          pw.Text(
            title,
            style: pw.TextStyle(
              font: bold,
              fontSize: 22,
              color: _ink,
              letterSpacing: -0.4,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Container(width: 46, height: 3, color: _accent),
          pw.SizedBox(height: 16),
          metaRow('기간', period),
          metaRow('장소', place),
          metaRow('참가', '${attendees.length}명'),
          if (desc.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              desc,
              style: pw.TextStyle(font: reg, fontSize: 9, color: _gray),
            ),
          ],
          pw.SizedBox(height: 20),

          // ---- 참가자 표 ----
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _line, width: 0.5),
            ),
            columnWidths: widthMap,
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _softBg),
                children: headers,
              ),
              for (var i = 0; i < attendees.length; i++) buildRow(i),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            '· 접속 V = 해당 참가자가 사진폴더에 접근한 이력',
            style: pw.TextStyle(font: reg, fontSize: 7.5, color: _gray),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _th(String t, pw.Font bold) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 3),
    child: pw.Text(
      t,
      style: pw.TextStyle(font: bold, fontSize: 8, color: _accent),
    ),
  );

  static pw.Widget _td(
    String t,
    pw.TextStyle style, {
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor? color,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 3),
    child: pw.Text(
      t,
      textAlign: align,
      style: (color == null)
          ? style
          : pw.TextStyle(
              font: style.font,
              fontSize: style.fontSize,
              fontWeight: style.fontWeight,
              color: color,
            ),
    ),
  );

  /// 명단을 텍스트(TXT)로 변환
  static String buildText({
    required String title,
    required String period,
    required String place,
    required String desc,
    required List<Map<String, dynamic>> attendees,
    String org = '한국범스카우트중앙회 (TSAK)',
    String year = '',
    bool showEventFee = false,
    bool showLifetime = false,
    bool showYearFee = false,
  }) {
    final b = StringBuffer();
    b.writeln('■ $title');
    if (period.isNotEmpty) b.writeln('기간 : $period');
    if (place.isNotEmpty) b.writeln('장소 : $place');
    b.writeln('참가 : ${attendees.length}명');
    if (desc.isNotEmpty) b.writeln(desc);
    b.writeln('-' * 72);
    b.write('No. 접속  인가번호   이름      소속(활동)           성별  연락처');
    b.write('     메일');
    if (showEventFee) b.write('   참가비');
    if (showLifetime) b.write('  평생');
    if (showYearFee) b.write('  연회비');
    b.writeln();
    b.writeln('-' * 72);
    for (var i = 0; i < attendees.length; i++) {
      final a = attendees[i];
      final v = _access(a) ? 'V' : ' ';
      b.write(
        '${(i + 1).toString().padRight(3)} ${v.padRight(4)} '
        '${_number(a).padRight(9)} '
        '${_name(a).padRight(9)} '
        '${_unit(a).padRight(20)} '
        '${_gender(a).padRight(5)} '
        '${_phone(a).padRight(14)}',
      );
      b.write('  ${_email(a).padRight(24)}');
      if (showEventFee) b.write('   ${_yn(_bool(a, 'eventFee')).padRight(5)}');
      if (showLifetime) b.write('  ${_yn(_bool(a, 'lifetime')).padRight(4)}');
      if (showYearFee) b.write('  ${_yn(_bool(a, 'yearFee')).padRight(5)}');
      b.writeln();
    }
    b.writeln('-' * 72);
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
    String year = '',
    bool showEventFee = false,
    bool showLifetime = false,
    bool showYearFee = false,
  }) {
    final extraHead = StringBuffer();
    if (showEventFee) extraHead.write('<th style="text-align:center">참가비</th>');
    if (showLifetime) extraHead.write('<th style="text-align:center">평생</th>');
    if (showYearFee) {
      extraHead.write(
        '<th style="text-align:center">${year.isNotEmpty ? '$year년 ' : ''}연회비</th>',
      );
    }
    final rows = StringBuffer();
    for (var i = 0; i < attendees.length; i++) {
      final a = attendees[i];
      final v = _access(a) ? 'V' : '';
      final roles = _rolesText(a);
      final extra = StringBuffer();
      if (showEventFee) {
        extra.write(
          '<td class="c ${_bool(a, 'eventFee') ? 'v' : ''}">${_yn(_bool(a, 'eventFee'))}</td>',
        );
      }
      if (showLifetime) {
        extra.write(
          '<td class="c ${_bool(a, 'lifetime') ? 'v' : ''}">${_yn(_bool(a, 'lifetime'))}</td>',
        );
      }
      if (showYearFee) {
        extra.write(
          '<td class="c ${_bool(a, 'yearFee') ? 'v' : ''}">${_yn(_bool(a, 'yearFee'))}</td>',
        );
      }
      rows.write('''
    <tr>
      <td class="c">${i + 1}</td>
      <td class="c ${v.isNotEmpty ? 'v' : ''}">$v</td>
      <td class="c">${_esc(_number(a))}</td>
      <td class="n">${_esc(_name(a))}</td>
      <td class="g">${_esc(_unit(a))}</td>
      <td class="c">${_esc(_gender(a))}</td>
      <td class="ph">${_esc(_phone(a))}</td>
      <td class="g">${_esc(_email(a))}</td>
      <td>${_esc(roles)}</td>$extra
    </tr>''');
    }
    return '''<html><head><meta charset="utf-8">
<style>
  body { font-family:$kDocFontStack; color:#1F1A2E; }
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
  td.ph { white-space:nowrap; }
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
    <thead><tr><th>#</th><th>접속</th><th>인가번호</th><th>이름</th><th>소속(활동)</th><th>성별</th>
    <th>연락처</th><th>메일</th><th>항목</th>$extraHead</tr></thead>
    <tbody>$rows</tbody>
  </table>
  <div class="foot">· 접속 V = 사진폴더 접근 이력 &nbsp;|&nbsp; ${_esc(org)}</div>
</body></html>''';
  }
}
