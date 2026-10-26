// 결산 표 '상세' 레이아웃 회귀 테스트.
//
// 배경(사용자 지적):
//   "행사 결산 창에서 … 세리 확장 되면 레이아웃이 더 깔끔해질 것 같음.
//    특히 기부·후원해서 온 층에 열었을 때 하나로 합쳐서 글자가
//    한꺼번에 나열되면 좋겠음."
//
// 원인: Flutter 의 Table 은 colspan(열 병합)을 지원하지 않는다.
//       상세 문장을 좁은 2번째 열에만 넣을 수밖에 없어 세로로 길게 쪼개졌다.
//
// 수정: 상세 행을 표에서 분리해 **표 아래 전폭 블록**으로 모아
//       한 줄에 이어 붙인다.
//
// 이 테스트는 그 동작을 고정한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/settlement_layout.dart';
import 'package:tsak_credential_manager/widgets/settlement_paper_view.dart';

const _details = [
  '2026-10-20 · 이항복 · 기타후원 · 메모: 2026 ATAS MOU',
  '2026-10-20 · 이항복 · 식사후원 · 너른마당 점심식사제공 (5인)',
  '2026-10-20 · 이승준 · 기타후원 · 행사 잔액 인원 후원',
  '2026-10-20 · 이항복 · 물품후원 · 박가스 40병, 비타500 40병',
];

SettlementBlockData _sponsor({bool withDetails = true}) =>
    SettlementBlockData(
      block: SettlementBlock.sponsor,
      rows: const [
        ['식사후원', '140,000원', '1건'],
        ['물품후원', '80,000원', '1건'],
        ['후원 합계', '440,000원', '5건'],
      ],
      note: '후원 5건 · 총 합계 440,000원',
      details: withDetails ? _details : const [],
    );

Future<void> _pump(WidgetTester tester, SettlementLayout layout) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SettlementPaperView(
            layout: layout,
            data: {SettlementBlock.sponsor: _sponsor()},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('상세를 켜면 전폭 "상세 내역" 블록이 나타난다', (tester) async {
    final layout = SettlementLayout(detailOff: {});
    await _pump(tester, layout);

    expect(find.textContaining('상세 내역'), findsWidgets);
    // 상세 문장이 실제로 그려진다.
    expect(find.textContaining('이항복'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('상세 문장이 한 줄로 이어 붙는다(· 구분자)', (tester) async {
    final layout = SettlementLayout(detailOff: {});
    await _pump(tester, layout);

    // join('   ·   ') 로 합쳐졌는지 — 두 상세가 한 Text 안에 있으면 통과.
    final joined = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data ?? '').contains('이항복') &&
          (w.data ?? '').contains('너른마당') &&
          (w.data ?? '').contains('비타500'),
    );
    expect(joined, findsWidgets, reason: '상세가 하나로 합쳐져야 한다');
  });

  testWidgets('상세를 끄면 상세 블록이 사라진다', (tester) async {
    // 상세 끔 — 모든 블록을 detailOff 에 넣는다.
    final layout = SettlementLayout(
      detailOff: {...SettlementBlock.values},
    );
    await _pump(tester, layout);

    expect(find.textContaining('상세 내역'), findsNothing);
    // 합계 표는 그대로 남아야 한다.
    expect(find.textContaining('440,000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('표 안에 상세 행이 남아있지 않다(세로 늘어짐 방지)', (tester) async {
    final layout = SettlementLayout(detailOff: {});
    await _pump(tester, layout);

    // '· 상세' 라는 라벨이 표 셀로 남아 있으면 안 된다.
    expect(find.text('· 상세'), findsNothing);
  });

  testWidgets('배지가 합계행+상세건수를 함께 보여준다', (tester) async {
    final layout = SettlementLayout(detailOff: {});
    await _pump(tester, layout);

    // '3 + 4' 형태
    expect(find.text('3 + 4'), findsWidgets);
  });
}
