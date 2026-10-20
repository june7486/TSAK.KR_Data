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
import '../widgets/tsak_table_options.dart';
import '../widgets/tsak_output_preview.dart';
import 'member_detail_screen.dart';

/// 아타스(ATAS) 명부 — 범스카우트 인가자 중 **ATAS 인가번호**를 보유한 대원 명단.
///
/// 관리자·마스터 전용. 항목: ATAS 인가번호 · 범인가번호 · 성명 · 소속 · 인가년월일.
/// (홈 화면 메인 버튼 행의 "아타스" 버튼에서 진입)
class AtasRosterScreen extends StatefulWidget {
  const AtasRosterScreen({super.key});

  @override
  State<AtasRosterScreen> createState() => _AtasRosterScreenState();
}

class _AtasRosterScreenState extends State<AtasRosterScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _busyBuilding = false;

  /// 좌측 선택박스로 고른 항목(회원 id). 선택 시 그 항목만 출력한다.
  final Set<String> _sel = {};

  /// 출력 옵션 — **출력 시 각각의 정보를 선택**(범스카우트 인가정보 / ATAS 인가정보
  /// / 소속 등)하고 순서·글씨·줄간격·용지를 정한다.
  ///
  /// (요구: "츌력시 각각의 정보를 선택할 수 있도록 업데이트 할 것")
  TableOutputOptions? _outOpts;

  /// 출력 항목(헤더) — 인가정보 그룹을 나눠 정의한다.
  ///
  ///  · ATAS 인가정보 : ATAS 인가번호 · 영문 이름
  ///  · 범스카우트 인가정보 : 범인가번호 · 성명 · 소속 연맹 · 등록 단위대 · 인가년월일
  ///  → 두 그룹을 각각 켜고 끌 수 있어 "ATAS 정보만" 또는 "범스카우트 정보만"
  ///    뽑을 수 있다.
  static const _atasFields = ['ATAS 인가번호', '영문 이름'];
  static const _beomFields = ['범인가번호', '성명', '소속 연맹', '등록 단위대', '인가년월일'];
  static List<String> get _allHeaders => [..._beomFields, ..._atasFields];

  /// 현재 옵션을 적용한 실제 출력 (헤더, 행) 쌍.
  ({List<String> headers, List<List<String>> rows}) _view(
    List<Member> list,
  ) {
    final all = _allHeaders;
    final full = <List<String>>[
      for (final m in list)
        [
          m.number.trim(),
          m.name,
          m.league.trim(),
          m.unit.trim(),
          m.date.trim(),
          m.atasNo.trim(),
          m.nameEn.trim(),
        ],
    ];
    final o = _outOpts;
    if (o == null || o.cols == null) return (headers: all, rows: full);
    final v = applyTableOptions(
      columns: all,
      rows: full,
      order: o.cols,
      selected: o.cols!.toSet(),
    );
    return (headers: v.columns, rows: v.rows);
  }

  /// 출력 옵션 편집 — 정보 그룹(범/ATAS) 프리셋 + 항목 선택·순서·글씨·줄간격·용지.
  Future<void> _editOptions(List<Member> list) async {
    final out = await showTsakTableOptions(
      context,
      title: '아타스 명부 출력 옵션',
      subtitle: '범스카우트 인가정보 / ATAS 인가정보를 각각 골라 출력하세요.',
      columns: _allHeaders,
      initial: _outOpts,
    );
    if (out != null && mounted) {
      setState(() => _outOpts = out);
      _snack('출력 옵션을 저장했습니다 · ${out.badge}');
    }
  }

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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// ATAS 인가번호를 가진 대원만 대상으로 한다(빈 값 제외).
  List<Member> _atasAll(AppState state) =>
      state.members.where((m) => m.atasNo.trim().isNotEmpty).toList();

  List<Member> _filtered(List<Member> ms) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return ms;
    return ms
        .where(
          (m) =>
              m.searchText.contains(q) ||
              'atas${m.atasNo}'.contains(q) ||
              m.atasNo.contains(q) ||
              m.name.contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final all = _atasAll(state);
    final list = _filtered(all);

    return Scaffold(
      appBar: TsakAppBar(
        title: const Text('아타스(ATAS) 명부'),
        actions: [
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
                          hintText: '이름 · ATAS번호 · 범인가번호 · 소속 검색',
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
                      Icons.military_tech,
                      size: 16,
                      color: AppColors.tigerGold,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ATAS 명부 ${all.length}명'
                      '${_q.isEmpty ? '' : ' · 검색 ${list.length}명'}'
                      '${_sel.isEmpty ? '' : ' · 선택 ${_sel.length}명'}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        foregroundColor: AppColors.lifetimeGold,
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
                child: list.isEmpty
                    ? const Center(
                        child: Text(
                          'ATAS 인가번호가 등록된 대원이 없습니다.',
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
            title: '아타스 명부를 만드는 중입니다',
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

  Future<void> _openOutput(BuildContext context, List<Member> list) async {
    if (list.isEmpty) {
      _snack('출력할 아타스 명부가 없습니다');
      return;
    }
    // (요구) **출력 시 각각의 정보를 선택** — 옵션으로 고른 항목만 나간다.
    //  · ATAS 인가정보(ATAS 인가번호·영문 이름)와 범스카우트 인가정보(범인가번호·
    //    성명·소속 연맹·등록 단위대·인가년월일)를 각각 켜고 끌 수 있다.
    final view = _view(list);
    final headers = view.headers;
    final rows = view.rows;
    final title = '아타스(ATAS) 명부${_q.isEmpty ? '' : ' (검색 ${list.length}명)'}';
    await showTsakOutputSheet(
      context,
      title: '아타스 명부 출력',
      subtitle: 'ATAS ${list.length}명 · 범스카우트',
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
          subtitle: '아타스 · 명부관리',
          description: '아타스(ATAS) 명부 출력물입니다.',
          columns: headers,
          rows: rows,
          summary: ['총 ${rows.length}명'],
          footerLeft: '한국범스카우트중앙회 · 아타스',
          options: _outOpts,
        ),
      ),
      // (요구) 출력 시 **각각의 정보를 선택** — 범인가/ATAS 그룹·항목·순서·글씨·
      //  줄간격·용지를 이 자리에서 고른다(관리자 명부와 동일한 화면).
      onOptions: () => _editOptions(list),
      onOnePage: () => _runOnePage(_atasAll(context.read<AppState>())),
      onShareLink: () => showLinkShareDialog(context, Uri.base.toString()),
    );
  }

  /// ATAS 명부 전원을 A4 한 장에 담아 PDF로 저장/인쇄한다.
  Future<void> _runOnePage(List<Member> members) async {
    if (members.isEmpty) {
      _snack('출력할 아타스 명부가 없습니다');
      return;
    }
    setState(() => _busyBuilding = true);
    try {
      final loc = await askTsakSaveLocation(
        context,
        info: '아타스 명부 · 전원 ${members.length}명 · A4 1장 PDF',
      );
      if (loc == null) {
        if (mounted) _snack('저장을 취소했습니다');
        return;
      }
      if (!mounted) return;
      await runWithTsakProgress(
        context,
        title: '아타스 명부 A4 한 장 생성',
        note: '전원 ${members.length}명을 한 장에 맞춥니다.',
        steps: const ['레이아웃 계산', 'PDF 생성', '파일 저장'],
        task: (ctl) async {
          ctl.update(progress: 0.2, message: '열·글자 크기를 계산하는 중…', stepIndex: 0);
          final pdf = await DocPdf.buildRosterOnePage(
            meta: const DocMeta(title: '아타스(ATAS) 명부', subtitle: '범스카우트 인가자'),
            rows: [
              // (요구) 한글 이름 옆에 영문 이름을 함께 배치한다(없으면 한글만).
              for (final m in members)
                [
                  m.atasNo.trim(),
                  m.nameEn.trim().isEmpty
                      ? m.name
                      : '${m.name} (${m.nameEn.trim()})',
                ],
            ],
            footerLeft: '한국범스카우트중앙회 · 아타스',
          );
          ctl.update(progress: 0.7, message: 'PDF를 저장하는 중…', stepIndex: 1);
          final cols = DocPdf.lastRosterCols;
          final name = 'TSAK_아타스_명부_A4한장_$cols열_전원${members.length}명';
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
      subtitle: '아타스 · 명부관리',
      description: '아타스(ATAS) 명부 출력물입니다.',
      columns: headers,
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · 아타스',
      // 글씨·줄간격·용지 옵션 반영.
      options: _outOpts,
    );
    setState(() => _busyBuilding = true);
    try {
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
      subtitle: '아타스 · 명부관리',
      columns: headers,
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · 아타스',
    );
    await emailTsakTable(context, doc);
  }

  /// 명부를 **OS 공유 시트**(모든 기기)로 공유한다 — 지정 형식(기본 PDF)으로 전송.
  Future<void> _shareOutput(
    String title,
    List<String> headers,
    List<List<String>> rows, {
    TsakOutputFormat format = TsakOutputFormat.pdf,
  }) async {
    if (rows.isEmpty) {
      _snack('공유할 명부가 없습니다');
      return;
    }
    final doc = TsakTableDoc(
      title: title,
      subtitle: '아타스 · 명부관리',
      description: '아타스(ATAS) 명부입니다.',
      columns: headers,
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · 아타스',
    );
    setState(() => _busyBuilding = true);
    try {
      late TsakShareResult res;
      await runWithTsakProgress(
        context,
        title: '아타스 명부 공유 준비',
        note: '${rows.length}명 명부를 ${format.label}(으)로 만들어 공유합니다.',
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
        _snack(tsakShareMessage(res, what: '아타스 명부 ${format.label}'));
    } catch (e) {
      if (mounted) _snack('공유 실패: $e');
    } finally {
      if (mounted) setState(() => _busyBuilding = false);
    }
  }

  /// 명부를 지정 형식으로 만들어 **외부 프로그램**으로 연다(모든 포맷 공통).
  Future<void> _openOutputFile(
    String title,
    List<String> headers,
    List<List<String>> rows,
    TsakOutputFormat format,
  ) async {
    if (rows.isEmpty) {
      _snack('내보낼 명부가 없습니다');
      return;
    }
    final doc = TsakTableDoc(
      title: title,
      subtitle: '아타스 · 명부관리',
      description: '아타스(ATAS) 명부입니다.',
      columns: headers,
      rows: rows,
      summary: ['총 ${rows.length}명'],
      footerLeft: '한국범스카우트중앙회 · 아타스',
    );
    setState(() => _busyBuilding = true);
    try {
      late TsakShareResult res;
      await runWithTsakProgress(
        context,
        title: '아타스 명부 ${format.label} 외부 열기',
        note: '${rows.length}명 명부를 ${format.label}(으)로 만들어 엽니다.',
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
        _snack(tsakShareMessage(res, what: '아타스 명부 ${format.label}'));
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
            activeColor: AppColors.lifetimeGold,
            onChanged: (_) => _toggle(m.id),
          ),
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.tigerGold.withValues(alpha: 0.16),
            child: Text(
              '${idx + 1}',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.lifetimeGold,
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
            'ATAS ${m.atasNo.trim()}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.lifetimeGold,
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
          // (요구) 한글 이름 옆에 영문 이름 배치 — 없으면 표시하지 않는다.
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
          if (m.number.trim().isNotEmpty) '범인가 ${m.number.trim()}',
          if (m.unit.trim().isNotEmpty) m.unit.trim(),
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
