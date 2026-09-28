import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member.dart';
import '../services/contact_service.dart';
import '../services/export_service.dart';
import '../services/file_save.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/hscroll_menu.dart';
import '../widgets/member_card.dart';

/// 명단 내보내기 + 단체 문자/메일 화면
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.members, required this.title});

  final List<Member> members;
  final String title;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _chunk100 = false;
  bool _busy = false;
  ExportFormat _format = ExportFormat.excel;

  /// 선택된 개인정보 항목 (기본: 전체)
  final Set<String> _selectedFields = {...kDefaultFieldKeys};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  List<String> get _fieldKeys {
    // kExportFields 순서를 유지하며 선택된 항목만
    return kExportFields
        .map((f) => f.key)
        .where(_selectedFields.contains)
        .toList();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  List<List<Member>> get _chunks {
    if (!_chunk100) return [widget.members];
    final out = <List<Member>>[];
    for (var i = 0; i < widget.members.length; i += 100) {
      out.add(
        widget.members.sublist(
          i,
          (i + 100 > widget.members.length) ? widget.members.length : i + 100,
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: const [AppHomeEmblem(size: 24)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: HsTabStrip(
            controller: _tab,
            labels: const ['파일 내보내기', '문자 발송', '메일 발송'],
            icons: const [Icons.file_download, Icons.sms, Icons.email],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_exportTab(), _smsTab(), _mailTab()],
      ),
    );
  }

  // ---------------- 내보내기 ----------------
  Widget _exportTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _countBanner(),
        const SizedBox(height: 12),
        const Text(
          '출력 형식 선택',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ExportFormat.values.map((f) {
            final sel = _format == f;
            return ChoiceChip(
              label: Text(f.label),
              selected: sel,
              selectedColor: AppColors.purple,
              labelStyle: TextStyle(
                color: sel ? Colors.white : AppColors.textDark,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (_) => setState(() => _format = f),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        _fieldSelector(),
        const SizedBox(height: 14),
        Card(
          child: SwitchListTile(
            value: _chunk100,
            activeThumbColor: AppColors.purple,
            title: const Text(
              '100명 단위로 분할 출력',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _chunk100 ? '${_chunks.length}개 파일로 나누어 저장합니다' : '하나의 파일로 저장합니다',
            ),
            onChanged: (v) => setState(() => _chunk100 = v),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.purple,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _busy ? null : _doExport,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download),
          label: Text(_busy ? '생성 중...' : '내보내기 실행'),
        ),
        const SizedBox(height: 10),
        if (_format == ExportFormat.pdf)
          OutlinedButton.icon(
            onPressed: _busy ? null : _previewPdf,
            icon: const Icon(Icons.print),
            label: const Text('PDF 미리보기 / 인쇄'),
          ),
        const SizedBox(height: 20),
        const Text(
          '미리보기 (상위 30명)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 6),
        ...widget.members.take(30).map((m) => MemberCard(member: m)),
        if (widget.members.length > 30)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '외 ${widget.members.length - 30}명...',
              style: const TextStyle(color: AppColors.textGray),
            ),
          ),
      ],
    );
  }

  /// 개인정보 출력 항목 선택 UI (명단에 넣을 항목을 골라서 출력)
  Widget _fieldSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist, color: AppColors.purple, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '출력할 개인정보 항목',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const Spacer(),
                Text(
                  '${_selectedFields.length}/${kExportFields.length}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGray,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '선택한 항목만 명단(모든 형식)에 포함됩니다.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in kExportFields)
                  FilterChip(
                    label: Text(f.label),
                    selected: _selectedFields.contains(f.key),
                    selectedColor: AppColors.purple,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: _selectedFields.contains(f.key)
                          ? Colors.white
                          : AppColors.textDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedFields.add(f.key);
                      } else {
                        _selectedFields.remove(f.key);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(
                      () => _selectedFields.addAll(kExportFields.map((e) => e.key))),
                  child: const Text('전체 선택'),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _selectedFields.addAll(kDefaultFieldKeys)),
                  child: const Text('기본값'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _countBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.purple, AppColors.purpleLight],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.checklist, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '선택된 인가자 ${widget.members.length}명',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          if (_chunk100)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_chunks.length}개 파일',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _doExport() async {
    if (widget.members.isEmpty) {
      _snack('선택된 인가자가 없습니다');
      return;
    }
    setState(() => _busy = true);
    try {
      final chunks = _chunks;
      final fields = _fieldKeys.isEmpty ? kDefaultFieldKeys : _fieldKeys;
      final baseName = 'TSAK_인가자명단_${DateTime.now().millisecondsSinceEpoch}';
      for (var i = 0; i < chunks.length; i++) {
        final list = chunks[i];
        final suffix = chunks.length > 1 ? '_${i + 1}' : '';
        final name = '$baseName$suffix';
        Uint8List bytes;
        switch (_format) {
          case ExportFormat.excel:
            bytes = ExportService.buildExcel(list, fieldKeys: fields);
            break;
          case ExportFormat.pdf:
            bytes = await ExportService.buildPdf(list, fieldKeys: fields);
            break;
          case ExportFormat.word:
            bytes = ExportService.buildWord(list, fieldKeys: fields);
            break;
          case ExportFormat.txt:
            bytes = ExportService.buildTxt(list, fieldKeys: fields);
            break;
          case ExportFormat.ppt:
            bytes = ExportService.buildPpt(list, fieldKeys: fields);
            break;
          case ExportFormat.jpg:
            bytes = await ExportService.buildPdf(list, fieldKeys: fields);
            break;
        }
        if (_format == ExportFormat.jpg) {
          // JPG는 첫 페이지를 이미지로 저장
          final img = await Printing.raster(bytes, dpi: 150).first;
          final png = await img.toPng();
          await saveBytes(
            bytes: png,
            name: name,
            ext: 'png',
            mime: 'image/png',
            mimeType: MimeType.png,
          );
        } else {
          await saveBytes(
            bytes: bytes,
            name: name,
            ext: _format.extension,
            mime: _mimeStr(_format),
            mimeType: _mimeOf(_format),
          );
        }
      }
      _snack('내보내기 완료 (${chunks.length}개 파일)');
    } catch (e) {
      _snack('내보내기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  MimeType _mimeOf(ExportFormat f) {
    switch (f) {
      case ExportFormat.excel:
        return MimeType.microsoftExcel;
      case ExportFormat.pdf:
        return MimeType.pdf;
      case ExportFormat.word:
        return MimeType.microsoftWord;
      case ExportFormat.txt:
        return MimeType.text;
      case ExportFormat.jpg:
        return MimeType.jpeg;
      case ExportFormat.ppt:
        return MimeType.microsoftPresentation;
    }
  }

  /// 웹 다운로드용 MIME 문자열.
  String _mimeStr(ExportFormat f) {
    switch (f) {
      case ExportFormat.excel:
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case ExportFormat.pdf:
        return 'application/pdf';
      case ExportFormat.word:
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case ExportFormat.txt:
        return 'text/plain;charset=utf-8';
      case ExportFormat.jpg:
        return 'image/jpeg';
      case ExportFormat.ppt:
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
  }

  Future<void> _previewPdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await ExportService.buildPdf(widget.members);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      _snack('미리보기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- 문자 ----------------
  Widget _smsTab() {
    final phones = ContactService.phones(widget.members);
    final ctrl = TextEditingController();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _countBanner(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '문자 내용',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: '발송할 문자 내용을 입력하세요',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.taegeukBlue,
                        ),
                        onPressed: () => _openSms(ctrl.text),
                        icon: const Icon(Icons.sms),
                        label: const Text('문자 앱 열기'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '* 대량 문자는 통신사 정책상 시스템 문자 앱에서 다수 수신자로 열립니다. 필요 시 명단을 복사해 문자 대량발송 서비스에 붙여넣으세요.',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _recipientList(
          title: '수신 번호 (${phones.length}개)',
          items: phones,
          copyText: ContactService.phoneList(widget.members),
        ),
      ],
    );
  }

  Future<void> _openSms(String body) async {
    final uri = Uri.parse(ContactService.smsUri(widget.members, body: body));
    await _launch(uri, '문자 앱');
  }

  Future<void> _launch(Uri uri, String appName) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        _snack('$appName을(를) 열 수 없습니다');
      }
    } catch (e) {
      if (mounted) _snack('$appName 실행 실패: $e');
    }
  }

  // ---------------- 메일 ----------------
  Widget _mailTab() {
    final emails = ContactService.emails(widget.members);
    final subjectCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _countBanner(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '메일 작성',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(hintText: '제목'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: '본문 내용'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.taegeukRed,
                  ),
                  onPressed: () => _openMail(subjectCtrl.text, bodyCtrl.text),
                  icon: const Icon(Icons.email),
                  label: const Text('메일 앱 열기'),
                ),
                const SizedBox(height: 8),
                const Text(
                  '* 기본 메일 앱이 열리고 수신자(BCC)가 자동 입력됩니다. 대량 발송은 메일 서비스(Gmail 등)에서 진행하세요.',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _recipientList(
          title: '수신 이메일 (${emails.length}개)',
          items: emails,
          copyText: ContactService.emailList(widget.members),
        ),
      ],
    );
  }

  Future<void> _openMail(String subject, String body) async {
    var uri = Uri.parse(
      ContactService.mailtoUri(widget.members, subject: subject, body: body),
    );
    // BCC 방식 폴백 (URL 길이 초과 대비)
    if (uri.toString().length > 1800) {
      uri = Uri.parse(
        'mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
      );
    }
    await _launch(uri, '메일 앱');
  }

  Widget _recipientList({
    required String title,
    required List<String> items,
    required String copyText,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: '전체 복사',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: copyText));
                    _snack('복사되었습니다 (${items.length}개)');
                  },
                ),
              ],
            ),
            const Divider(),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '수신자 정보가 없습니다',
                  style: TextStyle(color: AppColors.textGray),
                ),
              )
            else
              ...items
                  .take(100)
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(e, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
            if (items.length > 100)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '외 ${items.length - 100}개...',
                  style: const TextStyle(color: AppColors.textGray),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
