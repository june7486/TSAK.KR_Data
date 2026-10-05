import 'package:flutter/material.dart';
import '../widgets/marquee_text.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/file_save.dart';
import '../services/output_formats.dart';
import '../services/table_export.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/tsak_detail_sheet.dart';
import '../widgets/tsak_output_sheet.dart';
import '../widgets/tsak_table_options.dart';

/// 로그 확인 — 전체 회원 접속·열람 기록 (마스터 전용).
///
/// 요구사항(p.11): 회원접속기록은 마스터만 열람 가능.
///  · 로그인/열람 이벤트를 최신순으로 통합 표시
///  · 역할(마스터/관리자/인가자/비인가자)·구분(본인/타인)·기기·IP 표시
///  · 이벤트/역할/검색 필터 + 출력(PDF)·공유·CSV 내보내기
///  · 개별 삭제 / 선택 삭제 / 전체 삭제(마스터 전용)
class AccessLogScreen extends StatefulWidget {
  const AccessLogScreen({super.key});

  @override
  State<AccessLogScreen> createState() => _AccessLogScreenState();
}

class _AccessLogScreenState extends State<AccessLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _busy = false;

  /// 이벤트 필터: '' 전체 | 'login' 로그인 | 'view' 열람.
  String _eventFilter = '';

  /// 역할 필터: '' 전체 | master/app/personal/guest.
  String _tierFilter = '';

  /// 검색어(이름·신원·기기·IP).
  final TextEditingController _qCtl = TextEditingController();

  /// 선택 삭제 모드.
  bool _selectMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _qCtl.dispose();
    super.dispose();
  }

  String _key(Map<String, dynamic> l) =>
      '${l['ts'] ?? ''}\u0000${l['ident'] ?? ''}\u0000${l['event'] ?? ''}';

  List<Map<String, dynamic>> get _filtered {
    final q = _qCtl.text.trim().toLowerCase();
    return _logs.where((l) {
      final ev = '${l['event'] ?? ''}';
      if (_eventFilter.isNotEmpty && ev != _eventFilter) return false;
      final tier = '${l['tier'] ?? ''}';
      if (_tierFilter.isNotEmpty && tier != _tierFilter) return false;
      if (q.isNotEmpty) {
        final hay = [
          l['name'],
          l['who'],
          l['ident'],
          l['viewer'],
          l['device'],
          l['ip'],
          l['role'],
        ].map((e) => '${e ?? ''}').join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (!state.isMaster) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final logs = await state.fetchAllAccessLogs(limit: 500);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
      _selected.clear();
    });
  }

  // ---------------- 삭제 ----------------
  Future<void> _deleteOne(Map<String, dynamic> log) async {
    final ok = await _confirm('이 기록 1건을 삭제할까요?');
    if (ok != true) return;
    final done = await context.read<AppState>().deleteMemberAccessLog(
      mode: 'one',
      ts: '${log['ts'] ?? ''}',
      number: '${log['ident'] ?? ''}',
    );
    if (!mounted) return;
    _snack(done ? '삭제했습니다' : '삭제 실패');
    if (done) await _load();
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await _confirm('선택한 기록 ${_selected.length}건을 삭제할까요?');
    if (ok != true) return;
    final items = <Map<String, dynamic>>[];
    for (final l in _logs) {
      if (_selected.contains(_key(l))) {
        items.add({'ts': '${l['ts'] ?? ''}', 'ident': '${l['ident'] ?? ''}'});
      }
    }
    final done = await context.read<AppState>().deleteMemberAccessLog(
      mode: 'bulk',
      items: items,
    );
    if (!mounted) return;
    _snack(done ? '선택한 ${items.length}건을 삭제했습니다' : '삭제 실패');
    if (done) {
      setState(() {
        _selectMode = false;
        _selected.clear();
      });
      await _load();
    }
  }

  Future<void> _deleteAll() async {
    final ok = await _confirm('전체 접속 기록을 모두 삭제할까요? 이 작업은 되돌릴 수 없습니다.');
    if (ok != true) return;
    final done = await context.read<AppState>().deleteMemberAccessLog(
      mode: 'all',
    );
    if (!mounted) return;
    _snack(done ? '전체 접속 기록을 삭제했습니다' : '삭제 실패');
    if (done) await _load();
  }

  Future<bool?> _confirm(String msg) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('접속 기록 삭제'),
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.taegeukRed),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------- 출력 옵션 / 출력 / 공유 / 내보내기 ----------------
  /// 출력 옵션(출력내용선택·위치이동·글씨크기·줄간격·용지) — 명부출력과 동일.
  TableOutputOptions? _outOpts;

  /// 접속기록 표준 컬럼(명부출력과 동일 규칙: 앞 열 순서 유지).
  static const List<String> _logCols = [
    '일시',
    '구분',
    '이벤트',
    '역할',
    '대상',
    '열람자',
    '기기',
    'IP',
  ];

  /// 현재 필터(및 선택 여부)를 반영한 접속기록 문서.
  TsakTableDoc _accessDoc({required bool selectedOnly}) {
    final src = selectedOnly
        ? [
            for (final l in _filtered)
              if (_selected.contains(_key(l))) l,
          ]
        : _filtered;
    final rows = <List<String>>[
      for (final l in src)
        [
          '${l['ts'] ?? ''}',
          l['self'] == true ? '본인' : '타인',
          '${l['event'] ?? ''}' == 'view' ? '열람' : '로그인',
          '${l['role'] ?? l['tier'] ?? ''}',
          '${l['name'] ?? ''}',
          '${l['viewer'] ?? ''}',
          '${l['device'] ?? ''}',
          '${l['ip'] ?? ''}',
        ],
    ];
    return TsakTableDoc(
      title: selectedOnly ? 'TSAK 회원 접속·열람 기록 (선택)' : 'TSAK 회원 접속·열람 기록',
      subtitle: '한국범스카우트중앙회 · 마스터 전용',
      description: '회원 로그인·열람 이력을 최신순으로 통합한 기록입니다.',
      author: '마스터',
      extra: {
        '건수': selectedOnly ? '선택 ${rows.length}건' : '전체 ${rows.length}건',
        if (_eventFilter.isNotEmpty)
          '이벤트': _eventFilter == 'view' ? '열람' : '로그인',
        if (_tierFilter.isNotEmpty) '역할': _tierFilter,
      },
      columns: _logCols,
      rows: rows,
      summary: ['총 ${rows.length}건'],
      footerLeft: '한국범스카우트중앙회 · 마스터 전용',
      options: _outOpts,
    );
  }

  /// 출력 옵션 편집 — 명부출력과 동일한 화면(출력내용선택·위치이동·줄간격·글씨·용지).
  Future<void> _editOptions() async {
    final out = await showTsakTableOptions(
      context,
      title: '접속기록 출력 옵션',
      subtitle: '출력할 항목을 고르고, 순서를 옮기고, 줄 간격·글씨·용지를 정하세요.',
      columns: _logCols,
      initial: _outOpts,
    );
    if (out != null && mounted) {
      setState(() => _outOpts = out);
      _snack('출력 옵션을 저장했습니다 · ${out.badge}');
    }
  }

  /// 선택 개수를 구한다(선택 출력 안내용).
  int _selectedInFiltered() =>
      _filtered.where((l) => _selected.contains(_key(l))).length;

  /// 출력 시트를 연다 — 명부 '모두 출력 / 선택 명단 출력' 과 동일한 포맷.
  ///
  /// 규칙(#14): 카드 선택 시 저장, 카드 위 열기/공유 버튼으로 **모든 포맷**을
  /// 외부 프로그램(뷰어·인쇄·OS 공유 시트)으로 내보낸다. 아이폰에서도 저장/출력
  /// 시 **OS 공유 시트**가 열려 카톡·메일·드라이브·파일앱으로 바로 보낼 수 있다.
  Future<void> _openOutputSheet({required bool selectedOnly}) async {
    final rowsN = selectedOnly ? _selectedInFiltered() : _filtered.length;
    if (rowsN == 0) {
      _snack(selectedOnly ? '선택된 접속기록이 없습니다' : '출력할 접속기록이 없습니다');
      return;
    }
    await showTsakOutputSheet(
      context,
      title: selectedOnly ? '접속기록 선택 출력' : '접속기록 출력',
      subtitle: selectedOnly ? '선택 $rowsN건' : '전체 $rowsN건',
      onPick: (f) => _runOutput(selectedOnly: selectedOnly, format: f),
      // 모든 포맷 → 외부 프로그램/뷰어로 열기.
      onOpen: (f) =>
          _runOutput(selectedOnly: selectedOnly, format: f, open: true),
      // 모든 포맷 → OS 공유 시트(아이폰 포함 카톡·메일·드라이브로 바로 전송).
      onShareFormat: (f) =>
          _runOutput(selectedOnly: selectedOnly, format: f, share: true),
      onPrint: () => _runOutput(
        selectedOnly: selectedOnly,
        format: TsakOutputFormat.pdf,
        justPrint: true,
      ),
      onEmail: () => _emailOutput(selectedOnly: selectedOnly),
      onShare: () => _runOutput(
        selectedOnly: selectedOnly,
        format: TsakOutputFormat.pdf,
        share: true,
      ),
      onOptions: _editOptions,
      onShareImage: () => _runOutput(
        selectedOnly: selectedOnly,
        format: TsakOutputFormat.jpg,
        share: true,
      ),
      onShareLink: () => showLinkShareDialog(context, Uri.base.toString()),
    );
  }

  /// 접속기록을 지정 형식으로 만들어 저장/열기/공유/프린트한다(진행 대기창 포함).
  Future<void> _runOutput({
    required bool selectedOnly,
    required TsakOutputFormat format,
    bool open = false,
    bool share = false,
    bool justPrint = false,
  }) async {
    final doc = _accessDoc(selectedOnly: selectedOnly);
    if (doc.rows.isEmpty) {
      _snack('출력할 접속기록이 없습니다');
      return;
    }
    // 1) 저장 위치를 **진행창 이전에** 먼저 확정(명부출력과 동일 규칙).
    var choose = false;
    if (!open && !share && !justPrint) {
      final loc = await askTsakSaveLocation(
        context,
        info:
            '접속기록 · ${selectedOnly ? '선택 ${doc.rows.length}건' : '전체 ${doc.rows.length}건'} · ${format.label}',
      );
      if (loc == null) {
        if (mounted) _snack('저장을 취소했습니다');
        return;
      }
      choose = loc;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await runWithTsakProgress(
        context,
        title: justPrint
            ? '접속기록 프린트 준비'
            : open
            ? '접속기록 ${format.label} 외부 열기'
            : '접속기록 ${format.label} 파일 생성',
        note: '${doc.rows.length}건을 처리합니다.',
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
          if (open) {
            final res = await openTsakTableChosen(context, doc, format);
            if (mounted)
              _snack(tsakShareMessage(res, what: '접속기록 ${format.label}'));
          } else if (share) {
            final res = await shareTsakTableChosen(context, doc, format);
            if (mounted)
              _snack(tsakShareMessage(res, what: '접속기록 ${format.label}'));
          } else {
            final ok = await saveTsakTableChosen(
              context,
              doc,
              format,
              choose: choose,
            );
            if (ok && mounted) _snack('${format.label} 파일로 저장했습니다');
          }
          ctl.update(progress: 1.0, stepIndex: 2);
        },
      );
    } catch (e) {
      _snack('내보내기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 접속기록을 메일 본문으로 연다(명부출력과 동일).
  Future<void> _emailOutput({required bool selectedOnly}) async {
    final doc = _accessDoc(selectedOnly: selectedOnly);
    await emailTsakTable(context, doc);
  }

  /// CSV(엑셀) — 명부출력과 동일한 저장위치 선택 + 아이폰 공유 대응.
  ///
  /// 아이폰은 저장위치 API 미지원이므로 Web Share(OS 공유 시트)로 폴백한다.
  Future<void> _exportCsv() async {
    final doc = _accessDoc(selectedOnly: false);
    await _runOutput(selectedOnly: false, format: TsakOutputFormat.excel);
    if (doc.rows.isEmpty) return;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return Scaffold(
        appBar: TsakAppBar(title: const Text('로그 확인')),
        body: const Center(child: Text('마스터 권한이 필요합니다')),
      );
    }
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('로그 확인'),
        actions: [
          const AppHomeEmblem(size: 22),
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _header(),
              _filters(),
              if (_selectMode) _selectBar(filtered),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? const Center(
                        child: Text(
                          '접속 기록이 없습니다',
                          style: TextStyle(color: AppColors.textGray),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _logTile(filtered[i], i),
                        ),
                      ),
              ),
            ],
          ),
          BusyOverlay(
            visible: _loading || _busy,
            title: _busy ? '문서를 만드는 중입니다' : '접속기록을 불러오는 중입니다',
            lines: _busy
                ? const [
                    '선택한 접속기록으로 문서를 생성하고 있습니다...',
                    'PDF·엑셀 파일로 만드는 중...',
                    '저장·공유 준비 중...',
                  ]
                : const [
                    'NAS 서버에서 접속 기록을 가져오는 중...',
                    '최신 기록으로 정리하는 중...',
                    '잠시만 기다려 주세요...',
                  ],
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: AppColors.purple.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                size: 15,
                color: AppColors.lifetimeGold,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '접속·열람 기록은 마스터만 열람할 수 있습니다. 기기·시각·IP가 기록됩니다.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.lifetimeGold,
                  ),
                ),
              ),
              Text(
                '총 ${_logs.length}건',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // (요구) 명부출력과 동일 포맷 — 모든 포맷 저장/외부열기/공유 + 출력옵션.
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                ),
                onPressed: _busy || _filtered.isEmpty
                    ? null
                    : () => _openOutputSheet(selectedOnly: false),
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('출력/공유 (형식)'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || _selected.isEmpty
                    ? null
                    : () => _openOutputSheet(selectedOnly: true),
                icon: const Icon(Icons.checklist, size: 16),
                label: Text('선택 출력 (${_selected.length})'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || _filtered.isEmpty ? null : _exportCsv,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('CSV'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _editOptions,
                icon: const Icon(Icons.tune, size: 16),
                label: Text(
                  _outOpts == null ? '출력 옵션' : '출력 옵션 · ${_outOpts!.badge}',
                ),
              ),
              if (_filtered.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _selectMode
                        ? Colors.white
                        : AppColors.purple,
                    backgroundColor: _selectMode ? AppColors.purple : null,
                    side: BorderSide(
                      color: AppColors.purple.withValues(alpha: 0.6),
                    ),
                  ),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _selectMode = !_selectMode;
                          _selected.clear();
                        }),
                  icon: Icon(
                    _selectMode ? Icons.close : Icons.checklist,
                    size: 16,
                  ),
                  label: Text(_selectMode ? '선택 취소' : '선택 삭제'),
                ),
              if (_logs.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.taegeukRed,
                  ),
                  onPressed: _busy ? null : _deleteAll,
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text('전체 삭제'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qCtl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '이름 · 신원 · 기기 · IP 검색',
                    hintStyle: const TextStyle(fontSize: 12.5),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  '전체',
                  _eventFilter.isEmpty,
                  () => setState(() => _eventFilter = ''),
                ),
                _chip(
                  '로그인',
                  _eventFilter == 'login',
                  () => setState(() => _eventFilter = 'login'),
                ),
                _chip(
                  '열람',
                  _eventFilter == 'view',
                  () => setState(() => _eventFilter = 'view'),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 1,
                  height: 20,
                  color: AppColors.textGray.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 10),
                _chip(
                  '전체 역할',
                  _tierFilter.isEmpty,
                  () => setState(() => _tierFilter = ''),
                ),
                _chip(
                  '마스터',
                  _tierFilter == 'master',
                  () => setState(() => _tierFilter = 'master'),
                ),
                _chip(
                  '관리자',
                  _tierFilter == 'app',
                  () => setState(() => _tierFilter = 'app'),
                ),
                _chip(
                  '인가자',
                  _tierFilter == 'personal',
                  () => setState(() => _tierFilter = 'personal'),
                ),
                _chip(
                  '비인가자',
                  _tierFilter == 'guest',
                  () => setState(() => _tierFilter = 'guest'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.purple : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.purple
                  : AppColors.purple.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.purpleDark,
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectBar(List<Map<String, dynamic>> filtered) {
    final allSel =
        filtered.isNotEmpty &&
        filtered.every((l) => _selected.contains(_key(l)));
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '선택 ${_selected.length}건 / 표시 ${filtered.length}건',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.purple,
              ),
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    if (allSel) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(filtered.map(_key));
                    }
                  }),
            child: Text(
              allSel ? '전체 해제' : '전체 선택',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _busy || _selected.isEmpty ? null : _deleteSelected,
            icon: const Icon(Icons.delete, size: 15),
            label: Text('선택 ${_selected.length}건 삭제'),
          ),
        ],
      ),
    );
  }

  /// 한 로그의 상세를 시트로 표시(행 클릭).
  void _showLogDetail(Map<String, dynamic> l) {
    final tier = '${l['tier'] ?? ''}';
    final role = '${l['role'] ?? l['tier'] ?? ''}';
    final isView = '${l['event'] ?? ''}' == 'view';
    final isSelf = l['self'] == true;
    Color c = AppColors.purple;
    if (tier == 'master') c = AppColors.lifetimeGold;
    if (tier == 'app') c = AppColors.taegeukBlue;
    if (tier == 'guest') c = AppColors.scoutGreen;
    final rowColor = isSelf ? AppColors.taegeukRed : c;
    showTsakDetailSheet(
      context,
      title: '${l['name'] ?? '(이름없음)'}',
      subtitle: '${isView ? '열람' : '로그인'} · $role',
      icon: isView ? Icons.visibility_outlined : Icons.login,
      accent: rowColor,
      entries: tsakEntries([
        TsakDetailEntry(
          label: '구분',
          value: isView ? '열람' : '로그인',
          icon: isView ? Icons.visibility : Icons.login,
          color: isView ? AppColors.purple : AppColors.scoutGreen,
          copyable: false,
        ),
        TsakDetailEntry(
          label: '본인여부',
          value: isSelf ? '본인' : '타인',
          icon: Icons.person_outline,
          color: isSelf ? AppColors.taegeukRed : AppColors.textGray,
          copyable: false,
        ),
        TsakDetailEntry(label: '역할', value: role, icon: Icons.badge_outlined),
        TsakDetailEntry(
          label: '회원구분',
          value: tier,
          icon: Icons.groups_outlined,
        ),
        TsakDetailEntry(
          label: '열람대상',
          value: '${l['viewer'] ?? ''}',
          icon: Icons.person_search_outlined,
        ),
        TsakDetailEntry(
          label: '식별번호',
          value: '${l['ident'] ?? ''}',
          icon: Icons.tag,
          mono: true,
        ),
        TsakDetailEntry(label: '대상', value: '${l['who'] ?? ''}'),
        TsakDetailEntry(
          label: '기기',
          value: '${l['device'] ?? ''}',
          icon: Icons.devices_outlined,
        ),
        TsakDetailEntry(
          label: 'IP 주소',
          value: '${l['ip'] ?? ''}',
          icon: Icons.public,
          mono: true,
        ),
        TsakDetailEntry(
          label: '시각',
          value: '${l['ts'] ?? ''}',
          icon: Icons.schedule,
          mono: true,
        ),
      ]),
    );
  }

  Widget _logTile(Map<String, dynamic> l, int i) {
    final role = '${l['role'] ?? l['tier'] ?? ''}';
    final device = '${l['device'] ?? ''}';
    final ts = '${l['ts'] ?? ''}';
    final ip = '${l['ip'] ?? ''}';
    final tier = '${l['tier'] ?? ''}';
    final name = '${l['name'] ?? ''}';
    final isSelf = l['self'] == true;
    final isView = '${l['event'] ?? ''}' == 'view';
    final viewer = '${l['viewer'] ?? ''}'.trim();
    Color c = AppColors.purple;
    if (tier == 'master') c = AppColors.lifetimeGold;
    if (tier == 'app') c = AppColors.taegeukBlue;
    if (tier == 'guest') c = AppColors.scoutGreen;
    final Color rowColor = isSelf ? AppColors.taegeukRed : c;
    final bool selected = _selectMode && _selected.contains(_key(l));
    final Widget tile = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.purple.withValues(alpha: 0.10)
            : (isSelf
                  ? rowColor.withValues(alpha: 0.07)
                  : (i.isEven ? const Color(0xFFF8F6FC) : Colors.white)),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected
              ? AppColors.purple
              : (isSelf
                    ? rowColor.withValues(alpha: 0.45)
                    : AppColors.purple.withValues(alpha: 0.12)),
          width: selected ? 1.6 : (isSelf ? 1.4 : 1),
        ),
      ),
      child: Row(
        children: [
          // 좌측 선택박스 — 상시 노출(체크 시 선택모드 자동 진입).
          Checkbox(
            value: selected,
            visualDensity: VisualDensity.compact,
            activeColor: AppColors.purple,
            onChanged: (_) => setState(() {
              if (selected) {
                _selected.remove(_key(l));
                if (_selected.isEmpty) _selectMode = false;
              } else {
                _selected.add(_key(l));
                _selectMode = true;
              }
            }),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: rowColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              role.isEmpty ? '-' : role,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: rowColor,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: (isView ? AppColors.purple : AppColors.scoutGreen)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isView ? '열람' : '로그인',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isView ? AppColors.purple : AppColors.scoutGreen,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 12,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      ts,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelf ? FontWeight.w900 : FontWeight.w700,
                        color: isSelf
                            ? AppColors.taegeukRed
                            : AppColors.textDark,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.taegeukRed,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          '본인 접속',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (name.isNotEmpty || (isView && viewer.isNotEmpty)) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        isView ? Icons.visibility : Icons.person,
                        size: 12,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: MarqueeText(
                          isView
                              ? '대상 ${name.isEmpty ? '(${l['ident'] ?? ''})' : name}'
                                    '${viewer.isNotEmpty ? '  ·  열람자 $viewer' : ''}'
                              : (name.isEmpty
                                    ? '(${l['who'] ?? l['ident'] ?? ''})'
                                    : name),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelf
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelf
                                ? AppColors.taegeukRed
                                : AppColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.devices_other,
                      size: 12,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: MarqueeText(
                        device,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelf
                              ? FontWeight.w800
                              : FontWeight.w400,
                          color: isSelf
                              ? AppColors.taegeukRed
                              : AppColors.textDark,
                        ),
                      ),
                    ),
                    if (ip.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.public,
                        size: 11,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        ip,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '이 기록 삭제',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: AppColors.taegeukRed,
            ),
            onPressed: () => _deleteOne(l),
          ),
        ],
      ),
    );
    // 행 클릭 → 상세 시트 (선택은 좌측 체크박스로).
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => _showLogDetail(l),
      child: tile,
    );
  }
}
