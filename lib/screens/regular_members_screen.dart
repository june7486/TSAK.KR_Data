import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/member_avatar.dart';
import 'member_detail_screen.dart';

/// 일반회원(비인가자) 관리 — 목록/검색/인가자 승격. (관리자·마스터 전용)
///
/// 일반회원은 인가번호 없이 전화번호로 가입한 참가자다. 잘못 등록되었거나
/// 정식 인가 자격을 얻으면 여기서 바로 [인가자로 승격] 할 수 있다.
class RegularMembersScreen extends StatefulWidget {
  const RegularMembersScreen({super.key});

  @override
  State<RegularMembersScreen> createState() => _RegularMembersScreenState();
}

class _RegularMembersScreenState extends State<RegularMembersScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Member> _filtered(AppState state) {
    final all = state.regularMembers;
    final t = _q.trim().toLowerCase();
    if (t.isEmpty) return all;
    return all
        .where(
          (m) =>
              m.name.toLowerCase().contains(t) ||
              m.phone
                  .replaceAll(RegExp(r'[^0-9]'), '')
                  .contains(t.replaceAll(RegExp(r'[^0-9]'), '')) ||
              m.loginId.toLowerCase().contains(t),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!(state.isApp || state.isMaster)) {
      return Scaffold(
        appBar: TsakAppBar(
          leading: const AppBackButton(label: '뒤로'),
          leadingWidth: 84,
          title: const Text('일반회원 관리'),
        ),
        body: const Center(child: Text('관리자 권한이 필요합니다')),
      );
    }
    final list = _filtered(state);
    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: Text('일반회원 관리 · ${state.regularCount}명'),
        actions: const [AppHomeEmblem(size: 24)],
      ),
      body: Column(
        children: [
          _summary(state),
          _searchBar(),
          Expanded(
            child: list.isEmpty
                ? _empty(state.regularCount == 0)
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _card(state, list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summary(AppState state) {
    Widget stat(String label, int value, Color color, IconData icon) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 4),
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Row(
        children: [
          stat('전체 회원', state.total, AppColors.purple, Icons.groups),
          const SizedBox(width: 8),
          stat(
            '인가자',
            state.credentialCount,
            AppColors.taegeukBlue,
            Icons.verified_user,
          ),
          const SizedBox(width: 8),
          stat(
            '일반회원',
            state.regularCount,
            AppColors.textGray,
            Icons.person_outline,
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
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

  Widget _card(AppState state, Member m) {
    void openDetail() => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberDetailScreen(memberId: m.id)),
    );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: openDetail,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
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
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.textGray.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '일반회원',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textGray,
                            ),
                          ),
                        ),
                        if (!m.privacyAgreed) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 15,
                            color: AppColors.tigerGold,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.phone,
                          size: 13,
                          color: AppColors.scoutGreen,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          m.phone.isEmpty ? m.loginId : m.phone,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textDark,
                          ),
                        ),
                        if (m.privacyAgreedAt.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '가입 ${m.privacyAgreedAt.split(' ').first}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textGray,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '상세',
                onPressed: openDetail,
                icon: const Icon(Icons.info_outline, color: AppColors.purple),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.taegeukBlue,
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _promote(state, m),
                child: const Text(
                  '승격',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(bool noneAtAll) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            noneAtAll ? Icons.person_off_outlined : Icons.search_off,
            size: 56,
            color: AppColors.textGray.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 10),
          Text(
            noneAtAll ? '등록된 일반회원이 없습니다' : '검색 결과가 없습니다',
            style: const TextStyle(color: AppColors.textGray, fontSize: 14),
          ),
          if (noneAtAll) ...[
            const SizedBox(height: 6),
            const Text(
              '범스카우트 인가자 생성은 관리자 이상만 가능하며,\n'
              '신규 일반 아이디는 서포터즈 권한으로 등록됩니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textGray, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _promote(AppState state, Member m) async {
    final noCtrl = TextEditingController(text: '');
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
    final updated = await state.promoteToCredential(
      m,
      number: noCtrl.text.trim(),
      league: leagueCtrl.text.trim(),
      unit: unitCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated == null
              ? '승격 실패: 인가번호가 비었거나 중복됩니다'
              : '인가자로 승격했습니다 (#${updated.number})',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
