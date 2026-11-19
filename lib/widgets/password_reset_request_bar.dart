import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 본인용 — "비밀번호를 분실한 경우 관리자·마스터에게 초기화를 요청" 안내 배너.
///
/// ## [turn71] 왜 이 위젯을 따로 만들었나
///  같은 배너가 `member_edit_screen` 과 `member_detail_screen` 에
///  **똑같이 복사**되어 있었다. 한쪽만 고치면 다른 쪽이 옛 색으로 남는다.
///  실제로 가독성 문제(아래)를 고칠 때 두 곳을 동시에 손대야 했다.
///
/// ## [turn71] 가독성 실측 (요구: "글자 가독성 좀 높여줘")
///  수정 전:
///   · 안내문 = `lifetimeGold(#B8860B)` on 금색 12% 배경 → **2.84:1**
///   · 버튼 글자 = `tigerGold(#F2B705)` on 같은 배경    → **1.59:1**
///   11pt 글씨에서 1.59:1 은 사실상 배경과 같은 밝기다. 화면에서
///   '있는데 안 읽히는' 상태였다 — 사용자 지적이 정확했다.
///
///  수정 후 (WCAG 본문 기준 4.5:1 이상):
///   · 안내문 = `warmInk(#A84307)` on `warmTint(#FDEDE3)` → **5.30:1**
///   · 버튼    = 흰 글자 on `warmOrange(#C74A0A)`        → **4.76:1**
///
/// ## 색만이 아니라 '형태'도 바꿨다
///  수정 전 초기화 요청은 **테두리만 있는 버튼(OutlinedButton)** 이었고
///  그 테두리 색이 배경과 거의 같아 버튼의 경계조차 보이지 않았다.
///  초기화 요청은 본인에게는 유일한 탈출구이므로 **채움 버튼**으로 올려
///  '누를 수 있는 것'임을 분명히 했다.
class PasswordResetRequestBar extends StatelessWidget {
  const PasswordResetRequestBar({
    super.key,
    required this.onRequest,
    this.text = '비밀번호를 분실한 경우 관리자·마스터에게 초기화를 요청하세요.',
    this.label = '비밀번호 초기화 요청',
  });

  final VoidCallback onRequest;
  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.warmTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.warmOrange.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.help_outline,
                  size: 16,
                  color: AppColors.warmOrange,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    // 작은 글씨라 배경 대비 5.3:1 인 warmInk 를 쓴다.
                    color: AppColors.warmInk,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warmOrange,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onRequest,
              icon: const Icon(Icons.send, size: 17),
              label: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}
