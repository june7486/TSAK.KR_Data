import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/doc_pdf.dart';
import '../services/extra_fields.dart';
import '../services/extra_output.dart';
import '../services/file_save.dart';
import '../services/output_formats.dart';
import '../services/pdf_to_jpg.dart';
import '../services/table_export.dart';
import '../theme/app_theme.dart';

/// 추가입력 항목을 **미리보기에서 직접 켜고 끌 수 있게** 하기 위한 입력 정보.
///
/// ## 요구 (원문 2026-10-31)
/// > "출력 미리보기시에도 추가항목 선택할 수 있도록 하고 실시간으로 미리보며
/// >  출력 할 수 있도록 해줘"
///
/// [source] 는 문서의 행과 **1:1 로 대응하는** 참석자 원본 행 목록이다.
/// 미리보기 창에서 항목을 체크하면 [extraColumns] 로 열을 즉시 덧붙여 다시
/// 그리므로, "체크 → 바로 화면에 반영"이 된다.
class TsakExtraPick {
  const TsakExtraPick({required this.source, this.initial = const <String>{}});

  /// 참석자 원본 행(events.json attendees 와 동일 구조).
  final List<Map<String, dynamic>> source;

  /// 처음부터 켜 둘 항목 키([ExtraField.key]).
  final Set<String> initial;
}

/// 미리보기가 보여줄 **최종 문서**를 계산한다 — 옵션·추가항목·열선택을 모두 반영.
///
/// ## 🐞 버그 수정 (2026-11-02, build #563)
/// 보고: **"미리보기 출력시, 항목선택 사항이 실시간으로 반영되고 있지 않음"**
/// (추가항목 8/8 전부 켜져 있고 '입력자 5명' 인데 미리보기 표에는 추가항목 열이
///  하나도 없었다.)
///
/// 원인이 셋이었고 셋 다 여기서 고친다.
///
/// **① 열 선택이 추가항목 열을 잘라먹었다.**
///   종전에는 `extraColumns()` 로 추가항목 열을 **붙인 뒤에** `pickedCols` 로
///   열을 걸렀다. 그런데 `pickedCols` 는 *원본* 열 인덱스만 담으므로
///   추가항목 열(인덱스 >= 원본 열 수)은 조건에 걸리지 않아 전부 탈락했다.
///   → 붙이자마자 사라져 "반영이 안 되는" 것처럼 보였다.
///   (원본 옵션에 `cols` 가 있는 화면, 또는 출력항목 칩을 한 번이라도 누른 경우
///    100% 재현. 참가자 명부 기본값은 `cols` 가 없어 우연히 정상으로 보였다.)
///   → **먼저 원본 열을 고르고, 그 다음에 추가항목 열을 붙인다.**
///
/// **② `copyWith(cols: null)` 로는 `cols` 를 지울 수 없었다.**
///   `copyWith` 가 `cols ?? this.cols` 라서 null 을 주면 기존값이 그대로 살아남고,
///   살아남은 `cols` 가 `viewColumns` 에서 추가항목 열을 다시 잘라냈다.
///   → `clearCols` 플래그로 **명시적으로** 지운다.
///
/// **③** 미리보기 재생성 서명(`_key`)에 **행사 총 인원**이 빠져 있었다.
///   칩 개수('8 / 8')는 그대로인데 '입력자 5명 → 6명' 처럼 데이터만 바뀌면
///   서명이 같아 미리보기가 갱신되지 않았다. → 서명에 인원을 포함한다.
///
/// [pickedCols] 가 null 이면 '전체 열' 선택 상태다.
TsakTableDoc resolveOutputPreviewDoc({
  required TsakTableDoc doc,
  TsakExtraPick? extra,
  required Set<String> extraKeys,
  required Set<int>? pickedCols,
}) {
  // ── 1단계: **원본** 열에 대해서만 열 선택을 적용한다.
  var base = doc;
  final p = pickedCols;
  if (p != null) {
    final total = doc.columns.length;
    final keep = <int>[
      for (var i = 0; i < total; i++)
        if (p.contains(i)) i,
    ];
    // 아무것도 안 남으면 '전체'로 되돌린다(빈 표가 되는 것을 막는다).
    if (keep.isNotEmpty && keep.length < total) {
      base = TsakTableDoc(
        title: doc.title,
        subtitle: doc.subtitle,
        description: doc.description,
        author: doc.author,
        extra: doc.extra,
        columns: <String>[for (final i in keep) doc.columns[i]],
        rows: <List<String>>[
          for (final r in doc.rows)
            <String>[for (final i in keep) i < r.length ? r[i] : ''],
        ],
        summary: doc.summary,
        footerLeft: doc.footerLeft,
        landscape: doc.landscape,
        // ⚠️ 여기서 cols 를 **확실히 지운다**. 남겨 두면 아래에서 붙인
        //    추가항목 열이 viewColumns 단계에서 다시 잘려 나간다.
        options: doc.options?.copyWith(cols: null, clearCols: true),
        reportBlocks: doc.reportBlocks,
        template: doc.template,
      );
    }
  }

  // ── 2단계: 추가항목 열을 **맨 뒤에** 붙인다(이제 잘릴 일이 없다).
  final ex = extra;
  if (ex == null || extraKeys.isEmpty) return base;
  final withExtra = extraColumns(base, source: ex.source, keys: extraKeys);

  // ── 3단계: 옵션의 cols 를 원본 열 기준으로 다시 매핑한다.
  //   `extraColumns` 가 이미 새 인덱스를 덧붙여 주지만, 위 1단계에서 열이
  //   줄었을 수 있으므로 **현재 열 순서**를 그대로 확정해 준다.
  //   (viewColumns 가 여기서 또 필터링하면 ①의 버그가 재발한다.)
  final mapped = <int>[for (var i = 0; i < withExtra.columns.length; i++) i];
  final o = withExtra.options;
  return TsakTableDoc(
    title: withExtra.title,
    subtitle: withExtra.subtitle,
    description: withExtra.description,
    author: withExtra.author,
    extra: withExtra.extra,
    columns: withExtra.columns,
    rows: withExtra.rows,
    summary: withExtra.summary,
    footerLeft: withExtra.footerLeft,
    landscape: withExtra.landscape,
    options: o?.copyWith(cols: mapped),
    reportBlocks: withExtra.reportBlocks,
    template: withExtra.template,
  );
}

/// 테스트에서 미리보기 위젯 없이 **같은 계산**을 돌리기 위한 얇은 훅.
///
/// 화면(위젯)을 띄우지 않고도 "칩을 켜면 표에 열이 붙는가"를 검증할 수 있다.
class TsakOutputPreviewDebug {
  const TsakOutputPreviewDebug._();

  static TsakTableDoc resolveDoc({
    required TsakTableDoc doc,
    TsakExtraPick? extra,
    required Set<String> extraKeys,
    Set<int>? pickedCols,
  }) => resolveOutputPreviewDoc(
    doc: doc,
    extra: extra,
    extraKeys: extraKeys,
    pickedCols: pickedCols,
  );
}

/// 모든 출력 화면 공용 **실시간 출력 미리보기** 창.
///
/// ## 요구
/// "모든 창에서 출력시 첨부파일과 같이 줄간격 폰트 크기를 볼수 있도록 미리보기
///  창을 띄워서 결과물을 실시간으로 확인 후 출력내보낼 수 있도록 해줘"
///
/// 표 문서([TsakTableDoc])를 받아 MUJI PDF를 만들고, **첫 페이지를 이미지로
/// 렌더**해 보여준다. `줄간격 · 글자 크기 · 2줄 방지 · 가로 모드 · 행 높이 ·
/// 셀 줄 수` 를 바꾸면 **즉시 다시 그린다**(라이브). 확정하면
/// **PDF · 이미지(JPG) · 인쇄**로 내보낸다. 아이폰 등은 저장 옵션 창
/// ([askSaveOption])을 거쳐 사진앱에 저장된다.
///
/// 미리보기 카드 안에 그릴 **종이 사각형**의 크기를 구한다(A4 실제 비율).
///
/// ## 🐞 왜 필요한가 (2026-11-02, build #567)
/// 보고: **"가로모드 선택시 세로모드가 됨"**
///
/// PDF 는 정상이었다(`landscape:true` → 841.9 × 595.3pt 실측). 문제는 미리보기
/// 카드가 **방향과 무관한 고정 세로 박스(흰 배경)** 였다는 것. 흰 종이가 흰 카드
/// 안에 들어가 종이 경계가 사라지고, **카드의 둥근 세로 테두리가 곧 종이**처럼
/// 읽혔다 → "가로를 골랐는데 세로가 됐다".
///
/// → 카드 배경을 회색 책상으로, 종이는 **A4 실제 비율**로 그린다.
///   가로 297:210 = 1.414, 세로 210:297 = 0.707. 방향을 고르면 종이가 실제로 눕는다.
///
/// [boxW]/[boxH] 는 카드 안쪽 여유 공간, [landscape] 는 현재 방향.
/// 반환값은 카드 안에 **꼭 맞게** 들어가는 (폭, 높이).
(double, double) paperSize(
  double boxW,
  double boxH, {
  required bool landscape,
}) {
  // A4 실제 비율 — 가로는 가로가 길고, 세로는 세로가 길다.
  final ratio = landscape ? 297 / 210 : 210 / 297;
  var w = boxW;
  var h = w / ratio;
  if (h > boxH) {
    h = boxH;
    w = h * ratio;
  }
  return (w, h);
}

/// 미리보기 카드의 높이를 구한다 — 가로 모드면 **낮게** 잡는다.
///
/// (버그 수정 #567) 종이가 낮아지는데 카드가 그대로 높으면 위아래 회색 여백만
/// 커져 "여전히 세로"로 보였다.
double previewCardHeight(double screenHeight, {required bool landscape}) {
  final base = (screenHeight * 0.34).clamp(180.0, 420.0);
  return landscape ? (base * 0.78).clamp(150.0, 330.0) : base;
}

/// [extra] 를 주면 **추가입력 항목 선택 칩**이 나타나고, 고른 항목이 열로
/// 덧붙은 결과를 실시간으로 보여준다(원문은 그대로 두고 매번 새로 조립).
Future<void> showTsakOutputPreview(
  BuildContext context, {
  required TsakTableDoc doc,
  TsakExtraPick? extra,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _TsakOutputPreview(doc: doc, extra: extra),
  );
}

class _TsakOutputPreview extends StatefulWidget {
  const _TsakOutputPreview({required this.doc, this.extra});

  final TsakTableDoc doc;
  final TsakExtraPick? extra;

  @override
  State<_TsakOutputPreview> createState() => _TsakOutputPreviewState();
}

class _TsakOutputPreviewState extends State<_TsakOutputPreview> {
  /// 2줄 방지 — 켜면 모든 열이 줄바꿈하지 않고 한 줄로 나온다.
  bool _noWrap = false;

  /// 가로 모드 — 문서 기본 방향으로 시작.
  late bool _landscape = widget.doc.effectiveLandscape;

  /// 줄 간격(밀도) 배율.
  double _lineSpace = 1.1;

  /// 글자 크기 배율(1.0 = 기본).
  double _fontScale = 1.0;

  /// **출력할 기본 열 선택** — 미리보기에서 직접 켜고 끈다.
  ///
  /// (요구 2026-10-31 6차) "미리보기 항목에도 출력시 선택할 수 있는 메뉴를
  ///  출력옵션에 추가해줘"
  ///  옵션 시트를 닫았다 다시 열지 않고도, 보면서 바로 열을 고를 수 있어야 한다.
  ///  null 이면 '전체 열' 선택 상태.
  late Set<int>? _pickedCols = _initialPickedCols();

  Set<int>? _initialPickedCols() {
    final o = widget.doc.options;
    if (o?.cols == null) return null; // 옵션 없음 = 전체
    return <int>{...o!.cols!};
  }

  /// 원본 열 목록(추가항목 열 제외) — 미리보기 선택 메뉴의 후보.
  List<String> get _baseCols => widget.doc.columns;

  bool _colOn(int i) {
    final p = _pickedCols;
    if (p == null) return true;
    return p.contains(i);
  }

  void _toggleCol(int i) {
    // 열 선택은 **표 자체**를 바꾸므로 미리보기를 즉시 다시 만든다.
    _bump(() {
      final p = <int>{...?_pickedCols};
      // null(전체) 상태에서 하나를 끄면 나머지를 전부 채워 넣는다.
      if (_pickedCols == null) {
        for (var k = 0; k < _baseCols.length; k++) {
          if (k != i) p.add(k);
        }
      } else if (p.contains(i)) {
        p.remove(i);
      } else {
        p.add(i);
      }
      _pickedCols = p;
    });
  }

  /// **행 높이(줄 칸)** — 이름 하나가 들어가는 행을 몇 줄분 높이로 할지.
  ///
  /// (요구 2026-10-31 정정) "두단 세단으로 표시하라는 것은 **이름별로 칸을 더
  ///  늘리라는 의미**임. 상하 두 단을 넣으라는 것이 아님"
  /// → 표를 쪼개지 않고 행 높이만 늘린다.
  ///
  /// ## 🗑️ 화면에서 제거 (2026-11-02, build #567)
  /// 보고: **"이름줄: 항목 삭제"**
  ///  미리보기 옵션의 `이름줄 1줄/2줄/3줄` 칩을 없앴다. 쓸모가 낮고 오히려
  ///  옵션 영역만 길게 만들었다. [DocPdf] 의 `rowLines` 자체는 남겨 두므로
  ///  (다른 화면이 쓸 수 있다) 값은 **항상 1**(기본)로 고정된다.
  final int _rowLines = 1;

  /// 셀 한 칸이 가질 수 있는 최대 줄 수 — null 이면 제한 없음.
  /// (요구 2026-10-31 2차) “항목이 너무 길어지면 이름하나당 2줄 이상”
  int? _cellLines;

  /// 추가입력 항목 선택(켜진 항목 키).
  ///
  /// (요구 2026-10-31 4차) "추가항목 모두 노출 … 미리보기시 모두 노출"
  /// → 처음 열 때 **값이 있는 항목은 전부 켜 둔다**. 사용자는 필요 없는 것만
  ///   끄면 된다(켜는 것보다 끄는 게 빠르고, '안 보인다'는 오해도 사라진다).
  late final Set<String> _extraKeys = _initialExtraKeys();

  Set<String> _initialExtraKeys() {
    final ex = widget.extra;
    if (ex == null) return <String>{};
    // 값이 하나라도 채워진 항목 — 이게 기본 노출 대상이다.
    final filled = <String>{
      for (final f in ExtraFields.all)
        if (ex.source.any((a) => f.hasValue(a))) f.key,
    };
    // 화면이 넘겨준 초기 선택은 **필터가 아니라 보탬**이다.
    // (종전: initial 이 그대로 대입 → 화면이 4개만 넘기면 나머지가 영영 안 보임)
    final merged = <String>{...filled, ...ex.initial};
    // 값이 아예 없는 행사라도 빈 표가 되지 않게 전 항목을 켠다.
    return merged.isEmpty
        ? <String>{for (final f in ExtraFields.all) f.key}
        : merged;
  }

  Future<Uint8List>? _previewFuture;
  String _previewKey = '';
  bool _busy = false;

  /// 옵션 서명 — 값이 바뀔 때만 미리보기를 다시 만든다.
  ///
  /// ## 🐞 버그 수정 (2026-11-01, build #561) — "미리보기를 누르면 창이 안 뜬다"
  /// 종전 코드는
  /// ```dart
  /// '${(_pickedCols?.toList() ?? const <int>[])..sort()}'
  /// ```
  /// 였다. `_pickedCols` 가 **null**(= '전체 열' 상태, 옵션에 cols 가 없는 화면의
  /// 기본값)이면 `?? const <int>[]` 로 떨어진다. 그런데 `const` 리스트는
  /// **불변(unmodifiable)** 이라 `..sort()` 가
  /// `UnsupportedError: Cannot modify an unmodifiable list` 를 던진다.
  ///
  /// `_key` 는 `build()` 안에서 `_previewKey` 와 비교되므로 **매 프레임** 호출되고,
  /// 따라서 위젯은 build 단계에서 즉사 → `showDialog` 가 끝내 화면에 그리지 못해
  /// "아무 창도 안 나온다"로 보였다. 참가자 명부처럼 `TableOutputOptions.cols`
  /// 를 지정하지 않는 화면은 **100% 재현**(항상 null).
  ///
  /// → 불변 리스트를 건드리지 않고, **새 가변 리스트를 만들어** 정렬한다.
  String get _key {
    final picked = <int>[...?_pickedCols]..sort();
    final extras = <String>[..._extraKeys]..sort();
    // ③ 행사 총 인원까지 서명에 넣는다.
    //   칩 개수('8 / 8')는 그대로인데 '입력자 5명 → 6명' 처럼 데이터만 바뀌면
    //   서명이 같아 미리보기가 갱신되지 않았다(보고된 "실시간 반영 안 됨").
    final srcCount = widget.extra?.source.length ?? 0;
    return '$_landscape|$_noWrap|${_lineSpace.toStringAsFixed(2)}|'
        '${_fontScale.toStringAsFixed(2)}|$_rowLines|${_cellLines ?? 0}|'
        '$srcCount|$picked|${extras.join(',')}';
  }

  String get _base => widget.doc.baseName(); // 예: TSAK_출력_게시판 출력

  /// 현재 옵션을 반영한 **최종 문서** — 추가항목 열이 덧붙은 결과.
  ///
  /// 매번 새로 조립하므로 원본 [TsakTableDoc] 은 절대 변하지 않는다
  /// (항목을 껐다 켜도 열이 중복되지 않는다).
  ///
  /// 실제 계산은 [resolveOutputPreviewDoc] 에 있다(화면 없이 테스트 가능하게 분리).
  TsakTableDoc get _doc => resolveOutputPreviewDoc(
    doc: widget.doc,
    extra: widget.extra,
    extraKeys: _extraKeys,
    pickedCols: _pickedCols,
  );

  /// 현재 옵션으로 PDF를 만든다.
  Future<Uint8List> _buildPdf() {
    final d = _doc;
    final n = d.viewColumns.length;
    // ⚠️ 2줄 방지(_noWrap)와 셀 줄 수(_cellLines)는 **정면으로 충돌**한다.
    //   종전에는 _noWrap 이 모든 열을 1줄로 고정해, 12열짜리 명부가 화면 밖으로
    //   잘려 나갔다(사용자 스크린샷의 실제 증상).
    //   → 사용자가 **셀 줄 수를 직접 고른 경우에는 그 선택을 우선**한다.
    //     (요구: "2줄방지되고 추가입력 항목이 다 보여지도록")
    final Set<int> nowrap;
    if (_cellLines != null && _cellLines! > 1) {
      // 셀 줄 수가 명시되면 문서 자체의 두줄방지 항목만 존중한다.
      nowrap = d.effectiveNoWrapCols;
    } else if (_noWrap) {
      nowrap = {for (var i = 0; i < n; i++) i};
    } else {
      nowrap = d.effectiveNoWrapCols;
    }
    return DocPdf.buildSimple(
      meta: d.meta,
      columns: d.viewColumns,
      rows: d.viewRows,
      summary: d.summary,
      footerLeft: d.footerLeft,
      landscape: _landscape,
      scale: _fontScale,
      rowSpaceMul: _lineSpace,
      noWrapCols: nowrap,
      rowLines: _rowLines,
      maxCellLines: _cellLines,
    );
  }

  /// 미리보기용 — PDF 첫 페이지를 JPG로 래스터화한 바이트.
  Future<Uint8List> _makePreview() async {
    final pdf = await _buildPdf();
    return pdfToJpg(pdf, dpi: 110, quality: 82);
  }

  /// 스위치 '2줄 방지'가 **실제로** 무엇을 하는지 화면에 알려 준다.
  ///
  /// ## 🐞 혼란의 원인 (2026-11-02, build #565)
  /// 참가자 명부는 기본 옵션에 `noWrap: {'인가번호','연락처'}` 가 이미 들어
  /// 있다. 즉 **스위치가 OFF 여도 그 두 열은 두줄방지**다. 사용자 입장에서는
  /// "스위치를 안 켰는데 잘리고, 켜도 똑같아 보인다" → "기능이 안 된다"로 보였다.
  ///  → 스위치 아래에 지금 무엇이 두줄방지인지 **글자로** 표시한다.
  String get _noWrapHint {
    final d = _doc;
    final base = d.effectiveNoWrapCols.length;
    if (_noWrap) {
      return _cellLines != null && _cellLines! > 1
          ? '스위치 ON — 셀 줄 수(${_cellLines!}줄)가 우선'
          : '스위치 ON — 모든 열 한 줄 고정(넘치면 글씨 축소)';
    }
    if (base == 0) return '스위치 OFF — 두 줄로 접힘';
    final names = <String>[
      for (var i = 0; i < d.viewColumns.length; i++)
        if (d.effectiveNoWrapCols.contains(i)) d.viewColumns[i],
    ];
    return '스위치 OFF — 문서 기본 두줄방지 $base열: ${names.join('·')}';
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 1500)),
    );
  }

  /// PDF·이미지 내보내기(아이폰 등은 저장 옵션 창을 거친다).
  Future<void> _save(TsakOutputFormat fmt) async {
    if (_busy) return;
    final opt = await askSaveOption(
      context,
      info: '${widget.doc.title} (${fmt.label})',
    );
    if (opt == null) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      if (fmt == TsakOutputFormat.jpg) {
        final jpg = await pdfToJpg(pdf, dpi: 150, quality: 90);
        await saveFileOption(
          bytes: jpg,
          filename: '$_base.jpg',
          mime: 'image/jpeg',
          option: opt,
        );
      } else {
        await saveFileOption(
          bytes: pdf,
          filename: '$_base.pdf',
          mime: 'application/pdf',
          option: opt,
        );
      }
      _snack('${widget.doc.title} ${fmt.label} 내보내기를 시작했습니다');
    } catch (e) {
      _snack('내보내기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 인쇄 — OS 인쇄 대화상자(웹 포함).
  Future<void> _print() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      await Printing.layoutPdf(onLayout: (_) async => pdf);
    } catch (e) {
      _snack('인쇄 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 칩·슬라이더를 건드리면 **바로** 다시 그리도록 예약한다.
  ///
  /// ## 🐞 버그 수정 (2026-11-02, build #563)
  /// 종전에는 `build()` 안에서만 `_key` 를 비교했다. 그런데 미리보기 카드의
  /// `FutureBuilder` 가 **완료된 Future 를 계속 물고 있으면** 그 서브트리는
  /// 다시 빌드되지 않아(값이 같으므로) 새 PDF 가 반영되지 않는 경우가 있었다.
  /// 또 `setState` 로 상태만 바꾸고 `_previewFuture` 를 갱신하지 않으면
  /// 화면에는 **이전 그림**이 그대로 남는다(보고된 "실시간 반영 안 됨").
  /// → 상태를 바꾸는 모든 지점에서 **명시적으로** 미리보기를 다시 만든다.
  void _bump([VoidCallback? change]) {
    setState(() {
      change?.call();
      _previewKey = _key;
      _previewFuture = _makePreview();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 옵션이 바뀌면 미리보기를 다시 만든다(값이 그대로면 캐시 재사용).
    if (_key != _previewKey) {
      _previewKey = _key;
      _previewFuture = _makePreview();
    }

    final h = MediaQuery.of(context).size.height;
    // 미리보기 카드 높이 — 가로 모드면 낮게(종이가 낮으므로).
    final previewHeight = previewCardHeight(h, landscape: _landscape);

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: const Color(0xFFF3F1EC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: h * 0.94),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            // maxHeight 까지 채운다 → 아래 Expanded(스크롤)가 동작한다.
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    color: AppColors.purple,
                    size: 20,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      widget.doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purpleDark,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 27),
                child: Text(
                  '출력 미리보기 · 항목·줄간격·글자 크기를 바꾸면 즉시 반영됩니다',
                  style: const TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ),
              const SizedBox(height: 6),
              // ── 미리보기 화면(첫 페이지) ──
              //
              // ## 🐞 버그 수정 (2026-11-02, build #567)
              // 보고: **"가로모드 선택시 세로모드가 됨"**
              //
              // ## 원인 — 종이가 아니라 **카드**가 세로였다
              //  PDF 는 처음부터 정상이었다. 실측(`landscape:true` →
              //  pymupdf 페이지 841.9 × 595.3pt = **가로**)로 확인했다.
              //  문제는 이 미리보기 카드가 **방향과 무관한 고정 박스**
              //  (`height: previewHeight`, 흰 배경)였다는 점이다.
              //   · 흰 종이가 **흰 카드** 안에 들어가니 종이 경계가 보이지 않고,
              //   · 카드 테두리(둥근 사각형)만 '종이'로 읽혔다.
              //   → 사용자는 **카드의 세로 비율**을 종이 방향으로 인식해
              //     "가로를 골랐는데 세로가 됐다"고 느꼈다.
              //
              // ## 해결
              //  ① 카드 배경을 **회색 책상**으로 바꿔 종이 경계를 보이게 한다.
              //  ② 종이 박스를 **A4 실제 비율**(가로 297:210 · 세로 210:297)로
              //     직접 계산해 그린다 → 방향을 고르면 종이가 **눈에 보이게**
              //     눕는다(가로 = 넓고 낮음, 세로 = 좁고 높음).
              Container(
                width: double.infinity,
                height: previewHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7E3DA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD8D3CA)),
                ),
                clipBehavior: Clip.antiAlias,
                child: FutureBuilder<Uint8List>(
                  future: _previewFuture,
                  builder: (c, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      );
                    }
                    if (snap.hasError || snap.data == null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '미리보기를 만들 수 없습니다\n${snap.error ?? ''}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textGray,
                            ),
                          ),
                        ),
                      );
                    }
                    // (버그 수정 #567) 종이를 **A4 실제 비율**로 그려 방향이
                    //  눈에 보이게 한다. 종전에는 BoxFit.contain 으로 이미지만
                    //  카드 안에 맞춰, 카드(세로 박스)의 테두리가 곧 '종이'처럼
                    //  읽혀 가로/세로 구분이 사라졌다.
                    return LayoutBuilder(
                      builder: (_, box) {
                        // A4 실제 비율로 종이를 그린다 — 방향이 눈에 보인다.
                        final size = paperSize(
                          box.maxWidth - 16,
                          box.maxHeight - 16,
                          landscape: _landscape,
                        );
                        final paperW = size.$1;
                        final paperH = size.$2;
                        return Center(
                          child: Container(
                            width: paperW,
                            height: paperH,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              // 종이가 '떠 있는' 느낌 — 책상색 위 그림자.
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 7,
                                  offset: Offset(0, 2),
                                ),
                              ],
                              borderRadius: BorderRadius.circular(2),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InteractiveViewer(
                              maxScale: 6,
                              boundaryMargin: const EdgeInsets.all(24),
                              child: Image.memory(
                                snap.data!,
                                gaplessPlayback: true,
                                width: paperW,
                                height: paperH,
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              // ── 옵션 영역 — 화면이 작아도 **잘리지 않게** 스크롤에 담는다.
              //  (버그: Column 이 maxHeight 를 넘겨 칩·버튼이 겹쳐 보였다)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 옵션: 2줄 방지 · 가로 모드 ──
                      Row(
                        children: [
                          Expanded(
                            child: _switchCell(
                              '2줄 방지',
                              _noWrap,
                              (v) => _bump(() => _noWrap = v),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _switchCell(
                              '가로 모드',
                              _landscape,
                              (v) => _bump(() => _landscape = v),
                            ),
                          ),
                        ],
                      ),
                      // 스위치가 **지금 무엇을 하는지** 글자로 알려 준다.
                      //  (참가자 명부는 OFF 여도 인가번호·연락처가 두줄방지라
                      //   "켜도 똑같다"는 혼란이 있었다)
                      Padding(
                        padding: const EdgeInsets.only(left: 2, top: 3),
                        child: Text(
                          _noWrapHint,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: _noWrap
                                ? AppColors.purple
                                : AppColors.textGray,
                          ),
                        ),
                      ),
                      // ── 셀 줄 수 — 항목이 길 때 이름하나당 2줄 이상 허용 ──
                      _linesCell(
                        label: '셀 줄 수',
                        value: _cellLines,
                        options: const <int?>[null, 1, 2, 3],
                        names: const <int?, String>{
                          null: '자동',
                          1: '1줄',
                          2: '2줄',
                          3: '3줄',
                        },
                        onPick: (v) => setState(() => _cellLines = v),
                      ),
                      // 2줄 방지와 셀 줄 수가 **서로 싸우지 않게** 알려 준다.
                      if (_noWrap && _cellLines != null)
                        const Padding(
                          padding: EdgeInsets.only(left: 58, top: 3),
                          child: Text(
                            '셀 줄 수가 우선입니다 (2줄 방지는 잠시 쉼)',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.hermesOrange,
                            ),
                          ),
                        ),
                      _sliderCell(
                        '줄간격',
                        _lineSpace,
                        0.7,
                        1.6,
                        _lineSpace.toStringAsFixed(1),
                        (v) => setState(() => _lineSpace = v),
                      ),
                      _sliderCell(
                        '글자 크기',
                        _fontScale,
                        0.8,
                        1.5,
                        '${(_fontScale * 10).round()} pt',
                        (v) => setState(() => _fontScale = v),
                      ),
                      // ── 출력항목 선택 — 미리보기에서 직접 켜고 끈다 ──
                      //   (요구 2026-10-31 6차) "미리보기 항목에도 출력시
                      //   선택할 수 있는 메뉴를 출력옵션에 추가해줘"
                      if (_baseCols.isNotEmpty) _colPickBar(),
                      // ── 추가입력 항목 선택 (있을 때만) ──
                      if (widget.extra != null) ...[
                        const SizedBox(height: 4),
                        _extraPickBar(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // ── 내보내기: PDF · 이미지 · 인쇄 ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _save(TsakOutputFormat.pdf),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                      label: const Text('PDF'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _save(TsakOutputFormat.jpg),
                      icon: const Icon(Icons.image_outlined, size: 17),
                      label: const Text('이미지'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                      ),
                      onPressed: _busy ? null : _print,
                      icon: const Icon(Icons.print_outlined, size: 17),
                      label: const Text('인쇄'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// **출력항목 선택 줄** — 원본 열을 칩으로 켜고 끈다(라이브).
  ///
  /// (요구 2026-10-31 6차) "미리보기 항목에도 출력시 선택할 수 있는 메뉴를
  ///  출력옵션에 추가해줘" → 옵션 시트를 오가지 않고 보면서 고른다.
  Widget _colPickBar() {
    final total = _baseCols.length;
    final onCount = _pickedCols == null
        ? total
        : _pickedCols!.where((i) => i >= 0 && i < total).length;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8D3CA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '출력항목',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$onCount / $total 선택',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.purple,
                ),
              ),
              const Spacer(),
              if (onCount == 0)
                const Text(
                  '모두 끄면 원래대로',
                  style: TextStyle(fontSize: 9.5, color: AppColors.hermesOrange),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < _baseCols.length; i++)
                _colChip(i, _baseCols[i]),
              _miniChip('전체', () {
                // '전체' = 모든 원본 열 켜기 → 표가 바뀌므로 즉시 반영.
                _bump(() => _pickedCols = null);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _colChip(int i, String label) {
    final on = _colOn(i);
    return InkWell(
      onTap: () => _toggleCol(i),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.purple : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: on ? AppColors.purple : const Color(0xFFD8D3CA),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 12,
              color: on ? Colors.white : AppColors.textGray,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                color: on ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 추가입력 항목 선택 줄 — 칩을 누르면 그 항목 열이 즉시 붙었다 빠진다.
  Widget _extraPickBar() {
    final src = widget.extra!.source;
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8D3CA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '추가항목',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_extraKeys.length} / ${ExtraFields.all.length} 선택',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.purple,
                ),
              ),
              const Spacer(),
              // 값이 하나라도 있는 **참석자 수** — 첫 사람만 보면 0으로 보여
              //  "값이 없다"고 오해하게 된다(실제 버그).
              Text(
                '입력자 ${src.where((a) => ExtraFields.filledCount(a) > 0).length}명',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // (버그 수정) 종전에는 **가로 스크롤**이라 8개 중 4개만 보이고
          //  나머지는 스크롤해야 나왔다 → 요구 "추가항목 모두 노출".
          //  Wrap 으로 바꿔 **한눈에 전부** 보이게 한다.
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in ExtraFields.all) _extraChip(f),
              _miniChip('전체', () {
                // 추가항목 '전체' — 열이 늘어나므로 즉시 반영.
                _bump(() {
                  _extraKeys.addAll(ExtraFields.all.map((e) => e.key));
                });
              }),
              _miniChip('해제', () => _bump(_extraKeys.clear)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _extraChip(ExtraField f) {
    final on = _extraKeys.contains(f.key);
    final c = ExtraFields.colorOf(f.group);
    return InkWell(
      onTap: () => _bump(() {
        if (on) {
          _extraKeys.remove(f.key);
        } else {
          _extraKeys.add(f.key);
        }
      }),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: on ? c : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: on ? c : const Color(0xFFD8D3CA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(f.icon, size: 12, color: on ? Colors.white : c),
            const SizedBox(width: 4),
            Text(
              f.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                color: on ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EDE6),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textGray,
        ),
      ),
    ),
  );

  /// 줄 수 선택 칸 (행 높이 · 셀 줄 수 공용).
  ///
  /// (요구 2026-10-31 3차 정정)
  ///  "두단 세단으로 표시하라는 것은 이름별로 간을 더 늘리라는 의미임
  ///   상하 두 단을 넣으라는 것이 아님"
  ///  · 행 높이 = **이름 한 줄의 세로 칸을 N줄분으로** → 행 사이에 여백이 생겨
  ///    답답하지 않게. 표 구조는 그대로.
  ///  · 셀 줄 수 = 셀 하나가 접힐 수 있는 최대 줄 수.
  Widget _linesCell<T>({
    required String label,
    required T value,
    required List<T> options,
    required Map<T, String> names,
    required ValueChanged<T> onPick,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textGray,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (final v in options) ...[
                  if (v != options.first) const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onPick(v),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: value == v ? AppColors.purple : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: value == v
                                ? AppColors.purple
                                : const Color(0xFFD8D3CA),
                          ),
                        ),
                        child: Text(
                          names[v] ?? '$v',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: value == v
                                ? Colors.white
                                : AppColors.textDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchCell(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8D3CA)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              onChanged: onChanged,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              trackColor: WidgetStatePropertyAll(
                value ? AppColors.purple : const Color(0xFFCFC9C0),
              ),
              trackOutlineColor: WidgetStatePropertyAll(
                value ? AppColors.purple : const Color(0xFFCFC9C0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliderCell(
    String label,
    double v,
    double min,
    double max,
    String val,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textGray,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: v.clamp(min, max),
            min: min,
            max: max,
            activeColor: AppColors.purple,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            val,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.purpleDark,
            ),
          ),
        ),
      ],
    );
  }
}
