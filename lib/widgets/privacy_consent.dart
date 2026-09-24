import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 개인정보 수집·이용 및 제3자 제공 동의 (범용 표준 문구)
///
/// 개인정보보호법 제15조·제17조·제22조에 따른 표준 동의 항목을 담는다.
/// 인가자(범스카우트)·비인가자(일반회원) 저장/가입 시 체크가 필수이며,
/// [onChanged] 로 동의 여부를 상위 화면에 전달한다.
class PrivacyConsentField extends StatelessWidget {
  const PrivacyConsentField({
    super.key,
    required this.agreed,
    required this.onChanged,
    this.showTitle = true,
  });

  final bool agreed;
  final ValueChanged<bool> onChanged;
  final bool showTitle;

  /// 표준 개인정보 동의 문구 (수집·이용 + 제3자 제공 + 고유식별정보)
  static const String consentText = '''
한국범스카우트중앙회(이하 "중앙회")는 「개인정보 보호법」 제15조·제17조·제22조에 따라 회원(인가자·일반회원) 관리 및 청소년 활동 운영을 위하여 아래와 같이 개인정보를 수집·이용하고자 합니다.

1. 개인정보의 수집·이용 목적
 · 회원(인가자) 등록·관리 및 본인 확인
 · 청소년 활동(행사·연수·캠프) 운영 및 참가자 관리
 · 연간회비·참가비·후원금 납부 확인 및 환수
 · 단체 공지·안내문자(SMS)·이메일 발송
 · 통계 작성 및 대외 보고

2. 수집하는 개인정보 항목
 · 필수항목: 성명(실명), 인가번호, 소속 연맹·단위대, 연락처(휴대폰), 주소
 · 선택항목: 이메일, 생년월일, 기념일, 훈련현황, 사진, 멘토·보호자 정보

3. 개인정보의 보유·이용 기간
 · 회원 자격 유지 기간 및 탈퇴 후 3년 (관련 법령에 따른 보존 기간 준수)

4. 개인정보의 제3자 제공
 · 제공받는 자: 한국스카우트연맹 및 관계 기관
 · 제공 목적: 인가 확인, 활동 인증, 대외 공적 보고
 · 제공 항목: 성명, 인가번호, 소속, 활동 내역
 · 보유·이용 기간: 제공 목적 달성 시까지

5. 고유식별정보 및 사진(초상) 처리
 · 활동 기록·홍보 자료로 사진 및 영상이 촬영·활용될 수 있습니다.
 · 행사 사진·영상은 중앙회 NAS 서버에 보관되며, 참가자 및 인가자만 열람합니다.

6. 동의를 거부할 권리 및 불이익
 · 귀하는 위 개인정보 수집·이용 및 제3자 제공에 대한 동의를 거부할 권리가 있습니다.
 · 다만 필수항목 동의를 거부하는 경우 회원 등록 및 활동 참여가 제한될 수 있습니다.

※ 만 14세 미만 아동의 개인정보는 법정대리인(보호자)의 동의가 필요합니다.''';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle)
            Row(
              children: [
                const Icon(Icons.privacy_tip, color: AppColors.purple, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '개인정보 수집·이용 및 제3자 제공 동의',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          if (showTitle) const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.purple.withValues(alpha: 0.15)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  consentText.trim(),
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged(!agreed),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: agreed
                    ? AppColors.scoutGreen.withValues(alpha: 0.10)
                    : AppColors.taegeukRed.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: agreed
                      ? AppColors.scoutGreen.withValues(alpha: 0.6)
                      : AppColors.taegeukRed.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: Checkbox(
                      value: agreed,
                      activeColor: AppColors.scoutGreen,
                      onChanged: (v) => onChanged(v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      agreed
                          ? '개인정보 수집·이용 및 제3자 제공에 동의합니다'
                          : '개인정보 동의가 필요합니다 (필수) — 눌러서 동의',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: agreed
                            ? AppColors.scoutGreen
                            : AppColors.taegeukRed,
                      ),
                    ),
                  ),
                  Icon(
                    agreed ? Icons.verified : Icons.warning_amber_rounded,
                    color: agreed ? AppColors.scoutGreen : AppColors.taegeukRed,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
