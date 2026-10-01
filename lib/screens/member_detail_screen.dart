import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/finance_transaction.dart';
import '../models/member.dart';
import '../services/app_state.dart';
import '../services/finance_service.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/member_avatar.dart';
import '../widgets/member_access_log.dart';
import '../widgets/link_code_field.dart';
import '../widgets/member_registration_request_section.dart';
import '../widgets/merch_activity_section.dart';
import '../widgets/personal_survey_section.dart';
import '../widgets/photo_pip.dart';
import '../widgets/scroll_down_hint.dart';
import 'finance_transaction_edit_screen.dart';
import 'export_screen.dart';
import 'member_edit_screen.dart';
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

  Map<String, dynamic> _profileOf(String code) {
    final key = code.replaceAll(RegExp(r'[^0-9]'), '');
    return (_linkProfilesCache[key] as Map?)?.cast<String, dynamic>() ??
        (_linkProfilesCache[code] as Map?)?.cast<String, dynamic>() ??
        {};
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
    });
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
              expandedHeight: 176,
              pinned: true,
              backgroundColor: AppColors.purple,
              leading: const AppBackButton(label: '뒤로'),
              leadingWidth: 84,
              flexibleSpace: FlexibleSpaceBar(background: _header(m)),
              actions: [
                const AppHomeEmblem(size: 24),
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
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: '편집',
                  onPressed: () => _edit(m),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _quickActions(m),
                  _approvalBanner(m),
                  // (요구) 인가정보·활동정보 위치 변경 — 개인 상세페이지 **최상단** 배치.
                  //   ① 범스카우트 인가 정보(인가 당시 정보) ② 현재 활동 등록 정보
                  //   · 관리자·본인·타인 모두에게 가장 먼저 보이도록 최상단에 노출한다.
                  _credentialCard(m),
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
                  _eventSection(m),
                  _depositSection(m),
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

  /// 상세 헤더 — 좌(번호 박스+이름) / 우(사진) 2분할, 축소
  Widget _header(Member m) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      padding: const EdgeInsets.fromLTRB(16, 44, 16, 10),
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
                const Text(
                  '한국 범스카우트중앙회',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                // 원형 대신 각진 박스로 인가번호 표시
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.tigerGold, width: 2),
                  ),
                  child: Text(
                    '#${m.number}',
                    style: const TextStyle(
                      color: AppColors.purple,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.name.isEmpty ? '(이름없음)' : m.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
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
                  Text(
                    '인가시: ${[m.league, m.unit].where((e) => e.isNotEmpty).join(' · ')}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                // 현재활동 소속 — 인가시와 다르거나 값이 있으면 노출.
                if ((m.regLeague.isNotEmpty && m.regLeague != m.league) ||
                    (m.regUnit.isNotEmpty && m.regUnit != m.unit) ||
                    m.position.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '현재활동: ${[if (m.regLeague.isNotEmpty) m.regLeague, if (m.regUnit.isNotEmpty) m.regUnit, if (m.position.isNotEmpty) m.position].join(' · ')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
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
            ),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                MemberAvatar(
                  name: m.name,
                  photoPath: m.photoPath,
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

  /// 개인별 입금 내역 — 후원/수품구매/참가비 등 모든 입금을 즉시 확인
  Widget _depositSection(Member m) {
    final fs = context.watch<FinanceService>();
    final deposits = fs.depositsOf(m.number);
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
                      t.category == '후원'
                          ? Icons.volunteer_activism
                          : t.category == '수품구매'
                          ? Icons.shopping_bag
                          : t.category == '참가비'
                          ? Icons.event_available
                          : Icons.savings,
                      size: 18,
                      color: AppColors.scoutGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${t.category}'
                            '${t.event.isNotEmpty ? ' · ${t.event}' : ''}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          Text(
                            '${t.date}'
                            '${t.context.isNotEmpty ? ' · ${t.context}' : ''}',
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

  /// (요구 #4) 평생회원 여부 — 편집 화면 최상단. 관리자·마스터만 노출.
  ///  마스터는 여기서 평생회원 지정/해제가 가능하다.
  Widget _lifetimeSection(Member m) {
    final state = context.watch<AppState>();
    final canMaster = state.isMaster;
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
          if (canMaster)
            Row(
              children: [
                Switch(
                  value: m.lifetimeMember,
                  activeThumbColor: AppColors.tigerGold,
                  onChanged: (v) => context.read<AppState>().save(
                    m.copyWith(
                      lifetimeMember: v,
                      lifetimeSince: v && m.lifetimeSince.isEmpty
                          ? DateTime.now().toIso8601String().substring(0, 10)
                          : m.lifetimeSince,
                    ),
                  ),
                ),
                const Text(
                  '평생회원 지정 (마스터)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 15,
                  color: AppColors.textGray,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '평생회원 지정은 마스터만 가능합니다. '
                    '개인 프로필의 “등록요청”으로 요청하세요.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
                  ),
                ),
              ],
            ),
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
        ],
      ),
    );
  }

  /// [삭제됨] 수품구매현황 단독 섹션 — MerchActivitySection으로 통합되어 제거.
  /// (메모 표시·편집은 MerchActivitySection의 memo/onEditMemo로 이관)

  Future<void> _editPurchases(Member m) async {
    final ctrl = TextEditingController(text: m.purchases);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
                      child: Text(
                        p,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
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

  /// 멘토·페런츠 연결 승인 상태 뱃지(라벨) — 승인대기/보류/승인.
  String _linkBadge(Member m) {
    switch (m.linkApprovalStatus) {
      case 'pending':
        return '  [승인대기]';
      case 'held':
        return '  [보류]';
      case 'approved':
        return '  [승인됨]';
      default:
        return '';
    }
  }

  /// 멘토·페런츠 인가번호 라벨 — 인적사항이 있으면 "이름 #번호" 로 표시한다.
  ///   (요구: 개인프로필에 멘토·페런츠 메달 수여자 이름도 함께 표시)
  ///   · memberNoKind == 'mentor' 이면 표시 번호는 **멘티(본인) 범인가자번호**.
  String _linkNameLabel(String code, {String numberKind = 'parent'}) {
    final p = _profileOf(code);
    final nm = '${p['name'] ?? ''}'.trim();
    final no = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (nm.isEmpty) {
      return numberKind == 'mentor' ? '멘티 #$code' : '#$code';
    }
    return numberKind == 'mentor' ? '$nm (멘티 #$no)' : '$nm #$no';
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
            child: Text(
              [
                product,
                if (detail.isNotEmpty) detail,
              ].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textDark),
              overflow: TextOverflow.ellipsis,
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
  Widget _credentialCard(Member m) {
    final state = context.watch<AppState>();
    final canEdit =
        state.isApp || state.isMaster || state.isSelfNumber(m.number);
    // 멘토: 코드는 멘티(본인) 범인가자번호 → 표시는 "멘토이름 (멘티 #번호)".
    final mentorLabels = m.mentors
        .map((e) => _linkNameLabel(e, numberKind: 'mentor'))
        .join(', ');
    final parentLabels = m.parents.map((e) => _linkNameLabel(e)).join(', ');
    return _section(
      title: '범스카우트 인가 정보 (인가 당시 정보)',
      icon: Icons.verified_user,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _plainRow('소속 연맹', m.league),
          _plainRow('등록 단위대', m.unit),
          _plainRow('인가일', m.date),
          // 멘토대장·페런츠 등록현황 — 미등록도 표시(누락 방지).
          _regRow(
            '멘토대장',
            mentorLabels.isEmpty ? '' : '$mentorLabels${_linkBadge(m)}',
          ),
          _regRow('페런츠', parentLabels),
          // (복원) 편집 권한자에게는 그 자리에서 입력하는 멘토·페런츠 입력창을 노출.
          if (canEdit) ...[const Divider(height: 22), _linkEditor(m)],
        ],
      ),
    );
  }

  /// 멘토·페런츠 **입력창 복원** — 개인정보(상세)창에서 직접 등록/수정.
  ///   · 편집 화면(member_edit_screen)과 완전히 동일한 위젯/기준을 사용한다.
  ///   · 변경 즉시 회원 데이터에 반영하고 저장(연결 승인 상태는 pending 으로 전환).
  Widget _linkEditor(Member m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '멘토·페런츠 등록 (복수 입력 가능)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.textGray,
          ),
        ),
        const SizedBox(height: 6),
        LinkCodeField(
          label: '멘토',
          icon: Icons.supervisor_account,
          kind: 'mentor',
          codes: m.mentors,
          menteeNumber: m.number.trim(),
          editable: true,
          onChanged: (v) => _saveLinks(m, mentors: v),
        ),
        LinkCodeField(
          label: '페런츠',
          icon: Icons.family_restroom,
          kind: 'parent',
          codes: m.parents,
          editable: true,
          // 요구: 소속연맹/단위대가 없으면 인가자(본인) 값을 쓴다.
          defaultLeague: m.league,
          defaultUnit: m.unit,
          onChanged: (v) => _saveLinks(m, parents: v),
        ),
      ],
    );
  }

  /// 멘토·페런츠 연결 저장 — 회원 데이터 반영 + 서버 저장.
  ///   · 대상이 바뀌면 연결 승인 상태를 'pending'(미승인)으로 전환한다
  ///     (편집 화면과 동일 정책).
  Future<void> _saveLinks(
    Member m, {
    List<String>? mentors,
    List<String>? parents,
  }) async {
    final state = context.read<AppState>();
    final nextMentors = mentors ?? List<String>.from(m.mentors);
    final nextParents = parents ?? List<String>.from(m.parents);
    final hasLinks = nextMentors.isNotEmpty || nextParents.isNotEmpty;
    final updated = m.copyWith(
      mentors: nextMentors,
      parents: nextParents,
      linkApprovalStatus: hasLinks ? 'pending' : '',
      linkApprovalNote: hasLinks ? m.linkApprovalNote : '',
    );
    try {
      await state.save(updated, linkRequestSource: 'direct');
      if (!mounted) return;
      await _loadLinkProfiles();
      _snack('멘토·페런츠 등록을 저장했습니다 (관리자 승인 대기)');
    } catch (_) {
      if (!mounted) return;
      _snack('저장에 실패했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  /// 등록현황 행 — 값이 없어도 항상 표시("미등록"). (멘토·페런츠 등록현황)
  Widget _regRow(String label, String value) {
    final empty = value.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
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
              empty ? '미등록' : value,
              style: TextStyle(
                color: empty ? AppColors.textGray : AppColors.textDark,
                fontSize: 13.5,
                fontStyle: empty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
    final fields = <List<String>>[
      ['Scout 고유번호', 'scoutNo', m.scoutNo],
      ['주민등록번호', 'residentNo', m.residentNo],
      ['생일', 'birthday', m.birthday],
      ['성별', 'gender', m.gender],
      ['기념일', 'anniversary', m.anniversary],
      ['훈련현황', 'trainingStatus', m.trainingStatus],
      ['포상', 'awards', m.awards],
      ['전문과정 이수', 'specialtyCourses', m.specialtyCourses],
      ['ATAS 인가번호', 'atasNo', m.atasNo],
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
  Widget _plainRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
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
                m.isRegular ? '현재: 일반회원 (비인가자)' : '현재: 인가자 (#${m.number})',
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
      _snack('인가자로 승격했습니다 (#${updated.number})');
      setState(() {});
    }
  }

  /// 비밀번호 관리 — 관리자·마스터 전용 (강제 변경/초기화)
  ///  · 현재 비밀번호 "실제값" 노출은 마스터만 가능 (요구사항)
  ///  · 관리자는 일반회원 비번 초기화만, 인가자 비번 변경·초기화는 마스터 전용
  Widget _passwordSection(Member m) {
    final state = context.watch<AppState>();
    if (!(state.isApp || state.isMaster)) return const SizedBox.shrink();
    final isRegular = m.isRegular;
    final isMaster = state.isMaster;
    // 서버 정책: 관리자(비마스터)는 일반회원 비번만 변경 가능, 인가자는 마스터 전용
    final canEditThis = isMaster || isRegular;
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
                      ? '일반회원 · ID ${m.loginId} · 기본비번(뒤 4자리) ${m.phoneLast4}'
                      : '인가자 · ID ${m.number} · 기본비번 ${m.number}!@@',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
              ),
            ],
          ),
          // ---- 마스터 전용: 현재 접속 비밀번호 실제값 노출 ----
          if (isMaster) ...[
            const SizedBox(height: 10),
            _currentPasswordReveal(m),
          ],
          const SizedBox(height: 10),
          if (!canEditThis)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.tigerGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.tigerGold.withValues(alpha: 0.5),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppColors.lifetimeGold,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '인가자 비밀번호 분실로 인한 비밀번호 변경 및 초기화는\n마스터만 가능합니다.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.lifetimeGold,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // 인가자(마스터 대상) 안내 — 요구 문구
            if (!isRegular)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '인가자 비밀번호 분실로 인한 비밀번호 변경 및 초기화는 마스터만 가능합니다.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGray,
                    height: 1.35,
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _forceReset(m),
                  icon: const Icon(Icons.lock_reset, size: 17),
                  label: const Text('비번 초기화'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _forceChange(m),
                  icon: const Icon(Icons.lock_open, size: 17),
                  label: const Text('비번 강제 변경'),
                ),
              ],
            ),
          ],
        ],
      ),
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

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
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
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.textDark,
                  ),
                ),
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

  void _edit(Member m) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberEditScreen(memberId: m.id)),
    );
    if (mounted) context.read<AppState>().refresh();
  }

  /// 개인정보 최종 출력 — 선택한 형식(PDF/JPG/엑셀/워드/PPT)으로 내보낸다.
  void _exportPersonal(Member m) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          members: [m],
          title: '개인정보 출력 — ${m.name} (#${m.number})',
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
