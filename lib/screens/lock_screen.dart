import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/privacy_consent.dart';

/// 앱 잠금(인증) 화면
///  - 관리자 접근: ID "TSAK"(대문자) + 앱 비밀번호 (Tsak1988!!)
///  - 범스카우트 접근: ID "인가번호" + 개인 비밀번호 (예: 인가번호 000 → 000!@@)
///  - 비인가자 접근: ID "휴대폰 전화번호" + 비밀번호(뒤 4자리) / 신규회원 생성
///  - 마스터 접근: Corbuser7!@@ (모든 기능/통제, 불변)
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, this.onUnlocked});

  final VoidCallback? onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _tier = 'app';
  final _ctrl = TextEditingController();
  final _idCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty) {
      setState(() => _error = '비밀번호를 입력하세요');
      return;
    }
    if (_tier != 'master' && _idCtrl.text.trim().isEmpty) {
      setState(() => _error = 'ID를 입력하세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    // 관리자는 ID 고정(TSAK), 그 외는 입력값 사용
    final idInput = _tier == 'app' ? 'TSAK' : _idCtrl.text.trim();
    final ok = await state.login(_tier, v, id: idInput);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onUnlocked?.call();
    } else {
      setState(() => _error = _hintForTier());
    }
  }

  /// 비인가자 신규회원 생성 → 생성 직후 자동 로그인
  Future<void> _createRegular() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool agreed = false;
    final created = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('신규회원 생성'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ID는 휴대폰 전화번호, 비밀번호는 전화번호 뒤 4자리로 자동 생성됩니다.',
                    style: TextStyle(fontSize: 12, color: AppColors.textGray),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '이름 (실명)',
                      helperText: '실명을 입력하세요 (닉네임 불가)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: '휴대폰 전화번호'),
                  ),
                  const SizedBox(height: 12),
                  // 개인정보 수집·이용 동의 (필수) — 동의해야 가입 가능
                  PrivacyConsentField(
                    agreed: agreed,
                    onChanged: (v) => setLocal(() => agreed = v),
                    showTitle: false,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
              onPressed: agreed
                  ? () => Navigator.pop(ctx, {
                      'name': nameCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                    })
                  : null,
              child: const Text('생성'),
            ),
          ],
        ),
      ),
    );
    if (created == null || !mounted) return;
    final name = created['name'] ?? '';
    final phone = created['phone'] ?? '';
    if (name.isEmpty || phone.replaceAll(RegExp(r'[^0-9]'), '').length < 4) {
      setState(() => _error = '이름과 전화번호를 정확히 입력하세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    final m = await state.createRegularMember(name, phone);
    if (!mounted) return;
    if (m == null) {
      setState(() {
        _busy = false;
        _error = '이미 등록된 번호이거나 입력이 올바르지 않습니다';
      });
      return;
    }
    // 생성된 비밀번호 = 뒤 4자리
    final ok = await state.login('guest', m.phoneLast4, id: m.loginId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onUnlocked?.call();
    } else {
      setState(() => _error = '생성 후 로그인에 실패했습니다. 다시 시도해 주세요');
    }
  }

  String _hintForTier() {
    switch (_tier) {
      case 'master':
        return '마스터 비밀번호가 올바르지 않습니다';
      case 'personal':
        return 'ID(인가번호) 또는 비밀번호가 올바르지 않습니다';
      case 'guest':
        return 'ID(전화번호) 또는 비밀번호(뒤 4자리)가 올바르지 않습니다';
      default:
        return 'ID 또는 앱 비밀번호가 올바르지 않습니다';
    }
  }

  void _switchTier(String t) {
    setState(() {
      _tier = t;
      _error = null;
      _ctrl.clear();
      _idCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/tsak_emblem.png',
                    width: 96,
                    height: 96,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.shield, size: 84, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '한국 범스카우트중앙회 통합 앱',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'TSAK 인가자 · 회원 통합 관리',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _tierTabs(),
                        const SizedBox(height: 16),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _tierHelp(),
                        ),
                        const SizedBox(height: 12),
                        // ID 입력 — 관리자·범스카우트·비인가자 표시 (마스터만 비밀번호 전용)
                        if (_tier != 'master') ...[
                          TextField(
                            controller: _idCtrl,
                            autofocus: true,
                            keyboardType:
                                (_tier == 'personal' || _tier == 'guest')
                                ? TextInputType.number
                                : TextInputType.text,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: _tier == 'guest' ? 'ID (전화번호)' : 'ID',
                              prefixIcon: const Icon(Icons.badge_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _ctrl,
                          obscureText: _obscure,
                          autofocus: _tier == 'master',
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: _tier == 'guest'
                                ? '비밀번호 (뒤 4자리)'
                                : '비밀번호',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: AppColors.taegeukRed,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppColors.taegeukRed,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.purple,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _busy ? null : _submit,
                            icon: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.login),
                            label: const Text('접속'),
                          ),
                        ),
                        if (_tier == 'guest') ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _busy ? null : _createRegular,
                            icon: const Icon(Icons.person_add_alt, size: 18),
                            label: const Text('신규회원 생성 (ID=전화번호, PW=뒤 4자리)'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '개발: 이승준 · 범스카우트415 · june7558@gmail.com',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    '한국 범스카우트중앙회 통합 앱 v1.0.0 · 업데이트 2025.09.24',
                    style: TextStyle(color: Colors.white60, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tierTabs() {
    final tabs = [
      ('app', '관리자', Icons.admin_panel_settings),
      ('personal', '범스카우트', Icons.person),
      ('guest', '비인가자', Icons.person_outline),
      ('master', '마스터', Icons.workspace_premium),
    ];
    return Row(
      children: [
        for (final t in tabs)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: GestureDetector(
                onTap: () => _switchTier(t.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _tier == t.$1
                        ? AppColors.purple
                        : AppColors.purple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        t.$3,
                        size: 18,
                        color: _tier == t.$1 ? Colors.white : AppColors.purple,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _tier == t.$1
                              ? Colors.white
                              : AppColors.purple,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tierHelp() {
    String text;
    switch (_tier) {
      case 'master':
        text = '모든 기능·초기화·통제 권한 (변경 불가)';
        break;
      case 'personal':
        text = 'ID에 본인 인가번호를 입력하세요';
        break;
      case 'guest':
        text = 'ID=휴대폰 전화번호 · 비밀번호=전화번호 뒤 4자리';
        break;
      default:
        text = 'ID와 비밀번호를 입력하세요 (평소에는 관리자를 선택하세요)';
    }
    return Row(
      key: ValueKey(_tier),
      children: [
        const Icon(Icons.info_outline, size: 15, color: AppColors.textGray),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.textGray),
          ),
        ),
      ],
    );
  }
}
