import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';

/// 멘토·페런츠 인적사항 입력 필드.
///
/// ## 요구사항
///  · "멘토 및 페런츠를 수동으로 입력할 경우 인적사항 넣도록 할 것"
///  · "각각 전화번호로 아이디 패스워드 이름 생성할 것"
///    → 아이디: 전화번호(숫자) / 비밀번호: 뒤 4자리 + '!@@'
///  · (인적사항 항목 변경 — 통계용)
///    멘토: 범인가자번호(멘티) · 이름(멘토) · 전화번호(멘토)
///          · 소속연맹(멘토) · 소속단위대(멘토)
///    페런츠: 인가번호 · 이름 · 전화번호 · 소속연맹 · 소속단위대
///            (요구: "페런츠 인가사항 입력란을 멘토랑 동일한 폼으로 구성")
///
/// ## 동작
///  · 인가번호를 추가하면 **인적사항 입력 다이얼로그**가 뜬다(이름·전화 필수).
///  · 등록된 인적사항은 칩 라벨에 "이름 #번호" 로 표시된다.
///  · 칩 탭 → 인적사항 수정 / 삭제.
///  · 인적사항은 서버(/api/link/profiles)에 저장되며 아이디·비번이 생성된다.
class LinkCodeField extends StatefulWidget {
  const LinkCodeField({
    super.key,
    required this.label,
    required this.icon,
    required this.kind,
    required this.codes,
    required this.onChanged,
    this.editable = true,
    this.menteeNumber = '',
    this.defaultLeague = '',
    this.defaultUnit = '',
  });

  final String label; // '멘토' | '페런츠'
  final IconData icon;
  final String kind; // 'mentor' | 'parent'
  final List<String> codes; // 인가번호(멘토: 멘티 인가번호) 목록
  final ValueChanged<List<String>> onChanged;
  final bool editable;

  /// 멘토 등록 시 기본값으로 채워지는 멘티(본인)의 범인가자번호.
  final String menteeNumber;

  /// 페런츠 소속연맹이 비어있을 때 안내로 쓰는 **인가자(본인) 연맹**.
  /// (요구: "소속연맹 (없을시 인가자 연맹)" — 비었으면 본인 값으로 저장)
  final String defaultLeague;

  /// 페런츠 소속단위대가 비어있을 때 안내로 쓰는 **인가자(본인) 단위대**.
  /// (요구: "소속연맹 (없을시 인가자 단위대)" — 비었으면 본인 값으로 저장)
  final String defaultUnit;

  @override
  State<LinkCodeField> createState() => _LinkCodeFieldState();
}

class _LinkCodeFieldState extends State<LinkCodeField> {
  Map<String, dynamic> _profiles = {};

  NasApi get _nas => context.read<NasApi>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfiles());
  }

  Future<void> _loadProfiles() async {
    final p = await _nas.linkProfiles();
    if (!mounted) return;
    setState(() => _profiles = p);
  }

  String _clean(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Map<String, dynamic> _profileOf(String code) {
    final key = _clean(code);
    return (_profiles[key] as Map?)?.cast<String, dynamic>() ??
        (_profiles[code] as Map?)?.cast<String, dynamic>() ??
        {};
  }

  /// 전화번호 → 아이디/비번 미리보기 (서버 규칙과 동일).
  (String, String) _genCred(String phone) {
    final ph = _clean(phone);
    final last4 = ph.length >= 4 ? ph.substring(ph.length - 4) : ph;
    return (ph, last4.isEmpty ? '' : '$last4!@@');
  }

  Color get _accent =>
      widget.kind == 'parent' ? AppColors.taegeukBlue : AppColors.purple;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 18, color: _accent),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.kind == 'mentor'
                    ? '인가번호(멘티) · 인적사항(멘토)'
                    : '인가번호 · 인적사항(페런츠)',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textGray,
                ),
              ),
              const Spacer(),
              if (widget.editable)
                TextButton.icon(
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('추가', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (widget.codes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 24, bottom: 4),
              child: Text(
                '등록된 인가번호 없음 (복수 입력 가능)',
                style: TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final code in widget.codes) _chip(code)],
            ),
        ],
      ),
    );
  }

  Widget _chip(String code) {
    final p = _profileOf(code);
    final nm = '${p['name'] ?? ''}'.trim();
    final hasProfile = nm.isNotEmpty || '${p['phone'] ?? ''}'.trim().isNotEmpty;
    final noLabel = widget.kind == 'mentor' ? '멘티 #$code' : '#$code';
    final label = hasProfile ? '$nm  $noLabel' : noLabel;
    return InputChip(
      avatar: hasProfile
          ? Icon(Icons.verified_user, size: 15, color: _accent)
          : null,
      label: Text(label),
      backgroundColor: _accent.withValues(alpha: 0.08),
      labelStyle: TextStyle(
        color: _accent,
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
      ),
      onPressed: widget.editable ? () => _edit(code) : null,
      deleteIcon: widget.editable ? const Icon(Icons.close, size: 16) : null,
      onDeleted: widget.editable
          ? () {
              final next = List<String>.from(widget.codes)..remove(code);
              widget.onChanged(next);
            }
          : null,
    );
  }

  /// 인가번호 + 인적사항 입력/수정 다이얼로그.
  Future<void> _edit(String? existing) async {
    final prof = existing != null ? _profileOf(existing) : {};
    final isMentor = widget.kind == 'mentor';
    // 멘토 신규 등록 시 멘티(본인) 범인가자번호를 기본값으로 채운다.
    final noCtrl = TextEditingController(
      text: existing ?? (isMentor ? widget.menteeNumber : ''),
    );
    final nameCtrl = TextEditingController(text: '${prof['name'] ?? ''}');
    final phoneCtrl = TextEditingController(text: '${prof['phone'] ?? ''}');
    final leagueCtrl = TextEditingController(text: '${prof['league'] ?? ''}');
    final unitCtrl = TextEditingController(text: '${prof['unit'] ?? ''}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isEdit = existing != null;
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            final previewPhone = phoneCtrl.text;
            final (pid, ppw) = _genCred(previewPhone);
            return AlertDialog(
              title: Text(isMentor ? '멘토 인적사항 · 멘티 인가번호' : '페런츠 인가번호 · 인적사항'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: noCtrl,
                      enabled: !isEdit,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: isMentor ? '범인가자번호 (멘티) *' : '인가번호 *',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: isMentor ? '이름 (멘토) *' : '이름 (페런츠) *',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setDlg(() {}),
                      decoration: InputDecoration(
                        labelText: isMentor ? '전화번호 (멘토) *' : '전화번호 (페런츠) *',
                        hintText: '010-0000-0000',
                        isDense: true,
                      ),
                    ),
                    // 멘토·페런츠 **동일 폼** — 소속연맹·소속단위대.
                    //  (요구: "페런츠 인가사항 입력란을 멘토랑 동일한 폼으로 구성")
                    const SizedBox(height: 10),
                    TextField(
                      controller: leagueCtrl,
                      decoration: InputDecoration(
                        labelText: isMentor ? '소속연맹 (멘토)' : '소속연맹 (페런츠)',
                        // 요구: 페런츠는 비었을 때 인가자(본인) 연맹을 안내/저장.
                        hintText: widget.defaultLeague.isNotEmpty
                            ? '없을시 인가자 연맹: ${widget.defaultLeague}'
                            : '예: 서울남부 / 인천',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: unitCtrl,
                      decoration: InputDecoration(
                        labelText: isMentor ? '소속단위대 (멘토)' : '소속단위대 (페런츠)',
                        // 요구: 페런츠는 비었을 때 인가자(본인) 단위대를 안내/저장.
                        hintText: widget.defaultUnit.isNotEmpty
                            ? '없을시 인가자 단위대: ${widget.defaultUnit}'
                            : '예: 샘물지역대',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.scoutGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '전화번호로 아이디·비밀번호 자동 생성',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.scoutGreen,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '아이디 : ${pid.isEmpty ? '(전화번호 입력)' : pid}\n'
                            '비밀번호 : ${ppw.isEmpty ? '(전화번호 입력)' : ppw}',
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (isEdit)
                  TextButton(
                    onPressed: () async {
                      await _nas.linkProfileDelete(_clean(existing));
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx, true);
                    },
                    child: const Text(
                      '삭제',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true || !mounted) return;

    final code = _clean(noCtrl.text);
    if (code.isEmpty) return;
    final nm = nameCtrl.text.trim();
    final ph = phoneCtrl.text.trim();
    // 인적사항을 입력했으면 프로필 저장(아이디·비번 생성).
    if (nm.isNotEmpty || ph.isNotEmpty) {
      if (nm.isEmpty || ph.isEmpty) {
        _snack('이름과 전화번호를 모두 입력해야 인적사항이 저장됩니다.');
      } else {
        // 요구: 페런츠 소속연맹/단위대가 비면 **인가자(본인) 값**으로 채운다.
        //  ("소속연맹 (없을시 인가자 연맹)" / "소속연맹 (없을시 인가자 단위대)")
        var lg = leagueCtrl.text.trim();
        var un = unitCtrl.text.trim();
        if (!isMentor) {
          if (lg.isEmpty) lg = widget.defaultLeague.trim();
          if (un.isEmpty) un = widget.defaultUnit.trim();
        }
        final r = await _nas.linkProfileSave(
          profile: {
            'number': code,
            'name': nm,
            'phone': ph,
            'league': lg,
            'unit': un,
            'kind': widget.kind,
          },
        );
        if (r['ok'] == true) {
          final p =
              (r['profile'] as Map?)?.cast<String, dynamic>() ??
              {'number': code, 'name': nm, 'phone': ph};
          setState(() => _profiles[code] = p);
        } else {
          _snack('인적사항 저장 실패: ${r['error'] ?? ''}');
        }
      }
    }
    // 목록에 인가번호 반영.
    if (!widget.codes.contains(code)) {
      widget.onChanged([...widget.codes, code]);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
