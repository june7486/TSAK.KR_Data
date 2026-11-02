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
  ///
  /// ## 2026-11-02 (build #574) 보강 — "입수한 정보에 대한 추가내용"
  ///  요구: "개인정보 활용 편집: 입수한 정보에 대한 추가내용을 넣어줘.
  ///        비밀번호, 사진, 인가정보 등등"
  ///
  ///  실제로 앱이 보관하는 항목을 빠짐없이 문구에 반영했다:
  ///   · **인가정보**(범인가번호·인가일·소속 연맹·등록 단위대·훈련현황·포상·
  ///     전문과정·ATAS 인가번호/인가일/영문명)
  ///   · **멘토·페런츠·멘티·자녀대원** 연결정보
  ///   · **비밀번호**(앱 로그인용 — 단방향/암호화 저장, 원문 미보관)
  ///   · **사진**(프로필 사진·활동 사진 — 초상권 포함)
  ///   · **주민등록번호**(고유식별정보 — 법 제24조의2 별도 동의, 뒷자리 마킹)
  static const String consentText = '''
한국범스카우트중앙회(이하 "중앙회")는 「개인정보 보호법」 제15조·제17조·제22조 및 제24조의2에 따라 회원(인가자·일반회원) 관리 및 청소년 활동 운영을 위하여 아래와 같이 개인정보를 수집·이용하고자 합니다.

1. 개인정보의 수집·이용 목적
 · 회원(인가자) 등록·관리 및 본인 확인
 · 청소년 활동(행사·연수·캠프) 운영 및 참가자 관리
 · 연간회비·참가비·후원금 납부 확인 및 환수
 · 단체 공지·안내문자(SMS)·이메일 발송
 · 통계 작성 및 대외 보고
 · 앱 로그인 계정 발급·관리 및 본인 확인(비밀번호)

2. 수집하는 개인정보 항목
 · 필수항목: 성명(실명), 인가번호, 소속 연맹·단위대, 연락처(휴대폰), 주소
 · 선택항목: 이메일, 생년월일, 기념일, 훈련현황, 사진·영상(초상), 멘토·페런츠 정보

 · [인가정보] 범스카우트 인가에 관한 정보 — 범인가번호, 인가일(인가 당시 날짜),
   인가 당시 소속 연맹·등록 단위대, 훈련현황(중급·상급·교수 등), 포상,
   전문과정 이수, 직위(현재활동), ATAS 인가번호·ATAS 인가일·영문(로마자) 이름
 · [연결정보] 멘토(범을 배출한 대장)·페런츠(부모)·멘티(내가 배출한 대원)·
   자녀대원의 인가번호 — 상호 등록·확인 및 인가 이력 관리 목적
 · [계정정보] 앱 로그인 아이디, 비밀번호 — 아래 6항의 비밀번호 관리 원칙에 따름
 · [사진] 프로필 사진 및 활동 사진(초상 포함) — 아래 5항의 사진 활용 동의에 따름
 · [고유식별정보] 주민등록번호 — 아래 4항에 따른 별도 동의 및 마킹 처리

3. 개인정보의 보유·이용 기간
 · 회원 자격 유지 기간 및 탈퇴 후 3년 (관련 법령에 따른 보존 기간 준수)

4. 주민등록번호(고유식별정보) 처리 — 「개인정보 보호법」 제24조의2
 · 수집 근거: 회원 본인 확인 및 인가 이력 관리(법령상 별도 동의)
 · 처리 방식
    - 저장 시 암호화하여 보관하며, 조회 권한을 마스터로 한정합니다.
    - **화면·개인카드·명부 등에 표시되는 주민등록번호는 뒷자리를 마킹**
      (예: 990328-1******) 하여 노출하지 않습니다.
    - 뒷자리 원본은 **마스터만** 확인할 수 있습니다.
 · 보유 기간: 회원 자격 유지 기간 및 탈퇴 후 3년, 이후 지체 없이 파기

5. 개인정보의 제3자 제공
 · 제공받는 자: 한국스카우트연맹 및 관계 기관
 · 제공 목적: 인가 확인, 활동 인증, 대외 공적 보고
 · 제공 항목: 성명, 인가번호, 소속, 활동 내역
 · 보유·이용 기간: 제공 목적 달성 시까지
 · 위 제공 항목에 주민등록번호·비밀번호는 포함되지 않습니다.

6. 비밀번호 관리 원칙
 · 앱 로그인용 비밀번호는 단방향/암호화로 저장하며 원문을 보관·표시하지 않습니다.
 · 비밀번호는 개인카드·명부·출력물에 표시되지 않습니다.
 · 아이디·비밀번호를 타인과 공유하지 않도록 하며, 분실 시 마스터에게 재발급을
   요청할 수 있습니다.
 · 시스템 관리자(마스터)는 계정 재설정을 위해 비밀번호를 초기화할 수 있으나,
   초기화 이전의 비밀번호 원문은 확인할 수 없습니다.

7. 사진(초상) 처리 · 사진 활용 동의
 · 청소년 활동(행사·연수·캠프) 중 사진 및 영상이 촬영될 수 있습니다.
 · 촬영된 사진·영상은 다음 목적으로 활용될 수 있습니다:
    - 행사·활동 기록 및 결과 보고, 인가자·참가자 열람(중앙회 NAS 서버 보관)
    - 중앙회 홍보·소식지·연간보고서 및 공식 홈페이지·네이버 카페 등 게시
    - 스카우트 활동 홍보 자료(포스터·영상·SNS 등) 제작
 · 사진·영상에는 참가자의 얼굴(초상)이 포함될 수 있으며, 위 활용에 동의합니다.
 · 프로필 사진은 앱의 개인카드·명부에 표시되며, 등록을 원하지 않으면 비워 둘 수 있습니다.
 · 원하지 않는 경우 촬영 전 담당자에게 알리거나, 게시 후 삭제를 요청할 수 있습니다.

8. 동의를 거부할 권리 및 불이익
 · 귀하는 위 개인정보 수집·이용 및 제3자 제공에 대한 동의를 거부할 권리가 있습니다.
 · 다만 필수항목 동의를 거부하는 경우 회원 등록 및 활동 참여가 제한될 수 있습니다.
 · 주민등록번호(4항) 동의를 거부하는 경우, 인가 이력 확인이 제한될 수 있습니다.

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
                const Icon(
                  Icons.privacy_tip,
                  color: AppColors.purple,
                  size: 20,
                ),
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
                border: Border.all(
                  color: AppColors.purple.withValues(alpha: 0.15),
                ),
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
