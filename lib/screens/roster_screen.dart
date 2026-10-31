import 'package:flutter/material.dart';

import '../services/file_save.dart';
import '../services/extra_fields.dart';
import '../services/output_formats.dart';
import '../services/table_export.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/scroll_arrows.dart';
import '../widgets/tsak_output_sheet.dart';
import '../widgets/tsak_output_preview.dart';
import '../widgets/tsak_table_options.dart';

/// 행사 참가자 명단 — 앱 내부에서 열리는 MUJI풍 미리보기 + 출력/공유.
/// (외부 브라우저로 튕기지 않아 뒤로가기가 정상 동작한다)
class RosterScreen extends StatefulWidget {
  const RosterScreen({
    super.key,
    required this.title,
    required this.year,
    required this.period,
    required this.place,
    required this.desc,
    required this.attendees,
  });

  final String title;
  final String year;
  final String period;
  final String place;
  final String desc;
  final List<Map<String, dynamic>> attendees;

  /// 파일명 규칙: {행사명}_참가자명부
  String get fileNameBase => '${title}_참가자명부';

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  bool _busy = false;

  // ---- 인쇄 항목 선택 ----
  //  · 항상 인쇄: # · 접속 · 인가번호 · 이름 · 연락처
  //  · 선택 항목(요구): 소속·성별·메일·항목 + 참가비·평생회원·연회비 납부여부 +
  //    참가신청 입력항목(도착·숙박·이동·동행·전달사항).
  bool _showUnit = true; // 소속(활동)
  bool _showGender = true; // 성별
  bool _showEmail = true; // 메일
  bool _showRoles = true; // 항목(역할)
  bool _showEventFee = false; // 참가비 납부 여부
  bool _showLifetime = false; // 평생회원 여부
  bool _showYearFee = false; // 행사년도 연회비 납부 여부
  bool _showApply = false; // 참가신청 입력항목 (전체 1컬럼 — 호환용)

  /// [요구 2026-10-30] 추가입력사항을 **항목별 개별 컬럼**으로 노출.
  ///
  /// > "추가입력사항도 매우 중요한 정보야 … 출력시 구분해서 보여져야 해"
  ///
  /// 종전에는 `_showApply` **한 컬럼**에
  /// `이동 자차 · 숙박 숙박 · 도착 정시 · 동행 김철수` 처럼 몰아넣어
  /// ① 항목이 늘면 한 칸이 터지고 ② Excel 에서 특정 항목만 골라 쓸 수 없었다.
  /// → 항목마다 **독립 컬럼**을 두고, 필요한 항목만 켜고 끌 수 있게 한다.
  final Set<String> _extraCols = <String>{};

  bool _extraOn(String key) => _extraCols.contains(key);

  void _toggleExtra(String key, bool v) {
    if (v) {
      _extraCols.add(key);
    } else {
      _extraCols.remove(key);
    }
  }

  String get _period => widget.period.isNotEmpty ? widget.period : widget.year;

  /// 출력 옵션(글씨크기·줄간격·용지·출력내용선택·위치이동) — 명부출력과 동일 규칙.
  ///
  /// ## 두줄 방지 기본값 — (요구 2026-10-31 6차) "전화번호, e-mail 내용이 잘림"
  /// 종전에는 `{'인가번호','이름','연락처','메일'}` 네 개를 1줄로 고정했다.
  /// 그런데 **메일은 평균 22~26자**(simonrhee75@gmail.com = 23 units)다.
  /// 1줄 고정이면 열 폭이 모자랄 때 그대로 **잘려서** …으로 끝났다.
  /// → 메일은 빼고, 접속·인가번호·연락처만 1줄 고정한다.
  ///   (메일은 접혀도 두 줄이면 최대 12자씩만 쓰면 되므로 폭이 절반이면 된다)
  TableOutputOptions? _outOpts = const TableOutputOptions(
    noWrap: {'인가번호', '연락처'},
  );

  /// [공용] 행사 정보(제목·부제·설명) + 참가자 표를 담은 출력 문서.
  ///   · 제목 = 행사명 · 부제·설명 = 행사 정보(장소·기간·안내글) → 문서 상단 노출.
  ///   · options = 글씨 크기·줄 간격·용지 방향·열 선택/순서(공용).
  ///   옵션(선택/순서·글씨·줄간격·용지)은 `TsakTableDoc` 이 PDF·JPG·문서에 반영한다.
  TsakTableDoc _doc() {
    final cols = <String>['#', '접속', '인가번호', '이름'];
    if (_showUnit) cols.add('소속(활동)');
    if (_showGender) cols.add('성별');
    cols.add('연락처');
    if (_showEmail) cols.add('메일');
    if (_showRoles) cols.add('항목');
    if (_showEventFee) cols.add('참가비');
    if (_showLifetime) cols.add('평생');
    if (_showYearFee) {
      cols.add('${widget.year.isNotEmpty ? '${widget.year}년 ' : ''}연회비');
    }
    if (_showApply) cols.add('참가신청');
    final rows = <List<String>>[];
    for (var i = 0; i < widget.attendees.length; i++) {
      final a = widget.attendees[i];
      final r = <String>[
        '${i + 1}',
        (a['visited'] == true) ? 'V' : '',
        _num(a),
        '${a['name'] ?? ''}',
      ];
      if (_showUnit) r.add(_first(a, const ['unitText', 'unit']));
      if (_showGender) r.add(_first(a, const ['genderText', 'gender']));
      r.add(_first(a, const ['phoneText', 'phone']));
      if (_showEmail) r.add(_first(a, const ['emailText', 'email']));
      if (_showRoles) r.add(_rolesText(a));
      if (_showEventFee) r.add(a['eventFee'] == true ? 'O' : '');
      if (_showLifetime) r.add(a['lifetime'] == true ? 'O' : '');
      if (_showYearFee) r.add(a['yearFee'] == true ? 'O' : '');
      if (_showApply) r.add(_applyText(a));
      rows.add(r);
    }
    return TsakTableDoc(
      title: widget.title,
      subtitle: widget.place.isEmpty ? '참가자 명단' : widget.place,
      description: widget.desc,
      author: '한국범스카우트중앙회',
      extra: {
        '기간': _period,
        '장소': widget.place,
        '참가': '${widget.attendees.length}명',
        '파일': '${widget.fileNameBase}.pdf',
      },
      columns: cols,
      rows: rows,
      summary: ['총 ${widget.attendees.length}명'],
      footerLeft: '한국범스카우트중앙회 · 참가자 명단',
      options: _outOpts,
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }

  // ---- 실제 인쇄 ----
  Future<void> _print() async => _run(TsakOutputFormat.pdf, justPrint: true);

  // ---- 공유 ----
  Future<void> _share() async => _run(TsakOutputFormat.pdf, share: true);

  // ---- 파일 저장/인쇄/공유 (다른 명부 출력과 동일한 공용 시트) ----
  /// [요구] 참가자 명부도 관리자·은하·아타스 명부와 **동일한 출력 흐름**을 쓴다.
  ///  · 형식: PDF → JPG → 엑셀 → PPT → 워드 → TXT.
  ///  · 옵션: 글씨 크기·줄 간격·용지(가로/세로)·출력내용선택·위치이동.
  ///  · 미리보기: 실시간(2줄 방지 포함)으로 확인 후 PDF·이미지·인쇄.
  Future<void> _saveAs() async {
    if (widget.attendees.isEmpty) {
      _snack('출력할 참가자가 없습니다');
      return;
    }
    await showTsakOutputSheet(
      context,
      title: '참가자 명부 출력',
      subtitle: '${widget.title} · ${widget.attendees.length}명',
      onPick: (f) => _run(f),
      onPrint: () => _run(TsakOutputFormat.pdf, justPrint: true),
      onEmail: () => emailTsakTable(context, _doc()),
      onShare: () => _run(TsakOutputFormat.pdf, share: true),
      // 모든 포맷을 외부 프로그램(뷰어·인쇄·공유 시트)으로 내보내기.
      onOpen: (f) => _run(f, open: true),
      onShareFormat: (f) => _run(f, share: true),
      // 출력내용선택 · 위치이동 · 줄간격 · 글씨 · 용지 옵션(명부출력과 동일 화면).
      onOptions: _editOptions,
      // 실시간 미리보기 — 글씨·줄간격·2줄방지·가로세로를 확인 후 출력.
      onPreview: () => showTsakOutputPreview(
        context,
        doc: _doc(),
        // (요구 2026-10-31 2차) **이 화면(참가자 명단)에서도** 미리보기 중에
        //  추가항목을 골라 출력 여부를 정할 수 있게 한다.
        //  스크린샷 피드백: 칩이 안 보였다 → 원인은 여기에 extra 미전달.
        extra: TsakExtraPick(
          source: widget.attendees,
          initial: _extraCols,
        ),
      ),
      onShareImage: () => _run(TsakOutputFormat.jpg, share: true),
      onShareLink: () => showLinkShareDialog(context, Uri.base.toString()),
    );
  }

  /// 출력 옵션 편집 — 관리자·은하·아타스 명부출력과 **동일한 화면**.
  Future<void> _editOptions() async {
    final out = await showTsakTableOptions(
      context,
      title: '참가자 명부 출력 옵션',
      subtitle: '출력할 항목을 고르고 순서를 옮기고, 줄 간격·글씨·용지를 정하세요.',
      columns: _doc().columns,
      initial: _outOpts,
    );
    if (out != null && mounted) {
      setState(() => _outOpts = out);
      _snack('출력 옵션을 저장했습니다 · ${out.badge}');
    }
  }

  /// 공용 출력 실행 — 저장/열기/공유/인쇄(진행 대기창 포함).
  ///   1) 저장 위치를 진행창 이전에 확정(공용 규칙) → 2) 진행창 → 파일 생성.
  Future<void> _run(
    TsakOutputFormat format, {
    bool open = false,
    bool share = false,
    bool justPrint = false,
  }) async {
    final doc = _doc();
    if (doc.rows.isEmpty) {
      _snack('출력할 참가자가 없습니다');
      return;
    }
    setState(() => _busy = true);
    try {
      var choose = false;
      if (!open && !share && !justPrint) {
        final loc = await askTsakSaveLocation(
          context,
          info: '${widget.title} · ${doc.rows.length}명 · ${format.label}',
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
        title: justPrint ? '참가자 명부 프린트 준비' : '참가자 명부 ${format.label} 생성',
        note: '${doc.rows.length}명 명부를 처리합니다.',
        steps: justPrint
            ? const ['문서 구성', '인쇄 창 열기']
            : ['문서 구성', '${format.label} 생성', '파일 처리'],
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
            final r = await openTsakTableChosen(context, doc, format);
            ctl.update(progress: 1.0, message: '완료', stepIndex: 2);
            if (mounted) {
              _snack(tsakShareMessage(r, what: '참가자 명부 ${format.label}'));
            }
            return;
          }
          if (share) {
            final r = await shareTsakTableChosen(context, doc, format);
            ctl.update(progress: 1.0, message: '완료', stepIndex: 2);
            if (mounted) {
              _snack(tsakShareMessage(r, what: '참가자 명부 ${format.label}'));
            }
            return;
          }
          await saveTsakTableChosen(context, doc, format, choose: choose);
          ctl.update(progress: 1.0, message: '완료', stepIndex: 2);
        },
      );
      if (mounted && !open && !share) {
        _snack(justPrint ? '인쇄 창을 열었습니다' : '${format.label} 저장을 시작했습니다');
      }
    } catch (e) {
      if (mounted) _snack('출력 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      appBar: TsakAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '뒤로',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('참가자 명단'),
        actions: [
          IconButton(
            tooltip: '인쇄 항목 선택',
            icon: const Icon(Icons.checklist),
            onPressed: _busy ? null : _optionsSheet,
          ),
          IconButton(
            tooltip: '인쇄',
            icon: const Icon(Icons.print),
            onPressed: _busy ? null : _print,
          ),
          IconButton(
            tooltip: '공유',
            icon: const Icon(Icons.ios_share),
            onPressed: _busy ? null : _share,
          ),
          const AppHomeEmblem(size: 24, adminHomeOnly: true),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _header(),
              const SizedBox(height: 12),
              _optionSummary(),
              const SizedBox(height: 12),
              _table(),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  '· 접속 V = 사진폴더 접근 이력',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ),
            ],
          ),
          if (_busy)
            BusyOverlay(
              visible: _busy,
              title: '명단을 처리하는 중입니다',
              lines: const [
                '선택한 항목으로 명단을 구성하고 있습니다...',
                'PDF·이미지로 만드는 중...',
                '저장/공유 준비 중...',
              ],
            ),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  /// MUJI풍 헤더 — 큰 제목 + 얇은 액센트 바 + 정보
  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Image.asset(
                'assets/images/tsak_emblem.png',
                width: 44,
                height: 44,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(width: 46, height: 3, color: AppColors.purple),
          const SizedBox(height: 16),
          _metaRow('기간', _period),
          if (widget.place.isNotEmpty) _metaRow('장소', widget.place),
          _metaRow('참가', '${widget.attendees.length}명'),
          _metaRow('파일', '${widget.fileNameBase}.pdf'),
          if (widget.desc.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.desc,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textGray),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textGray,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 인쇄 항목 요약 — 어떤 항목이 함께 인쇄되는지 한 줄로 표시.
  Widget _optionSummary() {
    final extras = <String>[
      if (_showUnit) '소속',
      if (_showGender) '성별',
      if (_showEmail) '메일',
      if (_showRoles) '항목',
      if (_showEventFee) '참가비',
      if (_showLifetime) '평생회원',
      if (_showYearFee)
        '${widget.year.isNotEmpty ? '${widget.year}년 ' : ''}연회비',
      if (_showApply) '참가신청',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.purple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '#·접속·인가번호·이름·연락처는 항상 인쇄'
              '${extras.isEmpty ? ' (선택 항목 없음)' : ' · 추가: ${extras.join(', ')}'}',
              style: const TextStyle(fontSize: 12, color: AppColors.textDark),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
            ),
            onPressed: _optionsSheet,
            child: const Text('항목', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 항목 체크 패널(작게) — 열리는 바텀시트.
  void _optionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 2, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '인쇄 항목 선택',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '# · 접속 · 인가번호 · 이름 · 연락처는 항상 인쇄됩니다.\n아래 항목을 골라 함께 출력하세요.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textGray,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 18),
                _sectionLabel('기본 정보'),
                _optTile('소속(활동)', _showUnit, (v) {
                  setD(() => _showUnit = v);
                  setState(() => _showUnit = v);
                }),
                _optTile('성별', _showGender, (v) {
                  setD(() => _showGender = v);
                  setState(() => _showGender = v);
                }),
                _optTile('메일', _showEmail, (v) {
                  setD(() => _showEmail = v);
                  setState(() => _showEmail = v);
                }),
                _optTile('항목(역할)', _showRoles, (v) {
                  setD(() => _showRoles = v);
                  setState(() => _showRoles = v);
                }),
                const Divider(height: 18),
                _sectionLabel('납부 여부'),
                _optTile('참가비 납부 여부', _showEventFee, (v) {
                  setD(() => _showEventFee = v);
                  setState(() => _showEventFee = v);
                }),
                _optTile('평생회원 여부', _showLifetime, (v) {
                  setD(() => _showLifetime = v);
                  setState(() => _showLifetime = v);
                }),
                _optTile(
                  '${widget.year.isNotEmpty ? '${widget.year}년 ' : ''}연회비 납부 여부',
                  _showYearFee,
                  (v) {
                    setD(() => _showYearFee = v);
                    setState(() => _showYearFee = v);
                  },
                ),
                const Divider(height: 18),
                _sectionLabel('참가신청 정보'),
                // [요구 2026-10-30] 추가입력사항 **항목별 컬럼** 토글.
                //  필요한 항목만 켜면 Excel 에서 바로 집계·정렬할 수 있다.
                _optTile('전체 (한 칸에 요약)', _showApply, (v) {
                  setD(() => _showApply = v);
                  setState(() => _showApply = v);
                }),
                for (final f in ExtraFields.all)
                  _optTile(f.label, _extraOn(f.key), (v) {
                    setD(() => _toggleExtra(f.key, v));
                    setState(() => _toggleExtra(f.key, v));
                  }),
                // 전체 켜기 / 끄기 — 한 번에 선택.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setD(() {
                            _showUnit = true;
                            _showGender = true;
                            _showEmail = true;
                            _showRoles = true;
                            _showEventFee = true;
                            _showLifetime = true;
                            _showYearFee = true;
                            _showApply = true;
                          });
                          setState(() {});
                        },
                        icon: const Icon(Icons.done_all, size: 17),
                        label: const Text('전체 선택'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          setD(() {
                            _showUnit = false;
                            _showGender = false;
                            _showEmail = false;
                            _showRoles = false;
                            _showEventFee = false;
                            _showLifetime = false;
                            _showYearFee = false;
                            _showApply = false;
                          });
                          setState(() {});
                        },
                        icon: const Icon(Icons.remove_done, size: 17),
                        label: const Text('전체 해제'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String s) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        s,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: AppColors.purple,
        ),
      ),
    ),
  );

  Widget _optTile(String label, bool val, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      controlAffinity: ListTileControlAffinity.leading,
      value: val,
      onChanged: (v) => onChanged(v == true),
      title: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _table() {
    if (widget.attendees.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(30),
        alignment: Alignment.center,
        child: const Text(
          '참가자가 없습니다',
          style: TextStyle(color: AppColors.textGray),
        ),
      );
    }
    // 항상: # · 접속 · 인가번호 · 이름 · 연락처 + 선택 컬럼
    final columns = <DataColumn>[
      const DataColumn(label: Text('#')),
      const DataColumn(label: Text('접속')),
      const DataColumn(label: Text('인가번호')),
      const DataColumn(label: Text('이름')),
      // [요구] 소속은 '현재 활동하는 곳(활동등록대)'을 먼저 노출한다.
      if (_showUnit) const DataColumn(label: Text('소속(활동)')),
      if (_showGender) const DataColumn(label: Text('성별')),
      const DataColumn(label: Text('연락처')),
      if (_showEmail) const DataColumn(label: Text('메일')),
      if (_showRoles) const DataColumn(label: Text('항목')),
      if (_showEventFee) const DataColumn(label: Text('참가비')),
      if (_showLifetime) const DataColumn(label: Text('평생')),
      if (_showYearFee)
        DataColumn(
          label: Text('${widget.year.isNotEmpty ? '${widget.year}년 ' : ''}연회비'),
        ),
      if (_showApply) const DataColumn(label: Text('참가신청')),
      // [요구 2026-10-30] 추가입력사항 — 항목마다 **독립 컬럼**(정의 순서).
      for (final f in ExtraFields.all)
        if (_extraOn(f.key)) DataColumn(label: Text(f.label)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEAE6)),
      ),
      clipBehavior: Clip.antiAlias,
      // PC 사용자를 위한 좌우 스크롤 화살표
      child: ScrollArrows(
        step: 220,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF6F4F1)),
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
          columnSpacing: 14,
          columns: columns,
          rows: [
            for (var i = 0; i < widget.attendees.length; i++)
              DataRow(
                cells: [
                  DataCell(
                    Text(
                      '${i + 1}',
                      style: const TextStyle(color: AppColors.textGray),
                    ),
                  ),
                  DataCell(_accessCell(widget.attendees[i])),
                  DataCell(
                    Text(
                      _num(widget.attendees[i]),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${widget.attendees[i]['name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  // [요구] 활동등록대(unitText) 우선 — 인가시 소속은 폴백.
                  if (_showUnit)
                    DataCell(
                      Text(
                        _first(widget.attendees[i], const ['unitText', 'unit']),
                        style: const TextStyle(color: AppColors.textGray),
                      ),
                    ),
                  if (_showGender)
                    DataCell(
                      Text(
                        _first(widget.attendees[i], const [
                          'genderText',
                          'gender',
                        ]),
                      ),
                    ),
                  DataCell(
                    Text(
                      _first(widget.attendees[i], const ['phoneText', 'phone']),
                    ),
                  ),
                  if (_showEmail)
                    DataCell(
                      Text(
                        _first(widget.attendees[i], const [
                          'emailText',
                          'email',
                        ]),
                        style: const TextStyle(color: AppColors.textGray),
                      ),
                    ),
                  if (_showRoles)
                    DataCell(Text(_rolesText(widget.attendees[i]))),
                  if (_showEventFee)
                    DataCell(_ynCell(widget.attendees[i]['eventFee'] == true)),
                  if (_showLifetime)
                    DataCell(_ynCell(widget.attendees[i]['lifetime'] == true)),
                  if (_showYearFee)
                    DataCell(_ynCell(widget.attendees[i]['yearFee'] == true)),
                  if (_showApply)
                    DataCell(
                      Text(
                        _applyText(widget.attendees[i]),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  // [요구 2026-10-30] 항목별 개별 셀 — 값이 없으면 공란.
                  for (final f in ExtraFields.all)
                    if (_extraOn(f.key))
                      DataCell(
                        Text(
                          f.valueOf(widget.attendees[i]),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: f.group == ExtraGroup.request
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: f.group == ExtraGroup.request
                                ? ExtraFields.colorOf(f.group)
                                : AppColors.textDark,
                          ),
                        ),
                      ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// [요구] 표시용 필드(서버 주입)를 우선 사용 — 개인카드 정보/활동등록대.
  String _first(Map<String, dynamic> a, List<String> keys) {
    for (final k in keys) {
      final v = '${a[k] ?? ''}'.trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _num(Map<String, dynamic> a) {
    // [요구] 서버가 준 표시용 인가번호(범#415/은하#43/일반#010…)를 우선한다.
    return _first(a, const ['numberLabel', 'number']);
  }

  Widget _ynCell(bool v) {
    return Text(
      v ? 'O' : '',
      style: TextStyle(
        fontWeight: FontWeight.w800,
        color: v ? AppColors.purple : AppColors.textGray,
      ),
    );
  }

  Widget _accessCell(Map<String, dynamic> a) {
    final v = a['visited'] == true;
    if (!v) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCCCCCC)),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.scoutGreen,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'V',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _rolesText(Map<String, dynamic> a) {
    final raw = a['rawRoles'];
    final roles = (raw is List ? raw : (a['roles'] as List?) ?? [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    return roles.join(', ');
  }

  /// 참가신청 입력항목 요약(도착·숙박·이동·동행·전달사항) — 선택 시 한 칸에 병기.
  String _applyText(Map<String, dynamic> a) {
    final bits = <String>[];
    for (final k in const ['arriveNote', 'arrive']) {
      final v = '${a[k] ?? ''}'.trim();
      if (v.isNotEmpty) {
        bits.add('도착 $v');
        break;
      }
    }
    for (final k in const ['transportNote', 'transport']) {
      final v = '${a[k] ?? ''}'.trim();
      if (v.isNotEmpty) {
        bits.add('이동 $v');
        break;
      }
    }
    final lodge = '${a['lodging'] ?? ''}'.trim();
    if (lodge.isNotEmpty) bits.add('숙박 $lodge');
    final comp = '${a['companion'] ?? ''}'.trim();
    if (comp.isNotEmpty) bits.add('동행 $comp');
    final msg = '${a['message'] ?? ''}'.trim();
    if (msg.isNotEmpty) bits.add(msg);
    return bits.join(' · ');
  }

  Widget _bottomBar() {
    return Material(
      color: Colors.white,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _busy ? null : _print,
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text(
                    '인쇄',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.taegeukBlue,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text(
                    '공유',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.taegeukBlue,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _busy ? null : _saveAs,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('출력/저장'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
