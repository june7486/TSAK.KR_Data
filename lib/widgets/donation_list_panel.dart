/// 후원 목록 — **후원자별 / 내역별** 분리 표시.
///
/// ## 요구사항 (그대로)
/// "대신 후원리스트에는 후원자와 후원내역을 별도로 정리할 것,
///  후원항목만 출력시 후원물품 혹은 금액에 대한 선택할 수 있도록 할 것."
///
/// ## 화면 구성
/// · 상단: 보기 전환(후원자별 ↔ 내역별) + 출력초점(물품중심 ↔ 금액중심 ↔ 둘 다)
/// · 요약: **후원금(수입)** 과 **현물후원** 을 두 줄로 분리 (절대 합치지 않음)
/// · 본문: 후원자 카드(여러 건이면 펼쳐 보기) 또는 분류 카드
///
/// 출력은 이 위젯이 아니라 부모(행사 상세)의 `onOutput(view, focus)` 로 넘긴다.
library;

import 'package:flutter/material.dart';

import '../services/donation_doc.dart';
import '../services/donation_kinds.dart';
import '../theme/app_theme.dart';

class DonationListPanel extends StatefulWidget {
  const DonationListPanel({
    super.key,
    required this.rows,
    required this.onOutput,
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
    this.won,
  });

  /// '후원·기타수입' 탭의 행 그대로(참가비 제외).
  final List<Map<String, dynamic>> rows;

  /// 출력 — 고른 보기/초점을 그대로 넘긴다.
  final void Function(DonationViewMode view, DonationFocus focus) onOutput;

  final void Function(Map<String, dynamic> row) onEdit;
  final Future<void> Function(Map<String, dynamic> row) onDelete;
  final VoidCallback onAdd;

  final String Function(int)? won;

  @override
  State<DonationListPanel> createState() => _DonationListPanelState();
}

class _DonationListPanelState extends State<DonationListPanel> {
  DonationViewMode _view = DonationViewMode.bySponsor;
  DonationFocus _focus = DonationFocus.both;
  final Set<String> _open = <String>{};

  String _won(int v) => widget.won?.call(v) ?? '${_comma(v)}원';

  static String _comma(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}$b';
  }

  List<DonationRow> get _all => widget.rows.map(DonationRow.fromMap).toList();

  List<DonationRow> get _donations =>
      _all.where((e) => !DonationKind.isNonDonation(e.category)).toList();

  List<DonationRow> get _cash => _donations.where((e) => e.isIncome).toList();

  List<DonationRow> get _sponsors =>
      _donations.where((e) => e.isSponsor).toList();

  @override
  Widget build(BuildContext context) {
    final cash = _cash;
    final sponsors = _sponsors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(),
        _summaryBar(cash, sponsors),
        const SizedBox(height: 2),
        Expanded(
          child: sponsors.isEmpty
              ? const Center(
                  child: Text(
                    '현물후원 내역이 없습니다',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                )
              : _view == DonationViewMode.bySponsor
              ? _sponsorList(sponsors)
              : _kindList(sponsors),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ 도구
  Widget _toolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.tigerGold,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: widget.onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    '후원 추가',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.tigerGold,
                  side: BorderSide(
                    color: AppColors.tigerGold.withValues(alpha: 0.55),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onPressed: () => widget.onOutput(_view, _focus),
                icon: const Icon(Icons.print_outlined, size: 17),
                label: const Text(
                  '출력',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.people_alt_outlined,
                size: 13,
                color: AppColors.textGray,
              ),
              const SizedBox(width: 4),
              for (final v in DonationViewMode.values) ...[
                _chip(
                  label: v.label,
                  active: _view == v,
                  onTap: () => setState(() => _view = v),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.tune, size: 13, color: AppColors.textGray),
              const SizedBox(width: 4),
              // (요구) '후원물품 혹은 금액' 선택 — 출력 초점.
              for (final f in DonationFocus.values) ...[
                _chip(
                  label: f.label,
                  active: _focus == f,
                  onTap: () => setState(() => _focus = f),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              Text(
                _view == DonationViewMode.bySponsor ? '후원자별' : '내역별',
                style: const TextStyle(fontSize: 10, color: AppColors.textGray),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final c = active ? AppColors.tigerGold : AppColors.textGray;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: active ? 0.14 : 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: active ? 0.6 : 0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 요약
  Widget _summaryBar(List<DonationRow> cash, List<DonationRow> sponsors) {
    final cashSum = cash.fold<int>(0, (s, e) => s + e.amount);
    final sCash = sponsors.fold<int>(0, (s, e) => s + e.amount);
    final sValue = sponsors.fold<int>(0, (s, e) => s + e.value);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Column(
        children: [
          // 수입으로 잡히는 것 — 후원금만.
          _sumRow(
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.scoutGreen,
            label: '후원금(수입)',
            count: cash.length,
            value: _won(cashSum),
            note: '수입에 합산',
          ),
          const SizedBox(height: 3),
          // 수입에 넣지 않는 것 — 현물후원. 금액과 상당을 **따로**.
          _sumRow(
            icon: Icons.card_giftcard,
            color: AppColors.tigerGold,
            label: '현물후원',
            count: sponsors.length,
            value: '${_won(sCash)} + 상당 ${_won(sValue)}',
            note: '수입 미포함',
          ),
        ],
      ),
    );
  }

  Widget _sumRow({
    required IconData icon,
    required Color color,
    required String label,
    required int count,
    required String value,
    required String note,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$count건',
            style: const TextStyle(fontSize: 10.5, color: AppColors.textGray),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              note,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- 후원자별
  Widget _sponsorList(List<DonationRow> sponsors) {
    final map = <String, List<DonationRow>>{};
    for (final e in sponsors) {
      map.putIfAbsent('${e.name}|${e.number}', () => []).add(e);
    }
    final keys = map.keys.toList()
      ..sort((a, b) {
        final ra = map[a]!;
        final rb = map[b]!;
        final va = ra.fold<int>(0, (s, e) => s + e.amount + e.value);
        final vb = rb.fold<int>(0, (s, e) => s + e.amount + e.value);
        final c = vb.compareTo(va);
        return c != 0 ? c : a.compareTo(b);
      });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final key = keys[i];
        final items = map[key]!;
        final first = items.first;
        final open = _open.contains(key);
        final cash = items.fold<int>(0, (s, e) => s + e.amount);
        final value = items.fold<int>(0, (s, e) => s + e.value);
        final kinds = <String>{for (final e in items) e.kind.label};

        return Card(
          margin: const EdgeInsets.only(bottom: 7),
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() {
                  if (open) {
                    _open.remove(key);
                  } else {
                    _open.add(key);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.tigerGold.withValues(
                          alpha: 0.18,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: AppColors.tigerGold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    first.name.isEmpty ? '(이름 없음)' : first.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (first.number.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '#${first.number}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppColors.textGray,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 1),
                            Text(
                              // (요구) 후원자와 후원내역을 **별도로** 정리.
                              '${kinds.join('·')} · ${items.length}건',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (cash > 0)
                            Text(
                              _won(cash),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textDark,
                              ),
                            ),
                          if (value > 0)
                            Text(
                              '상당 ${_won(value)}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.tigerGold,
                              ),
                            ),
                        ],
                      ),
                      Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: AppColors.textGray,
                      ),
                    ],
                  ),
                ),
              ),
              if (open)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                  decoration: BoxDecoration(
                    color: AppColors.bg.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    children: [
                      for (var k = 0; k < items.length; k++)
                        _itemLine(items[k], k + 1),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _itemLine(DonationRow e, int no) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$no.',
            style: const TextStyle(fontSize: 10.5, color: AppColors.textGray),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.tigerGold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              e.kind.label,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: AppColors.tigerGold,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              e.itemText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            e.displayAmount,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          _rowMenu(e),
        ],
      ),
    );
  }

  Widget _rowMenu(DonationRow e) {
    final row = widget.rows.firstWhere(
      (r) =>
          '${r['name'] ?? ''}'.trim() == e.name &&
          '${r['category'] ?? ''}'.trim() == e.category &&
          '${r['item'] ?? ''}'.trim() == e.item &&
          ((r['amount'] as num?)?.toInt() ?? 0) == e.amount,
      orElse: () => const {},
    );
    if (row.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 16,
      icon: const Icon(Icons.more_vert, color: AppColors.textGray),
      onSelected: (v) async {
        if (v == 'edit') widget.onEdit(row);
        if (v == 'del') await widget.onDelete(row);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('수정')),
        PopupMenuItem(value: 'del', child: Text('삭제')),
      ],
    );
  }

  // --------------------------------------------------------------- 내역별
  Widget _kindList(List<DonationRow> sponsors) {
    final order = <DonationKind>[
      DonationKind.meal,
      DonationKind.goods,
      DonationKind.vehicle,
      DonationKind.etc,
    ];
    final map = <DonationKind, List<DonationRow>>{};
    for (final e in sponsors) {
      map.putIfAbsent(e.kind, () => []).add(e);
    }
    final kinds = order.where(map.containsKey).toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
      itemCount: kinds.length,
      itemBuilder: (_, i) {
        final k = kinds[i];
        final items = map[k]!;
        final cash = items.fold<int>(0, (s, e) => s + e.amount);
        final value = items.fold<int>(0, (s, e) => s + e.value);
        final names = items
            .map((e) => e.name)
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();

        return Card(
          margin: const EdgeInsets.only(bottom: 7),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.tigerGold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        k.label,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.tigerGold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${items.length}건',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textGray,
                      ),
                    ),
                    const Spacer(),
                    if (cash > 0)
                      Text(
                        _won(cash),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textDark,
                        ),
                      ),
                    if (cash > 0 && value > 0)
                      const Text(
                        ' · ',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textGray,
                        ),
                      ),
                    if (value > 0)
                      Text(
                        '상당 ${_won(value)}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.tigerGold,
                        ),
                      ),
                  ],
                ),
                if (names.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    // (요구) 내역 옆에 후원자를 별도 표기.
                    '후원자: ${names.join(', ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                for (var j = 0; j < items.length; j++)
                  _itemLine(items[j], j + 1),
              ],
            ),
          ),
        );
      },
    );
  }
}
