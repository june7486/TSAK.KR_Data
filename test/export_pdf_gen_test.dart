import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:tsak_credential_manager/services/export_service.dart';

/// 두줄 방지 검증용 샘플 PDF 생성기.
/// 실행: flutter test test/export_pdf_gen_test.dart
void main() {
  test('두줄 방지 PDF 샘플 생성', () async {
    final reg = pw.Font.ttf(
      ByteData.view(
        File(
          'assets/fonts/NanumGothic-Regular-s.ttf',
        ).readAsBytesSync().buffer,
      ),
    );
    final bold = pw.Font.ttf(
      ByteData.view(
        File('assets/fonts/NanumGothic-Bold-s.ttf').readAsBytesSync().buffer,
      ),
    );
    final regBytes = ByteData.view(
      File('assets/fonts/NanumGothic-Regular-s.ttf').readAsBytesSync().buffer,
    );
    ExportService.debugSetPdfFonts(
      regular: reg,
      bold: bold,
      regularBytes: regBytes,
    );

    const headers = ['인가번호', '성명', '연락처', '핸드폰', '이메일', '소속대'];
    final rows = [
      ['185', '김진호', '2277-11-28', '010-9188-3784', 'jood@kepco.co.kr', '제484대 연장대'],
      ['188', '김진국', '978-04-17', '011-652-6428', 'shinny@hanmail.net', '제501대 연장대'],
      ['206', '백노현', '1978-12-22', '011-590-9062', 'nhbark@daum.net', '제1373대 연장대'],
      ['402', '박종한', '1990-09-28', '041-363-8832', 'jhpark@kmcvalue.co.kr', '제817단 연장대'],
    ];

    // (가) 두줄 방지 OFF
    final off = await ExportService.buildPdfFromRows(
      headers: headers,
      rows: rows,
      title: '두줄 방지 OFF (비교용)',
      landscape: true,
      noWrapKeys: const {},
    );
    File('/tmp/pdf_nowrap_off.pdf').writeAsBytesSync(off.buffer.asUint8List());

    // (나) 두줄 방지 ON — 이름/인가번호/핸드폰/이메일
    final onFn = await ExportService.buildPdfFromRows(
      headers: headers,
      rows: rows,
      title: '두줄 방지 ON (이름·인가번호·핸드폰·이메일)',
      landscape: true,
      noWrapKeys: const {'name', 'number', 'phone', 'email'},
    );
    File('/tmp/pdf_nowrap_on.pdf').writeAsBytesSync(onFn.buffer.asUint8List());

    // (다) 스트레스 — 세로 + 큰 글씨 + 열 16개(좁아서 두줄 강제 발생).
    const manyHeaders = [
      '인가번호',
      'ATAS',
      '성명',
      '인가일',
      '연락처',
      '핸드폰',
      '연맹',
      '소속대',
      '생일',
      '평생회원',
      '이메일',
      '주소',
      '자격지정',
      '활동',
      '멘토',
      '메모',
    ];
    final manyRows = <List<String>>[
      for (var i = 0; i < 20; i++)
        [
          '${185 + i}',
          'Z307-304',
          ['김진호', '김진국', '백노현', '이경재', '정문권'][i % 5],
          '1977-11-28',
          '2277-11-28',
          '010-9188-3784',
          '전남',
          '제484대 연장대',
          '1960.10.12',
          'O',
          ['jood@kepco.co.kr', 'shinny@hanmail.net'][i % 2],
          '전남 목포시 북교동 115',
          '완료',
          '대장',
          '이승준',
          '특이사항 없음',
        ],
    ];
    final manyOff = await ExportService.buildPdfFromRows(
      headers: manyHeaders,
      rows: manyRows,
      title: '스트레스 OFF · 세로·큰글씨·16열 (두줄 발생)',
      landscape: false,
      fontSize: ExportFontSize.large,
      noWrapKeys: const {},
    );
    File(
      '/tmp/pdf_stress_off.pdf',
    ).writeAsBytesSync(manyOff.buffer.asUint8List());
    final manyOn = await ExportService.buildPdfFromRows(
      headers: manyHeaders,
      rows: manyRows,
      title: '스트레스 ON · 세로·큰글씨·16열 (이름·인가번호·핸드폰·이메일 두줄방지)',
      landscape: false,
      fontSize: ExportFontSize.large,
      noWrapKeys: const {'name', 'number', 'phone', 'email'},
    );
    File(
      '/tmp/pdf_stress_on.pdf',
    ).writeAsBytesSync(manyOn.buffer.asUint8List());

    expect(off.isNotEmpty, isTrue);
    expect(onFn.isNotEmpty, isTrue);
    print('생성: /tmp/pdf_*.pdf');
  });
}
