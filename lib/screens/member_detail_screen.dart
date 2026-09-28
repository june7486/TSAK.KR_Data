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
import '../widgets/merch_activity_section.dart';
import '../widgets/photo_pip.dart';
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

  /// 마스터 전용 "현재 비밀번호" 조회 future 캐시 (리빌드 시 재조회 방지).
  Future<Map<String, dynamic>?>? _pwFuture;
  String? _pwFutureKey;

  /// 이름 공개/비공개 서버 저장 진행 중 여부(연타 방지).
  bool _nameBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadKnownEvents());
  }

  Future<void> _loadKnownEvents() async {
    try {
      final api = context.read<NasApi>();
      final ev = await api.eventList2(media: false);
      final names = <String>{};
      for (final e in ev) {
        if (e['defined'] == false) continue;
        final t = '${e['title'] ?? ''}'.trim();
        if (t.isNotEmpty) names.add(t);
      }
      if (mounted) {
        setState(() {
          _knownEvents = names;
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
      body: CustomScrollView(
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
                _depositSection(m),
                _feeTracker(m),
                _eventSection(m),
                MerchActivitySection(
                  ident: m.number.isNotEmpty ? m.number : m.phone,
                  memberName: m.name,
                  phone: m.phone,
                  email: m.email,
                  memo: m.purchases,
                  canEditMemo: context.read<AppState>().isApp,
                  onEditMemo: () => _editPurchases(m),
                ),
                _infoCard(m),
                _membershipSection(m),
                _passwordSection(m),
                MemberAccessLogSection(member: m),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
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
                if (m.league.isNotEmpty || m.unit.isNotEmpty)
                  Text(
                    [m.league, m.unit].where((e) => e.isNotEmpty).join(' · '),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                if ((m.regLeague.isNotEmpty && m.regLeague != m.league) ||
                    (m.regUnit.isNotEmpty && m.regUnit != m.unit))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '재적: ${[m.regLeague, m.regUnit].where((e) => e.isNotEmpty).join(' · ')}',
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

  Widget _feeTracker(Member m) {
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
          if (m.lifetimeMember)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.tigerGold, Color(0xFFE09F00)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text(
                    '평생회원',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: years.map((y) {
              final paid = m.feeYears[y] == true;
              return GestureDetector(
                onTap: () {
                  final map = Map<String, bool>.from(m.feeYears);
                  map[y] = !paid;
                  context.read<AppState>().save(m.copyWith(feeYears: map));
                },
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
          const SizedBox(height: 10),
          Row(
            children: [
              Switch(
                value: m.lifetimeMember,
                activeThumbColor: AppColors.tigerGold,
                onChanged: (v) => context.read<AppState>().save(
                  m.copyWith(lifetimeMember: v),
                ),
              ),
              const Text(
                '평생회원 지정',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Text(
            '* 연도를 눌러 납부 여부를 변경할 수 있습니다.',
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
    // 참가한 모든 행사를 최신순(연도 내림차순)으로 아래로 나열한다.
    final events = m.eventAttend.keys.toList()
      ..sort((a, b) {
        final ya = RegExp(r'\d{4}').firstMatch(a)?.group(0) ?? '0000';
        final yb = RegExp(r'\d{4}').firstMatch(b)?.group(0) ?? '0000';
        if (ya != yb) return yb.compareTo(ya);
        return b.compareTo(a);
      });
    final attendedCount = events.where((e) => m.eventAttend[e] == true).length;
    return _section(
      title: '행사참가',
      icon: Icons.event,
      child: events.isEmpty
          ? Row(
              children: [
                Text(
                  '등록된 행사가 없습니다.',
                  style: TextStyle(color: AppColors.textGray, fontSize: 13),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _addEvent(m),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('행사 추가'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '참가 $attendedCount건 · 전체 ${events.length}건',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ...events.map((e) {
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
                                attend ? '참가' : '불참',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: attend
                                      ? AppColors.taegeukBlue
                                      : AppColors.textGray,
                                  fontWeight: attend
                                      ? FontWeight.w700
                                      : FontWeight.w400,
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

  Future<void> _addEvent(Member m) async {
    final ctrl = TextEditingController();
    // 행사관리 목록에 있는 행사를 우선 선택하도록 제안 (관리목록누락 예방)
    final suggestions = _knownEvents.toList()..sort();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('행사 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (suggestions.isNotEmpty) ...[
              const Text(
                '행사관리 목록에서 선택',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      onPressed: () => Navigator.pop(ctx, s),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '또는 새 이름 직접 입력',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
            ],
            TextField(
              controller: ctrl,
              autofocus: suggestions.isEmpty,
              decoration: const InputDecoration(
                hintText: '예: 2026 정기총회 / 하계캠프',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      final map = Map<String, bool>.from(m.eventAttend);
      map[name] = true;
      await context.read<AppState>().save(m.copyWith(eventAttend: map));
      if (mounted) setState(() {});
    }
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

  Widget _infoCard(Member m) {
    final rows = <List<String>>[
      ['소속 연맹', m.league],
      ['등록 연맹', m.regLeague],
      ['소속 단위대', m.unit],
      ['등록 단위대', m.regUnit],
      ['인가일', m.date],
      ['생일', m.birthday],
      if (m.genderVisible && m.gender.isNotEmpty) ['성별', m.gender],
      ['기념일', m.anniversary],
      ['훈련현황', m.trainingStatus],
      ['포상', m.awards],
      ['전문과정 이수', m.specialtyCourses],
      ['멘토', m.mentors.map((e) => '#$e').join(', ')],
      ['페런츠', m.parents.map((e) => '#$e').join(', ')],
      ['ATAS 인가번호', m.atasNo],
      ['핸드폰', m.phone],
      ['이메일', m.email],
      ['주소', m.address],
      ['활동', m.activity],
      ['메모', m.memo],
      [
        '개인정보 동의',
        m.privacyAgreed
            ? '동의함${m.privacyAgreedAt.isNotEmpty ? ' (${m.privacyAgreedAt})' : ''}'
            : '미동의',
      ],
    ].where((r) => r[1].trim().isNotEmpty).toList();

    return _section(
      title: '인가 정보',
      icon: Icons.badge,
      child: rows.isEmpty
          ? Text(
              '등록된 상세 정보가 없습니다. 편집 버튼을 눌러 입력하세요.',
              style: TextStyle(color: AppColors.textGray, fontSize: 13),
            )
          : Column(
              children: rows
                  .map(
                    (r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              r[0],
                              style: const TextStyle(
                                color: AppColors.textGray,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              r[1],
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
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
