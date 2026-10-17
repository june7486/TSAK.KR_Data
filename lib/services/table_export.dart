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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'doc_pdf.dart';
import 'file_save.dart';
import 'mail_helper.dart';
import 'output_formats.dart';
import 'pdf_to_jpg.dart';
import 'print_doc.dart';
import 'table_options.dart';
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
    this.options,
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

  /// 출력 옵션(출력내용선택·위치이동·글씨크기·줄간격·용지) — null 이면 기본.
  ///
  /// ## 규칙 (요구: "수품판매관리의 메뉴도 관리자명단출력처럼 출력내용선택,
  /// 위치이동, 줄간격유지 항목등을 넣어줘")
  final TableOutputOptions? options;

  /// 옵션(선택·순서)을 적용한 **실제 출력 열**.
  List<String> get viewColumns {
    final o = options;
    if (o == null || o.cols == null) return columns;
    return applyTableOptions(
      columns: columns,
      rows: rows,
      order: o.cols,
      selected: o.cols!.toSet(),
    ).columns;
  }

  /// 옵션(선택·순서)을 적용한 **실제 출력 행**.
  List<List<String>> get viewRows {
    final o = options;
    if (o == null || o.cols == null) return rows;
    return applyTableOptions(
      columns: columns,
      rows: rows,
      order: o.cols,
      selected: o.cols!.toSet(),
    ).rows;
  }

  /// 두줄 방지할 **출력 열 인덱스** — [TableOutputOptions.noWrap](헤더 이름)을
  /// 실제 출력 열 순서에 맞춰 인덱스로 변환한다.
  ///
  /// (요구: "행사참가 출력파일 … 두줄방지 항목을 선택") 지정 열은 PDF/미리보기에서
  /// 줄바꿈하지 않는다(넘치면 자동 축소). 헤더 이름 기준이라 열 순서와 무관하게 동작.
  Set<int> get effectiveNoWrapCols {
    final names = options?.noWrap ?? const <String>{};
    if (names.isEmpty) return const {};
    final cols = viewColumns;
    return {
      for (var i = 0; i < cols.length; i++)
        if (names.contains(cols[i])) i,
    };
  }

  /// 옵션이 정한 용지 방향(없으면 문서 기본값).
  bool get effectiveLandscape => options?.landscape ?? landscape;

  DocMeta get meta => DocMeta(
    title: title,
    subtitle: subtitle,
    description: description,
    author: author,
    extra: extra,
  );

  /// .txt 용 평문(제목/헤더/행/합계) — 옵션(선택·순서) 반영.
  String toPlainText() {
    final cols = viewColumns;
    final rs = viewRows;
    final b = StringBuffer();
    b.writeln(title);
    if (subtitle.trim().isNotEmpty) b.writeln(subtitle);
    b.writeln('총 ${rs.length}건');
    b.writeln('─' * 40);
    if (cols.isNotEmpty) b.writeln(cols.join(' | '));
    for (final r in rs) {
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

  /// 엑셀 붙여넣기/CSV — 헤더 + 행. 옵션(선택·순서) 반영.
  String toCsv() {
    final cols = viewColumns;
    final rs = viewRows;
    String q(String s) {
      final v = s.replaceAll('"', '""');
      return '"$v"';
    }

    final b = StringBuffer();
    if (cols.isNotEmpty) {
      b.writeln(cols.map(q).join(','));
    }
    for (final r in rs) {
      b.writeln(r.map(q).join(','));
    }
    return b.toString();
  }

  /// PPT/워드용 서식 텍스트(불릿 목록). 옵션(선택·순서) 반영.
  String toFormattedText(TsakOutputFormat f) {
    final cols = viewColumns;
    final rs = viewRows;
    final b = StringBuffer();
    b.writeln(f == TsakOutputFormat.ppt ? '$title (슬라이드용)' : '$title (문서용)');
    if (subtitle.trim().isNotEmpty) b.writeln(subtitle);
    b.writeln();
    for (var i = 0; i < rs.length; i++) {
      final r = rs[i];
      final parts = <String>[];
      for (var c = 0; c < r.length; c++) {
        parts.add(c == 0 ? r[c] : '${cols.length > c ? cols[c] : ''}=${r[c]}');
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

/// 저장 위치를 묻는다(호출부 공용).
///
/// 반환: false=기본 폴더 / true=위치 직접 선택 / null=취소.
/// 진행 대기창을 열기 **이전**에 호출해서, 위치를 먼저 확정하도록 한다
/// (요구: "저장위치 선택창이 안나오니 이것도 조정해줘요").
Future<bool?> askTsakSaveLocation(BuildContext context, {String? info}) =>
    askSaveLocation(context, info: info);

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
  if (askLocation) {
    final choose = await askSaveLocation(context);
    if (choose == null) return false; // 취소
    if (!context.mounted) return false;
    return saveTsakTableChosen(
      context,
      doc,
      format,
      choose: choose,
      onStep: onStep,
    );
  }
  return saveTsakTableChosen(
    context,
    doc,
    format,
    choose: false,
    onStep: onStep,
  );
}

/// 지정 형식의 **파일 바이트**를 만들어 돌려준다(저장/공유 공용 빌더).
///
/// 저장([saveTsakTableChosen])과 공유([shareTsakTableChosen])가 **동일한 바이트**를
/// 쓰도록 한 곳에서 만든다(규칙: 형식별 산출물은 항상 이 빌더로 통일).
///
/// 확장자·MIME 은 규칙(#14)의 형식 정의를 따른다(엑셀=CSV·워드=DOC).
Future<({Uint8List bytes, String ext, String mime})> buildTsakTableFile(
  TsakTableDoc doc,
  TsakOutputFormat format,
) async {
  switch (format) {
    case TsakOutputFormat.pdf:
      return (
        bytes: await DocPdf.buildSimple(
          meta: doc.meta,
          columns: doc.viewColumns,
          rows: doc.viewRows,
          summary: doc.summary,
          footerLeft: doc.footerLeft,
          landscape: doc.effectiveLandscape,
          scale: doc.options?.scale ?? 1.0,
          rowSpaceMul: doc.options?.rowSpaceMul ?? 1.0,
          noWrapCols: doc.effectiveNoWrapCols,
        ),
        ext: 'pdf',
        mime: 'application/pdf',
      );
    case TsakOutputFormat.jpg:
      final pdf = await DocPdf.buildSimple(
        meta: doc.meta,
        columns: doc.viewColumns,
        rows: doc.viewRows,
        summary: doc.summary,
        footerLeft: doc.footerLeft,
        landscape: doc.effectiveLandscape,
        scale: doc.options?.scale ?? 1.0,
        rowSpaceMul: doc.options?.rowSpaceMul ?? 1.0,
        noWrapCols: doc.effectiveNoWrapCols,
      );
      return (bytes: await pdfToJpg(pdf), ext: 'jpg', mime: 'image/jpeg');
    case TsakOutputFormat.excel:
      // 규칙: excel 은 UTF-8 BOM 을 붙여 엑셀에서 한글이 깨지지 않게 한다.
      return (bytes: _csvBytes(doc.toCsv()), ext: 'csv', mime: 'text/csv');
    case TsakOutputFormat.ppt:
      return (
        bytes: _bytes(doc.toFormattedText(format)),
        ext: 'ppt',
        mime: 'application/vnd.ms-powerpoint',
      );
    case TsakOutputFormat.word:
      return (
        bytes: _bytes(doc.toFormattedText(format)),
        ext: 'doc',
        mime: 'application/msword',
      );
    case TsakOutputFormat.txt:
      return (bytes: _bytes(doc.toPlainText()), ext: 'txt', mime: 'text/plain');
  }
}

/// 저장 위치([choose])를 **이미 정한 상태**에서 문서를 만들어 저장한다.
///
/// 진행 대기창(task 콜백) **내부**에서 호출하기 좋다. 위치 선택창은 밖에서
/// 미리 물어본다([askTsakSaveLocation]).
/// - [choose]=false → 기기 기본(다운로드) 폴더로 저장.
/// - [choose]=true  → 사용자가 고른 위치/앱으로 저장.
Future<bool> saveTsakTableChosen(
  BuildContext context,
  TsakTableDoc doc,
  TsakOutputFormat format, {
  required bool choose,
  VoidCallback? onStep,
}) async {
  onStep?.call();
  final base = doc.baseName();
  final f = await buildTsakTableFile(doc, format);
  await _save(f.bytes, base, f.ext, f.mime, choose);
  return true;
}

/// 문서를 지정 형식으로 만들어 **OS 공유 시트**로 공유한다(모든 기기 공통).
///
/// 진행 대기창(task 콜백) **내부**에서 호출하기 좋다. 저장과 달리 위치를 묻지
/// 않고 곧바로 공유 시트를 연다(카톡·메일·드라이브 등으로 바로 전송).
///
/// 반환: [TsakShareResult] — 호출부는 [tsakShareMessage] 로 안내 문구를 만든다.
Future<TsakShareResult> shareTsakTableChosen(
  BuildContext context,
  TsakTableDoc doc,
  TsakOutputFormat format, {
  VoidCallback? onStep,
}) async {
  onStep?.call();
  final base = doc.baseName();
  final f = await buildTsakTableFile(doc, format);
  return shareBytes(
    bytes: f.bytes,
    name: base,
    ext: f.ext,
    mime: f.mime,
    subject: doc.title,
    text: '${doc.title} · ${doc.rows.length}건',
  );
}

/// 문서를 지정 형식으로 만들어 **외부 프로그램/뷰어로 연다** — 모든 포맷 공통.
///
/// ## 규칙 (요구: "모든 포맷도 외부 공유 프로그램으로 내보낼 수 있게")
/// 지금까지 'PDF 미리보기 / 인쇄'는 **PDF 전용**이었다. 이 함수는 동일한
/// '외부로 열기' 흐름을 **JPG·엑셀·PPT·워드·TXT 등 모든 포맷**에 제공한다.
///
/// - **웹**: Blob URL 을 새 탭으로 열어 브라우저/기본 앱이 처리하게 한다.
///   PDF→PDF 뷰어·인쇄, JPG→이미지 뷰어, CSV/DOC/PPT/TXT→다운로드 후 기본 앱.
/// - **네이티브(안드로이드 등)**: 새 탭 개념이 없으므로 **OS 공유/열기 시트**로
///   폴백한다([shareTsakTableChosen]) — 사용자가 열 앱·보낼 앱을 직접 고른다.
///
/// 반환: [TsakShareResult] — 호출부는 [tsakShareMessage] 로 안내 문구를 만든다.
///   웹에서 새 창을 열면 [TsakShareResult.shared] 로 간주한다.
Future<TsakShareResult> openTsakTableChosen(
  BuildContext context,
  TsakTableDoc doc,
  TsakOutputFormat format, {
  VoidCallback? onStep,
}) async {
  onStep?.call();
  final base = doc.baseName();
  final f = await buildTsakTableFile(doc, format);
  // 웹: 외부 뷰어/앱으로 새 창에서 연다(모든 포맷 공통).
  final opened = openFileExternally(f.bytes, '$base.${f.ext}', f.mime);
  if (opened) return TsakShareResult.shared;
  // 네이티브(또는 팝업 차단): OS 공유/열기 시트로 폴백.
  return shareBytes(
    bytes: f.bytes,
    name: base,
    ext: f.ext,
    mime: f.mime,
    subject: doc.title,
    text: '${doc.title} · ${doc.rows.length}건',
  );
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
  final emblem = await _emblemDataUri();
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
    emblemDataUri: emblem,
    noWrapCols: doc.effectiveNoWrapCols,
  );
  await openPrintWindow(html, doc.title);
}

// ── 내부 헬퍼 ──
Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// 출력물(HTML 인쇄/PDF)에 넣을 **중앙회 엠블럼(data URI)** 을 한 번만 읽어 캐시.
///
/// 인쇄 창은 Blob URL 로 열리므로 상대경로 이미지(`assets/...`)가 로드되지
/// 않는다(요구: "명부 출력시 아이콘이 표시되지 않음"). 따라서 자산을 base64
/// data URI 로 직접 인라인해야 어떤 브라우저/창에서도 아이콘이 보인다.
String? _emblemDataUriCache;
Future<String?> _emblemDataUri() async {
  if (_emblemDataUriCache != null) return _emblemDataUriCache;
  for (final key in const [
    'assets/images/tsak_emblem.png',
    'assets/assets/images/tsak_emblem.png',
  ]) {
    try {
      final b = await rootBundle.load(key);
      _emblemDataUriCache =
          'data:image/png;base64,${base64Encode(b.buffer.asUint8List())}';
      return _emblemDataUriCache;
    } catch (e) {
      if (kDebugMode) debugPrint('emblem load fail ($key): $e');
    }
  }
  _emblemDataUriCache = '';
  return null;
}


/// CSV 는 맨 앞에 UTF-8 BOM 을 붙여 엑셀에서 한글이 깨지지 않게 저장한다.
Uint8List _csvBytes(String s) =>
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(s)]);

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
