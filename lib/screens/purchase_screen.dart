import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/doc_pdf.dart';
import '../services/export_save.dart';
import '../services/file_pick.dart';
import '../services/file_save.dart';
import '../services/nas_api.dart';
import '../services/pdf_to_jpg.dart';
import '../services/print_doc.dart';
import '../services/output_formats.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/tsak_output_sheet.dart';

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
  List<Map<String, dynamic>> _makers = [];
  bool _loading = true;
  String? _error;
  String _updated = '';

  // 보기 모드: true=제작자별 구분 / false=전체보기(전체 항목 한번에)
  bool _byMaker = true;
  // 다중 선택(취합·이동) 모드
  bool _selectMode = false;
  final Set<String> _selected = {};

  NasApi get _nas => context.read<NasApi>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      final items = _list(r['purchases']);
      final makers = _list(r['makers']);
      final cfg = ((r['config'] as Map?) ?? {}).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _items = items;
        _makers = makers;
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
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  /// 제작자 id → 표시명(업체명). 배당 없으면 '미배당'.
  String _makerLabel(String mid) {
    if (mid.trim().isEmpty) return '미배당';
    for (final m in _makers) {
      if ('${m['id']}' == mid) {
        return '${m['company'] ?? m['name'] ?? mid}';
      }
    }
    return '미배당';
  }

  int get _total => _items.fold<int>(0, (a, e) => a + _wonInt(e['amount']));
  int get _totalQty => _items.fold<int>(0, (a, e) => a + _wonInt(e['qty']));

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
    final category = TextEditingController(
      text: '${existing?['category'] ?? ''}',
    );
    final size = TextEditingController(text: '${existing?['size'] ?? ''}');
    final qty = TextEditingController(text: '${existing?['qty'] ?? ''}');
    final unitPrice = TextEditingController(
      text: '${existing?['unitPrice'] ?? ''}',
    );
    final amount = TextEditingController(text: '${existing?['amount'] ?? ''}');
    final note = TextEditingController(text: '${existing?['note'] ?? ''}');
    final date = TextEditingController(text: '${existing?['date'] ?? ''}');
    final cost = TextEditingController(
      text: (existing?['cost'] ?? 0).toString() == '0'
          ? ''
          : '${existing?['cost']}',
    );
    final madeDate = TextEditingController(
      text: '${existing?['madeDate'] ?? ''}',
    );
    String photo = '${existing?['photo'] ?? ''}';
    String makerId = '${existing?['makerId'] ?? ''}';

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
                            ? const Icon(
                                Icons.image_outlined,
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
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
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
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => setDlg(() => photo = ''),
                              child: const Text(
                                '사진 제거',
                                style: TextStyle(fontSize: 12),
                              ),
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
                    labelText: '그룹 (예: 열전사 / 뱃지 / 굿즈)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: category,
                  decoration: const InputDecoration(
                    labelText: '분류 (예: 검정케이스 / 후드티)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: size,
                  decoration: const InputDecoration(
                    labelText: '사이즈 (예: 40mm / 56cm)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qty,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '수량',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: unitPrice,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '단가',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '금액 (비우면 수량×단가 자동)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  maxLines: 2,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: '비고',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: makerId.isEmpty ? '' : makerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '제작자 배당 (제작자 페이지에 노출)',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('미배당')),
                    for (final m in _makers)
                      DropdownMenuItem(
                        value: '${m['id']}',
                        child: Text(
                          '${m['company'] ?? m['name'] ?? m['id']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setDlg(() => makerId = v ?? ''),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: date,
                  decoration: const InputDecoration(
                    labelText: '날짜 (예: 2026.09.23)',
                    isDense: true,
                  ),
                ),
                // 원가(선택)·제작일 — 마스터 전용 금액/제작 정보
                if (context.read<AppState>().isMaster) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cost,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '원가 (원, 선택)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: madeDate,
                          decoration: const InputDecoration(
                            labelText: '제작일',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
      date: date.text.trim(),
      makerId: makerId,
      cost: int.tryParse(cost.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      madeDate: madeDate.text.trim(),
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
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
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
  static const List<String> _columns = [
    '번호',
    '그룹',
    '분류',
    '사이즈',
    '수량',
    '단가',
    '금액',
  ];

  DocMeta _meta() => DocMeta(
    title: '중앙회 물건 결제 내역',
    subtitle: '한국범스카우트중앙회 · 물건 구매·결제 내역',
    description: '아래 물건의 품목·수량·단가·금액을 확인합니다.',
    author: _whoName.isNotEmpty ? '범#$_whoNumber $_whoName' : '',
    extra: {
      '총 항목': '${_items.length}건',
      '총 수량': '$_totalQty',
      '총 금액': '${_won(_total)}원',
      if (_updated.isNotEmpty) '목록 갱신': _updated,
    },
  );

  List<List<DocCell>> _rows() {
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
        DocCell(
          _won(p['amount']),
          align: 'right',
          bold: true,
          sub: '${p['note'] ?? ''}'.trim().isEmpty ? null : '${p['note']}',
        ),
      ]);
    }
    return rows;
  }

  /// PDF/JPG 저장용 요약(줄 목록 — `DocPdf.build`의 summary 형식).
  List<String> _pdfSummary() => [
    '총 ${_items.length}개 항목 · 총 수량 $_totalQty',
    '총 금액 ${_won(_total)}원',
    '업데이트 ${_updated.isNotEmpty ? _updated : _today()}',
  ];

  String _docHtml() {
    return buildMujiDoc(
      meta: _meta(),
      columns: _columns,
      rows: _rows(),
      summary:
          '총 <b>${_items.length}</b>개 항목 · 총 수량 $_totalQty · '
          '총 금액 <span class="g">${_won(_total)}원</span>',
      footerRight: '업데이트 ${_updated.isNotEmpty ? _updated : _today()}',
    );
  }

  /// 지정 포맷의 **파일 바이트**를 만든다(저장·공유·외부열기 공용).
  Future<({Uint8List bytes, String ext, String mime})> _buildFormatBytes(
    TsakOutputFormat format,
  ) async {
    switch (format) {
      case TsakOutputFormat.pdf:
        return (
          bytes: await DocPdf.build(
            meta: _meta(),
            columns: _columns,
            rows: _rows(),
            summary: _pdfSummary(),
          ),
          ext: 'pdf',
          mime: 'application/pdf',
        );
      case TsakOutputFormat.jpg:
        final bytes = await DocPdf.build(
          meta: _meta(),
          columns: _columns,
          rows: _rows(),
          summary: _pdfSummary(),
        );
        return (bytes: await pdfToJpg(bytes), ext: 'jpg', mime: 'image/jpeg');
      case TsakOutputFormat.excel:
        return (
          bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(_csvText())]),
          ext: 'csv',
          mime: 'text/csv',
        );
      case TsakOutputFormat.ppt:
        return (
          bytes: Uint8List.fromList(utf8.encode(_plainText(format))),
          ext: 'ppt',
          mime: 'application/vnd.ms-powerpoint',
        );
      case TsakOutputFormat.word:
        return (
          bytes: Uint8List.fromList(utf8.encode(_plainText(format))),
          ext: 'doc',
          mime: 'application/msword',
        );
      case TsakOutputFormat.txt:
        return (
          bytes: Uint8List.fromList(
            utf8.encode(_plainText(TsakOutputFormat.txt)),
          ),
          ext: 'txt',
          mime: 'text/plain;charset=utf-8',
        );
    }
  }

  Future<void> _print({TsakOutputFormat format = TsakOutputFormat.pdf}) async {
    if (_items.isEmpty) {
      _snack('인쇄할 항목이 없습니다');
      return;
    }
    try {
      final f = await _buildFormatBytes(format);
      await _saveBytes(f.bytes, '중앙회_물건_결제_내역.${f.ext}', mime: f.mime);
    } catch (e) {
      _snack('${format.label} 생성 실패: $e');
    }
  }

  /// 지정 포맷을 **외부 프로그램**(뷰어·인쇄·기본 앱)으로 연다 — 모든 포맷 공통.
  Future<void> _openFormat(TsakOutputFormat format) async {
    if (_items.isEmpty) {
      _snack('내보낼 항목이 없습니다');
      return;
    }
    try {
      final f = await _buildFormatBytes(format);
      final ok = openFileExternally(
        f.bytes,
        '중앙회_물건_결제_내역.${f.ext}',
        f.mime,
      );
      if (!ok) {
        await _saveBytes(
          f.bytes,
          '중앙회_물건_결제_내역.${f.ext}',
          mime: f.mime,
        );
      }
      _snack(
        ok
            ? '${format.label} 파일을 외부 프로그램으로 열었습니다'
            : '외부 열기가 막혀 ${format.label} 파일로 저장했습니다',
      );
    } catch (e) {
      _snack('열기 실패: $e');
    }
  }

  /// 지정 포맷을 **OS 공유 시트**로 보낸다 — 모든 포맷 공통.
  Future<void> _shareFormat(TsakOutputFormat format) async {
    if (_items.isEmpty) {
      _snack('공유할 항목이 없습니다');
      return;
    }
    try {
      final f = await _buildFormatBytes(format);
      final res = await shareBytes(
        bytes: f.bytes,
        name: '중앙회_물건_결제_내역',
        ext: f.ext,
        mime: f.mime,
        subject: '중앙회 물건 결제 내역',
      );
      _snack(tsakShareMessage(res, what: '${format.label} 물건 결제 내역'));
    } catch (e) {
      _snack('공유 실패: $e');
    }
  }

  /// 바이트를 실제 파일로 저장(웹) / 클립보드 폴백.
  Future<void> _saveBytes(
    Uint8List bytes,
    String filename, {
    String? mime,
  }) async {
    try {
      final ok = await saveBytesAs(
        bytes,
        filename,
        mime ?? mimeForFilename(filename),
      );
      _snack(ok ? '$filename 저장을 시작했습니다' : '저장하지 못했습니다');
    } catch (e) {
      _snack('저장 실패: $e');
    }
  }

  /// 물건 결제 내역 → CSV(엑셀).
  String _csvText() {
    final buf = StringBuffer();
    buf.writeln('번호,그룹,분류,사이즈,수량,단가,금액,비고');
    for (var i = 0; i < _items.length; i++) {
      final p = _items[i];
      buf.writeln(
        '${i + 1},${p['group'] ?? ''},${p['category'] ?? ''},'
        '${p['size'] ?? ''},${p['qty'] ?? 0},${p['unitPrice'] ?? 0},'
        '${p['amount'] ?? 0},${p['note'] ?? ''}',
      );
    }
    return buf.toString();
  }

  /// 물건 결제 내역 → PPT/워드 붙여넣기용 텍스트.
  String _plainText(TsakOutputFormat format) {
    final buf = StringBuffer();
    buf.writeln(
      format == TsakOutputFormat.ppt
          ? '중앙회 물건 결제 (슬라이드용)'
          : '중앙회 물건 결제 내역서 (문서용)',
    );
    buf.writeln(
      '한국범스카우트중앙회 · ${_whoName.isNotEmpty ? '범#$_whoNumber $_whoName' : ''}',
    );
    buf.writeln();
    for (var i = 0; i < _items.length; i++) {
      final p = _items[i];
      buf.writeln(
        '${i + 1}. ${p['group'] ?? ''} ${p['category'] ?? ''} '
        '${p['size'] ?? ''} / ${p['qty'] ?? 0}개 / ${_won(p['amount'])}',
      );
    }
    buf.writeln();
    buf.writeln('총 금액: ${_won(_total)}');
    return buf.toString();
  }

  /// 출력 형식 선택 시트 (#14 규칙) — 모든 포맷 저장·열기·공유.
  Future<void> _showOutputDialog() async {
    if (_items.isEmpty) {
      _snack('출력할 항목이 없습니다');
      return;
    }
    await showTsakOutputSheet(
      context,
      title: '중앙회 물건 결제 내역 출력',
      subtitle: '${_items.length}건 · 총 ${_won(_total)}',
      onPick: (f) => _print(format: f),
      onOpen: _openFormat,
      onShareFormat: _shareFormat,
      onShare: () => _shareFormat(TsakOutputFormat.pdf),
      onShareLink: () => showLinkShareDialog(context, '${_nas.baseUrl}/#/purchase'),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      children: [
        _loading
            ? const SizedBox.shrink()
            : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppColors.taegeukRed,
                    ),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              )
            : _body(),
        BusyOverlay(
          visible: _loading,
          title: '물건 결제 내역을 불러오는 중입니다',
          lines: const [
            'NAS 서버에서 결제 내역을 가져오는 중...',
            '항목별 합계를 집계하는 중...',
            '잠시만 기다려 주세요...',
          ],
        ),
      ],
    );

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
      appBar: TsakAppBar(
        title: const Text('중앙회 물건 결제'),
        actions: [
          IconButton(
            tooltip: '출력 (형식 선택)',
            onPressed: _showOutputDialog,
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
        _viewToolbar(),
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Text(
                    '물건 결제 내역이 없습니다. 아래 + 버튼으로 추가하세요.',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                )
              : _byMaker
              ? _byMakerList()
              : _flatList(),
        ),
      ],
    );
  }

  /// 제작자별 그룹핑 결과: [{makerId, label, items}]
  List<Map<String, dynamic>> _groups() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final p in _items) {
      final mid = '${p['makerId'] ?? ''}'.trim();
      map.putIfAbsent(mid, () => []).add(p);
    }
    final keys = map.keys.toList()
      ..sort((a, b) {
        // 미배당은 항상 맨 아래.
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return _makerLabel(a).compareTo(_makerLabel(b));
      });
    return [
      for (final k in keys)
        {'makerId': k, 'label': _makerLabel(k), 'items': map[k]!},
    ];
  }

  Widget _byMakerList() {
    final groups = _groups();
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
      children: [
        for (final g in groups) _makerGroupCard(g),
        const SizedBox(height: 8),
        _totalLine(),
      ],
    );
  }

  Widget _makerGroupCard(Map<String, dynamic> g) {
    final items = (g['items'] as List).cast<Map<String, dynamic>>();
    final sum = items.fold<int>(0, (a, e) => a + _wonInt(e['amount']));
    final qty = items.fold<int>(0, (a, e) => a + _wonInt(e['qty']));
    final isNone = '${g['makerId']}'.isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 그룹 헤더
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: isNone
                  ? AppColors.textGray.withValues(alpha: 0.08)
                  : AppColors.purple.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isNone ? Icons.help_outline : Icons.factory_outlined,
                  size: 17,
                  color: isNone ? AppColors.textGray : AppColors.purple,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${g['label']}',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      color: isNone ? AppColors.textGray : AppColors.purpleDark,
                    ),
                  ),
                ),
                Text(
                  '${items.length}종 · ${_won(sum)}원',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          // 항목 목록
          for (var i = 0; i < items.length; i++)
            _row(items[i], i, allowDrag: false),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Text(
              '소계  수량 $qty · 금액 ${_won(sum)}원',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.taegeukBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _flatList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
      children: [
        _tableHead(),
        for (var i = 0; i < _items.length; i++) _row(_items[i], i),
        const SizedBox(height: 8),
        _totalLine(),
      ],
    );
  }

  Widget _totalLine() => Text(
    '총 ${_items.length}개 항목 · 총 수량 $_totalQty · 총 금액 ${_won(_total)}원',
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: AppColors.purpleDark,
    ),
  );

  /// 보기 모드 / 전체보기 / 선택(취합·이동) 툴바.
  Widget _viewToolbar() {
    final canMove = context.read<AppState>().isMaster;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('제작자별', style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.factory_outlined, size: 15),
              ),
              ButtonSegment(
                value: false,
                label: Text('전체보기', style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.view_list_outlined, size: 15),
              ),
            ],
            selected: {_byMaker},
            onSelectionChanged: (s) => setState(() => _byMaker = s.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          if (_selectMode) ...[
            Text(
              '선택 ${_selected.length}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _selected.length < 2 ? null : _mergeSelected,
              icon: const Icon(Icons.call_merge, size: 15),
              label: const Text('취합'),
            ),
            if (canMove)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _selected.isEmpty ? null : _moveSelected,
                icon: const Icon(Icons.drive_file_move_outline, size: 15),
                label: const Text('이동'),
              ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => setState(() {
                _selectMode = false;
                _selected.clear();
              }),
              child: const Text('선택 해제', style: TextStyle(fontSize: 12)),
            ),
          ] else
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _items.isEmpty
                  ? null
                  : () => setState(() => _selectMode = true),
              icon: const Icon(Icons.checklist, size: 15),
              label: const Text('선택(취합·이동)'),
            ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _edit(),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('항목 추가'),
          ),
        ],
      ),
    );
  }

  // ---------- 취합(merge) ----------
  Future<void> _mergeSelected() async {
    final sel = _items.where((p) => _selected.contains('${p['id']}')).toList();
    if (sel.length < 2) return;
    // 제작자가 다르면 취합 거부(안전).
    final mids = sel.map((e) => '${e['makerId'] ?? ''}').toSet();
    if (mids.length > 1) {
      _snack('제작자가 다른 항목은 취합할 수 없습니다');
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('취합(합치기)'),
        content: Text(
          '선택한 ${sel.length}개 항목을 하나로 합칠까요?\n'
          '수량·금액은 합산되고, 대표 항목 외 나머지는 삭제됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('취합'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final head = sel.first;
    final sumQty = sel.fold<int>(0, (a, e) => a + _wonInt(e['qty']));
    final sumAmt = sel.fold<int>(0, (a, e) => a + _wonInt(e['amount']));
    final note = sel
        .map((e) => '${e['note'] ?? ''}'.trim())
        .where((s) => s.isNotEmpty)
        .join(' / ');
    // 대표 항목을 합산값으로 갱신.
    await _nas.merchSavePurchase(
      id: '${head['id']}',
      group: '${head['group'] ?? ''}',
      category: '${head['category'] ?? ''}',
      size: '${head['size'] ?? ''}',
      qty: sumQty,
      unitPrice: _wonInt(head['unitPrice']),
      amount: sumAmt,
      note: note.length > 400 ? note.substring(0, 400) : note,
      photo: '${head['photo'] ?? ''}',
      date: '${head['date'] ?? ''}',
      makerId: '${head['makerId'] ?? ''}',
      cost: _wonInt(head['cost']),
      madeDate: '${head['madeDate'] ?? ''}',
      whoName: _whoName,
    );
    // 나머지 삭제.
    for (final e in sel.skip(1)) {
      await _nas.merchDeletePurchase('${e['id']}');
    }
    if (!mounted) return;
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    _snack('${sel.length}개 항목을 취합했습니다');
    _load();
  }

  // ---------- 이동(제작자 재배당) ----------
  Future<void> _moveSelected() async {
    String target = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('이동 (제작자 재배당) · ${_selected.length}건'),
          content: DropdownButtonFormField<String>(
            initialValue: target,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '이동할 제작자'),
            items: [
              const DropdownMenuItem(value: '', child: Text('미배당')),
              for (final m in _makers)
                DropdownMenuItem(
                  value: '${m['id']}',
                  child: Text(
                    '${m['company'] ?? m['name'] ?? m['id']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setDlg(() => target = v ?? ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('이동'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final sel = _items.where((p) => _selected.contains('${p['id']}')).toList();
    for (final p in sel) {
      await _nas.merchSavePurchase(
        id: '${p['id']}',
        group: '${p['group'] ?? ''}',
        category: '${p['category'] ?? ''}',
        size: '${p['size'] ?? ''}',
        qty: _wonInt(p['qty']),
        unitPrice: _wonInt(p['unitPrice']),
        amount: _wonInt(p['amount']),
        note: '${p['note'] ?? ''}',
        photo: '${p['photo'] ?? ''}',
        date: '${p['date'] ?? ''}',
        makerId: target,
        whoName: _whoName,
      );
    }
    if (!mounted) return;
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    _snack('${sel.length}개 항목을 ${_makerLabel(target)}(으)로 이동했습니다');
    _load();
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
              const Icon(
                Icons.receipt_long_outlined,
                size: 18,
                color: AppColors.purple,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '중앙회 물건 결제 내역',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${_items.length}건 · ${_won(_total)}원',
                style: const TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
              if (widget.embedded) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '출력 (형식 선택)',
                  onPressed: _showOutputDialog,
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
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      color: AppColors.textDark,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF4A4A48), width: 1.2),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(width: 30, child: Text('No', style: style)),
          SizedBox(width: 46, child: Text('사진', style: style)),
          Expanded(flex: 4, child: Text('그룹 · 분류', style: style)),
          SizedBox(
            width: 54,
            child: Text('수량', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 66,
            child: Text('금액', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> p, int i, {bool allowDrag = true}) {
    final note = '${p['note'] ?? ''}'.trim();
    final id = '${p['id']}';
    final checked = _selected.contains(id);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDEAE3))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_selectMode)
            SizedBox(
              width: 34,
              child: Checkbox(
                value: checked,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                }),
              ),
            )
          else
            SizedBox(
              width: 30,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textGray,
                ),
              ),
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
                  Text(
                    '${p['category'] ?? p['group'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    [
                      if ('${p['group'] ?? ''}'.trim().isNotEmpty)
                        '${p['group']}',
                      if ('${p['size'] ?? ''}'.trim().isNotEmpty)
                        '${p['size']}',
                      '단가 ${_won(p['unitPrice'])}',
                      '제작 ${_makerLabel('${p['makerId'] ?? ''}')}',
                      if ('${p['date'] ?? ''}'.trim().isNotEmpty)
                        '${p['date']}',
                      if (context.read<AppState>().isMaster &&
                          ((p['cost'] as num?)?.toInt() ?? 0) > 0)
                        '원가 ${_won(p['cost'])}',
                      if (context.read<AppState>().isMaster &&
                          '${p['madeDate'] ?? ''}'.trim().isNotEmpty)
                        '제작일 ${p['madeDate']}',
                    ].join('  ·  '),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                    ),
                  ),
                  if (note.isNotEmpty)
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.scoutGreen,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(
              '${p['qty'] ?? 0}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 66,
            child: Text(
              _won(p['amount']),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.taegeukBlue,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (v) {
                if (v == 'edit') _edit(existing: p);
                if (v == 'amount') _editAmount(p);
                if (v == 'add') _edit(); // 신규 추가
                if (v == 'copy') _duplicate(p); // 이 항목 복사(추가)
                if (v == 'move') _moveOne(p);
                if (v == 'del') _delete(p);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'amount', child: Text('금액 수정')),
                const PopupMenuItem(value: 'edit', child: Text('전체 수정')),
                const PopupMenuItem(value: 'add', child: Text('추가 (신규)')),
                const PopupMenuItem(value: 'copy', child: Text('복사 (이 항목)')),
                const PopupMenuItem(value: 'move', child: Text('이동 (제작자)')),
                const PopupMenuItem(value: 'del', child: Text('삭제')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 항목별 금액수정(빠른 편집) ----------
  Future<void> _editAmount(Map<String, dynamic> p) async {
    final c = TextEditingController(
      text: _wonInt(p['amount']) == 0 ? '' : '${_wonInt(p['amount'])}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('금액 수정 · ${p['category'] ?? p['group'] ?? ''}'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '금액 (원)', isDense: true),
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
    final amt = int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final r = await _nas.merchSavePurchase(
      id: '${p['id']}',
      group: '${p['group'] ?? ''}',
      category: '${p['category'] ?? ''}',
      size: '${p['size'] ?? ''}',
      qty: _wonInt(p['qty']),
      unitPrice: _wonInt(p['unitPrice']),
      amount: amt,
      note: '${p['note'] ?? ''}',
      photo: '${p['photo'] ?? ''}',
      date: '${p['date'] ?? ''}',
      makerId: '${p['makerId'] ?? ''}',
      cost: _wonInt(p['cost']),
      madeDate: '${p['madeDate'] ?? ''}',
      whoName: _whoName,
    );
    if (!mounted) return;
    _snack(r['ok'] == true ? '금액을 수정했습니다' : '수정 실패');
    if (r['ok'] == true) _load();
  }

  // ---------- 복사(추가) ----------
  Future<void> _duplicate(Map<String, dynamic> p) async {
    final r = await _nas.merchSavePurchase(
      id: '', // 새 항목
      group: '${p['group'] ?? ''}',
      category: '${p['category'] ?? ''}',
      size: '${p['size'] ?? ''}',
      qty: _wonInt(p['qty']),
      unitPrice: _wonInt(p['unitPrice']),
      amount: _wonInt(p['amount']),
      note: '${p['note'] ?? ''}',
      photo: '${p['photo'] ?? ''}',
      date: '${p['date'] ?? ''}',
      makerId: '${p['makerId'] ?? ''}',
      cost: _wonInt(p['cost']),
      madeDate: '${p['madeDate'] ?? ''}',
      whoName: _whoName,
    );
    if (!mounted) return;
    _snack(r['ok'] == true ? '복사했습니다' : '복사 실패');
    if (r['ok'] == true) _load();
  }

  // ---------- 단건 이동(제작자 재배당) ----------
  Future<void> _moveOne(Map<String, dynamic> p) async {
    String target = '${p['makerId'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('이동 (제작자 재배당)'),
          content: DropdownButtonFormField<String>(
            initialValue: target,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '이동할 제작자'),
            items: [
              const DropdownMenuItem(value: '', child: Text('미배당')),
              for (final m in _makers)
                DropdownMenuItem(
                  value: '${m['id']}',
                  child: Text(
                    '${m['company'] ?? m['name'] ?? m['id']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setDlg(() => target = v ?? ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('이동'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final r = await _nas.merchSavePurchase(
      id: '${p['id']}',
      group: '${p['group'] ?? ''}',
      category: '${p['category'] ?? ''}',
      size: '${p['size'] ?? ''}',
      qty: _wonInt(p['qty']),
      unitPrice: _wonInt(p['unitPrice']),
      amount: _wonInt(p['amount']),
      note: '${p['note'] ?? ''}',
      photo: '${p['photo'] ?? ''}',
      date: '${p['date'] ?? ''}',
      makerId: target,
      cost: _wonInt(p['cost']),
      madeDate: '${p['madeDate'] ?? ''}',
      whoName: _whoName,
    );
    if (!mounted) return;
    _snack(r['ok'] == true ? '${_makerLabel(target)}(으)로 이동했습니다' : '이동 실패');
    if (r['ok'] == true) _load();
  }

  Widget _photoThumb(Map<String, dynamic> p) {
    final photo = '${p['photo'] ?? ''}'.trim();
    if (photo.isEmpty) {
      return Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 20,
          color: AppColors.textGray.withValues(alpha: 0.4),
        ),
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
            color: AppColors.textGray,
          ),
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
              child: Image.network(
                _nas.merchImageUrl(photo),
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${p['category'] ?? p['group'] ?? ''}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
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
}
