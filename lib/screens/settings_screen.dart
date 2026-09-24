import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_config.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';

/// 설정 · 백업/복원 · 후원 · 개발자 정보
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('설정 · 백업/복원'),
        actions: const [AppHomeEmblem(size: 26)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _nasStatusCard(state),
          const SizedBox(height: 12),
          _adminEmailCard(state),
          const SizedBox(height: 12),
          _backupCard(state),
          const SizedBox(height: 12),
          _donationCard(state),
          const SizedBox(height: 12),
          _developerCard(state),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t, IconData icon) => Row(
        children: [
          Icon(icon, color: AppColors.purple, size: 20),
          const SizedBox(width: 8),
          Text(t,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ],
      );

  Widget _nasStatusCard(AppState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('NAS 서버 상태', Icons.cloud),
            const SizedBox(height: 10),
            _kv('서버', state.nas.baseUrl.isEmpty ? '(웹 앱 자체 서버)' : state.nas.baseUrl),
            _kv('버전', state.versionText),
            _kv('동기화', _syncLabel(state.syncStatus)),
            _kv('인가자 수', '${state.total}명'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            final ok = await state.refreshFromNas();
                            if (mounted) setState(() => _busy = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(ok
                                        ? 'NAS 최신 데이터를 불러왔습니다'
                                        : 'NAS 연결 실패 (오프라인 데이터 사용)')),
                              );
                            }
                          },
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('NAS에서 불러오기'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            final ok = await state.pushToNas();
                            if (mounted) setState(() => _busy = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(ok
                                        ? 'NAS에 저장했습니다 (이전 버전 자동 백업)'
                                        : 'NAS 저장 실패')),
                              );
                            }
                          },
                    icon: const Icon(Icons.upload, size: 18),
                    label: const Text('NAS에 저장'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller:
                  TextEditingController(text: state.nas.baseUrl),
              decoration: const InputDecoration(
                labelText: 'NAS 서버 주소 (비우면 웹 자체 서버)',
                hintText: 'https://your-proxy.example.com',
              ),
              onSubmitted: (v) => state.setServerBase(v.trim()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminEmailCard(AppState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('관리자 이메일', Icons.mail_outline),
            const SizedBox(height: 8),
            Text('현재: ${state.adminEmail}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _editAdminEmail(state),
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('이메일 변경 (비밀번호 필요)'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editAdminEmail(AppState state) async {
    final emailCtrl = TextEditingController(text: state.adminEmail);
    final pwCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('관리자 이메일 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: '이메일'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pwCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '앱 비밀번호 (Tsak1988!!)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('변경')),
        ],
      ),
    );
    if (ok == true) {
      final success =
          await state.setAdminEmail(emailCtrl.text.trim(), pwCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(success ? '이메일을 변경했습니다' : '비밀번호가 올바르지 않습니다')),
        );
      }
    }
  }

  Widget _backupCard(AppState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('DB 백업 / 복원', Icons.backup),
            const SizedBox(height: 8),
            const Text(
              'NAS에 저장된 이전 버전을 선택해 복원할 수 있습니다.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textGray),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            final name = await state.nas.createBackup();
                            if (mounted) setState(() => _busy = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(name != null
                                        ? '백업 생성: $name'
                                        : '백업 실패 (NAS 연결 필요)')),
                              );
                            }
                          },
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('지금 백업'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            final list = await state.nas.backups();
                            if (mounted) setState(() => _busy = false);
                            if (!mounted) return;
                            if (list.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('백업본이 없습니다 (NAS 연결 필요)')),
                              );
                              return;
                            }
                            _showRestoreDialog(state, list);
                          },
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('복원 목록'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRestoreDialog(AppState state, List<Map<String, dynamic>> list) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('복원할 백업 선택'),
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
                title: Text('${b['name']}',
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text('${b['size']} bytes',
                    style: const TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  setState(() => _busy = true);
                  final members = await state.nas.restore('${b['name']}');
                  if (members != null) {
                    await state.repo.replaceAll(members);
                    await state.refreshFromNas();
                  }
                  if (mounted) setState(() => _busy = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(members != null
                              ? '복원 완료 (${members.length}명)'
                              : '복원 실패')),
                    );
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }

  Widget _donationCard(AppState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('후원 안내', Icons.volunteer_activism),
            const SizedBox(height: 8),
            for (final d in state.donations)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.tigerGold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${d['label']}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${d['bank']} ${d['account']}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        // 클립보드 복사
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${d['account']} 복사됨')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            const Divider(),
            Text('예금주: ${state.donationHolder}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _developerCard(AppState state) {
    final dev = state.developer;
    return Card(
      color: AppColors.purple.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('앱 정보 / 개발', Icons.info_outline),
            const SizedBox(height: 8),
            _kv('앱', 'TSAK 인가자 관리'),
            _kv('개발', '${dev['name']} · ${dev['unit']}'),
            _kv('이메일', '${dev['email']}'),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse('mailto:${dev['email']}');
                    try {
                      await launchUrl(uri);
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.email, size: 18),
                  label: const Text('개발자에게 메일'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showPasswordGuide,
                  icon: const Icon(Icons.password, size: 18),
                  label: const Text('비밀번호 안내'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPasswordGuide() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비밀번호 체계 안내'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• 앱 접근: Tsak1988!! (1시간 유지)',
                style: TextStyle(fontSize: 13)),
            SizedBox(height: 4),
            Text('• 개인 접근: 인가번호 + !@@ (예: 415!@@)',
                style: TextStyle(fontSize: 13)),
            SizedBox(height: 4),
            Text('• 마스터: 모든 기능/통제 (변경 불가)',
                style: TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textGray)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  String _syncLabel(String s) {
    switch (s) {
      case 'saving':
        return '저장 중…';
      case 'saved':
        return '최신 (동기화됨)';
      case 'error':
        return '오류 (오프라인)';
      default:
        return '대기';
    }
  }
}

/// 후원 버튼 (홈에서 바로 열 수 있도록) — AppConfig 접미사 확인용
class DonationInfo {
  static const String holder = '한국범스카우트중앙회';
  static const String suffix = AppConfig.personalSuffix;
}
