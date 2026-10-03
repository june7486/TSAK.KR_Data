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
enum TsakFontSize { small, normal, large }

extension TsakFontSizeX on TsakFontSize {
  String get label => switch (this) {
    TsakFontSize.small => '작게',
    TsakFontSize.normal => '보통',
    TsakFontSize.large => '크게',
  };

  String get note => switch (this) {
    TsakFontSize.small => '촘촘하게',
    TsakFontSize.normal => '기본',
    TsakFontSize.large => '또렷하게',
  };

  double get scale => switch (this) {
    TsakFontSize.small => 0.86,
    TsakFontSize.normal => 1.0,
    TsakFontSize.large => 1.18,
  };
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
  });

  /// 출력할 열(0-based) 순서 — null 이면 원본 전체 순서.
  final List<int>? cols;

  /// 글씨 크기.
  final TsakFontSize fontSize;

  /// 줄 간격(밀도).
  final TsakRowSpace rowSpace;

  /// 용지 방향 — null 이면 문서 기본값(보통 가로)을 따른다.
  final bool? landscape;

  double get scale => fontSize.scale;
  double get rowSpaceMul => rowSpace.mul;

  TableOutputOptions copyWith({
    List<int>? cols,
    TsakFontSize? fontSize,
    TsakRowSpace? rowSpace,
    bool? landscape,
  }) => TableOutputOptions(
    cols: cols ?? this.cols,
    fontSize: fontSize ?? this.fontSize,
    rowSpace: rowSpace ?? this.rowSpace,
    landscape: landscape ?? this.landscape,
  );

  /// 부제/배지 표기 — 예: "글씨 보통 · 간격 넓게 · 가로".
  String get badge {
    final parts = <String>['글씨 ${fontSize.label}', '간격 ${rowSpace.label}'];
    if (landscape != null) parts.add(landscape! ? '가로' : '세로');
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
