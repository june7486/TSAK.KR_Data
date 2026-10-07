import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/export_save.dart';
import '../services/file_pick.dart';
import '../theme/app_theme.dart';

/// 재무 거래 1건의 첨부파일 관리 패널.
///
/// · 첨부 업로드(엑셀·pdf·jpg·png·zip·ppt 등 **모든 포맷**)
/// · 각 첨부 클릭 → 내용 확인(미리보기) + 다운로드 + 다른 앱 공유
/// · 선택/이름변경/이동/삭제
///
/// 마스터가 '재무 · 첨부파일' 권한을 끄면 업로드/삭제 버튼이 숨겨진다(조회만).
class FinanceAttachPanel extends StatefulWidget {
  const FinanceAttachPanel({
    super.key,
    required this.txid,
    this.title = '첨부파일',
  });

  final String txid;
  final String title;

  @override
  State<FinanceAttachPanel> createState() => _FinanceAttachPanelState();
}

class _FinanceAttachPanelState extends State<FinanceAttachPanel> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  bool _busy = false;
  final Set<String> _sel = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _canEdit {
    final s = context.read<AppState>();
    return s.isMaster || s.can('finAttach');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await context.read<AppState>().nas.fetchFinanceAttach(
      widget.txid,
    );
    if (!mounted) return;
    setState(() {
      _files = list;
      _loading = false;
    });
  }

  Future<void> _upload() async {
    // 모든 포맷 허용 (allowedExtensions 비움).
    final picked = await pickDataFiles(allowMultiple: true);
    if (picked.isEmpty) return;
    setState(() => _busy = true);
    for (final f in picked) {
      await context.read<AppState>().nas.uploadFinanceAttach(
        widget.txid,
        f.name,
        f.bytes,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    _snack('첨부 ${picked.length}건을 업로드했습니다');
  }

  Future<void> _open(Map<String, dynamic> f) async {
    final name = '${f['name'] ?? ''}';
    final url = context.read<AppState>().nas.financeAttachUrl(
      widget.txid,
      name,
    );
    final isImg = RegExp(
      r'\.(jpg|jpeg|png|gif|webp|bmp)$',
      caseSensitive: false,
    ).hasMatch(name);
    final isPdf = name.toLowerCase().endsWith('.pdf');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconFor(name), color: AppColors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${_fmtSize(f['size'])} · ${f['storage'] ?? 'nas'} · '
                '${f['uploaded'] ?? ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(height: 14),
              if (isImg)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    url,
                    headers: context.read<AppState>().nas.authHeaderMap,
                    height: 260,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('이미지를 불러올 수 없습니다 (권한 확인)'),
                    ),
                  ),
                ),
              if (isPdf)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.picture_as_pdf, color: AppColors.taegeukRed),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'PDF 문서입니다. 다운로드 후 확인하세요.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!isImg && !isPdf)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.insert_drive_file, color: AppColors.textGray),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '문서/압축 파일입니다. 다운로드 후 확인하세요.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _download(f),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('다운로드'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _share(name, url),
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('다른 앱으로'),
                    ),
                  ),
                ],
              ),
              if (_canEdit) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _rename(f),
                        icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                        label: const Text('이름변경/이동'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.taegeukRed,
                        ),
                        onPressed: () => _delete(f),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('삭제'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _download(Map<String, dynamic> f) async {
    final name = '${f['name'] ?? ''}';
    try {
      final (bytes, _) = await context.read<AppState>().nas.fetchBytes(
        context.read<AppState>().nas.financeAttachUrl(widget.txid, name),
      );
      await saveBytesAs(bytes, name.split('/').last, mimeForFilename(name));
      _snack('$name 다운로드를 시작했습니다');
    } catch (e) {
      _snack('다운로드 실패: $e');
    }
  }

  Future<void> _share(String name, String url) async {
    final s = context.read<AppState>();
    await showLinkShareDialog(context, name, url, extraHeaders: s.nas.authHeaderMap);
  }

  Future<void> _rename(Map<String, dynamic> f) async {
    final name = '${f['name'] ?? ''}';
    final ctrl = TextEditingController(text: name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('이름변경 / 이동'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '이름을 바꾸거나, "폴더/새이름" 처럼 입력하면 하위 폴더로 이동합니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '새 이름 또는 경로',
                hintText: '예: 2024/영수증.pdf',
                isDense: true,
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
            child: const Text('적용'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final nn = ctrl.text.trim();
    if (nn.isEmpty || nn == name) return;
    await context.read<AppState>().nas.renameFinanceAttach(
      widget.txid,
      name,
      nn,
    );
    await _load();
    _snack('이름/위치를 변경했습니다');
  }

  Future<void> _delete(Map<String, dynamic> f) async {
    final name = '${f['name'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('첨부 삭제'),
        content: Text("'$name' 을(를) 삭제할까요?", style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.taegeukRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().nas.deleteFinanceAttach(widget.txid, name);
    await _load();
    _snack('삭제했습니다');
  }

  Future<void> _bulkDelete() async {
    if (_sel.isEmpty) return;
    final n = _sel.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('선택 첨부 삭제'),
        content: Text('선택한 $n개 첨부를 삭제할까요?', style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.taegeukRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final name in _sel.toList()) {
      await context.read<AppState>().nas.deleteFinanceAttach(widget.txid, name);
    }
    _sel.clear();
    await _load();
    _snack('$n개를 삭제했습니다');
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_file, size: 18, color: AppColors.purple),
                const SizedBox(width: 6),
                Text(
                  '${widget.title} (${_files.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const Spacer(),
                if (_canEdit)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _busy ? null : _upload,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('첨부 추가'),
                  ),
                if (_canEdit && _sel.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.taegeukRed,
                    ),
                    onPressed: _bulkDelete,
                    icon: const Icon(Icons.delete_sweep, size: 16),
                    label: Text('선택삭제(${_sel.length})'),
                  ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_files.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '첨부파일이 없습니다. (엑셀·PDF·이미지·압축·PPT 등 모든 포맷 가능)',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
                ),
              )
            else
              Column(
                children: [
                  for (final f in _files) _attachRow(f),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _attachRow(Map<String, dynamic> f) {
    final name = '${f['name'] ?? ''}';
    final selected = _sel.contains(name);
    return InkWell(
      onTap: () => _open(f),
      onLongPress: _canEdit
          ? () => setState(() {
                if (selected) {
                  _sel.remove(name);
                } else {
                  _sel.add(name);
                }
              })
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.purple.withValues(alpha: 0.12)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.purple.withValues(alpha: selected ? 0.5 : 0.15),
          ),
        ),
        child: Row(
          children: [
            if (_canEdit)
              Icon(
                selected
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 18,
                color: AppColors.purple,
              ),
            if (_canEdit) const SizedBox(width: 6),
            Icon(_iconFor(name), size: 20, color: AppColors.taegeukBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${_fmtSize(f['size'])} · ${f['storage'] ?? 'nas'}'
                    '${f['uploaded'] != null ? ' · ${f['uploaded']}' : ''}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textGray),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)$').hasMatch(n)) {
      return Icons.image_outlined;
    }
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (RegExp(r'\.(xls|xlsx|csv)$').hasMatch(n)) return Icons.table_chart;
    if (RegExp(r'\.(ppt|pptx)$').hasMatch(n)) return Icons.slideshow;
    if (RegExp(r'\.(doc|docx)$').hasMatch(n)) return Icons.description;
    if (RegExp(r'\.(zip|7z|rar|tar|gz)$').hasMatch(n)) {
      return Icons.folder_zip;
    }
    if (RegExp(r'\.(mp4|mov|avi|mkv)$').hasMatch(n)) return Icons.movie;
    if (RegExp(r'\.(mp3|wav|m4a)$').hasMatch(n)) return Icons.audiotrack;
    return Icons.insert_drive_file;
  }

  static String _fmtSize(dynamic s) {
    final n = (s is num) ? s.toInt() : int.tryParse('$s') ?? 0;
    if (n <= 0) return '크기 미상';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) {
      return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
