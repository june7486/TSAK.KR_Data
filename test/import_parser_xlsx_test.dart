import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/import_parser.dart';
import 'package:tsak_credential_manager/services/xls_format_reader.dart';
import 'package:tsak_credential_manager/services/xlsx_reader.dart';

/// 회귀 테스트 — "엑셀파일을 첨부하면 인식을 못함" 재발 방지.
///
/// 핵심: `workbook.xml.rels` 의 Target 이 **절대경로**(`/xl/worksheets/sheet1.xml`)
/// 인 정상 xlsx(파이썬 openpyxl·일부 오피스 산출물)에서도 인식되어야 한다.
void main() {
  test('절대경로 rels xlsx(openpyxl) 를 인식한다', () {
    final bytes = File('test/fixtures/members_abspath.xlsx').readAsBytesSync();
    final sheets = XlsxReader.read(bytes);
    expect(sheets, isNotNull);
    expect(sheets!.first.rows.length, greaterThanOrEqualTo(3));

    final parsed = ImportParser.parse('members.xlsx', bytes);
    expect(parsed.length, 2);
    expect(parsed.first.number, '2186');
    expect(parsed.first.name, '홍길동');
    expect(parsed.first.league, '제주');
    expect(parsed.first.unit, '제405단');
    expect(parsed.first.phone, '010-1111-2222');
    expect(parsed.first.atasNo, 'A123');
  });

  test('공유문자열(sharedStrings) xlsx 도 인식한다', () {
    final e = Excel.createExcel();
    final s = e['Sheet1'];
    s.appendRow([
      TextCellValue('연번'),
      TextCellValue('성명'),
      TextCellValue('소속연맹'),
      TextCellValue('단위대'),
    ]);
    s.appendRow([
      IntCellValue(2186),
      TextCellValue('홍길동'),
      TextCellValue('제주'),
      TextCellValue('제405단'),
    ]);
    final bytes = Uint8List.fromList(e.encode()!);

    final parsed = ImportParser.parse('gen.xlsx', bytes);
    expect(parsed.length, 1);
    expect(parsed.first.number, '2186');
    expect(parsed.first.name, '홍길동');
  });

  test('BOM 포함 한글 CSV 도 인식한다', () {
    final content = '\uFEFF연번,성명,소속연맹,단위대\n2186,홍길동,제주,제405단\n';
    final bytes = Uint8List.fromList(utf8.encode(content));
    final parsed = ImportParser.parse('members.csv', bytes);
    expect(parsed.length, 1);
    expect(parsed.first.number, '2186');
    expect(parsed.first.name, '홍길동');
  });

  test('구형 .xls(BIFF8) 도 인식한다', () {
    final bytes = File('test/fixtures/members.xls').readAsBytesSync();
    final sheets = XlsFormatReader.read(bytes);
    expect(sheets, isNotNull);
    expect(sheets!.first.rows.length, greaterThanOrEqualTo(3));

    final parsed = ImportParser.parse('members.xls', bytes);
    expect(parsed.length, 2);
    expect(parsed.first.number, '2186');
    expect(parsed.first.name, '홍길동');
    expect(parsed.first.league, '제주');
    expect(parsed.first.unit, '제405단');
    expect(parsed.first.phone, '010-1111-2222');
    expect(parsed.first.atasNo, 'A123');
  });
}
