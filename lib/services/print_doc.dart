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

String _esc(String? s) => (s ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

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

  String toTd() {
    final style = StringBuffer('text-align:$align;');
    if (accent != null) style.write('border-left:4px solid $accent;');
    if (bold) style.write('font-weight:600;');
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
}) {
  final now = meta.createdAt.isNotEmpty ? meta.createdAt : _stamp();
  final head = StringBuffer();
  // 레터헤드 — 브랜드 · 문서명 + 1 of 1
  head.write(
    '<div class="letter"><span class="lbrand">한국범스카우트중앙회 · TSAK</span>'
    '<span class="lpage">1 of 1</span></div>',
  );
  head.write('<h1>${_esc(meta.title)}</h1>');
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

  final thead = columns.isEmpty
      ? ''
      : '<tr>${columns.map((c) => '<th>$c</th>').join()}</tr>';
  final tbody = rows
      .map((r) => '<tr>${r.map((c) => c.toTd()).join()}</tr>')
      .join();
  final table = columns.isEmpty && rows.isEmpty
      ? ''
      : '<table>$thead$tbody</table>';

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
 h1{font-size:22px;color:#3A3A3A;font-weight:800;margin:14px 0 6px;letter-spacing:-.3px}
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
