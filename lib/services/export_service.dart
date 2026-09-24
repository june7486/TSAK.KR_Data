import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/member.dart';

/// 내보내기 형식 (PDF / JPG / 엑셀 / 워드 / PPT / 텍스트)
enum ExportFormat { excel, pdf, word, txt, jpg, ppt }

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
      case ExportFormat.ppt:
        return '파워포인트 (PPTX)';
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
      case ExportFormat.ppt:
        return 'pptx';
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
      case ExportFormat.ppt:
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
  }
}

/// 내보낼 개인정보 항목 정의 (선택 가능)
class ExportField {
  const ExportField(this.key, this.label);
  final String key;
  final String label;
}

/// 내보내기에서 선택할 수 있는 전체 개인정보 항목
const List<ExportField> kExportFields = [
  ExportField('number', '인가번호'),
  ExportField('name', '성명'),
  ExportField('league', '연맹'),
  ExportField('unit', '소속대'),
  ExportField('date', '인가일'),
  ExportField('phone', '핸드폰'),
  ExportField('email', '이메일'),
  ExportField('address', '주소'),
  ExportField('birthday', '생일'),
  ExportField('anniversary', '기념일'),
  ExportField('trainingStatus', '훈련현황'),
  ExportField('atasNo', 'ATAS'),
  ExportField('activity', '활동'),
  ExportField('memo', '메모'),
  ExportField('lifetime', '평생회원'),
  ExportField('feeYears', '회비연도'),
  ExportField('events', '행사참가'),
];

/// 기본 선택 항목 (기존 명단 표와 동일 구성)
const List<String> kDefaultFieldKeys = [
  'number',
  'name',
  'league',
  'unit',
  'date',
  'phone',
  'email',
  'atasNo',
  'address',
  'activity',
  'memo',
  'lifetime',
  'feeYears',
  'events',
];

/// 값 추출기 — key → Member 값
String exportValueOf(Member m, String key) {
  switch (key) {
    case 'number':
      return m.number;
    case 'name':
      return m.name;
    case 'league':
      return m.league;
    case 'unit':
      return m.unit;
    case 'date':
      return m.date;
    case 'phone':
      return m.phone;
    case 'email':
      return m.email;
    case 'address':
      return m.address;
    case 'birthday':
      return m.birthday;
    case 'anniversary':
      return m.anniversary;
    case 'trainingStatus':
      return m.trainingStatus;
    case 'atasNo':
      return m.atasNo;
    case 'activity':
      return m.activity;
    case 'memo':
      return m.memo;
    case 'lifetime':
      return m.lifetimeMember ? 'O' : '';
    case 'feeYears':
      return m.paidYears.join(', ');
    case 'events':
      return m.attendedEvents.join(', ');
    default:
      return '';
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

  static List<String> rowOf(Member m) =>
      kDefaultFieldKeys.map((k) => exportValueOf(m, k)).toList();

  /// 선택된 필드 기준 헤더/행 생성
  static List<String> headersFor(List<String> keys) => keys
      .map((k) => kExportFields.firstWhere((f) => f.key == k,
              orElse: () => ExportField(k, k))
          .label)
      .toList();

  static List<String> rowFor(Member m, List<String> keys) =>
      keys.map((k) => exportValueOf(m, k)).toList();

  /// 엑셀 XLSX 바이트 생성
  static Uint8List buildExcel(List<Member> members,
      {List<String>? fieldKeys}) {
    final keys = fieldKeys ?? kDefaultFieldKeys;
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    sheet.appendRow(headersFor(keys).map((h) => TextCellValue(h)).toList());
    for (final m in members) {
      sheet.appendRow(
          rowFor(m, keys).map((v) => TextCellValue(v)).toList());
    }
    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// PDF 바이트 생성 (표 형식)
  static Future<Uint8List> buildPdf(
    List<Member> members, {
    String title = '한국범스카우트 중앙회 인가자 명단',
    List<String>? fieldKeys,
  }) async {
    final keys = fieldKeys ?? kDefaultFieldKeys;
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
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
            headers: headersFor(keys),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            data: members.map((m) => rowFor(m, keys)).toList(),
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
    List<String>? fieldKeys,
  }) {
    final keys = fieldKeys ?? kDefaultFieldKeys;
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
    for (final h in headersFor(keys)) {
      buf.write('<th>$h</th>');
    }
    buf.write('</tr>');
    for (final m in members) {
      buf.write('<tr>');
      for (final v in rowFor(m, keys)) {
        buf.write('<td>${_escape(v)}</td>');
      }
      buf.write('</tr>');
    }
    buf.write('</table></body></html>');
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  /// 파워포인트(PPTX) — OpenXML(presentationML) 최소 구조 생성
  ///
  /// 외부 라이브러리 없이 zip(archive)으로 최소 pptx 패키지를 직접 구성한다.
  /// 각 슬라이드에 제목 + 표(선택 필드)를 넣는다.
  static Uint8List buildPpt(
    List<Member> members, {
    String title = '한국범스카우트 중앙회 인가자 명단',
    List<String>? fieldKeys,
  }) {
    final keys = fieldKeys ?? kDefaultFieldKeys;
    final heads = headersFor(keys);

    // 한 슬라이드당 약 12행 (제목 1줄 포함)
    const rowsPerSlide = 12;
    final slideRows = <List<List<String>>>[];
    for (var i = 0; i < members.length; i += rowsPerSlide) {
      final chunk = members.sublist(
        i,
        (i + rowsPerSlide > members.length) ? members.length : i + rowsPerSlide,
      );
      final grid = <List<String>>[heads, ...chunk.map((m) => rowFor(m, keys))];
      slideRows.add(grid);
    }
    if (slideRows.isEmpty) slideRows.add([heads]);

    final slideCount = slideRows.length;
    // 열 개수에 따라 표 영역 폭/열폭 계산 (EMU)
    const slideW = 12192000; // 16:9
    const slideH = 6858000;
    final colCount = heads.length;
    final tableW = (slideW * 0.92).round();
    final startX = ((slideW - tableW) / 2).round();
    final colW = (tableW / (colCount == 0 ? 1 : colCount)).round();

    final buffer = _ZipBuilder();

    // 1) [Content_Types].xml
    final contentTypes = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write('<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>')
      ..write('<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>')
      ..write('<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>')
      ..write('<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>');
    for (var i = 0; i < slideCount; i++) {
      contentTypes.write(
          '<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
    }
    contentTypes.write('</Types>');
    buffer.add('[Content_Types].xml', contentTypes.toString());

    // 2) _rels/.rels
    buffer.add(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
      '</Relationships>',
    );

    // 3) ppt/presentation.xml
    final pres = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">')
      ..write('<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>')
      ..write('<p:sldIdLst>');
    for (var i = 0; i < slideCount; i++) {
      pres.write('<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>');
    }
    pres
      ..write('</p:sldIdLst>')
      ..write('<p:sldSz cx="$slideW" cy="$slideH"/>')
      ..write('<p:notesSz cx="6858000" cy="9144000"/>')
      ..write('</p:presentation>');
    buffer.add('ppt/presentation.xml', pres.toString());

    // 4) ppt/_rels/presentation.xml.rels
    final presRels = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')
      ..write('<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>');
    for (var i = 0; i < slideCount; i++) {
      presRels.write(
          '<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>');
    }
    presRels.write('</Relationships>');
    buffer.add('ppt/_rels/presentation.xml.rels', presRels.toString());

    // 5) slideMaster1.xml
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

    // 6) slideLayout1.xml
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

    // 7) theme1.xml (최소 테마)
    buffer.add(
      'ppt/theme/theme1.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office">'
      '<a:themeElements>'
      '<a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2><a:accent1><a:srgbClr val="5B2C8D"/></a:accent1><a:accent2><a:srgbClr val="D62828"/></a:accent2><a:accent3><a:srgbClr val="2E7D32"/></a:accent3><a:accent4><a:srgbClr val="1B4F9C"/></a:accent4><a:accent5><a:srgbClr val="F2B705"/></a:accent5><a:accent6><a:srgbClr val="7E4FB0"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme>'
      '<a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface="Malgun Gothic"/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface="Malgun Gothic"/><a:cs typeface=""/></a:minorFont></a:fontScheme>'
      '<a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>'
      '</a:themeElements></a:theme>',
    );

    // 8) 각 슬라이드
    for (var i = 0; i < slideCount; i++) {
      final grid = slideRows[i];
      final spTree = StringBuffer();
      // 제목 텍스트
      spTree.write(_textShape(2, 'TSAK 명단 - $title', startX, 250000, tableW, 500000, 2000));
      // 표
      spTree.write(_tableShape(3, startX, 850000, colW, grid));
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

  static String _textShape(int id, String text, int x, int y, int cx, int cy,
      int fontSize) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Title $id"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr lang="ko-KR" sz="$fontSize" b="1"><a:solidFill><a:srgbClr val="5B2C8D"/></a:solidFill></a:rPr><a:t>${_escape(text)}</a:t></a:r></a:p>'
        '</p:txBody></p:sp>';
  }

  static String _tableShape(
      int id, int x, int y, int colW, List<List<String>> grid) {
    const rowH = 300000;
    final buf = StringBuffer();
    buf.write(
        '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="$id" name="Table $id"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
        '<p:xfrm><a:off x="$x" y="$y"/><a:ext cx="${colW * (grid.isEmpty ? 1 : grid.first.length)}" cy="${rowH * grid.length}"/></p:xfrm>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">'
        '<a:tbl><a:tblPr firstRow="1"/><a:tblGrid>');
    final cols = grid.isEmpty ? 1 : grid.first.length;
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
            '<a:r><a:rPr lang="ko-KR" sz="900"${isHead ? ' b="1"' : ''}><a:solidFill><a:srgbClr val="${isHead ? 'FFFFFF' : '1F1A2E'}"/></a:solidFill></a:rPr>');
        buf.write('<a:t>${_escape(grid[r][c])}</a:t></a:r></a:p></a:txBody>');
        buf.write(
            '<a:tcPr><a:solidFill><a:srgbClr val="${isHead ? '5B2C8D' : 'FFFFFF'}"/></a:solidFill></a:tcPr></a:tc>');
      }
      buf.write('</a:tr>');
    }
    buf.write('</a:tbl></a:graphicData></a:graphic></p:graphicFrame>');
    return buf.toString();
  }

  /// 텍스트
  static Uint8List buildTxt(
    List<Member> members, {
    String title = '한국범스카우트 중앙회 인가자 명단',
    List<String>? fieldKeys,
  }) {
    final keys = fieldKeys ?? kDefaultFieldKeys;
    final buf = StringBuffer();
    buf.writeln(title);
    buf.writeln('총 ${members.length}명 | 출력일: ${_today()}');
    buf.writeln('=' * 60);
    for (final m in members) {
      buf.writeln(rowFor(m, keys).join('  '));
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
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// 최소 ZIP(저장 무압축, store) 작성기 — PPTX 패키징용
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
      // Local file header
      _writeU32(0x04034b50);
      _writeU16(20); // version needed
      _writeU16(0x0800); // flags: UTF-8
      _writeU16(0); // method: store
      _writeU16(0); // time
      _writeU16(0); // date
      _writeU32(crc);
      _writeU32(e.data.length); // compressed
      _writeU32(e.data.length); // uncompressed
      _writeU16(nb.length);
      _writeU16(0); // extra len
      _out.addAll(nb);
      _out.addAll(e.data);
    }

    // Central directory
    final cdStart = _out.length;
    for (var i = 0; i < _entries.length; i++) {
      final nb = nameBytes[i];
      _writeU32(0x02014b50);
      _writeU16(20); // version made by
      _writeU16(20); // version needed
      _writeU16(0x0800);
      _writeU16(0);
      _writeU16(0);
      _writeU16(0);
      _writeU32(crcList[i]);
      _writeU32(sizeList[i]);
      _writeU32(sizeList[i]);
      _writeU16(nb.length);
      _writeU16(0); // extra
      _writeU16(0); // comment
      _writeU16(0); // disk
      _writeU16(0); // internal attr
      _writeU32(0); // external attr
      _writeU32(localOffsets[i]);
      _out.addAll(nb);
    }
    final cdSize = _out.length - cdStart;

    // End of central directory
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
