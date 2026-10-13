import 'package:flutter/material.dart';
import 'marquee_text.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'fee_payment_request.dart';

/// 등록 · 자격 관리 섹션 — 개인 프로필(MemberDetailScreen)에 노출.
///
/// 요구사항:
///   · **자격(훈련현황)은 셀프 선택** — 본인이 직접 선택하면 즉시 반영된다.
///   · 평생회원 / 연회비 납부 / 행사 참가 등록은 개인 프로필에서 '등록요청' →
///     관리자·마스터가 승인하면 반영된다.
///   · (향후 추가되는 승인 항목도 통합 승인 창에서 처리)
class MemberRegistrationRequestSection extends StatefulWidget {
  const MemberRegistrationRequestSection({
    super.key,
    required this.member,
    required this.isSelf,
  });

  final Member member;
  final bool isSelf;

  @override
  State<MemberRegistrationRequestSection> createState() =>
      _MemberRegistrationRequestSectionState();
}

class _MemberRegistrationRequestSectionState
    extends State<MemberRegistrationRequestSection> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = false;

  /// 훈련자격(자격) 선택 항목 — 셀프 선택.
  static const List<String> _trainingOptions = [
    '중급',
    '상급',
    '커미셔너과정',
    '부교수',
    '교수',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (!state.repo.isNasMode) return;
    // 본인 또는 관리자·마스터(타인 프로필 열람)일 때 내역을 불러온다.
    final canView = widget.isSelf || state.isApp || state.isMaster;
    if (!canView) return;
    setState(() => _loading = true);
    final list = await state.fetchMyMemberRequests(ident: _ident);
    if (!mounted) return;
    setState(() {
      _requests = list;
      _loading = false;
    });
  }

  String get _ident => widget.member.number.isNotEmpty
      ? widget.member.number
      : widget.member.phone;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final state = context.watch<AppState>();
    final canRequest = widget.isSelf;
    // 내역(등록요청 이력)을 볼 수 있는 대상:
    //  · 요구 #11: 관리자·마스터는 모든 회원의 등록요청 내역을 볼 수 있다(삭제 가능).
    //  · 본인은 자기 내역을 볼 수 있다.
    final canViewHistory = state.isApp || state.isMaster || widget.isSelf;

    // 순서(요구 #5): 등록요청 창 → 자격(훈련현황) 페이지
    return Column(
      children: [
        // 1) 등록요청 — 평생회비 / 연간회비 (요구 #6: 행사참가 요청 삭제)
        //  본인은 요청 제출 가능, 관리자·마스터는 내역 열람/삭제 가능.
        if (canViewHistory) _requestSection(m, canSubmit: canRequest),
        // 2) 자격(훈련현황) — 셀프 선택(즉시 반영)
        _trainingSection(m),
      ],
    );
  }

  // ---------------- 1) 자격(훈련현황) 셀프 선택 ----------------
  Widget _trainingSection(Member m) {
    final state = context.watch<AppState>();
    final selected = m.trainingStatus
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    // 본인이거나 관리자·마스터만 편집 가능
    final editable = widget.isSelf || state.isApp || state.isMaster;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.school, color: AppColors.purple, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '자격 (훈련현황)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '셀프 선택',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.purple,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '이수한 훈련 과정을 직접 선택하세요 (복수 선택 가능 · 즉시 반영)',
              style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _trainingOptions)
                  FilterChip(
                    label: Text(t),
                    selected: selected.contains(t),
                    showCheckmark: editable,
                    checkmarkColor: Colors.white,
                    selectedColor: AppColors.purple,
                    labelStyle: TextStyle(
                      color: selected.contains(t)
                          ? Colors.white
                          : AppColors.textDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    onSelected: editable
                        ? (on) {
                            final next = Set<String>.from(selected);
                            if (on) {
                              next.add(t);
                            } else {
                              next.remove(t);
                            }
                            final joined = _trainingOptions
                                .where((o) => next.contains(o))
                                .join(', ');
                            context.read<AppState>().save(
                              m.copyWith(trainingStatus: joined),
                            );
                          }
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 2) 등록요청 (평생회비·연간회비) ----------------
  Widget _requestSection(Member m, {required bool canSubmit}) {
    final state = context.watch<AppState>();
    final isAdmin = state.isApp || state.isMaster;
    // 우측 휴지통(삭제)은 마스터 전용 — 개인 계정으로 로그인해 열람한 경우에도
    //  마스터만 내역을 삭제할 수 있도록 한다(요구).
    final canDelete = state.isMaster;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.app_registration,
                  color: AppColors.purple,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '등록요청 (평생회비·연간회비)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                // (요구) 본인·관리자·마스터 모두 요청 제출 가능.
                //  · 회원은 스스로 평생회원으로 '지정'할 수 없다 → '요청'만 가능.
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _openRequestSheet(),
                  icon: const Icon(Icons.edit_document, size: 16),
                  label: const Text(
                    '등록요청',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _statusRow(m),
            const SizedBox(height: 6),
            Text(
              canSubmit
                  ? '* 등록요청을 제출하면 관리자·마스터가 확인 후 승인합니다. '
                        '승인 시 연간회비 납부 이력과 연동됩니다.'
                  : (canDelete
                        ? '* 관리자·마스터는 아래 내역에서 요청을 확인할 수 있고, '
                              '마스터는 우측 휴지통으로 삭제할 수 있습니다.'
                        : '* 등록요청 내역은 관리자·마스터가 확인하며, '
                              '삭제는 마스터만 할 수 있습니다.'),
              style: const TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_requests.isNotEmpty) ...[
              const SizedBox(height: 10),
              _requestHistory(m, isAdmin: isAdmin, canDelete: canDelete),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusRow(Member m) {
    final latestPaid = _latestPaidYear(m);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _statusChip(
          label: '평생회원',
          value: m.lifetimeMember
              ? (m.lifetimeSince.isNotEmpty ? '등록 (${m.lifetimeSince})' : '등록됨')
              : '미등록',
          on: m.lifetimeMember,
          color: AppColors.lifetimeGold,
        ),
        _statusChip(
          label: '연회비',
          value: latestPaid == null ? '납부내역 없음' : '$latestPaid 납부',
          on: latestPaid != null,
          color: AppColors.scoutGreen,
        ),
      ],
    );
  }

  String? _latestPaidYear(Member m) {
    final years = m.paidYears;
    if (years.isEmpty) return null;
    years.sort();
    return years.last;
  }

  Widget _statusChip({
    required String label,
    required String value,
    required bool on,
    required Color color,
  }) {
    final c = on ? color : Colors.grey.shade500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            on ? Icons.check_circle : Icons.remove_circle_outline,
            size: 15,
            color: c,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestHistory(
    Member m, {
    required bool isAdmin,
    required bool canDelete,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isAdmin ? Icons.history : Icons.receipt_long,
              size: 15,
              color: AppColors.purple,
            ),
            const SizedBox(width: 5),
            Text(
              isAdmin ? '${m.name} 님의 등록요청 내역' : '내 등록요청 내역',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ..._requests.take(12).map((r) {
          final t = '${r['type'] ?? ''}';
          final label = MemberRequestLabels.label(t);
          final icon = MemberRequestLabels.icon(t);
          final status = '${r['status'] ?? ''}';
          final (txt, col) = switch (status) {
            'approved' => ('승인됨', AppColors.scoutGreen),
            'rejected' => ('반려', AppColors.taegeukRed),
            _ => ('승인 대기', AppColors.tigerGold),
          };
          final detail = [
            if ('${r['year'] ?? ''}'.isNotEmpty) '${r['year']}년',
            if ('${r['event'] ?? ''}'.isNotEmpty) '${r['event']}',
            if ('${r['date'] ?? ''}'.isNotEmpty) '${r['date']}',
          ].join(' · ');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(icon, size: 13, color: AppColors.textGray),
                const SizedBox(width: 5),
                Expanded(
                  child: MarqueeText(
                    '$label${detail.isNotEmpty ? ' ($detail)' : ''}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    txt,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: col,
                    ),
                  ),
                ),
                // 마스터 전용 — 우측 휴지통으로 등록요청 내역을 삭제한다.
                //  개인 계정(개인 로그인)으로 열람한 경우에도 마스터만 삭제 가능.
                if (canDelete)
                  IconButton(
                    tooltip: '내역 삭제 (마스터)',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 17,
                      color: AppColors.taegeukRed,
                    ),
                    onPressed: () => _deleteRequest(r),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// 등록요청 내역 삭제(관리자·마스터) — 목록에서 제거.
  Future<void> _deleteRequest(Map<String, dynamic> r) async {
    final id = '${r['id'] ?? ''}';
    if (id.isEmpty) return;
    final label = MemberRequestLabels.label('${r['type'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('등록요청 내역 삭제'),
        content: Text('“$label” 요청 내역을 삭제할까요?\n이 작업은 되돌릴 수 없습니다.'),
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
    if (ok != true || !mounted) return;
    final done = await context.read<AppState>().nas.memberRequestDelete(id);
    if (!mounted) return;
    if (done) {
      setState(() => _requests.removeWhere((x) => '${x['id']}' == id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('내역을 삭제했습니다')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('삭제에 실패했습니다')));
    }
  }

  // ---------------- 등록요청 제출 — 항목 선택 후 납부 정보 입력 ----------------
  /// 회원은 스스로 평생회원으로 지정할 수 없다 → '요청'만 가능.
  ///  · '평생회원 등록요청' / '연회비 납부 요청' 을 고르면 납부 요청 시트를 띄운다.
  Future<void> _openRequestSheet() async {
    final m = widget.member;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.app_registration, color: AppColors.purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '등록요청 — ${m.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text(
              '요청할 항목을 선택하세요. 관리자·마스터 승인 후 반영됩니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            _choiceTile(
              ctx,
              'lifetime',
              '평생회원 등록요청',
              '평생회비 납부 여부 · 납부자 이름',
              Icons.star,
              AppColors.lifetimeGold,
            ),
            const SizedBox(height: 8),
            _choiceTile(
              ctx,
              'fee',
              '연회비 납부 요청',
              '연도 · 납부완료/납부예정 · 납부자 이름',
              Icons.card_membership,
              AppColors.scoutGreen,
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final ok = await showFeePaymentRequestSheet(
      context,
      member: m,
      type: choice,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '등록요청을 제출했습니다. 관리자 승인을 기다려 주세요.' : '요청이 취소되었습니다.',
        ),
      ),
    );
    if (ok) _load();
  }

  Widget _choiceTile(
    BuildContext ctx,
    String value,
    String title,
    String sub,
    IconData icon,
    Color color,
  ) {
    return Material(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(ctx, value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textGray),
            ],
          ),
        ),
      ),
    );
  }


}
/// 등록요청 유형 라벨/아이콘 — 위젯·화면 공용.
class MemberRequestLabels {
  static String label(String t) => switch (t) {
    'lifetime' => '평생회원 등록',
    'fee' => '연회비 납부',
    'event' => '행사 참가 등록',
    'regular' => '비인가회원 등록',
    'qualification' => '자격 지정',
    'donation' => '후원금 등록',
    'supply' => '후원물품 등록',
    _ => t,
  };

  static IconData icon(String t) => switch (t) {
    'lifetime' => Icons.star,
    'fee' => Icons.card_membership,
    'event' => Icons.event_available,
    'regular' => Icons.person_add,
    'qualification' => Icons.workspace_premium,
    'donation' => Icons.volunteer_activism,
    'supply' => Icons.card_giftcard,
    _ => Icons.rule,
  };

  static Color color(String t) => switch (t) {
    'lifetime' => AppColors.lifetimeGold,
    'fee' => AppColors.scoutGreen,
    'event' => AppColors.taegeukBlue,
    'regular' => AppColors.purple,
    'qualification' => AppColors.purple,
    'donation' => AppColors.taegeukRed,
    'supply' => AppColors.taegeukBlue,
    _ => AppColors.textGray,
  };
}

