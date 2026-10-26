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

  /// 삭제 — 성공 여부를 돌려준다. `false` 면 화면에서 실패를 알린다.
  final Future<bool> Function(Map<String, dynamic> row) onDelete;
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

    // ── [버그 수정 2026-10-26] 목록이 통째로 사라지던 문제 ────────────────
    //
    //  이 패널은 내부에 `Expanded` + `ListView` 를 가진 '스스로 높이를 채우는'
    //  위젯이다. 그런데 호출부에서 **높이가 무한(unbounded)** 인 곳
    //  (예: 스크롤 영역 안, Column 의 비-flex 자식)에 넣으면
    //  Expanded/ListView 가 높이를 계산하지 못해 릴리스 빌드에서
    //  **아무것도 그리지 않았다**(예외 없이 조용히). 사용자에게는
    //  "요약은 보이는데 상세 내역이 없다"로 나타났다.
    //
    //  해결: 부모가 준 제약을 확인해
    //   · 높이가 유한하면 → 남은 높이를 채우는 고정 헤더 + 스크롤 목록
    //   · 무한하면       → 헤더/목록을 **하나의 스크롤 뷰**로 합쳐 그린다
    //     (이때 목록은 shrinkWrap + 물리 스크롤 없음)
    return LayoutBuilder(
      builder: (context, c) {
        final bounded = c.maxHeight.isFinite;
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(),
            _summaryBar(cash, sponsors),
            const SizedBox(height: 2),
          ],
        );
        final empty = const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(
              '현물후원 내역이 없습니다',
              style: TextStyle(color: AppColors.textGray),
            ),
          ),
        );

        if (!bounded) {
          // 높이 제약이 없는 곳 — 전체를 하나의 스크롤로.
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                if (sponsors.isEmpty)
                  empty
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _view == DonationViewMode.bySponsor
                        ? _sponsorList(sponsors, scrollable: false)
                        : _kindList(sponsors, scrollable: false),
                  ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: sponsors.isEmpty
                  ? empty
                  : (_view == DonationViewMode.bySponsor
                        ? _sponsorList(sponsors)
                        : _kindList(sponsors)),
            ),
          ],
        );
      },
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
  /// 후원자별 목록.
  ///  [scrollable] false 면 부모 스크롤 안에 들어가므로 스스로 스크롤하지 않고
  ///  내용 높이만큼 커진다(shrinkWrap). 높이 제약이 없는 곳에서 필수.
  Widget _sponsorList(List<DonationRow> sponsors, {bool scrollable = true}) {
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
      // 높이 제약이 없으면(shrinkWrap) 부모 스크롤이 스크롤을 담당한다.
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
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
    // ── [버그 수정 2026-10-26] '수정'은 되는데 '삭제'가 안 되던 문제 ──
    //
    //  원인: 삭제 대상을 찾을 때 **이름/분류/품목/금액 4개가 모두 같아야**
    //        매칭됐다(orElse → 빈 맵 → 메뉴 자체가 사라짐). 같은 후원자가
    //        같은 분류로 금액까지 같은 건을 두 번 넣으면 **어느 행인지
    //        특정할 수 없어** 삭제 버튼이 아예 렌더되지 않았다.
    //  해결: `id` 를 우선 사용하고, id 가 없을 때만 4-필드 매칭으로 되돌아간다.
    final row = _rowOf(e);
    if (row.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 16,
      icon: const Icon(Icons.more_vert, color: AppColors.textGray),
      onSelected: (v) async {
        if (v == 'edit') {
          widget.onEdit(row);
          return;
        }
        if (v == 'del') {
          final ok = await widget.onDelete(row);
          if (!mounted) return;
          _snack(ok ? '삭제했습니다' : '삭제하지 못했습니다 — 다시 시도해 주세요');
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('수정')),
        PopupMenuItem(value: 'del', child: Text('삭제')),
      ],
    );
  }

  /// [DonationRow] 에 대응하는 원본 행을 찾는다.
  ///
  /// `id` 가 있으면 **id 만으로** 찾는다 — 같은 후원자가 동일 분류·동일
  /// 금액으로 여러 건을 후원해도 정확히 그 행을 지목할 수 있다.
  Map<String, dynamic> _rowOf(DonationRow e) {
    final rows = widget.rows;
    if (e.id.isNotEmpty) {
      for (final r in rows) {
        if ('${r['id'] ?? ''}' == e.id) return r;
      }
    }
    for (final r in rows) {
      if ('${r['name'] ?? ''}'.trim() == e.name &&
          '${r['category'] ?? ''}'.trim() == e.category &&
          '${r['item'] ?? ''}'.trim() == e.item &&
          ((r['amount'] as num?)?.toInt() ?? 0) == e.amount) {
        return r;
      }
    }
    return const {};
  }

  void _snack(String msg) {
    final ctx = context;
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {}
  }

  // --------------------------------------------------------------- 내역별
  /// 내역(분류)별 목록. [scrollable] 의미는 [_sponsorList] 와 같다.
  Widget _kindList(List<DonationRow> sponsors, {bool scrollable = true}) {
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
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
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
