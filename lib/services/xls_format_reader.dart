/// **구형 .xls(Excel 97-2003/BIFF8) 리더** — 벤더링한 OLE2+BIFF 파서 파사드.
///
/// 요구: "xls 포멧도 지원해줘".
/// pub.dev 의 `excel2003` 패키지(순수 Dart OLE2/BIFF8 리더)를 **웹 호환**하도록
/// 내부 벤더링(`lib/services/xls/`)하여, dart:io 의존을 제거하고 bytes 기반으로만
/// 읽는다. 결과는 [XlsxSheet] 와 동일한 2차원 문자열 격자로 통일해 상위 파서가
/// xlsx/xls 를 구분 없이 처리할 수 있게 한다.
library;

import 'dart:typed_data';

import 'xls/excel2003.dart';
import 'xlsx_reader.dart';

class XlsFormatReader {
  /// .xls 바이트 → 시트 목록. 실패하면 null.
  static List<XlsxSheet>? read(Uint8List bytes) {
    try {
      final reader = XlsReader.fromBytes(bytes);
      final out = <XlsxSheet>[];
      for (var i = 0; i < reader.sheetCount; i++) {
        final sheet = reader.sheet(i);
        final rows = <List<String>>[];
        for (var r = sheet.firstRow; r < sheet.lastRow; r++) {
          final list = <String>[];
          for (var c = sheet.firstCol; c < sheet.lastCol; c++) {
            list.add(_fmt(sheet.cell(r, c)));
          }
          rows.add(list);
        }
        out.add(XlsxSheet(sheet.name, rows));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// 셀 값 → 문자열. 정수형 실수(2186.0)는 정수로 정리한다.
  static String _fmt(dynamic v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is bool) return v ? 'TRUE' : 'FALSE';
    if (v is double) {
      if (v.isFinite && v == v.roundToDouble()) return v.toInt().toString();
      return v.toString();
    }
    if (v is num) return v.toString();
    return v.toString().trim();
  }
}
