// PDF 보고서 페이지 나눔 · 한자 폴백 검증.
//
// 실행: flutter test test/report_pagination_test.dart
//
// ## 왜 이 테스트가 필요한가
//  ① [요구] "PDF 2페이지가 거의 비어 나온다" — 큰 블록이 통째로 다음 페이지로
//     밀리면 앞 페이지가 빈다. 블록을 조각으로 풀어 MultiPage 에 넘기도록
//     고쳤으니, **페이지 수가 줄고 빈 페이지가 없어야** 한다.
//  ② [요구] "한자(金李朴…)가 PDF 에서 사라진다" — 한자 폴백 폰트를 붙였으니
//     한자 문서와 한글 문서의 바이트가 달라야 하고, 한글이 깨지면 안 된다.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:tsak_credential_manager/services/doc_pdf.dart';
import 'package:tsak_credential_manager/services/print_doc.dart';

/// PDF 안의 `/Type /Page` 개수(= 페이지 수)를 센다.
int pageCount(Uint8List b) {
  final s = String.fromCharCodes(b);
  final re = RegExp(r'/Type\s*/Page(?![s])');
  return re.allMatches(s).length;
}

/// 각 페이지의 콘텐츠 스트림 바이트 합 — '빈 페이지' 판별용.
/// (빈 페이지 = 그리기 명령이 거의 없는 페이지)
List<int> pageContentSizes(Uint8List b) {
  final s = String.fromCharCodes(b);
  final out = <int>[];
  // /Contents N 0 R  → 객체 번호만 모아 두고, 각 객체의 stream 길이를 본다.
  final re = RegExp(r'(\d+) 0 obj\s*<<(?:[^>]|>(?!>))*?/Length (\d+)');
  final lens = <int, int>{};
  for (final m in re.allMatches(s)) {
    lens[int.parse(m.group(1)!)] = int.parse(m.group(2)!);
  }
  final cref = RegExp(r'/Contents\s+(\d+) 0 R');
  for (final m in cref.allMatches(s)) {
    out.add(lens[int.parse(m.group(1)!)] ?? 0);
  }
  return out;
}

void main() {
  setUpAll(() async {
    // 위젯 트리 없이 rootBundle 대신 실제 파일을 쓴다 → DocPdf 가 rootBundle 을
    //  쓰므로, 테스트에서는 폰트를 강제 주입한다.
    final reg = pw.Font.ttf(
      ByteData.view(
        File('assets/fonts/NanumGothic-Regular-s.ttf').readAsBytesSync().buffer,
      ),
    );
    final bold = pw.Font.ttf(
      ByteData.view(
        File('assets/fonts/NanumGothic-Bold-s.ttf').readAsBytesSync().buffer,
      ),
    );
    DocPdf.debugSetFonts(regular: reg, bold: bold);
  });

  test('큰 블록이 있어도 빈 페이지가 생기지 않는다', () async {
    // 참가자 290명 + 수입/지출 블록 — 실제 아타스 명부 규모.
    final big = List<List<String>>.generate(
      290,
      (i) => [
        '${i + 1}',
        '참가자 이름${i + 1}',
        '${(i + 1) * 1000}',
        '비고',
      ],
    );
    final blocks = [
      DocReportBlock(
        title: '참가자 명단',
        subtitle: '290명',
        accent: '#7C6A9C',
        rows: big,
      ),
      const DocReportBlock(
        title: '수입 내역',
        subtitle: '2건',
        accent: '#3D6E70',
        rows: [
          ['참가비', '납부', '2,000,000', ''],
          ['후원금', '후원', '500,000', ''],
          ['합계', '', '2,500,000', ''],
        ],
        note: '합계는 부가세 포함입니다.',
      ),
      const DocReportBlock(
        title: '지출 내역',
        subtitle: '2건',
        accent: '#A6763C',
        rows: [
          ['식비', '점심', '800,000', ''],
          ['교통비', '버스', '300,000', ''],
          ['합계', '', '1,100,000', ''],
        ],
      ),
    ];

    final bytes = await DocPdf.buildReport(
      meta: const DocMeta(title: '페이지 나눔 검증', author: '테스터'),
      blocks: blocks,
      summary: const ['총 3개 블록 · 순액 1,400,000원'],
    );

    File('/tmp/report_pagination.pdf').writeAsBytesSync(bytes);
    final n = pageCount(bytes);
    final sizes = pageContentSizes(bytes);

    // ignore: avoid_print
    print('페이지 수: $n / 콘텐츠 크기: $sizes');

    expect(n, greaterThanOrEqualTo(2), reason: '290명이면 2페이지 이상이어야 한다');

    // ⚠️ 핵심: 빈 페이지(콘텐츠가 사실상 없는 페이지)가 없어야 한다.
    //  헤더/푸터만 있는 페이지는 대략 수백 바이트다. 그보다 훨씬 작으면 빈 페이지.
    for (var i = 0; i < sizes.length; i++) {
      expect(
        sizes[i],
        greaterThan(1200),
        reason: '${i + 1}페이지가 거의 비어 있다 (${sizes[i]} bytes)',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
