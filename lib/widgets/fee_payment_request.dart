import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'donation_accounts.dart';

/// 평생회비·연회비 '납부 요청' 공용 UI.
///
/// 요구사항:
///   · 회원은 스스로 평생회원으로 **지정**할 수 없다 → 대신 '요청'한다.
///   · 평생회비 요청: 납부 여부 = 오래전 납부(1년 이상) / 최근 납부(1년 내) /
///     납부예정(오늘)  · 연회비 요청: 납부완료 / 납부예정
///   · 납부자 이름(선택) + '인가자와 동일' 체크 시 인가자(본인) 이름 자동 입력.
///   · '지급납부' 버튼 → 중앙회 계좌 3개 창(송금·복사, 닫기 가능).

/// 납부 시점 라벨 — 요청 시트·승인 화면·내역 표시 공용.
String feeTimingLabel(String type, String timing) {
  if (type == 'lifetime') {
    return switch (timing) {
      'old' => '오래전 납부(1년 이상)',
      'recent' => '최근 납부(1년 내)',
      'due' => '납부예정(오늘)',
      _ => '',
    };
  }
  return switch (timing) {
    'paid' => '납부완료',
    'due' => '납부예정',
    _ => '',
  };
}

/// 타입 라벨 (요청 시트 제목용).
String _typeTitle(String type) =>
    type == 'lifetime' ? '평생회원 등록요청' : '연회비 납부 요청';

/// 평생회비·연회비 납부 요청 시트를 연다. 제출 성공 시 true.
///
/// [member] 대상 회원, [type] 'lifetime' | 'fee', [initialYear] 연회비 기본 연도.
Future<bool> showFeePaymentRequestSheet(
  BuildContext context, {
  required Member member,
  required String type,
  String initialYear = '',
}) async {
  final state = context.read<AppState>();
  final now = DateTime.now();
  final years = <String>{'2024', '2025', '2026', '2027', '${now.year}'}.toList()
    ..sort();
  String year = initialYear.trim();
  if (!years.contains(year)) {
    year = years.contains('${now.year}')
        ? '${now.year}'
        : (years.contains('2026') ? '2026' : years.last);
  }
  // 기본 납부 시점 — 평생: 최근 납부 / 연회비: 납부완료.
  String timing = type == 'lifetime' ? 'recent' : 'paid';
  final payerCtrl = TextEditingController(text: member.name);
  bool payerIsSelf = true;

  final submit = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final isLifetime = type == 'lifetime';
        final timingOptions = isLifetime
            ? const [
                ('old', '오래전 납부 (1년 이상)', Icons.history),
                ('recent', '최근 납부 (1년 내)', Icons.schedule),
                ('due', '납부예정 (오늘)', Icons.event_available),
              ]
            : const [
                ('paid', '납부완료', Icons.check_circle),
                ('due', '납부예정', Icons.event_available),
              ];
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isLifetime
                          ? Icons.workspace_premium
                          : Icons.card_membership,
                      color: isLifetime
                          ? AppColors.lifetimeGold
                          : AppColors.scoutGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_typeTitle(type)} — ${member.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '요청하면 관리자·마스터가 확인 후 승인합니다. '
                  '승인 시 ${isLifetime ? '평생회원 등록' : '연회비 납부 이력'}과 연동됩니다.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
                const SizedBox(height: 14),
                if (!isLifetime) ...[
                  DropdownButtonFormField<String>(
                    initialValue: year,
                    decoration: const InputDecoration(
                      labelText: '납부 연도',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: years
                        .map(
                          (y) => DropdownMenuItem(value: y, child: Text('$y년')),
                        )
                        .toList(),
                    onChanged: (v) => setSheet(() => year = v ?? year),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  isLifetime ? '평생회비 납부 여부' : '연회비 납부 여부',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...timingOptions.map((o) {
                      final sel = timing == o.$1;
                      final col = isLifetime
                          ? AppColors.lifetimeGold
                          : AppColors.scoutGreen;
                      return ChoiceChip(
                        selected: sel,
                        // 한 번 더 누르면 선택 취소(토글).
                        onSelected: (_) =>
                            setSheet(() => timing = sel ? '' : o.$1),
                        avatar: Icon(
                          o.$3,
                          size: 15,
                          color: sel ? Colors.white : col,
                        ),
                        label: Text(o.$2),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: sel ? Colors.white : AppColors.textDark,
                        ),
                        selectedColor: col,
                        backgroundColor: col.withValues(alpha: 0.10),
                        showCheckmark: false,
                      );
                    }),
                    // (요구) 선택취소 — 납부 여부 선택을 **명시적으로** 해제한다.
                    //  · 칩을 다시 눌러도 취소되지만, 취소 버튼을 별도로 노출한다.
                    ActionChip(
                      avatar: Icon(
                        Icons.backspace_outlined,
                        size: 15,
                        color: timing.isEmpty
                            ? AppColors.textGray
                            : AppColors.taegeukRed,
                      ),
                      label: const Text('선택취소'),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: timing.isEmpty
                            ? AppColors.textGray
                            : AppColors.textDark,
                      ),
                      backgroundColor: timing.isEmpty
                          ? Colors.black.withValues(alpha: 0.04)
                          : AppColors.taegeukRed.withValues(alpha: 0.10),
                      side: BorderSide(
                        color: timing.isEmpty
                            ? Colors.black.withValues(alpha: 0.12)
                            : AppColors.taegeukRed.withValues(alpha: 0.55),
                      ),
                      // 선택된 항목이 있을 때만 실제로 비운다.
                      onPressed: timing.isEmpty
                          ? null
                          : () => setSheet(() => timing = ''),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: payerCtrl,
                  enabled: !payerIsSelf,
                  decoration: const InputDecoration(
                    labelText: '납부자 이름 (선택)',
                    hintText: '입금자 이름 (인가자와 다르면 입력)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: payerIsSelf,
                  activeColor: AppColors.purple,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    '인가자와 동일 (본인 이름으로 자동 입력)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onChanged: (v) => setSheet(() {
                    payerIsSelf = v ?? false;
                    if (payerIsSelf) payerCtrl.text = member.name;
                  }),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.purple,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => showPaymentAccountsSheet(context),
                        icon: const Icon(
                          Icons.account_balance_wallet,
                          size: 17,
                        ),
                        label: const Text(
                          '지급납부 (계좌 보기)',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    // 납부 여부를 선택하지 않으면(칩을 한 번 더 눌러 취소) 제출 불가.
                    onPressed: timing.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.send, size: 18),
                    label: Text(
                      timing.isEmpty ? '납부 여부를 선택하세요' : '등록요청 제출',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  if (submit != true) {
    payerCtrl.dispose();
    return false;
  }

  final payer = payerIsSelf ? member.name : payerCtrl.text.trim();
  final date = (type == 'lifetime' && timing == 'due')
      ? '${now.year}-${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}'
      : '';
  final err = await state.submitMemberRequest(
    type: type,
    ident: member.number.isNotEmpty ? member.number : member.phone,
    year: type == 'fee' ? year : '',
    date: date,
    payer: payer,
    timing: timing,
    payerIsSelf: payerIsSelf,
  );
  payerCtrl.dispose();
  return err == null;
}

/// '지급납부' — 중앙회 계좌 3개 창(송금·복사·닫기). 어디서나 재사용.
Future<void> showPaymentAccountsSheet(
  BuildContext context, {
  String title = '지급납부 — 중앙회 계좌 (3개)',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet,
                  color: AppColors.purple,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text(
              '아래 계좌로 납부하실 수 있습니다. 「송금」으로 은행 앱을 열거나 '
              '「복사」로 계좌번호를 복사하세요.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            const DonationAccounts(fontSize: 12.5, showHolder: true),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.purple,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, size: 17),
                label: const Text(
                  '닫기',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
