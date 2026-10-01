/// **견고한 XLSX 직접 파서** (외부 `excel` 패키지의 버그 우회).
///
/// ## 왜 필요한가 (요구: "엑셀파일을 첨부하면 인식을 못함")
/// `excel` 4.0.6 패키지는 `workbook.xml.rels` 의 `Target` 이 **절대경로**
/// (`/xl/worksheets/sheet1.xml`)인 정상 xlsx(예: 오피스·파이썬 openpyxl 생성)에서
/// 내부적으로 `'xl/' + target` = `xl//xl/worksheets/sheet1.xml` 를 찾다가
/// `Null check operator used on a null value` 로 **크래시**한다.
/// 파서가 그 예외를 삼켜 `[]` 를 반환하므로 사용자에게는 "인식 못함"으로 보인다.
///
/// 이 리더는 zip(archive) + xml 로 OOXML 을 직접 읽어
///   - Target 경로를 상대/절대/`../` 모두 정규화하고,
///   - sharedStrings / inlineStr / 숫자 셀을 모두 처리하며,
///   - 셀 참조(A1) 기반으로 열 위치를 정확히 복원한다.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// 시트 하나 = 이름 + 2차원 문자열 격자.
class XlsxSheet {
  XlsxSheet(this.name, this.rows);

  final String name;
  final List<List<String>> rows;
}

/// XLSX 바이트 → 시트 목록. 실패하면 null.
class XlsxReader {
  static List<XlsxSheet>? read(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // 아카이브 안 파일을 경로(정규화)로 찾는다.
      String norm(String p) =>
          p.replaceAll('\\', '/').replaceAll(RegExp(r'^\./+'), '');

      ArchiveFile? findFile(String path) {
        final want = norm(path);
        for (final f in archive.files) {
          if (!f.isFile) continue;
          if (norm(f.name) == want) return f;
        }
        return null;
      }

      String? readText(String path) {
        final f = findFile(path);
        if (f == null) return null;
        final c = f.content;
        if (c is List<int>) return utf8.decode(c, allowMalformed: true);
        return null;
      }

      // 1) 공유 문자열(sharedStrings).
      final shared = <String>[];
      final ssXml = readText('xl/sharedStrings.xml');
      if (ssXml != null) {
        final doc = XmlDocument.parse(ssXml);
        for (final si in doc.findAllElements('si')) {
          final sb = StringBuffer();
          for (final t in si.findAllElements('t')) {
            sb.write(t.innerText);
          }
          shared.add(sb.toString());
        }
      }

      // 2) 관계(workbook.xml.rels): rId → Target.
      final relTarget = <String, String>{};
      final relsXml = readText('xl/_rels/workbook.xml.rels');
      if (relsXml != null) {
        final doc = XmlDocument.parse(relsXml);
        for (final r in doc.findAllElements('Relationship')) {
          final id = r.getAttribute('Id');
          final tg = r.getAttribute('Target');
          if (id != null && tg != null) relTarget[id] = tg;
        }
      }

      // 3) 워크북의 시트 정의.
      final wbXml = readText('xl/workbook.xml');
      if (wbXml == null) return null;
      final wbDoc = XmlDocument.parse(wbXml);

      /// Target 을 `xl/...` 아카이브 경로로 정규화(절대/상대/.. 모두).
      String resolveTarget(String? target, int indexFallback) {
        var t = (target ?? '').replaceAll('\\', '/');
        if (t.isEmpty) t = 'worksheets/sheet${indexFallback + 1}.xml';
        t = t.replaceAll(RegExp(r'^(\./)+'), '');
        while (t.startsWith('../')) {
          t = t.substring(3);
        }
        if (t.startsWith('/')) t = t.substring(1);
        if (!t.startsWith('xl/')) {
          final at = t.indexOf('xl/');
          t = at >= 0 ? t.substring(at) : 'xl/$t';
        }
        return t;
      }

      final sheets = <XlsxSheet>[];
      var idx = 0;
      for (final sh in wbDoc.findAllElements('sheet')) {
        final name = sh.getAttribute('name') ?? 'Sheet${idx + 1}';
        final rid = sh.getAttribute('r:id') ?? sh.getAttribute('id');
        final target = resolveTarget(rid != null ? relTarget[rid] : null, idx);
        final sheetXml = readText(target);
        if (sheetXml == null) {
          idx++;
          continue;
        }
        sheets.add(XlsxSheet(name, _parseSheet(sheetXml, shared)));
        idx++;
      }
      return sheets;
    } catch (_) {
      return null;
    }
  }

  /// 시트 XML → 2차원 격자.
  static List<List<String>> _parseSheet(String xml, List<String> shared) {
    final doc = XmlDocument.parse(xml);
    final sheetData = doc.findAllElements('sheetData').isEmpty
        ? null
        : doc.findAllElements('sheetData').first;
    if (sheetData == null) return const [];

    final rows = <List<String>>[];
    for (final row in sheetData.findElements('row')) {
      final cells = <int, String>{};
      var nextCol = 0;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = _colIndex(ref) ?? nextCol;
        nextCol = col + 1;

        final type = c.getAttribute('t');
        String value;
        if (type == 's') {
          final v = _firstInner(c, 'v');
          final i = int.tryParse(v.trim()) ?? -1;
          value = (i >= 0 && i < shared.length) ? shared[i] : '';
        } else if (type == 'inlineStr') {
          final sb = StringBuffer();
          for (final t in c.findAllElements('t')) {
            sb.write(t.innerText);
          }
          value = sb.toString();
        } else if (type == 'b') {
          value = _firstInner(c, 'v').trim() == '1' ? 'TRUE' : 'FALSE';
        } else {
          value = _firstInner(c, 'v');
        }
        cells[col] = value.trim();
      }
      if (cells.isEmpty) {
        rows.add(const []);
        continue;
      }
      final maxCol = cells.keys.reduce((a, b) => a > b ? a : b);
      final list = List<String>.filled(maxCol + 1, '');
      cells.forEach((k, v) => list[k] = v);
      rows.add(list);
    }

    // 앞쪽의 완전 빈 행 제거(엑셀 상단 여백 대응).
    while (rows.isNotEmpty && rows.first.every((c) => c.trim().isEmpty)) {
      rows.removeAt(0);
    }
    // 뒤쪽의 완전 빈 행 제거.
    while (rows.isNotEmpty && rows.last.every((c) => c.trim().isEmpty)) {
      rows.removeLast();
    }
    return rows;
  }

  static String _firstInner(XmlElement e, String name) {
    final list = e.findElements(name);
    return list.isEmpty ? '' : list.first.innerText;
  }

  /// 셀 참조("A1", "AB12") → 0-based 열 인덱스.
  static int? _colIndex(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    final m = RegExp(r'^([A-Za-z]+)').firstMatch(ref);
    if (m == null) return null;
    var n = 0;
    for (final code in m.group(1)!.toUpperCase().codeUnits) {
      n = n * 26 + (code - 64);
    }
    return n - 1;
  }
}
