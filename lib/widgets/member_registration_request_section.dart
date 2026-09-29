import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// 등록요청 섹션 — 개인 프로필(MemberDetailScreen)에 노출.
///
/// 요구사항:
///   · 평생회원 / 연회비 납부 / 자격 지정 여부는 **개인 프로필 창**에서
///     '등록요청' 버튼으로 요청하고, **관리자·마스터가 승인**하면 반영된다.
///
/// 동작:
///   · [isSelf] 가 true(본인 프로필)이면 '등록요청' 버튼을 노출한다.
///   · 본인의 진행중/처리된 요청 내역을 함께 보여준다(서버 조회).
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

  /// 등록요청 가능한 유형 정의 (value, 라벨, 아이콘, 색).
  static const _types = <_ReqType>[
    _ReqType('lifetime', '평생회원 등록', Icons.star, AppColors.lifetimeGold),
    _ReqType('fee', '연회비 납부', Icons.card_membership, AppColors.scoutGreen),
    _ReqType('qualification', '자격 지정', Icons.workspace_premium,
        AppColors.purple),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!widget.isSelf) return;
    final state = context.read<AppState>();
    if (!state.repo.isNasMode) return;
    setState(() => _loading = true);
    final list = await state.fetchMyMemberRequests(ident: _ident);
    if (!mounted) return;
    setState(() {
      _requests = list;
      _loading = false;
    });
  }

  String get _ident =>
      widget.member.number.isNotEmpty ? widget.member.number : widget.member.phone;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    // 본인도 관리자/마스터도 아니면 요청 상태가 의미 없으므로 최소 노출.
    final canRequest = widget.isSelf;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.app_registration,
                    color: AppColors.purple, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '평생회원 · 연회비 · 자격 지정',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                if (canRequest)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _openRequestSheet(),
                    icon: const Icon(Icons.edit_document, size: 16),
                    label: const Text('등록요청',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _statusRow(m),
            if (canRequest) ...[
              const SizedBox(height: 6),
              const Text(
                '* 등록요청을 제출하면 관리자·마스터가 확인 후 승인합니다. '
                '승인되면 아래 상태에 반영됩니다.',
                style: TextStyle(fontSize: 11, color: AppColors.textGray),
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
                _requestHistory(),
              ],
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
        _statusChip(
          label: '자격 지정',
          value: m.qualificationApproved ? '지정됨' : '미지정',
          on: m.qualificationApproved,
          color: AppColors.purple,
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
          Icon(on ? Icons.check_circle : Icons.remove_circle_outline,
              size: 15, color: c),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }

  Widget _requestHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('내 등록요청 내역',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ..._requests.take(6).map((r) {
          final t = '${r['type'] ?? ''}';
          final label = _types
              .firstWhere((e) => e.value == t,
                  orElse: () => _ReqType(t, t, Icons.info, AppColors.textGray))
              .label;
          final status = '${r['status'] ?? ''}';
          final (txt, col) = switch (status) {
            'approved' => ('승인됨', AppColors.scoutGreen),
            'rejected' => ('반려', AppColors.taegeukRed),
            _ => ('승인 대기', AppColors.tigerGold),
          };
          final detail = [
            if ('${r['year'] ?? ''}'.isNotEmpty) '${r['year']}년',
            if ('${r['date'] ?? ''}'.isNotEmpty) '${r['date']}',
          ].join(' · ');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$label${detail.isNotEmpty ? ' ($detail)' : ''}',
                    style: const TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(txt,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, color: col)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ---------------- 등록요청 제출 시트 ----------------
  Future<void> _openRequestSheet() async {
    final m = widget.member;
    String type = 'lifetime';
    String year = '${DateTime.now().year}';
    final dateCtrl = TextEditingController(text: _today());
    final noteCtrl = TextEditingController();

    final submit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.app_registration, color: AppColors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('등록요청 — ${m.name}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Text(
                '요청할 항목을 선택하세요. 관리자·마스터 승인 후 반영됩니다.',
                style: TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
              const SizedBox(height: 12),
              // 유형 선택
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _types.map((t) {
                  final sel = type == t.value;
                  return ChoiceChip(
                    selected: sel,
                    onSelected: (_) => setSheet(() => type = t.value),
                    avatar: Icon(t.icon,
                        size: 16,
                        color: sel ? Colors.white : t.color),
                    label: Text(t.label),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : AppColors.textDark,
                    ),
                    selectedColor: t.color,
                    backgroundColor: t.color.withValues(alpha: 0.10),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              if (type == 'fee')
                DropdownButtonFormField<String>(
                  initialValue: year,
                  decoration: const InputDecoration(
                    labelText: '납부 연도',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['2024', '2025', '2026', '2027']
                      .map((y) =>
                          DropdownMenuItem(value: y, child: Text('$y년')))
                      .toList(),
                  onChanged: (v) => setSheet(() => year = v ?? year),
                ),
              if (type == 'lifetime')
                TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(
                    labelText: '평생회비 납부일자 (선택)',
                    hintText: '예: 2022-04-13',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (type == 'qualification')
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '자격 지정 사유·요청 내용',
                    hintText: '예: 지도자 자격 과정 이수, 멘토 지정 요청 등',
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('등록요청 제출',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (submit != true || !mounted) return;
    final state = context.read<AppState>();
    final err = await state.submitMemberRequest(
      type: type,
      year: type == 'fee' ? year : '',
      date: type == 'lifetime' ? dateCtrl.text.trim() : '',
      note: type == 'qualification' ? noteCtrl.text.trim() : '',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err == null ? '등록요청을 제출했습니다. 관리자 승인을 기다려 주세요.' : '요청 실패: $err'),
      ),
    );
    if (err == null) _load();
  }

  String _today() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }
}

class _ReqType {
  const _ReqType(this.value, this.label, this.icon, this.color);
  final String value;
  final String label;
  final IconData icon;
  final Color color;
}
