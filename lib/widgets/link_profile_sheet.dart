import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import 'tsak_name_lookup.dart';

/// 멘토 · 페런츠 **인적사항 입력/수정 시트**.
///
/// ## 요구
///  · "멘토 및 페런츠를 수동으로 입력할 경우 인적사항 넣도록 할 것
///     (그리고 통계에 포함하고, 각각 전화번호로 아이디 패스워드 이름 생성할 것)"
///  · "등록되어 있는 분들의 카드가 작성되어야 함 … 작성항목을 노출시키고"
///  · "범스카우트 인가자 여부확인 → 인가자일 경우 인가자 정보에 멘토·멘티·페런츠
///     정보 추가 입력 / 비인가자일 경우 멘토 및 페런츠 등록 페이지 노출
///     → 아이디: 전화번호 / 비번: 뒤 4자리"
///
/// ## 저장 위치
///  서버 `/api/link/profiles` — `link_profiles.json` (종류별 복합키 `멘토:<번호>` /
///  `페런츠:<번호>`). 저장 시 전화번호 기반 아이디·비밀번호가 생성된다.
Future<bool> showLinkProfileSheet(
  BuildContext context, {
  required String kind, // 'mentor' | 'parent'
  required String code, // 멘토: 멘티(본인)번호 / 페런츠: 페런츠 인가번호
  Map<String, dynamic> profile = const {},
  String defaultLeague = '',
  String defaultUnit = '',
  bool codeEditable = false,
  String selfNumber = '',
}) async {
  final nas = context.read<NasApi>();
  final isMentor = kind == 'mentor';
  // [요구 ①] 전체 인가자 명부를 이름으로 조회해 고르는 기능은 **마스터·관리자
  // 전용**이다. 개인 로그인에 열어 주면 인가자 개인정보를 아무나 훑을 수 있다.
  final state = context.read<AppState>();
  final canLookup = tsakIsAdminViewer(state);

  final codeCtrl = TextEditingController(
    text: code.isNotEmpty ? code : (isMentor ? selfNumber : ''),
  );
  final nameCtrl = TextEditingController(text: '${profile['name'] ?? ''}');
  final phoneCtrl = TextEditingController(text: '${profile['phone'] ?? ''}');
  final leagueCtrl = TextEditingController(
    text: '${profile['league'] ?? ''}'.trim().isNotEmpty
        ? '${profile['league']}'
        : defaultLeague,
  );
  final unitCtrl = TextEditingController(
    text: '${profile['unit'] ?? ''}'.trim().isNotEmpty
        ? '${profile['unit']}'
        : defaultUnit,
  );
  // [요구] 개인정보 상세 입력 — ① 범스카우트 인가 정보 / ② 현재 활동정보.
  var isScouter =
      (profile['isScouter'] == true) ||
      '${profile['scoutNo'] ?? ''}'.trim().isNotEmpty ||
      '${profile['inductedAt'] ?? ''}'.trim().isNotEmpty ||
      '${profile['atasNo'] ?? ''}'.trim().isNotEmpty;
  final scoutNoCtrl = TextEditingController(
    text: '${profile['scoutNo'] ?? ''}',
  );
  // 인가일 · ATAS 인가번호 (요구 ② 로 화면에서 감췄다) —
  //  저장 키는 살려 둔다. 기존에 적힌 값이 저장 한 번에 지워지면 안 된다.
  //  (값이 비어 있으면 저장 시 빈 문자열로 무해하게 넘어간다.)
  final inductedCtrl = TextEditingController(
    text: '${profile['inductedAt'] ?? ''}',
  );
  final atasCtrl = TextEditingController(text: '${profile['atasNo'] ?? ''}');
  final positionCtrl = TextEditingController(
    text: '${profile['position'] ?? ''}'.trim().isNotEmpty
        ? '${profile['position']}'
        : (isMentor ? '멘토(지도대장)' : '페런츠(보호자)'),
  );
  final activityCtrl = TextEditingController(
    text: '${profile['activity'] ?? ''}',
  );
  final trainingCtrl = TextEditingController(
    text: '${profile['trainingStatus'] ?? ''}',
  );

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) {
        final ph = phoneCtrl.text;
        final digits = ph.replaceAll(RegExp(r'[^0-9]'), '');
        final last4 = digits.length >= 4
            ? digits.substring(digits.length - 4)
            : '';
        // [요구 ①] 마스터·관리자가 인가자를 고르면 **현재 활동정보 자동 입력**.
        //  빈 칸만 채운다 — 이미 손으로 적은 값(예: 페런츠 직위)을 덮지 않는다.
        void fillIfEmpty(TextEditingController c, String v) {
          final t = v.trim();
          if (t.isEmpty) return;
          if (c.text.trim().isNotEmpty) return;
          c.text = t;
        }

        void fillFromMember(Member m) {
          final lg = m.regLeague.trim().isNotEmpty ? m.regLeague : m.league;
          final un = m.regUnit.trim().isNotEmpty ? m.regUnit : m.unit;
          fillIfEmpty(nameCtrl, m.name);
          fillIfEmpty(phoneCtrl, m.phone);
          fillIfEmpty(leagueCtrl, lg);
          fillIfEmpty(unitCtrl, un);
          fillIfEmpty(positionCtrl, m.position);
          fillIfEmpty(activityCtrl, m.activity);
          fillIfEmpty(trainingCtrl, m.trainingStatus);
          // 인가일·ATAS 는 화면에서 감췄지만, 조회해 온 값이 있으면 살려 둔다.
          fillIfEmpty(inductedCtrl, m.date);
          fillIfEmpty(atasCtrl, m.atasNo);
        }

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
        return AlertDialog(
          scrollable: true,
          title: Row(
            children: [
              Icon(
                isMentor ? Icons.school : Icons.family_restroom,
                color: AppColors.purple,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(isMentor ? '멘토 인적사항' : '페런츠 인적사항'),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMentor
                      ? '범스카우트를 배출한 대장(멘토)의 인적사항을 입력하세요.'
                      : '범스카우트를 배출한 부모님(페런츠)의 인적사항을 입력하세요.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
                const SizedBox(height: 12),
                if (codeEditable)
                  TextField(
                    controller: codeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: isMentor ? '멘티(본인) 인가번호' : '페런츠 인가번호 (선택)',
                      helperText: isMentor
                          ? '멘토는 본인 번호로 연결됩니다'
                          : '부모님이 인가자인 경우 입력',
                    ),
                  ),
                if (codeEditable) const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '이름 (실명)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setDlg(() {}),
                  decoration: const InputDecoration(labelText: '전화번호'),
                ),
                const SizedBox(height: 14),
                // ───────── ① 범스카우트 인가 정보 ─────────
                secHdr(
                  '① 범스카우트 인가 정보',
                  Icons.verified_user_outlined,
                  AppColors.purple,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: isScouter,
                  activeThumbColor: AppColors.purple,
                  onChanged: (v) => setDlg(() => isScouter = v),
                  // [요구 ③] 스위치 문구를 '멘토(페런츠)가 범인가인 경우' 로 바꿨다.
                  title: const Text(
                    '멘토(페런츠)가 범인가인 경우',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    '인가자이면 인가번호를 입력하세요 (비인가면 끄세요)',
                    style: TextStyle(fontSize: 10.5, height: 1.3),
                  ),
                ),
                if (isScouter) ...[
                  const SizedBox(height: 6),
                  if (canLookup)
                    // 마스터·관리자 — 이름/번호로 조회해 **이름을 선택**하고,
                    //  고른 인가자의 현재 활동정보를 자동으로 채운다.
                    TsakMemberLookupField(
                      controller: scoutNoCtrl,
                      label: isMentor
                          ? '인가번호 (멘토 본인 · 이름/번호 조회)'
                          : '인가번호 (페런츠 본인 · 이름/번호 조회)',
                      hint: '예: 2186 또는 김범수',
                      helper: '이름을 선택하면 현재 활동정보가 자동 입력됩니다',
                      onPicked: (m) => setDlg(() => fillFromMember(m)),
                    )
                  else
                    // 개인 로그인 — 개인정보 노출 위험이 있어 기존처럼 직접 입력.
                    TextField(
                      controller: scoutNoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: isMentor
                            ? '인가번호 (멘토 본인)'
                            : '인가번호 (페런츠 본인)',
                        hintText: '예: 2186',
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: leagueCtrl,
                        decoration: const InputDecoration(labelText: '소속연맹'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: unitCtrl,
                        decoration: const InputDecoration(labelText: '소속단위대'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: positionCtrl,
                  decoration: const InputDecoration(
                    labelText: '직위 (현재 활동)',
                    hintText: '예: 지역대장 / 부장 / 교수 / 스텝',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: activityCtrl,
                  decoration: const InputDecoration(
                    labelText: '활동 상태',
                    hintText: '예: 활동중 / 휴직 / 은퇴',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: trainingCtrl,
                  decoration: const InputDecoration(
                    labelText: '훈련현황',
                    hintText: '중급 / 상급 / 커미셔너과정 / 부교수 / 교수',
                  ),
                ),
                if (!canLookup) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '개인 로그인에서는 인가자 명부를 이름으로 조회할 수 없습니다.\n'
                    '인가번호와 활동정보를 직접 입력해 주세요.',
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.35,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // 아이디/비번 미리보기 (전화번호 → 아이디, 뒤 4자리 → 비번)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.taegeukBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.taegeukBlue.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '자동 생성 계정 (${isMentor ? '멘토' : '페런츠'} · 전화번호 기반)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.taegeukBlue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '아이디: ${digits.isEmpty ? '(전화번호 입력)' : digits}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      Text(
                        '비밀번호: ${last4.isEmpty ? '(뒤 4자리)' : '$last4!@@'}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '위 전화번호로 ${isMentor ? '멘토' : '페런츠'} 계정이 자동 생성됩니다.\n'
                        '따로 아이디를 만들 필요가 없습니다.',
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장'),
            ),
          ],
        );
      },
    ),
  );

  if (saved != true) return false;

  final nm = nameCtrl.text.trim();
  final ph = phoneCtrl.text.trim();
  if (nm.isEmpty || ph.isEmpty || digits(ph).length < 7) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이름과 전화번호를 정확히 입력하세요')));
    }
    return false;
  }
  var lg = leagueCtrl.text.trim();
  var un = unitCtrl.text.trim();
  if (lg.isEmpty) lg = defaultLeague.trim();
  if (un.isEmpty) un = defaultUnit.trim();
  var c = codeCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
  if (c.isEmpty) {
    // 인가번호가 없으면 이름 해시 기반 임시코드(9000xx)로 저장.
    c = (900000 + (nm.hashCode.abs() % 99999)).toString();
  }
  try {
    final r = await nas.linkProfileSave(
      profile: {
        'number': c,
        'name': nm,
        'phone': ph,
        'league': lg,
        'unit': un,
        'kind': kind,
        // [요구] ① 범스카우트 인가 정보
        'isScouter': isScouter,
        'scoutNo': scoutNoCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        'inductedAt': inductedCtrl.text.trim(),
        'atasNo': atasCtrl.text.trim(),
        // [요구] ② 현재 활동정보
        'position': positionCtrl.text.trim(),
        'activity': activityCtrl.text.trim(),
        'trainingStatus': trainingCtrl.text.trim(),
      },
    );
    if (context.mounted) {
      if (r['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${isMentor ? '멘토' : '페런츠'} 인적사항을 저장했습니다 '
              '(아이디 ${r['loginId'] ?? ''})',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: ${r['error'] ?? ''}')));
      }
    }
    return r['ok'] == true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
    return false;
  }
}

String digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
