import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Phase 4 — 은행거래내역 종합분석 MUJI 스타일 A4 세로 보고서.
///
/// 전문가급 재무 보고서: 중앙회 엠블럼 + 절제된 타이포 + 여백 중심 레이아웃 +
/// 색상 강조 + 소형 차트(막대/라인) + 작은 각주(footnote).
class FinanceReportService {
  static const _ink = PdfColor.fromInt(0xFF2B2B2B);
  static const _sub = PdfColor.fromInt(0xFF7A7A7A);
  static const _line = PdfColor.fromInt(0xFFD9D5CC); // MUJI 베이지 그레이
  static const _accent = PdfColor.fromInt(0xFF7A2E2E); // 절제된 적갈색
  static const _income = PdfColor.fromInt(0xFF3F6B4A); // 수입 녹색
  static const _expense = PdfColor.fromInt(0xFF8C5A2B); // 지출 갈색
  static const _gold = PdfColor.fromInt(0xFFB8860B); // 타이거 골드

  static String _p(int v) => v.toString().padLeft(2, '0');

  static String _today() {
    final n = DateTime.now();
    return '${n.year}.${_p(n.month)}.${_p(n.day)}';
  }

  static String _nowStamp() {
    final n = DateTime.now();
    return '${n.year}${_p(n.month)}${_p(n.day)}_${_p(n.hour)}${_p(n.minute)}';
  }

  static String _won(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// 짧은 금액 표기 (1,234만원 / 12.3억 등)
  static String _short(num v) {
    final n = v.abs();
    if (n >= 100000000) return '${(v / 100000000).toStringAsFixed(1)}억';
    if (n >= 10000) return '${(v / 10000).round()}만';
    return _won(v);
  }

  static String fileName() => 'TSAK_재무보고서_${_nowStamp()}';

  // --------------------------------------------------------------------------
  //  A4 세로 보고서 생성
  // --------------------------------------------------------------------------
  static Future<Uint8List> build(Map<String, dynamic> a) async {
    pw.Font? base;
    pw.Font? bold;
    try {
      base = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NanumGothic-Regular-s.ttf'));
      bold = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NanumGothic-Bold-s.ttf'));
    } catch (_) {
      base = null;
      bold = null;
    }
    final theme = (base != null)
        ? pw.ThemeData.withFont(base: base, bold: bold ?? base)
        : null;

    // 엠블럼 이미지
    pw.MemoryImage? emblem;
    try {
      final b = await rootBundle.load('assets/images/tsak_emblem.png');
      emblem = pw.MemoryImage(b.buffer.asUint8List());
    } catch (_) {
      emblem = null;
    }

    final t = (a['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    final years = (a['years'] as Map?)?.cast<String, dynamic>() ?? {};
    final events = (a['events'] as Map?)?.cast<String, dynamic>() ?? {};
    final files = (a['files'] as List?) ?? [];

    final yearKeys = years.keys.toList()
      ..sort((x, y) => y.compareTo(x)); // 최신순

    final doc = pw.Document(
      title: '한국범스카우트중앙회 재무 분석 보고서',
      author: '한국범스카우트중앙회 (TSAK)',
    );

    // ----------------------------------------------------------------------
    //  표지
    // ----------------------------------------------------------------------
    doc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 54, 48, 48),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 40),
            if (emblem != null)
              pw.Center(child: pw.Image(emblem, height: 96, width: 96)),
            pw.SizedBox(height: 22),
            pw.Center(
              child: pw.Column(children: [
                pw.Text('한국범스카우트중앙회',
                    style: pw.TextStyle(fontSize: 13, letterSpacing: 4, color: _sub)),
                pw.SizedBox(height: 4),
                pw.Text('TSAK',
                    style: pw.TextStyle(fontSize: 10, letterSpacing: 6, color: _gold)),
              ]),
            ),
            pw.SizedBox(height: 60),
            pw.Container(width: 40, height: 2, color: _accent),
            pw.SizedBox(height: 16),
            pw.Text('은행거래내역 종합분석 보고서',
                style: pw.TextStyle(
                    fontSize: 26, fontWeight: pw.FontWeight.bold,
                    color: _ink, lineSpacing: 1.3)),
            pw.SizedBox(height: 8),
            pw.Text('2013 – ${t['to'] ?? ''}  ·  후원 · 수품 · 지출 · 행사',
                style: const pw.TextStyle(fontSize: 11, color: _sub)),
            pw.SizedBox(height: 40),
            pw.Divider(color: _line, thickness: 0.8),
            pw.SizedBox(height: 16),
            _coverRow('분석 기간', '${t['from'] ?? ''} – ${t['to'] ?? ''}년 (${t['yearCount'] ?? 0}개 연도)'),
            _coverRow('분석 건수', '${t['rows'] ?? 0}건 · 원본파일 ${files.length}개'),
            _coverRow('총 수입', '${_won((t['income'] ?? 0) as num)}원  (${_short((t['income'] ?? 0) as num)}원)'),
            _coverRow('총 지출', '${_won((t['expense'] ?? 0) as num)}원  (${_short((t['expense'] ?? 0) as num)}원)'),
            _coverRow('순액', '${_won((t['net'] ?? 0) as num)}원'),
            pw.SizedBox(height: 30),
            pw.Divider(color: _line, thickness: 0.8),
            pw.SizedBox(height: 8),
            pw.Text('출력일 ${_today()}',
                style: const pw.TextStyle(fontSize: 9, color: _sub)),
            pw.SizedBox(height: 2),
            pw.Text(
              '※ 본 보고서는 중앙회 기본자료 은행거래내역 폴더의 최신 파일을 기준으로 자동 생성되었습니다.',
              style: const pw.TextStyle(fontSize: 7.5, color: _sub, lineSpacing: 1.4),
            ),
          ],
        ),
      ),
    );

    // ----------------------------------------------------------------------
    //  연도별 추이 (차트 + 표)
    // ----------------------------------------------------------------------
    final trendYears = yearKeys.reversed.toList(); // 오래된→최신
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 44, 42, 42),
        header: (ctx) => _pageHeader('Ⅰ. 연도별 재무 추이', emblem),
        footer: _pageFooter,
        build: (ctx) => [
          pw.SizedBox(height: 6),
          pw.Text('연도별 수입·지출 추이 (2013–${t['to'] ?? ''})',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.SizedBox(height: 10),
          _barChart(trendYears, years, width: 500, height: 150),
          pw.SizedBox(height: 18),
          _yearTable(yearKeys, years),
          pw.SizedBox(height: 16),
          pw.Text(
            '· 수입은 후원·수품구매·참가비·연회비·평생회비·기타를 포함하며, 지출은 행사비·운영비·수품구매·후원금집행을 포함합니다.',
            style: const pw.TextStyle(fontSize: 7.5, color: _sub, lineSpacing: 1.5),
          ),
        ],
      ),
    );

    // ----------------------------------------------------------------------
    //  카테고리 분석 (최근 연도 상세)
    // ----------------------------------------------------------------------
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 44, 42, 42),
        header: (ctx) => _pageHeader('Ⅱ. 항목별 분석 (후원·수품·지출·행사)', emblem),
        footer: _pageFooter,
        build: (ctx) {
          final out = <pw.Widget>[];
          for (final y in yearKeys.take(6)) {
            final b = (years[y] as Map).cast<String, dynamic>();
            out.add(_yearCategoryBlock(y, b));
            out.add(pw.SizedBox(height: 16));
          }
          out.add(pw.Text(
            '· 카테고리 별칭/규칙에 따라 입금자를 자동 분류한 결과입니다. 미분류 항목은 별도 검토가 필요합니다.',
            style: const pw.TextStyle(fontSize: 7.5, color: _sub, lineSpacing: 1.5),
          ));
          return out;
        },
      ),
    );

    // ----------------------------------------------------------------------
    //  행사별 분석
    // ----------------------------------------------------------------------
    final eventList = events.values.toList();
    eventList.sort((x, y) => ((y['income'] as num) + (y['expense'] as num))
        .compareTo((x['income'] as num) + (x['expense'] as num)));
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 44, 42, 42),
        header: (ctx) => _pageHeader('Ⅲ. 행사별 수입·지출', emblem),
        footer: _pageFooter,
        build: (ctx) {
          final out = <pw.Widget>[
            pw.Text('행사별 재무 규모 (수입+지출 상위)',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
            pw.SizedBox(height: 10),
          ];
          final rows = <List<String>>[];
          for (final e in eventList.take(20)) {
            final inc = (e['income'] as num?) ?? 0;
            final exp = (e['expense'] as num?) ?? 0;
            final evName = '${e['event'] ?? '미분류'}';
            rows.add([
              evName.length > 16 ? evName.substring(0, 16) : evName,
              _short(inc),
              _short(exp),
              _short(inc + exp),
              '${(e['count'] ?? 0)}',
            ]);
          }
          out.add(_table(
            ['행사명', '수입', '지출', '합계', '건수'],
            rows,
            aligns: const [pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight],
          ));
          out.add(pw.SizedBox(height: 14));
          out.add(pw.Text(
            '· 행사명이 거래 기재내용에 명시된 경우에만 행사로 귀속됩니다.',
            style: const pw.TextStyle(fontSize: 7.5, color: _sub, lineSpacing: 1.5),
          ));
          return out;
        },
      ),
    );

    // ----------------------------------------------------------------------
    //  최근 거래 상세 (최신 60건)
    // ----------------------------------------------------------------------
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 44, 42, 42),
        header: (ctx) => _pageHeader('Ⅳ. 최근 거래 상세', emblem),
        footer: _pageFooter,
        build: (ctx) {
          final out = <pw.Widget>[];
          int shown = 0;
          for (final y in yearKeys) {
            if (shown >= 60) break;
            final b = (years[y] as Map).cast<String, dynamic>();
            final rows = (b['rows'] as List?) ?? [];
            for (final r in rows) {
              if (shown >= 60) break;
              final rr = (r as Map).cast<String, dynamic>();
              final isExp = rr['type'] == 'expense';
              final nm = '${rr['name'] ?? ''}';
              out.add(_detailRow(rr, isExp, nm));
              shown++;
            }
          }
          out.add(pw.SizedBox(height: 8));
          out.add(pw.Text('· 이상 $shown건 (최신순). 자세한 전체 내역은 첨부 엑셀을 참조하세요.',
              style: const pw.TextStyle(fontSize: 7.5, color: _sub)));
          return out;
        },
      ),
    );

    return doc.save();
  }

  // --------------------------------------------------------------------------
  //  구성 요소
  // --------------------------------------------------------------------------
  static pw.Widget _coverRow(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
                width: 78,
                child: pw.Text(k,
                    style: const pw.TextStyle(fontSize: 10, color: _sub))),
            pw.Expanded(
              child: pw.Text(v,
                  style: pw.TextStyle(
                      fontSize: 11.5, color: _ink, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
      );

  static pw.Widget _pageHeader(String title, pw.MemoryImage? emblem) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (emblem != null) pw.Image(emblem, height: 18, width: 18),
              if (emblem != null) pw.SizedBox(width: 6),
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
              pw.Spacer(),
              pw.Text('한국범스카우트중앙회 · TSAK',
                  style: const pw.TextStyle(fontSize: 7.5, color: _sub, letterSpacing: 1)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Divider(color: _line, thickness: 0.6),
        ],
      );

  static pw.Widget _pageFooter(pw.Context ctx) => pw.Column(
        children: [
          pw.Divider(color: _line, thickness: 0.6),
          pw.SizedBox(height: 3),
          pw.Row(
            children: [
              pw.Text('은행거래내역 종합분석 · 생성 ${_today()}',
                  style: const pw.TextStyle(fontSize: 7, color: _sub)),
              pw.Spacer(),
              pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7, color: _sub)),
            ],
          ),
        ],
      );

  /// 연도별 막대 차트 (수입/지출 그룹)
  static pw.Widget _barChart(
    List<String> yearKeys,
    Map<String, dynamic> years, {
    required double width,
    required double height,
  }) {
    if (yearKeys.isEmpty) return pw.SizedBox();
    num maxV = 1;
    for (final y in yearKeys) {
      final b = (years[y] as Map).cast<String, dynamic>();
      final inc = (b['income'] as num?) ?? 0;
      final exp = (b['expense'] as num?) ?? 0;
      if (inc > maxV) maxV = inc;
      if (exp > maxV) maxV = exp;
    }
    final n = yearKeys.length;
    final gap = 4.0;
    final pairW = (width - gap * (n - 1)) / n;
    final barW = pairW / 2 - 1;

    pw.Widget col(String label, List<num> vals) {
      return pw.Expanded(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                    width: barW,
                    height: (vals[0] / maxV * height),
                    color: _income),
                pw.SizedBox(width: 1),
                pw.Container(
                    width: barW,
                    height: (vals[1] / maxV * height),
                    color: _expense),
              ],
            ),
            pw.SizedBox(height: 3),
            pw.Text(label.length > 4 ? label.substring(2) : label,
                style: const pw.TextStyle(fontSize: 6.5, color: _sub)),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          _legendDot(_income, '수입'),
          pw.SizedBox(width: 10),
          _legendDot(_expense, '지출'),
          pw.Spacer(),
          pw.Text('단위: 원 (최대 ${_short(maxV)}원)',
              style: const pw.TextStyle(fontSize: 6.5, color: _sub)),
        ]),
        pw.SizedBox(height: 6),
        pw.Container(
          height: height + 14,
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: yearKeys
                .map((y) {
                  final b = (years[y] as Map).cast<String, dynamic>();
                  return col(y, [(b['income'] ?? 0) as num, (b['expense'] ?? 0) as num]);
                })
                .toList(),
          ),
        ),
      ],
    );
  }

  static pw.Widget _legendDot(PdfColor c, String label) => pw.Row(children: [
        pw.Container(width: 7, height: 7, color: c),
        pw.SizedBox(width: 3),
        pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: _sub)),
      ]);

  static pw.Widget _yearTable(List<String> yearKeys, Map<String, dynamic> years) {
    final rows = <List<String>>[];
    num ti = 0, te = 0;
    for (final y in yearKeys) {
      final b = (years[y] as Map).cast<String, dynamic>();
      final inc = (b['income'] as num?) ?? 0;
      final exp = (b['expense'] as num?) ?? 0;
      ti += inc;
      te += exp;
      rows.add([y, _won(inc), _won(exp), _won(inc - exp), '${b['count'] ?? 0}']);
    }
    rows.add(['합계', _won(ti), _won(te), _won(ti - te), '']);
    return _table(
      ['연도', '수입(원)', '지출(원)', '순액(원)', '건수'],
      rows,
      aligns: const [pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight],
      boldLast: true,
    );
  }

  static pw.Widget _yearCategoryBlock(String y, Map<String, dynamic> b) {
    final cats = (b['byCategory'] as Map?)?.cast<String, dynamic>() ?? {};
    final entries = cats.entries.toList()
      ..sort((x, yy) => (yy.value as num).compareTo(x.value as num));
    final rows = <List<String>>[];
    for (final e in entries) {
      final isExp = e.key.startsWith('지출:');
      final label = e.key.split(':').last;
      rows.add([isExp ? '지출' : '수입', label, _won(e.value as num)]);
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          pw.Container(width: 3, height: 13, color: _gold),
          pw.SizedBox(width: 6),
          pw.Text('$y년',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.SizedBox(width: 8),
          pw.Text('수입 ${_short((b['income'] ?? 0) as num)} · 지출 ${_short((b['expense'] ?? 0) as num)} · 순액 ${_short((b['net'] ?? 0) as num)}',
              style: const pw.TextStyle(fontSize: 8, color: _sub)),
        ]),
        pw.SizedBox(height: 5),
        _table(['구분', '항목', '금액(원)'], rows,
            aligns: const [pw.Alignment.centerLeft, pw.Alignment.centerLeft, pw.Alignment.centerRight]),
      ],
    );
  }

  static pw.Widget _detailRow(Map<String, dynamic> r, bool isExp, String nm) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
      decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.4))),
      child: pw.Row(
        children: [
          pw.SizedBox(
              width: 52,
              child: pw.Text('${r['date'] ?? ''}',
                  style: const pw.TextStyle(fontSize: 7.5, color: _sub))),
          pw.SizedBox(
              width: 22,
              child: pw.Text(isExp ? '지출' : '수입',
                  style: pw.TextStyle(fontSize: 7.5,
                      color: isExp ? _expense : _income,
                      fontWeight: pw.FontWeight.bold))),
          pw.Expanded(
            child: pw.Text(
              '${nm.isEmpty ? (r['payer'] ?? '') : nm}'
              '${(r['number'] ?? '').toString().isNotEmpty ? ' (#${r['number']})' : ''}'
              '${(r['category'] ?? '').toString().isNotEmpty ? ' · ${r['category']}' : ''}',
              style: const pw.TextStyle(fontSize: 7.5, color: _ink),
              maxLines: 1,
            ),
          ),
          pw.Text(_won((r['amount'] ?? 0) as num),
              style: pw.TextStyle(
                  fontSize: 7.5,
                  color: isExp ? _expense : _income,
                  fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _table(
    List<String> headers,
    List<List<String>> rows, {
    List<pw.Alignment>? aligns,
    bool boldLast = false,
  }) {
    final widths = <int, pw.TableColumnWidth>{};
    for (int i = 0; i < headers.length; i++) {
      widths[i] = const pw.FlexColumnWidth();
    }
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line, width: 0.4),
        bottom: pw.BorderSide(color: _line, width: 0.8),
      ),
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.8))),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                    child: pw.Text(h,
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold, color: _ink)),
                  ))
              .toList(),
        ),
        ...rows.asMap().entries.map((entry) {
          final last = boldLast && entry.key == rows.length - 1;
          return pw.TableRow(
            children: entry.value.asMap().entries.map((c) {
              final align = (aligns != null && c.key < aligns.length)
                  ? aligns[c.key]
                  : pw.Alignment.centerLeft;
              return pw.Container(
                alignment: align,
                padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 3),
                child: pw.Text(c.value,
                    style: pw.TextStyle(
                        fontSize: 7.8,
                        color: _ink,
                        fontWeight: last ? pw.FontWeight.bold : pw.FontWeight.normal)),
              );
            }).toList(),
          );
        }),
      ],
    );
  }
}
