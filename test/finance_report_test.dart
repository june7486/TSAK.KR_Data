import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/finance_report.dart';

/// Phase 4 보고서 생성 검증 — 실제 분석 데이터 형태로 PDF 바이트가 생성되는지.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FinanceReportService.build 가 유효한 PDF를 생성한다', () async {
    // 실제 /api/finance/analysis 응답을 모사한 축약 샘플
    final analysis = <String, dynamic>{
      'ok': true,
      'totals': {
        'income': 224354161,
        'expense': 215383103,
        'net': 8971058,
        'rows': 2350,
        'yearCount': 4,
        'from': '2013',
        'to': '2026',
      },
      'files': [
        {'name': '(후원)_1005-102-281143.xlsx', 'rows': 900},
        {'name': '(수품)_1005-102-281143.xlsx', 'rows': 1200},
        {'name': '(지출)_1005-102-281143.xlsx', 'rows': 250},
      ],
      'years': {
        '2026': {
          'year': '2026', 'income': 27355135, 'expense': 19822324,
          'net': 7532811, 'count': 208,
          'byCategory': {'수입:수품구매': 14181240, '지출:후원금집행': 9703064,
            '지출:수품구매': 9581260, '수입:후원': 9054895},
          'byMonth': {'1': {'income': 4875500, 'expense': 11193944}},
          'byEvent': {'미분류': {'income': 27355135, 'expense': 19822324}},
          'rows': [
            {'date': '2026.09.13', 'type': 'income', 'amount': 268000,
             'name': '방예솔', 'number': '1757', 'category': '수품구매',
             'event': '', 'memo': '모바일', 'context': '', 'file': 'a.xlsx'},
          ],
        },
        '2024': {
          'year': '2024', 'income': 11738784, 'expense': 8985390,
          'net': 2753394, 'count': 166,
          'byCategory': {'지출:수품구매': 4825220, '수입:참가비': 3993500},
          'byMonth': {}, 'byEvent': {}, 'rows': [],
        },
        '2020': {
          'year': '2020', 'income': 9208896, 'expense': 10323553,
          'net': -1114657, 'count': 81,
          'byCategory': {'수입:후원': 8538305}, 'byMonth': {}, 'byEvent': {},
          'rows': [],
        },
        '2013': {
          'year': '2013', 'income': 21695357, 'expense': 18363620,
          'net': 3331737, 'count': 108,
          'byCategory': {'수입:후원': 19640519}, 'byMonth': {}, 'byEvent': {},
          'rows': [],
        },
      },
      'events': {
        '미분류': {'event': '미분류', 'income': 200000000, 'expense': 190000000,
          'count': 2200, 'years': {'2026': 47000000}},
        '야영대회': {'event': '야영대회', 'income': 5000000, 'expense': 3000000,
          'count': 40, 'years': {'2026': 8000000}},
      },
    };

    final bytes = await FinanceReportService.build(analysis);
    expect(bytes, isNotEmpty);
    // PDF 매직 넘버 %PDF
    expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46]));
    // 파일로 저장해 크기 확인(디버그)
    final f = File('/tmp/tsak_finance_report_test.pdf');
    await f.writeAsBytes(bytes);
    // ignore: avoid_print
    print('PDF 생성 성공: ${bytes.length} bytes → ${f.path}');
    expect(bytes.length, greaterThan(5000));
  });
}
