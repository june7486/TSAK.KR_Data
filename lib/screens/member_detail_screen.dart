import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/finance_transaction.dart';
import '../models/member.dart';
import '../services/app_state.dart';
import '../services/finance_service.dart';
import '../services/nas_api.dart';
import '../services/member_draft_store.dart';
import '../services/extra_fields.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/donation_accounts.dart';
import '../widgets/member_avatar.dart';
import '../widgets/marquee_text.dart';
import '../widgets/member_access_log.dart';
import '../widgets/link_people_tiles.dart';
import '../widgets/mentee_register_section.dart';
import '../widgets/member_registration_request_section.dart';
import '../widgets/fee_payment_request.dart';
import '../widgets/merch_activity_section.dart';
import '../widgets/personal_survey_section.dart';
import '../widgets/photo_pip.dart';
import '../widgets/scroll_down_hint.dart';
import 'finance_transaction_edit_screen.dart';
import 'export_screen.dart';
import 'member_edit_screen.dart';
import 'privacy_usage_edit_screen.dart';
import 'member_drafts_screen.dart';
import 'qr_screen.dart';

class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  final String memberId;

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  /// 행사관리(events.json)에 정의된 행사명 집합 — 관리목록누락 판정용.
  Set<String> _knownEvents = <String>{};
  bool _knownLoaded = false;

  /// 행사관리 목록 원본(연도별 선택·복수선택용). defined 행사만 담는다.
  List<Map<String, dynamic>> _knownEventList = [];

  /// 마스터 전용 "현재 비밀번호" 조회 future 캐시 (리빌드 시 재조회 방지).
  Future<Map<String, dynamic>?>? _pwFuture;
  String? _pwFutureKey;

  /// 이름 공개/비공개 서버 저장 진행 중 여부(연타 방지).
  bool _nameBusy = false;

  /// 멘토·페런츠 인적사항·메달 연동 캐시 (인가번호 → 데이터).
  Map<String, dynamic> _linkProfilesCache = {};
  final Map<String, Future<Map<String, dynamic>>> _medalFuture = {};

  /// 임시저장(초안) 개수 — 상단 버튼 배지용(관리자·마스터 전용).
  int _draftCount = 0;

  /// 행사별 참석자 행 캐시 — `'<연도>::<행사명>'` → attendees 리스트.
  ///
  /// 추가입력사항 카드가 이 회원의 참가 행사를 훑을 때 쓴다.
  /// 화면 진입 시 **한 번만** 받아오고, 실패한 키는 다시 시도하지 않는다.
  final Map<String, List<Map<String, dynamic>>> _extraCache = {};
  final Set<String> _extraTried = Set<String>();
  bool _extraLoading = false;

  /// 이 회원의 참가 행사들의 attendees 를 받아 캐시를 채운다.
  ///
  /// 과도한 요청을 막기 위해 **최대 12개 행사**까지만 조회한다(최근 순).
  Future<void> _loadEventExtras(Member m) async {
    if (_extraLoading) return;
    final nas = context.read<NasApi>();
    final names = m.eventAttend.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (names.isEmpty) return;
    final todo = <({String year, String name})>[];
    for (final full in names.take(12)) {
      final ym = RegExp(r'(\d{4})').firstMatch(full);
      final year = ym?.group(1) ?? '';
      final cands = <String>{full};
      if (full.contains('_')) cands.add(full.split('_').first);
      for (final t in cands) {
        final key = '$year::$t';
        if (_extraTried.contains(key)) continue;
        todo.add((year: year, name: t));
      }
    }
    if (todo.isEmpty) return;
    _extraLoading = true;
    var changed = false;
    for (final t in todo) {
      final key = '${t.year}::${t.name}';
      _extraTried.add(key);
      try {
        final e = await nas.eventGet(t.year, t.name);
        final inner = (e['event'] as Map?)?.cast<String, dynamic>() ?? e;
        final atts = ((inner['attendees'] as List?) ?? [])
            .map((x) => (x as Map).cast<String, dynamic>())
            .toList();
        if (atts.isNotEmpty) {
          _extraCache[key] = atts;
          changed = true;
        }
      } catch (_) {
        // 조용히 건너뛴다 — 카드가 없다고 화면이 깨지면 안 된다.
      }
    }
    _extraLoading = false;
    if (changed && mounted) setState(() {});
  }

  Future<void> _loadLinkProfiles() async {
    final p = await context.read<NasApi>().linkProfiles();
    if (mounted) setState(() => _linkProfilesCache = p);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadKnownEvents();
      _loadLinkProfiles();
      _logView();
      _loadDraftCount();
      _ensureFinanceLoaded();
    });
  }

  /// ── [요구 2026-10-26] 개인카드에 후원금·참가비 내역이 보이게 ─────────────
  ///  요구: "행사관리에서 후원금, 후원물품, 참가비, 각종 찬조 등록시 인가번호를
  ///        넣으면 개인카드에 후원금 및 금액 상당의 내역을 추가할 것"
  ///
  ///  ## 왜 비어 있었나
  ///   `_depositSection` 은 `context.watch<FinanceService>()` 로 **보기만** 하고
  ///   `load()` 를 부르는 곳이 **아무 데도 없었다**. 재무관리 화면을 한 번 열어야만
  ///   원장이 채워졌으므로, 개인 상세를 바로 열면 항상 '입금 내역이 없습니다' 였다.
  ///   (서버 401 문제와 **별개로** 존재하던 두 번째 원인)
  ///
  ///  ## 왜 force reload 가 아니라 '비었을 때만' 인가
  ///   상세 화면을 여러 번 오갈 때 매번 왕복하면 느려진다. 이미 채워져 있으면
  ///   건너뛰고, 비어 있을 때만 1회 조회한다. 새로고침은 당겨서 새로고침/재진입이
  ///   담당한다.
  void _ensureFinanceLoaded() {
    if (!mounted) return;
    final fs = context.read<FinanceService>();
    if (fs.transactions.isNotEmpty || fs.loading) return;
    fs.load();
  }

  /// 관리자·마스터에게 임시저장 개수를 알린다(상단 버튼 배지).
  Future<void> _loadDraftCount() async {
    final state = context.read<AppState>();
    if (!(state.isApp || state.isMaster)) return;
    final list = await MemberDraftStore.list();
    if (mounted) setState(() => _draftCount = list.length);
  }

  /// 프로필 열람 로그 기록 — 마스터/관리자/다른 회원이 본 이력을 남긴다.
  /// (개인·비인가자가 본인 프로필을 연 경우 서버가 중복 기록을 생략한다.)
  Future<void> _logView() async {
    try {
      final state = context.read<AppState>();
      final m = state.byId(widget.memberId);
      if (m == null) return;
      final ident = m.number.isNotEmpty ? m.number : m.phone;
      if (ident.trim().isEmpty) return;
      await state.logProfileView(ident);
      // 열람 기록이 갱신된 뒤 접속기록 섹션을 새로고침한다.
      if (mounted) setState(() => _accessLogRefreshKey++);
    } catch (_) {}
  }

  /// 접속기록 섹션 새로고침 트리거(열람 로그 기록 후 갱신).
  int _accessLogRefreshKey = 0;

  /// 상세 화면 스크롤 컨트롤러 — 하단 스크롤 유도 화살표(ScrollDownHint)에 사용.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadKnownEvents() async {
    try {
      final api = context.read<NasApi>();
      final ev = await api.eventList2(media: false);
      final names = <String>{};
      final list = <Map<String, dynamic>>[];
      for (final e in ev) {
        if (e['defined'] == false) continue;
        final t = '${e['title'] ?? ''}'.trim();
        if (t.isNotEmpty) {
          names.add(t);
          list.add({
            'title': t,
            'year': '${e['year'] ?? ''}',
            'period': '${e['period'] ?? ''}',
            'place': '${e['place'] ?? ''}',
          });
        }
      }
      if (mounted) {
        setState(() {
          _knownEvents = names;
          _knownEventList = list;
          _knownLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _knownLoaded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final m = state.byId(widget.memberId);
    if (m == null) {
      return const Scaffold(body: Center(child: Text('인가자를 찾을 수 없습니다')));
    }

    return Scaffold(
      body: ScrollDownHint(
        controller: _scroll,
        bottomInset: 16,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverAppBar(
              // ── 헤더 높이 (요구 2026-10-27) ─────────────────────────
              //  "개인카드에서 글자가 아래로 밀려서 안보임"
              //
              //  ## 원인 (실측)
              //   헤더 내용의 실제 필요 높이는 약 187dp 였다.
              //     상단 패딩 44 + 소속 13 + 6 + 인가번호카드 40 + 8 +
              //     이름 29 + 4 + '인가시:' 16 + 2 + '현재활동:' 15 + 하단 10
              //   그런데 expandedHeight 가 **176** 이라 마지막 두 줄
              //   ('인가시' / '현재활동')이 하단에서 잘려 나갔다.
              //   SliverAppBar 는 flexibleSpace 를 **클립**하므로 넘친
              //   글자는 '사라진 것처럼' 보인다. (사용자 스크린샷의 빨간 박스)
              //
              //  ## 수정
              //   ① expandedHeight 176 → **204** : 여유 17dp 확보.
              //   ② 상단 패딩 44 → 52 : 고정 툴바(56dp) 아래로 내려 소속명이
              //      툴바 아이콘과 겹치지 않게.
              //   ③ 그래도 넘칠 경우(폰트 스케일 확대·긴 '현재활동' 등)를 위해
              //      _header 안에서 FittedBox 로 **통째로 축소**한다.
              //      → 어떤 경우에도 글자가 잘리지 않는다(줄이지 않고 줄인다).
              expandedHeight: 204,
              pinned: true,
              backgroundColor: AppColors.purple,
              leading: const AppBackButton(label: '뒤로'),
              leadingWidth: 84,
              flexibleSpace: FlexibleSpaceBar(background: _header(m)),
              actions: [
                // (요구 복원) 홈 버튼 — 첫 화면(홈)으로 복귀.
                IconButton(
                  tooltip: '홈',
                  icon: const Icon(Icons.home_filled),
                  onPressed: _goHome,
                ),
                // 임시저장 불러오기 — 관리자·마스터 전용(작성중 복원).
                if (context.watch<AppState>().isApp ||
                    context.watch<AppState>().isMaster)
                  IconButton(
                    tooltip: '임시저장 불러오기',
                    icon: Badge(
                      isLabelVisible: _draftCount > 0,
                      label: Text('$_draftCount'),
                      child: const Icon(Icons.bookmark_added_outlined),
                    ),
                    onPressed: _openDrafts,
                  ),
                // (요구 복원) 개인정보 수정 버튼.
                IconButton(
                  tooltip: '개인정보 수정',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _edit(m),
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: '개인정보 출력 (PDF·JPG·엑셀·워드·PPT)',
                  onPressed: () => _exportPersonal(m),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_2),
                  tooltip: 'QR코드',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => QrScreen(member: m)),
                  ),
                ),
                const AppHomeEmblem(size: 24),
              ],
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _quickActions(m),
                  _approvalBanner(m),
                  // (요구) 인가정보·활동정보 위치 변경 — 개인 상세페이지 **최상단** 배치.
                  //   ① 범스카우트 인가 정보(인가 당시 정보)  ② ATAS 인가 정보
                  //   ③ 현재 활동 등록 정보
                  //   · 관리자·본인·타인 모두에게 가장 먼저 보이도록 최상단에 노출한다.
                  //   · (요구) "범스카우트인가정보페이지와 아타스인가정보를 분리할 것"
                  //     → 범인가/ATAS 를 **각각 별도 카드**로 나눠 노출한다.
                  _credentialCards(m),
                  _currentActivityCard(m),
                  // (요구 #4) 편집 화면 최상단: 평생회원 여부 → 연간회비 납부현황
                  //  · 관리자·마스터에게만 노출된다.
                  if (context.watch<AppState>().isApp ||
                      context.watch<AppState>().isMaster) ...[
                    _lifetimeSection(m),
                    _feeTracker(m),
                  ],
                  // (요구 #5) 순서: 연간회비 납부 이력 → 등록요청 → 자격
                  //  등록요청·자격은 MemberRegistrationRequestSection 내부 순서를 따른다.
                  MemberRegistrationRequestSection(
                    member: m,
                    isSelf: context.watch<AppState>().isSelfNumber(m.number),
                  ),
                  // (요구 #5-1) 후원금·후원물품 이력 — 수동입력 + 관리자·마스터 인증요청.
                  _donationSection(m),
                  _eventSection(m),
                  _eventExtraCard(m),
                  _depositSection(m),
                  _bankCard(m),
                  MerchActivitySection(
                    ident: m.number.isNotEmpty ? m.number : m.phone,
                    memberName: m.name,
                    phone: m.phone,
                    email: m.email,
                    memo: m.purchases,
                    canEditMemo: context.read<AppState>().isApp,
                    onEditMemo: () => _editPurchases(m),
                  ),
                  // 수요 대기(사전신청 순번) — 개인 상세 정보창에서 '수품 구매'와 함께 노출.
                  //  진행중인 수요조사가 없으면 위젯이 스스로 비표시된다.
                  PersonalSurveySection(
                    ident: m.number.isNotEmpty ? m.number : m.phone,
                  ),
                  // 정보 구분: 상세 정보 (인가·활동 정보는 상단으로 이동)
                  _infoCard(m),
                  _medalSection(m),
                  _membershipSection(m),
                  _passwordSection(m),
                  MemberAccessLogSection(
                    key: ValueKey('access-log-$_accessLogRefreshKey'),
                    member: m,
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 헤더 인가번호 서체 — `범#415` 와 `ATAS #13702` 가 **같은 상수**를 쓴다.
  ///
  ///  [요구 2026-10-27] "아타스글자 앞에 있는 아이콘은 삭제하고, 아타스
  ///   font사이즈와 크기를 범과 동일하게 해줘"
  ///
  ///  두 곳에 같은 숫자를 각각 적어 두면 다음 사람이 한쪽만 고쳐서
  ///  다시 어긋난다(이 화면에서 이미 한 번 겪은 일이다). 스타일을
  ///  하나로 묶어 **구조적으로** 같게 만든다.
  static const TextStyle _kHeaderNumberStyle = TextStyle(
    color: AppColors.purple,
    fontWeight: FontWeight.w900,
    fontSize: 22,
    height: 1.15,
  );

  /// 상세 헤더 — 좌(번호 박스+이름) / 우(사진) 2분할, 축소
  Widget _header(Member m) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      padding: const EdgeInsets.fromLTRB(16, 52, 16, 10),
      // ── [요구 2026-10-27] "개인카드에서 글자가 아래로 밀려서 안보임" ──
      //  expandedHeight 를 204 로 늘려 여유를 두었지만, 그것만으로는
      //  폰트 스케일 확대·긴 소속명 같은 경우를 보장하지 못한다.
      //  SliverAppBar 의 flexibleSpace 는 넘친 부분을 **클립**하기 때문에
      //  한 번 잘리면 사용자에게는 '데이터가 없는 것'처럼 보인다.
      //  → 내용 전체를 FittedBox(scaleDown) 로 감싸, 넘칠 때 **줄이지 않고
      //    통째로 축소**한다. 어떤 조건에서도 글자가 사라지지 않는다.
      child: LayoutBuilder(
        builder: (context, c) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: c.maxWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 좌측 패널: 인가번호(박스) + 이름
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // (요구#2) 모든 창 상단에 중앙회 브랜드 동일 노출
                        Text(
                          m.corpsOrgName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // 인가번호 + ATAS 인가번호 — **하나의 카드**에 나란히.
                        //
                        // (요구) "atas인가번호를 범스카우트 표시 옆에 노출할 것"
                        // (요구) "디자인 발란스를 맞춰야지 / 너무 언발란스 해"
                        //
                        // ## 왜 두 개의 박스 → 하나의 카드로 바꿨나
                        //  이전 구현은 흰 박스(높이 44dp, 글자 22)와 금색 배지
                        //  (높이 32dp, 글자 14)를 Wrap 으로 나란히 두었다. 높이·글자
                        //  크기·테두리가 모두 달라 **두 칸이 어긋나 보였다**(사용자 지적).
                        //  두 개를 따로 두는 한 높이를 맞춰도 '크기가 다른 두 물건'이
                        //  남는다. 그래서 **하나의 흰 카드 안**에 좌(범인가번호) ·
                        //  구분선 · 우(ATAS 인가번호)를 넣어 한 덩어리로 묶었다.
                        //   · 좌 : 범인가번호(은하인가번호) — 22pt / w900
                        //   · 우 : ATAS 인가번호 — **22pt / w900 (좌와 동일)**
                        //   · 사이에 얇은 세로 구분선 → "서로 다른 두 체계"임을 표시
                        //  높이가 구조적으로 같아질 수밖에 없고, 폭이 모자라면
                        //  FittedBox 가 통째로 축소해 잘림이 없다.
                        //
                        // [요구 2026-10-27] "아타스글자 앞에 있는 아이콘은 삭제하고,
                        //  아타스font사이즈와 크기를 범과 동일하게 해줘"
                        //  → 종전에는 ATAS 앞에 금색 훈장 아이콘(Icons.military_tech,
                        //    16dp)을 두고 글자를 15pt/w800 으로 '부 정보'로 낮춰
                        //    두었다. 사용자는 ① 아이콘을 없애고 ② **글자 크기·굵기를
                        //    범인가번호와 똑같이** 해 달라고 했다. 두 번호가 같은
                        //    무게로 읽히도록 아이콘·여백을 제거하고 22pt/w900 로
                        //    통일했다. 두 체계의 구분은 **세로 구분선 하나**가 맡는다.
                        //
                        // ## 폭 예산 (실측: NanumGothic Bold @22 → 범#415=74.0px,
                        //    ATAS #13702=142.1px). 390px 기기에서 흰 카드 가용폭은
                        //    `390 - 16*2 - 12(사진간격) - 104(사진) - 4(테두리)` ≈ 234px.
                        //    두 글자 + 구분선(1) + 좌우여백(6*2) = 229px → **거의 꽉
                        //    차지만 잘리지 않는다.** 22pt 를 그대로 살리려고 카드
                        //    내부 여백 14→10, 구분선 여백 11→6 으로 줄였다(종전엔
                        //    239px 라 0.88배로 축소됐다). 더 좁은 기기에서는
                        //    FittedBox 가 좌·우를 **같은 배율로** 줄이므로 두 글자의
                        //    상대 크기는 언제나 동일하다 — 이게 `_kHeaderNumberStyle`
                        //    을 공유하는 이유이기도 하다.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.tigerGold,
                              width: 2,
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // ① 범스카우트(은하스카우트) 인가번호 — 주 정보
                                //
                                //  [요구 2026-10-27] "은하 스카우트를 G라고 구분하는 것은
                                //   매우 좋음 / 개인카드에는 G대신 은하로 표기해야 함"
                                //  → 명부·목록은 `G43`(구분자) 그대로 두고, **개인카드**
                                //    에서만 `은하#43` 으로 말머리를 쓴다(cardNumberLabel).
                                //    범 카드의 `범#415` 와 같은 문법이 되어 두 카드가
                                //    한 규칙으로 읽힌다.
                                Text(
                                  m.cardNumberLabel,
                                  style: _kHeaderNumberStyle,
                                ),
                                // ② ATAS 인가번호 — 값이 있을 때만. 범인가와 별개이므로
                                //    세로 구분선으로 '다른 체계'임을 드러낸다.
                                //    서체 스펙은 ①과 **완전히 동일**(22/w900/purple).
                                //    ATAS 는 부제가 아니라 동급의 인가번호다.
                                //    (아이콘을 없앤 이유는 위 카드 주석 참조)
                                if (m.atasNo.trim().isNotEmpty) ...[
                                  Container(
                                    width: 1,
                                    height: 24,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    color: AppColors.purple.withValues(
                                      alpha: 0.22,
                                    ),
                                  ),
                                  Text(
                                    'ATAS #${m.atasNo.trim()}',
                                    style: _kHeaderNumberStyle,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Flexible(
                              child: MarqueeText(
                                m.name.isEmpty ? '(이름없음)' : m.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (m.lifetimeMember) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.star,
                                color: AppColors.tigerGold,
                                size: 20,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 범인가시(인가 당시) 소속 — 현재활동과 구분.
                        if (m.league.isNotEmpty || m.unit.isNotEmpty)
                          MarqueeText(
                            '인가시: ${[m.league, m.unit].where((e) => e.isNotEmpty).join(' · ')}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        // 현재활동 소속 — 인가시와 다르거나 값이 있으면 노출.
                        if ((m.regLeague.isNotEmpty &&
                                m.regLeague != m.league) ||
                            (m.regUnit.isNotEmpty && m.regUnit != m.unit) ||
                            m.position.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: MarqueeText(
                              '현재활동: ${[if (m.regLeague.isNotEmpty) m.regLeague, if (m.regUnit.isNotEmpty) m.regUnit, if (m.position.isNotEmpty) m.position].join(' · ')}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 우측 패널: 사진 (없으면 회색 스카우트 실루엣)
                  GestureDetector(
                    onTap: () => showPhotoPip(
                      context,
                      name: m.name,
                      number: m.number,
                      atasNo: m.atasNo,
                      league: m.league,
                      unit: m.unit,
                      photoPath: m.photoPath,
                      fallbackPhotoUrl:
                          context.read<AppState>().serverPhotoUrlFor(
                            m.number,
                          ) ??
                          '',
                    ),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        MemberAvatar(
                          name: m.name,
                          photoPath: m.photoPath,
                          fallbackPhotoUrl:
                              context.watch<AppState>().serverPhotoUrlFor(
                                m.number,
                              ) ??
                              '',
                          league: m.league,
                          number: m.number,
                          showNumber: false,
                          square: true,
                          size: 104,
                        ),
                        // 확대 아이콘 힌트
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.zoom_out_map,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _quickActions(Member m) {
    final state = context.watch<AppState>();
    final actions = [
      _QA(
        '전화',
        Icons.phone,
        AppColors.scoutGreen,
        () => _launch('tel:${m.phone}'),
        m.phone.isNotEmpty,
      ),
      _QA(
        '문자',
        Icons.sms,
        AppColors.taegeukBlue,
        () => _launch('sms:${m.phone}'),
        m.phone.isNotEmpty,
      ),
      _QA(
        '메일',
        Icons.email,
        AppColors.taegeukRed,
        () => _launch('mailto:${m.email}'),
        m.email.contains('@'),
      ),
      _QA('QR', Icons.qr_code_2, AppColors.purple, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => QrScreen(member: m)),
        );
      }, true),
      _QA('복사', Icons.copy, AppColors.textGray, () => _copy(m), true),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: actions.map((a) => _qaButton(a)).toList(),
          ),
        ),
        // 관리자·마스터 전용 — 이름 공개/비공개 좌우 토글
        if (state.isApp || state.isMaster) _nameVisibleToggle(m),
      ],
    );
  }

  /// 이름 공개/비공개 좌우 선택 버튼 (관리자·마스터). 다른 회원 혼란 방지.
  Widget _nameVisibleToggle(Member m) {
    final visible = m.nameVisible;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: visible
              ? AppColors.scoutGreen.withValues(alpha: 0.08)
              : AppColors.taegeukRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (visible ? AppColors.scoutGreen : AppColors.taegeukRed)
                .withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              visible ? Icons.visibility : Icons.visibility_off,
              size: 16,
              color: visible ? AppColors.scoutGreen : AppColors.taegeukRed,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                visible ? '이름 공개 중 (다른 회원에게 표시)' : '이름 비공개 (다른 회원에게 숨김)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SegmentedButton<bool>(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(value: true, label: Text('공개')),
                ButtonSegment(value: false, label: Text('비공개')),
              ],
              selected: {visible},
              onSelectionChanged: _nameBusy
                  ? null
                  : (s) => _setNameVisible(m, s.first),
            ),
            if (_nameBusy)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setNameVisible(Member m, bool visible) async {
    if (_nameBusy) return; // 연타 방지 (서버 저장은 순차 처리)
    if (m.nameVisible == visible) return;
    final ident = m.number.isNotEmpty ? m.number : m.phone;
    final state = context.read<AppState>();
    // ── 낙관적(즉시) 반영 — 서버 왕복을 기다리지 않고 UI를 바로 갱신 ──
    state.setNameVisible(m.id, visible);
    setState(() => _nameBusy = true);
    try {
      final r = await context.read<NasApi>().setMemberNameVisible(
        ident: ident,
        visible: visible,
      );
      if (!mounted) return;
      if (r['ok'] == true) {
        _snack(visible ? '이름을 공개로 설정했습니다.' : '이름을 비공개로 설정했습니다.');
      } else {
        // 실패 → 되돌림
        state.setNameVisible(m.id, !visible);
        _snack('변경 실패: ${r['error']}');
      }
    } catch (e) {
      if (!mounted) return;
      state.setNameVisible(m.id, !visible); // 되돌림
      _snack('오류: $e');
    } finally {
      if (mounted) setState(() => _nameBusy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _qaButton(_QA a) {
    final enabled = a.enabled;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? a.onTap : null,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: a.color.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(a.icon, color: a.color, size: 26),
            ),
            const SizedBox(height: 5),
            Text(
              a.label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 중앙회 계좌정보(3개) — **모든 회원 창**(인가자·비인가 포함)에서 노출(요구).
  ///   · 대표(참가비·후원 등) / 수품구매계좌 / 행사비계좌 — 각 계좌에 송금·복사 버튼.
  ///   · [DonationAccounts] 위젯 재사용(접기/펼치기 토글 자동 제공, 기본 펼침).
  Widget _bankCard(Member m) {
    return _section(
      title: '중앙회 계좌 (3개)',
      icon: Icons.account_balance,
      child: const DonationAccounts(
        fontSize: 11.5,
        title: '참가비 · 수품구매 · 행사비 납부 계좌',
        showHolder: true,
      ),
    );
  }

  /// 개인별 입금 내역 — 후원/수품구매/참가비 등 모든 입금을 즉시 확인
  Widget _depositSection(Member m) {
    final fs = context.watch<FinanceService>();
    final deposits = fs.depositsOf(m.number, corps: m.corps);
    final total = deposits.fold<int>(0, (s, t) => s + t.amount);
    final byCat = <String, int>{};
    for (final t in deposits) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    }
    return _section(
      title: '입금 내역 (${deposits.length}건 · ${_won(total)}원)',
      icon: Icons.savings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (byCat.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in byCat.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${e.key} ${_won(e.value)}원',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.purple,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (deposits.isEmpty)
            Row(
              children: [
                Text(
                  '입금 내역이 없습니다.',
                  style: TextStyle(color: AppColors.textGray, fontSize: 13),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _addDeposit(m),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('입금 추가'),
                ),
              ],
            )
          else ...[
            for (final t in deposits)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      _depositIcon(t.category),
                      size: 18,
                      color: AppColors.scoutGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${_depositLabel(t.category)}'
                                  '${t.event.isNotEmpty ? ' · ${t.event}' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // ── [요구 2026-10-26] '기타후원' 꼬리표 ──
                              //  요구: "기타후원도 표시할 것"
                              //  후원금/후원물품/참가비 로 분류되지 않는 찬조·기타
                              //  후원(차량·의전 등)을 한눈에 구분할 수 있게 배지를
                              //  붙인다. 금액이 0원이어도(현물·재능 후원) 목록에는
                              //  남겨 '무엇을 후원했는지' 기록이 사라지지 않게 한다.
                              if (_isOtherDonation(t.category)) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.tigerGold.withValues(
                                      alpha: 0.20,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '기타후원',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '${t.date}'
                            '${t.context.isNotEmpty ? ' · ${t.context}' : ''}'
                            '${t.memo.isNotEmpty ? ' · ${t.memo}' : ''}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_won(t.amount)}원',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.scoutGreen,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _addDeposit(m, existing: t),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.edit,
                          size: 15,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _addDeposit(m),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('입금 추가'),
              ),
            ),
          ],
          Text(
            '* 입금 내역은 재무 관리 화면과 NAS 데이터베이스에 즉시 반영됩니다.',
            style: TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Future<void> _addDeposit(Member m, {FinanceTransaction? existing}) async {
    final fs = context.read<FinanceService>();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FinanceTransactionEditScreen(
          finance: fs,
          members: [m],
          existing: existing,
        ),
      ),
    );
    if (mounted) fs.load();
  }

  /// ── [요구 2026-10-26] 입금 내역 카테고리 표시 규칙 ──────────────────────
  ///  요구: "기타후원도 표시할 것"
  ///
  ///  ## 왜 필요했나
  ///   종전에는 아이콘 분기가 `후원 / 수품구매 / 참가비` **3개만** 알고,
  ///   나머지는 전부 `Icons.savings` 로 떨어졌다. 그래서 행사관리에서
  ///   `기타후원`·`식사후원`·`물품후원`·`후원금` 으로 등록한 내역이
  ///   회색 저금통 아이콘 + 원문 그대로의 라벨로만 보여 **구분이 안 됐다**.
  ///
  ///  ## 분류 원칙
  ///   후원 계열(후원/후원금/후원물품/식사후원/물품후원/찬조/기타/기타후원)을
  ///   한 묶음으로 보되, **라벨과 아이콘은 원문을 살려** 무엇을 후원했는지
  ///   알 수 있게 한다. 금액만 뭉개면 기록의 의미가 사라진다.
  static bool _isOtherDonation(String cat) {
    final c = cat.trim();
    if (c.isEmpty) return true;
    if (c == '기타' || c == '기타후원' || c == '찬조' || c == '각종찬조') {
      return true;
    }
    // 후원 계열인데 후원금/후원물품 어느 쪽으로도 명시되지 않은 것.
    return c.contains('후원') == false &&
        c.contains('식사') == false &&
        c.contains('물품') &&
        c != '후원';
  }

  static IconData _depositIcon(String cat) {
    final c = cat.trim();
    switch (c) {
      case '후원':
      case '후원금':
      case '기타후원':
      case '찬조':
      case '각종찬조':
        return Icons.volunteer_activism;
      case '후원물품':
      case '물품후원':
        return Icons.inventory_2;
      case '식사후원':
        return Icons.restaurant;
      case '수품구매':
        return Icons.shopping_bag;
      case '참가비':
        return Icons.event_available;
      case '연회비':
      case '평생회비':
        return Icons.badge;
      default:
        // '기타' 등 — 후원 계열이면 후원 아이콘, 아니면 저금통.
        if (c.contains('후원') || c.contains('찬조')) {
          return Icons.volunteer_activism;
        }
        return Icons.savings;
    }
  }

  /// 카테고리 원문을 그대로 살리되 빈 값만 '기타후원' 으로 보정한다.
  static String _depositLabel(String cat) {
    final c = cat.trim();
    if (c.isEmpty) return '기타후원';
    // 금액 0원짜리 현물·재능 후원은 '기타' 만으로는 의미가 없어 후원임을 밝힌다.
    if (c == '기타') return '기타후원';
    return c;
  }

  static String _won(int v) {
    final neg = v < 0;
    final s = v.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${neg ? '-' : ''}$b';
  }

  /// (요구 #4) 평생회원 여부 — 편집 화면 최상단. 관리자·마스터·본인에게 노출.
  ///  회원은 스스로 '지정'할 수 없고, '평생회원 등록요청'만 가능하다.
  Widget _lifetimeSection(Member m) {
    return _section(
      title: '평생회원 여부',
      icon: Icons.workspace_premium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: m.lifetimeMember
                  ? const LinearGradient(
                      colors: [AppColors.tigerGold, Color(0xFFE09F00)],
                    )
                  : null,
              color: m.lifetimeMember ? null : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  m.lifetimeMember ? Icons.star : Icons.star_border,
                  color: m.lifetimeMember ? Colors.white : Colors.grey.shade600,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  m.lifetimeMember
                      ? (m.lifetimeSince.isNotEmpty
                            ? '평생회원 (${m.lifetimeSince})'
                            : '평생회원')
                      : '평생회원 미등록',
                  style: TextStyle(
                    color: m.lifetimeMember
                        ? Colors.white
                        : Colors.grey.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // (요구) 회원은 스스로 평생회원으로 '지정'할 수 없다 → '요청'만 가능.
          //  · 인가자 창에서도 실행 가능. 관리자·마스터가 승인한다.
          _feeRequestButtons(m, 'lifetime'),
        ],
      ),
    );
  }

  Widget _feeTracker(Member m) {
    final state = context.watch<AppState>();
    // 납부 연도 변경은 관리자·마스터 전용, 평생회원 지정은 마스터 전용이다.
    //  (일반 회원은 '등록요청'으로 요청 → 관리자·마스터 승인)
    final canAdmin = state.isApp || state.isMaster;
    final years = <String>{
      '2024',
      '2025',
      '2026',
      '2027',
      ...m.feeYears.keys,
    }.toList()..sort();
    return _section(
      title: '연간회비 납부 이력',
      icon: Icons.card_membership,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: years.map((y) {
              final paid = m.feeYears[y] == true;
              return GestureDetector(
                onTap: canAdmin
                    ? () {
                        final map = Map<String, bool>.from(m.feeYears);
                        map[y] = !paid;
                        context.read<AppState>().save(
                          m.copyWith(feeYears: map),
                        );
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: paid ? AppColors.scoutGreen : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        paid ? Icons.check_circle : Icons.cancel_outlined,
                        size: 16,
                        color: paid ? Colors.white : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        y,
                        style: TextStyle(
                          color: paid ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            canAdmin
                ? '* 연도를 눌러 납부 여부를 변경할 수 있습니다.'
                : '* 연회비 납부 여부는 관리자·마스터가 관리합니다. (본인은 등록요청)',
            style: TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
          const SizedBox(height: 10),
          // (요구) 연회비 납부 '요청' — 인가자 창에서도 실행 가능(관리자 승인).
          _feeRequestButtons(m, 'fee'),
        ],
      ),
    );
  }

  /// (요구) 평생회비·연회비 '납부 요청' 버튼 줄.
  ///  · 평생회비: '평생회원 등록요청' → 납부 여부(오래전/최근/납부예정)·납부자 이름.
  ///  · 연회비:   '연회비 납부 요청'   → 연도 · 납부완료/납부예정 · 납부자 이름.
  ///  · 두 항목 모두 인가자 편집창 이외에도 인가자 창에서 실행 가능하다.
  Widget _feeRequestButtons(Member m, String type) {
    final state = context.watch<AppState>();
    final canRequest = state.isApp || state.isMaster || state.isSelfAccess;
    if (!canRequest) return const SizedBox.shrink();
    final isLifetime = type == 'lifetime';
    final col = isLifetime ? AppColors.lifetimeGold : AppColors.scoutGreen;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: col,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () async {
            final ok = await showFeePaymentRequestSheet(
              context,
              member: m,
              type: type,
            );
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  ok ? '등록요청을 제출했습니다. 관리자 승인을 기다려 주세요.' : '요청이 취소되었습니다.',
                ),
              ),
            );
          },
          icon: Icon(isLifetime ? Icons.star : Icons.card_membership, size: 16),
          label: Text(
            isLifetime ? '평생회원 등록요청' : '연회비 납부 요청',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.purple,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () => showPaymentAccountsSheet(context),
          icon: const Icon(Icons.account_balance_wallet, size: 16),
          label: const Text(
            '지급납부',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  /// [삭제됨] 수품구매현황 단독 섹션 — MerchActivitySection으로 통합되어 제거.
  /// (메모 표시·편집은 MerchActivitySection의 memo/onEditMemo로 이관)

  Future<void> _editPurchases(Member m) async {
    final ctrl = TextEditingController(text: m.purchases);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
        scrollable: true,
        title: const Text('수품구매현황'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(
            labelText: '구매 내역',
            hintText: '한 줄에 하나씩 입력\n예: 2025.03 반팔티 1개',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().save(
      m.copyWith(purchases: ctrl.text.trim()),
    );
    if (mounted) setState(() {});
  }

  Widget _eventSection(Member m) {
    // [최종 결정 반영 · turn9-4] 개인정보(개인 프로필/상세)에 노출되는 행사리스트는
    // '실제 참여한 행사만' 보여준다. (PDF page27 의 "누락없이 모든 행사리스트 노출"과
    //  충돌하나, 사용자 지시 "가장 마지막 내용이 최종 의사결정"에 따라 참여한 행사만 노출.)
    //  - 참여(attend == true) 로 등록된 행사만 리스트에 포함한다.
    //  - '미등록'/'불참' 행사는 목록에서 제외한다(참여한 요약에만 반영됨).
    final events =
        m.eventAttend.entries
            .where((e) => e.value == true)
            .map((e) => e.key)
            .toList()
          ..sort((a, b) {
            final ya = RegExp(r'\d{4}').firstMatch(a)?.group(0) ?? '0000';
            final yb = RegExp(r'\d{4}').firstMatch(b)?.group(0) ?? '0000';
            if (ya != yb) return yb.compareTo(ya);
            return b.compareTo(a);
          });
    final attendedCount = events.length;
    // 본인이 제안했으나 아직 승인 전(심사중)인 행사 — '관리목록누락행사-심사중'
    final pending = m.pendingEventNames
        .where((e) => e.trim().isNotEmpty && !events.contains(e))
        .toList();
    return _section(
      title: '행사참가 이력',
      icon: Icons.event,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pending.isNotEmpty) ...[
            for (final p in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_top,
                      size: 15,
                      color: AppColors.tigerGold,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: MarqueeText(
                        p,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.tigerGold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.tigerGold.withValues(alpha: 0.6),
                        ),
                      ),
                      child: const Text(
                        '관리목록누락행사-심사중',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.lifetimeGold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
          ],
          if (events.isEmpty && pending.isEmpty)
            Row(
              children: [
                Flexible(
                  child: Text(
                    '아직 참여로 등록된 행사가 없습니다.',
                    style: TextStyle(color: AppColors.textGray, fontSize: 13),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _addEvent(m),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('행사 추가'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '참여 행사 $attendedCount건'
                  ' · 참여한 행사만 표시',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ...events.map((e) {
                  final hasKey = m.eventAttend.containsKey(e);
                  final attend = m.eventAttend[e] == true;
                  final missing = _knownLoaded && !_knownEvents.contains(e);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: attend,
                              activeColor: AppColors.taegeukBlue,
                              title: Text(
                                e,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                !hasKey ? '미등록' : (attend ? '참가' : '불참'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: attend
                                      ? AppColors.taegeukBlue
                                      : (hasKey
                                            ? AppColors.textGray
                                            : AppColors.lifetimeGold),
                                  fontWeight: attend
                                      ? FontWeight.w700
                                      : (hasKey
                                            ? FontWeight.w400
                                            : FontWeight.w700),
                                ),
                              ),
                              onChanged: (v) {
                                final map = Map<String, bool>.from(
                                  m.eventAttend,
                                );
                                map[e] = v == true;
                                context.read<AppState>().save(
                                  m.copyWith(eventAttend: map),
                                );
                                setState(() {});
                              },
                            ),
                          ),
                          if (missing)
                            IconButton(
                              tooltip: '관리목록누락 행사 삭제 (내 프로필에서 제거)',
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: AppColors.taegeukRed,
                              ),
                              onPressed: () => _removeEventName(m, e),
                            ),
                        ],
                      ),
                      if (missing)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.tigerGold.withValues(
                                alpha: 0.16,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.tigerGold.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            child: const Text(
                              '(관리목록누락)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.lifetimeGold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                }),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _addEvent(m),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('행사 추가'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 관리목록누락 행사명을 본인 프로필(eventAttend)에서 제거.
  Future<void> _removeEventName(Member m, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('행사명 삭제'),
        content: Text(
          '“$name” 은(는) 행사관리 목록에 없는 행사입니다.\n'
          '내 프로필(행사참가)에서 이 행사명을 삭제할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final map = Map<String, bool>.from(m.eventAttend);
    map.remove(name);
    await context.read<AppState>().save(m.copyWith(eventAttend: map));
    if (mounted) setState(() {});
  }

  /// (요구 #8·#10) 행사 추가 — '행사관리'의 행사만들기와 동일한 형식.
  ///  · 연도를 선택하면 해당 연도 행사리스트 중에서 고를 수 있고 복수선택도 가능.
  ///  · 목록에 없는 새 행사는 직접 만들어 등록요청(관리자·마스터 승인 후 등록).
  Future<void> _addEvent(Member m) async {
    final state = context.read<AppState>();
    final isAdmin = state.isApp || state.isMaster;
    // 연도 집합 (행사관리 목록 기준 + 올해)
    final years = <String>{
      ..._knownEventList.map((e) => '${e['year'] ?? ''}'.trim()),
      '${DateTime.now().year}',
    }.where((y) => y.isNotEmpty).toList()..sort((a, b) => b.compareTo(a));
    String year = years.isNotEmpty ? years.first : '${DateTime.now().year}';
    final selected = <String>{}; // 복수선택
    final titleCtrl = TextEditingController();
    final periodCtrl = TextEditingController();
    final placeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool addNew = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final inYear =
              _knownEventList
                  .where((e) => '${e['year']}'.trim() == year)
                  .toList()
                ..sort((a, b) => '${a['title']}'.compareTo('${b['title']}'));
          return AlertDialog(
            title: const Text('행사 추가'),
            content: SizedBox(
              width: 400,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 연도 선택 (요구 #10)
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: AppColors.purple,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '연도 선택',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: year,
                          isDense: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: years
                              .map(
                                (y) => DropdownMenuItem(
                                  value: y,
                                  child: Text('$y년'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setD(() {
                            year = v ?? year;
                            selected.clear();
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '해당 연도 행사 — 복수선택 가능',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: inYear.isEmpty
                        ? const Center(
                            child: Text(
                              '이 연도에 등록된 행사가 없습니다',
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12.5,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: inYear.length,
                            itemBuilder: (_, i) {
                              final e = inYear[i];
                              final t = '${e['title']}';
                              final chk = selected.contains(t);
                              return CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: chk,
                                activeColor: AppColors.purple,
                                title: Text(
                                  t,
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                                subtitle:
                                    [
                                      if ('${e['period']}'.trim().isNotEmpty)
                                        '${e['period']}',
                                      if ('${e['place']}'.trim().isNotEmpty)
                                        '${e['place']}',
                                    ].join(' · ').isEmpty
                                    ? null
                                    : Text(
                                        [
                                          if ('${e['period']}'
                                              .trim()
                                              .isNotEmpty)
                                            '${e['period']}',
                                          if ('${e['place']}'.trim().isNotEmpty)
                                            '${e['place']}',
                                        ].join(' · '),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                onChanged: (v) => setD(() {
                                  if (v == true) {
                                    selected.add(t);
                                  } else {
                                    selected.remove(t);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                  // 새 행사 직접 만들기 (요구 #8) — 관리자/마스터가 아니면 승인 요청.
                  const Divider(height: 18),
                  Row(
                    children: [
                      Checkbox(
                        value: addNew,
                        onChanged: (v) => setD(() => addNew = v == true),
                      ),
                      Expanded(
                        child: Text(
                          isAdmin
                              ? '새 행사 직접 만들기 (즉시 등록)'
                              : '새 행사 직접 만들기 (관리자 승인 후 등록)',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (addNew) ...[
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: '행사명 *',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: periodCtrl,
                      decoration: const InputDecoration(
                        labelText: '행사기간 (예: 2026.03.14~15)',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: placeCtrl,
                      decoration: const InputDecoration(
                        labelText: '장소',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '행사 소개/개요',
                        isDense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(addNew ? '등록' : '추가 (${selected.length})'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted) return;

    // ── 새 행사 직접 만들기 ──
    if (addNew) {
      final title = titleCtrl.text.trim();
      if (title.isEmpty) {
        _snack('행사명을 입력하세요');
        return;
      }
      if (isAdmin) {
        // 관리자·마스터는 즉시 행사로 등록 (행사관리 '행사만들기'와 동일).
        try {
          await context.read<NasApi>().eventCreate(
            year: year,
            title: title,
            period: periodCtrl.text.trim(),
            place: placeCtrl.text.trim(),
            desc: descCtrl.text.trim(),
            by: state.who.isNotEmpty
                ? state.who
                : (state.isMaster ? '마스터' : '관리자'),
          );
          await _loadKnownEvents();
          _snack('행사를 만들고 참가 이력에 추가했습니다');
        } catch (e) {
          _snack('행사 생성 실패: $e');
          return;
        }
        final map = Map<String, bool>.from(m.eventAttend);
        map[title] = true;
        await context.read<AppState>().save(m.copyWith(eventAttend: map));
      } else {
        // 개인은 제안 → 관리자·마스터 승인 후 등록(심사중으로 표시).
        try {
          await context.read<NasApi>().eventPrivateCreate(
            year: year,
            title: title,
            period: periodCtrl.text.trim(),
            place: placeCtrl.text.trim(),
            desc: descCtrl.text.trim(),
          );
          state.refresh();
          _snack('‘$title’ 행사를 등록요청했습니다 (관리자 승인 대기)');
        } catch (e) {
          _snack('행사 등록요청 실패: $e');
        }
      }
      if (mounted) setState(() {});
      return;
    }

    // ── 기존 행사 복수 추가 ──
    if (selected.isEmpty) {
      _snack('추가할 행사를 선택하세요');
      return;
    }
    final map = Map<String, bool>.from(m.eventAttend);
    for (final s in selected) {
      map[s] = true;
    }
    await context.read<AppState>().save(m.copyWith(eventAttend: map));
    _snack('${selected.length}건의 행사를 추가했습니다');
    if (mounted) setState(() {});
  }

  /// 미승인(승인 대기/보류) 일반회원 안내 배너. 관리자·마스터는 즉시 처리 가능.
  Widget _approvalBanner(Member m) {
    if (!m.isRegular) return const SizedBox.shrink();
    final st = m.approvalStatus;
    if (st != 'pending' && st != 'held') return const SizedBox.shrink();
    final state = context.watch<AppState>();
    final isPending = st == 'pending';
    final color = isPending ? AppColors.tigerGold : AppColors.taegeukRed;
    final label = isPending ? '미승인 회원 (승인 요청됨)' : '보류된 회원';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPending ? Icons.hourglass_top : Icons.pause_circle_outline,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '미승인 회원들에 대한 안내 : 관리자에게 승인 요청을 해주십시요.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textDark,
              height: 1.35,
            ),
          ),
          if (state.isApp || state.isMaster) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.scoutGreen,
                    minimumSize: const Size(0, 38),
                  ),
                  onPressed: () => _approvalSet(state, m, 'approve'),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('승인', style: TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    foregroundColor: AppColors.taegeukRed,
                  ),
                  onPressed: () => _approvalSet(state, m, 'hold'),
                  icon: const Icon(Icons.pause_circle_outline, size: 16),
                  label: const Text('보류', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              '권한에는 제한이 없으나, 관리자 승인 후 정상 회원으로 인정됩니다.',
              style: TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _approvalSet(AppState state, Member m, String action) async {
    final n = await state.setApproval(action, [m.id]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n > 0
              ? (action == 'approve' ? '승인했습니다' : '보류로 변경했습니다')
              : '처리 실패 — 잠시 후 다시 시도하세요',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 각인 메달(멘토·페런츠) 수상/수여 기록 — 개인프로필 연동.
  ///   · 받은 메달(awards) : 본인이 수여받은 각인 메달
  ///   · 수여한 메달(granted): 본인 이름·인가번호가 각인돼 남에게 준 메달
  Widget _medalSection(Member m) {
    final ident = m.number.isNotEmpty ? m.number : m.phone;
    if (ident.trim().isEmpty) return const SizedBox.shrink();
    final fut = _medalFuture.putIfAbsent(
      ident,
      () => context.read<NasApi>().memberMedals(number: ident),
    );
    return FutureBuilder<Map<String, dynamic>>(
      future: fut,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return const SizedBox.shrink();
        final awards = ((d['awards'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        final granted = ((d['granted'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        if (awards.isEmpty && granted.isEmpty) return const SizedBox.shrink();
        return _section(
          title: '각인 메달 (멘토·페런츠)',
          icon: Icons.workspace_premium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (awards.isNotEmpty) ...[
                const Text(
                  '받은 메달',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                for (final a in awards) _medalRow(a, '받음'),
              ],
              if (awards.isNotEmpty && granted.isNotEmpty)
                const SizedBox(height: 8),
              if (granted.isNotEmpty) ...[
                const Text(
                  '수여한 메달 (이름·인가번호 각인)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                for (final a in granted) _medalRow(a, '수여'),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _medalRow(Map<String, dynamic> a, String mode) {
    final kind = '${a['kindLabel'] ?? a['kind'] ?? ''}';
    final product = '${a['product'] ?? ''}';
    final created = '${a['created'] ?? ''}';
    final color = '${a['kind']}' == 'parent'
        ? AppColors.taegeukBlue
        : AppColors.purple;
    // 받은 메달: 이름 각인(누가 줬는지 표시 어려움) / 수여: 상대 이름
    final rcp = (a['recipient'] as Map?)?.cast<String, dynamic>();
    final detail = mode == '받음'
        ? (rcp != null
              ? '${rcp['unit'] ?? ''} ${rcp['name'] ?? ''}'.trim()
              : '')
        : '${a['buyerName'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.workspace_premium, size: 15, color: color),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              kind,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: MarqueeText(
              [
                product,
                if (detail.isNotEmpty) detail,
              ].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textDark),
            ),
          ),
          Text(
            created,
            style: const TextStyle(fontSize: 10, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  /// ① 현재활동 카드 — 소속연맹·등록단위대·직위.
  ///   · 현재활동(reg*) 값이 없으면 인가시 값을 "(인가시)" 표기로 폴백 노출.
  ///   · 이 데이터는 '현재활동기준' 통계의 근거가 된다.
  Widget _currentActivityCard(Member m) {
    final regL = m.regLeague.trim();
    final regU = m.regUnit.trim();
    final rows = <Widget>[
      _plainRow(
        '소속 연맹',
        regL.isNotEmpty
            ? regL
            : (m.league.trim().isEmpty ? '' : '${m.league} (인가시)'),
      ),
      _plainRow(
        '등록 단위대',
        regU.isNotEmpty
            ? regU
            : (m.unit.trim().isEmpty ? '' : '${m.unit} (인가시)'),
      ),
      _plainRow('직위', m.position),
    ];
    rows.removeWhere((w) => w is SizedBox);
    if (rows.isEmpty) return const SizedBox.shrink();
    return _section(
      title: '현재 활동 등록 정보',
      icon: Icons.play_circle_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  /// ② 범인가 정보 카드 — 인가 당시 정보를 한 번에 표시.
  ///   · 소속연맹·등록단위대·인가일·멘토대장·페런츠 (범인가자 통계의 근거).
  ///   · 멘토·페런츠는 **등록현황**으로서 값이 없어도 "미등록"을 항상 노출한다.
  ///   · 편집 권한(본인 또는 관리자·마스터)이 있으면 **그 자리에서 입력·수정**
  ///     할 수 있는 입력창(LinkCodeField)을 함께 노출한다.
  ///     (편집 화면과 동일한 기준: 멘티 인가번호 + 멘토/페런츠 인적사항)
  ///
  /// ## 범스카우트 인가정보 / ATAS 인가정보 **분리**
  /// (요구: "범스카우트인가정보페이지와 아타스인가정보를 분리할 것")
  /// 기존에는 ATAS 인가번호·영문 이름이 범인가 정보 카드 안에 섞여 있어, 인가
  /// 근거(연맹·단위대·인가일)와 ATAS 발급정보가 뒤섞여 보였다. 이제 카드를 둘로
  /// 나눈다:
  ///   ① [범스카우트 인가 정보] = 범인가 근거 + 멘토/페런츠
  ///   ② [ATAS 인가 정보]      = ATAS 인가번호 + 영문(로마자) 이름
  Widget _credentialCards(Member m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _credentialCard(m),
        _atasCard(m),
        // 멘토·페런츠 연결은 **별도 카드**로 내린다.
        //  (요구: "모든 회원 카드에 있던 atas 인가정보가 사라짐, 다시 노출해줘")
        //  원인: ATAS 카드가 '범인가 정보' 카드 **안에** 들어 있어서, 멘토·페런츠
        //  목록 + 정보수정요청 + 자녀대원 등록 섹션이 길게 붙은 탓에 ATAS 카드가
        //  화면 한참 아래로 밀려 보이지 않았다(사용자 스크린샷: 잘린 ATAS 카드).
        //  → 범인가 근거 → ATAS → 연결(멘토/페런츠) 3단으로 분리해 ATAS 를 위로 올린다.
        _linkCard(m),
      ],
    );
  }

  /// ① 범인가 정보 (인가 당시 정보) — **인가 근거 항목만**.
  ///    ATAS 항목은 ②, 멘토·페런츠 연결은 ③ 으로 분리했다.
  ///
  /// (요구: "범스카우트인가정보 맨 위에 atas처럼 범스카우트인가번호를 넣어줘")
  /// (요구: **"범스카우트인가정보 라고 길게 쓰니까 글자가 2줄 생김 /
  ///          범인가정보 로 줄여줘"**)
  ///  → 카드 제목을 '범인가 정보 (인가 당시 정보)' 로 축약하고, 항목 라벨도
  ///    '범인가번호' 로 짧게 쓴다. 은하스카우트도 같은 카드 구조를 쓰므로
  ///    제목은 소속에 따라 '은하인가 정보' 가 된다(길이가 짧아 1줄에 들어간다).
  Widget _credentialCard(Member m) {
    // [2026-10-29 서포터즈 사고] `corps == 'eunha' ? 은하 : 범` 이분법이라
    //  일반회원(서포터즈)이 **'범인가 정보'** 로 표시됐다. 서포터즈는 범
    //  인가자가 아니고 인가번호도 없다 → 3분법(범/은하/서포터즈)으로 고쳤다.
    return _section(
      title: m.credentialCardTitle,
      icon: Icons.verified_user,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _plainRow(m.numberRowLabel, m.numberRowValue),
          _plainRow('소속 연맹', m.league),
          _plainRow('등록 단위대', m.unit),
          // ── 인가일 ────────────────────────────────────────────────
          //  🐞 2026-11-02 (build #574) — 보고: "범스카우트 인가일을 인가정보에
          //  노출해줘".
          //
          //  원인: 종전에는 `_plainRow` 를 썼는데, 그 헬퍼는 **빈 값이면 행을
          //  아예 그리지 않는다**(ATAS 카드는 그래서 `_blankRow` 를 따로 쓴다).
          //  그래서 인가일이 비어 있는 회원은 '인가일' 항목이 **통째로 사라져**
          //  아예 없는 항목처럼 보였다.
          //  실측(운영 DB 2,242명): date 가 빈 회원 **57명**
          //  (예: 이소라 #893 — 연맹·단위대는 있는데 인가일만 공란).
          //
          //  수정: `_blankRow` 로 바꿔 **값이 없어도 자리를 지키고 `—`** 를
          //  표시한다. 이제 "인가일이 입력되지 않았다"와 "인가일 항목이 없다"가
          //  구별되고, 나중에 채울 자리도 남는다.
          //
          //  ※ 서포터즈(비인가 일반회원)는 범 인가 자체가 없으므로 인가일 행을
          //    만들지 않는다(있지도 않은 항목에 '미등록'을 띄우면 오해를 준다).
          //    실측: 서포터즈 13명 전원 date 공란 / 인가자 2,229명 중 44명 공란.
          //
          //  ※ 빈 값 표기는 `—` 가 아니라 **`미등록`**. 인가일은 '원래 없는 값'이
          //    아니라 '있어야 하는데 안 채운 값'이므로, "이 사람은 인가일이
          //    미등록"임을 바로 읽을 수 있어야 한다. (편집 화면의 '인가일'
          //    입력란에서 채우면 즉시 이 자리에 표시된다.)
          if (!m.isRegular)
            _blankRow('인가일', m.date, placeholder: '미등록'),
        ],
      ),
    );
  }

  /// ③ 멘토·페런츠·멘티·자녀대원 **연결 카드**.
  ///   · 멘티/멘토/페런츠는 `LinkPeopleTiles` 한 곳에서만 보여준다(중복 노출 제거).
  ///   · 자녀대원은 별도 섹션(자녀는 LinkPeopleTiles 에 없는 항목).
  Widget _linkCard(Member m) {
    final state = context.watch<AppState>();
    final canEdit =
        state.isApp || state.isMaster || state.isSelfNumber(m.number);
    return _section(
      title: '멘토 · 페런츠 · 멘티 연결',
      icon: Icons.hub_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinkPeopleTiles(
            member: m,
            profiles: _linkProfilesCache,
            canEdit: canEdit,
            onChanged: () {
              _loadLinkProfiles();
              context.read<AppState>().refresh();
            },
          ),
          // 승인대기중 안내 — 관리자·마스터 승인 전까지 명확히 표시(요구).
          if (m.linkApprovalStatus == 'pending') _linkPendingNotice(m),
          // [요구] 비인가회원 정보 수정요청 — 본인은 메모로 요청, 관리자·마스터는
          //  확인·수정. (본인+관리자+마스터 외에는 정보 수정 불가)
          _linkFixRequestSection(m),
          if (m.children.isNotEmpty || canEdit) ...[
            const Divider(height: 22),
            MenteeRegisterSection(
              member: m,
              kind: 'child',
              codes: m.children,
              canEdit: canEdit,
              onChanged: (v) => _saveLinks(m, children: v),
            ),
          ],
        ],
      ),
    );
  }

  /// 값이 비어 있어도 **자리를 지키는** 행 — ATAS·범인가 항목용.
  ///
  /// (요구: "아타스인가정보 중 인가번호만 있다면 나머지는 추후 입력할 수 있도록
  ///        항목만 만들고 비워 놔")
  /// [_plainRow] 는 빈 값을 숨기므로, 항목이 사라져 나중에 입력할 자리가 없어진다.
  /// 이 헬퍼는 비어 있으면 `—` 로 표시해 **항목을 항상 노출**한다.
  ///
  /// ## [placeholder] — 비었을 때의 안내 문구 (2026-11-02 추가)
  /// ATAS 처럼 '나중에 채울 정보'는 `—` 로 충분하지만, **인가일**처럼 '있어야
  /// 정상인 값'은 `—` 가 "값이 원래 없다"인지 "아직 안 넣었다"인지 모호하다.
  /// 그래서 문구를 바꿔 끼울 수 있게 열어 두고, 인가일에는 `미등록` 을 쓴다.
  /// 기본값 `—` 라 기존 호출부(ATAS)는 동작이 바뀌지 않는다.
  Widget _blankRow(
    String label,
    String value, {
    bool dense = false,
    String placeholder = '—',
  }) {
    final v = value.trim();
    final empty = v.isEmpty;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 5 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              // 라벨 2줄 방지 — ①범인가 카드(_plainRow)와 동일 규칙.
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              empty ? placeholder : v,
              style: TextStyle(
                color: empty ? AppColors.textGray : AppColors.textDark,
                fontSize: 13.5,
                fontWeight: empty ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// **행사 추가입력사항 카드** — 참가신청서에서 받은 상세 정보를 항목별로.
  ///
  /// ## [요구 2026-10-30]
  ///  > "추가입력사항도 매우 중요한 정보야 / 이 내용도 자세히 보여주고
  ///  >  정리되고 출력시 구분해서 보여져야 해, 그리고 항목별로 취합도 가능해야 해"
  ///
  /// ## 종전 문제
  ///  추가입력 항목(이동·숙박·도착·출발지·소요시간·동행자·전달사항)은
  ///  **행사 상세의 참석자 카드에서 9.5pt 마퀴 한 줄**(`⏰ … · 🛏 … · 🚗 …`)로만
  ///  보였다. 흐르는 글자라 읽기도 어렵고, **개인 상세화면에는 아예 없었다.**
  ///  → 회원 한 사람의 참가 상세를 볼 방법이 없었다.
  ///
  /// ## 지금
  ///  · 이 회원이 참가한 **모든 행사**를 훑어 추가입력 값을 모아 항목별로 보여준다.
  ///  · 항목 정의는 `ExtraFields`(단일 출처)를 그대로 쓴다 — 입력·출력·취합과
  ///    라벨이 어긋날 수 없다.
  ///  · 그룹(이동/숙박/도착/경로/동행/요청)별로 묶고, 그룹 색을 쓴다.
  ///  · **요청(전달사항)은 맨 앞에 강조**해 놓치지 않게 한다.
  Widget _eventExtraCard(Member m) {
    final hit = _extraRowsFor(m);
    if (hit.isEmpty) {
      // 아직 캐시가 비었으면 한 번 받아온다(중복 호출은 내부에서 막는다).
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadEventExtras(m));
      return const SizedBox.shrink();
    }
    // 요청사항을 먼저, 그 다음 정의 순서.
    final grouped = <ExtraGroup, List<MapEntry<ExtraField, String>>>{};
    for (final e in hit) {
      for (final f in ExtraFields.filled(e.rows)) {
        grouped.putIfAbsent(f.group, () => []).add(MapEntry(f, f.valueOf(e.rows)));
      }
    }
    final order = <ExtraGroup>[
      ExtraGroup.request,
      ExtraGroup.transport,
      ExtraGroup.lodging,
      ExtraGroup.arrival,
      ExtraGroup.route,
      ExtraGroup.companion,
    ];
    return _section(
      title: '행사 추가입력사항',
      icon: Icons.assignment_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${hit.length}개 행사에서 받은 상세 정보입니다. '
            '항목별로 취합·출력에서도 그대로 구분됩니다.',
            style: const TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
          const SizedBox(height: 6),
          for (final g in order)
            if (grouped[g] != null) ...[
              _extraGroupHeader(g),
              for (final entry in grouped[g]!)
                _extraLine(entry.key, entry.value, g),
              const SizedBox(height: 4),
            ],
        ],
      ),
    );
  }

  /// 이 회원이 참가한 행사들의 추가입력 행을 모은다.
  ///
  /// 매칭 규칙: 행사 참석자 행의 `number`(인가번호) 또는 `phone`(숫자만)이
  /// 이 회원과 일치. 은하는 `G` 접두어를 무시하고 숫자로 비교한다.
  List<({String year, String title, Map<String, dynamic> rows})> _extraRowsFor(
    Member m,
  ) {
    final out = <({String year, String title, Map<String, dynamic> rows})>[];
    final myNo = m.number.replaceAll(RegExp(r'[^0-9]'), '');
    final myPh = m.phoneDigits;
    if (myNo.isEmpty && myPh.isEmpty) return out;
    final names = m.eventAttend.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toList();
    // 개인 프로필의 참가행사명에서 **연도**를 뽑아 (연도, 행사명)으로 조회한다.
    for (final full in names) {
      final ym = RegExp(r'(\d{4})').firstMatch(full);
      final year = ym?.group(1) ?? '';
      // 저장된 행사명에 연도 접두어가 붙어 있을 수 있으므로 후보를 모두 시도.
      final cands = <String>{full};
      if (full.contains('_')) cands.add(full.split('_').first);
      for (final t in cands.toList()) {
        final hit = _extraCache['$year::$t'] ?? _extraCache['::$t'];
        if (hit == null) continue;
        // 그 안에서 이 회원 행을 찾는다.
        for (final a in hit) {
          final ano = '${a['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
          final aph = '${a['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
          final match = (myNo.isNotEmpty && ano == myNo) ||
              (myPh.length >= 7 && aph == myPh);
          if (!match) continue;
          if (ExtraFields.filledCount(a) == 0) continue;
          out.add((year: year, title: t, rows: a));
          break;
        }
      }
    }
    return out;
  }

  static Widget _extraGroupHeader(ExtraGroup g) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 2),
    child: Row(
      children: [
        Icon(g.icon, size: 13, color: ExtraFields.colorOf(g)),
        const SizedBox(width: 4),
        Text(
          g.label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: ExtraFields.colorOf(g),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Divider(
            height: 1,
            color: ExtraFields.colorOf(g).withValues(alpha: 0.25),
          ),
        ),
      ],
    ),
  );

  Widget _extraLine(ExtraField f, String value, ExtraGroup g) {
    final accent = ExtraFields.colorOf(g);
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              f.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textGray,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: f.group == ExtraGroup.request
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: f.group == ExtraGroup.request ? accent : AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }


  ///
  /// (요구: "범스카우트인가정보페이지와 아타스인가정보를 분리할 것"
  ///        + "아타스 인가정보: 인가번호 / 소속연맹·단위대 / 인가일")
  /// (요구: "인가번호만 있다면 나머지는 추후 입력할 수 있도록 항목만 만들고 비워 놔")
  /// (요구: "모든 회원 카드에 있던 atas 인가정보가 사라짐, 다시 노출해줘")
  /// (요구: **"atas인가 정보는 범인가정보와 달라 / atas 인가 정보가 입력되지
  ///          않은 경우 공란으로 둬"**)
  ///
  /// ## 표시 원칙 (2026-10-26 확정)
  ///  · **항목은 항상 전부 노출**한다 — ATAS 인가번호 · 소속 연맹 · 등록 단위대 ·
  ///    인가일 · 영문 이름. 값이 없으면 `공란(—)`.
  ///  · ⚠️ **범인가 값을 절대 상속하지 않는다.** ATAS 인가는 범인가와 별개의
  ///    인가이므로(사용자 지침), 범인가의 연맹·단위대·인가일을 끌어오면
  ///    "ATAS 로 제405단 샘물지역대에서 1997-02-19 인가"라는 **거짓 정보**가
  ///    된다. 값이 없으면 비워 두는 것이 정확하다.
  ///  · 카드는 인가자에게 **항상 노출**한다 — 빈 카드가 곧 "등록 필요" 안내다.
  ///    비인가회원(일반)은 ATAS 대상이 아니므로 값이 있을 때만 노출한다.
  Widget _atasCard(Member m) {
    final hasAtas = m.atasNo.trim().isNotEmpty;
    final hasEn = m.nameEn.trim().isNotEmpty;
    // 비인가회원(일반)은 ATAS 대상이 아니다 — 값이 없으면 카드를 만들지 않는다.
    if (m.isRegular && !hasAtas && !hasEn) return const SizedBox.shrink();

    // 편집 권한 — 본인 / 관리자 / 마스터만 ATAS 값을 직접 입력할 수 있다.
    final state = context.watch<AppState>();
    final canEdit =
        state.isApp || state.isMaster || state.isSelfNumber(m.number);

    return _section(
      title: 'ATAS 인가 정보 (인가 당시 정보)',
      icon: Icons.military_tech,
      // [요구] "ATAS인가정보는 비워두고 **직접 입력할 수 있도록** 할것"
      //  · 카드 제목 오른쪽에 '직접 입력' 버튼을 두어, 값이 비어 있는 상태에서도
      //    어디를 눌러 채우는지 즉시 알 수 있게 한다(빈 카드에 갇히지 않게).
      //  · 권한이 없으면 버튼을 만들지 않는다(눌러도 안 되는 버튼은 혼란만 준다).
      action: canEdit
          ? TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: AppColors.purple,
              ),
              onPressed: () => _edit(m, focusAtas: true),
              icon: const Icon(Icons.edit, size: 15),
              label: const Text(
                '직접 입력',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _blankRow('ATAS 인가번호', m.atasNo),
          // ATAS 전용 필드 — **범인가 값을 상속하지 않는다**(요구).
          //  값이 없으면 공란. ATAS 인가를 따로 받은 경우에만 채워진다.
          //  dense: 값이 '—' 인 행이 이어져도 ①범인가 카드와 행 높이가 같아지게.
          _blankRow('소속 연맹', m.atasLeague, dense: true),
          _blankRow('등록 단위대', m.atasUnit, dense: true),
          _blankRow('인가일', m.atasDate, dense: true),
          _blankRow('영문 이름', m.nameEn, dense: true),
          const SizedBox(height: 2),
          Text(
            hasAtas || hasEn
                ? 'ATAS(국제 범스카우트 인가) 기록입니다. 비어 있는 항목(—)은 추후 입력할 수 있습니다. '
                      'ATAS 인가는 범인가와 별개이므로 범인가 정보를 가져오지 않습니다.'
                : 'ATAS 인가 정보가 아직 등록되지 않았습니다. ATAS 인가를 받은 경우에만 입력합니다.',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
          ),
          // 값이 하나도 없고 편집 권한이 있으면, 큰 입력 유도 버튼을 하나 더 둔다.
          if (!hasAtas && !hasEn && canEdit) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.purple,
                  side: BorderSide(
                    color: AppColors.purple.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () => _edit(m, focusAtas: true),
                icon: const Icon(Icons.add, size: 17),
                label: const Text(
                  'ATAS 인가 정보 입력',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// [요구] 비인가회원 **정보 수정요청 메모**.
  ///   · 본인(비인가 포함) : 관리자·마스터에게 수정요청 메모를 보낼 수 있다.
  ///     (본인+관리자+마스터 외에는 정보 수정 불가 → 메모로 요청)
  ///   · 관리자·마스터     : 도착한 메모를 확인하고 직접 수정할 수 있다.
  ///   · 메모가 있으면 통합승인 '정보 수정요청' 큐에도 노출된다.
  Widget _linkFixRequestSection(Member m) {
    final state = context.watch<AppState>();
    final isAdmin = state.isApp || state.isMaster;
    final isSelf = state.isSelfNumber(m.number);
    final hasNote = m.hasLinkFixNote;
    // 관련자(본인·관리자·마스터)가 아니고 메모도 없으면 노출하지 않는다.
    if (!isAdmin && !isSelf && !hasNote) return const SizedBox.shrink();
    const color = AppColors.tigerGold;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                hasNote ? '정보 수정요청 도착' : '정보 수정요청 (메모 보내기)',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              const Spacer(),
              if (isAdmin && hasNote)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    foregroundColor: AppColors.purple,
                  ),
                  onPressed: () => _edit(m),
                  icon: const Icon(Icons.edit, size: 15),
                  label: const Text('직접 수정', style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
          if (hasNote) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.linkFixNote,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '요청: ${m.linkFixRequestedBy.isEmpty ? '본인' : m.linkFixRequestedBy}'
                    '${m.linkFixRequestedAt.trim().isEmpty ? '' : ' · ${m.linkFixRequestedAt}'}'
                    '${m.linkFixScope.trim().isEmpty ? '' : ' · ${m.linkFixScope}'}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            const Text(
              '멘토·페런츠·멘티 정보는 본인·관리자·마스터만 수정할 수 있습니다. '
              '수정이 필요하면 아래에 요청 내용을 남겨주세요. 관리자·마스터가 '
              '통합승인에서 확인하고 직접 수정합니다.',
              style: TextStyle(fontSize: 11, height: 1.4),
            ),
          ],
          if (isSelf || isAdmin) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.6)),
                ),
                onPressed: () => _sendFixNote(m),
                icon: const Icon(Icons.send, size: 16),
                label: Text(hasNote ? '수정요청 메모 수정·재전송' : '정보 수정요청 메모 보내기'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 정보 수정요청 메모 작성·전송.
  Future<void> _sendFixNote(Member m) async {
    final ctrl = TextEditingController(text: m.linkFixNote);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('정보 수정요청 메모'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '수정이 필요한 내용을 구체적으로 적어주세요. '
                '(예: 멘토 이름 변경, 페런츠 전화번호 오류 등)',
                style: TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: '수정 요청 내용을 입력하세요',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('보내기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final note = ctrl.text.trim();
    if (note.isEmpty) {
      _snack('요청 내용을 입력하세요');
      return;
    }
    final state = context.read<AppState>();
    final sent = await state.sendLinkFixNote(
      ident: m.number.isNotEmpty ? m.number : m.phone,
      note: note,
      scope: '인가정보 수정',
    );
    if (!mounted) return;
    if (sent) {
      _snack('정보 수정요청을 보냈습니다 (관리자·마스터 확인 대기)');
      state.refresh();
      await _loadLinkProfiles();
      if (mounted) setState(() {});
    } else {
      _snack('요청 전송에 실패했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  /// 멘토·페런츠 연결 '승인대기중' 안내 — 관리자·마스터 승인 전 상태 설명(요구).
  Widget _linkPendingNotice(Member m) {
    const color = AppColors.tigerGold;
    final src = m.linkRequestSource == 'merch' ? '수품신청시' : '직접입력';
    final at = m.linkRequestedAt;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_top, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                '승인대기중',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '멘토·페런츠 연결은 관리자·마스터의 승인이 필요합니다. '
            '승인되기 전까지는 \'승인대기중\'으로 표시되며, 승인 후 정식 등록됩니다.',
            style: TextStyle(fontSize: 11.5, height: 1.45),
          ),
          const SizedBox(height: 4),
          Text(
            '승인요청방법: $src'
            '${at.trim().isEmpty ? '' : ' · 승인요청 $at'}',
            style: const TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  /// 멘토·페런츠 **입력창 복원** — 개인정보(상세)창에서 직접 등록/수정.
  ///   · 편집 화면(member_edit_screen)과 완전히 동일한 위젯/기준을 사용한다.
  ///   · 변경 즉시 회원 데이터에 반영하고 저장(연결 승인 상태는 pending 으로 전환).
  /// 멘토·페런츠 연결 저장 — 회원 데이터 반영 + 서버 저장.
  ///   · 대상이 바뀌면 연결 승인 상태를 'pending'(미승인)으로 전환한다
  ///     (편집 화면과 동일 정책).
  Future<void> _saveLinks(
    Member m, {
    List<String>? mentors,
    List<String>? parents,
    List<String>? mentees,
    List<String>? children,
  }) async {
    final state = context.read<AppState>();
    final nextMentors = mentors ?? List<String>.from(m.mentors);
    final nextParents = parents ?? List<String>.from(m.parents);
    final nextMentees = mentees ?? List<String>.from(m.mentees);
    final nextChildren = children ?? List<String>.from(m.children);
    final hasLinks =
        nextMentors.isNotEmpty ||
        nextParents.isNotEmpty ||
        nextMentees.isNotEmpty ||
        nextChildren.isNotEmpty;
    final updated = m.copyWith(
      mentors: nextMentors,
      parents: nextParents,
      mentees: nextMentees,
      children: nextChildren,
      linkApprovalStatus: hasLinks ? 'pending' : '',
      linkApprovalNote: hasLinks ? m.linkApprovalNote : '',
    );
    try {
      await state.save(updated, linkRequestSource: 'direct');
      if (!mounted) return;
      await _loadLinkProfiles();
      _snack('등록을 저장했습니다 (관리자 승인 대기)');
    } catch (_) {
      if (!mounted) return;
      _snack('저장에 실패했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  /// 각인 메달(멘토·페런츠) 수상/수여 기록 — 개인프로필 연동.

  Widget _infoCard(Member m) {
    final state = context.watch<AppState>();
    final admin = state.isApp || state.isMaster; // 관리자·마스터: 전체 열람
    final isMaster = state.isMaster; // 마스터: 노출관리(체크박스)·비노출 열람까지
    final isSelf = state.isSelfNumber(m.number); // 본인: 노출 항목 전체 열람

    // 표시할 값 계산 — 회원별 노출권한 반영.
    //  · '비노출(hidden)' : **마스터에게만** 값 표시. 나머지(관리자·본인·타인)는 완전 숨김.
    //  · '관리자 노출(admin)': 관리자·마스터에게 표시. 본인·타인은 숨김.
    //  · '노출(public)'   : 모두 표시.
    String disp(String key, String value) {
      if (value.trim().isEmpty) return '';
      final p = state.permFor(m, key);
      if (p == AppState.permHidden) {
        // 비노출: 마스터만 값을 본다. 관리자·본인·타인에게는 어떤 형태로도 노출 금지.
        return isMaster ? '$value   (비노출)' : '';
      }
      if (p == AppState.permAdmin) {
        // 관리자 노출: 관리자·마스터만 본다.
        if (admin) return '$value   (관리자 노출)';
        return '';
      }
      return value; // public — 모두 표시
    }

    // (라벨, 키, 값) — 항목별 노출관리 대상.
    //  ※ 소속연맹/단위대/인가일은 위의 [현재활동]/[범인가 정보] 카드에서 다룬다.
    //
    //  ## 주민등록번호 — 뒷자리 마킹 (2026-11-02, build #574)
    //  요구: "주민등록정보는 뒷번호가 입력시 마킹처리가 안되고 있음
    //        (예시: 990328-1******) / 노출되는(개인카드에도) 정보에는 뒷번호를
    //        마킹처리하고 오로지 마스터만 뒷번호를 확인할 수 있도록 함"
    //
    //  종전에는 `m.residentNo` 를 그대로 그려서, 노출 권한이 있는 사람에게는
    //  뒷자리까지 전부 보였다(예: 990328-1234567).
    //  → **마스터만 원본**, 나머지(관리자·본인·타인)는 `residentNoMasked`
    //    (`990328-1******`) 를 본다.
    //    ※ 본인도 마킹본을 본다. 이 화면은 남에게 보여줄 수 있는 카드이고,
    //      본인 확인이 필요하면 마스터가 원본을 확인한다는 요구를 그대로 따른다.
    final isMasterForRn = isMaster;
    final fields = <List<String>>[
      // ## [요구 2026-11-03] 회원번호(스카우트회원번호) 노출 규칙
      //  "관리자 및 마스터는 모든 번호를 확인할 수 있도록 하고,
      //   회원에게는 뒷번호 2자리에 * 표 처리해서 노출해줘"
      //  · 관리자·마스터(admin == true) → 원본 전체
      //  · 본인·일반회원            → 뒷 2자리 `**` (예: 123456 → 1234**)
      //  값이 비면 권한 규칙(disp)에 맡겨 행 자체가 사라진다.
      [
        '스카우트회원번호',
        'scoutNo',
        m.scoutNoDisplay(canSeeAll: admin),
      ],
      [
        '주민등록번호',
        'residentNo',
        isMasterForRn ? m.residentNo : m.residentNoMasked,
      ],
      ['생일', 'birthday', m.birthday],
      ['성별', 'gender', m.gender],
      ['기념일', 'anniversary', m.anniversary],
      ['훈련현황', 'trainingStatus', m.trainingStatus],
      ['포상', 'awards', m.awards],
      ['전문과정 이수', 'specialtyCourses', m.specialtyCourses],
      ['ATAS 인가번호', 'atasNo', m.atasNo],
      ['영문 이름', 'nameEn', m.nameEn],
      ['핸드폰', 'phone', m.phone],
      ['연락처', 'tel', m.tel],
      ['이메일', 'email', m.email],
      ['우편번호', 'zipCode', m.zipCode],
      ['주소', 'address', m.address],
      ['한줄소개', 'bio', m.bio],
      ['활동', 'activity', m.activity],
      ['메모', 'memo', m.memo],
    ];

    final children = <Widget>[];
    for (final f in fields) {
      final label = f[0], key = f[1], raw = f[2];
      // 성별: 공개설정(genderVisible)도 함께 존중(관리자·본인 제외).
      if (key == 'gender' && !(admin || isSelf) && !m.genderVisible) continue;
      final hasPerm = m.fieldPerms.containsKey(key);
      if (raw.trim().isEmpty && !hasPerm) continue; // 값·설정 모두 없으면 숨김
      final shown = disp(key, raw);
      // 값이 비면(비노출을 볼 권한 없음 포함) 마스터가 아닌 한 행 자체를 만들지 않는다.
      if (shown.isEmpty && !isMaster) continue;
      children.add(_infoFieldRow(state, m, label, key, shown, isMaster));
      // 주민번호 행 바로 아래 — 마스터에게만 검증된 값/원본 여부를 알려준다.
      if (key == 'residentNo' && isMaster && m.hasResidentBack) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 96, bottom: 4),
            child: Text(
              '뒷자리는 마스터만 볼 수 있습니다 (마킹 표기: ${m.residentNoMasked})',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textGray,
                height: 1.3,
              ),
            ),
          ),
        );
      }
    }
    // 멘토·페런츠 등록현황은 '범인가 정보' 카드에서 표시한다(여기서는 제외).
    children.add(
      _plainRow(
        '개인정보 동의',
        m.privacyAgreed
            ? '동의함${m.privacyAgreedAt.isNotEmpty ? ' (${m.privacyAgreedAt})' : ''}'
            : '미동의',
      ),
    );
    children.removeWhere((w) => w is SizedBox);

    return _section(
      title: '상세 정보',
      icon: Icons.badge,
      // [요구 2026-11-02] "개인정보 활용 편집: 입수한 정보에 대한 추가내용을
      //  넣어줘. 비밀번호, 사진, 인가정보 등등"
      //  → 이 카드에서 그대로 [개인정보 활용 편집] 화면으로 들어갈 수 있게 한다.
      //    (마스터 전용 — 다른 권한에는 버튼을 만들지 않는다.)
      action: isMaster
          ? TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: AppColors.purple,
              ),
              onPressed: () => showPrivacyUsageEdit(context, m),
              icon: const Icon(Icons.privacy_tip_outlined, size: 15),
              label: const Text(
                '개인정보 활용',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            )
          : null,
      child: children.isEmpty
          ? Text(
              '등록된 상세 정보가 없습니다. 편집 버튼을 눌러 입력하세요.',
              style: TextStyle(color: AppColors.textGray, fontSize: 13),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
    );
  }

  /// 값 없는 일반 행(구조 항목용).
  /// 항목 1줄 — 라벨 / 값.
  ///
  /// ## 라벨 2줄 문제 (요구)
  ///  "범스카우트인가정보 라고 길게 쓰니까 글자가 2줄 생김 / 범인가정보 로 줄여줘"
  ///  라벨 폭 96px 에 '범스카우트 인가번호'(9자)를 넣으면 두 줄로 넘쳤다.
  ///  → 호출부에서 라벨 자체를 줄이고(범인가번호), 여기서는 폭을 104px 로
  ///    조금 넓히고 `maxLines: 1` + `softWrap: false` 로 **두 줄을 원천 차단**한다.
  ///    (폭만 늘리면 더 긴 라벨에서 또 넘친다 — 줄바꿈 금지가 확실한 방어다.)
  ///  · [dense] : ATAS 카드처럼 값이 '—' 인 행이 이어질 때 세로 여백을 줄인다.
  ///    두 카드의 행 높이를 같게 맞춰 좌우 균형을 잡기 위한 것이다.
  Widget _plainRow(String label, String value, {bool dense = false}) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 5 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textDark, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 항목 1줄 + (마스터면) 노출관리 체크박스.
  Widget _infoFieldRow(
    AppState state,
    Member m,
    String label,
    String key,
    String shown,
    bool isMaster,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  shown.isEmpty ? '(값 없음)' : shown,
                  style: TextStyle(
                    color: shown.isEmpty
                        ? AppColors.textGray
                        : AppColors.textDark,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          if (isMaster) _permRow(state, m, key),
        ],
      ),
    );
  }

  /// 마스터 전용 항목 노출관리 — 노출 / 관리자노출 / 비노출 / 삭제.
  Widget _permRow(AppState state, Member m, String key) {
    final cur = state.permFor(m, key); // 적용 중인 유효 권한
    final explicit = m.fieldPerms[key]; // 개별 지정값(없으면 전역 기본)
    const tips = {
      'public': '모든 회원에게 노출',
      'admin': '관리자·본인만 노출',
      'hidden': '아무에게도 비노출',
      'delete': '개별 설정 삭제(전역 기본값 적용)',
    };
    Widget chip(String val, String label, IconData icon, Color color) {
      final sel = (val == 'delete') ? explicit == null : cur == val;
      return Tooltip(
        message: tips[val] ?? '',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _setPerm(state, m, key, val == 'delete' ? null : val),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sel ? color.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? color : AppColors.textGray.withValues(alpha: 0.35),
                width: sel ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: sel ? color : AppColors.textGray),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                    color: sel ? color : AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 96, top: 4, bottom: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          chip('public', '노출', Icons.visibility, AppColors.scoutGreen),
          chip(
            'admin',
            '관리자',
            Icons.admin_panel_settings,
            AppColors.taegeukBlue,
          ),
          chip('hidden', '비노출', Icons.visibility_off, AppColors.textGray),
          chip('delete', '삭제', Icons.delete_outline, AppColors.taegeukRed),
        ],
      ),
    );
  }

  Future<void> _setPerm(
    AppState state,
    Member m,
    String key,
    String? value,
  ) async {
    try {
      await state.setMemberFieldPerm(m, key, value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }

  /// 회원 구분 관리 — 일반회원(비인가자) → 인가자 승격 / 강등 (관리자·마스터)
  Widget _membershipSection(Member m) {
    final state = context.watch<AppState>();
    if (!(state.isApp || state.isMaster)) return const SizedBox.shrink();
    return _section(
      title: '회원 구분 관리 (관리자)',
      icon: Icons.swap_horiz,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                m.isRegular ? Icons.person_outline : Icons.verified_user,
                size: 16,
                color: m.isRegular ? AppColors.textGray : AppColors.taegeukBlue,
              ),
              const SizedBox(width: 6),
              Text(
                m.isRegular
                    ? '현재: 일반회원 (비인가자)'
                    : '현재: 인가자 (${m.cardNumberLabel})',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (m.isRegular)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.taegeukBlue,
              ),
              onPressed: () => _promote(m),
              icon: const Icon(Icons.arrow_upward, size: 18),
              label: const Text('인가자로 승격'),
            )
          else
            const Text(
              '인가자로 등록되어 있습니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
        ],
      ),
    );
  }

  Future<void> _promote(Member m) async {
    final noCtrl = TextEditingController();
    final leagueCtrl = TextEditingController(text: m.league);
    final unitCtrl = TextEditingController(text: m.unit);
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('인가자 승격 — ${m.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '일반회원을 정식 인가자로 승격합니다. 부여할 인가번호를 입력하세요.',
                style: TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '인가번호',
                  helperText: '기존 번호와 중복되지 않아야 합니다',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: leagueCtrl,
                decoration: const InputDecoration(labelText: '소속 연맹'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: unitCtrl,
                decoration: const InputDecoration(labelText: '소속 단위대'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukBlue,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('승격'),
          ),
        ],
      ),
    );
    if (res != true || !mounted) return;
    final updated = await context.read<AppState>().promoteToCredential(
      m,
      number: noCtrl.text.trim(),
      league: leagueCtrl.text.trim(),
      unit: unitCtrl.text.trim(),
    );
    if (!mounted) return;
    if (updated == null) {
      _snack('승격 실패: 인가번호가 비었거나 중복됩니다');
    } else {
      _snack('인가자로 승격했습니다 (${updated.cardNumberLabel})');
      setState(() {});
    }
  }

  /// 비밀번호 관리 — 권한이 있는 사람에게만 노출 (요구).
  ///  · 관리자·마스터 : 관리(초기화 / 마스터는 변경까지)
  ///  · 본인           : 비밀번호 변경 + 분실 시 초기화 요청
  ///  · 그 외          : 미노출
  ///  · 현재 비밀번호 "실제값" 노출은 마스터만 가능
  Widget _passwordSection(Member m) {
    final state = context.watch<AppState>();
    final isAdmin = state.isApp || state.isMaster;
    final isMaster = state.isMaster;
    final isSelf = state.isSelfAccess && state.isSelfNumber(m.number);
    if (!isAdmin && !isSelf) return const SizedBox.shrink();
    final isRegular = m.isRegular;
    return _section(
      title: '접속 비밀번호 관리',
      icon: Icons.password,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRegular ? Icons.person_outline : Icons.badge_outlined,
                size: 16,
                color: AppColors.textGray,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isRegular
                      ? '일반회원 · ID ${m.loginId}'
                      : '인가자 · ID ${m.numPrefix(prefixHash: false)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
              ),
            ],
          ),
          // ---- 마스터 전용: 현재 접속 비밀번호 실제값 노출 ----
          if (isAdmin && isMaster) ...[
            const SizedBox(height: 10),
            _currentPasswordReveal(m),
          ],
          // ---- 관리자·마스터: 초기화 / (마스터) 강제 변경 ----
          if (isAdmin) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _forceReset(m),
                  icon: const Icon(Icons.lock_reset, size: 17),
                  label: const Text('비번 초기화'),
                ),
                if (isMaster)
                  OutlinedButton.icon(
                    onPressed: () => _forceChange(m),
                    icon: const Icon(Icons.lock_open, size: 17),
                    label: const Text('비번 강제 변경'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isMaster
                  ? '마스터는 모든 회원의 비밀번호를 열람·변경·초기화할 수 있습니다.'
                  : '관리자는 비밀번호 초기화만 할 수 있습니다. 변경은 마스터만 가능합니다.',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textGray,
                height: 1.35,
              ),
            ),
          ],
          // ---- 본인(비관리자): 비밀번호 변경 + 분실 시 초기화 요청 ----
          if (isSelf && !isAdmin) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                ),
                onPressed: () => _selfChangePassword(m),
                icon: const Icon(Icons.password, size: 18),
                label: const Text('비밀번호 변경'),
              ),
            ),
            const SizedBox(height: 8),
            _selfResetRequestBar(m),
          ],
        ],
      ),
    );
  }

  /// 본인 — 분실 시 관리자·마스터에게 초기화 요청 (요구).
  Widget _selfResetRequestBar(Member m) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.tigerGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.tigerGold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline, size: 15, color: AppColors.lifetimeGold),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  '비밀번호를 분실한 경우 관리자·마스터에게 초기화를 요청하세요.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.lifetimeGold,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.tigerGold,
              ),
              onPressed: () => _requestReset(m),
              icon: const Icon(Icons.send, size: 16),
              label: const Text('비밀번호 초기화 요청'),
            ),
          ),
        ],
      ),
    );
  }

  /// 본인 비밀번호 변경 다이얼로그.
  void _selfChangePassword(Member m) {
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final newCtrl2 = TextEditingController();
    bool busy = false;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('비밀번호 변경'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${m.name} (${m.loginId})',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: curCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '현재 비밀번호'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '새 비밀번호 (4자 이상)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newCtrl2,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '새 비밀번호 확인'),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '※ 비밀번호를 분실한 경우 관리자·마스터에게 초기화를 요청하세요.',
                    style: TextStyle(fontSize: 11, color: AppColors.textGray),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final cur = curCtrl.text.trim();
                      final nw = newCtrl.text.trim();
                      final nw2 = newCtrl2.text.trim();
                      if (cur.isEmpty || nw.isEmpty) {
                        _snack('모든 항목을 입력하세요');
                        return;
                      }
                      if (nw.length < 4) {
                        _snack('새 비밀번호는 4자 이상이어야 합니다');
                        return;
                      }
                      if (nw != nw2) {
                        _snack('새 비밀번호가 서로 다릅니다');
                        return;
                      }
                      setLocal(() => busy = true);
                      final err = await context
                          .read<AppState>()
                          .changePersonalPassword(cur, nw);
                      if (!ctx.mounted) return;
                      setLocal(() => busy = false);
                      if (err == null) {
                        Navigator.pop(ctx);
                        _snack('비밀번호가 변경되었습니다');
                      } else {
                        _snack('변경 실패: $err');
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('변경'),
            ),
          ],
        ),
      ),
    );
  }

  /// 본인 — 비밀번호 초기화 요청 접수(관리자·마스터 승인 대기).
  Future<void> _requestReset(Member m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.lock_reset,
          color: AppColors.tigerGold,
          size: 32,
        ),
        title: const Text('비밀번호 초기화 요청'),
        content: const Text(
          '관리자·마스터에게 비밀번호 초기화를 요청하시겠습니까?\n\n'
          '· 요청은 통합승인관리에 접수되어 승인 후 초기화됩니다.\n'
          '· 초기화되면 기본 비밀번호로 다시 로그인할 수 있습니다.',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('요청'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<AppState>().requestPasswordReset();
    if (!mounted) return;
    _snack(
      err == null ? '초기화 요청을 접수했습니다. 관리자·마스터 승인 후 초기화됩니다.' : '요청 실패: $err',
    );
  }

  /// 마스터 전용 — 현재 접속 비밀번호 실제값 표시(가림/보기 토글 + 복사)
  Widget _currentPasswordReveal(Member m) {
    final state = context.read<AppState>();
    final key = m.loginId;
    if (_pwFutureKey != key) {
      _pwFutureKey = key;
      _pwFuture = state.fetchMemberPassword(key);
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future: _pwFuture,
      builder: (ctx, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final d = snap.data;
        final pw = d == null ? null : '${d['password'] ?? ''}';
        final isDefault = d?['isDefault'] == true;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.purple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.key, size: 17, color: AppColors.purple),
              const SizedBox(width: 8),
              const Text(
                '현재 비밀번호',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loading
                      ? '조회 중…'
                      : (pw == null || pw.isEmpty
                            ? '조회 실패'
                            : '$pw${isDefault ? '  (기본값)' : ''}'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: pw == null ? 0 : 1.0,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (pw != null && pw.isNotEmpty) ...[
                IconButton(
                  tooltip: '복사',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 17),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pw));
                    _snack('비밀번호를 복사했습니다');
                  },
                ),
                IconButton(
                  tooltip: '다시 조회',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () {
                    setState(() {
                      _pwFuture = state.fetchMemberPassword(key);
                    });
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _forceReset(Member m) async {
    final target = m.isRegular ? m.phoneLast4 : '${m.number}!@@';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비밀번호 초기화'),
        content: Text(
          '${m.name}(${m.loginId}) 님의 비밀번호를 기본값으로 초기화할까요?\n\n'
          '초기화 값: $target',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<AppState>().setMemberPassword(
      m,
      reset: true,
    );
    if (!mounted) return;
    _snack(err == null ? '비밀번호를 초기화했습니다 ($target)' : '실패: $err');
  }

  Future<void> _forceChange(Member m) async {
    final ctrl = TextEditingController();
    final nw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
        scrollable: true,
        title: Text('비밀번호 강제 변경 — ${m.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '새 비밀번호',
            helperText: '4자 이상 입력하세요',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    if (nw == null || nw.length < 4 || !mounted) {
      if (nw != null && mounted) _snack('4자 이상 입력하세요');
      return;
    }
    final err = await context.read<AppState>().setMemberPassword(m, value: nw);
    if (!mounted) return;
    _snack(err == null ? '비밀번호를 변경했습니다' : '실패: $err');
  }

  // ================= 후원금 · 후원물품 이력 =================
  //  요구: "후원금/후원물품 이력 추가(수동입력) → 관리자·마스터 인증요청버튼 →
  //  통합승인관리에 승인항목 표시 및 승인 / 이력 하단에 합계 표시."
  //   · 승인된 이력만 목록에 나타나고, 수동입력은 승인요청 큐로 접수된다.
  /// 후원금 · 후원물품 이력 — **행사 후원(찬조)까지 한 곳에** 모아 보여준다.
  ///
  /// ## 왜 두 곳을 합쳤나 (요구)
  ///  "이전에 요청한 내용인데, 후원금, 물품 등의 이력을 가져와야해"
  ///  "2026 atas mou 행사에 후원한 이승준, 이항복 회원 카드에 후원내역 추가해줘
  ///   (연동필수)"
  ///
  ///  문제는 **데이터가 두 곳에 따로** 있었다는 점이다.
  ///   ① `member.donations`  — 개인카드에서 직접 입력한 후원(승인 후 반영)
  ///   ② `finance.json`      — 행사에서 등록한 후원금/후원물품/찬조
  ///                            (`source="event"` 로 기록됨)
  ///  이 카드는 ① 만 읽고 있었다. 그래서 행사에서 후원을 등록해도 개인카드의
  ///  '후원금·후원물품 이력' 은 **0건**으로 남았다(실측: 이승준·이항복이
  ///  2026 ATAS MOU 행사에 후원했는데 카드는 비어 있었다).
  ///
  ///  → 이제 **재무(finance) 기록을 1차 소스**로 삼고, ① 은 보조로 합친다.
  ///    행사 등록 시 `finance.json` 에 자동 기록되므로(연동), 앞으로 행사에서
  ///    후원을 넣으면 개인카드에 **자동으로** 나타난다.
  ///    직접 입력(①)은 승인 전에도 보여야 하므로 그대로 유지한다.
  Widget _donationSection(Member m) {
    final state = context.watch<AppState>();
    final fs = context.watch<FinanceService>();
    final canEdit = state.isApp || state.isMaster || state.isSelfAccess;

    // ── ① 재무 기록(행사 후원 포함) — 후원 성격만 ──
    //  참가비·연회비·수품구매는 '입금 내역' 카드에서 다루므로 여기서 뺀다.
    final fin = fs
        .depositsOf(m.number, corps: m.corps)
        .where((t) => _isDonationCategory(t.category))
        .toList();

    // ── ② 개인카드 직접 입력분 ──
    final items = m.donations;
    final manualDon = items.where((d) => '${d['kind']}' == 'donation').toList();
    final manualSup = items.where((d) => '${d['kind']}' == 'supply').toList();

    // 후원금 = 재무의 후원금/기타후원 + 직접입력 donation
    // 후원물품 = 재무의 물품후원/식사후원 + 직접입력 supply
    final donCount =
        fin.where((t) => !_isSupplyCategory(t.category)).length +
        manualDon.length;
    final supCount =
        fin.where((t) => _isSupplyCategory(t.category)).length +
        manualSup.length;

    // 합계 — 재무(금액) + 직접입력(금액)
    var donTotal = 0, supTotal = 0;
    for (final t in fin) {
      if (_isSupplyCategory(t.category)) {
        supTotal += t.amount;
      } else {
        donTotal += t.amount;
      }
    }
    donTotal += manualDon.fold<int>(
      0,
      (s, d) => s + ((d['amount'] as num?)?.toInt() ?? 0),
    );
    supTotal += manualSup.fold<int>(
      0,
      (s, d) => s + ((d['amount'] as num?)?.toInt() ?? 0),
    );

    final isEmpty = fin.isEmpty && manualDon.isEmpty && manualSup.isEmpty;

    return _section(
      title: '후원금 · 후원물품 이력',
      icon: Icons.volunteer_activism,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _donationChip('후원금', donCount, AppColors.taegeukRed),
              const SizedBox(width: 6),
              _donationChip('후원물품', supCount, AppColors.taegeukBlue),
            ],
          ),
          const SizedBox(height: 10),
          if (isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '등록된 후원 이력이 없습니다',
                style: TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
            )
          else ...[
            // 행사·재무 기록(연동) 먼저 — 최신순
            for (final t in fin) _finDonationRow(t),
            // 개인카드 직접 입력분
            for (final d in manualDon) _donationRow(d),
            for (final d in manualSup) _donationRow(d),
          ],
          // ── 합계 ──
          const Divider(height: 22),
          _donationTotalRow('후원금 합계', donTotal, AppColors.taegeukRed),
          const SizedBox(height: 4),
          _donationTotalRow('후원물품 합계', supTotal, AppColors.taegeukBlue),
          const SizedBox(height: 4),
          _donationTotalRow(
            '총 합계',
            donTotal + supTotal,
            AppColors.purple,
            strong: true,
          ),
          if (canEdit) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.purple,
                  side: const BorderSide(color: AppColors.purple),
                ),
                onPressed: () => _addDonationDialog(m),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('후원금·후원물품 입력 (인증요청)'),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '※ 입력하면 관리자·마스터의 통합승인관리에서 승인 후 이력에 반영됩니다. '
              '행사에서 등록한 후원은 자동으로 반영됩니다.',
              style: TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
          ],
        ],
      ),
    );
  }

  /// 후원 성격 분류 — 이 카드에 넣을 것인가.
  ///  · 후원금/후원물품/식사후원/기타(찬조)/찬조 = 후원
  ///  · 참가비/연회비/수품구매/행사비/운영비 = 후원 아님(입금내역 카드에서 처리)
  static bool _isDonationCategory(String cat) {
    final c = cat.replaceAll(' ', '');
    if (c.isEmpty) return false;
    const excluded = ['참가비', '연회비', '수품구매', '행사비', '운영비', '회비'];
    for (final e in excluded) {
      if (c.contains(e)) return false;
    }
    const included = ['후원', '찬조', '기부', '기타'];
    for (final e in included) {
      if (c.contains(e)) return true;
    }
    return false;
  }

  /// 물품 성격인가 — 후원물품/식사후원(현물 제공).
  static bool _isSupplyCategory(String cat) {
    final c = cat.replaceAll(' ', '');
    return c.contains('물품') || c.contains('식사') || c.contains('현물');
  }

  /// 재무(행사 연동) 후원 1건 표시.
  Widget _finDonationRow(FinanceTransaction t) {
    final isSup = _isSupplyCategory(t.category);
    final color = isSup ? AppColors.taegeukBlue : AppColors.taegeukRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_depositIcon(t.category), size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _depositLabel(t.category),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                    if (_isOtherDonation(t.category)) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.tigerGold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '기타후원',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.tigerGold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // 행사명 — 어느 행사 후원인지 명확히(연동 근거).
                if (t.event.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      t.event,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                        height: 1.3,
                      ),
                    ),
                  ),
                if (t.memo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      t.memo,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    t.date,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            t.amount > 0 ? '${_won(t.amount)}원' : '재능·물품',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _donationChip(String label, int n, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$label $n건',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _donationRow(Map<String, dynamic> d) {
    final isDon = '${d['kind']}' == 'donation';
    final color = isDon ? AppColors.taegeukRed : AppColors.taegeukBlue;
    final item = '${d['item'] ?? ''}'.trim();
    final amount = (d['amount'] as num?)?.toInt() ?? 0;
    final date = '${d['date'] ?? ''}'.trim();
    final note = '${d['note'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(
            isDon ? Icons.volunteer_activism : Icons.card_giftcard,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.isNotEmpty ? item : (isDon ? '후원금' : '후원물품'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (date.isNotEmpty || note.isNotEmpty)
                  Text(
                    [
                      if (date.isNotEmpty) date,
                      if (note.isNotEmpty) note,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            amount > 0 ? '${_won(amount)}원' : '-',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _donationTotalRow(
    String label,
    int value,
    Color color, {
    bool strong = false,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: strong ? 13.5 : 12.5,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            color: strong ? AppColors.textDark : AppColors.textGray,
          ),
        ),
        const Spacer(),
        Text(
          '${_won(value)}원',
          style: TextStyle(
            fontSize: strong ? 14 : 12.5,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 후원금·후원물품 수동 입력 → 관리자·마스터 인증요청.
  Future<void> _addDonationDialog(Member m) async {
    String kind = 'donation';
    final itemCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('후원금 · 후원물품 입력'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('후원금'),
                      selected: kind == 'donation',
                      onSelected: (_) => setS(() => kind = 'donation'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('후원물품'),
                      selected: kind == 'supply',
                      onSelected: (_) => setS(() => kind = 'supply'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: itemCtrl,
                  decoration: InputDecoration(
                    labelText: kind == 'donation' ? '후원 항목/내용' : '후원물품명',
                    hintText: kind == 'donation' ? '예: 정기후원' : '예: 스카우트 셔츠 10벌',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '금액 (원)',
                    hintText: '예: 100000',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(
                    labelText: '후원일',
                    hintText: '예: 2026-10-11',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '비고 (선택)',
                    hintText: '예: 입금자명, 영수증 번호 등',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('인증요청'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) {
      itemCtrl.dispose();
      amountCtrl.dispose();
      dateCtrl.dispose();
      noteCtrl.dispose();
      return;
    }
    final amount =
        int.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (itemCtrl.text.trim().isEmpty && amount <= 0) {
      _snack('항목 또는 금액을 입력하세요');
      itemCtrl.dispose();
      amountCtrl.dispose();
      dateCtrl.dispose();
      noteCtrl.dispose();
      return;
    }
    try {
      final r = await context.read<NasApi>().memberRequestSubmit(
        type: kind,
        ident: m.number.isNotEmpty ? m.number : m.accessPhone,
        item: itemCtrl.text.trim(),
        amount: amount,
        date: dateCtrl.text.trim(),
        note: noteCtrl.text.trim(),
      );
      if (r['ok'] == true) {
        _snack('후원 이력을 인증요청했습니다 (관리자·마스터 승인 대기)');
      } else {
        _snack('요청 실패: ${r['error'] ?? '알 수 없음'}');
      }
    } catch (e) {
      _snack('요청 오류: $e');
    }
    itemCtrl.dispose();
    amountCtrl.dispose();
    dateCtrl.dispose();
    noteCtrl.dispose();
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? action,
  }) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.purple, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                // 카드 제목 오른쪽 액션(직접 입력 등).
                if (action != null) action,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        _snack('앱을 열 수 없습니다: $url');
      }
    } catch (e) {
      if (mounted) _snack('실행 실패: $e');
    }
  }

  void _copy(Member m) {
    final text =
        '[${m.number}] ${m.name} | ${m.league} ${m.unit} | ${m.phone} | ${m.date}';
    Clipboard.setData(ClipboardData(text: text));
    _snack('복사되었습니다');
  }

  void _edit(Member m, {bool focusAtas = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberEditScreen(
          memberId: m.id,
          // [요구] ATAS 카드의 '직접 입력' → 편집화면의 ATAS 인가번호 칸으로
          //  바로 이동. 폼이 길어 그냥 열면 어디를 채울지 알 수 없다.
          focusAtas: focusAtas,
        ),
      ),
    );
    if (mounted) context.read<AppState>().refresh();
    _loadDraftCount();
  }

  /// 임시저장 목록 열기 — 선택한 초안을 편집 화면으로 복원한다(관리자·마스터).
  Future<void> _openDrafts() async {
    final res = await Navigator.push<MemberDraft>(
      context,
      MaterialPageRoute(builder: (_) => const MemberDraftsScreen()),
    );
    if (!mounted) return;
    await _loadDraftCount();
    if (res == null) return;
    if (res.isNew) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MemberEditScreen()),
      );
    } else if (res.memberId.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MemberEditScreen(memberId: res.memberId),
        ),
      );
    }
    if (mounted) context.read<AppState>().refresh();
  }

  /// (요구 복원) 홈 버튼 — 첫 화면(홈)까지 되돌아간다.
  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 개인정보 최종 출력 — 선택한 형식(PDF/JPG/엑셀/워드/PPT)으로 내보낸다.
  void _exportPersonal(Member m) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          members: [m],
          title: '개인정보 출력 — ${m.name} (${m.cardNumberLabel})',
        ),
      ),
    );
  }
}

class _QA {
  _QA(this.label, this.icon, this.color, this.onTap, this.enabled);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;
}
