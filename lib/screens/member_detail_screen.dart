import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/finance_transaction.dart';
import '../models/member.dart';
import '../services/app_state.dart';
import '../services/finance_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/member_avatar.dart';
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
                _depositSection(m),
                _feeTracker(m),
                _eventSection(m),
                _infoCard(m),
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
                    border: Border.all(
                      color: AppColors.tigerGold,
                      width: 2,
                    ),
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
                      const Icon(Icons.star,
                          color: AppColors.tigerGold, size: 20),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (m.league.isNotEmpty || m.unit.isNotEmpty)
                  Text(
                    [m.league, m.unit]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 우측 패널: 사진 (없으면 회색 스카우트 실루엣)
          MemberAvatar(
            name: m.name,
            photoPath: m.photoPath,
            league: m.league,
            number: m.number,
            showNumber: false,
            square: true,
            size: 104,
          ),
        ],
      ),
    );
  }

  Widget _quickActions(Member m) {
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: actions.map((a) => _qaButton(a)).toList(),
      ),
    );
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
                          horizontal: 10, vertical: 5),
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
                    horizontal: 10, vertical: 8),
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
                                color: AppColors.textDark),
                          ),
                          Text(
                            '${t.date}'
                            '${t.context.isNotEmpty ? ' · ${t.context}' : ''}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textGray),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_won(t.amount)}원',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppColors.scoutGreen),
                    ),
                    GestureDetector(
                      onTap: () => _addDeposit(m, existing: t),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.edit, size: 15,
                            color: AppColors.textGray),
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

  Widget _eventSection(Member m) {
    final events = m.eventAttend.keys.toList();
    return _section(
      title: '행사 참가 여부',
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
              children: [
                ...events.map((e) {
                  final attend = m.eventAttend[e] == true;
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: attend,
                    activeColor: AppColors.taegeukBlue,
                    title: Text(
                      e,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      attend ? '참가' : '불참',
                      style: TextStyle(fontSize: 11),
                    ),
                    onChanged: (v) {
                      final map = Map<String, bool>.from(m.eventAttend);
                      map[e] = v == true;
                      context.read<AppState>().save(
                        m.copyWith(eventAttend: map),
                      );
                    },
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

  Future<void> _addEvent(Member m) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('행사 추가'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 2026 정기총회 / 하계캠프'),
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
    }
  }

  Widget _infoCard(Member m) {
    final rows = <List<String>>[
      ['소속대', m.unit],
      ['인가일', m.date],
      ['생일', m.birthday],
      ['기념일', m.anniversary],
      ['훈련현황', m.trainingStatus],
      ['ATAS 인가번호', m.atasNo],
      ['핸드폰', m.phone],
      ['이메일', m.email],
      ['주소', m.address],
      ['활동', m.activity],
      ['메모', m.memo],
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

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
