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
/// ## 2026-10-31 7차 요구 (반영 완료)
///  · **인가일 · ATAS 인가번호 입력란 삭제** — 화면에서 감춘다.
///    저장은 계속 하되(기존 값 보존), 새 입력은 받지 않는다.
///  · **번호를 조회하면 현재 활동정보 자동 조회** — 멘토/페런츠가 범 인가자일 때
///    인가번호를 입력하는 순간 회원(명단)에서 찾아 이름·전화·소속·직위·활동·훈련을
///    자동으로 채운다. 이름으로도 찾을 수 있다(동명이인은 자동 채우지 않음).
///  · **자동생성계정 안내 명확화** — 멘토/페런츠 계정은 **전화번호로 자동 생성**됨을
///    폼 안에서 분명히 알린다(아이디=전화번호, 비밀번호=뒤 4자리+`!@@`).
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
    // 프로필이 없을 때의 폴백:
    //  · 멘토: 저장 코드가 **멘티(본인) 번호**이므로 명단 조회는 본인 이름이 된다.
    //    (a) 코드 == 본인 번호 → '내가 나의 멘토'는 불가능하므로 폴백하지 않음(빈값).
    //    (b) 코드가 다른 인가자 → 그 대장 이름으로 폴백(공유).
    if (widget.kind == 'mentor') {
      if (_clean(code) == _clean(widget.menteeNumber)) return ('', '');
      final mm = _memberOf(code);
      final mmn = (mm?.name ?? '').trim();
      if (mmn.isNotEmpty) return (mmn, _activityInfo(mm));
      return ('', '');
    }
    // 페런츠: 프로필이 없을 때만 명단으로 폴백(소속정보는 현재활동 등록정보).
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
    // [요구] 개인정보 상세 입력 — ① 범스카우트 인가 정보 / ② 현재 활동정보.
    var isScouter =
        (prof['isScouter'] == true) ||
        '${prof['scoutNo'] ?? ''}'.trim().isNotEmpty ||
        // 요구(2026-10-31): 인가일·ATAS 는 더 이상 입력받지 않는다.
        //  다만 **기존 저장분에 값이 있으면** 인가자로 판정해 스위치를 켠다
        //  (예전 데이터를 편집할 때 스위치가 꺼져 정보가 숨는 것을 막는다).
        '${prof['inductedAt'] ?? ''}'.trim().isNotEmpty ||
        '${prof['atasNo'] ?? ''}'.trim().isNotEmpty;
    final scoutNoCtrl = TextEditingController(text: '${prof['scoutNo'] ?? ''}');
    final inductedCtrl = TextEditingController(
      text: '${prof['inductedAt'] ?? ''}',
    );
    final atasCtrl = TextEditingController(text: '${prof['atasNo'] ?? ''}');
    final positionCtrl = TextEditingController(
      text: '${prof['position'] ?? ''}'.trim().isNotEmpty
          ? '${prof['position']}'
          : (isMentor ? '멘토(지도대장)' : '페런츠(보호자)'),
    );
    final activityCtrl = TextEditingController(
      text: '${prof['activity'] ?? ''}',
    );
    final trainingCtrl = TextEditingController(
      text: '${prof['trainingStatus'] ?? ''}',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isEdit = existing != null;
        // 섹션 헤더 (요구: '① 범스카우트 인가시 / ② 현재 활동정보' 구분).
        Widget secHdr(String text, IconData icon, Color color) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(color: color.withValues(alpha: 0.30), height: 1),
              ),
            ],
          ),
        );
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
                isMentor ? '멘토 인적사항 · 본인(멘티) 인가번호' : '페런츠 인적사항 (범을 배출한 부모님)',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 요구: 멘토 = 범을 배출한 지도대장 / 페런츠 = 범을 배출한 부모님.
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      isMentor
                          ? '멘토 = 이 회원(멘티)을 배출한 지도 대장입니다.\n'
                                '· 인가번호(멘티) : 이 회원 본인의 범 인가번호 (자동 입력)\n'
                                '· 아래 [① 범스카우트 인가]·[② 현재 활동정보]로 멘토(대장)의\n'
                                '  인적사항을 상세히 입력하세요.'
                          : '페런츠 = 이 회원(범)을 배출한 부모님입니다.\n'
                                '· 부모님이 범스카우트 인가자이면 [① 범스카우트 인가]에 입력\n'
                                '· 아래 [② 현재 활동정보]로 부모님의 인적사항을 상세히 입력',
                      style: const TextStyle(
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
                  // 요구: '범스카우트 인가정보 연동' — 기존 인가자 정보를 불러와
                  //   인가시 정보(인가일·ATAS·직위 등)까지 자동 채운다.
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
                        scoutNoCtrl: scoutNoCtrl,
                        inductedCtrl: inductedCtrl,
                        atasCtrl: atasCtrl,
                        positionCtrl: positionCtrl,
                        activityCtrl: activityCtrl,
                        trainingCtrl: trainingCtrl,
                        setScouter: (v) => isScouter = v,
                      ),
                      icon: const Icon(Icons.manage_search, size: 16),
                      label: const Text(
                        '범스카우트 인가정보 연동 (번호·이름으로 검색)',
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
                  const SizedBox(height: 14),
                  // ───────── ① 범스카우트 인가 정보 ─────────
                  secHdr(
                    '① 범스카우트 인가 정보',
                    Icons.verified_user_outlined,
                    _accent,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: isScouter,
                    activeThumbColor: _accent,
                    onChanged: (v) => setDlg(() => isScouter = v),
                    title: const Text(
                      '범스카우트 인가자',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      '인가자이면 인가번호를 입력하세요 (비인가면 끄세요)',
                      style: TextStyle(fontSize: 10.5, height: 1.3),
                    ),
                  ),
                  if (isScouter) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: scoutNoCtrl,
                      keyboardType: TextInputType.number,
                      // 요구(2026-10-31): "인가번호를 조회하면 현재 활동중인 정보가
                      //  조회되도록" — 번호를 입력하는 순간 기존 인가자 정보를 찾아
                      //  아래 [② 현재 활동정보]를 **자동으로 채운다**.
                      onChanged: (v) => _autoFillFromNumber(
                        v,
                        nameCtrl: nameCtrl,
                        phoneCtrl: phoneCtrl,
                        leagueCtrl: leagueCtrl,
                        unitCtrl: unitCtrl,
                        positionCtrl: positionCtrl,
                        activityCtrl: activityCtrl,
                        trainingCtrl: trainingCtrl,
                      ),
                      decoration: InputDecoration(
                        labelText: isMentor
                            ? '인가번호 (멘토 본인)'
                            : '인가번호 (페런츠 본인)',
                        hintText: '예: 2186 — 입력하면 활동정보가 자동 조회됩니다',
                        isDense: true,
                        helperText: '번호 또는 이름으로 조회 → 현재 활동정보 자동 입력',
                        helperMaxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '번호를 입력하면 기존 인가자의 현재 활동정보가 자동으로 채워집니다.\n'
                        '동명이인은 아래 [범스카우트 인가정보 연동]에서 이름으로 확인하세요.',
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // ───────── ② 현재 활동정보 ─────────
                  secHdr(
                    '② 현재 활동정보',
                    Icons.local_activity_outlined,
                    AppColors.scoutGreen,
                  ),
                  const SizedBox(height: 2),
                  TextField(
                    controller: leagueCtrl,
                    decoration: InputDecoration(
                      labelText: isMentor
                          ? '소속연맹 (멘토 · 현재 활동)'
                          : '소속연맹 (페런츠 · 현재 활동)',
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
                      labelText: isMentor
                          ? '소속단위대 (멘토 · 현재 활동)'
                          : '소속단위대 (페런츠 · 현재 활동)',
                      // 요구: 페런츠는 비었을 때 인가자(본인) 단위대를 안내/저장.
                      hintText: widget.defaultUnit.isNotEmpty
                          ? '없을시 인가자 단위대: ${widget.defaultUnit}'
                          : '예: 샘물지역대',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: positionCtrl,
                    decoration: const InputDecoration(
                      labelText: '직위 (현재 활동)',
                      hintText: '예: 지역대장 / 부장 / 교수 / 스텝',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: activityCtrl,
                    decoration: const InputDecoration(
                      labelText: '활동 상태',
                      hintText: '예: 활동중 / 휴직 / 은퇴',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: trainingCtrl,
                    decoration: const InputDecoration(
                      labelText: '훈련현황',
                      hintText: '중급 / 상급 / 커미셔너과정 / 부교수 / 교수',
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
                      // 요구(2026-10-31): "자동생성계정 → 멘토, 페런츠 추가시 전화번호
                      //  입력시 멘토 및 페런츠의 계정은 전화번호로 자동 생성됨"
                      Text(
                        isMentor
                            ? '자동 생성 계정 (멘토 · 전화번호 기반)'
                            : '자동 생성 계정 (페런츠 · 전화번호 기반)',
                        style: const TextStyle(
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
                      const SizedBox(height: 3),
                      Text(
                        '위 전화번호로 ${isMentor ? '멘토' : '페런츠'} 계정이 자동 생성됩니다. '
                        '따로 아이디를 만들 필요가 없습니다.',
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: AppColors.textGray,
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
            // [요구] ① 범스카우트 인가 정보
            'isScouter': isScouter,
            'scoutNo': _clean(scoutNoCtrl.text),
            'inductedAt': inductedCtrl.text.trim(),
            'atasNo': atasCtrl.text.trim(),
            // [요구] ② 현재 활동정보
            'position': positionCtrl.text.trim(),
            'activity': activityCtrl.text.trim(),
            'trainingStatus': trainingCtrl.text.trim(),
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

  /// 인가번호 입력 시 **자동 조회** — 현재 활동정보를 즉시 채운다.
  ///
  /// ## 요구 (원문 2026-10-31)
  /// > "멘토가 범스카우트일 경우 / 범스카우트 인가자일 경우 이름 또는 번호를
  /// >  조회하면 현재 활동중인 정보가 조회되도록 하는 시스템을 넣음"
  ///
  /// ## 왜 onChanged 인가
  ///  [범스카우트 인가정보 연동] 버튼은 **검색창을 한 번 더 거쳐야** 한다.
  ///  번호만 알고 있는 대장에게는 그 왕복이 번거롭고, 오타 확인도 늦다.
  ///  그래서 번호를 다 입력하는 순간 **자동으로** 회원을 찾아 채운다.
  ///
  /// ## 조회 순서
  ///  ① 범(tsak) 번호 → ② 은하 번호 → ③ 이름 **정확 일치**(동명이인은 채우지 않음:
  ///    잘못된 사람의 정보로 덮어쓰는 것이 빈 칸보다 위험하다)
  ///
  /// ## 덮어쓰기 규칙 (중요)
  ///  · **이름·전화·소속**은 찾았을 때만 채운다(빈 칸 유지 방지).
  ///  · **이미 값이 있는 칸은 건드리지 않는다** — 사용자가 고쳐 쓴 내용을
  ///    자동 조회가 지워버리면 안 된다.
  Future<void> _autoFillFromNumber(
    String raw, {
    required TextEditingController nameCtrl,
    required TextEditingController phoneCtrl,
    required TextEditingController leagueCtrl,
    required TextEditingController unitCtrl,
    required TextEditingController positionCtrl,
    required TextEditingController activityCtrl,
    required TextEditingController trainingCtrl,
  }) async {
    final code = _clean(raw);
    if (code.isEmpty) return;
    final m = _findMemberByCodeOrName(code);
    if (m == null) return;

    // 이미 값이 있는 칸은 보존한다(사용자 입력 우선).
    void fillIfEmpty(TextEditingController c, String v) {
      if (v.trim().isEmpty) return;
      if (c.text.trim().isNotEmpty) return;
      c.text = v.trim();
    }

    final lg = m.regLeague.trim().isNotEmpty ? m.regLeague : m.league;
    final un = m.regUnit.trim().isNotEmpty ? m.regUnit : m.unit;
    setState(() {
      fillIfEmpty(nameCtrl, m.name);
      fillIfEmpty(phoneCtrl, m.phone);
      fillIfEmpty(leagueCtrl, lg);
      fillIfEmpty(unitCtrl, un);
      fillIfEmpty(positionCtrl, m.position);
      fillIfEmpty(activityCtrl, m.activity);
      fillIfEmpty(trainingCtrl, m.trainingStatus);
    });
    _snack(
      '인가자 정보를 찾았습니다 — ${m.name} ${m.displayNumber}'
      '${lg.trim().isEmpty ? '' : ' · $lg'}',
    );
  }

  /// 번호 또는 **이름 정확 일치**로 회원을 찾는다.
  ///
  /// 동명이인이면 **찾지 않는다**(null) — 엉뚱한 사람의 정보를 채우는 것보다
  /// 사용자가 [범스카우트 인가정보 연동]에서 직접 고르는 편이 안전하다.
  Member? _findMemberByCodeOrName(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final state = context.read<AppState>();

    // ① 숫자 → 범(tsak) 우선, ② 없으면 은하.
    final digits = _clean(s);
    if (digits.isNotEmpty && RegExp(r'^[0-9]+$').hasMatch(digits)) {
      final tsak = state.byNumber(digits);
      if (tsak != null) return tsak;
      for (final m in state.allMembers) {
        if (m.corps == 'eunha' && _clean(m.number) == digits) return m;
      }
      return null;
    }

    // ③ 이름 정확 일치(공백 제거 후 비교). 동명이인은 제외.
    final key = s.replaceAll(RegExp(r'\s+'), '');
    final hits = <Member>[
      for (final m in state.allMembers)
        if (m.name.replaceAll(RegExp(r'\s+'), '') == key) m,
    ];
    return hits.length == 1 ? hits.first : null;
  }

  /// '범스카우트 인가정보 연동' (요구) — 기존 인가자를 검색해 인적사항을 채운다.
  ///   · 멘토: 번호칸은 **멘티(본인)번호**이므로 건드리지 않고, 이름·전화·소속만 채운다.
  ///   · 페런츠: 번호칸이 **페런츠 인가번호**이므로 번호까지 채운다.
  ///   · [요구] 인가시 정보(인가일·ATAS)·현재 활동정보(직위·활동·훈련)까지 채운다.
  Future<void> _linkFromScout(
    TextEditingController noCtrl,
    TextEditingController nameCtrl,
    TextEditingController phoneCtrl,
    TextEditingController leagueCtrl,
    TextEditingController unitCtrl,
    void Function(void Function()) setDlg, {
    TextEditingController? scoutNoCtrl,
    TextEditingController? inductedCtrl,
    TextEditingController? atasCtrl,
    TextEditingController? positionCtrl,
    TextEditingController? activityCtrl,
    TextEditingController? trainingCtrl,
    void Function(bool)? setScouter,
  }) async {
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
    final scoutNo = '${picked['scoutNo'] ?? ''}'.trim();
    final date = '${picked['date'] ?? ''}'.trim();
    final atas = '${picked['atasNo'] ?? ''}'.trim();
    final position = '${picked['position'] ?? ''}'.trim();
    final activity = '${picked['activity'] ?? ''}'.trim();
    final training = '${picked['trainingStatus'] ?? ''}'.trim();
    final regLeague = '${picked['regLeague'] ?? ''}'.trim();
    final regUnit = '${picked['regUnit'] ?? ''}'.trim();
    setDlg(() {
      if (name.isNotEmpty) nameCtrl.text = name;
      if (phone.isNotEmpty) phoneCtrl.text = phone;
      // 소속은 '현재 활동정보'(재적)를 우선 채운다(없으면 인가시 값).
      final lg = regLeague.isNotEmpty ? regLeague : league;
      final un = regUnit.isNotEmpty ? regUnit : unit;
      if (lg.isNotEmpty) leagueCtrl.text = lg;
      if (un.isNotEmpty) unitCtrl.text = un;
      // 멘토는 번호칸이 멘티(본인)번호이므로 연동 시 번호를 덮어쓰지 않는다.
      if (!isMentor && number.isNotEmpty) noCtrl.text = number;
      // ── ① 범스카우트 인가 정보 ──
      setScouter?.call(true);
      if (scoutNoCtrl != null && scoutNo.isNotEmpty) {
        scoutNoCtrl.text = scoutNo;
      }
      // 요구(2026-10-31): 인가일·ATAS 입력란은 **화면에서 삭제**했다.
      //  다만 기존에 저장된 값이 있으므로 **읽어온 값을 조용히 보존**한다
      //  (컨트롤러를 지우면 저장 시 빈 값으로 덮어써 데이터가 사라진다).
      if (inductedCtrl != null && inductedCtrl.text.trim().isEmpty) {
        if (date.isNotEmpty) inductedCtrl.text = date;
      }
      if (atasCtrl != null && atasCtrl.text.trim().isEmpty) {
        if (atas.isNotEmpty) atasCtrl.text = atas;
      }
      // ── ② 현재 활동정보 ──
      if (positionCtrl != null && position.isNotEmpty) {
        positionCtrl.text = position;
      }
      if (activityCtrl != null && activity.isNotEmpty) {
        activityCtrl.text = activity;
      }
      if (trainingCtrl != null && training.isNotEmpty) {
        trainingCtrl.text = training;
      }
    });
    _snack('인가정보를 불러왔습니다. 내용을 확인 후 저장하세요.');
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
