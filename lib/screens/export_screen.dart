import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member.dart';
import '../services/contact_service.dart';
import '../services/export_service.dart';
import '../services/file_save.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';
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
      appBar: TsakAppBar(
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
      body: Stack(
        children: [
          TabBarView(
            controller: _tab,
            children: [_exportTab(), _smsTab(), _mailTab()],
          ),
          // 출력/내보내기 대기 — 멈춘 것이 아님을 안내(공통 작업중 오버레이).
          BusyOverlay(
            visible: _busy,
            title: '출력물을 만드는 중입니다',
            lines: const [
              '선택한 인가자 정보로 문서를 생성하고 있습니다...',
              '파일로 저장하는 중입니다...',
              '잠시만 기다려 주세요...',
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- 내보내기 ----------------
  Widget _exportTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        _summaryRow(),
        const SizedBox(height: 18),
        _sectionTitle('출력 형식'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: ExportFormat.values.map((f) {
            return _chip(f.label, _format == f, () {
              setState(() => _format = f);
            });
          }).toList(),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _sectionTitle('출력할 항목'),
            const Spacer(),
            Text(
              '${_selectedFields.length}/${kExportFields.length}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textGray,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '선택한 항목만 명단(모든 형식)에 포함됩니다.',
          style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _miniTextButton(
              '전체',
              () => setState(
                () => _selectedFields.addAll(kExportFields.map((e) => e.key)),
              ),
            ),
            _miniTextButton(
              '기본값',
              () => setState(() => _selectedFields.addAll(kDefaultFieldKeys)),
            ),
            _miniTextButton(
              '해제',
              () => setState(() => _selectedFields.clear()),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _fieldGroups(),
        const SizedBox(height: 20),
        _chunkSwitch(),
        const SizedBox(height: 18),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.purple,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: _busy ? null : _doExport,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download, size: 19),
          label: Text(
            _busy ? '생성 중...' : '내보내기 실행',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (_format == ExportFormat.pdf) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _busy ? null : _previewPdf,
            icon: const Icon(Icons.print, size: 18),
            label: const Text('PDF 미리보기 / 인쇄'),
          ),
        ],
        const SizedBox(height: 26),
        _sectionTitle('미리보기 (상위 30명)'),
        const SizedBox(height: 8),
        ...widget.members.take(30).map((m) => MemberCard(member: m)),
        if (widget.members.length > 30)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '외 ${widget.members.length - 30}명...',
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// 최소한의 선택 칩 — 선택 시 보라 채움, 미선택 시 흰 배경 + 얇은 테두리.
  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.purple
                : AppColors.purple.withValues(alpha: 0.22),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textDark,
          ),
        ),
      ),
    );
  }

  Widget _miniTextButton(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          foregroundColor: AppColors.purple,
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      color: AppColors.textGray,
      letterSpacing: 0.2,
    ),
  );

  /// 항목을 그룹별로 나누어 간결하게 표시.
  Widget _fieldGroups() {
    const order = ['기본', '연락', '주소', '자격', '회비', '기타'];
    final groups = <String, List<ExportField>>{};
    for (final f in kExportFields) {
      groups.putIfAbsent(f.group, () => []).add(f);
    }
    final keys = order.where(groups.containsKey).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in keys) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 5),
            child: Text(
              g,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.purple,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in groups[g]!)
                _chip(
                  f.label,
                  _selectedFields.contains(f.key),
                  () => setState(() {
                    if (_selectedFields.contains(f.key)) {
                      _selectedFields.remove(f.key);
                    } else {
                      _selectedFields.add(f.key);
                    }
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// 선택 인원 요약 — 그라데이션 배너 대신 한 줄 요약.
  Widget _summaryRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.checklist, color: AppColors.purple, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '선택된 인가자 ${widget.members.length}명',
              style: const TextStyle(
                color: AppColors.purpleDark,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          if (_chunk100)
            Text(
              '${_chunks.length}개 파일',
              style: const TextStyle(
                color: AppColors.purple,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chunkSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: SwitchListTile(
        value: _chunk100,
        activeThumbColor: AppColors.purple,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: const Text(
          '100명 단위로 분할 출력',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        subtitle: Text(
          _chunk100 ? '${_chunks.length}개 파일로 나누어 저장합니다' : '하나의 파일로 저장합니다',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
        ),
        onChanged: (v) => setState(() => _chunk100 = v),
      ),
    );
  }

  Future<void> _doExport() async {
    if (widget.members.isEmpty) {
      _snack('선택된 인가자가 없습니다');
      return;
    }
    // ① 저장 방법·위치 선택 창 (PC·모든 모바일 공통)
    final choice = await _askSaveMethod();
    if (choice == null) return; // 취소
    final choose = choice == 'choose';

    setState(() => _busy = true);
    try {
      final chunks = _chunks;
      final fields = _fieldKeys.isEmpty ? kDefaultFieldKeys : _fieldKeys;
      final baseName = _baseName();
      var saved = 0;
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
          // JPG — 첫 페이지를 이미지로 변환해 저장.
          final raster = await Printing.raster(bytes, dpi: 150).first;
          final im = img.Image.fromBytes(
            width: raster.width,
            height: raster.height,
            bytes: raster.pixels.buffer,
            numChannels: 4,
          );
          final jpg = img.encodeJpg(im, quality: 88);
          final ok = await saveBytesChoose(
            bytes: jpg,
            name: name,
            ext: 'jpg',
            mime: 'image/jpeg',
            mimeType: MimeType.jpeg,
            choose: choose,
          );
          if (ok) saved++;
        } else {
          final ok = await saveBytesChoose(
            bytes: bytes,
            name: name,
            ext: _format.extension,
            mime: _mimeStr(_format),
            mimeType: _mimeOf(_format),
            choose: choose,
          );
          if (ok) saved++;
        }
      }
      if (saved == 0) {
        _snack('저장이 취소되었습니다');
      } else {
        _snack('내보내기 완료 ($saved개 파일 · ${_format.label})');
      }
    } catch (e) {
      _snack('내보내기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 파일명 기본값 — 제목에 숫자가 많으면(특정월 명단 등) 시각 대신 제목 사용.
  String _baseName() {
    final t = widget.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final base = t.isEmpty ? 'TSAK_인가자명단' : 'TSAK_$t';
    return '${base}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// ② 저장 방법·위치 선택 창.
  ///
  /// 반환: 'default'(기본 폴더) | 'choose'(위치 직접 선택) | null(취소).
  ///  · PC(크롬·엣지·웨일): [위치 선택] → 저장 폴더·파일명 지정.
  ///  · 안드로이드·아이폰: [위치 선택] → 시스템 저장 대화상자(파일 앱·드라이브).
  Future<String?> _askSaveMethod() {
    final canPick = supportsLocationPicker; // 모바일이면 항상 true
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.save_alt, color: AppColors.purple, size: 30),
        title: const Text('저장 방법 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_format.label} · ${widget.members.length}명'
              '${_chunk100 ? ' · ${_chunks.length}개 파일' : ''}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '저장 위치를 직접 고르거나, 기기 기본 폴더에 바로 저장할 수 있습니다.',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              canPick
                  ? '* [위치 직접 선택] 을 누르면 저장 위치·앱을 고를 수 있습니다.\n'
                        '  · PC: 폴더·파일명 지정\n'
                        '  · 안드로이드·아이폰: 파일 앱·드라이브 등 선택\n'
                        '* [기본 폴더에 저장] 은 다운로드(Downloads) 폴더에 바로 저장합니다.'
                  : '* 이 브라우저는 위치 선택을 지원하지 않아\n'
                        '  다운로드(Downloads) 폴더에 저장됩니다.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('취소'),
          ),
          if (canPick)
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'choose'),
              icon: const Icon(Icons.folder_open, size: 17),
              label: const Text('위치 직접 선택'),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
            onPressed: () => Navigator.pop(ctx, 'default'),
            icon: const Icon(Icons.download, size: 17),
            label: const Text('기본 폴더에 저장'),
          ),
        ],
      ),
    );
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
        _summaryRow(),
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
        _summaryRow(),
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
