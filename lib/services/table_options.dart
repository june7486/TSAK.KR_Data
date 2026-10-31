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
    this.noWrap = const <String>{},
    this.rowBands = 1,
    this.bandAnchors = const <String>{},
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

  /// 표를 **가로 띠(밴드)로 나누는 수** — 1 = 종전 그대로, 2 = 표를 위/아래
  /// 두 단으로 쌓아 한 줄에 놓는 열 수를 절반으로 줄인다.
  ///
  /// ## 요구 (원문 2026-10-31)
  /// > "항목이 많을 경우에는 가로줄을 하나 더 추가해서 두줄방지 되도록
  /// >  할 수 있는 옵션도 추가해줘"
  ///
  /// ## 왜 [noWrap] 만으로는 부족한가
  /// [noWrap] 은 "그 열을 접지 마라"는 **명령**일 뿐이다. 열이 12개면 A4 가로
  /// 폭에서 한 열에 30pt 남짓만 배정되므로, 접지 않으면 글씨가 2~3pt 로
  /// 줄어들어 **읽을 수 없다**. 진짜 해법은 **열을 두 단으로 쌓아** 열당 폭을
  /// 두 배로 늘리는 것이다. 띠와 띠 사이에 **가로 구분선이 하나 더** 생긴다
  /// (그래서 "가로줄을 하나 더 추가").
  ///
  /// 같은 행 번호가 두 단에 나뉘어 놓이므로, 각 단의 첫 열(연번 등)은
  /// 렌더링 시 자동으로 **반복 출력**된다([bandAnchors] 미지정 시).
  final int rowBands;

  /// 새 띠를 **시작하는 열 헤더 이름** 집합 — 비어 있으면 [rowBands] 에 맞춰
  /// 열 개수의 중간에서 자동 분할한다.
  ///
  /// 예: `{'소속'}` → '소속' 부터 아래 단이 시작된다(위 단: 앞쪽 열들).
  final Set<String> bandAnchors;

  /// 실제로 쓸 띠 수(2 이상은 2로 고정 — A4 에서 3단은 글씨가 너무 작아진다).
  int get effectiveRowBands => rowBands >= 2 ? 2 : 1;

  double get scale => fontSize.scale;
  double get rowSpaceMul => rowSpace.mul;

  TableOutputOptions copyWith({
    List<int>? cols,
    TsakFontSize? fontSize,
    TsakRowSpace? rowSpace,
    bool? landscape,
    Set<String>? noWrap,
    int? rowBands,
    Set<String>? bandAnchors,
  }) => TableOutputOptions(
    cols: cols ?? this.cols,
    fontSize: fontSize ?? this.fontSize,
    rowSpace: rowSpace ?? this.rowSpace,
    landscape: landscape ?? this.landscape,
    noWrap: noWrap ?? this.noWrap,
    rowBands: rowBands ?? this.rowBands,
    bandAnchors: bandAnchors ?? this.bandAnchors,
  );

  /// 부제/배지 표기 — 예: "글씨 보통 · 간격 넓게 · 가로 · 두줄방지 3".
  String get badge {
    final parts = <String>['글씨 ${fontSize.label}', '간격 ${rowSpace.label}'];
    if (landscape != null) parts.add(landscape! ? '가로' : '세로');
    if (noWrap.isNotEmpty) parts.add('두줄방지 ${noWrap.length}');
    if (effectiveRowBands > 1) parts.add('두 단');
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

/// 표를 **두 단(위/아래 띠)** 으로 쪼갠 결과.
///
/// [first] = 위 단 열 인덱스, [second] = 아래 단 열 인덱스(둘 다 대상 열 안에서의
/// 0-based 위치). [second] 가 비면 분할하지 않는다.
class TableBandSplit {
  const TableBandSplit({required this.first, required this.second});
  final List<int> first;
  final List<int> second;

  bool get isSplit => second.isNotEmpty;
}

/// 열 목록을 두 단으로 나눈다 — [TableOutputOptions.rowBands] 구현부.
///
/// 분할 기준:
///  1. [anchors] 중 실제 열 이름과 일치하는 것이 있으면 **그 열부터** 아래 단.
///  2. 없으면 열 개수의 **중간**(올림)에서 자른다.
///  3. 한쪽이 비면(열 1개 등) 분할하지 않는다.
///
/// 첫 열(연번·번호 등)은 아래 단에도 **자동 반복**되도록 [repeatFirst] 로
/// [second] 앞에 끼워 넣는다(보고 표에서 행 식별이 사라지지 않게).
TableBandSplit splitColumnBands(
  List<String> columns, {
  Set<String> anchors = const <String>{},
  bool repeatFirst = true,
}) {
  final n = columns.length;
  if (n < 3) return TableBandSplit(first: List.generate(n, (i) => i), second: const []);
  var cut = (n / 2).ceil();
  if (anchors.isNotEmpty) {
    for (var i = 1; i < n; i++) {
      if (anchors.contains(columns[i])) {
        cut = i;
        break;
      }
    }
  }
  if (cut <= 0 || cut >= n) cut = (n / 2).ceil();
  final first = <int>[for (var i = 0; i < cut; i++) i];
  final second = <int>[];
  // 첫 열은 아래 단에서도 반복(연번이 사라지면 어느 행인지 알 수 없다).
  if (repeatFirst && cut > 1) second.add(0);
  for (var i = cut; i < n; i++) {
    second.add(i);
  }
  if (second.length <= 1) {
    return TableBandSplit(first: List.generate(n, (i) => i), second: const []);
  }
  return TableBandSplit(first: first, second: second);
}
