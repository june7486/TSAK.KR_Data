import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';

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

  final codeCtrl = TextEditingController(
    text: code.isNotEmpty
        ? code
        : (isMentor ? selfNumber : ''),
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

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) {
        final ph = phoneCtrl.text;
        final digits = ph.replaceAll(RegExp(r'[^0-9]'), '');
        final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : '';
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
                  style: const TextStyle(fontSize: 12, color: AppColors.textGray),
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
                const SizedBox(height: 10),
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
                      const Text(
                        '자동 생성 계정 (전화번호 기반)',
                        style: TextStyle(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이름과 전화번호를 정확히 입력하세요')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: ${r['error'] ?? ''}')),
        );
      }
    }
    return r['ok'] == true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    }
    return false;
  }
}

String digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
