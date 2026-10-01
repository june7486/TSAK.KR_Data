import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// 멘티대원 / 자녀대원 등록정보 창.
///
/// ## 요구
///  · "범스카우트 인가자 개인창에 멘티 등록정보 창, (페런츠 인가자) 자녀대원
///    등록정보 창을 만들고 그 항목에 멘티대원 인가번호+이름, 자녀대원 인가정보+이름을
///    노출할 것"
///  · "인가자가 멘티대원·자녀대원을 직접 등록하고 승인을 요청 → 통합승인관리 창에서
///    관리자·마스터가 승인"
///  · "멘토=멘티=페런츠 데이터가 서로 연동되도록 함"
///
/// ## 연동
///  · 등록된 멘티/자녀대원의 이름은 **회원 명단(DB)** 에서 인가번호로 조회해 노출한다.
///  · 인가번호를 추가하면 회원 데이터에 저장되고 연결 승인상태가 'pending' 으로
///    전환되어 통합승인관리(멘토·페런츠 연결 큐)에 나타난다.
class MenteeRegisterSection extends StatefulWidget {
  const MenteeRegisterSection({
    super.key,
    required this.member,
    required this.kind, // 'mentee'(멘티대원) | 'child'(자녀대원)
    required this.codes,
    required this.canEdit,
    required this.onChanged,
    this.compact = false,
  });

  final Member member;
  final String kind;
  final List<String> codes;
  final bool canEdit;
  final ValueChanged<List<String>> onChanged;
  final bool compact;

  @override
  State<MenteeRegisterSection> createState() => _MenteeRegisterSectionState();
}

class _MenteeRegisterSectionState extends State<MenteeRegisterSection> {
  bool get _isMentee => widget.kind == 'mentee';

  Color get _accent => _isMentee ? AppColors.purple : AppColors.taegeukBlue;
  IconData get _icon =>
      _isMentee ? Icons.supervisor_account : Icons.family_restroom;
  String get _title => _isMentee ? '멘티 등록정보' : '자녀대원 등록정보';
  String get _codeLabel =>
      _isMentee ? '멘티대원 인가번호' : '자녀대원 인가번호';

  String _nameOf(String code) {
    final d = code.replaceAll(RegExp(r'[^0-9]'), '');
    final state = context.watch<AppState>();
    final byNo = state.byNumber(d);
    if (byNo != null && byNo.name.trim().isNotEmpty) return byNo.name.trim();
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_icon, size: 15, color: _accent),
            const SizedBox(width: 5),
            Text(
              _title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _accent,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '($_codeLabel · 이름)',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textGray,
              ),
            ),
            const Spacer(),
            if (widget.canEdit)
              TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                  foregroundColor: _accent,
                ),
                onPressed: _edit,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('등록', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        if (widget.codes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
            child: Text(
              _isMentee
                  ? '등록된 멘티대원 없음 (복수 등록 가능)'
                  : '등록된 자녀대원 없음 (복수 등록 가능)',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final code in widget.codes) _row(code),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(String code) {
    final d = code.replaceAll(RegExp(r'[^0-9]'), '');
    final nm = _nameOf(code);
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 3, bottom: 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '#${d.isEmpty ? code : d}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _accent,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              nm.isEmpty ? '(이름 미확인)' : nm,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: nm.isEmpty ? AppColors.textGray : AppColors.textDark,
                fontStyle: nm.isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (widget.canEdit)
            IconButton(
              tooltip: '삭제',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16, color: AppColors.textGray),
              onPressed: () {
                final next = List<String>.from(widget.codes)..remove(code);
                widget.onChanged(next);
              },
            ),
        ],
      ),
    );
  }

  /// 인가번호 + (자동 채움) 이름 입력 다이얼로그.
  Future<void> _edit() async {
    final noCtrl = TextEditingController();
    String resolved = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            title: Text('$_title 등록'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isMentee
                        ? '본인이 멘토인 멘티대원의 범스카우트 인가번호를 입력하세요.'
                        : '본인이 페런츠(보호자)인 자녀대원의 범스카우트 인가번호를 입력하세요.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textGray,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final d = v.replaceAll(RegExp(r'[^0-9]'), '');
                      final found = context.read<AppState>().byNumber(d);
                      setDlg(
                        () => resolved = found?.name.trim() ?? '',
                      );
                    },
                    decoration: InputDecoration(
                      labelText: '$_codeLabel *',
                      hintText: '예: 2186',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: resolved.isNotEmpty
                          ? AppColors.scoutGreen.withValues(alpha: 0.10)
                          : AppColors.tigerGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          resolved.isNotEmpty
                              ? Icons.verified_user
                              : Icons.info_outline,
                          size: 16,
                          color: resolved.isNotEmpty
                              ? AppColors.scoutGreen
                              : AppColors.tigerGold,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            resolved.isNotEmpty
                                ? '이름 : $resolved (명단에서 확인됨)'
                                : '인가번호를 입력하면 이름이 자동으로 채워집니다.',
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '등록하면 관리자·마스터 승인 대기중으로 표시되며, '
                    '통합승인관리 창에서 승인되면 정식 등록됩니다.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                      height: 1.4,
                    ),
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
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('등록 요청'),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true || !mounted) return;
    final code = noCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (code.isEmpty) {
      _snack('인가번호를 입력하세요.');
      return;
    }
    if (widget.codes.contains(code)) {
      _snack('이미 등록된 인가번호입니다.');
      return;
    }
    widget.onChanged([...widget.codes, code]);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
