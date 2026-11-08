/// 결산서 '항목 블록' 구성 모델.
///
/// ## 요구사항 (그대로)
/// "결산페이지 선택시 각 항목별로 취합된 데이터를 보여주고, 출력여부를 그 페이지
///  에서 선택할 수 있도록 하는 기능을 넣자. 그 페이지에서 어디에 넣을지도 항목별
///  위치 이동을 선택할 수 있도록 하며 미리보기 기능을 강화해서 출력시 보여지는
///  내용을 실시간으로 확인하면 편집 할 수 있도록 하자"
///
/// ## 설계
/// 결산서는 **블록(항목)의 순서 있는 목록**이다. 관리자는
///  ① 각 블록의 취합 데이터를 그 자리에서 보고
///  ② 블록별로 출력 포함/제외를 켜고 끄고
///  ③ 블록을 위/아래로 옮겨 출력 순서를 정하며
///  ④ 그 결과를 **실시간 미리보기**로 즉시 확인한다.
///
/// 화면 카드 · 미리보기 · 실제 출력문서가 **같은 데이터 소스**
/// ([SettlementBlockData])를 쓰므로 "보이는 것 = 인쇄되는 것"이 보장된다.
library;

import '../models/member.dart';
import 'attendee_roles.dart';
import 'donation_kinds.dart';
import 'output_templates.dart';
import 'event_settlement.dart';
import 'member_repository.dart';
import 'print_doc.dart';
import 'table_options.dart';

/// 결산서를 구성하는 항목 블록.
enum SettlementBlock {
  attendees('참가자 수', '직책별 인원과 합계'),
  income('수입', '참가비 · 후원금 · 기타수입'),
  sponsor('후원 내역', '현물 · 서비스 후원(수입 미포함)'),
  expenseCategory('지출 (분류별)', '행사비 · 제작비 등'),
  expenseAccount('지출 (계좌별)', '출금계좌 기준'),
  balance('잔액', '수입 − 지출');

  const SettlementBlock(this.label, this.hint);

  final String label;
  final String hint;

  static SettlementBlock? parse(String k) {
    for (final b in SettlementBlock.values) {
      if (b.name == k) return b;
    }
    return null;
  }
}

/// 한 블록의 취합 결과 — 화면 카드 / 미리보기 / 문서 출력 공용.
class SettlementBlockData {
  const SettlementBlockData({
    required this.block,
    required this.rows,
    required this.note,
    this.empty = false,
    this.details = const <String>[],
  });

  final SettlementBlock block;

  /// 3열 [항목, 금액·인원, 비고] 목록.
  /// (미리보기·문서에서 4열 표에 그대로 얹는다)
  final List<List<String>> rows;

  /// 블록 하단 한 줄 요약(선택).
  final String note;

  /// 데이터가 비어 있는가(카드에서 안내 문구 노출).
  final bool empty;

  /// 집계의 **근거가 된 원본 행** — 카드에서 펼쳐 확인한다.
  /// (요구: "각 항목별로 취합된 데이터를 보여주고")
  /// 예: `'2026-05-12 · 김철수 · 점심식사 12,000원 · 행사비'`
  final List<String> details;

  String get title => block.label;

  bool get hasDetails => details.isNotEmpty;

  /// 상세 내역을 **결산 표의 하위 행**으로 펼친다 — `['· 상세', 원본내용, '', '']`.
  ///
  /// ## 왜 필요한가 (요구: "후원내역 상세 항목, 지출 및 참가비 등도 상세 내역을
  ///  결산시 보여주고 … 출력여부를 상세까지 선택")
  /// [details] 는 `'2026-05-12 · 김철수 · 점심식사 12,000원 · 행사비'` 같은
  /// 한 줄 문자열이다. 결산 표는 `[항목, 금액/인원, 비고, 추가]` 4칸이므로
  /// 원본 줄을 **2번째 칸**에 넣고 1번째 칸에 `· 상세` 표시를 둔다.
  /// (미리보기·PDF·HTML 이 모두 이 함수를 쓰므로 화면=출력이 유지된다)
  ///
  /// [max] 를 주면 상세 줄 수를 제한한다(너무 길어지는 것 방지).
  ///
  /// ## [keep] — 상세 줄 **하나하나**를 고를 수 있게 한다
  /// (요구 2026-10-27) "모든 항목의 우측 끝에, 그 항목에 체크박스를 넣어서
  ///  출력시 포함할지 여부를 선택할 수 있도록 … 기본값은 모두 선택"
  /// → 블록 통째로만 켜고 끄면 "3건 중 1건만 빼고 출력" 같은 실제 회계
  ///   요구를 못 맞춘다. [keep] 이 주어지면 그 인덱스만 남긴다.
  ///   `max` 는 **남긴 뒤의 개수** 기준으로 센다.
  List<List<String>> detailRows({
    int max = 40,
    bool Function(int index)? keep,
  }) {
    if (details.isEmpty) return const [];
    final out = <List<String>>[];
    var kept = 0;
    var skipped = 0;
    var overflow = 0;
    for (var i = 0; i < details.length; i++) {
      if (keep != null && !keep(i)) {
        skipped++;
        continue;
      }
      if (kept >= max) {
        // 지면 제한으로 잘린 건수 — 사용자가 뺀 것과 **다르게** 표기한다.
        overflow++;
        continue;
      }
      out.add(['· 상세', details[i], '', '']);
      kept++;
    }
    // 두 사유를 구분해 남긴다. 예전에는 둘 다 '출력에서 제외'라고 적어
    //  사용자가 빼지도 않은 건이 빠진 것처럼 읽혔다.
    if (overflow > 0) {
      out.add(['· 상세', '… 외 $overflow건 (지면상 생략 — 미리보기에서 전체)', '', '']);
    }
    if (skipped > 0) {
      out.add(['· 상세', '… $skipped건은 출력에서 제외(사용자 선택)', '', '']);
    }
    return out;
  }

  /// 상세 줄 중 몇 건이 출력에 포함되는가([keep] 기준).
  int keptDetailCount({bool Function(int index)? keep}) {
    if (keep == null) return details.length;
    var n = 0;
    for (var i = 0; i < details.length; i++) {
      if (keep(i)) n++;
    }
    return n;
  }
}

/// 결산서 블록 배치 — 순서 + 출력 포함 여부 + 서식(글씨·줄간격·용지·두줄방지).
class SettlementLayout {
  SettlementLayout({
    List<SettlementBlock>? order,
    Set<SettlementBlock>? excluded,
    this.fontScale = 1.0,
    this.rowSpace = 1.0,
    this.landscape = false,
    this.noWrap = true,
    this.showNotes = true,
    this.showMemo = true,
    this.reportStyle = true,
    this.template = DocTemplate.report,
    Set<SettlementBlock>? detailOff,
    Set<String>? detailLineOff,
    Set<String>? rowOff,
    this.detailMax = 40,
  }) : order = order ?? [...SettlementBlock.values],
       excluded = excluded ?? <SettlementBlock>{},
       detailOff = detailOff ?? <SettlementBlock>{},
       detailLineOff = detailLineOff ?? <String>{},
       rowOff = rowOff ?? <String>{};

  /// 출력 순서.
  List<SettlementBlock> order;

  /// 출력에서 빼기로 한 블록.
  Set<SettlementBlock> excluded;

  // ── 요구: "결산에 후원내역 상세 항목, 지출 및 참가비 등도 상세 내역을
  //    결산시 보여주고 미리보기 창에서 출력여부를 상세까지 선택할 수 있도록"
  //
  //  블록(소제목)만 켜고 끄면 '합계만 있는 결산'이 된다. 실제로 회계를
  //  확인하는 사람이 보고 싶은 것은 **그 합계가 어디서 나왔는가**이다.
  //  그래서 블록마다 '상세 내역'(원본 행)을 표 아래에 붙일 수 있게 하고,
  //  미리보기 편집창에서 블록별로 켜고 끈다.
  //
  //  ## 설계 (3-상태의 함정을 피한다)
  //  '전체 스위치(showDetails) + 개별 예외(detailOff)' 2개를 두면
  //   (전체 off, 개별 on) 같은 **모순 조합**이 생겨 "전체를 껐는데 한 블록만
  //   켜져 있는" 상태가 만들어진다(실제로 그렇게 구현했다가 테스트에서 잡힘).
  //  → 진실원을 **하나**로 둔다. [detailOff] 만이 "이 블록은 상세를 빼라"를
  //   뜻하고, 전체 스위치([setAllDetails])는 그 집합을 통째로 채우거나 비운다.
  //   그래서 언제나 일관된 상태만 존재한다.

  /// 블록 하단 한 줄 설명(note)을 붙일지.
  bool showNotes;

  /// 상세 내역을 **빼기로 한** 블록 — 이 집합 하나가 진실원이다.
  Set<SettlementBlock> detailOff;

  // ── [요구 2026-10-27] 상세 줄 **하나하나**의 출력 여부 ──────────────
  //
  //  "결산 기본페이지에도 출력 미리보기 상세항목처럼 상세내역을 노출할 것
  //   (모든 항목의 우측 끝에, 그 항목에 체크박스를 넣어서 출력시 포함할지
  //    여부를 선택할 수 있도록 직관적으로 만들 것, 기본값은 모두 선택)"
  //
  //  ## 왜 필요한가
  //   종전에는 '블록(소제목)'과 '블록의 상세 전체'만 켜고 끌 수 있었다.
  //   실제 회계에서는 "후원 3건 중 이 1건은 내부 사정으로 빼고 인쇄" 같은
  //   요구가 흔한데, 블록 전체를 끄면 나머지 2건까지 사라졌다.
  //
  //  ## 설계 (예외만 저장 — 기본값은 '전부 포함')
  //   수천 건짜리 원본 행 목록을 **포함 목록으로 저장하면** 나중에 새 거래가
  //   추가됐을 때 목록에 없어서 **자동으로 빠진다**(조용한 데이터 누락).
  //   그래서 **제외된 줄만** [detailLineOff] 에 담는다.
  //     · 새 줄이 생기면 → 목록에 없음 → 자동 포함 (기본값 = 모두 선택 ✅)
  //     · 사용자가 끄면      → 그 (블록, 줄) 쌍만 기록
  //   키는 `'<블록name>#<줄인덱스>'`. 블록 안에서의 순서가 바뀌면 어긋날 수
  //   있지만, 상세 줄은 원본 재무 행에서 **결정적으로** 생성되므로
  //   같은 데이터면 같은 순서다(재무 탭에서 행을 지우면 그 아래가 당겨지는데,
  //   이때도 '제외' 표시가 남는 편이 '몰래 포함'보다 안전하다).
  //
  //  ## 블록 전체 스위치([detailOff])와의 관계
  //   `detailOff` = 그 블록의 **모든** 상세를 끈다(기존 동작, 유지).
  //   `detailLineOff` = 블록은 켜되 **일부 줄만** 끈다(새 기능).
  //   둘은 독립이며, 한 줄이 실제로 출력되려면 **둘 다** 통과해야 한다.
  Set<String> detailLineOff;

  /// (블록, 줄) 제외 키.
  static String lineKey(SettlementBlock b, int index) => '${b.name}#$index';

  /// 이 블록의 [index]번째 상세 줄을 출력하는가.
  ///
  /// 블록 단위 스위치([showsDetail])가 꺼져 있으면 무조건 false.
  bool showsDetailLine(SettlementBlock b, int index) =>
      showsDetail(b) && !detailLineOff.contains(lineKey(b, index));

  /// 상세 줄 하나를 켜고 끈다.
  void toggleDetailLine(SettlementBlock b, int index) {
    final k = lineKey(b, index);
    if (detailLineOff.contains(k)) {
      detailLineOff.remove(k);
    } else {
      detailLineOff.add(k);
    }
  }

  /// 이 블록의 상세 줄을 **전부** 포함/제외한다(줄 단위 예외를 초기화).
  void setBlockDetailLines(SettlementBlock b, bool on, int count) {
    if (on) {
      detailLineOff.removeWhere((k) => k.startsWith('${b.name}#'));
    } else {
      for (var i = 0; i < count; i++) {
        detailLineOff.add(lineKey(b, i));
      }
    }
  }

  /// 블록 [b] 에서 실제로 출력되는 상세 줄 수.
  int visibleDetailCount(SettlementBlock b, int total) {
    if (!showsDetail(b)) return 0;
    var n = 0;
    for (var i = 0; i < total; i++) {
      if (!detailLineOff.contains(lineKey(b, i))) n++;
    }
    return n;
  }

  /// 블록 [b] 의 상세 줄에 넘길 [keep] 함수 — 없으면 null(전부 포함).
  bool Function(int index)? lineKeeper(SettlementBlock b) {
    if (!showsDetail(b)) return null;
    final prefix = '${b.name}#';
    final offs = <int>{};
    for (final k in detailLineOff) {
      if (k.startsWith(prefix)) {
        final n = int.tryParse(k.substring(prefix.length));
        if (n != null) offs.add(n);
      }
    }
    if (offs.isEmpty) return null;
    return (i) => !offs.contains(i);
  }

  /// 줄 단위로 하나라도 제외된 상세가 있는가(배지 표기용).
  bool get hasLineFilter => detailLineOff.isNotEmpty;

  // ── [요구 2026-10-27] **표 행**의 출력 여부 ─────────────────────────
  //
  //  "나머지 항목에도 체크박스를 넣어줘요"
  //
  //  ## 배경
  //   종전 체크박스는 `상세 내역`(원본 행 목록)에만 붙어 있었다. 그런데
  //   `수입` 블록처럼 **표가 한 줄(합계)뿐**인 블록은 상세 자체가 없어서
  //   (또는 사용자가 상세를 꺼서) 체크박스가 **하나도 안 보였다**.
  //   사용자 화면에서 '참가자 수'에는 체크가 보이는데 '수입'에는 안 보여
  //   "나머지 항목에도 체크박스를 넣어줘요" 가 나온 이유다.
  //
  //  ## 설계 (상세와 동일 — 예외만 저장)
  //   기본값은 '전부 포함'. 사용자가 끈 (블록, 행) 쌍만 기록한다.
  //   새 행이 추가되면 목록에 없으므로 자동 포함 — 조용한 누락이 없다.
  //   키는 `'<블록name>r<행인덱스>'` (상세 키 `… #N` 과 접두가 겹치지 않게 r).
  Set<String> rowOff;

  /// (블록, 표 행) 제외 키.
  static String rowKey(SettlementBlock b, int index) => '${b.name}r$index';

  /// 이 블록의 [index]번째 **표 행**을 출력하는가.
  bool showsRow(SettlementBlock b, int index) =>
      showsDetail(b) && !rowOff.contains(rowKey(b, index));

  /// 표 행 하나를 켜고 끈다.
  void toggleRow(SettlementBlock b, int index) {
    final k = rowKey(b, index);
    if (rowOff.contains(k)) {
      rowOff.remove(k);
    } else {
      rowOff.add(k);
    }
  }

  /// 이 블록의 표 행을 **전부** 포함/제외한다.
  void setBlockRows(SettlementBlock b, bool on, int count) {
    if (on) {
      rowOff.removeWhere((k) => k.startsWith('${b.name}r'));
    } else {
      for (var i = 0; i < count; i++) {
        rowOff.add(rowKey(b, i));
      }
    }
  }

  /// 블록 [b] 에서 실제로 출력되는 표 행 수.
  int visibleRowCount(SettlementBlock b, int total) {
    if (!showsDetail(b)) return 0;
    var n = 0;
    for (var i = 0; i < total; i++) {
      if (!rowOff.contains(rowKey(b, i))) n++;
    }
    return n;
  }

  /// 표 행 목록을 걸러낸다 — 제외가 없으면 원본 그대로(불필요한 복사 방지).
  List<List<String>> filterRows(SettlementBlock b, List<List<String>> rows) {
    if (rowOff.isEmpty) return rows;
    final out = <List<String>>[];
    for (var i = 0; i < rows.length; i++) {
      if (!rowOff.contains(rowKey(b, i))) out.add(rows[i]);
    }
    return out;
  }

  /// 행 단위로 하나라도 제외된 표가 있는가(배지 표기용).
  bool get hasRowFilter => rowOff.isNotEmpty;

  /// ── [요구 2026-10-27] 상세 내역 출력 상한 ───────────────────────────
  /// "상세항목을 선택하면 모든 상세가 다 보여지는 기능으로 하면 좋겠음"
  ///
  /// 종전 상한은 PDF 빌더에 `detailMax = 40` 으로 **하드코딩**돼 있었다.
  /// 41건째부터는 `… 외 N건 (출력에서 제외)` 로 잘려, 사용자가 상세를
  /// 아무리 켜도 **모든 상세를 볼 방법이 없었다**. 이제 값을 화면에서
  /// 정한다(기본 40, '전체' 선택 시 99999).
  int detailMax;

  /// 상세 상한 없음(전부 출력).
  static const int detailMaxAll = 99999;

  /// 상세 내역을 **전체로** 붙이는가(어느 한 블록이라도 켜져 있으면 true).
  bool get showDetails => order.any((b) => !detailOff.contains(b));

  /// 이 블록의 상세 내역을 출력하는가.
  bool showsDetail(SettlementBlock b) => !detailOff.contains(b);

  /// 블록별 상세 내역 켜기/끄기 — 그 블록만 바꾼다(다른 블록 불변).
  void toggleDetail(SettlementBlock b) {
    if (detailOff.contains(b)) {
      detailOff.remove(b);
    } else {
      detailOff.add(b);
    }
  }

  /// 상세 내역 전체 켜기/끄기.
  void setAllDetails(bool on) {
    if (on) {
      detailOff.clear();
    } else {
      detailOff.addAll(SettlementBlock.values);
    }
  }

  /// 상세가 하나라도 켜져 있는가(배지 표기용).
  bool get anyDetail => included.any(showsDetail);

  /// 상세를 붙이는 블록 수.
  int get detailCount => included.where(showsDetail).length;

  // ── 서식 — 미리보기에서 바로 조절하고 **출력 문서에도 그대로** 적용된다.
  //    (요구: "미리보기 기능을 강화해서 출력시 보여지는 내용을 실시간으로
  //     확인하면 편집 할 수 있도록 하자")
  //    종전에는 미리보기 슬라이더가 화면에만 반영되고 실제 문서는 기본값으로
  //    나가는 불일치가 있었다. 서식을 [SettlementLayout] 에 담아
  //    화면·미리보기·문서가 **같은 값**을 쓰게 한다.

  /// 글씨 배율(0.86 ~ 1.26).
  double fontScale;

  /// 줄 간격 배율(0.72 ~ 1.5).
  double rowSpace;

  /// 가로(넓은) 용지.
  bool landscape;

  /// 두 줄 방지.
  bool noWrap;

  /// 상세 내역에 **메모**를 함께 보여줄지.
  ///
  /// (요구) "결산시에도 메모 내역을 추가해서 보여주고, 항목을 선택할 수 있도록"
  /// → 메모는 원본 재무 행의 자유 입력란이라 길이·형식이 제각각이다.
  ///   회계 보고서에 넣을지 말지는 **관리자가 고른다**(기본 켜짐).
  bool showMemo;

  /// 보고서형 출력(무인양품 표 대신 블록 제목 띠 + 4열 표)을 쓸지.
  ///
  /// (요구) "pdf 출력물의 형태는 결산의 경우 기존 무인양품 스타일을 버리고,
  ///  미리보기 항목의 내용을 참조해서 항목별로 보기좋게 출력 … 계산서처럼
  ///  보여지기보다는 보고서처럼"
  /// → true 면 [SettlementPaperView] 와 **같은 그래픽**(블록 컬러 띠·4열)으로
  ///   PDF 를 만든다. 화면 미리보기 = PDF 가 된다.
  bool reportStyle;

  /// 출력 템플릿(6종) — 블록 그래픽의 **모양**.
  ///
  /// (요구) "출력폼에 대한 옵션을 6가지 정도 템플릿을 만들어서 선택"
  /// [reportStyle] 이 false 면 이 값은 무시된다(평평한 표).
  DocTemplate template;

  bool includes(SettlementBlock b) => !excluded.contains(b);

  /// 실제 출력에 포함되는 블록(순서 유지).
  List<SettlementBlock> get included => order.where(includes).toList();

  int get includedCount => included.length;

  bool get isFiltered => excluded.isNotEmpty;

  void toggle(SettlementBlock b) {
    if (excluded.contains(b)) {
      excluded.remove(b);
    } else {
      excluded.add(b);
    }
  }

  void includeAll() => excluded.clear();

  void excludeAll() => excluded.addAll(SettlementBlock.values);

  /// 위로 한 칸. 이미 맨 위면 false.
  bool moveUp(SettlementBlock b) {
    final i = order.indexOf(b);
    if (i <= 0) return false;
    order.removeAt(i);
    order.insert(i - 1, b);
    return true;
  }

  /// 아래로 한 칸. 이미 맨 아래면 false.
  bool moveDown(SettlementBlock b) {
    final i = order.indexOf(b);
    if (i < 0 || i >= order.length - 1) return false;
    order.removeAt(i);
    order.insert(i + 1, b);
    return true;
  }

  /// 맨 위로.
  bool moveTop(SettlementBlock b) {
    final i = order.indexOf(b);
    if (i <= 0) return false;
    order.removeAt(i);
    order.insert(0, b);
    return true;
  }

  /// 맨 아래로.
  bool moveBottom(SettlementBlock b) {
    final i = order.indexOf(b);
    if (i < 0 || i >= order.length - 1) return false;
    order.removeAt(i);
    order.add(b);
    return true;
  }

  SettlementLayout copy() => SettlementLayout(
    order: [...order],
    excluded: {...excluded},
    fontScale: fontScale,
    rowSpace: rowSpace,
    landscape: landscape,
    noWrap: noWrap,
    showNotes: showNotes,
    showMemo: showMemo,
    reportStyle: reportStyle,
    template: template,
    detailOff: {...detailOff},
    detailLineOff: {...detailLineOff},
    rowOff: {...rowOff},
    detailMax: detailMax,
  );

  /// 서식만 기본값으로.
  void resetStyle() {
    fontScale = 1.0;
    rowSpace = 1.0;
    landscape = false;
    noWrap = true;
    showNotes = true;
    showMemo = true;
    reportStyle = true;
    template = DocTemplate.report;
    detailOff.clear();
    detailLineOff.clear();
    rowOff.clear();
  }

  /// 서식이 기본값과 다른가(배지 표기용).
  bool get isStyled =>
      (fontScale - 1.0).abs() > 0.001 ||
      (rowSpace - 1.0).abs() > 0.001 ||
      landscape ||
      !noWrap ||
      detailOff.isNotEmpty ||
      detailLineOff.isNotEmpty ||
      !showNotes ||
      !showMemo ||
      !reportStyle ||
      template != DocTemplate.report;

  /// 서식 요약 — 예: '가로 · 글씨 108% · 줄간격 92%'.
  String get styleBadge {
    final parts = <String>[];
    parts.add(landscape ? '가로' : '세로');
    if ((fontScale - 1.0).abs() > 0.001) {
      parts.add('글씨 ${(fontScale * 100).round()}%');
    }
    if ((rowSpace - 1.0).abs() > 0.001) {
      parts.add('줄간격 ${(rowSpace * 100).round()}%');
    }
    if (!noWrap) parts.add('두줄허용');
    parts.add(anyDetail ? '상세 $detailCount/$includedCount' : '상세 없음');
    if (hasLineFilter) {
      final filterOff = detailLineOff.length;
      parts.add('상세줄 $filterOff개 제외');
    }
    if (!showNotes) parts.add('설명 없음');
    if (!showMemo) parts.add('메모 없음');
    if (reportStyle) {
      parts.add(template.label);
    } else {
      parts.add('표형');
    }
    return parts.join(' · ');
  }

  /// 출력 문서(TsakTableDoc)에 넘길 옵션 — **미리보기 서식을 그대로** 옮긴다.
  TableOutputOptions toOutputOptions() => TableOutputOptions(
    fontSize: fontScale >= 1.14
        ? TsakFontSize.large
        : (fontScale <= 0.9 ? TsakFontSize.small : TsakFontSize.normal),
    rowSpace: rowSpace >= 1.2
        ? TsakRowSpace.loose
        : (rowSpace <= 0.85 ? TsakRowSpace.tight : TsakRowSpace.normal),
    landscape: landscape,
    noWrap: noWrap ? const {'구분', '항목', '금액/인원'} : const <String>{},
  );

  /// 저장/복원용 — 순서를 문자열 목록으로.
  List<String> toJson() => [for (final b in order) b.name];
  List<String> excludedJson() => [for (final b in excluded) b.name];
  List<String> detailOffJson() => [for (final b in detailOff) b.name];
  List<String> detailLineOffJson() => [...detailLineOff];
  static SettlementLayout fromJson(
    List<dynamic>? order,
    List<dynamic>? excluded, {
    double fontScale = 1.0,
    double rowSpace = 1.0,
    bool landscape = false,
    bool noWrap = true,
    bool showDetails = true,
    bool showNotes = true,
    bool showMemo = true,
    bool reportStyle = true,
    String template = 'report',
    List<dynamic>? detailOff,
    List<dynamic>? detailLineOff,
  }) {
    final ord = <SettlementBlock>[];
    for (final e in order ?? const []) {
      final b = SettlementBlock.parse('$e');
      if (b != null && !ord.contains(b)) ord.add(b);
    }
    // 누락된 블록은 뒤에 붙인다(신규 블록 자동 편입).
    for (final b in SettlementBlock.values) {
      if (!ord.contains(b)) ord.add(b);
    }
    final exc = <SettlementBlock>{};
    for (final e in excluded ?? const []) {
      final b = SettlementBlock.parse('$e');
      if (b != null) exc.add(b);
    }
    final off = <SettlementBlock>{};
    for (final e in detailOff ?? const []) {
      final b = SettlementBlock.parse('$e');
      if (b != null) off.add(b);
    }
    // 옛 저장값 호환 — showDetails=false 였으면 '전체 상세 끔'으로 복원한다.
    if (!showDetails) off.addAll(SettlementBlock.values);
    final lineOff = <String>{};
    for (final e in detailLineOff ?? const []) {
      final s = '$e'.trim();
      if (s.contains('#')) lineOff.add(s);
    }
    return SettlementLayout(
      order: ord,
      excluded: exc,
      fontScale: fontScale,
      rowSpace: rowSpace,
      landscape: landscape,
      noWrap: noWrap,
      showNotes: showNotes,
      showMemo: showMemo,
      reportStyle: reportStyle,
      template: DocTemplate.parse(template),
      detailOff: off,
      detailLineOff: lineOff,
    );
  }
}

/// 결산 데이터 → 블록별 취합 결과 목록.
///
/// [fees]·[expenses] 는 **출력에 포함하기로 고른 행만** 넘겨받는다
/// (재무 탭의 '출력 선택'과 동일한 규칙을 결산에도 적용).
///
/// 각 행은 `[항목, 금액·인원, 비고]` 3칸을 채운다 — 화면 카드·미리보기·
/// 문서가 모두 같은 3칸을 쓰므로 "나열"이 아니라 **정리된 표**가 된다.
/// (요구: "행사비 결산은 일목요연하게 세부항목별로 보여지게 해야 함")
class SettlementBuilder {
  const SettlementBuilder._();

  // ══════════════════════════════════════════════════════════════════
  // 연맹 / 단위대 — **행에 없으면 명부에서 채운다**.
  //  참석자 행은 unit 만 갖고 있는 경우가 많다(league 없음).
  //  요구 순서(… / 등급 / 연맹, 단위대)를 지키려면 연맹이 필요하다.
  // ══════════════════════════════════════════════════════════════════
  static Member? _memberOf(Map<String, dynamic> a) {
    // 신원 키 → 회원 조회. 전역 리포지토리를 쓴다(있으면).
    final repo = MemberRepository.instanceOrNull;
    if (repo == null) return null;
    final key = '${a['identityKey'] ?? ''}'.trim();
    if (key.startsWith('reg:')) {
      final d = key.substring(4);
      for (final c in repo.allUnscoped()) {
        if (c.phoneDigits == d) return c;
      }
    } else if (key.startsWith('tsak:')) {
      final d = key.substring(5);
      for (final c in repo.allUnscoped()) {
        if (!c.isRegular &&
            c.corps != 'eunha' &&
            c.number.replaceAll(RegExp(r'[^0-9]'), '') == d) {
          return c;
        }
      }
    } else if (key.startsWith('eunha:')) {
      final d = key.substring(6).replaceAll(RegExp(r'[^0-9]'), '');
      for (final c in repo.allUnscoped()) {
        if (c.corps == 'eunha' &&
            c.number.replaceAll(RegExp(r'[^0-9]'), '') == d) {
          return c;
        }
      }
    }
    return null;
  }

  static String _leagueOf(Map<String, dynamic> a) {
    final direct = '${a['league'] ?? a['leagueName'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct;
    return _memberOf(a)?.league.trim() ?? '';
  }

  static String _unitOf(Map<String, dynamic> a) {
    final direct = '${a['unit'] ?? a['unitText'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct;
    return _memberOf(a)?.unit.trim() ?? '';
  }

  /// 참석자 한 줄 — **표현 순서 고정**.
  ///
  /// `이름 / 범인가번호 / 은하인가번호 / 등급 / 연맹·단위대`
  ///
  /// ## [요구 2026-10-29]
  ///  "일반 회원은 범인가자정보가 아니라, 서포터즈 인가자 정보로 표시함
  ///   상세내역에 표현순서: 이름 / 범인가번호 / 은하인가번호 /
  ///   등급(리더,로버,벤처,스카우트,컵,비버,일반,서포터츠 등) / 연맹, 단위대"
  static String _attendeeDetailLine(
    Map<String, dynamic> a, {
    String leagueOf = '',
    String unitOf = '',
  }) =>
      SettlementLine.of(
        a,
        league: leagueOf,
        unit: unitOf,
      );

  static Map<SettlementBlock, SettlementBlockData> build({
    required EventSettlement settlement,
    required List<Map<String, dynamic>> fees,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> attendees,
    String Function(int) won = _wonDefault,

    /// (요구) 상세 내역에 **메모**를 넣을지 — 미리보기에서 켜고 끈다.
    bool memo = true,
  }) {
    final out = <SettlementBlock, SettlementBlockData>{};

    // ── ① 참가자 수 (8종 + 합계, 필수) ────────────────────────────────
    //   3번째 칸은 비워 둔다 — 화면 카드가 그 자리에 인원 비율 막대를 그린다.
    final bd = settlement.attendeeCount;
    // [요구 2026-11-07] 집계는 **배타적**이다 — 한 사람은 한 항목에만.
    //  인가번호 보유자는 인가자에만 들어가고 리더·로버 등에는 들어가지 않는다.
    //  그래서 항목 합 == 합계(bd.total) 가 항상 성립한다.
    //  · 인가자 줄: '직책 보유 N명 포함' — 리더가 0명인 이유를 오해하지 않게.
    //  · 합계 줄: 검증에 실패하면 경고를 띄운다(숫자가 안 맞으면 바로 보이게).
    final attRows = <List<String>>[
      for (final e in bd.ordered)
        [
          e.key,
          '${e.value}명',
          // 인가자·리더 줄에만 '왜 이 숫자인지' 근거를 붙인다.
          e.key == '인가자'
              ? bd.ivgaNote
              : e.key == AttendeeRole.leader
              ? bd.leaderNote
              : '',
        ],
      [
        '합계',
        '${bd.total}명',
        bd.isConsistent ? '' : '⚠ 항목 합 ${bd.rawItemSum}명과 불일치',
      ],
    ];
    out[SettlementBlock.attendees] = SettlementBlockData(
      block: SettlementBlock.attendees,
      rows: attRows,
      note: bd.summaryLine,
      empty: attendees.isEmpty,
      details: [
        // [2026-10-29] 인가번호 칸에 이름/전화번호가 들어 있던 행이
        //  '인가 류호준' 처럼 표시되던 문제를 없앴다.
        //  · 진짜 인가번호(짧은 숫자/G표기)일 때만 '인가 N'
        //  · 일반회원은 '일반 #전화번호'
        for (final a in attendees)
          _attendeeDetailLine(
            a,
            leagueOf: _leagueOf(a),
            unitOf: _unitOf(a),
          ),
      ],
    );

    // ── ② 수입 (참가비 + 후원금만 수입) ───────────────────────────────
    //
    // [버그 수정 turn 79] '참가비 N명 납부' 의 N 이 **9** 로 나오던 문제.
    //
    // ## 실제 증상 (사용자 스크린샷)
    //   참가비 600,000원 / **9명 납부** — 실제 참가자는 6명 (10만원 × 6)
    //   후원금 300,000원 / 3건
    //   상세 내역 9건
    //
    // ## 원인
    //   종전: fees.where((e) => e.amount > 0).length
    //   `fees` 에는 참가비·후원금·기타수입이 **모두** 들어 있어서
    //   참가비 6 + 후원금 3 = 9 가 됐다. 금액(feeTotal)은 '참가비'만
    //   합산했기 때문에 **금액과 인원이 다른 기준**으로 계산되어
    //   "60만원인데 9명" 이라는 모순이 생겼다.
    //
    // ## 수정
    //   인원수도 금액과 **같은 조건**('참가비' 행)으로 센다.
    //   후원금은 아래 '후원금' 줄에만 집계되고 참가비에 섞이지 않는다.
    final payers = settlement.feePayerCount;
    final cashDonors = settlement.fees
        .where(
          (e) =>
              DonationKind.parse(e.category) == DonationKind.cash &&
              e.amount > 0,
        )
        .length;
    // 금액이 인원으로 나누어떨어지면 근거를 함께 보여 준다(예: 10만원 × 6명).
    final per = settlement.feePerPayer;
    final feeNote = payers == 0
        ? '납부자 없음'
        : per > 0
        ? '$payers명 납부 · 1인 ${won(per)}'
        : '$payers명 납부';
    final incRows = <List<String>>[
      ['참가비', won(settlement.feeTotal), feeNote],
      [
        '후원금',
        won(settlement.cashDonationTotal),
        cashDonors == 0 ? '현금 후원 없음' : '$cashDonors건',
      ],
      [
        '기타수입',
        won(settlement.otherIncome),
        settlement.otherIncome == 0 ? '-' : '참가비·후원금 외',
      ],
      ['수입 합계', won(settlement.incomeTotal), ''],
    ];
    out[SettlementBlock.income] = SettlementBlockData(
      block: SettlementBlock.income,
      rows: incRows,
      note: '수입 = 참가비 + 후원금 + 기타수입 (후원 현물은 수입에 넣지 않음)',
      empty: settlement.incomeTotal == 0,
      details: [
        for (final f in fees)
          if (DonationKind.parse(f['category'] as String? ?? '').isIncome ||
              '${f['category'] ?? ''}'.trim() == '참가비' ||
              '${f['category'] ?? ''}'.trim() == '기타수입')
            _moneyLine(f, won, memo: memo),
      ],
    );

    // ── ③ 후원 내역 (후원금 + 현물·서비스) ─────────────────────────────
    //
    // [요구 turn 79] "참가비와 후원금은 **구분**해 주고, 후원금은 **후원 항목**에
    //  넣어서 금액을 집계하도록 할 것"
    //
    // ## 종전 문제
    //   이 블록은 `sponsorRows`(현물·서비스)만 그렸다. 그래서 후원금
    //   (현금) 300,000원은 위 '수입' 블록에만 나오고 **후원 내역에는
    //   보이지 않았다**. 후원 전체를 한눈에 볼 수 없었다.
    //
    // ## 수정
    //   이 블록 첫 줄에 **후원금(현금)** 을 넣어 후원 전체를 집계한다.
    //   · 후원금은 **수입에도 포함**되므로 그 줄에 '수입 포함' 이라고 명시한다.
    //   · 현물은 종전대로 '수입 미포함'.
    //   · `수입 합계`는 `feeTotal + cashDonationTotal + otherIncome` 로
    //     따로 계산되므로 **이중 계상되지 않는다**(이 블록은 표시 전용).
    //   · '후원 합계' 줄은 현물 기준임을 라벨에 분명히 적는다.
    final donations = DonationSummary(fees.map(DonationRow.fromMap).toList());
    final cashRows = donations.cashRows;
    final cashCash = donations.cashTotal;

    final spRows = <List<String>>[];
    // ① 후원금(현금) — 수입에 포함되는 유일한 후원 항목.
    if (cashRows.isNotEmpty || cashCash > 0) {
      spRows.add([
        DonationKind.cash.label,
        won(cashCash),
        '${cashRows.length}건 · 수입 포함',
      ]);
    }
    // ② 현물·서비스 후원 — 수입 미포함.
    for (final e in donations.byKind.entries) {
      if (e.value.$1 == 0 && e.value.$2 == 0) continue;
      final cnt = donations.sponsorRows
          .where((r) => r.kind.label == e.key)
          .length;
      spRows.add([e.key, _cashValue(e.value.$1, e.value.$2, won), '$cnt건']);
    }
    if (donations.sponsorRows.isNotEmpty) {
      spRows.add([
        '현물 후원 합계',
        _cashValue(
          donations.sponsorCashTotal,
          donations.sponsorValueTotal,
          won,
        ),
        '${donations.sponsorCount}건 · 수입 미포함',
      ]);
    }
    if (spRows.isEmpty) {
      spRows.add(['후원 내역', '없음', '']);
    }
    final hasSponsor = cashRows.isNotEmpty || donations.sponsorRows.isNotEmpty;
    out[SettlementBlock.sponsor] = SettlementBlockData(
      block: SettlementBlock.sponsor,
      rows: spRows,
      // 현물이 없으면 '현물 0건 — 참고 합계 -' 같은 꼬리를 붙이지 않는다.
      note: hasSponsor
          ? <String>[
              '후원금 ${cashRows.length}건(수입 포함)',
              if (donations.sponsorCount > 0)
                '현물 ${donations.sponsorCount}건(수입 미포함) — 참고 합계 '
                    '${_cashValue(donations.sponsorCashTotal, donations.sponsorValueTotal, won)}',
            ].join(' · ')
          : '후원 내역이 없습니다',
      empty: !hasSponsor,
      details: [
        // 후원금(현금) 먼저 — 참가비와 섞이지 않게 분리해서 보여 준다.
        for (final r in cashRows)
          [
            r.name.isEmpty ? '(후원자 미입력)' : r.name,
            DonationKind.cash.label,
            if (r.item.isNotEmpty) r.item,
            r.displayAmount,
            if (memo) _memoPart(r.memo),
          ].where((e) => e.isNotEmpty).join(' · '),
        // 현물·서비스 후원.
        for (final r in donations.sponsorRows)
          [
            r.name.isEmpty ? '(후원자 미입력)' : r.name,
            r.kind.label,
            if (r.item.isNotEmpty) r.item,
            r.displayAmount,
            // (요구) 후원자·후원금·후원물품의 **메모**도 상세에 함께.
            if (memo) _memoPart(r.memo),
          ].where((e) => e.isNotEmpty).join(' · '),
      ],
    );

    // ── ④ 지출 (분류별) ──────────────────────────────────────────────
    final byCat = settlement.expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final catRows = <List<String>>[
      if (byCat.isEmpty)
        ['지출', '없음', '']
      else
        for (final e in byCat)
          [
            e.key,
            won(e.value),
            '${expenses.where((x) => '${x['category'] ?? ''}'.trim() == e.key).length}건',
          ],
      if (byCat.isNotEmpty) ['지출 합계', won(settlement.expenseTotal), ''],
    ];
    out[SettlementBlock.expenseCategory] = SettlementBlockData(
      block: SettlementBlock.expenseCategory,
      rows: catRows,
      note: '지출 ${expenses.length}건 · 분류 ${byCat.length}종',
      empty: byCat.isEmpty,
      details: [for (final e in expenses) _moneyLine(e, won, memo: memo)],
    );

    // ── ⑤ 지출 (계좌별) ──────────────────────────────────────────────
    final byAcct = settlement.expenseByAccount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final acctRows = <List<String>>[
      if (byAcct.isEmpty)
        ['출금계좌', '없음', '']
      else
        for (final e in byAcct)
          [
            e.key,
            won(e.value),
            '${expenses.where((x) => '${x['account'] ?? ''}'.trim() == e.key || (e.key == '(계좌 미지정)' && '${x['account'] ?? ''}'.trim().isEmpty)).length}건',
          ],
    ];
    out[SettlementBlock.expenseAccount] = SettlementBlockData(
      block: SettlementBlock.expenseAccount,
      rows: acctRows,
      note: '출금계좌를 지정하지 않은 지출은 (계좌 미지정)으로 묶입니다',
      empty: byAcct.isEmpty,
      details: [for (final e in expenses) _moneyLine(e, won, memo: memo)],
    );

    // ── ⑥ 잔액 ───────────────────────────────────────────────────────
    final bal = settlement.balance;
    out[SettlementBlock.balance] = SettlementBlockData(
      block: SettlementBlock.balance,
      rows: [
        ['수입 합계', won(settlement.incomeTotal), ''],
        ['지출 합계', won(settlement.expenseTotal), ''],
        [
          bal >= 0 ? '잔액' : '초과',
          won(bal.abs()),
          bal >= 0 ? '잔액 발생' : '수입 초과 지출',
        ],
      ],
      note: bal >= 0 ? '잔액이 남았습니다' : '지출이 수입을 초과했습니다',
      empty: false,
    );

    return out;
  }

  /// 원본 재무 행 1건 → `'2026-05-12 · 김철수 · 점심식사 12,000원 · 행사비'`.
  ///
  /// (요구) "결산시에도 메모 내역을 추가해서 보여주고, 항목을 선택할 수 있도록"
  /// → [memo] 가 켜져 있고 그 행에 메모가 있으면 끝에 `· 메모: …` 를 붙인다.
  ///   메모는 여러 줄일 수 있으므로 한 줄로 눌러 담는다(표 안에서 안 터지게).
  static String _moneyLine(
    Map<String, dynamic> r,
    String Function(int) won, {
    bool memo = true,
  }) {
    final amount =
        int.tryParse(
          '${r['amount'] ?? 0}'.replaceAll(RegExp(r'[^0-9-]'), ''),
        ) ??
        0;
    final val =
        int.tryParse('${r['value'] ?? 0}'.replaceAll(RegExp(r'[^0-9-]'), '')) ??
        0;
    final parts = <String>[
      '${r['date'] ?? ''}'.trim(),
      '${r['name'] ?? ''}'.trim(),
      '${r['item'] ?? ''}'.trim().isEmpty
          ? '${r['category'] ?? ''}'.trim()
          : '${r['category'] ?? ''}'.trim() == ''
          ? '${r['item']}'.trim()
          : '${r['category']} · ${r['item']}'.trim(),
      amount > 0 ? won(amount) : '',
      val > 0 ? '${won(val)} 상당' : '',
      if (memo) _memoPart(r['memo']),
    ];
    return parts.where((e) => e.isNotEmpty).join(' · ');
  }

  /// 메모 한 조각 — 비어 있으면 빈 문자열(목록에서 자동 생략).
  static String _memoPart(Object? raw) {
    final t = '${raw ?? ''}'.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
    return t.isEmpty ? '' : '메모: $t';
  }

  /// `100,000원 + 100,000원 상당` 형태 — 0 인 쪽은 생략.
  static String _cashValue(int cash, int value, String Function(int) won) {
    final parts = <String>[
      if (cash > 0) won(cash),
      if (value > 0) '${won(value)} 상당',
    ];
    return parts.isEmpty ? '-' : parts.join(' + ');
  }

  static String _wonDefault(int v) => '${EventSettlement.comma(v)}원';
}

/// 결산 블록 → **보고서형 PDF 블록** 변환.
///
/// ## 요구사항 (그대로)
/// "pdf 출력물의 형태는 결산의 경우 기존 무인양품 스타일을 버리고, 미리보기
///  항목의 내용을 참조해서 항목별로 보기좋게 출력 … 계산서처럼 보여지기보다는
///  보고서처럼"
///
/// ## 규칙
///  · 블록 색은 미리보기(`SettlementPaperView._blockColor`)와 **같은 값**을 쓴다.
///  · 표 아래에 [SettlementLayout.showsDetail] 이 켜진 블록만 상세 내역을 붙인다.
///  · 메모는 [SettlementLayout.showMemo] 가 켜져 있을 때만 상세 줄에 이미
///    포함되어 있다(빌더가 이미 걸러 넣는다) — 여기서 또 거르지 않는다.
///  · [SettlementLayout.showNotes] 가 꺼져 있으면 note 를 비운다.
class SettlementReportBuilder {
  const SettlementReportBuilder._();

  /// 블록 강조색 — `SettlementPaperView._blockColor` 와 1:1 (hex).
  static String accentOf(SettlementBlock b) => switch (b) {
    SettlementBlock.attendees => '#2E5F8A', // taegeukBlue
    SettlementBlock.income => '#4E7A4B', // scoutGreen
    // [요구 2026-10-27] 후원 = 에르메스 오렌지 (금색 #A6763C 는 인쇄에서 흐림)
    SettlementBlock.sponsor => '#BF4E0B', // hermesInk
    SettlementBlock.expenseCategory => '#A63A3A', // taegeukRed
    SettlementBlock.expenseAccount => '#7C6A9C', // purple
    SettlementBlock.balance => '#3A3A3A', // masterInk
  };

  /// 결산 데이터 → 보고서 블록 목록(포함된 블록만, 고른 순서대로).
  static List<DocReportBlock> build({
    required SettlementLayout layout,
    required Map<SettlementBlock, SettlementBlockData> data,
    int? detailMax,
  }) {
    final out = <DocReportBlock>[];
    for (final b in layout.included) {
      final d = data[b];
      if (d == null) continue;
      // 상세 내역이 꺼져 있으면 표(합계)만 — '요약 보고서'.
      // (요구 2026-10-27) 표 행 단위 체크 — 사용자가 끈 행은 출력하지 않는다.
      final rows = <List<String>>[...layout.filterRows(b, d.rows)];
      if (layout.showsDetail(b)) {
        // (요구 2026-10-27) 줄 단위 체크 — 사용자가 끈 줄은 출력하지 않는다.
        rows.addAll(
          d.detailRows(
            max: detailMax ?? layout.detailMax,
            keep: layout.lineKeeper(b),
          ),
        );
      }
      out.add(
        DocReportBlock(
          title: b.label,
          subtitle: rows.length == 1 ? '' : '${rows.length}행',
          rows: rows,
          accent: accentOf(b),
          note: layout.showNotes ? d.note : '',
        ),
      );
    }
    return out;
  }
}
