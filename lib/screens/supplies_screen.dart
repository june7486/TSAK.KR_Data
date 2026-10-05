import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/file_save.dart';
import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../services/output_formats.dart';
import '../services/table_export.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/tsak_output_sheet.dart';
import '../widgets/tsak_table_options.dart';

/// 중앙회 비품 재고 리스트 — 표 형식 관리 화면.
///
/// - 품명 · 구분 · 수량 · 비고 + 업데이트/확인 날짜 · 확인자(인가번호·이름)
/// - 추가·수정·삭제, 좌측 손잡이로 **위치 이동**(순서 변경)
/// - **선택 창**(전체선택/선택 해제/개별 선택) — 명부출력과 동일
/// - **출력 옵션**(출력내용 선택·위치 이동·글씨크기·줄간격·가로/세로) — 명부출력과 동일
/// - 모든 포맷(PDF·JPG·엑셀·PPT·워드·TXT) 저장·열기·공유(아이폰 포함) — 명부출력과 동일 틀
///
/// [embedded] 가 true 이면 독립 Scaffold 없이 본문만 렌더한다(= 수품 판매관리 탭).
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

  // ── 명부출력식 선택/출력 상태 ──
  final Set<String> _sel = {};
  bool _selMode = false;
  bool _busyBuilding = false;
  TableOutputOptions? _outOpts;

  /// 비품 표준 컬럼 — 명부출력과 동일 규칙(구분 포함).
  static const List<String> _cols = [
    '번호',
    '구분',
    '품명',
    '수량',
    '비고',
    '확인일자',
    '확인자',
  ];

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
      final items = _list(r['supplies']);
      final cfg = ((r['config'] as Map?) ?? {}).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _items = items;
        _updated = '${cfg['suppliesUpdatedAt'] ?? ''}';
        _loading = false;
        _sel.clear();
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

  String _whoLabel(Map<String, dynamic> s) {
    final by = '${s['checkedBy'] ?? ''}'.trim();
    final nm = '${s['checkedByName'] ?? ''}'.trim();
    return [if (by.isNotEmpty) '범#$by', if (nm.isNotEmpty) nm].join(' ');
  }

  int get _total =>
      _items.fold<int>(0, (a, e) => a + ((e['qty'] as num?)?.toInt() ?? 0));

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

  // ---------- 추가 / 수정 (구분 포함) ----------
  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: '${existing?['name'] ?? ''}');
    final qty = TextEditingController(text: '${existing?['qty'] ?? ''}');
    final note = TextEditingController(text: '${existing?['note'] ?? ''}');
    final category = TextEditingController(
      text: '${existing?['category'] ?? ''}',
    );
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
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: '품명 *',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: category,
                  decoration: const InputDecoration(
                    labelText: '구분 (예: 잼버리 과정활동, 사무용품, 행사용품 등)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final c in kSupplyCategories)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          label: Text(
                            c,
                            style: const TextStyle(fontSize: 10.5),
                          ),
                          onPressed: () => setDlg(() => category.text = c),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '수량',
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
                TextField(
                  controller: checked,
                  decoration: const InputDecoration(
                    labelText: '재고 확인 날짜',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '확인자: 범#$_whoNumber $_whoName',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGray,
                    ),
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
      category: category.text.trim(),
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

  // ==================== 선택 창 (명부출력과 동일) ====================
  List<String> get _selKeys => [for (var i = 0; i < _items.length; i++) 'r$i'];

  List<Map<String, dynamic>> _selectedItems() => [
    for (var i = 0; i < _items.length; i++)
      if (_sel.contains('r$i')) _items[i],
  ];

  Widget _selPanel() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, size: 16, color: AppColors.purple),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  '선택 창',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AppColors.purpleDark,
                  ),
                ),
              ),
              Text(
                '${_sel.length}건',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purpleDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: () => setState(() {
                  _selMode = true;
                  _sel
                    ..clear()
                    ..addAll(_selKeys);
                }),
                child: const Text('전체선택', style: TextStyle(fontSize: 11.5)),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: _sel.isEmpty
                    ? null
                    : () => setState(() => _sel.clear()),
                child: const Text('선택 해제', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
          const Divider(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: _busyBuilding
                  ? null
                  : () => _openOutputSheet(selectedOnly: false),
              icon: const Icon(Icons.ios_share, size: 16),
              label: const Text(
                '모두 출력 (형식)',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.purpleDark,
                padding: const EdgeInsets.symmetric(vertical: 10),
                side: BorderSide(
                  color: AppColors.purple.withValues(alpha: 0.35),
                ),
              ),
              onPressed: (_sel.isEmpty || _busyBuilding)
                  ? null
                  : () => _openOutputSheet(selectedOnly: true),
              icon: const Icon(Icons.print_outlined, size: 16),
              label: const Text(
                '선택 항목 출력',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.purpleDark,
                padding: const EdgeInsets.symmetric(vertical: 8),
                side: BorderSide(
                  color: AppColors.purple.withValues(alpha: 0.25),
                ),
              ),
              onPressed: _busyBuilding ? null : _editOptions,
              icon: const Icon(Icons.tune, size: 15),
              label: const Text(
                '출력 옵션',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch.adaptive(
                value: _selMode,
                onChanged: (v) => setState(() {
                  _selMode = v;
                  if (!v) _sel.clear();
                }),
              ),
              const Expanded(
                child: Text(
                  '표에서 개별 선택 (관리 모드)',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
                ),
              ),
            ],
          ),
          if (_selMode)
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 2),
              child: Text(
                '· 표 행의 체크박스로 항목을 고르세요.',
                style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 출력 옵션 / 출력 / 공유 (명부출력과 동일) ====================
  TsakTableDoc _doc({required bool selectedOnly}) {
    final src = selectedOnly ? _selectedItems() : _items;
    final rows = <List<String>>[
      for (var i = 0; i < src.length; i++)
        [
          '${i + 1}',
          '${src[i]['category'] ?? ''}',
          '${src[i]['name'] ?? ''}',
          '${src[i]['qty'] ?? 0}',
          '${src[i]['note'] ?? ''}',
          '${src[i]['checkedAt'] ?? src[i]['updatedAt'] ?? ''}',
          _whoLabel(src[i]),
        ],
    ];
    final total = src.fold<int>(
      0,
      (a, e) => a + ((e['qty'] as num?)?.toInt() ?? 0),
    );
    return TsakTableDoc(
      title: selectedOnly ? '중앙회 비품 재고 (선택)' : '중앙회 비품 재고 리스트',
      subtitle: '한국범스카우트중앙회 · 비품 재고 및 입출고 현황',
      description: '아래 비품의 구분·수량·비고와 확인일자·확인자를 함께 기재합니다.',
      author: _whoName.isNotEmpty ? '범#$_whoNumber $_whoName' : '',
      extra: {
        '총 항목': '${src.length}건',
        '총 수량': '$total',
        if (_updated.isNotEmpty) '목록 갱신': _updated,
        '건수': selectedOnly ? '선택 ${src.length}건' : '전체 ${src.length}건',
      },
      columns: _cols,
      rows: rows,
      summary: ['총 ${src.length}건 · 총 수량 $total'],
      footerLeft: '한국범스카우트중앙회 · 비품 재고',
      options: _outOpts,
    );
  }

  Future<void> _editOptions() async {
    final out = await showTsakTableOptions(
      context,
      title: '비품 재고 출력 옵션',
      subtitle: '출력할 항목을 고르고, 순서를 옮기고, 줄 간격·글씨·용지를 정하세요.',
      columns: _cols,
      initial: _outOpts,
    );
    if (out != null && mounted) {
      setState(() => _outOpts = out);
      _snack('출력 옵션을 저장했습니다 · ${out.badge}');
    }
  }

  Future<void> _openOutputSheet({required bool selectedOnly}) async {
    final n = selectedOnly ? _selectedItems().length : _items.length;
    if (n == 0) {
      _snack(selectedOnly ? '선택된 항목이 없습니다' : '출력할 항목이 없습니다');
      return;
    }
    await showTsakOutputSheet(
      context,
      title: selectedOnly ? '비품 재고 선택 출력' : '중앙회 비품 재고 리스트 출력',
      subtitle: selectedOnly ? '선택 $n건' : '전체 $n건 · 비품 재고 및 입출고 현황',
      onPick: (f) => _runOutput(selectedOnly: selectedOnly, format: f),
      onOpen: (f) =>
          _runOutput(selectedOnly: selectedOnly, format: f, open: true),
      onShareFormat: (f) =>
          _runOutput(selectedOnly: selectedOnly, format: f, share: true),
      onPrint: () => _runOutput(
        selectedOnly: selectedOnly,
        format: TsakOutputFormat.pdf,
        justPrint: true,
      ),
      onEmail: () => _emailOutput(selectedOnly: selectedOnly),
      onShare: () => _runOutput(
        selectedOnly: selectedOnly,
        format: TsakOutputFormat.pdf,
        share: true,
      ),
      onOptions: _editOptions,
      onShareLink: () =>
          showLinkShareDialog(context, '${_nas.baseUrl}/#/supplies'),
    );
  }

  Future<void> _runOutput({
    required bool selectedOnly,
    required TsakOutputFormat format,
    bool open = false,
    bool share = false,
    bool justPrint = false,
  }) async {
    final src = selectedOnly ? _selectedItems() : _items;
    if (src.isEmpty) {
      _snack('출력할 항목이 없습니다');
      return;
    }
    final doc = _doc(selectedOnly: selectedOnly);
    setState(() => _busyBuilding = true);
    try {
      // 1) 저장 위치를 진행창 이전에 먼저 확정(명부출력과 동일).
      var choose = false;
      if (!open && !share && !justPrint) {
        final loc = await askTsakSaveLocation(
          context,
          info: '중앙회 비품 재고 · ${src.length}건 · ${format.label}',
        );
        if (loc == null) {
          if (mounted) _snack('저장을 취소했습니다');
          return;
        }
        choose = loc;
      }
      if (!mounted) return;
      // 2) 진행창 + 생성/열기/공유/인쇄.
      await runWithTsakProgress(
        context,
        title: justPrint
            ? '비품 재고 프린트 준비'
            : '${open
                  ? '외부 열기'
                  : share
                  ? '공유'
                  : '저장'} · 비품 재고 ${format.label}',
        note: '${src.length}건 비품 목록을 처리합니다.',
        steps: const ['문서 구성', '파일 생성', '내보내기'],
        task: (ctl) async {
          ctl.update(progress: 0.2, message: '문서를 구성하는 중…', stepIndex: 0);
          ctl.update(
            progress: 0.6,
            message: '${format.label} 생성 중…',
            stepIndex: 1,
          );
          if (justPrint) {
            await printTsakTable(doc);
          } else if (open) {
            final res = await openTsakTableChosen(context, doc, format);
            if (mounted)
              _snack(tsakShareMessage(res, what: '비품 ${format.label}'));
          } else if (share) {
            final res = await shareTsakTableChosen(context, doc, format);
            if (mounted)
              _snack(tsakShareMessage(res, what: '비품 ${format.label}'));
          } else {
            await saveTsakTableChosen(context, doc, format, choose: choose);
            if (mounted) _snack('${format.label} 저장을 시작했습니다');
          }
          ctl.update(progress: 1.0, message: '완료', stepIndex: 2);
        },
      );
    } catch (e) {
      if (mounted) _snack('출력 실패: $e');
    } finally {
      if (mounted) setState(() => _busyBuilding = false);
    }
  }

  Future<void> _emailOutput({required bool selectedOnly}) async {
    final src = selectedOnly ? _selectedItems() : _items;
    if (src.isEmpty) {
      _snack('메일로 보낼 항목이 없습니다');
      return;
    }
    await emailTsakTable(context, _doc(selectedOnly: selectedOnly));
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
          title: '비품 재고를 불러오는 중입니다',
          lines: const [
            'NAS 서버에서 비품 목록을 가져오는 중...',
            '재고 수량을 집계하는 중...',
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
            onPressed: _busyBuilding
                ? null
                : () => _openOutputSheet(selectedOnly: false),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: '출력 옵션',
            onPressed: _busyBuilding ? null : _editOptions,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: '메일 발송',
            onPressed: () => _emailOutput(selectedOnly: false),
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

  Widget _body() {
    return Column(
      children: [
        _headerBox(),
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Text(
                    '비품이 없습니다. 아래 + 버튼으로 추가하세요.',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                )
              : _tableWrap(),
        ),
      ],
    );
  }

  /// 선택창 + 표 (넓으면 좌우, 좁으면 상하) — 명부출력과 동일 배치.
  Widget _tableWrap() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final wide = c.maxWidth >= 760;
          final panel = _selPanel();
          final table = _table();
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 240, child: panel),
                const SizedBox(width: 10),
                Expanded(child: table),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
            children: [panel, const SizedBox(height: 10), table],
          );
        },
      ),
    );
  }

  Widget _table() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
            final key = 'r$i';
            return Container(
              key: ValueKey('sp-${s['id']}'),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEDEAE3))),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 위치 이동 손잡이 (명부출력과 동일한 관리 모드).
                    ReorderableDragStartListener(
                      index: i,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Container(
                          width: 30,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Icon(
                            Icons.drag_indicator,
                            size: 18,
                            color: AppColors.textGray.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: _row(s, i, key)),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '총 ${_items.length}개 항목 · 총 수량 $_total',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.purpleDark,
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
              const Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: AppColors.purple,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '중앙회 비품 재고 리스트',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${_items.length}건 · $_total개',
                style: const TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '출력 (형식 선택)',
                onPressed: _busyBuilding
                    ? null
                    : () => _openOutputSheet(selectedOnly: false),
                icon: const Icon(Icons.print_outlined, size: 20),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '출력 옵션',
                onPressed: _busyBuilding ? null : _editOptions,
                icon: const Icon(Icons.tune, size: 20),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '메일',
                onPressed: () => _emailOutput(selectedOnly: false),
                icon: const Icon(Icons.email_outlined, size: 20),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '새로고침',
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '업데이트 ${_updated.isNotEmpty ? _updated : _today()}'
            '${_whoName.isNotEmpty ? '   ·   확인자 범#$_whoNumber $_whoName' : ''}',
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
          SizedBox(width: 30),
          SizedBox(width: 30, child: Text('No', style: style)),
          SizedBox(
            width: 46,
            child: Text('사진', style: style, textAlign: TextAlign.center),
          ),
          Expanded(flex: 5, child: Text('품명 / 구분', style: style)),
          SizedBox(
            width: 60,
            child: Text('수량', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(width: 22),
          Expanded(flex: 3, child: Text('비고', style: style)),
          SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _qtyCell(Map<String, dynamic> s) {
    return _InlineQty(
      value: (s['qty'] as num?)?.toInt() ?? 0,
      onChanged: (v) => _saveQty(s, v),
    );
  }

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
      category: '${s['category'] ?? ''}',
    );
    if (!mounted) return;
    if (r['ok'] != true) {
      _snack('수량 저장 실패');
      return;
    }
    setState(() => s['qty'] = qty);
    _snack('수량을 $qty개로 저장했습니다');
  }

  Widget _row(Map<String, dynamic> s, int i, String key) {
    final checkedAt = '${s['checkedAt'] ?? ''}'.trim();
    final updatedAt = '${s['updatedAt'] ?? ''}'.trim();
    final who = _whoLabel(s);
    final category = '${s['category'] ?? ''}'.trim();
    final on = _sel.contains(key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 관리 모드일 때만 체크박스 노출(명부출력과 동일).
          if (_selMode)
            SizedBox(
              width: 30,
              child: Checkbox(
                value: on,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => setState(() {
                  if (on) {
                    _sel.remove(key);
                  } else {
                    _sel.add(key);
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
          SizedBox(width: 46, child: _photoThumb(s)),
          Expanded(
            flex: 5,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _edit(existing: s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (category.isNotEmpty)
                    Text(
                      category,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purple,
                      ),
                    ),
                  Text(
                    '${s['name'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (checkedAt.isNotEmpty || updatedAt.isNotEmpty)
                    Text(
                      '확인 $checkedAt'
                      '${updatedAt.isNotEmpty ? '  ·  갱신 $updatedAt' : ''}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textGray,
                      ),
                    ),
                  if (who.isNotEmpty)
                    Text(
                      '확인자 $who',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.scoutGreen,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: 60, child: _qtyCell(s)),
          const SizedBox(width: 22),
          Expanded(
            flex: 3,
            child: Text(
              '${s['note'] ?? ''}',
              style: const TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
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

  Widget _photoThumb(Map<String, dynamic> s) {
    final photo = '${s['photo'] ?? ''}'.trim();
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
            color: AppColors.textGray,
          ),
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
              child: Image.network(
                _nas.merchImageUrl(photo),
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${s['name'] ?? ''}',
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

/// 재고 수량 인라인 편집 위젯 — 숫자를 누르면 바로 입력/저장.
class _InlineQty extends StatefulWidget {
  const _InlineQty({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_InlineQty> createState() => _InlineQtyState();
}

class _InlineQtyState extends State<_InlineQty> {
  late final TextEditingController _ctrl = TextEditingController(
    text: '${widget.value}',
  );
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
      _ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _ctrl.text.length,
      );
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
        borderRadius: BorderRadius.circular(6),
        child: Tooltip(
          message: '탭하여 수량 수정',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Center(
              child: Text(
                '${widget.value}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.taegeukBlue,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.taegeukBlue,
                  decorationStyle: TextDecorationStyle.dotted,
                ),
              ),
            ),
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
          color: AppColors.taegeukBlue,
        ),
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

/// 구분(카테고리) 프리셋 — 비품 등록 시 빠른 선택용(인수인계 PDF 08페이지 분류).
const List<String> kSupplyCategories = [
  '잼버리 과정활동',
  '야영·장비',
  '행사·의전',
  '사무용품',
  '액자·기념',
  '배너·현수막',
  '포장·정리',
];
