import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 은하스카우트 명단 — 범스카우트와 **분리 관리**되는 별도 명단.
///
/// 관리자·마스터 전용. 항목: 인가번호(은하#N) · 성명 · 생년월일 · 소속 · 인가년월일.
class EunhaRosterScreen extends StatefulWidget {
  const EunhaRosterScreen({super.key});

  @override
  State<EunhaRosterScreen> createState() => _EunhaRosterScreenState();
}

class _EunhaRosterScreenState extends State<EunhaRosterScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AppState>().loadEunhaMembers(),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Member> _filtered(List<Member> ms) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return ms;
    return ms
        .where((m) =>
            m.searchText.contains(q) ||
            '은하#${m.number}'.contains(q) ||
            m.name.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final all = state.eunhaMembers;
    final list = _filtered(all);

    return Scaffold(
      appBar: TsakAppBar(
        title: const Text('은하스카우트 명단'),
        actions: const [AppHomeEmblem(size: 26)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      hintText: '이름 · 은하#번호 · 소속 검색',
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
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.groups, size: 16, color: AppColors.taegeukBlue),
                const SizedBox(width: 6),
                Text(
                  '전체 ${all.length}명' +
                      (_q.isEmpty ? '' : ' · 검색 ${list.length}명'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          Expanded(
            child: state.eunhaLoading && all.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const Center(
                        child: Text(
                          '은하스카우트 명단이 없습니다.',
                          style: TextStyle(color: AppColors.textGray),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _row(list[i], i),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _row(Member m, int idx) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.taegeukBlue.withValues(alpha: 0.12),
        child: Text(
          '${idx + 1}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.taegeukBlue,
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            '은하#${m.number}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.taegeukBlue,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            m.name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
      subtitle: Text(
        [
          if (m.unit.trim().isNotEmpty) m.unit.trim(),
          if (m.birthday.trim().isNotEmpty) '생 ${m.birthday.trim()}',
          if (m.date.trim().isNotEmpty) '인가 ${m.date.trim()}',
        ].join('  ·  '),
        style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
      ),
    );
  }
}
