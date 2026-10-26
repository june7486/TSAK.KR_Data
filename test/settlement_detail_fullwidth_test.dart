// [요구 2026-10-26] "결산자료 출력시 상세항목이 칸을 넓게 사용하지 않는
//  레이아웃임 → 옆간을 모두 사용하도록 변경 (기존요청사항임)"
//
//  ## 고정하는 규칙
//  상세 행(`['· 상세', 원본내용, '', '']`)은 4열 표 안에 넣지 않는다.
//  표 **아래 전폭 블록**(`.bdet`)으로 나가야 옆간을 모두 쓴다.
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/print_doc.dart';

void main() {
  DocMeta meta = const DocMeta(title: '테스트 결산서');

  /// 상세가 섞인 블록 하나짜리 문서.
  List<DocReportBlock> blocks() => [
        const DocReportBlock(
          title: '후원 내역',
          subtitle: '2행',
          rows: [
            ['식사후원', '140,000원', '1건', ''],
            ['물품후원', '80,000원', '1건', ''],
            ['· 상세', '이승준 · 물품후원 · 박스40병 · 80,000원 · 2026년서울북부연맹', '', ''],
            ['· 상세', '이항복 · 식사후원 · 140,000원 · 제944기지도자훈련상급과정', '', ''],
          ],
        ),
      ];

  test('상세 행은 4열 표 안에 남지 않는다', () {
    final html = buildReportDocHtml(meta: meta, blocks: blocks());
    // 표 본문에는 '· 상세' 라는 1번째 칸 글자가 없어야 한다.
    final tbl = RegExp(r'<table class="bt-tbl">.*?</table>', dotAll: true)
        .stringMatch(html);
    expect(tbl, isNotNull);
    expect(tbl!.contains('· 상세'), isFalse,
        reason: '상세 행이 표 안에 남아 있으면 좁은 칸에 갇힌다');
  });

  test('상세는 전폭 블록(.bdet)으로 나간다', () {
    final html = buildReportDocHtml(meta: meta, blocks: blocks());
    expect(html.contains('class="bdet"'), isTrue);
    expect(html.contains('class="bdb"'), isTrue);
    expect(html.contains('상세 내역 · 2건'), isTrue);
  });

  test('상세 원본 문자열이 잘리지 않고 모두 실린다', () {
    final html = buildReportDocHtml(meta: meta, blocks: blocks());
    expect(html.contains('박스40병'), isTrue);
    expect(html.contains('제944기지도자훈련상급과정'), isTrue);
  });

  test('일반 행(합계 등)은 그대로 표에 남는다', () {
    final html = buildReportDocHtml(
      meta: meta,
      blocks: const [
        DocReportBlock(
          title: '수입',
          rows: [
            ['참가비', '0원', '2명 납부', ''],
            ['수입 합계', '0원', '', ''],
          ],
        ),
      ],
    );
    final tbl = RegExp(r'<table class="bt-tbl">.*?</table>', dotAll: true)
        .stringMatch(html);
    expect(tbl!.contains('수입 합계'), isTrue);
    expect(html.contains('class="bdet"'), isFalse, reason: '상세가 없으면 블록도 없다');
  });
}
