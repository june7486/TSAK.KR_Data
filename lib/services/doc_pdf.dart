/// 실제 **PDF 파일 바이트** 생성기 (규칙: 기본 출력 = PDF).
///
/// ## 왜 필요한가 (요구 p.28: "파일 생성 자체가 안 됨")
/// 그동안 "PDF 저장"은 새 창에 **인쇄 대화상자**를 띄우는 방식이었다.
/// 브라우저·OS 환경에 따라 인쇄창이 막히거나, 사용자가 "PDF로 저장"을 못 찾아
/// **실제 파일이 만들어지지 않았다.** 이 파일은 `pdf` 패키지로 **진짜 .pdf 바이트**를
/// 만들어 사용자 폴더에 **다운로드**시킨다(인쇄창 불필요).
///
/// `print_doc.dart` 의 [DocMeta]·[DocCell] 표 데이터를 그대로 받아, 인쇄용 HTML
/// (`buildMujiDoc`)과 **동일한 무인양품 스타일**의 PDF를 생성한다.
///
/// ## 샘플 규격 (모든 출력 공통 — 명부·리스트·오더·메뉴·비품·주문·명단·승인창)
///  · 페이지를 **얇은 테두리 박스**로 감싼다.
///  · 최상단 **레터헤드**: 좌 브랜드 · 우 `N of M`(페이지 번호).
///  · 큰 **제목** + 부제/설명/메타(생성일·생성자).
///  · 표 위 **`PART 1`** 구분 라벨 + 가로 규칙선 + 항목 수.
///  · 하단 **출력규칙 · 보고서 · N/M** 푸터.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'print_doc.dart';

class DocPdf {
  static pw.Font? _regular;
  static pw.Font? _bold;

  /// 브랜드 엠블럼(중앙회 마크) — 최초 1회 로드 후 캐시. 문서 제목 옆에 표시한다.
  /// [요구] "명부 출력시 아이콘이 표시되지 않음" — 화면의 엠블럼을 PDF에도 넣는다.
  static pw.MemoryImage? _emblem;
  static bool _emblemTried = false;

  /// 한글 폰트(나눔고딕) — 최초 1회 로드 후 캐시.
  static Future<void> _ensureFonts() async {
    _regular ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Regular-s.ttf'),
    );
    _bold ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NanumGothic-Bold-s.ttf'),
    );
  }

  /// 엠블럼 로드(실패해도 문서 생성은 계속 — 아이콘만 생략).
  static Future<void> _ensureEmblem() async {
    if (_emblemTried) return;
    _emblemTried = true;
    try {
      final b = await rootBundle.load('assets/images/tsak_emblem.png');
      _emblem = pw.MemoryImage(b.buffer.asUint8List());
    } catch (_) {
      _emblem = null;
    }
  }

  /// 제목 + (선택) 엠블럼 아이콘 행.
  static pw.Widget _titleRow(
    String title,
    pw.Font bold, {
    double emblemH = 30,
  }) {
    final t = pw.Text(
      sanitize(title),
      style: pw.TextStyle(
        font: bold,
        fontSize: 18,
        color: _title,
        letterSpacing: -0.2,
      ),
    );
    if (_emblem == null) return t;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: t),
        pw.SizedBox(width: 8),
        pw.Image(_emblem!, height: emblemH, width: emblemH),
      ],
    );
  }

  // MUJI 저채도 팔레트 (print_doc 과 일치)
  static const _ink = PdfColor.fromInt(0xFF3A3A3A);
  static const _title = PdfColor.fromInt(0xFF4A4A48);
  static const _gray = PdfColor.fromInt(0xFF8C877E);
  static const _line = PdfColor.fromInt(0xFFEDEAE3);

  /// 페이지 테두리 박스 색(샘플 규격).
  static const _border = PdfColor.fromInt(0xFFD8D3CA);

  /// 표 헤더 옅은 배경.
  static const _head = PdfColor.fromInt(0xFFF4F1EA);
  static const _strong = PdfColor.fromInt(0xFF4A4A48);

  static PdfColor _hex(String h) {
    var s = h.replaceAll('#', '').trim();
    if (s.length == 6) s = 'FF$s';
    final v = int.tryParse(s, radix: 16) ?? 0xFF7C6A9C;
    return PdfColor.fromInt(v);
  }

  static String _stamp() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${p(d.month)}.${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  /// PDF 폰트(나눔고딕)가 그릴 수 없는 글자(이모지·일부 한자 등)를 **안전한 텍스트로
  /// 치환**한다. (요구: "이모지가 안 보임" — PDF 에서 ▯(두부) 박스로 깨지는 문제)
  ///
  /// 실제 규칙은 print_doc.dart 의 [sanitizeDocText] 하나로 공유한다 — 미리보기(HTML)
  /// 와 실제 PDF 가 **동일한 문자열**을 쓰도록 해 화면=출력이 어긋나지 않게 한다.
  static String sanitize(String? s) => sanitizeDocText(s);

  /// 표 데이터로 **실제 PDF 바이트**를 만든다. (A4 세로 기본)
  ///
  /// 샘플 규격(모든 출력 공통): 얇은 **테두리 박스** + 최상단 **레터헤드**(브랜드 +
  /// `N of M`) + 큰 **제목** + 메타 + **`PART 1`** 구분 라벨 + 표 + 합계 + 푸터.
  ///
  /// [scale] 글씨 크기 배율(작게 0.86 · 보통 1.0 · 크게 1.18).
  /// [rowSpaceMul] 행 간격(밀도) 배율(좁게 0.72 · 보통 1.0 · 넓게 1.35).
  /// [noWrapCols] 두줄 방지 열 인덱스 — 해당 열은 줄바꿈하지 않는다(글씨 자동 축소).
  static Future<Uint8List> build({
    required DocMeta meta,
    List<String> columns = const [],
    List<List<DocCell>> rows = const [],
    List<String> summary = const [],
    String footerLeft = '한국범스카우트중앙회',
    bool landscape = false,
    double scale = 1.0,
    double rowSpaceMul = 1.0,
    Set<int> noWrapCols = const {},
  }) async {
    await _ensureFonts();
    await _ensureEmblem();
    final reg = _regular!;
    final bold = _bold!;
    final now = meta.createdAt.isNotEmpty ? meta.createdAt : _stamp();
    final fmt = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    // (요구) 좁은 열(성명·인가년월일 등)이 **2줄로 접히지 않도록** 폰트를 8.5로
    //  낮추고 셀 좌우 패딩을 줄이며, 열 폭 계산에 패딩을 반영한다(_contentCols).
    //  (요구) 수품 출력에 글씨 크기·줄 간격 옵션 — 배율([scale]/[rowSpaceMul]) 반영.
    final double cellPt = (8.5 * scale * 10).roundToDouble() / 10;
    final int padV = (5 * rowSpaceMul).round().clamp(1, 14);
    final int headV = (6 * rowSpaceMul).round().clamp(1, 16);
    final base = pw.TextStyle(font: reg, fontSize: cellPt, color: _ink);
    final baseBold = pw.TextStyle(font: bold, fontSize: cellPt, color: _ink);

    final doc = pw.Document();

    // ── 헤더 메타(작은 글씨) ──
    final facts = <MapEntry<String, String>>[
      if (meta.author.trim().isNotEmpty) MapEntry('생성자', meta.author),
      MapEntry('생성일', now),
      ...meta.extra.entries,
    ];

    // ── 기초정보 블록 (설명 + 생성일·생성자·추가정보) ──
    final metaBlock = pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _line),
          bottom: pw.BorderSide(color: _line),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (meta.description.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Text(
                sanitize(meta.description),
                style: pw.TextStyle(font: reg, fontSize: 9.5, color: _ink),
              ),
            ),
          pw.Wrap(
            spacing: 22,
            runSpacing: 2,
            children: facts
                .map(
                  (e) => pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: '${e.key} ',
                          style: pw.TextStyle(
                            font: bold,
                            fontSize: 8.5,
                            color: _gray,
                          ),
                        ),
                        pw.TextSpan(
                          text: sanitize(e.value),
                          style: pw.TextStyle(
                            font: reg,
                            fontSize: 8.5,
                            color: _gray,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );

    // ── PART 라벨 (샘플 규격: 다크 라벨 + 가로 규칙선 + 항목 수) ──
    pw.Widget partLabel(int count) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(
            color: _ink,
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Text(
            'PART 1',
            style: pw.TextStyle(
              font: bold,
              fontSize: 8,
              color: PdfColors.white,
              letterSpacing: 0.8,
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(child: pw.Container(height: 0.8, color: _border)),
        pw.SizedBox(width: 10),
        if (count > 0)
          pw.Text(
            '$count개 항목',
            style: pw.TextStyle(font: reg, fontSize: 8, color: _gray),
          ),
      ],
    );

    // ───────────────────────────────────────────────────────────────────────
    // 표 행 단위 수동 페이지 나눔 + **페이지마다 머리행(구분표) 반복**
    //
    // ## 왜 MultiPage + Table 을 쓰지 않는가 (요구: "명부 출력시 페이지가 넘어갈
    // 경우 상단에 구분표 반복해서 노출할 것")
    // `pw.Table` 은 페이지 경계에서 **분할되지 않는다**(canSpan=false). 표가 한
    // 페이지보다 크면 통째로 다음 페이지로 밀리고, 넘치는 행은 아예 사라진다.
    // 실제로 아타스 명부 290명을 출력하면 2페이지 이후가 잘려 나왔다.
    // 그래서 ① 행 높이를 미리 재어 페이지에 담기는 행 수를 계산하고 ② 페이지마다
    // 같은 머리행 위젯을 **다시 그려** 넣는다. 헤더가 모든 페이지 상단에 반복된다.
    // ───────────────────────────────────────────────────────────────────────

    final widths = _contentCols(
      columns,
      rows,
      availableWidth: fmt.width - 36 * 2 - 8,
    );
    final availW = fmt.width - 36 * 2;
    final margin = const pw.EdgeInsets.fromLTRB(36, 40, 36, 30);
    final availBody = fmt.height - margin.vertical;

    // ── 페이지 장식(레터헤드·푸터) — 높이를 **실제로 재어** 본문 가용 높이에서
    //  뺀다. 추정값을 쓰면 첫 페이지에서 행이 한 줄 넘쳐 다음 페이지로 밀리고,
    //  그 페이지에 머리행이 없어 '구분표 없는 페이지'가 생긴다(실제 발생).
    pw.Widget pageHeader(pw.Context ctx) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '한국범스카우트중앙회 · TSAK',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 7.5,
                  color: _gray,
                  letterSpacing: 1.0,
                ),
              ),
              pw.Text(
                '${ctx.pageNumber} of ${ctx.pagesCount}',
                style: pw.TextStyle(font: reg, fontSize: 7.5, color: _gray),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(height: 0.6, color: _line),
        ],
      ),
    );

    pw.Widget pageFooter(pw.Context ctx) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              footerLeft,
              style: pw.TextStyle(
                font: reg,
                fontSize: 7.5,
                color: _gray,
                letterSpacing: 0.4,
              ),
            ),
            pw.Text(
              '출력규칙 · 보고서 · ${ctx.pageNumber}/${ctx.pagesCount}',
              style: pw.TextStyle(
                font: reg,
                fontSize: 7.5,
                color: _gray,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );

    /// 1페이지 머리(제목·부제·메타·PART 라벨) — 높이 측정용으로도 쓴다.
    final firstHead = <pw.Widget>[
      _titleRow(meta.title, bold, emblemH: 34),
      if (meta.subtitle.trim().isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text(
            sanitize(meta.subtitle),
            style: pw.TextStyle(font: reg, fontSize: 10, color: _gray),
          ),
        ),
      pw.SizedBox(height: 8),
      metaBlock,
      pw.SizedBox(height: 12),
      if (columns.isNotEmpty || rows.isNotEmpty) ...[
        partLabel(rows.length),
        pw.SizedBox(height: 8),
      ],
    ];

    /// 머리행 — 모든 페이지 상단에 반복 출력된다.
    pw.Widget headRow() => pw.Table(
      border: pw.TableBorder(
        horizontalInside: const pw.BorderSide(color: _line, width: 0.6),
        bottom: const pw.BorderSide(color: _border, width: 0.8),
      ),
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _head),
          children: columns
              .map(
                (c) => pw.Padding(
                  padding: pw.EdgeInsets.fromLTRB(
                    4,
                    headV.toDouble(),
                    4,
                    headV.toDouble(),
                  ),
                  child: pw.Text(
                    sanitize(c),
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: cellPt,
                      color: _strong,
                      // 머리행은 한 줄 고정 — 두 줄로 접히면 페이지마다 높이가
                      // 달라져 행 배치가 어긋난다.
                    ),
                    maxLines: 1,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );

    /// 본문 행 하나.
    pw.Widget bodyRow(int i) => pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line, width: 0.6),
        bottom: pw.BorderSide(color: _border, width: 0.8),
      ),
      columnWidths: widths,
      children: [
        pw.TableRow(
          children: rows[i]
              .asMap()
              .entries
              .map(
                (e) => pw.Container(
                  padding: pw.EdgeInsets.fromLTRB(
                    4,
                    padV.toDouble(),
                    4,
                    padV.toDouble(),
                  ),
                  decoration: e.value.accent != null
                      ? pw.BoxDecoration(
                          border: pw.Border(
                            left: pw.BorderSide(
                              color: _hex(e.value.accent!),
                              width: 2.4,
                            ),
                          ),
                        )
                      : null,
                  child: pw.Column(
                    crossAxisAlignment: _cross(e.value.align),
                    children: [
                      pw.Text(
                        sanitize(e.value.text),
                        style: e.value.bold ? baseBold : base,
                        textAlign: _align(e.value.align),
                        // (요구) 두줄 방지 열 — 줄바꿈 금지(넘치면 자동 축소).
                        softWrap: !noWrapCols.contains(e.key),
                        maxLines: noWrapCols.contains(e.key) ? 1 : null,
                      ),
                      if (e.value.sub != null && e.value.sub!.trim().isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 1.5),
                          child: pw.Text(
                            sanitize(e.value.sub!),
                            style: pw.TextStyle(
                              font: reg,
                              fontSize: (7.5 * scale * 10).roundToDouble() / 10,
                              color: _gray,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );

    // ── 모든 높이를 **실제로 잰다**(레이아웃만 하고 그리지 않는다).
    //  · headerH/footerH: 레터헤드·푸터가 잡아먹는 높이
    //  · headH: 반복 머리행(구분표) 높이
    //  · firstH: 1페이지에만 있는 제목·메타·PART 라벨 높이
    //  추정값 대신 측정값을 쓰므로 '행 1개가 넘쳐서 머리행 없는 페이지'가 생기지
    //  않는다. (측정은 순수 계산이라 부작용 없음 — pdf 패키지 layout 단계)
    final measureDoc = pw.Document();
    final measureCtx = pw.Context(
      document: measureDoc.document,
    ).inheritFromAll(<pw.Inherited>[pw.ThemeData.base()]);

    double measure(pw.Widget w) {
      try {
        w.layout(measureCtx, pw.BoxConstraints(maxWidth: availW));
        return w.box?.height ?? 0;
      } catch (_) {
        return 24.0; // 측정 실패 시 보수적으로 2줄 높이
      }
    }

    final headerH = measure(pageHeader(_FakeCtx()));
    final footerH = measure(pageFooter(_FakeCtx()));
    final headH = columns.isEmpty ? 0.0 : measure(headRow());
    final firstH = measure(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: firstHead,
      ),
    );
    final rowHeights = <double>[
      for (var i = 0; i < rows.length; i++) measure(bodyRow(i)),
    ];

    /// 1페이지 본문 가용 높이 = 전체 − 레터헤드 − 푸터 − 1페이지 머리 − (반복)머리행
    final firstCap = availBody - headerH - footerH - firstH - headH;

    /// 2페이지 이후 = 전체 − 레터헤드 − 푸터 − (반복)머리행
    final contCap = availBody - headerH - footerH - headH;

    /// 한 페이지에 담기는 행 인덱스 구간 목록.
    var pages = <List<int>>[];
    var buf = <int>[];
    var used = 0.0;
    var cap = firstCap;
    for (var i = 0; i < rows.length; i++) {
      // 안전 여유 0.5pt — 반올림 오차로 한 행이 넘치는 것을 막는다.
      if (buf.isNotEmpty && used + rowHeights[i] > cap - 0.5) {
        pages.add(buf);
        buf = <int>[];
        used = 0.0;
        cap = contCap;
      }
      buf.add(i);
      used += rowHeights[i];
    }
    if (buf.isNotEmpty) pages.add(buf);
    if (pages.isEmpty) pages = [<int>[]];

    // ── 합계 ──
    pw.Widget? sumWidget() {
      if (summary.isEmpty) return null;
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 14),
        padding: const pw.EdgeInsets.only(top: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _strong, width: 1.4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: summary
              .map(
                (s) => pw.Text(
                  sanitize(s),
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: (10 * scale * 10).roundToDouble() / 10,
                    color: _ink,
                  ),
                ),
              )
              .toList(),
        ),
      );
    }

    for (var pi = 0; pi < pages.length; pi++) {
      final idxs = pages[pi];
      final last = pi == pages.length - 1;
      doc.addPage(
        pw.MultiPage(
          maxPages: 2,
          pageTheme: pw.PageTheme(
            pageFormat: fmt,
            margin: margin,
            // 샘플 규격: 페이지를 얇은 테두리 박스로 감싼다.
            buildBackground: (ctx) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Container(
                margin: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _border, width: 0.8),
                ),
              ),
            ),
          ),
          // 레터헤드 / 푸터 — 위에서 만든 빌더를 그대로 쓴다(측정값과 동일).
          header: pageHeader,
          footer: pageFooter,
          build: (ctx) => [
            // 1페이지에만 제목·메타·PART 라벨(계속 페이지는 곧바로 머리행).
            if (pi == 0) ...firstHead,
            // ★ 머리행(구분표) — 모든 페이지 상단에 반복된다.
            if (columns.isNotEmpty && idxs.isNotEmpty) headRow(),
            // 이 페이지에 담기는 본문 행.
            for (final i in idxs) bodyRow(i),
            if (last) ?sumWidget(),
          ],
        ),
      );
    }
    return doc.save();
  }

  /// 열 폭을 **내용 길이에 비례**해 자동 배분한다.
  ///
  /// ## 왜 필요한가 (요구: "범스카우트명단, 은하스카우트명단 출력시 여백을 조정해서
  /// 불필요한 공간이 생기지 않도록 해줘")
  /// 기존에는 첫 열만 2배 고정이라, 짧은 '인가번호' 열이 넓게 벌어지고 긴 '성명'
  /// 열이 좁아지는 **불필요한 여백**이 생겼다. 열마다 헤더·셀의 최대 글자폭을 재서
  /// 그 비율대로 폭을 나눠 여백을 없앤다.
  static Map<int, pw.TableColumnWidth> _contentCols(
    List<String> columns,
    List<List<DocCell>> rows, {
    double availableWidth = 517.0,
  }) {
    final n = columns.length;
    if (n <= 0) return const {};
    // 각 열의 **내용** 폭(폰트 1pt 기준). 헤더·서브텍스트·본문을 모두 고려한다.
    final units = List<double>.filled(n, 2.0);
    for (var i = 0; i < n; i++) {
      units[i] = _textUnits(columns[i]);
    }
    for (final r in rows) {
      final lim = r.length < n ? r.length : n;
      for (var i = 0; i < lim; i++) {
        final u = _textUnits(r[i].text);
        if (u > units[i]) units[i] = u;
        final subText = r[i].sub;
        if (subText != null && subText.trim().isNotEmpty) {
          // 서브텍스트는 7.5pt(=본문 8.5pt 대비 환산) — 본문 폭으로 환산해 비교.
          final su = _textUnits(subText) * (7.5 / 8.5);
          if (su > units[i]) units[i] = su;
        }
      }
    }
    // ── 열 폭 배분: **최소요구폭 보장형** ──
    //  좁은 열(예: 성명·인가년월일)이 셀 패딩에 잠식되어 글자가 2줄로 접히는
    //  문제를 막기 위해, 먼저 각 열에 "줄바꿈 없이 필요한 최소 폭"을 배정한 뒤
    //  남는 폭만 내용 비율대로 나눠 준다.
    const double fontPt = 8.5; // 셀 본문 폰트
    const double padU = 8.0; // 셀 좌우 패딩 합(좌 4 + 우 4)
    const double lead = 3.0; // 헤어라인/렌더 오차 여유
    // 페이지 폭 − 좌우 여백 − 테두리(≈ 595 − 36·2 − 여유).
    //  가로(landscape) 출력에서도 같은 비율이 되도록 A4 폭 기준값은 그대로 두되,
    //  호출부가 넘긴 사용 가능 폭이 있으면 그쪽을 우선한다([availableWidth]).
    final double avail = availableWidth;
    final req = <double>[
      for (var i = 0; i < n; i++) units[i] * fontPt + padU + lead,
    ];
    final reqSum = req.fold<double>(0, (a, b) => a + b);
    final unitSum = units.fold<double>(0, (a, b) => a + b);
    final m = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < n; i++) {
      double band;
      if (reqSum < avail) {
        // 남는 폭을 내용 비율로 분배.
        final extra = unitSum > 0 ? (avail - reqSum) * units[i] / unitSum : 0;
        band = req[i] + extra;
      } else {
        // 폭이 부족한 극단적 경우엔 내용 비율대로 축소(최소 10pt 보장).
        band =
            avail *
            (units[i] + padU) /
            (unitSum + padU * n).clamp(1.0, double.infinity);
      }
      m[i] = pw.FlexColumnWidth(band.clamp(10.0, 300.0));
    }
    return m;
  }

  /// 문자열의 대략적 글자폭(폰트 1pt 기준). 한글 1.0 · 공백 0.32 · 그 외 0.56.
  static double _textUnits(String? s) {
    var u = 0.0;
    for (final c in (s ?? '').trim().runes) {
      if (c == 0x20) {
        u += 0.32;
      } else if (c >= 0x1100) {
        u += 1.0;
      } else {
        u += 0.56;
      }
    }
    return u;
  }

  static pw.TextAlign _align(String a) {
    switch (a) {
      case 'center':
        return pw.TextAlign.center;
      case 'right':
        return pw.TextAlign.right;
      default:
        return pw.TextAlign.left;
    }
  }

  static pw.CrossAxisAlignment _cross(String a) {
    switch (a) {
      case 'center':
        return pw.CrossAxisAlignment.center;
      case 'right':
        return pw.CrossAxisAlignment.end;
      default:
        return pw.CrossAxisAlignment.start;
    }
  }

  /// 표 없이 제목·본문(줄 목록)만 있는 간단 PDF.
  static Future<Uint8List> buildText({
    required DocMeta meta,
    required List<String> lines,
    String footerLeft = '한국범스카우트중앙회',
  }) => build(meta: meta, summary: lines, footerLeft: footerLeft);

  // ─────────────────────────────────────────────────────────────────────────
  // 보고서형 PDF — 미리보기(SettlementPaperView)와 **같은 그래픽**
  //
  // ## 요구사항 (그대로)
  // "pdf 출력물의 형태는 결산의 경우 기존 무인양품 스타일을 버리고, 미리보기
  //  항목의 내용을 참조해서 항목별로 보기좋게 출력해주고 … pdf 출력된 항목은
  //  계산서처럼 보여지기보다는 보고서처럼 보여지는게 좋아서그래."
  //
  // ## 왜 별도 빌더인가
  // 기존 [build] 는 머리행 1개 + 평평한 행 목록(무인양품 표)이다. 결산은
  // **여러 블록(참가자·수입·후원·지출·잔액)** 이 이어지고 블록마다 색이 다르며
  // 합계 행은 강조된다. 평평한 표로는 그 구조가 사라져 '계산서'처럼 읽힌다.
  // 이 빌더는 블록마다 ① 컬러 제목 띠(좌측 3pt 바 + 10% 틴트) ② 4열 표
  // ③ 합계 행 5.5% 틴트 ④ 하단 메모 를 그려 **화면 미리보기와 동일한 인상**을
  // 준다.
  // ─────────────────────────────────────────────────────────────────────────

  /// 보고서 한 블록 — 제목 띠 + 4열 행 + 하단 메모.
  static Future<Uint8List> buildReport({
    required DocMeta meta,
    required List<DocReportBlock> blocks,
    List<String> summary = const [],
    String footerLeft = '한국범스카우트중앙회',
    bool landscape = false,
    double scale = 1.0,
    double rowSpaceMul = 1.0,
  }) async {
    await _ensureFonts();
    await _ensureEmblem();
    final reg = _regular!;
    final bold = _bold!;
    final now = meta.createdAt.isNotEmpty ? meta.createdAt : _stamp();
    final fmt = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    final cellPt = (9.0 * scale * 10).roundToDouble() / 10;
    final int padV = (4 * rowSpaceMul).round().clamp(1, 12);
    final base = pw.TextStyle(font: reg, fontSize: cellPt, color: _ink);
    final baseBold = pw.TextStyle(font: bold, fontSize: cellPt, color: _ink);
    // 블록 안 4열 비율 — 미리보기(SettlementPaperView)와 동일: 1.1 / 1.9 / 1.35 / 1.45
    final widths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.1),
      1: const pw.FlexColumnWidth(1.9),
      2: const pw.FlexColumnWidth(1.35),
      3: const pw.FlexColumnWidth(1.45),
    };

    final doc = pw.Document();
    final margin = const pw.EdgeInsets.fromLTRB(34, 38, 34, 28);

    final facts = <MapEntry<String, String>>[
      if (meta.author.trim().isNotEmpty) MapEntry('작성', meta.author),
      MapEntry('출력일', now),
      ...meta.extra.entries,
    ];

    // ── 블록 위젯 ──────────────────────────────────────────────────────
    pw.Widget blockWidget(DocReportBlock b, bool first) {
      final accent = _hex(b.accent);
      return pw.Padding(
        padding: pw.EdgeInsets.only(top: first ? 0 : 10 * rowSpaceMul),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // ① 제목 띠 — 좌측 3pt 컬러 바 + 10% 틴트 (미리보기와 동일)
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(7, 4, 7, 4),
              decoration: pw.BoxDecoration(
                color: PdfColor(
                  accent.red,
                  accent.green,
                  accent.blue,
                  0.10,
                ),
                border: pw.Border(
                  left: pw.BorderSide(color: accent, width: 3),
                ),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      sanitize(b.title),
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: cellPt * 1.02,
                        color: accent,
                      ),
                    ),
                  ),
                  if (b.subtitle.trim().isNotEmpty)
                    pw.Text(
                      sanitize(b.subtitle),
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: cellPt * 0.78,
                        color: PdfColor(
                          accent.red,
                          accent.green,
                          accent.blue,
                          0.7,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ② 4열 표
            pw.Table(
              columnWidths: widths,
              border: pw.TableBorder(
                horizontalInside: const pw.BorderSide(
                  color: _border,
                  width: 0.6,
                ),
              ),
              children: [
                for (final r in b.rows)
                  pw.TableRow(
                    decoration: _isReportTotal(r)
                        ? pw.BoxDecoration(
                            color: PdfColor(
                              accent.red,
                              accent.green,
                              accent.blue,
                              0.055,
                            ),
                          )
                        : null,
                    children: [
                      _rcell(
                        r.isNotEmpty ? r[0] : '',
                        base: baseBold,
                        accent: _isReportTotal(r) ? accent : null,
                        padV: padV,
                      ),
                      _rcell(r.length > 1 ? r[1] : '', base: base, padV: padV),
                      _rcell(
                        r.length > 2 ? r[2] : '',
                        base: baseBold,
                        align: 'right',
                        accent: _isReportTotal(r) ? accent : null,
                        padV: padV,
                      ),
                      _rcell(r.length > 3 ? r[3] : '', base: base, padV: padV),
                    ],
                  ),
              ],
            ),
            // ③ 하단 메모
            if (b.note.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3, left: 2),
                child: pw.Text(
                  sanitize(b.note),
                  style: pw.TextStyle(
                    font: reg,
                    fontSize: cellPt * 0.82,
                    color: _gray,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: fmt,
          margin: margin,
          buildBackground: (ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(
              margin: const pw.EdgeInsets.all(13),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _border, width: 0.8),
              ),
            ),
          ),
        ),
        header: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 7),
          child: pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '한국범스카우트중앙회 · TSAK',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 7.5,
                      color: _gray,
                      letterSpacing: 1.0,
                    ),
                  ),
                  pw.Text(
                    '${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: pw.TextStyle(
                      font: reg,
                      fontSize: 7.5,
                      color: _gray,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Container(height: 0.6, color: _line),
            ],
          ),
        ),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Container(
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _line)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  footerLeft,
                  style: pw.TextStyle(
                    font: reg,
                    fontSize: 7.5,
                    color: _gray,
                    letterSpacing: 0.4,
                  ),
                ),
                pw.Text(
                  '보고서 · ${ctx.pageNumber}/${ctx.pagesCount}',
                  style: pw.TextStyle(
                    font: reg,
                    fontSize: 7.5,
                    color: _gray,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        build: (ctx) => [
          // 제목 + 부제 (1페이지 상단)
          _titleRow(meta.title, bold, emblemH: 32),
          if (meta.subtitle.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(
                sanitize(meta.subtitle),
                style: pw.TextStyle(font: reg, fontSize: 10, color: _gray),
              ),
            ),
          pw.SizedBox(height: 7),
          // 설명 + 작성/출력일
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: _line),
                bottom: pw.BorderSide(color: _line),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (meta.description.trim().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Text(
                      sanitize(meta.description),
                      style: pw.TextStyle(
                        font: reg,
                        fontSize: 9,
                        color: _ink,
                      ),
                    ),
                  ),
                pw.Wrap(
                  spacing: 20,
                  runSpacing: 2,
                  children: [
                    for (final e in facts)
                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(
                              text: '${e.key} ',
                              style: pw.TextStyle(
                                font: bold,
                                fontSize: 8,
                                color: _gray,
                              ),
                            ),
                            pw.TextSpan(
                              text: sanitize(e.value),
                              style: pw.TextStyle(
                                font: reg,
                                fontSize: 8,
                                color: _gray,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          // 블록들 — MultiPage 가 페이지 경계에서 자연스럽게 나눈다.
          for (var i = 0; i < blocks.length; i++)
            blockWidget(blocks[i], i == 0),
          // 합계 요약
          if (summary.isNotEmpty)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 14),
              padding: const pw.EdgeInsets.only(top: 9),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: _strong, width: 1.3)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  for (final s in summary)
                    pw.Text(
                      sanitize(s),
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: (10 * scale * 10).roundToDouble() / 10,
                        color: _ink,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    return doc.save();
  }

  /// 보고서 표의 셀 하나.
  static pw.Widget _rcell(
    String text, {
    required pw.TextStyle base,
    String align = 'left',
    PdfColor? accent,
    int padV = 4,
  }) {
    return pw.Container(
      padding: pw.EdgeInsets.fromLTRB(5, padV.toDouble(), 5, padV.toDouble()),
      child: pw.Text(
        sanitize(text),
        style: accent == null
            ? base
            : pw.TextStyle(
                font: base.font,
                fontSize: base.fontSize,
                color: accent,
                fontWeight: pw.FontWeight.bold,
              ),
        textAlign: _align(align),
      ),
    );
  }

  /// 합계 행인가 — 미리보기 `_isTotal` 과 같은 규칙.
  static bool _isReportTotal(List<String> r) {
    final k = r.isNotEmpty ? r[0] : '';
    return k.contains('합계') || k == '잔액' || k == '초과';
  }

  /// 문자열 표(헤더/행)로 **실제 PDF**를 만든다.
  ///
  /// 여러 화면(판매대장·재고·공여 등)이 표 데이터를 `List<List<String>>`
  /// 형태로 이미 갖고 있어, 이를 그대로 받아 MUJI 스타일 PDF로 변환한다.
  /// 첫 열에 좌측 컬러 바를 자동 적용한다.
  static Future<Uint8List> buildSimple({
    required DocMeta meta,
    List<String> columns = const [],
    List<List<String>> rows = const [],
    List<String> summary = const [],
    String footerLeft = '한국범스카우트중앙회',
    bool landscape = false,
    String align = 'left',
    double scale = 1.0,
    double rowSpaceMul = 1.0,
    Set<int> noWrapCols = const {},
  }) {
    final docRows = rows.asMap().entries.map((e) {
      final ac = kMujiAccents[e.key % kMujiAccents.length];
      return e.value.asMap().entries.map((c) {
        return DocCell(
          c.value,
          accent: c.key == 0 ? ac : null,
          align: c.key == 0 ? 'left' : align,
        );
      }).toList();
    }).toList();
    return build(
      meta: meta,
      columns: columns,
      rows: docRows,
      summary: summary,
      footerLeft: footerLeft,
      landscape: landscape,
      scale: scale,
      rowSpaceMul: rowSpaceMul,
      noWrapCols: noWrapCols,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 전원을 **A4 한 장**에 담는 압축 명부 레이아웃
  // ─────────────────────────────────────────────────────────────────────────

  /// NanumGothic ascender / upem (행 높이 계산 보정값).
  static const double _asc = 1.024;

  /// 열 간격(여백 사이) · 각 행 상하 패딩.
  static const double _rosterGap = 2.0;
  static const double _rosterPad = 1.2;

  /// 번호 문자열(예: `은하165`)의 폭(폰트 1pt 기준). 한글 0.96 · 숫자 0.55.
  static double _numUnits(int maxNum) {
    var u = 0.0;
    for (final c in '은하$maxNum'.runes) {
      u += c >= 0x1100 ? 0.96 : 0.55;
    }
    return u;
  }

  /// 이름 문자열의 폭(폰트 1pt 기준). 한글 0.98 · 공백 0.32.
  static double _nameUnits(String s) {
    var u = 0.0;
    for (final c in s.trim().runes) {
      u += (c == 0x20) ? 0.32 : 0.98;
    }
    return u < 1.0 ? 1.0 : u;
  }

  /// PDF 바이트의 **페이지 수**를 센다(pdf 패키지 산출물은 비압축이라 가능).
  static int _pdfPageCount(Uint8List b) {
    final s = String.fromCharCodes(b);
    final re = RegExp(r'/Type\s*/Page(?![s])');
    var n = 0;
    for (final _ in re.allMatches(s)) {
      n++;
    }
    return n;
  }

  /// 명부 항목([rows]: `[번호, 이름]`)을 **여러 열**로 나눠 A4 **한 장**에 담는다.
  ///
  /// 글자 크기와 열 수를 폭·높이에 맞춰 **자동**으로 고르고, 마지막에 실제 페이지
  /// 수를 확인(2-pass)해 1장을 보장한다. 샘플 규격(레터헤드·PART 1·푸터·테두리
  /// 박스)은 그대로 유지한다.
  static Future<Uint8List> buildRosterOnePage({
    required DocMeta meta,
    required List<List<String>> rows,
    String footerLeft = '한국범스카우트중앙회',
    int maxCols = 6,
    double desiredPt = 14.0,
  }) async {
    await _ensureFonts();
    await _ensureEmblem();
    _lastRosterCols = 1;

    if (rows.isEmpty) {
      return build(meta: meta, footerLeft: footerLeft);
    }

    const double ml = 34, mr = 34, mt = 22, mb = 16;
    final availW = PdfPageFormat.a4.width - ml - mr;
    final contentH = PdfPageFormat.a4.height - mt - mb;
    final n = rows.length;

    // 이름/번호 최대 폭(폰트 1pt 기준).
    var maxNameU = 1.0;
    var maxNum = 0;
    for (final r in rows) {
      if (r.isNotEmpty) {
        final u = _nameUnits(r.length > 1 ? r[1] : '');
        if (u > maxNameU) maxNameU = u;
        final num = int.tryParse((r[0]).replaceAll(RegExp(r'[^0-9]'), ''));
        if (num != null && num > maxNum) maxNum = num;
      }
    }
    final maxNumU = _numUnits(maxNum);

    Uint8List? out;
    // 본문에 허용할 높이(고정 헤더/푸터/제목 여백을 뺀 값)를 조금씩 줄여가며
    // 1장이 되는 계획을 찾는다.
    for (final reserve in const [58.0, 84.0, 116.0, 150.0]) {
      final maxBodyH = contentH - reserve;

      // 가장 글자가 큰(=열이 적은) 계획을 고른다.
      int cols = 1;
      var pt = 8.0;
      var rowH = pt * _asc + 2 * _rosterPad;
      var bodyH = 0.0;
      var found = false;
      for (var c = 1; c <= maxCols; c++) {
        if (c > n) break;
        final per = (n + c - 1) ~/ c;
        final colW = (availW - (c - 1) * _rosterGap) / c;
        final ptW = (colW - 2.0 - _rosterGap) / (maxNameU + maxNumU);
        final ptH = (maxBodyH / per - 2 * _rosterPad) / _asc;
        var p = desiredPt;
        if (ptW < p) p = ptW;
        if (ptH < p) p = ptH;
        if (p < 7) continue;
        final rh = p * _asc + 2 * _rosterPad;
        final bh = rh * per;
        if (bh > maxBodyH) continue;
        if (!found || p > pt + 0.001) {
          cols = c;
          pt = p;
          rowH = rh;
          bodyH = bh;
          found = true;
        }
      }

      final bytes = await _buildRoster(
        meta: meta,
        rows: rows,
        cols: cols,
        pt: pt,
        rowH: rowH,
        bodyH: bodyH,
        numW: maxNumU * pt + 2.0,
        availW: availW,
        footerLeft: footerLeft,
        margins: const pw.EdgeInsets.fromLTRB(ml, mt, mr, mb),
      );
      out = bytes;
      if (_pdfPageCount(bytes) <= 1) break;
    }
    return out!;
  }

  /// 마지막 [buildRosterOnePage] 에서 고른 열 수(참고용).
  static int _lastRosterCols = 1;
  static int get lastRosterCols => _lastRosterCols;

  static Future<Uint8List> _buildRoster({
    required DocMeta meta,
    required List<List<String>> rows,
    required int cols,
    required double pt,
    required double rowH,
    required double bodyH,
    required double numW,
    required double availW,
    required String footerLeft,
    required pw.EdgeInsets margins,
  }) async {
    final reg = _regular!;
    final bold = _bold!;
    _lastRosterCols = cols;
    final n = rows.length;
    final colW = (availW - (cols - 1) * _rosterGap) / cols;
    final nameW = colW - numW - 2.0;

    // ── 격자 ──
    final per = (n + cols - 1) ~/ cols;
    final cells = <pw.Widget>[];
    for (var c = 0; c < cols; c++) {
      final col = <pw.Widget>[];
      for (var i = 0; i < per; i++) {
        final idx = c * per + i;
        if (idx >= n) break;
        col.add(
          pw.Container(
            height: rowH,
            padding: const pw.EdgeInsets.symmetric(vertical: _rosterPad),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(
                  width: numW,
                  child: pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      sanitize(rows[idx][0]),
                      style: pw.TextStyle(
                        font: reg,
                        fontSize: pt * 0.8,
                        color: _title,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
                pw.SizedBox(width: 2),
                pw.SizedBox(
                  width: nameW,
                  child: pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      sanitize(rows[idx].length > 1 ? rows[idx][1] : ''),
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: pt,
                        color: _ink,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      cells.add(
        pw.SizedBox(
          width: colW,
          height: bodyH,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: col,
          ),
        ),
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: margins,
          buildBackground: (ctx) => tsakPdfPageBox(inset: 12),
        ),
        build: (ctx) => [
          // 레터헤드
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 3),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _line)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '한국범스카우트중앙회 · TSAK',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 6.5,
                    color: _gray,
                    letterSpacing: 0.8,
                  ),
                ),
                pw.Text(
                  '1 of 1',
                  style: pw.TextStyle(font: reg, fontSize: 6.5, color: _gray),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 2),
          // 제목 + (엠블럼 아이콘)
          _titleRow(meta.title, bold, emblemH: 26),
          pw.Text(
            meta.subtitle.trim().isNotEmpty
                ? '${sanitize(meta.subtitle)}    인원 전체 $n명'
                : '인원 전체 $n명',
            style: pw.TextStyle(font: reg, fontSize: 6.5, color: _gray),
          ),
          pw.SizedBox(height: 3),
          // PART 라벨 + 규칙선 + 항목 수
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: pw.BoxDecoration(
                  color: _title,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Text(
                  'PART 1',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 6,
                    color: PdfColors.white,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(child: pw.Container(height: 0.6, color: _border)),
              pw.SizedBox(width: 6),
              pw.Text(
                '$n개 항목 · A4 1장',
                style: pw.TextStyle(font: reg, fontSize: 6, color: _gray),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Wrap(spacing: _rosterGap, runSpacing: 0, children: cells),
          pw.SizedBox(height: 4),
          // 푸터
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 3),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _line)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  footerLeft,
                  style: pw.TextStyle(font: reg, fontSize: 6.5, color: _gray),
                ),
                pw.Text(
                  '출력규칙 · 보고서 · 1/1',
                  style: pw.TextStyle(font: reg, fontSize: 6.5, color: _gray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// 줄바꿈 텍스트([text])를 문단 목록으로 렌더한 **실제 PDF**를 만든다.
  ///
  /// 표 구조가 없는 리포트(요약 텍스트)를 빠르게 PDF 파일로 저장할 때 사용한다.
  static Future<Uint8List> buildFromText({
    required DocMeta meta,
    required String text,
    String footerLeft = '한국범스카우트중앙회',
    double scale = 1.0,
    double rowSpaceMul = 1.0,
  }) {
    final lines = text.split('\n').map((l) => l.trimRight()).toList();
    return build(
      meta: meta,
      summary: lines,
      footerLeft: footerLeft,
      scale: scale,
      rowSpaceMul: rowSpaceMul,
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// 샘플 규격 공용 PDF 크롬(chrome) — 자체 `pw.MultiPage` 로 PDF 를 만드는 화면
/// (명단·회계·출입기록 등)에서 재사용하는 최소 헬퍼. `DocPdf.build` 를 쓰지 않는
/// 출력도 동일한 **테두리 박스 + 푸터** 규격을 유지하도록 한다.
/// ─────────────────────────────────────────────────────────────────────────

const PdfColor _tsakPdfBorder = PdfColor.fromInt(0xFFD8D3CA);
const PdfColor _tsakPdfLine = PdfColor.fromInt(0xFFEDEAE3);
const PdfColor _tsakPdfGray = PdfColor.fromInt(0xFF8C877E);

/// (샘플 규격) 페이지를 감싸는 **얇은 테두리 박스** 배경.
pw.Widget tsakPdfPageBox({
  double inset = 14,
  PdfColor color = _tsakPdfBorder,
}) => pw.FullPage(
  ignoreMargins: true,
  child: pw.Container(
    margin: pw.EdgeInsets.all(inset),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: color, width: 0.8),
    ),
  ),
);

/// (샘플 규격) 자체 `pw.MultiPage` 에 넘길 `pageTheme` — 테두리 박스 포함.
pw.PageTheme tsakPdfPageTheme({
  required PdfPageFormat format,
  pw.EdgeInsets margin = const pw.EdgeInsets.fromLTRB(36, 40, 36, 30),
}) => pw.PageTheme(
  pageFormat: format,
  margin: margin,
  buildBackground: (ctx) => tsakPdfPageBox(),
);

/// (샘플 규격) 공통 **푸터** — 좌 기관명 · 우 `출력규칙 · 보고서 · N/M`.
pw.Widget tsakPdfFooter({
  required int pageNumber,
  required int pagesCount,
  String left = '한국범스카우트중앙회',
  pw.Font? font,
  pw.Font? fontBold,
}) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 8),
  child: pw.Container(
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _tsakPdfLine)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          left,
          style: pw.TextStyle(
            font: font,
            fontWeight: fontBold != null && font == null
                ? pw.FontWeight.bold
                : null,
            fontSize: 7.5,
            color: _tsakPdfGray,
            letterSpacing: 0.4,
          ),
        ),
        pw.Text(
          '출력규칙 · 보고서 · $pageNumber/$pagesCount',
          style: pw.TextStyle(
            font: font,
            fontSize: 7.5,
            color: _tsakPdfGray,
            letterSpacing: 0.4,
          ),
        ),
      ],
    ),
  ),
);

/// 페이지 번호를 **측정용으로만** 흉내내는 최소 Context.
///
/// 레터헤드/푸터는 `ctx.pageNumber`·`ctx.pagesCount` 를 읽는다. 높이만 재면 되므로
/// 0/0 으로도 폭·높이가 동일하다. `pw.Context` 를 직접 만들 수 없어 얇은 대역을 쓴다.
class _FakeCtx implements pw.Context {
  @override
  int get pageNumber => 0;

  @override
  int get pagesCount => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
