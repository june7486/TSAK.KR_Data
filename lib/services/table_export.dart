/// **모든 게시판·명단 공용 출력 엔진**.
///
/// ## 왜 필요한가 (요구: "모든 게시판, 명단 등등에서도 출력(형식) 이렇게 선택할
/// 수 있도록 해줘. 아주 깔끔해")
/// 화면마다 PDF/CSV 코드가 흩어져 있어 형식·규격이 제각각이었다. 이 서비스는
/// **표 데이터(제목·컬럼·행)** 를 받아 규칙(#14) 순서대로
/// `PDF → JPG → 엑셀(CSV) → PPT → 워드(DOC) → TXT` 파일을 만들어 저장한다.
///
/// 문서 규격은 프로젝트 공통 MUJI 포맷([DocPdf])을 그대로 사용한다.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'doc_pdf.dart';
import 'file_save.dart';
import 'mail_helper.dart';
import 'output_formats.dart';
import 'pdf_to_jpg.dart';
import 'print_doc.dart';
import 'web_nav.dart';

/// 표 형식 문서 데이터(게시판/명단 공용).
class TsakTableDoc {
  const TsakTableDoc({
    required this.title,
    this.subtitle = '',
    this.description = '',
    this.author = '',
    this.extra = const {},
    this.columns = const [],
    this.rows = const [],
    this.summary = const [],
    this.footerLeft = '한국범스카우트중앙회',
    this.landscape = false,
  });

  final String title;
  final String subtitle;
  final String description;
  final String author;
  final Map<String, String> extra;
  final List<String> columns;
  final List<List<String>> rows;
  final List<String> summary;
  final String footerLeft;
  final bool landscape;

  DocMeta get meta => DocMeta(
    title: title,
    subtitle: subtitle,
    description: description,
    author: author,
    extra: extra,
  );

  /// .txt 용 평문(제목/헤더/행/합계).
  String toPlainText() {
    final b = StringBuffer();
    b.writeln(title);
    if (subtitle.trim().isNotEmpty) b.writeln(subtitle);
    b.writeln('총 ${rows.length}건');
    b.writeln('─' * 40);
    if (columns.isNotEmpty) b.writeln(columns.join(' | '));
    for (final r in rows) {
      b.writeln(r.join(' | '));
    }
    if (summary.isNotEmpty) {
      b.writeln('─' * 40);
      for (final s in summary) {
        b.writeln(s);
      }
    }
    return b.toString();
  }

  /// 엑셀 붙여넣기/CSV — 헤더 + 행.
  String toCsv() {
    String q(String s) {
      final v = s.replaceAll('"', '""');
      return '"$v"';
    }

    final b = StringBuffer();
    if (columns.isNotEmpty) {
      b.writeln(columns.map(q).join(','));
    }
    for (final r in rows) {
      b.writeln(r.map(q).join(','));
    }
    return b.toString();
  }

  /// PPT/워드용 서식 텍스트(불릿 목록).
  String toFormattedText(TsakOutputFormat f) {
    final b = StringBuffer();
    b.writeln(f == TsakOutputFormat.ppt ? '$title (슬라이드용)' : '$title (문서용)');
    if (subtitle.trim().isNotEmpty) b.writeln(subtitle);
    b.writeln();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final parts = <String>[];
      for (var c = 0; c < r.length; c++) {
        parts.add(
          c == 0 ? r[c] : '${columns.length > c ? columns[c] : ''}=${r[c]}',
        );
      }
      b.writeln('${i + 1}. ${parts.join(' / ')}');
    }
    if (summary.isNotEmpty) {
      b.writeln();
      b.writeln(summary.join(' · '));
    }
    return b.toString();
  }

  /// 저장용 기본 파일명(확장자 제외).
  String baseName([String prefix = 'TSAK_출력']) {
    final t = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return t.isEmpty ? prefix : '${prefix}_$t';
  }
}

/// 사용자에게 저장 방법(기본 폴더 / 위치 직접 선택)을 물어본 뒤 지정 형식으로 저장.
///
/// 반환: 저장을 시작했으면 true, 취소했으면 false.
Future<bool> saveTsakTable(
  BuildContext context,
  TsakTableDoc doc,
  TsakOutputFormat format, {
  bool askLocation = true,
  VoidCallback? onStep,
}) async {
  bool? choose;
  if (askLocation) {
    choose = await askSaveLocation(context);
    if (choose == null) return false; // 취소
  } else {
    choose = false;
  }
  onStep?.call();
  final base = doc.baseName();
  switch (format) {
    case TsakOutputFormat.pdf:
      final bytes = await DocPdf.buildSimple(
        meta: doc.meta,
        columns: doc.columns,
        rows: doc.rows,
        summary: doc.summary,
        footerLeft: doc.footerLeft,
        landscape: doc.landscape,
      );
      await _save(bytes, base, 'pdf', 'application/pdf', choose);
      return true;
    case TsakOutputFormat.jpg:
      final pdf = await DocPdf.buildSimple(
        meta: doc.meta,
        columns: doc.columns,
        rows: doc.rows,
        summary: doc.summary,
        footerLeft: doc.footerLeft,
        landscape: doc.landscape,
      );
      final jpg = await pdfToJpg(pdf);
      await _save(jpg, base, 'jpg', 'image/jpeg', choose);
      return true;
    case TsakOutputFormat.excel:
      await saveText(
        content: doc.toCsv(),
        name: base,
        ext: 'csv',
        mime: 'text/csv',
      );
      return true;
    case TsakOutputFormat.ppt:
      await _save(
        _bytes(doc.toFormattedText(format)),
        base,
        'ppt',
        'application/vnd.ms-powerpoint',
        choose,
      );
      return true;
    case TsakOutputFormat.word:
      await _save(
        _bytes(doc.toFormattedText(format)),
        base,
        'doc',
        'application/msword',
        choose,
      );
      return true;
    case TsakOutputFormat.txt:
      await saveText(
        content: doc.toPlainText(),
        name: base,
        ext: 'txt',
        mime: 'text/plain',
      );
      return true;
  }
}

/// 문서를 메일 본문으로 열기(공용).
Future<void> emailTsakTable(BuildContext context, TsakTableDoc doc) async {
  final body = doc.toPlainText();
  final ok = await openMailOrCopy(
    subject: doc.title,
    body: body,
    fallbackText: body,
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '메일 앱을 열었습니다' : '메일 앱을 열 수 없어 내용을 복사했습니다')),
    );
  }
}

/// 문서를 MUJI HTML로 만들어 브라우저 인쇄창을 연다(공용 '프린트').
Future<void> printTsakTable(TsakTableDoc doc) async {
  final html = buildMujiDoc(
    meta: doc.meta,
    columns: doc.columns,
    rows: doc.rows
        .map(
          (r) => r
              .asMap()
              .entries
              .map(
                (c) => DocCell(
                  c.value,
                  accent: c.key == 0
                      ? kMujiAccents[c.key % kMujiAccents.length]
                      : null,
                ),
              )
              .toList(),
        )
        .toList(),
    summary: doc.summary.join(' · '),
    footerLeft: doc.footerLeft,
    landscape: doc.landscape,
  );
  await openPrintWindow(html, doc.title);
}

// ── 내부 헬퍼 ──
Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

Future<void> _save(
  Uint8List bytes,
  String name,
  String ext,
  String mime,
  bool choose,
) async {
  await saveBytesChoose(
    bytes: bytes,
    name: name,
    ext: ext,
    mime: mime,
    choose: choose,
  );
}

/// 프린트 창 열기 — 웹은 새 창 인쇄, 네이티브는 아무 동작 안 함(호출부 안내).
Future<void> openPrintWindow(String html, String title) async {
  openPrintableHtml(html, autoPrint: true);
}
