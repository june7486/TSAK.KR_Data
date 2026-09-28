import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/merch_order_detail.dart';
import 'order_detail_screen.dart';

/// 수품 판매관리 화면 (관리자·마스터 전용).
/// 탭: 판매관리 / 누적판매 / 재고 / 공여 / 제작자 / 설정
class MerchAdminScreen extends StatefulWidget {
  const MerchAdminScreen({super.key});

  @override
  State<MerchAdminScreen> createState() => _MerchAdminScreenState();
}

class _MerchAdminScreenState extends State<MerchAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 7, vsync: this);

  NasApi get _nas => context.read<NasApi>();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _reserves = [];
  List<Map<String, dynamic>> _makers = [];
  List<Map<String, dynamic>> _donations = [];
  List<Map<String, dynamic>> _stockLog = [];
  Map<String, dynamic> _config = {};
  Map<String, dynamic> _stats = {};

  // 수품판매대장(ledger)
  List<Map<String, dynamic>> _ledgerRows = [];
  Map<String, dynamic> _ledgerSummary = {};
  String _ledgerYear = '';
  String _ledgerMonth = '';
  String _ledgerKind = '';
  bool _ledgerLoading = false;
  late final TextEditingController _ledgerYearCtl =
      TextEditingController(text: _ledgerYear);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tab.dispose();
    _ledgerYearCtl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _list(dynamic v) => ((v as List?) ?? [])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _nas.merchAdmin();
      Map<String, dynamic> stats = {};
      try {
        final s = await _nas.merchReports();
        stats = ((s['stats'] as Map?) ?? {}).cast<String, dynamic>();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _products = _list(r['products']);
        _orders = _list(r['orders']);
        _reserves = _list(r['reservations']);
        _makers = _list(r['makers']);
        _donations = _list(r['donations']);
        _stockLog = _list(r['stockLog']);
        _config = ((r['config'] as Map?) ?? {}).cast<String, dynamic>();
        _stats = stats;
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

  // ---------- config getters ----------
  int get _annualFee => (_config['annualFee'] as num?)?.toInt() ?? 0;
  bool get _salesOpen => _config['salesOpen'] != false;
  bool get _feeRequired => _config['annualFeeRequired'] == true;
  bool get _reserveMode => _config['reserveMode'] == true;
  Map<String, dynamic> get _account =>
      ((_config['account'] as Map?) ?? {}).cast<String, dynamic>();
  Map<String, dynamic> get _guide =>
      ((_config['guide'] as Map?) ?? {}).cast<String, dynamic>();
  List<String> get _statuses =>
      ((_config['statuses'] as List?) ??
              const [
                "입금확인중",
                "입금확인",
                "상품준비중",
                "택배발송준비중",
                "택배발송",
                "배송완료",
                "현장수령완료",
                "주문취소",
              ])
          .map((e) => '$e')
          .toList();
  List<String> get _reserveStatuses =>
      ((_config['reserveStatuses'] as List?) ??
              const ["예약접수", "제작검토", "제작확정", "제작중", "입고완료", "취소"])
          .map((e) => '$e')
          .toList();

  String _won(num? v) {
    final s = (v?.toInt() ?? 0).abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${(v?.toInt() ?? 0) < 0 ? '-' : ''}${buf.toString()}원';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('수품 판매관리'),
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
          isScrollable: true,
          tabs: const [
            Tab(text: '판매관리'),
            Tab(text: '누적판매'),
            Tab(text: '판매대장'),
            Tab(text: '재고'),
            Tab(text: '공여'),
            Tab(text: '제작자'),
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
                _salesTab(),
                _reportsTab(),
                _ledgerTab(),
                _stockTab(),
                _donationTab(),
                _makerTab(),
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

  // ==================== 1) 판매관리 탭 ====================
  Widget _salesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        _noticeEditor(),
        const SizedBox(height: 14),
        _subHeader('소품(상품) 관리', '상품 등록·수정·판매중지 · 이미지/가격/사이즈/재고',
            Icons.shopping_bag_outlined),
        const SizedBox(height: 8),
        if (_products.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              '등록된 소품이 없습니다. 아래 + 버튼으로 추가하세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textGray),
            ),
          )
        else
          for (final p in _products) _productCard(p),
        const SizedBox(height: 8),
        _addProductButton(),
        const SizedBox(height: 16),
        _subHeader(
          '주문 내역 (${_groupCount(_orders)}건 / ${_orders.length}항목)',
          '주문번호별 통합 · 클릭하면 장바구니형 상세',
          Icons.receipt_long_outlined,
        ),
        const SizedBox(height: 8),
        if (_orders.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '주문이 없습니다',
              style: TextStyle(color: AppColors.textGray),
            ),
          )
        else
          for (final g in _groupBy(_orders)) _groupCard(g, isReserve: false),
        const SizedBox(height: 16),
        _subHeader(
          '예약·수요조사 (${_groupCount(_reserves)}건 / ${_reserves.length}항목)',
          '제작 판단용 접수 · 주문번호별 통합',
          Icons.bookmark_border,
        ),
        const SizedBox(height: 8),
        if (_reserves.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '예약 접수가 없습니다',
              style: TextStyle(color: AppColors.textGray),
            ),
          )
        else
          for (final g in _groupBy(_reserves)) _groupCard(g, isReserve: true),
      ],
    );
  }

  // ---------- 주문번호별 그룹핑 ----------
  static String _groupKeyOf(Map<String, dynamic> o) {
    final no = '${o['orderNo'] ?? ''}'.trim();
    if (no.isNotEmpty) return no;
    return '#${o['id'] ?? ''}';
  }

  /// 주문번호(또는 id)별로 그룹핑. 순서는 첫 등장 순서 유지.
  List<List<Map<String, dynamic>>> _groupBy(List<Map<String, dynamic>> src) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final o in src) {
      final k = _groupKeyOf(o);
      (map[k] ??= []).add(o);
    }
    return map.values.toList();
  }

  int _groupCount(List<Map<String, dynamic>> src) => _groupBy(src).length;

  /// 그룹 내 대표 항목(첫 품목).
  void _openGroup(List<Map<String, dynamic>> items, {required bool isReserve}) {
    if (items.isEmpty) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => OrderDetailScreen(
            groupKey: _groupKeyOf(items.first),
            initialItems: items,
            canManage: true,
            statuses: isReserve ? _reserveStatuses : _statuses,
            isReserve: isReserve,
          ),
        ))
        .then((_) => _load());
  }

  /// 그룹 요약 카드(주문번호 통합). 클릭 → 장바구니형 상세.
  Widget _groupCard(List<Map<String, dynamic>> items,
      {required bool isReserve}) {
    final head = items.first;
    final orderNo = '${head['orderNo'] ?? ''}'.trim();
    final buyer = '${head['buyerName'] ?? ''}'.trim();
    final created = '${head['created'] ?? head['createdAt'] ?? ''}'.trim();
    final allPaid = items.every((o) => o['paid'] == true);
    final anyCancelled =
        items.any((o) => '${o['status'] ?? ''}'.contains('취소'));
    final received = items.every((o) => o['received'] == true);
    final grand = items.fold<int>(
        0, (p, o) => p + ((o['grandTotal'] ?? o['total'] ?? 0) as num).toInt());
    final sumQty = items.fold<int>(
        0, (p, o) => p + ((o['qty'] as num?)?.toInt() ?? 1));
    final tone = isReserve
        ? Colors.orange
        : (anyCancelled
            ? Colors.red
            : (allPaid ? AppColors.scoutGreen : AppColors.taegeukRed));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: InkWell(
        onTap: () => _openGroup(items, isReserve: isReserve),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                      isReserve
                          ? Icons.bookmark_border
                          : Icons.receipt_long_outlined,
                      size: 15,
                      color: isReserve ? Colors.orange : AppColors.purple),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                        orderNo.isEmpty
                            ? (isReserve ? '(예약번호 없음)' : '(주문번호 없음)')
                            : '${isReserve ? '예약' : '주문'} $orderNo',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: AppColors.purpleDark,
                            letterSpacing: 0.2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (!isReserve)
                    _pill(allPaid ? '입금완료' : '미입금',
                        allPaid ? AppColors.scoutGreen : AppColors.taegeukRed),
                  if (received)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: _pill('수령확인', AppColors.tigerGold),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // 품목 미리보기 (장바구니처럼 나열)
              for (final o in items.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Text('· ',
                          style: TextStyle(color: AppColors.textGray)),
                      Expanded(
                        child: Text(
                          '${o['product'] ?? o['productName'] ?? '수품'} '
                          '×${(o['qty'] as num?)?.toInt() ?? 1}'
                          '${('${o['option'] ?? ''}'.trim()).isEmpty ? '' : ' / ${o['option']}'}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textDark),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              if (items.length > 4)
                Text('외 ${items.length - 4}개 품목…',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textGray)),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 13, color: AppColors.textGray),
                  const SizedBox(width: 3),
                  Text(buyer.isEmpty ? '구매자 미상' : buyer,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textDark)),
                  const SizedBox(width: 10),
                  const Icon(Icons.event_outlined,
                      size: 13, color: AppColors.textGray),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(created,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textGray),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const Spacer(),
                  Text('총 ${items.length}종 $sumQty개',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textGray)),
                  const SizedBox(width: 8),
                  Text(_won(grand),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              const Row(
                children: [
                  Text('장바구니형 상세 보기',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.purple,
                          fontWeight: FontWeight.w800)),
                  SizedBox(width: 3),
                  Icon(Icons.chevron_right, size: 16, color: AppColors.purple),
                  Spacer(),
                  Text('수량·금액·송장·인쇄',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.lifetimeGold,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noticeEditor() {
    final notices = TextEditingController(text: '${_config['notices'] ?? ''}');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.campaign_outlined,
                size: 18,
                color: AppColors.purple,
              ),
              const SizedBox(width: 6),
              const Text(
                '공지글 (구매창 상단 표시)',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: AppColors.purpleDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: notices,
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
            decoration: const InputDecoration(
              hintText: '예: 설 연휴 배송 일정 안내 / 신규 인가자 세트 입고 완료',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: () async {
                final r = await _nas.merchSaveConfig(notices: notices.text);
                if (!mounted) return;
                if (r['ok'] == true) {
                  _snack('공지글을 저장했습니다');
                  _load();
                } else {
                  _snack('저장 실패');
                }
              },
              icon: const Icon(Icons.save, size: 16),
              label: const Text('공지 저장'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> p) {
    final active = p['active'] != false;
    final options = ((p['options'] as List?) ?? []).map((e) => '$e').toList();
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final price = (p['price'] as num?)?.toInt() ?? 0;
    final imgUrl = _nas.merchImageUrl('${p['image'] ?? ''}');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (active ? AppColors.purple : AppColors.textGray).withValues(
            alpha: 0.15,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 56,
              height: 56,
              color: Colors.white,
              child: imgUrl.isEmpty
                  ? Icon(
                      active ? Icons.shopping_bag : Icons.visibility_off,
                      color: active ? AppColors.purple : AppColors.textGray,
                    )
                  : Image.network(
                      imgUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        active ? Icons.shopping_bag : Icons.visibility_off,
                        color: active ? AppColors.purple : AppColors.textGray,
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
                      child: Text(
                        '${p['name'] ?? ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    if (!active) _chip('판매중지'),
                    if (p['kind'] != null && '${p['kind']}'.isNotEmpty)
                      _chip('${p['kind']}'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _won(price),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.taegeukBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '재고 $stock개',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
                if (options.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '옵션: ${options.join(', ')}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _editProduct(existing: p);
              if (v == 'del') _deleteProduct(p);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('수정')),
              PopupMenuItem(value: 'del', child: Text('삭제')),
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
    String image = '${existing?['image'] ?? ''}';
    final size = TextEditingController(text: '${existing?['size'] ?? ''}');
    final options = TextEditingController(
      text: (((existing?['options'] as List?) ?? [])
          .map((e) => '$e')
          .join(', ')),
    );
    bool active = existing?['active'] != false;

    Future<void> pickImage(StateSetter setDlg) async {
      try {
        final files = await pickDataFiles(
            dialogTitle: '소품 이미지 선택', allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp']);
        if (files.isEmpty) return;
        final f = files.first;
        final b64 = base64Encode(f.bytes);
        final r = await _nas.merchImageUpload(f.name, b64);
        if (r['ok'] == true && r['file'] != null) {
          setDlg(() => image = '${r['file']}');
          if (mounted) _snack('이미지를 업로드했습니다');
        } else {
          if (mounted) _snack('이미지 업로드 실패: ${r['error']}');
        }
      } catch (e) {
        if (mounted) _snack('이미지 오류: $e');
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? '소품 등록' : '소품 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 이미지 미리보기 + 업로드
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 64,
                        height: 64,
                        color: AppColors.bg,
                        child: image.trim().isEmpty
                            ? const Icon(Icons.image_outlined,
                                color: AppColors.textGray)
                            : (image.startsWith('http')
                                ? Image.network(image, fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_outlined,
                                        color: AppColors.textGray))
                                : Image.network(
                                    _nas.merchImageUrl(image),
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_outlined,
                                        color: AppColors.textGray))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact),
                            onPressed: () => pickImage(setDlg),
                            icon: const Icon(Icons.upload_file, size: 16),
                            label: const Text('이미지 업로드'),
                          ),
                          if (image.trim().isNotEmpty)
                            TextButton(
                              style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact),
                              onPressed: () => setDlg(() => image = ''),
                              child: const Text('이미지 제거',
                                  style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _dlgField(name, '소품명'),
                _dlgField(kind, '종류 (예: 인가자 전용)'),
                _dlgField(price, '가격 (원)', number: true),
                _dlgField(stock, '재고 수량', number: true),
                _dlgField(options, '옵션 (쉼표 구분, 예: S,M,L / 58,60)'),
                _dlgField(size, '사이즈 안내 (자유 텍스트)'),
                _dlgField(desc, '설명'),
                // 사이즈 프리셋
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in const [
                        'S (28)',
                        'M (30)',
                        'L (32)',
                        'XL (34)',
                        'XXL (36)',
                      ])
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(s, style: const TextStyle(fontSize: 11)),
                          onPressed: () {
                            final cur = size.text.trim();
                            final parts = cur.isEmpty
                                ? <String>[]
                                : cur.split(',').map((e) => e.trim()).toList();
                            if (!parts.contains(s)) parts.add(s);
                            setDlg(() => size.text = parts.join(', '));
                          },
                        ),
                    ],
                  ),
                ),
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
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장'),
            ),
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
        size: size.text.trim(),
        image: image.trim(),
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
    final yes = await _confirm('상품 삭제', '"${p['name']}" 상품을 삭제할까요?');
    if (yes != true) return;
    final ok = await _nas.merchDeleteProduct('${p['id']}');
    if (!mounted) return;
    _snack(ok ? '삭제했습니다' : '삭제 실패');
    if (ok) _load();
  }

  /// 소품(상품) 추가 — 이미지/가격/사이즈/재고 등 기존 구성과 동일하게 등록.
  Widget _addProductButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.purple,
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(
              color: AppColors.purple.withValues(alpha: 0.5),
              style: BorderStyle.solid),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => _editProduct(existing: null),
        icon: const Icon(Icons.add_circle_outline, size: 20),
        label: const Text('소품 추가 (이미지·가격·사이즈·재고)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      ),
    );
  }

  /// 주문 카드 — 요약 정보만 표시(주문번호·대표상품·구매일·구매자·총금액).
  /// 주문번호를 누르면 상세내역이 열린다.
  void _showOrderDetail(Map<String, dynamic> rec, {required bool isReserve}) {
    MerchOrderDetail.show(
      context,
      rec: rec,
      isReserve: isReserve,
      statuses: isReserve ? _reserveStatuses : _statuses,
      editable: true,
      onChanged: _load,
      onDelete: () => _confirmDelete(rec, isReserve: isReserve),
    );
  }

  Future<bool> _confirmDelete(Map<String, dynamic> rec,
      {required bool isReserve}) async {
    final yes = await _confirm(
      isReserve ? '예약 삭제' : '주문 삭제',
      isReserve
          ? '"${rec['buyerName']}"님의 예약을 삭제할까요?'
          : '${rec['buyerName']}님의 "${rec['product'] ?? rec['productName']}" 주문을 삭제할까요?',
    );
    if (yes != true) return false;
    final ok = isReserve
        ? await _nas.merchDeleteReserve('${rec['id']}')
        : await _nas.merchDeleteOrder('${rec['id']}');
    if (!mounted) return ok;
    _snack(ok ? '삭제했습니다' : '삭제 실패');
    if (ok) await _load();
    return ok;
  }

  // ==================== 2) 누적판매 탭 ====================
  Widget _reportsTab() {
    final byStatus = ((_stats['byStatus'] as Map?) ?? {})
        .cast<String, dynamic>();
    final byMonth = ((_stats['byMonth'] as Map?) ?? {}).cast<String, dynamic>();
    final byProduct = ((_stats['byProduct'] as Map?) ?? {})
        .cast<String, dynamic>();
    final orderCount =
        (_stats['orderCount'] as num?)?.toInt() ?? _orders.length;
    final totalSales = (_stats['totalSales'] as num?)?.toInt() ?? 0;
    final totalFee = (_stats['totalAnnualFee'] as num?)?.toInt() ?? 0;
    final reserveCount =
        (_stats['reserveCount'] as num?)?.toInt() ?? _reserves.length;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            _statCard('총 주문', '$orderCount건', AppColors.purple),
            const SizedBox(width: 8),
            _statCard('총 매출', _won(totalSales), AppColors.taegeukBlue),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _statCard('연회비', _won(totalFee), AppColors.scoutGreen),
            const SizedBox(width: 8),
            _statCard('예약접수', '$reserveCount건', Colors.orange),
          ],
        ),
        const SizedBox(height: 12),
        _exportBar(),
        const SizedBox(height: 14),
        _sectionBox('진행 상태별', [
          if (byStatus.isEmpty)
            const Text('데이터 없음', style: TextStyle(color: AppColors.textGray))
          else
            for (final e in byStatus.entries) _kv(e.key, '${e.value}건'),
        ]),
        const SizedBox(height: 12),
        _sectionBox('월별 매출', [
          if (byMonth.isEmpty)
            const Text('데이터 없음', style: TextStyle(color: AppColors.textGray))
          else
            for (final e in byMonth.entries)
              _kv(e.key, _won((e.value as num?)?.toInt() ?? 0)),
        ]),
        const SizedBox(height: 12),
        _sectionBox('상품별 판매', [
          if (byProduct.isEmpty)
            const Text('데이터 없음', style: TextStyle(color: AppColors.textGray))
          else
            for (final e in byProduct.entries)
              _kv(e.key, () {
                final m = (e.value as Map?)?.cast<String, dynamic>() ?? {};
                return '${m['qty'] ?? 0}개 · ${_won((m['amount'] as num?)?.toInt() ?? 0)}';
              }()),
        ]),
      ],
    );
  }

  Widget _exportBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '내보내기 (출력)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppColors.purpleDark,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _exportBtn(
                Icons.table_chart_outlined,
                '엑셀(CSV)',
                () => _exportReport('csv'),
              ),
              _exportBtn(Icons.grid_on, '표 복사', () => _exportReport('clip')),
              _exportBtn(Icons.link, '링크 복사', () => _exportReport('link')),
              _exportBtn(
                Icons.print_outlined,
                '인쇄',
                () => _exportReport('print'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _exportBtn(IconData i, String t, VoidCallback onTap) =>
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: onTap,
        icon: Icon(i, size: 15),
        label: Text(t),
      );

  Future<void> _exportReport(String type) async {
    if (type == 'link') {
      final link = Uri.base.toString();
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) _snack('현재 페이지 링크를 복사했습니다');
      return;
    }
    if (type == 'print') {
      if (mounted) _snack('브라우저 인쇄(Ctrl+P)로 저장하세요');
      return;
    }
    final buf = StringBuffer();
    if (type == 'csv') {
      buf.writeln('구분,항목,수치');
      buf.writeln('총주문,${(_stats['orderCount'] ?? _orders.length)}건,');
      buf.writeln('총매출,${_stats['totalSales'] ?? 0},원');
      buf.writeln('연회비,${_stats['totalAnnualFee'] ?? 0},원');
      buf.writeln('예약접수,${_stats['reserveCount'] ?? _reserves.length}건,');
      final byStatus = ((_stats['byStatus'] as Map?) ?? {});
      for (final e in byStatus.entries) {
        buf.writeln('상태별,${e.key},${e.value}건');
      }
      final byProduct = ((_stats['byProduct'] as Map?) ?? {});
      for (final e in byProduct.entries) {
        final m = (e.value as Map?) ?? {};
        buf.writeln('상품별,${e.key},${m['qty'] ?? 0}개/${m['amount'] ?? 0}원');
      }
    } else {
      buf.writeln('수품 판매 리포트');
      buf.writeln('총 주문: ${_stats['orderCount'] ?? _orders.length}건');
      buf.writeln(
        '총 매출: ${_won((_stats['totalSales'] as num?)?.toInt() ?? 0)}',
      );
      buf.writeln(
        '연회비: ${_won((_stats['totalAnnualFee'] as num?)?.toInt() ?? 0)}',
      );
      buf.writeln('예약접수: ${_stats['reserveCount'] ?? _reserves.length}건');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) _snack(type == 'csv' ? 'CSV를 복사했습니다(엑셀에 붙여넣기)' : '표를 복사했습니다');
  }

  // ---------- 수품판매대장 로드 ----------
  Future<void> _loadLedger() async {
    setState(() => _ledgerLoading = true);
    try {
      final r = await _nas.merchLedger(
        year: _ledgerYear,
        month: _ledgerMonth,
        kind: _ledgerKind,
      );
      if (!mounted) return;
      setState(() {
        _ledgerRows = _list(r['rows']);
        _ledgerSummary = ((r['summary'] as Map?) ?? {}).cast<String, dynamic>();
        _ledgerLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _ledgerLoading = false);
      _snack('판매대장을 불러오지 못했습니다: $e');
    }
  }

  Future<void> _downloadLedgerCsv() async {
    final url = _nas.merchLedgerCsvUrl(year: _ledgerYear, month: _ledgerMonth);
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) _snack('다운로드를 열 수 없습니다');
    } catch (_) {
      // 일부 브라우저/플랫폼에서 실패 시 현재 창에서 시도
      try {
        await launchUrl(Uri.parse(url));
      } catch (_) {
        if (mounted) _snack('CSV 다운로드 링크: $url');
      }
    }
  }

  // ==================== 3) 판매대장 탭 ====================
  Widget _ledgerTab() {
    if (_ledgerRows.isEmpty &&
        _ledgerSummary.isEmpty &&
        !_ledgerLoading &&
        _ledgerYear.isEmpty &&
        _ledgerMonth.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLedger());
    }
    final amountTotal = (_ledgerSummary['amountTotal'] as num?)?.toInt() ?? 0;
    final orderCount = (_ledgerSummary['orderCount'] as num?)?.toInt() ?? 0;
    final reserveCount = (_ledgerSummary['reserveCount'] as num?)?.toInt() ?? 0;
    final paidCount = (_ledgerSummary['paidCount'] as num?)?.toInt() ?? 0;
    final unpaidCount = (_ledgerSummary['unpaidCount'] as num?)?.toInt() ?? 0;

    final months = <String>[''];
    for (int m = 1; m <= 12; m++) {
      months.add(m.toString().padLeft(2, '0'));
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _subHeader('수품판매대장', '주문·예약 통합 장부 · CSV 출력', Icons.receipt_long),
        const SizedBox(height: 10),
        Row(
          children: [
            _statCard('주문', '$orderCount건', AppColors.purple),
            const SizedBox(width: 8),
            _statCard('예약', '$reserveCount건', Colors.orange),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _statCard('매출합계', _won(amountTotal), AppColors.taegeukBlue),
            const SizedBox(width: 8),
            _statCard('입금/미입금', '$paidCount / $unpaidCount', AppColors.scoutGreen),
          ],
        ),
        const SizedBox(height: 12),
        // 필터 + 다운로드
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.purple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('기간/구분 필터',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.purpleDark)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ledgerYearCtl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        labelText: '연도',
                        hintText: '예: 2026',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => _ledgerYear = v.trim(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _ledgerMonth,
                      decoration: const InputDecoration(
                        labelText: '월',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final m in months)
                          DropdownMenuItem(
                            value: m,
                            child: Text(m.isEmpty ? '전체' : '$m월'),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _ledgerMonth = v ?? ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _ledgerKind,
                      decoration: const InputDecoration(
                        labelText: '구분',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('전체')),
                        DropdownMenuItem(value: '주문', child: Text('주문')),
                        DropdownMenuItem(value: '예약', child: Text('예약')),
                      ],
                      onChanged: (v) =>
                          setState(() => _ledgerKind = v ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: _ledgerLoading ? null : _loadLedger,
                    icon: const Icon(Icons.filter_alt_outlined, size: 16),
                    label: const Text('조회'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: _downloadLedgerCsv,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('판매대장 CSV'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: _ledgerYear.isEmpty && _ledgerMonth.isEmpty
                        ? null
                        : () {
                            _ledgerYearCtl.clear();
                            setState(() {
                              _ledgerYear = '';
                              _ledgerMonth = '';
                              _ledgerKind = '';
                            });
                            _loadLedger();
                          },
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('초기화'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_ledgerLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_ledgerRows.isEmpty)
          _sectionBox('판매대장', [
            const Text('조회된 내역이 없습니다.',
                style: TextStyle(color: AppColors.textGray)),
          ])
        else
          _sectionBox('판매대장 (${_ledgerRows.length}건)', [
            for (final row in _ledgerRows) _ledgerRow(row),
          ]),
      ],
    );
  }

  Widget _ledgerRow(Map<String, dynamic> row) {
    final kind = (row['_kind'] ?? row['kind'] ?? '').toString();
    final orderNo = (row['orderNo'] ?? '').toString();
    final buyer = (row['buyerName'] ?? row['name'] ?? '').toString();
    final created = (row['created'] ?? '').toString();
    final product = (row['product'] ?? '').toString();
    final qty = (row['qty'] as num?)?.toInt() ?? 1;
    final amount = (row['grandTotal'] ?? row['total'] ?? row['amount'] ?? 0);
    final status = (row['status'] ?? '').toString();
    final paid = row['paid'] == true;
    final isOrder = kind == '주문';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _pill(kind.isEmpty ? (isOrder ? '주문' : '예약') : kind,
                  isOrder ? AppColors.purple : Colors.orange),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: () => _showOrderDetail(row, isReserve: !isOrder),
                  borderRadius: BorderRadius.circular(6),
                  child: Text(orderNo.isEmpty ? '(번호 없음)' : '$orderNo  ›',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: AppColors.purpleDark,
                          letterSpacing: 0.2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              Text(_won((amount as num?)?.toInt() ?? 0),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 5),
          InkWell(
            onTap: () => _showBuyerHistory(
              buyer.isEmpty ? '주문자 미상' : buyer,
              (row['contactId'] ?? row['buyerNumber'] ?? '').toString(),
            ),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 13, color: AppColors.taegeukBlue),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${buyer.isEmpty ? '주문자 미상' : buyer} · '
                      '${product.isEmpty ? '상품' : product}${qty > 1 ? ' ×$qty' : ''}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.taegeukBlue),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Text('  이력',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.taegeukBlue,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text(created.isEmpty ? '-' : created,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textGray)),
              const Spacer(),
              if (status.isNotEmpty)
                Text(status,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.purpleDark,
                        fontWeight: FontWeight.w700)),
              if (isOrder) ...[
                const SizedBox(width: 8),
                Text(paid ? '입금완료' : '미입금',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: paid ? AppColors.scoutGreen : AppColors.taegeukRed)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 주문자별 주문 이력 조회(대장에서 주문자명 클릭).
  void _showBuyerHistory(String buyerName, String ident) {
    final d = ident.replaceAll(RegExp(r'[^0-9]'), '');
    bool match(Map<String, dynamic> r) {
      if (d.isNotEmpty) {
        for (final k in const ['contactId', 'buyerNumber', 'phone']) {
          if ('${r[k] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '') == d) {
            return true;
          }
        }
      }
      return '${r['buyerName'] ?? ''}'.trim() == buyerName.trim();
    }

    final orders = _orders.where(match).toList()
      ..sort((a, b) => '${b['created']}'.compareTo('${a['created']}'));
    final reserves = _reserves.where(match).toList()
      ..sort((a, b) => '${b['created']}'.compareTo('${a['created']}'));
    int sumOf(List<Map<String, dynamic>> xs) => xs.fold(
        0, (p, o) => p + ((o['grandTotal'] ?? o['total'] ?? 0) as num).toInt());

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.history, size: 20, color: AppColors.taegeukBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$buyerName 주문 이력',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('주문 ${orders.length}건 · 예약 ${reserves.length}건',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textGray)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (orders.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.scoutGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text('총 주문금액(합계): ${_won(sumOf(orders))}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.scoutGreen)),
                  ),
                const SizedBox(height: 10),
                if (orders.isEmpty && reserves.isEmpty)
                  const Text('이 주문자의 내역이 없습니다.',
                      style: TextStyle(color: AppColors.textGray)),
                for (final o in orders)
                  _buyerHistoryTile(o, isReserve: false),
                for (final r in reserves) _buyerHistoryTile(r, isReserve: true),
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

  Widget _buyerHistoryTile(Map<String, dynamic> r, {required bool isReserve}) {
    final paid = r['paid'] == true;
    final amount = (r['grandTotal'] ?? r['total'] ?? r['_amount'] ?? 0);
    return InkWell(
      onTap: () => _showOrderDetail(r, isReserve: isReserve),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: (isReserve ? Colors.orange : AppColors.purple)
                  .withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(isReserve ? Icons.bookmark_border : Icons.receipt_long,
                size: 15,
                color: isReserve ? Colors.orange : AppColors.purple),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['orderNo'] ?? '(번호 없음)'}',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w800)),
                  Text(
                    '${r['product'] ?? ''}'
                    '${(r['qty'] as num?)?.toInt() != null ? ' ×${r['qty']}' : ''}'
                    ' · ${r['created'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textGray),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_won((amount as num?)?.toInt() ?? 0),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                Text(
                  isReserve
                      ? '${r['status'] ?? '예약'}'
                      : (paid ? '입금완료' : '미입금'),
                  style: TextStyle(
                      fontSize: 10,
                      color: isReserve
                          ? Colors.orange
                          : (paid
                              ? AppColors.scoutGreen
                              : AppColors.taegeukRed)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 4) 재고 탭 ====================
  Widget _stockTab() {
    final stock = ((_stats['stock'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        _subHeader('재고 현황', '상품별 재고 및 입출고 조정', Icons.inventory_2_outlined),
        const SizedBox(height: 8),
        if (stock.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '재고 데이터가 없습니다',
              style: TextStyle(color: AppColors.textGray),
            ),
          )
        else
          for (final s in stock) _stockRow(s),
        const SizedBox(height: 16),
        _subHeader('재고 입출고 기록 (${_stockLog.length})', '변동 이력', Icons.history),
        const SizedBox(height: 8),
        _sectionBox('최근 기록', [
          if (_stockLog.isEmpty)
            const Text('기록 없음', style: TextStyle(color: AppColors.textGray))
          else
            for (final l in _stockLog.take(30))
              _kv(
                '${l['product'] ?? l['name'] ?? ''} '
                    '${((l['delta'] as num?)?.toInt() ?? 0) > 0 ? '+' : ''}${l['delta'] ?? 0}',
                '${l['at'] ?? l['created'] ?? ''}'
                    '${'${l['note'] ?? ''}'.isNotEmpty ? ' · ${l['note']}' : ''}',
              ),
        ]),
      ],
    );
  }

  Widget _stockRow(Map<String, dynamic> s) {
    final name = '${s['name'] ?? ''}';
    final stock = (s['stock'] as num?)?.toInt() ?? 0;
    final sold = (s['sold'] as num?)?.toInt() ?? 0;
    final low = stock <= 5;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (low ? AppColors.taegeukRed : AppColors.purple).withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              _pill(
                '재고 $stock',
                low ? AppColors.taegeukRed : AppColors.scoutGreen,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '누적판매 $sold개',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _miniStockBtn(s, -1, '−1'),
              _miniStockBtn(s, 1, '+1'),
              _miniStockBtn(s, 10, '+10'),
              _miniStockBtn(s, -10, '−10'),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _adjustStock(s, null),
                icon: const Icon(Icons.edit, size: 15),
                label: const Text('직접입력'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStockBtn(Map<String, dynamic> s, int delta, String label) =>
      OutlinedButton(
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: () => _adjustStock(s, delta),
        child: Text(label),
      );

  Future<void> _adjustStock(Map<String, dynamic> s, int? delta) async {
    final id = '${s['id']}';
    if (delta != null) {
      final r = await _nas.merchStock(id, delta);
      if (!mounted) return;
      if (r['ok'] == true) {
        _snack('재고를 조정했습니다');
        _load();
      } else {
        _snack('조정 실패');
      }
      return;
    }
    final c = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('재고 조정 · ${s['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '변동 수량 (+ 입고 / - 출고)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: '사유', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final d = int.tryParse(c.text.trim()) ?? 0;
    if (d == 0) return;
    final r = await _nas.merchStock(id, d, note: note.text.trim());
    if (!mounted) return;
    if (r['ok'] == true) {
      _snack('재고를 조정했습니다');
      _load();
    } else {
      _snack('조정 실패');
    }
  }

  // ==================== 4) 공여 탭 ====================
  Widget _donationTab() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editDonation(),
        icon: const Icon(Icons.add),
        label: const Text('공여 기록'),
        backgroundColor: AppColors.purple,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          _subHeader(
            '수품 공여 (행사·홍보)',
            '수품을 무상 제공한 내역 관리',
            Icons.volunteer_activism_outlined,
          ),
          const SizedBox(height: 8),
          if (_donations.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '공여 기록이 없습니다',
                style: TextStyle(color: AppColors.textGray),
              ),
            )
          else
            for (final d in _donations) _donationCard(d),
        ],
      ),
    );
  }

  Widget _donationCard(Map<String, dynamic> d) {
    final qty = (d['qty'] as num?)?.toInt() ?? 0;
    final amount = (d['amount'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${d['product'] ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              _chip('${d['kind'] ?? d['category'] ?? '공여'}'),
            ],
          ),
          const SizedBox(height: 4),
          _row('수량', '$qty개'),
          if (amount > 0) _row('금액', _won(amount)),
          if ('${d['recipient'] ?? ''}'.isNotEmpty)
            _row('수령처', '${d['recipient']}'),
          if ('${d['event'] ?? ''}'.isNotEmpty) _row('행사', '${d['event']}'),
          _row('일자', '${d['date'] ?? d['created'] ?? ''}'),
          if ('${d['memo'] ?? ''}'.isNotEmpty) _row('메모', '${d['memo']}'),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _editDonation(existing: d),
                icon: const Icon(Icons.edit, size: 15),
                label: const Text('수정'),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  final r = await _nas.merchSaveDonation({
                    'id': '${d['id']}',
                    'delete': true,
                  });
                  if (!mounted) return;
                  if (r['ok'] == true) _load();
                },
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('삭제'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editDonation({Map<String, dynamic>? existing}) async {
    final product = TextEditingController(
      text: '${existing?['product'] ?? ''}',
    );
    final qty = TextEditingController(text: '${existing?['qty'] ?? ''}');
    final amount = TextEditingController(text: '${existing?['amount'] ?? ''}');
    final recipient = TextEditingController(
      text: '${existing?['recipient'] ?? ''}',
    );
    final event = TextEditingController(text: '${existing?['event'] ?? ''}');
    final date = TextEditingController(text: '${existing?['date'] ?? ''}');
    final memo = TextEditingController(text: '${existing?['memo'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '수품 공여 기록' : '공여 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dlgField(product, '수품명'),
              _dlgField(qty, '수량', number: true),
              _dlgField(amount, '금액 (원, 선택)', number: true),
              _dlgField(recipient, '수령처 (기관/개인)'),
              _dlgField(event, '행사명 (선택)'),
              _dlgField(date, '일자 (예: 2026-03-01)'),
              _dlgField(memo, '메모'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _nas.merchSaveDonation({
      'id': '${existing?['id'] ?? ''}',
      'product': product.text.trim(),
      'qty': int.tryParse(qty.text.trim()) ?? 0,
      'amount': int.tryParse(amount.text.trim()) ?? 0,
      'recipient': recipient.text.trim(),
      'event': event.text.trim(),
      'date': date.text.trim(),
      'memo': memo.text.trim(),
    });
    if (!mounted) return;
    if (r['ok'] == true) {
      _snack('저장했습니다');
      _load();
    } else {
      _snack('저장 실패');
    }
  }

  // ==================== 5) 제작자 탭 ====================
  Widget _makerTab() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editMaker(),
        icon: const Icon(Icons.add),
        label: const Text('제작자 등록'),
        backgroundColor: AppColors.purple,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          _subHeader(
            '수품 제작자 관리',
            '제작자 정보·견적·입금·배송·진행상황',
            Icons.factory_outlined,
          ),
          const SizedBox(height: 8),
          if (_makers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '등록된 제작자가 없습니다',
                style: TextStyle(color: AppColors.textGray),
              ),
            )
          else
            for (final m in _makers) _makerCard(m),
        ],
      ),
    );
  }

  Widget _makerCard(Map<String, dynamic> m) {
    final files = ((m['extraFiles'] as List?) ?? []).map((e) => '$e').toList();
    final progress = ((m['progress'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final photo = '${m['photo'] ?? ''}';
    final photoUrl = photo.isEmpty
        ? ''
        : (photo.startsWith('http') ? photo : _nas.merchFileUrl(photo));
    final quote = '${m['quoteFile'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    photoUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _chipBox(),
                  ),
                ),
              if (photoUrl.isNotEmpty) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${m['company'] ?? m['name'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if ('${m['category'] ?? ''}'.isNotEmpty)
                          _chip('${m['category']}'),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if ('${m['ceo'] ?? ''}'.isNotEmpty)
                      _row('대표자', '${m['ceo']}'),
                    if ('${m['manager'] ?? ''}'.isNotEmpty)
                      _row('담당자', '${m['manager']}'),
                    if ('${m['phone'] ?? ''}'.isNotEmpty)
                      _row('연락처', '${m['phone']}'),
                    if ('${m['email'] ?? ''}'.isNotEmpty)
                      _row('이메일', '${m['email']}'),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          _row('제작일', '${m['madeDate'] ?? '-'}'),
          _row('제작단가', _won((m['unitPrice'] as num?)?.toInt() ?? 0)),
          _row('금액', _won((m['amount'] as num?)?.toInt() ?? 0)),
          _row('입금일', '${m['paidDate'] ?? '-'}'),
          _row('배송일', '${m['shipDate'] ?? '-'}'),
          if (quote.isNotEmpty) ...[
            const SizedBox(height: 4),
            _fileChip(quote, '견적서'),
          ],
          if (files.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final f in files) _fileChip(f, null)],
            ),
          ],
          if (progress.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '주문 진행상황',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
            const SizedBox(height: 4),
            for (final p in progress)
              _kv('${p['date'] ?? ''}', '${p['note'] ?? p['content'] ?? ''}'),
          ],
          if ('${m['memo'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 4),
            _row('메모', '${m['memo']}'),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _editMaker(existing: m),
                icon: const Icon(Icons.edit, size: 15),
                label: const Text('수정'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _deleteMaker(m),
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('삭제'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _exportMaker,
                icon: const Icon(Icons.table_chart_outlined, size: 15),
                label: const Text('내보내기'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipBox() => Container(
    width: 52,
    height: 52,
    color: AppColors.purple.withValues(alpha: 0.08),
    child: const Icon(Icons.image, color: AppColors.purple),
  );

  Widget _fileChip(String name, String? label) => InkWell(
    onTap: () {
      final url = name.startsWith('http') ? name : _nas.merchFileUrl(name);
      Clipboard.setData(ClipboardData(text: url));
      _snack('파일 링크를 복사했습니다: $url');
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_file, size: 13, color: AppColors.purple),
          const SizedBox(width: 3),
          Text(
            '${label ?? ''}${label != null ? ': ' : ''}$name',
            style: const TextStyle(fontSize: 11, color: AppColors.purple),
          ),
        ],
      ),
    ),
  );

  Future<void> _editMaker({Map<String, dynamic>? existing}) async {
    final category = TextEditingController(
      text: '${existing?['category'] ?? ''}',
    );
    final company = TextEditingController(
      text: '${existing?['company'] ?? ''}',
    );
    final ceo = TextEditingController(text: '${existing?['ceo'] ?? ''}');
    final manager = TextEditingController(
      text: '${existing?['manager'] ?? ''}',
    );
    final phone = TextEditingController(text: '${existing?['phone'] ?? ''}');
    final email = TextEditingController(text: '${existing?['email'] ?? ''}');
    final madeDate = TextEditingController(
      text: '${existing?['madeDate'] ?? ''}',
    );
    final unitPrice = TextEditingController(
      text: '${existing?['unitPrice'] ?? ''}',
    );
    final amount = TextEditingController(text: '${existing?['amount'] ?? ''}');
    final paidDate = TextEditingController(
      text: '${existing?['paidDate'] ?? ''}',
    );
    final shipDate = TextEditingController(
      text: '${existing?['shipDate'] ?? ''}',
    );
    final memo = TextEditingController(text: '${existing?['memo'] ?? ''}');
    String quoteFile = '${existing?['quoteFile'] ?? ''}';
    String photo = '${existing?['photo'] ?? ''}';
    final List<String> extraFiles = ((existing?['extraFiles'] as List?) ?? [])
        .map((e) => '$e')
        .toList();
    final List<Map<String, dynamic>> progress =
        ((existing?['progress'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? '제작자 등록' : '제작자 수정'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dlgField(category, '제작 구분 (예: 패치/메달/의류)'),
                  _dlgField(company, '제작자 상호'),
                  _dlgField(ceo, '대표자'),
                  _dlgField(manager, '담당자'),
                  _dlgField(phone, '연락처'),
                  _dlgField(email, '이메일'),
                  _dlgField(madeDate, '제작일'),
                  _dlgField(unitPrice, '제작단가 (원)', number: true),
                  _dlgField(amount, '금액 (원)', number: true),
                  _dlgField(paidDate, '입금일'),
                  _dlgField(shipDate, '배송일'),
                  const Divider(),
                  _fileRow(
                    '견적서 파일',
                    quoteFile,
                    () => _pickFile((n) => setDlg(() => quoteFile = n)),
                    () => setDlg(() => quoteFile = ''),
                  ),
                  _fileRow(
                    '사진 파일',
                    photo,
                    () => _pickFile((n) => setDlg(() => photo = n)),
                    () => setDlg(() => photo = ''),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '기타 파일',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGray,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _pickFile((n) => setDlg(() => extraFiles.add(n))),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('추가'),
                      ),
                    ],
                  ),
                  for (final f in extraFiles)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '· $f',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          icon: const Icon(Icons.close),
                          onPressed: () => setDlg(() => extraFiles.remove(f)),
                        ),
                      ],
                    ),
                  const Divider(),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '주문 진행상황',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _addProgress(progress, setDlg),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('추가'),
                      ),
                    ],
                  ),
                  for (final p in progress)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${p['date'] ?? ''} · ${p['note'] ?? ''}',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            icon: const Icon(Icons.close),
                            onPressed: () => setDlg(() => progress.remove(p)),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  _dlgField(memo, '메모'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final r = await _nas.merchSaveMaker({
      'id': '${existing?['id'] ?? ''}',
      'category': category.text.trim(),
      'company': company.text.trim(),
      'ceo': ceo.text.trim(),
      'manager': manager.text.trim(),
      'phone': phone.text.trim(),
      'email': email.text.trim(),
      'madeDate': madeDate.text.trim(),
      'unitPrice': int.tryParse(unitPrice.text.trim()) ?? 0,
      'amount': int.tryParse(amount.text.trim()) ?? 0,
      'paidDate': paidDate.text.trim(),
      'shipDate': shipDate.text.trim(),
      'quoteFile': quoteFile,
      'photo': photo,
      'extraFiles': extraFiles,
      'progress': progress,
      'memo': memo.text.trim(),
    });
    if (!mounted) return;
    if (r['ok'] == true) {
      _snack('저장했습니다');
      _load();
    } else {
      _snack('저장 실패');
    }
  }

  Widget _fileRow(
    String label,
    String value,
    VoidCallback pick,
    VoidCallback clear,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value.isEmpty ? '$label (없음)' : '$label: $value',
              style: TextStyle(
                fontSize: 12,
                color: value.isEmpty ? AppColors.textGray : AppColors.textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: pick,
            child: const Text('선택', style: TextStyle(fontSize: 12)),
          ),
          if (value.isNotEmpty)
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: const Icon(Icons.close),
              onPressed: clear,
            ),
        ],
      ),
    );
  }

  Future<void> _pickFile(ValueChanged<String> onPicked) async {
    try {
      final files = await pickDataFiles(dialogTitle: '파일 선택');
      if (files.isEmpty) return;
      for (final f in files) {
        final b64 = base64Encode(f.bytes);
        final r = await _nas.merchMakerUpload(f.name, b64);
        if (r['ok'] == true && r['file'] != null) {
          onPicked('${r['file']}');
        } else {
          _snack('업로드 실패: ${r['error']}');
        }
      }
    } catch (e) {
      _snack('파일 오류: $e');
    }
  }

  Future<void> _addProgress(
    List<Map<String, dynamic>> progress,
    StateSetter setDlg,
  ) async {
    final date = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('진행상황 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dlgField(date, '날짜 (예: 2026-03-01)'),
            _dlgField(note, '진행 내용'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setDlg(
      () => progress.add({'date': date.text.trim(), 'note': note.text.trim()}),
    );
  }

  Future<void> _deleteMaker(Map<String, dynamic> m) async {
    final yes = await _confirm(
      '제작자 삭제',
      '"${m['company'] ?? m['name']}" 제작자를 삭제할까요?',
    );
    if (yes != true) return;
    final ok = await _nas.merchDeleteMaker('${m['id']}');
    if (!mounted) return;
    _snack(ok ? '삭제했습니다' : '삭제 실패');
    if (ok) _load();
  }

  Future<void> _exportMaker() async {
    final buf = StringBuffer();
    buf.writeln('수품 제작자 목록');
    for (final m in _makers) {
      buf.writeln(
        '${m['company'] ?? ''},${m['ceo'] ?? ''},${m['manager'] ?? ''},'
        '${m['phone'] ?? ''},${m['email'] ?? ''},${m['madeDate'] ?? ''},'
        '${m['unitPrice'] ?? 0},${m['amount'] ?? 0},${m['paidDate'] ?? ''},${m['shipDate'] ?? ''}',
      );
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) _snack('제작자 목록을 복사했습니다(엑셀 붙여넣기)');
  }

  // ==================== 6) 설정 탭 ====================
  Widget _configTab() {
    final fee = TextEditingController(text: '$_annualFee');
    final bank = TextEditingController(text: '${_account['bank'] ?? ''}');
    final no = TextEditingController(text: '${_account['no'] ?? ''}');
    final holder = TextEditingController(text: '${_account['holder'] ?? ''}');
    final shipFee = TextEditingController(
      text: '${(_account['shipFee'] as num?)?.toInt() ?? 0}',
    );
    final gTitle = TextEditingController(text: '${_guide['title'] ?? ''}');
    final gMembership = TextEditingController(
      text: '${_guide['membership'] ?? ''}',
    );
    final gRules = TextEditingController(text: '${_guide['rules'] ?? ''}');
    final gSets = TextEditingController(text: '${_guide['sets'] ?? ''}');
    final gNotes = TextEditingController(text: '${_guide['notes'] ?? ''}');
    final statusesCtl = TextEditingController(text: _statuses.join(', '));
    final rStatusesCtl = TextEditingController(
      text: _reserveStatuses.join(', '),
    );
    bool open = _salesOpen;
    bool strict = _feeRequired;
    bool reserve = _reserveMode;

    return StatefulBuilder(
      builder: (ctx, setSt) => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text(
            '판매 설정',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.purpleDark,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.12),
              ),
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
                _dlgField(fee, '연회비 (원)', number: true),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('연회비 엄격모드'),
                  subtitle: Text(
                    strict ? '연회비 미납자는 주문 차단' : '구매 시 연회비 납부여부를 직접 선택(면제/추가)',
                  ),
                  value: strict,
                  onChanged: (v) => setSt(() => strict = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('예약·수요조사 모드'),
                  subtitle: Text(
                    reserve ? '구매 대신 "예약"으로 접수 (제작 판단용)' : '일반 판매 모드',
                  ),
                  value: reserve,
                  onChanged: (v) => setSt(() => reserve = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '수품계좌 (입금 안내)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.purpleDark,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.12),
              ),
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
              const Icon(
                Icons.menu_book_outlined,
                size: 18,
                color: AppColors.purple,
              ),
              const SizedBox(width: 6),
              const Text(
                '수품 안내문 (구매창에 표시)',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.purpleDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            '구글폼 공식 안내와 연계 — 여기 수정하면 구매창에 바로 반영됩니다.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.12),
              ),
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
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.timeline, size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              const Text(
                '진행 상태 목록 관리',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.purpleDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            '쉼표로 구분 · 순서가 진행 단계 순서입니다(개인 프로필 진행바에 반영).',
            style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              children: [
                _dlgField(statusesCtl, '주문 진행 상태 (순서대로)'),
                _dlgField(rStatusesCtl, '예약 진행 상태 (순서대로)'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.purple,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () async {
              final r = await _nas.merchSaveConfig(
                annualFee: int.tryParse(fee.text.trim()) ?? _annualFee,
                salesOpen: open,
                annualFeeRequired: strict,
                reserveMode: reserve,
                statuses: statusesCtl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList(),
                reserveStatuses: rStatusesCtl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList(),
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
  Widget _subHeader(String title, String sub, IconData icon) => Row(
    children: [
      Icon(icon, size: 18, color: AppColors.purple),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.purpleDark,
              ),
            ),
            Text(
              sub,
              style: const TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _statCard(String label, String value, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: c,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
        ],
      ),
    ),
  );

  Widget _sectionBox(String title, List<Widget> children) => Container(
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
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: AppColors.purpleDark,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textDark),
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.purple,
          ),
        ),
      ],
    ),
  );

  Widget _chip(String t) => Container(
    margin: const EdgeInsets.only(left: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.purple.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 10.5,
        color: AppColors.purple,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _pill(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      t,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c),
    ),
  );

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            k,
            style: const TextStyle(fontSize: 12, color: AppColors.textGray),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textDark),
          ),
        ),
      ],
    ),
  );

  Widget _dlgField(
    TextEditingController c,
    String label, {
    bool number = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

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

  Future<bool?> _confirm(String title, String msg) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
