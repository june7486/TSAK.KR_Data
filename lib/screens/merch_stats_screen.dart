import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/merch_order_detail.dart';

/// 수품 통계·현황 페이지 — **관리자·마스터 전용**.
///
/// 구매자별 현황 / 판매(상품별) 현황 / 입금 현황 / 미수금 현황 / 발송 현황 등
/// 필요한 모든 통계를 한 화면에서 한 번에 보여준다.
class MerchStatsScreen extends StatefulWidget {
  const MerchStatsScreen({super.key});

  @override
  State<MerchStatsScreen> createState() => _MerchStatsScreenState();
}

class _MerchStatsScreenState extends State<MerchStatsScreen> {
  NasApi get _nas => context.read<NasApi>();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _reserves = [];
  List<String> _statuses = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _nas.merchAdmin();
      if (!mounted) return;
      setState(() {
        _orders = ((r['orders'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _reserves = ((r['reservations'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        final cfg = ((r['config'] as Map?) ?? {}).cast<String, dynamic>();
        _statuses = ((cfg['statuses'] as List?) ?? const [])
            .map((e) => '$e')
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  int _i(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  String _won(num? v) {
    final n = v?.toInt() ?? 0;
    final s = n.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}${b.toString()}원';
  }

  bool _isCancelled(Map<String, dynamic> o) =>
      '${o['status'] ?? ''}'.contains('취소');

  int _actual(Map<String, dynamic> o) =>
      _i(o['grandTotal'] ?? o['total']);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('수품 통계·현황'),
        actions: [
          const AppHomeEmblem(size: 22),
          IconButton(
            tooltip: '새로고침',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 44, color: AppColors.taegeukRed),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      ElevatedButton(
                          onPressed: _load, child: const Text('다시 시도')),
                    ],
                  ),
                )
              : _body(),
    );
  }

  Widget _body() {
    final valid = _orders.where((o) => !_isCancelled(o)).toList();
    final cancelled = _orders.where(_isCancelled).toList();

    // 합계
    final totalSales = valid.fold<int>(0, (p, o) => p + _actual(o));
    final totalFee = valid.fold<int>(0, (p, o) => p + _i(o['annualFeeAdded']));
    final paidSum =
        valid.where((o) => o['paid'] == true).fold<int>(0, (p, o) => p + _actual(o));
    final unpaidSum = totalSales - paidSum;
    final paidCount = valid.where((o) => o['paid'] == true).length;
    final unpaidCount = valid.length - paidCount;

    // 구매자별 현황
    final byBuyer = <String, Map<String, dynamic>>{};
    for (final o in valid) {
      final key = '${o['buyerName'] ?? ''}'.trim().isEmpty
          ? '구매자 미상'
          : '${o['buyerName']}'.trim();
      final b = byBuyer.putIfAbsent(
          key, () => {'name': key, 'count': 0, 'amount': 0, 'unpaid': 0});
      b['count'] = (b['count'] as int) + 1;
      b['amount'] = (b['amount'] as int) + _actual(o);
      if (o['paid'] != true) {
        b['unpaid'] = (b['unpaid'] as int) + _actual(o);
      }
    }
    final buyerList = byBuyer.values.toList()
      ..sort((a, b) => (b['amount'] as int).compareTo(a['amount'] as int));

    // 상품별(판매) 현황
    final byProduct = <String, Map<String, dynamic>>{};
    for (final o in valid) {
      final key = '${o['product'] ?? ''}'.trim().isEmpty
          ? '기타'
          : '${o['product']}'.trim();
      final b = byProduct.putIfAbsent(
          key, () => {'name': key, 'qty': 0, 'amount': 0});
      b['qty'] = (b['qty'] as int) + (_i(o['qty']) == 0 ? 1 : _i(o['qty']));
      b['amount'] = (b['amount'] as int) + _actual(o);
    }
    final productList = byProduct.values.toList()
      ..sort((a, b) => (b['amount'] as int).compareTo(a['amount'] as int));

    // 발송(진행상태) 현황
    final byStatus = <String, int>{};
    for (final s in _statuses) {
      byStatus[s] = 0;
    }
    for (final o in valid) {
      final s = '${o['status'] ?? '입금확인중'}';
      byStatus[s] = (byStatus[s] ?? 0) + 1;
    }

    // 미수금(미입금) 주문 목록
    final unpaidOrders = valid.where((o) => o['paid'] != true).toList()
      ..sort((a, b) => _actual(b).compareTo(_actual(a)));

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            _stat('총 주문', '${valid.length}건', AppColors.purple),
            const SizedBox(width: 8),
            _stat('총 매출', _won(totalSales), AppColors.taegeukBlue),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _stat('입금 완료', _won(paidSum), AppColors.scoutGreen),
            const SizedBox(width: 8),
            _stat('미수금', _won(unpaidSum), AppColors.taegeukRed),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _stat('연회비 합계', _won(totalFee), AppColors.lifetimeGold),
            const SizedBox(width: 8),
            _stat('예약접수', '${_reserves.length}건', Colors.orange),
          ],
        ),
        const SizedBox(height: 14),
        _box('구매자별 현황 (${buyerList.length}명)', [
          if (buyerList.isEmpty)
            const Text('데이터 없음', style: TextStyle(color: AppColors.textGray))
          else
            for (final b in buyerList)
              _line(
                '${b['name']}',
                '${b['count']}건 · ${_won(b['amount'] as int)}'
                '${(b['unpaid'] as int) > 0 ? ' (미수 ${_won(b['unpaid'] as int)})' : ''}',
                danger: (b['unpaid'] as int) > 0,
              ),
        ]),
        const SizedBox(height: 12),
        _box('판매(상품별) 현황', [
          if (productList.isEmpty)
            const Text('데이터 없음', style: TextStyle(color: AppColors.textGray))
          else
            for (final p in productList)
              _line('${p['name']}',
                  '${p['qty']}개 · ${_won(p['amount'] as int)}'),
        ]),
        const SizedBox(height: 12),
        _box('입금 현황', [
          _line('입금 완료', '$paidCount건 · ${_won(paidSum)}',
              danger: false),
          _line('미입금', '$unpaidCount건 · ${_won(unpaidSum)}', danger: true),
        ]),
        const SizedBox(height: 12),
        _box('발송(진행상태) 현황', [
          if (byStatus.isEmpty)
            const Text('데이터 없음', style: TextStyle(color: AppColors.textGray))
          else
            for (final e in byStatus.entries)
              if (e.value > 0) _line(e.key, '${e.value}건'),
        ]),
        const SizedBox(height: 12),
        _box('미수금 현황 (미입금 주문 ${unpaidOrders.length}건)', [
          if (unpaidOrders.isEmpty)
            const Text('미수금이 없습니다.',
                style: TextStyle(color: AppColors.scoutGreen))
          else
            for (final o in unpaidOrders.take(50))
              _unpaidRow(o),
        ]),
        if (cancelled.isNotEmpty) ...[
          const SizedBox(height: 12),
          _box('취소된 주문 (${cancelled.length}건)', [
            for (final o in cancelled.take(30))
              _line('${o['orderNo'] ?? ''}',
                  '${o['product'] ?? ''} · ${_won(_actual(o))}'),
          ]),
        ],
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _stat(String label, String value, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textGray)),
              const SizedBox(height: 3),
              Text(value,
                  style: TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w800, color: c)),
            ],
          ),
        ),
      );

  Widget _box(String title, List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.purpleDark)),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      );

  Widget _line(String k, String v, {bool danger = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(k,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textDark)),
            ),
            Text(v,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: danger ? AppColors.taegeukRed : AppColors.textDark)),
          ],
        ),
      );

  Widget _unpaidRow(Map<String, dynamic> o) => InkWell(
        onTap: () => MerchOrderDetail.show(
          context,
          rec: o,
          isReserve: false,
          statuses: _statuses,
          editable: true,
          onChanged: _load,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 14, color: AppColors.taegeukRed),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${o['orderNo'] ?? ''} · ${o['buyerName'] ?? ''}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(_won(_actual(o)),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.taegeukRed)),
            ],
          ),
        ),
      );
}
