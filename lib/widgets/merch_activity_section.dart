import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';

/// 개인 프로필 — 수품구매 내역 + 진행 상황 가로 바차트 + 예약(수요조사) 대기자.
/// 인가번호/전화 기반으로 /api/merch/mine 을 조회하여 표시한다.
class MerchActivitySection extends StatefulWidget {
  const MerchActivitySection({
    super.key,
    required this.ident,
    this.title = '수품구매 내역',
  });

  /// 인가번호(우선) 또는 전화번호.
  final String ident;
  final String title;

  @override
  State<MerchActivitySection> createState() => _MerchActivitySectionState();
}

class _MerchActivitySectionState extends State<MerchActivitySection> {
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _reserves = [];
  List<String> _statuses = const [];
  List<String> _reserveStatuses = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant MerchActivitySection old) {
    super.didUpdateWidget(old);
    if (old.ident != widget.ident) _load();
  }

  Future<void> _load() async {
    final ident = widget.ident.trim();
    if (ident.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await context.read<NasApi>().merchMine(ident: ident);
      if (!mounted) return;
      setState(() {
        _orders = ((r['orders'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _reserves = ((r['reservations'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _statuses = ((r['statuses'] as List?) ?? []).map((e) => '$e').toList();
        _reserveStatuses =
            ((r['reserveStatuses'] as List?) ?? []).map((e) => '$e').toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _won(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${b.toString()}원';
  }

  @override
  Widget build(BuildContext context) {
    final total = _orders.length + _reserves.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_outlined,
                  size: 18, color: AppColors.purpleDark),
              const SizedBox(width: 6),
              Text(widget.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: AppColors.purpleDark)),
              const Spacer(),
              if (total > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$total건',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.purple)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('수품 구매/예약 내역이 없습니다.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textGray)),
            )
          else ...[
            // 주문 내역
            for (final o in _orders) _orderTile(o),
            // 예약(수요조사) 대기자
            if (_reserves.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('예약(수요조사) 대기',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: AppColors.tigerGold)),
              const SizedBox(height: 4),
              for (final r in _reserves) _reserveTile(r),
            ],
          ],
        ],
      ),
    );
  }

  Widget _orderTile(Map<String, dynamic> o) {
    final st = '${o['status'] ?? '입금확인중'}';
    final grand = (o['grandTotal'] as num?)?.toInt() ??
        ((o['total'] as num?)?.toInt() ?? 0) +
            ((o['annualFeeAdded'] as num?)?.toInt() ?? 0);
    final cancelled = st == '주문취소';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8FE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${o['product'] ?? ''}'
                  '${'${o['option'] ?? ''}'.isNotEmpty ? ' (${o['option']})' : ''}'
                  ' × ${o['qty'] ?? 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ),
              Text(grand > 0 ? _won(grand) : '가격문의',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AppColors.taegeukBlue)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${o['created'] ?? ''}'
            '${'${o['id'] ?? ''}'.isNotEmpty ? ' · ${o['id']}' : ''}',
            style: const TextStyle(fontSize: 10, color: AppColors.textGray),
          ),
          const SizedBox(height: 8),
          // ── 가로형 진행 바차트 ──
          _ProgressBar(
            statuses: _statuses,
            current: st,
            cancelled: cancelled,
            compact: true,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cancelled
                      ? AppColors.taegeukRed.withValues(alpha: 0.12)
                      : AppColors.purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('현재: $st',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: cancelled
                            ? AppColors.taegeukRed
                            : AppColors.purple)),
              ),
              const Spacer(),
              if ('${o['shipMethod'] ?? ''}'.isNotEmpty)
                Text('${o['shipMethod']}',
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.textGray)),
            ],
          ),
          if ('${o['memo'] ?? ''}'.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('메모: ${o['memo']}',
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.textGray)),
            ),
        ],
      ),
    );
  }

  Widget _reserveTile(Map<String, dynamic> r) {
    final st = '${r['status'] ?? '예약접수'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.tigerGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.tigerGold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r['product'] ?? ''}'
                  '${'${r['option'] ?? ''}'.isNotEmpty ? ' (${r['option']})' : ''}'
                  ' × ${r['qty'] ?? 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.tigerGold.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(st,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF8A6100))),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('${r['created'] ?? ''}',
              style: const TextStyle(fontSize: 10, color: AppColors.textGray)),
        ],
      ),
    );
  }
}

/// 가로형 진행 바차트 — 주문 상태를 단계별로 시각화.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.statuses,
    required this.current,
    this.cancelled = false,
    this.compact = false,
  });

  final List<String> statuses;
  final String current;
  final bool cancelled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // 취소 상태는 진행 바 대신 취소 표시만.
    final pipeline = statuses.where((s) => s != '주문취소').toList();
    if (pipeline.isEmpty) pipeline = const ['입금확인중', '입금확인', '상품준비중', '배송완료'];
    final idx = pipeline.indexOf(current);
    final done = cancelled ? -1 : idx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (ctx, c) {
            final n = pipeline.length;
            final segW = c.maxWidth / n;
            return Row(
              children: [
                for (int i = 0; i < n; i++)
                  Expanded(
                    child: Container(
                      height: compact ? 6 : 8,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: done >= i
                            ? AppColors.purple
                            : AppColors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 3),
        // 현재 단계 라벨만 (컴팩트: 시작/현재/끝)
        Row(
          children: [
            if (!compact) ...[
              Expanded(
                  child: Text(pipeline.first,
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textGray))),
              Expanded(
                  child: Text(current,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.purple,
                          fontWeight: FontWeight.w700))),
              Expanded(
                  child: Text(pipeline.last,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textGray))),
            ] else
              Text(
                cancelled
                    ? '주문이 취소되었습니다'
                    : '$current (${done + 1}/${pipeline.length} 단계)',
                style: TextStyle(
                    fontSize: 9.5,
                    color: cancelled ? AppColors.taegeukRed : AppColors.purple,
                    fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ],
    );
  }
}
