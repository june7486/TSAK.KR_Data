import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'doc_pdf.dart';
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

/// 표 스타일(감격/강조) — 머리글·행·테두리 강조 정도를 결정한다.
enum ExportTableStyle { plain, framed, accent, zebra }

extension ExportTableStyleX on ExportTableStyle {
  String get label {
    switch (this) {
      case ExportTableStyle.plain:
        return '민무늬';
      case ExportTableStyle.framed:
        return '기본 격자';
      case ExportTableStyle.accent:
        return '강조 머리글';
      case ExportTableStyle.zebra:
        return '교차 음영';
    }
  }

  /// 문서 하단에 표기할 규칙 문구.
  String get note {
    switch (this) {
      case ExportTableStyle.plain:
        return '머리글 강조 · 얇은 구분선';
      case ExportTableStyle.framed:
        return '격자 테두리 · 흑백 머리글';
      case ExportTableStyle.accent:
        return '브랜드 퍼플 머리글 · 굵은 구분선';
      case ExportTableStyle.zebra:
        return '머리글 강조 · 홀수행 음영';
    }
  }
}

/// 글씨 크기 — 출력물(표) 본문/머리글/제목 폰트 크기 프리셋.
enum ExportFontSize { small, normal, large }

extension ExportFontSizeX on ExportFontSize {
  String get label {
    switch (this) {
      case ExportFontSize.small:
        return '작게';
      case ExportFontSize.normal:
        return '보통';
      case ExportFontSize.large:
        return '크게';
    }
  }

  double get cell {
    switch (this) {
      case ExportFontSize.small:
        return 6.2;
      case ExportFontSize.normal:
        return 7.4;
      case ExportFontSize.large:
        return 8.8;
    }
  }

  double get head {
    switch (this) {
      case ExportFontSize.small:
        return 7.0;
      case ExportFontSize.normal:
        return 8.0;
      case ExportFontSize.large:
        return 9.6;
    }
  }

  double get title {
    switch (this) {
      case ExportFontSize.small:
        return 13;
      case ExportFontSize.normal:
        return 14;
      case ExportFontSize.large:
        return 16;
    }
  }

  String get note {
    switch (this) {
      case ExportFontSize.small:
        return '한 페이지에 많이 · 잘림 최소';
      case ExportFontSize.normal:
        return '가독·밀도 균형 · 기본';
      case ExportFontSize.large:
        return '크게 읽기 편함';
    }
  }
}

/// 행 간격(밀도) — 셀 안쪽 여백(세로/가로) 프리셋.
enum ExportRowSpace { tight, normal, loose }

extension ExportRowSpaceX on ExportRowSpace {
  String get label {
    switch (this) {
      case ExportRowSpace.tight:
        return '좁게';
      case ExportRowSpace.normal:
        return '보통';
      case ExportRowSpace.loose:
        return '넓게';
    }
  }

  double get vPad {
    switch (this) {
      case ExportRowSpace.tight:
        return 1.6;
      case ExportRowSpace.normal:
        return 3.0;
      case ExportRowSpace.loose:
        return 5.2;
    }
  }

  double get hPad {
    switch (this) {
      case ExportRowSpace.tight:
        return 3.0;
      case ExportRowSpace.normal:
        return 4.0;
      case ExportRowSpace.loose:
        return 6.0;
    }
  }

  String get note {
    switch (this) {
      case ExportRowSpace.tight:
        return '행 높이 최소 · 한 장에 최대';
      case ExportRowSpace.normal:
        return '표준 간격 · 기본';
      case ExportRowSpace.loose:
        return '숨 쉬는 간격';
    }
  }
}

/// 두줄 방지 대상 후보 — 이름·인가번호(범/아타스/은하)·핸드폰·이메일·소속대·연맹·주소·생년월일.
/// (줄바꿈이 생기면 표가 지저분해지는 핵심 항목)
const List<String> kNoWrapCandidates = [
  'name',
  'nameEn',
  'number',
  'atasNo',
  'eunhaNo',
  'phone',
  'email',
  'unit',
  'league',
  'address',
  'birthday',
];

/// 두줄 방지 기본 선택 — 식별자·연락 핵심(주소·소속대·연맹·생년월일은 필요 시 켬).
///  · 이름(name)·영어이름(nameEn)은 신원 핵심이라 기본으로 켜 줄바꿈을 막는다.
const Set<String> kNoWrapDefault = {
  'name',
  'nameEn',
  'number',
  'atasNo',
  'eunhaNo',
  'phone',
  'email',
};

/// 두줄 방지 옵션 라벨(key → 화면 표기).
const Map<String, String> kNoWrapLabels = {
  'name': '이름',
  'nameEn': '영어이름',
  'number': '범인가번호',
  'atasNo': '아타스인가번호',
  'eunhaNo': '은하인가번호',
  'phone': '핸드폰번호',
  'email': '이메일',
  'unit': '소속대',
  'league': '연맹',
  'address': '주소',
  'birthday': '생년월일',
};

/// 내보낼 개인정보 항목 정의 (선택 가능)
class ExportField {
  const ExportField(this.key, this.label, [this.group = '기타']);
  final String key;
  final String label;

  /// 묶음 구분(화면 그룹핑용) — '기본' | '연락' | '주소' | '자격' | '회비' | '기타'
  final String group;
}

/// 내보내기에서 선택할 수 있는 전체 개인정보 항목 (회원 모델의 모든 필드).
/// 그룹 순서대로 화면에 표시된다.
const List<ExportField> kExportFields = [
  // ---- 기본 정보 ----
  ExportField('number', '인가번호', '기본'),
  ExportField('scoutNo', '스카우트 고유번호', '기본'),
  ExportField('atasNo', 'ATAS 인가번호', '기본'),
  ExportField('name', '성명', '기본'),
  ExportField('nameEn', '영어이름', '기본'),
  ExportField('gender', '성별', '기본'),
  ExportField('league', '연맹', '기본'),
  ExportField('unit', '소속대', '기본'),
  ExportField('regLeague', '등록연맹', '기본'),
  ExportField('regUnit', '등록단위대', '기본'),
  ExportField('date', '인가일', '기본'),
  ExportField('birthday', '생일', '기본'),
  ExportField('anniversary', '기념일', '기본'),
  // ---- 연락 ----
  ExportField('phone', '핸드폰', '연락'),
  ExportField('tel', '연락처', '연락'),
  ExportField('email', '이메일', '연락'),
  // ---- 주소 ----
  ExportField('zipCode', '우편번호', '주소'),
  ExportField('address', '주소', '주소'),
  ExportField('residentNo', '주민등록번호', '주소'),
  // ---- 자격 · 활동 ----
  ExportField('trainingStatus', '훈련현황', '자격'),
  ExportField('qualificationStatus', '자격지정', '자격'),
  ExportField('activity', '활동', '자격'),
  ExportField('position', '직위(현재활동)', '자격'),
  ExportField('awards', '포상', '자격'),
  ExportField('specialtyCourses', '전문과정', '자격'),
  ExportField('purchases', '수품구매현황', '자격'),
  // ---- 회비 · 행사 ----
  ExportField('lifetime', '평생회원', '회비'),
  ExportField('feeYears', '회비연도', '회비'),
  ExportField('events', '행사참가', '회비'),
  // ---- 기타 ----
  ExportField('mentors', '멘토', '기타'),
  ExportField('parents', '페런츠', '기타'),
  ExportField('approvalStatus', '승인상태', '기타'),
  ExportField('memo', '메모', '기타'),
  ExportField('bio', '비고', '기타'),
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
    case 'scoutNo':
      return m.scoutNo;
    case 'name':
      return m.name;
    case 'nameEn':
      return m.nameEn;
    case 'gender':
      return m.gender;
    case 'league':
      return m.league;
    case 'unit':
      return m.unit;
    case 'regLeague':
      return m.regLeague;
    case 'regUnit':
      return m.regUnit;
    case 'date':
      return m.date;
    case 'phone':
      return m.phone;
    case 'tel':
      return m.tel;
    case 'email':
      return m.email;
    case 'address':
      return m.address;
    case 'zipCode':
      return m.zipCode;
    case 'residentNo':
      return m.residentNo;
    case 'bio':
      return m.bio;
    case 'birthday':
      return m.birthday;
    case 'anniversary':
      return m.anniversary;
    case 'trainingStatus':
      return m.trainingStatus;
    case 'qualificationStatus':
      return m.qualificationApproved ? '승인' : '';
    case 'atasNo':
      return m.atasNo;
    case 'activity':
      return m.activity;
    case 'position':
      return m.position;
    case 'awards':
      return m.awards;
    case 'specialtyCourses':
      return m.specialtyCourses;
    case 'purchases':
      return m.purchases;
    case 'memo':
      return m.memo;
    case 'lifetime':
      return m.lifetimeMember ? 'O' : '';
    case 'lifetimeSince':
      return m.lifetimeSince;
    case 'feeYears':
      return m.paidYears.join(', ');
    case 'events':
      return m.attendedEvents.join(', ');
    case 'mentors':
      return m.mentors.join(', ');
    case 'parents':
      return m.parents.join(', ');
    case 'approvalStatus':
      switch (m.approvalStatus) {
        case 'approved':
          return '승인';
        case 'pending':
          return '미승인';
        case 'held':
          return '보류';
        default:
          return '';
      }
    default:
      return '';
  }
}

/// 명단 내보내기 서비스
class ExportService {
  // ── PDF 한글 폰트(나눔고딕) 캐시 ──────────────────────────────
  // 폰트를 임베딩하지 않으면 pdf 패키지 기본 Helvetica 로 출력되어
  // 한글이 전부 □(두부)로 깨진다. 최초 1회 로드 후 재사용한다.
  static pw.Font? _pdfReg;
  static pw.Font? _pdfBold;

  // 실제 폰트 메트릭(문자 폭) 측정용. 두줄 방지 열의 정확한 너비 계산에 사용.
  static ByteData? _pdfRegBytes;
  static TtfParser? _pdfRegParser;

  static Future<void> _ensurePdfFonts() async {
    if (_pdfReg == null || _pdfRegBytes == null) {
      final b = await rootBundle.load('assets/fonts/NanumGothic-Regular-s.ttf');
      _pdfRegBytes = b;
      _pdfReg = pw.Font.ttf(b);
      _pdfRegParser = TtfParser(b);
    }
    _pdfBold ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Bold-s.ttf'),
    );
  }

  /// 검증/미리보기 생성기용 — 에셋 번들 없이(순수 Dart) 폰트를 주입한다.
  /// (테스트 훅: 설정하면 [_ensurePdfFonts] 는 rootBundle 을 건드리지 않는다.)
  /// [regularBytes] 를 주면 실제 메트릭 기반 두줄 방지 폭 계산도 활성화된다.
  @visibleForTesting
  static void debugSetPdfFonts({
    required pw.Font regular,
    required pw.Font bold,
    ByteData? regularBytes,
  }) {
    _pdfReg = regular;
    _pdfBold = bold;
    if (regularBytes != null) {
      _pdfRegBytes = regularBytes;
      _pdfRegParser = TtfParser(regularBytes);
    }
  }

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
      .map(
        (k) => kExportFields
            .firstWhere((f) => f.key == k, orElse: () => ExportField(k, k))
            .label,
      )
      .toList();

  static List<String> rowFor(Member m, List<String> keys) =>
      keys.map((k) => exportValueOf(m, k)).toList();

  /// 엑셀 XLSX 바이트 생성 — 표 폼 디자인(테마 색) + 상단 필터 + 머리글 고정.
  static Uint8List buildExcel(
    List<Member> members, {
    List<String>? fieldKeys,
    String title = '인가자 명단',
  }) {
    final keys = fieldKeys ?? kDefaultFieldKeys;
    final heads = headersFor(keys);
    final cols = heads.length;
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    // ── 표 폼 스타일 ──
    final headFill = ExcelColor.fromHexString('FF5B2C8D'); // 브랜드 퍼플
    final headText = ExcelColor.fromHexString('FFFFFFFF');
    final zebra = ExcelColor.fromHexString('FFF3EFF9'); // 아주 옅은 보라
    final lineColor = ExcelColor.fromHexString('FFD9D2E6');
    Border b(String? hint) => Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: hint == null
          ? lineColor
          : ExcelColor.fromHexString('FF$hint'),
    );

    final headStyle = CellStyle(
      backgroundColorHex: headFill,
      fontColorHex: headText,
      bold: true,
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      leftBorder: b(null),
      rightBorder: b(null),
      topBorder: b(null),
      bottomBorder: b(null),
    );
    CellStyle bodyStyle(int r) => CellStyle(
      backgroundColorHex: r.isEven ? ExcelColor.none : zebra,
      fontSize: 9,
      verticalAlign: VerticalAlign.Center,
      leftBorder: b(null),
      rightBorder: b(null),
      topBorder: b(null),
      bottomBorder: b(null),
    );

    // 헤더
    final headerRow = <CellValue>[for (final h in heads) TextCellValue(h)];
    sheet.appendRow(headerRow);
    for (var c = 0; c < cols; c++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
              .cellStyle =
          headStyle;
    }

    // 본문
    var rowIndex = 1;
    for (final m in members) {
      sheet.appendRow(rowFor(m, keys).map((v) => TextCellValue(v)).toList());
      final st = bodyStyle(rowIndex);
      for (var c = 0; c < cols; c++) {
        sheet
                .cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: c,
                    rowIndex: rowIndex,
                  ),
                )
                .cellStyle =
            st;
      }
      rowIndex++;
    }

    // 열 너비 자동(항목별 적정) + 머리글 행 높이
    for (var c = 0; c < cols; c++) {
      final w = _excelColWidth(heads[c]);
      sheet.setColumnWidth(c, w);
    }
    sheet.setRowHeight(0, 26);
    sheet.setDefaultRowHeight(18);

    final bytes = excel.encode();
    if (bytes == null) return Uint8List(0);
    // 상단 자동 필터 + 항목(머리글) 고정
    return _augmentSheetXml(Uint8List.fromList(bytes), cols);
  }

  /// 항목명 길이에 따른 엑셀 열 너비.
  static double _excelColWidth(String label) {
    const wide = <String, double>{
      '주소': 34,
      '이메일': 26,
      '비고': 22,
      '메모': 22,
      '수품구매현황': 24,
      '행사참가': 24,
      '멘토': 22,
      '페런츠': 22,
      '전문과정': 22,
      '포상': 20,
    };
    const mid = <String, double>{
      '성명': 12,
      '연맹': 16,
      '소속대': 16,
      '등록연맹': 12,
      '등록단위대': 12,
      '생일': 12,
      '기념일': 12,
      '핸드폰': 15,
      '연락처': 15,
      '우편번호': 9,
      '주민등록번호': 16,
      '훈련현황': 12,
      '자격지정': 12,
      '활동': 10,
      '평생회원': 10,
      '회비연도': 16,
      '승인상태': 10,
      'Scout 회원번호': 14,
      'ATAS 인가번호': 14,
      '인가번호': 10,
      '인가일': 12,
    };
    if (wide.containsKey(label)) return wide[label]!;
    if (mid.containsKey(label)) return mid[label]!;
    return 12.0;
  }

  /// 엑셀 시트 XML 에 `<autoFilter>`(상단 필터) 와 `<pane>`(머리글 고정)를 주입한다.
  ///
  /// excel 4.0.6 이 두 기능을 지원하지 않아, 생성된 XLSX(ZIP)의
  /// `xl/worksheets/sheet1.xml` 만 문자열 후처리한다.
  static Uint8List _augmentSheetXml(Uint8List xlsx, int cols) {
    try {
      final archive = ZipDecoder().decodeBytes(xlsx);
      final out = Archive();
      final lastCol = _colLetter(cols - 1);
      for (final f in archive.files) {
        if (f.name == 'xl/worksheets/sheet1.xml') {
          var xml = utf8.decode(f.content as List<int>);
          final lastRow = _maxRow(xml);
          // 머리글 고정 + 상단 필터 보기
          xml = xml.replaceFirst(
            '<sheetView workbookViewId="0"/>',
            '<sheetView workbookViewId="0">'
                '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
                '</sheetView>',
          );
          // 상단 항목 자동 필터(autoFilter) — 머리글 행 기준
          xml = xml.replaceFirst(
            '<drawing ',
            '<autoFilter ref="A1:$lastCol$lastRow"/>'
                '<drawing ',
          );
          out.addFile(
            ArchiveFile(f.name, utf8.encode(xml).length, utf8.encode(xml)),
          );
        } else {
          out.addFile(ArchiveFile(f.name, f.size, f.content as List<int>));
        }
      }
      return Uint8List.fromList(ZipEncoder().encode(out)!);
    } catch (_) {
      return xlsx; // 후처리 실패 시 원본 반환(기능 손실 없음 — 필터/고정만 빠짐)
    }
  }

  /// 시트 XML 에서 마지막 행 번호를 찾는다(필터 범위 계산용).
  static int _maxRow(String xml) {
    var max = 1;
    for (final m in RegExp(r'<row r="(\d+)"').allMatches(xml)) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > max) max = n;
    }
    return max;
  }

  /// 0-based 열 인덱스 → 엑셀 열 문자(A, B, ..., Z, AA...).
  static String _colLetter(int c) {
    var i = c;
    final sb = StringBuffer();
    while (i >= 0) {
      sb.write(String.fromCharCode(65 + (i % 26)));
      i = (i ~/ 26) - 1;
    }
    return sb.toString().split('').reversed.join();
  }

  /// PDF 바이트 생성 (표 형식) — **한글 폰트(나눔고딕) 임베딩 필수**.
  ///
  /// 폰트를 지정하지 않으면 기본 Helvetica 로 출력되어 한글이 □ 로 깨진다.
  static Future<Uint8List> buildPdf(
    List<Member> members, {
    String title = '한국범스카우트 중앙회 인가자 명단',
    List<String>? fieldKeys,
    bool landscape = true,
    ExportTableStyle style = ExportTableStyle.accent,
    ExportFontSize fontSize = ExportFontSize.normal,
    ExportRowSpace rowSpace = ExportRowSpace.normal,
    Set<String> noWrapKeys = const {},
  }) async {
    final keys = fieldKeys ?? kDefaultFieldKeys;
    return buildPdfFromRows(
      headers: headersFor(keys),
      rows: members.map((m) => rowFor(m, keys)).toList(),
      title: title,
      landscape: landscape,
      style: style,
      fontSize: fontSize,
      rowSpace: rowSpace,
      noWrapKeys: noWrapKeys,
    );
  }

  /// 표 형식 PDF 바이트 생성 (제네릭 — 헤더·행 직접 지정).
  ///
  /// [landscape]=가로(false=세로) · [style]=표 강조(감격) 정도 ·
  /// [fontSize]=글씨 크기 · [rowSpace]=행 간격(밀도) ·
  /// [noWrapKeys]=두줄 방지 열(헤더 라벨 기준, 줄바꿈 금지 + 열 너비 자동 확보).
  /// 한글 폰트(나눔고딕) 임베딩 필수 — 미지정 시 □ 로 깨진다.
  static Future<Uint8List> buildPdfFromRows({
    required List<String> headers,
    required List<List<String>> rows,
    String title = '한국범스카우트 중앙회 인가자 명단',
    bool landscape = true,
    ExportTableStyle style = ExportTableStyle.accent,
    ExportFontSize fontSize = ExportFontSize.normal,
    ExportRowSpace rowSpace = ExportRowSpace.normal,
    Set<String> noWrapKeys = const {},
  }) async {
    await _ensurePdfFonts();
    final reg = _pdfReg!;
    final bold = _pdfBold!;
    final doc = pw.Document();
    final pageFormat = landscape
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
    final line = PdfColor.fromInt(0xFFD9D2E6);
    final purple = PdfColor.fromInt(0xFF5B2C8D);
    final zebraTint = PdfColor.fromInt(0xFFF3EFF9);
    final framedHead = PdfColor.fromInt(0xFFEDEAE3);

    // 본문 스타일 (규칙: 브랜드 퍼플 + 얇은 테두리, 저채도) — 크기는 fontSize.
    final titleStyle = pw.TextStyle(
      font: bold,
      fontSize: fontSize.title,
      color: PdfColor.fromInt(0xFF3D1B63),
    );
    final metaStyle = pw.TextStyle(
      font: reg,
      fontSize: fontSize.head + 1,
      color: PdfColor.fromInt(0xFF6E6A7C),
    );
    final headStyle = style == ExportTableStyle.framed
        ? pw.TextStyle(
            font: bold,
            fontSize: fontSize.head,
            color: PdfColor.fromInt(0xFF3A3A3A),
          )
        : pw.TextStyle(
            font: bold,
            fontSize: fontSize.head,
            color: PdfColors.white,
          );
    final cellStyle = pw.TextStyle(font: reg, fontSize: fontSize.cell);

    // 표 강조(감격) 분기.
    pw.BoxDecoration? headDeco;
    switch (style) {
      case ExportTableStyle.plain:
        headDeco = null;
        break;
      case ExportTableStyle.framed:
        headDeco = pw.BoxDecoration(
          color: framedHead,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
        );
        break;
      case ExportTableStyle.accent:
      case ExportTableStyle.zebra:
        headDeco = pw.BoxDecoration(
          color: purple,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
        );
        break;
    }
    final tableBorder = style == ExportTableStyle.framed
        ? pw.TableBorder.all(color: line, width: 0.5)
        : pw.TableBorder(
            horizontalInside: pw.BorderSide(color: line, width: 0.4),
            bottom: pw.BorderSide(color: line, width: 0.6),
          );
    final oddRowDeco = style == ExportTableStyle.zebra
        ? pw.BoxDecoration(color: zebraTint)
        : null;

    // 두줄 방지 열 인덱스 + 실측 기반 열 너비.
    // 표 폭이 페이지를 넘으면 pdf 패키지가 전체 열을 비례 축소하므로,
    // 총합을 페이지 안에 맞춰 두줄 방지 열의 예약 폭이 깎이지 않게 한다.
    final noWrapLabels = <String>{};
    for (final k in noWrapKeys) {
      noWrapLabels.addAll(_headersForNoWrapKey(k));
    }
    final noWrapCols = <int>{};
    for (var i = 0; i < headers.length; i++) {
      if (noWrapLabels.contains(headers[i])) noWrapCols.add(i);
    }
    final colWidths = _computeColumnWidths(
      headers: headers,
      rows: rows,
      cellStyle: cellStyle,
      headStyle: headStyle,
      hPad: rowSpace.hPad,
      noWrapCols: noWrapCols,
      maxTotal: pageFormat.width - 36, // 좌우 여백 18pt × 2
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: tsakPdfPageTheme(
          format: pageFormat,
          margin: const pw.EdgeInsets.all(18),
        ),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: titleStyle),
            pw.SizedBox(height: 3),
            pw.Text(
              '총 ${rows.length}명  ·  ${landscape ? '가로' : '세로'}  ·  '
              '글씨 ${fontSize.label} · 간격 ${rowSpace.label}  ·  '
              '출력일: ${_today()}',
              style: metaStyle,
            ),
            pw.SizedBox(height: 5),
            pw.Divider(color: line, thickness: 0.8),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '출력규칙 · ${style.note} · ${ctx.pageNumber}/${ctx.pagesCount}',
            style: pw.TextStyle(
              font: reg,
              fontSize: 8,
              color: PdfColor.fromInt(0xFF8C877E),
            ),
          ),
        ),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            headerStyle: headStyle,
            headerDecoration: headDeco,
            headerAlignment: pw.Alignment.center,
            cellStyle: cellStyle,
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: pw.EdgeInsets.symmetric(
              horizontal: rowSpace.hPad,
              vertical: rowSpace.vPad,
            ),
            columnWidths: colWidths,
            border: tableBorder,
            oddRowDecoration: oddRowDeco,
            cellBuilder: (cu, data, rowNum) {
              final col = cu - 1; // 1-based 열 인덱스 → 0-based
              if (!noWrapCols.contains(col)) return null; // 기본 셀(줄바꿈 허용)
              // softWrap:false 만이 줄바꿈을 막는다(maxLines 는 잘림만 유발).
              return pw.Text(
                data?.toString() ?? '',
                style: cellStyle,
                softWrap: false,
              );
            },
            data: rows,
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// key → 표 헤더 라벨(kExportFields 기준). 두줄 방지 열 매칭에 사용.
  static String _labelFor(String key) => kExportFields
      .firstWhere((f) => f.key == key, orElse: () => ExportField(key, key))
      .label;

  /// 두줄 방지 키 → 보호할 표 열 헤더 라벨(들).
  ///
  /// '범인가번호'·'은하인가번호'는 export 표에서 하나의 '인가번호' 열을 공유하고,
  /// '아타스인가번호'는 'ATAS 인가번호' 열에 대응한다.
  static List<String> _headersForNoWrapKey(String key) {
    switch (key) {
      case 'number':
      case 'eunhaNo':
        return const ['인가번호'];
      case 'atasNo':
        return const ['ATAS 인가번호'];
      default:
        return [_labelFor(key)];
    }
  }

  /// 모든 열의 고정 너비를 실측해 배분한다.
  ///
  /// 핵심: 총합을 페이지 안에 맞춰 표의 비례 축소를 원천 차단한다.
  /// 두줄 방지 열([noWrapCols])은 한 줄 폭을 온전히 확보하고,
  /// 나머지 열이 남는 폭을 내용 비례로 나눠 갖는다.
  static Map<int, pw.TableColumnWidth> _computeColumnWidths({
    required List<String> headers,
    required List<List<String>> rows,
    required pw.TextStyle cellStyle,
    required pw.TextStyle headStyle,
    required double hPad,
    required Set<int> noWrapCols,
    required double maxTotal,
  }) {
    final n = headers.length;
    final cellFs = cellStyle.fontSize ?? 7.4;
    final headFs = headStyle.fontSize ?? 7.4;
    final pad = hPad * 2 + 2.5; // 좌우 패딩 + 테두리 여유

    // 실제 폰트 메트릭(있으면)으로 문자 폭 합을 계산.
    double measure(String s, double fs) {
      final parser = _pdfRegParser;
      if (parser == null) return _unitsWidth(s, fs);
      var w = 0.0;
      for (final code in s.runes) {
        final g = parser.charToGlyphIndexMap[code];
        if (g == null) continue;
        w += (parser.glyphInfoMap[g]?.advanceWidth ?? 0) * fs;
      }
      return w;
    }

    // 열별 최대 내용 폭(헤더 포함).
    final content = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      var maxW = measure(headers[i], headFs);
      for (final r in rows) {
        if (i >= r.length) continue;
        final w = measure(r[i].toString(), cellFs);
        if (w > maxW) maxW = w;
      }
      content[i] = maxW;
    }

    final width = List<double>.generate(n, (i) => content[i] + pad);
    final total = width.fold(0.0, (s, e) => s + e);
    if (total > maxTotal) {
      // 1) 두줄 방지 열은 온전히 보존.
      var fixed = 0.0;
      final shrinkable = <int>[];
      for (var i = 0; i < n; i++) {
        if (noWrapCols.contains(i)) {
          fixed += width[i];
        } else {
          shrinkable.add(i);
        }
      }
      // 2) 나머지 열 최소폭(두 줄 감당) = 내용의 55% 또는 22pt.
      final minW = List<double>.generate(n, (i) {
        final m = content[i] * 0.55;
        return m < 22 ? 22 : m;
      });
      var minSum = 0.0;
      for (final i in shrinkable) {
        minSum += minW[i];
      }
      final avail = maxTotal - fixed;
      if (avail <= minSum) {
        for (final i in shrinkable) {
          width[i] = minW[i];
        }
        // 그래도 넘치면 두줄 방지 열을 아주 약간만 줄여 페이지 안에 맞춘다.
        var over = fixed + minSum - maxTotal;
        for (var i = 0; i < n && over > 0.5; i++) {
          if (!noWrapCols.contains(i)) continue;
          final floor = content[i] * 0.92 + pad;
          final cut = (width[i] - floor).clamp(0.0, over);
          width[i] -= cut;
          over -= cut;
        }
      } else {
        var flexSum = 0.0;
        for (final i in shrinkable) {
          flexSum += content[i];
        }
        for (final i in shrinkable) {
          final ratio = flexSum > 0
              ? content[i] / flexSum
              : 1 / shrinkable.length;
          width[i] = (avail * ratio).clamp(minW[i], width[i]);
        }
      }
    }

    return <int, pw.TableColumnWidth>{
      for (var i = 0; i < n; i++) i: pw.FixedColumnWidth(width[i]),
    };
  }

  /// 텍스트 폭(pt 근사) — 나눔고딕 기준, 잘림 방지를 위해 약간 넉넉히.
  static double _unitsWidth(String s, double fs) {
    // 폰트 메트릭이 없으므로 문자 종류별 계수로 폭을 근사한다.
    var units = 0.0;
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      if (RegExp(r'[0-9]').hasMatch(c)) {
        units += fs * 0.62; // 숫자
      } else if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        units += fs * 0.66; // 영문
      } else if (ch > 0x2E80) {
        units += fs * 1.02; // 한글·한자 등 전각
      } else {
        units += fs * 0.5; // 기호(-, ., @ 등)
      }
    }
    return units + 2;
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
    for (var i = 0; i < slideCount; i++) {
      contentTypes.write(
        '<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
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
      ..write(
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">',
      )
      ..write(
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>',
      )
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
      ..write(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      )
      ..write(
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>',
      );
    for (var i = 0; i < slideCount; i++) {
      presRels.write(
        '<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>',
      );
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
      spTree.write(
        _textShape(2, 'TSAK 명단 - $title', startX, 250000, tableW, 500000, 2000),
      );
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
        '<a:p><a:r><a:rPr lang="ko-KR" sz="$fontSize" b="1"><a:solidFill><a:srgbClr val="5B2C8D"/></a:solidFill></a:rPr><a:t>${_escape(text)}</a:t></a:r></a:p>'
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
    buf.write(
      '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="$id" name="Table $id"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="$x" y="$y"/><a:ext cx="${colW * (grid.isEmpty ? 1 : grid.first.length)}" cy="${rowH * grid.length}"/></p:xfrm>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">'
      '<a:tbl><a:tblPr firstRow="1"/><a:tblGrid>',
    );
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
          '<a:r><a:rPr lang="ko-KR" sz="900"${isHead ? ' b="1"' : ''}><a:solidFill><a:srgbClr val="${isHead ? 'FFFFFF' : '1F1A2E'}"/></a:solidFill></a:rPr>',
        );
        buf.write('<a:t>${_escape(grid[r][c])}</a:t></a:r></a:p></a:txBody>');
        buf.write(
          '<a:tcPr><a:solidFill><a:srgbClr val="${isHead ? '5B2C8D' : 'FFFFFF'}"/></a:solidFill></a:tcPr></a:tc>',
        );
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
