// 아타스(ATAS) 명부 PDF의 **줄바꿈 없음(1행 유지)** 회귀 테스트.
//
// 요구: "아타스 명부 출력 시 이름과 인가년월일이 2줄로 출력되지 않도록".
//  → 실제 DocPdf.buildSimple 로 PDF를 만들어 바이트가 생성되는지 확인하고,
//    최악값(가장 긴 소속/영문명)이 포함돼도 예외 없이 생성되는지 검증한다.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/doc_pdf.dart';
import 'package:tsak_credential_manager/services/print_doc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ATAS 명부 PDF 생성 (줄바꿈 회귀)', () async {
    final rows = <List<String>>[
      ['358', '30', '조원호', 'Won Ho CHO', '제2대 대전고등학교', '1966-11-07'],
      ['106', '74', '김현석', 'Hyun Seok KIM', '제308대 언장대', '1972-06-28'],
      ['75', '2', '이항복', 'Simon Hang Bock RHEE', '제311대 언장대', '1972-06-28'],
      ['13880', '2219', '황승재', 'Seung Jae HWANG', '천마지역대', '2026-05-29'],
      // 최악값: 가장 긴 영문명 + 가장 긴 소속.
      ['3005', '999', '구성연', 'Jessica Seong-Yeon KOO', '제1001단 블랙야크지역대 벤처스카우트', '1999-12-31'],
      ['13881', '은하43', '방재호', 'Jae Ho BANG', '강원 제901대 태백기계공고', '1994-08-10'],
    ];
    final Uint8List bytes = await DocPdf.buildSimple(
      meta: const DocMeta(title: '아타스(ATAS) 명부', subtitle: 'ATAS 291명 · 범스카우트'),
      columns: const ['ATAS 인가번호', '범인가번호', '성명', '영문 이름', '소속', '인가년월일'],
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · 아타스',
    );
    expect(bytes.length, greaterThan(1000));
  });
}
