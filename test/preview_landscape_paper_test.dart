// 가로 모드 · 이름줄 삭제 회귀 테스트 (2026-11-02, build #567)
//
// ## 보고 (스크린샷 Kb1wbB71)
//  ① "가로모드 선택시 세로모드가 됨"
//     — 미리보기에서 '가로 모드' 스위치가 **ON(보라)** 인데도 화면의 종이가
//       세로처럼 보였다.
//  ② "이름줄: 항목 삭제"
//     — 미리보기 옵션의 `이름줄 1줄/2줄/3줄` 칩을 없애 달라.
//
// ## ①의 실제 원인 (중요 — PDF 는 무죄)
//  `landscape:true` 로 만든 PDF 페이지를 pymupdf 로 재면 **841.9 × 595.3pt(가로)**
//  로 처음부터 정상이었다. 문제는 미리보기 카드였다.
//    · 카드는 방향과 무관한 **고정 높이 세로 박스**(흰 배경)였고,
//    · 흰 종이가 흰 카드 안에 들어가 종이 경계가 사라져
//      **카드의 둥근 테두리(세로 사각형)가 곧 종이**로 읽혔다.
//  → "가로를 골랐는데 세로가 됐다"는 인식.
//  이제 카드 배경은 회색 책상, 종이는 A4 실제 비율로 그려 **눈에 보이게 눕는다.**
//
// ## 이 파일이 고정하는 것
//  ① `landscape:true` → PDF 페이지가 실제로 가로(width > height). 대조군 포함.
//  ② `paperSize()` — 카드 안 종이 사각형의 비율이 방향에 따라 실제로 뒤집힌다.
//  ③ `previewCardHeight()` — 가로 모드에서 카드가 더 낮아진다.
//  ④ 미리보기 옵션에 '이름줄' 칩이 **없고** '셀 줄 수' 는 남아 있다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tsak_credential_manager/services/doc_pdf.dart';
import 'package:tsak_credential_manager/services/print_doc.dart';
import 'package:tsak_credential_manager/services/table_export.dart';
import 'package:tsak_credential_manager/widgets/tsak_output_preview.dart';

void _injectFonts() {
  final reg = File('assets/fonts/NanumGothic-Regular-s.ttf');
  final bold = File('assets/fonts/NanumGothic-Bold-s.ttf');
  expect(reg.existsSync(), isTrue);
  expect(bold.existsSync(), isTrue);
  DocPdf.debugSetFonts(
    regular: pw.Font.ttf(reg.readAsBytesSync().buffer.asByteData()),
    bold: pw.Font.ttf(bold.readAsBytesSync().buffer.asByteData()),
  );
}

/// 미리보기 카드의 래스터화는 테스트 환경에서 끝나지 않는다(플러그인 없음).
/// 그래서 pumpAndSettle 대신 **고정 프레임**만 넘긴다.
Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

TsakTableDoc _doc() => TsakTableDoc(
  title: '2026 ATAS와 사이버한국외국어대학교 MOU',
  subtitle: '서삼릉훈련원 방문',
  columns: const ['#', '접속', '인가번호', '이름', '연락처', '메일', '항목'],
  rows: const [
    ['1', 'V', '범#75', '이승준', '010-9367-3344', 'simonrhee75@gmail.com', '전체'],
    ['2', 'V', '범#135', '김종환', '010-3590-2280', 'kgh135@naver.com', '전체'],
  ],
  summary: const ['총 2명'],
  footerLeft: '한국범스카우트중앙회',
);

void main() {
  setUpAll(_injectFonts);

  group('① PDF 레이어 — 가로/세로가 실제로 바뀐다', () {
    test('landscape:true → 페이지가 가로(width > height)', () async {
      final pdf = await DocPdf.buildSimple(
        meta: DocMeta(
          title: '가로 테스트',
          author: '테스터',
          createdAt: '2026-11-02 10:00',
        ),
        columns: const ['#', '이름', '연락처'],
        rows: const [
          ['1', '이승준', '010-9367-3344'],
        ],
        landscape: true,
      );
      final path = '/tmp/preview_land_yes.pdf';
      await File(path).writeAsBytes(pdf);
      final size = await _pageSize(path);
      expect(
        size.$1 > size.$2,
        isTrue,
        reason: '가로 모드인데 페이지가 세로다: ${size.$1} x ${size.$2}',
      );
      expect(size.$1, closeTo(841.9, 2.0)); // A4 가로 폭
      expect(size.$2, closeTo(595.3, 2.0)); // A4 가로 높이
    });

    test('landscape:false → 페이지가 세로(height > width) — 대조군', () async {
      final pdf = await DocPdf.buildSimple(
        meta: DocMeta(
          title: '세로 테스트',
          author: '테스터',
          createdAt: '2026-11-02 10:00',
        ),
        columns: const ['#', '이름', '연락처'],
        rows: const [
          ['1', '이승준', '010-9367-3344'],
        ],
      );
      final path = '/tmp/preview_land_no.pdf';
      await File(path).writeAsBytes(pdf);
      final size = await _pageSize(path);
      expect(size.$2 > size.$1, isTrue, reason: '세로인데 가로로 나왔다');
      expect(size.$1, closeTo(595.3, 2.0));
      expect(size.$2, closeTo(841.9, 2.0));
    });
  });

  group('② 종이 사각형 비율 — 가로를 켜면 실제로 눕는다', () {
    test('세로 → 비율 < 1 (A4 210:297 = 0.707)', () {
      final s = paperSize(500, 300, landscape: false);
      expect(s.$2, greaterThan(s.$1), reason: '세로인데 폭이 더 넓다');
      expect(s.$1 / s.$2, closeTo(210 / 297, 0.01));
    });

    test('가로 → 비율 > 1 (A4 297:210 = 1.414)', () {
      final s = paperSize(500, 300, landscape: true);
      expect(s.$1, greaterThan(s.$2), reason: '가로인데 높이가 더 크다');
      expect(s.$1 / s.$2, closeTo(297 / 210, 0.01));
    });

    test('종이는 카드 안에 반드시 들어간다(넘침 없음)', () {
      for (final land in [false, true]) {
        for (final box in [
          (320.0, 200.0),
          (200.0, 400.0),
          (500.0, 150.0),
          (100.0, 90.0),
        ]) {
          final s = paperSize(box.$1, box.$2, landscape: land);
          expect(
            s.$1 <= box.$1 + 0.01 && s.$2 <= box.$2 + 0.01,
            isTrue,
            reason: 'landscape=$land box=$box → paper=${s.$1}x${s.$2} 넘침',
          );
          expect(s.$1, greaterThan(0));
          expect(s.$2, greaterThan(0));
        }
      }
    });
  });

  group('③ 카드 높이 — 가로 모드에서 더 낮다', () {
    test('가로 카드가 세로 카드보다 낮다', () {
      for (final h in [600.0, 800.0, 1000.0, 1400.0]) {
        final p = previewCardHeight(h, landscape: false);
        final l = previewCardHeight(h, landscape: true);
        expect(l, lessThan(p), reason: 'screen=$h → 세로 $p / 가로 $l');
      }
    });
  });

  group('④ 이름줄 항목 삭제', () {
    testWidgets("'이름줄' 칩은 없고 '셀 줄 수' 는 남아 있다", (tester) async {
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
      // ⚠️ await 하면 안 된다 — 다이얼로그가 닫힐 때까지 Future 가 끝나지 않는다.
      showTsakOutputPreview(ctx, doc: _doc());
      await tester.pump(); // dialog 삽입
      await _settle(tester);

      expect(
        find.text('이름줄'),
        findsNothing,
        reason: "보고: '이름줄: 항목 삭제' — 옵션에서 사라져야 한다",
      );
      expect(find.text('셀 줄 수'), findsOneWidget);
      // 1줄/2줄/3줄 칩은 '셀 줄 수' 몫으로 **한 벌만** 남아야 한다.
      expect(find.text('1줄'), findsOneWidget);
      expect(find.text('2줄'), findsOneWidget);
      expect(find.text('3줄'), findsOneWidget);
      expect(find.text('자동'), findsOneWidget);
    });

    testWidgets('가로 모드 스위치가 실제로 상태를 바꾼다', (tester) async {
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
      // ⚠️ await 하면 안 된다 — 다이얼로그가 닫힐 때까지 Future 가 끝나지 않는다.
      showTsakOutputPreview(ctx, doc: _doc());
      await tester.pump(); // dialog 삽입
      await _settle(tester);

      final toggles = find.byType(Switch);
      expect(toggles, findsNWidgets(2), reason: '2줄방지 · 가로모드 스위치');
      expect(tester.widget<Switch>(toggles.at(1)).value, isFalse);

      await tester.tap(toggles.at(1), warnIfMissed: false);
      await _settle(tester);
      expect(
        tester.widget<Switch>(toggles.at(1)).value,
        isTrue,
        reason: '가로 모드 스위치가 켜지지 않았다',
      );
    });
  });
}

/// PDF 첫 페이지의 (width, height) pt — pymupdf 로 실측한다.
/// (PyMuPDF 는 `/usr/local/bin/python3` 에만 있다.)
Future<(double, double)> _pageSize(String path) async {
  for (final py in ['/usr/local/bin/python3', 'python3']) {
    try {
      final r = await Process.run(py, [
        '-c',
        'import pymupdf,sys\n'
            'd=pymupdf.open(sys.argv[1])\n'
            'p=d[0]\n'
            'print(p.rect.width, p.rect.height)\n',
        path,
      ]);
      if (r.exitCode != 0) continue;
      final parts = (r.stdout as String).trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      return (double.parse(parts[0]), double.parse(parts[1]));
    } catch (_) {
      continue;
    }
  }
  fail('PDF 페이지 크기를 읽지 못했다(파이썬/pymupdf 없음): $path');
}
