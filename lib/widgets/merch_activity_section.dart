import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';

/// 개인 프로필에 표시되는 수품 구매/예약 내역 위젯.
/// 수품 주문 진행 상황을 가로 진행 바(세그먼트)로 보여준다.
class MerchActivitySection extends StatefulWidget {
  const MerchActivitySection({super.key, required this.ident, this.title = '수품구매 내역'});

  final String ident;
  final String title;

  @override
  State<MerchActivitySection> createState() => _MerchActivitySectionState();
}

class _MerchActivitySectionState extends State<MerchActivitySection> {
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _reserves = [];
  List<dynamic> _statuses = const [];
  List<dynamic> _reserveStatuses = const [];

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
        _reserveStatuses = (r['reserveStatuses'] as List?) ?? const [];
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
        ],
      ),
    );
  }

  Widget _orderRow(Map<String, dynamic> o) {
    final status = (o['status'] ?? '').toString();
    final statuses = _statuses.map((e) => e.toString()).toList();
    final current = statuses.indexOf(status);
    final cancelled = status.contains('취소');
    final items = (o['items'] as List?) ?? const [];
    final itemNames = items
        .map((it) => (it is Map ? it['name'] : it).toString())
        .where((s) => s.isNotEmpty)
        .take(3)
        .join(', ');
    final total = (o['grandTotal'] ?? o['total']) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  itemNames.isEmpty ? '수품 주문' : itemNames,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${_won((total as num?)?.toInt() ?? 0)}원',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 6),
          if (statuses.isNotEmpty && !cancelled)
            _ProgressBar(steps: statuses, current: current)
          else
            _pill(status.isEmpty ? '접수' : status, cancelled ? Colors.red : AppColors.purple),
          const SizedBox(height: 3),
          Text('주문일 ${o['createdAt'] ?? '-'}',
              style: const TextStyle(fontSize: 11, color: AppColors.textGray)),
        ],
      ),
    );
  }

  Widget _reserveRow(Map<String, dynamic> r) {
    final status = (r['status'] ?? '예약접수').toString();
    final items = (r['items'] as List?) ?? const [];
    final itemNames = items
        .map((it) => (it is Map ? it['name'] : it).toString())
        .where((s) => s.isNotEmpty)
        .take(3)
        .join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(itemNames.isEmpty ? '수품 예약' : itemNames,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              _pill('예약 ${status}', Colors.orange),
            ],
          ),
          const SizedBox(height: 4),
          const Text('예약(수요조사) 접수됨 — 제작 판단 후 안내됩니다.',
              style: TextStyle(fontSize: 11, color: AppColors.textGray)),
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
