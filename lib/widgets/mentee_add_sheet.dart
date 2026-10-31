/// **멘티 추가** 시트 — 직접입력 + 인가정보 연동(멘토 체계와 동일).
///
/// ## 요구 (원문 2026-10-31)
/// > "멘티 등록도 직접입력 가능 및 기존 인가자 정보와 연계시키고 연동 되도록
/// >  할 것 (멘토체계와 동일)"
///
/// ## 왜 별도 시트인가
///  멘토·페런츠는 **인가자가 아닌 사람**(인적사항만)일 수 있으므로
///  `link_profiles` 시트를 쓴다. 반면 **멘티는 반드시 범 인가자**다
///  ("내가 배출한 범 대원"). 그래서 인가번호를 받아 **회원 카드와 직접 연결**한다.
///
/// ## 두 가지 입력 경로
///  ① **직접입력** — 인가번호(예: 143, G75)를 직접 적는다. 이름을 함께 적으면
///     저장 전에 어떤 회원인지 **미리 확인**해서 보여준다(오타 방지).
///  ② **[인가정보 연동]** — 서버에서 인가자를 검색해 고른다(멘토와 동일한 창).
///
/// 반환: 확정 시 **정규화된 코드**(예: `143`, `G75`), 취소 시 null.
///  은하 번호는 `G` 접두어를 보존한다 — 은하 75 와 범 75 는 다른 사람이다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'link_member_picker.dart';

/// 멘티 추가 시트를 연다.
///
/// [member] 는 **멘토(나)** — 자기 자신은 멘티가 될 수 없다.
/// [existing] 은 이미 등록된 멘티 코드 목록(중복 방지).
Future<String?> showMenteeAddSheet(
  BuildContext context, {
  required Member member,
  List<String> existing = const <String>[],
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _MenteeAddDialog(member: member, existing: existing),
  );
}

class _MenteeAddDialog extends StatefulWidget {
  const _MenteeAddDialog({required this.member, required this.existing});

  final Member member;
  final List<String> existing;

  @override
  State<_MenteeAddDialog> createState() => _MenteeAddDialogState();
}

class _MenteeAddDialogState extends State<_MenteeAddDialog> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  String? _error;

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// 코드 정규화 — **`G` 접두어를 보존**한다(은하 G75 ↔ 범 75 는 다른 사람).
  ///
  /// 공백·`#`·`범`/`은하` 같은 표기는 떼어내고 숫자와 `G` 만 남긴다.
  static String normCode(String raw) {
    var s = raw.trim().toUpperCase();
    if (s.isEmpty) return '';
    s = s.replaceAll('은하', 'G').replaceAll('범', '');
    s = s.replaceAll(RegExp(r'[^0-9G]'), '');
    if (s.isEmpty) return '';
    final isG = s.startsWith('G');
    final d = _digits(s);
    if (d.isEmpty) return '';
    return isG ? 'G$d' : d;
  }

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  /// 입력한 코드로 회원을 찾는다(범/은하 통합 조회).
  Member? _lookup(String code) {
    final c = normCode(code);
    if (c.isEmpty) return null;
    final state = context.read<AppState>();
    if (c.startsWith('G')) {
      // 은하 — 접두어 보존 조회.
      final d = _digits(c);
      for (final m in state.allMembers) {
        if (m.corps == 'eunha' && _digits(m.number) == d) return m;
      }
      return null;
    }
    return state.byNumber(c);
  }

  /// 인가정보 연동 — 서버 검색 창(멘토와 **동일한** 창).
  Future<void> _link() async {
    final picked = await showLinkMemberPicker(
      context,
      nas: context.read<AppState>().nas,
      kind: 'mentee',
      hint: '멘티로 등록할 범 대원을 고르세요.',
    );
    if (picked == null || !mounted) return;
    final num = '${picked['number'] ?? ''}'.trim();
    final corps = '${picked['corps'] ?? 'tsak'}'.trim();
    final nm = '${picked['name'] ?? ''}'.trim();
    final code = normCode(corps == 'eunha' ? 'G$num' : num);
    setState(() {
      _code.text = code;
      if (nm.isNotEmpty) _name.text = nm;
      _error = null;
    });
  }

  void _submit() {
    final code = normCode(_code.text);
    if (code.isEmpty) {
      setState(() => _error = '인가번호를 입력하세요.');
      return;
    }
    // 자기 자신 금지.
    final selfNo = _digits(widget.member.number);
    final selfIsEunha = widget.member.corps == 'eunha';
    final codeIsEunha = code.startsWith('G');
    if (_digits(code) == selfNo && selfIsEunha == codeIsEunha) {
      setState(() => _error = '본인은 멘티로 등록할 수 없습니다.');
      return;
    }
    // 중복 금지.
    for (final e in widget.existing) {
      if (normCode(e) == code) {
        setState(() => _error = '이미 등록된 멘티입니다.');
        return;
      }
    }
    // 이름을 함께 적었는데 회원과 다르면 알려준다(오타 방지 — 저장은 허용).
    final found = _lookup(code);
    final typed = _name.text.trim();
    if (found != null && typed.isNotEmpty && found.name.trim() != typed) {
      setState(
        () => _error =
            '입력한 이름($typed)과 인가번호의 이름(${found.name})이 다릅니다. '
            '인가번호만 저장됩니다.',
      );
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    final code = normCode(_code.text);
    final found = _lookup(code);
    final selfNo = _digits(widget.member.number);
    final selfIsEunha = widget.member.corps == 'eunha';
    final isSelf =
        code.isNotEmpty &&
        _digits(code) == selfNo &&
        code.startsWith('G') == selfIsEunha;
    final dup = code.isNotEmpty && widget.existing.any((e) => normCode(e) == code);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: const Color(0xFFFBF9F4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: h * 0.70,
          minWidth: w > 500 ? 420 : 0,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.supervisor_account,
                    size: 20,
                    color: AppColors.purple,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      '멘티 추가',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purpleDark,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Text(
                '내가 배출한 범 대원을 등록합니다 · '
                '${widget.member.name.isNotEmpty ? widget.member.name : '본인'}'
                ' (범#${selfNo.isEmpty ? '-' : selfNo})',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(height: 12),
              // ── ① 직접입력 ──
              const Text(
                '① 직접 입력',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  SizedBox(
                    width: 118,
                    child: TextField(
                      controller: _code,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '인가번호',
                        hintText: '예: 143 / G75',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '이름 (선택)',
                        hintText: '확인용',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _preview(code: code, found: found, isSelf: isSelf, dup: dup),
              const SizedBox(height: 10),
              // ── ② 인가정보 연동 ──
              const Text(
                '② 기존 인가자 정보와 연동',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(height: 5),
              OutlinedButton.icon(
                onPressed: _link,
                icon: const Icon(Icons.link, size: 17),
                label: const Text('인가정보 연동 (검색해서 고르기)'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 42),
                  foregroundColor: AppColors.purple,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.taegeukRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                      ),
                      onPressed: (code.isEmpty || isSelf || dup) ? null : _submit,
                      icon: const Icon(Icons.check, size: 17),
                      label: const Text('멘티로 등록'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 입력한 코드의 **실시간 미리보기** — 어떤 회원인지 즉시 확인.
  Widget _preview({
    required String code,
    required Member? found,
    required bool isSelf,
    required bool dup,
  }) {
    if (code.isEmpty) {
      return const Text(
        '인가번호를 입력하면 해당 대원을 미리 확인할 수 있습니다. '
        '(은하는 G 를 붙입니다 — 예: G75)',
        style: TextStyle(fontSize: 10.5, color: AppColors.textGray, height: 1.35),
      );
    }
    if (isSelf) {
      return _banner('본인은 멘티로 등록할 수 없습니다.', AppColors.taegeukRed);
    }
    if (dup) {
      return _banner('이미 등록된 멘티입니다.', AppColors.tigerGold);
    }
    if (found == null) {
      return _banner(
        '범#$code — 아직 등록된 카드가 없습니다. '
        '그래도 등록하면 나중에 카드가 생겼을 때 자동으로 연결됩니다.',
        AppColors.tigerGold,
      );
    }
    final l = found.regLeague.trim().isNotEmpty
        ? found.regLeague.trim()
        : found.league.trim();
    final u = found.regUnit.trim().isNotEmpty
        ? found.regUnit.trim()
        : found.unit.trim();
    final org = [l, u].where((e) => e.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.scoutGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.scoutGreen.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 16, color: AppColors.scoutGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${found.name}  ${found.displayNumber}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                if (org.isNotEmpty)
                  Text(
                    org,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(String msg, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: c.withValues(alpha: 0.3)),
    ),
    child: Text(
      msg,
      style: TextStyle(fontSize: 11, color: c, height: 1.35),
    ),
  );
}
