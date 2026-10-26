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
import '../widgets/marquee_text.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/tsak_output_sheet.dart';
import '../widgets/tsak_output_preview.dart';
import 'member_detail_screen.dart';

/// 은하스카우트 명단 — 범스카우트와 **분리 관리**되는 별도 명단.
///
/// 관리자·마스터 전용. 항목: 인가번호(G1~G165) · 성명 · 생년월일 · 소속 · 인가년월일.
///
/// ── [번호체계 2026-10-26] 은하 = **G + 번호** (G = Galaxy) ──────────────────
///  요구(원문): "은하스카우트는 1~165와 같은 단순 번호를 G1~G165로 알파벳과
///              합친 넘버 체계로 모두 다시 바꾸면 좋겠음 / G는 Galaxy(은하)의
///              약자임"
///
///  ## 왜 바꿨나
///   은하와 범의 번호 공간이 **똑같이 1~165** 라서, 번호만 보고는 누구인지
///   구분할 수 없었다. 그 결과 은하 43호 화면에 **범 43호 사진**이 뜨고,
///   개인카드·세션·권한이 서로 뒤바뀌는 사고가 반복됐다.
///   접두어 G 하나로 두 체계가 **절대 겹치지 않게** 된다(범 43 / 은하 G43).
///
///  ## 표시 규칙
///   이제 번호 자체가 'G43' 이므로 '은하G43' 처럼 **접두어를 두 번 붙이지
///   않는다**. `eunhaLabel()` 이 그 규칙을 한 곳에서 보장한다.
///
///  ## 하위호환
///   서버가 아직 '43' 처럼 G 없이 내려주는 경우(구 캐시·구 응답)에도 화면에는
///   'G43' 으로 보이게 한다. 사용자가 번호를 눈으로 확인할 때 체계가 드러나야
///   같은 실수가 반복되지 않는다.
String eunhaLabel(String number) {
  final d = number.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return number.trim().isEmpty ? 'G-' : 'G-';
  return 'G$d';
}

class EunhaRosterScreen extends StatefulWidget {
  const EunhaRosterScreen({super.key});

  @override
  State<EunhaRosterScreen> createState() => _EunhaRosterScreenState();
}

class _EunhaRosterScreenState extends State<EunhaRosterScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _busyBuilding = false;

  /// 좌측 선택박스로 고른 항목(회원 id). 선택 시 그 항목만 출력한다.
  final Set<String> _sel = {};

  void _toggle(String id) {
    setState(() {
      if (_sel.contains(id)) {
        _sel.remove(id);
      } else {
        _sel.add(id);
      }
    });
  }

  void _toggleAll(List<Member> list) {
    setState(() {
      if (_sel.length == list.length) {
        _sel.clear();
      } else {
        _sel
          ..clear()
          ..addAll(list.map((m) => m.id));
      }
    });
  }

  /// 명단 항목 클릭 → 개인정보(상세) 화면으로 이동.
  void _openDetail(Member m) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberDetailScreen(memberId: m.id)),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AppState>().reloadEunhaMembers(),
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
        .where(
          (m) =>
              m.searchText.contains(q) ||
              eunhaLabel(m.number).contains(q) ||
              m.name.contains(q),
        )
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
            tooltip: '명단 새로고침',
            onPressed: state.eunhaLoading
                ? null
                : () => context.read<AppState>().reloadEunhaMembers(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: _sel.isEmpty ? '출력 (PDF·엑셀 등)' : '선택 ${_sel.length}명 출력',
            onPressed: _busyBuilding
                ? null
                : () => _openOutput(
                    context,
                    _sel.isEmpty
                        ? list
                        : list.where((m) => _sel.contains(m.id)).toList(),
                  ),
            icon: Icon(_sel.isEmpty ? Icons.ios_share : Icons.check_circle),
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
                    const Icon(
                      Icons.groups,
                      size: 16,
                      color: AppColors.taegeukBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '전체 ${all.length}명${_q.isEmpty ? '' : ' · 검색 ${list.length}명'}'
                      '${_sel.isEmpty ? '' : ' · 선택 ${_sel.length}명'}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const Spacer(),
                    // 좌측 선택박스 전체선택/해제 — 선택 시 그 항목만 출력한다.
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        foregroundColor: AppColors.taegeukBlue,
                      ),
                      onPressed: list.isEmpty ? null : () => _toggleAll(list),
                      icon: Icon(
                        _sel.isNotEmpty && _sel.length == list.length
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 16,
                      ),
                      label: Text(
                        _sel.isNotEmpty && _sel.length == list.length
                            ? '전체해제'
                            : '전체선택',
                        style: const TextStyle(fontSize: 11.5),
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
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.groups_outlined,
                              size: 46,
                              color: AppColors.textGray,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _q.trim().isEmpty
                                  ? '은하스카우트 명단이 없습니다.'
                                  : '검색 결과가 없습니다.',
                              style: const TextStyle(color: AppColors.textGray),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: state.eunhaLoading
                                  ? null
                                  : () => context
                                        .read<AppState>()
                                        .reloadEunhaMembers(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('명단 다시 불러오기'),
                            ),
                          ],
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
    final headers = ['은하번호', '성명', '영문 이름', '소속', '생년월일', '인가년월일'];
    final rows = <List<String>>[];
    for (final m in list) {
      rows.add([
        eunhaLabel(m.number),
        // (요구) 이름은 '한글 (영어)'로 합치지 않는다 — 합치면 두 줄로 접혀
        //       표가 지저분해진다. 성명·영문 이름을 별도 열로 분리한다.
        m.name,
        m.nameEn.trim(),
        m.unit.trim(),
        m.birthday.trim(),
        m.date.trim(),
      ]);
    }
    final title =
        '은하스카우트 명단'
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
      onShare: () => _shareOutput(title, headers, rows),
      // (요구) 모든 포맷을 외부 프로그램(뷰어·인쇄·공유 시트)으로 내보내기.
      onOpen: (f) => _openOutputFile(title, headers, rows, f),
      onShareFormat: (f) => _shareOutput(title, headers, rows, format: f),
      onPreview: () => showTsakOutputPreview(
        context,
        doc: TsakTableDoc(
          title: title,
          subtitle: '은하스카우트 · 명부관리',
          description: '은하스카우트 명부 출력물입니다.',
          columns: headers,
          rows: rows,
          summary: ['총 ${rows.length}명'],
          footerLeft: '한국범스카우트중앙회 · 은하스카우트',
        ),
      ),
      onOnePage: () => _runOnePage(context.read<AppState>().eunhaMembers),
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
            meta: const DocMeta(title: '은하스카우트 명부', subtitle: '소속 은하스카우트'),
            rows: [
              // (요구) 한글 이름 옆에 영문 이름을 함께 배치한다(없으면 한글만).
              for (final m in members)
                [
                  eunhaLabel(m.number),
                  m.nameEn.trim().isEmpty
                      ? m.name
                      : '${m.name} (${m.nameEn.trim()})',
                ],
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

  /// 명단을 **OS 공유 시트**(모든 기기)로 공유한다 — 지정 형식(기본 PDF)으로 전송.
  Future<void> _shareOutput(
    String title,
    List<String> headers,
    List<List<String>> rows, {
    TsakOutputFormat format = TsakOutputFormat.pdf,
  }) async {
    if (rows.isEmpty) {
      _snack('공유할 명단이 없습니다');
      return;
    }
    final doc = TsakTableDoc(
      title: title,
      subtitle: '은하스카우트 · 명부관리',
      description: '은하스카우트 명단입니다.',
      columns: headers,
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · 은하스카우트',
    );
    setState(() => _busyBuilding = true);
    try {
      late TsakShareResult res;
      await runWithTsakProgress(
        context,
        title: '은하스카우트 명단 공유 준비',
        note: '${rows.length}명 명단을 ${format.label}(으)로 만들어 공유합니다.',
        steps: ['문서 구성', '${format.label} 생성', '공유 시트 열기'],
        task: (ctl) async {
          ctl.update(progress: 0.2, message: '문서를 구성하는 중…', stepIndex: 0);
          ctl.update(
            progress: 0.6,
            message: '${format.label} 생성 중…',
            stepIndex: 1,
          );
          res = await shareTsakTableChosen(context, doc, format);
          ctl.update(progress: 1.0, message: '공유 시트를 엽니다', stepIndex: 2);
        },
      );
      if (mounted)
        _snack(tsakShareMessage(res, what: '은하스카우트 명단 ${format.label}'));
    } catch (e) {
      if (mounted) _snack('공유 실패: $e');
    } finally {
      if (mounted) setState(() => _busyBuilding = false);
    }
  }

  /// 명단을 지정 형식으로 만들어 **외부 프로그램**으로 연다(모든 포맷 공통).
  Future<void> _openOutputFile(
    String title,
    List<String> headers,
    List<List<String>> rows,
    TsakOutputFormat format,
  ) async {
    if (rows.isEmpty) {
      _snack('내보낼 명단이 없습니다');
      return;
    }
    final doc = TsakTableDoc(
      title: title,
      subtitle: '은하스카우트 · 명부관리',
      description: '은하스카우트 명단입니다.',
      columns: headers,
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · 은하스카우트',
    );
    setState(() => _busyBuilding = true);
    try {
      late TsakShareResult res;
      await runWithTsakProgress(
        context,
        title: '은하스카우트 명단 ${format.label} 외부 열기',
        note: '${rows.length}명 명단을 ${format.label}(으)로 만들어 엽니다.',
        steps: ['문서 구성', '${format.label} 생성', '외부 프로그램 열기'],
        task: (ctl) async {
          ctl.update(progress: 0.2, message: '문서를 구성하는 중…', stepIndex: 0);
          ctl.update(
            progress: 0.6,
            message: '${format.label} 생성 중…',
            stepIndex: 1,
          );
          res = await openTsakTableChosen(context, doc, format);
          ctl.update(progress: 1.0, message: '외부 프로그램을 엽니다', stepIndex: 2);
        },
      );
      if (mounted)
        _snack(tsakShareMessage(res, what: '은하스카우트 명단 ${format.label}'));
    } catch (e) {
      if (mounted) _snack('열기 실패: $e');
    } finally {
      if (mounted) setState(() => _busyBuilding = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _row(Member m, int idx) {
    final on = _sel.contains(m.id);
    return ListTile(
      dense: true,
      // 좌측 선택박스 — 선택 시 그 항목만 출력한다(요구).
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: on,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            activeColor: AppColors.taegeukBlue,
            onChanged: (_) => _toggle(m.id),
          ),
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.taegeukBlue.withValues(alpha: 0.12),
            child: Text(
              '${idx + 1}',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.taegeukBlue,
              ),
            ),
          ),
        ],
      ),
      // 항목 클릭 → 개인정보(상세) 화면으로 이동(요구).
      onTap: () => _openDetail(m),
      title: Row(
        children: [
          Text(
            eunhaLabel(m.number),
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
          // (요구) 한글 이름 옆에 영문 이름을 함께 배치한다(없으면 표시하지 않음).
          if (m.nameEn.trim().isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: MarqueeText(
                m.nameEn.trim(),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textGray,
                ),
              ),
            ),
          ],
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
      trailing: const Icon(
        Icons.chevron_right,
        size: 18,
        color: AppColors.textGray,
      ),
    );
  }
}
