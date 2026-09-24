import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/finance_service.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';

/// 은행거래파일 → 자동 이름별 분류 → 검토 → 저장
class BankImportScreen extends StatefulWidget {
  const BankImportScreen({super.key});

  @override
  State<BankImportScreen> createState() => _BankImportScreenState();
}

class _BankImportScreenState extends State<BankImportScreen> {
  final List<ClassifiedRow> _rows = [];
  bool _busy = false;
  bool _usedServer = false;
  bool _usedOcr = false;
  String _fileName = '';

  @override
  Widget build(BuildContext context) {
    final matched = _rows.where((r) => r.matched).length;
    final total = _rows.fold<int>(0, (s, r) => s + r.amount);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('은행거래 자동분류'),
        titleSpacing: 0,
        actions: const [AppHomeEmblem(size: 24)],
      ),
      body: Column(
        children: [
          _infoCard(),
          if (_rows.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text('전체 ${_rows.length}건 · 매칭 $matched건',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: AppColors.textDark)),
                  const Spacer(),
                  Text('합계 ${_won(total)}원',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppColors.purple)),
                ],
              ),
            ),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? _empty()
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _rows.length,
                        itemBuilder: (_, i) => _rowTile(_rows[i], i),
                      ),
          ),
          if (_rows.isNotEmpty) _bottom(),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '은행에서 내려받은 거래내역(엑셀/CSV)뿐 아니라 '
              '거래내역 이미지·출력물(PNG/JPG/PDF)도 자동 인식(OCR)합니다.\n'
              '입금자 텍스트에서 이름 앞뒤 내용을 검색해 인가번호를 자동 기입하고, '
              '후원/수품/참가비/연회비/평생회비/행사 및 지출로 자동 분류합니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('거래파일/이미지 선택'),
                  ),
                ),
              ],
            ),
            if (_fileName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '파일: $_fileName'
                    '${_usedServer ? (_usedOcr ? ' · 서버 OCR 자동분류' : ' · 서버 자동분류') : ' · 로컬 자동분류'}',
                    style: const TextStyle(fontSize: 11, color: AppColors.purple)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance,
                size: 56, color: AppColors.textGray.withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            const Text('거래파일을 선택하면 자동분류 결과가 여기에 표시됩니다',
                style: TextStyle(color: AppColors.textGray, fontSize: 13)),
          ],
        ),
      );

  Widget _rowTile(ClassifiedRow r, int i) {
    final color = r.matched ? AppColors.scoutGreen : AppColors.taegeukRed;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 42,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(r.date,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textGray)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(r.matched ? '매칭' : '미매칭',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: color)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('원문: ${r.payer}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  if (r.number.isNotEmpty)
                    Text('→ ${r.matchedName} (#${r.number})',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.scoutGreen,
                            fontWeight: FontWeight.w700)),
                  if (r.context.isNotEmpty)
                    Text('인식: ${r.context}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.purple)),
                  Text('${r.category}${r.memo.isNotEmpty ? ' · ${r.memo}' : ''}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGray)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${_won(r.amount)}원',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13)),
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit, size: 16),
                      onPressed: () => _editRow(i),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _rows.removeAt(i)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottom() {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(_rows.clear),
                child: const Text('초기화'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.scoutGreen),
                  onPressed: _commit,
                  icon: const Icon(Icons.save, size: 18),
                  label: Text('DB에 저장 (${_rows.length}건)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final nas = context.read<NasApi>();
    final res = await pickDataFiles(
      allowedExtensions: [
        'xlsx', 'xls', 'csv', 'txt',
        'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'pdf',
      ],
    );
    if (res.isEmpty) return;
    final f = res.first;
    final bytes = f.bytes;
    if (bytes.isEmpty) return;
    if (!mounted) return;
    final low = f.name.toLowerCase();
    final isImageOrPdf = low.endsWith('.pdf') ||
        low.endsWith('.png') ||
        low.endsWith('.jpg') ||
        low.endsWith('.jpeg') ||
        low.endsWith('.webp') ||
        low.endsWith('.gif') ||
        low.endsWith('.bmp');
    setState(() {
      _busy = true;
      _fileName = f.name;
      _usedOcr = false;
    });

    // 1) 서버 자동분류(엑셀/CSV/이미지/PDF 모두 지원) 우선, 실패 시 로컬 엔진
    List<ClassifiedRow> rows = [];
    try {
      final j = await nas.parseBankFull(f.name, bytes);
      if (j['ok'] == true) {
        _usedServer = true;
        _usedOcr = '${j['engine']}' == 'ocr';
        rows = ((j['rows'] as List?) ?? [])
            .map((e) => ClassifiedRow.fromMap((e as Map).cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {
      rows = [];
    }
    // OCR/서버 실패 시에만 로컬 CSV 파서 (이미지/PDF는 로컬 파싱 불가)
    if (rows.isEmpty && !isImageOrPdf) {
      _usedServer = false;
      _usedOcr = false;
      rows = _localParse(f.name, bytes);
    }
    if (!mounted) return;
    setState(() {
      _rows
        ..clear()
        ..addAll(rows);
      _busy = false;
    });
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isImageOrPdf
              ? '이미지/PDF에서 거래내역을 인식하지 못했습니다. 선명한 원본을 사용해 주세요.'
              : '거래내역을 찾지 못했습니다. 파일 형식을 확인해 주세요.'),
          backgroundColor: AppColors.tigerGold,
        ),
      );
    }
  }

  /// 로컬 파서 (오프라인/간이 CSV)
  List<ClassifiedRow> _localParse(String name, List<int> bytes) {
    final fs = context.read<FinanceService>();
    final state = context.read<AppState>();
    final members = state.repo.all();
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty);
    final out = <ClassifiedRow>[];
    var first = true;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(RegExp(r'[,\t]')).map((e) => e.trim().replaceAll('"', '')).toList();
      if (first) {
        first = false;
        if (parts.any((p) => p.contains('입금') || p.contains('이름') || p.contains('금액'))) {
          continue; // header
        }
      }
      final raw = {
        'date': parts.isNotEmpty ? parts[0] : '',
        'payer': parts.length > 1 ? parts[1] : '',
        'amount': parts.length > 2 ? parts[2] : '',
        'memo': parts.length > 3 ? parts[3] : '',
      };
      out.add(fs.classify(raw, members: members));
    }
    return out;
  }

  void _editRow(int i) {
    final r = _rows[i];
    final nameCtrl = TextEditingController(text: r.matchedName);
    final catCtrl = TextEditingController(text: r.category);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('분류 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: '이름'),
              controller: nameCtrl,
            ),
            TextField(
              decoration: const InputDecoration(labelText: '분류'),
              controller: catCtrl,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                r.matchedName = nameCtrl.text;
                r.name = nameCtrl.text;
                r.category = catCtrl.text;
              });
              Navigator.pop(context);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _commit() async {
    final fs = context.read<FinanceService>();
    final added = fs.commitClassified(_rows);
    final ok = await fs.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '${added.length}건을 DB에 저장했습니다'
            : '${added.length}건 메모리 반영(서버 저장 실패 — 오프라인)'),
        backgroundColor: ok ? AppColors.scoutGreen : AppColors.tigerGold,
      ),
    );
    setState(() {
      _rows.clear();
      _fileName = '';
    });
  }

  static String _won(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
