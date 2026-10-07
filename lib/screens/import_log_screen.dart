import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';

/// 자료 가져오기(업데이트) 감사로그 + 복원 (마스터 전용).
///
/// 요구: "자료가 실수로 업데이트되면 안 되기 때문에 반드시 마스터에게 알림을 주고,
///       어떤 데이터가 업데이트 되었고, 누구의 계정으로 진행되었는지 로그를 남기고,
///       마스터는 복원 버튼을 통해 기존 항목으로 복원할 수 있도록."
class ImportLogScreen extends StatefulWidget {
  const ImportLogScreen({super.key});

  @override
  State<ImportLogScreen> createState() => _ImportLogScreenState();
}

class _ImportLogScreenState extends State<ImportLogScreen> {
  bool _busy = false;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await context.read<AppState>().nas.importLog();
      final list = ((r['items'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('자료 가져오기 로그 · 복원'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          const AppHomeEmblem(size: 26),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '아직 자료 가져오기(업데이트) 기록이 없습니다.\n'
                          '자료를 반영하면 누가·무엇을·언제 했는지 이곳에 기록됩니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textGray),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _items.length,
                      itemBuilder: (c, i) => _entryCard(_items[i]),
                    ),
          BusyOverlay(
            visible: _busy,
            title: '복원하는 중입니다',
            lines: const [
              '이전 항목으로 되돌리는 중...',
              '백업 후 안전하게 반영합니다...',
              '잠시만 기다려 주세요...',
            ],
          ),
        ],
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> e) {
    final changes = (e['changes'] as List?) ?? [];
    final restored = e['restored'] == true;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ExpansionTile(
        leading: Icon(
          restored ? Icons.restore : Icons.cloud_upload,
          color: restored ? AppColors.textGray : AppColors.taegeukBlue,
        ),
        title: Text(
          '${e['name'] ?? '자료'}',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${e['byLabel'] ?? '관리자'} · ${e['at'] ?? ''}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
            Text(
              '${e['summary'] ?? ''}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textDark),
            ),
            if (restored)
              const Text(
                '복원 완료',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.scoutGreen,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        trailing: _restoreBtn(e, changes, restored),
        children: [
          if (changes.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '변경 내역이 없습니다 (신규 등록만 있음)',
                style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
              ),
            )
          else
            for (final c in changes) _changeTile(c),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _restoreBtn(Map<String, dynamic> e, List changes, bool restored) {
    if (changes.isEmpty) {
      return const Icon(Icons.chevron_right, color: AppColors.textGray);
    }
    return TextButton.icon(
      onPressed: _busy || restored ? null : () => _confirmRestore(e, changes),
      icon: const Icon(Icons.restore, size: 16),
      label: Text('복원${restored ? '됨' : ''}', style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _changeTile(dynamic c) {
    final cc = (c as Map).cast<String, dynamic>();
    final diffs = (cc['diffs'] as List?) ?? [];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.tigerGold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.tigerGold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${cc['number'] ?? ''} ${cc['name'] ?? ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          for (final d in diffs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 76,
                    child: Text(
                      '${(d as Map)['label'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textDark,
                        ),
                        children: [
                          TextSpan(
                            text: '${d['old'] ?? ''}'.isEmpty
                                ? '(없음)'
                                : '${d['old'] ?? ''}',
                            style: const TextStyle(
                              color: AppColors.textGray,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const TextSpan(text: '  →  '),
                          TextSpan(
                            text: '${d['new'] ?? ''}',
                            style: const TextStyle(
                              color: AppColors.taegeukBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRestore(
    Map<String, dynamic> e,
    List changes,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('복원 확인'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${e['name'] ?? '자료'} (${e['at'] ?? ''}) 의 '
              '업데이트를 이전 항목으로 복원하시겠습니까?',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('· 복원 대상 : ${changes.length}건의 회원'),
            const SizedBox(height: 8),
            const Text(
              '현재 값은 백업 후, 변경된 항목만 이전 값으로 되돌립니다.\n'
              '이후 다른 변경이 있었다면 그 값은 유지됩니다.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('복원'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final state = context.read<AppState>();
    try {
      final r = await state.nas.importRestore('${e['id'] ?? ''}');
      if (r['ok'] == true) {
        await state.refreshFromNas();
        await _load();
        if (mounted) {
          _snack('${r['restored'] ?? 0}건을 이전 값으로 복원했습니다');
        }
      } else {
        _snack('복원 실패: ${r['error'] ?? '서버 오류'}');
      }
    } catch (err) {
      _snack('복원 실패: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
