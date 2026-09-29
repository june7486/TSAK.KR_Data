import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../services/print_doc.dart';
import '../services/output_formats.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 주문(그룹) 상세 — **장바구니 형식**.
///
/// 같은 주문번호(orderNo)의 모든 품목을 한 화면에서 장바구니처럼 보여주고,
/// 전체 수량·금액·연회비·배송비를 확인·수정한다. 관리자/마스터는 진행상태·
/// 입금·수령·송장·배송사진·항목 수정/삭제가 가능하고, 구매자는 수령확인을
/// 누를 수 있다. 주문 내역을 인쇄(PDF)·메일·공유할 수 있다.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.groupKey,
    required this.initialItems,
    this.canManage = false,
    this.ident = '',
    this.statuses = const [],
    this.isReserve = false,
  });

  /// 그룹 키 — 주문번호(없으면 '#(id)').
  final String groupKey;

  /// 최초 표시 항목(상위 화면에서 그룹핑해 전달).
  final List<Map<String, dynamic>> initialItems;

  /// 관리자·마스터 여부(수정 권한).
  final bool canManage;

  /// 개인 조회용 식별자(인가번호/전화).
  final String ident;

  final List<String> statuses;
  final bool isReserve;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  NasApi get _nas => context.read<NasApi>();

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;

  /// 주문상태 적용 방식 — true: 전체 일괄적용, false: 선택 항목만.
  bool _applyAll = true;

  /// 선택된 항목 id(선택 적용 모드).
  final Set<String> _selItems = <String>{};

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    try {
      final r = widget.canManage
          ? await _nas.merchAdmin()
          : await _nas.merchMine(ident: widget.ident);
      if (!mounted) return;
      final all = <Map<String, dynamic>>[
        ...((r['orders'] as List?) ?? []).map(
          (e) => (e as Map).cast<String, dynamic>(),
        ),
        ...((r['reservations'] as List?) ?? []).map(
          (e) => (e as Map).cast<String, dynamic>(),
        ),
      ];
      final g = all.where((o) => keyOf(o) == widget.groupKey).toList();
      setState(() {
        if (g.isNotEmpty) _items = g;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 그룹 키 계산 — 주문번호가 있으면 그것, 없으면 '#(id)'.
  static String keyOf(Map<String, dynamic> o) {
    final no = '${o['orderNo'] ?? ''}'.trim();
    if (no.isNotEmpty) return no;
    return '#${o['id'] ?? ''}';
  }

  int _i(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  String _s(Map<String, dynamic> m, String k) => '${m[k] ?? ''}'.trim();

  /// 각인 메달 종류('mentor'|'parent'|'') — 수령인 정보 표시 여부 판단.
  String _medalKind(Map<String, dynamic> o) {
    final k = _s(o, 'recipientKind');
    if (k == 'mentor' || k == 'parent') return k;
    return '';
  }

  /// 해당 품목의 수령인 목록(각인 메달).
  List<Map<String, dynamic>> _recipsOf(Map<String, dynamic> o) {
    final list = o['recipients'];
    final out = <Map<String, dynamic>>[];
    if (list is List) {
      for (final r in list) {
        if (r is Map) out.add(r.cast<String, dynamic>());
      }
    } else if (o['recipient'] is Map) {
      out.add((o['recipient'] as Map).cast<String, dynamic>());
    }
    return out;
  }

  int get _sumTotal => _items.fold(0, (p, o) => p + _i(o, 'total'));

  int get _sumFee => _items.fold(0, (p, o) => p + _i(o, 'annualFeeAdded'));

  int get _sumShip => _items.fold(0, (p, o) => p + _i(o, 'shipFee'));

  int get _grand => _sumTotal + _sumFee + _sumShip;

  int get _sumQty =>
      _items.fold(0, (p, o) => p + (_i(o, 'qty') == 0 ? 1 : _i(o, 'qty')));

  bool get _allPaid =>
      _items.isNotEmpty && _items.every((o) => o['paid'] == true);
  bool get _anyReceived =>
      _items.isNotEmpty && _items.every((o) => o['received'] == true);

  Map<String, dynamic> get _head => _items.isEmpty ? {} : _items.first;

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

  // ==================== 저장 ====================
  Future<Map<String, dynamic>> _saveItem(
    String id,
    Map<String, dynamic> patch,
  ) async {
    if (widget.isReserve) {
      return _nas.merchUpdateReserveRaw(id: id, fields: patch);
    }
    return _nas.merchUpdateOrderRaw(id: id, fields: patch);
  }

  Future<void> _patchGroup(Map<String, dynamic> patch) async {
    // 그룹 전체 항목에 동일 patch 적용(상태/입금 등).
    setState(() => _busy = true);
    try {
      for (final o in _items) {
        final r = await _saveItem('${o['id']}', patch);
        if (r['ok'] == true && r['order'] is Map) {
          final nx = (r['order'] as Map).cast<String, dynamic>();
          final idx = _items.indexWhere((x) => x['id'] == o['id']);
          if (idx >= 0) _items[idx] = nx;
        }
      }
      _changed = true;
      if (mounted) _snack('저장했습니다');
    } catch (e) {
      if (mounted) _snack('오류: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 그룹 공통 항목(상태 등) — 항목별로 개별 저장.
  Future<void> _patchItem(String id, Map<String, dynamic> patch) async {
    setState(() => _busy = true);
    try {
      final r = await _saveItem(id, patch);
      if (r['ok'] == true) {
        final nx = ((r['order'] ?? r['reservation']) as Map)
            .cast<String, dynamic>();
        final idx = _items.indexWhere((x) => x['id'] == id);
        if (idx >= 0) _items[idx] = nx;
        _changed = true;
        if (mounted) _snack('저장했습니다');
      } else {
        if (mounted) _snack('저장 실패: ${r['error']}');
      }
    } catch (e) {
      if (mounted) _snack('오류: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 연회비/배송비처럼 그룹 단위 금액 — 첫 항목에 반영하고 나머지는 0으로.
  Future<void> _setGroupFee(String field, int value) async {
    setState(() => _busy = true);
    try {
      for (int i = 0; i < _items.length; i++) {
        final o = _items[i];
        final v = i == 0 ? value : 0;
        final r = await _saveItem('${o['id']}', {field: v});
        if (r['ok'] == true) {
          final nx = ((r['order'] ?? r['reservation']) as Map)
              .cast<String, dynamic>();
          _items[i] = nx;
        }
      }
      _changed = true;
      if (mounted) _snack('저장했습니다');
    } catch (e) {
      if (mounted) _snack('오류: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeQty(Map<String, dynamic> o, int delta) async {
    final cur = _i(o, 'qty') == 0 ? 1 : _i(o, 'qty');
    final nx = cur + delta;
    if (nx < 1) return;
    await _patchItem('${o['id']}', {'qty': nx});
  }

  /// 항목 순서 이동 — 화면 표시 순서만 변경(주문번호 그룹 내 정렬).
  void _moveItem(int from, int to) {
    if (to < 0 || to >= _items.length) return;
    setState(() {
      final it = _items.removeAt(from);
      _items.insert(to, it);
      _changed = true;
    });
  }

  Future<void> _deleteItem(Map<String, dynamic> o) async {
    final yes = await _confirm(
      '항목 삭제',
      '"${_s(o, 'product')}" 항목을 이 주문에서 삭제할까요?',
    );
    if (yes != true) return;
    setState(() => _busy = true);
    try {
      final fn = widget.isReserve
          ? _nas.merchDeleteReserve('${o['id']}')
          : _nas.merchDeleteOrder('${o['id']}');
      final ok = await fn;
      if (ok) {
        setState(() => _items.removeWhere((x) => x['id'] == o['id']));
        _changed = true;
        if (mounted) _snack('항목을 삭제했습니다');
      } else {
        if (mounted) _snack('삭제 실패');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteGroup() async {
    final yes = await _confirm(
      '주문 삭제',
      '주문번호 "${widget.groupKey}" 의 모든 항목(${_items.length}개)을 삭제할까요?',
    );
    if (yes != true) return;
    setState(() => _busy = true);
    try {
      final r = await _nas.merchDeleteOrderGroup(widget.groupKey);
      if (r['ok'] == true) {
        _changed = true;
        if (mounted) {
          _snack('주문을 삭제했습니다');
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) _snack('삭제 실패');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receive() async {
    final yes = await _confirm(
      '수령 확인',
      '이 주문(${widget.groupKey})을 정상적으로 수령하셨습니까?\n확인 시 [배송완료]로 처리됩니다.',
    );
    if (yes != true) return;
    setState(() => _busy = true);
    try {
      final r = await _nas.merchReceiveOrder(
        orderNo: widget.groupKey,
        received: true,
      );
      if (r['ok'] == true) {
        _changed = true;
        await _reload();
        if (mounted) _snack('수령 확인되었습니다. 감사합니다!');
      } else {
        if (mounted) _snack('수령 확인 실패: ${r['error']}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 1800)),
    );
  }

  Future<bool?> _confirm(String title, String msg) => showDialog<bool>(
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

  // ==================== 편집 다이얼로그 ====================
  Future<void> _editItem(Map<String, dynamic> o) async {
    final product = TextEditingController(text: _s(o, 'product'));
    final size = TextEditingController(text: _s(o, 'size'));
    final option = TextEditingController(text: _s(o, 'option'));
    final qty = TextEditingController(
      text: '${_i(o, 'qty') == 0 ? 1 : _i(o, 'qty')}',
    );
    final unit = TextEditingController(text: '${_i(o, 'unitPrice')}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('항목 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _f(product, '상품명'),
              _f(size, '사이즈'),
              _f(option, '옵션'),
              _f(qty, '수량', number: true),
              _f(unit, '단가 (원)', number: true),
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
    await _patchItem('${o['id']}', {
      'product': product.text.trim(),
      'size': size.text.trim(),
      'option': option.text.trim(),
      'qty': int.tryParse(qty.text.trim()) ?? 1,
      'unitPrice': int.tryParse(unit.text.trim()) ?? 0,
    });
  }

  Future<void> _editBuyer() async {
    final h = _head;
    final name = TextEditingController(text: _s(h, 'buyerName'));
    final number = TextEditingController(text: _s(h, 'buyerNumber'));
    final phone = TextEditingController(text: _s(h, 'phone'));
    final email = TextEditingController(text: _s(h, 'email'));
    final address = TextEditingController(text: _s(h, 'address'));
    final shipMethod = TextEditingController(text: _s(h, 'shipMethod'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('주문자·배송 정보 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _f(name, '주문자(입금자)명'),
              _f(number, '인가번호', number: true),
              _f(phone, '연락처'),
              _f(email, '이메일'),
              _f(shipMethod, '배송방법 (현장구매/택배발송/기타)'),
              _f(address, '배송 주소'),
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
    await _patchGroup({
      'buyerName': name.text.trim(),
      'buyerNumber': number.text.trim(),
      'phone': phone.text.trim(),
      'email': email.text.trim(),
      'shipMethod': shipMethod.text.trim(),
      'address': address.text.trim(),
    });
  }

  Future<void> _editFee(String field, String label, int current) async {
    final c = TextEditingController(text: '$current');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label 수정'),
        content: _f(c, '$label (원)', number: true),
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
    await _setGroupFee(field, int.tryParse(c.text.trim()) ?? 0);
  }

  /// 송장·운송장·배송사진 입력(관리자).
  Future<void> _editShipping() async {
    final h = _head;
    final invoice = TextEditingController(text: _s(h, 'invoice'));
    final company = TextEditingController(text: _s(h, 'invoiceCompany'));
    final shipDate = TextEditingController(text: _s(h, 'shipDate'));
    String photo = _s(h, 'shipPhoto');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('배송 정보 (송장·사진)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _f(company, '택배사 (예: 우체국택배)'),
                _f(invoice, '운송장 번호'),
                _f(shipDate, '발송일 (예: 2026.10.01)'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 60,
                        height: 60,
                        color: AppColors.bg,
                        child: photo.isEmpty
                            ? const Icon(
                                Icons.photo_camera_back_outlined,
                                color: AppColors.textGray,
                              )
                            : Image.network(
                                _nas.merchImageUrl(photo),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.textGray,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '배송 패키지 사진 (선택)',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textGray,
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              final picked = await _pickAndUpload();
                              if (picked != null) {
                                setDlg(() => photo = picked);
                              }
                            },
                            icon: const Icon(Icons.upload_file, size: 16),
                            label: const Text('사진 첨부'),
                          ),
                          if (photo.isNotEmpty)
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => setDlg(() => photo = ''),
                              child: const Text(
                                '제거',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
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
    await _patchGroup({
      'invoice': invoice.text.trim(),
      'invoiceCompany': company.text.trim(),
      'shipDate': shipDate.text.trim(),
      'shipPhoto': photo,
    });
  }

  Future<String?> _pickAndUpload() async {
    try {
      final files = await pickDataFiles(
        dialogTitle: '배송 패키지 사진 선택',
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      );
      if (files.isEmpty) return null;
      final f = files.first;
      final r = await _nas.merchImageUpload(f.name, base64Encode(f.bytes));
      if (r['ok'] == true && r['file'] != null) return '${r['file']}';
      _snack('업로드 실패: ${r['error']}');
    } catch (e) {
      _snack('오류: $e');
    }
    return null;
  }

  Widget _f(TextEditingController c, String label, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  // ==================== 출력 / 메일 / 공유 ====================
  String _orderText() {
    final h = _head;
    final b = StringBuffer();
    b.writeln('주문번호: ${widget.groupKey}');
    b.writeln('주문일: ${_s(h, 'created')}');
    b.writeln('주문자: ${_s(h, 'buyerName')} (${_s(h, 'buyerNumber')})');
    b.writeln('연락처: ${_s(h, 'phone')}');
    b.writeln(
      '진행상태: ${_s(h, 'status')} · ${_allPaid ? '입금완료' : '미입금'}'
      '${_anyReceived ? ' · 수령완료' : ''}',
    );
    b.writeln('--- 주문 내역 ---');
    for (final o in _items) {
      b.writeln(
        '· ${_s(o, 'product')}'
        '${_s(o, 'size').isNotEmpty ? ' / ${_s(o, 'size')}' : ''}'
        ' × ${_i(o, 'qty') == 0 ? 1 : _i(o, 'qty')} = ${_won(_i(o, 'total'))}',
      );
    }
    b.writeln('상품합계: ${_won(_sumTotal)}');
    if (_sumFee > 0) b.writeln('연회비: ${_won(_sumFee)}');
    if (_sumShip > 0) b.writeln('배송비: ${_won(_sumShip)}');
    b.writeln('총 결제금액: ${_won(_grand)}');
    return b.toString();
  }

  String _orderHtml() {
    final h = _head;
    // 전역 기본 출력 규칙: 무인양품(MUJI) + 다양한 색채, A4 세로.
    final rows = _items.asMap().entries.map((e) {
      final o = e.value;
      final ac = kMujiAccents[e.key % kMujiAccents.length];
      final opt = [
        if (_s(o, 'size').isNotEmpty) '사이즈 ${_s(o, 'size')}',
        if (_s(o, 'option').isNotEmpty) '옵션 ${_s(o, 'option')}',
      ].join(' · ');
      return [
        DocCell(_s(o, 'product'), accent: ac, sub: opt.isEmpty ? null : opt),
        DocCell('${_i(o, 'qty') == 0 ? 1 : _i(o, 'qty')}', align: 'center'),
        DocCell(_won(_i(o, 'unitPrice')), align: 'right'),
        DocCell(_won(_i(o, 'total')), align: 'right', bold: true),
      ];
    }).toList();
    final summary = StringBuffer('상품합계 ${_won(_sumTotal)}');
    if (_sumFee > 0) summary.write('<br>연회비 ${_won(_sumFee)}');
    if (_sumShip > 0) summary.write('<br>배송비 ${_won(_sumShip)}');
    summary.write('<br>총 결제금액 <span class="g">${_won(_grand)}</span>');
    return buildMujiDoc(
      meta: DocMeta(
        title: '수품 주문 내역서',
        subtitle: '주문번호 ${widget.groupKey}',
        author: _s(h, 'buyerName'),
        extra: {
          '주문일': _s(h, 'created'),
          '상태':
              '${_s(h, 'status')} (${_allPaid ? '입금완료' : '미입금'}'
              '${_anyReceived ? ' · 수령완료' : ''})',
          '주문자': '${_s(h, 'buyerName')} (${_s(h, 'buyerNumber')})',
          '연락처': _s(h, 'phone'),
          '이메일': _s(h, 'email'),
          '배송': _s(h, 'shipMethod'),
          '주소': _s(h, 'address'),
          if (_s(h, 'invoice').isNotEmpty)
            '운송장':
                '${_s(h, 'invoice')}'
                '${_s(h, 'invoiceCompany').isNotEmpty ? ' (${_s(h, 'invoiceCompany')})' : ''}',
        },
      ),
      columns: const ['상품', '수량', '단가', '금액'],
      rows: rows,
      summary: summary.toString(),
      footerLeft: '한국범스카우트중앙회 수품 판매',
    );
  }

  /// 엑셀(CSV) — UTF-8 BOM 포함(Excel 한글 호환).
  String _orderCsv() {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    final rows = <List<String>>[
      ['주문번호', '주문일', '상태', '입금', '수령', '주문자', '연락처', '이메일', '배송', '주소'],
      [
        widget.groupKey,
        _s(_head, 'created'),
        _s(_head, 'status'),
        _allPaid ? '입금완료' : '미입금',
        _anyReceived ? '수령완료' : '',
        _s(_head, 'buyerName'),
        _s(_head, 'phone'),
        _s(_head, 'email'),
        _s(_head, 'shipMethod'),
        _s(_head, 'address'),
      ],
      [],
      ['상품', '사이즈', '옵션', '수량', '단가', '금액'],
      for (final o in _items)
        [
          _s(o, 'product'),
          _s(o, 'size'),
          _s(o, 'option'),
          '${_i(o, 'qty') == 0 ? 1 : _i(o, 'qty')}',
          '${_i(o, 'unitPrice')}',
          '${_i(o, 'total')}',
        ],
      [],
      ['상품합계', '$_sumTotal'],
      ['연회비', '$_sumFee'],
      ['배송비', '$_sumShip'],
      ['총 결제금액', '$_grand'],
    ];
    return '\uFEFF${rows.map((r) => r.map(q).join(',')).join('\r\n')}';
  }

  /// 워드(HTML .doc) — Word에서 바로 열림.
  String _orderWord() => _orderHtml();

  /// PPT(HTML 슬라이드) — 브라우저/PPT에서 열리는 간이 프레젠테이션.
  String _orderPpt() {
    final h = _head;
    final items = _items
        .map(
          (o) =>
              '<li>${_s(o, 'product')} × ${_i(o, 'qty') == 0 ? 1 : _i(o, 'qty')} = ${_won(_i(o, 'total'))}</li>',
        )
        .join();
    final inner =
        '''<style>
 body{font-family:$kDocFontStack;margin:0}
 .slide{width:960px;height:540px;margin:12px auto;padding:48px;box-sizing:border-box;
   background:#fff;border:1px solid #E4E0D8;display:flex;flex-direction:column}
 .s1{border-left:14px solid #7C6A9C}
 .s2{border-left:14px solid #3D6E70}
 .s3{border-left:14px solid #A6763C}
 h2{color:#4A4A48;font-weight:600;margin:0 0 6px}
 .no{color:#8C877E;letter-spacing:.5px;margin-bottom:16px}
 ul{line-height:2;font-size:16px;color:#3A3A3A}
 .big{font-size:34px;color:#7C6A9C;font-weight:700;margin-top:auto}
 .brand{font-size:11px;letter-spacing:3px;color:#9A9388}
</style>
<div class="slide s1">
 <div class="brand">한국범스카우트중앙회 · TSAK</div>
 <h2>수품 주문 내역서</h2>
 <div class="no">주문번호 ${widget.groupKey}</div>
 <div>주문자 ${_s(h, 'buyerName')} · ${_s(h, 'created')}</div>
</div>
<div class="slide s2">
 <h2>주문 품목</h2>
 <ul>$items</ul>
</div>
<div class="slide s3">
 <h2>합계</h2>
 <div>상품합계 ${_won(_sumTotal)}${_sumFee > 0 ? ' · 연회비 ${_won(_sumFee)}' : ''}${_sumShip > 0 ? ' · 배송비 ${_won(_sumShip)}' : ''}</div>
 <div class="big">총 ${_won(_grand)}</div>
</div>''';
    return wrapPrintHtml('수품 주문 내역서 (슬라이드)', inner);
  }

  Future<void> _print() async {
    if (isWebRuntime) {
      // 기본 출력 형식 = PDF. 새 창에서 자동으로 인쇄(=PDF 저장) 대화상자를 띄운다.
      openPrintableHtml(_orderHtml(), autoPrint: true);
    } else {
      await Clipboard.setData(ClipboardData(text: _orderText()));
      _snack('내역을 복사했습니다(문서에 붙여넣기)');
    }
  }

  /// 저장 — 기본(PDF: 인쇄 대화상자에서 "PDF로 저장") + 기타 포맷 옵션.
  Future<void> _save() async {
    // 1) 기본값: PDF 저장 확인
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('파일로 저장'),
        content: const Text(
          '주문내역을 PDF로 저장하시겠습니까?\n(기본: PDF — 인쇄창에서 "PDF로 저장")',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              _pickFormat();
            },
            child: const Text('다른 형식'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('PDF 저장'),
          ),
        ],
      ),
    );
    if (go != true) return;
    _print();
  }

  /// 다양한 포맷으로 저장 — 규칙(#14): PDF → JPG → 엑셀 → PPT → 워드.
  Future<void> _pickFormat() async {
    final fmt = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Text(
                '저장 형식 선택 · 규칙순서 PDF→JPG→엑셀→PPT→워드',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.picture_as_pdf,
                color: AppColors.taegeukRed,
              ),
              title: const Text('PDF (기본 · 추천)'),
              subtitle: const Text('인쇄화면에서 "PDF로 저장" · 보관/전송용'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.image, color: AppColors.purple),
              title: const Text('JPG (이미지)'),
              subtitle: const Text('인쇄화면에서 "이미지로 저장" · 스마트폰 저장에 적합'),
              onTap: () => Navigator.pop(ctx, 'jpg'),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on, color: AppColors.scoutGreen),
              title: const Text('엑셀 (CSV)'),
              subtitle: const Text('표 데이터 · 회계/정산용'),
              onTap: () => Navigator.pop(ctx, 'excel'),
            ),
            ListTile(
              leading: const Icon(
                Icons.slideshow,
                color: AppColors.lifetimeGold,
              ),
              title: const Text('PPT (파워포인트)'),
              subtitle: const Text('슬라이드 · 회의 보고용 (.ppt)'),
              onTap: () => Navigator.pop(ctx, 'ppt'),
            ),
            ListTile(
              leading: const Icon(
                Icons.description,
                color: AppColors.taegeukBlue,
              ),
              title: const Text('워드 (Word)'),
              subtitle: const Text('문서 편집용 (.doc)'),
              onTap: () => Navigator.pop(ctx, 'word'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.ios_share, color: AppColors.purple),
              title: const Text('이미지 공유 (JPG)'),
              subtitle: const Text('이미지로 저장 후 사진/메신저로 공유'),
              onTap: () => Navigator.pop(ctx, 'jpg'),
            ),
            ListTile(
              leading: const Icon(Icons.link, color: AppColors.taegeukBlue),
              title: const Text('링크 공유'),
              subtitle: const Text('로그인한 권한자만 열람 가능한 링크 복사'),
              onTap: () => Navigator.pop(ctx, 'link'),
            ),
          ],
        ),
      ),
    );
    if (fmt == null || !mounted) return;
    switch (fmt) {
      case 'jpg':
      case 'pdf':
        _print();
        break;
      case 'excel':
        await _downloadFile(
          _orderCsv(),
          '${widget.groupKey}.csv',
          'text/csv;charset=utf-8',
        );
        break;
      case 'ppt':
        await _downloadFile(
          _orderPpt(),
          '${widget.groupKey}.ppt',
          'application/vnd.ms-powerpoint',
        );
        break;
      case 'word':
        await _downloadFile(
          _orderWord(),
          '${widget.groupKey}.doc',
          'application/msword',
        );
        break;
      case 'link':
        await showLinkShareDialog(
          context,
          '${_nasBase()}/#/order?id=${Uri.encodeComponent(widget.groupKey)}',
        );
        break;
    }
  }

  String _nasBase() {
    try {
      return context.read<NasApi>().baseUrl;
    } catch (_) {
      return '';
    }
  }

  /// 웹에서 파일 다운로드 트리거(Blob). 비웹은 클립보드 폴백.
  Future<void> _downloadFile(
    String content,
    String filename,
    String mime,
  ) async {
    if (isWebRuntime) {
      downloadTextFile(content, filename, mime);
      _snack('$filename 저장을 시작했습니다');
    } else {
      await Clipboard.setData(ClipboardData(text: content));
      _snack('내용을 복사했습니다($filename 대신 붙여넣기)');
    }
  }

  Future<void> _mail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'june7558@gmail.com',
      query: _encodeQuery({
        'subject': '[수품 주문내역] ${widget.groupKey}',
        'body': _orderText(),
      }),
    );
    try {
      await launchUrl(uri);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: _orderText()));
      _snack('메일을 열 수 없어 내역을 복사했습니다');
    }
  }

  String _encodeQuery(Map<String, String> q) => q.entries
      .map(
        (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');

  Future<void> _share() async {
    await Clipboard.setData(ClipboardData(text: _orderText()));
    _snack('주문 내역을 복사했습니다 — 붙여넣어 공유하세요');
  }

  // ==================== build ====================
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final canManage = widget.canManage || app.isApp;
    final isSelf = app.isSelfAccess || widget.ident.isNotEmpty;
    final h = _head;
    final status = _s(h, 'status').isEmpty
        ? (widget.isReserve ? '예약접수' : '입금확인중')
        : _s(h, 'status');
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: TsakAppBar(
          title: Text(widget.isReserve ? '예약 상세' : '주문 상세'),
          actions: [const AppHomeEmblem(size: 22)],
        ),
        body: _loading && _items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? const Center(child: Text('주문 항목이 없습니다.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  _headerCard(h, status),
                  const SizedBox(height: 12),
                  _itemsCard(canManage),
                  const SizedBox(height: 12),
                  _amountCard(canManage),
                  if (canManage) ...[
                    const SizedBox(height: 12),
                    _manageCard(status),
                  ],
                  const SizedBox(height: 12),
                  _actionsCard(canManage, isSelf),
                  const SizedBox(height: 12),
                  _footer(),
                ],
              ),
        bottomNavigationBar: _bottomBar(canManage, isSelf),
      ),
    );
  }

  Widget _card({required Widget child, Color? border}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: (border ?? AppColors.purple).withValues(alpha: 0.15),
      ),
    ),
    child: child,
  );

  Widget _title(String t, IconData icon, Color color) => Row(
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Text(
        t,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 14.5,
          color: color,
        ),
      ),
    ],
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2.5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 74,
          child: Text(
            k,
            style: const TextStyle(fontSize: 12, color: AppColors.textGray),
          ),
        ),
        Expanded(
          child: Text(
            v.isEmpty ? '-' : v,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _headerCard(Map<String, dynamic> h, String status) {
    final paid = h['paid'] == true;
    final received = _anyReceived;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.groupKey,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppColors.purpleDark,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              _pill(status, _statusColor(status)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _tag(
                paid ? '입금완료' : '미입금',
                paid ? AppColors.scoutGreen : AppColors.taegeukRed,
              ),
              _tag(
                widget.isReserve
                    ? '예약(수요조사)'
                    : _s(h, 'shipMethod').isEmpty
                    ? '주문'
                    : _s(h, 'shipMethod'),
                AppColors.taegeukBlue,
              ),
              if (received) _tag('수령완료 ✓', AppColors.scoutGreen),
              _tag('총 $_sumQty개', AppColors.purple),
            ],
          ),
          const Divider(height: 20),
          _kv('구매일', _s(h, 'created')),
          if (_s(h, 'paidDate').isNotEmpty) _kv('입금일', _s(h, 'paidDate')),
          if (_s(h, 'shipDate').isNotEmpty) _kv('발송일', _s(h, 'shipDate')),
          _kv('구매자', '${_s(h, 'buyerName')} (${_s(h, 'buyerNumber')})'),
          _kv('연락처', _s(h, 'phone')),
          if (_s(h, 'email').isNotEmpty) _kv('이메일', _s(h, 'email')),
          if (_s(h, 'address').isNotEmpty) _kv('주소', _s(h, 'address')),
          if (_s(h, 'invoice').isNotEmpty)
            _kv('운송장', '${_s(h, 'invoiceCompany')} ${_s(h, 'invoice')}'.trim()),
          if (received) _kv('수령일', _s(h, 'receivedAt')),
        ],
      ),
    );
  }

  Widget _itemsCard(bool canManage) {
    // 묶인 주문번호 목록(중복 제거, 등장 순서 유지)
    final orderNos = <String>[];
    for (final o in _items) {
      final no = _s(o, 'orderNo');
      if (no.isNotEmpty && !orderNos.contains(no)) orderNos.add(no);
    }
    final showNos = orderNos.length > 1;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _title(
                '주문 내역 (장바구니)',
                Icons.shopping_cart_outlined,
                AppColors.purple,
              ),
              const Spacer(),
              Text(
                '${_items.length}개 항목',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ),
          // 묶인 경우: 구성 주문번호 모두 표시
          if (showNos) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.taegeukBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.taegeukBlue.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.merge_type,
                        size: 14,
                        color: AppColors.taegeukBlue,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '묶인 주문번호 ${orderNos.length}건',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.taegeukBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final no in orderNos)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.taegeukBlue.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Text(
                            no,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.purpleDark,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // 주문상태 적용 바 (일괄/선택) — 관리자·마스터, 예약 아님
          if (canManage && widget.statuses.isNotEmpty && !widget.isReserve) ...[
            _bulkStatusBar(),
            const SizedBox(height: 10),
          ],
          for (int i = 0; i < _items.length; i++)
            if (canManage)
              Container(
                key: ValueKey('di-${_items[i]['id']}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _itemRow(_items[i], i, canManage)),
                    // 우측 순서변경 삼선(≡) 손잡이 — 위/아래로 항목 순서 이동
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: _busy || i == 0
                              ? null
                              : () => _moveItem(i, i - 1),
                          child: Icon(
                            Icons.keyboard_arrow_up,
                            size: 20,
                            color: i == 0
                                ? AppColors.textGray.withValues(alpha: 0.3)
                                : AppColors.purple,
                          ),
                        ),
                        const Icon(
                          Icons.drag_handle,
                          size: 18,
                          color: AppColors.textGray,
                        ),
                        InkWell(
                          onTap: _busy || i == _items.length - 1
                              ? null
                              : () => _moveItem(i, i + 1),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: i == _items.length - 1
                                ? AppColors.textGray.withValues(alpha: 0.3)
                                : AppColors.purple,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              _itemRow(_items[i], i, canManage),
          const Divider(height: 20),
          Row(
            children: [
              const Text(
                '상품 합계',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                _won(_sumTotal),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.taegeukBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 주문상태 적용 바 — [일괄적용] 체크 여부에 따라 전체 또는 선택 항목에 적용.
  Widget _bulkStatusBar() {
    final selCount = _selItems.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers, size: 15, color: AppColors.purple),
              const SizedBox(width: 5),
              const Text(
                '주문상태 적용',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purpleDark,
                ),
              ),
              const Spacer(),
              // 일괄적용 체크란
              InkWell(
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _applyAll = !_applyAll;
                        if (_applyAll) _selItems.clear();
                      }),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _applyAll
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 17,
                        color: AppColors.purple,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '일괄적용',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.purpleDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _applyAll
                ? '전체 ${_items.length}개 항목에 적용됩니다'
                : '항목별로 체크(☑) 후 적용 · 선택 $selCount개',
            style: const TextStyle(fontSize: 10.5, color: AppColors.textGray),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in widget.statuses)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 30),
                    foregroundColor: _statusColor(s),
                    side: BorderSide(
                      color: _statusColor(s).withValues(alpha: 0.5),
                    ),
                  ),
                  onPressed: _busy || (!_applyAll && _selItems.isEmpty)
                      ? null
                      : () => _applyStatus(s),
                  child: Text(
                    s,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 상태 적용 — 일괄이면 전체, 아니면 선택 항목만.
  Future<void> _applyStatus(String s) async {
    if (_applyAll) {
      await _patchGroup({'status': s});
    } else {
      final ids = _selItems.toList();
      for (final id in ids) {
        await _saveItem(id, {'status': s});
      }
      if (mounted) {
        setState(() => _selItems.clear());
        _snack('선택 $ids.length개 항목 상태를 "$s"(으)로 변경했습니다');
      }
    }
  }

  Widget _itemRow(Map<String, dynamic> o, int idx, bool canManage) {
    final img = _nas.merchImageUrl('${o['image'] ?? ''}');
    final qty = _i(o, 'qty') == 0 ? 1 : _i(o, 'qty');
    final unit = _i(o, 'unitPrice');
    final total = _i(o, 'total');
    final size = _s(o, 'size');
    final option = _s(o, 'option');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 일괄적용이 아닐 때만 항목 선택 체크란(관리자·마스터)
          if (canManage &&
              !_applyAll &&
              widget.statuses.isNotEmpty &&
              !widget.isReserve)
            Padding(
              padding: const EdgeInsets.only(right: 2, top: 14),
              child: InkWell(
                onTap: _busy
                    ? null
                    : () => setState(() {
                        final id = '${o['id']}';
                        if (_selItems.contains(id)) {
                          _selItems.remove(id);
                        } else {
                          _selItems.add(id);
                        }
                      }),
                child: Icon(
                  _selItems.contains('${o['id']}')
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 19,
                  color: AppColors.purple,
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 54,
              height: 54,
              color: Colors.white,
              child: img.isEmpty
                  ? const Icon(Icons.image_outlined, color: AppColors.textGray)
                  : Image.network(
                      img,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textGray,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s(o, 'product').isEmpty ? '(상품명 없음)' : _s(o, 'product'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // 항목이 속한 주문번호(묶음 주문 시 항목별로 다를 수 있음)
                if (_s(o, 'orderNo').isNotEmpty)
                  Text(
                    '주문번호 ${_s(o, 'orderNo')}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                      letterSpacing: 0.2,
                    ),
                  ),
                if (size.isNotEmpty || option.isNotEmpty)
                  Text(
                    [
                      if (size.isNotEmpty) '사이즈 $size',
                      if (option.isNotEmpty) option,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${_won(unit)} × $qty = ${_won(total)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.taegeukBlue,
                  ),
                ),
                // 각인 메달(멘토/페런츠) 수여받는 분(수령인) 정보 표시.
                if (_medalKind(o).isNotEmpty && _recipsOf(o).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.tigerGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.tigerGold.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.card_giftcard,
                              size: 13,
                              color: AppColors.tigerGold,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '각인 — ${_medalKind(o) == 'mentor' ? '멘토' : '페런츠'} 수령인',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.purpleDark,
                              ),
                            ),
                          ],
                        ),
                        for (final r in _recipsOf(o))
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              [
                                if ('${r['unit'] ?? ''}'.trim().isNotEmpty)
                                  '소속 ${r['unit']}',
                                if ('${r['name'] ?? ''}'.trim().isNotEmpty)
                                  '${r['name']}',
                                if ('${r['phone'] ?? ''}'.trim().isNotEmpty)
                                  '${r['phone']}',
                              ].join(' · '),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                // 항목별 배송상태 선택 (관리자·마스터)
                if (canManage &&
                    widget.statuses.isNotEmpty &&
                    !widget.isReserve) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_outlined,
                        size: 14,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '배송상태',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: DropdownButton<String>(
                          value: widget.statuses.contains(_s(o, 'status'))
                              ? _s(o, 'status')
                              : null,
                          isExpanded: true,
                          isDense: true,
                          hint: Text(
                            _s(o, 'status').isEmpty ? '미지정' : _s(o, 'status'),
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textDark,
                          ),
                          items: [
                            for (final s in widget.statuses)
                              DropdownMenuItem(value: s, child: Text(s)),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) {
                                  if (v != null) {
                                    _patchItem('${o['id']}', {'status': v});
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
                if (canManage) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _stepBtn('-', () => _changeQty(o, -1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '$qty',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      _stepBtn('+', () => _changeQty(o, 1)),
                      const SizedBox(width: 8),
                      Text(
                        '수량',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: _busy ? null : () => _editItem(o),
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text(
                          '수정',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.taegeukRed,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: _busy ? null : () => _deleteItem(o),
                        icon: const Icon(Icons.delete_outline, size: 14),
                        label: const Text(
                          '삭제',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 수량 증감 버튼 — 아이콘 글리프(폰트 tree-shaking) 이슈를 피하기 위해
  /// 부호 문자(-/+)를 직접 렌더링한다(모든 플랫폼에서 동일하게 표시).
  Widget _stepBtn(String sign, VoidCallback onTap) => InkWell(
    onTap: _busy ? null : onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        sign,
        style: const TextStyle(
          fontSize: 17,
          height: 1.0,
          fontWeight: FontWeight.w900,
          color: AppColors.purple,
        ),
      ),
    ),
  );

  Widget _amountCard(bool canManage) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('결제 금액', Icons.receipt_outlined, AppColors.taegeukBlue),
          const SizedBox(height: 10),
          _amtRow('상품 합계', _sumTotal, onEdit: null),
          _amtRow(
            '연회비',
            _sumFee,
            onEdit: canManage && !widget.isReserve
                ? () => _editFee('annualFeeAdded', '연회비', _sumFee)
                : null,
          ),
          _amtRow(
            '배송비',
            _sumShip,
            onEdit: canManage && !widget.isReserve
                ? () => _editFee('shipFee', '배송비', _sumShip)
                : null,
          ),
          const Divider(height: 18),
          Row(
            children: [
              const Text(
                '총 결제금액',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
              const Spacer(),
              Text(
                _won(_grand),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: AppColors.purpleDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _amtRow(String label, int v, {VoidCallback? onEdit}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5)),
        const SizedBox(width: 6),
        if (onEdit != null)
          InkWell(
            onTap: _busy ? null : onEdit,
            child: const Icon(
              Icons.edit,
              size: 13,
              color: AppColors.lifetimeGold,
            ),
          ),
        const Spacer(),
        Text(
          _won(v),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _manageCard(String status) {
    return _card(
      border: AppColors.tigerGold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            '관리 (관리자·마스터)',
            Icons.admin_panel_settings_outlined,
            AppColors.lifetimeGold,
          ),
          const SizedBox(height: 10),
          // 진행 상태 변경
          if (widget.statuses.isNotEmpty && !widget.isReserve) ...[
            const Text(
              '진행 상태',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: widget.statuses.contains(status) ? status : null,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                for (final s in widget.statuses)
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) _patchGroup({'status': v});
                    },
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _busy
                    ? null
                    : () => _patchGroup({'paid': !_allPaid}),
                icon: Icon(
                  _allPaid ? Icons.undo : Icons.check_circle_outline,
                  size: 16,
                ),
                label: Text(_allPaid ? '입금 취소' : '입금 처리'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _busy
                    ? null
                    : () => _patchGroup({'received': !_anyReceived}),
                icon: const Icon(Icons.inventory_2_outlined, size: 16),
                label: Text(_anyReceived ? '수령 취소' : '수령 처리'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _busy ? null : _editBuyer,
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text('주문자·배송 정보'),
              ),
              if (!widget.isReserve)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _busy ? null : _editShipping,
                  icon: const Icon(Icons.local_shipping_outlined, size: 16),
                  label: const Text('송장·배송사진'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.taegeukRed,
                ),
                onPressed: _busy ? null : _deleteGroup,
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: const Text('주문 삭제'),
              ),
            ],
          ),
          if (_s(_head, 'invoice').isNotEmpty ||
              _s(_head, 'shipPhoto').isNotEmpty) ...[
            const Divider(height: 20),
            if (_s(_head, 'invoice').isNotEmpty)
              Text(
                '운송장: ${_s(_head, 'invoiceCompany')} ${_s(_head, 'invoice')}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (_s(_head, 'shipPhoto').isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text(
                '배송 패키지 사진',
                style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  _nas.merchImageUrl('${_head['shipPhoto']}'),
                  height: 160,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _actionsCard(bool canManage, bool isSelf) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('출력 · 저장 · 전송', Icons.ios_share, AppColors.purple),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text(
                    '저장 (PDF 기본)',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.scoutGreen,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                onPressed: _mail,
                icon: const Icon(Icons.mail_outline, size: 18),
                label: const Text('메일'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _print,
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('출력 · 인쇄'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _downloadFile(
                  _orderCsv(),
                  '${widget.groupKey}.csv',
                  'text/csv;charset=utf-8',
                ),
                icon: const Icon(Icons.grid_on, size: 16),
                label: const Text('엑셀'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _downloadFile(
                  _orderWord(),
                  '${widget.groupKey}.doc',
                  'application/msword',
                ),
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('워드'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _downloadFile(
                  _orderPpt(),
                  '${widget.groupKey}.ppt',
                  'application/vnd.ms-powerpoint',
                ),
                icon: const Icon(Icons.slideshow_outlined, size: 16),
                label: const Text('PPT'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _share,
                icon: const Icon(Icons.share_outlined, size: 16),
                label: const Text('공유(복사)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      '※ 수량·금액 변경 시 개인 페이지의 수품 구매현황에 즉시 반영됩니다.\n'
      '※ 구매자는 물품 수령 후 [수령 확인]을 눌러 주세요.',
      style: TextStyle(fontSize: 11, color: AppColors.textGray, height: 1.5),
    ),
  );

  Widget _bottomBar(bool canManage, bool isSelf) {
    final showReceive = (_anyReceived == false) && !widget.isReserve;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '총 결제금액',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                  ),
                  Text(
                    _won(_grand),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: AppColors.purpleDark,
                    ),
                  ),
                ],
              ),
            ),
            if (showReceive)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _anyReceived
                      ? AppColors.textGray
                      : AppColors.scoutGreen,
                ),
                onPressed: _busy ? null : _receive,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text(
                  '수령 확인',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            if (!showReceive)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                ),
                onPressed: () => Navigator.pop(context, _changed),
                child: const Text('닫기'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      t,
      style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w800),
    ),
  );

  Widget _tag(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.withValues(alpha: 0.3)),
    ),
    child: Text(
      t,
      style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.w700),
    ),
  );

  Color _statusColor(String s) {
    if (s.contains('취소')) return AppColors.taegeukRed;
    if (s.contains('완료') || s.contains('수령')) return AppColors.scoutGreen;
    if (s.contains('입금') || s.contains('준비') || s.contains('발송')) {
      return AppColors.taegeukBlue;
    }
    return AppColors.purple;
  }
}
