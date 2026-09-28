import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';

/// 수품구매 관리자 화면 — 상품/주문/설정(연회비·수품계좌) 관리.
/// 관리자(app)·마스터 전용.
class MerchAdminScreen extends StatefulWidget {
  const MerchAdminScreen({super.key});

  @override
  State<MerchAdminScreen> createState() => _MerchAdminScreenState();
}

class _MerchAdminScreenState extends State<MerchAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  NasApi get _nas => context.read<NasApi>();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic> _config = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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
        _products = ((r['products'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _orders = ((r['orders'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _config = ((r['config'] as Map?) ?? {}).cast<String, dynamic>();
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

  int get _annualFee => (_config['annualFee'] as num?)?.toInt() ?? 0;
  bool get _salesOpen => _config['salesOpen'] != false;
  Map<String, dynamic> get _account =>
      ((_config['account'] as Map?) ?? {}).cast<String, dynamic>();
  Map<String, dynamic> get _guide =>
      ((_config['guide'] as Map?) ?? {}).cast<String, dynamic>();

  int get _paidCount => _orders.where((o) => o['paid'] == true).length;
  int get _unpaidCount => _orders.where((o) => o['paid'] != true).length;
  int get _totalAmount => _orders.fold<int>(
      0, (s, o) => s + ((o['total'] as num?)?.toInt() ?? 0));

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
        title: const Text('수품구매 관리'),
        actions: [
          const AppHomeEmblem(size: 22),
          IconButton(
            tooltip: '새로고침',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '상품'),
            Tab(text: '주문'),
            Tab(text: '설정'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : TabBarView(
                  controller: _tab,
                  children: [
                    _productsTab(),
                    _ordersTab(),
                    _configTab(),
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

  // ==================== 상품 탭 ====================
  Widget _productsTab() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editProduct(),
        icon: const Icon(Icons.add),
        label: const Text('상품 등록'),
        backgroundColor: AppColors.purple,
      ),
      body: _products.isEmpty
          ? const Center(
              child: Text('등록된 상품이 없습니다\n우측 하단 버튼으로 등록하세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textGray)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: _products.length,
              itemBuilder: (_, i) => _productCard(_products[i]),
            ),
    );
  }

  Widget _productCard(Map<String, dynamic> p) {
    final active = p['active'] != false;
    final options = ((p['options'] as List?) ?? []).map((e) => '$e').toList();
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final price = (p['price'] as num?)?.toInt() ?? 0;
    final imgUrl = context.read<NasApi>().merchImageUrl('${p['image'] ?? ''}');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 56,
              height: 56,
              color: AppColors.purple.withValues(alpha: 0.08),
              child: imgUrl.isEmpty
                  ? Icon(
                      active ? Icons.shopping_bag : Icons.visibility_off,
                      color: active ? AppColors.purple : AppColors.textGray,
                    )
                  : Image.network(
                      imgUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        active ? Icons.shopping_bag : Icons.visibility_off,
                        color:
                            active ? AppColors.purple : AppColors.textGray,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${p['name'] ?? ''}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                    if (p['kind'] != null && '${p['kind']}'.isNotEmpty)
                      _chip('${p['kind']}'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(_won(price),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.taegeukBlue)),
                    const SizedBox(width: 10),
                    Text('재고 $stock개',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textGray)),
                  ],
                ),
                if (options.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('옵션: ${options.join(', ')}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGray)),
                ],
                if ('${p['desc'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('${p['desc']}',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textDark)),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _editProduct(existing: p);
              if (v == 'del') _deleteProduct(p);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('수정')),
              const PopupMenuItem(value: 'del', child: Text('삭제')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editProduct({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: '${existing?['name'] ?? ''}');
    final kind = TextEditingController(text: '${existing?['kind'] ?? ''}');
    final price = TextEditingController(text: '${existing?['price'] ?? ''}');
    final stock = TextEditingController(text: '${existing?['stock'] ?? ''}');
    final desc = TextEditingController(text: '${existing?['desc'] ?? ''}');
    final image = TextEditingController(text: '${existing?['image'] ?? ''}');
    final options = TextEditingController(
        text: (((existing?['options'] as List?) ?? []).map((e) => '$e').join(', ')));
    bool active = existing?['active'] != false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? '상품 등록' : '상품 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dlgField(name, '상품명'),
                _dlgField(kind, '종류 (예: 의류/기념품)'),
                _dlgField(price, '가격 (원)', number: true),
                _dlgField(stock, '재고 수량', number: true),
                _dlgField(options, '옵션 (쉼표 구분, 예: S,M,L)'),
                _dlgField(image, '이미지 (파일명 또는 URL)'),
                _dlgField(desc, '설명'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('판매중'),
                  value: active,
                  onChanged: (v) => setDlg(() => active = v),
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
                child: const Text('저장')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final optList = options.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    try {
      final r = await _nas.merchSaveProduct(
        id: '${existing?['id'] ?? ''}',
        name: name.text.trim(),
        kind: kind.text.trim(),
        price: int.tryParse(price.text.trim()) ?? 0,
        stock: int.tryParse(stock.text.trim()) ?? 0,
        options: optList,
        image: image.text.trim(),
        desc: desc.text.trim(),
        active: active,
      );
      if (!mounted) return;
      if (r['ok'] == true) {
        _snack('저장했습니다');
        _load();
      } else {
        _snack('저장 실패: ${r['error']}');
      }
    } catch (e) {
      if (mounted) _snack('오류: $e');
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('상품 삭제'),
        content: Text('"${p['name']}" 상품을 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await _nas.merchDeleteProduct('${p['id']}');
    if (!mounted) return;
    _snack(ok ? '삭제했습니다' : '삭제 실패');
    if (ok) _load();
  }

  // ==================== 주문 탭 ====================
  Widget _ordersTab() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('주문', '${_orders.length}건', AppColors.purple),
              _stat('입금완료', '$_paidCount건', AppColors.scoutGreen),
              _stat('미입금', '$_unpaidCount건', AppColors.taegeukRed),
              _stat('총액', _won(_totalAmount), AppColors.taegeukBlue),
            ],
          ),
        ),
        Expanded(
          child: _orders.isEmpty
              ? const Center(
                  child: Text('주문이 없습니다',
                      style: TextStyle(color: AppColors.textGray)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                  itemCount: _orders.length,
                  itemBuilder: (_, i) => _orderCard(_orders[i]),
                ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color c) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14, color: c)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.textGray)),
        ],
      );

  Widget _orderCard(Map<String, dynamic> o) {
    final paid = o['paid'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: paid
                ? AppColors.scoutGreen.withValues(alpha: 0.3)
                : AppColors.taegeukRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${o['product'] ?? ''}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (paid ? AppColors.scoutGreen : AppColors.taegeukRed)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(paid ? '입금완료' : '미입금',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: paid ? AppColors.scoutGreen : AppColors.taegeukRed)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _row('구매자', '${o['buyerName'] ?? ''}'
              '${'${o['buyerNumber'] ?? ''}'.isNotEmpty ? ' (${o['buyerNumber']})' : ''}'),
          if ('${o['phone'] ?? ''}'.isNotEmpty) _row('연락처', '${o['phone']}'),
          if ('${o['email'] ?? ''}'.isNotEmpty) _row('이메일', '${o['email']}'),
          _row('수량·합계',
              '${o['qty'] ?? 1}개${'${o['option'] ?? ''}'.isNotEmpty ? ' / ${o['option']}' : ''} · ${_won((o['total'] as num?)?.toInt() ?? 0)}'),
          _row('배송', '${o['shipMethod'] ?? ''}'
              '${'${o['address'] ?? ''}'.isNotEmpty ? ' · ${o['address']}' : ''}'),
          _row('주문일', '${o['created'] ?? ''}'),
          if ('${o['memo'] ?? ''}'.isNotEmpty) _row('메모', '${o['memo']}'),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: () => _togglePaid(o),
                icon: Icon(
                    paid ? Icons.undo : Icons.check_circle_outline,
                    size: 16),
                label: Text(paid ? '입금 취소' : '입금 처리'),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: () => _editOrderMemo(o),
                icon: const Icon(Icons.edit_note, size: 16),
                label: const Text('메모'),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: '주문 삭제',
                icon: const Icon(Icons.delete_outline, color: AppColors.textGray),
                onPressed: () => _deleteOrder(o),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textGray)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textDark)),
            ),
          ],
        ),
      );

  Future<void> _togglePaid(Map<String, dynamic> o) async {
    final r = await _nas.merchUpdateOrder(
        id: '${o['id']}', paid: o['paid'] != true);
    if (!mounted) return;
    if (r['ok'] == true) {
      _load();
    } else {
      _snack('변경 실패');
    }
  }

  Future<void> _editOrderMemo(Map<String, dynamic> o) async {
    final memo = TextEditingController(text: '${o['memo'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('주문 메모'),
        content: TextField(
          controller: memo,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '관리 메모'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _nas.merchUpdateOrder(id: '${o['id']}', memo: memo.text);
    if (!mounted) return;
    if (r['ok'] == true) {
      _load();
    } else {
      _snack('저장 실패');
    }
  }

  Future<void> _deleteOrder(Map<String, dynamic> o) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('주문 삭제'),
        content: Text('${o['buyerName']}님의 "${o['product']}" 주문을 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await _nas.merchDeleteOrder('${o['id']}');
    if (!mounted) return;
    _snack(ok ? '삭제했습니다' : '삭제 실패');
    if (ok) _load();
  }

  // ==================== 설정 탭 ====================
  Widget _configTab() {
    final fee = TextEditingController(text: '$_annualFee');
    final bank = TextEditingController(text: '${_account['bank'] ?? ''}');
    final no = TextEditingController(text: '${_account['no'] ?? ''}');
    final holder = TextEditingController(text: '${_account['holder'] ?? ''}');
    final shipFee =
        TextEditingController(text: '${(_account['shipFee'] as num?)?.toInt() ?? 0}');
    final gTitle = TextEditingController(text: '${_guide['title'] ?? ''}');
    final gMembership =
        TextEditingController(text: '${_guide['membership'] ?? ''}');
    final gRules = TextEditingController(text: '${_guide['rules'] ?? ''}');
    final gSets = TextEditingController(text: '${_guide['sets'] ?? ''}');
    final gNotes = TextEditingController(text: '${_guide['notes'] ?? ''}');
    bool open = _salesOpen;

    return StatefulBuilder(
      builder: (ctx, setSt) => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text('판매 설정',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.purpleDark)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('판매창 열기'),
                  subtitle: Text(open ? '비로그인 구매 가능' : '판매 중지 상태'),
                  value: open,
                  onChanged: (v) => setSt(() => open = v),
                ),
                const Divider(),
                _dlgField(fee, '연회비 (원) — 전체 상품 구매 전 필수', number: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('수품계좌 (입금 안내)',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.purpleDark)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                _dlgField(bank, '은행'),
                _dlgField(no, '계좌번호'),
                _dlgField(holder, '예금주'),
                _dlgField(shipFee, '택배 배송료 (원)', number: true),
                const SizedBox(height: 6),
                const Text(
                  '입금자명은 "인가자이름+수품구매" 로 안내됩니다.\n'
                  '교환·반품 배송비는 구매자 부담입니다.',
                  style: TextStyle(fontSize: 12, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.menu_book_outlined,
                  size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              const Text('수품 안내문 (구매창에 표시)',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.purpleDark)),
            ],
          ),
          const SizedBox(height: 2),
          const Text('구글폼 공식 안내와 연계 — 여기 수정하면 구매창에 바로 반영됩니다.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textGray)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                _dlgField(gTitle, '안내 제목'),
                _multiField(gMembership, '멤버십 안내'),
                _multiField(gRules, '구매 자격'),
                _multiField(gSets, '멤버십 세트 구성'),
                _multiField(gNotes, '유의사항 · 문의'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              final r = await _nas.merchSaveConfig(
                annualFee: int.tryParse(fee.text.trim()) ?? _annualFee,
                salesOpen: open,
                account: {
                  'bank': bank.text.trim(),
                  'no': no.text.trim(),
                  'holder': holder.text.trim(),
                  'shipFee': int.tryParse(shipFee.text.trim()) ?? 0,
                },
                guide: {
                  'title': gTitle.text,
                  'membership': gMembership.text,
                  'rules': gRules.text,
                  'sets': gSets.text,
                  'notes': gNotes.text,
                },
              );
              if (!mounted) return;
              if (r['ok'] == true) {
                _snack('설정을 저장했습니다');
                _load();
              } else {
                _snack('저장 실패');
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('설정 저장'),
          ),
        ],
      ),
    );
  }

  // ==================== 공용 위젯 ====================
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

  Widget _dlgField(TextEditingController c, String label,
      {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  /// 여러 줄 안내문 입력 필드.
  Widget _multiField(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: 6,
        minLines: 3,
        style: const TextStyle(fontSize: 12.5, height: 1.4),
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
