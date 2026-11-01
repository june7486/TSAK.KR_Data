// 미리보기 종이가 **화면에서 실제로** 눕는가 (2026-11-02, build #569)
//
// ## 왜 이 테스트가 필요한가
//  build #567 에서 "가로 모드인데 세로처럼 보인다" 를 고쳤지만, 그때 확인한 것은
//  ① PDF 페이지 크기(pymupdf 실측) ② paperSize() 수식 — **둘 다 '화면'이 아니다**.
//  실제 미리보기 카드는 테스트 환경에서 래스터라이저가 없어 로딩 스피너에서
//  멈추므로, "종이가 화면에서 정말 눕는지"는 아무도 보지 못했다.
//
// ## 어떻게 확인하는가
//  `TsakPreviewPaper` 를 **세로 직사각형 카드**(340x300) 안에 넣고 위젯 트리를
//  실제로 빌드한 뒤, `getSize()` 로 **배치된 종이 사각형의 실측 크기**를 읽는다.
//  (픽셀 렌더(`toImage`)도 시도했으나 테스트 러너에서 Future 가 끝나지 않아
//   4분 넘게 멈췄다 — 재는 값은 어차피 레이아웃 크기이므로 getSize 로 충분하다.)
//
//   · 세로 → 높이 > 폭  (A4 210:297 = 0.707)
//   · 가로 → 폭 > 높이  (A4 297:210 = 1.414)
//  → "방향을 바꾸면 종이가 실제로 눕는다"를 **레이아웃 실측**으로 고정한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/widgets/tsak_output_preview.dart';

/// 카드 상자 크기 — 실제 다이얼로그와 비슷한 **세로 직사각형**.
/// (핵심: 카드가 세로여도 종이는 방향을 따라 눕는다는 것을 보여야 한다.)
const Size _cardSize = Size(340, 300);

/// [paper] 를 카드 크기 상자에 넣고, 배치된 **종이 사각형**의 실측 크기.
Future<Size> _paperSize(WidgetTester tester, Widget paper) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _cardSize.width,
            height: _cardSize.height,
            child: ColoredBox(
              color: const Color(0xFFE7E3DA), // 책상색
              child: paper,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 30));
  final f = find.byKey(TsakPreviewPaper.paperKey);
  expect(f, findsOneWidget, reason: '종이 사각형을 찾지 못했다');
  return tester.getSize(f);
}

void main() {
  group('종이가 화면에서 실제로 눕는다 (레이아웃 실측)', () {
    testWidgets('세로 → 종이가 세로로 길다', (tester) async {
      final s = await _paperSize(
        tester,
        const TsakPreviewPaper(landscape: false),
      );
      // ignore: avoid_print
      print('세로: 종이 ${s.width}x${s.height}  비율 '
          '${(s.width / s.height).toStringAsFixed(3)}');
      expect(s.height, greaterThan(s.width), reason: '세로인데 종이가 누웠다');
      expect(s.width / s.height, closeTo(210 / 297, 0.01)); // 0.707
    });

    testWidgets('가로 → 종이가 가로로 길다 (핵심 수정)', (tester) async {
      final s = await _paperSize(
        tester,
        const TsakPreviewPaper(landscape: true),
      );
      // ignore: avoid_print
      print('가로: 종이 ${s.width}x${s.height}  비율 '
          '${(s.width / s.height).toStringAsFixed(3)}');
      expect(s.width, greaterThan(s.height), reason: '가로 모드인데 종이가 세로다!');
      expect(s.width / s.height, closeTo(297 / 210, 0.01)); // 1.414
    });

    testWidgets('같은 카드에서 방향만 바꿔도 종이가 뒤집힌다', (tester) async {
      final p = await _paperSize(
        tester,
        const TsakPreviewPaper(landscape: false),
      );
      final l = await _paperSize(
        tester,
        const TsakPreviewPaper(landscape: true),
      );
      // 가로는 폭을 더 쓰고, 세로는 높이를 더 쓴다.
      expect(l.width, greaterThan(p.width), reason: '가로가 세로보다 좁다');
      expect(p.height, greaterThan(l.height), reason: '세로가 가로보다 낮다');
      // 비율이 서로 역수 관계 (같은 A4 를 눕힌 것).
      expect((l.width / l.height) * (p.width / p.height), closeTo(1.0, 0.03));
    });

    testWidgets('두 방향 모두 카드 밖으로 넘치지 않고 충분히 크다', (tester) async {
      for (final land in [false, true]) {
        final s = await _paperSize(
          tester,
          TsakPreviewPaper(landscape: land),
        );
        expect(
          s.width,
          lessThanOrEqualTo(_cardSize.width),
          reason: 'landscape=$land 가로 넘침',
        );
        expect(
          s.height,
          lessThanOrEqualTo(_cardSize.height),
          reason: 'landscape=$land 세로 넘침',
        );
        // 카드 면적의 40% 이상을 채운다(너무 작아 보이지 않게).
        expect(
          s.width * s.height,
          greaterThan(_cardSize.width * _cardSize.height * 0.4),
          reason: 'landscape=$land 종이가 너무 작다: $s',
        );
      }
    });

    testWidgets('로딩 중에도 종이 상자는 방향을 따른다', (tester) async {
      final s = await _paperSize(
        tester,
        const TsakPreviewPaper(landscape: true, loading: true),
      );
      expect(s.width, greaterThan(s.height), reason: '로딩 중 종이가 세로다');
    });

    testWidgets('오류 상태에서도 종이 상자는 방향을 따른다', (tester) async {
      final s = await _paperSize(
        tester,
        const TsakPreviewPaper(landscape: false, error: '테스트 오류'),
      );
      expect(s.height, greaterThan(s.width), reason: '오류 상태 종이가 가로다');
    });
  });
}
