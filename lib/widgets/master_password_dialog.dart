import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';

/// 🐯 마스터 비밀번호 변경 창 (turn69)
///
/// ## 사용자 요구 (그대로)
///   "마스터비번 변경 … 마스터창에 비번 변경 창 추가로 넣음,
///    비번 변경 시 변경된 비번 확인 3번 할 것"
///
/// ## 왜 '3번 확인'인가
///   마스터 비밀번호는 **되찾을 수 없다**. 서버에는 PBKDF2 해시만 있어서
///   원문을 복원할 방법이 존재하지 않는다(그게 해시의 목적이다).
///   즉 한 글자만 틀려도 마스터 계정은 영구히 잠긴다.
///   자유 입력 비밀번호에서 실제로 사고가 나는 지점은 '오타'이므로,
///   같은 값을 **세 번** 받아 서로 일치할 때만 저장한다.
///
/// ## 3단계 진행
///   ① 새 비밀번호 입력
///   ② 새 비밀번호 다시 입력  (①과 일치해야 다음)
///   ③ 새 비밀번호 마지막 확인 (①·②와 일치해야 저장)
///   → 세 칸이 모두 같은 값일 때만 '변경' 버튼이 살아난다.
///
/// ## 실패 시
///   현재 비밀번호가 틀리면 서버가 401 을 준다. 그때는 **저장이 되지
///   않았으므로** 입력값을 유지한 채 안내만 띄운다(다시 3번 받게 하면
///   화면을 처음부터 다시 하게 되어 오히려 오타를 유발한다).
///   단, "지난번과 다르게" 같은 규칙 위반은 값이 그대로 살아 있으므로
///   해당 칸만 고치면 된다.
Future<bool?> showMasterPasswordDialog(
  BuildContext context,
  NasApi nas,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _MasterPasswordDialog(nas: nas),
  );
}

class _MasterPasswordDialog extends StatefulWidget {
  final NasApi nas;
  const _MasterPasswordDialog({required this.nas});

  @override
  State<_MasterPasswordDialog> createState() => _MasterPasswordDialogState();
}

class _MasterPasswordDialogState extends State<_MasterPasswordDialog> {
  final _cur = TextEditingController();
  final _n1 = TextEditingController();
  final _n2 = TextEditingController();
  final _n3 = TextEditingController();

  bool _busy = false;
  bool _show = false;
  String _err = '';

  @override
  void initState() {
    super.initState();
    for (final c in [_cur, _n1, _n2, _n3]) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (mounted) setState(() => _err = '');
  }

  @override
  void dispose() {
    for (final c in [_cur, _n1, _n2, _n3]) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  // ── 규칙 ────────────────────────────────────────────────────────────
  //  서버(_master_pw_set)와 **같은 규칙**을 화면에서 먼저 검사한다.
  //  서버는 최종 방어선이고, 화면은 왕복 없이 바로 알려주는 역할.
  String? _ruleOf(String v) {
    if (v.isEmpty) return null;
    if (v.length < 8) return '8자 이상이어야 합니다';
    if (v.trim() != v) return '앞뒤에 공백을 둘 수 없습니다';
    if (!RegExp(r'[0-9]').hasMatch(v)) return '숫자를 포함해야 합니다';
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return '영문을 포함해야 합니다';
    return null;
  }

  bool get _allThreeSame {
    final a = _n1.text, b = _n2.text, c = _n3.text;
    return a.isNotEmpty && a == b && b == c;
  }

  bool get _canSubmit =>
      !_busy &&
      _cur.text.isNotEmpty &&
      _ruleOf(_n1.text) == null &&
      _allThreeSame &&
      _n1.text != _cur.text;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      final j = await widget.nas
          .changeMasterPassword(_cur.text, _n1.text);
      if (j['ok'] == true) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _err = (j['error'] ?? '변경에 실패했습니다').toString();
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _err = '변경 요청 실패: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rule = _ruleOf(_n1.text);
    final step2ok = _n1.text.isNotEmpty && _n2.text == _n1.text;
    final step3ok = _allThreeSame;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.key_rounded, color: AppColors.taegeukRed),
          SizedBox(width: 8),
          Expanded(
            child: Text('마스터 비밀번호 변경',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 되찾을 수 없다는 경고 (가장 먼저 읽히게) ──
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.taegeukRed.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.taegeukRed.withValues(alpha: 0.25)),
                ),
                child: const Text(
                  '이 비밀번호는 되찾을 수 없습니다.\n'
                  '세 번 모두 같은 값으로 입력해야 저장됩니다.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.taegeukRed,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 14),

              _field(
                ctrl: _cur,
                label: '현재 마스터 비밀번호',
                icon: Icons.lock_outline,
              ),
              const SizedBox(height: 12),

              _stepLabel('① 새 비밀번호', true),
              _field(
                ctrl: _n1,
                label: '새 비밀번호 (영문+숫자 8자 이상)',
                icon: Icons.lock_reset,
              ),
              if (rule != null)
                _hint(rule, AppColors.taegeukRed)
              else if (_n1.text.isNotEmpty &&
                  _cur.text.isNotEmpty &&
                  _n1.text == _cur.text)
                _hint('지금 쓰는 비밀번호와 다르게 정해 주세요', AppColors.taegeukRed)
              else if (_n1.text.isNotEmpty)
                _hint('사용할 수 있는 형식입니다', Colors.green.shade700),
              const SizedBox(height: 12),

              _stepLabel('② 새 비밀번호 다시 입력', step2ok),
              _field(
                ctrl: _n2,
                label: '새 비밀번호 재입력',
                icon: Icons.repeat_rounded,
                errorText: _n2.text.isNotEmpty && !step2ok
                    ? '①과 같지 않습니다'
                    : null,
              ),
              const SizedBox(height: 12),

              _stepLabel('③ 새 비밀번호 마지막 확인', step3ok),
              _field(
                ctrl: _n3,
                label: '새 비밀번호 확인 (3번째)',
                icon: Icons.verified_outlined,
                errorText: _n3.text.isNotEmpty && !step3ok
                    ? '①·②와 같지 않습니다'
                    : null,
              ),

              if (_allThreeSame)
                _hint('세 번 모두 일치합니다 — 변경할 수 있습니다',
                    Colors.green.shade700)
              else
                _hint(
                  '세 칸이 모두 같아야 변경 버튼이 활성화됩니다 '
                  '(${_n3.text.isEmpty ? "3번째 입력 대기" : "일치 확인 중"})',
                  AppColors.textGray,
                ),

              if (_err.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.taegeukRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _err,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.taegeukRed,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(_busy ? '변경 중…' : '변경'),
        ),
      ],
    );
  }

  Widget _stepLabel(String t, bool done) => Padding(
        padding: const EdgeInsets.only(bottom: 4, left: 2),
        child: Row(
          children: [
            Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14,
                color: done ? Colors.green.shade700 : AppColors.textGray),
            const SizedBox(width: 5),
            Text(t,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: done ? Colors.green.shade800 : AppColors.textGray)),
          ],
        ),
      );

  Widget _hint(String t, Color c) => Padding(
        padding: const EdgeInsets.only(top: 4, left: 2),
        child: Text(t, style: TextStyle(fontSize: 11.5, color: c)),
      );

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    String? errorText,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: !_show,
      enabled: !_busy,
      // 마스터 비번은 브라우저 비밀번호 저장 대상이 아니다(공용 PC 대비).
      autofillHints: const <String>[],
      enableSuggestions: false,
      autocorrect: false,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 19),
        isDense: true,
        border: const OutlineInputBorder(),
        errorText: errorText,
        suffixIcon: IconButton(
          tooltip: _show ? '가리기' : '보기',
          icon: Icon(_show ? Icons.visibility_off : Icons.visibility, size: 19),
          onPressed: () => setState(() => _show = !_show),
        ),
      ),
      onSubmitted: (_) {
        if (_canSubmit) _submit();
      },
    );
  }
}
