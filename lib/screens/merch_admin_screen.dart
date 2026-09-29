import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/file_pick.dart';
import '../services/app_state.dart';
import '../services/nas_api.dart';
import '../services/print_doc.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/hscroll_menu.dart';
import '../widgets/merch_order_detail.dart';
import 'order_detail_screen.dart';
import 'supplies_screen.dart';
import 'purchase_screen.dart';
import 'plans_tab.dart';

/// 수품 판매관리 화면 (관리자·마스터 전용).
/// 탭: 판매관리 / 누적판매 / 재고 / 공여 / 제작자 / 설정
class MerchAdminScreen extends StatefulWidget {
  const MerchAdminScreen({super.key});

  @override
  State<MerchAdminScreen> createState() => _MerchAdminScreenState();
}

class _MerchAdminScreenState extends State<MerchAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 8, vsync: this);

  NasApi get _nas => context.read<NasApi>();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _reserves = [];
  List<Map<String, dynamic>> _deletedOrders = [];
  List<Map<String, dynamic>> _deletedReserves = [];
  List<Map<String, dynamic>> _makers = [];
  List<Map<String, dynamic>> _donations = [];
  List<Map<String, dynamic>> _stockLog = [];
  List<Map<String, dynamic>> _purchases = [];
  Map<String, dynamic> _config = {};
  Map<String, dynamic> _stats = {};
  // 주문 일괄편집/순서/보관
  List<String> _orderOrder = [];
  List<Map<String, dynamic>> _bundles = [];
  bool _selMode = false;
  final Set<String> _selKeys = {};
  bool _showArchive = false;
  bool _archiveLoading = false;
  final List<Map<String, dynamic>> _archived = [];
  // 주문내역별 보기 — ON 시 주문번호 묶음 내부를 주문번호별로 펼쳐서 노출
  bool _perOrderView = false;

  // 수품판매대장(ledger)
  List<Map<String, dynamic>> _ledgerRows = [];
  Map<String, dynamic> _ledgerSummary = {};
  String _ledgerYear = '';
  String _ledgerMonth = '';
  String _ledgerKind = '';
  bool _ledgerLoading = false;
  late final TextEditingController _ledgerYearCtl = TextEditingController(
    text: _ledgerYear,
  );

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
      final allOrders = _list(r['orders']);
      final allReserves = _list(r['reservations']);
      setState(() {
        _products = _list(r['products']);
        // 삭제(소프트)된 것은 주문관리 본문이 아닌 '삭제됨' 영역에서 관리.
        _orders = allOrders.where((o) => o['deleted'] != true).toList();
        _reserves = allReserves.where((o) => o['deleted'] != true).toList();
        _deletedOrders = allOrders.where((o) => o['deleted'] == true).toList();
        _deletedReserves = allReserves
            .where((o) => o['deleted'] == true)
            .toList();
        _orderOrder = ((r['orderOrder'] as List?) ?? [])
            .map((e) => '$e')
            .toList();
        _bundles = _list(r['bundles']);
        _makers = _list(r['makers']);
        _donations = _list(r['donations']);
        _stockLog = _list(r['stockLog']);
        _purchases = _list(r['purchases']);
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
  /// 견적서/사업자등록증 파일 열람권한 관리자 허용 여부(마스터 전용 설정).
  bool get _makerFileAdminAllowed =>
      _config['makerFileAdminAllowed'] == true;
  /// 견적서 기반 판매상품 세부항목 관리자 노출 허용 여부(마스터 전용 설정).
  bool get _quoteSpecAdminAllowed =>
      _config['quoteSpecAdminAllowed'] == true;
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            color: AppColors.purple,
            padding: const EdgeInsets.only(bottom: 4),
            child: HScrollMenu(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: _tabLabels.asMap().entries.map((e) {
                  final i = e.key;
                  final selected = _tab.index == i;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _tab.index = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? AppColors.purpleDark
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
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
                _reportsTab(),
                _ledgerTab(),
                _stockTab(),
                const SuppliesScreen(embedded: true),
                const PurchaseScreen(embedded: true),
                const PlansTab(),
                _donationTab(),
                _makerTab(),
                _configTab(),
              ],
            ),
    );
  }

  static const List<String> _tabLabels = [
    '상품관리',
    '주문관리',
    '누적판매',
    '판매대장',
    '재고',
    '비품재고',
    '물건결제',
    '기획실',
    '공여',
    '제작자',
    '설정',
  ];

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

  // ==================== 1) 상품(소품) 관리 탭 ====================
  Widget _productsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        _noticeEditor(),
        const SizedBox(height: 14),
        _subHeader(
          '소품(상품) 관리',
          '좌측 손잡이를 끌어 순서 변경 · 등록·수정·판매중지 · 인가자 전용/일반 구분',
          Icons.shopping_bag_outlined,
        ),
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
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _products.length,
            onReorder: _onReorderProducts,
            itemBuilder: (ctx, i) {
              final p = _products[i];
              return Container(
                key: ValueKey('prod-${p['id']}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 좌측 순서변경 손잡이 (마우스/손가락으로 끌어 이동, 항상 노출)
                      ReorderableDragStartListener(
                        index: i,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Container(
                            width: 40,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: AppColors.purple.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.purple.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.drag_indicator,
                                  size: 20,
                                  color: AppColors.purple,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '순서변경',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.purple.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: _productCard(p, inList: true)),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        _addProductButton(),
      ],
    );
  }

  /// 상품 순서 변경 — 즉시 UI 반영 후 저장(실패 시 스낵바).
  Future<void> _onReorderProducts(int oldI, int newI) async {
    if (newI > oldI) newI -= 1;
    setState(() {
      final moved = _products.removeAt(oldI);
      _products.insert(newI, moved);
    });
    final ids = _products.map((p) => '${p['id']}').toList();
    final ok = await _nas.merchProductsOrder(ids);
    if (!ok && mounted) _snack('순서 저장 실패');
  }

  // ==================== 2) 주문 관리 탭 ====================
  Widget _ordersTab() {
    // 표시 순서(orderOrder)에 따라 그룹 정렬
    final groups = _orderedGroups(_orders);
    final reserveGroups = _orderedGroups(_reserves);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        _bulkToolbar(),
        const SizedBox(height: 8),
        _subHeader(
          '주문 내역 (${groups.length}건 / ${_orders.length}항목)',
          '주문번호별 통합 · 체크박스로 일괄편집 · 주문번호 클릭 시 상세',
          Icons.receipt_long_outlined,
        ),
        const SizedBox(height: 8),
        _perOrderToggle(),
        const SizedBox(height: 8),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '주문이 없습니다',
              style: TextStyle(color: AppColors.textGray),
            ),
          )
        else if (_perOrderView)
          // 주문내역별 보기: 주문번호 다음 주문내역·다음 주문번호 순으로 펼침
          for (final g in groups) ..._perOrderBlocks(g, isReserve: false)
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: groups.length,
            onReorder: (a, b) => _onReorderGroups(groups, a, b),
            itemBuilder: (ctx, i) {
              final g = groups[i];
              final k = _groupKeyOf(g.first);
              return Container(
                key: ValueKey('ord-$k'),
                margin: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_selMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Checkbox(
                            value: _selKeys.contains(k),
                            onChanged: (_) => _toggleSel(k),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      Expanded(child: _groupCard(g, isReserve: false)),
                      // 우측 순서변경 손잡이 — 좌측 체크박스와 높이·정렬 통일(항상 노출)
                      ReorderableDragStartListener(
                        index: i,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Container(
                            width: 44,
                            height: 52,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              color: AppColors.purple.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.purple.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.drag_indicator,
                                  size: 20,
                                  color: AppColors.purple,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '순서변경',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.purple.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 16),
        _subHeader(
          '예약·수요조사 (${reserveGroups.length}건 / ${_reserves.length}항목)',
          '제작 판단용 접수 · 주문번호별 통합',
          Icons.bookmark_border,
        ),
        const SizedBox(height: 8),
        if (reserveGroups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '예약 접수가 없습니다',
              style: TextStyle(color: AppColors.textGray),
            ),
          )
        else if (_perOrderView)
          for (final g in reserveGroups) ..._perOrderBlocks(g, isReserve: true)
        else
          for (final g in reserveGroups) _groupCard(g, isReserve: true),
        const SizedBox(height: 20),
        _deletedSection(),
        const SizedBox(height: 10),
        if (_showArchive) _archiveSection(),
      ],
    );
  }

  // ---------- 주문내역별 보기 토글 ----------
  /// ON 시 주문번호 묶음 내부를 "주문번호 → 주문내역" 순으로 펼쳐
  /// 합치기 전 개별 주문 상황을 확인할 수 있게 한다.
  Widget _perOrderToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _perOrderView
            ? AppColors.taegeukBlue.withValues(alpha: 0.10)
            : AppColors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (_perOrderView ? AppColors.taegeukBlue : AppColors.purple)
              .withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _perOrderView ? Icons.view_list : Icons.view_agenda_outlined,
            size: 18,
            color: _perOrderView ? AppColors.taegeukBlue : AppColors.purple,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '주문내역별 보기',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppColors.purpleDark,
                  ),
                ),
                Text(
                  'ON: 주문번호 → 주문내역 순으로 펼쳐 합치기 전 상황 확인',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          Switch(
            value: _perOrderView,
            activeThumbColor: AppColors.taegeukBlue,
            onChanged: (v) => setState(() => _perOrderView = v),
          ),
        ],
      ),
    );
  }

  /// 주문내역별 보기 블록 — 주문번호 헤더 + 품목별 개별 내역 줄.
  List<Widget> _perOrderBlocks(
    List<Map<String, dynamic>> items, {
    required bool isReserve,
  }) {
    final head = items.first;
    final orderNo = '${head['orderNo'] ?? ''}'.trim();
    final buyer = '${head['buyerName'] ?? ''}'.trim();
    final created = '${head['created'] ?? head['createdAt'] ?? ''}'.trim();
    final grand = items.fold<int>(
      0,
      (p, o) => p + ((o['grandTotal'] ?? o['total'] ?? 0) as num).toInt(),
    );
    final bundle = _bundleNameOf(items);
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (isReserve ? Colors.orange : AppColors.purple)
                .withValues(alpha: 0.30),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 주문번호 헤더(중요 tag) ──
            Row(
              children: [
                Icon(
                  isReserve ? Icons.bookmark_border : Icons.receipt_long_outlined,
                  size: 15,
                  color: isReserve ? Colors.orange : AppColors.purple,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    orderNo.isEmpty ? '(번호없음) ' : orderNo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.purpleDark,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _pill('${items.length}항목', AppColors.textGray),
              ],
            ),
            if (buyer.isNotEmpty || created.isNotEmpty || bundle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '$buyer'
                  '${created.isNotEmpty ? ' · $created' : ''}'
                  '${bundle != null ? ' · 묶음:$bundle' : ''}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textGray,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Divider(height: 14),
            // ── 주문내역 개별 라인 ──
            for (final o in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: InkWell(
                        onTap: () =>
                            _openGroup([o], isReserve: isReserve),
                        child: const Icon(Icons.edit,
                            size: 11, color: AppColors.purple),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${o['product'] ?? o['productName'] ?? '수품'} '
                        '×${(o['qty'] as num?)?.toInt() ?? 1}'
                        '${('${o['option'] ?? ''}'.trim()).isEmpty ? '' : ' / ${o['option']}'}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isReserve) ...[
                      _pill(
                        '${o['status'] ?? ''}'.trim().isEmpty
                            ? '접수'
                            : '${o['status']}',
                        AppColors.textGray,
                      ),
                      const SizedBox(width: 4),
                      _pill(
                        o['paid'] == true ? '입금' : '미입금',
                        o['paid'] == true
                            ? AppColors.scoutGreen
                            : AppColors.taegeukRed,
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '합계 ${_won(grand)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppColors.taegeukBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // ---------- 일괄편집 툴바 ----------
  Widget _bulkToolbar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _selMode
            ? AppColors.purple.withValues(alpha: 0.08)
            : AppColors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _selMode ? Icons.checklist : Icons.tune,
                size: 17,
                color: AppColors.purple,
              ),
              const SizedBox(width: 6),
              Text(
                _selMode ? '일괄편집 모드' : '주문 일괄편집',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: AppColors.purpleDark,
                ),
              ),
              const Spacer(),
              Switch.adaptive(
                value: _selMode,
                onChanged: (v) => setState(() {
                  _selMode = v;
                  if (!v) _selKeys.clear();
                }),
              ),
            ],
          ),
          if (_selMode) ...[
            const SizedBox(height: 4),
            Text(
              '선택 ${_selKeys.length}건 · 우측 「순서변경」 손잡이를 끌어 이동',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.taegeukBlue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: _selKeys.length >= 2 ? _mergeSelected : null,
                  icon: const Icon(Icons.merge_type, size: 16),
                  label: const Text('주문 합치기', style: TextStyle(fontSize: 12.5)),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.taegeukRed,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: _selKeys.isEmpty ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('주문 삭제', style: TextStyle(fontSize: 12.5)),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.purpleDark,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: _selKeys.isEmpty
                      ? null
                      : () => setState(() => _selKeys.clear()),
                  icon: const Icon(Icons.deselect, size: 16),
                  label: const Text('선택 해제', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 삭제된 주문(30일 보관) ----------
  Widget _deletedSection() {
    final deleted = <List<Map<String, dynamic>>>[
      ..._orderedGroups(_deletedOrders),
      ..._orderedGroups(_deletedReserves),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.delete_outline, size: 17, color: Colors.red),
              const SizedBox(width: 6),
              Text(
                '삭제된 주문 (${deleted.length}건)',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '※ 삭제 후 30일간 보관되며, 30일이 지나면 목록에서 사라집니다. '
            '(아래 "30일 초과 삭제 내역"에서 계속 확인 가능)',
            style: TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
          const SizedBox(height: 8),
          if (deleted.isEmpty)
            const Text(
              '삭제된 주문이 없습니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            )
          else
            for (final g in deleted) _deletedRow(g),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.purpleDark,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _loadArchive,
            icon: const Icon(Icons.history, size: 16),
            label: Text(
              _showArchive ? '30일 초과 삭제 내역 숨기기' : '30일 초과 삭제 주문내역 확인',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deletedRow(List<Map<String, dynamic>> items) {
    final head = items.first;
    final k = _groupKeyOf(head);
    final orderNo = '${head['orderNo'] ?? ''}'.trim();
    final buyer = '${head['buyerName'] ?? ''}'.trim();
    final deletedAt = '${head['deletedAt'] ?? ''}';
    final days = _daysLeft(deletedAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${orderNo.isEmpty ? '(번호없음)' : orderNo} · $buyer',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '삭제 ${deletedAt.isEmpty ? '' : deletedAt} · '
                  '${days > 0 ? 'D-$days ($days일 후 완전삭제)' : '곧 완전삭제'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: AppColors.scoutGreen,
            ),
            onPressed: () => _restoreKeys([k]),
            icon: const Icon(Icons.restore, size: 15),
            label: const Text('복원', style: TextStyle(fontSize: 12)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '완전 삭제',
            icon: const Icon(Icons.delete_forever, size: 17, color: Colors.red),
            onPressed: () => _hardDeleteKeys([k]),
          ),
        ],
      ),
    );
  }

  Widget _archiveSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textGray.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 17,
                color: AppColors.textGray,
              ),
              const SizedBox(width: 6),
              Text(
                '30일 초과 삭제 주문내역 보관함 (${_archived.length}건)',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '※ 삭제 후 30일이 지나 목록에서 사라진 내역입니다. 영구 보전되어 확인만 가능합니다.',
            style: TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
          const SizedBox(height: 8),
          if (_archiveLoading)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else if (_archived.isEmpty)
            const Text(
              '보관된 내역이 없습니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            )
          else
            for (final a in _archived) _archiveRow(a),
        ],
      ),
    );
  }

  Widget _archiveRow(Map<String, dynamic> a) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(
            Icons.archive_outlined,
            size: 13,
            color: AppColors.textGray,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '${a['orderNo'] ?? ''} · ${a['buyerName'] ?? ''} · ${a['product'] ?? ''}',
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${a['_archivedAt'] ?? ''}',
            style: const TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  // ---------- 주문번호별 그룹핑 ----------
  /// 그룹 키 — 백엔드 `_merch_group_key`와 동일 규칙.
  /// 합쳐진 주문은 bundleId('B:...')로, 아니면 주문번호로 묶는다.
  static String _groupKeyOf(Map<String, dynamic> o) {
    final b = '${o['bundleId'] ?? ''}'.trim();
    if (b.isNotEmpty) return 'B:$b';
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

  /// 그룹의 묶음 이름(합쳐진 주문이면 이름, 아니면 null).
  String? _bundleNameOf(List<Map<String, dynamic>> items) {
    final bid = '${items.first['bundleId'] ?? ''}'.trim();
    if (bid.isEmpty) return null;
    for (final b in _bundles) {
      if ('${b['id']}' == bid) return '${b['name'] ?? bid}';
    }
    return bid;
  }

  /// orderOrder(백엔드 표시순서)에 맞춰 그룹을 정렬. 배열에 없는 그룹은 뒤에.
  List<List<Map<String, dynamic>>> _orderedGroups(
    List<Map<String, dynamic>> src,
  ) {
    final groups = _groupBy(src);
    final idx = <String, int>{};
    for (int i = 0; i < _orderOrder.length; i++) {
      idx[_orderOrder[i]] = i;
    }
    groups.sort((a, b) {
      final ia = idx[_groupKeyOf(a.first)] ?? 9999;
      final ib = idx[_groupKeyOf(b.first)] ?? 9999;
      return ia.compareTo(ib);
    });
    return groups;
  }

  // ----- 선택 -----
  void _toggleSel(String k) {
    setState(() {
      if (_selKeys.contains(k)) {
        _selKeys.remove(k);
      } else {
        _selKeys.add(k);
      }
    });
  }

  // ----- 드래그 재정렬 -----
  Future<void> _onReorderGroups(
    List<List<Map<String, dynamic>>> groups,
    int oldI,
    int newI,
  ) async {
    if (newI > oldI) newI -= 1;
    final keys = groups.map((g) => _groupKeyOf(g.first)).toList();
    final moved = keys.removeAt(oldI);
    keys.insert(newI, moved);
    setState(() => _orderOrder = List<String>.from(keys));
    final r = await _nas.merchOrdersOrder(keys);
    if (r['ok'] != true && mounted) _snack('순서 저장 실패');
  }

  // ----- 삭제 / 복원 / 완전삭제 -----
  Future<void> _deleteSelected() async {
    if (_selKeys.isEmpty) return;
    final yes = await _confirm(
      '주문 삭제',
      '선택한 ${_selKeys.length}건을 삭제할까요?\n삭제 후 30일간 보관되며 복원할 수 있습니다.',
    );
    if (yes != true) return;
    final r = await _nas.merchOrdersDelete(_selKeys.toList());
    if (!mounted) return;
    if (r['ok'] == true) {
      _snack('${r['count']}항목을 삭제했습니다 (30일 보관)');
      setState(() {
        _selKeys.clear();
        _selMode = false;
      });
      _load();
    } else {
      _snack('삭제 실패: ${r['error']}');
    }
  }

  Future<void> _restoreKeys(List<String> keys) async {
    final r = await _nas.merchOrdersRestore(keys);
    if (!mounted) return;
    _snack(r['ok'] == true ? '복원했습니다' : '복원 실패');
    if (r['ok'] == true) _load();
  }

  Future<void> _hardDeleteKeys(List<String> keys) async {
    final yes = await _confirm('완전 삭제', '복원할 수 없습니다. 정말 완전 삭제할까요?');
    if (yes != true) return;
    final r = await _nas.merchOrdersHardDelete(keys);
    if (!mounted) return;
    _snack(r['ok'] == true ? '완전 삭제했습니다' : '실패');
    if (r['ok'] == true) _load();
  }

  // ----- 합치기 -----
  Future<void> _mergeSelected() async {
    if (_selKeys.length < 2) return;
    final nameCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('주문 합치기 (묶음)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '선택한 ${_selKeys.length}건을 하나의 묶음으로 관리합니다.\n'
              '각 주문번호는 그대로 유지되어 주문서에 개별로 표기됩니다.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                labelText: '묶음 이름 (선택)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
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
            child: const Text('합치기'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _nas.merchOrdersMerge(
      _selKeys.toList(),
      name: nameCtl.text.trim(),
    );
    if (!mounted) return;
    _snack(r['ok'] == true ? '주문을 합쳤습니다' : '실패: ${r['error']}');
    if (r['ok'] == true) {
      setState(() {
        _selKeys.clear();
        _selMode = false;
      });
      _load();
    }
  }

  Future<void> _unmerge(String bundleId) async {
    final r = await _nas.merchOrdersUnmerge(bundleId);
    if (!mounted) return;
    _snack(r['ok'] == true ? '묶음을 해제했습니다' : '실패');
    if (r['ok'] == true) _load();
  }

  // ----- 30일 초과 보관함 -----
  Future<void> _loadArchive() async {
    if (_showArchive) {
      setState(() => _showArchive = false);
      return;
    }
    setState(() {
      _showArchive = true;
      _archiveLoading = true;
    });
    final r = await _nas.merchArchive();
    if (!mounted) return;
    setState(() {
      _archived
        ..clear()
        ..addAll(
          ((r['archive'] as List?) ?? []).map(
            (e) => (e as Map).cast<String, dynamic>(),
          ),
        );
      _archiveLoading = false;
    });
  }

  /// 삭제 후 남은 보관일(D-n) 계산.
  int _daysLeft(String deletedAt) {
    try {
      final dt = DateTime.parse(deletedAt);
      final passed = DateTime.now().difference(dt).inDays;
      return (30 - passed).clamp(0, 30);
    } catch (_) {
      return 30;
    }
  }

  /// 그룹 내 대표 항목(첫 품목).
  void _openGroup(List<Map<String, dynamic>> items, {required bool isReserve}) {
    if (items.isEmpty) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              groupKey: _groupKeyOf(items.first),
              initialItems: items,
              canManage: true,
              statuses: isReserve ? _reserveStatuses : _statuses,
              isReserve: isReserve,
            ),
          ),
        )
        .then((_) => _load());
  }

  /// 그룹 요약 카드(주문번호 통합). 클릭 → 장바구니형 상세.
  Widget _groupCard(
    List<Map<String, dynamic>> items, {
    required bool isReserve,
  }) {
    final head = items.first;
    final orderNo = '${head['orderNo'] ?? ''}'.trim();
    final buyer = '${head['buyerName'] ?? ''}'.trim();
    final buyerNo = '${head['buyerNumber'] ?? ''}'.trim();
    final buyerPhone = '${head['phone'] ?? ''}'.trim();
    final created = '${head['created'] ?? head['createdAt'] ?? ''}'.trim();
    final allPaid = items.every((o) => o['paid'] == true);
    final anyCancelled = items.any(
      (o) => '${o['status'] ?? ''}'.contains('취소'),
    );
    final received = items.every((o) => o['received'] == true);
    final grand = items.fold<int>(
      0,
      (p, o) => p + ((o['grandTotal'] ?? o['total'] ?? 0) as num).toInt(),
    );
    final sumQty = items.fold<int>(
      0,
      (p, o) => p + ((o['qty'] as num?)?.toInt() ?? 1),
    );
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
                    color: isReserve ? Colors.orange : AppColors.purple,
                  ),
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
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isReserve)
                    _pill(
                      allPaid ? '입금완료' : '미입금',
                      allPaid ? AppColors.scoutGreen : AppColors.taegeukRed,
                    ),
                  if (received)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: _pill('수령확인', AppColors.tigerGold),
                    ),
                ],
              ),
              if (_bundleNameOf(items) != null) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    _pill('묶음: ${_bundleNameOf(items)}', AppColors.taegeukBlue),
                    const SizedBox(width: 6),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      onPressed: () =>
                          _unmerge('${items.first['bundleId'] ?? ''}'),
                      child: const Text('해제', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              // 품목 미리보기 (장바구니처럼 나열, 아주 작은 글씨)
              for (final o in items.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Text(
                        '· ',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                      Expanded(
                        child: Text(
                          '${o['product'] ?? o['productName'] ?? '수품'} '
                          '×${(o['qty'] as num?)?.toInt() ?? 1}'
                          '${('${o['option'] ?? ''}'.trim()).isEmpty ? '' : ' / ${o['option']}'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isReserve) ...[
                        const SizedBox(width: 6),
                        _pill(
                          '${o['status'] ?? ''}'.trim().isEmpty
                              ? '접수'
                              : '${o['status']}',
                          AppColors.textGray,
                        ),
                      ],
                    ],
                  ),
                ),
              if (items.length > 6)
                Text(
                  '외 ${items.length - 6}개 품목…',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGray,
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 13,
                    color: AppColors.textGray,
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      '${buyer.isEmpty ? '구매자 미상' : buyer}'
                      '${buyerNo.isEmpty ? '' : ' · $buyerNo'}'
                      '${buyerPhone.isEmpty ? '' : ' · $buyerPhone'}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      created,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '총 ${items.length}종 $sumQty개',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _won(grand),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Row(
                children: [
                  Text(
                    '장바구니형 상세 보기',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.purple,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 3),
                  Icon(Icons.chevron_right, size: 16, color: AppColors.purple),
                  Spacer(),
                  Text(
                    '수량·금액·송장·인쇄',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.lifetimeGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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

  Widget _productCard(Map<String, dynamic> p, {bool inList = false}) {
    final active = p['active'] != false;
    final options = ((p['options'] as List?) ?? []).map((e) => '$e').toList();
    final specList =
        ((p['specList'] as List?) ?? []).whereType<Map>().toList();
    final quoteName = '${p['quoteFileName'] ?? ''}';
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final price = (p['price'] as num?)?.toInt() ?? 0;
    final imgUrl = _nas.merchImageUrl('${p['image'] ?? ''}');
    final credentialOnly = p['credentialOnly'] == true;
    return Container(
      margin: EdgeInsets.only(bottom: inList ? 0 : 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // 인가자 전용 상품은 바탕색을 다르게(틸/청록 계열) 표시
        color: credentialOnly ? const Color(0xFFE6F4F1) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              (credentialOnly
                      ? AppColors.scoutGreen
                      : (active ? AppColors.purple : AppColors.textGray))
                  .withValues(alpha: credentialOnly ? 0.55 : 0.15),
          width: credentialOnly ? 1.6 : 1,
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _editProduct(existing: p),
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
                    // 인가자 전용 상품 — 상품명 말머리 표시
                    if (credentialOnly) ...[
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.scoutGreen,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '범인가자 전용',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        '${p['name'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ],
                ),
                // 상태·종류 칩은 별도 줄로 분리(상품명 폭을 잠식해
                //  이름이 세로로 깨지던 문제 방지)
                if (!active ||
                    (p['kind'] != null && '${p['kind']}'.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (!active) _chip('판매중지'),
                        if (p['kind'] != null && '${p['kind']}'.isNotEmpty)
                          _chip('${p['kind']}'),
                      ],
                    ),
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
                // 원가·제작일 — 마스터 전용 표시
                if (context.read<AppState>().isMaster &&
                    (((p['cost'] as num?)?.toInt() ?? 0) > 0 ||
                        '${p['madeDate'] ?? ''}'.trim().isNotEmpty)) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.factory_outlined,
                          size: 13, color: AppColors.lifetimeGold),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          [
                            if (((p['cost'] as num?)?.toInt() ?? 0) > 0)
                              '원가 ${_won(p['cost'])}',
                            if ('${p['madeDate'] ?? ''}'.trim().isNotEmpty)
                              '제작일 ${p['madeDate']}',
                          ].join('  ·  '),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.lifetimeGold),
                        ),
                      ),
                    ],
                  ),
                ],
                // 견적서 기반 세부항목 — 마스터/허용 관리자에게만 수신된 경우 표시
                if (specList.isNotEmpty || quoteName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.request_quote_outlined,
                          size: 13, color: AppColors.tigerGold),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '견적 세부항목 ${specList.length}건'
                          '${quoteName.isNotEmpty ? ' · $quoteName' : ''}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.tigerGold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
    bool credentialOnly = existing?['credentialOnly'] == true;
    // 견적서 기반 세부항목(사양/옵션) — 마스터만 편집. [{label, value, note}]
    final bool isMaster = context.read<AppState>().isMaster;
    final List<Map<String, String>> specList =
        ((existing?['specList'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry('$k', '${v ?? ''}')))
            .toList();
    if (specList.isEmpty) {
      specList.add({'label': '', 'value': '', 'note': ''});
    }
    String quoteFile = '${existing?['quoteFile'] ?? ''}';
    String quoteFileName = '${existing?['quoteFileName'] ?? ''}';
    // 원가(선택)·제작일·제작자 — 마스터 전용 금액/제작 정보.
    final cost = TextEditingController(
        text: (existing?['cost'] ?? 0).toString() == '0'
            ? ''
            : '${existing?['cost']}');
    final madeDate = TextEditingController(text: '${existing?['madeDate'] ?? ''}');
    String makerId = '${existing?['makerId'] ?? ''}';

    Future<void> pickQuote(StateSetter setDlg) async {
      try {
        final files = await pickDataFiles(
          dialogTitle: '견적서 파일 선택',
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'xlsx', 'xls'],
        );
        if (files.isEmpty) return;
        final f = files.first;
        final r = await _nas.merchMakerUpload(f.name, base64Encode(f.bytes));
        if (r['ok'] == true && r['file'] != null) {
          setDlg(() {
            quoteFile = '${r['file']}';
            quoteFileName = f.name;
          });
          if (mounted) _snack('견적서를 첨부했습니다');
        } else {
          if (mounted) _snack('첨부 실패: ${r['error']}');
        }
      } catch (e) {
        if (mounted) _snack('첨부 오류: $e');
      }
    }

    Future<void> pickImage(StateSetter setDlg) async {
      try {
        final files = await pickDataFiles(
          dialogTitle: '소품 이미지 선택',
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp'],
        );
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
                            ? const Icon(
                                Icons.image_outlined,
                                color: AppColors.textGray,
                              )
                            : (image.startsWith('http')
                                  ? Image.network(
                                      image,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_outlined,
                                        color: AppColors.textGray,
                                      ),
                                    )
                                  : Image.network(
                                      _nas.merchImageUrl(image),
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_outlined,
                                        color: AppColors.textGray,
                                      ),
                                    )),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => pickImage(setDlg),
                            icon: const Icon(Icons.upload_file, size: 16),
                            label: const Text('이미지 업로드'),
                          ),
                          if (image.trim().isNotEmpty)
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => setDlg(() => image = ''),
                              child: const Text(
                                '이미지 제거',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _dlgField(name, '소품명'),
                _dlgField(kind, '종류 · 추가설명 (예: 각인 가능, 세트)'),
                _dlgField(price, '가격 (원)', number: true),
                _dlgField(stock, '재고 수량', number: true),
                _dlgField(options, '옵션 (쉼표 구분, 예: S,M,L / 58,60)'),
                _dlgField(size, '사이즈 안내 (자유 텍스트)'),
                _dlgField(desc, '설명'),
                // ── 제작 정보 (원가·제작일·제작자, 마스터 전용) ──
                if (isMaster) ...[
                  const Divider(height: 18),
                  Row(
                    children: [
                      const Icon(Icons.factory_outlined,
                          size: 16, color: AppColors.tigerGold),
                      const SizedBox(width: 5),
                      const Expanded(
                        child: Text('제작 정보 (원가·제작일·제작자)',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.purpleDark)),
                      ),
                    ],
                  ),
                  const Text(
                    '원가는 선택 입력입니다. 원가·금액 정보는 마스터만 확인할 수 있습니다.',
                    style: TextStyle(fontSize: 11, color: AppColors.textGray),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: _dlgField(cost, '원가 (원, 선택)', number: true),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dlgField(madeDate, '제작일 (예: 2026.09.23)'),
                    ),
                  ]),
                  DropdownButtonFormField<String>(
                    initialValue: makerId.isEmpty ? '' : makerId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: '제작자', isDense: true),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('미배당')),
                      for (final m in _makers)
                        DropdownMenuItem(
                          value: '${m['id']}',
                          child: Text('${m['company'] ?? m['name'] ?? m['id']}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setDlg(() => makerId = v ?? ''),
                  ),
                ],
                // ── 견적서 기반 세부항목 (마스터 전용 관리) ──
                if (isMaster) ...[
                  const Divider(height: 18),
                  Row(
                    children: [
                      const Icon(Icons.request_quote_outlined,
                          size: 16, color: AppColors.tigerGold),
                      const SizedBox(width: 5),
                      const Expanded(
                        child: Text('견적서 기반 세부항목 (사양/옵션)',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.purpleDark)),
                      ),
                      TextButton.icon(
                        onPressed: () => setDlg(() => specList.add(
                            {'label': '', 'value': '', 'note': ''})),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('항목 추가',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const Text(
                    '견적서에서 확인한 사양·옵션·단가 근거 등을 항목별로 기록합니다. '
                    '(마스터 전용 — 관리자 노출은 설정에서 허용)',
                    style: TextStyle(fontSize: 11, color: AppColors.textGray),
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < specList.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: specList[i]['label'],
                              decoration: const InputDecoration(
                                  labelText: '항목', isDense: true),
                              style: const TextStyle(fontSize: 12.5),
                              onChanged: (v) => specList[i]['label'] = v,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 4,
                            child: TextFormField(
                              initialValue: specList[i]['value'],
                              decoration: const InputDecoration(
                                  labelText: '사양/값', isDense: true),
                              style: const TextStyle(fontSize: 12.5),
                              onChanged: (v) => specList[i]['value'] = v,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            icon: const Icon(Icons.close),
                            onPressed: () => setDlg(() => specList.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.attach_file,
                          size: 15, color: AppColors.tigerGold),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          quoteFileName.isEmpty
                              ? '견적서 파일 없음'
                              : '견적서: $quoteFileName',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.textGray),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => pickQuote(setDlg),
                        icon: const Icon(Icons.upload_file, size: 15),
                        label: const Text('견적서 첨부',
                            style: TextStyle(fontSize: 12)),
                      ),
                      if (quoteFile.isNotEmpty)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          icon: const Icon(Icons.close),
                          onPressed: () => setDlg(() {
                            quoteFile = '';
                            quoteFileName = '';
                          }),
                        ),
                    ],
                  ),
                ],
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(
                    Icons.badge_outlined,
                    color: AppColors.tigerGold,
                  ),
                  title: const Text('인가자 전용 상품'),
                  subtitle: const Text(
                    '인가번호가 확인된 인가자(또는 관리자)에게만 노출',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  value: credentialOnly,
                  onChanged: (v) => setDlg(() => credentialOnly = v),
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
        makerId: isMaster ? makerId : '${existing?['makerId'] ?? ''}',
        cost: isMaster
            ? (int.tryParse(cost.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
            : (existing?['cost'] as int? ?? 0),
        madeDate: isMaster ? madeDate.text.trim() : '',
        specList: isMaster
            ? specList
                .where((e) =>
                    (e['label'] ?? '').trim().isNotEmpty ||
                    (e['value'] ?? '').trim().isNotEmpty)
                .toList()
            : const [],
        quoteFile: isMaster ? quoteFile : '',
        quoteFileName: isMaster ? quoteFileName : '',
        active: active,
        credentialOnly: credentialOnly,
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
            style: BorderStyle.solid,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () => _editProduct(existing: null),
        icon: const Icon(Icons.add_circle_outline, size: 20),
        label: const Text(
          '소품 추가 (이미지·가격·사이즈·재고)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
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

  Future<bool> _confirmDelete(
    Map<String, dynamic> rec, {
    required bool isReserve,
  }) async {
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
      // MUJI 규칙 문서(A4 세로)로 인쇄/PDF 저장
      final html = _reportDocHtml();
      if (isWebRuntime) {
        openPrintableHtml(html);
      } else {
        await Clipboard.setData(ClipboardData(text: _reportText()));
        if (mounted) _snack('리포트를 복사했습니다');
      }
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
      buf.write(_reportText());
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      _snack(type == 'csv' ? 'CSV를 복사했습니다(엑셀에 붙여넣기)' : '표를 복사했습니다');
    }
  }

  String _reportText() {
    final buf = StringBuffer();
    buf.writeln('수품 판매 리포트');
    buf.writeln('총 주문: ${_stats['orderCount'] ?? _orders.length}건');
    buf.writeln(
        '총 매출: ${_won((_stats['totalSales'] as num?)?.toInt() ?? 0)}');
    buf.writeln(
        '연회비: ${_won((_stats['totalAnnualFee'] as num?)?.toInt() ?? 0)}');
    buf.writeln('예약접수: ${_stats['reserveCount'] ?? _reserves.length}건');
    final byStatus = ((_stats['byStatus'] as Map?) ?? {});
    for (final e in byStatus.entries) {
      buf.writeln('  · ${e.key}: ${e.value}건');
    }
    return buf.toString();
  }

  /// 누적판매 리포트를 MUJI 규칙 문서로 생성.
  String _reportDocHtml() {
    final totalSales = (_stats['totalSales'] as num?)?.toInt() ?? 0;
    final totalFee = (_stats['totalAnnualFee'] as num?)?.toInt() ?? 0;
    final orderCount =
        (_stats['orderCount'] as num?)?.toInt() ?? _orders.length;
    final reserveCount =
        (_stats['reserveCount'] as num?)?.toInt() ?? _reserves.length;
    final byStatus = ((_stats['byStatus'] as Map?) ?? {}).cast<String, dynamic>();
    final byMonth = ((_stats['byMonth'] as Map?) ?? {}).cast<String, dynamic>();
    final byProduct =
        ((_stats['byProduct'] as Map?) ?? {}).cast<String, dynamic>();
    final rows = <List<DocCell>>[];
    var i = 0;
    for (final e in byProduct.entries) {
      final m = (e.value as Map?)?.cast<String, dynamic>() ?? {};
      rows.add([
        DocCell('${++i}', align: 'center'),
        DocCell(e.key, accent: kMujiAccents[i % kMujiAccents.length], bold: true),
        DocCell('${m['qty'] ?? 0}개', align: 'center'),
        DocCell(_won((m['amount'] as num?)?.toInt() ?? 0), align: 'right'),
      ]);
    }
    final extraRows = <List<DocCell>>[];
    for (final e in byStatus.entries) {
      extraRows.add([
        DocCell(e.key, accent: kMujiAccents[0]),
        DocCell('${e.value}건', align: 'right'),
      ]);
    }
    for (final e in byMonth.entries) {
      extraRows.add([
        DocCell(e.key, accent: kMujiAccents[1]),
        DocCell(_won((e.value as num?)?.toInt() ?? 0), align: 'right'),
      ]);
    }
    return buildMujiDoc(
      meta: DocMeta(
        title: '수품 누적판매 리포트',
        subtitle: '한국범스카우트중앙회 · 매출/상태 분석',
        description: '총 주문·매출·연회비·예약 현황과 상품별/상태별/월별 분석입니다.',
        author: _whoName(),
        extra: {
          '총 주문': '$orderCount건',
          '총 매출': _won(totalSales),
          '연회비': _won(totalFee),
          '예약접수': '$reserveCount건',
        },
      ),
      columns: const ['번호', '상품', '판매수량', '금액'],
      rows: rows,
      summary: '총 <b>${byProduct.length}</b>종 상품 · 총 매출 '
          '<span class="g">${_won(totalSales)}</span>',
    );
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

  /// 판매대장을 MUJI 규칙 문서로 인쇄/PDF 저장.
  void _printLedger() {
    final html = _ledgerDocHtml();
    if (isWebRuntime) {
      openPrintableHtml(html);
    } else {
      Clipboard.setData(ClipboardData(text: _ledgerText()));
      _snack('판매대장을 복사했습니다');
    }
  }

  /// 판매대장을 메일로 발송.
  void _emailLedger() {
    final subject = '수품 판매대장 (${_ledgerLabel()})';
    final uri =
        'mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(_ledgerText())}';
    if (isWebRuntime) {
      openExternalUrl(uri);
    } else {
      _snack('메일 앱에서 전송하세요');
    }
  }

  String _ledgerLabel() {
    final y = _ledgerYear.isEmpty ? '전체연도' : '$_ledgerYear년';
    final m = _ledgerMonth.isEmpty ? '전체' : '$_ledgerMonth월';
    return '$y $m';
  }

  String _ledgerText() {
    final b = StringBuffer();
    b.writeln('수품 판매대장 (${_ledgerLabel()})');
    final amountTotal = (_ledgerSummary['amountTotal'] as num?)?.toInt() ?? 0;
    b.writeln('합계 ${_won(amountTotal)} · ${_ledgerRows.length}건');
    b.writeln('────────────────────────────');
    b.writeln('구분 | 주문번호 | 주문자 | 상품 | 수량 | 금액 | 상태');
    for (final row in _ledgerRows) {
      final kind = (row['_kind'] ?? row['kind'] ?? '').toString();
      final amount = (row['grandTotal'] ?? row['total'] ?? row['amount'] ?? 0);
      b.writeln('$kind | ${row['orderNo'] ?? ''} | ${row['buyerName'] ?? ''} | '
          '${row['product'] ?? ''} | ${row['qty'] ?? 1} | ${_won((amount as num?)?.toInt() ?? 0)} | ${row['status'] ?? ''}');
    }
    return b.toString();
  }

  String _ledgerDocHtml() {
    final amountTotal = (_ledgerSummary['amountTotal'] as num?)?.toInt() ?? 0;
    final orderCount = (_ledgerSummary['orderCount'] as num?)?.toInt() ?? 0;
    final reserveCount = (_ledgerSummary['reserveCount'] as num?)?.toInt() ?? 0;
    final paidCount = (_ledgerSummary['paidCount'] as num?)?.toInt() ?? 0;
    final unpaidCount = (_ledgerSummary['unpaidCount'] as num?)?.toInt() ?? 0;
    final rows = <List<DocCell>>[];
    for (var i = 0; i < _ledgerRows.length; i++) {
      final row = _ledgerRows[i];
      final kind = (row['_kind'] ?? row['kind'] ?? '').toString();
      final isOrder = kind == '주문';
      final amount = (row['grandTotal'] ?? row['total'] ?? row['amount'] ?? 0);
      final paid = row['paid'] == true;
      rows.add([
        DocCell('${i + 1}', align: 'center'),
        DocCell(kind.isEmpty ? (isOrder ? '주문' : '예약') : kind,
            accent: kMujiAccents[isOrder ? 0 : 2], align: 'center'),
        DocCell('${row['orderNo'] ?? ''}'),
        DocCell('${row['buyerName'] ?? row['name'] ?? ''}'),
        DocCell('${row['product'] ?? ''}',
            sub: '${row['qty'] ?? 1}개'),
        DocCell(_won((amount as num?)?.toInt() ?? 0), align: 'right', bold: true),
        DocCell('${row['status'] ?? ''}', align: 'center',
            sub: isOrder ? (paid ? '입금완료' : '미입금') : null),
      ]);
    }
    return buildMujiDoc(
      meta: DocMeta(
        title: '수품 판매대장',
        subtitle: '한국범스카우트중앙회 · ${_ledgerLabel()}',
        description: '주문·예약 통합 장부입니다. 상태와 입금 여부를 함께 표기합니다.',
        author: _whoName(),
        extra: {
          '조회기간': _ledgerLabel(),
          '합계': _won(amountTotal),
          '주문/예약': '$orderCount / $reserveCount',
          '입금/미입금': '$paidCount / $unpaidCount',
        },
      ),
      columns: const ['번호', '구분', '주문번호', '주문자', '상품', '금액', '상태'],
      rows: rows,
      summary: '총 <b>${_ledgerRows.length}</b>건 · 합계 '
          '<span class="g">${_won(amountTotal)}</span>',
    );
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
            _statCard(
              '입금/미입금',
              '$paidCount / $unpaidCount',
              AppColors.scoutGreen,
            ),
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
              const Text(
                '기간/구분 필터',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.purpleDark,
                ),
              ),
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
                      onChanged: (v) => setState(() => _ledgerMonth = v ?? ''),
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
                      onChanged: (v) => setState(() => _ledgerKind = v ?? ''),
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
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _ledgerLoading ? null : _loadLedger,
                    icon: const Icon(Icons.filter_alt_outlined, size: 16),
                    label: const Text('조회'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _downloadLedgerCsv,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('판매대장 CSV'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _ledgerRows.isEmpty ? null : _printLedger,
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: const Text('인쇄/PDF'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _ledgerRows.isEmpty ? null : _emailLedger,
                    icon: const Icon(Icons.email_outlined, size: 16),
                    label: const Text('메일'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
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
            const Text(
              '조회된 내역이 없습니다.',
              style: TextStyle(color: AppColors.textGray),
            ),
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
              _pill(
                kind.isEmpty ? (isOrder ? '주문' : '예약') : kind,
                isOrder ? AppColors.purple : Colors.orange,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: () => _showOrderDetail(row, isReserve: !isOrder),
                  borderRadius: BorderRadius.circular(6),
                  child: Text(
                    orderNo.isEmpty ? '(번호 없음)' : '$orderNo  ›',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: AppColors.purpleDark,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Text(
                _won((amount as num?)?.toInt() ?? 0),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
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
                  const Icon(
                    Icons.person_outline,
                    size: 13,
                    color: AppColors.taegeukBlue,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${buyer.isEmpty ? '주문자 미상' : buyer} · '
                      '${product.isEmpty ? '상품' : product}${qty > 1 ? ' ×$qty' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.taegeukBlue,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Text(
                    '  이력',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.taegeukBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text(
                created.isEmpty ? '-' : created,
                style: const TextStyle(fontSize: 11, color: AppColors.textGray),
              ),
              const Spacer(),
              if (status.isNotEmpty)
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.purpleDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (isOrder) ...[
                const SizedBox(width: 8),
                Text(
                  paid ? '입금완료' : '미입금',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: paid ? AppColors.scoutGreen : AppColors.taegeukRed,
                  ),
                ),
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
      0,
      (p, o) => p + ((o['grandTotal'] ?? o['total'] ?? 0) as num).toInt(),
    );

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
                  Text(
                    '$buyerName 주문 이력',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '주문 ${orders.length}건 · 예약 ${reserves.length}건',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textGray,
                    ),
                  ),
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
                    child: Text(
                      '총 주문금액(합계): ${_won(sumOf(orders))}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.scoutGreen,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                if (orders.isEmpty && reserves.isEmpty)
                  const Text(
                    '이 주문자의 내역이 없습니다.',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                for (final o in orders) _buyerHistoryTile(o, isReserve: false),
                for (final r in reserves) _buyerHistoryTile(r, isReserve: true),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
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
            color: (isReserve ? Colors.orange : AppColors.purple).withValues(
              alpha: 0.2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isReserve ? Icons.bookmark_border : Icons.receipt_long,
              size: 15,
              color: isReserve ? Colors.orange : AppColors.purple,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r['orderNo'] ?? '(번호 없음)'}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${r['product'] ?? ''}'
                    '${(r['qty'] as num?)?.toInt() != null ? ' ×${r['qty']}' : ''}'
                    ' · ${r['created'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _won((amount as num?)?.toInt() ?? 0),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  isReserve
                      ? '${r['status'] ?? '예약'}'
                      : (paid ? '입금완료' : '미입금'),
                  style: TextStyle(
                    fontSize: 10,
                    color: isReserve
                        ? Colors.orange
                        : (paid ? AppColors.scoutGreen : AppColors.taegeukRed),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 4) 재고 탭 (심플) ====================
  Widget _stockTab() {
    final stock = ((_stats['stock'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final total = stock.fold<int>(
        0, (a, e) => a + ((e['stock'] as num?)?.toInt() ?? 0));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        Row(
          children: [
            Expanded(
              child: _subHeader('재고 현황', '${stock.length}종 · 총 재고 $total',
                  Icons.inventory_2_outlined),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '재고 현황표 인쇄 / PDF',
              onPressed: () => _printStock(stock),
              icon: const Icon(Icons.print_outlined, size: 20),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '재고 현황표 메일',
              onPressed: () => _emailStock(stock),
              icon: const Icon(Icons.email_outlined, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (stock.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '재고 데이터가 없습니다',
              style: TextStyle(color: AppColors.textGray),
            ),
          )
        else ...[
          _stockTableHead(),
          for (final s in stock) _stockRow(s),
          const SizedBox(height: 8),
          Text('총 ${stock.length}종 · 총 재고 $total',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.purpleDark)),
        ],
        if (_stockLog.isNotEmpty) ...[
          const SizedBox(height: 14),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text('입출고 이력 (${_stockLog.length})',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
              children: [
                for (final l in _stockLog.take(30))
                  _kv(
                    '${l['product'] ?? l['name'] ?? ''} '
                        '${((l['delta'] as num?)?.toInt() ?? 0) > 0 ? '+' : ''}${l['delta'] ?? 0}',
                    '${l['at'] ?? l['created'] ?? ''}'
                        '${'${l['note'] ?? ''}'.isNotEmpty ? ' · ${l['note']}' : ''}',
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _stockTableHead() {
    const style = TextStyle(
        fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.textDark);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF4A4A48), width: 1.2)),
      ),
      child: const Row(
        children: [
          SizedBox(
              width: 44,
              child: Text('사진', style: style, textAlign: TextAlign.center)),
          Expanded(flex: 5, child: Text('품명', style: style)),
          SizedBox(
              width: 62,
              child: Text('재고', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 14),
          SizedBox(
              width: 54,
              child: Text('판매', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 36),
        ],
      ),
    );
  }

  /// 재고 현황표를 MUJI 규칙 문서로 인쇄/PDF 저장.
  void _printStock(List<Map<String, dynamic>> stock) {
    if (stock.isEmpty) {
      _snack('인쇄할 재고가 없습니다');
      return;
    }
    final html = _stockDocHtml(stock);
    if (isWebRuntime) {
      openPrintableHtml(html);
    } else {
      Clipboard.setData(ClipboardData(text: _stockText(stock)));
      _snack('재고 내역을 복사했습니다');
    }
  }

  /// 재고 현황표를 메일로 발송.
  void _emailStock(List<Map<String, dynamic>> stock) {
    if (stock.isEmpty) {
      _snack('메일로 보낼 재고가 없습니다');
      return;
    }
    final subject = '수품 재고 현황표 (${_todayYmd()})';
    final uri =
        'mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(_stockText(stock))}';
    if (isWebRuntime) {
      openExternalUrl(uri);
    } else {
      _snack('메일 앱에서 전송하세요');
    }
  }

  String _todayYmd() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${p(d.month)}.${p(d.day)}';
  }

  String _stockText(List<Map<String, dynamic>> stock) {
    final b = StringBuffer();
    b.writeln('수품 재고 현황표');
    b.writeln('기준일 ${_todayYmd()}');
    b.writeln('────────────────────────────');
    b.writeln('No | 품명 | 재고 | 누적판매');
    var i = 1;
    for (final s in stock) {
      b.writeln(
          '${i++}. ${s['name']} | ${s['stock'] ?? 0} | ${s['sold'] ?? 0}');
    }
    final total = stock.fold<int>(
        0, (a, e) => a + ((e['stock'] as num?)?.toInt() ?? 0));
    b.writeln('────────────────────────────');
    b.writeln('총 ${stock.length}개 상품 · 총 재고 $total');
    return b.toString();
  }

  String _stockDocHtml(List<Map<String, dynamic>> stock) {
    final total = stock.fold<int>(
        0, (a, e) => a + ((e['stock'] as num?)?.toInt() ?? 0));
    final rows = <List<DocCell>>[];
    for (var i = 0; i < stock.length; i++) {
      final s = stock[i];
      final qty = (s['stock'] as num?)?.toInt() ?? 0;
      final low = qty <= 5;
      rows.add([
        DocCell('${i + 1}', align: 'center'),
        DocCell('${s['name'] ?? ''}',
            accent: kMujiAccents[i % kMujiAccents.length], bold: true),
        DocCell('$qty',
            align: 'center',
            bold: low,
            sub: low ? '재고 부족' : null),
        DocCell('${s['sold'] ?? 0}', align: 'center'),
      ]);
    }
    return buildMujiDoc(
      meta: DocMeta(
        title: '수품 재고 현황표',
        subtitle: '한국범스카우트중앙회 · 수품 재고 및 누적판매',
        description: '상품별 현재 재고와 누적판매 수량입니다. 재고 5개 이하는 "재고 부족"으로 표시됩니다.',
        author: _whoName(),
        extra: {'총 상품': '${stock.length}종', '총 재고': '$total'},
      ),
      columns: const ['번호', '품명', '재고', '누적판매'],
      rows: rows,
      summary: '총 <b>${stock.length}</b>종 · 총 재고 '
          '<span class="g">$total</span>',
    );
  }

  String _whoName() {
    final s = context.read<AppState>();
    if (s.isMaster) return '마스터';
    if (s.isApp) return '관리자';
    if (s.who.isNotEmpty) {
      final m = s.repo.byNumber(s.who);
      if (m != null && m.name.isNotEmpty) return m.name;
      return s.who;
    }
    return '';
  }

  Widget _stockRow(Map<String, dynamic> s) {
    final name = '${s['name'] ?? ''}';
    final stock = (s['stock'] as num?)?.toInt() ?? 0;
    final sold = (s['sold'] as num?)?.toInt() ?? 0;
    final low = stock <= 5;
    final product = _productOf(s);
    final image = product == null ? '' : '${product['image'] ?? ''}'.trim();
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDEAE3))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 44, child: _stockThumb(image)),
          Expanded(
            flex: 5,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: product == null
                  ? null
                  : () => _editProduct(existing: product),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  if (low)
                    const Text('재고 부족',
                        style: TextStyle(
                            fontSize: 10.5, color: AppColors.taegeukRed)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: _StockQty(
              value: stock,
              onChanged: (v) async {
                final delta = v - stock;
                if (delta == 0) return;
                final r = await _nas.merchStock('${s['id']}', delta);
                if (!mounted) return;
                if (r['ok'] == true) {
                  _snack('재고를 $v개로 조정했습니다');
                  _load();
                } else {
                  _snack('조정 실패');
                }
              },
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 54,
            child: Text('$sold',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textGray)),
          ),
          SizedBox(
            width: 36,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (v) {
                if (v == 'p1') _adjustStock(s, 1);
                if (v == 'm1') _adjustStock(s, -1);
                if (v == 'set') _adjustStock(s, null);
                if (v == 'edit') {
                  if (product != null) _editProduct(existing: product);
                }
                if (v == 'del') {
                  if (product != null) _deleteProduct(product);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'p1', child: Text('+1 입고')),
                PopupMenuItem(value: 'm1', child: Text('−1 출고')),
                PopupMenuItem(value: 'set', child: Text('수량 직접입력')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'edit', child: Text('상품 수정 (사진·정보)')),
                PopupMenuItem(value: 'del', child: Text('상품 삭제')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 재고 표 사진 썸네일 — 상품 이미지가 있으면 표시.
  Widget _stockThumb(String image) {
    if (image.isEmpty) {
      return Center(
        child: Icon(Icons.image_not_supported_outlined,
            size: 20, color: AppColors.textGray.withValues(alpha: 0.4)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        _nas.merchImageUrl(image),
        width: 38,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined,
            size: 20, color: AppColors.textGray),
      ),
    );
  }

  /// 재고 항목에 대응하는 상품(products) 원본을 찾는다.
  Map<String, dynamic>? _productOf(Map<String, dynamic> s) {
    final id = '${s['id']}';
    for (final p in _products) {
      if ('${p['id']}' == id) return p;
    }
    return null;
  }

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

  // ==================== 5) 제작자 탭 (제작 내역 중심) ====================
  Widget _makerTab() {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            _subHeader(
              '수품 제작자 관리',
              '제작자별 수품 제작 내역 (결제·입금 정보 제외)',
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
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'makerAdd',
            onPressed: () => _editMaker(),
            icon: const Icon(Icons.add),
            label: const Text('제작자 등록'),
            backgroundColor: AppColors.purple,
          ),
        ),
      ],
    );
  }

  Widget _makerCard(Map<String, dynamic> m) {
    final photo = '${m['photo'] ?? ''}';
    final photoUrl = photo.isEmpty
        ? ''
        : (photo.startsWith('http') ? photo : _nas.merchFileUrl(photo));
    // 이 제작자에게 배당된 제작 내역(물건 결제 항목) — 결제/입금 정보는 제외.
    final mid = '${m['id']}';
    final made = _purchases
        .where((p) => '${p['makerId'] ?? ''}' == mid)
        .toList();
    final madeAmount =
        made.fold<int>(0, (a, p) => a + ((p['amount'] as num?)?.toInt() ?? 0));
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
                    Text(
                      '${m['company'] ?? m['name'] ?? ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if ('${m['category'] ?? ''}'.isNotEmpty)
                          _chip('${m['category']}'),
                        _chip('제작 ${made.length}건'),
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
                    // ── 계좌·사업자등록증·입금현황 (PDF page28~29 최종 결정) ──
                    if ('${m['account'] ?? ''}'.isNotEmpty)
                      _row('계좌', '${m['account']}'),
                    if ('${m['bizNumber'] ?? ''}'.isNotEmpty)
                      _row('사업자등록번호', '${m['bizNumber']}'),
                    _makerBizLicenseRow(m),
                    _makerDepositRow(m),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          // ── 제작 수품 내역 (엑셀 이미지·단가·수량·합계·날짜·메모 포함) ──
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 15, color: AppColors.purple),
              const SizedBox(width: 4),
              const Expanded(
                child: Text('제작 수품 내역',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purpleDark)),
              ),
              Text('${made.length}건 · ${_won(madeAmount)}원',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textGray)),
            ],
          ),
          const SizedBox(height: 6),
          if (made.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('배당된 제작 내역이 없습니다 (물건결제 탭에서 배당)',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textGray)),
            )
          else
            for (final p in made) _makerMadeRow(p),
          if ('${m['memo'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 6),
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
                onPressed: () => _duplicateMaker(m),
                icon: const Icon(Icons.copy_all_outlined, size: 15),
                label: const Text('복사'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _exportMaker,
                icon: const Icon(Icons.print_outlined, size: 15),
                label: const Text('인쇄/저장'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.taegeukBlue,
                ),
                onPressed: () => _showInvoice(m, made),
                icon: const Icon(Icons.receipt_long_outlined, size: 15),
                label: const Text('인보이스 보기'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 제작자별 인보이스(거래명세서) — 레퍼런스 디자인(미니멀·엣지) 요약 보기.
  void _showInvoice(Map<String, dynamic> m, List<Map<String, dynamic>> made) {
    final madeAmount =
        made.fold<int>(0, (a, p) => a + ((p['amount'] as num?)?.toInt() ?? 0));
    final madeQty =
        made.fold<int>(0, (a, p) => a + ((p['qty'] as num?)?.toInt() ?? 0));
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('INVOICE',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                                color: AppColors.textDark)),
                      ),
                      Text(DateTime.now().toString().substring(0, 10),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textGray)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(height: 2, color: AppColors.textDark),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.factory_outlined,
                        size: 15, color: AppColors.purple),
                    const SizedBox(width: 5),
                    Text('${m['company'] ?? m['name'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ]),
                  if ('${m['bizNumber'] ?? ''}'.isNotEmpty)
                    Text('사업자등록번호 ${m['bizNumber']}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textGray)),
                  if ('${m['account'] ?? ''}'.isNotEmpty)
                    Text('계좌 ${m['account']}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textGray)),
                  const SizedBox(height: 10),
                  // 표 헤더
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF2A2A2A), width: 1),
                      ),
                    ),
                    child: const Row(children: [
                      Expanded(
                          flex: 4,
                          child: Text('Description',
                              style: TextStyle(
                                  fontSize: 10.5, fontWeight: FontWeight.w800))),
                      SizedBox(
                          width: 36,
                          child: Text('Qty.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 10.5, fontWeight: FontWeight.w800))),
                      SizedBox(
                          width: 74,
                          child: Text('Amount',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 10.5, fontWeight: FontWeight.w800))),
                    ]),
                  ),
                  for (final p in made)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: Color(0xFFEDEAE3), width: 0.6),
                        ),
                      ),
                      child: Row(children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            '${p['category'] ?? p['group'] ?? ''}'
                            '${'${p['size'] ?? ''}'.trim().isNotEmpty ? ' / ${p['size']}' : ''}'
                            '${'${p['madeDate'] ?? ''}'.trim().isNotEmpty ? ' · ${p['madeDate']}' : ''}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        SizedBox(
                            width: 36,
                            child: Text('${p['qty'] ?? 0}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11))),
                        SizedBox(
                            width: 74,
                            child: Text(_won(p['amount']),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700))),
                      ]),
                    ),
                  const SizedBox(height: 10),
                  Container(height: 2, color: AppColors.textDark),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('TOTAL  ',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1)),
                      Text('${_won(madeAmount)}원',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.taegeukRed)),
                    ],
                  ),
                  Text('총 ${made.length}종 · 수량 $madeQty',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGray)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _exportMaker(),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                        label: const Text('PDF/인쇄'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('닫기')),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 제작자별 제작 수품 1건 — 엑셀 이미지 + 분류/사이즈/수량/단가/금액/날짜/메모.
  Widget _makerMadeRow(Map<String, dynamic> p) {
    final photo = '${p['photo'] ?? ''}'.trim();
    final note = '${p['note'] ?? ''}'.trim();
    final date = '${p['date'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (photo.isNotEmpty)
            GestureDetector(
              onTap: () => _showMadePhoto(p),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  _nas.merchImageUrl(photo),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                      width: 40, height: 40,
                      child: Icon(Icons.broken_image_outlined,
                          size: 18, color: AppColors.textGray)),
                ),
              ),
            )
          else
            const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.image_not_supported_outlined,
                    size: 18, color: AppColors.textGray)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['category'] ?? p['group'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                Text(
                  [
                    if ('${p['group'] ?? ''}'.trim().isNotEmpty)
                      '${p['group']}',
                    if ('${p['size'] ?? ''}'.trim().isNotEmpty)
                      '${p['size']}',
                    '${p['qty'] ?? 0}개',
                    '단가 ${_won(p['unitPrice'])}',
                    if ('${p['madeDate'] ?? ''}'.trim().isNotEmpty)
                      '제작일 ${p['madeDate']}',
                    if (date.isNotEmpty) date,
                  ].join('  ·  '),
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.textGray),
                ),
                if (note.isNotEmpty)
                  Text(note,
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.scoutGreen)),
              ],
            ),
          ),
          Text(_won(p['amount']),
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.taegeukBlue)),
        ],
      ),
    );
  }

  void _showMadePhoto(Map<String, dynamic> p) {
    final photo = '${p['photo'] ?? ''}'.trim();
    if (photo.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child:
                  Image.network(_nas.merchImageUrl(photo), fit: BoxFit.contain),
            ),
            const SizedBox(height: 8),
            Text('${p['category'] ?? p['group'] ?? ''}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white),
              label: const Text('닫기', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipBox() => Container(
    width: 52,
    height: 52,
    color: AppColors.purple.withValues(alpha: 0.08),
    child: const Icon(Icons.image, color: AppColors.purple),
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
    final memo = TextEditingController(text: '${existing?['memo'] ?? ''}');
    // [turn9-5] 제작자 페이지 보강 — 계좌번호·사업자등록증·입금현황 (PDF page28~29 최종 결정).
    final account = TextEditingController(text: '${existing?['account'] ?? ''}');
    final bizNumber = TextEditingController(
      text: '${existing?['bizNumber'] ?? ''}',
    );
    final paidAmount = TextEditingController(
      text: '${existing?['paidAmount'] ?? ''}',
    );
    String bizLicenseFile = '${existing?['bizLicenseFile'] ?? ''}';
    bool paid = existing?['paid'] == true;
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
                  const Divider(),
                  // ── 계좌번호 · 사업자등록증 · 입금현황 (PDF page28~29 최종 결정) ──
                  _dlgField(account, '계좌번호 (예: 기업은행 01087539798 안승휘)'),
                  _dlgField(bizNumber, '사업자등록번호'),
                  _fileRow(
                    '사업자등록증',
                    bizLicenseFile,
                    () => _pickFile((n) => setDlg(() => bizLicenseFile = n)),
                    () => setDlg(() => bizLicenseFile = ''),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '입금현황',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: _dlgField(paidAmount, '입금액(원)'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '입금 완료',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      Switch(
                        value: paid,
                        activeThumbColor: AppColors.scoutGreen,
                        onChanged: (v) => setDlg(() => paid = v),
                      ),
                    ],
                  ),
                  const Divider(),
                  // 결제·입금 관련 항목은 제작자 페이지에서 제외(제작 내역 중심).
                  _fileRow(
                    '대표 사진',
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
    // 제작자 페이지는 '만든 수품 내역' 중심 — 결제/입금 필드는 저장하지 않는다.
    final r = await _nas.merchSaveMaker({
      'id': '${existing?['id'] ?? ''}',
      'category': category.text.trim(),
      'company': company.text.trim(),
      'ceo': ceo.text.trim(),
      'manager': manager.text.trim(),
      'phone': phone.text.trim(),
      'email': email.text.trim(),
      'account': account.text.trim(),
      'bizNumber': bizNumber.text.trim(),
      'bizLicenseFile': bizLicenseFile,
      'paidAmount': paidAmount.text.trim(),
      'paid': paid,
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

  /// 제작자 복사 — 기존 제작자 정보를 복제해 새 제작자로 등록(이름 뒤 "(복사)").
  Future<void> _duplicateMaker(Map<String, dynamic> m) async {
    final r = await _nas.merchSaveMaker({
      'id': '',
      'company': '${m['company'] ?? m['name'] ?? ''}(복사)',
      'category': '${m['category'] ?? ''}',
      'ceo': '${m['ceo'] ?? ''}',
      'manager': '${m['manager'] ?? ''}',
      'phone': '${m['phone'] ?? ''}',
      'email': '${m['email'] ?? ''}',
      'account': '${m['account'] ?? ''}',
      'bizNumber': '${m['bizNumber'] ?? ''}',
      'bizLicenseFile': '${m['bizLicenseFile'] ?? ''}',
      'memo': '${m['memo'] ?? ''}',
    });
    if (!mounted) return;
    _snack(r['ok'] == true ? '제작자를 복사했습니다' : '복사 실패: ${r['error']}');
    if (r['ok'] == true) _load();
  }

  /// 제작자별 '만든 수품 내역'을 MUJI 규칙 문서(A4 세로)로 인쇄/저장/복사한다.
  /// 결제·입금 관련 항목은 포함하지 않는다(제작 내역 중심).
  Future<void> _exportMaker() async {
    if (_makers.isEmpty) {
      _snack('제작자 목록이 없습니다');
      return;
    }
    final rows = <List<DocCell>>[];
    var totalQty = 0;
    var totalAmt = 0;
    var madeCount = 0;
    for (var i = 0; i < _makers.length; i++) {
      final m = _makers[i];
      final mid = '${m['id'] ?? ''}';
      final company = '${m['company'] ?? m['name'] ?? ''}';
      final contact = [
        if ('${m['ceo'] ?? ''}'.isNotEmpty) '대표 ${m['ceo']}',
        if ('${m['manager'] ?? ''}'.isNotEmpty) '담당 ${m['manager']}',
        if ('${m['phone'] ?? ''}'.isNotEmpty) '${m['phone']}',
      ].join(' · ');
      final made = _purchases
          .where((p) => '${p['makerId'] ?? ''}' == mid)
          .toList();
      if (made.isEmpty) {
        rows.add([
          DocCell('${i + 1}', align: 'center'),
          DocCell(company,
              accent: kMujiAccents[i % kMujiAccents.length],
              bold: true,
              sub: contact.isEmpty ? null : contact),
          DocCell('${m['category'] ?? ''}'),
          DocCell('—', align: 'center'),
          DocCell('', align: 'center'),
          DocCell('', align: 'right'),
          DocCell('', align: 'right'),
          DocCell('', align: 'center'),
          DocCell('제작 내역 없음', sub: null),
        ]);
        continue;
      }
      for (var k = 0; k < made.length; k++) {
        final p = made[k];
        totalQty += (p['qty'] as num?)?.toInt() ?? 0;
        totalAmt += (p['amount'] as num?)?.toInt() ?? 0;
        madeCount++;
        final spec = [
          if ('${p['group'] ?? ''}'.isNotEmpty) '${p['group']}',
          if ('${p['category'] ?? ''}'.isNotEmpty) '${p['category']}',
          if ('${p['size'] ?? ''}'.isNotEmpty) '${p['size']}',
        ].join(' · ');
        rows.add([
          DocCell('${i + 1}', align: 'center'),
          if (k == 0)
            DocCell(company,
                accent: kMujiAccents[i % kMujiAccents.length],
                bold: true,
                sub: contact.isEmpty ? null : contact)
          else
            DocCell('↳', align: 'center'),
          DocCell(spec),
          DocCell('${(p['qty'] as num?)?.toInt() ?? 0}', align: 'center'),
          DocCell(_won((p['unitPrice'] as num?)?.toInt() ?? 0),
              align: 'right'),
          DocCell(_won((p['amount'] as num?)?.toInt() ?? 0), align: 'right'),
          DocCell('${p['date'] ?? '-'}', align: 'center'),
          DocCell('${p['note'] ?? ''}'),
        ]);
      }
    }
    final html = buildMujiDoc(
      meta: DocMeta(
        title: '수품 제작 내역서',
        subtitle: '한국범스카우트중앙회 · 제작자별 제작 수품',
        description: '제작자(업체)별로 제작한 수품의 규격·수량·단가·합계·제작일 내역입니다. '
            '(결제·입금 정보 제외)',
        author: _whoName(),
        extra: {
          '제작자': '${_makers.length}곳',
          '제작 항목': '$madeCount건',
          '총 수량': '$totalQty개',
          '총 합계': _won(totalAmt),
        },
      ),
      columns: const [
        '번호', '제작자/담당', '그룹·분류·규격', '수량', '단가', '합계', '제작일', '메모',
      ],
      rows: rows,
      summary: '총 <b>${_makers.length}</b>곳 · <b>$madeCount</b>건 · '
          '합계 <span class="g">${_won(totalAmt)}</span>',
    );
    if (isWebRuntime) {
      openPrintableHtml(html);
    } else {
      // 네이티브: CSV 텍스트를 클립보드로 (엑셀 붙여넣기)
      final buf = StringBuffer();
      buf.writeln('수품 제작 내역서');
      for (final m in _makers) {
        final mid = '${m['id'] ?? ''}';
        final made = _purchases
            .where((p) => '${p['makerId'] ?? ''}' == mid)
            .toList();
        for (final p in made) {
          buf.writeln(
            '${m['company'] ?? ''},${p['group'] ?? ''},${p['category'] ?? ''},'
            '${p['size'] ?? ''},${p['qty'] ?? 0},${p['unitPrice'] ?? 0},'
            '${p['amount'] ?? 0},${p['date'] ?? ''},${p['note'] ?? ''}',
          );
        }
      }
      await Clipboard.setData(ClipboardData(text: buf.toString()));
      if (mounted) _snack('제작 내역을 복사했습니다(엑셀 붙여넣기)');
    }
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
    // [turn9-7] 온라인 결제 방법 안내 (PDF page12 최종 결정).
    final gPayment = TextEditingController(text: '${_guide['payment'] ?? ''}');
    final gForm = TextEditingController(text: '${_guide['formUrl'] ?? ''}');
    final gFormLabel = TextEditingController(
      text: '${_guide['formLabel'] ?? ''}',
    );
    final statusesCtl = TextEditingController(text: _statuses.join(', '));
    final rStatusesCtl = TextEditingController(
      text: _reserveStatuses.join(', '),
    );
    bool open = _salesOpen;
    bool strict = _feeRequired;
    bool reserve = _reserveMode;
    bool makerFileAdmin = _makerFileAdminAllowed;
    bool quoteSpecAdmin = _quoteSpecAdminAllowed;
    final isMaster = context.read<AppState>().isMaster;

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
                const Divider(),
                // ── 마스터 전용 권한 제어 ──
                //  견적서/사업자등록증·견적기반 세부항목은 기본적으로 마스터만
                //  열람 가능하며, 아래 토글로 관리자(app) 접근을 허용/차단한다.
                //  (마스터만 조작 가능 — 관리자에게는 read-only 표시)
                Row(
                  children: [
                    const Icon(Icons.key, size: 15, color: AppColors.tigerGold),
                    const SizedBox(width: 5),
                    Text(
                      '마스터 전용 권한',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: isMaster
                            ? AppColors.purpleDark
                            : AppColors.textGray,
                      ),
                    ),
                    if (!isMaster) ...[
                      const SizedBox(width: 6),
                      const Text('(마스터만 변경 가능)',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textGray)),
                    ],
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('견적서·사업자등록증 관리자 열람 허용'),
                  subtitle: Text(
                    makerFileAdmin
                        ? '관리자도 견적서/사업자등록증 파일 열람·다운로드 가능'
                        : '마스터만 열람·다운로드 가능 (기본)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: makerFileAdmin,
                  onChanged: isMaster
                      ? (v) => setSt(() => makerFileAdmin = v)
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('견적서 기반 상품 세부항목 관리자 노출 허용'),
                  subtitle: Text(
                    quoteSpecAdmin
                        ? '관리자도 견적서 기반 세부항목(사양/옵션) 열람 가능'
                        : '마스터만 열람 가능 (기본)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: quoteSpecAdmin,
                  onChanged: isMaster
                      ? (v) => setSt(() => quoteSpecAdmin = v)
                      : null,
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
                _multiField(gPayment, '온라인 결제 방법 안내'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.link, size: 18, color: AppColors.taegeukBlue),
              const SizedBox(width: 6),
              const Text(
                '연계 구매 링크 (구글폼·네이버폼 등)',
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
            '주소가 유동적이므로 여기서 언제든 바꿀 수 있습니다. '
            '비워 두면 구매창의 링크 버튼이 숨겨집니다.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.taegeukBlue.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              children: [
                _dlgField(gForm, '연계 주소 (URL)'),
                _dlgField(gFormLabel, '버튼 문구'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        gForm.text.trim().isEmpty
                            ? '현재 주소 없음 — 구매창에 링크 버튼이 표시되지 않습니다.'
                            : '구매창에 위 주소로 이동하는 버튼이 표시됩니다.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: gForm.text.trim().isEmpty
                              ? AppColors.textGray
                              : AppColors.scoutGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: gForm.text.trim().isEmpty
                          ? null
                          : () async {
                              var url = gForm.text.trim();
                              if (!url.startsWith('http://') &&
                                  !url.startsWith('https://')) {
                                url = 'https://$url';
                              }
                              final uri = Uri.tryParse(url);
                              if (uri != null) {
                                try {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                } catch (_) {}
                              }
                            },
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text(
                        '주소 확인',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
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
                makerFileAdminAllowed: makerFileAdmin,
                quoteSpecAdminAllowed: quoteSpecAdmin,
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
                  'payment': gPayment.text,
                  'formUrl': gForm.text.trim(),
                  'formLabel': gFormLabel.text.trim(),
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

  /// 제작자 카드 — 사업자등록증 파일 행(열람/다운로드, PDF page28 최종 결정).
  Widget _makerBizLicenseRow(Map<String, dynamic> m) {
    final f = '${m['bizLicenseFile'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 64,
            child: Text(
              '사업자등록증',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
          ),
          Expanded(
            child: f.isEmpty
                ? const Text(
                    '미첨부',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textGray),
                  )
                : TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _openMakerFile(f),
                    icon: const Icon(Icons.description_outlined, size: 15),
                    label: const Text(
                      '사업자등록증 열람/다운로드',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 제작자 카드 — 입금현황 행(입금액·완료여부, PDF page29 최종 결정).
  Widget _makerDepositRow(Map<String, dynamic> m) {
    final paid = m['paid'] == true;
    final amt = m['paidAmount'] ?? 0;
    final hasData = paid || (amt != null && '$amt' != '0' && '$amt'.isNotEmpty);
    if (!hasData) return const SizedBox.shrink();
    return _row(
      '입금현황',
      '${_won(amt)}원${paid ? ' · 입금완료' : ' · 미완료'}',
    );
  }

  /// 제작자 민감파일(견적서/사업자등록증) 열람 — 마스터, 허용된 관리자만 서버가 허용.
  Future<void> _openMakerFile(String name) async {
    final url = _nas.merchFileUrl(name);
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) _snack('파일을 열 수 없습니다 (열람 권한 확인)');
    } catch (_) {
      try {
        await launchUrl(Uri.parse(url));
      } catch (_) {
        if (mounted) _snack('파일 링크: $url');
      }
    }
  }

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

/// 재고 수량 인라인 편집 위젯 — 숫자를 누르면 바로 입력/저장.
class _StockQty extends StatefulWidget {
  const _StockQty({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_StockQty> createState() => _StockQtyState();
}

class _StockQtyState extends State<_StockQty> {
  late final TextEditingController _ctrl =
      TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _editing = true;
      _ctrl.text = '${widget.value}';
      _ctrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    });
    _focus.requestFocus();
  }

  void _commit() {
    if (!_editing) return;
    final v = int.tryParse(_ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    setState(() => _editing = false);
    if (v != null && v != widget.value) {
      widget.onChanged(v);
    } else {
      _ctrl.text = '${widget.value}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return InkWell(
        onTap: _start,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.taegeukBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: AppColors.taegeukBlue.withValues(alpha: 0.35)),
          ),
          child: Center(
            child: Text('${widget.value}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.taegeukBlue)),
          ),
        ),
      );
    }
    return SizedBox(
      width: 56,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: AppColors.taegeukBlue),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _commit(),
      ),
    );
  }
}
