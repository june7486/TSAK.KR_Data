import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';

/// 수품구매(굿즈) 판매창 — 로그인 없이 열람·주문 가능.
/// 단, 연회비 미납 시 서버가 주문을 차단한다(연회비 게이트).
class MerchShopScreen extends StatefulWidget {
  const MerchShopScreen({super.key});

  @override
  State<MerchShopScreen> createState() => _MerchShopScreenState();
}

class _MerchShopScreenState extends State<MerchShopScreen> {
  NasApi get _nas => context.read<NasApi>();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic> _config = {};
  int _annualFee = 0;

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
      final r = await _nas.merch();
      if (!mounted) return;
      setState(() {
        _products = ((r['products'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _config = ((r['config'] as Map?) ?? {}).cast<String, dynamic>();
        _annualFee = (_config['annualFee'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '상품을 불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  bool get _salesOpen => _config['salesOpen'] != false;
  Map<String, dynamic> get _account =>
      ((_config['account'] as Map?) ?? {}).cast<String, dynamic>();

  String _won(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${buf.toString()}원';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('수품구매'),
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
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _noticeCard(),
                      const SizedBox(height: 10),
                      if (_products.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text('판매 중인 상품이 없습니다',
                                style: TextStyle(color: AppColors.textGray)),
                          ),
                        )
                      else
                        ..._products.map(_productCard),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.taegeukRed),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );

  Widget _noticeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.purple.withValues(alpha: 0.10),
            AppColors.taegeukBlue.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag, color: AppColors.purple, size: 20),
              const SizedBox(width: 6),
              const Text('수품(굿즈) 구매 안내',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.purpleDark)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '· 로그인 없이 주문할 수 있습니다.\n'
            '· 연회비(회원)를 납부하신 분만 구매 가능합니다.\n'
            '· 교환·반품 시 배송비는 구매자 부담입니다.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textDark, height: 1.5),
          ),
          if (_annualFee > 0) ...[
            const SizedBox(height: 6),
            Text('· 현재 연회비: ${_won(_annualFee)}',
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.taegeukBlue,
                    fontWeight: FontWeight.w700)),
          ],
          if (!_salesOpen) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.taegeukRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('현재 판매가 일시 중지되어 있습니다.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.taegeukRed,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> p) {
    final price = (p['price'] as num?)?.toInt() ?? 0;
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final options = ((p['options'] as List?) ?? []).map((e) => '$e').toList();
    final image = '${p['image'] ?? ''}';
    final kind = '${p['kind'] ?? ''}';
    final soldOut = stock <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image.startsWith('http'))
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Image.network(
                image,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${p['name'] ?? ''}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    if (kind.isNotEmpty) _chip(kind),
                  ],
                ),
                if ('${p['desc'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('${p['desc']}',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textGray)),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(_won(price),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.taegeukBlue)),
                    const SizedBox(width: 10),
                    Text(soldOut ? '품절' : '재고 $stock',
                        style: TextStyle(
                            fontSize: 12,
                            color: soldOut
                                ? AppColors.taegeukRed
                                : AppColors.textGray)),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: soldOut || !_salesOpen
                            ? AppColors.textGray
                            : AppColors.purple,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: (soldOut || !_salesOpen)
                          ? null
                          : () => _buy(p, options),
                      icon: const Icon(Icons.add_shopping_cart, size: 16),
                      label: const Text('구매'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.purple.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(t,
            style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.purple,
                fontWeight: FontWeight.w800)),
      );

  Future<void> _buy(Map<String, dynamic> p, List<String> options) async {
    final name = TextEditingController();
    final number = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final qty = TextEditingController(text: '1');
    final otherShip = TextEditingController();
    String option = options.isNotEmpty ? options.first : '';
    String ship = '현장구매';

    final price = (p['price'] as num?)?.toInt() ?? 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final q = int.tryParse(qty.text.trim()) ?? 1;
          final total = price * (q < 1 ? 1 : q);
          return AlertDialog(
            title: Text('${p['name']} 구매'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: number,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '인가번호 (연회비 확인용)', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                        labelText: '입금자명 (인가자 이름)', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  if (options.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: option,
                      isDense: true,
                      decoration: const InputDecoration(
                          labelText: '옵션 (사이즈 등)', isDense: true),
                      items: options
                          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                          .toList(),
                      onChanged: (v) => setDlg(() => option = v ?? ''),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: qty,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDlg(() {}),
                    decoration: const InputDecoration(
                        labelText: '수량', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: '연락처 (선택)', isDense: true),
                  ),
                  const SizedBox(height: 10),
                  const Text('배송 방법',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final m in ['현장구매', '택배발송', '기타'])
                        ChoiceChip(
                          label: Text(m),
                          selected: ship == m,
                          onSelected: (_) => setDlg(() => ship = m),
                        ),
                    ],
                  ),
                  if (ship == '택배발송') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: address,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: '배송 주소', isDense: true),
                    ),
                  ],
                  if (ship == '기타') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: otherShip,
                      decoration: const InputDecoration(
                          labelText: '배송 방법 직접입력', isDense: true),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.taegeukBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Text('합계:',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(_won(total),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.taegeukBlue)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('주문하기'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;

    // 주문 전송
    try {
      final r = await _nas.merchOrder(
        productId: '${p['id']}',
        buyerName: name.text.trim(),
        buyerNumber: number.text.trim(),
        qty: int.tryParse(qty.text.trim()) ?? 1,
        option: option,
        phone: phone.text.trim(),
        address: address.text.trim(),
        shipMethod: ship == '기타' ? otherShip.text.trim() : ship,
        shipNote: ship == '기타' ? otherShip.text.trim() : '',
        unitPrice: price,
      );
      if (!mounted) return;
      if (r['ok'] == true) {
        await _showPayment(r);
        _load();
      } else if (r['error'] == 'annual_fee_required') {
        _snack('연회비 납부 후 구매할 수 있습니다. (연회비 ${_won(_annualFee)})',
            color: AppColors.taegeukRed);
      } else if (r['error'] == 'sales_closed') {
        _snack('현재 판매가 중지되어 있습니다.', color: AppColors.taegeukRed);
      } else {
        _snack('주문 실패: ${r['error']}', color: AppColors.taegeukRed);
      }
    } catch (e) {
      if (mounted) _snack('오류: $e', color: AppColors.taegeukRed);
    }
  }

  Future<void> _showPayment(Map<String, dynamic> r) async {
    final order = ((r['order'] as Map?) ?? {}).cast<String, dynamic>();
    final acc = ((r['account'] as Map?) ?? _account).cast<String, dynamic>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('주문이 접수되었습니다'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('상품: ${order['product']}'
                '${'${order['option'] ?? ''}'.isNotEmpty ? ' / ${order['option']}' : ''}'),
            Text('수량: ${order['qty']}개'),
            Text('합계: ${_won((order['total'] as num?)?.toInt() ?? 0)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.taegeukBlue)),
            const Divider(height: 20),
            const Text('입금 계좌 (수품계좌)',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
            const SizedBox(height: 4),
            Text('${acc['bank'] ?? ''} ${acc['no'] ?? ''}'),
            Text('예금주: ${acc['holder'] ?? ''}'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.tigerGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '입금자명: 인가자이름 + "수품구매"\n'
                '(예: 홍길동수품구매)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '입금 확인 후 배송/수령 안내드립니다.\n교환·반품 배송비는 구매자 부담입니다.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
        ],
      ),
    );
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }
}
