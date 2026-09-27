import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import 'finance_analysis_screen.dart';

/// 기본자료 폴더 — 명단/인가자명단/은행거래내역/후원현황/지출내역/행사자료 파일 첨부
/// 첨부 시 NAS에 저장하고 자동 분석하여 요약을 보여준다.
class SourceFolderScreen extends StatefulWidget {
  const SourceFolderScreen({super.key});

  @override
  State<SourceFolderScreen> createState() => _SourceFolderScreenState();
}

class _SourceFolderScreenState extends State<SourceFolderScreen> {
  static const _folders = [
    ('member_list', '인가자명단', Icons.badge, AppColors.purple),
    ('roster', '명단', Icons.list_alt, AppColors.taegeukBlue),
    ('bank', '은행거래내역', Icons.account_balance, AppColors.scoutGreen),
    ('donation', '후원현황', Icons.volunteer_activism, AppColors.taegeukRed),
    ('expense', '지출내역', Icons.payments, Color(0xFFB8860B)),
    ('event', '행사자료', Icons.event, Color(0xFF00838F)),
  ];

  String _selected = 'member_list';
  List<Map<String, dynamic>> _files = [];
  bool _loading = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final nas = context.read<NasApi>();
      final files = await nas.listFiles(_selected);
      if (mounted) setState(() => _files = files);
    } catch (_) {
      if (mounted) setState(() => _files = []);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('기본자료 폴더'),
        titleSpacing: 0,
        actions: [
          const AppHomeEmblem(size: 24),
          if (_selected == 'bank')
            IconButton(
              tooltip: '은행거래 종합분석 보고서',
              icon: const Icon(Icons.insights, color: AppColors.scoutGreen),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FinanceAnalysisScreen()),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.purple,
        onPressed: _busy ? null : _pickAndUpload,
        icon: _busy
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.attach_file),
        label: const Text('파일 첨부'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  for (final f in _folders)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: Icon(f.$3,
                            size: 15,
                            color: _selected == f.$1
                                ? Colors.white
                                : f.$4),
                        label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                        selected: _selected == f.$1,
                        selectedColor: f.$4,
                        labelStyle: TextStyle(
                          color: _selected == f.$1
                              ? Colors.white
                              : AppColors.textDark,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selected = f.$1;
                            _files = [];
                          });
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 15, color: AppColors.textGray),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '첨부한 파일은 NAS "$_selectedLabel" 폴더에 저장되고 '
                    '자동 분석되어 인가자별 기록·통계에 반영됩니다.',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textGray),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? _empty()
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _files.length,
                        itemBuilder: (_, i) => _fileTile(_files[i]),
                      ),
          ),
        ],
      ),
    );
  }

  String get _selectedLabel =>
      _folders.firstWhere((f) => f.$1 == _selected).$2;

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open,
                size: 56, color: AppColors.textGray.withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            Text('$_selectedLabel 폴더가 비어 있습니다',
                style: const TextStyle(color: AppColors.textGray, fontSize: 13)),
            const SizedBox(height: 4),
            const Text('아래 파일 첨부 버튼으로 자료를 올려주세요',
                style: TextStyle(color: AppColors.textGray, fontSize: 11.5)),
          ],
        ),
      );

  Widget _fileTile(Map<String, dynamic> f) {
    final name = '${f['name']}';
    final size = (f['size'] is num) ? (f['size'] as num).toInt() : 0;
    IconData icon = Icons.insert_drive_file;
    Color color = AppColors.textGray;
    final low = name.toLowerCase();
    if (low.endsWith('.xlsx') || low.endsWith('.xls') || low.endsWith('.csv')) {
      icon = Icons.table_chart;
      color = AppColors.scoutGreen;
    } else if (low.endsWith('.pdf')) {
      icon = Icons.picture_as_pdf;
      color = AppColors.taegeukRed;
    } else if (low.endsWith('.jpg') || low.endsWith('.png')) {
      icon = Icons.image;
      color = AppColors.taegeukBlue;
    } else if (low.endsWith('.docx') || low.endsWith('.doc')) {
      icon = Icons.description;
      color = AppColors.purple;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.13),
          child: Icon(icon, size: 19, color: color),
        ),
        title: Text(name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        subtitle: Text(_sizeText(size),
            style: const TextStyle(fontSize: 11, color: AppColors.textGray)),
        trailing: IconButton(
          icon: const Icon(Icons.download, size: 20),
          onPressed: () {
            final nas = context.read<NasApi>();
            final url = nas.fileDownloadUrl(_selected, name);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: SelectableText(url,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 11, color: Colors.white)),
                duration: const Duration(seconds: 6),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    final nas = context.read<NasApi>();
    final res = await pickDataFiles();
    if (res.isEmpty) return;
    final f = res.first;
    final bytes = f.bytes;
    if (bytes.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await nas.uploadFile(_selected, f.name, bytes);
      if (!mounted) return;
      final analysis = r['analysis'];
      final summary = (analysis is Map) ? '${analysis['summary'] ?? ''}' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('업로드 완료 · $summary'),
          backgroundColor: AppColors.scoutGreen,
          duration: const Duration(seconds: 4),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('업로드 실패: $e'),
          backgroundColor: AppColors.taegeukRed,
        ),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  static String _sizeText(int bytes) {
    if (bytes <= 0) return '-';
    if (bytes > 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes > 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}
