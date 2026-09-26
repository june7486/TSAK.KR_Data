import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';

/// 마스터 전용 — 앱 관리
///  1) 앱 접근 비밀번호 변경
///  2) 개인 비밀번호 초기화 / 변경
///  3) 앱 서버 일시 정지
///  4) 복구 (최종 백업 버전/일시로 되돌리기)
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadAdmin();
      context.read<AppState>().refreshServerPaused();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return const Scaffold(body: Center(child: Text('마스터만 접근할 수 있습니다')));
    }
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('앱 관리 (마스터)'),
        actions: const [AppHomeEmblem(size: 26)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _serverPauseCard(state),
          const SizedBox(height: 12),
          _appPasswordCard(state),
          const SizedBox(height: 12),
          _personalPasswordCard(state),
          const SizedBox(height: 12),
          _restoreCard(state),
        ],
      ),
    );
  }

  Widget _title(String t, IconData icon, Color color) => Row(
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Text(
        t,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ],
  );

  // ---- 3) 앱 서버 일시 정지 ----
  Widget _serverPauseCard(AppState state) {
    final paused = state.serverPaused;
    return Card(
      color: paused ? AppColors.taegeukRed.withValues(alpha: 0.06) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(
              '앱 서버 일시 정지',
              Icons.pause_circle_outline,
              paused ? AppColors.taegeukRed : AppColors.purple,
            ),
            const SizedBox(height: 8),
            Text(
              paused
                  ? '현재 서버가 일시 정지 상태입니다. 모든 사용자 접속이 차단됩니다.'
                  : '정지 시 모든 사용자가 웹앱에 접속할 수 없습니다 (마스터 복구 가능).',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: paused
                          ? AppColors.scoutGreen
                          : AppColors.taegeukRed,
                    ),
                    onPressed: _busy
                        ? null
                        : () => _togglePause(state, !paused),
                    icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                    label: Text(paused ? '서버 재개' : '서버 일시 정지'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePause(AppState state, bool pause) async {
    final master = await _askMaster('서버 ${pause ? '일시 정지' : '재개'}');
    if (master == null) return;
    setState(() => _busy = true);
    final ok = await state.setServerPaused(master, pause);
    if (mounted) setState(() => _busy = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '적용되었습니다' : '실패 (마스터 비밀번호 확인)')),
      );
    }
  }

  // ---- 1) 앱 접근 비밀번호 변경 ----
  Widget _appPasswordCard(AppState state) {
    final cur = '${state.adminState['appPassword'] ?? 'Tsak1988!!'}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('앱 접근 비밀번호', Icons.password, AppColors.taegeukBlue),
            const SizedBox(height: 8),
            Text(
              '현재: $cur',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _changeAppPassword(state),
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('앱 비밀번호 변경'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeAppPassword(AppState state) async {
    final newCtrl = TextEditingController();
    final masterCtrl = TextEditingController();
    final isPM = state.isPermanentMaster;
    if (isPM) masterCtrl.text = state.masterToken();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('앱 접근 비밀번호 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newCtrl,
              decoration: const InputDecoration(labelText: '새 앱 비밀번호'),
            ),
            if (!isPM) ...[
              const SizedBox(height: 8),
              TextField(
                controller: masterCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '마스터 비밀번호 확인'),
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Text('영구 마스터는 별도 확인 없이 변경됩니다.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textGray)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final err = await state.changeAppPassword(
      masterCtrl.text,
      newCtrl.text.trim(),
    );
    await state.loadAdmin();
    if (mounted) setState(() => _busy = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err == null ? '앱 비밀번호를 변경했습니다' : '실패: $err')),
      );
    }
  }

  // ---- 2) 개인 비밀번호 초기화 / 변경 ----
  Widget _personalPasswordCard(AppState state) {
    final pws = (state.adminState['personalPasswords'] as Map?) ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(
              '개인 비밀번호 초기화 / 재설정',
              Icons.person_outline,
              AppColors.scoutGreen,
            ),
            const SizedBox(height: 8),
            const Text(
              '특정 인가자를 선택해 비밀번호를 초기화(기본값)하거나 재설정할 수 있습니다.\n'
              '기본값은 「인가번호!@@」 입니다.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textGray),
            ),
            if (pws.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '변경 지정된 번호: ${pws.keys.join(', ')}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.purple),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _managePersonal(state, reset: false),
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('비번 재설정'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _managePersonal(state, reset: true),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('초기화'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _managePersonal(AppState state, {required bool reset}) async {
    // 인가번호 입력 대신 "인가자 선택"으로 지정 (오타 방지)
    final member = await _pickMember(state);
    if (member == null) return;
    await _applyPersonalPassword(state, member, reset: reset);
  }

  /// 특정 인가자 선택 — 번호/이름 검색 팝업
  Future<Member?> _pickMember(AppState state) async {
    final all = state.repo.allUnscoped();
    final ctrl = TextEditingController();
    return showDialog<Member>(
      context: context,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final list = query.trim().isEmpty
                ? all
                : all.where((m) {
                    final q = query.trim().toLowerCase();
                    return m.number.contains(q) ||
                        m.name.toLowerCase().contains(q) ||
                        m.unit.toLowerCase().contains(q);
                  }).toList();
            return AlertDialog(
              title: const Text('인가자 선택'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      onChanged: (v) => setLocal(() => query = v),
                      decoration: const InputDecoration(
                        hintText: '인가번호 또는 이름으로 검색',
                        prefixIcon: Icon(Icons.search, size: 18),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(child: Text('검색 결과가 없습니다'))
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (c, i) {
                                final m = list[i];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppColors.purple
                                        .withValues(alpha: 0.12),
                                    child: Text(
                                      m.number,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.purple,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    '${m.name.isEmpty ? '(이름없음)' : m.name}'
                                    ' · #${m.number}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    m.unit,
                                    style: const TextStyle(fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => Navigator.pop(ctx, m),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 선택한 인가자에 대해 마스터가 초기화(기본값) 또는 재설정(지정값)
  Future<void> _applyPersonalPassword(
    AppState state,
    Member member, {
    required bool reset,
  }) async {
    final valCtrl = TextEditingController();
    final masterCtrl = TextEditingController();
    final isPM = context.read<AppState>().isPermanentMaster;
    if (isPM) masterCtrl.text = context.read<AppState>().masterToken();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reset ? '개인 비밀번호 초기화' : '개인 비밀번호 재설정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '#${member.number} ${member.name}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.purple,
              ),
            ),
            const SizedBox(height: 8),
            if (!reset)
              TextField(
                controller: valCtrl,
                decoration: const InputDecoration(labelText: '새 개인 비밀번호'),
              ),
            if (!reset) const SizedBox(height: 8),
            if (!isPM)
              TextField(
                controller: masterCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '마스터 비밀번호 확인'),
              ),
            const SizedBox(height: 8),
            Text(
              reset
                  ? '초기화하면 ${member.number} → ${member.number}!@@ 로 되돌아갑니다.'
                  : '지정한 비밀번호로 재설정합니다.',
              style: const TextStyle(fontSize: 11, color: AppColors.textGray),
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
            child: Text(reset ? '초기화' : '재설정'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final err = await state.setPersonalPassword(
      masterCtrl.text.trim(),
      member.number,
      value: valCtrl.text.trim(),
      reset: reset,
    );
    if (mounted) setState(() => _busy = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err == null
                ? (reset
                      ? '#${member.number} ${member.name} 비밀번호를 초기화했습니다 (${member.number}!@@)'
                      : '#${member.number} ${member.name} 비밀번호를 재설정했습니다')
                : '실패: $err',
          ),
        ),
      );
    }
  }

  // ---- 4) 복구 (최종 백업 버전/일시) ----
  Widget _restoreCard(AppState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('복구 (백업 버전 / 일시)', Icons.restore, AppColors.tigerGold),
            const SizedBox(height: 8),
            const Text(
              'NAS에 저장된 백업 목록에서 원하는 버전(일시)을 선택해 '
              '그 시점으로 DB를 되돌립니다.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _createBackup(state),
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('지금 백업'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _openRestore(state),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('복구 목록'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBackup(AppState state) async {
    setState(() => _busy = true);
    final name = await state.nas.createBackup();
    if (mounted) setState(() => _busy = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(name != null ? '백업 생성: $name' : '백업 실패')),
      );
    }
  }

  Future<void> _openRestore(AppState state) async {
    setState(() => _busy = true);
    final list = await state.nas.backups();
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('백업본이 없습니다')));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('복구할 백업(버전/일시) 선택'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (c, i) {
              final b = list[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.description, size: 20),
                title: Text(
                  '${b['name']}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                subtitle: Text(
                  '${b['size']} bytes',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _restore(state, '${b['name']}');
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(AppState state, String name) async {
    final master = await _askMaster('복구 ($name)');
    if (master == null) return;
    setState(() => _busy = true);
    // 복구는 서버 측에서 백업본을 DB로 덮어쓰고 반환
    final members = await state.nas.restore(name);
    if (members != null) {
      await state.repo.replaceAll(members);
      await state.refreshFromNas();
    }
    if (mounted) setState(() => _busy = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            members != null ? '복구 완료 (${members.length}명) · $name' : '복구 실패',
          ),
        ),
      );
    }
  }

  Future<String?> _askMaster(String action) async {
    // 영구 마스터(예: 415)는 비번 확인 없이 진행.
    final s = context.read<AppState>();
    if (s.isPermanentMaster) return s.masterToken();
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('마스터 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$action 을(를) 진행하려면 마스터 비밀번호를 입력하세요.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '마스터 비밀번호'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}
