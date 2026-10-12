import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'confirm.dart';

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
  String get _title => _isMentee ? '멘티 등록정보 (내가 만든 범 대원)' : '자녀대원 등록정보';
  String get _codeLabel => _isMentee ? '멘티대원 인가번호' : '자녀대원 인가번호';

  String _nameOf(String code) {
    final d = code.replaceAll(RegExp(r'[^0-9]'), '');
    final state = context.watch<AppState>();
    final byNo = state.byNumber(d);
    if (byNo != null && byNo.name.trim().isNotEmpty) return byNo.name.trim();
    return '';
  }

  /// 자녀대원/멘티대원의 **소속정보 = 현재활동 등록정보** — 회원 명단에서 조회.
  ///   (요구: "멘토(멘티,페런츠) 이름 아래 소속정보는 현재활동 등록정보를 넣어줘")
  ///   · 현재활동(regLeague·regUnit)이 비어 있으면 인가 당시(league·unit)로 폴백.
  String _infoOf(String code) {
    final d = code.replaceAll(RegExp(r'[^0-9]'), '');
    final state = context.watch<AppState>();
    final m = state.byNumber(d);
    if (m == null) return '';
    final parts = <String>[];
    if (m.regLeague.trim().isNotEmpty) parts.add(m.regLeague.trim());
    if (m.regUnit.trim().isNotEmpty) parts.add(m.regUnit.trim());
    if (parts.isEmpty) {
      if (m.league.trim().isNotEmpty) parts.add(m.league.trim());
      if (m.unit.trim().isNotEmpty) parts.add(m.unit.trim());
    }
    return parts.join(' · ');
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
              _isMentee
                  ? '($_codeLabel · 이름 · 현재활동 등록정보) · 본인이 배출한 범 대원'
                  : '($_codeLabel · 이름 · 현재활동 등록정보)',
              style: const TextStyle(fontSize: 10.5, color: AppColors.textGray),
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
                  ? '본인이 만든(배출한) 범 대원 없음 (복수 등록 가능)'
                  : '등록된 자녀대원 없음 (복수 등록 가능)',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final code in widget.codes) _row(code)],
            ),
          ),
      ],
    );
  }

  Widget _row(String code) {
    final d = code.replaceAll(RegExp(r'[^0-9]'), '');
    final nm = _nameOf(code);
    final info = _infoOf(code);
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '범#${d.isEmpty ? code : d}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _accent,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nm.isEmpty ? '(이름 미확인)' : nm,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: nm.isEmpty ? AppColors.textGray : AppColors.textDark,
                    fontStyle: nm.isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                if (info.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      info,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textGray,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.canEdit)
            IconButton(
              tooltip: '삭제',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.close,
                size: 16,
                color: AppColors.textGray,
              ),
              onPressed: () async {
                // (요구) 삭제 전 한 번 더 확인.
                final ok = await confirmDialog(
                  context,
                  title: '인가번호 삭제',
                  message: '범#$code 인가번호 연결을 삭제할까요?',
                );
                if (!ok) return;
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
    String resolvedInfo = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            // (요구) 키보드가 올라오면 창이 줄어들어 입력칸이 잘리던 문제 →
            //  내용을 스크롤 가능하게 하고, 키보드만큼 창을 위로 올린다.
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            title: Text('$_title 등록'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isMentee
                      ? '본인이 멘토(배출 대장)로서 만든 범 대원의 범 인가번호를 입력하세요.'
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
                    final nm2 = found?.name.trim() ?? '';
                    final infoParts = <String>[];
                    if ((found?.league.trim() ?? '').isNotEmpty) {
                      infoParts.add(found!.league.trim());
                    }
                    if ((found?.unit.trim() ?? '').isNotEmpty) {
                      infoParts.add(found!.unit.trim());
                    }
                    setDlg(() {
                      resolved = nm2;
                      resolvedInfo = infoParts.join(' · ');
                    });
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
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                    '${resolvedInfo.isEmpty ? '' : '\n인가정보 : $resolvedInfo'}'
                              : '인가번호를 입력하면 이름·인가정보(연맹·단위대)가 자동으로 채워집니다.',
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
