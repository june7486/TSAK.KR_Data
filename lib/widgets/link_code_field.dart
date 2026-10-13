import 'package:flutter/material.dart';
import 'marquee_text.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import 'confirm.dart';
import 'link_member_picker.dart';

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

  /// 저장키 접두어(종류별 복합키) — 서버와 동일 규칙.
  ///   멘토의 number = 멘티(본인) 번호, 페런츠의 number = 인가번호이므로
  ///   두 번호가 같아도 **서로 덮어쓰지 않도록** 종류 접두어를 붙여 저장/조회한다.
  String _prefix() => widget.kind == 'parent' ? '페런츠' : '멘토';

  /// 숫자 → 저장키 후보(복합키 우선 → 구(무접두어) 폴백).
  List<String> _keyCands(String code) {
    final d = _clean(code);
    return ['${_prefix()}:$d', d];
  }

  /// 인적사항 조회 — **종류별 복합키 우선**, 없으면 구(무접두어) 키 폴백.
  ///   · 페런츠 이름이 인가자 본인 이름으로 보이던 문제(요구)는 프로필을
  ///     우선 사용하는 것으로 해결한다.
  Map<String, dynamic> _profileOf(String code) {
    final p = _profiles;
    for (final k in _keyCands(code)) {
      final v = p[k];
      if (v is Map && v.isNotEmpty) return v.cast<String, dynamic>();
    }
    return {};
  }

  /// 전화번호 → 아이디/비번 미리보기 (서버 규칙과 동일).
  (String, String) _genCred(String phone) {
    final ph = _clean(phone);
    final last4 = ph.length >= 4 ? ph.substring(ph.length - 4) : ph;
    return (ph, last4.isEmpty ? '' : '$last4!@@');
  }

  Color get _accent =>
      widget.kind == 'parent' ? AppColors.taegeukBlue : AppColors.purple;

  /// 연결된 인가번호의 회원(명단) — 이름·소속(활동) 조회용.
  Member? _memberOf(String code) {
    final d = _clean(code);
    if (d.isEmpty) return null;
    return context.watch<AppState>().byNumber(d);
  }

  /// 인가번호 배지 — 은하회원은 '은하N', 그 외(범·미확인)는 '범#N'.
  String _numBadge(String code) {
    final d = _clean(code);
    final m = _memberOf(code);
    if (m != null && m.corps == 'eunha') return '은하$d';
    return '범#${d.isEmpty ? code : d}';
  }

  /// 소속정보 = **현재활동 등록정보**(없으면 인가시 값으로 폴백). (요구 #4)
  String _activityInfo(Member? m) {
    if (m == null) return '';
    final regL = m.regLeague.trim();
    final regU = m.regUnit.trim();
    final l = regL.isNotEmpty ? regL : m.league.trim();
    final u = regU.isNotEmpty ? regU : m.unit.trim();
    return [l, u].where((s) => s.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 16, color: _accent),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: MarqueeText(
                  widget.kind == 'mentor'
                      ? '인가번호(멘티=본인) · 이름(멘토=범을 배출한 대장) · 소속'
                      : '인가번호 · 이름(페런츠=범을 배출한 부모님) · 소속',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textGray,
                  ),
                ),
              ),
              const Spacer(),
              if (widget.editable)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: _accent,
                  ),
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('추가', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (widget.codes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
              child: Text(
                widget.kind == 'mentor'
                    ? '등록된 멘토(범을 배출한 대장) 없음 (복수 등록 가능)'
                    : '등록된 페런츠(범을 배출한 부모님) 없음 (복수 등록 가능)',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textGray,
                ),
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
      ),
    );
  }

  /// 표시용 [이름, 소속정보] — **멘토·페런츠 모두 인적사항 프로필을 우선**한다.
  ///   · 멘토: 저장 코드가 **멘티(본인) 번호**이므로, 회원 명단에서 이름을 찾으면
  ///     멘티(본인) 이름이 노출되는 오류가 있었다.
  ///     (요구: "멘토이름에는 범 인가자가 아니라 멘토의 이름과 소속을 노출해야 함")
  ///     → **멘토(범을 배출한 대장) 프로필** 이름·소속만 사용(명단 폴백 없음).
  ///   · 페런츠: 번호(인가번호)로 조회되는 회원은 **인가자 본인**일 수 있으므로,
  ///     회원 명단 이름을 먼저 쓰면 인가자(자녀) 이름이 노출된다.
  ///     (요구: "페런츠 항목에는 부모님 이름을 노출시킬 것")
  ///     → **부모님(페런츠) 프로필** 이름·소속을 우선, 없을 때만 명단으로 폴백.
  (String, String) _displayOf(String code) {
    final p = _profileOf(code);
    final pName = '${p['name'] ?? ''}'.trim();
    final pInfo = [
      '${p['league'] ?? ''}'.trim(),
      '${p['unit'] ?? ''}'.trim(),
    ].where((s) => s.isNotEmpty).join(' · ');
    if (pName.isNotEmpty || pInfo.isNotEmpty) return (pName, pInfo);
    // 멘토는 프로필이 없으면 명단 폴백을 쓰지 않는다(명단은 '멘티=본인'이라
    //  본인 이름이 노출되므로 오히려 오표시). 미입력 상태로 안내한다.
    if (widget.kind == 'mentor') return ('', '');
    // 페런츠는 프로필이 없을 때만 명단으로 폴백(소속정보는 현재활동 등록정보).
    final m = _memberOf(code);
    final nm = (m?.name ?? '').trim();
    if (nm.isNotEmpty) return (nm, _activityInfo(m));
    return ('', '');
  }

  /// 멘티 등록정보와 **동일한 형식** — [인가번호 배지] [이름 / 소속정보] [수정·삭제].
  ///   (요구: "멘토 정보도 멘티정보와 같은 형식으로 노출")
  Widget _row(String code) {
    final (nm, info) = _displayOf(code);
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
              _numBadge(code),
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
          if (widget.editable)
            IconButton(
              tooltip: '수정',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit, size: 16, color: AppColors.textGray),
              onPressed: () => _edit(code),
            ),
          if (widget.editable)
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
                  message: '${_numBadge(code)} 인가번호 연결을 삭제할까요?',
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
              // (요구) 키보드가 올라오면 창이 줄어들어 입력칸이 잘리고
              //  오버플로 에러가 나던 문제 → 내용을 **스크롤 가능**하게 하고,
              //  키보드(뷰인셋)만큼 **창을 위로 올려** 입력칸·버튼이 항상 보이게 한다.
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              title: Text(
                isMentor
                    ? '멘토 인적사항 · 본인(멘티) 인가번호'
                    : '페런츠 인적사항 (범을 배출한 부모님)',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 요구: 멘토=범을 배출한 대장 / 멘티=내가 만든 범 대원 —
                  //   혼동 방지를 위해 입력 항목의 의미를 먼저 안내한다.
                  if (isMentor)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.purple.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Text(
                        '멘토 = 이 회원(멘티)을 배출한 지도 대장입니다.\n'
                        '· 인가번호(멘티) : 이 회원 본인의 범 인가번호 (자동 입력)\n'
                        '· 이름(멘토) : 지도한 대장(멘토)의 이름·소속을 입력하세요.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.45,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  TextField(
                    controller: noCtrl,
                    enabled: !isEdit,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: isMentor
                          ? '본인(멘티) 범 인가번호 *'
                          // 요구: 페런츠가 범스카우트 인가자인 경우에만 입력(선택).
                          : '인가번호 (페런츠가 범스카우트일 경우 입력) (선택)',
                      hintText: isMentor ? null : '모르면 비워두세요 (선택사항)',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 요구: 멘토·페런츠 개인정보 입력 시 '범스카우트 인가정보 연동'
                  //   창(선택)으로 기존 인가자 정보를 불러와 자동 채운다.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _linkFromScout(
                        noCtrl,
                        nameCtrl,
                        phoneCtrl,
                        leagueCtrl,
                        unitCtrl,
                        setDlg,
                      ),
                      icon: const Icon(Icons.manage_search, size: 16),
                      label: const Text(
                        '범스카우트 인가정보 연동 (선택)',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: isMentor
                          ? '이름 (멘토 · 범을 배출한 대장) *'
                          : '이름 (페런츠 · 범을 배출한 부모님) *',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setDlg(() {}),
                    decoration: InputDecoration(
                      labelText: isMentor
                          ? '전화번호 (멘토) *'
                          : '전화번호 (페런츠 · 범을 배출한 부모님) *',
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
                  // 요구: 페런츠가 범스카우트 인가자인 경우 그 페이지(자녀대원)와
                  //   연동됨을 안내. 인가번호 입력은 **선택사항**이다.
                  if (!isMentor)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.tigerGold.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.tigerGold.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text(
                        '인가번호는 페런츠가 범스카우트 인가자일 때 입력합니다(선택).\n'
                        '인가번호를 입력하면 그 인가자 페이지의 [자녀대원 등록정보]에 '
                        '이 대원이 자동 연동됩니다.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  Column(
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
                ],
              ),
              actions: [
                if (isEdit)
                  TextButton(
                    onPressed: () async {
                      // (요구) 삭제 전 한 번 더 확인.
                      final ok = await confirmDialog(
                        ctx,
                        title: '인적사항 삭제',
                        message: '이 인적사항(아이디·비밀번호 포함)을 삭제할까요?',
                      );
                      if (!ok) return;
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
    final nm = nameCtrl.text.trim();
    final ph = phoneCtrl.text.trim();
    // 페런츠 인가번호는 **선택** — 비어 있어도 인적사항을 저장한다(요구).
    //  · 멘토: 인가번호(멘티=본인)는 필수 → 비면 저장하지 않음.
    if (isMentor && code.isEmpty) return;
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
            // 페런츠 인가번호가 없으면 이름 기반 임시 코드(9000xx)로 저장.
            'number': code.isNotEmpty
                ? code
                : (900000 + (nm.hashCode.abs() % 99999)).toString(),
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
          // 종류별 복합키('멘토:<번호>'/'페런츠:<번호>')로 로컬 캐시도 갱신 →
          //  멘토/페런츠 번호가 같아도 서로 덮어쓰지 않는다.
          final skey = '${p['_key'] ?? ''}'.trim().isNotEmpty
              ? '${p['_key']}'
              : '${_prefix()}:${p['number'] ?? code}';
          setState(() {
            _profiles[skey] = p;
            _profiles['${p['number'] ?? code}'] = p;
          });
        } else {
          _snack('인적사항 저장 실패: ${r['error'] ?? ''}');
        }
      }
    }
    // 목록에 인가번호 반영 — 페런츠 인가번호가 있을 때만.
    if (code.isNotEmpty && !widget.codes.contains(code)) {
      widget.onChanged([...widget.codes, code]);
    }
  }

  /// '범스카우트 인가정보 연동' (요구) — 기존 인가자를 검색해 인적사항을 채운다.
  ///   · 멘토: 번호칸은 **멘티(본인)번호**이므로 건드리지 않고, 이름·전화·소속만 채운다.
  ///   · 페런츠: 번호칸이 **페런츠 인가번호**이므로 번호까지 채운다.
  Future<void> _linkFromScout(
    TextEditingController noCtrl,
    TextEditingController nameCtrl,
    TextEditingController phoneCtrl,
    TextEditingController leagueCtrl,
    TextEditingController unitCtrl,
    void Function(void Function()) setDlg,
  ) async {
    final isMentor = widget.kind == 'mentor';
    final picked = await showLinkMemberPicker(
      context,
      nas: _nas,
      kind: widget.kind,
      hint: isMentor
          ? '멘토 본인의 인가정보를 선택하세요. (멘티 번호는 그대로 유지됩니다)'
          : '페런츠(범을 배출한 부모님)의 인가정보를 선택하세요. (인가번호까지 채워집니다)',
    );
    if (picked == null || !mounted) return;
    final name = '${picked['name'] ?? ''}'.trim();
    final phone = '${picked['phone'] ?? ''}'.trim();
    final league = '${picked['league'] ?? ''}'.trim();
    final unit = '${picked['unit'] ?? ''}'.trim();
    final number = '${picked['number'] ?? ''}'.trim();
    setDlg(() {
      if (name.isNotEmpty) nameCtrl.text = name;
      if (phone.isNotEmpty) phoneCtrl.text = phone;
      if (league.isNotEmpty) leagueCtrl.text = league;
      if (unit.isNotEmpty) unitCtrl.text = unit;
      // 멘토는 번호칸이 멘티(본인)번호이므로 연동 시 번호를 덮어쓰지 않는다.
      if (!isMentor && number.isNotEmpty) noCtrl.text = number;
    });
    _snack('인가정보를 불러왔습니다. 내용을 확인 후 저장하세요.');
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
