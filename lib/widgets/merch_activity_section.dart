import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/order_detail_screen.dart';
import '../services/app_state.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import 'merch_inquiry_sheet.dart';

/// 개인 프로필에 표시되는 수품 구매/예약 내역 위젯(수품구매현황 통합).
/// - 주문 진행 상황을 가로 진행 바(세그먼트)로 보여준다.
/// - 주문번호를 클릭하면 주문 상세 내역을 조회한다(관리자·마스터는 수정 가능).
/// - 자가/관리 입력 메모([memo])를 함께 표시하여 기존 '수품구매현황' 메뉴를 통합한다.
/// - 하단 문의하기 버튼은 개인(본인) 열람 시에만 노출한다.
class MerchActivitySection extends StatefulWidget {
  const MerchActivitySection({
    super.key,
    required this.ident,
    this.title = '수품구매현황',
    this.memberName = '',
    this.phone = '',
    this.email = '',
    this.memo = '',
    this.canEditMemo = false,
    this.onEditMemo,
  });

  final String ident;
  final String title;
  final String memberName;
  final String phone;
  final String email;
  final String memo;
  final bool canEditMemo;
  final VoidCallback? onEditMemo;

  @override
  State<MerchActivitySection> createState() => _MerchActivitySectionState();
}

class _MerchActivitySectionState extends State<MerchActivitySection> {
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _reserves = [];
  List<Map<String, dynamic>> _surveys = [];
  List<dynamic> _statuses = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final api = context.read<NasApi>();
      final r = await api.merchMine(ident: widget.ident);
      if (!mounted) return;
      setState(() {
        _orders = (r['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _reserves = (r['reservations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _surveys = (r['surveys'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _statuses = (r['statuses'] as List?) ?? const [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelf = context.read<AppState>().isSelfAccess;
    final memo = widget.memo.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_outlined, size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              Text(widget.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.purpleDark)),
              const Spacer(),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18, color: AppColors.textGray),
                tooltip: '새로고침',
              ),
            ],
          ),
          // (통합) 자가/관리 입력 메모 — 기존 '수품구매현황' 내용
          if (memo.isNotEmpty) ...[
            const SizedBox(height: 2),
            ...memo.split(RegExp(r'[\n/]')).where((e) => e.trim().isNotEmpty).map(
                  (line) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3, right: 6),
                          child: Icon(Icons.check_circle,
                              size: 13, color: AppColors.scoutGreen),
                        ),
                        Expanded(
                          child: Text(line.trim(),
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textDark,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 4),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_orders.isEmpty && _reserves.isEmpty && _surveys.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(memo.isEmpty ? '수품 구매 내역이 없습니다.' : '온라인 주문 내역이 없습니다.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textGray)),
            )
          else ...[
            if (memo.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text('온라인 주문 내역',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textGray)),
              ),
            for (final g in _groupBy(_orders)) _groupRow(g, isReserve: false),
            for (final g in _groupBy(_reserves)) _groupRow(g, isReserve: true),
            // 사전신청(수요조사) 수품 리스트 — 프로필 수품구매 항목에 노출
            if (_surveys.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Row(
                children: [
                  Icon(Icons.campaign_outlined, size: 14, color: AppColors.tigerGold),
                  SizedBox(width: 5),
                  Text('사전신청한 수품 (수요조사)',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textGray)),
                ],
              ),
              for (final s in _surveys) _surveyRow(s),
            ],
          ],
          if (!_loading) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            if (widget.canEditMemo && widget.onEditMemo != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: widget.onEditMemo,
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text('구매현황 메모 편집',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            // 문의하기 — 개인(본인) 열람 시에만 노출
            if (isSelf)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.purple,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => showMerchInquiry(
                    context: context,
                    name: widget.memberName,
                    phone: widget.phone,
                    email: widget.email,
                  ),
                  icon: const Icon(Icons.mark_email_read_outlined, size: 17),
                  label: const Text('문의하기 (메일로 문의)',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ---------- 주문번호별 그룹핑 ----------
  static String _groupKeyOf(Map<String, dynamic> o) {
    final no = '${o['orderNo'] ?? ''}'.trim();
    if (no.isNotEmpty) return no;
    return '#${o['id'] ?? ''}';
  }

  List<List<Map<String, dynamic>>> _groupBy(List<Map<String, dynamic>> src) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final o in src) {
      final k = _groupKeyOf(o);
      (map[k] ??= []).add(o);
    }
    return map.values.toList();
  }

  /// 그룹(주문번호) 상세 — 장바구니형 페이지로 이동.
  Future<void> _openGroup(List<Map<String, dynamic>> items,
      {required bool isReserve}) async {
    if (items.isEmpty) return;
    final editable = context.read<AppState>().isApp;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OrderDetailScreen(
        groupKey: _groupKeyOf(items.first),
        initialItems: items,
        canManage: editable,
        ident: widget.ident,
        statuses: _statuses.map((e) => '$e').toList(),
        isReserve: isReserve,
      ),
    ));
    _load();
  }

  /// 주문번호로 통합된 행(장바구니 요약). 클릭 → 장바구니형 상세.
  Widget _groupRow(List<Map<String, dynamic>> items,
      {required bool isReserve}) {
    final head = items.first;
    final orderNo = '${head['orderNo'] ?? ''}'.trim();
    final status = (head['status'] ?? (isReserve ? '예약접수' : '')).toString();
    final cancelled = status.contains('취소');
    final created =
        (head['created'] ?? head['createdAt'] ?? '').toString().trim();
    final grand = items.fold<int>(
        0, (p, o) => p + ((o['grandTotal'] ?? o['total'] ?? 0) as num).toInt());
    final sumQty = items.fold<int>(
        0, (p, o) => p + ((o['qty'] as num?)?.toInt() ?? 1));
    final received = items.every((o) => o['received'] == true);
    final statuses = _statuses.map((e) => e.toString()).toList();
    final current = statuses.indexOf(status);

    // 품목명 요약 (없으면 '수품 주문')
    final names = items
        .map((o) => ('${o['product'] ?? o['productName'] ?? ''}').trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final title = names.isEmpty
        ? (isReserve ? '수품 예약' : '수품 주문')
        : (names.length == 1 ? names.first : '${names.first} 외 ${names.length - 1}종');

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: () => _openGroup(items, isReserve: isReserve),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: (cancelled
                        ? Colors.red
                        : (isReserve ? Colors.orange : AppColors.purple))
                    .withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${_won(grand)}원',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                      isReserve
                          ? Icons.bookmark_border
                          : Icons.receipt_long_outlined,
                      size: 12,
                      color: isReserve ? Colors.orange : AppColors.purple),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${isReserve ? '예약번호' : '주문번호'} ${orderNo.isEmpty ? '-' : orderNo}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.purpleDark,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      size: 14, color: AppColors.purple),
                  const Text('상세',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.purple,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${items.length}종 $sumQty개',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGray)),
                  if (received) ...[
                    const SizedBox(width: 5),
                    _pill('수령확인', AppColors.tigerGold),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              if (isReserve)
                _pill('예약 $status', Colors.orange)
              else if (statuses.isNotEmpty && !cancelled)
                _ProgressBar(steps: statuses, current: current)
              else
                _pill(status.isEmpty ? '접수' : status,
                    cancelled ? Colors.red : AppColors.purple),
              const SizedBox(height: 3),
              Text(
                  '${isReserve ? '예약' : '주문'}일 ${created.isEmpty ? '-' : created}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textGray)),
            ],
          ),
        ),
      ),
    );
  }

  /// 사전신청(수요조사) 수품 한 줄 — 내 순번 + 최소제작 대비 인원.
  Widget _surveyRow(Map<String, dynamic> s) {
    final name = '${s['name'] ?? ''}'.trim();
    final myNo = (s['myNo'] as num?)?.toInt() ?? 0;
    final minQty = (s['minQty'] as num?)?.toInt() ?? 0;
    final count = (s['count'] as num?)?.toInt() ?? 0;
    final progress = '${s['progress'] ?? ''}'.trim();
    final open = s['surveyOpen'] == true;
    final ratio = minQty > 0 ? (count / minQty).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.tigerGold.withValues(alpha: 0.35)),
          color: AppColors.tigerGold.withValues(alpha: 0.05),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name.isEmpty ? '수품' : name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (!open)
                  _pill('조사마감', AppColors.textGray)
                else if (progress.isNotEmpty)
                  _pill(progress, AppColors.scoutGreen),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                if (myNo > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.tigerGold.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$myNo번째 신청자',
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.purpleDark)),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '/ $count명 신청 (최소 $minQty명)',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.purple),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: AppColors.purpleLight.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation(AppColors.tigerGold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(t,
            style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.w800)),
      );

  String _won(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return (v < 0 ? '-' : '') + b.toString();
  }
}

/// 진행 상황을 세그먼트 바로 표시하는 위젯.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < steps.length; i++)
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 6,
                  margin: EdgeInsets.only(right: i == steps.length - 1 ? 0 : 3),
                  decoration: BoxDecoration(
                    color: i <= current
                        ? AppColors.purple
                        : AppColors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  steps[i],
                  style: TextStyle(
                    fontSize: 8,
                    color: i <= current ? AppColors.purpleDark : AppColors.textGray,
                    fontWeight: i == current ? FontWeight.w800 : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
