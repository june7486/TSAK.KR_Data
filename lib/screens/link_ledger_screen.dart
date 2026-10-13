import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/file_save.dart';
import '../services/nas_api.dart';
import '../services/output_formats.dart';
import '../services/table_export.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/marquee_text.dart';
import '../widgets/member_avatar.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/tsak_output_preview.dart';
import '../widgets/tsak_output_sheet.dart';
import '../widgets/tsak_table_options.dart';
import 'member_detail_screen.dart';

/// 멘토장부 · 페런츠장부 · 멘티장부 — 관리자·마스터 전용.
///
/// ## 요구
///  · "멘토장부, 페런츠 장부, 멘티장부 모두 존재해야함"
///  · "멘토, 페런츠 장부에는 멘토메달, 멘토항건 구매여부, 시점도 표시함.
///    연차등록 여부도 표시함"
///  · "모든 정보는 회원정보와 동일한 카드구성이며 노출여부도 회원과 동일한
///    기준으로 적용함"
///  · "출력항목 선택시에도 동일하게 미리보기 및 각종 사이즈 조정 가능하도록 함.
///    외부출력도 동일한 포멧임"
///
/// ## 데이터
///  · 멘토/페런츠 : link_profiles.json(kind) 인적사항(번호·이름·연락처·소속·아이디).
///  · 멘티        : 회원 명단의 mentees[](멘토=멘티=페런츠 연동)에서 파생.
///  · 멘토/페런츠 메달·중앙회 항건 구매여부·시점 = 수품 주문(merch.json) 연동.
///  · 연차등록 여부 = 회원 연회비 납부(feeYears) / 평생회원 여부.
class LinkLedgerScreen extends StatefulWidget {
  const LinkLedgerScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<LinkLedgerScreen> createState() => _LinkLedgerScreenState();
}

class _LinkLedgerScreenState extends State<LinkLedgerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// kind('mentor'|'parent'|'mentee') → 엔트리 목록.
  Map<String, List<Map<String, dynamic>>> _data = {
    'mentor': [],
    'parent': [],
    'mentee': [],
  };

  final _searchCtrl = TextEditingController();
  String _q = '';

  // 좌측 선택(개별) 방식 — 회원정보와 동일 규칙으로 출력 대상을 고른다.
  final Set<String> _sel = {};
  bool _selMode = false;

  /// 출력 옵션(출력항목 선택·위치이동·글씨크기·줄간격·용지) — 명부와 동일.
  TableOutputOptions? _outOpts;

  static const List<String> _kinds = ['mentor', 'parent', 'mentee'];
  static const List<String> _tabLabels = ['멘토장부', '페런츠장부', '멘티장부'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _tab.addListener(() {
      if (_tab.indexIsChanging) return;
      if (_sel.isNotEmpty) setState(() => _sel.clear());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final nas = context.read<NasApi>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await nas.linkLedger();
      if (!mounted) return;
      setState(() {
        _data = {
          'mentor': _asList(d['mentor']),
          'parent': _asList(d['parent']),
          'mentee': _asList(d['mentee']),
        };
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _asList(dynamic v) {
    if (v is List) {
      return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return [];
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String get _kind => _kinds[_tab.index];

  List<Map<String, dynamic>> _filtered(String kind) {
    final all = _data[kind] ?? const <Map<String, dynamic>>[];
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return all;
    final dn = q.replaceAll(RegExp(r'[^0-9]'), '');
    return all.where((e) {
      final hay = [
        '${e['name'] ?? ''}',
        '${e['number'] ?? ''}',
        '${e['phone'] ?? ''}',
        '${e['league'] ?? ''}',
        '${e['unit'] ?? ''}',
        '${e['loginId'] ?? ''}',
        '${e['mentor'] ?? ''}',
      ].join(' ').toLowerCase();
      if (hay.contains(q)) return true;
      if (dn.isNotEmpty &&
          '${e['phone'] ?? ''}'
              .replaceAll(RegExp(r'[^0-9]'), '')
              .contains(dn)) {
        return true;
      }
      return false;
    }).toList();
  }

  // ---- 값 추출 헬퍼 ----
  String _org(Map<String, dynamic> e) {
    final l = '${e['league'] ?? ''}'.trim();
    final u = '${e['unit'] ?? ''}'.trim();
    if (l.isEmpty && u.isEmpty) return '';
    if (l.isEmpty) return u;
    if (u.isEmpty) return l;
    return '$l · $u';
  }

  Map<String, dynamic> _medal(Map<String, dynamic> e, String key) {
    final v = e[key];
    return v is Map ? v.cast<String, dynamic>() : const {};
  }

  Map<String, dynamic> _annual(Map<String, dynamic> e) {
    final v = e['annual'];
    return v is Map ? v.cast<String, dynamic>() : const {};
  }

  String _medalText(Map<String, dynamic> e, String key) {
    final m = _medal(e, key);
    return m['bought'] == true ? '있음' : '없음';
  }

  String _medalAt(Map<String, dynamic> e, String key) {
    final m = _medal(e, key);
    return m['bought'] == true ? '${m['at'] ?? ''}'.trim() : '-';
  }

  // ===================== 출력 컬럼 =====================
  List<String> _columnsFor(String kind) {
    if (kind == 'parent') {
      return [
        '#',
        '인가번호',
        '이름',
        '연락처',
        '소속',
        '아이디',
        '페런츠메달',
        '페런츠메달시점',
        '항건',
        '항건시점',
        '연차등록',
        '보호대원',
      ];
    }
    if (kind == 'mentee') {
      return [
        '#',
        '인가번호',
        '이름',
        '연락처',
        '소속',
        '아이디',
        '멘토메달',
        '멘토메달시점',
        '항건',
        '항건시점',
        '연차등록',
        '배출멘토',
      ];
    }
    return [
      '#',
      '인가번호',
      '이름',
      '연락처',
      '소속',
      '아이디',
      '멘토메달',
      '멘토메달시점',
      '항건',
      '항건시점',
      '연차등록',
      '배출대원',
    ];
  }

  List<String> _rowFor(String kind, Map<String, dynamic> e, int idx) {
    final medalKey = kind == 'parent' ? 'parentMedal' : 'mentorMedal';
    final last = kind == 'mentee'
        ? '${e['mentor'] ?? ''}'.trim()
        : '${e['links'] ?? 0}';
    return [
      '${idx + 1}',
      '${e['number'] ?? ''}',
      '${e['name'] ?? ''}',
      '${e['phone'] ?? ''}',
      _org(e),
      '${e['loginId'] ?? ''}'.trim(),
      _medalText(e, medalKey),
      _medalAt(e, medalKey),
      _medalText(e, 'hangeon'),
      _medalAt(e, 'hangeon'),
      '${_annual(e)['status'] ?? '—'}',
      last,
    ];
  }

  String _titleFor(String kind) {
    if (kind == 'parent') return '페런츠장부';
    if (kind == 'mentee') return '멘티장부';
    return '멘토장부';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!(state.isApp || state.isMaster)) {
      return Scaffold(
        appBar: TsakAppBar(
          leading: const AppBackButton(label: '뒤로'),
          leadingWidth: 84,
          title: const Text('장부'),
        ),
        body: const Center(child: Text('관리자 권한이 필요합니다')),
      );
    }

    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('멘토 · 페런츠 · 멘티 장부'),
        actions: [
          IconButton(
            tooltip: '출력 옵션 (항목 선택 · 사이즈)',
            onPressed: _editOptions,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const AppHomeEmblem(size: 26),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: AppColors.purple,
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
              tabs: [for (final l in _tabLabels) Tab(text: l)],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [_body(state), if (_busy) const BusyOverlay(visible: true)],
      ),
    );
  }

  Widget _body(AppState state) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 44,
              color: AppColors.tigerGold,
            ),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _refresh, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    return TabBarView(
      controller: _tab,
      children: [for (final k in _kinds) _ledgerTab(k)],
    );
  }

  Widget _ledgerTab(String kind) {
    final list = _filtered(kind);
    final total = (_data[kind] ?? const []).length;
    return Column(
      children: [
        _searchBar(),
        _toolbar(kind, list.length, total),
        const Divider(height: 1),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    total == 0
                        ? '${_titleFor(kind)}에 표시할 항목이 없습니다.'
                        : '검색 결과가 없습니다.',
                    style: const TextStyle(color: AppColors.textGray),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 18),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _ledgerCard(kind, list[i], i),
                ),
        ),
      ],
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _q = v),
        decoration: InputDecoration(
          hintText: '이름 · 인가번호 · 연락처 · 소속 검색',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          suffixIcon: _q.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _q = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _toolbar(String kind, int shown, int total) {
    final canOutput = shown > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
      child: Row(
        children: [
          Text(
            '${_titleFor(kind)} $total명'
            '${_q.isEmpty ? '' : ' · 검색 $shown명'}'
            '${_sel.isEmpty ? '' : ' · 선택 ${_sel.length}명'}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: _selMode ? '개별 선택 끄기' : '개별 선택',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() {
              _selMode = !_selMode;
              if (!_selMode) _sel.clear();
            }),
            icon: Icon(
              _selMode ? Icons.check_box : Icons.check_box_outline_blank,
              size: 19,
              color: _selMode ? AppColors.purple : AppColors.textGray,
            ),
          ),
          if (_selMode)
            IconButton(
              tooltip: _sel.length == shown ? '전체해제' : '전체선택',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                final keys = [for (var i = 0; i < shown; i++) _keyOf(kind, i)];
                if (_sel.length == shown) {
                  _sel.clear();
                } else {
                  _sel
                    ..clear()
                    ..addAll(keys);
                }
              }),
              icon: const Icon(Icons.select_all, size: 19),
            ),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: AppColors.purpleDark,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: canOutput ? () => _openOutputSheet(kind) : null,
            icon: const Icon(Icons.ios_share, size: 16),
            label: const Text(
              '출력',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  String _keyOf(String kind, int idx) => '$kind:$idx';

  /// 회원정보와 동일한 카드구성 — 사진·인가번호 배지·이름·소속 + 장부 정보칩.
  Widget _ledgerCard(String kind, Map<String, dynamic> e, int idx) {
    final state = context.watch<AppState>();
    final num = '${e['number'] ?? ''}'.trim();
    final member = num.isEmpty ? null : state.byNumber(num);
    // 멘토는 number 가 **멘티(받는분) 번호**이므로(기존 link_profiles 규칙),
    //  회원 조회명을 그대로 쓰면 멘티 이름이 노출된다 → 멘토 이름(e['name']) 우선.
    //  (페런츠·멘티는 number 가 본인 번호이므로 회원 조회명을 그대로 사용 — 노출기준 동일)
    final useMember = kind != 'mentor' && member != null;
    final name = useMember
        ? member.displayName(canSeeRealName: state.isApp || state.isMaster)
        : (('${e['name'] ?? ''}'.trim().isEmpty)
              ? '(이름 미확인)'
              : '${e['name']}'.trim());
    final annual = _annual(e);
    final life = annual['life'] == true;
    final key = _keyOf(kind, idx);
    final on = _sel.contains(key);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: on
            ? const BorderSide(color: AppColors.purple, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: member != null ? () => _openDetail(member.id) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_selMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() {
                          if (on) {
                            _sel.remove(key);
                          } else {
                            _sel.add(key);
                          }
                        }),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: on ? AppColors.purple : Colors.white,
                            border: Border.all(
                              color: AppColors.purple.withValues(alpha: 0.5),
                              width: 2,
                            ),
                          ),
                          child: on
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                )
                              : null,
                        ),
                      ),
                    ),
                  _avatar(state, member, e, num, name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: MarqueeText(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _kindChip(kind),
                            const SizedBox(width: 4),
                            if (num.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.purple,
                                      AppColors.purpleLight,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$num호',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            if (life) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.star,
                                size: 16,
                                color: AppColors.tigerGold,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (('${e['phone'] ?? ''}'.trim()).isNotEmpty) ...[
                              const Icon(
                                Icons.phone,
                                size: 13,
                                color: AppColors.scoutGreen,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${e['phone']}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ],
                            if (_org(e).isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: MarqueeText(
                                  _org(e),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textGray,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textGray,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _infoChips(kind, e, annual),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(
    AppState state,
    Member? member,
    Map<String, dynamic> e,
    String num,
    String name,
  ) {
    return MemberAvatar(
      name: name,
      photoPath: member?.photoPath ?? '',
      fallbackPhotoUrl: num.isEmpty ? '' : (state.serverPhotoUrlFor(num) ?? ''),
      league: '${e['league'] ?? ''}',
      size: 50,
      number: num,
      showNumber: false,
      useTigerDefault: true,
    );
  }

  Widget _kindChip(String kind) {
    final (label, color) = switch (kind) {
      'parent' => ('페런츠', AppColors.taegeukBlue),
      'mentee' => ('멘티', AppColors.scoutGreen),
      _ => ('멘토', AppColors.purple),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  /// 장부 정보칩 — 멘토메달/페런츠메달/항건 구매여부·시점 + 연차등록 여부.
  List<Widget> _infoChips(
    String kind,
    Map<String, dynamic> e,
    Map<String, dynamic> annual,
  ) {
    final chips = <Widget>[];
    final medalKey = kind == 'parent' ? 'parentMedal' : 'mentorMedal';
    final medalLabel = kind == 'parent' ? '페런츠메달' : '멘토메달';
    final medalColor = kind == 'parent'
        ? AppColors.taegeukBlue
        : AppColors.purple;
    chips.add(
      _chip(
        Icons.workspace_premium,
        medalLabel,
        _medalText(e, medalKey),
        medalColor,
        _medalAt(e, medalKey),
      ),
    );
    chips.add(
      _chip(
        Icons.style,
        '중앙회 항건',
        _medalText(e, 'hangeon'),
        AppColors.tigerGold,
        _medalAt(e, 'hangeon'),
      ),
    );
    if (kind == 'mentee') {
      final mn = '${e['mentor'] ?? ''}'.trim();
      chips.add(
        _chip(
          Icons.supervisor_account,
          '배출 멘토',
          mn.isEmpty ? '—' : mn,
          AppColors.purple,
          '${e['mentorNo'] ?? ''}',
        ),
      );
    } else {
      chips.add(
        _chip(
          Icons.groups,
          kind == 'parent' ? '보호대원' : '배출대원',
          '${e['links'] ?? 0}',
          AppColors.taegeukBlue,
          '',
        ),
      );
    }
    chips.add(_annualChip(annual));
    return chips;
  }

  Widget _chip(
    IconData icon,
    String label,
    String value,
    Color color,
    String sub,
  ) {
    final has =
        value == '있음' || (value != '없음' && value != '—' && value != '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: has ? AppColors.textDark : AppColors.textGray,
            ),
          ),
          if (sub.trim().isNotEmpty && sub != '-') ...[
            const SizedBox(width: 4),
            Text(
              sub.trim(),
              style: const TextStyle(fontSize: 10, color: AppColors.textGray),
            ),
          ],
        ],
      ),
    );
  }

  Widget _annualChip(Map<String, dynamic> annual) {
    final status = '${annual['status'] ?? '—'}';
    final life = annual['life'] == true;
    final paid = status.startsWith('연차등록');
    final color = life
        ? AppColors.lifetimeGold
        : (paid ? AppColors.scoutGreen : AppColors.taegeukRed);
    final icon = life
        ? Icons.star
        : (paid ? Icons.event_available : Icons.event_busy);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          const Text(
            '연차등록 ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textGray,
            ),
          ),
          Text(
            status,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(String id) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MemberDetailScreen(memberId: id)));
  }

  // ===================== 출력 =====================

  TsakTableDoc _buildDoc(
    String kind, {
    required List<Map<String, dynamic>> list,
    required String subtitle,
  }) {
    final cols = _columnsFor(kind);
    final rows = <List<String>>[
      for (var i = 0; i < list.length; i++) _rowFor(kind, list[i], i),
    ];
    return TsakTableDoc(
      title: _titleFor(kind),
      subtitle: subtitle,
      description: '${_titleFor(kind)} 출력물입니다.',
      columns: cols,
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · ${_titleFor(kind)}',
      options: _outOpts,
    );
  }

  /// 출력 대상 — 개별 선택이 있으면 선택분만, 없으면 현재 화면(검색) 전체.
  List<Map<String, dynamic>> _targets(String kind) {
    final list = _filtered(kind);
    if (_selMode && _sel.isNotEmpty) {
      final out = <Map<String, dynamic>>[];
      for (var i = 0; i < list.length; i++) {
        if (_sel.contains(_keyOf(kind, i))) out.add(list[i]);
      }
      return out;
    }
    return list;
  }

  Future<void> _editOptions() async {
    final kind = _kind;
    final out = await showTsakTableOptions(
      context,
      title: '${_titleFor(kind)} 출력 옵션',
      subtitle: '출력할 항목을 고르고, 순서를 옮기고, 줄 간격·글씨·용지를 정하세요.',
      columns: _columnsFor(kind),
      initial: _outOpts,
    );
    if (out != null && mounted) {
      setState(() => _outOpts = out);
      _snack('출력 옵션을 저장했습니다 · ${out.badge}');
    }
  }

  Future<void> _openOutputSheet(String kind) async {
    final list = _targets(kind);
    if (list.isEmpty) {
      _snack('출력할 항목이 없습니다');
      return;
    }
    final selectedOnly = _selMode && _sel.isNotEmpty;
    final subtitle =
        '${selectedOnly ? '선택' : '전체'} ${list.length}명'
        '${_outOpts == null ? '' : ' · ${_outOpts!.badge}'}';
    await showTsakOutputSheet(
      context,
      title: '${_titleFor(kind)} 출력',
      subtitle: subtitle,
      onPick: (f) => _runOutput(kind, list, f, selectedOnly: selectedOnly),
      onOpen: (f) => _openOutputFile(kind, list, f, selectedOnly: selectedOnly),
      onShareFormat: (f) =>
          _shareOutput(kind, list, f, selectedOnly: selectedOnly),
      onPrint: () => _runOutput(
        kind,
        list,
        TsakOutputFormat.pdf,
        justPrint: true,
        selectedOnly: selectedOnly,
      ),
      onEmail: () => _emailOutput(kind, list, selectedOnly: selectedOnly),
      onShare: () => _shareOutput(
        kind,
        list,
        TsakOutputFormat.pdf,
        selectedOnly: selectedOnly,
      ),
      onOptions: _editOptions,
      onPreview: () => showTsakOutputPreview(
        context,
        doc: _buildDoc(
          kind,
          list: list,
          subtitle: '한국범스카우트중앙회 · ${_titleFor(kind)}',
        ),
      ),
      onShareLink: () => showLinkShareDialog(context, Uri.base.toString()),
    );
  }

  Future<void> _runOutput(
    String kind,
    List<Map<String, dynamic>> list,
    TsakOutputFormat format, {
    bool justPrint = false,
    required bool selectedOnly,
  }) async {
    final doc = _buildDoc(
      kind,
      list: list,
      subtitle: '한국범스카우트중앙회 · ${_titleFor(kind)}',
    );
    setState(() => _busy = true);
    try {
      var choose = false;
      if (!justPrint) {
        final loc = await askTsakSaveLocation(
          context,
          info: '${_titleFor(kind)} · ${list.length}명 · ${format.label}',
        );
        if (loc == null) {
          if (mounted) _snack('저장을 취소했습니다');
          return;
        }
        choose = loc;
      }
      if (!mounted) return;
      await runWithTsakProgress(
        context,
        title: justPrint ? '프린트 준비' : '${_titleFor(kind)} ${format.label} 생성',
        note: '${list.length}명을 처리합니다.',
        steps: justPrint
            ? const ['문서 구성', '인쇄 창 열기']
            : ['문서 구성', '${format.label} 생성', '파일 저장'],
        task: (ctl) async {
          ctl.update(progress: 0.15, message: '문서를 구성하는 중…', stepIndex: 0);
          if (justPrint) {
            ctl.update(progress: 0.6, message: '인쇄 창을 여는 중…', stepIndex: 1);
            await printTsakTable(doc);
            ctl.update(progress: 1.0, stepIndex: 2);
            return;
          }
          ctl.update(
            progress: 0.5,
            message: '${format.label} 생성 중…',
            stepIndex: 1,
          );
          await saveTsakTableChosen(context, doc, format, choose: choose);
          ctl.update(progress: 1.0, message: '완료', stepIndex: 2);
        },
      );
      if (mounted) {
        _snack(justPrint ? '인쇄 창을 열었습니다' : '${format.label} 저장을 시작했습니다');
      }
    } catch (e) {
      if (mounted) _snack('출력 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOutputFile(
    String kind,
    List<Map<String, dynamic>> list,
    TsakOutputFormat format, {
    required bool selectedOnly,
  }) async {
    final doc = _buildDoc(
      kind,
      list: list,
      subtitle: '한국범스카우트중앙회 · ${_titleFor(kind)}',
    );
    setState(() => _busy = true);
    try {
      late TsakShareResult res;
      await runWithTsakProgress(
        context,
        title: '${_titleFor(kind)} ${format.label} 외부 열기',
        note: '${list.length}명을 ${format.label}(으)로 만들어 엽니다.',
        steps: ['문서 구성', '${format.label} 생성', '외부 프로그램 열기'],
        task: (ctl) async {
          ctl.update(progress: 0.2, message: '문서를 구성하는 중…', stepIndex: 0);
          ctl.update(
            progress: 0.6,
            message: '${format.label} 생성 중…',
            stepIndex: 1,
          );
          res = await openTsakTableChosen(context, doc, format);
          ctl.update(progress: 1.0, message: '외부 프로그램을 엽니다', stepIndex: 2);
        },
      );
      if (mounted) {
        _snack(
          tsakShareMessage(res, what: '${_titleFor(kind)} ${format.label}'),
        );
      }
    } catch (e) {
      if (mounted) _snack('열기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareOutput(
    String kind,
    List<Map<String, dynamic>> list,
    TsakOutputFormat format, {
    required bool selectedOnly,
  }) async {
    final doc = _buildDoc(
      kind,
      list: list,
      subtitle: '한국범스카우트중앙회 · ${_titleFor(kind)}',
    );
    setState(() => _busy = true);
    try {
      late TsakShareResult res;
      await runWithTsakProgress(
        context,
        title: '${_titleFor(kind)} 공유 준비',
        note: '${list.length}명을 ${format.label}(으)로 만들어 공유합니다.',
        steps: ['문서 구성', '${format.label} 생성', '공유 시트 열기'],
        task: (ctl) async {
          ctl.update(progress: 0.2, message: '문서를 구성하는 중…', stepIndex: 0);
          ctl.update(
            progress: 0.6,
            message: '${format.label} 생성 중…',
            stepIndex: 1,
          );
          res = await shareTsakTableChosen(context, doc, format);
          ctl.update(progress: 1.0, message: '공유 시트를 엽니다', stepIndex: 2);
        },
      );
      if (mounted) {
        _snack(
          tsakShareMessage(res, what: '${_titleFor(kind)} ${format.label}'),
        );
      }
    } catch (e) {
      if (mounted) _snack('공유 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emailOutput(
    String kind,
    List<Map<String, dynamic>> list, {
    required bool selectedOnly,
  }) async {
    final doc = _buildDoc(
      kind,
      list: list,
      subtitle: '한국범스카우트중앙회 · ${_titleFor(kind)}',
    );
    await emailTsakTable(context, doc);
  }
}
