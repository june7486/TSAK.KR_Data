/// **추가입력사항을 출력물에 붙이는 공용 도구**.
///
/// ## 요구 (원문 2026-10-31)
/// > "출력 미리보기시에도 추가항목 선택할 수 있도록 하고 실시간으로 미리보며
/// >  출력 할 수 있도록 해줘
/// >  항목이 많을 경우에는 가로줄을 하나 더 추가해서 두줄방지 되도록 할 수
/// >  있는 옵션도 추가해줘
/// >  그리고 추가항목별로 인원 확인 할 수 있는 출력 옵션도 추가해줘"
///
/// ## 왜 서비스로 뺐나
///  추가입력 항목을 출력에 붙이는 일은 **세 곳**에서 필요하다.
///   ① 실시간 미리보기(항목 체크 → 즉시 반영)
///   ② 실제 저장/인쇄(같은 항목이 그대로 나가야 함)
///   ③ 항목별 인원 현황 문서(별도 출력 옵션)
///  화면마다 조립하면 ①과 ②가 어긋나 "미리보기와 인쇄물이 다르다"는 문제가
///  다시 생긴다. 그래서 [extraColumns] 하나로 열을 붙이고, [extraHeadcountDoc]
///  하나로 인원 현황 문서를 만든다.
library;

import 'extra_fields.dart';
import 'table_export.dart';
import 'table_options.dart';

/// [TsakTableDoc] 에 **추가입력 항목 열**을 덧붙인 새 문서를 만든다.
///
/// [keys] 는 [ExtraField.key] 집합(예: `{'transport', 'lodging'}`).
/// 순서는 [ExtraFields.all] 정의 순서를 따른다(사용자가 고른 순서가 아니라
/// 참가신청서 순서 — 인쇄물마다 열 순서가 달라지면 혼란스럽다).
///
/// [source] 는 [TsakTableDoc.rows] 와 **1:1 로 대응하는** 참석자 원본 행 목록이다.
/// 열만 늘리고 행 수는 건드리지 않으므로, 옵션(열 선택·순서)으로 일부 행을
/// 숨긴 문서라도 정렬이 어긋나지 않는다.
TsakTableDoc extraColumns(
  TsakTableDoc doc, {
  required List<Map<String, dynamic>> source,
  required Set<String> keys,
}) {
  final picked = <ExtraField>[
    for (final f in ExtraFields.all)
      if (keys.contains(f.key)) f,
  ];
  if (picked.isEmpty) return doc;
  final cols = <String>[...doc.columns, for (final f in picked) f.label];
  final rows = <List<String>>[];
  for (var i = 0; i < doc.rows.length; i++) {
    final a = i < source.length ? source[i] : const <String, dynamic>{};
    rows.add(<String>[
      ...doc.rows[i],
      for (final f in picked) f.valueOf(a),
    ]);
  }
  // ⚠️ 옵션의 cols(선택·순서)가 그대로 남아 있으면 [viewColumns] 가 **원래
  //  열 인덱스만** 골라내므로 방금 붙인 추가항목 열이 통째로 사라진다.
  //  (증상: "추가항목 4개 선택" 인데 미리보기에 열이 안 보인다)
  //  기존 선택 순서를 유지한 채 새 열 인덱스를 **뒤에 덧붙여** 넘긴다.
  final o = doc.options;
  final List<int>? newCols;
  if (o == null || o.cols == null) {
    newCols = null; // 옵션 없음 → 전체 열 그대로
  } else {
    final base = o.cols!.where((i) => i >= 0 && i < doc.columns.length);
    newCols = <int>[
      ...base,
      for (var k = doc.columns.length; k < cols.length; k++) k,
    ];
  }
  return TsakTableDoc(
    title: doc.title,
    subtitle: doc.subtitle,
    description: doc.description,
    author: doc.author,
    extra: doc.extra,
    columns: cols,
    rows: rows,
    summary: doc.summary,
    footerLeft: doc.footerLeft,
    landscape: doc.landscape,
    options: o?.copyWith(cols: newCols),
    reportBlocks: doc.reportBlocks,
    template: doc.template,
  );
}

/// 항목별 인원을 **한 줄 요약**으로 만든다(합계란·CSV 꼬리말 공용).
///
/// 예: `이동 방법 — 자차 4 · 대중교통 2 · 미입력 1`
List<String> extraTallyLines(
  Iterable<Map<String, dynamic>> attendees, {
  bool includeMessage = false,
}) {
  final rows = attendees.toList();
  if (rows.isEmpty) return const <String>[];
  final out = <String>[];
  for (final f in ExtraFields.countable) {
    final t = ExtraFields.tally(f, rows);
    if (t.isEmpty) continue;
    final body = t.entries.map((e) => '${e.key} ${e.value}').join(' · ');
    out.add('${f.label} — $body');
  }
  if (includeMessage) {
    final n = rows.where((a) => ExtraFields.message.hasValue(a)).length;
    if (n > 0) out.add('운영진 전달사항 — $n명 작성');
  }
  return out;
}

/// **추가항목별 인원 현황** 문서 — 별도 출력 옵션.
///
/// ## 구성
///  · 선택지가 있는 항목(이동·숙박·도착)은 **값별 인원수**를 한 행씩.
///  · 자유 입력 항목(출발 장소·소요시간·동행자·주소)은 **값별 인원 + 명단**.
///  · 운영진 전달사항은 **작성 인원 + 내용 발췌**(가장 놓치면 안 되는 항목).
///
/// 열: `항목 | 구분 | 인원 | 명단`. 인원이 많은 순으로 정렬해 한눈에 보이게 한다.
TsakTableDoc extraHeadcountDoc({
  required String title,
  required String year,
  required List<Map<String, dynamic>> attendees,
  String footerLeft = '한국범스카우트중앙회 · 추가입력 현황',
}) {
  final rows = <List<String>>[];
  final total = attendees.length;

  for (final f in ExtraFields.all) {
    if (f.options.isNotEmpty) {
      final t = ExtraFields.tally(f, attendees);
      final entries = t.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries) {
        // 값 → 해당자 명단(최대 12명, 나머지는 '외 N명').
        final names = <String>[
          for (final a in attendees)
            if ('${a[f.key] ?? ''}'.trim() == e.key ||
                (('${a[f.key] ?? ''}'.trim().isEmpty) && e.key == '미입력'))
              _who(a),
        ];
        rows.add([f.label, e.key, '${e.value}명', _nameList(names)]);
      }
      continue;
    }
    // 자유 입력 — 값별 묶음.
    final map = ExtraFields.listOf(f, attendees);
    if (map.isEmpty) continue;
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in entries) {
      rows.add([f.label, e.key, '${e.value.length}명', _nameList(e.value)]);
    }
  }

  // 요약 — 숫자로 바로 확인할 수 있는 핵심 3개.
  final summary = <String>[
    '총 $total명 기준',
    ...extraTallyLines(attendees, includeMessage: true),
  ];

  return TsakTableDoc(
    title: '$year $title',
    subtitle: '추가입력 항목별 인원 현황 · $total명',
    description:
        '참가신청서의 추가 입력 사항을 항목별로 집계합니다. '
        '이동·숙박·도착은 선택지별 인원수, 출발장소·소요시간·동행자·주소는 '
        '값별 인원과 명단, 운영진 전달사항은 작성 인원과 내용을 보여줍니다.',
    author: '한국범스카우트중앙회',
    extra: {
      '행사': title,
      '참가': '$total명',
      '파일': 'TSAK_출력_$title 추가입력 현황.pdf',
    },
    columns: const ['항목', '구분', '인원', '명단'],
    rows: rows.isEmpty
        ? <List<String>>[
            ['(없음)', '', '0명', '추가입력 내용이 없습니다'],
          ]
        : rows,
    summary: summary,
    footerLeft: footerLeft,
    landscape: false,
    options: const TableOutputOptions(
      // 좁은 열이 두 줄로 접히지 않게 — 요구의 "두줄방지" 기본값.
      noWrap: {'항목', '구분', '인원'},
    ),
  );
}

/// 참석자 행 → 표기용 이름.
String _who(Map<String, dynamic> a) {
  final nm = '${a['name'] ?? ''}'.trim();
  if (nm.isNotEmpty) return nm;
  final no = '${a['number'] ?? ''}'.trim();
  return no.isEmpty ? '(이름없음)' : '#$no';
}

/// 이름 목록을 `김승수, 이승준 외 3명` 형태로 줄인다.
String _nameList(List<String> names) {
  if (names.isEmpty) return '';
  const lim = 12;
  if (names.length <= lim) return names.join(', ');
  return '${names.take(lim).join(', ')} 외 ${names.length - lim}명';
}
