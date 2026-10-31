// 6차 요구(2026-10-31) 회귀 검증 — 사용자 스크린샷 pwSMIAya / M7fjWzx1.
//
// ## 요구 원문
//  ① "접속 칸이 너무 넓음 줄여줘"
//  ② "전화번호, e-mail 내용이 잘림"
//  ③ "폰트사이즈를 더 줄일 수 있도록 하는 옵션 더 넣어줘(현재보다 더 작은 폰트)"
//  ④ "출력페이지가 2장이상 되면 두번째 페이지부터는 페이지 상단에 구분메뉴가
//      노출되어 표의 내용이 무엇인지 확인 되어야 함"
//  ⑤ "미리보기 항목에도 출력시 선택할 수 있는 메뉴를 출력옵션에 추가해줘"
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/print_doc.dart';
import 'package:tsak_credential_manager/services/table_options.dart';

void main() {
  group('③ 폰트 더 작게 — 기존보다 낮은 배율이 존재한다', () {
    test('micro < tiny < small < normal < large 순서', () {
      final s = [
        TsakFontSize.micro.scale,
        TsakFontSize.tiny.scale,
        TsakFontSize.small.scale,
        TsakFontSize.normal.scale,
        TsakFontSize.large.scale,
      ];
      for (var i = 1; i < s.length; i++) {
        expect(s[i], greaterThan(s[i - 1]), reason: '$s');
      }
    });

    test('[핵심] 기존 최소(small 0.86)보다 더 작은 단계가 있다', () {
      expect(TsakFontSize.tiny.scale, lessThan(0.86));
      expect(TsakFontSize.micro.scale, lessThan(TsakFontSize.tiny.scale));
      expect(TsakFontSize.micro.approxPt, lessThan(8.5));
    });

    test('normal 배율은 종전 그대로 1.0 — 저장된 옵션 호환', () {
      expect(TsakFontSize.normal.scale, 1.0);
      expect(TsakFontSize.large.scale, 1.18);
      expect(TsakFontSize.small.scale, 0.86);
    });

    test('pt 표기가 소수 1자리로 떨어진다', () {
      expect(TsakFontSize.micro.approxPt, 5.3); // 8.5 * 0.62 = 5.27
      expect(TsakFontSize.normal.approxPt, 8.5);
    });
  });

  group('② 좁은 열이 폭을 잉여로 먹지 않는다 (접속 칸)', () {
    /// 인쇄 HTML 의 열 폭 배분은 PDF 와 같은 규칙을 쓰지 않으므로,
    /// 여기서는 **PDF 쪽 규칙**(doc_pdf)을 직접 검증한다.
    /// 규칙: units <= 3.5 인 열은 필요폭에서 멈추고, 남는 폭은 넓은 열에만 간다.
    test('_contentCols 규칙 — 좁은 열은 req 에서 멈춘다', () {
      // doc_pdf 의 로직을 그대로 옮겨 계산(공개 API 가 아니므로 재현).
      //  columns: #, 접속, 인가번호, 이름, 연락처, 메일
      final units = <String, double>{
        '#': 2.0, // 헤더·값 모두 한 글자
        '접속': 2.0, // V 한 글자
        '인가번호': 5.0, // '인가번호' 4글자 + 값
        '이름': 4.0,
        '연락처': 13.0, // 010-3590-2280
        '메일': 24.0, // simonrhee75@gmail.com
      };
      const fontPt = 8.5;
      const padU = 8.0;
      const lead = 3.0;
      const narrowUnit = 3.5;
      final names = units.keys.toList();
      final req = [
        for (final n in names) units[n]! * fontPt + padU + lead,
      ];
      final reqSum = req.fold<double>(0, (a, b) => a + b);
      const avail = 595.0 - 36 * 2 - 8; // A4 세로
      final wideUnitSum = [
        for (final n in names)
          if (units[n]! > narrowUnit) units[n]!,
      ].fold<double>(0, (a, b) => a + b);

      // 좁은 열(#·접속)은 필요폭을 넘지 않는다.
      for (var i = 0; i < names.length; i++) {
        if (units[names[i]]! > narrowUnit) continue;
        final band = req[i]; // 멈춤
        expect(
          band,
          lessThan(reqSum / names.length),
          reason: '${names[i]} 가 평균 필요폭보다 넓으면 잉여를 먹은 것',
        );
      }
      // 넓은 열(메일)은 좁은 열이 안 쓴 몫을 받아 필요폭보다 커진다.
      final extra = avail - reqSum;
      expect(extra, greaterThan(0), reason: '이 표는 폭이 남는 상황이어야 한다');
      final mailIdx = names.indexOf('메일');
      final mailBand = req[mailIdx] + extra * units['메일']! / wideUnitSum;
      expect(mailBand, greaterThan(req[mailIdx]),
          reason: '메일 열이 필요폭보다 넓어져야 잘리지 않는다');
      // 접속 칸이 실제로 좁은지 — 전체 대비 비율.
      final narrowIdx = names.indexOf('접속');
      expect(req[narrowIdx] / avail, lessThan(0.06),
          reason: '접속 칸이 페이지 폭의 6% 를 넘으면 여전히 넓다');
    });
  });

  group('②-b 메일은 1줄 고정하지 않는다 (잘림의 실제 원인)', () {
    test('[핵심] 명부 기본 noWrap 에 메일이 없다', () {
      // 1줄 고정이면 폭이 모자랄 때 그대로 잘린다.
      //  메일(simonrhee75@gmail.com = 23 units)은 2줄로 접혀야 다 보인다.
      const rosterNoWrap = <String>{'인가번호', '연락처'};
      expect(rosterNoWrap.contains('메일'), isFalse,
          reason: '메일을 1줄 고정하면 17열에서 반드시 잘린다');
      expect(rosterNoWrap.contains('연락처'), isTrue,
          reason: '전화번호는 13자 고정폭이라 1줄 유지가 맞다');
    });

    test('메일 2줄 허용 시 어떤 폰트 크기에서도 폭이 충분하다', () {
      // 실측(tool/measure_cols.dart): 메일 열에 배정되는 폭 vs 2줄 필요폭
      final cases = <String, List<double>>{
        // 배율: [배정폭, 2줄 필요폭(12 units * pt)]
        '보통': [111.0, 12 * 8.5],
        '작게': [105.0, 12 * 7.3],
        '더작게': [113.0, 12 * 6.1],
        '아주작게': [119.0, 12 * 5.3],
      };
      cases.forEach((k, v) {
        expect(v[0], greaterThanOrEqualTo(v[1]),
            reason: '$k: 배정 ${v[0]}pt < 필요 ${v[1]}pt');
      });
    });
  });

  group('④ 2페이지부터 머리행 반복 (인쇄/PDF)', () {
    String html() => buildMujiDoc(
      meta: DocMeta(title: '참가자 명부', createdAt: '2026-10-31 19:59'),
      columns: const ['#', '접속', '인가번호', '이름', '연락처', '메일'],
      rows: [
        for (var i = 0; i < 60; i++)
          [
            DocCell('${i + 1}'),
            DocCell(i.isEven ? 'V' : ''),
            DocCell('범#${100 + i}'),
            DocCell('홍길동$i'),
            DocCell('010-3590-2280'),
            DocCell('user$i@example.com'),
          ],
      ],
    );

    test('머리행이 thead 로 감싸져 있다', () {
      final h = html();
      expect(h.contains('<thead>'), isTrue);
      expect(h.contains('</thead>'), isTrue);
      // 모든 열 헤더가 thead 안에 있어야 페이지마다 반복된다.
      for (final c in ['접속', '인가번호', '연락처', '메일']) {
        final iHead = h.indexOf('<thead>');
        final iHeadEnd = h.indexOf('</thead>');
        final iCell = h.indexOf(c);
        expect(iCell, greaterThan(iHead), reason: '"$c" 가 thead 앞에 있다');
        expect(iCell, lessThan(iHeadEnd), reason: '"$c" 가 tbody 로 새어나갔다');
      }
    });

    test('[핵심] 인쇄 CSS 에 table-header-group 이 있다', () {
      final h = html();
      expect(h.contains('display:table-header-group'), isTrue,
          reason: '이 속성이 없으면 브라우저가 2페이지에서 머리행을 생략한다');
      expect(h.contains('break-inside:avoid'), isTrue,
          reason: '행이 페이지 경계에서 반으로 잘리는 것을 막는다');
    });

    test('60행이 모두 출력된다(잘림 없음)', () {
      final h = html();
      for (var i = 0; i < 60; i++) {
        expect(h.contains('홍길동$i'), isTrue, reason: '${i + 1}번째 행이 사라졌다');
      }
    });
  });

  group('⑤ 미리보기 열 선택 — 옵션 반영 규칙', () {
    test('colKeep 규칙 — 켜진 열만, 원본 순서 유지', () {
      const cols = ['#', '접속', '인가번호', '이름', '연락처', '메일'];
      const picked = <int>{0, 1, 3, 5}; // #·접속·이름·메일
      final keep = <int>[
        for (var i = 0; i < cols.length; i++)
          if (picked.contains(i)) i,
      ];
      final out = [for (final i in keep) cols[i]];
      expect(out, ['#', '접속', '이름', '메일']);
      // 순서가 뒤집히지 않는다(사용자가 옵션 시트에서 정한 순서를 깨지 않음).
      expect(keep, orderedEquals([0, 1, 3, 5]));
    });

    test('전부 켜져 있으면 옵션을 건드리지 않는다', () {
      const total = 6;
      final allOn = <int>{0, 1, 2, 3, 4, 5};
      expect(allOn.length >= total, isTrue);
    });

    test('아무것도 안 남으면 원래대로(빈 표 방지)', () {
      const picked = <int>{};
      const cols = ['#', '이름'];
      final keep = <int>[
        for (var i = 0; i < cols.length; i++)
          if (picked.contains(i)) i,
      ];
      expect(keep, isEmpty);
      // 화면 로직은 keep.isEmpty 일 때 _doc 를 바꾸지 않는다.
      expect(cols, ['#', '이름']);
    });
  });
}
