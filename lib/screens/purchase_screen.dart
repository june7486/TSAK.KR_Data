import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/file_save.dart';
import '../services/nas_api.dart';
import '../services/print_doc.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';

/// 중앙회 물건 결제 리스트 — 표 형식 관리 화면.
///
/// 범중앙회 물건 구매·결제 내역(열전사/뱃지/굿즈 등)을 품목·수량·단가·금액·
/// 비고로 관리한다. 사진 등록, 순서 변경, MUJI 규칙 A4 문서 인쇄/PDF.
///
/// [embedded] 가 true 이면 독립 Scaffold 없이 본문만 렌더한다.
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _updated = '';

  NasApi get _nas => context.read<NasApi>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  List<Map<String, dynamic>> _list(dynamic v) =>
      ((v as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _nas.merchAdmin();
      final items = _list(r['purchases']);
      final cfg = ((r['config'] as Map?) ?? {}).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _items = items;
        _updated = '${cfg['purchasesUpdatedAt'] ?? ''}';
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

  String get _whoNumber {
    final s = context.read<AppState>();
    return s.who.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String get _whoName {
    final s = context.read<AppState>();
    if (s.isMaster) return '마스터';
    if (s.who.isNotEmpty) {
      final m = s.repo.byNumber(s.who);
      if (m != null && m.name.isNotEmpty) return m.name;
      return s.who;
    }
    return s.isApp ? '관리자' : '';
  }

  String _today() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${p(d.month)}.${p(d.day)}';
  }

  int _wonInt(dynamic v) => (v as num?)?.toInt() ?? 0;
  String _won(dynamic v) => _wonInt(v).toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  int get _total =>
      _items.fold<int>(0, (a, e) => a + _wonInt(e['amount']));
  int get _totalQty =>
      _items.fold<int>(0, (a, e) => a + _wonInt(e['qty']));

  // ---------- 사진 업로드 ----------
  Future<String?> _pickPhoto() async {
    try {
      final files = await pickDataFiles(
        dialogTitle: '사진 선택',
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      );
      if (files.isEmpty) return null;
      final f = files.first;
      final r = await _nas.merchImageUpload(f.name, base64Encode(f.bytes));
      if (r['ok'] == true && r['file'] != null) {
        _snack('사진을 업로드했습니다');
        return '${r['file']}';
      }
      _snack('사진 업로드 실패: ${r['error'] ?? ''}');
      return null;
    } catch (e) {
      _snack('사진 오류: $e');
      return null;
    }
  }

  // ---------- 추가 / 수정 ----------
  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final group = TextEditingController(text: '${existing?['group'] ?? ''}');
    final category =
        TextEditingController(text: '${existing?['category'] ?? ''}');
    final size = TextEditingController(text: '${existing?['size'] ?? ''}');
    final qty = TextEditingController(text: '${existing?['qty'] ?? ''}');
    final unitPrice =
        TextEditingController(text: '${existing?['unitPrice'] ?? ''}');
    final amount = TextEditingController(text: '${existing?['amount'] ?? ''}');
    final note = TextEditingController(text: '${existing?['note'] ?? ''}');
    String photo = '${existing?['photo'] ?? ''}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? '물건 결제 추가' : '물건 결제 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 64,
                        height: 64,
                        color: AppColors.bg,
                        child: photo.trim().isEmpty
                            ? const Icon(Icons.image_outlined,
                                color: AppColors.textGray)
                            : Image.network(
                                _nas.merchImageUrl(photo),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.textGray),
                              ),
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
                            onPressed: () async {
                              final f = await _pickPhoto();
                              if (f != null) setDlg(() => photo = f);
                            },
                            icon: const Icon(Icons.upload_file, size: 16),
                            label: const Text('사진 업로드'),
                          ),
                          if (photo.trim().isNotEmpty)
                            TextButton(
                              style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact),
                              onPressed: () => setDlg(() => photo = ''),
                              child: const Text('사진 제거',
                                  style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: group,
                  decoration: const InputDecoration(
                      labelText: '그룹 (예: 열전사 / 뱃지 / 굿즈)', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: category,
                  decoration: const InputDecoration(
                      labelText: '분류 (예: 검정케이스 / 후드티)', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: size,
                  decoration: const InputDecoration(
                      labelText: '사이즈 (예: 40mm / 56cm)', isDense: true),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: qty,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: '수량', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: unitPrice,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: '단가', isDense: true),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '금액 (비우면 수량×단가 자동)', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  maxLines: 2,
                  minLines: 1,
                  decoration: const InputDecoration(
                      labelText: '비고', isDense: true),
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
    if (category.text.trim().isEmpty && group.text.trim().isEmpty) {
      _snack('그룹 또는 분류를 입력하세요');
      return;
    }
    final q = int.tryParse(qty.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final up =
        int.tryParse(unitPrice.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    var am = int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (am == 0) am = q * up;
    final r = await _nas.merchSavePurchase(
      id: '${existing?['id'] ?? ''}',
      group: group.text.trim(),
      category: category.text.trim(),
      size: size.text.trim(),
      qty: q,
      unitPrice: up,
      amount: am,
      note: note.text.trim(),
      photo: photo.trim(),
      whoName: _whoName,
    );
    if (!mounted) return;
    _snack(r['ok'] == true ? '저장했습니다' : '저장 실패');
    if (r['ok'] == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final label = '${p['category'] ?? p['group'] ?? ''}';
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('물건 결제 삭제'),
        content: Text('"$label" 항목을 삭제할까요?'),
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
    final ok = await _nas.merchDeletePurchase('${p['id']}');
    if (!mounted) return;
    _snack(ok ? '삭제했습니다' : '삭제 실패');
    if (ok) _load();
  }

  // ---------- MUJI 문서 ----------
  String _docHtml() {
    final rows = <List<DocCell>>[];
    for (var i = 0; i < _items.length; i++) {
      final p = _items[i];
      rows.add([
        DocCell('${i + 1}', align: 'center'),
        DocCell('${p['group'] ?? ''}', bold: true),
        DocCell('${p['category'] ?? ''}'),
        DocCell('${p['size'] ?? ''}', align: 'center'),
        DocCell('${p['qty'] ?? 0}', align: 'center'),
        DocCell(_won(p['unitPrice']), align: 'right'),
        DocCell(_won(p['amount']), align: 'right', bold: true,
            sub: '${p['note'] ?? ''}'.trim().isEmpty ? null : '${p['note']}'),
      ]);
    }
    return buildMujiDoc(
      meta: DocMeta(
        title: '중앙회 물건 결제 내역',
        subtitle: '한국범스카우트중앙회 · 물건 구매·결제 내역',
        description: '아래 물건의 품목·수량·단가·금액을 확인합니다.',
        author: _whoName.isNotEmpty ? '#$_whoNumber $_whoName' : '',
        extra: {
          '총 항목': '${_items.length}건',
          '총 수량': '$_totalQty',
          '총 금액': '${_won(_total)}원',
          if (_updated.isNotEmpty) '목록 갱신': _updated,
        },
      ),
      columns: const ['번호', '그룹', '분류', '사이즈', '수량', '단가', '금액'],
      rows: rows,
      summary: '총 <b>${_items.length}</b>개 항목 · 총 수량 $_totalQty · '
          '총 금액 <span class="g">${_won(_total)}원</span>',
      footerRight: '업데이트 ${_updated.isNotEmpty ? _updated : _today()}',
    );
  }

  Future<void> _print() async {
    if (_items.isEmpty) {
      _snack('인쇄할 항목이 없습니다');
      return;
    }
    final html = _docHtml();
    if (isWebRuntime) {
      openPrintableHtml(html);
    } else {
      await saveText(
        content: html,
        name: '중앙회_물건_결제_내역_${_today().replaceAll('.', '')}',
        ext: 'html',
        mime: 'text/html;charset=utf-8',
      );
      _snack('문서를 저장했습니다');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.taegeukRed),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                        onPressed: _load, child: const Text('다시 시도')),
                  ],
                ),
              )
            : _body();

    if (widget.embedded) {
      return Stack(
        children: [
          content,
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'purchaseAdd',
              onPressed: () => _edit(),
              backgroundColor: AppColors.purple,
              icon: const Icon(Icons.add),
              label: const Text('물건 결제 추가'),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('중앙회 물건 결제'),
        actions: [
          IconButton(
            tooltip: '인쇄 / PDF 저장',
            onPressed: _print,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: AppColors.purple,
        icon: const Icon(Icons.add),
        label: const Text('물건 결제 추가'),
      ),
      body: content,
    );
  }

  Widget _body() {
    return Column(
      children: [
        _headerBox(),
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Text('물건 결제 내역이 없습니다. 아래 + 버튼으로 추가하세요.',
                      style: TextStyle(color: AppColors.textGray)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
                  children: [
                    _tableHead(),
                    for (var i = 0; i < _items.length; i++) _row(_items[i], i),
                    const SizedBox(height: 8),
                    Text('총 ${_items.length}개 항목 · 총 수량 $_totalQty · '
                        '총 금액 ${_won(_total)}원',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.purpleDark)),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _headerBox() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('중앙회 물건 결제 내역',
                    style: TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w800)),
              ),
              Text('${_items.length}건 · ${_won(_total)}원',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textGray)),
              if (widget.embedded) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '인쇄 / PDF',
                  onPressed: _print,
                  icon: const Icon(Icons.print_outlined, size: 20),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '새로고침',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '업데이트 ${_updated.isNotEmpty ? _updated : _today()}'
            '${_whoName.isNotEmpty ? '   ·   담당 #$_whoNumber $_whoName' : ''}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _tableHead() {
    const style = TextStyle(
        fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.textDark);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF4A4A48), width: 1.2)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 30, child: Text('No', style: style)),
          SizedBox(width: 46, child: Text('사진', style: style)),
          Expanded(flex: 4, child: Text('그룹 · 분류', style: style)),
          SizedBox(
              width: 54,
              child: Text('수량', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 12),
          SizedBox(
              width: 66,
              child: Text('금액', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> p, int i) {
    final note = '${p['note'] ?? ''}'.trim();
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDEAE3))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 30,
            child: Text('${i + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textGray)),
          ),
          SizedBox(width: 46, child: _photoThumb(p)),
          Expanded(
            flex: 4,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _edit(existing: p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p['category'] ?? p['group'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(
                    [
                      if ('${p['group'] ?? ''}'.trim().isNotEmpty)
                        '${p['group']}',
                      if ('${p['size'] ?? ''}'.trim().isNotEmpty)
                        '${p['size']}',
                      '단가 ${_won(p['unitPrice'])}',
                    ].join('  ·  '),
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.textGray),
                  ),
                  if (note.isNotEmpty)
                    Text(note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.scoutGreen)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 54,
            child: Text('${p['qty'] ?? 0}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 66,
            child: Text(_won(p['amount']),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.taegeukBlue)),
          ),
          SizedBox(
            width: 40,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (v) {
                if (v == 'edit') _edit(existing: p);
                if (v == 'del') _delete(p);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('수정')),
                PopupMenuItem(value: 'del', child: Text('삭제')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoThumb(Map<String, dynamic> p) {
    final photo = '${p['photo'] ?? ''}'.trim();
    if (photo.isEmpty) {
      return Center(
        child: Icon(Icons.image_not_supported_outlined,
            size: 20, color: AppColors.textGray.withValues(alpha: 0.4)),
      );
    }
    return GestureDetector(
      onTap: () => _showPhoto(p),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          _nas.merchImageUrl(photo),
          width: 38,
          height: 38,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: AppColors.textGray),
        ),
      ),
    );
  }

  void _showPhoto(Map<String, dynamic> p) {
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
              child: Image.network(_nas.merchImageUrl(photo),
                  fit: BoxFit.contain),
            ),
            const SizedBox(height: 8),
            Text('${p['category'] ?? p['group'] ?? ''}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white),
              label:
                  const Text('닫기', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
