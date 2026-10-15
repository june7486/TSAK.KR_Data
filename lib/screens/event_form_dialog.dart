import 'package:flutter/material.dart';

import '../services/file_pick.dart';
import '../theme/app_theme.dart';

/// 행사 생성/수정 폼 다이얼로그의 결과.
///
/// [mode] = create 이면 [year]/[title] 이 필수값, edit 이면 기존 값을 수정한다.
class EventFormResult {
  EventFormResult({
    required this.year,
    required this.title,
    required this.period,
    required this.place,
    required this.desc,
    required this.startDate,
    required this.endDate,
    required this.contacts,
    required this.newFiles,
    required this.deletedDist,
  });

  final String year;
  final String title;
  final String period;
  final String place;
  final String desc;

  /// 구조화된 시작일/종료일 (YYYY-MM-DD). 없으면 ''.
  final String startDate;
  final String endDate;

  /// 담당자 연락처(복수) — [{name, phone}].
  final List<Map<String, String>> contacts;

  /// 새로 첨부할 파일(복수) — '참가신청시 배포용' 폴더로 업로드.
  final List<PickedFileData> newFiles;

  /// 삭제할 기존 배포용 파일 이름 목록.
  final List<String> deletedDist;
}

/// 행사 생성/수정 공용 다이얼로그.
///
/// [요구] 행사를 수정하면 입력했던 내용을 모두 수정할 수 있고,
///   기간은 시작일·종료일을 달력에서 선택하며,
///   담당자 연락처(복수)와 첨부파일(복수 → '참가신청시 배포용')을 관리한다.
class EventFormDialog extends StatefulWidget {
  const EventFormDialog({
    super.key,
    required this.createMode,
    this.initialYear = '',
    this.initialTitle = '',
    this.initialPeriod = '',
    this.initialPlace = '',
    this.initialDesc = '',
    this.initialStart = '',
    this.initialEnd = '',
    this.initialContacts = const [],
    this.initialDist = const [],
  });

  final bool createMode;
  final String initialYear;
  final String initialTitle;
  final String initialPeriod;
  final String initialPlace;
  final String initialDesc;
  final String initialStart;
  final String initialEnd;
  final List<Map<String, dynamic>> initialContacts;

  /// 기존 배포용 자료 [{name, size, ext}].
  final List<Map<String, dynamic>> initialDist;

  @override
  State<EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends State<EventFormDialog> {
  late final TextEditingController _year;
  late final TextEditingController _title;
  late final TextEditingController _place;
  late final TextEditingController _desc;

  DateTime? _start;
  DateTime? _end;

  /// 담당자 행(이름/전화) — 복수 입력.
  final List<_ContactRow> _contacts = [];

  /// 새로 첨부할 파일(복수).
  final List<PickedFileData> _newFiles = [];

  /// 삭제 예정 기존 배포용 파일 이름.
  final Set<String> _deleted = {};

  late final List<Map<String, dynamic>> _dist;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().year;
    _year = TextEditingController(
      text: widget.initialYear.isNotEmpty ? widget.initialYear : '$now',
    );
    _title = TextEditingController(text: widget.initialTitle);
    _place = TextEditingController(text: widget.initialPlace);
    _desc = TextEditingController(text: widget.initialDesc);
    _start = _parseDate(widget.initialStart) ?? _parsePeriodStart(widget.initialPeriod);
    _end = _parseDate(widget.initialEnd) ?? _parsePeriodEnd(widget.initialPeriod);
    for (final c in widget.initialContacts) {
      final nm = '${c['name'] ?? ''}';
      final ph = '${c['phone'] ?? ''}';
      if (nm.isNotEmpty || ph.isNotEmpty) {
        _contacts.add(_ContactRow(nm, ph));
      }
    }
    if (_contacts.isEmpty) _contacts.add(_ContactRow('', ''));
    _dist = List<Map<String, dynamic>>.from(widget.initialDist);
  }

  @override
  void dispose() {
    _year.dispose();
    _title.dispose();
    _place.dispose();
    _desc.dispose();
    for (final c in _contacts) {
      c.dispose();
    }
    super.dispose();
  }

  static DateTime? _parseDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(t);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  /// 기간 문자열(예: '2026.03.14~15', '2026.03.14~2026.03.15')에서 시작일 추정.
  static DateTime? _parsePeriodStart(String s) {
    final m = RegExp(r'(\d{4})\.(\d{1,2})\.(\d{1,2})').firstMatch(s);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  static DateTime? _parsePeriodEnd(String s) {
    final start = _parsePeriodStart(s);
    if (start == null) return null;
    // '~15' / '~03.15' / '~2026.03.15' 형태의 종료부.
    final m = RegExp(r'~\s*(\d{4}\.)?(\d{1,2})\.(\d{1,2})').firstMatch(s);
    if (m != null && m.group(2) != null && m.group(3) != null) {
      final y = m.group(1) != null
          ? int.parse(m.group(1)!.replaceAll('.', ''))
          : start.year;
      return DateTime(y, int.parse(m.group(2)!), int.parse(m.group(3)!));
    }
    // '~15' — 시작일과 같은 달의 일자만.
    final m2 = RegExp(r'~\s*(\d{1,2})\s*$').firstMatch(s);
    if (m2 != null) {
      return DateTime(start.year, start.month, int.parse(m2.group(1)!));
    }
    return start;
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 표시용 기간 문자열 조합.
  String get _periodText {
    if (_start == null && _end == null) return '';
    final s = _start ?? _end!;
    final e = _end ?? _start!;
    if (s.year == e.year && s.month == e.month && s.day == e.day) {
      return '${s.year}.${s.month.toString().padLeft(2, '0')}.'
          '${s.day.toString().padLeft(2, '0')}';
    }
    if (s.year == e.year && s.month == e.month) {
      return '${s.year}.${s.month.toString().padLeft(2, '0')}.'
          '${s.day.toString().padLeft(2, '0')}~${e.day.toString().padLeft(2, '0')}';
    }
    return '${s.year}.${s.month.toString().padLeft(2, '0')}.'
        '${s.day.toString().padLeft(2, '0')}~'
        '${e.year}.${e.month.toString().padLeft(2, '0')}.'
        '${e.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final base = isStart ? (_start ?? now) : (_end ?? _start ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(1980),
      lastDate: DateTime(now.year + 8),
      helpText: isStart ? '시작일 선택' : '종료일 선택',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start != null && _start!.isAfter(picked)) _start = picked;
      }
    });
  }

  Future<void> _pickFiles() async {
    final picked = await pickDataFiles(
      allowMultiple: true,
      dialogTitle: '배포용 자료 선택 (복수 선택 가능)',
    );
    if (picked.isEmpty) return;
    setState(() => _newFiles.addAll(picked));
  }

  bool get _yearOk => RegExp(r'^\d{4}$').hasMatch(_year.text.trim());
  bool get _canSave => _yearOk && _title.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.createMode ? '새 행사 만들기' : '행사 수정'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- 연도 ----
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: '연도 * (필수)',
                      counterText: '',
                      errorText:
                          _year.text.trim().isEmpty || _yearOk
                              ? null
                              : '4자리 연도를 입력하세요',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final now = DateTime.now().year;
                    final picked = await showDialog<int>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('연도 선택'),
                        content: SizedBox(
                          width: 300,
                          height: 300,
                          child: YearPicker(
                            firstDate: DateTime(1980),
                            lastDate: DateTime(now + 8),
                            selectedDate: DateTime(
                              int.tryParse(_year.text.trim()) ?? now,
                            ),
                            onChanged: (d) => Navigator.pop(context, d.year),
                          ),
                        ),
                      ),
                    );
                    if (picked != null) {
                      _year.text = '$picked';
                      setState(() {});
                    }
                  },
                  child: const Text('선택'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ---- 행사명 ----
            TextField(
              controller: _title,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: '행사명 *'),
            ),
            const SizedBox(height: 10),
            // ---- 기간 (시작일 / 종료일) ----
            const Text(
              '행사기간',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 17),
                    label: Text(
                      _start == null ? '시작일 선택' : _fmt(_start!),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    onPressed: () => _pickDate(isStart: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('~'),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_available, size: 17),
                    label: Text(
                      _end == null ? '종료일 선택' : _fmt(_end!),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    onPressed: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            if (_periodText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5, left: 2),
                child: Text(
                  '표시: $_periodText',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGray,
                  ),
                ),
              ),
            // 종료일이 있으면 시작일도 함께 초기화할 수 있게 안내.
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  _start = null;
                  _end = null;
                }),
                child: const Text('기간 지우기', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(height: 4),
            // ---- 장소 ----
            TextField(
              controller: _place,
              decoration: const InputDecoration(labelText: '장소'),
            ),
            const SizedBox(height: 10),
            // ---- 소개/개요 ----
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '행사 소개/개요',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            // ---- 담당자 연락처 (복수) ----
            Row(
              children: [
                const Icon(Icons.headset_mic, size: 17, color: AppColors.purple),
                const SizedBox(width: 6),
                const Text(
                  '행사 담당자 (문의하기 · 복수 가능)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '담당자 추가',
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () =>
                      setState(() => _contacts.add(_ContactRow('', ''))),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (_contacts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 2, bottom: 4),
                child: Text(
                  '(선택) 담당자 번호를 입력하면 참가신청 페이지에 문의 버튼이 나타납니다.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
                ),
              ),
            for (var i = 0; i < _contacts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: TextField(
                        controller: _contacts[i].name,
                        decoration: const InputDecoration(
                          labelText: '이름',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _contacts[i].phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: '전화번호',
                          isDense: true,
                          hintText: '010-0000-0000',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '삭제',
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        size: 20,
                        color: AppColors.taegeukRed,
                      ),
                      onPressed: () => setState(() {
                        _contacts.removeAt(i).dispose();
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            // ---- 첨부파일 → '참가신청시 배포용' (복수) ----
            Row(
              children: [
                const Icon(Icons.attach_file, size: 17, color: AppColors.scoutGreen),
                const SizedBox(width: 6),
                const Text(
                  '참가신청시 배포용 자료 (복수 가능)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('파일 추가', style: TextStyle(fontSize: 12)),
                  onPressed: _pickFiles,
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '여기에 올린 파일은 참가신청 페이지에서 바로 내려받을 수 있습니다.\n'
                "저장 위치: 기획서 폴더 › '참가신청시 배포용'",
                style: TextStyle(fontSize: 11, color: AppColors.textGray, height: 1.5),
              ),
            ),
            // 기존 배포용 파일 (삭제 가능)
            for (final d in _dist)
              if (!_deleted.contains('${d['name']}'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.scoutGreen.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: AppColors.scoutGreen.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.description,
                          size: 16,
                          color: AppColors.scoutGreen,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '${d['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        Text(
                          _fmtSize((d['size'] as num?)?.toInt() ?? 0),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textGray,
                          ),
                        ),
                        IconButton(
                          tooltip: '삭제',
                          icon: const Icon(
                            Icons.close,
                            size: 17,
                            color: AppColors.taegeukRed,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setState(() => _deleted.add('${d['name']}')),
                        ),
                      ],
                    ),
                  ),
                ),
            // 새로 추가한 파일
            for (var i = 0; i < _newFiles.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: AppColors.purple.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.upload_file, size: 16, color: AppColors.purple),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${_newFiles[i].name}  (신규)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      Text(
                        _fmtSize(_newFiles[i].bytes.length),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textGray,
                        ),
                      ),
                      IconButton(
                        tooltip: '빼기',
                        icon: const Icon(
                          Icons.close,
                          size: 17,
                          color: AppColors.taegeukRed,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _newFiles.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
          onPressed: _canSave
              ? () {
                  final contacts = <Map<String, String>>[];
                  for (final c in _contacts) {
                    final nm = c.name.text.trim();
                    final ph =
                        c.phone.text.replaceAll(RegExp(r'[^0-9]'), '');
                    if (ph.isNotEmpty) {
                      contacts.add({'name': nm, 'phone': ph});
                    }
                  }
                  Navigator.pop(
                    context,
                    EventFormResult(
                      year: _year.text.trim(),
                      title: _title.text.trim(),
                      period: _periodText,
                      place: _place.text.trim(),
                      desc: _desc.text.trim(),
                      startDate: _start == null ? '' : _fmt(_start!),
                      endDate: _end == null ? '' : _fmt(_end!),
                      contacts: contacts,
                      newFiles: _newFiles,
                      deletedDist: _deleted.toList(),
                    ),
                  );
                }
              : null,
          child: Text(widget.createMode ? '생성' : '저장'),
        ),
      ],
    );
  }

  static String _fmtSize(int n) {
    if (n < 1024) return '$n B';
    if (n < 1048576) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1048576).toStringAsFixed(1)} MB';
  }
}

class _ContactRow {
  _ContactRow(String name, String phone)
      : name = TextEditingController(text: name),
        phone = TextEditingController(text: phone);

  final TextEditingController name;
  final TextEditingController phone;

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}
