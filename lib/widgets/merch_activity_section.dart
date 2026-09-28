import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import 'merch_inquiry_sheet.dart';
import 'merch_order_detail.dart';

/// 개인 프로필에 표시되는 수품 구매/예약 내역 위젯.
/// 수품 주문 진행 상황을 가로 진행 바(세그먼트)로 보여준다.
/// 주문번호를 클릭하면 주문 상세 내역을 조회할 수 있다.
class MerchActivitySection extends StatefulWidget {
  const MerchActivitySection({
    super.key,
    required this.ident,
    this.title = '수품구매 내역',
    this.memberName = '',
    this.phone = '',
    this.email = '',
  });

  final String ident;
  final String title;
  final String memberName;
  final String phone;
  final String email;

  @override
  State<MerchActivitySection> createState() => _MerchActivitySectionState();
}

class _MerchActivitySectionState extends State<MerchActivitySection> {
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _reserves = [];
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
        _statuses = (r['statuses'] as List?) ?? const [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_orders.isEmpty && _reserves.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('수품 구매 내역이 없습니다.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textGray)),
            )
          else ...[
            for (final o in _orders) _orderRow(o),
            for (final r in _reserves) _reserveRow(r),
          ],
          if (!_loading) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
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

  void _openDetail(Map<String, dynamic> rec, {required bool isReserve}) {
    MerchOrderDetail.show(
      context,
      rec: rec,
      isReserve: isReserve,
      statuses: _statuses.map((e) => '$e').toList(),
    );
  }

  Widget _orderRow(Map<String, dynamic> o) {
    final status = (o['status'] ?? '').toString();
    final statuses = _statuses.map((e) => e.toString()).toList();
    final current = statuses.indexOf(status);
    final cancelled = status.contains('취소');
    final product = (o['product'] ?? '').toString().trim();
    final orderNo = (o['orderNo'] ?? '').toString().trim();
    final qty = (o['qty'] as num?)?.toInt() ?? 1;
    final total = (o['grandTotal'] ?? o['total']) ?? 0;
    final created = (o['created'] ?? o['createdAt'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product.isEmpty ? '수품 주문' : (qty > 1 ? '$product ×$qty' : product),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${_won((total as num?)?.toInt() ?? 0)}원',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
          if (orderNo.isNotEmpty) ...[
            const SizedBox(height: 3),
            InkWell(
              onTap: () => _openDetail(o, isReserve: false),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        size: 12, color: AppColors.purple),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '주문번호 $orderNo',
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
                    Text('상세',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.purple,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (statuses.isNotEmpty && !cancelled)
            _ProgressBar(steps: statuses, current: current)
          else
            _pill(status.isEmpty ? '접수' : status, cancelled ? Colors.red : AppColors.purple),
          const SizedBox(height: 3),
          Text('주문일 ${created.isEmpty ? '-' : created}',
              style: const TextStyle(fontSize: 11, color: AppColors.textGray)),
        ],
      ),
    );
  }

  Widget _reserveRow(Map<String, dynamic> r) {
    final status = (r['status'] ?? '예약접수').toString();
    final product = (r['product'] ?? '').toString().trim();
    final orderNo = (r['orderNo'] ?? '').toString().trim();
    final qty = (r['qty'] as num?)?.toInt() ?? (r['quantity'] as num?)?.toInt() ?? 1;
    final created = (r['created'] ?? r['createdAt'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    product.isEmpty ? '수품 예약' : (qty > 1 ? '$product ×$qty' : product),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              _pill('예약 $status', Colors.orange),
            ],
          ),
          if (orderNo.isNotEmpty) ...[
            const SizedBox(height: 3),
            InkWell(
              onTap: () => _openDetail(r, isReserve: true),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        size: 12, color: Colors.orange),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('예약번호 $orderNo',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.purpleDark,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        size: 14, color: Colors.orange),
                    const Text('상세',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.orange,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(created.isEmpty ? '예약(수요조사) 접수됨 — 제작 판단 후 안내됩니다.' : '$created · 수요조사 접수됨',
              style: const TextStyle(fontSize: 11, color: AppColors.textGray)),
        ],
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
