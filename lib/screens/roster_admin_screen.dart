import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/output_formats.dart';
import '../services/table_export.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/hscroll_menu.dart';
import '../widgets/scroll_arrows.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/tsak_output_sheet.dart';

/// 명부관리 — (관리자·마스터, 관리자 명부는 마스터 전용)
///
/// 별도 창(화면)으로 5종 명부를 탭으로 제공한다.
///   1. 범스카우트 인가자 명부 : 범인가번호 + 아타스인가번호 + 이름 + 연락처 + 소속
///   2. 멘토 대장 명부        : 범인가번호(멘토메달신청인) + 받는분의 범인가번호
///                              또는 생성년월(수정가능) + 이름 + 연락처 + 소속
///   3. 페런츠 명부           : 2와 동일 스키마
///   4. 서포터즈              : 아이디생성년월 + 이름 + 전화번호 + 소속
///   5. 관리자 명부 (마스터만) : 범인가번호 + 아타스인가번호 + 이름 + 연락처 + 소속
///                              + 관리자권한 부여일
class RosterAdminScreen extends StatefulWidget {
  const RosterAdminScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<RosterAdminScreen> createState() => _RosterAdminScreenState();
}

class _RosterAdminScreenState extends State<RosterAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> _profiles = <String, dynamic>{};
  Map<String, dynamic> _adminInfo = <String, dynamic>{};

  // 좌측 선택창 — 탭별 선택된 행(로스터 항목) 인덱스 집합
  final Set<String> _sel = {};
  bool _selMode = false;
  bool _busyBuilding = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _tab.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    // 탭 이동 시 선택 초기화(탭마다 스키마가 달라 혼선 방지).
    if (_sel.isNotEmpty) setState(() => _sel.clear());
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profs = await state.nas.linkProfiles();
      Map<String, dynamic> admins = <String, dynamic>{};
      if (state.isMaster) {
        admins = await state.nas.merchantAdmins();
      }
      if (!mounted) return;
      setState(() {
        _profiles = profs;
        _adminInfo = admins;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ---- 소속 문자열 ----
  String _org(String league, String unit) {
    final l = league.trim();
    final u = unit.trim();
    if (l.isEmpty && u.isEmpty) return '';
    if (l.isEmpty) return u;
    if (u.isEmpty) return l;
    return '$l · $u';
  }

  // ---- 생성년월 (yyyy.MM) ----
  String _ym(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final m = RegExp(r'(\d{4})[.\-/]?(\d{2})').firstMatch(s);
    if (m != null) return '${m.group(1)}.${m.group(2)}';
    return s;
  }

  List<Member> _credentialMembers(AppState state) {
    final list = state.allMembers.where((m) => !m.isRegular).toList();
    list.sort((a, b) => a.numberInt.compareTo(b.numberInt));
    return list;
  }

  List<Member> _supporters(AppState state) {
    final list = state.allMembers.where((m) => m.isRegular).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// kind('mentor'|'parent') 프로필을 [번호, 프로필] 목록으로 정렬 반환.
  List<MapEntry<String, Map<String, dynamic>>> _linkProfiles(String kind) {
    final out = <MapEntry<String, Map<String, dynamic>>>[];
    _profiles.forEach((k, v) {
      if (v is Map && (v['kind'] ?? 'mentor').toString() == kind) {
        out.add(MapEntry(k, v.cast<String, dynamic>()));
      }
    });
    out.sort((a, b) => '${a.value['name']}'.compareTo('${b.value['name']}'));
    return out;
  }

  // ---- 받는분 인가번호/생성년월 셀 (인라인 수정) ----
  Widget _receiverCell(Map<String, dynamic> prof) {
    final state = context.read<AppState>();
    final receiverNo = '${prof['receiverNo'] ?? ''}'.trim();
    final created = _ym('${prof['updatedAt'] ?? ''}');
    final canEdit = state.isApp || state.isMaster;
    if (!canEdit) {
      return Text(
        receiverNo.isNotEmpty ? receiverNo : created,
        style: TextStyle(
          fontSize: 12,
          fontWeight: receiverNo.isNotEmpty ? FontWeight.w800 : FontWeight.w500,
          color: receiverNo.isNotEmpty
              ? AppColors.textDark
              : AppColors.textGray,
        ),
      );
    }
    return InkWell(
      onTap: () => _editReceiver(prof),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            receiverNo.isNotEmpty ? receiverNo : created,
            style: TextStyle(
              fontSize: 12,
              fontWeight: receiverNo.isNotEmpty
                  ? FontWeight.w800
                  : FontWeight.w500,
              color: receiverNo.isNotEmpty
                  ? AppColors.textDark
                  : AppColors.textGray,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.edit, size: 13, color: AppColors.purpleLight),
        ],
      ),
    );
  }

  Future<void> _editReceiver(Map<String, dynamic> prof) async {
    final nas = context.read<AppState>().nas;
    final ctrl = TextEditingController(text: '${prof['receiverNo'] ?? ''}');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('받는분의 범인가번호 — ${prof['name'] ?? ''}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '받는분의 범인가번호',
                hintText: '예: 2186 (비우면 생성년월로 표시)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '생성년월: ${_ym('${prof['updatedAt'] ?? ''}')}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (r == null) return;
    // 취소(null)와 빈값('') 구분: 빈값은 삭제(생성년월 대체).
    setState(() => _busy = true);
    try {
      final res = await nas.linkProfileSetReceiver(
        number: '${prof['number'] ?? ''}',
        receiverNo: r,
      );
      if (!mounted) return;
      if (res['ok'] == true) {
        _snack('저장했습니다');
        await _refresh();
      } else {
        _snack('저장 실패');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMaster = state.isMaster;

    if (!(state.isApp || state.isMaster)) {
      return Scaffold(
        appBar: TsakAppBar(
          leading: const AppBackButton(label: '뒤로'),
          leadingWidth: 84,
          title: const Text('명부관리'),
        ),
        body: const Center(child: Text('관리자 권한이 필요합니다')),
      );
    }

    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('명부관리'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: HsTabStrip(
            controller: _tab,
            labels: ['범인가자', '멘토 대장', '페런츠', '서포터즈', if (isMaster) '관리자'],
            bg: AppColors.purple,
          ),
        ),
      ),
      body: Stack(
        children: [
          _body(state, isMaster),
          if (_busy) const BusyOverlay(visible: true),
        ],
      ),
    );
  }

  Widget _body(AppState state, bool isMaster) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 44,
              color: AppColors.tigerGold,
            ),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _refresh, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    return TabBarView(
      controller: _tab,
      children: [
        _credentialTable(state),
        _linkTable(state, 'mentor'),
        _linkTable(state, 'parent'),
        _supporterTable(state),
        if (isMaster) _adminTable(),
      ],
    );
  }

  // ---- 공통 테이블 래퍼 (좌측 선택창 + 선택/모두 출력) ----
  Widget _tableWrap(
    String title,
    List<String> headers,
    List<List<Widget>> rows, {
    List<List<String>>? textRows,
  }) {
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '표시할 명부가 없습니다.',
            style: TextStyle(color: AppColors.textGray),
          ),
        ),
      );
    }
    final texts = textRows ?? _extractText(headers, rows);
    final keys = [for (var i = 0; i < rows.length; i++) 'r$i'];
    return Padding(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final wide = c.maxWidth >= 760;
          final panel = _selPanel(title, headers, texts, keys);
          final table = _tableView(headers, rows);
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 240, child: panel),
                const SizedBox(width: 10),
                Expanded(child: table),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [panel, const SizedBox(height: 10), table],
          );
        },
      ),
    );
  }

  /// 위젯 행에서 텍스트만 추출(엑셀/CSV용).
  List<List<String>> _extractText(
    List<String> headers,
    List<List<Widget>> rows,
  ) {
    String cell(Widget w) {
      if (w is Text) return w.data ?? '';
      if (w is Row) {
        final t = w.children.whereType<Text>().firstOrNull;
        return t?.data ?? '';
      }
      if (w is InkWell) {
        final ch = w.child;
        return ch == null ? '' : cell(ch);
      }
      return '';
    }

    return [
      for (final r in rows) [for (final w in r) cell(w)],
    ];
  }

  /// 좌측 「선택 창」 — 항목 선택 + 선택 명단 출력 / 모두 출력.
  Widget _selPanel(
    String title,
    List<String> headers,
    List<List<String>> texts,
    List<String> keys,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, size: 16, color: AppColors.purple),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  '선택 창',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AppColors.purpleDark,
                  ),
                ),
              ),
              Text(
                '${_sel.length}명',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purpleDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: () => setState(() {
                  _selMode = true;
                  _sel
                    ..clear()
                    ..addAll(keys);
                }),
                child: const Text('전체선택', style: TextStyle(fontSize: 11.5)),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: _sel.isEmpty
                    ? null
                    : () => setState(() => _sel.clear()),
                child: const Text('선택 해제', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
          const Divider(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: _busyBuilding
                  ? null
                  : () => _rosterOutput(
                      title,
                      headers,
                      texts,
                      selectedOnly: false,
                    ),
              icon: const Icon(Icons.ios_share, size: 16),
              label: const Text(
                '모두 출력 (형식)',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.purpleDark,
                padding: const EdgeInsets.symmetric(vertical: 10),
                side: BorderSide(
                  color: AppColors.purple.withValues(alpha: 0.35),
                ),
              ),
              onPressed: (_sel.isEmpty || _busyBuilding)
                  ? null
                  : () => _rosterOutput(
                      title,
                      headers,
                      texts,
                      selectedOnly: true,
                    ),
              icon: const Icon(Icons.print_outlined, size: 16),
              label: const Text(
                '선택 명단 출력',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch.adaptive(
                value: _selMode,
                onChanged: (v) => setState(() {
                  _selMode = v;
                  if (!v) _sel.clear();
                }),
              ),
              const Text(
                '개별 선택',
                style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
              ),
            ],
          ),
          if (_selMode) ...[
            const Divider(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < texts.length; i++)
                      _selItem(keys[i], texts[i], i),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _selItem(String key, List<String> row, int idx) {
    final on = _sel.contains(key);
    // 0=번호, 1=인가번호, 2=이름 순서를 가정(Live) — 없으면 앞 두 칸.
    final no = row.isNotEmpty ? row[0] : '${idx + 1}';
    final name = row.length > 2 ? row[2] : (row.length > 1 ? row[1] : '');
    return InkWell(
      onTap: () => setState(() {
        if (on) {
          _sel.remove(key);
        } else {
          _sel.add(key);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Checkbox(
              value: on,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (_) => setState(() {
                if (on) {
                  _sel.remove(key);
                } else {
                  _sel.add(key);
                }
              }),
            ),
            Expanded(
              child: Text(
                '$no  $name',
                style: const TextStyle(fontSize: 11.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tableView(List<String> headers, List<List<Widget>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFFF6F4F1),
            child: Row(
              children: [
                Text(
                  '총 ${rows.length}명',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.purple,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _copyTsv(headers, rows),
                  icon: const Icon(Icons.copy_all, size: 15),
                  label: const Text('표 복사', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return ScrollArrows(
                    step: 220,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          const Color(0xFFF6F4F1),
                        ),
                        headingTextStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.purple,
                        ),
                        dataTextStyle: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDark,
                        ),
                        horizontalMargin: 12,
                        columnSpacing: 16,
                        columns: [
                          for (final h in headers) DataColumn(label: Text(h)),
                        ],
                        rows: [
                          for (final r in rows)
                            DataRow(cells: [for (final c in r) DataCell(c)]),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 명부를 공용 출력 시트로 출력(선택/모두) — 실시간 진행 대기창 포함.
  Future<void> _rosterOutput(
    String title,
    List<String> headers,
    List<List<String>> texts, {
    required bool selectedOnly,
  }) async {
    final rows = selectedOnly
        ? [
            for (var i = 0; i < texts.length; i++)
              if (_sel.contains('r$i')) texts[i],
          ]
        : texts;
    if (rows.isEmpty) {
      _snack(selectedOnly ? '선택된 명단이 없습니다' : '출력할 명단이 없습니다');
      return;
    }
    await showTsakOutputSheet(
      context,
      title: title,
      subtitle: selectedOnly ? '선택 ${rows.length}명' : '전체 ${rows.length}명',
      onPick: (f) => _runRosterOutput(title, headers, rows, f),
      onPrint: () => _runRosterOutput(
        title,
        headers,
        rows,
        TsakOutputFormat.pdf,
        justPrint: true,
      ),
      onEmail: () => _emailRoster(title, headers, rows),
      onShareLink: () => showLinkShareDialog(context, Uri.base.toString()),
    );
  }

  Future<void> _runRosterOutput(
    String title,
    List<String> headers,
    List<List<String>> rows,
    TsakOutputFormat format, {
    bool justPrint = false,
  }) async {
    final doc = TsakTableDoc(
      title: title,
      subtitle: '한국범스카우트중앙회 · 명부관리',
      description: '인가자 명부 출력물입니다.',
      columns: headers,
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · 마스터 전용',
    );
    setState(() => _busyBuilding = true);
    try {
      await runWithTsakProgress(
        context,
        title: justPrint ? '명부 프린트 준비' : '명부 ${format.label} 생성',
        note: '${rows.length}명 명단을 처리합니다.',
        steps: justPrint
            ? const ['문서 구성', '인쇄 창 열기']
            : ['문서 구성', '${format.label} 생성', '파일 저장'],
        task: (ctl) async {
          ctl.update(progress: 0.15, message: '문서를 구성하는 중…', stepIndex: 0);
          if (justPrint) {
            ctl.update(progress: 0.6, message: '인쇄 창을 여는 중…', stepIndex: 1);
            await printTsakTable(doc);
            ctl.update(progress: 1.0, stepIndex: 2);
            return;
          }
          ctl.update(
            progress: 0.5,
            message: '${format.label} 생성 중…',
            stepIndex: 1,
          );
          await saveTsakTable(context, doc, format, askLocation: false);
          ctl.update(progress: 1.0, message: '완료', stepIndex: 2);
        },
      );
      if (mounted)
        _snack(justPrint ? '인쇄 창을 열었습니다' : '${format.label} 저장을 시작했습니다');
    } catch (e) {
      if (mounted) _snack('출력 실패: $e');
    } finally {
      if (mounted) setState(() => _busyBuilding = false);
    }
  }

  Future<void> _emailRoster(
    String title,
    List<String> headers,
    List<List<String>> rows,
  ) async {
    final doc = TsakTableDoc(
      title: title,
      subtitle: '한국범스카우트중앙회 · 명부관리',
      columns: headers,
      rows: rows,
      summary: ['총 ${rows.length}명'],
    );
    await emailTsakTable(context, doc);
  }

  Future<void> _copyTsv(List<String> headers, List<List<Widget>> rows) async {
    // 위젯에서 텍스트만 추출해 탭 구분 텍스트로 복사(엑셀 붙여넣기용).
    final buf = StringBuffer(headers.join('\t'));
    buf.writeln();
    for (final r in rows) {
      final cells = r.map((w) {
        if (w is Text) return w.data ?? '';
        if (w is Row) {
          final t = w.children.whereType<Text>().firstOrNull;
          return t?.data ?? '';
        }
        return '';
      });
      buf.writeln(cells.join('\t'));
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    _snack('명부를 복사했습니다 (엑셀에 붙여넣기)');
  }

  Widget _t(String s, {bool bold = false}) => Text(
    s,
    style: TextStyle(
      fontSize: 12,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      color: bold ? AppColors.textDark : AppColors.textDark,
    ),
  );

  // ---- 1. 범스카우트 인가자 명부 ----
  Widget _credentialTable(AppState state) {
    final list = _credentialMembers(state);
    final headers = ['#', '범인가번호', '아타스인가번호', '이름', '연락처', '소속'];
    final rows = <List<Widget>>[];
    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      final contact = m.phone.trim().isNotEmpty ? m.phone : m.tel;
      rows.add([
        _t('${i + 1}'),
        _t(m.number, bold: true),
        _t(m.atasNo),
        _t(m.name, bold: true),
        _t(contact),
        _t(_org(m.league, m.unit)),
      ]);
    }
    return _tableWrap('범스카우트 인가자 명부', headers, rows);
  }

  // ---- 2/3. 멘토 대장 · 페런츠 명부 ----
  Widget _linkTable(AppState state, String kind) {
    final list = _linkProfiles(kind);
    final headers = ['#', '범인가번호', '이름', '연락처', '아이디', '소속'];
    final rows = <List<Widget>>[];
    for (var i = 0; i < list.length; i++) {
      final prof = list[i].value;
      // 자동생성 아이디(수품구매시 입력한 인적사항의 전화번호 기반).
      final loginId = '${prof['loginId'] ?? ''}'.trim();
      rows.add([
        _t('${i + 1}'),
        _receiverCell(prof),
        _t('${prof['name'] ?? ''}', bold: true),
        _t('${prof['phone'] ?? ''}'),
        _t(loginId.isEmpty ? '—' : loginId),
        _t(_org('${prof['league'] ?? ''}', '${prof['unit'] ?? ''}')),
      ]);
    }
    return _tableWrap(kind == 'mentor' ? '멘토 대장 명부' : '페런츠 명부', headers, rows);
  }

  // ---- 4. 서포터즈 ----
  Widget _supporterTable(AppState state) {
    final list = _supporters(state);
    final headers = ['#', '아이디생성년월', '이름', '전화번호', '소속'];
    final rows = <List<Widget>>[];
    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      // 아이디(계정) 생성년월 — 서버가 저장 시 부여한 createdAt(updatedAt) 기준.
      final created = _ym(
        m.updatedAt != null
            ? '${m.updatedAt!.year}.${m.updatedAt!.month.toString().padLeft(2, '0')}'
            : '',
      );
      final phone = m.phone.trim().isNotEmpty ? m.phone : m.accessPhone;
      rows.add([
        _t('${i + 1}'),
        _t(created),
        _t(m.name, bold: true),
        _t(phone),
        _t(_org(m.league, m.unit)),
      ]);
    }
    return _tableWrap('서포터즈 명부', headers, rows);
  }

  // ---- 5. 관리자 명부 (마스터만) ----
  Widget _adminTable() {
    final list = (_adminInfo['admins'] as List?) ?? const [];
    final headers = ['#', '범인가번호', '이름', '연락처', '소속', '권한부여일'];
    final rows = <List<Widget>>[];
    for (var i = 0; i < list.length; i++) {
      final a = (list[i] as Map).cast<String, dynamic>();
      rows.add([
        _t('${i + 1}'),
        _t('${a['number'] ?? ''}', bold: true),
        _t('${a['name'] ?? ''}', bold: true),
        _t('${a['phone'] ?? ''}'),
        _t(_org('${a['league'] ?? ''}', '${a['unit'] ?? ''}')),
        _t('${a['grantedAt'] ?? ''}'),
      ]);
    }
    return _tableWrap('관리자 명부', headers, rows);
  }
}
