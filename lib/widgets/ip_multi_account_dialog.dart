import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// [turn65] 같은 IP 다계정 접속 경고 팝업.
///
/// ## 왜 만들었나 (요구 원문)
/*
 *  "동일 아이피로 다른 계정을 3개 이상 접속할 경우 경고창을 보내고
 *   승인창에 그 사실을 알림으로 알려줄 것 (특정 회원이 특정 아이피로 계속
 *   접속함, 그리고 어떤 아이디에 접속했었는지 노출할 것 — 개인정보 무단
 *   접속 우려 피해 방지)
 *   이런 경우 팝업창을 해당 접속자에게 띄어서 타인의 정보를 무단으로
 *   열람할 경우 관리자에게 해당 정보가 통보되며 불이익을 받을 수 있습니다
 *   라는 내용으로 통보해줘"
 *
 * ## 설계 의도
 *  · **차단이 아니라 통보**다. 가족·학교·사무실은 IP 를 정상적으로 공유하고,
 *    한 지도자가 여러 대원 계정을 확인해야 하는 업무도 있다.
 *    로그인 자체를 막으면 정상 사용자가 먼저 피해를 본다.
 *  · 그래서 "막았다"가 아니라 "기록되고 있다"를 분명히 알린다.
 *    억제 효과는 차단보다 이쪽이 크고, 분쟁도 줄어든다.
 *  · 문구(title/body/policy)는 **서버가 만든다**. 법적 고지를 앱 배포 없이
 *    고칠 수 있어야 하기 때문. 앱은 표시만 한다.
 */
Future<void> showIpMultiAccountDialog(
  BuildContext context,
  Map<String, dynamic> notice,
) {
  final accounts = (notice['accounts'] as List?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList() ??
      const <Map<String, dynamic>>[];
  final band = '${notice['band'] ?? ''}';
  final count = (notice['count'] as num?)?.toInt() ?? accounts.length;
  final window = (notice['windowMin'] as num?)?.toInt() ?? 15;
  final title = '${notice['title'] ?? '같은 회선에서 여러 계정이 접속했습니다'}';
  final body = '${notice['body'] ?? ''}';
  final policy = '${notice['policy'] ?? ''}';

  return showDialog<void>(
    context: context,
    barrierDismissible: false, // 반드시 읽고 닫게 한다(실수로 지나치지 않도록)
    builder: (ctx) {
      return AlertDialog(
        icon: const Icon(
          Icons.gpp_maybe_rounded,
          color: Color(0xFFB3261E),
          size: 34,
        ),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            height: 1.35,
          ),
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 1) 무슨 일이 있었는지 ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF3C6C1)),
                  ),
                  child: Text(
                    body.isNotEmpty
                        ? body
                        : '최근 $window분 동안 서로 다른 $count개의 계정으로 '
                              '접속한 기록이 있습니다.\n같은 회선: $band',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.65,
                      color: Color(0xFF5F1A14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── 2) 어떤 아이디로 접속했는지 (요구: 노출할 것) ──
                Row(
                  children: [
                    const Icon(Icons.manage_accounts,
                        size: 15, color: AppColors.textGray),
                    const SizedBox(width: 5),
                    Text(
                      '최근 $window분 · 같은 회선에서 접속한 계정 $count개',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...accounts.map((a) {
                  final ident = '${a['ident'] ?? ''}';
                  final name = '${a['name'] ?? ''}';
                  final tier = '${a['tier'] ?? ''}';
                  final cnt = (a['count'] as num?)?.toInt() ?? 1;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.purple.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ident.isEmpty ? '—' : ident,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: AppColors.purple,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            name.isEmpty ? '(이름 미확인)' : name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (tier.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              tier,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textGray,
                              ),
                            ),
                          ),
                        Text(
                          '$cnt회',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),

                // ── 3) 법적 고지 ──
                if (policy.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE8D9A8)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.gavel_rounded,
                            size: 15, color: Color(0xFF8A6A00)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            policy,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.6,
                              color: Color(0xFF6B5300),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                const Text(
                  '· 본인 계정만 이용해 주세요.\n'
                  '· 이 경고는 접속 기록을 근거로 자동 표시되며, 관리자에게도 '
                  '같은 내용이 통보됩니다.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                '내용을 확인했습니다',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
              ),
            ),
          ),
        ],
      );
    },
  );
}
