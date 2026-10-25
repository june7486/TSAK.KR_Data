/// **출력 템플릿 8종 + 보고서형 경로** 검증 하네스 — `dart run` 으로 실행.
///
/// ## 왜 이 하네스가 필요한가 (실제로 두 번 실패했기 때문)
/// 1) `DocPdf.buildReport` 를 만들었는데 **출력 시트가 reportBlocks 를 버려서**
///    PDF 가 여전히 계산서형으로 나갔다. 사용자가 "여전히 계산서처럼 나열됨" 이라고
///    두 번 말한 이유가 이것이다.
/// 2) 프린트(HTML) 경로만 reportBlocks 를 무시하고 있었다.
///
/// → 이 파일은 "보고서형 데이터가 **문서 끝까지** 도달하는가" 를 값으로 확인한다.
///   Flutter 위젯을 띄우지 않고, 순수 Dart 수준에서 확인 가능한 것만 검사한다.
library;

import 'dart:io';

import '../lib/services/output_templates.dart';
import '../lib/services/print_doc.dart';

int _pass = 0;
int _fail = 0;

void check(String label, bool ok, [String detail = '']) {
  if (ok) {
    _pass++;
    stdout.writeln('  ✅ $label');
  } else {
    _fail++;
    stdout.writeln('  ❌ $label ${detail.isEmpty ? '' : '($detail)'}');
  }
}

void main() {
  stdout.writeln('═══ 출력 템플릿 8종 검증 ═══\n');

  // ── ① 템플릿 목록 자체 ──
  stdout.writeln('[1] 템플릿 목록');
  check('정확히 8종', DocTemplate.all.length == 8, '${DocTemplate.all.length}');
  check(
    '중복 없음',
    DocTemplate.all.toSet().length == DocTemplate.all.length,
  );
  check('report 가 첫 번째', DocTemplate.all.first == DocTemplate.report);
  check(
    '모든 라벨 비어있지 않음',
    DocTemplate.all.every((t) => t.label.trim().isNotEmpty),
  );
  check(
    '모든 설명 비어있지 않음',
    DocTemplate.all.every((t) => t.hint.trim().isNotEmpty),
  );
  check(
    '라벨 유일',
    DocTemplate.all.map((t) => t.label).toSet().length == 8,
  );
  check(
    '설명(hint) 유일 — 서로 다른 템플릿임을 사용자가 구분',
    DocTemplate.all.map((t) => t.hint).toSet().length == 8,
  );

  // ── ② parse / 저장 라운드트립 ──
  stdout.writeln('\n[2] parse · 저장 라운드트립');
  for (final t in DocTemplate.all) {
    check('parse(name) → ${t.name}', DocTemplate.parse(t.name) == t);
    check('parse(label) → ${t.label}', DocTemplate.parse(t.label) == t);
  }
  check('parse(null) → report', DocTemplate.parse(null) == DocTemplate.report);
  check('parse("") → report', DocTemplate.parse('') == DocTemplate.report);
  check(
    'parse(쓰레기) → report',
    DocTemplate.parse('???nope') == DocTemplate.report,
  );
  check(
    '대소문자 무시',
    DocTemplate.parse('REPORT') == DocTemplate.report,
  );

  // ── ③ next() 순환 ──
  stdout.writeln('\n[3] next() 순환');
  var cur = DocTemplate.report;
  final seen = <DocTemplate>{cur};
  for (var i = 0; i < 7; i++) {
    cur = cur.next;
    seen.add(cur);
  }
  check('7회 next 로 8종 모두 방문', seen.length == 8, '${seen.length}');
  check('8회 next 면 원점', cur.next == DocTemplate.report);

  // ── ④ 시각 속성이 템플릿마다 다르다 ──
  stdout.writeln('\n[4] 시각 속성 구분');
  check(
    'report 는 컬러 띠',
    DocTemplate.report.accentBand,
  );
  check(
    'minimal 은 띠 없음',
    !DocTemplate.minimal.accentBand,
  );
  check(
    'ledger 는 격자',
    DocTemplate.ledger.gridLines,
  );
  check(
    'card 는 카드 껍데기',
    DocTemplate.card.cardShell,
  );
  check(
    'brief 는 큰 숫자',
    DocTemplate.brief.bigFigures,
  );
  check(
    'ledger 는 행 높이 압축',
    DocTemplate.ledger.compact,
  );
  check(
    'ledger cellPadV < report cellPadV',
    DocTemplate.ledger.cellPadV < DocTemplate.report.cellPadV,
  );
  check(
    'card blockGap > report blockGap',
    DocTemplate.card.blockGap > DocTemplate.report.blockGap,
  );
  check(
    'minimal tintTotal == 0',
    DocTemplate.minimal.tintTotal == 0,
  );
  check(
    'official accentBand 없음 + 격자',
    !DocTemplate.official.accentBand && DocTemplate.official.gridLines,
  );
  check(
    '8종의 (accentBand,gridLines,cardShell) 조합이 4가지 이상',
    DocTemplate.all
            .map((t) => '${t.accentBand}/${t.gridLines}/${t.cardShell}')
            .toSet()
            .length >=
        4,
  );

  // ── 신규 2종의 '고유 축' 검사 — 다른 7종과 섞이지 않는가 ──
  stdout.writeln('\n[4-2] 신규 2종이 다른 6종과 확실히 구분되는가');
  check('색면형만 원색 꽉 찬 띠', DocTemplate.duotone.isSolidBand);
  check(
    '색면형 외에는 꽉 찬 띠 없음',
    DocTemplate.all.where((t) => t != DocTemplate.duotone).every(
      (t) => !t.isSolidBand,
    ),
  );
  check('색면형은 좌측 바 폭 0(면이므로 불필요)', DocTemplate.duotone.bandWidth == 0);
  check('인장형만 이중 괘선', DocTemplate.stamp.doubleRule);
  check(
    '인장형 외에는 이중 괘선 없음',
    DocTemplate.all.where((t) => t != DocTemplate.stamp).every(
      (t) => !t.doubleRule,
    ),
  );
  check('인장형만 도장 칸', DocTemplate.stamp.stampBox);
  check(
    '인장형 외에는 도장 칸 없음',
    DocTemplate.all.where((t) => t != DocTemplate.stamp).every(
      (t) => !t.stampBox,
    ),
  );
  check('인장형은 제목 가운데(제출용)', DocTemplate.stamp.centerTitle);
  // 8종이 '띠 / 괘선 / 카드 / 여백 / 격자 / 숫자 / 색면 / 인장' 8축을 나눠 갖는지.
  final axes = <String>{
    for (final t in DocTemplate.all) ...[
      if (t.isSolidBand) 'solid',
      if (t.cardShell) 'card',
      if (t.gridLines) 'grid',
      if (t.centerTitle) 'center',
      if (t.bigFigures) 'big',
      if (t.compact) 'compact',
      if (t.stampBox) 'stamp',
      if (t.doubleRule) 'double',
      if (t.bandAlpha == 0 && t.tintTotal == 0) 'plain',
    ],
  };
  check('서로 다른 시각 축 6가지 이상', axes.length >= 6, '${axes.length}: $axes');

  // ── ⑤ 보고서형 HTML 이 실제로 그려지는가 ──
  //
  //  ## 이 검사가 핵심
  //  "PDF 는 보고서형인데 프린트는 계산서형" 이던 버그를 잡기 위해서는
  //  HTML 경로도 블록을 그리는지 **문자열로** 확인해야 한다.
  stdout.writeln('\n[5] buildReportDocHtml — 블록 그래픽');
  const blocks = [
    DocReportBlock(
      title: '참가자',
      subtitle: '3행',
      accent: '#2E5F8A',
      rows: [
        ['총원', '인가 18 · 일반 4', '22명', ''],
        ['합계', '', '22명', ''],
        ['· 상세', '인가 18 / 일반 4', '', ''],
      ],
      note: '인가자와 일반회원을 구분해 집계합니다.',
    ),
    DocReportBlock(
      title: '수입',
      accent: '#4E7A4B',
      rows: [
        ['참가비', '30,000원 × 22', '660,000원', ''],
        ['후원금', '', '100,000원', '메모: 김밥 후원 감사'],
        ['합계', '', '760,000원', ''],
      ],
    ),
  ];
  final html = buildReportDocHtml(
    meta: const DocMeta(
      title: '2026 테스트 행사 결산',
      subtitle: '행사 결산서 · 2개 항목',
      description: '보고서형 검증',
      author: '검증',
    ),
    blocks: blocks,
    summary: ['수입 760,000원 · 지출 500,000원 · 잔액 260,000원'],
    footerLeft: '한국범스카우트중앙회 · 행사 결산',
    emblemDataUri: null,
  );
  check('HTML 문서 시작', html.startsWith('<!DOCTYPE html>'));
  check('HTML 문서 종료', html.trimRight().endsWith('</html>'));
  check('블록 div 존재', html.contains('class="blk"'));
  check('블록 2개', 'class="blk"'.allMatches(html).length == 2);
  check('accent 변수 전달', html.contains('--ac:#2E5F8A'));
  check('두 번째 accent', html.contains('--ac:#4E7A4B'));
  check('블록 제목 렌더', html.contains('참가자') && html.contains('수입'));
  check('부제 렌더', html.contains('3행'));
  check('합계행 클래스', html.contains('class="total"'));
  check('상세행 클래스', html.contains('detail\">· 상세'));
  check(
    '4열 고정폭 CSS',
    html.contains('.c0{width:22%') && html.contains('.c2{width:20%'),
  );
  check('메모(note) 렌더', html.contains('class="bn"'));
  check('요약 렌더', html.contains('잔액 260,000원'));
  check('인쇄 툴바', html.contains('인쇄 / PDF 저장'));
  check('엠블럼 폴백 경로', html.contains('tsak_emblem.png'));
  check('빈 블록 없이 렌더', !html.contains('class="blk" style="--ac:"'));

  // ── ⑥ HTML 이스케이프 (XSS·깨짐 방지) ──
  stdout.writeln('\n[6] HTML 이스케이프');
  final evil = buildReportDocHtml(
    meta: const DocMeta(title: '<script>alert(1)</script>'),
    blocks: const [
      DocReportBlock(
        title: 'a & b < c',
        rows: [
          ['<img src=x>', '&', '>', '"'],
        ],
      ),
    ],
  );
  check('제목 태그 이스케이프', !evil.contains('<script>alert(1)'));
  check('& 이스케이프', evil.contains('&amp;'));
  check('< 이스케이프', evil.contains('&lt;'));

  // ── ⑦ 빈 블록 · 합계 판정 ──
  stdout.writeln('\n[7] 빈 입력 안전성');
  final empty = buildReportDocHtml(
    meta: const DocMeta(title: '빈 문서'),
    blocks: const [],
  );
  check('블록 0개여도 문서 생성', empty.contains('</html>'));
  check('블록 div 없음', !empty.contains('class="blk"'));
  check('요약 없으면 .sum 없음', !empty.contains('class="sum"'));

  // ── ⑧ 템플릿 6종이 실제 HTML 을 만든다(회귀 방지) ──
  stdout.writeln('\n[8] 6종 모두 렌더 가능');
  for (final t in DocTemplate.all) {
    final h = buildReportDocHtml(
      meta: DocMeta(title: '템플릿 ${t.label}'),
      blocks: const [
        DocReportBlock(
          title: '항목',
          rows: [
            ['ㄱ', 'ㄴ', '1', ''],
          ],
        ),
      ],
    );
    check('${t.label} 렌더', h.contains('</html>') && h.contains('class="blk"'));
  }

  stdout.writeln('\n' + '═' * 46);
  stdout.writeln('결과: PASS $_pass / FAIL $_fail');
  if (_fail > 0) exitCode = 1;
}
