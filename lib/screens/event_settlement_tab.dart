/// 행사 결산 탭 — 참가자 수 + 수입/지출 + 계좌별 지출을 한 화면에 정리.
///
/// ## 요구사항
/// "행사결산: 참가자 수(인가자, 리더, 로버, 비버, 스카우트, 벤처, 일반, 기타의
///  각 참가자 수 및 합산은 필수) · 참가비 · 후원금 · 후원 · 수송지원 등 ·
///  행사비지출(각종 지출·수품제작·기념품제작 등), 지출은 출금계좌(대표 3계좌 중
///  선택)도 선택 또는 직접입력"
///
/// "행사관리를 일목요연하게 정리하고 결산하며 관리될 수 있도록" — 그래서 이 탭은
/// ① 요약 카드(수입/지출/잔액) ② 참가자 수 표 ③ 분류별 지출 ④ 계좌별 지출
/// ⑤ 출력(옵션·미리보기·인쇄) 순으로 위에서 아래로 읽히게 배치한다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/event_settlement.dart';
import '../theme/app_theme.dart';

/// 결산 탭 본문.
class EventSettlementTab extends StatelessWidget {
  const EventSettlementTab({
    super.key,
    required this.year,
    required this.title,
    required this.attendees,
    required this.fees,
    required this.expenses,
    required this.onOutput,
    required this.onOutputAttendees,
  });

  final String year;
  final String title;
  final List<Map<String, dynamic>> attendees;
  final List<Map<String, dynamic>> fees;
  final List<Map<String, dynamic>> expenses;

  /// 결산 출력(옵션·미리보기 포함 공용 시트).
  final VoidCallback onOutput;

  /// 참가자 명단 출력.
  final VoidCallback onOutputAttendees;

  @override
  Widget build(BuildContext context) {
    final s = EventSettlement(
      title: title,
      year: year,
      attendeeCount: EventAttendeeBreakdown.fromAttendees(attendees),
      attendees: attendees,
      fees: fees.map((e) => EventMoneyRow.fromMap(e)).toList(),
      expenses: expenses
          .map((e) => EventMoneyRow.fromMap(e, expense: true))
          .toList(),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        _summaryCard(s),
        const SizedBox(height: 10),
        _attendeeCard(s),
        const SizedBox(height: 10),
        _incomeCard(s),
        const SizedBox(height: 10),
        _expenseCategoryCard(s),
        const SizedBox(height: 10),
        _expenseAccountCard(s),
        const SizedBox(height: 14),
        _outputRow(),
      ],
    );
  }

  // ---------------------------------------------------------------- 요약
  Widget _summaryCard(EventSettlement s) {
    final surplus = s.balance >= 0;
    return _card(
      icon: Icons.summarize_outlined,
      title: '결산 요약',
      color: AppColors.purple,
      child: Column(
        children: [
          Row(
            children: [
              _kpi('수입 계', s.incomeTotal, AppColors.scoutGreen),
              const SizedBox(width: 8),
              _kpi('지출 계', s.expenseTotal, AppColors.taegeukRed),
              const SizedBox(width: 8),
              _kpi(
                surplus ? '잔액' : '초과',
                s.balance.abs(),
                surplus ? AppColors.taegeukBlue : AppColors.taegeukRed,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '참가자 ${s.attendeeCount.total}명 · '
              '수입 ${s.fees.length}건 · 지출 ${s.expenses.length}건',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, int amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${EventSettlement.comma(amount)}원',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------- 참가자 수(필수)
  Widget _attendeeCard(EventSettlement s) {
    final b = s.attendeeCount;
    return _card(
      icon: Icons.groups_2_outlined,
      title: '참가자 수',
      color: AppColors.taegeukBlue,
      trailing: TextButton.icon(
        onPressed: attendees.isEmpty ? null : onOutputAttendees,
        icon: const Icon(Icons.print_outlined, size: 15),
        label: const Text('명단 출력', style: TextStyle(fontSize: 11.5)),
      ),
      child: Column(
        children: [
          // 필수 8종 + 합계 — 4열 그리드로 한눈에.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in b.ordered)
                _countChip(e.key, e.value, AppColors.taegeukBlue),
              _countChip('합계', b.total, AppColors.purple, strong: true),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              b.summaryLine,
              style: const TextStyle(fontSize: 10.5, color: AppColors.textGray),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countChip(String label, int v, Color color, {bool strong = false}) {
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: strong
            ? color.withValues(alpha: 0.12)
            : color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: color.withValues(alpha: strong ? 0.5 : 0.22),
          width: strong ? 1.3 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '$v',
            style: TextStyle(
              fontSize: strong ? 16 : 14.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 수입
  Widget _incomeCard(EventSettlement s) {
    return _card(
      icon: Icons.volunteer_activism_outlined,
      title: '수입 (참가비·후원금·후원·기타)',
      color: AppColors.scoutGreen,
      child: Column(
        children: [
          _moneyLine('참가비', s.feeTotal, AppColors.scoutGreen),
          _moneyLine('후원금', s.donationFund, AppColors.scoutGreen),
          _moneyLine('후원', s.donation, AppColors.scoutGreen),
          _moneyLine('기타수입', s.otherIncome, AppColors.textGray),
          const Divider(height: 14),
          _moneyLine(
            '수입 합계',
            s.incomeTotal,
            AppColors.scoutGreen,
            strong: true,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- 지출(분류별)
  Widget _expenseCategoryCard(EventSettlement s) {
    final byCat = s.expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _card(
      icon: Icons.payments_outlined,
      title: '행사비지출 (분류별)',
      color: AppColors.taegeukRed,
      child: byCat.isEmpty
          ? const Text(
              '지출 내역이 없습니다',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            )
          : Column(
              children: [
                for (final e in byCat)
                  _moneyLine(e.key, e.value, AppColors.taegeukRed),
                const Divider(height: 14),
                _moneyLine(
                  '지출 합계',
                  s.expenseTotal,
                  AppColors.taegeukRed,
                  strong: true,
                ),
              ],
            ),
    );
  }

  // ------------------------------------------------------- 지출(계좌별)
  Widget _expenseAccountCard(EventSettlement s) {
    final byAcct = s.expenseByAccount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _card(
      icon: Icons.account_balance_outlined,
      title: '지출 계좌별 (대표 3계좌)',
      color: AppColors.purple,
      child: byAcct.isEmpty
          ? const Text(
              '계좌가 지정된 지출이 없습니다\n'
              '지출 입력 시 출금계좌를 선택하면 여기에 집계됩니다',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            )
          : Column(
              children: [
                for (final e in byAcct)
                  _moneyLine(e.key, e.value, AppColors.purple),
              ],
            ),
    );
  }

  Widget _moneyLine(
    String label,
    int amount,
    Color color, {
    bool strong = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: strong ? 13 : 12.5,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
                color: strong ? color : AppColors.textDark,
              ),
            ),
          ),
          Text(
            '${EventSettlement.comma(amount)}원',
            style: TextStyle(
              fontSize: strong ? 14 : 12.5,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 출력
  Widget _outputRow() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.purple,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: onOutput,
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text(
              '결산 출력 (옵션·미리보기)',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.taegeukBlue,
              side: BorderSide(
                color: AppColors.taegeukBlue.withValues(alpha: 0.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: attendees.isEmpty ? null : onOutputAttendees,
            icon: const Icon(Icons.list_alt, size: 18),
            label: const Text(
              '참가자 명단 출력',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// 출금계좌 선택 도우미 — 대표 3계좌 중 선택 또는 직접입력.
///
/// (요구) "지출은 출금계좌(대표 3계좌 중 선택)도 선택 또는 직접입력할 수 있도록"
class EventAccountPicker extends StatelessWidget {
  const EventAccountPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowDirect = true,
  });

  /// 현재 선택된 계좌 표기('행사비 · 우리은행 1005-003-886274') 또는 직접입력 값.
  final String value;

  /// 선택/입력 결과 콜백.
  final ValueChanged<String> onChanged;

  /// 직접입력 허용 여부.
  final bool allowDirect;

  @override
  Widget build(BuildContext context) {
    // AppState 설정의 대표 계좌 목록(대표·수품구매·행사비).
    final accounts = context
        .watch<AppState>()
        .donations
        .map(
          (d) => EventAccount(
            label: '${d['label'] ?? ''}'.split('(').first.trim(),
            bank: '${d['bank'] ?? ''}',
            account: '${d['account'] ?? ''}',
          ),
        )
        .where((a) => a.isValid)
        .toList();

    final isPreset = accounts.any((a) => a.pickLabel == value);
    final sel = isPreset ? value : '__direct__';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: sel,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '출금계좌', isDense: true),
          items: [
            for (final a in accounts)
              DropdownMenuItem(
                value: a.pickLabel,
                child: Text(
                  a.pickLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            if (allowDirect)
              const DropdownMenuItem(
                value: '__direct__',
                child: Text('직접입력', style: TextStyle(fontSize: 12.5)),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            onChanged(v == '__direct__' ? '' : v);
          },
        ),
        if (!isPreset && allowDirect)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextFormField(
              initialValue: value,
              decoration: const InputDecoration(
                labelText: '출금계좌 직접입력',
                hintText: '예: 국민은행 123-456-789',
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12.5),
              onChanged: onChanged,
            ),
          ),
      ],
    );
  }
}
