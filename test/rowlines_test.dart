// 행 높이(rowLines) 옵션 회귀 검증 — 순수 문자열/위젯 (폰트 자산 불필요).
//
// ## 배경 (사용자 정정)
// "두단 세단으로 표시하라는 것은 **이름별로 간을 더 늘리라는 의미**임
//  상하 두 단을 넣으라는 것이 아님(현재 적용된 것은 잘 못 반영된 것임)"
//
// 따라서 검증 대상은 **표를 쪼개지 않고, 행의 세로 여백만 커지는가** 이다.
//  1) 인쇄용 HTML(buildMujiDoc): td padding 이 rowLines 배로 커진다.
//  2) 표가 하나뿐이다(<table> 개수 1) — 상하 두 단이 되살아나지 않았는가.
//  3) 머리행은 <thead> 로 감싸여 페이지마다 반복된다.
//  4) 셀 줄 수(maxCellLines)는 -webkit-line-clamp 로 반영된다.
//  5) 옵션 배지에 '행 N줄' 이 표기된다.
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/print_doc.dart';
import 'package:tsak_credential_manager/services/table_options.dart';
import 'package:tsak_credential_manager/services/table_export.dart';

String _html({int rowLines = 1, int? maxCellLines}) {
  return buildMujiDoc(
    meta: DocMeta(
      title: '테스트 명부',
      subtitle: '',
      description: '',
      author: '검증',
      createdAt: '2026-10-31 19:00',
    ),
    columns: const ['연번', '이름', '인가번호'],
    rows: const [
      [DocCell('1'), DocCell('홍길동'), DocCell('12')],
      [DocCell('2'), DocCell('김승수'), DocCell('34')],
    ],
    rowLines: rowLines,
    maxCellLines: maxCellLines,
  );
}

void main() {
  group('행 높이(rowLines) — "이름 칸을 더 늘리라"', () {
    test('td 세로 패딩이 rowLines 배로 커진다', () {
      final one = _html(rowLines: 1);
      final two = _html(rowLines: 2);
      final three = _html(rowLines: 3);

      expect(one.contains('padding:9px 10px'), isTrue,
          reason: '1줄 = 기본 9px');
      expect(two.contains('padding:18px 10px'), isTrue,
          reason: '2줄 = 9×2');
      expect(three.contains('padding:27px 10px'), isTrue,
          reason: '3줄 = 9×3');
    });

    test('표 구조는 그대로 — 상하 두 단이 아니다 (table 1개)', () {
      for (final n in [1, 2, 3]) {
        final html = _html(rowLines: n);
        final tables = '<table'.allMatches(html).length;
        expect(tables, 1, reason: 'rowLines=$n 에서 표는 하나여야 한다');
        // 두 단 시절의 흔적이 남아 있으면 안 된다.
        expect(html.contains('bandsep'), isFalse);
        expect(html.contains('lowband'), isFalse);
      }
    });

    test('머리행은 thead 로 감싸여 페이지마다 반복된다', () {
      final html = _html(rowLines: 2);
      expect(html.contains('<thead>'), isTrue);
      expect(html.contains('<tbody>'), isTrue);
      expect(html.contains('연번'), isTrue);
    });

    test('셀 줄 수는 -webkit-line-clamp 로 반영된다', () {
      final clamped = _html(maxCellLines: 2);
      expect(clamped.contains('-webkit-line-clamp'), isTrue);
      final free = _html();
      expect(free.contains('-webkit-line-clamp'), isFalse,
          reason: '자동(null)이면 클램프하지 않는다');
    });
  });

  group('TableOutputOptions — 배지 표기', () {
    test('행 높이가 1줄이면 배지에 넣지 않는다', () {
      const o = TableOutputOptions();
      expect(o.rowLines, 1);
      expect(o.badge.contains('행 '), isFalse);
    });

    test('행 높이 2줄·셀 3줄이 배지에 함께 표기된다', () {
      const o = TableOutputOptions(rowLines: 2, cellLines: 3);
      expect(o.badge.contains('행 2줄'), isTrue, reason: o.badge);
      expect(o.badge.contains('셀 3줄'), isTrue, reason: o.badge);
    });

    test('copyWith 로만 값이 바뀌고 나머지는 유지된다', () {
      const o = TableOutputOptions(rowLines: 1, cellLines: 2, landscape: true);
      final n = o.copyWith(rowLines: 3);
      expect(n.rowLines, 3);
      expect(n.cellLines, 2);
      expect(n.landscape, isTrue);
    });
  });

  group('TsakTableDoc — 옵션이 페이지 나눔 경로로 전달된다', () {
    test('options.rowLines / cellLines 가 보존된다', () {
      final doc = TsakTableDoc(
        title: 't',
        subtitle: '',
        description: '',
        author: '',
        extra: const {},
        columns: const ['이름'],
        rows: const [
          ['홍길동'],
        ],
        options: const TableOutputOptions(rowLines: 2, cellLines: 3),
      );
      expect(doc.options?.rowLines, 2);
      expect(doc.options?.cellLines, 3);
      expect(doc.viewColumns, ['이름']);
      expect(doc.viewRows.length, 1);
    });
  });
}
