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

import 'output_templates.dart';
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

  // ───────────────────────────────────────────────────────────────────────
  // 한자(CJK) 폴백 — [요구] "한자(金李朴…)가 PDF 에서 사라진다"
  //
  // 왜 별도 폰트인가:
  //  번들 나눔고딕(-s, 서브셋)은 **한글 전용**이다. cmap 에 CJK 구간이 0자라
  //  한자를 그릴 수 없고, `_paperSafe` 가 조용히 지워버렸다(□ 조차 안 남음).
  //  나눔고딕을 통짜로 쓰면 20MB 라 앱이 무거워지므로, **한자 구간만** 뽑은
  //  Noto Sans CJK KR 서브셋(4.9MB)을 fontFallback 으로 붙인다.
  //
  // 왜 조건부(지연) 로딩인가:
  //  문서에 한자가 한 글자도 없으면 4.9MB 를 읽을 이유가 없다. 그래서
  //  [build]/[buildReport] 진입 시 **문서 텍스트를 먼저 훑어** 한자가 있을
  //  때만 `_ensureHanja()` 를 호출한다. (웹 초기 로딩·메모리 부담 최소화)
  //
  // ⚠️ OOM 주의: 이 서브셋은 `CFF `(OTF) 아웃라인이다. CJK 폰트를 임베드하면
  //  서브셋 글리프가 늘어 파일이 커질 수 있으므로, 한자를 쓰는 문서에서만
  //  로드하고 로드 후 캐시를 유지한다(매 문서 재파싱 금지).
  // ───────────────────────────────────────────────────────────────────────
  /// ⚠️ (2026-10-25) **기본 비활성.** 아래 실패 원인이 해결되면 `_hanjaOn = true`.
  ///
  /// pdf 3.12.0 은 `TextStyle.fontFallback` 을 제공하지만, 표 셀·TextSpan 등
  /// 일부 경로에서 폴백 폰트를 조회하지 않고 **원본 폰트로만** 글자를 그린다.
  /// 그래서 한자가 들어오면 `Invalid argument (string): Contains invalid
  /// characters` 로 PDF 생성이 **통째로 실패**한다(실측).
  /// 조용히 사라지는 것보다, 아예 켜지 않는 편이 안전하다.
  ///
  /// 대신 `print_doc.sanitizeDocText` 의 한자 제거를 없앴으므로
  /// **브라우저 인쇄(HTML) 경로에서는 이제 한자가 정상 출력**된다.
  static const bool _hanjaOn = false;

  static pw.Font? _hanja;
  static bool _hanjaTried = false;

  /// 테스트 전용 — rootBundle 없이 폰트를 주입한다(`flutter test` 용).
  ///  `_ensureFonts`/`_ensureHanja` 는 이미 값이 있으면 다시 읽지 않으므로,
  ///  테스트에서 실제 파일을 로드해 넣으면 네트워크/에셋 없이 검증할 수 있다.
  static void debugSetFonts({
    pw.Font? regular,
    pw.Font? bold,
    pw.Font? hanja,
  }) {
    if (regular != null) _regular = regular;
    if (bold != null) _bold = bold;
    if (hanja != null) {
      _hanja = hanja;
      _hanjaTried = true;
    }
  }

  static bool _hasHanja(String? s) {
    if (s == null || s.isEmpty) return false;
    for (final r in s.runes) {
      if ((r >= 0x3400 && r <= 0x4DBF) || // CJK 확장 A
          (r >= 0x4E00 && r <= 0x9FFF) || // CJK 통합
          (r >= 0xF900 && r <= 0xFAFF)) {
        // CJK 호환
        return true;
      }
    }
    return false;
  }

  static bool _hasHanjaIn(Object? v) {
    if (v == null) return false;
    if (v is String) return _hasHanja(v);
    if (v is Iterable) return v.any(_hasHanjaIn);
    if (v is Map) return v.values.any(_hasHanjaIn);
    return false;
  }

  /// 문서에 한자가 있을 때만 한자 폴백 폰트를 로드한다(실패해도 계속).
  static Future<void> _ensureHanja() async {
    if (!_hanjaOn) return; // 위 주석 참조 — pdf 패키지 미지원
    if (_hanjaTried) return;
    _hanjaTried = true;
    try {
      _hanja = pw.Font.ttf(
        await rootBundle.load('assets/fonts/TsakHanja-s.ttf'),
      );
    } catch (_) {
      _hanja = null;
    }
  }

  /// 텍스트 스타일에 한자 폴백을 붙인다(로드되지 않았으면 그대로 반환).
  static pw.TextStyle _fb(pw.TextStyle s) {
    final h = _hanja;
    if (h == null) return s;
    return pw.TextStyle(
      font: s.font,
      fontFallback: [h],
      fontSize: s.fontSize,
      color: s.color,
      fontWeight: s.fontWeight,
      fontStyle: s.fontStyle,
      letterSpacing: s.letterSpacing,
      lineSpacing: s.lineSpacing,
      decoration: s.decoration,
    );
  }

  /// 엠블럼 로드(실패해도 문서 생성은 계속 — 아이콘만 생략).
  static Future<void> _ensureEmblem() async {    if (_emblemTried) return;
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
    bool centered = false,
  }) {
    final t = pw.Text(
      sanitize(title),
      textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left,
      style: pw.TextStyle(
        font: bold,
        fontSize: 18,
        color: _title,
        letterSpacing: -0.2,
      ),
    );
    // 인장형(official·stamp) — 제목을 **가운데** 두고 문장(엠블럼)은 위에 얹는다.
    //  제출용 문서는 제목이 가운데 오는 것이 관례라, 표 정렬만 바꾸면 다른
    //  템플릿과 시각적으로 섞이지 않는다.
    if (centered && _emblem != null) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: pw.Image(_emblem!, height: emblemH, width: emblemH)),
          pw.SizedBox(height: 4),
          t,
        ],
      );
    }
    final body = centered
        ? pw.SizedBox(width: double.infinity, child: t)
        : t;
    if (_emblem == null) return body;
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

  /// ⚠️ **`PdfColor(r, g, b, alpha)` 의 4번째 인자(알파)는 `pdf` 패키지가
  /// 버린다** — `BoxDecoration.color` / `TableRow.decoration` 안에서는 조용히
  /// 무시되어 **완전 불투명**으로 그려진다.
  ///
  /// 실측 근거: 알파 0.10 으로 지정한 `#2E5F8A` 띠를 PDF 에서 역추적하면
  /// `fill (0.18039, 0.37255, 0.54118)` = 알파가 사라진 원색 그대로였다.
  /// 그 결과 ① 띠가 진한 색으로 꽉 차고 ② 제목 글씨도 같은 색이라 **글자가
  /// 배경에 묻혀 보이지 않았다**. (요구: "글자와 배경의 가독성이 매우 낮아짐")
  ///
  /// 그래서 여기서는 알파를 **흰 종이 위에 합성한 불투명 색**으로 미리 계산한다.
  /// `blend = 1 - (1 - c) * a` (a=0 → 흰색, a=1 → 원색).
  static PdfColor _tint(PdfColor c, double a) {
    final t = a.clamp(0.0, 1.0);
    if (t >= 0.999) return c;
    if (t <= 0.001) return PdfColor.fromInt(0xFFFFFFFF);
    return PdfColor(
      1 - (1 - c.red) * t,
      1 - (1 - c.green) * t,
      1 - (1 - c.blue) * t,
    );
  }

  /// 악센트를 살짝 어둡게 — 띠 위 제목 글씨용(배경과 **명도 차이**를 만든다).
  /// `k = 0` 원색, `k = 1` 검정.
  static PdfColor _darken(PdfColor c, double k) {
    final t = k.clamp(0.0, 1.0);
    // 0.62 는 '진한 색이되 검정은 아닌' 지점 — 인쇄에서도 악센트가 남는다.
    final m = t * 0.62;
    return PdfColor(c.red * (1 - m), c.green * (1 - m), c.blue * (1 - m));
  }

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
  ///
  /// 여기에 **종이(PDF) 전용 2차 필터**를 하나 더 건다. 이유:
  ///  · HTML(브라우저)은 OS 폰트로 CJK·기호를 모두 그리지만, PDF 는 번들
  ///    나눔고딕 **하나**로 그린다. 이 폰트에는 CJK 한자(0x4E00~)와 `✓ ㎡ ① ㎏ ㈜`
  ///    같은 일부 기호가 **없다** → 그대로 두면 PDF 에서 □(두부)가 된다.
  ///    (요구: "아이콘이 박스로 표현되는 것도 다시 체크")
  ///  · 그래서 [sanitize] 는 PDF 경로 전용으로 두고, 실측한 글리프 표와 대조해
  ///    그릴 수 없는 글자만 조용히 제거한다. HTML 경로는 [sanitizeDocText] 만 쓴다.
  static String sanitize(String? s) => _paperSafe(sanitizeDocText(s));

  /// 번들 나눔고딕(s) 이 실제로 가진 글자 구간 — `fontTools` 로 cmap 을 뽑아 만든
  /// **실측 표**이다(35개 구간). 여기 없는 글자는 PDF 에서 반드시 □ 가 된다.
  ///
  /// ⚠️ 폰트를 교체하면 이 표도 다시 뽑아야 한다.
  static const List<String> _paperRanges = [
    '0x20-0x7E,0xB0-0xB3,0xB7,0xD7,0xF7,0x2013-0x2014,0x2018-0x2019,0x201C-0x201D',
    '0x2022,0x2026,0x203B,0x20A9,0x2190-0x2194,0x25A0-0x25A1,0x25B2,0x25B6,0x25BC',
    '0x25C0,0x25C6-0x25C7,0x25CB,0x25CF,0x2605-0x2606,0x2661,0x2665,0x2716',
    '0x3001-0x3003,0x3008-0x3019,0x301E-0x3020,0x3036,0x3131-0x3163,0x3165-0x318E',
    '0xAC00-0xD7A3,0xFF01-0xFF5E,0xFFE0-0xFFE3,0xFFE5-0xFFE6',
  ];

  static List<List<int>>? _rangeCache;

  static List<List<int>> _ranges() {
    final c = _rangeCache;
    if (c != null) return c;
    final out = <List<int>>[];
    for (final line in _paperRanges) {
      for (final token in line.split(',')) {
        final t = token.trim();
        if (t.isEmpty) continue;
        final dash = t.indexOf('-', 1);
        if (dash < 0) {
          final v = int.parse(t);
          out.add([v, v]);
        } else {
          out.add([int.parse(t.substring(0, dash)), int.parse(t.substring(dash + 1))]);
        }
      }
    }
    _rangeCache = out;
    return out;
  }

  /// 폰트가 그릴 수 없는 글자를 제거한다(PDF 전용). 공백·줄바꿈은 보존.
  ///
  /// 한자 폴백([_hanja])이 로드돼 있으면 CJK 구간을 **지우지 않는다** —
  /// 예전에는 한자를 무조건 지워 '金 李 朴' 같은 이름이 통째로 사라졌다.
  static bool _isCjk(int r) =>
      (r >= 0x3400 && r <= 0x4DBF) ||
      (r >= 0x4E00 && r <= 0x9FFF) ||
      (r >= 0xF900 && r <= 0xFAFF);

  static String _paperSafe(String s) {
    if (s.isEmpty) return s;
    final ranges = _ranges();
    final keepHanja = _hanja != null;
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r == 0x0A || r == 0x0D || r == 0x09 || r == 0x20) {
        b.writeCharCode(r);
        continue;
      }
      if (keepHanja && _isCjk(r)) {
        b.writeCharCode(r);
        continue;
      }
      var ok = false;
      for (final g in ranges) {
        if (r >= g[0] && r <= g[1]) {
          ok = true;
          break;
        }
      }
      if (ok) b.writeCharCode(r);
    }
    return b.toString().replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  }

  /// 표 데이터로 **실제 PDF 바이트**를 만든다. (A4 세로 기본)
  ///
  /// 샘플 규격(모든 출력 공통): 얇은 **테두리 박스** + 최상단 **레터헤드**(브랜드 +
  /// `N of M`) + 큰 **제목** + 메타 + **`PART 1`** 구분 라벨 + 표 + 합계 + 푸터.
  ///
  /// [scale] 글씨 크기 배율(작게 0.86 · 보통 1.0 · 크게 1.18).
  /// [rowSpaceMul] 행 간격(밀도) 배율(좁게 0.72 · 보통 1.0 · 넓게 1.35).
  /// [noWrapCols] 두줄 방지 열 인덱스 — 해당 열은 줄바꿈하지 않는다(글씨 자동 축소).
  /// [bands] 열을 **위/아래 두 단으로 쌓을 때** 각 단의 열 인덱스 목록.
  ///
  /// ## 요구 (원문 2026-10-31)
  /// > "항목이 많을 경우에는 가로줄을 하나 더 추가해서 두줄방지 되도록
  /// >  할 수 있는 옵션도 추가해줘"
  ///
  /// 열이 10개를 넘으면 A4 폭에서 열당 30pt 남짓만 남아, 접지 않으면 글씨가
  /// 2pt 로 줄어 읽을 수 없다. [bands] 를 주면 표를 두 단으로 쌓아 **열당 폭을
  /// 두 배**로 늘리고, 단과 단 사이에 **가로 구분선을 하나 더** 긋는다.
  /// null/1개면 종전과 완전히 동일하게 그린다(다른 문서 영향 0).
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
    List<List<int>>? bands,
    int? maxCellLines,
  }) async {
    await _ensureFonts();
    // 한자가 문서에 있을 때만 4.9MB 폴백 폰트를 읽는다(없으면 종전과 동일).
    if (_hanjaOn && (_hasHanjaIn(columns) || _hasHanjaIn(rows))) {
      await _ensureHanja();
    }
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
    // [_fb] — 한자 폴백 폰트를 붙인다(로드되지 않았으면 원본 그대로).
    final base = _fb(pw.TextStyle(font: reg, fontSize: cellPt, color: _ink));
    final baseBold = _fb(pw.TextStyle(font: bold, fontSize: cellPt, color: _ink));

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

    // (요구 2026-10-31 2차) "항목이 너무 길어지면 이름하나당 2줄 이상"
    //  maxCellLines 를 주면 열 폭을 그 줄 수만큼 나눠 잡아, 글씨를 2pt 로
    //  깎아 1줄에 욱여넣는 대신 **2줄로 편하게** 접히게 한다.
    final int cellLines = (maxCellLines ?? 1).clamp(1, 4);
    final widths = _contentCols(
      columns,
      rows,
      availableWidth: fmt.width - 36 * 2 - 8,
      lines: cellLines,
    );
    final availW = fmt.width - 36 * 2;
    final margin = const pw.EdgeInsets.fromLTRB(36, 40, 36, 30);
    final availBody = fmt.height - margin.vertical;

    // ── 두 단(가로 띠) 분할 정의 ─────────────────────────────────────────
    //  bands 가 없으면 bandSplits 는 비어 있고, 아래 렌더링은 종전과 **완전히
    //  동일**하게 동작한다(다른 문서 영향 0).
    final bandSplits = <List<int>>[];
    if (bands != null && bands.length > 1) {
      var ok2 = true;
      for (final b in bands) {
        if (b.isEmpty) {
          ok2 = false;
          break;
        }
      }
      if (ok2) bandSplits.addAll(bands);
    }
    // 단별 열 폭 — 각 단이 **페이지 전폭**을 쓰므로 열당 폭이 약 2배가 된다.
    Map<int, pw.TableColumnWidth> bandWidthsOf(List<int> b) => _contentCols(
      [for (final i in b) i < columns.length ? columns[i] : ''],
      [
        for (final r in rows)
          [for (final i in b) i < r.length ? r[i] : const DocCell('')],
      ],
      availableWidth: fmt.width - 36 * 2 - 8,
      lines: cellLines,
    );

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
    ///
    /// [pick] 을 주면 그 열 인덱스만 골라 **한 단**만 그린다(두 단 모드).
    /// [isLower] 가 true 면 단과 단 사이의 **가로 구분선을 굵게** 그어
    /// "가로줄을 하나 더" 보이게 한다.
    pw.Widget headRow({List<int>? pick, bool isLower = false}) {
      final idx = pick ?? List<int>.generate(columns.length, (i) => i);
      // 두 단 모드 — 아래 단 머리행 위에 **굵은 가로 구분선**을 하나 더 긋는다.
      const sep = pw.BorderSide(color: _strong, width: 1.2);
      return pw.Table(
        border: pw.TableBorder(
          horizontalInside: const pw.BorderSide(color: _line, width: 0.6),
          top: isLower ? sep : pw.BorderSide.none,
          bottom: const pw.BorderSide(color: _border, width: 0.8),
        ),
        columnWidths: pick == null ? widths : bandWidthsOf(idx),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _head),
            children: idx
                .map(
                  (i) => pw.Padding(
                    padding: pw.EdgeInsets.fromLTRB(
                      4,
                      headV.toDouble(),
                      4,
                      headV.toDouble(),
                    ),
                    child: pw.Text(
                      sanitize(i < columns.length ? columns[i] : ''),
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
    }

    /// 본문 행 하나.
    ///
    /// [pick] 이 있으면 그 열만 골라 **한 단**으로 그린다(두 단 모드).
    pw.Widget bodyRow(int i, {List<int>? pick}) {
      final row = rows[i];
      final idx =
          pick ?? List<int>.generate(columns.length, (j) => j);
      return pw.Table(
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _line, width: 0.6),
          bottom: pw.BorderSide(color: _border, width: 0.8),
        ),
        columnWidths: pick == null ? widths : bandWidthsOf(idx),
        children: [
          pw.TableRow(
            children: [
              for (var bi = 0; bi < idx.length; bi++)
                () {
                  // 원본 열 인덱스 — 두줄방지 판정은 **원본 기준**이어야 한다
                  // (단 안에서의 위치 e.key 로 판정하면 엉뚱한 열이 걸린다).
                  final key = idx[bi];
                  final cell = key < row.length
                      ? row[key]
                      : const DocCell('');
                  return pw.Container(
                    padding: pw.EdgeInsets.fromLTRB(
                      4,
                      padV.toDouble(),
                      4,
                      padV.toDouble(),
                    ),
                    decoration: cell.accent != null
                        ? pw.BoxDecoration(
                            border: pw.Border(
                              left: pw.BorderSide(
                                color: _hex(cell.accent!),
                                width: 2.4,
                              ),
                            ),
                          )
                        : null,
                    child: pw.Column(
                      crossAxisAlignment: _cross(cell.align),
                      children: [
                        pw.Text(
                          sanitize(cell.text),
                          style: cell.bold ? baseBold : base,
                          textAlign: _align(cell.align),
                          // (요구) 두줄 방지 열 — 줄바꿈 금지(넘치면 자동 축소).
                          softWrap: !noWrapCols.contains(key),
                          maxLines: noWrapCols.contains(key)
                              ? 1
                              : (maxCellLines == null ? null : cellLines),
                        ),
                        if (cell.sub != null && cell.sub!.trim().isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 1.5),
                            child: pw.Text(
                              sanitize(cell.sub!),
                              style: pw.TextStyle(
                                font: reg,
                                fontSize:
                                    (7.5 * scale * 10).roundToDouble() / 10,
                                color: _gray,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }(),
            ],
          ),
        ],
      );
    }

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
    // 두 단 모드: 단마다 머리행이 하나씩 있으므로 머리 높이는 **단 수 × 단일 머리**.
    final singleHeadH = columns.isEmpty ? 0.0 : measure(headRow());
    final headH = bandSplits.isEmpty
        ? singleHeadH
        : singleHeadH * bandSplits.length;
    final firstH = measure(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: firstHead,
      ),
    );
    // 행 높이 — 두 단이면 각 단의 높이를 **합산**한다(위 단 + 가로줄 + 아래 단).
    final rowHeights = <double>[
      for (var i = 0; i < rows.length; i++)
        bandSplits.isEmpty
            ? measure(bodyRow(i))
            : bandSplits.fold<double>(
                0,
                (s, b) => s + measure(bodyRow(i, pick: b)),
              ),
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
            //  두 단 모드에서는 **단마다** 머리행을 하나씩 두고, 두 번째 단의
            //  머리행 위에 굵은 가로 구분선을 그어 "가로줄이 하나 더" 생긴다.
            if (columns.isNotEmpty && idxs.isNotEmpty) ...[
              if (bandSplits.isEmpty)
                headRow()
              else
                for (var bi = 0; bi < bandSplits.length; bi++) ...[
                  if (bi > 0) pw.SizedBox(height: 7),
                  headRow(pick: bandSplits[bi], isLower: bi > 0),
                ],
            ],
            // 이 페이지에 담기는 본문 행 — 단이 있으면 단별로 쌓는다.
            if (bandSplits.isEmpty) ...[
              for (final i in idxs) bodyRow(i),
            ] else ...[
              for (var bi = 0; bi < bandSplits.length; bi++) ...[
                if (bi > 0) pw.SizedBox(height: 7),
                for (final i in idxs) bodyRow(i, pick: bandSplits[bi]),
              ],
            ],
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
    /// 셀이 가질 수 있는 줄 수 — 2 이상이면 그 줄 수만큼 폭을 **미리** 잡아
    /// 글씨를 깎지 않고도 접히게 한다(요구: "이름하나당 2줄 이상").
    int lines = 1,
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
    // 줄 수([lines]) 를 반영 — 2줄 허용이면 필요한 **1줄 폭**을 절반으로 봐도
    //  된다(그만큼 글씨를 깎지 않고 접혀 들어간다). 최소 폭은 지켜 준다.
    final double lf = lines <= 1 ? 1.0 : (1.0 / lines);
    final req = <double>[
      for (var i = 0; i < n; i++) (units[i] * fontPt * lf) + padU + lead,
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
        //  줄 수 허용([lf])을 반영해, 2줄 모드에서는 열 폭을 그만큼 적게
        //  요구하게 한다(글씨가 2pt 로 깎이는 것을 막는다).
        final uu = units[i] * lf;
        band =
            avail *
            (uu + padU) /
            (unitSum * lf + padU * n).clamp(1.0, double.infinity);
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
    DocTemplate template = DocTemplate.report,
  }) async {
    await _ensureFonts();
    // 한자가 문서에 있을 때만 4.9MB 폴백 폰트를 읽는다.
    if (_hanjaOn &&
        (_hasHanjaIn(blocks.map((b) => [b.title, b.subtitle, b.note, ...b.rows])) ||
            _hasHanjaIn(summary) ||
            _hasHanjaIn(meta.title))) {
      await _ensureHanja();
    }
    await _ensureEmblem();
    final reg = _regular!;
    final bold = _bold!;
    final now = meta.createdAt.isNotEmpty ? meta.createdAt : _stamp();
    final fmt = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    final t = template;
    // ── 글씨 크기 ────────────────────────────────────────────────────────
    //  종전: 9.0pt × 사용자 배율(0.86) = **7.7pt** — A4 인쇄에서 본문이 사실상
    //  읽히지 않았다(요구: "글자와 배경의 가독성이 매우 낮아짐"). 배율은
    //  사용자 의도이므로 살리되, **읽을 수 있는 하한(8.4pt)** 을 둔다.
    final cellPt = ((t.compact ? 8.8 : 9.4) * scale).clamp(8.4, 15.0);
    final int padV = (t.cellPadV * rowSpaceMul).round().clamp(2, 14);
    // [_fb] — 한자 폴백 폰트를 붙인다(로드되지 않았으면 원본 그대로).
    final base = _fb(pw.TextStyle(font: reg, fontSize: cellPt, color: _ink));
    final baseBold = _fb(pw.TextStyle(font: bold, fontSize: cellPt, color: _ink));
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


    /// 한 블록을 **페이지 경계에서 나뉠 수 있는 조각들**로 푼다.
    ///
    /// 반환 순서: [헤더 조각, 행 표 조각, (메모 조각)] — 부가 껍데기(카드
    /// 테두리)는 `pw.Container` 가 SpanningWidget 이 아니므로 **여기서는 쓰지
    /// 않는다**. 카드형 템플릿의 테두리는 포기하고, 대신 블록이 페이지를 넘어도
    /// 내용이 잘리지 않는 쪽을 택한다(빈 페이지보다 낫다).
    ///
    /// `firstFragment`: 블록 첫 조각인지(블록 간 여백 계산용).
    /// `lastFragment` : 블록 마지막 조각인지(아래 여백 계산용).
    List<pw.Widget> blockFrags(DocReportBlock b, bool first) {
      final accent = _hex(b.accent);
      // 색면형(duotone) — 제목 띠를 **원색으로 꽉 채우고 글씨를 흰색**으로 쓴다.
      //  `_tint(accent, 1.0)` 은 원색 그대로다(알파 1 = 흰색 섞임 0).
      //  살짝 어둡게(_darken 0.10) 해서 인쇄기 잉크 번짐에도 대비가 남게 한다.
      final solid = t.isSolidBand;
      final bandTint = solid
          ? _darken(accent, 0.10)
          : _tint(accent, t.bandAlpha * 0.62);
      final totalTint = _tint(accent, t.tintTotal * 0.55);
      final bandInk = _darken(accent, 0.72);
      // 색면 위 글씨는 흰색. 부제는 '흰색 82%' 를 종이에 미리 합성한 옅은 색.
      final bandTitleInk = solid
          ? PdfColor.fromInt(0xFFFFFFFF)
          : (t.accentBand ? bandInk : _ink);
      final bandSubInk = solid ? _tint(accent, 0.84) : _darken(_gray, 0.25);

      // ① 헤더 — 제목 띠 (뜯지 않고 한 덩어리)
      final titleRow = pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Text(
              sanitize(b.title),
              style: pw.TextStyle(
                font: bold,
                fontSize: cellPt * (t.bigFigures ? 1.24 : 1.06),
                color: bandTitleInk,
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (b.subtitle.trim().isNotEmpty)
            pw.Text(
              sanitize(b.subtitle),
              style: pw.TextStyle(
                font: bold,
                fontSize: cellPt * 0.78,
                color: bandSubInk,
              ),
            ),
        ],
      );

      final pw.Widget header = t.accentBand
          ? pw.Container(
              padding: pw.EdgeInsets.fromLTRB(
                t.cellPadH + (solid ? 0 : 2),
                (t.cellPadV + 1.4).roundToDouble(),
                t.cellPadH + (solid ? 0 : 1),
                (t.cellPadV + 1.4).roundToDouble(),
              ),
              decoration: pw.BoxDecoration(
                color: bandTint,
                // 색면형은 꽉 찬 면이라 좌측 바·하단선이 필요 없다(오히려 지저분).
                border: solid
                    ? null
                    : pw.Border(
                        left: pw.BorderSide(
                          color: _darken(accent, 0.25),
                          width: t.bandWidth > 0 ? t.bandWidth : 2.5,
                        ),
                        bottom: pw.BorderSide(
                          color: _tint(accent, 0.42),
                          width: 0.9,
                        ),
                      ),
              ),
              child: titleRow,
            )
          : pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 3),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: _border,
                    width: t.gridLines ? 0.9 : 0.6,
                  ),
                ),
              ),
              child: titleRow,
            );

      // ② 행 표 — MultiPage 의 직접 자식이어야 분할된다.
      final rowsTable = pw.Table(
        columnWidths: widths,
        border: t.gridLines
            ? pw.TableBorder.all(color: _border, width: 0.6)
            : pw.TableBorder(
                horizontalInside: const pw.BorderSide(
                  color: _border,
                  width: 0.6,
                ),
              ),
        children: [
          // ── [요구 2026-10-26] "결산자료 출력시 상세항목이 칸을 넓게 사용하지
          //  않는 레이아웃임 → 옆간을 모두 사용하도록 변경 (기존요청사항임)"
          //
          //  상세 행(`['· 상세', 원본내용, '', '']`)을 4열 표에 그대로 넣으면
          //  긴 원본내용이 **2번째 칸(33%)에만** 갇히고 3·4번째 칸(43%)이 빈다.
          //  → 표에서 빼고 아래 **전폭 블록**으로 내보낸다(미리보기와 동일).
          for (final r in b.rows.where((r) => !_isReportDetail(r)))
            pw.TableRow(
              decoration: (_isReportTotal(r) && t.tintTotal > 0)
                  ? pw.BoxDecoration(color: totalTint)
                  : null,
              children: [
                _rcell(
                  r.isNotEmpty ? r[0] : '',
                  base: baseBold,
                  accent: _isReportTotal(r) ? bandInk : null,
                  padV: padV,
                  padH: t.cellPadH,
                ),
                _rcell(
                  r.length > 1 ? r[1] : '',
                  base: base,
                  padV: padV,
                  padH: t.cellPadH,
                ),
                _rcell(
                  r.length > 2 ? r[2] : '',
                  base: baseBold,
                  align: 'right',
                  accent: _isReportTotal(r) ? bandInk : null,
                  padV: padV,
                  padH: t.cellPadH,
                ),
                _rcell(
                  r.length > 3 ? r[3] : '',
                  base: base,
                  padV: padV,
                  padH: t.cellPadH,
                ),
              ],
            ),
        ],
      );

      // ③ 상세 내역 — 전폭 블록(표 밖).
      final detailLines = <String>[];
      for (final r in b.rows) {
        if (!_isReportDetail(r)) continue;
        final t2 = (r.length > 1 ? r[1] : '').trim();
        if (t2.isNotEmpty) detailLines.add(t2);
      }
      final detailWidget = detailLines.isEmpty
          ? null
          : pw.Container(
              margin: pw.EdgeInsets.only(top: 4, left: t.cellPadH * 0.4),
              padding: pw.EdgeInsets.fromLTRB(
                (t.cellPadH * 0.9).clamp(4.0, 10.0),
                3,
                5,
                4,
              ),
              decoration: pw.BoxDecoration(
                // ⚠️ `_tint(c, a)` 는 **a 가 작을수록 흰색에 가깝다**.
                //  처음엔 0.94 로 줬다가 원색에 가까운 진한 면이 되어
                //  상세 글씨가 배경에 묻혔다(인쇄 가독성 사고).
                //  → 0.07 = 아주 옅은 틴트. 좌측 바만 악센트로 남긴다.
                color: _tint(accent, 0.07),
                border: pw.Border(
                  left: pw.BorderSide(color: _tint(accent, 0.5), width: 1.8),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    sanitize('상세 내역 · ${detailLines.length}건'),
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: (cellPt * 0.86).clamp(7.8, 12.0),
                      color: _darken(accent, 0.35),
                    ),
                  ),
                  pw.SizedBox(height: 1.6),
                  // ── [요구 2026-10-26] "상세내역은 항목별 연번을 매기고
                  //  구분해서 각각의 내역을 보여줘야 읽을 수가 있어"
                  //  이어 붙이면 건별 경계가 사라진다 → 한 건 = 한 줄 + 연번.
                  ...detailLines.asMap().entries.map((e) {
                    final n = e.key + 1;
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 1.2),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // 연번 — 고정폭으로 정렬한다.
                          pw.SizedBox(
                            width: cellPt * 1.5,
                            child: pw.Text(
                              '$n.',
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                font: bold,
                                fontSize: (cellPt * 0.90).clamp(8.0, 12.4),
                                color: _darken(accent, 0.30),
                                lineSpacing: 1.3,
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 3),
                          pw.Expanded(
                            child: pw.Text(
                              sanitize(e.value),
                              style: pw.TextStyle(
                                font: reg,
                                fontSize: (cellPt * 0.94).clamp(8.2, 13.0),
                                // 본문은 배경과 무관하게 **진한 잉크색** 고정.
                                color: _ink,
                                lineSpacing: 1.30,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );

      // ③ 하단 메모
      final noteWidget = b.note.trim().isEmpty
          ? null
          : pw.Container(
              margin: pw.EdgeInsets.only(top: 4, left: t.cellPadH * 0.4),
              padding: pw.EdgeInsets.only(
                left: (t.cellPadH * 0.9).clamp(4.0, 10.0),
                top: 1.5,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  left: pw.BorderSide(color: _tint(accent, 0.5), width: 1.6),
                ),
              ),
              child: pw.Text(
                sanitize(b.note),
                style: pw.TextStyle(
                  font: reg,
                  fontSize: (cellPt * 0.86).clamp(7.6, 12.0),
                  color: _darken(_gray, 0.42),
                  lineSpacing: 1.2,
                ),
              ),
            );

      // 조각 결합 — 블록 사이 여백은 '헤더 조각의 위쪽'에만 준다.
      return [
        pw.Padding(
          padding: pw.EdgeInsets.only(top: first ? 0 : t.blockGap * rowSpaceMul),
          // ⚠ 여백(Padding)은 SpanningWidget 이 아니지만, 그 안의 Table 이
          //  분할되려면 Padding 으로 감싸면 안 된다 → 헤더만 감싼다.
          child: header,
        ),
        if (b.rows.isNotEmpty) rowsTable,
        // 상세 내역 — 표 아래 전폭 블록(요구: 옆간을 모두 사용).
        if (detailWidget != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1),
            child: detailWidget,
          ),
        if (noteWidget != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1),
            child: noteWidget,
          )
        else
          pw.SizedBox(height: 1),
      ];
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
                border: t.doubleRule
                    // 인장형 — 안쪽에 한 줄 더 그어 **이중 실선**으로 만든다.
                    //  다른 7종은 단선이므로 서식만 봐도 구분된다.
                    ? pw.Border.all(color: _border, width: 0.8)
                    : pw.Border.all(color: _border, width: 0.8),
              ),
              child: t.doubleRule
                  ? pw.Container(
                      margin: const pw.EdgeInsets.all(3.2),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _border, width: 1.6),
                      ),
                    )
                  : null,
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
          _titleRow(
            meta.title,
            bold,
            emblemH: 32,
            centered: t.centerTitle,
          ),
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
          // ── 블록들 — **조각(frag) 단위**로 풀어서 MultiPage 에 넘긴다 ─────
          //
          //  ## 왜 블록을 조각으로 쪼개는가 (요구: "PDF 2페이지가 거의 비어 나온다")
          //  `pw.MultiPage` 는 SpanningWidget(Table)만 페이지 경계에서 나눈다.
          //  종전 코드는 블록 전체를 `Column[header, Table, note]` 로 감쌌는데
          //  Column 은 SpanningWidget 이 아니라 **쪼갤 수 없는 덩어리**였다.
          //  → 큰 블록(참가자 290명 등)은 통째로 다음 페이지로 밀리고, 남은
          //    앞 페이지는 거의 빈 채로 인쇄됐다.
          //
          //  그래서 각 블록을 ① 헤더 조각 ② 행 조각들 ③ 메모 조각 으로 풀어
          //  MultiPage 의 **직접 자식**으로 넣는다. Table 이 직접 자식이면
          //  페이지 경계에서 행 단위로 자연스럽게 이어진다.
          //  (머리행 반복은 `header:` 콜백이 모든 페이지에 그리므로 유지된다.)
          for (var i = 0; i < blocks.length; i++)
            ...blockFrags(blocks[i], i == 0),
          // 합계 요약
          if (summary.isNotEmpty)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 14),
              padding: const pw.EdgeInsets.only(top: 9, left: 2, right: 2),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: _strong, width: 1.3)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  for (final s in summary)
                    pw.Padding(
                      // 요약줄끼리 겹치던 문제(2페이지 실측) — 줄 간 여백 확보.
                      padding: const pw.EdgeInsets.only(top: 2.5),
                      child: pw.Text(
                        sanitize(s),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: ((10 * scale).clamp(9.0, 15.0) * 10)
                                  .roundToDouble() /
                              10,
                          color: _ink,
                          lineSpacing: 2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // ── 인장형 전용: 확인 도장 칸 ────────────────────────────────
          //
          // (요구) "8가지 템플릿 — 구분이 확실히 되는 디자인 포멧"
          //  증명서·확인서에서 실제로 쓰는 요소는 '직인 자리'다. 표만으로는
          //  다른 템플릿과 구분되지 않으므로 이 칸이 인장형의 표식이 된다.
          if (t.stampBox)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 18),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  for (final role in const ['작성', '확인', '승인'])
                    pw.Container(
                      width: 74,
                      margin: const pw.EdgeInsets.only(left: 5),
                      child: pw.Column(
                        children: [
                          pw.Container(
                            width: double.infinity,
                            padding: const pw.EdgeInsets.symmetric(vertical: 3),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: _strong, width: 0.7),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                role,
                                style: pw.TextStyle(
                                  font: bold,
                                  fontSize: 8,
                                  color: _ink,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                          pw.Container(
                            width: double.infinity,
                            height: 44,
                            decoration: pw.BoxDecoration(
                              border: pw.Border(
                                left: pw.BorderSide(color: _strong, width: 0.7),
                                right: pw.BorderSide(color: _strong, width: 0.7),
                                bottom: pw.BorderSide(color: _strong, width: 0.7),
                              ),
                            ),
                          ),
                        ],
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
    double padH = 5,
  }) {
    return pw.Container(
      padding: pw.EdgeInsets.fromLTRB(
        padH,
        padV.toDouble(),
        padH,
        padV.toDouble(),
      ),
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

  /// 상세 행인가 — `['· 상세', 원본내용, '', '']`.
  ///  미리보기(`SettlementPaperView._isDetail`)와 **같은 규칙**.
  ///  상세는 4열 표에 넣지 않고 전폭 블록으로 내보낸다(요구 2026-10-26).
  static bool _isReportDetail(List<String> r) =>
      r.isNotEmpty && r[0].startsWith('· 상세');

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
    List<List<int>>? bands,
    int? maxCellLines,
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
      bands: bands,
      maxCellLines: maxCellLines,
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
    if (_hanjaOn && _hasHanjaIn(rows)) await _ensureHanja();
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
