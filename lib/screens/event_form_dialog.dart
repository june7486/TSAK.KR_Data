import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/file_pick.dart';
import '../services/nas_api.dart';
import '../services/web_nav.dart';
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
    this.lat = '',
    this.lng = '',
  });

  final String year;
  final String title;
  final String period;
  final String place;
  final String desc;

  /// 구조화된 시작일/종료일 (YYYY-MM-DD). 없으면 ''.
  final String startDate;
  final String endDate;

  /// (요구) 기획 시 지정한 지도 위치(좌표). 없으면 ''.
  final String lat;
  final String lng;

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
    this.initialLat = '',
    this.initialLng = '',
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

  /// (요구) 기획 시 지정한 지도 위치(좌표).
  final String initialLat;
  final String initialLng;

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

  /// (요구) 기획 시 지정한 지도 위치(좌표). 없으면 '' → 장소 검색으로 노출.
  String _lat = '';
  String _lng = '';
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().year;
    _year = TextEditingController(
      text: widget.initialYear.isNotEmpty ? widget.initialYear : '$now',
    );
    _title = TextEditingController(text: widget.initialTitle);
    _place = TextEditingController(text: widget.initialPlace);
    _lat = widget.initialLat;
    _lng = widget.initialLng;
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
            // ---- 장소 + 카카오지도 검색 ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _place,
                    decoration: const InputDecoration(labelText: '장소'),
                    onChanged: (_) => setState(() => _lat = _lng = ''),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: OutlinedButton.icon(
                    onPressed: _searchOnMap,
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('지도에서 검색', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            if (_lat.isNotEmpty && _lng.isNotEmpty) ...[
              const SizedBox(height: 6),
              _mapPreview(_lat, _lng),
            ],
            if (_lat.isNotEmpty && _lng.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE500).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.place, size: 16, color: Color(0xFF3C1E1E)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '지도 위치 지정됨 · $_lat, $_lng',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _lat = _lng = ''),
                        child: const Text('(삭제)',
                            style: TextStyle(fontSize: 11, color: AppColors.textGray)),
                      ),
                    ],
                  ),
                ),
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
                      lat: _lat,
                      lng: _lng,
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

  /// [요구] 행사기획 시 지도에서 위치를 '검색하면 곧바로 입력'한다.
  ///   · 웹 + 카카오 JS 키가 있으면 → **실제 카카오맵(드래그·검색)** 선택기.
  ///   · 그 외 → 무료 지오코딩 검색 목록(좌표 즉시 입력) + 미리보기.
  Future<void> _searchOnMap() async {
    final nas = context.read<NasApi>();
    if (isWebRuntime) {
      final cfg = await nas.geoConfig();
      final jsKey = '${cfg['kakaoJsKey'] ?? ''}'.trim();
      if (jsKey.isNotEmpty) {
        final picked = await openKakaoMapPicker(
          key: jsKey,
          title: _title.text.trim(),
          place: _place.text.trim(),
          lat: _lat,
          lng: _lng,
        );
        if (picked != null) {
          // 카카오 JS SDK 로드 실패(키 무효/도메인 미등록 등) →
          //   조용히 아무 일도 안 일어나는 대신, 무료 검색으로 자동 폴백한다.
          if ((picked['error'] ?? '').isNotEmpty) {
            if (!mounted) return;
            await _searchOnMapFallback(kakaoError: true);
            return;
          }
          if (!mounted) return;
          setState(() {
            _lat = picked['lat'] ?? '';
            _lng = picked['lng'] ?? '';
            final nm = (picked['place'] ?? '').trim();
            if (nm.isNotEmpty) _place.text = nm;
          });
          _toast('지도 위치가 지정되었습니다');
        }
        return;
      }
    }
    await _searchOnMapFallback();
  }

  /// 무료 지오코딩 기반 검색(카카오 JS 키가 없거나 네이티브일 때).
  /// [kakaoError] 가 true 면 "카카오 키가 있는데 SDK 로드 실패" 상태 → 정확한 안내.
  Future<void> _searchOnMapFallback({bool kakaoError = false}) async {
    // (버그수정) 검색어는 '장소' 우선 — 행사명이 섞이면 엉뚱한 곳이 검색된다.
    final qCtrl = TextEditingController(
      text: _place.text.trim().isNotEmpty
          ? _place.text.trim()
          : _title.text.trim(),
    );
    List<Map<String, dynamic>> items = [];
    bool loading = false;
    String? err;
    final nas = context.read<NasApi>();
    // 카카오 진단(키가 있는데 실패한 경우) — 정확한 원인을 사용자에게 그대로 보여준다.
    final diagVN = ValueNotifier<String?>(null);
    if (kakaoError) {
      nas.geoKakaoTest().then((t) {
        diagVN.value = _fmtKakaoDiag(t);
      }).catchError((_) {
        diagVN.value = '카카오맵 서비스가 꺼져 있거나 키가 유효하지 않습니다. '
            '마스터 콘솔 → [지도 검색 키 (카카오)]에서 확인하세요. '
            '지금은 무료 지도로 검색합니다.';
      });
    }
    Future<void> doSearch(StateSetter setSt) async {
      final q = qCtrl.text.trim();
      if (q.length < 2) return;
      setSt(() {
        loading = true;
        err = null;
      });
      try {
        final r = await nas.geoSearch(q, limit: 8);
        setSt(() {
          items = r;
          loading = false;
          if (r.isEmpty) err = '검색 결과가 없습니다. 다른 검색어로 시도해 보세요.';
        });
      } catch (e) {
        setSt(() {
          loading = false;
          err = '검색 실패: $e';
        });
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.map, size: 20, color: AppColors.purple),
              SizedBox(width: 6),
              Text('지도에서 위치 검색', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '장소/주소를 검색하면 좌표가 곧바로 입력됩니다. '
                    '결과를 누르면 정확한 위치가 저장됩니다.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
                  ),
                  const SizedBox(height: 6),
                  if (kakaoError)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.taegeukRed.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline, size: 15, color: AppColors.taegeukRed),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  '카카오맵을 불러오지 못했습니다. 아래 무료 지도(OpenStreetMap)로 검색합니다.',
                                  style: TextStyle(fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          ValueListenableBuilder<String?>(
                            valueListenable: diagVN,
                            builder: (_, dv, __) {
                              if (dv == null || dv.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 6, left: 21),
                                  child: SizedBox(
                                    height: 12,
                                    width: 12,
                                    child: CircularProgressIndicator(strokeWidth: 1.6),
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4, left: 21),
                                child: Text(
                                  dv,
                                  style: const TextStyle(
                                      fontSize: 11, height: 1.45, color: AppColors.textGray),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '💡 무료 지도(OpenStreetMap) 검색 중입니다. 상호명(예: 송정호텔)이 '
                        '안 잡히면 마스터 콘솔 → [지도 검색 키 (카카오)]에 카카오 키를 '
                        '등록하고 카카오맵 서비스를 켜면 카카오맵(정확)으로 전환됩니다.',
                        style: TextStyle(fontSize: 11, height: 1.45),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: '장소/주소 검색',
                            hintText: '예) 부산 송정해수욕장',
                          ),
                          onSubmitted: (_) => doSearch(setSt),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: loading ? null : () => doSearch(setSt),
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('검색', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  if (err != null && !loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(err!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.taegeukRed)),
                    ),
                  for (final it in items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE0DCE8)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined,
                            size: 18, color: AppColors.purple),
                        title: Text(
                          '${it['label'] ?? it['name'] ?? ''}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        subtitle: Text('${it['lat']}, ${it['lng']}',
                            style: const TextStyle(fontSize: 10.5)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyGeoChoice(it);
                        },
                      ),
                    ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _mapPreview('${items.first['lat']}', '${items.first['lng']}'),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setSt(() {
                  _lat = '';
                  _lng = '';
                  items = [];
                });
              },
              child: const Text('좌표 지우기'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('직접 입력'),
            ),
          ],
        ),
      ),
    );
    qCtrl.dispose();
    diagVN.dispose();
  }

  /// 카카오 진단 응답(JSON) → 사용자가 바로 이해할 수 있는 한 줄 안내.
  static String _fmtKakaoDiag(Map<String, dynamic> t) {
    final hint = '${t['hint'] ?? ''}'.trim();
    if (t['ok'] == true) return '카카오 키·서비스 정상입니다.';
    if (hint.isNotEmpty) return hint;
    final kakao = t['kakao'];
    if (kakao is Map && '${kakao['message'] ?? ''}'.trim().isNotEmpty) {
      return '카카오 오류: ${kakao['message']} '
          '(마스터 콘솔 → [지도 검색 키 (카카오)]에서 확인하세요)';
    }
    final err = '${t['error'] ?? ''}'.trim();
    if (err.isNotEmpty) return '카카오 연결 오류: $err';
    return '카카오 응답을 확인할 수 없습니다. 키/서비스 상태를 점검하세요.';
  }

  /// 검색 결과에서 선택한 위치를 저장(장소명이 비어 있으면 결과 라벨 사용).
  void _applyGeoChoice(Map<String, dynamic> it) {
    setState(() {
      _lat = '${it['lat'] ?? ''}';
      _lng = '${it['lng'] ?? ''}';
      if (_place.text.trim().isEmpty) {
        final lb = '${it['name'] ?? it['label'] ?? ''}'.trim();
        if (lb.isNotEmpty) _place.text = lb;
      }
    });
  }

  /// (요구) 검색 위치 지도 미리보기.
  ///   카카오 지도(JS 키 등록 시) → 실패하면 무료 OSM 지도로 자동 폴백.
  Widget _mapPreview(String lat, String lng) {
    if (lat.isEmpty || lng.isEmpty) return const SizedBox.shrink();
    final nas = context.read<NasApi>();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        nas.geoKakaoMapUrl(lat, lng, w: 520, h: 240),
        height: 160,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.network(
          nas.geoStaticMapUrl(lat, lng, w: 520, h: 240),
          height: 160,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFEE500).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('지도 미리보기를 불러올 수 없습니다',
                style: TextStyle(fontSize: 11, color: AppColors.textGray)),
          ),
        ),
      ),
    );
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }

  static String _fmtSize(int n) {    if (n < 1024) return '$n B';
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
