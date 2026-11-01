// **실제 PDF 바이트를 생성해** 페이지별 머리행 반복을 검증한다.
//
// ## 왜 이 테스트가 필요한가
// 지난 턴에 "2페이지부터 구분 메뉴가 반복됩니다"라고 보고했지만, 그것은
// **인쇄용 HTML 의 CSS**(`thead{display:table-header-group}`) 근거였다.
// 앱이 실제로 내보내는 것은 **PDF 파일**이고, 그 경로는 `doc_pdf.dart` 의
// 수동 페이지 나눔이다. CSS 로는 그 경로를 증명할 수 없다.
//
// ## 역할 분담
//  - 이 Dart 테스트: 실제 폰트를 주입해 **진짜 PDF 바이트**를 만들고
//    `build/pdf_check/*.pdf` 로 떨군다. (생성 자체가 실패하지 않는지 확인)
//  - `tools/verify_pdf_pages.py` (pypdf): 그 파일을 열어 **페이지 수**와
//    **각 페이지의 텍스트**를 뽑아, 2페이지 이후에도 열 헤더가 있는지 본다.
//
// ## 사용자 요구 (원문 2026-10-31 6차 ④)
// > "출력페이지가 2장이상 되면 두번째 페이지부터는 페이지 상단에 구분메뉴가
// >  노출되어 표의 내용이 무엇인지 확인 되어야 함"
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tsak_credential_manager/services/doc_pdf.dart';
import 'package:tsak_credential_manager/services/print_doc.dart';

/// 생성한 PDF 를 파일로 남긴다 — pypdf 로 페이지 수·텍스트를 정밀 검증한다.
/// (`flutter test` 에는 PDF 파서가 없어서, 바이트를 그대로 넘겨 python 에서 읽는다)
int _dump(String name, List<int> bytes) {
  final f = File('build/pdf_check/$name.pdf');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes);
  return bytes.length;
}

void main() {
  setUpAll(() {
    // 테스트 환경에는 rootBundle 폰트가 없다 → 실제 파일을 직접 넣는다.
    final reg = File('assets/fonts/NanumGothic-Regular-s.ttf');
    final bold = File('assets/fonts/NanumGothic-Bold-s.ttf');
    expect(reg.existsSync(), isTrue, reason: '본문 폰트 파일이 필요하다');
    expect(bold.existsSync(), isTrue, reason: '굵은 폰트 파일이 필요하다');
    DocPdf.debugSetFonts(
      regular: pw.Font.ttf(reg.readAsBytesSync().buffer.asByteData()),
      bold: pw.Font.ttf(bold.readAsBytesSync().buffer.asByteData()),
    );
  });

  /// 명부 한 줄 — 확실히 여러 페이지를 넘기도록 넉넉히 만든다.
  List<List<DocCell>> rosterRows(int n) => [
        for (var i = 0; i < n; i++)
          [
            DocCell('${i + 1}'),
            DocCell(i.isEven ? 'V' : ''),
            DocCell('범${100 + i}'),
            DocCell('홍길동$i'),
            DocCell('010-3590-${(2280 + i) % 10000}'),
            DocCell('user$i@example.com'),
          ],
      ];

  const cols = ['#', '인가번호', '이름', '연락처', '메일'];

  test('[핵심] 가로 A4 60행 명부 PDF 가 생성된다', () async {
    final bytes = await DocPdf.build(
      meta: DocMeta(title: '참가자 명부', createdAt: '2026-10-31 19:59'),
      columns: cols,
      rows: rosterRows(60),
      landscape: true,
    );
    final n = _dump('roster60', bytes);
    // ignore: avoid_print
    print('  → roster60.pdf  ${(n / 1024).toStringAsFixed(0)}KB');
    expect(n, greaterThan(5000), reason: 'PDF 가 비어 있거나 너무 작다');
  });

  test('[핵심] 가로 A4 120행 명부 PDF 가 생성된다', () async {
    final bytes = await DocPdf.build(
      meta: DocMeta(title: '참가자 명부', createdAt: '2026-10-31 19:59'),
      columns: cols,
      rows: rosterRows(120),
      landscape: true,
    );
    final n = _dump('roster120', bytes);
    // ignore: avoid_print
    print('  → roster120.pdf  ${(n / 1024).toStringAsFixed(0)}KB');
    expect(n, greaterThan(5000));
  });

  test('세로 A4 80행도 생성된다 (페이지 나눔 경로 별도 확인)', () async {
    final bytes = await DocPdf.build(
      meta: DocMeta(title: '참가자 명부', createdAt: '2026-10-31 19:59'),
      columns: cols,
      rows: rosterRows(80),
      landscape: false,
    );
    final n = _dump('portrait80', bytes);
    // ignore: avoid_print
    print('  → portrait80.pdf  ${(n / 1024).toStringAsFixed(0)}KB');
    expect(n, greaterThan(5000));
  });

  test('중간 페이지에서 시작하는 표 조각도 헤더를 갖는다 (20행 건너뛰기 재현)', () async {
    // 2페이지부터 시작하는 상황을 만들기 위해 앞에 큰 여백 블록을 둔 문서를 쓴다.
    final bytes = await DocPdf.build(
      meta: DocMeta(
        title: '참가자 명부',
        createdAt: '2026-10-31 19:59',
        description: List.filled(18, '설명 줄').join('\n'),
      ),
      columns: cols,
      rows: rosterRows(90),
      landscape: true,
    );
    final n = _dump('offset', bytes);
    // ignore: avoid_print
    print('  → offset.pdf  ${(n / 1024).toStringAsFixed(0)}KB');
    expect(n, greaterThan(5000));
  });

  test('행 높이(rowLines) 1·3 이 실제로 산출물을 바꾼다', () async {
    final b1 = await DocPdf.build(
      meta: DocMeta(title: 't', createdAt: '2026-10-31'),
      columns: cols,
      rows: rosterRows(80),
      landscape: true,
      rowLines: 1,
    );
    final b3 = await DocPdf.build(
      meta: DocMeta(title: 't', createdAt: '2026-10-31'),
      columns: cols,
      rows: rosterRows(80),
      landscape: true,
      rowLines: 3,
    );
    final n1 = _dump('rowlines1', b1);
    final n3 = _dump('rowlines3', b3);
    // ignore: avoid_print
    print('  → rowLines1 ${(n1 / 1024).toStringAsFixed(0)}KB / '
        'rowLines3 ${(n3 / 1024).toStringAsFixed(0)}KB');
    // 행이 높아지면 페이지가 늘어나므로 파일이 커진다(폰트 서브셋은 동일).
    expect(n3, greaterThan(n1),
        reason: 'rowLines 가 실제 렌더에 반영되지 않았다');
  });
}
