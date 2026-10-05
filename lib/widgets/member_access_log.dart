import 'package:flutter/material.dart';
import 'marquee_text.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/file_save.dart';
import '../services/output_formats.dart';
import '../services/table_export.dart';
import '../theme/app_theme.dart';
import 'tsak_output_sheet.dart';
import 'tsak_table_options.dart';

/// 회원 접속 로그 — 마스터 전용.
///
/// 요구사항:
///  · 개인 페이지 하단에 최근 100건까지 표시
///  · 접속기기이름·시각·IP·역할 등 구체 정보 표시
///  · 출력 / 공유 / 파일로 내보내기 버튼
///  · 각 로그마다 삭제 버튼
class MemberAccessLogSection extends StatefulWidget {
  const MemberAccessLogSection({super.key, required this.member});

  final Member member;

  @override
  State<MemberAccessLogSection> createState() => _MemberAccessLogSectionState();
}

class _MemberAccessLogSectionState extends State<MemberAccessLogSection> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _busy = false;

  /// 선택 삭제 모드 — 마스터가 원하는 기록만 골라 지울 수 있다.
  bool _selectMode = false;

  /// 선택된 로그의 고유키 (ts + '\u0000' + ident).
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _key(Map<String, dynamic> l) =>
      '${l['ts'] ?? ''}\u0000${(l['ident'] ?? widget.member.loginId) ?? ''}';

  String get _title => '${widget.member.name} (${widget.member.loginId})';

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (!state.isMaster) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final logs = await state.fetchMemberAccessLog(widget.member.loginId);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
      _selected.clear();
    });
  }

  Future<void> _deleteOne(Map<String, dynamic> log) async {
    final ok = await _confirm('이 접속 기록 1건을 삭제할까요?');
    if (ok != true) return;
    final done = await context.read<AppState>().deleteMemberAccessLog(
      mode: 'one',
      ts: '${log['ts'] ?? ''}',
      number: widget.member.loginId,
    );
    if (!mounted) return;
    _snack(done ? '삭제했습니다' : '삭제 실패');
    if (done) await _load();
  }

  /// 선택한 기록들을 한 번에 삭제한다(마스터 전용, 선택 삭제).
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await _confirm('선택한 접속 기록 ${_selected.length}건을 삭제할까요?');
    if (ok != true) return;
    final items = <Map<String, dynamic>>[];
    for (final l in _logs) {
      if (_selected.contains(_key(l))) {
        items.add({
          'ts': '${l['ts'] ?? ''}',
          'ident': '${l['ident'] ?? widget.member.loginId}',
        });
      }
    }
    final done = await context.read<AppState>().deleteMemberAccessLog(
      mode: 'bulk',
      number: widget.member.loginId,
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
    final ok = await _confirm(
      '${widget.member.name} 님의 접속 기록을 모두(최근 100건 대상) 삭제할까요?',
    );
    if (ok != true) return;
    final done = await context.read<AppState>().deleteMemberAccessLog(
      mode: 'member',
      number: widget.member.loginId,
    );
    if (!mounted) return;
    _snack(done ? '회원 접속 기록을 삭제했습니다' : '삭제 실패');
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

  /// 회원 접속기록 표준 컬럼(명부출력과 동일 규칙).
  static const List<String> _logCols = [
    '일시',
    '구분',
    '이벤트',
    '역할',
    '열람자',
    '기기',
    'IP',
  ];

  /// 본 회원의 접속기록 문서(선택 여부 반영).
  TsakTableDoc _accessDoc({required bool selectedOnly}) {
    final src = selectedOnly
        ? [
            for (final l in _logs)
              if (_selected.contains(_key(l))) l,
          ]
        : _logs;
    final rows = <List<String>>[
      for (final l in src)
        [
          '${l['ts'] ?? ''}',
          l['self'] == true ? '본인' : '타인',
          '${l['event'] ?? ''}' == 'view' ? '열람' : '로그인',
          '${l['role'] ?? l['tier'] ?? ''}',
          '${l['viewer'] ?? ''}',
          '${l['device'] ?? ''}',
          '${l['ip'] ?? ''}',
        ],
    ];
    return TsakTableDoc(
      title: selectedOnly ? '회원 접속 기록 (선택)' : '회원 접속 기록',
      subtitle: '한국범스카우트중앙회 · 마스터 전용',
      description: '$_title 회원의 접속·열람 기록입니다.',
      author: '마스터',
      extra: {
        '대상': _title,
        '건수': selectedOnly ? '선택 ${rows.length}건' : '전체 ${rows.length}건',
      },
      columns: _logCols,
      rows: rows,
      summary: ['총 ${rows.length}건'],
      footerLeft: '한국범스카우트중앙회 · 마스터 전용',
      options: _outOpts,
    );
  }

  /// 출력 옵션 편집 — 명부출력과 동일 화면.
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

  /// 출력 시트 — 명부출력과 동일 포맷(모든 포맷 저장/열기/공유 + 출력옵션).
  Future<void> _openOutputSheet({bool selectedOnly = false}) async {
    final rowsN = selectedOnly
        ? _logs.where((l) => _selected.contains(_key(l))).length
        : _logs.length;
    if (rowsN == 0) {
      _snack(selectedOnly ? '선택된 기록이 없습니다' : '출력할 기록이 없습니다');
      return;
    }
    await showTsakOutputSheet(
      context,
      title: selectedOnly ? '회원 접속기록 선택 출력' : '회원 접속기록 출력',
      subtitle: selectedOnly ? '선택 $rowsN건' : '전체 $rowsN건',
      onPick: (f) => _runOutput(selectedOnly: selectedOnly, format: f),
      onOpen: (f) =>
          _runOutput(selectedOnly: selectedOnly, format: f, open: true),
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

  /// 지정 형식으로 저장/열기/공유/프린트(진행 대기창 포함) — 명부출력과 동일.
  Future<void> _runOutput({
    required bool selectedOnly,
    required TsakOutputFormat format,
    bool open = false,
    bool share = false,
    bool justPrint = false,
  }) async {
    final doc = _accessDoc(selectedOnly: selectedOnly);
    if (doc.rows.isEmpty) {
      _snack('출력할 기록이 없습니다');
      return;
    }
    var choose = false;
    if (!open && !share && !justPrint) {
      final loc = await askTsakSaveLocation(
        context,
        info: '회원 접속기록 · ${format.label}',
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

  /// 메일 본문으로 열기(명부출력과 동일).
  Future<void> _emailOutput({required bool selectedOnly}) async {
    final doc = _accessDoc(selectedOnly: selectedOnly);
    await emailTsakTable(context, doc);
  }

  /// CSV(엑셀) — 저장위치 선택 + 아이폰 공유 대응.
  Future<void> _exportCsv() async {
    await _runOutput(selectedOnly: false, format: TsakOutputFormat.excel);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 19, color: AppColors.purple),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '회원 접속·열람 기록 (최근 100건)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                IconButton(
                  tooltip: '새로고침',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.tigerGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 14,
                    color: AppColors.lifetimeGold,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '접속 기록은 마스터만 열람할 수 있습니다. 접속기기·시각·IP가 기록됩니다.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.lifetimeGold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 출력 / 공유 / 내보내기 / 선택삭제 / 전체삭제
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // (요구) 명부출력과 동일 포맷 — 모든 포맷 저장/외부열기/공유 + 옵션.
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                  ),
                  onPressed: _busy || _logs.isEmpty
                      ? null
                      : () => _openOutputSheet(),
                  icon: const Icon(Icons.ios_share, size: 17),
                  label: const Text('출력/공유 (형식)'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _selected.isEmpty
                      ? null
                      : () => _openOutputSheet(selectedOnly: true),
                  icon: const Icon(Icons.checklist, size: 17),
                  label: Text('선택 출력 (${_selected.length})'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _logs.isEmpty ? null : _exportCsv,
                  icon: const Icon(Icons.download, size: 17),
                  label: const Text('CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _editOptions,
                  icon: const Icon(Icons.tune, size: 17),
                  label: Text(
                    _outOpts == null ? '출력 옵션' : '출력 옵션 · ${_outOpts!.badge}',
                  ),
                ),
                if (_logs.isNotEmpty)
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
                      size: 17,
                    ),
                    label: Text(_selectMode ? '선택 취소' : '선택 삭제'),
                  ),
                if (_logs.isNotEmpty)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.taegeukRed,
                    ),
                    onPressed: _busy ? null : _deleteAll,
                    icon: const Icon(Icons.delete_sweep, size: 17),
                    label: const Text('기록 전체 삭제'),
                  ),
              ],
            ),
            // 선택 삭제 모드일 때 표시되는 선택 툴바
            if (_selectMode && _logs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: AppColors.purple.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '선택 ${_selected.length}건 / 전체 ${_logs.length}건',
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
                              if (_selected.length == _logs.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(_logs.map(_key));
                              }
                            }),
                      child: Text(
                        _selected.length == _logs.length ? '전체 해제' : '전체 선택',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.taegeukRed,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : _deleteSelected,
                      icon: const Icon(Icons.delete, size: 16),
                      label: Text('선택 ${_selected.length}건 삭제'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(
                    '접속 기록이 없습니다',
                    style: TextStyle(color: AppColors.textGray, fontSize: 12.5),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _logs.length,
                itemBuilder: (_, i) => _logTile(_logs[i], i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _logTile(Map<String, dynamic> l, int i) {
    final role = '${l['role'] ?? l['tier'] ?? ''}';
    final device = '${l['device'] ?? ''}';
    final ts = '${l['ts'] ?? ''}';
    final ip = '${l['ip'] ?? ''}';
    final tier = '${l['tier'] ?? ''}';
    final isSelf = l['self'] == true;
    final isView = '${l['event'] ?? ''}' == 'view';
    final viewer = '${l['viewer'] ?? ''}'.trim();
    Color c = AppColors.purple;
    if (tier == 'master') c = AppColors.lifetimeGold;
    if (tier == 'app') c = AppColors.taegeukBlue;
    if (tier == 'guest') c = AppColors.scoutGreen;
    // 본인 로그인/접속은 색상 변경 + 굵게 강조한다.
    final Color selfColor = AppColors.taegeukRed;
    final Color rowColor = isSelf ? selfColor : c;
    final bool selected = _selectMode && _selected.contains(_key(l));
    final Widget tile = Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.purple.withValues(alpha: 0.10)
            : (isSelf
                  ? selfColor.withValues(alpha: 0.07)
                  : (i.isEven ? const Color(0xFFF8F6FC) : Colors.white)),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected
              ? AppColors.purple
              : (isSelf
                    ? selfColor.withValues(alpha: 0.45)
                    : AppColors.purple.withValues(alpha: 0.12)),
          width: selected ? 1.6 : (isSelf ? 1.4 : 1),
        ),
      ),
      child: Row(
        children: [
          if (_selectMode)
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              activeColor: AppColors.purple,
              onChanged: (_) => setState(() {
                if (selected) {
                  _selected.remove(_key(l));
                } else {
                  _selected.add(_key(l));
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
          // 이벤트 구분: 본인 로그인 / 열람
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
                    Icon(
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
                        color: isSelf ? selfColor : AppColors.textDark,
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
                          color: selfColor,
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
                if (isView && viewer.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.visibility,
                        size: 12,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: MarqueeText(
                          '열람자 $viewer',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelf
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelf ? selfColor : AppColors.textDark,
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
                          color: isSelf ? selfColor : AppColors.textDark,
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
    // 선택 삭제 모드에서는 타일 전체를 눌러도 토글되게 감싼다.
    if (!_selectMode) return tile;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() {
        if (selected) {
          _selected.remove(_key(l));
        } else {
          _selected.add(_key(l));
        }
      }),
      child: tile,
    );
  }
}
