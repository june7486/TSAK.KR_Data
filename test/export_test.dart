import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/contact_service.dart';
import 'package:tsak_credential_manager/services/export_service.dart';

void main() {
  final sample = [
    Member(
      id: 'm1',
      number: '2186',
      name: '현지환',
      league: '제주',
      unit: '제405단 샘물지역대',
      date: '2025.12.19.',
      phone: '010-6888-6397',
      email: 'a@example.com',
    ),
    Member(
      id: 'm2',
      number: '2185',
      name: '김태준',
      league: '기독교',
      phone: '010-8967-6852',
      lifetimeMember: true,
      feeYears: {'2025': true},
    ),
  ];

  test('Excel export produces non-empty bytes', () {
    final bytes = ExportService.buildExcel(sample);
    expect(bytes.length, greaterThan(1000));
  });

  test('TXT export contains names', () {
    final bytes = ExportService.buildTxt(sample);
    final text = utf8.decode(bytes);
    expect(text.contains('현지환'), isTrue);
    expect(text.contains('2186'), isTrue);
  });

  test('Word export contains table', () {
    final bytes = ExportService.buildWord(sample);
    final text = utf8.decode(bytes);
    expect(text.contains('<table'), isTrue);
    expect(text.contains('현지환'), isTrue);
  });

  test('Contact service dedups phones and emails', () {
    final members = [
      ...sample,
      Member(id: 'm3', number: '1', name: '중복', phone: '010-6888-6397'),
    ];
    expect(ContactService.phones(members).length, 2); // 2 unique
    expect(ContactService.emails(members), ['a@example.com']);
  });

  test('연번 옵션 — Word 헤더/본문에 순번 포함(기본은 미포함)', () {
    final off = utf8.decode(ExportService.buildWord(sample));
    expect(off.contains('<th>연번</th>'), isFalse);

    final on = utf8.decode(ExportService.buildWord(sample, numbering: true));
    expect(on.contains('<th>연번</th>'), isTrue);
    expect(on.contains('<td>1</td>'), isTrue);
    expect(on.contains('<td>2</td>'), isTrue);
  });

  test('연번 시작값(numberingStart) — 분할 출력 시 이어짐', () {
    final on = utf8.decode(
      ExportService.buildWord(sample, numbering: true, numberingStart: 101),
    );
    expect(on.contains('<td>101</td>'), isTrue);
    expect(on.contains('<td>102</td>'), isTrue);
  });

  test('인가일(date)이 두줄 방지 후보·기본 선택에 포함', () {
    expect(kNoWrapCandidates.contains('date'), isTrue);
    expect(kNoWrapDefault.contains('date'), isTrue);
    expect(kNoWrapLabels['date'], '인가일');
  });

  test('headersWithIndex/rowWithIndex 헬퍼 — 연번 선택', () {
    expect(ExportService.headersWithIndex(['name']).first, '성명');
    expect(ExportService.headersWithIndex(['name'], numbering: true).first, '연번');
    final row = ExportService.rowWithIndex(sample[0], ['name'], 7,
        numbering: true);
    expect(row.first, '7');
    expect(row[1], '현지환');
  });
}
