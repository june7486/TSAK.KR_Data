import 'package:flutter/material.dart';
import '../widgets/marquee_text.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

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
      _loadAdmins();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return const Scaffold(body: Center(child: Text('마스터만 접근할 수 있습니다')));
    }
    return Scaffold(
      appBar: TsakAppBar(
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
          _grantAdminCard(state),
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

  // ---- 관리자 지정 (마스터가 인가번호별로 관리자 권한 부여/회수) ----
  bool _adminsLoading = true;
  List<String> _adminNumbers = [];
  final TextEditingController _grantCtrl = TextEditingController();

  @override
  void dispose() {
    _grantCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    setState(() => _adminsLoading = true);
    final r = await context.read<AppState>().nas.merchantAdmins();
    if (!mounted) return;
    _captureAdminNames(r);
    // 서버는 [{number, name}] 객체 배열을 반환한다(문자열 배열 호환도 유지).
    final lst = <String>[];
    for (final e in (r['admins'] as List?) ?? []) {
      if (e is Map) {
        final no = '${e['number'] ?? ''}'.trim();
        if (no.isNotEmpty) lst.add(no);
      } else {
        final s = '$e'.trim();
        if (s.isNotEmpty) lst.add(s);
      }
    }
    setState(() {
      _adminNumbers = lst;
      _adminsLoading = false;
    });
  }

  /// 서버 응답에서 관리자 이름 힌트를 얻는다 (없으면 회원명 fallback).
  final Map<String, String> _adminNames = {};

  void _captureAdminNames(Map<String, dynamic> r) {
    for (final e in (r['admins'] as List?) ?? []) {
      if (e is Map) {
        final no = '${e['number'] ?? ''}'.trim();
        final nm = '${e['name'] ?? ''}'.trim();
        if (no.isNotEmpty && nm.isNotEmpty) _adminNames[no] = nm;
      }
    }
  }

  Widget _grantAdminCard(AppState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('관리자 계정 (생성 · 삭제)', Icons.vpn_key, AppColors.taegeukRed),
            const SizedBox(height: 6),
            const Text(
              '관리자 계정은 「아이디(로그인) = 인가번호」 + 「암호 = 개인 비밀번호」로 동작합니다. '
              '인가번호를 지정하면 그 ID가 관리자로 승격되고, 개인 로그인으로 접속해도 '
              '수품판매관리·통계 등 관리자 기능을 사용할 수 있습니다.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _grantCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '아이디 (인가번호)',
                      hintText: '예: 1234',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _grantAdmin(state),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('권한 부여'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _busy ? null : () => _createAdminAccount(state),
                    icon: const Icon(Icons.badge_outlined, size: 16),
                    label: const Text('계정 생성 (권한+암호)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _busy ? null : () => _loadAdmins(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('목록 새로고침'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: AppColors.scoutGreen,
                ),
                const SizedBox(width: 6),
                const Text(
                  '현재 지정된 관리자',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${_adminNumbers.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_adminsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_adminNumbers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '지정된 관리자가 없습니다.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textGray),
                ),
              )
            else
              Column(
                children: [
                  for (final no in _adminNumbers) _adminAccountTile(state, no),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 관리자 계정 1행 — 아이디/권한/암호 조작 진입.
  Widget _adminAccountTile(AppState state, String no) {
    final name = _memberName(state, no);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.admin_panel_settings,
            size: 18,
            color: AppColors.purple,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아이디 #$no',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                MarqueeText(
                  name.isEmpty ? '이름 미확인' : name,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '아이디 복사',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: no));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('관리자 아이디(#$no)를 복사했습니다')));
            },
            icon: const Icon(Icons.copy, size: 17),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '계정 관리 (암호 생성·삭제)',
            onPressed: _busy ? null : () => _adminAccountSheet(state, no),
            icon: const Icon(Icons.tune, size: 18),
          ),
        ],
      ),
    );
  }

  String _memberName(AppState state, String no) {
    final hint = _adminNames[no];
    if (hint != null && hint.isNotEmpty) return hint;
    try {
      final m = state.repo.byNumber(no);
      return m?.name ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 계정 생성 = 관리자 권한 부여 + 개인 비밀번호 지정을 한 번에.
  Future<void> _createAdminAccount(AppState state) async {
    final noCtrl = TextEditingController(text: _grantCtrl.text.trim());
    final pwCtrl = TextEditingController();
    final isPM = state.isPermanentMaster;
    final masterCtrl = TextEditingController();
    if (isPM) masterCtrl.text = state.masterToken();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('관리자 계정 생성'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '아이디(인가번호)와 암호(개인 비밀번호)를 지정하면 '
              '해당 계정이 관리자로 생성됩니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '아이디 (인가번호)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pwCtrl,
              decoration: InputDecoration(
                labelText: '암호 (개인 비밀번호)',
                hintText: '비우면 기본 {인가번호}!@@',
                isDense: true,
              ),
            ),
            if (!isPM) ...[
              const SizedBox(height: 8),
              TextField(
                controller: masterCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '마스터 비밀번호 확인'),
              ),
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
            child: const Text('생성'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final no = noCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (no.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('인가번호를 입력하세요')));
      return;
    }
    setState(() => _busy = true);
    // 1) 권한 부여
    final r = await state.nas.grantAdmin(masterCtrl.text.trim(), no);
    // 2) 암호 지정/초기화
    final val = pwCtrl.text.trim();
    final err = await state.setPersonalPassword(
      masterCtrl.text.trim(),
      no,
      value: val,
      reset: val.isEmpty,
    );
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    final granted = r['ok'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? '관리자 계정(#$no) 생성 완료 · 암호 '
                    '${val.isEmpty ? '기본값($no!@@)' : '지정됨'}'
                    '${err != null ? ' (암호: $err)' : ''}'
              : '실패: ${r['error'] ?? '권한 부여 확인 불가'}',
        ),
      ),
    );
    if (granted) {
      _grantCtrl.clear();
      await state.loadAdmin();
      _loadAdmins();
    }
  }

  /// 계정별 관리 시트 — 아이디/암호 생성·초기화·삭제.
  Future<void> _adminAccountSheet(AppState state, String no) async {
    final name = _memberName(state, no);
    final pws = (state.adminState['personalPasswords'] as Map?) ?? {};
    final hasCustom = pws.containsKey(no);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.vpn_key, color: AppColors.taegeukRed),
                  const SizedBox(width: 8),
                  Text(
                    '관리자 계정 관리',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _kvLine('아이디 (로그인)', '범#$no'),
              _kvLine('이름', name.isEmpty ? '미확인' : name),
              _kvLine('암호 상태', hasCustom ? '지정됨 (개별 설정)' : '기본값 ($no!@@)'),
              const SizedBox(height: 6),
              Text(
                '개인 로그인 화면에서 아이디 #$no · 위 암호로 접속하면 관리자 기능이 열립니다.',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: no));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('아이디(#$no)를 복사했습니다')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('아이디 복사'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _adminResetPassword(state, no);
                      },
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('암호 초기화'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _adminSetPassword(state, no);
                      },
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('암호 지정'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.taegeukRed,
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _revokeAdmin(state, no);
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('계정 삭제 (권한 회수)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kvLine(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            k,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textGray),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Future<void> _adminResetPassword(AppState state, String no) async {
    final master = await _askMaster('관리자 #$no 암호 초기화');
    if (master == null) return;
    setState(() => _busy = true);
    final err = await state.setPersonalPassword(master, no, reset: true);
    await state.loadAdmin();
    if (mounted) setState(() => _busy = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err == null ? '범#$no 암호를 기본값($no!@@)으로 초기화했습니다' : '실패: $err',
          ),
        ),
      );
    }
  }

  Future<void> _adminSetPassword(AppState state, String no) async {
    final pwCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('관리자 #$no 암호 지정'),
        content: TextField(
          controller: pwCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '새 암호 (개인 비밀번호)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('지정'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final val = pwCtrl.text.trim();
    if (val.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('암호를 입력하세요')));
      return;
    }
    final master = await _askMaster('관리자 #$no 암호 지정');
    if (master == null) return;
    setState(() => _busy = true);
    final err = await state.setPersonalPassword(master, no, value: val);
    await state.loadAdmin();
    if (mounted) setState(() => _busy = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err == null ? '범#$no 관리자 암호를 지정했습니다' : '실패: $err'),
        ),
      );
    }
  }

  Future<void> _grantAdmin(AppState state) async {
    final no = _grantCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (no.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('인가번호를 입력하세요')));
      return;
    }
    final master = await _askMaster('관리자 권한 부여 (인가 $no)');
    if (master == null) return;
    setState(() => _busy = true);
    final r = await state.nas.grantAdmin(master, no);
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    final ok = r['ok'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '인가 $no 님에게 관리자 권한을 부여했습니다' : '실패: ${r['error'] ?? '확인 불가'}',
        ),
      ),
    );
    if (ok) {
      _grantCtrl.clear();
      _loadAdmins();
    }
  }

  Future<void> _revokeAdmin(AppState state, String no) async {
    final master = await _askMaster('관리자 권한 회수 (인가 $no)');
    if (master == null) return;
    setState(() => _busy = true);
    final r = await state.nas.revokeAdmin(master, no);
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    final ok = r['ok'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '인가 $no 님의 관리자 권한을 회수했습니다' : '실패')),
    );
    if (ok) _loadAdmins();
  }

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
              const Text(
                '영구 마스터는 별도 확인 없이 변경됩니다.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
              ),
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
                                    ' · ${m.numberLabel}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: MarqueeText(
                                    m.unit,
                                    style: const TextStyle(fontSize: 11),
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
              '${member.numberLabel} ${member.name}',
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
                      ? '${member.numberLabel} ${member.name} 비밀번호를 초기화했습니다 (${member.number}!@@)'
                      : '${member.numberLabel} ${member.name} 비밀번호를 재설정했습니다')
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
