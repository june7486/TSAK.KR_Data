import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/hscroll_menu.dart';
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
      appBar: TsakAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('기본자료 폴더'),
        titleSpacing: 0,
        actions: [
          const AppHomeEmblem(size: 24),
          if (_selected == 'member_list')
            IconButton(
              tooltip: '회원정보 업데이트 (주소록 엑셀 반영)',
              icon: const Icon(Icons.sync_alt, color: AppColors.purple),
              onPressed: _busy ? null : _syncAddressbookFromPicker,
            ),
          if (_selected == 'bank')
            IconButton(
              tooltip: '은행거래 종합분석 보고서',
              icon: const Icon(Icons.insights, color: AppColors.scoutGreen),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FinanceAnalysisScreen(),
                ),
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
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.attach_file),
        label: const Text('파일 첨부'),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: HScrollMenu(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      for (final f in _folders)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            avatar: Icon(
                              f.$3,
                              size: 15,
                              color: _selected == f.$1 ? Colors.white : f.$4,
                            ),
                            label: Text(
                              f.$2,
                              style: const TextStyle(fontSize: 12),
                            ),
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
                    const Icon(
                      Icons.info_outline,
                      size: 15,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '첨부한 파일은 NAS "$_selectedLabel" 폴더에 저장되고 '
                        '자동 분석되어 인가자별 기록·통계에 반영됩니다.',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textGray,
                        ),
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
          BusyOverlay(
            visible: _loading || _busy,
            title: _busy ? '파일을 처리하는 중입니다' : '기본자료를 불러오는 중입니다',
            lines: _busy
                ? const [
                    'NAS 서버에 파일을 저장하고 있습니다...',
                    '자동 분석하여 반영하는 중...',
                    '잠시만 기다려 주세요...',
                  ]
                : const [
                    'NAS 서버에서 폴더 목록을 가져오는 중...',
                    '파일 목록을 정리하는 중...',
                    '잠시만 기다려 주세요...',
                  ],
          ),
        ],
      ),
    );
  }

  String get _selectedLabel => _folders.firstWhere((f) => f.$1 == _selected).$2;

  Widget _empty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.folder_open,
          size: 56,
          color: AppColors.textGray.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 10),
        Text(
          '$_selectedLabel 폴더가 비어 있습니다',
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
        const SizedBox(height: 4),
        const Text(
          '아래 파일 첨부 버튼으로 자료를 올려주세요',
          style: TextStyle(color: AppColors.textGray, fontSize: 11.5),
        ),
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
        title: Text(
          name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          _sizeText(size),
          style: const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download, size: 20),
          onPressed: () {
            final nas = context.read<NasApi>();
            final url = nas.fileDownloadUrl(_selected, name);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: SelectableText(
                  url,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
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
      // (요구#2) 인가자명단(주소록) 엑셀이면 → 회원정보 업데이트 제안.
      final low = f.name.toLowerCase();
      final isExcel =
          low.endsWith('.xls') || low.endsWith('.xlsx') || low.endsWith('.csv');
      if (_selected == 'member_list' && isExcel) {
        await _offerAddressbookSync(f.name, bytes);
      }
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

  /// (요구#2) 이미 보관 중인 주소록 파일을 골라 회원정보에 반영.
  Future<void> _syncAddressbookFromPicker() async {
    final res = await pickDataFiles(allowedExtensions: ['xls', 'xlsx', 'csv']);
    if (res.isEmpty) return;
    final f = res.first;
    if (f.bytes.isEmpty) return;
    await _offerAddressbookSync(f.name, f.bytes);
  }

  /// (요구#2) 회원정보 업데이트 — 명단 주소록(엑셀)을 회원정보에 반영.
  ///
  ///  · 먼저 **미리보기(dry)** 로 매칭/갱신 예정 건수를 계산해 보여주고,
  ///  · 관리자가 승인하면 **비파괴(빈 칸만 채우기)** 로 반영한다.
  ///    (기존에 입력된 값은 절대 덮어쓰지 않는다)
  Future<void> _offerAddressbookSync(String filename, List<int> bytes) async {
    final nas = context.read<NasApi>();
    try {
      final prev = await nas.mergeAddressbook(filename, bytes, dry: true);
      if (!mounted) return;
      final matched = (prev['matched'] as num?)?.toInt() ?? 0;
      final upd = (prev['updated'] as num?)?.toInt() ?? 0;
      final filled = prev['filled'];
      if (upd == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('반영할 새 정보가 없습니다(이미 최신 상태).')),
        );
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('회원정보 업데이트'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('주소록에서 $matched명을 확인했고,\n$upd명의 정보를 채울 수 있습니다.'),
                const SizedBox(height: 8),
                if (filled is Map)
                  Text(
                    '· 주소 ${filled['address'] ?? 0} · 연락처 ${filled['phone'] ?? 0}\n'
                    '· 이메일 ${filled['email'] ?? 0} · 생일 ${filled['birthday'] ?? 0}\n'
                    '· 소속대 ${filled['unit'] ?? 0} · 연맹 ${filled['league'] ?? 0}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textGray,
                    ),
                  ),
                const SizedBox(height: 10),
                const Text(
                  '기존에 입력된 값은 그대로 두고 비어 있는 항목만 채웁니다.',
                  style: TextStyle(fontSize: 12, color: AppColors.textGray),
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
              child: const Text('업데이트'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      setState(() => _busy = true);
      final res = await nas.mergeAddressbook(filename, bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('회원정보 업데이트 완료 · ${res['updated'] ?? 0}명 갱신'),
          backgroundColor: AppColors.scoutGreen,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('업데이트 실패: $e'),
          backgroundColor: AppColors.taegeukRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
