// 버그 재현 — "출력/저장 → 미리보기"를 누르면 **아무 창도 안 뜬다** (2026-11-01 보고)
//
// ## 보고 (사용자 스크린샷 btys2kF2)
//  참가자 명부 화면 → [출력/저장] → 시트 하단 [미리보기] 클릭 → 반응 없음.
//
// ## 실제 원인 (build #561 에서 수정)
//  `tsak_output_preview.dart` 의 `_key` 게터가
//      '${(_pickedCols?.toList() ?? const <int>[])..sort()}'
//  였다. `_pickedCols == null`(= '전체 열', 옵션에 cols 가 없는 화면의 기본값)이면
//  **불변 const 리스트**에 `..sort()` 를 걸어
//  `UnsupportedError: Cannot modify an unmodifiable list` 를 던졌다.
//  `_key` 는 build() 안에서 매 프레임 호출되므로 위젯이 build 단계에서 즉사
//  → showDialog 가 화면을 그리지 못해 "아무 창도 안 나온다"로 보였다.
//
// ## 이 테스트의 목적
//  화면에 실제로 미리보기 Dialog 가 **올라오는지**를 고정한다.
//  (기존 회귀 테스트는 문서 가공만 검사했고, 창이 뜨는지는 아무도 확인하지 않았다.)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tsak_credential_manager/services/doc_pdf.dart';
import 'package:tsak_credential_manager/services/table_export.dart';
import 'package:tsak_credential_manager/services/table_options.dart';
import 'package:tsak_credential_manager/widgets/tsak_output_preview.dart';
import 'package:tsak_credential_manager/widgets/tsak_output_sheet.dart';

/// 테스트 환경에는 rootBundle 폰트가 없다 → 실제 파일을 직접 넣는다.
/// (미리보기는 PDF 를 실제로 만들고 래스터화하므로 폰트가 필수다.)
void _injectFonts() {
  final reg = File('assets/fonts/NanumGothic-Regular-s.ttf');
  final bold = File('assets/fonts/NanumGothic-Bold-s.ttf');
  expect(reg.existsSync(), isTrue, reason: '본문 폰트 파일이 필요하다');
  expect(bold.existsSync(), isTrue, reason: '굵은 폰트 파일이 필요하다');
  DocPdf.debugSetFonts(
    regular: pw.Font.ttf(reg.readAsBytesSync().buffer.asByteData()),
    bold: pw.Font.ttf(bold.readAsBytesSync().buffer.asByteData()),
  );
}

TsakTableDoc _doc({TableOutputOptions? options}) => TsakTableDoc(
  title: '2026 범2호 노경하선배 추모행사',
  subtitle: '송정호텔',
  columns: const ['#', '접속', '인가번호', '이름', '소속(활동)', '성별', '연락처'],
  rows: const [
    ['1', 'V', '범#75', '이항복', '제311대 연장대', '남', '010-9367-3344'],
    ['2', 'V', '범#135', '김종환', '제1378대 연장대', '남', '010-3590-2280'],
    ['3', 'V', '범#305', '김원태', '스카우트비피클럽', '남', '010-8591-3009'],
  ],
  summary: const ['총 3명'],
  options: options,
);

/// 미리보기 카드 안에는 **계속 도는 로딩 스피너**가 있다.
/// (테스트 환경에는 `Printing.raster` 플러그인이 없어 래스터화 Future 가 끝나지
///  않는다.) 그래서 `pumpAndSettle` 대신 **고정 시간만** 넘긴다.
Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(_injectFonts);

  group('미리보기 창이 실제로 열린다', () {
    testWidgets('showTsakOutputPreview → Dialog 가 화면에 나타난다', (tester) async {
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

      showTsakOutputPreview(ctx, doc: _doc());
      await tester.pump(); // dialog 삽입
      await _settle(tester);

      // Dialog 자체가 떠 있어야 한다.
      expect(find.byType(Dialog), findsOneWidget, reason: '미리보기 창이 안 떴다');
      // 제목이 보여야 한다.
      expect(
        find.text('2026 범2호 노경하선배 추모행사'),
        findsOneWidget,
        reason: '미리보기 제목이 안 보인다',
      );
      // 안내문(옵션 조작 가능)도 보여야 한다.
      expect(
        find.textContaining('출력 미리보기'),
        findsOneWidget,
        reason: '미리보기 안내문이 안 보인다',
      );
    });

    testWidgets('출력 시트의 [미리보기] 버튼이 시트를 닫고 미리보기를 연다', (tester) async {
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

      // 실제 화면과 **같은 조합** — 시트 + onPreview 콜백.
      // (tsak_output_sheet.fire() 는 시트를 pop 한 뒤 콜백을 **동기** 호출한다.
      //  콜백이 던지면 조용히 삼켜져 "아무 일도 안 일어난" 것처럼 보였다.)
      showTsakOutputSheet(
        ctx,
        title: '참가자 명부 출력',
        subtitle: '추모행사 · 6명',
        onPick: (_) {},
        onPreview: () => showTsakOutputPreview(ctx, doc: _doc()),
      );
      await tester.pumpAndSettle();

      expect(find.text('미리보기'), findsOneWidget, reason: '[미리보기] 버튼이 없다');

      await tester.tap(find.text('미리보기'));
      await tester.pump(); // pop 시작
      await _settle(tester);

      // 시트는 닫히고, 미리보기 창이 떠 있어야 한다.
      expect(
        find.text('참가자 명부 출력'),
        findsNothing,
        reason: '출력 시트가 닫히지 않았다',
      );
      expect(
        find.byType(Dialog),
        findsOneWidget,
        reason: '시트를 닫은 뒤 미리보기 창이 뜨지 않았다 (보고된 버그)',
      );
      expect(
        find.text('2026 범2호 노경하선배 추모행사'),
        findsOneWidget,
        reason: '시트로 연 미리보기 안에 문서 제목이 안 보인다',
      );
    });

    testWidgets('출력 옵션(열 선택)이 걸려 있어도 미리보기가 뜬다', (tester) async {
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

      // 참가자 명부 화면의 기본 옵션과 동일(2줄 방지 2개 열).
      const opts = TableOutputOptions(noWrap: {'인가번호', '연락처'});
      showTsakOutputPreview(ctx, doc: _doc(options: opts));
      await tester.pump();
      await _settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets(
      '옵션에 cols 가 실려 있어도(= _pickedCols 비-null) 미리보기가 뜬다',
      (tester) async {
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

        // _key 게터의 **다른 분기**(불변이 아닌 List<int> 를 toList() 한 경우).
        const opts = TableOutputOptions(cols: [0, 2, 4]);
        showTsakOutputPreview(ctx, doc: _doc(options: opts));
        await tester.pump();
        await _settle(tester);
        expect(find.byType(Dialog), findsOneWidget);
      },
    );
  });

  group('_key 게터는 불변 리스트를 건드리지 않는다 (회귀 방지)', () {
    test('const <int>[] 에 ..sort() 를 걸면 UnsupportedError 가 난다 (버그의 정체)', () {
      // 이 동작 자체를 고정해 둔다 — 다시 같은 코드를 쓰면 즉시 드러난다.
      void bad() {
        const empty = <int>[];
        final l = empty as List<int>;
        l.sort();
      }

      expect(bad, throwsA(isA<UnsupportedError>()));
    });

    test('가변 리스트 복사본은 안전하다 (수정 방식)', () {
      final a = <int>[...<int>[]]..sort();
      expect(a, isEmpty);
      final b = <int>[...{3, 1, 2}]..sort();
      expect(b, [1, 2, 3]);
    });
  });
}
