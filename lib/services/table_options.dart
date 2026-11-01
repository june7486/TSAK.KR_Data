/// 표(리스트) 출력 옵션 모델 — 출력내용선택 · 위치이동 · 줄간격 · 글씨크기 · 용지.
///
/// ## 규칙 (요구: "수품판매관리의 메뉴도 관리자명단출력처럼 출력내용선택,
/// 위치이동, 줄간격유지 항목등을 넣어줘")
/// 관리자명단출력에는 ①출력할 항목(선택) ②열 순서(위치이동) ③글씨 크기
/// ④행 간격(밀도) ⑤용지 방향 옵션이 있었다. 수품(판매대장·재고·리포트·공여)
/// 에는 이런 옵션이 없었다. 이 모델이 그 옵션을 담아 표 문서(TsakTableDoc)
/// 생성 시 열 선택·순서·글씨·줄간격·용지에 반영한다. (편집 UI 는
/// `widgets/tsak_table_options.dart` 의 showTsakTableOptions.)
library;

/// 표 출력 **글씨 크기** (명단출력과 동일 개념).
/// 글씨 크기 — 표 출력 옵션.
///
/// (요구 2026-10-31 6차) "폰트사이즈를 더 줄일 수 있도록 하는 옵션 더 넣어줘
///  (현재보다 더 작은 폰트)"
/// → 열이 12개를 넘으면 '작게'(0.86)로도 A4 폭에 안 들어간다.
///   그래서 [micro](0.62) · [tiny](0.72) 두 단계를 **아래쪽에** 더 붙였다.
///   (기존 small/normal/large 는 배율을 건드리지 않았다 — 저장된 옵션 호환)
enum TsakFontSize { micro, tiny, small, normal, large }

extension TsakFontSizeX on TsakFontSize {
  String get label => switch (this) {
    TsakFontSize.micro => '아주작게',
    TsakFontSize.tiny => '더작게',
    TsakFontSize.small => '작게',
    TsakFontSize.normal => '보통',
    TsakFontSize.large => '크게',
  };

  String get note => switch (this) {
    TsakFontSize.micro => '최대한 촘촘히',
    TsakFontSize.tiny => '촘촘히',
    TsakFontSize.small => '약간 작게',
    TsakFontSize.normal => '기본',
    TsakFontSize.large => '또렷하게',
  };

  double get scale => switch (this) {
    TsakFontSize.micro => 0.62,
    TsakFontSize.tiny => 0.72,
    TsakFontSize.small => 0.86,
    TsakFontSize.normal => 1.0,
    TsakFontSize.large => 1.18,
  };

  /// 이 단계에서 실제로 찍히는 본문 pt(기본 8.5pt 기준) — 화면 표기용.
  double get approxPt => (8.5 * scale * 10).roundToDouble() / 10;
}

/// 표 출력 **줄 간격(밀도)** — "줄간격 유지" 항목.
enum TsakRowSpace { tight, normal, loose }

extension TsakRowSpaceX on TsakRowSpace {
  String get label => switch (this) {
    TsakRowSpace.tight => '좁게',
    TsakRowSpace.normal => '보통',
    TsakRowSpace.loose => '넓게',
  };

  String get note => switch (this) {
    TsakRowSpace.tight => '한 장에 더 많이',
    TsakRowSpace.normal => '기본',
    TsakRowSpace.loose => '여백 넉넉히',
  };

  double get mul => switch (this) {
    TsakRowSpace.tight => 0.72,
    TsakRowSpace.normal => 1.0,
    TsakRowSpace.loose => 1.35,
  };
}

/// 표(리스트) 출력 옵션.
class TableOutputOptions {
  const TableOutputOptions({
    this.cols,
    this.fontSize = TsakFontSize.normal,
    this.rowSpace = TsakRowSpace.normal,
    this.landscape,
    this.noWrap = const <String>{},
    this.rowLines = 1,
    this.cellLines,
  });

  /// 출력할 열(0-based) 순서 — null 이면 원본 전체 순서.
  final List<int>? cols;

  /// 글씨 크기.
  final TsakFontSize fontSize;

  /// 줄 간격(밀도).
  final TsakRowSpace rowSpace;

  /// 용지 방향 — null 이면 문서 기본값(보통 가로)을 따른다.
  final bool? landscape;

  /// 두줄 방지 대상 **열 헤더 이름** 집합.
  ///
  /// (요구: "행사참가 출력파일 … 두줄방지 항목을 선택할 수 있도록 해줘")
  /// 지정된 열은 줄바꿈하지 않고(한 줄 유지), 넘치면 글씨가 자동 축소된다.
  final Set<String> noWrap;

  /// **행 하나의 높이를 몇 줄분으로 할지** — 1 = 종전 그대로.
  ///
  /// ## 요구 (원문 2026-10-31, 2차 정정)
  /// > "두단 세단으로 표시하라는 것은 **이름별로 칸을 더 늘리라는 의미**임
  /// >  상하 두 단을 넣으라는 것이 아님(현재 적용된 것은 잘 못 반영된 것임)"
  ///
  /// ## 정정 내용
  /// 1차에서 나는 "열을 위/아래 두 단으로 쌓는" 방식으로 만들었다. 그러나
  /// 요구는 **표를 쪼개라는 것이 아니라, 이름 하나가 들어가는 칸(행)의 높이를
  /// 한 줄분 더 늘려 여유를 달라**는 뜻이었다.
  /// → 이 값이 2면 각 행이 **2줄 높이**가 되어, 이름·소속이 눌리지 않고
  ///   행과 행 사이에 **가로 구분선이 한 줄 더** 생긴 것처럼 보인다.
  final int rowLines;
  /// 셀 하나가 **가질 수 있는 최대 줄 수** — null 이면 제한 없음(종전 그대로).
  ///
  /// ## 요구 (원문 2026-10-31 2차)
  /// > "항목이 너무 길어지면 이름하나당 2줄 이상을 넣도록 함"
  ///
  /// 지금까지는 A4 폭에 맞추려고 폰트와 열 폭을 자동으로 줄였다. 그 결과 이름
  /// 하나가 1줄로 눌리거나, 반대로 긴 주소가 4~5줄로 터져 행 높이가 들쭉날쭉했다.
  /// 이 값을 주면 셀 텍스트가 **그 줄 수 안에서** 접히도록 폭·폰트를 맞춘다
  /// (2 = 이름 한 명이 최대 2줄까지 들어가게).
  final int? cellLines;

  double get scale => fontSize.scale;
  double get rowSpaceMul => rowSpace.mul;

  /// 값을 복사하되 **`cols` 를 null 로 지울 수 있는** 유일한 통로.
  ///
  /// ## 🐞 왜 `clearCols` 가 필요한가 (2026-11-02, build #563)
  /// 종전에는 `cols ?? this.cols` 라서 `copyWith(cols: null)` 을 해도 기존
  /// `cols` 가 그대로 살아남았다. 그 결과 문서에 열을 덧붙인 뒤
  /// `copyWith(cols: null)` 로 "열 필터 해제"를 시도해도 필터가 남아,
  /// **새로 붙인 열이 viewColumns 단계에서 잘려 나갔다**
  /// (증상: 미리보기에서 추가항목을 켜도 열이 안 보인다).
  ///
  /// 하위 호환을 위해 `clearCols` 를 주지 않으면 종전과 똑같이 동작한다.
  TableOutputOptions copyWith({
    List<int>? cols,
    TsakFontSize? fontSize,
    TsakRowSpace? rowSpace,
    bool? landscape,
    Set<String>? noWrap,
    int? rowLines,
    int? cellLines,
    bool clearCols = false,
  }) => TableOutputOptions(
    cols: clearCols ? cols : (cols ?? this.cols),
    fontSize: fontSize ?? this.fontSize,
    rowSpace: rowSpace ?? this.rowSpace,
    landscape: landscape ?? this.landscape,
    noWrap: noWrap ?? this.noWrap,
    rowLines: rowLines ?? this.rowLines,
    cellLines: cellLines ?? this.cellLines,
  );

  /// 부제/배지 표기 — 예: "글씨 보통 · 간격 넓게 · 가로 · 두줄방지 3".
  String get badge {
    final parts = <String>['글씨 ${fontSize.label}', '간격 ${rowSpace.label}'];
    if (landscape != null) parts.add(landscape! ? '가로' : '세로');
    if (noWrap.isNotEmpty) parts.add('두줄방지 ${noWrap.length}');
    if (rowLines > 1) parts.add('행 $rowLines줄');
    if (cellLines != null) parts.add('셀 $cellLines줄');
    return parts.join(' · ');
  }
}

/// 선택([selected])·순서([order])를 표에 적용한 결과.
class TableDocView {
  const TableDocView({required this.columns, required this.rows});
  final List<String> columns;
  final List<List<String>> rows;
}

/// 선택([selected])·순서([order])를 표에 적용해 열/행을 재구성한다.
///
/// - [order]: 0-based 열 인덱스의 출력 순서(위치이동 결과). 없으면 원본 순서.
/// - [selected]: 출력할 열 인덱스 집합. 없으면 모든 열.
TableDocView applyTableOptions({
  required List<String> columns,
  required List<List<String>> rows,
  required List<int>? order,
  required Set<int> selected,
}) {
  final seq = order ?? List<int>.generate(columns.length, (i) => i);
  final keep = <int>[];
  for (final i in seq) {
    if (i < 0 || i >= columns.length) continue;
    if (selected.contains(i)) keep.add(i);
  }
  final outCols = [for (final i in keep) columns[i]];
  final outRows = [
    for (final r in rows) [for (final i in keep) i < r.length ? r[i] : ''],
  ];
  return TableDocView(columns: outCols, rows: outRows);
}
