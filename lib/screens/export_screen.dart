import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import '../widgets/marquee_text.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member.dart';
import '../services/contact_service.dart';
import '../services/export_service.dart';
import '../services/file_save.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/tsak_output_sheet.dart';
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

  /// 용지 방향 — true: A4 가로(landscape) / false: A4 세로(portrait).
  bool _landscape = true;

  /// 표 스타일(감격/강조) — 머리글·테두리 강조 정도.
  ExportTableStyle _tableStyle = ExportTableStyle.accent;

  /// 글씨 크기 — 표 본문/머리글/제목 폰트 크기 프리셋.
  ExportFontSize _fontSize = ExportFontSize.normal;

  /// 행 간격(밀도) — 셀 안쪽 여백 프리셋.
  ExportRowSpace _rowSpace = ExportRowSpace.normal;

  /// 두줄 방지 대상 열 — 켜면 해당 열은 줄바꿈하지 않고 열 너비를 확보한다.
  /// 기본: 이름·범/아타스/은하 인가번호·핸드폰·이메일 6개.
  final Set<String> _noWrap = {...kNoWrapDefault};

  /// 표 맨 앞에 연번(순번) 열을 넣을지 — 사용자 선택(기본 꺼짐).
  bool _numbering = false;

  /// 상단에 노출되는 메뉴(열) 순서 — 전체 항목 key 를 담으며 사용자가 재정렬한다.
  /// 실제 출력 열 순서 = `_order` 중 선택된 항목만(순서 유지).
  List<String> _order = kExportFields.map((f) => f.key).toList();

  /// 선택된 개인정보 항목 (기본: 전체)
  final Set<String> _selectedFields = {...kDefaultFieldKeys};

  /// 상단 구분(카테고리) 필터 — 범스카우트/은하스카우트/멘토/페런츠/서포터츠.
  /// (요구: 전체명단출력 상단에 구분버튼 추가 · 복수선택 가능)
  final Set<String> _cats = {'tsak', 'eunha', 'mentor', 'parent', 'supporters'};

  /// 구분 라벨(고정 순서).
  static const List<List<String>> _catDefs = [
    ['tsak', '범스카우트'],
    ['eunha', '은하스카우트'],
    ['mentor', '멘토'],
    ['parent', '페런츠'],
    ['supporters', '서포터츠'],
  ];

  /// 구분 필터가 적용된 실제 대상 명단.
  List<Member> get _visible {
    if (_cats.length == _catDefs.length) return widget.members;
    return widget.members.where((m) {
      // 서포터츠(비인가/일반회원): 전화 기반 계정.
      final isSupporter = m.isRegular || m.accessPhone.trim().isNotEmpty;
      if (m.corps == 'eunha') return _cats.contains('eunha');
      if (isSupporter) return _cats.contains('supporters');
      final hasMentee = m.mentees.isNotEmpty;
      final hasChild = m.children.isNotEmpty;
      if (hasMentee && _cats.contains('mentor')) return true;
      if (hasChild && _cats.contains('parent')) return true;
      return _cats.contains('tsak');
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  List<String> get _fieldKeys {
    // 사용자가 정한 열 순서(_order)를 따르며 선택된 항목만.
    final sel = _order.where(_selectedFields.contains).toList();
    // 혹시 누락된 항목이 있으면 뒤에 붙여 안전하게.
    for (final f in kExportFields) {
      if (_selectedFields.contains(f.key) && !sel.contains(f.key)) {
        sel.add(f.key);
      }
    }
    return sel;
  }

  /// 라벨 조회 헬퍼 — key → 표시명.
  String _labelOf(String key) => kExportFields
      .firstWhere((f) => f.key == key, orElse: () => ExportField(key, key))
      .label;

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  List<List<Member>> get _chunks {
    if (!_chunk100) return [_visible];
    final out = <List<Member>>[];
    for (var i = 0; i < _visible.length; i += 100) {
      out.add(
        _visible.sublist(
          i,
          (i + 100 > _visible.length) ? _visible.length : i + 100,
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
        const SizedBox(height: 12),
        _categoryFilter(),
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
          'V 표시된 항목만 명단(모든 형식)에 포함됩니다. 항목을 눌러 켜고 끄세요.',
          style: TextStyle(fontSize: 11, color: AppColors.textGray),
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
            const Spacer(),
            _miniTextButton('열 순서', _editOrder),
          ],
        ),
        const SizedBox(height: 6),
        _fieldPanel(),
        const SizedBox(height: 18),
        _sectionTitle('표 스타일 · 감격'),
        const SizedBox(height: 6),
        _tableStyleRow(),
        const SizedBox(height: 18),
        _sectionTitle('글씨 크기'),
        const SizedBox(height: 6),
        _segmented<ExportFontSize>(
          ExportFontSize.values,
          _fontSize,
          (v) => v.label,
          (v) => v.note,
          (v) => setState(() => _fontSize = v),
        ),
        const SizedBox(height: 18),
        _sectionTitle('행 간격 (밀도)'),
        const SizedBox(height: 6),
        _segmented<ExportRowSpace>(
          ExportRowSpace.values,
          _rowSpace,
          (v) => v.label,
          (v) => v.note,
          (v) => setState(() => _rowSpace = v),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _sectionTitle('두줄 방지 (줄바꿈 금지)'),
            const Spacer(),
            _miniTextButton('전체', () {
              setState(() => _noWrap.addAll(kNoWrapCandidates));
            }),
            _miniTextButton('해제', () => setState(() => _noWrap.clear())),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '켠 항목은 두 줄로 깨지지 않고, 값이 한 줄에 들어가도록 열 너비를 자동 확보합니다. (PDF·이미지)',
          style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
        ),
        const SizedBox(height: 6),
        _noWrapPanel(),
        const SizedBox(height: 18),
        _sectionTitle('출력 용지 방향'),
        const SizedBox(height: 6),
        _orientationRow(),
        const SizedBox(height: 20),
        _numberingSwitch(),
        const SizedBox(height: 20),
        _chunkSwitch(),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.purple,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: _busy ? null : _showPreview,
          icon: const Icon(Icons.table_view, size: 18),
          label: const Text('출력 미리보기 (예상)'),
        ),
        const SizedBox(height: 10),
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
        // (요구) 모든 포맷을 외부 프로그램(OS 공유 시트 · 뷰어)으로 내보낸다.
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: AppColors.purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _busy ? null : _openCurrent,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text('${_format.label} 외부로 열기'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.taegeukBlue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _busy ? null : _shareCurrent,
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('공유 시트로 보내기'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _sectionTitle('미리보기 (상위 30명)'),
        const SizedBox(height: 8),
        ..._visible.take(30).map((m) => MemberCard(member: m)),
        if (_visible.length > 30)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '외 ${_visible.length - 30}명...',
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// 상단 구분(카테고리) 필터 — 복수선택 가능. (요구 #4)
  ///   범스카우트 / 은하스카우트 / 멘토 / 페런츠 / 서포터츠
  Widget _categoryFilter() {
    final all = _cats.length == _catDefs.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.filter_alt_outlined,
              size: 15,
              color: AppColors.purple,
            ),
            const SizedBox(width: 5),
            const Text(
              '구분 (복수선택 가능)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.purple,
              ),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.purple,
              ),
              onPressed: () => setState(() {
                if (all) {
                  _cats.clear();
                } else {
                  _cats.addAll(_catDefs.map((e) => e[0]));
                }
              }),
              child: Text(
                all ? '전체해제' : '전체선택',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final d in _catDefs)
              _chip(d[1], _cats.contains(d[0]), () {
                setState(() {
                  if (_cats.contains(d[0])) {
                    _cats.remove(d[0]);
                  } else {
                    _cats.add(d[0]);
                  }
                });
              }),
          ],
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

  /// 항목 선택 — 문서형(작은 글씨·V 체크) 목록. 버튼식 칩 대신 표 한 줄.
  ///
  /// · 왼쪽: V 체크박스(선택 표시) · 가운데: 번호 · 항목명 · 오른쪽: 그룹 태그.
  /// · 그룹(기본/연락/주소/자격/회비/기타)마다 얇은 머리글 줄로 구분한다.
  Widget _fieldPanel() {
    const order = ['기본', '연락', '주소', '자격', '회비', '기타'];
    final groups = <String, List<ExportField>>{};
    for (final f in kExportFields) {
      groups.putIfAbsent(f.group, () => []).add(f);
    }
    final groupKeys = order.where(groups.containsKey).toList();
    var rowNo = 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var gi = 0; gi < groupKeys.length; gi++) ...[
            if (gi > 0)
              const Divider(height: 1, thickness: 1, color: Color(0xFFEEEBF3)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
              child: Row(
                children: [
                  Text(
                    groupKeys[gi],
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.purple,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${groups[groupKeys[gi]]!.length}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            for (final f in groups[groupKeys[gi]]!) _fieldDocRow(f, ++rowNo),
          ],
        ],
      ),
    );
  }

  /// 항목 한 줄 — V 체크 + 순번 + 항목명 + 그룹 태그. 글씨 최소화·아이콘 없음.
  Widget _fieldDocRow(ExportField f, int no) {
    final on = _selectedFields.contains(f.key);
    return InkWell(
      onTap: () => setState(() {
        if (on) {
          _selectedFields.remove(f.key);
        } else {
          _selectedFields.add(f.key);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            // V 표 체크 — 선택 시만 보라 V, 미선택 시 옅은 빈 상자.
            SizedBox(
              width: 17,
              height: 17,
              child: on
                  ? const Icon(Icons.check, size: 16, color: AppColors.purple)
                  : Icon(
                      Icons.check_box_outline_blank,
                      size: 15,
                      color: AppColors.purple.withValues(alpha: 0.35),
                    ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 20,
              child: Text(
                '$no',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textGray,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                f.label,
                style: TextStyle(
                  fontSize: 12,
                  color: on ? AppColors.textDark : AppColors.textGray,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                f.group,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: AppColors.purple,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 두줄 방지 — 이름/인가번호/핸드폰/이메일을 문서형 V체크로 켜고 끈다.
  Widget _noWrapPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < kNoWrapCandidates.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: Color(0xFFEEEBF3)),
            _noWrapRow(kNoWrapCandidates[i], i + 1),
          ],
        ],
      ),
    );
  }

  Widget _noWrapRow(String key, int no) {
    final on = _noWrap.contains(key);
    return InkWell(
      onTap: () => setState(() {
        if (on) {
          _noWrap.remove(key);
        } else {
          _noWrap.add(key);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 17,
              height: 17,
              child: on
                  ? const Icon(Icons.check, size: 16, color: AppColors.purple)
                  : Icon(
                      Icons.check_box_outline_blank,
                      size: 15,
                      color: AppColors.purple.withValues(alpha: 0.35),
                    ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 20,
              child: Text(
                '$no',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textGray,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                kNoWrapLabels[key] ?? key,
                style: TextStyle(
                  fontSize: 12,
                  color: on ? AppColors.textDark : AppColors.textGray,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const Text(
              '줄바꿈 금지',
              style: TextStyle(
                fontSize: 9.5,
                color: AppColors.purple,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3분할 세그먼트 컨트롤 — 라벨 + 보조설명. 글씨 크기/간격 선택 공용.
  Widget _segmented<T>(
    List<T> values,
    T current,
    String Function(T) label,
    String Function(T) note,
    ValueChanged<T> onPick,
  ) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: InkWell(
                onTap: () => onPick(v),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  padding: const EdgeInsets.symmetric(
                    vertical: 7,
                    horizontal: 2,
                  ),
                  decoration: BoxDecoration(
                    color: current == v ? AppColors.purple : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        label(v),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: current == v
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: current == v
                              ? Colors.white
                              : AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 1),
                      MarqueeText(
                        note(v),
                        align: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9,
                          color: current == v
                              ? Colors.white.withValues(alpha: 0.85)
                              : AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 표 스타일(감격/강조) 선택 — 가로 스크롤 소형 텍스트 라디오.
  Widget _tableStyleRow() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in ExportTableStyle.values)
            InkWell(
              onTap: () => setState(() => _tableStyle = s),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    Icon(
                      _tableStyle == s
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: _tableStyle == s
                          ? AppColors.purple
                          : AppColors.purple.withValues(alpha: 0.35),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _tableStyle == s
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _tableStyle == s
                            ? AppColors.textDark
                            : AppColors.textGray,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      s.note,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 용지 방향 선택 — 가로/세로.
  Widget _orientationRow() {
    return Row(
      children: [
        Expanded(
          child: _orientTile(
            '가로 (A4 가로)',
            '항목이 많을 때 · 기본',
            Icons.stay_current_landscape,
            true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _orientTile(
            '세로 (A4 세로)',
            '항목이 적을 때',
            Icons.stay_current_portrait,
            false,
          ),
        ),
      ],
    );
  }

  Widget _orientTile(String title, String sub, IconData icon, bool value) {
    final on = _landscape == value;
    return InkWell(
      onTap: () => setState(() => _landscape = value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppColors.purple.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on
                ? AppColors.purple
                : AppColors.purple.withValues(alpha: 0.18),
            width: on ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: on ? AppColors.purple : AppColors.textGray,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                      color: on ? AppColors.purpleDark : AppColors.textDark,
                    ),
                  ),
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
            if (on)
              const Icon(Icons.check_circle, size: 16, color: AppColors.purple),
          ],
        ),
      ),
    );
  }

  /// 열(메뉴) 순서 편집 — 바텀시트에서 위/아래로 재정렬.
  /// 이 순서가 그대로 출력물 상단 메뉴 순서가 된다.
  Future<void> _editOrder() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void move(int i, int d) {
            final to = i + d;
            if (to < 0 || to >= _order.length) return;
            setState(() {
              final it = _order.removeAt(i);
              _order.insert(to, it);
            });
            setSheet(() {});
          }

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.82,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '열(메뉴) 순서',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(
                            () => _order = kExportFields
                                .map((f) => f.key)
                                .toList(),
                          ),
                          child: const Text(
                            '기본 순서',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '위·아래로 옮겨 출력물 상단 메뉴 순서를 정하세요. '
                        'V 표시된 항목만 실제로 출력됩니다.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _order.length,
                      onReorder: (oldI, newI) => setSheet(() {
                        setState(() {
                          if (newI > oldI) newI -= 1;
                          final it = _order.removeAt(oldI);
                          _order.insert(newI, it);
                        });
                      }),
                      itemBuilder: (ctx, i) {
                        final key = _order[i];
                        final on = _selectedFields.contains(key);
                        return ListTile(
                          key: ValueKey(key),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: SizedBox(
                            width: 34,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textGray,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  on
                                      ? Icons.check
                                      : Icons.check_box_outline_blank,
                                  size: 14,
                                  color: on
                                      ? AppColors.purple
                                      : AppColors.purple.withValues(alpha: 0.3),
                                ),
                              ],
                            ),
                          ),
                          title: Text(
                            _labelOf(key),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.keyboard_arrow_up,
                                  size: 18,
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 30,
                                  minHeight: 30,
                                ),
                                onPressed: i == 0 ? null : () => move(i, -1),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 18,
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 30,
                                  minHeight: 30,
                                ),
                                onPressed: i == _order.length - 1
                                    ? null
                                    : () => move(i, 1),
                              ),
                              const Icon(
                                Icons.drag_handle,
                                size: 18,
                                color: AppColors.textGray,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.purple,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('적용'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 출력 전 예상 — 선택 항목·순서·방향·표 스타일을 반영한 표 미리보기.
  Future<void> _showPreview() async {
    if (_visible.isEmpty) {
      _snack('선택된 인가자가 없습니다');
      return;
    }
    final keys = _fieldKeys.isEmpty ? kDefaultFieldKeys : _fieldKeys;
    final heads = keys.map(_labelOf).toList();
    final sample = _visible.take(12).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.86,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '출력 미리보기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _previewBadge('${_visible.length}명'),
                      const SizedBox(width: 6),
                      _previewBadge(_landscape ? '가로' : '세로'),
                      const SizedBox(width: 6),
                      _previewBadge(_tableStyle.label),
                      const SizedBox(width: 6),
                      _previewBadge('글씨 ${_fontSize.label}'),
                      const SizedBox(width: 6),
                      _previewBadge('간격 ${_rowSpace.label}'),
                      const SizedBox(width: 6),
                      _previewBadge('두줄방지 ${_noWrap.length}'),
                      const SizedBox(width: 6),
                      _previewBadge(_numbering ? '연번 있음' : '연번 없음'),
                      const SizedBox(width: 6),
                      _previewBadge('${heads.length}개 항목'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '상위 12명만 예시로 표시합니다. (실제 출력은 전체 대상)',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 34,
                      dataRowMinHeight: 30,
                      dataRowMaxHeight: 40,
                      horizontalMargin: 10,
                      columnSpacing: 14,
                      headingRowColor: WidgetStateProperty.all(
                        _tableStyle == ExportTableStyle.framed
                            ? const Color(0xFFEDEAE3)
                            : AppColors.purple.withValues(alpha: 0.10),
                      ),
                      border: TableBorder.all(
                        color: AppColors.purple.withValues(alpha: 0.25),
                        width: 0.6,
                      ),
                      columns: [
                        if (_numbering)
                          const DataColumn(
                            label: Text(
                              '연번',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        for (final h in heads)
                          DataColumn(
                            label: Text(
                              h,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.purpleDark,
                              ),
                            ),
                          ),
                      ],
                      rows: [
                        for (var i = 0; i < sample.length; i++)
                          DataRow(
                            color:
                                (_tableStyle == ExportTableStyle.zebra &&
                                    i.isOdd)
                                ? WidgetStateProperty.all(
                                    AppColors.purple.withValues(alpha: 0.05),
                                  )
                                : null,
                            cells: [
                              if (_numbering)
                                DataCell(
                                  Text(
                                    '${i + 1}',
                                    style: const TextStyle(fontSize: 10.5),
                                  ),
                                ),
                              for (final k in keys)
                                DataCell(
                                  Text(
                                    _short(exportValueOf(sample[i], k)),
                                    style: const TextStyle(fontSize: 10.5),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewBadge(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.purple.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 10.5,
        color: AppColors.purple,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  String _short(String v) {
    final s = v.trim();
    if (s.isEmpty) return '-';
    return s.length > 14 ? '${s.substring(0, 13)}…' : s;
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
              '선택된 인가자 ${_visible.length}명',
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

  /// 연번(표 맨 앞 순번) 열 포함 여부 — 사용자 선택.
  Widget _numberingSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: SwitchListTile(
        value: _numbering,
        activeThumbColor: AppColors.purple,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: const Text(
          '표 맨 앞에 연번(순번) 표시',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        subtitle: Text(
          _numbering ? '맨 앞에 1부터 시작하는 연번 열을 넣습니다' : '연번 없이 항목만 표시합니다',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
        ),
        onChanged: (v) => setState(() => _numbering = v),
      ),
    );
  }

  Future<void> _doExport() async {
    if (_visible.isEmpty) {
      _snack('선택된 인가자가 없습니다');
      return;
    }
    // ① 저장 방법·위치 선택 창 (PC·모든 모바일 공통)
    final choice = await _askSaveMethod();
    if (choice == null) return; // 취소
    final choose = choice == 'choose';
    if (!mounted) return;

    // ② 실시간 진행 대기창을 띄우고 파일을 만든다(공통 진행창).
    var saved = 0;
    final chunks = _chunks;
    final fields = _fieldKeys.isEmpty ? kDefaultFieldKeys : _fieldKeys;
    final baseName = _baseName();
    final total = chunks.length;
    var numStart = 1; // 분할 출력 시 연번 이어짐(청크별 시작 번호)
    var failed = false;
    try {
      await runWithTsakProgress(
        context,
        title: '명단 ${_format.label} 생성',
        note:
            '${_visible.length}명 · $total개 파일'
            '${_chunk100 ? ' (100명 분할)' : ''}',
        steps: const ['문서 구성', '파일 생성', '파일 저장'],
        task: (ctl) async {
          ctl.update(progress: 0.05, message: '문서를 구성하는 중…', stepIndex: 0);
          for (var i = 0; i < chunks.length; i++) {
            final list = chunks[i];
            final suffix = chunks.length > 1 ? '_${i + 1}' : '';
            final name = '$baseName$suffix';
            final frac = (i + 1) / total;
            ctl.update(
              progress: 0.10 + 0.80 * (i / total),
              message:
                  '$total개 중 ${i + 1}번째 파일 생성 중…'
                  ' (${list.length}명)',
              stepIndex: 1,
            );
            Uint8List bytes;
            switch (_format) {
              case ExportFormat.excel:
                bytes = ExportService.buildExcel(
                  list,
                  fieldKeys: fields,
                  numbering: _numbering,
                  numberingStart: numStart,
                );
                break;
              case ExportFormat.pdf:
                bytes = await ExportService.buildPdf(
                  list,
                  fieldKeys: fields,
                  landscape: _landscape,
                  style: _tableStyle,
                  fontSize: _fontSize,
                  rowSpace: _rowSpace,
                  noWrapKeys: _noWrap,
                  numbering: _numbering,
                  numberingStart: numStart,
                );
                break;
              case ExportFormat.word:
                bytes = ExportService.buildWord(
                  list,
                  fieldKeys: fields,
                  numbering: _numbering,
                  numberingStart: numStart,
                );
                break;
              case ExportFormat.txt:
                bytes = ExportService.buildTxt(
                  list,
                  fieldKeys: fields,
                  numbering: _numbering,
                  numberingStart: numStart,
                );
                break;
              case ExportFormat.ppt:
                bytes = ExportService.buildPpt(
                  list,
                  fieldKeys: fields,
                  numbering: _numbering,
                  numberingStart: numStart,
                );
                break;
              case ExportFormat.jpg:
                bytes = await ExportService.buildPdf(
                  list,
                  fieldKeys: fields,
                  landscape: _landscape,
                  style: _tableStyle,
                  fontSize: _fontSize,
                  rowSpace: _rowSpace,
                  noWrapKeys: _noWrap,
                  numbering: _numbering,
                  numberingStart: numStart,
                );
                break;
            }
            numStart += list.length; // 다음 청크 연번 시작
            ctl.update(
              progress: 0.10 + 0.80 * frac,
              message: '파일 저장 중… ($name.${_format.extension})',
              stepIndex: 2,
            );
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
          ctl.update(progress: 1.0, message: '완료', stepIndex: 2);
        },
      );
    } catch (e) {
      failed = true;
      _snack('내보내기 실패: $e');
    }
    if (failed) return;
    if (saved == 0) {
      _snack('저장이 취소되었습니다');
    } else {
      _snack('내보내기 완료 ($saved개 파일 · ${_format.label})');
    }
  }

  /// 선택 형식의 **첫 파일 바이트와 이름/확장자/MIME**을 만든다(저장·공유·열기 공용).
  ///
  /// JPG 는 PDF 를 만들어 첫 페이지를 래스터화한다([_doExport] 와 동일 규칙).
  Future<({Uint8List bytes, String name, String ext, String mime})>
  _buildFirstFile(
    List<Member> list,
    List<String> fields,
    String baseName,
    int suffix,
  ) async {
    final name = '$baseName$suffix';
    final bytes = await _buildBytesFor(_format, list, fields);
    return (
      bytes: bytes,
      name: name,
      ext: _format.extension,
      mime: _mimeStr(_format),
    );
  }

  /// 형식별 바이트 생성(저장/공유/열기 공용).
  Future<Uint8List> _buildBytesFor(
    ExportFormat fmt,
    List<Member> list,
    List<String> fields,
  ) async {
    switch (fmt) {
      case ExportFormat.excel:
        return ExportService.buildExcel(
          list,
          fieldKeys: fields,
          numbering: _numbering,
        );
      case ExportFormat.pdf:
      case ExportFormat.jpg:
        final pdf = await ExportService.buildPdf(
          list,
          fieldKeys: fields,
          landscape: _landscape,
          style: _tableStyle,
          fontSize: _fontSize,
          rowSpace: _rowSpace,
          noWrapKeys: _noWrap,
          numbering: _numbering,
        );
        if (fmt == ExportFormat.jpg) {
          final raster = await Printing.raster(pdf, dpi: 150).first;
          final im = img.Image.fromBytes(
            width: raster.width,
            height: raster.height,
            bytes: raster.pixels.buffer,
            numChannels: 4,
          );
          return img.encodeJpg(im, quality: 88);
        }
        return pdf;
      case ExportFormat.word:
        return ExportService.buildWord(
          list,
          fieldKeys: fields,
          numbering: _numbering,
        );
      case ExportFormat.txt:
        return ExportService.buildTxt(
          list,
          fieldKeys: fields,
          numbering: _numbering,
        );
      case ExportFormat.ppt:
        return ExportService.buildPpt(
          list,
          fieldKeys: fields,
          numbering: _numbering,
        );
    }
  }

  /// 생성한 파일을 **OS 공유 시트**(모든 기기)로 바로 보낸다 — 모든 형식 공통.
  ///
  /// (요구: "모든 포맷도 외부 공유 프로그램으로 내보낼 수 있게")
  Future<void> _shareCurrent() async {
    if (_visible.isEmpty) {
      _snack('선택된 인가자가 없습니다');
      return;
    }
    final fields = _fieldKeys.isEmpty ? kDefaultFieldKeys : _fieldKeys;
    setState(() => _busy = true);
    try {
      late TsakShareResult res;
      await runWithTsakProgress(
        context,
        title: '명단 ${_format.label} 공유 준비',
        note: '${_visible.length}명 명단을 ${_format.label}(으)로 만들어 공유합니다.',
        steps: ['문서 구성', '${_format.label} 생성', '공유 시트 열기'],
        task: (ctl) async {
          ctl.update(progress: 0.2, message: '문서를 구성하는 중…', stepIndex: 0);
          ctl.update(
            progress: 0.6,
            message: '${_format.label} 생성 중…',
            stepIndex: 1,
          );
          final f = await _buildFirstFile(_visible, fields, _baseName(), 0);
          res = await shareBytes(
            bytes: f.bytes,
            name: f.name,
            ext: f.ext,
            mime: f.mime,
            subject: 'TSAK 인가자 명단',
            text: '명단 ${_visible.length}명 · ${_format.label}',
          );
          ctl.update(progress: 1.0, message: '공유 시트를 엽니다', stepIndex: 2);
        },
      );
      if (mounted) _snack(tsakShareMessage(res, what: '명단 ${_format.label}'));
    } catch (e) {
      if (mounted) _snack('공유 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 생성한 파일을 **외부 프로그램/뷰어로 연다** — 모든 형식 공통(웹은 새 탭).
  ///
  /// (요구: "모든 포맷도 외부 공유 프로그램으로 내보낼 수 있게")
  Future<void> _openCurrent() async {
    if (_visible.isEmpty) {
      _snack('선택된 인가자가 없습니다');
      return;
    }
    final fields = _fieldKeys.isEmpty ? kDefaultFieldKeys : _fieldKeys;
    setState(() => _busy = true);
    try {
      late TsakShareResult res;
      await runWithTsakProgress(
        context,
        title: '명단 ${_format.label} 외부 열기',
        note: '${_visible.length}명 명단을 ${_format.label}(으)로 만들어 엽니다.',
        steps: ['문서 구성', '${_format.label} 생성', '외부 프로그램 열기'],
        task: (ctl) async {
          ctl.update(progress: 0.2, message: '문서를 구성하는 중…', stepIndex: 0);
          ctl.update(
            progress: 0.6,
            message: '${_format.label} 생성 중…',
            stepIndex: 1,
          );
          final f = await _buildFirstFile(_visible, fields, _baseName(), 0);
          final opened = openFileExternally(
            f.bytes,
            '${f.name}.${f.ext}',
            f.mime,
          );
          res = opened
              ? TsakShareResult.shared
              : await shareBytes(
                  bytes: f.bytes,
                  name: f.name,
                  ext: f.ext,
                  mime: f.mime,
                  subject: 'TSAK 인가자 명단',
                );
          ctl.update(progress: 1.0, message: '외부 프로그램을 엽니다', stepIndex: 2);
        },
      );
      if (mounted) _snack(tsakShareMessage(res, what: '명단 ${_format.label}'));
    } catch (e) {
      if (mounted) _snack('열기 실패: $e');
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
              '${_format.label} · ${_visible.length}명'
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
      final bytes = await ExportService.buildPdf(
        _visible,
        fieldKeys: _fieldKeys.isEmpty ? kDefaultFieldKeys : _fieldKeys,
        landscape: _landscape,
        style: _tableStyle,
        fontSize: _fontSize,
        rowSpace: _rowSpace,
        noWrapKeys: _noWrap,
        numbering: _numbering,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      _snack('미리보기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- 문자 ----------------
  Widget _smsTab() {
    final phones = ContactService.phones(_visible);
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
          copyText: ContactService.phoneList(_visible),
        ),
      ],
    );
  }

  Future<void> _openSms(String body) async {
    final uri = Uri.parse(ContactService.smsUri(_visible, body: body));
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
    final emails = ContactService.emails(_visible);
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
          copyText: ContactService.emailList(_visible),
        ),
      ],
    );
  }

  Future<void> _openMail(String subject, String body) async {
    var uri = Uri.parse(
      ContactService.mailtoUri(_visible, subject: subject, body: body),
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
