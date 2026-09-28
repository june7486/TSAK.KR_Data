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

/// 앱 전역 기본 출력 문서를 만든다(무인양품 + 다양한 색채, A4 세로).
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
  head.write('<div class="brand">한국범스카우트중앙회 · TSAK</div>');
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

  final thead = columns.isEmpty
      ? ''
      : '<tr>${columns.map((c) => '<th>$c</th>').join()}</tr>';
  final tbody = rows
      .map((r) => '<tr>${r.map((c) => c.toTd()).join()}</tr>')
      .join();
  final table = columns.isEmpty && rows.isEmpty
      ? ''
      : '<table>$thead$tbody</table>';

  final sumHtml =
      summary.trim().isEmpty ? '' : '<div class="sum">$summary</div>';

  return '''<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8">
<title>${_esc(meta.title)}</title>
<style>
 *{box-sizing:border-box}
 @page{size:A4 ${landscape ? 'landscape' : 'portrait'};margin:14mm}
 body{font-family:'Malgun Gothic','NanumGothic',sans-serif;color:#3A3A3A;
   padding:30px;max-width:820px;margin:0 auto;background:#fff;font-size:13px}
 .brand{font-size:11px;letter-spacing:3px;color:#9A9388}
 h1{font-size:21px;color:#4A4A48;font-weight:600;margin:4px 0 2px}
 .sub2{font-size:12.5px;color:#8C877E;margin:2px 0 10px}
 .meta{padding:12px 0;border-top:1px solid #E4E0D8;border-bottom:1px solid #E4E0D8;
   font-size:11.5px;line-height:1.7}
 .desc{font-size:12px;color:#5A564E;margin-bottom:8px;white-space:pre-wrap}
 .facts{display:flex;flex-wrap:wrap;gap:0 24px;color:#8C877E}
 .facts b{color:#6E6960;font-weight:600;display:inline-block;min-width:52px}
 table{width:100%;border-collapse:collapse;margin-top:16px}
 th{font-weight:600;color:#6E6960;text-align:left;font-size:12px;letter-spacing:.4px;
   border-bottom:1px solid #4A4A48;padding:8px 10px}
 td{border-bottom:1px solid #EDEAE3;padding:9px 10px;vertical-align:top}
 .sub{font-size:11px;color:#9A9388;margin-top:2px}
 .sum{margin-top:20px;padding-top:14px;border-top:2px solid #4A4A48;text-align:right;font-size:13px;line-height:2}
 .sum .g{font-size:18px;font-weight:700;color:#7C6A9C}
 .foot{margin-top:28px;padding-top:12px;border-top:1px solid #E4E0D8;font-size:11px;color:#9A9388;
   display:flex;justify-content:space-between}
 @media print{body{padding:0}}
</style></head><body>
$head
$metaHtml
$table
$sumHtml
<div class="foot"><span>${_esc(footerLeft)}</span><span>${_esc(footerRight.isNotEmpty ? footerRight : now)}</span></div>
</body></html>''';
}

String _stamp() {
  final d = DateTime.now();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}.${p(d.month)}.${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}
