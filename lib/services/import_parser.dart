import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/member.dart';

/// 문서(엑셀/CSV/TSV/텍스트/JSON) → 인가자 목록 자동 인식 파서
///
/// 외부 AI 호출 없이도 표 형태의 자료를 열/헤더 추론으로 인식한다.
/// 인식 결과는 승인/수정 후 DB에 저장된다.
class ImportParser {
  /// 지원 확장자
  static const supported = ['.xlsx', '.xls', '.csv', '.tsv', '.txt', '.json'];

  /// 헤더 키워드 → Member 필드 매핑 사전
  /// 헤더 키워드 → Member 필드 (구체적인 항목을 먼저 검사하도록 순서 중요)
  static const Map<String, List<String>> _headerMap = {
    'atasNo': ['atas'],
    'date': ['인가일', '인가일자', '등록일', 'date', '일자'],
    'number': ['인가번호', '번호', '회원번호', 'no', 'number', 'num', '연번'],
    'name': ['성명', '이름', '성함', 'name', '회원명'],
    'league': ['소속연맹', '연맹', 'league', '지역'],
    'unit': ['단위대', '소속대', '소속단', 'unit', '부대'],
    'address': ['주소', 'address', '거주'],
    'phone': ['핸드폰', '전화', '휴대폰', '연락처', 'phone', 'tel', 'mobile'],
    'email': ['이메일', '메일', 'email', 'mail'],
    'activity': ['활동', 'activity'],
    'memo': ['메모', '비고', 'memo', 'note'],
  };

  static String? _fieldForHeader(String header) {
    final h = header.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    for (final e in _headerMap.entries) {
      for (final kw in e.value) {
        if (h.contains(kw.toLowerCase())) return e.key;
      }
    }
    return null;
  }

  /// 파일 바이트 → 인가자 후보 목록
  static List<Member> parse(String filename, Uint8List bytes) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.json')) return _parseJson(bytes);
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return _parseExcel(bytes);
    }
    // csv / tsv / txt
    return _parseText(bytes, tsv: lower.endsWith('.tsv'));
  }

  static List<Member> _parseJson(Uint8List bytes) {
    try {
      final text = _decode(bytes);
      final data = json.decode(text);
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['members'] is List) {
        list = data['members'] as List;
      } else {
        return [];
      }
      return list.whereType<Map>().map((e) => Member.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static List<Member> _parseExcel(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes);
      final out = <Member>[];
      for (final table in excel.tables.keys) {
        final rows = excel.tables[table]!.rows;
        if (rows.isEmpty) continue;
        final headers = rows.first.map((c) => _cell(c)).toList();
        final mapping = <int, String>{};
        for (var i = 0; i < headers.length; i++) {
          final f = _fieldForHeader(headers[i]);
          if (f != null) mapping[i] = f;
        }
        final startRow = mapping.isEmpty ? 1 : 1; // 헤더 다음부터
        if (mapping.isEmpty) {
          // 헤더 인식 실패 시 관례적 순서 가정: 번호, 이름, 연맹, 단위대, ...
          mapping[0] = 'number';
          mapping[1] = 'name';
          mapping[2] = 'league';
          mapping[3] = 'unit';
        }
        for (var r = startRow; r < rows.length; r++) {
          final row = rows[r];
          if (row.every((c) => _cell(c).trim().isEmpty)) continue;
          final m = _rowToMember(row, mapping);
          if (m.name.trim().isEmpty && m.number.trim().isEmpty) continue;
          out.add(m);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static List<Member> _parseText(Uint8List bytes, {bool tsv = false}) {
    final text = _decode(bytes);
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];
    final delim = tsv ? '\t' : _guessDelimiter(lines.first);
    final rows = lines.map((l) => l.split(delim)).toList();
    final headers = rows.first.map((h) => h.trim()).toList();
    final mapping = <int, String>{};
    for (var i = 0; i < headers.length; i++) {
      final f = _fieldForHeader(headers[i]);
      if (f != null) mapping[i] = f;
    }
    var start = 1;
    if (mapping.isEmpty) {
      // 헤더 없음 → 관례적 순서
      mapping[0] = 'number';
      mapping[1] = 'name';
      mapping[2] = 'league';
      mapping[3] = 'unit';
      start = 0;
    }
    final out = <Member>[];
    for (var r = start; r < rows.length; r++) {
      final row = rows[r];
      if (row.every((c) => c.trim().isEmpty)) continue;
      final m = _rowToMember(row, mapping);
      if (m.name.trim().isEmpty && m.number.trim().isEmpty) continue;
      out.add(m);
    }
    return out;
  }

  static Member _rowToMember(List<dynamic> row, Map<int, String> mapping) {
    final values = <String, String>{};
    mapping.forEach((idx, field) {
      if (idx < row.length) values[field] = _cell(row[idx]).trim();
    });
    return Member(
      id: 'imp${DateTime.now().microsecondsSinceEpoch}${values['number'] ?? ''}',
      number: values['number'] ?? '',
      name: values['name'] ?? '',
      league: values['league'] ?? '',
      unit: values['unit'] ?? '',
      address: values['address'] ?? '',
      phone: values['phone'] ?? '',
      email: values['email'] ?? '',
      date: values['date'] ?? '',
      atasNo: values['atasNo'] ?? '',
      activity: values['activity'] ?? '',
      memo: values['memo'] ?? '',
    );
  }

  static String _cell(dynamic c) {
    if (c == null) return '';
    if (c is String) return _unquote(c);
    if (c is num) return '$c';
    // excel Data 셀
    try {
      final v = (c as dynamic).value;
      if (v == null) return '';
      return _unquote('$v');
    } catch (_) {
      return '$c';
    }
  }

  /// CSV 따옴표 제거
  static String _unquote(String s) {
    var t = s.trim();
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      t = t.substring(1, t.length - 1);
    }
    return t;
  }

  static String _decode(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      try {
        return latin1.decode(bytes);
      } catch (_) {
        return '';
      }
    }
  }

  static String _guessDelimiter(String line) {
    final counts = {
      ',': RegExp(',').allMatches(line).length,
      '\t': RegExp('\t').allMatches(line).length,
      ';': RegExp(';').allMatches(line).length,
      '|': RegExp(r'\|').allMatches(line).length,
    };
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value > 0 ? best.key : ',';
  }
}
