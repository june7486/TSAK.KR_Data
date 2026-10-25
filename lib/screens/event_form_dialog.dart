import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';

/// 행사 생성/수정 폼 다이얼로그의 결과.
///
/// [mode] = create 이면 [year]/[title] 이 필수값, edit 이면 기존 값을 수정한다.
class EventFormResult {
  EventFormResult({
    required this.year,
    required this.title,
    required this.period,
    required this.place,
    required this.desc,
    required this.startDate,
    required this.endDate,
    required this.contacts,
    required this.newFiles,
    required this.deletedDist,
    this.lat = '',
    this.lng = '',
  });

  final String year;
  final String title;
  final String period;
  final String place;
  final String desc;

  /// 구조화된 시작일/종료일 (YYYY-MM-DD). 없으면 ''.
  final String startDate;
  final String endDate;

  /// (요구) 기획 시 지정한 지도 위치(좌표). 없으면 ''.
  final String lat;
  final String lng;

  /// 담당자 연락처(복수) — [{name, phone}].
  final List<Map<String, String>> contacts;

  /// 새로 첨부할 파일(복수) — '참가신청시 배포용' 폴더로 업로드.
  final List<PickedFileData> newFiles;

  /// 삭제할 기존 배포용 파일 이름 목록.
  final List<String> deletedDist;
}

/// 행사 생성/수정 공용 다이얼로그.
///
/// [요구] 행사를 수정하면 입력했던 내용을 모두 수정할 수 있고,
///   기간은 시작일·종료일을 달력에서 선택하며,
///   담당자 연락처(복수)와 첨부파일(복수 → '참가신청시 배포용')을 관리한다.
class EventFormDialog extends StatefulWidget {
  const EventFormDialog({
    super.key,
    required this.createMode,
    this.initialYear = '',
    this.initialTitle = '',
    this.initialPeriod = '',
    this.initialPlace = '',
    this.initialDesc = '',
    this.initialStart = '',
    this.initialEnd = '',
    this.initialContacts = const [],
    this.initialDist = const [],
    this.initialLat = '',
    this.initialLng = '',
  });

  final bool createMode;
  final String initialYear;
  final String initialTitle;
  final String initialPeriod;
  final String initialPlace;
  final String initialDesc;
  final String initialStart;
  final String initialEnd;
  final List<Map<String, dynamic>> initialContacts;

  /// 기존 배포용 자료 [{name, size, ext}].
  final List<Map<String, dynamic>> initialDist;

  /// (요구) 기획 시 지정한 지도 위치(좌표).
  final String initialLat;
  final String initialLng;

  @override
  State<EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends State<EventFormDialog>
    with WidgetsBindingObserver {
  late final TextEditingController _year;
  late final TextEditingController _title;
  late final TextEditingController _place;
  late final TextEditingController _desc;

  DateTime? _start;
  DateTime? _end;

  /// 담당자 행(이름/전화) — 복수 입력.
  final List<_ContactRow> _contacts = [];

  /// 새로 첨부할 파일(복수).
  final List<PickedFileData> _newFiles = [];

  /// 삭제 예정 기존 배포용 파일 이름.
  final Set<String> _deleted = {};

  late final List<Map<String, dynamic>> _dist;

  /// (요구) 기획 시 지정한 지도 위치(좌표). 없으면 '' → 장소 검색으로 노출.
  String _lat = '';
  String _lng = '';

  /// 카카오 지도 오버레이가 열려 있는 동안 true (중복 호출 방지).
  bool _kakaoOpening = false;

  /// 본문 스크롤 컨트롤러 — 스크롤바·방향 화살표용.
  ///   (요구: "행사생성시 스크롤바가 없어서 키보드 누르면 입력란이 안 보임.
  ///          키보드 선택시 입력중인 창이 노출되고 나머지가 위로 밀렸으면.
  ///          그리고 스크롤 방향화살표 생성")
  final ScrollController _scroll = ScrollController();

  /// 가로 스크롤 컨트롤러.
  ///
  /// ## 왜 가로 스크롤인가 (요구: "상하좌우 스크롤화살표 추가해줘")
  ///  폼 폭은 `_formMinWidth` 로 최소 폭을 보장한다. 좁은 기기(360~390px)에서는
  ///  `_formMinWidth` 가 화면보다 넓어 **가로 스크롤**이 생기고, 넓은 기기
  ///  (태블릿·가로모드)에서는 화면에 그대로 들어와 가로 스크롤이 없다.
  ///  즉 좌우 화살표는 좁은 기기에서 라벨 잘림을 피하기 위한 장치다.
  final ScrollController _hscroll = ScrollController();

  /// 폼 본문의 최소 폭.
  ///  (요구: "첫 화면 창은 스마트폰 창에 맞춰서 보여줘")
  ///  종전 400 고정은 360~390px 기기에서 폼이 화면보다 넓어져 **첫 화면부터**
  ///  가로 스크롤이 생겼다. 이제 폭은 화면에서 계산하고, 이 값은 하한선일 뿐이다.
  static const double _formMinWidth = 280;

  /// 좌우 화살표가 차지하는 띠 폭(양쪽 합).
  static const double _edgeBand = 72;

  /// 폼 본문의 최대 폭 — 태블릿·가로모드에서 입력칸이 지나치게 늘어나지 않게.
  static const double _formMaxWidth = 620;

  /// 스크롤 화살표 패드를 다시 그리기 위한 틱.
  final ValueNotifier<int> _padTick = ValueNotifier<int>(0);

  void _onScrollTick() {
    if (mounted) _padTick.value++;
  }

  @override
  void initState() {
    super.initState();
    // 키보드가 올라오면(뷰 인셋 변화) 현재 입력 중인 칸을 화면 안으로 끌어올린다.
    WidgetsBinding.instance.addObserver(this);
    // 스크롤 화살표 활성/비활성 표시용 리스너.
    _scroll.addListener(_onScrollTick);
    _hscroll.addListener(_onScrollTick);

    final now = DateTime.now().year;
    _year = TextEditingController(
      text: widget.initialYear.isNotEmpty ? widget.initialYear : '$now',
    );
    _title = TextEditingController(text: widget.initialTitle);
    _place = TextEditingController(text: widget.initialPlace);
    _lat = widget.initialLat;
    _lng = widget.initialLng;
    _desc = TextEditingController(text: widget.initialDesc);
    _start =
        _parseDate(widget.initialStart) ??
        _parsePeriodStart(widget.initialPeriod);
    _end =
        _parseDate(widget.initialEnd) ?? _parsePeriodEnd(widget.initialPeriod);
    for (final c in widget.initialContacts) {
      final nm = '${c['name'] ?? ''}';
      final ph = '${c['phone'] ?? ''}';
      if (nm.isNotEmpty || ph.isNotEmpty) {
        _contacts.add(_ContactRow(nm, ph));
      }
    }
    if (_contacts.isEmpty) _contacts.add(_ContactRow('', ''));
    _dist = List<Map<String, dynamic>>.from(widget.initialDist);

    // ── 버그 수정: 다이얼로그가 '중간부터' 보이던 문제 ────────────────────
    //  원인 두 가지.
    //   ① Flutter 는 첫 포커스 가능 위젯에 자동으로 초기 포커스를 주고,
    //      그 위젯을 **보이게 하려고 스크롤을 옮긴다**. 이 폼의 첫 TextField
    //      (연도)가 화면 밖이면 중간/하단으로 점프했다.
    //   ② ScrollController 의 첫 클라이언트가 붙는 순간 위치가 0 이 아닐 수
    //      있다(이전 스크롤 위치 보존).
    //  → 첫 프레임 뒤에 스크롤을 **맨 위로 확정**하고, 초기 포커스를 비운다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 초기 포커스 해제 — 키보드가 저절로 올라와 화면을 밀지 않게.
      final f = FocusManager.instance.primaryFocus;
      if (f != null && f is! FocusScopeNode) f.unfocus();
      if (_scroll.hasClients && _scroll.offset != 0) {
        _scroll.jumpTo(0);
      }
      // 스크롤 클라이언트가 붙은 **뒤**에 화살표 상태를 한 번 갱신한다.
      //  (붙기 전에는 maxScrollExtent 를 알 수 없어 '맨 위'로 오판했다)
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScrollTick);
    _hscroll.removeListener(_onScrollTick);
    _scroll.dispose();
    _hscroll.dispose();
    _padTick.dispose();
    _year.dispose();
    _title.dispose();
    _place.dispose();
    _desc.dispose();
    for (final c in _contacts) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------
  // 키보드 대응 — 지금 입력 중인 칸을 화면 안(키보드 위)으로 끌어올린다.
  // ---------------------------------------------------------------
  double _lastViewInset = 0;

  @override
  void didChangeMetrics() {
    final inset =
        WidgetsBinding
            .instance
            .platformDispatcher
            .views
            .first
            .viewInsets
            .bottom /
        (WidgetsBinding
                    .instance
                    .platformDispatcher
                    .views
                    .first
                    .devicePixelRatio ==
                0
            ? 1
            : WidgetsBinding
                  .instance
                  .platformDispatcher
                  .views
                  .first
                  .devicePixelRatio);
    final rising = inset > _lastViewInset + 1;
    _lastViewInset = inset;
    if (!rising) return;
    // 키보드가 올라오는 순간에만 스크롤을 보정한다(내려갈 때는 그대로).
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealFocusedField());
  }

  /// 현재 포커스된 입력 칸을 스크롤 영역 안으로 노출한다.
  ///   · `Scrollable.ensureVisible` 은 다이얼로그 안 스크롤까지 자동 처리한다.
  ///   · 애니메이션을 짧게 두어 '확 밀리는' 느낌을 없앤다.
  void _revealFocusedField() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !mounted) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.18, // 화면 위쪽 18% 지점에 오도록 → 아래 남은 칸이 보인다
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  /// 스크롤 방향 화살표 — 상·하·좌·우로 한 화면씩 부드럽게 이동.
  ///   (요구: "스크롤 방향화살표 생성" → "상하좌우 스크롤화살표 추가해줘")
  ///
  /// [axis] 가 vertical 이면 [_scroll], horizontal 이면 [_hscroll] 을 움직인다.
  /// 화살표가 실제로 움직일 수 없으면(스크롤 여지 없음) 아무 일도 하지 않는다.
  Future<void> _nudge(double dir, {Axis axis = Axis.vertical}) async {
    final ctrl = axis == Axis.vertical ? _scroll : _hscroll;
    if (!ctrl.hasClients) return;
    final pos = ctrl.position;
    if (pos.maxScrollExtent <= 0) return; // 스크롤 여지 없음
    final target = (pos.pixels + dir * pos.viewportDimension * 0.72).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    await ctrl.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  /// 스크롤 extent 를 **안전하게** 읽는다.
  ///
  /// ## 왜 필요한가 (테스트가 잡은 실제 크래시)
  /// `controller.hasClients == true` 인데도 `position.maxScrollExtent` 가
  /// 아직 `null` 인 프레임이 있다(레이아웃 전). 그 상태에서 곧바로 읽으면
  /// `Null check operator used on a null value` 로 **화살표 위젯이 통째로
  /// 예외**를 던진다. → `hasContentDimensions` 로 한 번 더 막는다.
  double? _vExtent() {
    if (!_scroll.hasClients) return null;
    final p = _scroll.position;
    if (!p.hasContentDimensions) return null;
    return p.maxScrollExtent;
  }

  double? _hExtent() {
    if (!_hscroll.hasClients) return null;
    final p = _hscroll.position;
    if (!p.hasContentDimensions) return null;
    return p.maxScrollExtent;
  }

  /// 좌우 화살표를 흐리게(비활성) 표시할지 판단한다.
  bool _hAtStart() {
    if (!_hscroll.hasClients) return true;
    return _hscroll.offset <= 2;
  }

  bool _hAtEnd() {
    final max = _hExtent();
    if (max == null) return true; // 아직 모름 — 흐리게(오작동 방지).
    return _hscroll.offset >= max - 2;
  }

  static DateTime? _parseDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(t);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  /// 기간 문자열(예: '2026.03.14~15', '2026.03.14~2026.03.15')에서 시작일 추정.
  static DateTime? _parsePeriodStart(String s) {
    final m = RegExp(r'(\d{4})\.(\d{1,2})\.(\d{1,2})').firstMatch(s);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  static DateTime? _parsePeriodEnd(String s) {
    final start = _parsePeriodStart(s);
    if (start == null) return null;
    // '~15' / '~03.15' / '~2026.03.15' 형태의 종료부.
    final m = RegExp(r'~\s*(\d{4}\.)?(\d{1,2})\.(\d{1,2})').firstMatch(s);
    if (m != null && m.group(2) != null && m.group(3) != null) {
      final y = m.group(1) != null
          ? int.parse(m.group(1)!.replaceAll('.', ''))
          : start.year;
      return DateTime(y, int.parse(m.group(2)!), int.parse(m.group(3)!));
    }
    // '~15' — 시작일과 같은 달의 일자만.
    final m2 = RegExp(r'~\s*(\d{1,2})\s*$').firstMatch(s);
    if (m2 != null) {
      return DateTime(start.year, start.month, int.parse(m2.group(1)!));
    }
    return start;
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 표시용 기간 문자열 조합.
  String get _periodText {
    if (_start == null && _end == null) return '';
    final s = _start ?? _end!;
    final e = _end ?? _start!;
    if (s.year == e.year && s.month == e.month && s.day == e.day) {
      return '${s.year}.${s.month.toString().padLeft(2, '0')}.'
          '${s.day.toString().padLeft(2, '0')}';
    }
    if (s.year == e.year && s.month == e.month) {
      return '${s.year}.${s.month.toString().padLeft(2, '0')}.'
          '${s.day.toString().padLeft(2, '0')}~${e.day.toString().padLeft(2, '0')}';
    }
    return '${s.year}.${s.month.toString().padLeft(2, '0')}.'
        '${s.day.toString().padLeft(2, '0')}~'
        '${e.year}.${e.month.toString().padLeft(2, '0')}.'
        '${e.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final base = isStart ? (_start ?? now) : (_end ?? _start ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(1980),
      lastDate: DateTime(now.year + 8),
      helpText: isStart ? '시작일 선택' : '종료일 선택',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start != null && _start!.isAfter(picked)) _start = picked;
      }
    });
  }

  Future<void> _pickFiles() async {
    final picked = await pickDataFiles(
      allowMultiple: true,
      dialogTitle: '배포용 자료 선택 (복수 선택 가능)',
    );
    if (picked.isEmpty) return;
    setState(() => _newFiles.addAll(picked));
  }

  bool get _yearOk => RegExp(r'^\d{4}$').hasMatch(_year.text.trim());
  bool get _canSave => _yearOk && _title.text.trim().isNotEmpty;

  @override
  @override
  Widget build(BuildContext context) {
    // ## 이 폼에서 실제로 터진 버그 3건 (모두 다른 원인)
    //   ① `ConstrainedBox(maxHeight) > Stack > [Scrollbar, Positioned(화살표)]`
    //      → Stack 의 비배치 자식이 loose 제약을 받아 첫 프레임이 중간에서
    //        그려지고(연도 칸이 화면 밖) 화살표가 입력칸을 덮었다.
    //   ② 안내문구 `Row[Text, Spacer]` 가 폭 298~306px 기기에서 가로로 넘쳐
    //      (RenderFlex overflow) **본문이 통째로 빈 화면**이 됐다.
    //   ③ 키보드가 올라오면 AlertDialog 의 insetPadding 이 커지며 창이 급격히
    //      줄어 **입력칸이 화면에서 사라졌다**.
    //
    // ## 확정 구조 — AlertDialog 폐기, 바텀시트 3단(고정)
    //   바깥: [showEventFormSheet] →
    //         showModalBottomSheet(isScrollControlled: true)
    //         높이 = (화면높이 − 키보드높이) × 0.94  ← **키보드와 무관하게 고정**
    //   안쪽: 헤더(고정) / 본문(스크롤) / 버튼(고정)
    //   → 키보드가 떠도 창이 줄지 않고 입력칸이 가려지지 않는다.
    //
    // ⚠ 이 build 는 **본문 필드만** 만든다(단독 dialog 로 띄우지 말 것).
    // ── 키보드와 무관하게 창 높이를 고정한다 ────────────────────────────
    //  sheetHeight = (화면높이 − 키보드높이) × 0.94
    //  키보드가 떠도 이 값은 '사용 가능한 높이' 기준이라 창이 찌그러지지 않고,
    //  아래 Padding 으로 시트 전체를 키보드 위로 들어올린다.
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final sheetHeight = ((mq.size.height - keyboard) * 0.94).clamp(
      240.0,
      1600.0,
    );
    // (요구) 첫 화면이 스마트폰 폭에 맞도록 — 화면 폭에서 화살표 띠만 뺀다.
    // 화살표 띠(양쪽 20+20) + 세로 Scrollbar 두께(6) 를 뺀 실제 본문 폭.
    final availW = mq.size.width - _edgeBand;
    final formW = availW.clamp(_formMinWidth, _formMaxWidth);
    // 화면이 _formMinWidth 보다 좁을 때만 가로 스크롤이 생긴다.
    final needH = availW < _formMinWidth;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHeader(),
            Divider(height: 1, color: AppColors.purple.withValues(alpha: 0.15)),
            // ── 본문: 여기만 스크롤 (헤더·버튼은 고정) ────────────────────
            //
            // ## 화살표 배치 (요구: "스크롤은 하단 스크롤 화살표는 하단에,
            //    상단 스크롤 화살표는 상단에 표시 / 좌우 화살표도 동일")
            //  종전에는 화살표를 헤더 우측에 십자(+)로 몰아넣어 폼 상단을 덮었다.
            //  이제 **각 가장자리**로 분산한다.
            //    ▲ 본문 위 모서리(가로 중앙)   ▼ 본문 아래 모서리(가로 중앙)
            //    ◀ 본문 왼쪽(세로 중앙)        ▶ 본문 오른쪽(세로 중앙)
            //  화살표는 본문 바깥 띠(22px) 안에만 있어 **입력칸을 덮지 않는다.**
            Expanded(
              child: Stack(
                children: [
                  // 본문은 화살표 띠만큼 안쪽으로 밀어 넣는다.
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      child: Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        trackVisibility: false,
                        thickness: 6,
                        radius: const Radius.circular(3),
                        child: SingleChildScrollView(
                          controller: _scroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.only(top: 2, bottom: 10),
                          // ── 좌우 스크롤 (요구: "상하좌우 스크롤화살표") ──────────
                          //  폭은 화면에서 계산한 formW. 화면이 _formMinWidth 보다
                          //  좁을 때만 가로 스크롤이 생긴다(넓으면 ◀▶ 자동 흐림).
                          child: SingleChildScrollView(
                            controller: _hscroll,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox(
                              width: formW,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ---- 연도 ----
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _year,
                                          keyboardType: TextInputType.number,
                                          maxLength: 4,
                                          onChanged: (_) => setState(() {}),
                                          decoration: InputDecoration(
                                            labelText: '연도 * (필수)',
                                            counterText: '',
                                            errorText:
                                                _year.text.trim().isEmpty ||
                                                    _yearOk
                                                ? null
                                                : '4자리 연도를 입력하세요',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: () async {
                                          final now = DateTime.now().year;
                                          final picked = await showDialog<int>(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              title: const Text('연도 선택'),
                                              content: SizedBox(
                                                width: 300,
                                                height: 300,
                                                child: YearPicker(
                                                  firstDate: DateTime(1980),
                                                  lastDate: DateTime(now + 8),
                                                  selectedDate: DateTime(
                                                    int.tryParse(
                                                          _year.text.trim(),
                                                        ) ??
                                                        now,
                                                  ),
                                                  onChanged: (d) =>
                                                      Navigator.pop(
                                                        context,
                                                        d.year,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          );
                                          if (picked != null) {
                                            _year.text = '$picked';
                                            setState(() {});
                                          }
                                        },
                                        child: const Text('선택'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // ---- 행사명 ----
                                  TextField(
                                    controller: _title,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: '행사명 *',
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // ---- 기간 (시작일 / 종료일) ----
                                  const Text(
                                    '행사기간',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          icon: const Icon(
                                            Icons.event,
                                            size: 17,
                                          ),
                                          label: Text(
                                            _start == null
                                                ? '시작일 선택'
                                                : _fmt(_start!),
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          onPressed: () =>
                                              _pickDate(isStart: true),
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: Text('~'),
                                      ),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          icon: const Icon(
                                            Icons.event_available,
                                            size: 17,
                                          ),
                                          label: Text(
                                            _end == null
                                                ? '종료일 선택'
                                                : _fmt(_end!),
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          onPressed: () =>
                                              _pickDate(isStart: false),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_periodText.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 5,
                                        left: 2,
                                      ),
                                      child: Text(
                                        '표시: $_periodText',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textGray,
                                        ),
                                      ),
                                    ),
                                  // 종료일이 있으면 시작일도 함께 초기화할 수 있게 안내.
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => setState(() {
                                        _start = null;
                                        _end = null;
                                      }),
                                      child: const Text(
                                        '기간 지우기',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // ---- 장소 + 카카오지도 검색 ----
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _place,
                                          decoration: const InputDecoration(
                                            labelText: '장소',
                                          ),
                                          onChanged: (_) =>
                                              setState(() => _lat = _lng = ''),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: OutlinedButton.icon(
                                          onPressed: _searchOnMap,
                                          icon: const Icon(
                                            Icons.map_outlined,
                                            size: 16,
                                          ),
                                          label: const Text(
                                            '지도에서 검색',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_lat.isNotEmpty && _lng.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    _mapPreview(_lat, _lng),
                                  ],
                                  if (_lat.isNotEmpty && _lng.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFFFEE500,
                                          ).withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.place,
                                              size: 16,
                                              color: Color(0xFF3C1E1E),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                '지도 위치 지정됨 · $_lat, $_lng',
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () => setState(
                                                () => _lat = _lng = '',
                                              ),
                                              child: const Text(
                                                '(삭제)',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textGray,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  // ---- 소개/개요 ----
                                  TextField(
                                    controller: _desc,
                                    maxLines: 3,
                                    decoration: const InputDecoration(
                                      labelText: '행사 소개/개요',
                                      alignLabelWithHint: true,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  // ---- 담당자 연락처 (복수) ----
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.headset_mic,
                                        size: 17,
                                        color: AppColors.purple,
                                      ),
                                      const SizedBox(width: 6),
                                      // 좁은 화면(폭 ~300px)에서 제목이 길어 Row 가 넘치지 않도록
                                      //  Expanded 로 감싸 남는 폭만 쓰게 한다. (빈 화면 버그 원인)
                                      const Expanded(
                                        child: Text(
                                          '행사 담당자 (문의하기 · 복수 가능)',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '담당자 추가',
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          size: 20,
                                        ),
                                        onPressed: () => setState(
                                          () => _contacts.add(
                                            _ContactRow('', ''),
                                          ),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  if (_contacts.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(
                                        left: 2,
                                        bottom: 4,
                                      ),
                                      child: Text(
                                        '(선택) 담당자 번호를 입력하면 참가신청 페이지에 문의 버튼이 나타납니다.',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textGray,
                                        ),
                                      ),
                                    ),
                                  for (var i = 0; i < _contacts.length; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 92,
                                            child: TextField(
                                              controller: _contacts[i].name,
                                              decoration: const InputDecoration(
                                                labelText: '이름',
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: TextField(
                                              controller: _contacts[i].phone,
                                              keyboardType: TextInputType.phone,
                                              decoration: const InputDecoration(
                                                labelText: '전화번호',
                                                isDense: true,
                                                hintText: '010-0000-0000',
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: '삭제',
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                              size: 20,
                                              color: AppColors.taegeukRed,
                                            ),
                                            onPressed: () => setState(() {
                                              _contacts.removeAt(i).dispose();
                                            }),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  // ---- 첨부파일 → '참가신청시 배포용' (복수) ----
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.attach_file,
                                        size: 17,
                                        color: AppColors.scoutGreen,
                                      ),
                                      const SizedBox(width: 6),
                                      // 위와 같은 이유로 Expanded (좁은 화면 가로 넘침 방지).
                                      const Expanded(
                                        child: Text(
                                          '참가신청시 배포용 자료 (복수 가능)',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      TextButton.icon(
                                        icon: const Icon(
                                          Icons.upload_file,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          '파일 추가',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        onPressed: _pickFiles,
                                      ),
                                    ],
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '여기에 올린 파일은 참가신청 페이지에서 바로 내려받을 수 있습니다.\n'
                                      "저장 위치: 기획서 폴더 › '참가신청시 배포용'",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textGray,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                  // 기존 배포용 파일 (삭제 가능)
                                  for (final d in _dist)
                                    if (!_deleted.contains('${d['name']}'))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.scoutGreen
                                                .withValues(alpha: 0.07),
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                            border: Border.all(
                                              color: AppColors.scoutGreen
                                                  .withValues(alpha: 0.25),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.description,
                                                size: 16,
                                                color: AppColors.scoutGreen,
                                              ),
                                              const SizedBox(width: 7),
                                              Expanded(
                                                child: Text(
                                                  '${d['name']}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                _fmtSize(
                                                  (d['size'] as num?)
                                                          ?.toInt() ??
                                                      0,
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: AppColors.textGray,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: '삭제',
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 17,
                                                  color: AppColors.taegeukRed,
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: () => setState(
                                                  () => _deleted.add(
                                                    '${d['name']}',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  // 새로 추가한 파일
                                  for (var i = 0; i < _newFiles.length; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.purple.withValues(
                                            alpha: 0.06,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            9,
                                          ),
                                          border: Border.all(
                                            color: AppColors.purple.withValues(
                                              alpha: 0.25,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.upload_file,
                                              size: 16,
                                              color: AppColors.purple,
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Text(
                                                '${_newFiles[i].name}  (신규)',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _fmtSize(
                                                _newFiles[i].bytes.length,
                                              ),
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                color: AppColors.textGray,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: '빼기',
                                              icon: const Icon(
                                                Icons.close,
                                                size: 17,
                                                color: AppColors.taegeukRed,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () => setState(
                                                () => _newFiles.removeAt(i),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  // 좁은 기기에서만 — 가로로 넘친다는 사실을 알린다.
                                  if (needH)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.swipe,
                                            size: 12,
                                            color: AppColors.textGray
                                                .withValues(alpha: 0.85),
                                          ),
                                          const SizedBox(width: 4),
                                          const Expanded(
                                            child: Text(
                                              '화면이 좁아 가로로 넘칩니다 · 좌우 화살표로 이동',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: AppColors.textGray,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ── 화살표 4개: 각 가장자리 ─────────────────────────────
                  _edgeArrow(
                    top: 0,
                    bottom: null,
                    left: 0,
                    right: 0,
                    icon: Icons.keyboard_arrow_up,
                    tip: '위로 스크롤',
                  ),
                  _edgeArrow(
                    top: null,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    icon: Icons.keyboard_arrow_down,
                    tip: '아래로 스크롤',
                  ),
                  _edgeArrow(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    right: null,
                    icon: Icons.keyboard_arrow_left,
                    tip: '왼쪽으로 스크롤',
                    horizontal: true,
                  ),
                  _edgeArrow(
                    top: 0,
                    bottom: 0,
                    left: null,
                    right: 0,
                    icon: Icons.keyboard_arrow_right,
                    tip: '오른쪽으로 스크롤',
                    horizontal: true,
                  ),
                ],
              ),
            ),
            _sheetFooter(),
          ],
        ),
      ),
    );
  }

  /// 시트 헤더(고정) — 제목 + 스크롤 방향 화살표.
  ///
  /// ## 화살표를 헤더로 옮긴 이유
  ///  종전에는 본문 위에 떠 있는 알약(pill) 모양이었는데, 폭이 좁은 기기에서
  ///  **입력칸을 덮었다**(스크린샷의 ▲▼✓ 막대). 헤더는 절대 본문을 덮지
  ///  않으므로 기능은 유지하고 겹침만 없앤다.
  Widget _sheetHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(
            widget.createMode ? Icons.add_box_outlined : Icons.edit_note,
            size: 18,
            color: AppColors.purple,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.createMode ? '새 행사 만들기' : '행사 수정',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  '연도와 행사명은 필수입니다',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 가장자리 스크롤 화살표 1개.
  ///
  /// ## 요구 (그대로)
  /// "스크롤은 하단 스크롤 화살표는 하단에 상단 스크롤 화살표는 상단에 표시,
  ///  좌우 화살표도 동일"
  ///
  /// ## 배치 규칙
  ///  · [top]/[bottom]/[left]/[right] 로 가장자리를 지정한다.
  ///    - 상·하 화살표: `left:0, right:0` → 가로 가운데 정렬
  ///    - 좌·우 화살표: `top:0, bottom:0` → 세로 가운데 정렬
  ///  · 화살표는 본문 바깥 띠(22px) 안에만 있으므로 **입력칸을 덮지 않는다.**
  ///  · 스크롤 여지가 없으면(맨 끝/맨 위) 자동으로 흐려지고 눌리지 않는다.
  ///
  /// ⚠ ScrollController 는 첫 프레임에 아직 attach 전일 수 있다
  ///   (`hasClients == false`, `maxScrollExtent` 미확정). 그때 값을 읽어
  ///   상태를 굳히면 화살표가 영구히 비활성이 되므로, [_padTick] 로 다시 그린다.
  Widget _edgeArrow({
    required IconData icon,
    required String tip,
    double? top,
    double? bottom,
    double? left,
    double? right,
    bool horizontal = false,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: AnimatedBuilder(
        animation: _padTick,
        builder: (context, _) {
          var dim = false;
          if (horizontal) {
            dim =
                (_hAtStart() && tip.contains('왼')) ||
                (_hAtEnd() && tip.contains('오른'));
          } else {
            final max = _vExtent();
            if (max == null) {
              dim = true; // 아직 붙기 전/치수 미확정 — 흐리게.
            } else {
              final px = _scroll.offset;
              final atTop = px <= 2;
              final atBottom = px >= max - 2;
              dim =
                  (atTop && tip.contains('위')) ||
                  (atBottom && tip.contains('아래'));
            }
          }

          final color = dim
              ? AppColors.textGray.withValues(alpha: 0.28)
              : AppColors.purple;

          return Tooltip(
            message: tip,
            child: Material(
              color: dim
                  ? AppColors.purple.withValues(alpha: 0.04)
                  : AppColors.purple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: dim
                    ? null
                    : () => _nudge(
                        tip.contains('위') || tip.contains('왼') ? -1 : 1,
                        axis: horizontal ? Axis.horizontal : Axis.vertical,
                      ),
                child: SizedBox(
                  width: 34,
                  height: 24,
                  child: Icon(icon, size: 20, color: color),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 시트 하단 버튼(고정) — 항상 보인다.
  Widget _sheetFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.purple.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: _canSave
                  ? () => Navigator.pop(context, _buildResult())
                  : null,
              child: Text(
                widget.createMode ? '생성' : '저장',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 시트의 '저장/생성' 버튼이 눌렸을 때 돌려줄 값.
  EventFormResult _buildResult() {
    final contacts = <Map<String, String>>[];
    for (final c in _contacts) {
      final nm = c.name.text.trim();
      final ph = c.phone.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (ph.isNotEmpty) contacts.add({'name': nm, 'phone': ph});
    }
    return EventFormResult(
      year: _year.text.trim(),
      title: _title.text.trim(),
      period: _periodText,
      place: _place.text.trim(),
      desc: _desc.text.trim(),
      lat: _lat,
      lng: _lng,
      startDate: _start == null ? '' : _fmt(_start!),
      endDate: _end == null ? '' : _fmt(_end!),
      contacts: contacts,
      newFiles: _newFiles,
      deletedDist: _deleted.toList(),
    );
  }

  /// [요구] 행사기획 시 지도에서 위치를 '검색하면 곧바로 입력'한다.
  ///   · 웹 + 카카오(키·서비스 정상) 확인 시 → **실제 카카오맵(드래그·검색)** 선택기.
  ///   · 그 외 → 무료 지오코딩 검색 목록(좌표 즉시 입력) + 미리보기.
  ///
  /// ## 버그 수정: "지도에서 검색 → 다운/멈춤"
  ///  카카오맵 서비스가 꺼져 있으면 지도가 하얗게 뜨고 오버레이에 갇혔다.
  ///  → 서버가 카카오 상태(canOpenKakao)를 확인해 줄 때만 오버레이를 열고,
  ///    아니면 곧바로 무료 지도 검색으로 전환한다(JS/Dart 이중 안전장치).
  Future<void> _searchOnMap() async {
    if (_kakaoOpening) return; // 중복 호출(연타) 방지 — 오버레이 2중 생성 차단
    final nas = context.read<NasApi>();
    if (isWebRuntime) {
      Map<String, dynamic> cfg = {};
      try {
        cfg = await nas.geoConfig();
      } catch (_) {}
      final jsKey = '${cfg['kakaoJsKey'] ?? ''}'.trim();
      final canOpen = cfg['canOpenKakao'] == true;
      if (jsKey.isNotEmpty && canOpen) {
        _kakaoOpening = true;
        Map<String, String>? picked;
        try {
          picked = await openKakaoMapPicker(
            key: jsKey,
            title: _title.text.trim(),
            place: _place.text.trim(),
            lat: _lat,
            lng: _lng,
          );
        } finally {
          _kakaoOpening = false;
        }
        final err = picked?['error'] ?? '';
        if (picked != null && err.isEmpty) {
          if (!mounted) return;
          final p = picked;
          setState(() {
            _lat = p['lat'] ?? '';
            _lng = p['lng'] ?? '';
            final nm = (p['place'] ?? '').trim();
            if (nm.isNotEmpty) _place.text = nm;
          });
          _toast('지도 위치가 지정되었습니다');
          return; // 정상적으로 지정/취소됨
        }
        // 오류/시간초과 → 무료 지도로 폴백(+원인 진단 배너)
        if (!mounted) return;
        await _searchOnMapFallback(kakaoError: true);
        return;
      }
      // 카카오 준비 안 됨(키 없음/서비스 꺼짐/미확인) → 무료 지도 검색으로.
      if (!mounted) return;
      await _searchOnMapFallback(kakaoError: jsKey.isNotEmpty);
      return;
    }
    await _searchOnMapFallback();
  }

  /// 무료 지오코딩 기반 검색(카카오 JS 키가 없거나 네이티브일 때).
  /// [kakaoError] 가 true 면 "카카오 키가 있는데 SDK 로드 실패" 상태 → 정확한 안내.
  Future<void> _searchOnMapFallback({bool kakaoError = false}) async {
    // (버그수정) 검색어는 '장소' 우선 — 행사명이 섞이면 엉뚱한 곳이 검색된다.
    final qCtrl = TextEditingController(
      text: _place.text.trim().isNotEmpty
          ? _place.text.trim()
          : _title.text.trim(),
    );
    List<Map<String, dynamic>> items = [];
    bool loading = false;
    String? err;
    final nas = context.read<NasApi>();
    // 카카오 진단(키가 있는데 실패한 경우) — 정확한 원인을 사용자에게 그대로 보여준다.
    final diagVN = ValueNotifier<String?>(null);
    if (kakaoError) {
      nas
          .geoKakaoTest()
          .then((t) {
            diagVN.value = _fmtKakaoDiag(t);
          })
          .catchError((_) {
            diagVN.value =
                '카카오맵 서비스가 꺼져 있거나 키가 유효하지 않습니다. '
                '마스터 콘솔 → [지도 검색 키 (카카오)]에서 확인하세요. '
                '지금은 무료 지도로 검색합니다.';
          });
    }
    Future<void> doSearch(StateSetter setSt) async {
      final q = qCtrl.text.trim();
      if (q.length < 2) return;
      setSt(() {
        loading = true;
        err = null;
      });
      try {
        final r = await nas.geoSearch(q, limit: 8);
        setSt(() {
          items = r;
          loading = false;
          if (r.isEmpty) err = '검색 결과가 없습니다. 다른 검색어로 시도해 보세요.';
        });
      } catch (e) {
        setSt(() {
          loading = false;
          err = '검색 실패: $e';
        });
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.map, size: 20, color: AppColors.purple),
              SizedBox(width: 6),
              Text('지도에서 위치 검색', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '장소/주소를 검색하면 좌표가 곧바로 입력됩니다. '
                    '결과를 누르면 정확한 위치가 저장됩니다.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
                  ),
                  const SizedBox(height: 6),
                  if (kakaoError)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.taegeukRed.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 15,
                                color: AppColors.taegeukRed,
                              ),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  '카카오맵을 불러오지 못했습니다. 아래 무료 지도(OpenStreetMap)로 검색합니다.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.4,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ValueListenableBuilder<String?>(
                            valueListenable: diagVN,
                            builder: (_, dv, __) {
                              if (dv == null || dv.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 6, left: 21),
                                  child: SizedBox(
                                    height: 12,
                                    width: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.6,
                                    ),
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  left: 21,
                                ),
                                child: Text(
                                  dv,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.45,
                                    color: AppColors.textGray,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '💡 무료 지도(OpenStreetMap) 검색 중입니다. 상호명(예: 송정호텔)이 '
                        '안 잡히면 마스터 콘솔 → [지도 검색 키 (카카오)]에 카카오 키를 '
                        '등록하고 카카오맵 서비스를 켜면 카카오맵(정확)으로 전환됩니다.',
                        style: TextStyle(fontSize: 11, height: 1.45),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: '장소/주소 검색',
                            hintText: '예) 부산 송정해수욕장',
                          ),
                          onSubmitted: (_) => doSearch(setSt),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: loading ? null : () => doSearch(setSt),
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('검색', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (err != null && !loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        err!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.taegeukRed,
                        ),
                      ),
                    ),
                  for (final it in items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE0DCE8)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.place_outlined,
                          size: 18,
                          color: AppColors.purple,
                        ),
                        title: Text(
                          '${it['label'] ?? it['name'] ?? ''}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        subtitle: Text(
                          '${it['lat']}, ${it['lng']}',
                          style: const TextStyle(fontSize: 10.5),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyGeoChoice(it);
                        },
                      ),
                    ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _mapPreview(
                      '${items.first['lat']}',
                      '${items.first['lng']}',
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setSt(() {
                  _lat = '';
                  _lng = '';
                  items = [];
                });
              },
              child: const Text('좌표 지우기'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('직접 입력'),
            ),
          ],
        ),
      ),
    );
    qCtrl.dispose();
    diagVN.dispose();
  }

  /// 카카오 진단 응답(JSON) → 사용자가 바로 이해할 수 있는 한 줄 안내.
  static String _fmtKakaoDiag(Map<String, dynamic> t) {
    final hint = '${t['hint'] ?? ''}'.trim();
    if (t['ok'] == true) return '카카오 키·서비스 정상입니다.';
    if (hint.isNotEmpty) return hint;
    final kakao = t['kakao'];
    if (kakao is Map && '${kakao['message'] ?? ''}'.trim().isNotEmpty) {
      return '카카오 오류: ${kakao['message']} '
          '(마스터 콘솔 → [지도 검색 키 (카카오)]에서 확인하세요)';
    }
    final err = '${t['error'] ?? ''}'.trim();
    if (err.isNotEmpty) return '카카오 연결 오류: $err';
    return '카카오 응답을 확인할 수 없습니다. 키/서비스 상태를 점검하세요.';
  }

  /// 검색 결과에서 선택한 위치를 저장(장소명이 비어 있으면 결과 라벨 사용).
  void _applyGeoChoice(Map<String, dynamic> it) {
    setState(() {
      _lat = '${it['lat'] ?? ''}';
      _lng = '${it['lng'] ?? ''}';
      if (_place.text.trim().isEmpty) {
        final lb = '${it['name'] ?? it['label'] ?? ''}'.trim();
        if (lb.isNotEmpty) _place.text = lb;
      }
    });
  }

  /// (요구) 검색 위치 지도 미리보기.
  ///   카카오 지도(JS 키 등록 시) → 실패하면 무료 OSM 지도로 자동 폴백.
  Widget _mapPreview(String lat, String lng) {
    if (lat.isEmpty || lng.isEmpty) return const SizedBox.shrink();
    final nas = context.read<NasApi>();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        nas.geoKakaoMapUrl(lat, lng, w: 520, h: 240),
        height: 160,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.network(
          nas.geoStaticMapUrl(lat, lng, w: 520, h: 240),
          height: 160,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFEE500).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '지도 미리보기를 불러올 수 없습니다',
              style: TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
          ),
        ),
      ),
    );
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }

  static String _fmtSize(int n) {
    if (n < 1024) return '$n B';
    if (n < 1048576) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1048576).toStringAsFixed(1)} MB';
  }
}

class _ContactRow {
  _ContactRow(String name, String phone)
    : name = TextEditingController(text: name),
      phone = TextEditingController(text: phone);

  final TextEditingController name;
  final TextEditingController phone;

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

/// 행사 만들기/수정 창을 **바텀시트**로 띄운다.
///
/// ## 왜 showDialog 가 아니라 이 함수인가 (버그 3연속의 최종 해법)
///  알림창(AlertDialog)은 키보드가 올라오면 `insetPadding.bottom` 이 커지면서
///  **창 자체가 줄어든다**. 그래서 입력칸이 화면 밖으로 밀려나 "입력할 창이
///  안 보이는" 상태가 됐다(아이폰·안드로이드 공통).
///
///  바텀시트는 `isScrollControlled: true` 로 화면 하단에 붙이고
///  **높이 = (화면높이 − 키보드높이) × 0.94** 로 계산한다. 키보드가 떠도
///  헤더·본문·버튼의 비율이 유지되고 본문만 스크롤되므로 입력칸이 사라지지
///  않는다.
Future<EventFormResult?> showEventFormSheet({
  required BuildContext context,
  required bool createMode,
  String initialYear = '',
  String initialTitle = '',
  String initialPeriod = '',
  String initialPlace = '',
  String initialDesc = '',
  String initialStart = '',
  String initialEnd = '',
  List<Map<String, dynamic>> initialContacts = const [],
  List<Map<String, dynamic>> initialDist = const [],
  String initialLat = '',
  String initialLng = '',
}) {
  return showModalBottomSheet<EventFormResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    showDragHandle: false,
    builder: (_) => EventFormDialog(
      createMode: createMode,
      initialYear: initialYear,
      initialTitle: initialTitle,
      initialPeriod: initialPeriod,
      initialPlace: initialPlace,
      initialDesc: initialDesc,
      initialStart: initialStart,
      initialEnd: initialEnd,
      initialContacts: initialContacts,
      initialDist: initialDist,
      initialLat: initialLat,
      initialLng: initialLng,
    ),
  );
}
