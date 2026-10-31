/// 앱 전역 **기본 출력 형식(규칙)** — 무인양품(MUJI) + 다양한 색채.
///
/// ## 프로젝트 규칙
/// 출력이 필요한 **모든 항목**(주문서·재고표·판매대장·제작자 목록·회계 자료 등)은
/// 텍스트로 보내지 말고, 반드시 이 헬퍼로 만든 **MUJI 스타일 A4 세로 문서**로
/// 출력한다. 상단에 타이틀·세부설명·파일 생성일·생성자 등 기초정보를 작은 글씨로
/// 배치하고, 표는 얇은 구분선 + 저채도 다색 악센트(좌측 컬러 바)로 디자인한다.
///
/// 새 출력 기능을 추가할 때도 동일한 헬퍼를 사용한다(신규/수정 공통 규칙).
library;

/// 출력 HTML 공통 **크로스플랫폼 한글 폰트 스택** (규칙).
///
/// ## 왜 필요한가 (요구 p.4·p.5: "출력시 폰트가 깨져")
/// 그동안 일부 출력이 `'Malgun Gothic'`(윈도우 전용 폰트)만 지정해,
/// **아이폰(iOS)·안드로이드·맥**에서 한글이 두부(□□□)로 깨졌다.
/// 폰트는 **각 OS 에 존재하는 시스템 폰트를 우선순위대로** 나열하고,
/// 마지막에 generic `sans-serif` 로 폴백하면 못 찾아도 기본폰트로 정상 표시된다.
/// (웹폰트 로딩 없이도 안전 — 미리보기·인쇄·PDF 저장 모두 동일.)
const String kDocFontStack =
    "'Malgun Gothic','Apple SD Gothic Neo','NanumGothic','Noto Sans KR',"
    "system-ui,-apple-system,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif";

/// 무인양품 스타일 저채도 다색 악센트 팔레트(규칙).
const List<String> kMujiAccents = [
  '#7C6A9C', // 보라
  '#3D6E70', // 청록
  '#A6763C', // 황토
  '#4C6A92', // 청람
  '#8A5A75', // 자주
  '#5E7A4B', // 연두
];

String _esc(String? s) => sanitizeDocText(
  s,
).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// PDF(나눔고딕 벡터) 에서 그릴 수 없는 글자(이모지·일부 한자)를 **안전 텍스트로
/// 치환**한다. (요구: "이모지가 안 보임")
///
/// HTML 인쇄·미리보기(브라우저)는 이모지를 렌더하지만, 실제 **PDF 파일**은 폰트
/// 글리프가 없어 ▯(두부)로 깨진다. 두 경로의 결과가 어긋나지 않도록 문서 텍스트를
/// 공통으로 정돈한다. 미리보기(HTML)도 PDF와 동일 문자열을 받으므로 화면=출력 일치.
/// 자주 쓰는 이모지 → 대응 텍스트(문서 의미 보존).
const Map<String, String> _kEmojiText = {
  '📅': '일시 :',
  '🗓': '일시 :',
  '📆': '일시 :',
  '⏰': '시간 :',
  '📍': '장소 :',
  '🗺': '장소 :',
  '🏠': '장소 :',
  '☎': '전화 :',
  '📞': '전화 :',
  '📱': '연락 :',
  '✉': '메일 :',
  '📧': '메일 :',
  '📨': '메일 :',
  // ── 기호류 ───────────────────────────────────────────────────────────
  //  종전에는 아래 글자들이 그대로 남아 **PDF 폰트에 글리프가 없어 □(두부)**
  //  로 찍혔다. (요구: "아이콘이 박스로 표현되는 것도 다시 체크")
  //  지우면 의미가 사라지므로, 뜻이 통하는 문자로 바꿔 둔다.
  '✓': '○',
  '✔': '○',
  '☑': '○',
  '✕': '×',
  '✗': '×',
  '✘': '×',
  '⚠': '주의',
  '❗': '!',
  '❕': '!',
  '🔒': '잠금',
  '🔓': '열림',
  '⭐': '★',
  '🌟': '★',
  '✅': '○',
  '❌': '×',
  '➡': '→',
  '⬅': '←',
  '⬆': '↑',
  '⬇': '↓',
};

/// 문서 텍스트 안전화 — 이모지/미지원 글리프를 정리한다(print_doc·doc_pdf 공용 규칙).
String sanitizeDocText(String? s) {
  if (s == null || s.isEmpty) return s ?? '';
  var t = s;
  _kEmojiText.forEach((k, v) => t = t.replaceAll(k, v));
  final b = StringBuffer();
  for (final r in t.runes) {
    if (r == 0x0A || r == 0x0D || r == 0x09) {
      b.writeCharCode(r);
      continue;
    }
    if (r == 0x200D || r == 0xFE0F || r == 0xFE0E) {
      continue; // ZWJ·variation selector
    }
    if (r >= 0x1F000 && r <= 0x1FAFF) continue; // 이모지 블록
    if (r >= 0x2600 && r <= 0x27BF) continue; // 기타 기호/딩벳
    if (r >= 0x2B00 && r <= 0x2BFF) continue; // 화살표·도형
    if (r >= 0x2190 && r <= 0x21FF) continue; // 화살표
    if (r >= 0x3200 && r <= 0x33FF) continue; // 원문자·CJK 호환
    if (r >= 0xFE30 && r <= 0xFE4F) continue; // CJK 호환 형태
    // ⚠️ (변경) CJK 한자는 **여기서 지우지 않는다.**
    //  · PDF 경로: `DocPdf.sanitize` → `_paperSafe` 가 담당한다. 한자 폴백
    //    폰트(TsakHanja-s.otf)가 로드된 경우에만 남기고, 없으면 종전처럼 지운다.
    //  · HTML(브라우저 인쇄) 경로: 시스템 폰트가 한자를 그릴 수 있으므로
    //    지우는 것이 오히려 손해였다('金 李 朴' 이 사라짐).
    if (r >= 0xE000 && r <= 0xF8FF) continue; // 사설영역(PUA)
    b.writeCharCode(r);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
}

/// 보고서형 PDF 의 **한 블록** — 컬러 제목 띠 + 4열 표 + 하단 메모.
///
/// ## 요구사항 (그대로)
/// "pdf 출력물의 형태는 결산의 경우 기존 무인양품 스타일을 버리고, 미리보기
///  항목의 내용을 참조해서 항목별로 보기좋게 출력 … 계산서처럼 보여지기보다는
///  보고서처럼 보여지는게 좋아서그래."
///
/// ## 설계
/// 미리보기(`SettlementPaperView`)의 블록 하나와 **1:1 대응**한다.
///  · [accent] : 좌측 3pt 컬러 바 + 10% 배경 틴트 색
///  · [rows]   : 4열 [항목, 내용, 금액·인원, 비고/메모]
///  · [note]   : 표 아래 작은 설명 한 줄
class DocReportBlock {
  const DocReportBlock({
    required this.title,
    required this.rows,
    this.accent = '#7C6A9C',
    this.subtitle = '',
    this.note = '',
  });

  /// 블록 제목(예: '후원 내역').
  final String title;

  /// 우측 작은 글씨(예: '8건').
  final String subtitle;

  /// 4열 행 목록.
  final List<List<String>> rows;

  /// 강조색(hex) — 좌측 바·틴트·합계 행 글씨에 쓰인다.
  final String accent;

  /// 표 아래 한 줄 메모.
  final String note;
}

/// 표 셀 — 좌측 컬러 바/정렬/굵기 옵션.
class DocCell {
  const DocCell(
    this.text, {
    this.align = 'left',
    this.accent,
    this.bold = false,
    this.sub,
  });

  final String text;
  final String align;

  /// 좌측 컬러 바 색(지정 시 4px 좌측 보더).
  final String? accent;
  final bool bold;
  final String? sub;

  String toTd({bool nowrap = false, int? maxLines}) {
    final style = StringBuffer('text-align:$align;');
    if (accent != null) style.write('border-left:4px solid $accent;');
    if (bold) style.write('font-weight:600;');
    if (nowrap) style.write('white-space:nowrap;');
    // 셀 줄 수 상한 — 2줄 허용이면 그 안에서 접히게(넘치면 말줄임).
    if (maxLines != null && maxLines > 0 && !nowrap) {
      style.write(
        'display:-webkit-box;-webkit-line-clamp:$maxLines;'
        '-webkit-box-orient:vertical;overflow:hidden;',
      );
    }
    final subHtml = (sub != null && sub!.trim().isNotEmpty)
        ? '<div class="sub">${_esc(sub)}</div>'
        : '';
    return '<td style="$style">${_esc(text)}$subHtml</td>';
  }
}

/// MUJI 스타일 문서 헤더 정보.
class DocMeta {
  const DocMeta({
    required this.title,
    this.subtitle = '',
    this.description = '',
    this.createdAt = '',
    this.author = '',
    this.extra = const {},
  });

  final String title;
  final String subtitle;
  final String description;

  /// 파일 생성일(미지정 시 호출부에서 채움).
  final String createdAt;
  final String author;

  /// 추가 기초정보(라벨→값) — 헤더 메타 영역에 작은 글씨로 표시.
  final Map<String, String> extra;
}

/// 앱 전역 기본 출력 문서를 만든다.
///
/// ## 디자인 규칙 (샘플 포맷 — 모든 출력 공통)
///  · 페이지를 **얇은 테두리 박스**로 감싼다(둥근 모서리).
///  · 최상단 좌측에 **레터헤드**(브랜드 · 문서명) + 우측 **`1 of 1`**.
///  · 큰 **제목** + 작은 **부제/설명/메타(생성일·생성자)**.
///  · 표 위에 **`PART 1 | N개 항목`** 구분 라벨.
///  · 표 헤더는 옅은 배경 + 좌측 컬러바, 본문은 저채도 다색 악센트.
///  · 하단 **출력규칙 · 보고서 · 1/1** 푸터.
///
/// [columns] 표 헤더, [rows] 각 행의 셀 목록, [summary] 하단 합계(HTML 조각 허용).
String buildMujiDoc({
  required DocMeta meta,
  List<String> columns = const [],
  List<List<DocCell>> rows = const [],
  String summary = '',
  String footerLeft = '한국범스카우트중앙회',
  String footerRight = '',
  bool landscape = false,
  String? emblemDataUri,
  Set<int> noWrapCols = const {},
  List<List<int>>? bands,
  int? maxCellLines,
}) {
  final now = meta.createdAt.isNotEmpty ? meta.createdAt : _stamp();
  final head = StringBuffer();
  // 레터헤드 — 브랜드 · 문서명 + 1 of 1
  head.write(
    '<div class="letter"><span class="lbrand">한국범스카우트중앙회 · TSAK</span>'
    '<span class="lpage">1 of 1</span></div>',
  );
  head.write('<div class="title-row">');
  head.write('<h1>${_esc(meta.title)}</h1>');
  // [요구] 명부/출력물 아이콘 — 중앙회 엠블럼을 제목 우측에 표시.
  // · data URI(base64) 가 있으면 그것을 우선 사용(Blob/새 창에서도 로드됨).
  // · 없으면 상대경로로 폴백(서버가 직접 서빙하는 경우).
  final emblemSrc = (emblemDataUri != null && emblemDataUri.trim().isNotEmpty)
      ? emblemDataUri
      : 'assets/assets/images/tsak_emblem.png';
  head.write(
    '<img class="emblem" src="$emblemSrc" alt="" '
    'onerror="this.style.display=\'none\'">',
  );
  head.write('</div>');
  if (meta.subtitle.trim().isNotEmpty) {
    head.write('<div class="sub2">${_esc(meta.subtitle)}</div>');
  }
  // 기초정보(작은 글씨): 세부설명 + 생성일 + 생성자 + 추가정보
  final metaItems = <String>[];
  if (meta.description.trim().isNotEmpty) {
    metaItems.add('<div class="desc">${_esc(meta.description)}</div>');
  }
  final facts = <String, String>{
    if (meta.author.trim().isNotEmpty) '생성자': meta.author,
    '생성일': now,
    ...meta.extra,
  };
  final factHtml = facts.entries
      .map((e) => '<div><b>${_esc(e.key)}</b> ${_esc(e.value)}</div>')
      .join();
  final metaHtml =
      '<div class="meta">${metaItems.join()}'
      '<div class="facts">$factHtml</div></div>';

  // PART 라벨 — 표 위 구분선 + 섹션 표시.
  final rowCount = rows.length;
  final partLabel = columns.isEmpty
      ? ''
      : '<div class="part"><span class="plabel">PART 1</span>'
            '<span class="prule"></span>'
            '<span class="pcount">${rowCount > 0 ? '$rowCount개 항목' : ''}</span></div>';

  // 머리행 반복 (요구: "명부 출력시 페이지가 넘어갈 경우 상단에 구분표 반복").
  //  th 를 <thead> 로 감싸야 브라우저 인쇄에서 **페이지마다 머리행이 반복**된다.
  //  기존에는 <tr><th> 만 있어 2페이지부터 구분표가 사라졌다.
  //
  //  (요구 2026-10-31) "항목이 많을 경우 가로줄을 하나 더 추가해서 두줄방지"
  //  → [bands] 가 있으면 표를 **단별로 따로** 만들어 세로로 쌓는다. 단마다
  //    머리행이 반복되고, 단 사이에 굵은 가로 구분선(`.bandsep`)이 하나 더 생긴다.
  //    각 단은 전폭을 쓰므로 열당 폭이 약 2배가 되어 접히지 않는다.
  final useBands = bands != null &&
      bands.length > 1 &&
      bands.every((b) => b.isNotEmpty);
  String oneTable(List<int>? pick, {bool lower = false}) {
    final idx = pick ?? List<int>.generate(columns.length, (i) => i);
    final th = '<thead><tr>'
        '${idx.map((i) => '<th>${_esc(i < columns.length ? columns[i] : '')}</th>').join()}'
        '</tr></thead>';
    final tb = '<tbody>'
        '${rows.map((r) => '<tr>${idx.map((i) {
          final cell = i < r.length ? r[i] : const DocCell('');
          return cell.toTd(
            nowrap: noWrapCols.contains(i),
            // 셀 줄 수 제한 — 넘치면 브라우저가 말줄임 대신 접도록 line-clamp.
            maxLines: maxCellLines,
          );
        }).join()}</tr>').join()}'
        '</tbody>';
    return '<table${lower ? ' class="lowband"' : ''}>$th$tb</table>';
  }

  final bandsL = bands;
  final table = (columns.isEmpty && rows.isEmpty)
      ? ''
      : (useBands && bandsL != null)
      ? '${oneTable(bandsL[0])}'
            '<div class="bandsep"></div>'
            '${oneTable(bandsL[1], lower: true)}'
      : oneTable(null);

  final sumHtml = summary.trim().isEmpty
      ? ''
      : '<div class="sum">$summary</div>';

  final footRightText = footerRight.isNotEmpty
      ? footerRight
      : '출력규칙 · 보고서 · 1/1';
  return '''<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8">
<title>${_esc(meta.title)}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 *{box-sizing:border-box}
 @page{size:A4 ${landscape ? 'landscape' : 'portrait'};margin:12mm}
 body{font-family:$kDocFontStack;color:#3A3A3A;
   padding:24px;margin:0;background:#EFEDE8;font-size:13px}
 /* 페이지 테두리 박스(샘플 규칙) */
 .page{background:#fff;border:1px solid #D8D3CA;border-radius:4px;
   padding:26px 26px 16px;max-width:820px;margin:16px auto;
   box-shadow:0 1px 3px rgba(0,0,0,.05)}
 /* 레터헤드 */
 .letter{display:flex;justify-content:space-between;align-items:center;
   font-size:10px;letter-spacing:1.2px;color:#9A9388;padding-bottom:6px;
   border-bottom:1px solid #EDEAE3}
 .letter .lbrand{font-weight:700}
 .letter .lpage{font-variant-numeric:tabular-nums}
 .title-row{display:flex;align-items:center;justify-content:space-between;gap:12px}
 .title-row .emblem{width:44px;height:44px;object-fit:contain;flex:none}
 h1{font-size:22px;color:#3A3A3A;font-weight:800;margin:14px 0 6px;letter-spacing:-.3px}
 .title-row h1{margin:14px 0 6px;flex:1}
 .sub2{font-size:12.5px;color:#8C877E;margin:0 0 12px}
 .meta{padding:10px 0;border-top:1px solid #E4E0D8;border-bottom:1px solid #E4E0D8;
   font-size:11px;line-height:1.7;margin-bottom:4px}
 .desc{font-size:12px;color:#5A564E;margin-bottom:8px;white-space:pre-wrap}
 .facts{display:flex;flex-wrap:wrap;gap:0 22px;color:#8C877E}
 .facts b{color:#6E6960;font-weight:600;display:inline-block;min-width:50px}
 /* PART 라벨 */
 .part{display:flex;align-items:center;gap:10px;margin:14px 0 0}
 .part .plabel{font-size:11px;font-weight:800;color:#fff;background:#3A3A3A;
   padding:3px 9px;border-radius:3px;letter-spacing:.6px;white-space:nowrap}
 .part .prule{flex:1;height:1px;background:#D8D3CA}
 .part .pcount{font-size:11px;color:#8C877E;white-space:nowrap}
 table{width:100%;border-collapse:collapse;margin-top:10px}
 /* 두 단(가로줄 추가) — 단과 단 사이 굵은 구분선. */
 .bandsep{height:0;border-top:1.6px solid #4A4A48;margin:10px 0 0}
 table.lowband{margin-top:0}
 th{font-weight:700;color:#5A564E;text-align:left;font-size:11.5px;letter-spacing:.3px;
   background:#F4F1EA;border-bottom:1px solid #C9C2B6;padding:8px 10px}
 td{border-bottom:1px solid #EDEAE3;padding:9px 10px;vertical-align:top}
 tr:nth-child(even) td{background:#FBFAF7}
 .sub{font-size:11px;color:#9A9388;margin-top:2px}
 .sum{margin-top:18px;padding:14px 16px;border-top:2px solid #3A3A3A;
   background:#F8F7F4;border-radius:0 0 4px 4px;
   text-align:right;font-size:13px;line-height:2}
 .sum .g{font-size:18px;font-weight:700;color:#7C6A9C}
 .foot{margin-top:22px;padding-top:12px;border-top:1px solid #E4E0D8;font-size:11px;
   color:#9A9388;display:flex;justify-content:space-between;
   letter-spacing:.4px}
 /* 상단 툴바 — 닫기(뒤로가기)·인쇄 버튼. (모든 출력창 공통 규칙) */
 .tsak-bar{position:sticky;top:0;z-index:99;display:flex;gap:8px;align-items:center;
   justify-content:flex-end;padding:10px 14px;background:#F4F1EA;
   border-bottom:1px solid #E4E0D8;margin:-24px -24px 16px}
 .tsak-bar .sp{flex:1;font-size:12px;color:#8C877E;text-align:center}
 .tsak-bar button{font-family:inherit;font-size:13px;font-weight:700;cursor:pointer;
   border-radius:8px;padding:8px 16px;border:1px solid #7C6A9C;background:#fff;color:#5A4A78}
 .tsak-bar button.pri{background:#7C6A9C;color:#fff}
 .tsak-bar button.back{background:#5E7A4B;color:#fff;border-color:#5E7A4B}
 @media print{body{background:#fff;padding:0}
   .tsak-bar{display:none!important}
   .page{border:0;box-shadow:none;margin:0;padding:0;max-width:none}}
</style></head><body>
<div class="tsak-bar">
  <button class="back" onclick="window.close(); if(!window.closed){history.back();}" title="이전 화면으로">‹ 돌아가기</button>
  <span class="sp">${_esc(meta.title)}</span>
  <button class="pri" onclick="window.print()">인쇄 / PDF 저장</button>
</div>
<div class="page">
$head
$metaHtml
$partLabel
$table
$sumHtml
<div class="foot"><span>${_esc(footerLeft)}</span><span>${_esc(footRightText)}</span></div>
</div>
</body></html>''';
}

String _stamp() {
  final d = DateTime.now();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}.${p(d.month)}.${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}

/// (모든 이미지·출력창 공통 규칙) 상단 툴바(닫기/뒤로가기 + 인쇄) + 기본 스타일로
/// 임의 [inner] HTML 본문을 감싸 완전한 문서를 만든다.
///
/// `buildMujiDoc` 를 사용하지 않는 특수 출력(통계 표, 슬라이드형 PPT 등)에서
/// 재사용한다. 툴바는 인쇄 시 숨겨진다.
String wrapPrintHtml(String title, String inner, {bool landscape = false}) =>
    '''<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8">
<title>${_esc(title)}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 *{box-sizing:border-box}
 @page{size:A4 ${landscape ? 'landscape' : 'portrait'};margin:14mm}
 body{font-family:$kDocFontStack;color:#3A3A3A;padding:0;margin:0;background:#EFEDE8;font-size:13px}
 /* 샘플 규격: 페이지 테두리 박스 + 레터헤드 */
 .page{background:#fff;border:1px solid #D8D3CA;border-radius:4px;
   padding:26px 26px 16px;max-width:820px;margin:16px auto;
   box-shadow:0 1px 3px rgba(0,0,0,.05)}
 .letter{display:flex;justify-content:space-between;align-items:center;
   font-size:10px;letter-spacing:1.2px;color:#9A9388;padding-bottom:6px;
   border-bottom:1px solid #EDEAE3}
 .letter .lbrand{font-weight:700}
 .print-body{padding:0}
 table{border-collapse:collapse;width:100%;font-size:12.5px;margin-top:10px}
 th,td{border-bottom:1px solid #EDEAE3;padding:8px 10px}
 th{background:#F4F1EA;color:#5A564E;font-weight:700}
 tr:nth-child(even) td{background:#FBFAF7}
 /* 상단 툴바 — 닫기(뒤로가기)·인쇄 버튼. (모든 출력창 공통 규칙) */
 .tsak-bar{position:sticky;top:0;z-index:99;display:flex;gap:8px;align-items:center;
   justify-content:flex-end;padding:10px 14px;background:#F4F1EA;
   border-bottom:1px solid #E4E0D8}
 .tsak-bar .sp{flex:1;font-size:12px;color:#8C877E;text-align:center}
 .tsak-bar button{font-family:inherit;font-size:13px;font-weight:700;cursor:pointer;
   border-radius:8px;padding:8px 16px;border:1px solid #7C6A9C;background:#fff;color:#5A4A78}
 .tsak-bar button.pri{background:#7C6A9C;color:#fff}
 .tsak-bar button.back{background:#5E7A4B;color:#fff;border-color:#5E7A4B}
 @media print{body{background:#fff;padding:0}.tsak-bar{display:none!important}
   .page{border:0;box-shadow:none;margin:0;padding:0;max-width:none}.print-body{padding:0}}
</style></head><body>
<div class="tsak-bar">
  <button class="back" onclick="window.close(); if(!window.closed){history.back();}" title="이전 화면으로">‹ 돌아가기</button>
  <span class="sp">${_esc(title)}</span>
  <button class="pri" onclick="window.print()">인쇄 / PDF 저장</button>
</div>
<div class="page">
  <div class="letter"><span class="lbrand">한국범스카우트중앙회 · TSAK</span><span>1 of 1</span></div>
  <div class="print-body">$inner</div>
</div>
</body></html>''';

// ============================================================================
//  보고서형 HTML — 결산서를 **블록 그래픽**으로 인쇄한다.
// ============================================================================

/// [DocReportBlock] 목록을 브라우저 인쇄용 HTML 로 만든다.
///
/// ## 왜 필요한가 (요구)
/// "행사결산 출력시 보고서 형식이 아니라 계산서처럼 나열됨"
/// → PDF 는 `DocPdf.buildReport` 로 보고서형이 됐지만, **브라우저 인쇄**는
///   계속 무인양품 표(`doc.columns`/`doc.rows`)를 썼다. 같은 문서가 두 모습으로
///   나오면 사용자 입장에서는 "고쳐지지 않았다"가 된다.
/// → 이 함수가 [DocPdf.buildReport] 와 **같은 그래픽**을 HTML/CSS 로 그린다.
///
/// [template] 은 모양만 바꾼다(색 띠·괘선·카드·큰 숫자). 데이터는 동일하다.
String buildReportDocHtml({
  required DocMeta meta,
  required List<DocReportBlock> blocks,
  List<String> summary = const [],
  String footerLeft = '한국범스카우트중앙회',
  String footerRight = '',
  bool landscape = false,
  String? emblemDataUri,
  double scale = 1.0,
}) {
  final now = meta.createdAt.isNotEmpty ? meta.createdAt : _stamp();
  final emblemSrc = (emblemDataUri != null && emblemDataUri.trim().isNotEmpty)
      ? emblemDataUri
      : 'assets/assets/images/tsak_emblem.png';

  // ── 머리부 ──
  final head = StringBuffer()
    ..write(
      '<div class="letter"><span class="lbrand">한국범스카우트중앙회 · TSAK</span>'
      '<span class="lpage">1 of 1</span></div>',
    )
    ..write('<div class="title-row"><h1>${_esc(meta.title)}</h1>')
    ..write(
      '<img class="emblem" src="$emblemSrc" alt="" '
      "onerror=\"this.style.display='none'\">",
    )
    ..write('</div>');
  if (meta.subtitle.trim().isNotEmpty) {
    head.write('<div class="sub2">${_esc(meta.subtitle)}</div>');
  }
  final facts = <String, String>{
    if (meta.author.trim().isNotEmpty) '생성자': meta.author,
    '생성일': now,
    ...meta.extra,
  };
  head.write(
    '<div class="meta">'
    '${meta.description.trim().isNotEmpty ? '<div class="desc">${_esc(meta.description)}</div>' : ''}'
    '<div class="facts">'
    '${facts.entries.map((e) => '<div><b>${_esc(e.key)}</b> ${_esc(e.value)}</div>').join()}'
    '</div></div>',
  );

  // ── 블록부 ──
  final body = StringBuffer();
  for (final b in blocks) {
    final isTotalRow = <int>{};
    final rowsHtml = StringBuffer();
    // ── [요구 2026-10-26] "결산자료 출력시 상세항목이 칸을 넓게 사용하지 않는
    //  레이아웃임 → 옆간을 모두 사용하도록 변경 (기존요청사항임)"
    //
    //  ## 원인
    //  상세 행은 `['· 상세', 원본내용, '', '']` 4칸짜리다. 종전에는 이것을
    //  일반 4열 표에 그대로 넣어서, 긴 원본내용이 **c1(38%) 칸에만** 갇히고
    //  c2(20%)·c3(20%) 는 빈 채로 남았다. 종이의 40% 를 버린 셈이다.
    //
    //  ## 해결 — 미리보기(SettlementPaperView._detailBlock)와 같은 모양
    //  상세 행을 표에서 **빼고**, 표 아래에 **전폭(full-width) 블록**으로
    //  내보낸다. 한 줄에 이어 붙이되 가운데점(` · `)으로 구분해 흐르게 한다.
    //  → 화면 미리보기 = 인쇄물 = PDF 가 같은 모양이 된다.
    final detailLines = <String>[];
    for (final r in b.rows) {
      if (_isDetailRowHtml(r)) {
        // 2번째 칸이 원본 한 줄. (비어 있으면 1번째 칸 사용)
        final t = (r.length > 1 ? r[1] : r.isNotEmpty ? r[0] : '').trim();
        if (t.isNotEmpty) detailLines.add(t);
        continue;
      }
      final total = _isTotalRowHtml(r);
      if (total) isTotalRow.add(detailLines.length);
      final cells = <String>[];
      for (var c = 0; c < 4; c++) {
        final v = c < r.length ? r[c] : '';
        cells.add('<td class="c$c">${_esc(v)}</td>');
      }
      rowsHtml.write(
        '<tr${total ? ' class="total"' : ''}>${cells.join()}</tr>',
      );
    }
    final detailHtml = detailLines.isEmpty
        ? ''
        : '<div class="bdet">'
              '<div class="bdh">상세 내역 · ${detailLines.length}건</div>'
              // [요구 2026-10-26] "상세내역은 항목별 연번을 매기고 구분해서
              //  각각의 내역을 보여줘야 읽을 수가 있어"
              //  한 덩어리로 이어 붙이면 어디서 끊기는지 알 수 없다.
              //  → 한 건 = 한 줄, 앞에 연번을 붙인다.
              '${_detailListHtml(detailLines)}'
              '</div>';
    body.write(
      '<div class="blk" style="--ac:${b.accent}">'
      '<div class="bh"><span class="bt">${_esc(b.title)}</span>'
      '${b.subtitle.trim().isEmpty ? '' : '<span class="bs">${_esc(b.subtitle)}</span>'}'
      '</div>'
      '<table class="bt-tbl"><tbody>$rowsHtml</tbody></table>'
      '$detailHtml'
      '${b.note.trim().isEmpty ? '' : '<div class="bn">${_esc(b.note)}</div>'}'
      '</div>',
    );
  }

  final sumHtml = summary.isEmpty
      ? ''
      : '<div class="sum">${summary.map(_esc).join(' · ')}</div>';

  return '''<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8">
<title>${_esc(meta.title)}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 *{box-sizing:border-box}
 @page{size:A4 ${landscape ? 'landscape' : 'portrait'};margin:12mm}
 body{font-family:$kDocFontStack;color:#3A3A3A;padding:24px;margin:0;
   background:#EFEDE8;font-size:${(12.6 * scale).toStringAsFixed(1)}px}
 .page{background:#fff;border:1px solid #D8D3CA;border-radius:4px;
   padding:26px 26px 16px;max-width:860px;margin:16px auto;
   box-shadow:0 1px 3px rgba(0,0,0,.05)}
 .letter{display:flex;justify-content:space-between;align-items:center;
   font-size:10px;letter-spacing:1.2px;color:#9A9388;padding-bottom:6px;
   border-bottom:1px solid #EDEAE3}
 .letter .lbrand{font-weight:700}
 h1{font-size:22px;color:#3A3A3A;font-weight:800;margin:14px 0 6px;
   letter-spacing:-.3px}
 .title-row{display:flex;align-items:center;justify-content:space-between;gap:12px}
 .title-row h1{flex:1;margin:14px 0 6px}
 .title-row .emblem{width:44px;height:44px;object-fit:contain;flex:none}
 .sub2{font-size:12.5px;color:#8C877E;margin:0 0 12px}
 .meta{padding:10px 0;border-top:1px solid #E4E0D8;
   border-bottom:1px solid #E4E0D8;font-size:11px;line-height:1.7;
   margin-bottom:14px}
 .desc{font-size:12px;color:#5A564E;margin-bottom:8px;white-space:pre-wrap}
 .facts{display:flex;flex-wrap:wrap;gap:0 22px;color:#8C877E}
 .facts b{color:#6E6960;font-weight:600;display:inline-block;min-width:50px}
 /* ── 블록 ── */
 .blk{margin:0 0 13px;page-break-inside:avoid}
 .blk:last-child{margin-bottom:0}
 /* 띠 배경은 아주 옅게(종이 느낌). 글자는 **배경보다 진한 색** —
    종전에는 배경과 같은 악센트 원색이라 글자가 배경에 묻혔다.
    (요구: "글자와 배경의 가독성이 매우 낮아짐") */
 .bh{display:flex;align-items:baseline;justify-content:space-between;
   gap:8px;padding:5px 8px;background:#F1EFF4;
   background:color-mix(in srgb,var(--ac) 8%,#fff);
   border-left:4px solid #5A4A78;border-left:4px solid var(--ac);
   border-bottom:1px solid #E2DEE8;
   border-bottom:1px solid color-mix(in srgb,var(--ac) 34%,#fff)}
 .bt{font-size:12.8px;font-weight:800;color:#2A2A2A;letter-spacing:.2px;
   color:color-mix(in srgb,var(--ac) 76%,#111)}
 .bs{font-size:10.5px;color:#6E6960;white-space:nowrap}
 .bt-tbl{width:100%;border-collapse:collapse;table-layout:fixed}
 .bt-tbl td{border-bottom:1px solid #DDD8CE;padding:4.5px 6px;
   vertical-align:top;word-break:break-word}
 .bt-tbl td.c0{width:22%;font-weight:600;color:#3A3A3A}
 .bt-tbl td.c1{width:38%;color:#333}
 .bt-tbl td.c2{width:20%;text-align:right;font-variant-numeric:tabular-nums}
 .bt-tbl td.c3{width:20%;color:#57534B;font-size:.94em}
 .bt-tbl td.detail{color:#5A564E;font-weight:400;font-style:italic}
 /* ── 상세 내역 — 표 아래 **전폭** 블록 ────────────────────────────────
    [요구 2026-10-26] "상세항목이 칸을 넓게 사용하지 않는 레이아웃 →
     옆간을 모두 사용하도록 변경". 종전에는 표의 c1 칸(38%)에만 갇혀
     오른쪽 40%가 비어 있었다. 이제 표 밖 전폭으로 내보낸다. */
 .bdet{margin:6px 0 0;padding:5px 8px 6px;
   background:color-mix(in srgb,var(--ac) 5%,#fff);
   border-left:2px solid color-mix(in srgb,var(--ac) 55%,#fff);
   border-radius:3px}
 .bdh{font-size:10px;font-weight:800;letter-spacing:.2px;
   color:color-mix(in srgb,var(--ac) 70%,#111);margin-bottom:2px}
 /* 한 건 = 한 줄, 앞에 연번. 이어 붙이면 건별 경계가 사라져 못 읽는다. */
 .bdb{margin:0;padding-left:2.2em}
 .bdb li{font-size:11px;line-height:1.6;color:#3A3A3A;
   word-break:break-word;white-space:normal;
   list-style-position:outside;padding-left:2px}
 .bdb li::marker{font-weight:700;
   color:color-mix(in srgb,var(--ac) 80%,#111)}
 .bt-tbl tr.total td{background:#F6F4F9;
   background:color-mix(in srgb,var(--ac) 7%,#fff);
   font-weight:700;color:#2A2A2A;
   border-top:1px solid color-mix(in srgb,var(--ac) 30%,#fff)}
 .bn{font-size:10.5px;color:#5A564E;padding:5px 8px 0;line-height:1.55;
   border-left:2px solid #D8D3CA;
   border-left:2px solid color-mix(in srgb,var(--ac) 45%,#fff);
   margin-left:2px}
 /* ── 합계 ── */
 .sum{margin-top:16px;padding:12px 16px;border-top:2px solid #3A3A3A;
   background:#F8F7F4;text-align:right;font-size:12.5px;line-height:1.9;
   font-weight:600}
 .foot{margin-top:20px;padding-top:12px;border-top:1px solid #E4E0D8;
   font-size:11px;color:#9A9388;display:flex;justify-content:space-between;
   letter-spacing:.4px}
 .tsak-bar{position:sticky;top:0;z-index:99;display:flex;gap:8px;
   align-items:center;justify-content:flex-end;padding:10px 14px;
   background:#F4F1EA;border-bottom:1px solid #E4E0D8;margin:-24px -24px 16px}
 .tsak-bar .sp{flex:1;font-size:12px;color:#8C877E;text-align:center}
 .tsak-bar button{font-family:inherit;font-size:13px;font-weight:700;
   cursor:pointer;border-radius:8px;padding:8px 16px;
   border:1px solid #7C6A9C;background:#fff;color:#5A4A78}
 .tsak-bar button.pri{background:#7C6A9C;color:#fff}
 .tsak-bar button.back{background:#5E7A4B;color:#fff;border-color:#5E7A4B}
 @media print{body{background:#fff;padding:0}
   .tsak-bar{display:none!important}
   .page{border:0;box-shadow:none;margin:0;padding:0;max-width:none}
   .blk{page-break-inside:avoid}}
</style></head><body>
<div class="tsak-bar">
  <button class="back" onclick="window.close(); if(!window.closed){history.back();}" title="이전 화면으로">‹ 돌아가기</button>
  <span class="sp">${_esc(meta.title)}</span>
  <button class="pri" onclick="window.print()">인쇄 / PDF 저장</button>
</div>
<div class="page">
$head
$body
$sumHtml
<div class="foot"><span>${_esc(footerLeft)}</span><span>${_esc(footerRight.isNotEmpty ? footerRight : '출력규칙 · 보고서 · 1/1')}</span></div>
</div>
</body></html>''';
}

/// 합계 성격의 행인가(굵게/틴트).
bool _isTotalRowHtml(List<String> r) {
  final k = r.isNotEmpty ? r[0] : '';
  return k.contains('합계') || k == '잔액' || k == '초과' || k == '이월';
}

/// 상세 행 판별 — `['· 상세', 원본내용, '', '']`.
///  미리보기(`SettlementPaperView._isDetail`)와 **같은 규칙**을 쓴다.
bool _isDetailRowHtml(List<String> r) =>
    r.isNotEmpty && r[0].startsWith('· 상세');

/// 상세 내역을 **연번 목록**(`<ol>`)으로 만든다.
///
/// [요구 2026-10-26] "상세내역은 항목별 연번을 매기고 구분해서 각각의 내역을
///  보여줘야 읽을 수가 있어" — 이어 붙이면 건별 경계가 사라진다.
String _detailListHtml(List<String> lines) {
  final b = StringBuffer('<ol class="bdb">');
  for (final t in lines) {
    b.write('<li>${_esc(t)}</li>');
  }
  b.write('</ol>');
  return b.toString();
}
