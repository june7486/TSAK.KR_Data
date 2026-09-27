import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/member_avatar.dart';
import 'member_detail_screen.dart';

/// 일반회원 승인 관리 — (관리자·마스터 전용)
///
/// 일반회원(비인가자)은 관리자/마스터의 승인을 받아야 정상 회원으로 인정된다.
/// 승인 여부가 권한을 제한하지는 않지만, 비정상적인 ID(스팸·오입력·중복)는
/// 삭제할 수 있다.
///
/// 분류 상태:
///   · pending  — 미승인(승인 요청됨)
///   · held     — 보류
///   · approved — 승인됨
///
/// 우측 버튼: 승인 / 보류 / 미승인 / 삭제
class ApprovalScreen extends StatefulWidget {
  const ApprovalScreen({super.key});

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  final _search = TextEditingController();
  String _q = '';
  bool _busy = false;
  bool _loading = true;

  /// 필터: 'all' | 'pending' | 'held' | 'approved'
  String _filter = 'pending';

  /// 선택된 회원 id 집합
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    setState(() => _loading = true);
    await state.fetchApprovalPending();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  List<Member> _source(AppState state) {
    final all = state.regularMembers;
    switch (_filter) {
      case 'pending':
        return all.where((m) => m.approvalStatus == 'pending').toList();
      case 'held':
        return all.where((m) => m.approvalStatus == 'held').toList();
      case 'approved':
        return all
            .where((m) => m.approvalStatus == 'approved' || m.approvalStatus == '')
            .toList();
      default:
        return all.toList();
    }
  }

  List<Member> _filtered(AppState state) {
    final list = _source(state);
    final t = _q.trim().toLowerCase();
    if (t.isEmpty) return list;
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    return list.where((m) {
      if (m.name.toLowerCase().contains(t)) return true;
      if (m.loginId.toLowerCase().contains(t)) return true;
      if (digits.isNotEmpty &&
          m.phone.replaceAll(RegExp(r'[^0-9]'), '').contains(digits)) {
        return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!(state.isApp || state.isMaster)) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(label: '뒤로'),
          leadingWidth: 84,
          title: const Text('일반회원 승인 관리'),
        ),
        body: const Center(child: Text('관리자 권한이 필요합니다')),
      );
    }
    final list = _filtered(state);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('일반회원 승인 관리'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const AppHomeEmblem(size: 24),
        ],
      ),
      body: Column(
        children: [
          _summary(state),
          _filterBar(),
          _searchBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? _empty()
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _card(state, list[i]),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty ? null : _bulkBar(state),
    );
  }

  Widget _summary(AppState state) {
    final all = state.regularMembers;
    int c(String s) => all.where((m) => m.approvalStatus == s).length;
    final pending = c('pending');
    final held = c('held');
    final approved =
        all.where((m) => m.approvalStatus == 'approved' || m.approvalStatus == '')
            .length;
    Widget stat(String label, int value, Color color, IconData icon,
            String key) =>
        Expanded(
          child: InkWell(
            onTap: () => setState(() {
              _filter = key;
              _selected.clear();
            }),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: _filter == key
                    ? color.withValues(alpha: 0.12)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _filter == key
                      ? color
                      : color.withValues(alpha: 0.25),
                  width: _filter == key ? 1.6 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(height: 4),
                  Text('$value',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: color)),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textGray),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Row(
        children: [
          stat('미승인', pending, AppColors.tigerGold, Icons.hourglass_top,
              'pending'),
          const SizedBox(width: 8),
          stat('보류', held, AppColors.taegeukRed, Icons.pause_circle_outline,
              'held'),
          const SizedBox(width: 8),
          stat('승인됨', approved, AppColors.scoutGreen, Icons.verified, 'approved'),
          const SizedBox(width: 8),
          stat('전체', all.length, AppColors.purple, Icons.groups, 'all'),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selected.isEmpty
                  ? '항목을 길게 눌러 선택할 수 있습니다'
                  : '${_selected.length}명 선택됨',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _selected.isEmpty
                    ? AppColors.textGray
                    : AppColors.taegeukBlue,
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _selected.clear()),
              icon: const Icon(Icons.deselect, size: 16),
              label: const Text('선택 해제', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: TextField(
        controller: _search,
        onChanged: (v) => setState(() => _q = v),
        decoration: InputDecoration(
          hintText: '이름 · 전화번호 검색',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _q.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _search.clear();
                    setState(() => _q = '');
                  },
                ),
          isDense: true,
        ),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return AppColors.tigerGold;
      case 'held':
        return AppColors.taegeukRed;
      case 'approved':
        return AppColors.scoutGreen;
      default:
        return AppColors.textGray;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return '미승인';
      case 'held':
        return '보류';
      case 'approved':
        return '승인';
      default:
        return '일반';
    }
  }

  Widget _card(AppState state, Member m) {
    final sel = _selected.contains(m.id);
    final sc = _statusColor(m.approvalStatus);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: sel
            ? const BorderSide(color: AppColors.taegeukBlue, width: 1.8)
            : BorderSide(color: sc.withValues(alpha: 0.25), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () => setState(() {
          if (sel) {
            _selected.remove(m.id);
          } else {
            _selected.add(m.id);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            children: [
              Checkbox(
                value: sel,
                onChanged: (_) => setState(() {
                  if (sel) {
                    _selected.remove(m.id);
                  } else {
                    _selected.add(m.id);
                  }
                }),
              ),
              MemberAvatar(
                name: m.name,
                photoPath: m.photoPath,
                league: m.league,
                size: 30,
                number: '',
                showNumber: false,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            m.name.isEmpty ? '(이름없음)' : m.name,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: sc.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _statusLabel(m.approvalStatus),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: sc,
                            ),
                          ),
                        ),
                        if (!m.privacyAgreed) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.warning_amber_rounded,
                              size: 15, color: AppColors.tigerGold),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.phone,
                            size: 13, color: AppColors.scoutGreen),
                        const SizedBox(width: 3),
                        Text(
                          m.phone.isEmpty ? m.loginId : m.phone,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.textDark),
                        ),
                        if (m.privacyAgreedAt.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '가입 ${m.privacyAgreedAt.split(' ').first}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textGray),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '상세',
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MemberDetailScreen(memberId: m.id),
                  ),
                ).then((_) => _refresh()),
                icon: const Icon(Icons.info_outline,
                    color: AppColors.purple, size: 20),
              ),
              _actionColumn(state, m),
            ],
          ),
        ),
      ),
    );
  }

  /// 우측 분류 액션 버튼: 승인 / 보류 / 미승인 / 삭제
  Widget _actionColumn(AppState state, Member m) {
    Widget b(
      String label,
      IconData icon,
      Color color,
      String action,
    ) {
      final active = (action == 'approve' && m.approvalStatus == 'approved') ||
          (action == 'hold' && m.approvalStatus == 'held') ||
          (action == 'pending' && m.approvalStatus == 'pending');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: SizedBox(
          width: 62,
          height: 24,
          child: OutlinedButton.icon(
            onPressed: _busy || active ? null : () => _apply(state, action, m),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: BorderSide(
                  color: active
                      ? color.withValues(alpha: 0.35)
                      : color.withValues(alpha: 0.7)),
              backgroundColor:
                  active ? color.withValues(alpha: 0.10) : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7)),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(icon,
                size: 12,
                color: active ? color.withValues(alpha: 0.45) : color),
            label: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: active ? color.withValues(alpha: 0.45) : color,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        b('승인', Icons.check_circle_outline, AppColors.scoutGreen, 'approve'),
        b('보류', Icons.pause_circle_outline, AppColors.tigerGold, 'hold'),
        b('미승인', Icons.hourglass_top, AppColors.textGray, 'pending'),
        b('삭제', Icons.delete_outline, AppColors.taegeukRed, 'delete'),
      ],
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_outlined,
              size: 56, color: AppColors.textGray.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          const Text('해당 상태의 회원이 없습니다',
              style: TextStyle(color: AppColors.textGray, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _bulkBar(AppState state) {
    final n = _selected.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
              top: BorderSide(color: AppColors.purple.withValues(alpha: 0.15))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('선택 $n명 일괄 처리',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.scoutGreen,
                        minimumSize: const Size(0, 40)),
                    onPressed: _busy ? null : () => _bulk(state, 'approve'),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('승인',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.tigerGold,
                        minimumSize: const Size(0, 40)),
                    onPressed: _busy ? null : () => _bulk(state, 'hold'),
                    icon: const Icon(Icons.pause_circle_outline, size: 16),
                    label: const Text('보류',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.taegeukRed,
                        minimumSize: const Size(0, 40)),
                    onPressed: _busy ? null : () => _bulk(state, 'delete'),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('삭제',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apply(AppState state, String action, Member m) async {
    if (action == 'delete') {
      final ok = await _confirm(
        '삭제',
        '${m.name.isEmpty ? '(이름없음)' : m.name} (${m.phone.isEmpty ? m.loginId : m.phone}) 회원을 삭제할까요?\n\n이 작업은 되돌릴 수 없습니다.',
        danger: true,
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    final label = {
      'approve': '승인',
      'hold': '보류',
      'pending': '미승인',
      'delete': '삭제',
    }[action];
    final n = await state.setApproval(action, [m.id]);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(n > 0 ? '$label 완료' : '$label 실패 — 잠시 후 다시 시도하세요');
  }

  Future<void> _bulk(AppState state, String action) async {
    final ids = _selected.toList();
    final label = {
      'approve': '승인',
      'hold': '보류',
      'pending': '미승인',
      'delete': '삭제',
    }[action];
    final ok = await _confirm(
      '$label 일괄 처리',
      '선택한 ${ids.length}명을 $label 처리할까요?'
      '${action == 'delete' ? '\n\n삭제는 되돌릴 수 없습니다.' : ''}',
      danger: action == 'delete',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final n = await state.setApproval(action, ids);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    _snack('$label $n명 완료');
  }

  Future<bool?> _confirm(String title, String body, {bool danger = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: TextStyle(
                color: danger ? AppColors.taegeukRed : AppColors.textDark)),
        content: Text(body, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  danger ? AppColors.taegeukRed : AppColors.taegeukBlue,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(danger ? '삭제' : '확인'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}
