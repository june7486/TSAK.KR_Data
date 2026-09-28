import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/import_parser.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/hscroll_menu.dart';
import '../widgets/member_avatar.dart';

/// 자료 가져오기 (AI 자동 인식)
/// PDF/엑셀/워드/텍스트/JPG/카메라 → 목록 자동 인식 → 승인/수정 → DB 저장
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  List<Member> _recognized = [];
  String _sourceName = '';
  bool _busy = false;
  final _pasteCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('자료 가져오기 (AI 인식)'),
        actions: const [AppHomeEmblem(size: 26)],
      ),
      body: Column(
        children: [
          _sourceBar(),
          if (_recognized.isNotEmpty) _recognizedHeader(),
          Expanded(
            child: _recognized.isEmpty ? _intro() : _list(),
          ),
          if (_recognized.isNotEmpty) _saveBar(),
        ],
      ),
    );
  }

  Widget _sourceBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: AppColors.purple.withValues(alpha: 0.05),
      child: HScrollMenu(
        height: 44,
        child: Row(
          children: [
            _srcBtn(Icons.folder_open, '파일 (엑셀/CSV/PDF/워드/JSON)', _pickFile),
            const SizedBox(width: 8),
            _srcBtn(Icons.photo_library, '이미지(JPG)', () => _pickImage(ImageSource.gallery)),
            const SizedBox(width: 8),
            _srcBtn(Icons.photo_camera, '카메라', () => _pickImage(ImageSource.camera)),
            const SizedBox(width: 8),
            _srcBtn(Icons.content_paste, '텍스트 붙여넣기', _pasteDialog),
          ],
        ),
      ),
    );
  }

  Widget _srcBtn(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _intro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome,
                size: 60, color: AppColors.purple.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            const Text(
              '자료를 불러오면 인가자 정보를 자동으로 인식합니다',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '엑셀·CSV·텍스트 등 표 형태 자료는 열/헤더를 자동 추론하여\n'
              '이름·인가번호·연맹·단위대 등을 인식합니다.\n'
              '이미지/PDF는 인식된 텍스트를 붙여넣어 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textGray),
            ),
            if (_busy) ...[
              const SizedBox(height: 18),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recognizedHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.scoutGreen, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '인식 결과 ${_recognized.length}건 · $_sourceName',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _recognized = [];
              _sourceName = '';
            }),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    return ListView.builder(
      itemCount: _recognized.length,
      itemBuilder: (c, i) {
        final m = _recognized[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: MemberAvatar(
              name: m.name,
              league: m.league,
              number: m.number,
              size: 34,
            ),
            title: Text('${m.number} ${m.name}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
              [
                if (m.league.isNotEmpty) m.league,
                if (m.unit.isNotEmpty) m.unit,
                if (m.phone.isNotEmpty) m.phone,
                if (m.atasNo.isNotEmpty) 'ATAS ${m.atasNo}',
              ].join(' · '),
              style: const TextStyle(fontSize: 11.5),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _editItem(i),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 18, color: AppColors.taegeukRed),
                  onPressed: () => setState(() => _recognized.removeAt(i)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _saveBar() {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '총 ${_recognized.length}건을 NAS DB에 추가합니다',
                  style: const TextStyle(fontSize: 12, color: AppColors.textGray),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.scoutGreen,
                ),
                onPressed: _busy ? null : _saveAll,
                icon: const Icon(Icons.save),
                label: const Text('승인 후 저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 파일/이미지 선택 ----------
  Future<void> _pickFile() async {
    try {
      final res = await pickDataFiles(
        allowedExtensions: ['xlsx', 'xls', 'csv', 'tsv', 'txt', 'json'],
      );
      if (res.isEmpty) return;
      final file = res.first;
      final bytes = file.bytes;
      if (bytes.isEmpty) return;
      setState(() {
        _busy = true;
        _sourceName = file.name;
      });
      final parsed = ImportParser.parse(file.name, bytes);
      if (mounted) {
        setState(() {
          _recognized = parsed;
          _busy = false;
        });
        if (parsed.isEmpty) _snack('인식된 항목이 없습니다. 텍스트 붙여넣기를 이용해 주세요.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('파일을 읽을 수 없습니다: $e');
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final x = await _picker.pickImage(source: source, maxWidth: 1600);
      if (x == null) return;
      await x.readAsBytes(); // 존재 확인
      if (mounted) {
        setState(() => _sourceName = x.name);
      }
      // 이미지에서는 표 형태 직접 파싱이 불가하므로 텍스트 붙여넣기 안내
      _snack('이미지를 불러왔습니다. 인식된 텍스트를 붙여넣어 주세요.');
      _pasteDialog();
    } catch (e) {
      if (mounted) _snack('이미지를 불러올 수 없습니다: $e');
    }
  }

  void _pasteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('텍스트 붙여넣기로 인식'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: _pasteCtrl,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '예)\n2186\t홍길동\t제주\t제405단\n'
                  '2187, 김철수, 광주, 제101단',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _parsePasted();
            },
            child: const Text('인식'),
          ),
        ],
      ),
    );
  }

  void _parsePasted() {
    final text = _pasteCtrl.text.trim();
    if (text.isEmpty) return;
    final bytes = Uint8List.fromList(text.codeUnits);
    final parsed = ImportParser.parse('pasted.txt', bytes);
    setState(() {
      _recognized = parsed;
      _sourceName = '붙여넣기';
    });
    if (parsed.isEmpty) _snack('인식된 항목이 없습니다.');
  }

  void _editItem(int index) {
    final m = _recognized[index];
    final ctrls = {
      'number': TextEditingController(text: m.number),
      'name': TextEditingController(text: m.name),
      'league': TextEditingController(text: m.league),
      'unit': TextEditingController(text: m.unit),
      'phone': TextEditingController(text: m.phone),
      'atasNo': TextEditingController(text: m.atasNo),
    };
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('항목 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ctrls.entries
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: TextField(
                        controller: e.value,
                        decoration: InputDecoration(labelText: e.key),
                      ),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              setState(() {
                _recognized[index] = m.copyWith(
                  number: ctrls['number']!.text.trim(),
                  name: ctrls['name']!.text.trim(),
                  league: ctrls['league']!.text.trim(),
                  unit: ctrls['unit']!.text.trim(),
                  phone: ctrls['phone']!.text.trim(),
                  atasNo: ctrls['atasNo']!.text.trim(),
                );
              });
              Navigator.pop(ctx);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAll() async {
    setState(() => _busy = true);
    final state = context.read<AppState>();
    var added = 0;
    for (final m in _recognized) {
      // 인가번호 중복 시 새 번호 부여
      var member = m;
      if (member.number.trim().isEmpty ||
          state.byNumber(member.number) != null) {
        final next = await state.nextNumber();
        member = member.copyWith(number: '$next');
      }
      await state.save(member);
      added++;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _recognized = [];
      });
      _snack('$added건을 저장했습니다 (NAS 동기화)');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
