// 미리보기 회귀 검증 — 사용자 스크린샷으로 보고된 **세 가지 증상**을 고정한다.
//
// ## 보고된 증상 (2026-10-31, 스크린샷 lXGlFwoY)
//  ① "추가항목 4개 선택" 인데 **나머지 항목이 안 보인다** → "추가항목 모두 노출"
//  ② 미리보기 이미지에서 표 **오른쪽 열이 잘려** 추가항목이 화면 밖으로 나감
//  ③ "좌측 이름 하나당 세로줄 2줄 3줄" 옵션이 필요한데 2줄방지와 충돌
//
// 이 테스트는 ①의 **진짜 원인**을 재현한다:
//   옵션에 cols(열 선택)가 걸려 있으면, extraColumns 가 붙인 새 열이
//   viewColumns 단계에서 **필터로 삭제**되어 사라졌다.
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/extra_fields.dart';
import 'package:tsak_credential_manager/services/extra_output.dart';
import 'package:tsak_credential_manager/services/print_doc.dart';
import 'package:tsak_credential_manager/services/table_options.dart';
import 'package:tsak_credential_manager/services/table_export.dart';

TsakTableDoc _roster({TableOutputOptions? options}) {
  const cols = ['연번', '이름', '인가번호', '소속', '직책', '연락처', '메일'];
  return TsakTableDoc(
    title: '2026 범2호 노경하선배 추모행사',
    subtitle: '참가 5명',
    columns: cols,
    rows: const [
      ['1', '홍길동', '12', '리더', '대중교통', '010-1111-1111', 'a@x.com'],
      ['2', '김승수', '34', '리더', '자차', '010-2222-2222', 'b@x.com'],
    ],
    options: options,
  );
}

/// 스크린샷의 참석자 원본(추가입력 포함).
List<Map<String, dynamic>> _attendees() => <Map<String, dynamic>>[
  {
    'name': '홍길동',
    'number': '12',
    'transport': '대중교통',
    'lodging': '숙박',
    'arrive': '점심 전',
    'from': '서울',
    'eta': '2시간',
    'companion': '2명',
    'address': '서울시 강남구',
    'message': '주차 안내 부탁',
  },
  {
    'name': '김승수',
    'number': '34',
    'transport': '자차',
    'lodging': '비숙박',
    'arrive': '저녁',
    'from': '부산',
    'eta': '5시간',
    'companion': '1명',
    'address': '부산시 해운대',
    'message': '',
  },
];

/// 값이 채워진 항목 키 — 미리보기 기본 선택과 같은 규칙.
Set<String> _filledKeys(List<Map<String, dynamic>> src) => <String>{
  for (final f in ExtraFields.all)
    if (src.any((a) => f.hasValue(a))) f.key,
};

void main() {
  group('① 추가항목이 실제로 출력 열에 붙는다 — "모두 노출"', () {
    test('옵션 cols 가 없으면 8개 항목이 모두 열로 붙는다', () {
      final doc = _roster();
      final keys = _filledKeys(_attendees());
      final out = extraColumns(doc, source: _attendees(), keys: keys);

      // message 는 1명만 썼지만 값이 있으므로 포함된다.
      expect(keys.length, 8, reason: '$keys');
      expect(out.columns.length, doc.columns.length + 8);
      expect(out.viewColumns.length, out.columns.length,
          reason: '옵션 cols 가 없으면 전체 열이 그대로 나와야 한다');
      expect(out.viewColumns, containsAll(ExtraFields.all.map((f) => f.label)));
    });

    test('[회귀] 옵션 cols 가 있어도 추가항목 열이 삭제되지 않는다', () {
      // 화면이 넘기는 실제 옵션 — 원래 열 7개만 선택된 상태.
      const opts = TableOutputOptions(
        cols: [0, 1, 2, 3, 4, 5, 6],
        noWrap: {'인가번호', '연락처'},
      );
      final doc = _roster(options: opts);
      final out = extraColumns(
        doc,
        source: _attendees(),
        keys: _filledKeys(_attendees()),
      );

      // 종전 버그: cols=[0..6] 그대로면 viewColumns 가 7개만 남아
      //  추가한 8개 열이 **통째로 사라졌다**. 이제는 살아 있어야 한다.
      expect(out.viewColumns.length, 15,
          reason: '원래 7열 + 추가 8열 = 15열');
      for (final f in ExtraFields.all) {
        expect(out.viewColumns, contains(f.label),
            reason: '${f.label} 열이 사라졌다');
      }
      // 원래 열 순서는 유지된다.
      expect(out.viewColumns.take(7).toList(), doc.columns);
    });

    test('추가항목 값이 각 행에 정확히 들어간다', () {
      final doc = _roster();
      final out = extraColumns(
        doc,
        source: _attendees(),
        keys: const {'transport', 'lodging'},
      );
      final iT = out.viewColumns.indexOf(ExtraFields.transport.label);
      final iL = out.viewColumns.indexOf(ExtraFields.lodging.label);
      expect(iT, greaterThanOrEqualTo(0));
      expect(iL, greaterThanOrEqualTo(0));
      expect(out.viewRows[0][iT], '대중교통');
      expect(out.viewRows[1][iT], '자차');
      expect(out.viewRows[0][iL], '숙박');
      expect(out.viewRows[1][iL], '비숙박');
    });

    test('원본 문서는 변하지 않는다 — 껐다 켜도 열이 중복되지 않는다', () {
      final doc = _roster();
      final before = doc.columns.length;
      extraColumns(doc, source: _attendees(), keys: const {'transport'});
      extraColumns(doc, source: _attendees(), keys: const {'transport'});
      expect(doc.columns.length, before);
    });
  });

  group('② 표가 잘리지 않는다 — 미리보기 렌더 회귀', () {
    test('열이 15개여도 인쇄 HTML 이 열 손실 없이 만들어진다', () {
      final doc = extraColumns(
        _roster(),
        source: _attendees(),
        keys: _filledKeys(_attendees()),
      );
      final html = buildMujiDoc(
        meta: DocMeta(title: doc.title, createdAt: '2026-10-31 19:00'),
        columns: doc.viewColumns,
        rows: [
          for (final r in doc.viewRows) [for (final c in r) DocCell(c)],
        ],
        rowLines: 2,
        maxCellLines: 2,
      );
      // 모든 열 헤더가 html 에 존재해야 한다(잘림 = 누락).
      for (final c in doc.viewColumns) {
        expect(html.contains(c), isTrue, reason: '열 "$c" 가 인쇄물에서 빠졌다');
      }
      expect('<table'.allMatches(html).length, 1);
    });
  });

  group('③ 이름줄(rowLines) — 좌측 이름 칸 세로 확장', () {
    test('rowLines 2·3 이 td 세로 패딩에 반영된다', () {
      String html(int rl) => buildMujiDoc(
        meta: DocMeta(title: 't', createdAt: '2026-10-31'),
        columns: const ['이름'],
        rows: const [
          [DocCell('홍길동')],
        ],
        rowLines: rl,
      );
      expect(html(1).contains('padding:9px 10px'), isTrue);
      expect(html(2).contains('padding:18px 10px'), isTrue);
      expect(html(3).contains('padding:27px 10px'), isTrue);
    });

    test('2줄방지와 셀 줄 수가 동시에 걸려도 표는 하나다', () {
      final html = buildMujiDoc(
        meta: DocMeta(title: 't', createdAt: '2026-10-31'),
        columns: const ['이름', '메일'],
        rows: const [
          [DocCell('홍길동'), DocCell('hong@example.com')],
        ],
        noWrapCols: const {0, 1},
        rowLines: 3,
        maxCellLines: 3,
      );
      expect('<table'.allMatches(html).length, 1);
      expect(html.contains('padding:27px 10px'), isTrue);
    });
  });

  group('ExtraFields 기본 선택 규칙', () {
    test('값이 있는 항목만 기본 노출 대상이 된다', () {
      final partial = <Map<String, dynamic>>[
        {'transport': '자차'},
      ];
      expect(_filledKeys(partial), {'transport'});
    });

    test('값이 하나도 없으면 전 항목을 켠다(빈 표 방지)', () {
      expect(_filledKeys(<Map<String, dynamic>>[<String, dynamic>{}]), isEmpty);
    });
  });
}
