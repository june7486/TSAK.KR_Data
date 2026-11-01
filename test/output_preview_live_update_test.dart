// 버그 재현 — "미리보기에서 항목선택(칩)이 실시간으로 반영되지 않는다"
// (2026-11-02 보고, 스크린샷 NRJRnuHN / build #562)
//
// ## 보고된 증상
//  · 출력항목 7/9 (인가번호·이름·소속·성별·연락처·메일·항목) → 미리보기 표에 7열.
//    → 이것은 **정상 동작**이었다(칠해진 칩 = 출력되는 열).
//  · 추가항목 8/8 전부 ON, '입력자 5명' 인데 **미리보기에 추가항목 열이 하나도 없다**.
//    → 이것이 진짜 버그.
//
// ## 원인 (3개)
//  ① `_doc` 게터가 `_pickedCols` 로 열을 자를 때 **추가항목 열까지 잘라냈다**.
//     `extraColumns()` 가 붙인 열(인덱스 >= 원본 열 수)은 `_pickedCols` 에
//     들어 있을 수 없으므로 `keep` 에서 탈락 → 붙자마자 사라졌다.
//     (원본 옵션에 cols 가 있으면 100% 재현, 출력항목 칩을 한 번이라도 누르면 재현)
//  ② `TableOutputOptions.copyWith(cols: null)` 이 `cols ?? this.cols` 라
//     **null 로 지울 수 없었다.** 그래서 `_doc` 의 `copyWith(cols: null)` 의도가
//     무효였고, 나중에 붙인 열이 다시 옵션에 걸려 잘렸다.
//  ③ `_key` 에 '행사 총 인원'이 빠져, 입력자 수(5명/6명)를 고쳐도
//     미리보기가 다시 만들어지지 않았다(같은 '8 / 8' 이라 서명이 동일).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tsak_credential_manager/services/doc_pdf.dart';
import 'package:tsak_credential_manager/services/extra_fields.dart';
import 'package:tsak_credential_manager/services/extra_output.dart';
import 'package:tsak_credential_manager/services/table_export.dart';
import 'package:tsak_credential_manager/services/table_options.dart';
import 'package:tsak_credential_manager/widgets/tsak_output_preview.dart';

void _injectFonts() {
  final reg = File('assets/fonts/NanumGothic-Regular-s.ttf');
  final bold = File('assets/fonts/NanumGothic-Bold-s.ttf');
  DocPdf.debugSetFonts(
    regular: pw.Font.ttf(reg.readAsBytesSync().buffer.asByteData()),
    bold: pw.Font.ttf(bold.readAsBytesSync().buffer.asByteData()),
  );
}

/// 참가자 명부 화면(`roster_screen.dart`)이 만드는 문서와 **같은 모양**.
///   · 열 7개 · 옵션에 cols 없음(참가자 명부 기본값: noWrap 만 지정)
TsakTableDoc _rosterDoc({TableOutputOptions? options}) => TsakTableDoc(
  title: '2026 범2호 노경하선배 추모행사',
  subtitle: '송정호텔',
  columns: const ['#', '접속', '인가번호', '이름', '소속(활동)', '성별', '연락처', '메일', '항목'],
  rows: const [
    ['1', 'V', '범#75', '이항복', '연장대', '남', '010-9367-3344', 'a@a.com', '정회원'],
    ['2', 'V', '범#135', '김종환', '연장대', '남', '010-3590-2280', 'b@b.com', '정회원'],
  ],
  summary: const ['총 2명'],
  options: options,
);

/// 참석자 원본 행 — `map['transport']` 같은 추가항목 키를 담는다.
List<Map<String, dynamic>> _attendees() => [
  {
    'name': '이항복',
    'number': '75',
    'transport': '자차',
    'lodging': '숙박',
    'arrive': '18:00',
    'from': '서울',
    'eta': '2시간',
    'companion': '김종환',
    'address': '서울시 강남구',
    'message': '늦게 도착합니다',
  },
  {
    'name': '김종환',
    'number': '135',
    'transport': '대중교통',
    'lodging': '숙박',
    'arrive': '17:30',
    'from': '부산',
    'eta': '4시간',
    'companion': '',
    'address': '부산시 해운대구',
    'message': '',
  },
];

void main() {
  setUpAll(_injectFonts);

  group('① extraColumns 는 추가항목 열을 붙인다 (기준선)', () {
    test('옵션에 cols 가 없으면 원본 + 추가항목 열', () {
      final d = extraColumns(
        _rosterDoc(),
        source: _attendees(),
        keys: {'transport', 'lodging'},
      );
      expect(d.columns.length, 9 + 2);
      expect(d.columns.last, ExtraFields.lodging.label);
      expect(d.viewColumns.length, 11, reason: 'cols 없음 → 전체 열');
    });

    test('옵션에 cols 가 있으면 옵션이 고른 원본 열 + 추가항목 열', () {
      // 0,2,3 = #, 인가번호, 이름
      const opts = TableOutputOptions(cols: [0, 2, 3]);
      final d = extraColumns(
        _rosterDoc(options: opts),
        source: _attendees(),
        keys: {'transport'},
      );
      expect(d.columns.length, 10);
      // 원본 3열 + 추가 1열 = 4열 (추가항목 열이 살아 있어야 한다)
      expect(d.viewColumns.length, 4);
      expect(d.viewColumns.last, ExtraFields.transport.label);
      expect(d.viewRows.first.last, '자차', reason: '추가항목 값이 실려야 한다');
    });
  });

  group('② copyWith(cols: null) 은 실제로 cols 를 지운다', () {
    test('cols 를 지정한 옵션을 null 로 되돌릴 수 있다', () {
      const o = TableOutputOptions(cols: [0, 2, 3]);
      expect(o.cols, [0, 2, 3]);
      final cleared = o.copyWith(cols: null, clearCols: true);
      expect(cleared.cols, isNull, reason: 'null 로 지워지지 않으면 뒤에 붙인 열이 잘린다');
      // 다른 값은 보존
      expect(cleared.noWrap, o.noWrap);
    });

    test('copyWith(cols: [...]) 는 그대로 동작한다', () {
      const o = TableOutputOptions(cols: [0, 2, 3]);
      expect(o.copyWith(cols: [1, 4]).cols, [1, 4]);
    });

    test('clearCols 없이 null 을 주면 기존값 유지(하위 호환)', () {
      const o = TableOutputOptions(cols: [0, 2, 3]);
      expect(o.copyWith(cols: null).cols, [0, 2, 3]);
    });
  });

  group('③ 미리보기에서 추가항목을 켜면 실제 표에 열이 붙는다 (핵심 버그)', () {
    /// 미리보기 위젯이 노출한 **검증용 훅** — 화면 없이 같은 로직을 돌린다.
    TsakTableDoc docFor({
      required Set<String> extraKeys,
      TableOutputOptions? options,
      Set<int>? pickedCols,
    }) {
      return TsakOutputPreviewDebug.resolveDoc(
        doc: _rosterDoc(options: options),
        extra: TsakExtraPick(source: _attendees()),
        extraKeys: extraKeys,
        pickedCols: pickedCols,
      );
    }

    testWidgets('참가자 명부 기본 옵션 + 추가항목 8종 전부 → 미리보기 열에 나타난다',
        (tester) async {
      final all = <String>{for (final f in ExtraFields.all) f.key};
      final d = docFor(
        // 참가자 명부 기본 옵션: cols 없음, noWrap 만.
        options: const TableOutputOptions(noWrap: {'인가번호', '연락처'}),
        extraKeys: all,
      );
      final cols = d.viewColumns;
      expect(cols.length, 9 + ExtraFields.all.length,
          reason: '원본 9열 + 추가항목 ${ExtraFields.all.length}열이 모두 보여야 한다');
      for (final f in ExtraFields.all) {
        expect(cols.contains(f.label), isTrue,
            reason: '"${f.label}" 열이 미리보기에서 사라졌다 (보고된 버그)');
      }
      // 값도 첫 참석자 기준으로 실려야 한다.
      final i = cols.indexOf(ExtraFields.transport.label);
      expect(i, greaterThanOrEqualTo(0));
      expect(d.viewRows.first[i], '자차');
    });

    testWidgets('출력항목 칩을 눌러 일부 열만 고른 상태에서도 추가항목이 살아남는다',
        (tester) async {
      // 스크린샷과 같은 상태: 인가번호·이름·소속·성별·연락처·메일·항목 = 7/9
      // 원본 인덱스: 2,3,4,5,6,7,8
      final d = docFor(
        options: const TableOutputOptions(noWrap: {'인가번호', '연락처'}),
        pickedCols: {2, 3, 4, 5, 6, 7, 8},
        extraKeys: {'transport', 'lodging'},
      );
      final cols = d.viewColumns;
      expect(cols, contains(ExtraFields.transport.label),
          reason: '추가항목 열이 선택에서 잘려 나갔다 (보고된 버그)');
      expect(cols, contains(ExtraFields.lodging.label));
      expect(cols.length, 7 + 2, reason: '원본 7열 + 추가 2열');
    });

    testWidgets('옵션에 cols 가 실려 있어도 추가항목이 살아남는다', (tester) async {
      final d = docFor(
        options: const TableOutputOptions(cols: [0, 2, 3], noWrap: {'이름'}),
        extraKeys: {'transport'},
      );
      expect(d.viewColumns, contains(ExtraFields.transport.label));
      expect(d.viewRows.first.last, '자차');
    });

    testWidgets('추가항목을 모두 끄면 원본 열로 돌아간다', (tester) async {
      final d = docFor(
        options: const TableOutputOptions(noWrap: {'인가번호'}),
        extraKeys: const <String>{},
      );
      expect(d.viewColumns.length, 9);
      expect(d.viewColumns, isNot(contains(ExtraFields.transport.label)));
    });
  });

  group('④ 칩을 누르면 미리보기가 실제로 다시 만들어진다 (위젯 수준)', () {
    testWidgets('추가항목 칩을 끄면 선택 수가 즉시 바뀐다', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      showTsakOutputPreview(
        ctx,
        doc: _rosterDoc(
          options: const TableOutputOptions(noWrap: {'인가번호'}),
        ),
        extra: TsakExtraPick(source: _attendees()),
      );
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      // 처음에는 추가항목 8종이 모두 켜져 있다.
      expect(find.textContaining('8 / 8 선택'), findsOneWidget);

      // '이동 방법' 칩을 눌러 끈다.
      //  (옵션 영역은 SingleChildScrollView 안이라 화면 밖일 수 있다 →
      //   먼저 보이게 스크롤한 뒤 누른다. 안 하면 탭이 빗나가 아무 일도 안 한다.)
      final chip = find.text(ExtraFields.transport.label).first;
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(
        find.textContaining('7 / 8 선택'),
        findsOneWidget,
        reason: '칩을 눌러도 선택 수가 바뀌지 않았다 (실시간 반영 안 됨)',
      );
    });
  });
}
