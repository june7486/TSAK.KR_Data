import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/member_draft_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/tsak_app_bar.dart';

/// 임시저장(초안) 목록 화면 — 관리자·마스터 전용.
///
/// 회원정보 편집 중 자동으로 남겨진 임시저장 항목을 조회하고,
/// [불러오기] 로 편집 화면에 복원하거나 [삭제] 할 수 있다.
///  · 불러오기를 누르면 선택한 초안을 pop 으로 반환한다(호출 화면이 처리).
class MemberDraftsScreen extends StatefulWidget {
  const MemberDraftsScreen({super.key});

  @override
  State<MemberDraftsScreen> createState() => _MemberDraftsScreenState();
}

class _MemberDraftsScreenState extends State<MemberDraftsScreen> {
  List<MemberDraft> _drafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await MemberDraftStore.list();
    if (!mounted) return;
    setState(() {
      _drafts = list;
      _loading = false;
    });
  }

  Future<void> _delete(MemberDraft d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('임시저장 삭제'),
        content: Text('${d.displayName} 의 임시저장을 삭제할까요?'),
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
    await MemberDraftStore.delete(d.key);
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allowed = state.isApp || state.isMaster;
    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('임시저장 불러오기'),
      ),
      body: !allowed
          ? const Center(child: Text('관리자·마스터만 볼 수 있습니다'))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
          ? _empty()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _drafts.length,
                itemBuilder: (ctx, i) => _card(_drafts[i]),
              ),
            ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.bookmark_border, size: 54, color: AppColors.textGray),
          SizedBox(height: 12),
          Text('임시저장된 항목이 없습니다', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text(
            '회원정보를 수정하다 저장하지 않고 닫으면\n자동으로 이곳에 남습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _card(MemberDraft d) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.purple.withValues(alpha: 0.12),
                  child: const Icon(
                    Icons.person_outline,
                    size: 20,
                    color: AppColors.purple,
                  ),
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
                              d.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (d.isNew) ...[
                            const SizedBox(width: 6),
                            _tag('신규', AppColors.scoutGreen),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${d.number.isNotEmpty ? '인가번호 ${d.number} · ' : ''}'
                        '${d.savedAtLabel} 저장'
                        '${d.savedBy.isNotEmpty ? ' · ${d.savedBy}' : ''}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => Navigator.pop(context, d),
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('불러오기', style: TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.taegeukRed,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _delete(d),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('삭제', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
}
