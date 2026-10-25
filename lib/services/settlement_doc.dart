/// 결산서 → **출력 문서** 변환기 (화면 미리보기 · PDF · JPG · 엑셀 · 워드 공용).
///
/// ## 왜 이 파일이 생겼나 (요구)
/// "결산자료 출력 시스템 변경 -> 추모행사 명단 출력과 같은 시스템과 로직으로
///  변경 (실시간으로 미리보기 화면을 보면서 출력물의 내용과 디자인을 보면서
///  선택할 수 있도록 해줘. 테마를 포함해서), 대신 추가로 하단에 총 8가지
///  템플릿 … 과 PDF, JPG, 엑셀, 워드파일 등도 넣어줘"
///
/// ## 설계 — "보이는 것 = 인쇄되는 것"
/// 종전에는 결산 문서를 만드는 코드가 `event_detail_screen.dart` 안에만 있어,
/// **미리보기 위젯**과 **문서**가 서로 다른 규칙으로 늘어날 위험이 있었다.
/// 이 파일 하나가 유일한 변환 지점이 되어, 미리보기 · PDF · JPG · 엑셀 ·
/// 워드가 **같은 데이터·같은 순서·같은 서식**을 쓴다.
///
/// ## 템플릿 8종과의 관계
/// [DocTemplate] 이 문서의 *모양*(색 띠 / 격자 / 카드 / 색면 / 인장 …)을 정하고,
/// 이 파일은 그 모양에 넣을 *내용*을 만든다. 두 축이 분리돼 있어 템플릿을
/// 바꿔도 데이터가 흔들리지 않는다.
library;

import 'event_settlement.dart';
import 'settlement_layout.dart';
import 'table_export.dart';

/// 결산서 문서 빌더 — 화면·파일 모두 이 함수만 호출한다.
class SettlementDoc {
  const SettlementDoc._();

  /// 블록 데이터 → 4열 표 행 `[구분, 항목, 금액·인원, 비고]`.
  ///
  /// 블록 경계마다 첫 칸에 **블록 이름**을 넣어 "나열"이 아니라 "정리된 표"로
  /// 만든다. CSV(엑셀)·워드·TXT 는 이 4열을 그대로 쓰므로, PDF 의 블록 그래픽과
  /// 내용이 어긋나지 않는다.
  static List<List<String>> tableRows(
    SettlementLayout layout,
    Map<SettlementBlock, SettlementBlockData> data,
  ) {
    final rows = <List<String>>[];
    for (final b in layout.included) {
      final d = data[b];
      if (d == null) continue;
      // 블록 구분 띠 — 첫 칸에 블록명, 나머지는 비운다(엑셀에서 병합 느낌).
      rows.add([b.label, '', '', '']);
      for (final r in d.rows) {
        rows.add([
          '',
          r.isNotEmpty ? r[0] : '',
          r.length > 1 ? r[1] : '',
          r.length > 2 ? r[2] : '',
        ]);
      }
      // 상세 내역(원본 행) — 미리보기에서 켠 블록만. PDF 와 **같은 규칙**.
      if (layout.showsDetail(b)) {
        for (final r in d.detailRows()) {
          rows.add([
            '',
            r.isNotEmpty ? r[0] : '',
            r.length > 1 ? r[1] : '',
            r.length > 2 ? r[2] : '',
          ]);
        }
      }
      if (layout.showNotes && d.note.isNotEmpty) {
        rows.add(['', '· ${d.note}', '', '']);
      }
    }
    return rows;
  }

  /// 결산서 [TsakTableDoc] — PDF/JPG/엑셀/워드/인쇄가 모두 이걸 받는다.
  ///
  /// [year]·[title] 은 문서 제목에, [summary] 는 합계 줄에 쓴다.
  static TsakTableDoc build({
    required String year,
    required String title,
    required SettlementLayout layout,
    required Map<SettlementBlock, SettlementBlockData> data,
    required EventSettlement settlement,
    String Function(int)? won,
  }) {
    final blocks = layout.included;
    final w = won ?? _wonDefault;
    return TsakTableDoc(
      title: '$year $title'.trim(),
      // (요구) "문서의 편집스타일을 넣지마" — 세로/글씨/줄간격 같은 편집기 상태는
      //  문서 내용이 아니므로 부제에 넣지 않는다. '무엇을 담았는지'만 남긴다.
      subtitle: '행사 결산서 · ${blocks.length}개 항목',
      description: '참가자 수·수입·후원·지출·잔액을 항목별로 정리한 결산서입니다.',
      columns: const ['구분', '항목', '금액/인원', '비고'],
      rows: tableRows(layout, data),
      summary: [
        '수입 ${w(settlement.incomeTotal)}'
            ' · 지출 ${w(settlement.expenseTotal)}'
            ' · 잔액 ${w(settlement.balance)}',
        settlement.attendeeCount.summaryLine,
      ],
      footerLeft: '한국범스카우트중앙회 · 행사 결산',
      // 미리보기에서 고른 용지 방향·서식을 그대로 넘긴다.
      landscape: layout.landscape,
      options: layout.toOutputOptions(),
      // PDF/JPG 는 블록 그래픽(보고서)으로, CSV/워드/TXT 는 위 4열 표로 나간다.
      reportBlocks: SettlementReportBuilder.build(layout: layout, data: data),
      // (요구) "총 8가지 템플릿" — 미리보기에서 고른 모양 그대로.
      template: layout.template,
    );
  }

  /// [EventSettlement.comma] 와 같은 기본 포맷(원 단위).
  static String _wonDefault(int v) => '${EventSettlement.comma(v)}원';
}
