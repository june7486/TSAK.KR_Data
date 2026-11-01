// 가로/세로 PDF 를 **실제 이미지로 렌더**해 눈으로 확인할 수 있게 만든다.
//
// ## 왜 만드는가 (2026-11-02, build #569)
//  build #567/#568 에서 "가로 모드인데 세로처럼 보인다" 를 수정했고, 값은
//  레이아웃 실측(비율 0.707 / 1.414)으로 고정했다. 그래도 **사람이 눈으로 볼
//  산출물**이 없으면 "정말 낫나?" 를 확인할 수 없다.
//  → 이 테스트는 실제 문서를 가로·세로로 각각 PDF 로 만들고, PNG 로 렌더해
//    build/pdf_check/ 에 남긴다. 실패하면 안 되는 검증(치수)과
//    눈으로 보는 산출물(이미지)을 한 번에 얻는다.
//
// ## 산출물
//   build/pdf_check/
//     ├─ landscape_A4.pdf / landscape_A4.png   (가로 841.9 x 595.3)
//     └─ portrait_A4.pdf  / portrait_A4.png    (세로 595.3 x 841.9)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tsak_credential_manager/services/doc_pdf.dart';
import 'package:tsak_credential_manager/services/print_doc.dart';

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

/// 스크린샷(Kb1wbB71)과 같은 9열 명부 — 8명.
const List<String> _cols = [
  '#',
  '접속',
  '인가번호',
  '이름',
  '소속(활동)',
  '성별',
  '연락처',
  '메일',
  '항목',
];

const List<List<String>> _rows = [
  ['1', 'V', '범#75', '이승준', '제311대 연장대', '남', '010-9367-3344', 'simonrhee75@gmail.com', '전체'],
  ['2', 'V', '범#135', '김종환', '제1378대 연장대', '남', '010-3590-2280', 'kgh135@naver.com', '전체'],
  ['3', 'V', '범#305', '김원태', '스카우트비피클럽', '남', '010-8591-3009', 'scouter305@naver.com', '전체'],
  ['4', 'V', '범#2186', '현지환', '제2100대 연장대', '남', '010-4471-8820', 'hj2186@gmail.com', '전체'],
  ['5', 'V', '범#590', '현승용', '제1200대 연장대', '남', '010-2211-7745', 'hs590@naver.com', '전체'],
  ['6', 'V', '은하165', '박은하', '사이버한국외대', '여', '010-8823-1140', 'eunha165@nate.com', '전체'],
  ['7', 'V', '범#412', '양다솜', '제412대 연장대', '여', '010-5567-9901', 'dasom412@gmail.com', '전체'],
  ['8', 'V', '범#77', '최민석', '제77대 연장대', '남', '010-3344-7788', 'ms77@hanmail.net', '전체'],
];

/// PDF 첫 페이지를 PNG 로 렌더한다(PyMuPDF 는 /usr/local/bin/python3 에만 있다).
Future<bool> _renderPng(String pdfPath, String pngPath) async {
  for (final py in ['/usr/local/bin/python3', 'python3']) {
    try {
      final r = await Process.run(py, [
        '-c',
        'import pymupdf,sys\n'
            'd=pymupdf.open(sys.argv[1])\n'
            'p=d[0]\n'
            'p.get_pixmap(dpi=120).save(sys.argv[2])\n'
            'print(round(p.rect.width,1), round(p.rect.height,1))\n',
        pdfPath,
        pngPath,
      ]);
      if (r.exitCode == 0) {
        // ignore: avoid_print
        print('  → $pdfPath  ${(r.stdout as String).trim()}pt'
            '  (${File(pdfPath).lengthSync() ~/ 1024}KB)');
        return true;
      }
    } catch (_) {
      continue;
    }
  }
  return false;
}

Future<(double, double)> _pageSize(String path) async {
  final r = await Process.run('/usr/local/bin/python3', [
    '-c',
    'import pymupdf,sys\n'
        'd=pymupdf.open(sys.argv[1])\n'
        'p=d[0]\n'
        'print(p.rect.width, p.rect.height)\n',
    path,
  ]);
  final p = (r.stdout as String).trim().split(RegExp(r'\s+'));
  return (double.parse(p[0]), double.parse(p[1]));
}

void main() {
  setUpAll(_injectFonts);

  test('가로/세로 명부 PDF 를 만들고 이미지로 렌더한다', () async {
    final dir = Directory('build/pdf_check');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final meta = DocMeta(
      title: '2026 ATAS와 사이버한국외국어대학교 MOU, PARAM 서상훈련원 방문',
      author: '한국범스카우트중앙회',
      createdAt: '2026-11-02 10:00',
    );

    // ── 가로 ──
    final landPdf = await DocPdf.buildSimple(
      meta: meta,
      columns: _cols,
      rows: _rows,
      summary: const ['총 8명'],
      landscape: true,
    );
    final landPath = 'build/pdf_check/landscape_A4.pdf';
    await File(landPath).writeAsBytes(landPdf);
    final land = await _pageSize(landPath);
    expect(land.$1, greaterThan(land.$2), reason: '가로인데 세로로 나왔다');
    expect(land.$1, closeTo(841.9, 2.0));
    expect(land.$2, closeTo(595.3, 2.0));
    expect(
      await _renderPng(landPath, 'build/pdf_check/landscape_A4.png'),
      isTrue,
      reason: '가로 PDF 를 이미지로 렌더하지 못했다',
    );

    // ── 세로(대조군) ──
    final portPdf = await DocPdf.buildSimple(
      meta: meta,
      columns: _cols,
      rows: _rows,
      summary: const ['총 8명'],
    );
    final portPath = 'build/pdf_check/portrait_A4.pdf';
    await File(portPath).writeAsBytes(portPdf);
    final port = await _pageSize(portPath);
    expect(port.$2, greaterThan(port.$1), reason: '세로인데 가로로 나왔다');
    expect(port.$1, closeTo(595.3, 2.0));
    expect(port.$2, closeTo(841.9, 2.0));
    expect(
      await _renderPng(portPath, 'build/pdf_check/portrait_A4.png'),
      isTrue,
      reason: '세로 PDF 를 이미지로 렌더하지 못했다',
    );

    // 산출물이 실제로 남았는지 확인.
    for (final f in [
      'build/pdf_check/landscape_A4.pdf',
      'build/pdf_check/landscape_A4.png',
      'build/pdf_check/portrait_A4.pdf',
      'build/pdf_check/portrait_A4.png',
    ]) {
      expect(File(f).existsSync(), isTrue, reason: '$f 가 없다');
      expect(File(f).lengthSync(), greaterThan(1000), reason: '$f 가 비었다');
    }
  });
}
