import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/doc_pdf.dart';
import '../services/file_save.dart';
import '../services/output_formats.dart';
import '../services/print_doc.dart';
import '../services/table_export.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/tsak_output_sheet.dart';

/// 은하스카우트 명단 — 범스카우트와 **분리 관리**되는 별도 명단.
///
/// 관리자·마스터 전용. 항목: 인가번호(은하N) · 성명 · 생년월일 · 소속 · 인가년월일.
class EunhaRosterScreen extends StatefulWidget {
  const EunhaRosterScreen({super.key});

  @override
  State<EunhaRosterScreen> createState() => _EunhaRosterScreenState();
}

class _EunhaRosterScreenState extends State<EunhaRosterScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _busyBuilding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AppState>().loadEunhaMembers(),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Member> _filtered(List<Member> ms) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return ms;
    return ms
        .where((m) =>
            m.searchText.contains(q) ||
            '은하${m.number}'.contains(q) ||
            m.name.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final all = state.eunhaMembers;
    final list = _filtered(all);

    return Scaffold(
      appBar: TsakAppBar(
        title: const Text('은하스카우트 명단'),
        actions: [
          IconButton(
            tooltip: '출력 (PDF·엑셀 등)',
            onPressed: _busyBuilding ? null : () => _openOutput(context, list),
            icon: const Icon(Icons.ios_share),
          ),
          const AppHomeEmblem(size: 26),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      hintText: '이름 · 은하번호 · 소속 검색',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      suffixIcon: _q.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _q = '');
                              },
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.groups, size: 16, color: AppColors.taegeukBlue),
                const SizedBox(width: 6),
                Text(
                  '전체 ${all.length}명${_q.isEmpty ? '' : ' · 검색 ${list.length}명'}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          Expanded(
            child: state.eunhaLoading && all.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const Center(
                        child: Text(
                          '은하스카우트 명단이 없습니다.',
                          style: TextStyle(color: AppColors.textGray),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _row(list[i], i),
                      ),
          ),
            ],
          ),
          BusyOverlay(
            visible: _busyBuilding,
            title: '은하스카우트 명단을 만드는 중입니다',
            lines: const [
              '명단을 정리하고 문서를 구성하고 있습니다...',
              '파일로 저장하는 중입니다...',
              '잠시만 기다려 주세요...',
            ],
          ),
        ],
      ),
    );
  }

  // ===================== 출력 (범스카우트와 동일 규격) =====================

  /// 은하스카우트 명단을 **범스카우트와 동일한 공용 출력 시트/시트 규격**으로 출력.
  ///  · 형식 순서 규칙(#14): PDF → JPG → 엑셀 → PPT → 워드 → TXT.
  ///  · 저장 위치 선택 → 실시간 진행 대기창(runWithTsakProgress) 순서로 동작.
  Future<void> _openOutput(BuildContext context, List<Member> list) async {
    if (list.isEmpty) {
      _snack('출력할 은하스카우트 명단이 없습니다');
      return;
    }
    final headers = ['은하번호', '성명', '소속', '생년월일', '인가년월일'];
    final rows = <List<String>>[];
    for (final m in list) {
      rows.add([
        '은하${m.number}',
        m.name,
        m.unit.trim(),
        m.birthday.trim(),
        m.date.trim(),
      ]);
    }
    final title = '은하스카우트 명단'
        '${_q.isEmpty ? '' : ' (검색 ${list.length}명)'}';
    await showTsakOutputSheet(
      context,
      title: '은하스카우트 명단 출력',
      subtitle: '전체 ${list.length}명 · 은하스카우트',
      onPick: (f) => _runOutput(title, headers, rows, f),
      onPrint: () => _runOutput(
        title,
        headers,
        rows,
        TsakOutputFormat.pdf,
        justPrint: true,
      ),
      onEmail: () => _emailOutput(title, headers, rows),
      onOnePage: () =>
          _runOnePage(context.read<AppState>().eunhaMembers),
      onShareLink: () => showLinkShareDialog(context, Uri.base.toString()),
    );
  }

  /// 은하스카우트 명부 **전원을 A4 한 장**에 담아 PDF로 저장/인쇄한다.
  ///
  /// 요구: "은하스카우트 명부 모두 출력 a4한장에".
  ///  · 열 수·글자 크기를 자동 계산해 165명 전원을 1페이지에 담는다.
  ///  · 검색 중이어도 **전체 명단**을 대상으로 한다.
  Future<void> _runOnePage(List<Member> members) async {
    if (members.isEmpty) {
      _snack('출력할 은하스카우트 명부가 없습니다');
      return;
    }
    setState(() => _busyBuilding = true);
    try {
      final loc = await askTsakSaveLocation(
        context,
        info: '은하스카우트 명부 · 전원 ${members.length}명 · A4 1장 PDF',
      );
      if (loc == null) {
        if (mounted) _snack('저장을 취소했습니다');
        return;
      }
      if (!mounted) return;
      await runWithTsakProgress(
        context,
        title: '은하스카우트 명부 A4 한 장 생성',
        note: '전원 ${members.length}명을 한 장에 맞춥니다.',
        steps: const ['레이아웃 계산', 'PDF 생성', '파일 저장'],
        task: (ctl) async {
          ctl.update(progress: 0.2, message: '열·글자 크기를 계산하는 중…', stepIndex: 0);
          final pdf = await DocPdf.buildRosterOnePage(
            meta: const DocMeta(
              title: '은하스카우트 명부',
              subtitle: '소속 은하스카우트',
            ),
            rows: [
              for (final m in members) ['은하${m.number}', m.name],
            ],
            footerLeft: '한국범스카우트중앙회 · 은하스카우트',
          );
          ctl.update(progress: 0.7, message: 'PDF를 저장하는 중…', stepIndex: 1);
          final cols = DocPdf.lastRosterCols;
          final name = 'TSAK_은하스카우트_명부_A4한장_$cols열_전원${members.length}명';
          await saveBytesChoose(
            bytes: pdf,
            name: name,
            ext: 'pdf',
            mime: 'application/pdf',
            choose: loc,
          );
          ctl.update(progress: 1.0, message: '완료', stepIndex: 2);
        },
      );
      if (mounted) {
        _snack('A4 한 장 PDF 저장을 시작했습니다 (전원 ${members.length}명)');
      }
    } catch (e) {
      if (mounted) _snack('출력 실패: $e');
    } finally {
      if (mounted) setState(() => _busyBuilding = false);
    }
  }

  Future<void> _runOutput(
    String title,
    List<String> headers,
    List<List<String>> rows,
    TsakOutputFormat format, {
    bool justPrint = false,
  }) async {
    final doc = TsakTableDoc(
      title: title,
      subtitle: '은하스카우트 · 명부관리',
      description: '은하스카우트 명단 출력물입니다.',
      columns: headers,
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · 은하스카우트',
    );
    setState(() => _busyBuilding = true);
    try {
      // 1) 저장 위치를 진행창 이전에 먼저 확정한다(공용 규칙).
      var choose = false;
      if (!justPrint) {
        final loc = await askTsakSaveLocation(
          context,
          info: '$title · ${rows.length}명 · ${format.label}',
        );
        if (loc == null) {
          if (mounted) _snack('저장을 취소했습니다');
          return;
        }
        choose = loc;
      }
      if (!mounted) return;
      // 2) 진행창을 열고 파일을 만든다.
      await runWithTsakProgress(
        context,
        title: justPrint ? '명단 프린트 준비' : '명단 ${format.label} 생성',
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
          await saveTsakTableChosen(context, doc, format, choose: choose);
          ctl.update(progress: 1.0, message: '완료', stepIndex: 2);
        },
      );
      if (mounted) {
        _snack(justPrint ? '인쇄 창을 열었습니다' : '${format.label} 저장을 시작했습니다');
      }
    } catch (e) {
      if (mounted) _snack('출력 실패: $e');
    } finally {
      if (mounted) setState(() => _busyBuilding = false);
    }
  }

  Future<void> _emailOutput(
    String title,
    List<String> headers,
    List<List<String>> rows,
  ) async {
    final doc = TsakTableDoc(
      title: title,
      subtitle: '은하스카우트 · 명부관리',
      columns: headers,
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · 은하스카우트',
    );
    await emailTsakTable(context, doc);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _row(Member m, int idx) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.taegeukBlue.withValues(alpha: 0.12),
        child: Text(
          '${idx + 1}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.taegeukBlue,
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            '은하${m.number}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.taegeukBlue,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            m.name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
      subtitle: Text(
        [
          if (m.unit.trim().isNotEmpty) m.unit.trim(),
          if (m.birthday.trim().isNotEmpty) '생 ${m.birthday.trim()}',
          if (m.date.trim().isNotEmpty) '인가 ${m.date.trim()}',
        ].join('  ·  '),
        style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
      ),
    );
  }
}
