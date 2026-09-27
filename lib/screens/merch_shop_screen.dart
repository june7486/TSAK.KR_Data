import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/address_field.dart';
import '../widgets/app_home_emblem.dart';

/// 수품구매(굿즈) 쇼핑몰 — 로그인 없이 열람·장바구니·주문 가능.
/// 연회비 미납 시 서버가 주문을 차단한다(연회비 게이트).
class MerchShopScreen extends StatefulWidget {
  const MerchShopScreen({super.key});

  @override
  State<MerchShopScreen> createState() => _MerchShopScreenState();
}

/// 장바구니 한 줄: 상품 + 옵션 + 수량.
class _CartLine {
  final Map<String, dynamic> product;
  String option;
  int qty;
  _CartLine(this.product, this.option, this.qty);

  int get price => (product['price'] as num?)?.toInt() ?? 0;
  int get total => price * qty;
  String get key => '${product['id']}::${option.trim()}';
}

class _MerchShopScreenState extends State<MerchShopScreen> {
  NasApi get _nas => context.read<NasApi>();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic> _config = {};
  int _annualFee = 0;

  final List<_CartLine> _cart = [];
  String _sort = '기본'; // 기본 | 낮은가격 | 높은가격 | 이름

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
  Map<String, dynamic> get _guide =>
      ((_config['guide'] as Map?) ?? {}).cast<String, dynamic>();
  int get _shipFee => (_account['shipFee'] as num?)?.toInt() ?? 0;

  int get _cartCount => _cart.fold<int>(0, (s, e) => s + e.qty);
  int get _cartTotal => _cart.fold<int>(0, (s, e) => s + e.total);
  bool get _hasShipping => _cart.any((e) => e.product['_ship'] == '택배발송');

  String _won(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${buf.toString()}원';
  }

  List<Map<String, dynamic>> get _sortedProducts {
    final list = [..._products];
    switch (_sort) {
      case '낮은가격':
        list.sort((a, b) =>
            ((a['price'] as num?)?.toInt() ?? 0)
                .compareTo((b['price'] as num?)?.toInt() ?? 0));
        break;
      case '높은가격':
        list.sort((a, b) =>
            ((b['price'] as num?)?.toInt() ?? 0)
                .compareTo((a['price'] as num?)?.toInt() ?? 0));
        break;
      case '이름':
        list.sort((a, b) =>
            '${a['name']}'.compareTo('${b['name']}'));
        break;
      default:
        break;
    }
    return list;
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
              : _body(),
      bottomNavigationBar: _loading || _error != null ? null : _cartBar(),
    );
  }

  Widget _body() {
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _noticeCard()),
          SliverToBoxAdapter(child: _sortBar()),
          if (_products.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('판매 중인 상품이 없습니다',
                    style: TextStyle(color: AppColors.textGray)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.60,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _productCard(_sortedProducts[i]),
                  childCount: _sortedProducts.length,
                ),
              ),
            ),
        ],
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

  Widget _sortBar() {
    final items = ['기본', '낮은가격', '높은가격', '이름'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      child: Row(
        children: [
          const Text('정렬',
              style: TextStyle(fontSize: 12, color: AppColors.textGray)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final it in items)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(it, style: const TextStyle(fontSize: 12)),
                        selected: _sort == it,
                        onSelected: (_) => setState(() => _sort = it),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeCard() {
    return Container(
      margin: const EdgeInsets.all(14),
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
          Text(
            '· 로그인 없이 장바구니에 담아 주문할 수 있습니다.\n'
            '· 연회비(회원)를 납부하신 분만 구매 가능합니다.\n'
            '· 교환·반품 시 배송비는 구매자 부담입니다.'
            '${_shipFee > 0 ? '\n· 택배 배송료 ${_won(_shipFee)} 별도(우체국 택배).' : ''}',
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.textDark, height: 1.5),
          ),
          if (_annualFee > 0) ...[
            const SizedBox(height: 6),
            Text('· 현재 연회비: ${_won(_annualFee)}',
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.taegeukBlue,
                    fontWeight: FontWeight.w700)),
          ],
          if ('${_guide['membership'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.purple.withValues(alpha: 0.15)),
              ),
              child: Text('${_guide['membership']}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textDark, height: 1.5)),
            ),
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.purple,
                side: BorderSide(color: AppColors.purple.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onPressed: _showGuide,
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('수품 안내 · 세트구성 자세히 보기',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> p) {
    final price = (p['price'] as num?)?.toInt() ?? 0;
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final options = ((p['options'] as List?) ?? []).map((e) => '$e').toList();
    final imgUrl = _nas.merchImageUrl('${p['image'] ?? ''}');
    final kind = '${p['kind'] ?? ''}';
    final soldOut = stock <= 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이미지: 크롭 없이 전체가 보이도록 contain
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              color: const Color(0xFFF7F5FB),
              child: imgUrl.isEmpty
                  ? const Icon(Icons.image_outlined,
                      size: 40, color: AppColors.textGray)
                  : Image.network(
                      imgUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, prog) => prog == null
                          ? child
                          : const Center(
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported,
                          color: AppColors.textGray),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kind.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(kind,
                        style: const TextStyle(
                            fontSize: 9.5,
                            color: AppColors.purple,
                            fontWeight: FontWeight.w800)),
                  ),
                const SizedBox(height: 4),
                Text('${p['name'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text('${p['desc'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.textGray)),
                const SizedBox(height: 6),
                Text(price > 0 ? _won(price) : '가격문의',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.taegeukBlue)),
                Text(soldOut ? '품절' : '재고 $stock',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: soldOut
                            ? AppColors.taegeukRed
                            : AppColors.textGray)),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: soldOut || !_salesOpen
                          ? AppColors.textGray
                          : AppColors.purple,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: (soldOut || !_salesOpen)
                        ? null
                        : () => _addToCart(p, options),
                    icon: const Icon(Icons.add_shopping_cart, size: 15),
                    label: const Text('장바구니',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 장바구니 ====================
  void _addToCart(Map<String, dynamic> p, List<String> options) {
    if (options.isEmpty) {
      _mergeCart(p, '');
      return;
    }
    // 옵션이 있으면 옵션 선택 다이얼로그
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${p['name']} 옵션 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in options)
              ListTile(
                dense: true,
                title: Text(o),
                leading: const Icon(Icons.radio_button_unchecked, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  _mergeCart(p, o);
                },
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        ],
      ),
    );
  }

  void _mergeCart(Map<String, dynamic> p, String option) {
    final idx = _cart.indexWhere(
        (e) => e.key == '${p['id']}::${option.trim()}');
    setState(() {
      if (idx >= 0) {
        _cart[idx].qty += 1;
      } else {
        _cart.add(_CartLine(p, option, 1));
      }
    });
    _snack('장바구니에 담았습니다 (${p['name']}${option.isNotEmpty ? ' / $option' : ''})');
  }

  Widget _cartBar() {
    final has = _cart.isNotEmpty;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: has
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('장바구니 $_cartCount개',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textGray)),
                        Text(_won(_cartTotal),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: AppColors.taegeukBlue)),
                      ],
                    )
                  : const Text('장바구니가 비어 있습니다',
                      style: TextStyle(color: AppColors.textGray)),
            ),
            OutlinedButton.icon(
              onPressed: has ? _openCart : null,
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: const Text('장바구니 보기'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
              onPressed: (has && _salesOpen) ? _checkout : null,
              icon: const Icon(Icons.payment, size: 18),
              label: const Text('주문하기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCart() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => _cartSheet(setSheet),
      ),
    );
  }

  Widget _cartSheet(StateSetter setSheet) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textGray.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart, color: AppColors.purple),
                const SizedBox(width: 6),
                Text('장바구니 ($_cartCount)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                if (_cart.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() => _cart.clear());
                      setSheet(() {});
                    },
                    child: const Text('전체 삭제'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _cart.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text('장바구니가 비어 있습니다',
                        style: TextStyle(color: AppColors.textGray)),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final line = _cart[i];
                      final imgUrl = _nas
                          .merchImageUrl('${line.product['image'] ?? ''}');
                      return Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 58,
                                height: 58,
                                color: const Color(0xFFF7F5FB),
                                child: imgUrl.isEmpty
                                    ? const Icon(Icons.image_outlined,
                                        color: AppColors.textGray)
                                    : Image.network(imgUrl,
                                        fit: BoxFit.contain),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${line.product['name']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5)),
                                  if (line.option.isNotEmpty)
                                    Text('옵션: ${line.option}',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.textGray)),
                                  const SizedBox(height: 4),
                                  if (line.product['_ship'] == '택배발송')
                                    const Text('· 택배발송 선택됨',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: AppColors.taegeukBlue)),
                                  Text(_won(line.total),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.taegeukBlue)),
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                Row(
                                  children: [
                                    _qtyBtn(Icons.remove, () {
                                      setState(() {
                                        if (line.qty > 1) {
                                          line.qty -= 1;
                                        }
                                      });
                                      setSheet(() {});
                                    }),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Text('${line.qty}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800)),
                                    ),
                                    _qtyBtn(Icons.add, () {
                                      setState(() => line.qty += 1);
                                      setSheet(() {});
                                    }),
                                  ],
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: AppColors.taegeukRed),
                                  onPressed: () {
                                    setState(() => _cart.removeAt(i));
                                    setSheet(() {});
                                  },
                                  icon: const Icon(Icons.delete_outline,
                                      size: 15),
                                  label: const Text('삭제',
                                      style: TextStyle(fontSize: 11.5)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('합계',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(_won(_cartTotal),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: AppColors.taegeukBlue)),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        padding: const EdgeInsets.symmetric(vertical: 13)),
                    onPressed: _cart.isEmpty
                        ? null
                        : () {
                            Navigator.pop(context);
                            _checkout();
                          },
                    icon: const Icon(Icons.payment, size: 18),
                    label: const Text('주문하기',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.textGray.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 15),
        ),
      );

  // ==================== 결제(주문) 단계 ====================
  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final number = TextEditingController();
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final address = TextEditingController();
    final otherShip = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String ship = '현장구매';

    final price = _cartTotal;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final extra = ship == '택배발송'
              ? (_shipFee > 0 && _hasShipping ? 0 : _shipFee)
              : 0;
          final total = price + extra;
          return AlertDialog(
            title: const Text('주문 정보 입력'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.tigerGold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '※ 입금자명과 주문자(인가자) 이름이 같아야 합니다.\n'
                        '※ 인가번호 또는 인가자 이름을 꼭 함께 넣어주세요.\n'
                        '   → 기록이 남아 구매 이력이 관리됩니다.',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: number,
                      keyboardType: TextInputType.number,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '인가번호를 입력하세요'
                          : null,
                      decoration: const InputDecoration(
                          labelText: '인가번호 * (연회비 확인·이력관리)',
                          isDense: true),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: name,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '입금자명(인가자 이름)을 입력하세요'
                          : null,
                      decoration: const InputDecoration(
                          labelText: '입금자명 * (인가자 이름과 동일)',
                          isDense: true),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '연락처를 입력하세요'
                          : null,
                      decoration: const InputDecoration(
                          labelText: '연락처 *', isDense: true),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return null;
                        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(s)
                            ? null
                            : '이메일 형식이 올바르지 않습니다';
                      },
                      decoration: const InputDecoration(
                          labelText: '이메일 (선택)', isDense: true),
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
                      AddressField(
                        controller: address,
                        label: '배송 주소',
                        hint: '주소검색 버튼으로 검색하세요',
                        required: true,
                      ),
                    ],
                    if (ship == '기타') ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: otherShip,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '배송 방법을 입력하세요'
                            : null,
                        decoration: const InputDecoration(
                            labelText: '배송 방법 직접입력 *', isDense: true),
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
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Text('상품 합계',
                                  style: TextStyle(fontSize: 12.5)),
                              const Spacer(),
                              Text(_won(price),
                                  style: const TextStyle(fontSize: 12.5)),
                            ],
                          ),
                          if (extra > 0)
                            Row(
                              children: [
                                const Text('택배 배송료',
                                    style: TextStyle(fontSize: 12.5)),
                                const Spacer(),
                                Text(_won(extra),
                                    style: const TextStyle(fontSize: 12.5)),
                              ],
                            ),
                          const Divider(height: 12),
                          Row(
                            children: [
                              const Text('합계:',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                              const Spacer(),
                              Text(_won(total),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: AppColors.taegeukBlue)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소')),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('주문 완료'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;

    // 장바구니를 순차 주문(각 라인 = 주문 1건) + 관리자 메모로 묶음 표기
    final group = 'JB${DateTime.now().millisecondsSinceEpoch % 100000}';
    final shipMethod = ship == '기타' ? otherShip.text.trim() : ship;
    int success = 0;
    Map<String, dynamic> last = {};
    try {
      for (final line in _cart) {
        final r = await _nas.merchOrder(
          productId: '${line.product['id']}',
          buyerName: name.text.trim(),
          buyerNumber: number.text.trim(),
          qty: line.qty,
          option: line.option,
          phone: phone.text.trim(),
          email: email.text.trim(),
          address: address.text.trim(),
          shipMethod: shipMethod,
          shipNote: ship == '기타' ? otherShip.text.trim() : '',
          memo: '장바구니묶음:$group',
          unitPrice: line.price,
        );
        if (r['ok'] == true) {
          success += 1;
          last = r;
        } else if (r['error'] == 'annual_fee_required') {
          if (!mounted) return;
          _snack('연회비 납부 후 구매할 수 있습니다. (연회비 ${_won(_annualFee)})',
              color: AppColors.taegeukRed);
          return;
        } else if (r['error'] == 'sales_closed') {
          if (!mounted) return;
          _snack('현재 판매가 중지되어 있습니다.', color: AppColors.taegeukRed);
          return;
        } else {
          if (!mounted) return;
          _snack('주문 실패: ${r['error']}', color: AppColors.taegeukRed);
          return;
        }
      }
      if (!mounted) return;
      if (success > 0) {
        await _showPayment(last, extraShip:
            ship == '택배발송' && _shipFee > 0 ? _shipFee : 0);
        setState(() => _cart.clear());
        _load();
      }
    } catch (e) {
      if (mounted) _snack('오류: $e', color: AppColors.taegeukRed);
    }
  }

  Future<void> _showPayment(Map<String, dynamic> r,
      {int extraShip = 0}) async {
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
            Text('주문번호: ${order['id'] ?? ''}'),
            Text('주문자: ${order['buyerName'] ?? ''}'
                '${'${order['buyerNumber'] ?? ''}'.isNotEmpty ? ' (${order['buyerNumber']})' : ''}'),
            Text('합계: ${_won(_cartTotal + extraShip)}'
                '${extraShip > 0 ? '  (배송료 ${_won(extraShip)} 포함)' : ''}',
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
                '(예: 홍길동수품구매)\n'
                '※ 입금자명과 주문자 이름이 같아야 합니다.',
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

  // ==================== 안내문(구글폼 연계) ====================
  Future<void> _showGuide() async {
    final g = _guide;
    final acc = _account;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${g['title'] ?? '수품 구매 안내'}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _guideBlock('멤버십 안내', '${g['membership'] ?? ''}'),
                _guideBlock('구매 자격', '${g['rules'] ?? ''}'),
                _guideBlock('멤버십 세트 구성', '${g['sets'] ?? ''}'),
                _guideBlock('유의사항 · 문의', '${g['notes'] ?? ''}'),
                const Divider(height: 22),
                Row(
                  children: [
                    const Icon(Icons.account_balance,
                        size: 16, color: AppColors.taegeukBlue),
                    const SizedBox(width: 6),
                    Text('납부계좌: ${acc['bank'] ?? ''} ${acc['no'] ?? ''}'
                        '${_shipFee > 0 ? '  (배송료 ${_won(_shipFee)} 별도)' : ''}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.taegeukBlue)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('예금주: ${acc['holder'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textGray)),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('공식 수품 구매 구글폼 열기',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }

  static const _formUrl =
      'https://docs.google.com/forms/d/e/1FAIpQLSeW24jatei6gRJGFYTCvqYfFipKImbQdT6gVKSFs9WxCKQY4A/viewform';

  Future<void> _openForm() async {
    final uri = Uri.parse(_formUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // ignore
    }
  }

  Widget _guideBlock(String title, String body) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: AppColors.purpleDark)),
          const SizedBox(height: 4),
          Text(body,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textDark, height: 1.5)),
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
