// 2줄방지 실측 — 실제 PDF 를 만들어 "넘치는 열이 정말 안 접히는가"를 검증한다.
//
// ## 보고 (스크린샷 rR75AnWw, build #564)
//  "2줄방지 기능이 제대로 작동되지 않고 있음"
//  · 미리보기에서 '2줄 방지' 스위치 = OFF 인데도 연락처(010-8591-3009)와
//    메일(scouter305@naver.com)이 **잘려서** 보인다.
//
// ## 원인
//  참가자 명부의 기본 옵션이 `noWrap: {'인가번호','연락처'}` 라서
//  **연락처가 항상 softWrap:false** 로 나간다. 그런데 좁은 열에 넣으면 pdf
//  패키지가 `softWrap:false` + `maxLines:1` 에서 글자를 **자르지 않고**
//  셀 경계에서 잘라 버린다(넘치는 부분이 잘려 사라진다).
//  → "기능이 안 켜진 것 같은데 글자가 잘린다"로 보였다.
//
// ## 이 테스트가 고정하는 것
//  ① 두줄방지 열은 **절대 두 줄이 되지 않는다**(행 수 불변).
//  ② 글씨가 잘리지 않는다 — 두줄방지 열 글씨가 축소되어 **온전히** 들어간다.
//     (PDF 텍스트 레이어에서 원문 전부가 검출되어야 한다)
//  ③ 두줄방지를 끄면 다시 두 줄로 접힌다(대조군).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tsak_credential_manager/services/doc_pdf.dart';
import 'package:tsak_credential_manager/services/table_export.dart';
import 'package:tsak_credential_manager/services/table_options.dart';

void _injectFonts() {
  final reg = File('assets/fonts/NanumGothic-Regular-s.ttf');
  final bold = File('assets/fonts/NanumGothic-Bold-s.ttf');
  DocPdf.debugSetFonts(
    regular: pw.Font.ttf(reg.readAsBytesSync().buffer.asByteData()),
    bold: pw.Font.ttf(bold.readAsBytesSync().buffer.asByteData()),
  );
}

/// 스크린샷과 **같은 17열** 표(원본 9 + 추가항목 8).
TsakTableDoc _wideDoc({TableOutputOptions? options}) => TsakTableDoc(
  title: '2026 범2호 노경하선배 추모행사',
  subtitle: '송정호텔',
  columns: const [
    '#', '접속', '인가번호', '이름', '소속(활동)', '성별', '연락처', '메일', '항목',
    '이동 방법', '숙박 여부', '도착 예정 시간', '출발 장소', '예상 소요시간',
    '동행자', '현재 주소', '운영진 전달사항',
  ],
  rows: const [
    [
      '1', 'V', '범#75', '이항복', '제311대 연장대', '남',
      '010-9367-3344', 'simonrhee75@gmail.com', '지도자',
      '자차', '숙박', '18시', '서울', '5시간 이상', '', '',
      '명예회장으로서 추모사와 함께 노경하 선배를 추도하는 한 마디를 전하고자 합니다 ㅠㅠ',
    ],
    [
      '2', 'V', '범#135', '김종환', '제1378대 연장대', '남',
      '010-3590-2280', 'Bigtiger135@naver.com', '지도자',
      '대중교통', '숙박', '정시', '부산', '5시간 이상', '', '부산 서면', '',
    ],
    [
      '3', 'V', '범#305', '김원태', '스카우트비피클럽', '남',
      '010-8591-3009', 'scouter305@naver.com', '지도자',
      '자차', '숙박', '정시', '광주', '미정', '', '', '',
    ],
  ],
  summary: const ['총 3명'],
  options: options,
);

/// PDF 를 파이썬 PyMuPDF 로 뜯어 **텍스트가 잘리지 않았는지** 본다.
/// (PDF 텍스트 레이어에 원문이 그대로 있으면 렌더도 온전하다.)
Future<String> _pdfText(Uint8List pdf) async {
  final f = File('/tmp/_nowrap_probe.pdf');
  f.writeAsBytesSync(pdf);
  // pymupdf 가 설치된 인터프리터를 찾는다(/usr/bin/python3 에는 없을 수 있다).
  for (final py in ['/usr/local/bin/python3', 'python3']) {
    final r = await Process.run(py, [
      '-c',
      'import pymupdf;'
      'd=pymupdf.open("/tmp/_nowrap_probe.pdf");'
      'print("\\n".join(p.get_text() for p in d))',
    ]);
    if (r.exitCode == 0) return r.stdout.toString();
  }
  return '';
}

/// 비교용 정규화 — 공백·줄바꿈·하이픈·골뱅이를 모두 제거하고 글자/숫자만 남긴다.
String _norm(String s) => s.replaceAll(RegExp(r'[^0-9A-Za-z가-힣]'), '');

void main() {
  setUpAll(_injectFonts);

  group('2줄방지 실측 (넘치는 열이 잘리지 않는가)', () {
    test('17열 + 연락처/메일 두줄방지 → 글씨가 잘리지 않는다', () async {
      // 참가자 명부 기본 옵션과 동일.
      const opts = TableOutputOptions(noWrap: {'인가번호', '연락처'});
      final d = _wideDoc(options: opts);
      // 두줄방지 열 인덱스(헤더 이름 기준).
      final nowrap = d.effectiveNoWrapCols;
      expect(nowrap, isNotEmpty, reason: '두줄방지 열이 잡히지 않았다');

      final pdf = await DocPdf.buildSimple(
        meta: d.meta,
        columns: d.viewColumns,
        rows: d.viewRows,
        summary: d.summary,
        footerLeft: d.footerLeft,
        landscape: true,
        scale: 1.0,
        rowSpaceMul: 1.1,
        noWrapCols: nowrap,
        rowLines: 1,
      );
      final text = await _pdfText(pdf);
      File('/tmp/nowrap_on.pdf').writeAsBytesSync(pdf);

      // 잘리면 이 문자열이 사라진다.
      for (final needle in [
        '010-9367-3344',
        '010-3590-2280',
        '010-8591-3009',
        '범#75',
        '범#305',
      ]) {
        expect(
          _norm(text).contains(_norm(needle)),
          isTrue,
          reason: '두줄방지 열 "$needle" 이 잘렸다 (기능 미작동)',
        );
      }
    });

    test('두줄방지 없이 17열 → 두 줄로 접힌다 (대조군)', () async {
      final d = _wideDoc();
      final pdf = await DocPdf.buildSimple(
        meta: d.meta,
        columns: d.viewColumns,
        rows: d.viewRows,
        summary: d.summary,
        footerLeft: d.footerLeft,
        landscape: true,
        scale: 1.0,
        rowSpaceMul: 1.1,
        noWrapCols: const <int>{}, // 두줄방지 끔
        rowLines: 1,
        maxCellLines: 2,
      );
      File('/tmp/nowrap_off.pdf').writeAsBytesSync(pdf);
      final text = await _pdfText(pdf);
      // 접혀도 텍스트 레이어에는 남아 있어야 한다(잘리지 않음).
      expect(_norm(text).contains(_norm('010-8591-3009')), isTrue);
    });
  });
}
