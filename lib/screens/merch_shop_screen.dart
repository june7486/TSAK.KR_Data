import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/hscroll_menu.dart';
import 'merch_checkout_screen.dart';

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
  /// 상품 카드별 수량(장바구니 담기 전 선택값). 키 = 상품 id.
  final Map<String, int> _cardQty = {};
  String _sort = '기본'; // 기본 | 낮은가격 | 높은가격 | 이름

  int _qtyOf(Map<String, dynamic> p) =>
      _cardQty['${p['id']}'] ?? 1;

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
  bool get _reserveMode => _config['reserveMode'] == true;
  Map<String, dynamic> get _account =>
      ((_config['account'] as Map?) ?? {}).cast<String, dynamic>();
  Map<String, dynamic> get _guide =>
      ((_config['guide'] as Map?) ?? {}).cast<String, dynamic>();
  int get _shipFee => (_account['shipFee'] as num?)?.toInt() ?? 0;

  int get _cartCount => _cart.fold<int>(0, (s, e) => s + e.qty);
  int get _cartTotal => _cart.fold<int>(0, (s, e) => s + e.total);

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
      // 안전영역 + 키보드 대응: 하단바가 항상 보이도록 SafeArea 로 감싼다.
      bottomNavigationBar:
          _loading || _error != null ? null : SafeArea(top: false, child: _cartBar()),
    );
  }

  /// 화면 폭에 맞춰 카드 높이를 넉넉히 계산 → '장바구니' 버튼이 잘리지 않도록.
  double _cardAspect(double screenW) {
    final cardW = (screenW - 14 * 2 - 12) / 2;
    // 이미지(정사각) + 정보영역(약 172px) 확보
    return cardW / (cardW + 172);
  }

  Widget _body() {
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (ctx, c) {
          final aspect = _cardAspect(c.maxWidth);
          return CustomScrollView(
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
                  // 하단 장바구니 바(약 76px)에 가려지지 않도록 여백 확보
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
                  sliver: SliverGrid(
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: aspect,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _productCard(_sortedProducts[i]),
                      childCount: _sortedProducts.length,
                    ),
                  ),
                ),
            ],
          );
        },
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
            child: HScrollMenu(
              height: 40,
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
          // 안내: 예약(수요조사) 모드 안내
          if (_reserveMode) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.tigerGold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '※ 현재 예약(수요조사) 기간입니다.\n'
                '   구매 의사가 있으시면 "예약"으로 신청해 주세요.\n'
                '   일정 수량 이상 예약 시 제작이 확정됩니다.',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, height: 1.45),
              ),
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
    final qty = _qtyOf(p);
    final credentialOnly = p['credentialOnly'] == true;
    return Container(
      decoration: BoxDecoration(
        // 인가자 전용 상품은 바탕색을 다르게
        color: credentialOnly ? const Color(0xFFE6F4F1) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (credentialOnly ? AppColors.scoutGreen : AppColors.purple)
              .withValues(alpha: credentialOnly ? 0.55 : 0.12),
          width: credentialOnly ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이미지: 크롭 없이 전체가 보이도록 contain
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFFF7F5FB),
              child: imgUrl.isEmpty
                  ? const Center(
                      child: Icon(Icons.image_outlined,
                          size: 40, color: AppColors.textGray))
                  : Image.network(
                      imgUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, prog) => prog == null
                          ? child
                          : const Center(
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                      errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.image_not_supported,
                              color: AppColors.textGray)),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                // 인가자 전용 — 상품명 말머리 표시
                if (credentialOnly)
                  Container(
                    margin: const EdgeInsets.only(bottom: 3),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.scoutGreen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('범인가자 전용',
                        style: TextStyle(
                            fontSize: 9.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w900)),
                  ),
                Text('${p['name'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 2),
                Text('${p['desc'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textGray)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(price > 0 ? _won(price) : '가격문의',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: AppColors.taegeukBlue)),
                    ),
                    Text(soldOut ? '품절' : '재고 $stock',
                        style: TextStyle(
                            fontSize: 10,
                            color: soldOut
                                ? AppColors.taegeukRed
                                : AppColors.textGray)),
                  ],
                ),
                const SizedBox(height: 6),
                // ── 수량 선택 + 장바구니 (한 줄) ──
                Row(
                  children: [
                    _qtyBtn('-', () {
                      if (qty > 1) setState(() => _cardQty['${p['id']}'] = qty - 1);
                    }),
                    Expanded(
                      child: Center(
                        child: Text('$qty',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                      ),
                    ),
                    _qtyBtn('+', () {
                      final max = stock > 0 ? stock : 99;
                      if (qty < max) setState(() => _cardQty['${p['id']}'] = qty + 1);
                    }),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 34,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: soldOut || (!_salesOpen && !_reserveMode)
                                ? AppColors.textGray
                                : (_reserveMode
                                    ? AppColors.tigerGold
                                    : AppColors.purple),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: (soldOut || (!_salesOpen && !_reserveMode))
                              ? null
                              : () => _reserveMode
                                  ? _reserve(p, options, qty)
                                  : _addToCart(p, options, qty),
                          child: Text(_reserveMode ? '예약' : '담기',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: _reserveMode
                                      ? Colors.black87
                                      : Colors.white)),
                        ),
                      ),
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

  // ==================== 장바구니 ====================
  void _addToCart(Map<String, dynamic> p, List<String> options, [int qty = 1]) {
    if (options.isEmpty) {
      _mergeCart(p, '', qty);
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
                  _mergeCart(p, o, qty);
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

  // 예약(수요조사) — 장바구니 없이 단일 품목 예약 신청 화면으로 이동.
  Future<void> _reserve(
      Map<String, dynamic> p, List<String> options, int qty) async {
    if (options.isNotEmpty) {
      final chosen = await showDialog<String>(
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
                  onTap: () => Navigator.pop(ctx, o),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ],
        ),
      );
      if (chosen == null) return;
      _doReserve(p, chosen, qty);
      return;
    }
    _doReserve(p, '', qty);
  }

  Future<void> _doReserve(
      Map<String, dynamic> p, String option, int qty) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MerchCheckoutScreen(
          lines: [
            {
              'productId': '${p['id']}',
              'name': '${p['name']}',
              'image': '${p['image'] ?? ''}',
              'price': (p['price'] as num?)?.toInt() ?? 0,
              'option': option,
              'qty': qty,
            }
          ],
          config: _config,
          mode: 'reserve',
        ),
      ),
    );
    if (ok == true) {
      _snack('예약이 접수되었습니다. (${p['name']}'
          '${option.isNotEmpty ? ' / $option' : ''} × $qty)');
    }
  }

  void _mergeCart(Map<String, dynamic> p, String option, [int qty = 1]) {
    final idx = _cart.indexWhere(
        (e) => e.key == '${p['id']}::${option.trim()}');
    setState(() {
      if (idx >= 0) {
        _cart[idx].qty += qty;
      } else {
        _cart.add(_CartLine(p, option, qty));
      }
    });
    _snack(
        '장바구니에 담았습니다 (${p['name']}${option.isNotEmpty ? ' / $option' : ''} × $qty)');
  }

  Widget _cartBar() {
    final has = _cart.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 좌측: 개수·합계 (없으면 안내)
          Expanded(
            child: has
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shopping_cart,
                              size: 15, color: AppColors.purple),
                          const SizedBox(width: 4),
                          Text('장바구니 $_cartCount개',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textGray,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                      Text(_won(_cartTotal),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppColors.taegeukBlue)),
                    ],
                  )
                : const Text('장바구니가 비어 있습니다\n상품을 골라 담아주세요',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textGray, height: 1.3)),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onPressed: has ? _openCart : null,
            child: const Text('장바구니', style: TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(width: 6),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.purple,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: (has && _salesOpen) ? _checkout : null,
            child: const Text('주문하기',
                style:
                    TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
        ],
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
                                    _qtyBtn('-', () {
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
                                    _qtyBtn('+', () {
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

  /// 수량 증감 버튼 — 아이콘 글리프(tree-shaking) 이슈 회피를 위해 부호 문자 사용.
  Widget _qtyBtn(String sign, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(sign,
              style: const TextStyle(
                  fontSize: 17,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  color: AppColors.purple)),
        ),
      );

  // ==================== 결제(주문) 단계 ====================
  //  팝업 대신 전용 페이지(MerchCheckoutScreen)로 이동 → 모든 브라우저 오류 없이 동작.
  Future<void> _checkout({String mode = 'order'}) async {
    if (_cart.isEmpty) return;
    final lines = _cart
        .map((l) => <String, dynamic>{
              'productId': '${l.product['id']}',
              'name': '${l.product['name']}',
              'image': '${l.product['image'] ?? ''}',
              'price': l.price,
              'option': l.option,
              'qty': l.qty,
            })
        .toList();
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MerchCheckoutScreen(
          lines: lines,
          config: _config,
          mode: mode,
        ),
      ),
    );
    if (ok == true) {
      setState(() => _cart.clear());
      _load();
    }
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
                if (_formUrl.trim().isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: Text(_formLabel,
                        style: const TextStyle(fontSize: 12)),
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

  // 연계 구매 링크(구글폼·네이버폼 등) — 관리자 설정(guide.formUrl)에서 읽어온다.
  // 주소가 유동적이므로 하드코딩하지 않고, 비어 있으면 버튼을 숨긴다.
  static const _fallbackFormUrl =
      'https://docs.google.com/forms/d/e/1FAIpQLSeW24jatei6gRJGFYTCvqYfFipKImbQdT6gVKSFs9WxCKQY4A/viewform';

  String get _formUrl {
    final u = '${_guide['formUrl'] ?? ''}'.trim();
    return u.isEmpty ? _fallbackFormUrl : u;
  }

  String get _formLabel {
    final l = '${_guide['formLabel'] ?? ''}'.trim();
    return l.isEmpty ? '공식 수품 구매 링크 열기' : l;
  }

  Future<void> _openForm() async {
    final raw = _formUrl;
    var url = raw;
    // 사용자가 'naver.me/xxx' 처럼 스킴 없이 입력한 경우 https:// 를 붙여준다.
    if (!url.startsWith('http://') &&
        !url.startsWith('https://') &&
        !url.startsWith('mailto:')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
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
