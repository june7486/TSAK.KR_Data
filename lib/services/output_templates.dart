/// **출력 템플릿 6종** — 보고서·결산 인쇄물의 *모양*을 사용자가 고른다.
///
/// ## 왜 필요한가 (요구)
/// "pdf 출력물의 형태는 결산의 경우 기존 무인양품 스타일을 버리고, 미리보기
/// 항목의 내용을 참조해서 항목별로 보기좋게 출력 … 보고서처럼"
/// "출력폼에 대한 옵션을 6가지 정도 템플릿을 만들어서 선택할 수 있도록"
///
/// 지금까지 출력물 모양은 **코드에 박혀** 있었다. 그래서 사용자가 "계산서
/// 같다"고 느껴도 화면에서 바꿀 방법이 없었다. 이 파일은 모양을 **데이터**로
/// 끌어올린다 — `DocTemplate` 하나를 고르면 색 띠·여백·괘선·머리행·합계
/// 강조가 통째로 바뀐다.
///
/// ## 6종의 성격
/// | 템플릿 | 느낌 | 잘 맞는 곳 |
/// |---|---|---|
/// | `report`  | 컬러 띠 블록 · 넉넉한 여백 | 기본. 결산서·사업보고 |
/// | `ledger`  | 조밀한 괘선 · 우측 정렬 강조 | 회계장부·대장 |
/// | `card`    | 블록마다 둥근 카드 | 안내문·배포용 |
/// | `minimal` | 괘선 최소 · 흑백 | 흑백 인쇄·스캔 |
/// | `official`| 격자 테두리 · 제목 가운데 | 공문·제출용 |
/// | `brief`   | 큰 숫자 요약 먼저 | 임원 보고·슬라이드 |
///
/// 이 파일은 **Flutter 를 import 하지 않는다**(순수 Dart) — `dart run` 으로
/// 검증 하네스를 돌리기 위해서다(`tool/verify_output_templates.dart`).
library;

/// 인쇄물의 시각적 정체성.
enum DocTemplate {
  /// 컬러 띠 + 넉넉한 여백. 종전 `buildReport` 모양 그대로.
  report(
    '보고서형',
    '항목마다 색 띠 · 가장 무난한 결산서',
    accentBand: true,
    cardShell: false,
    gridLines: false,
    centerTitle: false,
    bigFigures: false,
    compact: false,
    tintTotal: 0.055,
    bandAlpha: 0.10,
    bandWidth: 3,
    blockGap: 10,
    cellPadH: 6,
    cellPadV: 4,
  ),

  /// 회계장부 — 조밀하고 괘선이 살아 있다. 금액 열을 우측 정렬.
  ledger(
    '장부형',
    '촘촘한 괘선 · 회계장부 느낌',
    accentBand: false,
    cardShell: false,
    gridLines: true,
    centerTitle: false,
    bigFigures: false,
    compact: true,
    tintTotal: 0.08,
    bandAlpha: 0.0,
    bandWidth: 0,
    blockGap: 6,
    cellPadH: 4,
    cellPadV: 2.5,
  ),

  /// 카드 — 블록마다 둥근 사각형으로 분리. 여백 최대.
  card(
    '카드형',
    '블록마다 둥근 카드 · 읽기 편함',
    accentBand: true,
    cardShell: true,
    gridLines: false,
    centerTitle: false,
    bigFigures: false,
    compact: false,
    tintTotal: 0.05,
    bandAlpha: 0.13,
    bandWidth: 4,
    blockGap: 14,
    cellPadH: 7,
    cellPadV: 5,
  ),

  /// 미니멀 — 괘선 거의 없음. 흑백 인쇄에서도 깔끔.
  minimal(
    '미니멀형',
    '괘선 최소 · 흑백 인쇄에 강함',
    accentBand: false,
    cardShell: false,
    gridLines: false,
    centerTitle: false,
    bigFigures: false,
    compact: false,
    tintTotal: 0.0,
    bandAlpha: 0.0,
    bandWidth: 0,
    blockGap: 12,
    cellPadH: 6,
    cellPadV: 5,
  ),

  /// 공문 — 전체 격자 + 가운데 제목. 제출·보관용.
  official(
    '공문서형',
    '격자 테두리 · 제목 가운데 · 제출용',
    accentBand: false,
    cardShell: false,
    gridLines: true,
    centerTitle: true,
    bigFigures: false,
    compact: false,
    tintTotal: 0.0,
    bandAlpha: 0.0,
    bandWidth: 0,
    blockGap: 8,
    cellPadH: 6,
    cellPadV: 4.5,
  ),

  /// 브리핑 — 항목별 **핵심 숫자를 크게**. 임원 보고용.
  brief(
    '브리핑형',
    '핵심 숫자를 크게 · 임원 보고용',
    accentBand: true,
    cardShell: true,
    gridLines: false,
    centerTitle: false,
    bigFigures: true,
    compact: false,
    tintTotal: 0.07,
    bandAlpha: 0.12,
    bandWidth: 4,
    blockGap: 12,
    cellPadH: 6,
    cellPadV: 4,
  );

  const DocTemplate(
    this.label,
    this.hint, {
    required this.accentBand,
    required this.cardShell,
    required this.gridLines,
    required this.centerTitle,
    required this.bigFigures,
    required this.compact,
    required this.tintTotal,
    required this.bandAlpha,
    required this.bandWidth,
    required this.blockGap,
    required this.cellPadH,
    required this.cellPadV,
  });

  /// 사용자에게 보이는 이름.
  final String label;

  /// 한 줄 설명(선택 시트에 표시).
  final String hint;

  /// 블록 제목에 컬러 띠(좌측 바 + 틴트)를 그리는가.
  final bool accentBand;

  /// 블록 전체를 둥근 카드 테두리로 감싸는가.
  final bool cardShell;

  /// 행 사이 가로 괘선을 그리는가.
  final bool gridLines;

  /// 문서 제목을 가운데 정렬하는가.
  final bool centerTitle;

  /// 요약 숫자를 큰 글씨로 먼저 보여주는가.
  final bool bigFigures;

  /// 행 높이를 줄여 더 많이 담는가.
  final bool compact;

  /// 합계 행 배경 틴트 알파(0이면 없음).
  final double tintTotal;

  /// 블록 띠 배경 틴트 알파.
  final double bandAlpha;

  /// 블록 좌측 바 두께(pt). 0이면 없음.
  final double bandWidth;

  /// 블록 사이 세로 여백(pt).
  final double blockGap;

  /// 셀 좌우 여백(pt).
  final double cellPadH;

  /// 셀 상하 여백(pt).
  final double cellPadV;

  /// 이 템플릿이 **표 형태**를 쓰는가(= 보고서형이 아닌가).
  ///
  /// `ledger`·`official` 은 괘선 위주의 표, 나머지는 블록 그래픽.
  bool get isTabular => gridLines && !accentBand && !cardShell;

  /// 배지용 짧은 이름.
  String get short => label.replaceAll('형', '');

  /// 문자열 → 템플릿(모르면 [report]).
  static DocTemplate parse(String? raw) {
    final k = (raw ?? '').trim().toLowerCase();
    for (final t in DocTemplate.values) {
      if (t.name == k) return t;
    }
    // 한글 이름으로도 받아준다(저장값 호환).
    for (final t in DocTemplate.values) {
      if (t.label == (raw ?? '').trim()) return t;
    }
    return DocTemplate.report;
  }

  /// 선택 시트에 나열할 순서(요구: "6가지 정도").
  static List<DocTemplate> get all => const [
    DocTemplate.report,
    DocTemplate.ledger,
    DocTemplate.card,
    DocTemplate.minimal,
    DocTemplate.official,
    DocTemplate.brief,
  ];

  /// 다음 템플릿(빠른 순환 버튼용).
  DocTemplate get next {
    final list = DocTemplate.all;
    final i = list.indexOf(this);
    return list[(i + 1) % list.length];
  }
}

/// 템플릿 목록을 **JSON 안전**한 문자열로 — 저장/복원용.
String encodeTemplate(DocTemplate t) => t.name;
