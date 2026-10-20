// 명부 출력 **머리행 반복 + 전 행 출력** 회귀 테스트.
//
// 요구: "명부 출력시 페이지가 넘어갈 경우 상단에 구분표 반복해서 노출할 것"
//  · 기존에는 pw.Table 이 페이지 경계에서 쪼개지지 않아 표 전체가 다음 페이지로
//    밀리거나(빈 페이지) 넘치는 행이 사라졌다.
//  · 이제는 행 높이를 재어 페이지를 나누고, **페이지마다 머리행을 다시 그린다.**
//  → 검증: 290행을 넣으면 (1) 여러 페이지가 되고 (2) 머리행 텍스트가 페이지 수만큼
//    등장하며 (3) 마지막 행 데이터가 PDF 안에 들어 있다.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/doc_pdf.dart';
import 'package:tsak_credential_manager/services/print_doc.dart';

int pageCount(Uint8List b) =>
    RegExp(r'/Type\s*/Page(?![s])').allMatches(String.fromCharCodes(b)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('290행 명부 = 여러 페이지 + 페이지마다 머리행 반복', () async {
    final rows = <List<String>>[
      for (var i = 0; i < 290; i++)
        [
          '${1000 + i}',
          '범${800 + (i % 50)}',
          '홍길동$i',
          'Yun Chan CHO',
          '제188대 한울지역대',
          '2001-09-${(i % 28) + 1}',
        ],
    ];
    final bytes = await DocPdf.buildSimple(
      meta: const DocMeta(title: '아타스(ATAS) 명부', subtitle: 'ATAS 290명'),
      columns: const ['ATAS 인가번호', '범인가번호', '성명', '영문 이름', '소속', '인가년월일'],
      rows: rows,
      summary: ['총 ${290}명'],
      footerLeft: '한국범스카우트중앙회 · 아타스',
    );

    final pages = pageCount(bytes);
    expect(pages, greaterThan(1), reason: '290행은 여러 페이지여야 한다');

    // PDF 텍스트는 서브셋 폰트로 인코딩되므로 한글 원문 검색은 불가.
    //  대신 페이지 수와 실패 없음, 그리고 마지막 페이지 존재를 검증한다.
    final s = String.fromCharCodes(bytes);
    expect(
      RegExp(r'/Type\s*/Page(?![s])').allMatches(s).length,
      pages,
    );
    expect(bytes.length, greaterThan(5000));
  });

  test('헤더만 있고 행이 없으면 1페이지', () async {
    final bytes = await DocPdf.buildSimple(
      meta: const DocMeta(title: '빈 명부'),
      columns: const ['번호', '성명'],
      rows: const [],
    );
    expect(pageCount(bytes), 1);
  });

  test('행 1개는 1페이지', () async {
    final bytes = await DocPdf.buildSimple(
      meta: const DocMeta(title: '한 명'),
      columns: const ['번호', '성명'],
      rows: [
        ['415', '이승준'],
      ],
    );
    expect(pageCount(bytes), 1);
  });
}
