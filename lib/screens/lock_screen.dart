import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// 앱 잠금(인증) 화면
///  - 앱 접근: ID "TSAK"(대문자, 기본값) + 앱 비밀번호 (Tsak1988!!)
///  - 개인 접근: ID "인가번호" + 개인 비밀번호 (예: 인가번호 000 → 000!@@)
///  - 마스터: Corbuser7!@@ (모든 기능/통제, 불변)
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
    if (_tier == 'personal' && _idCtrl.text.trim().isEmpty) {
      setState(() => _error = 'ID를 입력하세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    // 앱 접근은 ID를 노출하지 않음(내부 고정값 TSAK), 개인 접근은 입력한 인가번호 사용
    final idInput = _tier == 'app' ? 'TSAK' : _idCtrl.text.trim();
    final ok = await state.login(_tier, v, id: idInput);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      if (widget.onUnlocked != null) {
        widget.onUnlocked!();
      }
    } else {
      setState(() => _error = _hintForTier());
    }
  }

  String _hintForTier() {
    switch (_tier) {
      case 'master':
        return '마스터 비밀번호가 올바르지 않습니다';
      case 'personal':
        return 'ID(인가번호) 또는 비밀번호가 올바르지 않습니다';
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
                    'TSAK 인가자 관리',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '한국범스카우트 중앙회',
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
                        // ID 입력 — 개인 접근에서만 표시 (앱/마스터는 ID 비노출)
                        if (_tier == 'personal') ...[
                          TextField(
                            controller: _idCtrl,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'ID',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _ctrl,
                          obscureText: _obscure,
                          autofocus: _tier != 'personal',
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: '비밀번호',
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '개발: 이승준 · 범스카우트415 · june7558@gmail.com',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
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
      ('app', '앱 접근', Icons.phone_android),
      ('personal', '개인 접근', Icons.person),
      ('master', '마스터', Icons.workspace_premium),
    ];
    return Row(
      children: [
        for (final t in tabs)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
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
                        style: TextStyle(
                          fontSize: 12,
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
      default:
        text = '앱 접근 비밀번호 · 1시간마다 재입력';
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
