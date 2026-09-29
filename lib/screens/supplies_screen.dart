import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/file_save.dart';
import '../services/nas_api.dart';
import '../services/print_doc.dart';
import '../services/output_formats.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 중앙회 비품 재고 리스트 — 표 형식 관리 화면.
///
/// - 품명 · 수량 · 비고 + **업데이트 날짜 / 재고 확인 날짜 / 확인자(인가번호·이름)**
/// - 추가·수정·삭제, 좌측 손잡이로 순서 변경
/// - MUJI 규칙(무인양품 + 다양한 색채) A4 세로 문서로 인쇄 / 메일 발송
///
/// [embedded] 가 true 이면 독립 Scaffold 없이 본문만 렌더한다
/// (= 수품 판매관리 내부 탭에서 사용).
class SuppliesScreen extends StatefulWidget {
  const SuppliesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SuppliesScreen> createState() => _SuppliesScreenState();
}

class _SuppliesScreenState extends State<SuppliesScreen> {
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
      final items = _list(r['supplies']);
      final cfg = ((r['config'] as Map?) ?? {}).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _items = items;
        _updated = '${cfg['suppliesUpdatedAt'] ?? ''}';
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

  // ---------- 현재 사용자(확인자) ----------
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
    final name = TextEditingController(text: '${existing?['name'] ?? ''}');
    final qty =
        TextEditingController(text: '${existing?['qty'] ?? ''}');
    final note = TextEditingController(text: '${existing?['note'] ?? ''}');
    final checked = TextEditingController(
      text: '${existing?['checkedAt'] ?? ''}'.isNotEmpty
          ? '${existing?['checkedAt']}'
          : _today(),
    );
    String photo = '${existing?['photo'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? '비품 추가' : '비품 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 사진 미리보기 + 업로드
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
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: '품명 *', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '수량', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  maxLines: 2,
                  minLines: 1,
                  decoration: const InputDecoration(
                      labelText: '비고', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: checked,
                  decoration: const InputDecoration(
                      labelText: '재고 확인 날짜', isDense: true),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '확인자: #$_whoNumber $_whoName',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textGray),
                  ),
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
    if (name.text.trim().isEmpty) {
      _snack('품명을 입력하세요');
      return;
    }
    final r = await _nas.merchSaveSupply(
      id: '${existing?['id'] ?? ''}',
      name: name.text.trim(),
      qty: int.tryParse(qty.text.trim()) ?? 0,
      note: note.text.trim(),
      checkedAt: checked.text.trim(),
      whoName: _whoName,
      photo: photo.trim(),
    );
    if (!mounted) return;
    _snack(r['ok'] == true ? '저장했습니다' : '저장 실패');
    if (r['ok'] == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비품 삭제'),
        content: Text('"${s['name']}" 항목을 삭제할까요?'),
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
    final ok = await _nas.merchDeleteSupply('${s['id']}');
    if (!mounted) return;
    _snack(ok ? '삭제했습니다' : '삭제 실패');
    if (ok) _load();
  }

  Future<void> _onReorder(int oldI, int newI) async {
    if (newI > oldI) newI -= 1;
    setState(() {
      final moved = _items.removeAt(oldI);
      _items.insert(newI, moved);
    });
    final ids = _items.map((e) => '${e['id']}').toList();
    final ok = await _nas.merchSuppliesOrder(ids);
    if (!ok && mounted) _snack('순서 저장 실패');
  }

  // ---------- MUJI 문서 ----------
  String _docHtml() {
    final total = _items.fold<int>(
        0, (a, e) => a + ((e['qty'] as num?)?.toInt() ?? 0));
    final rows = <List<DocCell>>[];
    for (var i = 0; i < _items.length; i++) {
      final s = _items[i];
      final checkedBy = '${s['checkedBy'] ?? ''}'.trim();
      final checkedName = '${s['checkedByName'] ?? ''}'.trim();
      final who = [
        if (checkedBy.isNotEmpty) '#$checkedBy',
        if (checkedName.isNotEmpty) checkedName,
      ].join(' ');
      rows.add([
        DocCell('${i + 1}', align: 'center'),
        DocCell('${s['name'] ?? ''}',
            accent: kMujiAccents[i % kMujiAccents.length], bold: true),
        DocCell('${s['qty'] ?? 0}', align: 'center'),
        DocCell('${s['note'] ?? ''}'),
        DocCell(
          '${s['checkedAt'] ?? ''}'.isNotEmpty
              ? '${s['checkedAt']}'
              : '${s['updatedAt'] ?? ''}',
          sub: who.isEmpty ? null : who,
        ),
      ]);
    }
    return buildMujiDoc(
      meta: DocMeta(
        title: '중앙회 비품 재고 리스트',
        subtitle: '한국범스카우트중앙회 · 비품 재고 및 입출고 현황',
        description: '아래 비품의 수량과 비고를 확인하고, 확인일자·확인자를 함께 기재합니다.',
        author: _whoName.isNotEmpty ? '#$_whoNumber $_whoName' : '',
        extra: {
          '총 항목': '${_items.length}건',
          '총 수량': '$total',
          if (_updated.isNotEmpty) '목록 갱신': _updated,
        },
      ),
      columns: const ['번호', '품명', '수량', '비고', '확인일자 · 확인자'],
      rows: rows,
      summary: '총 <b>${_items.length}</b>개 항목 · 총 수량 '
          '<span class="g">$total</span>',
      footerRight: '업데이트 ${_updated.isNotEmpty ? _updated : _today()}',
    );
  }

  Future<void> _print({
    TsakOutputFormat format = TsakOutputFormat.pdf,
  }) async {
    if (_items.isEmpty) {
      _snack('인쇄할 항목이 없습니다');
      return;
    }
    final html = _docHtml();
    if (isWebRuntime) {
      // 규칙(#14): 형식 순서 PDF→JPG→엑셀→PPT→워드.
      switch (format) {
        case TsakOutputFormat.pdf:
        case TsakOutputFormat.jpg:
          openPrintableHtml(html);
          _snack(format == TsakOutputFormat.jpg
              ? '인쇄창에서 대상=이미지로 저장하세요'
              : '인쇄창에서 PDF로 저장하세요');
          return;
        case TsakOutputFormat.excel:
          await Clipboard.setData(ClipboardData(text: _csvText()));
          _snack('엑셀용 데이터를 복사했습니다 (붙여넣기)');
          return;
        case TsakOutputFormat.ppt:
        case TsakOutputFormat.word:
          await Clipboard.setData(ClipboardData(text: _plainText(format)));
          _snack('${format.label}용 텍스트를 복사했습니다 (붙여넣기)');
          return;
      }
    } else {
      await saveText(
        content: html,
        name: '중앙회_비품_재고_리스트_${_today().replaceAll('.', '')}',
        ext: 'html',
        mime: 'text/html;charset=utf-8',
      );
      _snack('문서를 저장했습니다');
    }
  }

  /// 비품 재고 → CSV(엑셀).
  String _csvText() {
    final buf = StringBuffer();
    buf.writeln('번호,품명,수량,비고,확인일자,확인자');
    for (var i = 0; i < _items.length; i++) {
      final p = _items[i];
      buf.writeln('${i + 1},${p['name'] ?? ''},${p['qty'] ?? 0},'
          '${p['note'] ?? ''},${p['checked'] ?? ''},${p['whoName'] ?? ''}');
    }
    return buf.toString();
  }

  /// 비품 재고 → PPT/워드 붙여넣기용 텍스트.
  String _plainText(TsakOutputFormat format) {
    final buf = StringBuffer();
    buf.writeln(format == TsakOutputFormat.ppt
        ? '중앙회 비품 재고 (슬라이드용)'
        : '중앙회 비품 재고 리스트 (문서용)');
    buf.writeln('한국범스카우트중앙회 · ${_whoName.isNotEmpty ? '#$_whoNumber $_whoName' : ''}');
    buf.writeln();
    for (var i = 0; i < _items.length; i++) {
      final p = _items[i];
      buf.writeln('${i + 1}. ${p['name'] ?? ''} / ${p['qty'] ?? 0}개'
          '${'${p['note'] ?? ''}'.trim().isEmpty ? '' : ' / ${p['note']}'}');
    }
    return buf.toString();
  }

  /// 출력 형식 선택 다이얼로그 (#14 규칙).
  Future<void> _showOutputDialog() async {
    if (_items.isEmpty) {
      _snack('출력할 항목이 없습니다');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('출력 형식 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('규칙 순서: PDF → JPG → 엑셀 → PPT → 워드',
                style: TextStyle(fontSize: 11.5, color: AppColors.textGray)),
            const SizedBox(height: 12),
            TsakOutputBar(
              onFormat: (f) {
                Navigator.pop(ctx);
                _print(format: f);
              },
              onShareImage: () {
                Navigator.pop(ctx);
                _print(format: TsakOutputFormat.jpg);
              },
              onShareLink: () {
                Navigator.pop(ctx);
                showLinkShareDialog(context, '${_nas.baseUrl}/#/supplies');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }

  Future<void> _email() async {
    if (_items.isEmpty) {
      _snack('메일로 보낼 항목이 없습니다');
      return;
    }
    final total = _items.fold<int>(
        0, (a, e) => a + ((e['qty'] as num?)?.toInt() ?? 0));
    final b = StringBuffer();
    b.writeln('중앙회 비품 재고 리스트');
    b.writeln('업데이트: ${_updated.isNotEmpty ? _updated : _today()}');
    b.writeln(
        '확인자: ${_whoName.isNotEmpty ? '#$_whoNumber $_whoName' : '-'}');
    b.writeln('──────────────────────────────────');
    b.writeln('연번 | 품명 | 수량 | 비고 | 확인일자 | 확인자');
    for (var i = 0; i < _items.length; i++) {
      final s = _items[i];
      final who = [
        if ('${s['checkedBy'] ?? ''}'.trim().isNotEmpty)
          '#${s['checkedBy']}',
        if ('${s['checkedByName'] ?? ''}'.trim().isNotEmpty)
          '${s['checkedByName']}',
      ].join(' ');
      b.writeln('${i + 1}. ${s['name']} | ${s['qty']} | ${s['note'] ?? ''} | '
          '${'${s['checkedAt'] ?? ''}'.isNotEmpty ? s['checkedAt'] : s['updatedAt'] ?? ''} | $who');
    }
    b.writeln('──────────────────────────────────');
    b.writeln('총 ${_items.length}개 항목 · 총 수량 $total');
    final subject = '중앙회 비품 재고 리스트 (${_updated.isNotEmpty ? _updated : _today()})';
    final uri =
        'mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(b.toString())}';
    if (isWebRuntime) {
      openExternalUrl(uri);
    } else {
      _snack('메일 앱에서 전송하세요');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<int>(
        0, (a, e) => a + ((e['qty'] as num?)?.toInt() ?? 0));
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
            : _body(total);

    if (widget.embedded) {
      return Stack(
        children: [
          content,
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'supplyAdd',
              onPressed: () => _edit(),
              backgroundColor: AppColors.purple,
              icon: const Icon(Icons.add),
              label: const Text('비품 추가'),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        title: const Text('중앙회 비품 재고'),
        actions: [
          const AppHomeEmblem(size: 22),
          IconButton(
            tooltip: '출력 (형식 선택)',
            onPressed: _showOutputDialog,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: '메일 발송',
            onPressed: _email,
            icon: const Icon(Icons.email_outlined),
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
        label: const Text('비품 추가'),
      ),
      body: content,
    );
  }

  Widget _body(int total) {
    return Column(
      children: [
        _headerBox(total),
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Text('비품이 없습니다. 아래 + 버튼으로 추가하세요.',
                      style: TextStyle(color: AppColors.textGray)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
                  children: [
                    _tableHead(),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: _items.length,
                      onReorder: _onReorder,
                      itemBuilder: (ctx, i) {
                        final s = _items[i];
                        return Container(
                          key: ValueKey('sp-${s['id']}'),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFEDEAE3)),
                            ),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.grab,
                                    child: Container(
                                      width: 34,
                                      alignment: Alignment.center,
                                      color: AppColors.purple
                                          .withValues(alpha: 0.05),
                                      child: Icon(Icons.drag_indicator,
                                          size: 18,
                                          color: AppColors.purple
                                              .withValues(alpha: 0.7)),
                                    ),
                                  ),
                                ),
                                Expanded(child: _row(s, i)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '총 ${_items.length}개 항목 · 총 수량 $total',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.purpleDark),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _headerBox(int total) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('중앙회 비품 재고 리스트',
                    style: TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w800)),
              ),
              Text('${_items.length}건 · $total개',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textGray)),
              if (widget.embedded) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '출력 (형식 선택)',
                  onPressed: _showOutputDialog,
                  icon: const Icon(Icons.print_outlined, size: 20),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '메일',
                  onPressed: _email,
                  icon: const Icon(Icons.email_outlined, size: 20),
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
            '${_whoName.isNotEmpty ? '   ·   확인자 #$_whoNumber $_whoName' : ''}',
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
          SizedBox(width: 34),
          SizedBox(width: 30, child: Text('No', style: style)),
          SizedBox(
              width: 46,
              child: Text('사진', style: style, textAlign: TextAlign.center)),
          Expanded(flex: 4, child: Text('품명', style: style)),
          SizedBox(
              width: 60,
              child: Text('수량', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 14),
          Expanded(flex: 3, child: Text('비고', style: style)),
          SizedBox(width: 44),
        ],
      ),
    );
  }

  /// 수량 셀 — 화면에서 바로 수정(인라인 편집) 가능.
  Widget _qtyCell(Map<String, dynamic> s) {    return _InlineQty(
      value: (s['qty'] as num?)?.toInt() ?? 0,
      onChanged: (v) => _saveQty(s, v),
    );
  }

  /// 인라인 수량 저장 — 품명 등 나머지 정보는 유지한 채 수량만 갱신.
  Future<void> _saveQty(Map<String, dynamic> s, int qty) async {
    if (qty < 0) return;
    final r = await _nas.merchSaveSupply(
      id: '${s['id']}',
      name: '${s['name'] ?? ''}',
      qty: qty,
      note: '${s['note'] ?? ''}',
      checkedAt: '${s['checkedAt'] ?? ''}',
      whoName: _whoName,
      photo: '${s['photo'] ?? ''}',
    );
    if (!mounted) return;
    if (r['ok'] != true) {
      _snack('수량 저장 실패');
      return;
    }
    setState(() => s['qty'] = qty);
    _snack('수량을 $qty개로 저장했습니다');
  }

  Widget _row(Map<String, dynamic> s, int i) {
    final checkedAt = '${s['checkedAt'] ?? ''}'.trim();
    final updatedAt = '${s['updatedAt'] ?? ''}'.trim();
    final checkedBy = '${s['checkedBy'] ?? ''}'.trim();
    final checkedName = '${s['checkedByName'] ?? ''}'.trim();
    final who = [
      if (checkedBy.isNotEmpty) '#$checkedBy',
      if (checkedName.isNotEmpty) checkedName,
    ].join(' ');
    return Padding(
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
          SizedBox(width: 46, child: _photoThumb(s)),
          Expanded(
            flex: 4,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _edit(existing: s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${s['name'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                  if (checkedAt.isNotEmpty || updatedAt.isNotEmpty)
                    Text(
                      '확인 $checkedAt'
                      '${updatedAt.isNotEmpty ? '  ·  갱신 $updatedAt' : ''}',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textGray),
                    ),
                  if (who.isNotEmpty)
                    Text('확인자 $who',
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.scoutGreen)),
                ],
              ),
            ),
          ),
          SizedBox(width: 60, child: _qtyCell(s)),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Text('${s['note'] ?? ''}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textGray)),
          ),
          SizedBox(
            width: 44,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (v) {
                if (v == 'edit') _edit(existing: s);
                if (v == 'del') _delete(s);
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

  /// 비품 사진 썸네일 — 없으면 흐린 아이콘, 있으면 탭하여 확대.
  Widget _photoThumb(Map<String, dynamic> s) {
    final photo = '${s['photo'] ?? ''}'.trim();
    if (photo.isEmpty) {
      return Center(
        child: Icon(Icons.image_not_supported_outlined,
            size: 20, color: AppColors.textGray.withValues(alpha: 0.4)),
      );
    }
    return GestureDetector(
      onTap: () => _showPhoto(s),
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

  void _showPhoto(Map<String, dynamic> s) {
    final photo = '${s['photo'] ?? ''}'.trim();
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
            Text('${s['name'] ?? ''}',
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

/// 재고 수량 인라인 편집 위젯 — 숫자를 누르면 바로 입력/저장.
///
/// 화면(표) 안에서 각 비품의 수량을 즉시 수정할 수 있어, 항목을 열지 않고도
/// 재고를 관리할 수 있게 한다. 값이 바뀌면 [onChanged]로 저장한다.
class _InlineQty extends StatefulWidget {
  const _InlineQty({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_InlineQty> createState() => _InlineQtyState();
}

class _InlineQtyState extends State<_InlineQty> {
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