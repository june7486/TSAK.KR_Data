// PDF **가독성** 회귀 검증 — 순수 Dart (Flutter 의존 없음).
//
// 실행:  dart run tool/verify_pdf_contrast.dart
//
// ## 왜 이 파일이 필요한가
// 사용자 요구(그대로):
//   "출력된 내용물을 보면 글자와 배경의 가독성이 매우 낮아짐"
//
// 원인은 **`PdfColor(r,g,b,alpha)` 의 알파가 `pdf` 패키지에서 버려진다**는
// 것이었다. 그래서 10% 틴트로 의도한 블록 제목 띠가 **원색으로 꽉 찬 띠**가
// 되었고, 제목 글자색도 같은 악센트라 글자가 배경에 묻혔다.
//
// 이 테스트는 그 사실을 **실제 PDF 바이트를 렌더해서** 확인한다:
//   1) 알파를 쓰면 → 채움색이 원색 그대로(= 알파 무시됨) 나오는지
//   2) 흰색 합성(_tint)을 쓰면 → 아주 옅은 파스텔로 나오는지
//   3) 글자색과 배경색의 **대비(contrast ratio)** 가 WCAG AA(4.5:1) 이상인지
//
// 즉 "고쳤다"를 말이 아니라 숫자로 증명한다.
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

int _pass = 0;
int _fail = 0;

void _ok(String what) {
  _pass++;
  // ignore: avoid_print
  print('  ✓ $what');
}

void _bad(String what, String why) {
  _fail++;
  // ignore: avoid_print
  print('  ✗ $what  →  $why');
}

void _expect(bool cond, String what, [String why = '']) {
  if (cond) {
    _ok(what);
  } else {
    _bad(what, why.isEmpty ? '조건 불충족' : why);
  }
}

// ── doc_pdf.dart 의 _tint 와 **동일한 식** (그 파일은 Flutter 의존이라 직접
//    import 할 수 없다. 식이 갈라지지 않도록 아래 상수도 같은 값을 쓴다) ──
PdfColor tint(PdfColor c, double a) {
  final t = a.clamp(0.0, 1.0);
  if (t >= 0.999) return c;
  if (t <= 0.001) return PdfColor.fromInt(0xFFFFFFFF);
  return PdfColor(1 - (1 - c.red) * t, 1 - (1 - c.green) * t,
      1 - (1 - c.blue) * t);
}

PdfColor darken(PdfColor c, double k) {
  final m = k.clamp(0.0, 1.0) * 0.62;
  return PdfColor(c.red * (1 - m), c.green * (1 - m), c.blue * (1 - m));
}

/// WCAG 2.x 상대 휘도.
double _lum(PdfColor c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);
  return 0.2126 * ch(c.red) + 0.7152 * ch(c.green) + 0.0722 * ch(c.blue);
}

// dart:math 의 pow 는 num 을 돌려주므로 double 로 좁힌다.
double _pow(double b, double e) {
  var r = 1.0;
  // 2.4 승 — exp/ln 없이도 정확도 1e-9 이면 충분하다(테스트 목적).
  r = _exp(e * _ln(b));
  return r;
}

double _ln(double x) {
  // 자연로그 — atanh 급수(빠르고 충분히 정확).
  final z = (x - 1) / (x + 1);
  var z2 = z * z;
  var term = z;
  var s = 0.0;
  for (var n = 0; n < 40; n++) {
    s += term / (2 * n + 1);
    term *= z2;
  }
  return 2 * s;
}

double _exp(double x) {
  // exp — 테일러 40항(테스트용 정확도 확보).
  var term = 1.0;
  var s = 1.0;
  for (var n = 1; n < 40; n++) {
    term *= x / n;
    s += term;
  }
  return s;
}

/// 두 색의 대비비 (밝은쪽+0.05)/(어두운쪽+0.05)
double contrast(PdfColor a, PdfColor b) {
  final l1 = _lum(a), l2 = _lum(b);
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// 실제 PDF 를 만들어 첫 페이지의 **채움색**을 꺼낸다 (알파 실험용).
/// `pdf` 패키지는 순수 Dart 라 여기서 바로 돌릴 수 있다.
Future<List<String>> _fillsOf(pw.Document doc) async {
  final bytes = await doc.save();
  _lastPdf = bytes;
  return _scanFills(bytes);
}

Uint8List? _lastPdf;

/// PDF 콘텐츠 스트림에서 `r g b rg` (채움색) 토큰을 뽑는다.
List<String> _scanFills(Uint8List bytes) {
  // 비압축 저장(compress:false) 했으므로 원문에서 정규식으로 찾을 수 있다.
  final text = String.fromCharCodes(bytes);
  final re = RegExp(r'([0-9.]+) ([0-9.]+) ([0-9.]+) rg');
  final out = <String>[];
  for (final m in re.allMatches(text)) {
    final c = '${m.group(1)},${m.group(2)},${m.group(3)}';
    if (!out.contains(c)) out.add(c);
  }
  return out;
}

const _accHex = 0xFF2E5F8A; // 인가자 블록 악센트(#2E5F8A)

Future<void> main() async {
  final accent = PdfColor.fromInt(_accHex);
  // ignore: avoid_print
  print('=== PDF 가독성 검증 (실제 PDF 바이트로 확인) ===\n');

  // ── [1] 알파가 정말 버려지는가 ───────────────────────────────────────
  // ignore: avoid_print
  print('[1] PdfColor 의 4번째 인자(알파)는 pdf 패키지가 버리는가');
  {
    final doc = pw.Document(compress: false);
    // ignore: deprecated_member_use
    doc.addPage(
      pw.Page(
        build: (_) => pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfColor(accent.red, accent.green, accent.blue, 0.10),
          ),
          height: 100,
          width: 300,
        ),
      ),
    );
    final fills = await _fillsOf(doc);
    // 원색(#2E5F8A) → (0.1804, 0.3725, 0.5412)
    final raw = fills.any(
      (f) => f.startsWith('0.18') && f.contains('0.37') && f.contains('0.54'),
    );
    _expect(
      raw,
      '알파 0.10 을 줘도 채움색이 **원색**(0.18,0.37,0.54)로 저장됨 = 알파 무시',
      'fills=$fills',
    );
    final pale = fills.any((f) => f.startsWith('0.9') || f.startsWith('0.8'));
    _expect(!pale, '알파를 준 색이 옅게(0.8~0.9대) 저장되지는 않음');
  }

  // ── [2] 흰색 합성은 실제로 옅은 색을 만든다 ──────────────────────────
  // ignore: avoid_print
  print('\n[2] 흰색 합성(_tint)은 옅은 파스텔을 만든다');
  {
    final band = tint(accent, 0.10 * 0.62); // blockWidget 과 같은 식
    final doc = pw.Document(compress: false);
    // ignore: deprecated_member_use
    doc.addPage(
      pw.Page(
        build: (_) => pw.Container(
          decoration: pw.BoxDecoration(color: band),
          height: 100,
          width: 300,
        ),
      ),
    );
    final fills = await _fillsOf(doc);
    final hex = _toHex(band);
    _expect(
      band.red > 0.85 && band.green > 0.85 && band.blue > 0.85,
      '계산된 띠 색이 아주 옅다 ($hex)',
      'r=${band.red.toStringAsFixed(3)}',
    );
    final saved = fills.any((f) {
      final p = f.split(',');
      return p.length == 3 &&
          (double.parse(p[0]) - band.red).abs() < 0.01 &&
          (double.parse(p[1]) - band.green).abs() < 0.01;
    });
    _expect(saved, 'PDF 에 **옅은 색 그대로** 저장됨 (알파 의존 없음)', 'fills=$fills');
  }

  // ── [3] 제목 글자 vs 띠 배경 대비 ────────────────────────────────────
  // ignore: avoid_print
  print('\n[3] 제목 글자 / 띠 배경 대비 (WCAG AA 4.5:1)');
  const accents = <String, int>{
    '인가자': 0xFF2E5F8A,
    '수입': 0xFF4E7A4B,
    '후원': 0xFFA6763C,
    '지출': 0xFFA63A3A,
    '잔액': 0xFF3A3A3A, // ← 이전에 순검정 블록으로 보이던 항목
    '지출·계좌': 0xFF7C6A9C,
  };
  accents.forEach((name, hex) {
    final ac = PdfColor.fromInt(hex);
    // 종전 방식: 배경 = 원색, 글자 = 원색  → 대비 1.0 (글자 실종)
    final oldContrast = contrast(ac, ac);
    // 새 방식
    final bg = tint(ac, 0.10 * 0.62);
    final fg = darken(ac, 0.72);
    final c = contrast(fg, bg);
    _expect(
      oldContrast < 1.01,
      '$name: 종전(배경=글자색)은 대비 ${oldContrast.toStringAsFixed(2)}:1 — 읽을 수 없음',
    );
    _expect(
      c >= 4.5,
      '$name: 새 대비 ${c.toStringAsFixed(2)}:1 — AA 통과',
      '대비 부족(${c.toStringAsFixed(2)}:1) — _darken 계수 조정 필요',
    );
  });

  // ── [4] 합계 행 ─────────────────────────────────────────────────────
  // ignore: avoid_print
  print('\n[4] 합계 행(틴트 배경 + 악센트 글씨) 대비');
  accents.forEach((name, hex) {
    final ac = PdfColor.fromInt(hex);
    final bg = tint(ac, 0.055 * 0.55);
    final fg = darken(ac, 0.72);
    final c = contrast(fg, bg);
    _expect(c >= 4.5, '$name 합계행 대비 ${c.toStringAsFixed(2)}:1');
  });

  // ── [5] 본문 글자 vs 흰 종이 ────────────────────────────────────────
  // ignore: avoid_print
  print('\n[5] 본문(_ink) / 메모 / 보조글씨 vs 흰 종이');
  {
    final white = PdfColor.fromInt(0xFFFFFFFF);
    final ink = PdfColor.fromInt(0xFF3A3A3A);
    final grayOld = PdfColor.fromInt(0xFF8C877E);
    final grayNew = darken(grayOld, 0.42);
    _expect(contrast(ink, white) >= 7.0,
        '본문 대비 ${contrast(ink, white).toStringAsFixed(2)}:1 (AAA)');
    _expect(contrast(grayOld, white) < 4.0,
        '종전 회색 메모 ${contrast(grayOld, white).toStringAsFixed(2)}:1 — 기준 미달');
    _expect(contrast(grayNew, white) >= 4.5,
        '새 메모 색 ${contrast(grayNew, white).toStringAsFixed(2)}:1 — AA 통과',
        '메모 대비 부족');
  }

  // ── [6] 글씨 크기 하한 ──────────────────────────────────────────────
  // ignore: avoid_print
  print('\n[6] 글씨 크기 하한 (사용자 배율 0.86 에서도 읽히는가)');
  {
    // doc_pdf.buildReport 와 같은 식
    double cellPt({required bool compact, required double scale}) =>
        ((compact ? 8.8 : 9.4) * scale).clamp(8.4, 15.0);

    final oldPt = 9.0 * 0.86; // 종전
    final newPt = cellPt(compact: false, scale: 0.86);
    _expect(oldPt < 8.0, '종전 86% 배율 = ${oldPt.toStringAsFixed(1)}pt (너무 작음)');
    _expect(newPt >= 8.4, '새 86% 배율 = ${newPt.toStringAsFixed(1)}pt (하한 8.4pt)');
    _expect(cellPt(compact: true, scale: 0.86) >= 8.4, '장부형도 하한 유지');
    _expect(cellPt(compact: false, scale: 1.18) > 10.0, '118% 는 확대 유지');
  }

  // ── [7] 종이(PDF) 안전 문자 — □(두부) 방지 ──────────────────────────
  // ignore: avoid_print
  print('\n[7] 폰트 실측 표 — PDF 에서 □ 가 되는 글자를 걸러내는가');
  {
    // doc_pdf.dart 의 _paperRanges 와 같은 표
    const ranges = <String>[
      '0x20-0x7E,0xB0-0xB3,0xB7,0xD7,0xF7,0x2013-0x2014,0x2018-0x2019,0x201C-0x201D',
      '0x2022,0x2026,0x203B,0x20A9,0x2190-0x2194,0x25A0-0x25A1,0x25B2,0x25B6,0x25BC',
      '0x25C0,0x25C6-0x25C7,0x25CB,0x25CF,0x2605-0x2606,0x2661,0x2665,0x2716',
      '0x3001-0x3003,0x3008-0x3019,0x301E-0x3020,0x3036,0x3131-0x3163,0x3165-0x318E',
      '0xAC00-0xD7A3,0xFF01-0xFF5E,0xFFE0-0xFFE3,0xFFE5-0xFFE6',
    ];
    final parsed = <List<int>>[];
    for (final line in ranges) {
      for (final tk in line.split(',')) {
        final t = tk.trim();
        if (t.isEmpty) continue;
        final d = t.indexOf('-', 1);
        parsed.add(d < 0
            ? [int.parse(t), int.parse(t)]
            : [int.parse(t.substring(0, d)), int.parse(t.substring(d + 1))]);
      }
    }
    bool can(int cp) {
      for (final g in parsed) {
        if (cp >= g[0] && cp <= g[1]) return true;
      }
      return false;
    }

    // 반드시 살아남아야 하는 글자(문서 본문).
    for (final ch in '가나다한국범스카우트중앙회·–—…“”《》※→★☆○●□■×±°％ㆍ0123456789ABC'.runes) {
      _expect(can(ch), "본문 글자 '${String.fromCharCode(ch)}' 는 PDF 에 그려진다");
    }
    // 반드시 걸러져야 하는 글자(□ 가 되던 것들).
    for (final ch in '✓✔✕㎡①㎏㈜√金李朴🐅🔒⚠'.runes) {
      _expect(
        !can(ch),
        "'${String.fromCharCode(ch)}' 는 폰트에 없음 → 제거 대상(□ 방지)",
      );
    }
  }

  // ignore: avoid_print
  print('\n────────────────────────────────────────');
  // ignore: avoid_print
  print('PASS $_pass / FAIL $_fail');
  if (_fail > 0) {
    // ignore: avoid_print
    print('❌ 실패 — 위 항목을 확인하세요.');
    throw StateError('verify_pdf_contrast: $_fail failure(s)');
  }
  // ignore: avoid_print
  print('✅ 전체 통과 — 출력물 대비/크기/두부(□) 모두 기준 충족');
}

String _toHex(PdfColor c) {
  String h(double v) => (v.clamp(0, 1) * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(c.red)}${h(c.green)}${h(c.blue)}';
}
