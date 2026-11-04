import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/event_custom_board.dart';
import '../widgets/marquee_text.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/event_finance_picks.dart';
import '../services/donation_doc.dart';
import '../services/attendee_roles.dart';
import '../services/extra_fields.dart';
import '../services/extra_output.dart';
import '../services/event_settlement.dart';
import '../services/file_pick.dart';
import '../services/file_save.dart';
import '../services/nas_api.dart';
import '../services/output_formats.dart';
import '../services/settlement_doc.dart';
import '../services/settlement_layout.dart';
import '../services/table_export.dart';
import '../services/table_options.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/tsak_form_sheet.dart';
import '../widgets/address_field.dart';
import '../widgets/donation_accounts.dart';
import '../widgets/donation_list_panel.dart';
import '../widgets/confirm.dart';
import '../widgets/event_account_picker.dart';
import '../widgets/hscroll_menu.dart';
import '../widgets/tsak_output_preview.dart';
import '../widgets/tsak_output_sheet.dart';
import '../widgets/tsak_table_options.dart';
import '../widgets/extra_fields_summary.dart';
import '../widgets/tsak_name_lookup.dart';
import 'roster_screen.dart';
import 'event_finance_tab.dart';
import 'event_review_screen.dart';
import 'event_settlement_tab.dart';
import 'member_detail_screen.dart';
import 'member_edit_screen.dart';
import 'role_permissions_screen.dart';

/// 행사 상세 — 항목(계획서/참석자/사진+동영상/참가비·후원금/행사비지출)
///
/// 관리자·마스터는 모든 항목 관리. 참가자는 사진+동영상 폴더만 접근한다.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.year,
    required this.title,
    required this.canManage,
  });

  final String year;
  final String title;
  final bool canManage;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic> _event = {};
  bool _loading = true;
  TabController? _tab;

  /// (요구 #14) 행사 스텝(STAFF) 여부 — 지정자는 해당 행사 전체 게시판이 노출된다.
  bool _isStaff = false;
  List<Map<String, dynamic>> _staff = [];

  /// (요구 #14) 스텝 포함 전체 게시판 노출 여부.
  bool get _fullView => widget.canManage || _isStaff;

  /// ── [요구 2026-10-26] "B + A 조합" ───────────────────────────────────
  ///  사용자 선택: **B(권한 없어도 항목은 회색으로 보이게) + A(스탭도 관리)**
  ///
  ///  ## 왜 이 조합인가
  ///   `widget.canManage` 는 `state.isApp || state.isMaster` 다. 그래서 스탭
  ///   계정(tiger415 등)은 `false` 가 되고, 종전에는 관리자 구역이 **통째로
  ///   렌더되지 않아** "메뉴 관리가 어디 있냐"는 문의가 반복됐다.
  ///   · A: 스탭도 그 행사의 메뉴/게시판을 관리할 수 있게 한다(서버도 수정).
  ///   · B: 그래도 권한이 없는 사람에게는 **항목을 회색으로 보여준다.**
  ///        기능이 어디 있는지는 알아야 요청할 수 있다.
  ///  → 두 가지를 합쳐 "보이되, 누를 수 있는 것만 눌린다"로 만든다.
  bool get _canManageMenu =>
      widget.canManage || _isStaff || _isMasterView;

  /// (요구) 마스터 전용 항목 노출 여부 — '관리'(관리자 세부권한) 탭은
  ///   마스터에게만 보인다.
  bool get _isMasterView {
    if (!widget.canManage) return false;
    try {
      return context.watch<AppState>().isMaster;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> _plan = [];

  /// 재무(참가비·후원금/후원/지출/결산) 로드 실패 사유.
  ///
  /// ## [버그 수정 2026-10-25]
  /// 종전에는 인증·통신 오류가 나도 목록이 그냥 빈 배열이 되어 화면에
  /// **"0건"** 으로 표시됐다. 사용자는 입력한 자료가 삭제된 것으로 오해했다.
  /// 이제 실패 사유를 담아 "불러오지 못했습니다 + 다시 시도" 로 구분해 보여준다.
  String? _financeError;
  List<Map<String, dynamic>> _media = [];
  List<Map<String, dynamic>> _attendees = [];

  /// 참가자 일괄 선택 모드.
  ///
  /// ## 요구: "참가자 삭제시 개인정보카드와 연계해서 참가행사에서도 삭제"
  ///  한 명씩 지우는 것만으로는 행사 정리 때 너무 느리다. 여러 명을 체크해
  ///  한 번에 삭제하면 서버가 그 인원 전원을 프로필에서 해제한다
  ///  (`linkedRemoved` 로 인원이 돌아온다).
  bool _selMode = false;

  /// 선택된 참가자 인덱스 집합.
  final Set<int> _selIdx = <int>{};

  /// 추가입력사항 블록을 **접어 둔** 참가자 키 집합.
  ///
  /// (요구 2026-10-31 5차) "접어두기 버튼 추가"
  ///  추가입력 항목이 7~8개면 카드 한 장이 화면을 다 먹어, 5명만 넘어도
  ///  명단이 안 보인다. 카드마다 **한 줄 요약 + 펼치기**로 접을 수 있게 한다.
  ///  키는 인덱스가 아니라 **참가자 식별자**를 쓴다 — 목록을 새로고침하거나
  ///  누군가를 삭제해도 접힘 상태가 엉뚱한 사람에게 붙지 않는다.
  final Set<String> _extraCollapsed = <String>{};

  /// 전체 접기/펼치기 상태 — null 이면 "사용자가 개별 조작한 상태".
  bool? _extraAllCollapsed;

  /// 참가자 한 명의 고유 키(접힘 상태 저장용).
  ///
  /// ⚠️ 번호 공간이 겹친다 — 은하 75 와 범 75 는 **다른 사람**이다.
  ///  그래서 '은하'→'G' 로 바꿔 접두를 살린다([_normCode] 와 같은 규칙).
  ///  이걸 빠뜨리면 은하75 와 범75 가 같은 키가 되어, 한 사람을 접으면
  ///  다른 사람까지 같이 접힌다.
  String _attendeeKey(Map<String, dynamic> a) {
    final raw = '${a['number'] ?? a['ident'] ?? a['phone'] ?? ''}';
    // 은하 표기 → G 접두 보존.
    var s = raw.trim().toUpperCase().replaceAll('은하', 'G');
    s = s.replaceAll('범', '').replaceAll(RegExp(r'[^0-9G]'), '');
    if (s.isNotEmpty) {
      final isG = s.startsWith('G');
      final d = s.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.isNotEmpty) return isG ? 'G$d' : d;
    }
    final nm = '${a['name'] ?? ''}'.trim();
    return nm.isEmpty ? 'row-${_attendees.indexOf(a)}' : 'nm:$nm';
  }
  Map<String, dynamic> _access = {};
  List<Map<String, dynamic>> _fees = [];
  List<Map<String, dynamic>> _expenses = [];

  /// 사용자 정의 '메뉴추가' 탭 목록 [{name, note}] (PDF page9 최종 결정).
  List<Map<String, dynamic>> _customTabs = [];

  /// (요구) 결산서 항목 배치(순서·출력 포함) — 탭을 오가도 유지.
  SettlementLayout? _settleLayout;

  /// (요구) 후원 출력 설정 — 후원자별/내역별 · 물품중심/금액중심.
  DonationViewMode _donView = DonationViewMode.bySponsor;
  DonationFocus _donFocus = DonationFocus.both;

  /// (요구) 출력에 노출할 항목 — '메모' 포함 9종을 직접 켜고 끈다.
  Set<DonationField> _donFields = DonationDocOptions().fields;

  int _cols = 5;
  int _pinchBaseCols = 3;

  /// 사진+동영상 하위폴더 탐색 스택 (예: ['봄행사','1팀'])
  List<String> _mediaPath = [];
  bool _mediaSelect = false;
  final Set<String> _mediaSel = {};

  /// (버그 수정) 나스에 **폴더 하나만** 있고 그 안에 사진이 전부 들어 있는
  /// 경우, 앱은 폴더 카드 1장만 보여줘 사용자에게는 "사진이 안 보인다"로
  /// 보였다(실측: `00 사진+동영상` 안에 387장). 폴더를 **자동으로 열어**
  /// 사진이 바로 보이게 한다. 사용자가 브레드크럼으로 루트에 돌아가면
  /// [_mediaAutoOpened] 로 다시 자동 진입하지 않는다.
  bool _mediaAutoOpened = false;

  /// 방금 _load 에서 읽은 '지금 폴더' 항목들(자동 진입 판단용).
  List<Map<String, dynamic>> _mediaHere = const [];

  /// (요구) "나스 내에 있는 폴더내 사진이 보여지지 않음" — 재귀 평탄화 보기.
  ///  사진이 `00 사진+동영상` 처럼 한 겹 안쪽 폴더에 있어도 한 번에 보인다.
  bool _mediaDeep = false;

  /// (요구) "앱 상단 제목과 나스 폴더명이 다릅니다" — 불일치 시 실제 폴더명.
  ///  {app: 앱 제목, nas: 나스 실제 폴더명} / null 이면 일치.
  Map<String, dynamic>? _folderAlias;

  String get _mediaSub => _mediaPath.join('/');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // [요구] 행사 폴더 열기 속도 개선 — 접근 이력 기록(로그)과 본문 로딩을
      //   직렬로 기다리지 않고 동시에 시작한다(로그 실패는 무시).
      _logMediaAccess();
      _load();
    });
  }

  /// 참가자가 접속하면 사진+동영상 접근 이력 기록
  Future<void> _logMediaAccess() async {
    if (widget.canManage) return;
    final s = context.read<AppState>();
    if (!s.isPersonal && !s.isGuest) return;
    try {
      await context.read<NasApi>().eventAccessLog(
        widget.year,
        widget.title,
        id: s.who,
        role: s.isGuest ? '일반회원' : '범인가자',
      );
    } catch (_) {}
  }

  NasApi get _nas => context.read<NasApi>();

  /// [fresh] true 면 서버 파일목록 캐시를 버리고 NAS 에서 다시 읽는다.
  ///  (요구) "직접 업로드 한 폴더가 보여지지 않는 버그" — PC·NAS 탐색기에서
  ///   직접 만든 폴더/사진은 서버 캐시에 없으므로 사용자가 새로고침할 수 있어야 한다.
  Future<void> _load({bool fresh = false}) async {
    setState(() => _loading = true);
    try {
      // [요구] 행사 폴더 열기 속도 개선 — 5개 API(행사·기획서·미디어·접근·재무)를
      //   순차(약 5×RTT)로 기다리던 것을 '동시 병렬' 호출로 바꾼다.
      //   가장 느린 1개 응답 시간에 수렴 → 체감 로딩 대폭 단축.
      // [안정] 간헐적 연결 끊김/일시 오류(예: 앞단 게이트웨이가 HTML 오류를
      //   반환)에 대비해 1회 자동 재시도한다. '불러오기 실패' 창이 뜨지 않게.
      Future<List<Object>> _fetchAll() => Future.wait<Object>([
        _nas.eventGet(widget.year, widget.title),
        _nas.eventFiles(widget.year, widget.title, 'plan'),
        _nas.eventFiles(
          widget.year,
          widget.title,
          'media',
          sub: _mediaSub,
          fresh: fresh,
        ),
        _nas.eventAccessMap(widget.year, widget.title),
      ]);

      List<Object> results;
      try {
        results = await _fetchAll();
      } catch (_) {
        // 짧게 쉬고 1회 재시도(순간적인 연결 폭주/끊김 흡수).
        await Future.delayed(const Duration(milliseconds: 700));
        results = await _fetchAll();
      }
      final e = results[0] as Map<String, dynamic>;
      final plan = results[1] as List<Map<String, dynamic>>;
      var media = results[2] as List<Map<String, dynamic>>;
      final access = results[3] as Map<String, dynamic>;

      // ── (요구 #14) 스탭 여부를 **재무 요청보다 먼저** 판정한다 ────────────
      //  종전에는 스탭 판정이 재무 조회 뒤에 있어서, 재무를 띄우려면
      //  `widget.canManage`(관리자·마스터)만 볼 수밖에 없었다.
      //  → 스탭에게 재무 탭이 0건으로 보이던 원인.
      //  이제 스탭이면 `canSeeFinance` 가 참이 되어 재무도 함께 불러온다.
      final staffList = ((e['staff'] as List?) ?? [])
          .map((x) => (x as Map).cast<String, dynamic>())
          .toList();
      //  async gap 이후이므로 mounted 확인 후에만 context 를 쓴다.
      if (!mounted) return;
      final appStateForStaff = context.read<AppState>();
      final myIdent = appStateForStaff.who.replaceAll(RegExp(r'[^0-9]'), '');
      bool isStaff = false;
      if (myIdent.isNotEmpty) {
        for (final a in staffList) {
          final id =
              '${a['number'] ?? a['ident'] ?? a['loginId'] ?? a['phone'] ?? ''}'
                  .replaceAll(RegExp(r'[^0-9]'), '');
          if (id.isNotEmpty && id == myIdent) {
            isStaff = true;
            break;
          }
        }
      }
      final bool canSeeFinance = widget.canManage || isStaff;

      // ── 재무(참가비·후원금 / 후원 / 지출 / 결산)는 **따로** 불러온다 ──────
      //
      // ## [버그 수정 2026-10-25] "기존 입력자료도 안 보이고 새로 넣은 값도 사라짐"
      //
      //  종전에는 재무를 위 Future.wait 배치에 **함께** 넣었다. 그래서 재무만
      //  인증오류(401)가 나도 배치 전체가 실패 → 참가자·사진·기획서까지
      //  "불러오기 실패"가 되거나, 반대로 401 JSON 이 조용히 파싱되어
      //  `fees`=null → **0건**으로 표시됐다. 사용자는 데이터가 삭제된 줄 알았다.
      //
      //  이제 재무는 분리해서:
      //   ① 인증오류면 화면 권한등급으로 **세션을 다시 발급**받고 1회 재시도.
      //   ② 그래도 실패하면 `_financeError` 에 사유를 담아 **0건과 구분**해
      //      화면에 "불러오지 못했습니다 + 다시 시도" 로 보여준다.
      Map<String, dynamic> fin = const {};
      String? financeError;
      // ── [버그 수정 2026-10-26] 스탭인데 재무가 안 보이던 문제 ────────────
      //  증상: 스탭으로 등록된 계정으로 행사에 들어가면 참가자·사진·계획서는
      //        보이는데 **참가비·후원금 / 후원·기타수입 / 행사비지출 / 결산**
      //        이 0원·"없음"으로 비어 있었다(마스터는 정상).
      //  원인: 재무 조회를 `widget.canManage`(= 관리자·마스터)로만 감쌌다.
      //        스탭 여부는 아래에서 판정하지만 **재무 요청 조건에 쓰지 않았다.**
      //        (서버도 `_require("admin")` 이라 스탭 세션은 401 이었다)
      //  해결: 재무 요청 조건을 `전체 열람 권한`(= 관리자·마스터·스탭)과 같게 둔다.
      //        스탭은 앱에서 이미 해당 행사 전체 열람 권한을 갖는다.
      if (canSeeFinance) {
        Future<Map<String, dynamic>> tryFin() =>
            _nas.eventFinance(widget.year, widget.title);
        try {
          fin = await tryFin();
        } on NasAuthException {
          // 세션 등급 불일치(personal 세션으로 관리화면 진입 등) → 자동 승격.
          //  await 전에 상태객체 참조를 잡아 두어 async gap 이후 context 사용을 피한다.
          final appState = context.read<AppState>();
          if (!mounted) return;
          final recovered = await appState.ensureServerSession(needAdmin: true);
          if (recovered) {
            try {
              fin = await tryFin();
            } on NasAuthException catch (err) {
              financeError = '$err';
            } catch (err) {
              financeError = '재무 자료를 불러오지 못했습니다. ($err)';
            }
          } else {
            financeError = '재무 자료 열람 권한이 없습니다. 다시 로그인해 주세요.';
          }
        } catch (err) {
          // 일시 오류는 1회만 더 시도(무한 대기 방지).
          try {
            await Future.delayed(const Duration(milliseconds: 500));
            fin = await tryFin();
          } catch (err2) {
            financeError = '재무 자료를 불러오지 못했습니다. ($err2)';
          }
        }
      }

      // [요구] "나스 내에 있는 폴더내 사진이 보여지지 않음" — 근본 해결.
      //  사진이 항목 폴더 바로 아래가 아니라 '00 사진+동영상' 처럼 한 겹
      //  더 안쪽 폴더에 있으면, 앱은 폴더 카드만 보여줬다(사용자는 빈 화면으로
      //  오해). 폴더만 있고 사진이 없으면 **재귀 평탄화(deep)** 로 다시 받아
      //  하위 폴더의 사진·동영상을 '한 화면에' 모두 보여준다.
      bool mediaDeep = false;
      if (_mediaPath.isEmpty) {
        final hasMediaHere = media.any((m) {
          final k = '${m['kind'] ?? ''}';
          return m['isdir'] != true && (k == 'image' || k == 'video');
        });
        final hasFolder = media.any((m) => m['isdir'] == true);
        if (!hasMediaHere && hasFolder) {
          try {
            final deepList = await _nas.eventFiles(
              widget.year,
              widget.title,
              'media',
              fresh: fresh,
              deep: true,
            );
            if (deepList.isNotEmpty) {
              media = deepList;
              mediaDeep = true;
            }
          } catch (_) {
            // 평탄화 실패 시 폴더 탐색 방식으로 그대로 진행.
          }
        }
      }
      _mediaDeep = mediaDeep;
      _folderAlias = _nas.lastFolderAlias;
      final atts = ((e['attendees'] as List?) ?? [])
          .map((x) => (x as Map).cast<String, dynamic>())
          .toList();
      List<Map<String, dynamic>> fees = [];
      List<Map<String, dynamic>> exps = [];
      if (canSeeFinance) {
        fees = ((fin['fees'] as List?) ?? [])
            .map((x) => (x as Map).cast<String, dynamic>())
            .toList();
        exps = ((fin['expenses'] as List?) ?? [])
            .map((x) => (x as Map).cast<String, dynamic>())
            .toList();
      }
      // [버그 수정] 재무가 '진짜로 비었는지'와 '못 불러왔는지'를 구분해 둔다.
      //  화면은 이 값으로 "0건" 대신 "불러오기 실패 + 다시 시도"를 보여준다.
      _financeError = financeError;
      if (!mounted) return;
      // (요구 #14) 스텝 여부는 위에서 이미 판정했다(isStaff) — 전체 게시판 노출.
      final fullView = canSeeFinance;
      setState(() {
        _event = e;
        _plan = plan;
        _media = media;
        _mediaHere = media;
        _mediaHere = media;
        _access = access;
        _attendees = atts;
        _isStaff = isStaff;
        _staff = staffList;
        _fees = fees;
        _expenses = exps;
        _customTabs = ((e['customTabs'] as List?) ?? [])
            .map((x) => (x as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
        // 기본 탭(고정) + 사용자 정의 '메뉴추가' 탭(PDF page9 최종 결정).
        final customCount = _customTabs.length;
        // [요구] 행사 탭 세분화 —
        //   참가자 / 사진+동영상 / 후기 / 기획서 / **참가비·후원금** /
        //   **후원·기타수입** / **행사비지출** / **행사결산** (+마스터 전용 **관리**)
        //   종전 '참가비·후원금' 한 탭에 섞여 있던 후원·기타수입을 분리하고,
        //   결산 탭을 새로 둔다. 총 8 + (마스터면 1) + 사용자 정의 탭.
        final len =
            (fullView ? 8 : 3) +
            (_isMasterView ? 1 : 0) +
            (fullView ? customCount : 0);
        // ⚠️ 버그 수정: _load() 마다 TabController 를 새로 만들면 index 가 0
        // (참가자 탭)으로 되돌아가, 사진+동영상 하위폴더에 진입해도 다시
        // 사진 탭으로 돌아가 버렸다. 현재 탭 인덱스를 보존한다.
        final prevIndex = _tab?.index ?? 0;
        if (_tab == null || _tab!.length != len) {
          _tab?.dispose();
          _tab = TabController(
            length: len,
            vsync: this,
            initialIndex: prevIndex.clamp(0, len - 1),
          );
        }
        if (!fullView) _tab!.index = 0;
      });

      // ── 사진 폴더 자동 진입 ────────────────────────────────────────────
      //  이 행사의 '사진+동영상' 루트에 **미디어 파일이 하나도 없고 폴더만**
      //  있으면, 그 폴더가 유일할 때 자동으로 열어 준다.
      //  (PC 에서 만든 폴더에 사진을 몰아넣은 경우가 대부분 — 사용자는
      //   폴더 카드만 보고 "사진이 안 보인다"고 느꼈다.)
      if (!_mediaDeep && _mediaPath.isEmpty && !_mediaAutoOpened) {
        final hasMediaHere = media.any((m) {
          final k = '${m['kind'] ?? ''}';
          return m['isdir'] != true && (k == 'image' || k == 'video');
        });
        final dirs = media.where((m) => m['isdir'] == true).toList();
        if (!hasMediaHere && dirs.length == 1) {
          final only = '${dirs.first['name']}';
          if (only.isNotEmpty && (dirs.first['count'] ?? 0) != 0) {
            _mediaAutoOpened = true;
            // 다음 프레임에 폴더 진입(현재 setState 사이클을 깨지 않도록).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _mediaPath.isNotEmpty) return;
              _enterFolder(only, auto: true);
            });
          }
        }
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('불러오기 실패: $err')));
    }
    if (mounted) hideBusy();
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // [요구] 상단 탭 순서 — 참가자 → 사진+동영상 → 후기 → 기획서 →
    //   참가비·후원금 → 후원·기타수입 → 행사비지출 → 행사결산 (+ 마스터: 관리).
    //   '후기'는 별도 탭 화면(_reviewTab)이며, 기존 우측 상단 아이콘도 유지한다.
    final baseTabs = const [
      '참가자',
      '사진+동영상',
      '후기',
      '기획서',
      '참가비·후원금',
      '후원·기타수입',
      '행사비지출',
      '행사결산',
    ];
    // (요구) 관리자권한 — 마스터 항목은 마스터에게만 노출한다.
    // ── [요구 2026-10-26] "상부 버튼은 모두에게 노출되지만, 게시물은
    //   권한이 있는 사람에게만 노출됨"
    //   → 커스텀 게시판 **탭(버튼)** 은 모든 인가자에게 보인다. 글 목록은
    //     서버가 노출권한(all/staff/admin)으로 거르고, 볼 수 없으면 게시판
    //     안에서 "권한이 없습니다"만 안내한다(탭 자체를 숨기지 않는다).
    final tabs = _fullView
        ? <String>[
            ...baseTabs,
            if (_isMasterView) '관리',
            ..._customTabs.map((e) => '${e['name'] ?? ''}'),
          ]
        : <String>[
            '참가자',
            '사진+동영상',
            '후기',
            ..._customTabs.map((e) => '${e['name'] ?? ''}'),
          ];
    return Scaffold(
      appBar: TsakAppBar(
        title: Row(
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarqueeText(
                    widget.title,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    '${widget.year}'
                    '${'${_event['place'] ?? ''}'.isNotEmpty ? ' · ${_event['place']}' : ''}'
                    '${((_event['credViewers'] as num?)?.toInt() ?? 0) > 0 ? ' · 👁 인가자 ${(_event['credViewers'] as num).toInt()}명 열람' : ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
            // [turn9-6] 행사명 옆 QR 아이콘 (PDF page9 최종 결정) — 참가 등록 QR.
            // (요구) 장소 클릭 → 카카오지도에서 위치 표시.
            if ('${_event['place'] ?? ''}'.trim().isNotEmpty)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '지도에서 위치 보기',
                onPressed: _openEventMap,
                icon: const Icon(Icons.place_outlined, size: 20),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '행사 QR 코드 (참가신청 / 게시판)',
              onPressed: _showEventQr,
              icon: const Icon(Icons.qr_code_2, size: 20),
            ),
          ],
        ),
        bottom: _tab == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: HsTabStrip(controller: _tab!, labels: tabs),
              ),
        actions: [
          const AppHomeEmblem(size: 22),
          // 후기 게시판 — 개인(범스카우트·일반회원)도 행사 후기를 열람/작성한다.
          IconButton(
            tooltip: '행사 후기 게시판',
            icon: const Icon(Icons.forum_outlined),
            onPressed: _openReview,
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          // ── [요구 2026-10-26] 메뉴(⋯)는 **항상 노출**한다.
          //  종전에는 `if (widget.canManage)` 로 통째로 감싸서, 권한 판정이
          //  어긋나면(예: 스탭 계정·세션 등급 불일치) 메뉴 자체가 사라져
          //  "메뉴 관리 기능이 없다"고 보였다.
          //  이제는 누구에게나 보이고, 항목을 **권한별 구역**으로 나눈다.
          PopupMenuButton<String>(
            tooltip: '행사 메뉴',
            onSelected: (v) {
              switch (v) {
                case 'zip':
                  _download(
                    context.read<NasApi>().eventZipUrl(
                      widget.year,
                      widget.title,
                      'media',
                    ),
                  );
                  break;
                case 'request':
                  _requestPhoto();
                  break;
                case 'qr':
                  _showEventQr();
                  break;
                case 'staff':
                  _manageStaff();
                  break;
                case 'addmenu':
                  _addCustomTab();
                  break;
                case 'managemenu':
                  _manageCustomTabs();
                  break;
                case 'boarddelete':
                  _deleteCustomBoard();
                  break;
              }
            },
            itemBuilder: (_) {
              // 권한 3단계를 **구역으로 분리**해 보여준다(요구: "관리자/마스터
              //  권한으로 구분해서 정리해줘").
              //  ── [요구 2026-10-26] "B + A 조합" ────────────────────────
              //  B: 권한이 없어도 항목을 **회색(disabled)** 으로 보여준다.
              //     → 기능이 어디 있는지 알 수 있어야 요청도 할 수 있다.
              //  A: 행사 스탭은 실제로 **누를 수 있다**(서버도 스탭 허용).
              final isMaster = _isMasterView;
              final isAdmin = _canManageMenu;
              // 실제로 실행 가능한가 (스탭 포함)
              final canRun = _canManageMenu;
              // 회색 처리 + 오른쪽에 사유 배지
              Widget gate(String label, {IconData? icon, Color? color}) => Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 15,
                            color: canRun ? (color ?? AppColors.purple)
                                          : AppColors.textGray),
                        const SizedBox(width: 6),
                      ],
                      Expanded(child: Text(label)),
                      if (!canRun)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.lock_outline,
                              size: 13, color: AppColors.textGray),
                        ),
                    ],
                  );
              return [
                // ── 공통(모든 인가자) ──────────────────────────────
                const PopupMenuItem<String>(
                  enabled: false,
                  height: 26,
                  child: Text(
                    '공통',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textGray,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const PopupMenuItem(
                  value: 'zip',
                  child: Text('사진 전체 ZIP 다운로드'),
                ),
                const PopupMenuItem(
                  value: 'request',
                  child: Text('전체 참가자 사진 업로드 요청'),
                ),
                // ── 관리자·마스터·스탭 ─────────────────────────────
                //  ⚠️ 종전 `if (isAdmin) ...` 로 **통째로 감싸서** 권한이
                //   없으면 항목이 아예 안 보였다(B 요구의 원인).
                //   이제는 **항상 그리고**, 권한이 없으면 enabled:false 로
                //   회색 처리한다.
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  enabled: false,
                  height: 26,
                  child: Text(
                    isMaster
                        ? '관리자·마스터 전용'
                        : (canRun ? '관리자·스탭 전용' : '관리자·스탭 전용 (권한 없음)'),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: canRun ? AppColors.purple : AppColors.textGray,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'qr',
                  enabled: isAdmin,
                  child: gate('행사 QR 코드 (참가신청 / 게시판)'),
                ),
                PopupMenuItem(
                  value: 'staff',
                  enabled: isAdmin,
                  child: gate('행사 스텝(STAFF) 등록',
                      icon: Icons.badge_outlined),
                ),
                PopupMenuItem(
                  value: 'addmenu',
                  enabled: isAdmin,
                  child: gate('메뉴 추가 (사용자 정의 탭)',
                      icon: Icons.add_box_outlined),
                ),
                // 메뉴 관리 — 관리자·스탭도 열 수 있다. 단, 게시판 통째로
                //  삭제는 마스터만.
                PopupMenuItem(
                  value: 'managemenu',
                  enabled: isAdmin,
                  child: gate('메뉴 관리 (추가·변경·삭제)',
                      icon: Icons.dashboard_customize_outlined),
                ),
                // ── 마스터 전용 ────────────────────────────────────
                //  B 요구에 따라 마스터가 아니어도 **회색으로 보여준다**.
                if (!isMaster) const PopupMenuDivider(),
                if (!isMaster)
                  const PopupMenuItem<String>(
                    enabled: false,
                    height: 26,
                    child: Text(
                      '마스터 전용 (권한 없음)',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textGray,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                if (isMaster) ...[
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    enabled: false,
                    height: 26,
                    child: Text(
                      '마스터 전용',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.tigerGold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
                // B 요구: 마스터가 아니어도 **회색으로는 보여준다**.
                PopupMenuItem(
                  value: 'boarddelete',
                  enabled: isMaster,
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever_outlined,
                          size: 15,
                          color: isMaster
                              ? AppColors.taegeukRed
                              : AppColors.textGray),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('게시판 통째로 삭제')),
                      if (!isMaster)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.lock_outline,
                              size: 13, color: AppColors.textGray),
                        ),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: _loading || _tab == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // (요구#3) 후기 — 위치를 본문 상단으로 옮겨 **모든 회원**이
                //  관리자 여부와 무관하게 바로 열람·작성할 수 있게 한다.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.scoutGreen,
                        side: BorderSide(
                          color: AppColors.scoutGreen.withValues(alpha: 0.5),
                        ),
                        backgroundColor: AppColors.scoutGreen.withValues(
                          alpha: 0.06,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: _openReview,
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      label: const Text(
                        '행사 후기 (모든 회원 열람·작성)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
                // 참가자(개인 접근): 참가비·후원 납부 계좌 3개 + 송금 버튼
                if (!_fullView)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: DonationAccounts(
                      title: '참가비·후원 납부 계좌',
                      showHolder: true,
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: _fullView
                        ? [
                            _attendeeTab(),
                            _mediaTab(),
                            // [요구] 후기 탭 — 참가자→사진+동영상→후기→기획서→…
                            EventReviewScreen(
                              year: widget.year,
                              title: widget.title,
                              embedded: true,
                            ),
                            _planTab(),
                            // (요구) 참가비/후원금 · 후원·기타수입 · 행사비지출
                            //   세 탭으로 분리. 같은 데이터(fees)를 구분(category)
                            //   으로 나눠 보여준다.
                            _financeTab('fee'),
                            _financeTab('donation'),
                            _financeTab('expense'),
                            // (요구) 행사결산 — 항목별 취합 · 출력 선택 · 순서 이동
                            //   · 실시간 미리보기.
                            EventSettlementTab(
                              year: widget.year,
                              title: widget.title,
                              attendees: _attendees,
                              fees: _fees,
                              expenses: _expenses,
                              initialLayout: _settleLayout,
                              onLayoutChanged: (l) => _settleLayout = l,
                              onOutput: _outputSettlement,
                              onOutputAttendees: _outputAttendees,
                              // (요구) 미리보기 시트 안 '인쇄' 버튼 —
                              //  시트를 닫지 않고 바로 브라우저 인쇄창을 연다.
                              onPrint: (layout, data) =>
                                  _doPrint(_settlementDoc(layout, data)),
                            ),
                            if (_isMasterView) _masterManageTab(),
                            for (final t in _customTabs) _customTabView(t),
                          ]
                        // [요구] 일반 참가자(비스텝): 참가자(읽기) · 사진+동영상 · 후기.
                        //   참가자 탭은 이름·인가번호만 노출(개인정보 없음).
                        : [
                            _attendeeTab(),
                            _mediaTab(),
                            EventReviewScreen(
                              year: widget.year,
                              title: widget.title,
                              embedded: true,
                            ),
                            //  [요구 2026-10-26] "상부 버튼은 모두에게 노출되지만,
                            //   게시물은 권한이 있는 사람에게만 노출됨"
                            //   → 커스텀 게시판 탭은 일반 참가자에게도 노출한다.
                            //     글은 서버가 노출권한(all/staff/admin)으로 거르고,
                            //     볼 수 없으면 게시판 안에서 안내만 한다.
                            for (final t in _customTabs) _customTabView(t),
                          ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _download(String url) async {
    // [사고 대응] 사진 폴더 전체(수 GB)를 ZIP 으로 받으면 서버가 메모리 부족으로
    //  죽었다. 서버는 이제 용량을 사전에 검사해 413(too large)으로 거절하고,
    //  우리는 그 URL 을 미리 조회해 **사람이 읽을 수 있는 안내**로 바꿔준다.
    //  (브라우저 새 창에 raw JSON 이 뜨는 것을 막는다)
    if (url.contains('/api/event/zip')) {
      final tooBig = await _zipTooLargeHint(url);
      if (tooBig != null) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('폴더가 너무 큽니다'),
            content: Text(tooBig),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        return;
      }
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      _snack('다운로드 실패: $e');
    }
  }

  /// ZIP 요청이 413 이면 안내 문구를, 아니면 null 을 돌려준다.
  ///  실제 다운로드(브라우저)를 막지 않도록 HEAD 가 아니라 '가벼운 선검사'만 한다.
  Future<String?> _zipTooLargeHint(String url) async {
    try {
      final probe = url.contains('?') ? '$url&probe=1' : '$url?probe=1';
      final r = await http
          .get(Uri.parse(probe))
          .timeout(const Duration(seconds: 120));
      if (r.statusCode == 413) {
        return '이 폴더의 전체 용량이 서버 제한을 넘습니다.\n\n'
            '· 폴더를 나누어(하위 폴더별로) 받으시거나\n'
            '· 사진을 선택한 뒤 "선택 다운로드"를 사용하세요.';
      }
    } catch (_) {
      // 선검사 실패는 무시하고 정상 다운로드로 진행.
    }
    return null;
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ============================ 계획서 ============================
  Widget _planTab() {
    return _fileListPane(
      key: 'plan',
      files: _plan,
      emptyText: '계획서를 업로드하세요 (엑셀·워드·PDF 등)',
      allowedExts: const ['xlsx', 'xls', 'docx', 'doc', 'pdf', 'hwp', 'txt'],
    );
  }

  Widget _fileListPane({
    required String key,
    required List<Map<String, dynamic>> files,
    required String emptyText,
    List<String> allowedExts = const [],
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _uploadFiles(key, allowedExts: allowedExts),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('파일 업로드'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    _download(_nas.eventZipUrl(widget.year, widget.title, key)),
                icon: const Icon(Icons.download),
                label: const Text('ZIP'),
              ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? Center(
                  child: Text(
                    emptyText,
                    style: const TextStyle(color: AppColors.textGray),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = files[i];
                    final name = '${f['name']}';
                    final size = (f['size'] as num?)?.toInt() ?? 0;
                    final kind = '${f['kind'] ?? 'other'}';
                    final up = '${f['uploader'] ?? ''}';
                    // ── [개선 2026-10-26] 이미지 파일은 아이콘 대신 **미리보기** ──
                    //  종전엔 kind 와 무관하게 아이콘만 그려서, 계획서·영수증
                    //  폴더에 사진을 올려도 목록에서 내용을 확인할 수 없었다.
                    //  썸네일은 이 패널의 폴더 key 를 그대로 넘겨 받는다
                    //  (key 를 안 넘기면 서버가 media 폴더를 뒤져 404 가 된다).
                    final lead = kind == 'image'
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              _nas.eventThumb2Url(
                                widget.year,
                                widget.title,
                                name,
                                size: 'normal',
                                key: key,
                              ),
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              headers: _nas.imageAuthHeaders,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.image_outlined,
                                color: AppColors.purple,
                              ),
                            ),
                          )
                        : Icon(
                            kind == 'video'
                                ? Icons.videocam_outlined
                                : Icons.description_outlined,
                            color: AppColors.purple,
                          );
                    return ListTile(
                      leading: lead,
                      title: Text(name),
                      subtitle: Text(
                        '${_fmtSize(size)}'
                        '${up.isNotEmpty ? ' · $up' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'open') {
                            _download(
                              _nas.eventFile2Url(
                                widget.year,
                                widget.title,
                                key,
                                name,
                              ),
                            );
                          } else if (v == 'dl') {
                            _download(
                              _nas.eventFile2Url(
                                widget.year,
                                widget.title,
                                key,
                                name,
                                download: true,
                              ),
                            );
                          } else if (v == 'rename') {
                            await _renameFile(key, name);
                          } else if (v == 'del') {
                            await _deleteFile(key, name);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'open', child: Text('열기')),
                          PopupMenuItem(value: 'dl', child: Text('다운로드')),
                          PopupMenuItem(value: 'rename', child: Text('이름 변경')),
                          PopupMenuItem(value: 'del', child: Text('삭제')),
                        ],
                      ),
                      onTap: () => _download(
                        _nas.eventFile2Url(
                          widget.year,
                          widget.title,
                          key,
                          name,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _uploadFiles(
    String key, {
    List<String> allowedExts = const [],
    String? uploader,
    String sub = '',
    VoidCallback? onDone,
  }) async {
    final state = context.read<AppState>();
    // 사진·동영상(초상 포함) 업로드 시에는 초상 활용 동의를 먼저 확인한다.
    if (key == 'media') {
      final ok = await _confirmPhotoConsent();
      if (ok != true) return;
    }
    final upName =
        uploader ??
        (state.isMaster
            ? '마스터'
            : state.isApp
            ? '관리자'
            : state.who);
    final picked = await pickDataFiles(
      allowedExtensions: allowedExts,
      allowMultiple: true,
      dialogTitle: '파일 선택',
    );
    if (picked.isEmpty) return;
    var done = 0;
    // 공통 "작업중" 오버레이 — 멈춘 것이 아님을 보여준다(업로드 진행률 포함).
    showBusy(
      context,
      title: '사진·동영상 업로드 중입니다',
      lines: [
        'NAS 서버로 파일을 전송하고 있습니다...',
        '총 ${picked.length}개 중 0개 완료',
        '창을 닫지 마세요. 잠시만 기다려 주세요...',
      ],
    );
    for (final p in picked) {
      try {
        updateBusy(
          lines: [
            '전송 중: ${p.name}',
            '총 ${picked.length}개 중 ${done + 1}개 진행 중',
            '완료 $done개 · 남은 ${picked.length - done - 1}개',
          ],
          progress: picked.isEmpty ? null : (done / picked.length),
        );
        await _nas.eventUpload2(
          widget.year,
          widget.title,
          key,
          p.name,
          p.bytes,
          contentType: _contentType(p.name),
          uploader: upName,
          sub: sub,
        );
        done++;
      } catch (e) {
        _snack('업로드 실패: ${p.name} ($e)');
      }
    }
    hideBusy();
    onDone?.call();
    await _load();
  }

  String _contentType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.mp4')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  /// 사진·동영상 업로드 전 초상(사진) 활용 동의 확인 다이얼로그.
  /// (청소년 얼굴이 포함될 수 있어 행사 사진 게시 전 동의를 받는다)
  Future<bool?> _confirmPhotoConsent() {
    bool agreed = false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          icon: const Icon(Icons.photo_camera_front, color: AppColors.purple),
          title: const Text('사진·영상 게시 동의 확인'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '행사 사진·영상에는 참가자(청소년 포함)의 얼굴(초상)이 담길 수 '
                    '있습니다. 게시 전 아래 내용을 확인하고 동의해 주세요.',
                    style: TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.purple.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Text(
                      '· 촬영·게시 목적: 행사 기록·결과 보고·중앙회 홍보\n'
                      '· 게시 범위: 중앙회 앱(인가자 열람)·홈페이지·네이버 카페·소식지\n'
                      '· 동의 철회: 게시 후 삭제 요청 가능(담당자에게 연락)\n'
                      '· 업로드 권한은 인가자(관리자)에게 있으며, 게시 책임은 업로드한 사람에게 있습니다.',
                      style: TextStyle(fontSize: 11.5, height: 1.55),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => setLocal(() => agreed = !agreed),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Checkbox(
                            value: agreed,
                            onChanged: (v) =>
                                setLocal(() => agreed = v ?? false),
                          ),
                          const Expanded(
                            child: Text(
                              '참가자(페런츠 포함)의 초상 활용에 동의하며 게시합니다',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Text(
                    '※ 동의 없이 게시할 수 없습니다. 원하지 않는 참가자는 게시 전 담당자에게 알릴 수 있습니다.',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: agreed ? AppColors.purple : Colors.grey,
              ),
              onPressed: agreed ? () => Navigator.pop(ctx, true) : null,
              child: const Text('동의하고 업로드'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameFile(String key, String name, {String sub = ''}) async {
    final ctrl = TextEditingController(text: name);
    // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 바텀시트로 전환.
    final ok = await showTsakFormSheet(
      context: context,
      title: '이름 변경',
      subtitle: '파일 이름을 새로 입력하세요',
      icon: Icons.drive_file_rename_outline,
      saveLabel: '저장',
      builder: (ctx, setSheetState) => SizedBox(
        width: 420,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '새 이름'),
        ),
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await _nas.eventFileRename(
      widget.year,
      widget.title,
      key,
      name,
      ctrl.text.trim(),
      sub: sub,
    );
    await _load();
  }

  Future<void> _deleteFile(
    String key,
    String name, {
    String sub = '',
    bool isdir = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제'),
        content: Text(isdir ? '“$name” 폴더를 삭제할까요?' : '“$name”을(를) 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _nas.eventFileDelete(
      widget.year,
      widget.title,
      key,
      name,
      sub: sub,
      isdir: isdir,
    );
    await _load();
  }

  /// (요구) 행사 장소를 카카오지도에서 연다 — 기획 시 지정한 좌표 우선.
  Future<void> _openEventMap() async {
    final place = '${_event['place'] ?? ''}'.trim();
    final lat = '${_event['lat'] ?? ''}'.trim();
    final lng = '${_event['lng'] ?? ''}'.trim();
    String url;
    if (lat.isNotEmpty && lng.isNotEmpty) {
      final nm = Uri.encodeComponent(
        '${_event['title'] ?? widget.title}'.trim().isEmpty
            ? place
            : '${_event['title'] ?? widget.title}'.trim(),
      );
      url = 'https://map.kakao.com/link/map/$nm,$lat,$lng';
    } else {
      final q = '${_event['title'] ?? widget.title} $place'.trim();
      url = 'https://map.kakao.com/link/search/${Uri.encodeComponent(q)}';
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('지도를 열 수 없습니다')));
      }
    }
  }

  /// 행사 QR 링크를 연다(요구: 행사 QR·링크주소 클릭 → 접속).
  ///
  ///  · 웹: 같은 창에서 접속 주소로 이동(새 탭 아님).
  ///  · 그 외: 외부 브라우저/앱으로 연다.
  ///  · 열 수 없으면 주소를 복사해 준다.
  Future<void> _openEventQrLink(String payload) async {
    if (!payload.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '공개 접속 주소가 설정되지 않아 링크를 열 수 없습니다.\n설정 → "QR 공개 주소"를 입력하세요.',
          ),
        ),
      );
      return;
    }
    final uri = Uri.parse(payload);
    try {
      // 웹에서는 같은 창(_self)으로 이동해 새 탭/팝업 차단을 피하고,
      //  곧바로 접속(딥링크)되게 한다.
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      if (!ok) {
        final ok2 = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok2) throw Exception('open failed');
      }
    } catch (_) {
      if (!mounted) return;
      Clipboard.setData(ClipboardData(text: payload));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 주소창에 붙여넣어 접속하세요. (주소를 복사했습니다)')),
      );
    }
  }

  /// 행사 QR 코드 — **두 종류**를 한 화면에서 각각 보여준다.
  ///
  /// (요구) "행사별 QR 생성은 행사 참가 신청에 대한 QR 입니다.
  ///   행사 참가 신청 QR 과 각 행사폴더에 바로 접근할 수 있는 QR 을 따로 만들 수
  ///   있도록 해줘. 각 QR 상단에 그 행사명과 QR 의 종류를 명확히 해줘.
  ///   1. 행사 참가신청  2. 행사 게시판"
  ///
  /// ① 참가 신청 — 경량 착지 페이지(`/qr.html`). 앱 다운로드 없이 바로 신청.
  /// ② 행사 게시판 — `/?access=event&year=…&title=…` 로 앱을 열어 행사 상세
  ///    (자료·사진·후기)로 직행.
  ///
  /// 각 QR 위에 ① 행사명 ② QR 종류 ③ 대상(누가 쓰는지) 을 **명시**한다.
  void _showEventQr() {
    final state = context.read<AppState>();
    final applyLink = state.eventApplyQrLink(widget.year, widget.title);
    final boardLink = state.eventBoardQrLink(widget.year, widget.title);

    showDialog<void>(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 행사명 (모든 QR 상단에 공통으로 명시) ──
              const Text('행사 QR 코드', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                '${widget.year} · ${widget.title}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                  height: 1.3,
                ),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ⚠️ (버그수정) 상단 탭 테마가 '흰 글자'라 밝은 다이얼로그에서
                //  '1. 행사 참가신청 / 2. 행사 게시판' 이 보이지 않았다.
                //  여기서는 색을 **명시**해 테마와 무관하게 읽히도록 한다.
                TabBar(
                  labelColor: AppColors.purpleDark,
                  unselectedLabelColor: AppColors.textGray,
                  indicatorColor: AppColors.purple,
                  dividerColor: AppColors.purple.withValues(alpha: 0.15),
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [
                    Tab(text: '1. 행사 참가신청'),
                    Tab(text: '2. 행사 게시판'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 400,
                  child: TabBarView(
                    children: [
                      _qrPane(
                        ctx: ctx,
                        kind: '1. 행사 참가신청',
                        who: '비회원·외부인 포함 — 스캔하면 신청 화면이 바로 열립니다',
                        payload: applyLink,
                        hasBase: state.hasQrBase,
                        // (요구) 참가신청 QR 색상을 녹색 → **검정**으로.
                        color: const Color(0xFF111111),
                        icon: Icons.how_to_reg_outlined,
                      ),
                      _qrPane(
                        ctx: ctx,
                        kind: '2. 행사 게시판',
                        who: '로그인한 회원 — 스캔하면 이 행사 자료·사진·후기로 바로 들어갑니다',
                        payload: boardLink,
                        hasBase: state.hasQrBase,
                        color: AppColors.purple,
                        icon: Icons.dashboard_customize_outlined,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }

  /// QR 한 칸 — ① 종류 ② 행사명 ③ 안내 ④ QR ⑤ 주소 순으로 명확히 적는다.
  Widget _qrPane({
    required BuildContext ctx,
    required String kind,
    required String who,
    required String payload,
    required bool hasBase,
    required Color color,
    required IconData icon,
  }) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── QR 종류 배지 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  kind,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ── QR ──
          Tooltip(
            message: 'QR/링크를 클릭하면 접속 화면이 열립니다',
            child: InkWell(
              onTap: () => _openEventQrLink(payload),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 190,
                  backgroundColor: Colors.white,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: color,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            who,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textGray,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          // ── 주소(클릭하면 열림) ──
          InkWell(
            onTap: () => _openEventQrLink(payload),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                payload,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  decoration: TextDecoration.underline,
                  decorationColor: color,
                ),
              ),
            ),
          ),
          if (!hasBase) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.taegeukRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.taegeukRed.withValues(alpha: 0.4),
                ),
              ),
              child: const Text(
                '⚠ 공개 접속 주소가 설정되지 않아 상대경로입니다.\n'
                '설정 → "QR 공개 주소"에서 배포 주소를 입력하세요.',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.4,
                  color: AppColors.taegeukRed,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // ── 복사 / 열기 ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: payload));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$kind 주소를 복사했습니다')),
                  );
                },
                icon: const Icon(Icons.link, size: 16),
                label: const Text('주소 복사', style: TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: () => _openEventQrLink(payload),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('열기', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================ 참석자 ============================
  Widget _attendeeTab() {
    return Column(
      children: [
        // (요구 #13) 참가자 등록은 관리자·마스터만 가능하다.
        if (widget.canManage)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                    ),
                    onPressed: _searchAndAddAttendee,
                    icon: const Icon(Icons.search),
                    label: const Text('인가자 검색'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _manualAddAttendee,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('수동 입력'),
                  ),
                ),
              ],
            ),
          ),
        // ── 일괄 선택 툴바 (요구: 여러 명 한 번에 삭제) ──────────────────
        if (widget.canManage && _attendees.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _selMode
                ? Row(
                    children: [
                      Text(
                        '${_selIdx.length}명 선택',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.purple,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => setState(() {
                          if (_selIdx.length == _attendees.length) {
                            _selIdx.clear();
                          } else {
                            _selIdx
                              ..clear()
                              ..addAll(
                                List<int>.generate(_attendees.length, (i) => i),
                              );
                          }
                        }),
                        child: Text(
                          _selIdx.length == _attendees.length
                              ? '전체 해제'
                              : '전체 선택',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.taegeukRed,
                        ),
                        onPressed: _selIdx.isEmpty ? null : _deleteSelected,
                        icon: const Icon(Icons.delete_sweep, size: 17),
                        label: Text(
                          '선택 삭제 (${_selIdx.length})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 4),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => setState(() {
                          _selMode = false;
                          _selIdx.clear();
                        }),
                        child: const Text('취소', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => setState(() {
                        _selMode = true;
                        _selIdx.clear();
                      }),
                      icon: const Icon(Icons.checklist, size: 17),
                      label: const Text(
                        '여러 명 선택',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
          ),
        if (_isStaff && !widget.canManage)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Text(
              '행사 스텝으로 등록되어 참가자 명단을 열람합니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
          ),
        // [요구] 일반 참가자(비스텝): 이름·인가번호만 열람(개인정보 비노출) 안내.
        if (!widget.canManage && !_isStaff)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: Text(
              '참가자 명단을 열람합니다 — 이름·인가번호만 표시됩니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
          ),
        // [요구] 명단 출력·문자·메일은 개인정보(연락처·메일)를 포함하므로
        //   스텝·관리자·마스터(_fullView)에게만 노출한다(참가자 열람 불가).
        if (_fullView)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _rosterButton(Icons.table_chart, '명단 출력', () => _openRoster()),
                const SizedBox(width: 6),
                // [요구 2026-10-30] 추가입력사항 **항목별 취합**.
                //  "항목별로 취합도 가능해야 해" → 이동·숙박·도착 집계 +
                //  자유입력 명단 + 전달사항 전문을 한 화면에.
                _rosterButton(
                  Icons.summarize,
                  '추가입력 취합',
                  _openExtraSummary,
                ),
                const SizedBox(width: 6),
                // (요구 2026-10-31) 추가항목별 인원 확인 — **출력 옵션**.
                _rosterButton(
                  Icons.bar_chart,
                  '항목별 인원',
                  _outputExtraHeadcount,
                ),
                const SizedBox(width: 6),
                _rosterButton(Icons.sms, '문자', _sendSms),
                const SizedBox(width: 6),
                _rosterButton(Icons.mail, '메일', _sendMail),
                const Spacer(),
                Text(
                  '${_attendees.length}명',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.purple,
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Spacer(),
                Text(
                  '${_attendees.length}명',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.purple,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        // (요구 2026-10-31 5차) "접어두기 버튼 추가" — 전체 접기/펼치기.
        //  카드마다 하나씩 누르는 대신 **한 번에** 정리할 수 있게 한다.
        if (_fullView && _attendees.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() {
                    final anyOpen = _attendees.any((a) {
                      final filled = ExtraFields.filled(a);
                      if (filled.isEmpty) return false;
                      return !_extraCollapsed.contains(_attendeeKey(a));
                    });
                    // 하나라도 펼쳐져 있으면 → 전부 접기, 아니면 → 전부 펼치기.
                    if (anyOpen) {
                      _extraCollapsed.addAll(
                        _attendees.map(_attendeeKey),
                      );
                      _extraAllCollapsed = true;
                    } else {
                      _extraCollapsed.clear();
                      _extraAllCollapsed = false;
                    }
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.purple.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _extraAllCollapsed == true
                              ? Icons.unfold_more
                              : Icons.unfold_less,
                          size: 14,
                          color: AppColors.purple,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _extraAllCollapsed == true ? '추가입력 펼치기' : '추가입력 접기',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.purple,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '접힘 ${_extraCollapsed.length}/${_attendees.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: AppColors.textGray),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  '접속 V = 해당 참가자가 사진폴더에 접근한 이력',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _attendees.isEmpty
              ? const Center(
                  child: Text(
                    '참석자를 추가하세요',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                )
              : ListView.builder(
                  itemCount: _attendees.length,
                  itemBuilder: (_, i) => _attendeeTile(i),
                ),
        ),
      ],
    );
  }

  Widget _rosterButton(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  /// (요구) 목록 표기용 직책 텍스트 — 코드 우선(B/C/S/V/R/L/일반),
  ///   '기타'면 직접입력 내용을 그대로 노출.
  String _roleDisplay(Map<String, dynamic> a) {
    final code = '${a['roleCode'] ?? ''}'.trim();
    if (code == '기타') {
      final raw = a['rawRoles'];
      final roles = (raw is List ? raw : (a['roles'] as List?) ?? [])
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty && e.trim() != '기타')
          .toList();
      if (roles.isNotEmpty) return roles.join(', ');
      return '기타';
    }
    return code;
  }

  Widget _attendeeTile(int i) {
    final a = _attendees[i];
    final ident = '${a['number'] ?? a['phone'] ?? ''}'.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final visited = ident.isNotEmpty && _access.containsKey(ident);
    final roles = (a['roles'] as List?) ?? [];
    // (요구) 소속 구분 뱃지 — 범/은하/일반. 서버가 내려준 corps(권위) 기반.
    //   ★ (요구) "일반 비인가자는 범 단추 대신 일반 단추를 달아줘.
    //     범 단추는 인가자 중심(=인가자에게만 범 단추)."
    //   판정은 서버가 내려준 corps 로만 한다:
    //     · corps == 'tsak'  → '범'  (인가자)
    //     · corps == 'eunha' → '은하' (인가자)
    //     · corps == ''      → '일반' (비인가)
    //   ⚠️ 기존엔 linkable(개인카드 열기 가능)로 판정해, 비인가자에게 인가번호
    //      '일반#…' 라벨이 세팅되면 linkable=true 가 되어 '범'으로 잘못 표시됐다.
    final corpsRaw = '${a['corps'] ?? ''}'.trim();
    // [요구 2026-11-04] "범스카우트인가자 및 은하스카우트들은 이름 옆에
    //   범, 은하 단추와 번호를 꼭 같이 기입해줘"
    //  서버가 corps 를 비워 보낸 옛 참가 행에서도 배지가 '일반' 으로
    //  떨어지지 않도록 **로컬 명부로 소속을 복원**한다(AppState 단일 구현).
    final st0 = context.read<AppState>();
    //  서버 값이 tsak/eunha 면 그대로 신뢰하고, **비어 있을 때만** 명부로 복원한다.
    final mark = (corpsRaw == 'tsak' || corpsRaw == 'eunha')
        ? (corpsRaw == 'eunha' ? '은하' : '범')
        : st0.corpsMarkForAttendee(a);
    final isRegularRow = mark == '일반';
    final corpLabel = mark;
    final corpColor = isRegularRow
        ? AppColors.textGray
        : (mark == '은하' ? AppColors.taegeukBlue : AppColors.taegeukRed);
    // (요구) 역할 코드 — 비버(B)/컵(C)/스카우트(S)/벤쳐(V)/로버(R)/리더(L)/일반/기타
    final roleCode = '${a['roleCode'] ?? ''}'.trim();
    // (요구) 인가번호 우선 노출 — 서버가 준 numberLabel(범#415/은하#43).
    // [요구 2026-11-04] 서버가 라벨을 비워 보낸 옛 참가 행은 이름 옆 번호가
    //   사라진다 → AppState 가 명부로 복원한 라벨을 쓴다.
    final numLabel = st0.numberLabelForAttendee(a);
    // (요구 #15) STAFF 여부 — 인가번호 옆 STAFF 단추.
    final isStaff = _staff.any(
      (s) =>
          '${s['number'] ?? s['ident'] ?? s['phone'] ?? ''}'.replaceAll(
                RegExp(r'[^0-9]'),
                '',
              ) ==
              ident &&
          ident.isNotEmpty,
    );
    final canManage = widget.canManage;
    // [요구] 회원 등록정보(개인카드) 유무 — 없으면 클릭 시 신규 등록을 유도한다.
    //   서버가 내려준 registered 를 우선하고, 없으면 로컬 저장소로 보정한다.
    final hasCard =
        a['registered'] == true ||
        (canManage &&
            ident.isNotEmpty &&
            context.read<AppState>().byNumber(ident) != null);
    // (요구) 이름 클릭 → 개인카드 연결(관리자·마스터만). 등록정보가 없으면
    //   신규 등록 창을 연다.
    final canOpenCard = canManage && (a['linkable'] == true || hasCard);
    // [요구] 개인카드가 없어도 클릭은 가능해야 한다(신규 등록 유도).
    final canTap = canManage;
    // ── 일괄 선택 모드 ──────────────────────────────────────────────────
    //  체크박스가 leading 을 대체하고, 타일 탭 = 선택 토글이 된다.
    final selected = _selIdx.contains(i);
    if (_selMode) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        color: selected ? AppColors.purple.withValues(alpha: 0.08) : null,
        child: InkWell(
          onTap: () => setState(() {
            if (selected) {
              _selIdx.remove(i);
            } else {
              _selIdx.add(i);
            }
          }),
          child: ListTile(
            dense: true,
            leading: Checkbox(
              value: selected,
              activeColor: AppColors.purple,
              onChanged: (_) => setState(() {
                if (selected) {
                  _selIdx.remove(i);
                } else {
                  _selIdx.add(i);
                }
              }),
            ),
            title: Row(
              children: [
                // [요구 2026-11-04] 일괄 선택 모드에서도 범/은하 단추 + 번호를
                //   이름 옆에 함께 보여준다(선택 중에도 누가 누구인지 확인).
                if (corpLabel.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: corpColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: corpColor.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      corpLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: corpColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    '${a['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (numLabel.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Text(
                    numLabel,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: corpColor,
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              [
                if (numLabel.isNotEmpty) numLabel,
                if (_roleDisplay(a).isNotEmpty) _roleDisplay(a),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: canTap ? () => _openOrRegister(a) : null,
        child: ListTile(
          leading: _attendeeLeading(a, ident, visited, isStaff),
          title: Row(
            children: [
              // 소속 구분 뱃지(범/은하/일반) — **이름 바로 앞**에 고정.
              //  [요구 2026-11-04] "이름 옆에 범, 은하 단추와 번호를 꼭 같이"
              //   → 배지·이름·번호가 한 덩어리로 읽히도록 간격을 좁게 유지한다.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: corpColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: corpColor.withValues(alpha: 0.55)),
                ),
                child: Text(
                  corpLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: corpColor,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              // [요구] 이름이 길면 흐르는 글자(마퀴)로 표시 — 폭을 확정(Expanded)
              //   해야 MarqueeText 가 넘침을 감지해 애니메이션을 시작한다.
              Expanded(
                child: InkWell(
                  onTap: canTap ? () => _openOrRegister(a) : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: MarqueeText(
                          '${a['name'] ?? ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            decoration: canOpenCard
                                ? TextDecoration.underline
                                : null,
                          ),
                        ),
                      ),
                      if (canOpenCard) ...[
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.open_in_new,
                          size: 12,
                          color: AppColors.textGray,
                        ),
                      ] else if (canManage) ...[
                        // 등록정보 없음 → 신규 등록 유도 아이콘.
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.person_add_alt_1,
                          size: 12,
                          color: AppColors.tigerGold,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // (요구) 인가번호 — 이름 바로 옆에 **색 있는 알약**으로 붙인다.
              //  [요구 2026-11-04] "이름 옆에 범, 은하 단추와 번호를 꼭 같이"
              //   종전엔 회색 11pt 텍스트라 이름·배지와 따로 떨어져 보였다.
              if (numLabel.isNotEmpty) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: corpColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    numLabel,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: corpColor,
                    ),
                  ),
                ),
              ],
              // (요구) 역할 코드 뱃지 — 목록에는 코드만(B/C/S/V/R/L/일반).
              //   '기타'는 직접입력한 내용을 그대로 노출한다.
              if (roleCode.isNotEmpty) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _roleDisplay(a),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.purple,
                    ),
                  ),
                ),
              ],
              // STAFF로 지정된 사람만 '스텝' 단추를 부여한다(색상 단추).
              if (isStaff) ...[
                const SizedBox(width: 6),
                _staffButton(a, ident, isStaff),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  // [요구] 활동등록대(unitText)를 우선 표시 — 없으면 인가시 단위대.
                  if ('${a['unitText'] ?? ''}'.trim().isNotEmpty)
                    '${a['unitText']}'
                  else if ('${a['unit'] ?? ''}'.trim().isNotEmpty)
                    '${a['unit']}',
                  // [요구 개인정보] 전화·성별은 참가자(_fullView=false)에게 비노출.
                  if (_fullView)
                    if ('${a['phoneText'] ?? ''}'.trim().isNotEmpty)
                      '${a['phoneText']}'
                    else if ('${a['phone'] ?? ''}'.trim().isNotEmpty)
                      '${a['phone']}',
                  if (_fullView)
                    if ('${a['genderText'] ?? ''}'.trim().isNotEmpty)
                      '${a['genderText']}'
                    else if ('${a['gender'] ?? ''}'.trim().isNotEmpty)
                      '${a['gender']}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12),
              ),
              // (요구) 메일주소 — 개인카드(회원 프로필)에서 가져와 작게 병기.
              //   참가자(_fullView=false)에게는 비노출.
              if (_fullView)
                Builder(
                  builder: (_) {
                    final em = '${a['emailText'] ?? ''}'.trim().isNotEmpty
                        ? '${a['emailText']}'
                        : '${a['email'] ?? ''}'.trim();
                    if (em.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        em,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textGray.withValues(alpha: 0.9),
                        ),
                      ),
                    );
                  },
                ),
              // [요구 2026-10-30] 추가입력사항을 **항목별로** 표시 —
              //   "추가입력사항도 매우 중요한 정보야 / 자세히 보여주고 정리되고
              //    출력시 구분해서 보여져야 해, 항목별로 취합도 가능해야 해"
              //
              // ## 종전 문제
              //  9.5pt **마퀴(흐르는 글자) 한 줄**에 이모지로 이어붙였다.
              //  `⏰ 1일 14:30 · 🛏 숙박 · 🚗 자차 · 👥 김철수 · 💬 알레르기`
              //  마퀴는 흐르기 때문에 **읽는 도중 사라지고**, 폭이 좁으면 잘렸다.
              //  전달사항(알레르기·식이요법)은 놓치면 현장 사고로 이어진다.
              //
              // ## 지금
              //  · 값이 있는 항목만 **한 줄에 하나씩** 라벨과 함께 표시.
              //  · 항목 정의는 `ExtraFields` 단일 출처(입력·출력·취합과 동일 라벨).
              //  · 전달사항은 색을 달리해 **강조**(굵게).
              //  · 개인정보 보호: 참가자(_fullView=false)에게는 비노출(기존 정책 유지).
              if (_fullView)
                Builder(
                  builder: (_) {
                    final filled = ExtraFields.filled(a);
                    if (filled.isEmpty) return const SizedBox.shrink();
                    // (요구 2026-10-31 5차) "접어두기 버튼 추가"
                    //  카드마다 접힘 상태를 따로 기억한다(_extraCollapsed).
                    //  전달사항(request)이 있는 사람은 **접어도 한 줄은 보이게**
                    //  한다 — 놓치면 현장 사고로 이어지는 정보라서.
                    final k = _attendeeKey(a);
                    final collapsed = _extraCollapsed.contains(k);
                    final req = filled
                        .where((f) => f.group == ExtraGroup.request)
                        .toList();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.purple.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── 머리줄: 항목수 + 접기/펼치기 단추 ──
                            InkWell(
                              onTap: () => setState(() {
                                if (collapsed) {
                                  _extraCollapsed.remove(k);
                                } else {
                                  _extraCollapsed.add(k);
                                }
                              }),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 1,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.tune,
                                      size: 12,
                                      color: AppColors.purple.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '추가입력 ${filled.length}항목',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.purple,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      collapsed ? '펼치기' : '접어두기',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textGray,
                                      ),
                                    ),
                                    const SizedBox(width: 1),
                                    Icon(
                                      collapsed
                                          ? Icons.keyboard_arrow_down
                                          : Icons.keyboard_arrow_up,
                                      size: 16,
                                      color: AppColors.textGray,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // ── 접힌 상태: 한 줄 요약(+전달사항은 강조 유지) ──
                            if (collapsed) ...[
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 2,
                                  left: 16,
                                  right: 2,
                                ),
                                child: Text(
                                  filled
                                      .map((f) => f.valueOf(a))
                                      .where((v) => v.trim().isNotEmpty)
                                      .join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    height: 1.3,
                                    color: AppColors.textGray,
                                  ),
                                ),
                              ),
                              if (req.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 1,
                                    left: 16,
                                    right: 2,
                                  ),
                                  child: Text(
                                    req
                                        .map(
                                          (f) => '${f.label}: ${f.valueOf(a)}',
                                        )
                                        .join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: ExtraFields.colorOf(
                                        ExtraGroup.request,
                                      ),
                                    ),
                                  ),
                                ),
                            ] else ...[
                              for (final f in filled)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        f.icon,
                                        size: 11,
                                        color: ExtraFields.colorOf(f.group),
                                      ),
                                      const SizedBox(width: 4),
                                      SizedBox(
                                        width: 78,
                                        child: Text(
                                          f.label,
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textGray,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          f.valueOf(a),
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1.3,
                                            fontWeight:
                                                f.group == ExtraGroup.request
                                                ? FontWeight.w800
                                                : FontWeight.w500,
                                            color:
                                                f.group == ExtraGroup.request
                                                ? ExtraFields.colorOf(f.group)
                                                : AppColors.textDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              // [요구] 회원 등록정보 없음 → 클릭 시 신규 등록을 유도한다.
              if (canManage && !hasCard)
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Text(
                    '미등록 — 클릭하여 신규 회원 등록',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.tigerGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (roles.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: [
                    for (final r in roles)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$r',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.purple,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          trailing: widget.canManage
              ? PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await _manualAddAttendee(editIndex: i);
                    } else if (v == 'del') {
                      // (요구) 삭제 전 한 번 더 확인.
                      //  삭제하면 **개인정보카드의 '행사참가 이력'에서도**
                      //  사라진다는 사실을 미리 알린다.
                      final ok = await confirmDialog(
                        context,
                        title: '참가자 삭제',
                        message:
                            '${a['name'] ?? ''} 님을 참가자 명단에서 삭제할까요?\n\n'
                            '개인정보카드의 「행사참가 이력」에서도 함께 '
                            '제외됩니다.',
                      );
                      if (!ok) return;
                      final wasLinked = (a['number'] ?? a['phone'] ?? '')
                          .toString()
                          .replaceAll(RegExp(r'[^0-9]'), '')
                          .isNotEmpty;
                      setState(() => _attendees.removeAt(i));
                      final res = await _saveAttendeesLinked();
                      // 서버는 이미 eventAttend[행사명]=False 로 되돌렸다.
                      // 앱 메모리 캐시도 함께 정리해야 **개인정보카드를 바로
                      // 열었을 때** '행사참가 이력'에서 사라진다.
                      var localFreed = 0;
                      if (mounted) {
                        try {
                          localFreed = await context
                              .read<AppState>()
                              .unlinkEventFromMembers(
                                widget.title,
                                keepIdents: [
                                  for (final x in _attendees)
                                    '${x['number'] ?? ''}',
                                  for (final x in _attendees)
                                    '${x['phone'] ?? ''}',
                                ],
                              );
                        } catch (_) {}
                      }
                      if (!mounted) return;
                      final freed =
                          int.tryParse('${res['linkedRemoved'] ?? 0}') ?? 0;
                      final total = freed > localFreed ? freed : localFreed;
                      _snack(
                        total > 0
                            ? '삭제 완료 · 개인정보카드 「행사참가 이력」에서도 '
                                  '$total명 제외했습니다'
                            : (wasLinked
                                  ? '삭제 완료 (개인정보카드에 이 행사 참가 '
                                        '기록이 없어 해제할 항목이 없습니다)'
                                  : '삭제 완료'),
                      );
                    } else if (v == 'top') {
                      await _moveAttendee(i, 0);
                    } else if (v == 'up') {
                      if (i > 0) await _moveAttendee(i, i - 1);
                    } else if (v == 'down') {
                      if (i < _attendees.length - 1) {
                        await _moveAttendee(i, i + 1);
                      }
                    } else if (v == 'role') {
                      await _editAttendeeRole(i);
                    } else if (v == 'card') {
                      await _openOrRegister(a);
                    } else if (v == 'register') {
                      await _openOrRegister(a);
                    }
                  },
                  itemBuilder: (_) => [
                    if (hasCard)
                      const PopupMenuItem(value: 'card', child: Text('개인카드 열기'))
                    else
                      // [요구] 등록정보가 없으면 신규 회원 등록을 유도한다.
                      const PopupMenuItem(
                        value: 'register',
                        child: Text('신규 회원 등록'),
                      ),
                    const PopupMenuItem(value: 'edit', child: Text('정보 수정')),
                    const PopupMenuItem(
                      value: 'role',
                      child: Text('항목(역할) 변경'),
                    ),
                    const PopupMenuItem(value: 'top', child: Text('맨 위로')),
                    const PopupMenuItem(value: 'up', child: Text('위로 이동')),
                    const PopupMenuItem(value: 'down', child: Text('아래로 이동')),
                    const PopupMenuItem(value: 'del', child: Text('삭제')),
                  ],
                )
              : const Icon(Icons.chevron_right, color: AppColors.textGray),
        ),
      ),
    );
  }

  /// (요구) 명단 관리 — 위치 변경(로컬 순서 조정 후 저장).
  Future<void> _moveAttendee(int from, int to) async {
    if (from < 0 || from >= _attendees.length) return;
    final item = _attendees.removeAt(from);
    _attendees.insert(to.clamp(0, _attendees.length), item);
    setState(() {});
    await _saveAttendees();
  }

  /// (요구) 명단 관리 — 항목(역할) 변경. L/B/S/V/R 등 코드로 표시된다.
  Future<void> _editAttendeeRole(int i) async {
    if (i < 0 || i >= _attendees.length) return;
    final cur =
        ((_attendees[i]['rawRoles'] as List?) ??
                (_attendees[i]['roles'] as List?) ??
                [])
            .map((e) => '$e')
            .toSet();
    // [2026-10-29] 직책 목록은 AttendeeRoles.picker 하나만 쓴다.
    const all = AttendeeRoles.picker;
    final sel = {...cur};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('항목(역할) 변경'),
          content: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in all)
                FilterChip(
                  label: Text(r),
                  selected: sel.contains(r),
                  selectedColor: AppColors.purple,
                  labelStyle: TextStyle(
                    color: sel.contains(r) ? Colors.white : AppColors.purple,
                  ),
                  onSelected: (v) => setD(() => v ? sel.add(r) : sel.remove(r)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    _attendees[i]['roles'] = sel.toList();
    // 표시용 코드도 즉시 갱신(서버 재조회 전 화면 반영)
    // [2026-10-29] 코드 계산도 단일 정의로 — '컵' 누락 재발 방지.
    final code = AttendeeRoles.codeOf(sel);
    _attendees[i]['roleCode'] = code;
    setState(() {});
    await _saveAttendees();
  }

  /// 참가자 타일 좌측(leading).
  ///  - 접속 여부(V)는 항상 표시(접속기록 유지).
  ///  - 관리자·마스터에게는 그 위에 STAFF 지정 체크박스를 추가로 노출한다.
  Widget _attendeeLeading(
    Map<String, dynamic> a,
    String ident,
    bool visited,
    bool isStaff,
  ) {
    final canStaff = widget.canManage && ident.isNotEmpty;
    return SizedBox(
      width: 34,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (canStaff) ...[
            // STAFF 지정 체크박스 (마스터·관리자 전용) — 보라색 마크
            GestureDetector(
              onTap: () => _toggleStaff(a, ident, isStaff),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isStaff ? AppColors.purple : Colors.white,
                  border: Border.all(
                    color: isStaff ? AppColors.purple : Colors.grey.shade400,
                    width: isStaff ? 2 : 1.4,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: isStaff
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(height: 1),
          ],
          // 접속 여부(V) — 삭제하지 않고 항상 유지
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: visited ? AppColors.scoutGreen : Colors.transparent,
              border: Border.all(
                color: visited ? AppColors.scoutGreen : Colors.grey.shade300,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: visited
                ? const Text(
                    'V',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 1),
          Text(
            '접속',
            style: TextStyle(
              fontSize: 8.5,
              color: visited ? AppColors.scoutGreen : AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }

  /// STAFF(스텝)로 지정된 사람에게 부여되는 색상 단추(작게).
  ///  - 관리자·마스터: 눌러서 해제 가능.
  ///  - 그 외: 지정 사실만 표시(비활성).
  Widget _staffButton(Map<String, dynamic> a, String ident, bool isStaff) {
    final canToggle = widget.canManage && ident.isNotEmpty;
    return GestureDetector(
      onTap: canToggle ? () => _toggleStaff(a, ident, isStaff) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.purple, AppColors.purpleDark],
          ),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.purpleDark),
        ),
        child: const Text(
          '스텝',
          style: TextStyle(
            fontSize: 8.5,
            height: 1.1,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleStaff(
    Map<String, dynamic> a,
    String ident,
    bool isStaff,
  ) async {
    if (!widget.canManage) return;
    try {
      final list = isStaff
          ? await _nas.eventStaffRemove(
              year: widget.year,
              title: widget.title,
              number: ident,
            )
          : await _nas.eventStaffAdd(
              year: widget.year,
              title: widget.title,
              number: ident,
            );
      if (!mounted) return;
      setState(() => _staff = list);
      _snack(isStaff ? '스텝에서 해제했습니다' : '행사 스텝(STAFF)으로 등록했습니다');
    } catch (e) {
      _snack('처리 실패: $e');
    }
  }

  // ⚠️ [2026-10-29] `_resolveMember()` 를 **삭제**했다.
  //   그 함수는 "번호가 없으면 이름으로 찾는다" 는 폴백을 담고 있었고,
  //   그것이 비인가자 '김종선' 을 범 222호 '김종선' 카드로 열게 만든
  //   직접 원인이었다. 같은 실수를 다시 만들 수 없도록 **함수 자체를 없앴다.**
  //   카드 연결은 오직 `AppState.resolveIdentity()` 결과(`MemberIdentity`)
  //   하나만 통과한다. 이름은 어떤 경우에도 회원을 단정하지 않는다.

  /// [요구] 참가자 이름 클릭:
  ///  · 개인카드(등록정보)가 있으면 → 개인카드 열기.
  ///  · 등록정보가 없으면 → '신규 회원 등록할까요?' 확인 후, 등록 창을 열어
  ///    이름·전화번호를 미리 채운다. (일반회원 신규 등록)
  Future<void> _openOrRegister(Map<String, dynamic> a) async {
    if (!widget.canManage) return;
    final s = context.read<AppState>();
    final idn = s.resolveIdentity(
      //  ⚠️ number 는 **원본 문자열**을 넘긴다(숫자만 뽑지 않는다).
      //   'G75'(은하) 와 '75'(범) 를 구분해야 하므로 접두어를 반드시 보존.
      number: '${a['number'] ?? ''}',
      phone: '${a['phone'] ?? a['loginId'] ?? ''}',
      name: '${a['name'] ?? ''}',
      corps: '${a['corps'] ?? ''}'.trim(),
      // 저장된 신원 — false 면 비인가 확정(회원 조회 안 함),
      //                 true  면 인가 확정(이름 폴백 금지).
      licensed: a['licensed'] is bool ? a['licensed'] as bool : null,
    );

    // ── 동명이인: **절대 단정하지 않는다** → 사용자가 직접 고른다 ─────────
    if (idn.needsChoice) {
      final picked = await _pickSameNameCandidate(a, idn.candidates);
      if (picked == null || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MemberDetailScreen(memberId: picked.id)),
      );
      if (mounted) _load();
      return;
    }

    // ── 단일/미확인 — idn 하나만 신뢰한다(다른 조회 경로 없음) ────────────
    final m = idn.isResolved ? idn.member : null;
    if (m != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MemberDetailScreen(memberId: m.id)),
      );
      if (mounted) _load();
      return;
    }
    // ---- 등록정보 없음 → 신규 회원 등록 유도 ----
    final nm = '${a['name'] ?? ''}'.trim();
    final ph = '${a['phone'] ?? a['loginId'] ?? a['number'] ?? ''}'.trim();
    // 인가자(범/은하)면 인가자로, 그 외(일반)면 일반회원으로 등록한다.
    //   ⚠️ [2026-10-29 무한루프 재수정] 저장된 `licensed` 를 **맹신하지 않는다.**
    //
    //   서버가 오랫동안 `number` 칸의 전화번호를 인가번호로 오인해
    //   `licensed=true / corps='tsak'` 을 써 왔다(이지원 사고). 그 값을
    //   그대로 믿으면 "인가자로 신규 등록" 을 계속 권하게 되고, 등록해도
    //   일반회원 레코드와 키가 달라 다시 안 잡히는 **루틴**이 된다.
    //
    //   그래서 **행 자체의 모양**을 1차 근거로 삼는다.
    //     · 인가번호 칸이 전화번호 모양(11자리) → 일반회원
    //     · 인가번호 칸이 짧은 숫자 / G·은하 표기 → 인가자
    //     · 판단 불가 → 저장된 licensed, 그것도 없으면 corps 공백 여부
    final _nRaw = '${a['number'] ?? ''}'.trim();
    final _nDig = _nRaw.replaceAll(RegExp(r'[^0-9]'), '');
    final _nLooksPhone = _nDig.length >= 10 || _nDig.startsWith('01');
    final _nLooksLicense = _nDig.isNotEmpty &&
        !_nLooksPhone &&
        (RegExp(r'^(g|G|은하|갤럭시|갤럭시)').hasMatch(_nRaw) ||
            _nDig.length <= 4);
    final storedLic = a['licensed'];
    final bool isRegular;
    if (_nLooksPhone) {
      isRegular = true;
    } else if (_nLooksLicense) {
      isRegular = false;
    } else if (storedLic is bool) {
      isRegular = !storedLic;
    } else {
      isRegular = '${a['corps'] ?? ''}'.trim().isEmpty;
    }
    // 비인가자는 "회원 정보가 없다" 가 **정상**이므로 문구를 구분한다.
    final msg = isRegular
        ? '${nm.isEmpty ? '이 참가자' : nm}'
            '${ph.isNotEmpty ? ' ($ph)' : ''} 님은 일반(비인가) 참가자입니다.\n\n'
            '일반회원으로 등록할까요?\n'
            '· 인가번호가 없으므로 범/은하 인가자와는 연결되지 않습니다.'
        : '${nm.isEmpty ? '이 참가자' : nm}'
            '${ph.isNotEmpty ? ' ($ph)' : ''} 님은 등록된 회원 정보가 없습니다.\n\n'
            '인가자로 신규 등록할까요?';
    final ok = await confirmDialog(
      context,
      title: isRegular ? '일반회원 신규 등록' : '신규 회원 등록',
      message: msg,
      confirmLabel: '신규 등록',
      cancelLabel: '취소',
      danger: false,
    );
    if (!ok || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberEditScreen(
          registerAsRegular: isRegular,
          prefillName: nm,
          prefillPhone: ph,
          prefillUnit: '${a['unitText'] ?? a['unit'] ?? ''}'.trim(),
          prefillEmail: '${a['emailText'] ?? a['email'] ?? ''}'.trim(),
        ),
      ),
    );
    if (mounted) _load();
  }

  /// 동명이인 후보 선택 창.
  ///
  /// ## [2026-10-29] 왜 필요한가
  ///  이름만 같은 여러 회원 중 하나를 **코드가 찍는 것**이 사고의 원인이었다.
  ///  대신 후보를 소속·인가번호·연락처와 함께 보여주고 사람이 고르게 한다.
  ///  여기서 고른 결과는 **세션 동안만** 기억한다(다음부터 자동 연결).
  Future<Member?> _pickSameNameCandidate(
    Map<String, dynamic> a,
    List<Member> cands,
  ) async {
    // 이미 이 참가자에 대해 선택한 적이 있으면 그 회원으로 바로 연다.
    final memoKey = '${a['number'] ?? ''}|${a['phone'] ?? ''}|'
        '${a['name'] ?? ''}'.toLowerCase();
    final memoId = _sameNameChoice[memoKey];
    if (memoId != null) {
      for (final m in cands) {
        if (m.id == memoId) return m;
      }
    }
    final nm = '${a['name'] ?? ''}'.trim();
    final picked = await showDialog<Member>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.people_alt_outlined,
            color: AppColors.hermesOrange, size: 30),
        title: Text('동명이인 ${cands.length}명'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '“${nm.isEmpty ? '이름 없음' : nm}” 과(와) 이름이 같은 회원이 '
                '${cands.length}명입니다.\n'
                '잘못 열면 다른 사람의 개인정보가 보이므로 자동으로 열지 '
                '않았습니다. 열 사람을 직접 선택해 주세요.',
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final m in cands)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: m.isRegular
                                ? AppColors.textGray
                                : (m.corps == 'eunha'
                                    ? AppColors.taegeukBlue
                                    : AppColors.purple),
                            child: Text(
                              m.corpsMarkLabel,
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            '${m.name}  ·  ${m.rosterNumber}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (m.regLeague.trim().isNotEmpty) m.regLeague,
                              if (m.regUnit.trim().isNotEmpty) m.regUnit,
                              if (m.phone.trim().isNotEmpty) m.phone,
                            ].join(' · '),
                            style: const TextStyle(fontSize: 10.5),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => Navigator.pop(ctx, m),
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
        ],
      ),
    );
    if (picked != null) _sameNameChoice[memoKey] = picked.id;
    return picked;
  }

  /// 동명이인 선택 기억(참가자 키 → 회원 id). 화면 수명 동안만 유지.
  final Map<String, String> _sameNameChoice = {};

  /// (요구 #14) 행사 스텝(STAFF) 등록 — 관리자·마스터만. 인가자 검색 후 스텝 등록.
  Future<void> _manageStaff() async {
    if (!widget.canManage) return;
    final ctrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = false;
    String errMsg = '';
    List<Map<String, dynamic>> staff = List.from(_staff);

    Future<void> doSearch(StateSetter setD) async {
      setD(() => loading = true);
      try {
        results = await _nas.eventSearchMember(ctrl.text.trim(), limit: 60);
        errMsg = '';
      } catch (e) {
        errMsg = '검색 실패: $e';
      }
      setD(() => loading = false);
    }

    if (mounted) setState(() => _loading); // no-op 유지
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) {
            doSearch(setD);
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.engineering, color: AppColors.purple),
                  SizedBox(width: 8),
                  Text('행사 스텝(STAFF) 등록'),
                ],
              ),
              content: SizedBox(
                width: 400,
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '스텝으로 등록하면 해당 행사의 모든 게시판이 노출됩니다.',
                      style: TextStyle(fontSize: 12, color: AppColors.textGray),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        labelText: '인가번호 / 이름 / 소속',
                        isDense: true,
                      ),
                      onSubmitted: (_) => doSearch(setD),
                    ),
                    const SizedBox(height: 6),
                    if (staff.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in staff)
                            Chip(
                              avatar: const Icon(Icons.engineering, size: 15),
                              label: Text(
                                '${s['name'] ?? ''} ${Member.numLabelOf('${s['number'] ?? s['ident'] ?? ''}', '${s['corps'] ?? 'tsak'}')}',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              onDeleted: () async {
                                final list = await _nas.eventStaffRemove(
                                  year: widget.year,
                                  title: widget.title,
                                  number: '${s['number'] ?? s['ident'] ?? ''}',
                                );
                                setD(() => staff = List.from(list));
                                if (mounted) setState(() => _staff = list);
                              },
                            ),
                        ],
                      ),
                    const Divider(height: 16),
                    if (errMsg.isNotEmpty)
                      Text(
                        errMsg,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (_, i) {
                                final r = results[i];
                                final num = '${r['number'] ?? ''}'.replaceAll(
                                  RegExp(r'[^0-9]'),
                                  '',
                                );
                                final already = staff.any(
                                  (s) =>
                                      '${s['number'] ?? s['ident'] ?? ''}'
                                          .replaceAll(RegExp(r'[^0-9]'), '') ==
                                      num,
                                );
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.person_outline),
                                  title: Text(
                                    '${r['name']} · ${Member.numLabelOf('${r['number'] ?? ''}', '${r['corps'] ?? 'tsak'}')}',
                                  ),
                                  subtitle: Text(
                                    '${r['unit'] ?? ''}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: already
                                      ? const Text(
                                          '등록됨',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.scoutGreen,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add_circle_outline,
                                          color: AppColors.purple,
                                        ),
                                  onTap: already
                                      ? null
                                      : () async {
                                          final list = await _nas.eventStaffAdd(
                                            year: widget.year,
                                            title: widget.title,
                                            number: '${r['number']}',
                                          );
                                          setD(() => staff = List.from(list));
                                          if (mounted) {
                                            setState(() => _staff = list);
                                          }
                                        },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        ),
      );
      if (mounted) _load();
    }
  }

  Future<void> _saveAttendees() async {
    await _nas.eventSetAttendees(widget.year, widget.title, _attendees);
    await _load();
  }

  /// 참가자 명단 저장 + **개인정보카드 연동 결과**까지 받아온다.
  ///
  /// ## 요구: "참가자 삭제시 개인정보카드와 연계해서 참가행사에서도 삭제"
  ///  서버가 명단을 저장하면서 회원 프로필(eventAttend)을 양방향으로 갱신한다.
  ///  여기서는 그 결과(해제된 인원)를 사용자에게 알려준다.
  Future<Map<String, dynamic>> _saveAttendeesLinked() async {
    final res = await _nas.eventSetAttendeesDetailed(
      widget.year,
      widget.title,
      _attendees,
    );
    await _load();
    return res;
  }

  /// 선택한 참가자를 **한 번에** 삭제한다.
  ///
  /// ## 요구: "참가자 삭제시 개인정보카드와 연계해서 참가행사에서도 삭제"
  ///  한 명씩 지우던 흐름을 여러 명으로 확장한다.
  ///  서버는 저장된 명단에 없는 회원을 모두 프로필에서 해제하므로,
  ///  한 번의 저장으로 N명이 정리된다.
  Future<void> _deleteSelected() async {
    if (_selIdx.isEmpty || !widget.canManage) return;
    final idx = _selIdx.toList()..sort((a, b) => b.compareTo(a));
    final names = [
      for (final i in idx)
        if (i >= 0 && i < _attendees.length) '${_attendees[i]['name'] ?? ''}',
    ].where((e) => e.trim().isNotEmpty).toList();
    if (names.isEmpty) return;

    // 실수 방지 — 몇 명이 사라지는지, 어디까지 반영되는지 명시.
    final head = names.length <= 5
        ? names.join(', ')
        : '${names.take(5).join(', ')} 외 ${names.length - 5}명';
    final ok = await confirmDialog(
      context,
      title: '참가자 ${names.length}명 삭제',
      message:
          '$head\n\n'
          '삭제하면 개인정보카드의 「행사참가 이력」에서도 함께 제외됩니다.',
    );
    if (!ok) return;

    // 내림차순으로 지워야 인덱스가 밀리지 않는다.
    setState(() {
      for (final i in idx) {
        if (i >= 0 && i < _attendees.length) _attendees.removeAt(i);
      }
      _selIdx.clear();
      _selMode = false;
    });

    final res = await _saveAttendeesLinked();
    var localFreed = 0;
    if (mounted) {
      try {
        localFreed = await context.read<AppState>().unlinkEventFromMembers(
          widget.title,
          keepIdents: [
            for (final x in _attendees) '${x['number'] ?? ''}',
            for (final x in _attendees) '${x['phone'] ?? ''}',
          ],
        );
      } catch (_) {}
    }
    if (!mounted) return;
    final freed = int.tryParse('${res['linkedRemoved'] ?? 0}') ?? 0;
    final total = freed > localFreed ? freed : localFreed;
    _snack(
      '${names.length}명 삭제 완료'
      '${total > 0 ? ' · 개인정보카드 「행사참가 이력」에서도 $total명 제외' : ''}',
    );
  }

  /// 인가자 다중 검색 & 일괄 추가.
  /// - 한 번에 여러 명을 체크해 추가(반복 입력 불필요).
  /// - 검색어가 비어 있으면 최근/전체 목록을 보여주고, 항목 선택 시 일괄 적용.
  Future<void> _searchAndAddAttendee() async {
    final ctrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    final checked = <String, Map<String, dynamic>>{}; // number -> member
    bool loading = false;
    String errMsg = '';

    Future<void> doSearch(StateSetter setD) async {
      loading = true;
      errMsg = '';
      setD(() {});
      try {
        final q = ctrl.text.trim();
        results = await _nas.eventSearchMember(q.isEmpty ? '' : q, limit: 60);
        // 이미 명단에 있는 사람 표시용 집합
      } catch (e) {
        errMsg = '검색 실패: $e';
      }
      loading = false;
      setD(() {});
    }

    final existing = <String>{
      for (final a in _attendees)
        '${a['number'] ?? ''}${a['phone'] ?? ''}${a['loginId'] ?? ''}'
            .replaceAll(RegExp(r'[^0-9]'), ''),
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(
            children: [
              const Text('인가자 검색 · 일괄추가'),
              const Spacer(),
              Text(
                '${checked.length}명 선택',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.purple,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 380,
            height: 480,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: '인가번호 / 이름 / 소속 (비우면 전체)',
                          isDense: true,
                        ),
                        onSubmitted: (_) => doSearch(setD),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: () => doSearch(setD),
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
                if (errMsg.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      errMsg,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 6),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : results.isEmpty
                      ? const Center(
                          child: Text(
                            '검색어를 입력하고 검색하세요',
                            style: TextStyle(color: AppColors.textGray),
                          ),
                        )
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final r = results[i];
                            final num = '${r['number'] ?? ''}'.replaceAll(
                              RegExp(r'[^0-9]'),
                              '',
                            );
                            final already =
                                existing.contains(num) ||
                                checked.containsKey(num);
                            return CheckboxListTile(
                              dense: true,
                              value: checked.containsKey(num),
                              onChanged: already && !checked.containsKey(num)
                                  ? null
                                  : (v) {
                                      setD(() {
                                        if (v == true) {
                                          checked[num] = r;
                                        } else {
                                          checked.remove(num);
                                        }
                                      });
                                    },
                              title: Text(
                                '${r['name']} · ${Member.numLabelOf('${r['number'] ?? ''}', '${r['corps'] ?? 'tsak'}')}',
                              ),
                              subtitle: Text(
                                '${already ? '이미 등록됨 · ' : ''}${r['unit'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: already ? AppColors.textGray : null,
                                ),
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                checked.clear();
                await doSearch(setD);
              },
              child: const Text('전체 보기'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton.icon(
              onPressed: checked.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.playlist_add_check),
              label: Text('선택 ${checked.length}명 추가'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || checked.isEmpty) return;

    // 일괄 항목(roles) 선택
    final roles = await _pickRoles();
    if (roles == null) return;

    final picks = checked.values.map((r) {
      return {
        'number': '${r['number']}',
        'name': '${r['name']}',
        'unit': '${r['unit']}',
        'league': '${r['league']}',
        'phone': '${r['phone']}',
        'roles': roles,
      };
    }).toList();

    try {
      final res = await _nas.eventAttendeesAdd(
        widget.year,
        widget.title,
        picks,
      );
      final added = res['added'] ?? 0;
      final skipped = res['skipped'] ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped > 0 ? '$added명 추가 완료 (중복 $skipped명 건너뜀)' : '$added명 추가 완료',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('추가 실패: $e')));
    }
  }

  Future<List<String>?> _pickRoles() async {
    // [2026-10-29] 단일 정의(컵 포함).
    const all = AttendeeRoles.picker;
    final sel = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('항목 선택 (복수 가능)'),
          content: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in all)
                FilterChip(
                  label: Text(r),
                  selected: sel.contains(r),
                  selectedColor: AppColors.purple,
                  labelStyle: TextStyle(
                    color: sel.contains(r) ? Colors.white : AppColors.purple,
                  ),
                  onSelected: (v) => setD(() => v ? sel.add(r) : sel.remove(r)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, sel.toList()),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manualAddAttendee({int? editIndex}) async {
    final cur = editIndex != null ? _attendees[editIndex] : null;
    final nameC = TextEditingController(text: '${cur?['name'] ?? ''}');
    final unitC = TextEditingController(text: '${cur?['unit'] ?? ''}');
    final genderC = TextEditingController(text: '${cur?['gender'] ?? ''}');
    final phoneC = TextEditingController(text: '${cur?['phone'] ?? ''}');
    final emailC = TextEditingController(text: '${cur?['email'] ?? ''}');
    final addrC = TextEditingController(text: '${cur?['address'] ?? ''}');
    final numC = TextEditingController(text: '${cur?['number'] ?? ''}');
    // (요구) '행사 참가신청 창'과 동일 포맷 — 추가 입력 항목.
    final transportC = TextEditingController(
      text: '${cur?['transport'] ?? ''}',
    );
    final transportNoteC = TextEditingController(
      text: '${cur?['transportNote'] ?? ''}',
    );
    final lodgingC = TextEditingController(text: '${cur?['lodging'] ?? ''}');
    final arriveC = TextEditingController(text: '${cur?['arrive'] ?? ''}');
    final arriveNoteC = TextEditingController(
      text: '${cur?['arriveNote'] ?? ''}',
    );
    final fromC = TextEditingController(text: '${cur?['from'] ?? ''}');
    final etaC = TextEditingController(text: '${cur?['eta'] ?? ''}');
    final companionC = TextEditingController(
      text: '${cur?['companion'] ?? ''}',
    );
    final messageC = TextEditingController(text: '${cur?['message'] ?? ''}');
    final roles = <String>{
      ...((cur?['roles'] as List?)?.map((e) => '$e') ?? []),
    };
    // (요구) 직책: 비버/컵/스카우트/벤쳐스카우트/로버스카우트/리더/일반/기타.
    // [2026-10-29] 단일 정의 — 8종/9종 혼재 해소.
    const all = AttendeeRoles.picker;
    // (요구) 인가번호 자동채움 상태 — 다이얼로그 로컬 상태.
    var lookupBusy = false;
    var lookupOk = false;
    // 동명이인 응답(후보 목록) — 있으면 조회 결과 대신 선택 UI 를 보여준다.
    Map<String, dynamic>? lookupAmbiguous;
    // [요구 2026-10-29] 인가자만이 아니라 **일반회원(비인가)도** 조회된다.
    var lookupHint = '인가번호·전화번호·이름으로 개인정보를 불러옵니다';
    // 매칭된 회원(있으면 저장 시 corps/numberLabel 판단에 쓴다).
    Map<String, dynamic>? matched;
    // ── 바텀시트로 전환 ────────────────────────────────────────────────
    //  ## 왜 (요구: 키보드가 창을 줄여 입력칸이 안 보이던 문제)
    //   AlertDialog(scrollable:true) 는 여전히 키보드가 올라오면 창 자체가
    //   줄어든다. 이 폼은 입력칸이 15개라 증상이 가장 심했다.
    //   showTsakFormSheet 는 높이를 (화면−키보드)×0.94 로 고정하고
    //   헤더/스크롤본문/버튼 3단으로 나눠 입력칸이 사라지지 않는다.
    final saved = await showTsakFormSheet(
      context: context,
      title: editIndex != null ? '참석자 수정' : '참석자 수동 입력',
      subtitle: '인가번호를 넣으면 개인정보를 자동으로 불러옵니다',
      icon: Icons.edit_note,
      saveLabel: '저장',
      heightFactor: 0.94,
      builder: (ctx, setSheetState) {
        // ---- 인가번호 → 개인정보 자동채움 ----
        //   관리자가 이미 입력/수정한 칸은 덮어쓰지 않는다(빈 칸만 채움).
        Future<void> autoFill() async {
          final q = numC.text.trim();
          if (q.isEmpty || lookupBusy) return;
          setSheetState(() {
            lookupBusy = true;
            lookupAmbiguous = null;
            lookupHint = '개인정보 불러오는 중…';
          });
          Map<String, dynamic>? m;
          try {
            // ══════════════════════════════════════════════════════════════
            // [요구 2026-10-29] "수동입력시 인가자 정보만 불러올 수 있는데,
            //  비인가자(일반회원) 정보도 조회 후 불러올 수 있도록"
            //
            //  ## 왜 예전엔 안 됐나
            //   로컬 조회가 `byNumber(q) ?? byId(q)` 였다. 둘 다 **인가번호/ID**
            //   축이라 일반회원(인가번호 없음, 전화번호가 사실상의 키)은
            //   절대 걸리지 않았다. 서버 폴백도 있었지만 화면 라벨이
            //   '인가번호 (인가자만)' 이고 키보드가 숫자 전용이라
            //   관리자가 전화번호를 넣을 생각 자체를 못 했다.
            //
            //  ## 고친 방식
            //   입력값을 **인가번호 / 전화번호 / 이름** 어느 것으로도 받는다.
            //    ① 로컬: resolveIdentity(전화번호·이름 포함)로 먼저 찾고
            //    ② 없으면 서버(/api/member/lookup)로 최신값 조회.
            //   일반회원이면 isRegular=true 로 표시해 저장 시 범 배지가
            //   붙지 않도록 한다(요구: 일반회원은 '일반' 단추).
            // ══════════════════════════════════════════════════════════════
            final s = context.read<AppState>();
            final idn = s.resolveIdentity(
              number: q,
              phone: q,
              name: q,
              // 이름 단독 입력으로 남의 카드를 채우지 않는다 —
              //  자동채움은 '사람이 특정한 값'일 때만 동작해야 안전하다.
              allowNameFallback: true,
            );
            final local = idn.isResolved ? idn.member : null;
            //  로컬에서 **여러 명**이면 그 후보를 그대로 보여 준다(선택).
            if (idn.needsChoice && idn.candidates.isNotEmpty) {
              lookupAmbiguous = {
                'count': idn.candidates.length,
                'candidates': [
                  for (final c in idn.candidates)
                    {
                      'id': c.id,
                      'name': c.name,
                      'numberLabel': c.numberLabel,
                      'corps': c.isRegular ? '' : c.corps,
                      'corpsLabel': c.corpsMarkLabel,
                      'isRegular': c.isRegular,
                      'unit': c.regUnit.trim().isNotEmpty
                          ? c.regUnit
                          : c.unit,
                      'league': c.regLeague.trim().isNotEmpty
                          ? c.regLeague
                          : c.league,
                      'phone': c.phone,
                      'email': c.email,
                      'address': c.address,
                      'gender': c.gender,
                    },
                ],
              };
            }
            if (local != null) {
              m = {
                'id': local.id,
                'number': local.number,
                'name': local.name,
                'corps': local.corps,
                'corpsLabel': local.corpsMarkLabel,
                'numberLabel': local.numberLabel,
                'isRegular': local.isRegular,
                'league': local.regLeague.trim().isNotEmpty
                    ? local.regLeague
                    : local.league,
                'unit': local.regUnit.trim().isNotEmpty
                    ? local.regUnit
                    : local.unit,
                'gender': local.gender,
                'phone': local.phone,
                'email': local.email,
                'address': local.address,
              };
            }
            // 2) 로컬에 없으면 서버 조회(최신값).
            //   접두어(은하/G/갤럭시)가 있으면 은하 명단만 — 서버가 판정한다.
            if (m == null) {
              //  `allCandidates: true` → 일치 후보를 **전부** 받아 목록으로
              //   보여 준다. 1명뿐이면 서버가 found=true 로 바로 확정해 준다.
              final res = await _nas.memberLookup(q, allCandidates: true);
              if (res['found'] == true && res['member'] is Map) {
                m = (res['member'] as Map).cast<String, dynamic>();
              } else if (res['candidates'] is List &&
                  (res['candidates'] as List).isNotEmpty) {
                // 후보가 여럿(또는 1명인데 확정 못한 경우) → 사람이 고른다.
                lookupAmbiguous = res;
              }
            }
          } catch (_) {
            m = null;
          }
          if (!mounted) return;
          setSheetState(() {
            lookupBusy = false;
            if (m == null) {
              lookupOk = false;
              lookupHint = lookupAmbiguous != null
                  ? '이름이 같은 회원이 여러 명입니다 — 오른쪽 목록에서 선택하세요'
                  : '일치하는 회원(인가자·일반회원)을 찾지 못했습니다';
              return;
            }
            final mm = m;
            matched = mm;
            lookupOk = true;
            //  소속을 문구에 **명시**한다 — 범/은하 혼동을 눈으로 확인할 수 있게.
            final label = '${mm['numberLabel'] ?? mm['number'] ?? ''}';
            final corpTag = (mm['isRegular'] == true)
                ? '일반회원'
                : (mm['corps'] == 'eunha' ? '은하스카우트' : '범스카우트');
            lookupHint =
                '$corpTag · ${mm['name'] ?? ''} ($label) 정보를 불러왔습니다';
            // 빈 칸만 채운다(관리자가 고친 값 보존).
            void fill(TextEditingController c, String? v) {
              final t = '${v ?? ''}'.trim();
              if (c.text.trim().isEmpty && t.isNotEmpty) c.text = t;
            }

            fill(nameC, '${mm['name'] ?? ''}');
            fill(unitC, '${mm['unit'] ?? ''}');
            fill(genderC, '${mm['gender'] ?? ''}');
            fill(phoneC, '${mm['phone'] ?? ''}');
            fill(emailC, '${mm['email'] ?? ''}');
            fill(addrC, '${mm['address'] ?? ''}');
          });
        }

        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: '이름 *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: unitC,
                decoration: const InputDecoration(labelText: '소속'),
              ),
              const SizedBox(height: 8),
              // (요구) 인가번호를 넣으면 그 회원의 개인정보를 자동으로 채운다.
              //   · 숫자 입력 후 포커스를 잃거나 돋보기(조회)를 누르면 조회.
              //   · 이름·소속·성별·연락처·메일·주소를 비어 있는 칸에만 채워
              //     관리자가 이미 고친 값은 덮어쓰지 않는다.
              Focus(
                onFocusChange: (has) {
                  if (!has) autoFill();
                },
                child: TextField(
                  controller: numC,
                  // [요구 2026-10-29] 일반회원은 인가번호가 없다 →
                  //  전화번호·이름도 넣을 수 있어야 하므로 숫자 전용 키보드를 뺀다.
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: '인가번호 / 전화번호 / 이름',
                    helperText: lookupHint,
                    helperStyle: TextStyle(
                      fontSize: 10.5,
                      color: lookupOk
                          ? AppColors.scoutGreen
                          : AppColors.textGray,
                    ),
                    suffixIcon: lookupBusy
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: '개인정보 불러오기',
                            icon: const Icon(Icons.person_search, size: 20),
                            onPressed: autoFill,
                          ),
                  ),
                  onSubmitted: (_) => autoFill(),
                ),
              ),
              // ── 동명이인 후보 선택 ────────────────────────────────
              //  이름으로 조회했을 때 후보가 여러 명이면 **아무나 채우지
              //  않는다.** 범/은하 번호가 겹치는 체계에서 자동 선택은 곧
              //  남의 개인정보 노출이다. 사람이 직접 고른다.
              if (lookupAmbiguous != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.hermesTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.hermesOrange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '이름이 같은 회원 ${lookupAmbiguous!['count'] ?? ''}명 '
                        '— 열 사람을 선택하세요',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.hermesInk,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final c in ((lookupAmbiguous!['candidates']
                                  as List?) ??
                              const [])
                          .whereType<Map>())
                        InkWell(
                          onTap: () {
                            final cc = c.cast<String, dynamic>();
                            setSheetState(() {
                              matched = cc;
                              lookupOk = true;
                              lookupAmbiguous = null;
                              lookupHint =
                                  '${cc['numberLabel'] ?? ''} · ${cc['name'] ?? ''} 선택됨';
                              void fill(TextEditingController t, String? v) {
                                final x = '$v'.trim();
                                if (t.text.trim().isEmpty && x.isNotEmpty) {
                                  t.text = x;
                                }
                              }

                              fill(nameC, '${cc['name'] ?? ''}');
                              fill(unitC, '${cc['unit'] ?? ''}');
                              fill(genderC, '${cc['gender'] ?? ''}');
                              fill(phoneC, '${cc['phone'] ?? ''}');
                              fill(emailC, '${cc['email'] ?? ''}');
                              fill(addrC, '${cc['address'] ?? ''}');
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c['corps'] == 'eunha'
                                        ? AppColors.taegeukBlue
                                        : (c['isRegular'] == true
                                            ? AppColors.textGray
                                            : AppColors.taegeukRed),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    c['corps'] == 'eunha'
                                        ? '은하'
                                        : (c['isRegular'] == true
                                            ? '일반'
                                            : '범'),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${c['name'] ?? ''} · '
                                    '${c['numberLabel'] ?? ''}'
                                    '${'${c['unit'] ?? ''}'.trim().isEmpty ? '' : ' · ${c['unit']}'}',
                                    style: const TextStyle(fontSize: 11.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 16),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: genderC,
                decoration: const InputDecoration(labelText: '성별'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneC,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: '연락처'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailC,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '메일주소'),
              ),
              const SizedBox(height: 8),
              AddressField(
                controller: addrC,
                label: '현재 주소 (회원정보에 반영)',
                hint: '주소검색 버튼으로 검색하세요',
              ),
              const SizedBox(height: 8),
              // (요구) 참가신청 창과 동일한 '추가 입력 사항'.
              TextField(
                controller: transportC,
                decoration: const InputDecoration(labelText: '이동 방법'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: transportNoteC,
                decoration: const InputDecoration(labelText: '이동 방법 직접입력 (기타)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: lodgingC,
                decoration: const InputDecoration(labelText: '숙박 여부'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: arriveC,
                decoration: const InputDecoration(labelText: '도착 예정 시간'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: arriveNoteC,
                decoration: const InputDecoration(
                  labelText: '도착 예정 시간 직접입력 (기타)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fromC,
                decoration: const InputDecoration(labelText: '출발 장소'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: etaC,
                decoration: const InputDecoration(labelText: '예상 소요시간'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: companionC,
                decoration: const InputDecoration(labelText: '동행자 이름'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: messageC,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '운영진께 전달할 내용'),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '항목 (복수 선택)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in all)
                    FilterChip(
                      label: Text(r),
                      selected: roles.contains(r),
                      selectedColor: AppColors.purple,
                      labelStyle: TextStyle(
                        color: roles.contains(r)
                            ? Colors.white
                            : AppColors.purple,
                      ),
                      onSelected: (v) => setSheetState(
                        () => v ? roles.add(r) : roles.remove(r),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
    // 시트는 true(저장)/null(취소) 을 돌려준다.
    if (saved != true) return;
    if (nameC.text.trim().isEmpty) {
      _snack('이름을 입력하세요');
      return;
    }
    // ══════════════════════════════════════════════════════════════════
    // [신원 명시 저장 2026-10-29] "이 사람이 인가자인가" 를 **저장**한다.
    //
    //  ## 사고 재발 방지의 핵심
    //   예전에는 인가번호가 없으면 그냥 빈 문자열이었고, 조회할 때
    //   "번호가 없네 → 이름으로 찾자" 는 폴백이 사고를 만들었다.
    //   이제는 저장 시점에 신원을 **못박아** 둔다:
    //     · identityType = 'licensed'(인가자) | 'regular'(비인가/일반)
    //     · identityKey  = 'tsak:415' | 'eunha:G75' | 'reg:010…'
    //     · licensed     = bool (서버·구버전 호환용 명시 필드)
    //   → 나중에 이름이 같아도 이 키로만 연결하므로 절대 섞이지 않는다.
    // ══════════════════════════════════════════════════════════════════
    // ══════════════════════════════════════════════════════════════════
    // [사고 수정 2026-10-29] **전화번호를 인가번호로 오인하던 버그**
    //
    // ## 실제 사고 (요구: "이지원 일반회원을 클릭 → 신규등록 → 또 신규등록")
    //  조회 결과가 없어 관리자가 [인가번호] 칸에 전화번호
    //  `010-2702-1126` 을 넣고 저장하면, 종전 코드는 "숫자가 있으니 인가자"
    //  로 단정해 `identityKey = tsak:01027021126` 을 저장했다.
    //  그런데 회원 명부의 이지원은 `reg:01027021126`(일반회원) 이다.
    //  키가 **영원히 만나지 않으니** 등록을 몇 번 해도 매번 "신규 등록" 이
    //  떴다. 루틴이 반복된 진짜 이유가 이것이다.
    //
    // ## 고친 규칙 (우선순위)
    //   ① 자동채움으로 **매칭된 회원**이 있으면 그 회원의 신원을 그대로 쓴다.
    //      (사람이 이미 조회해서 고른 결과가 가장 믿을 만하다)
    //   ② 매칭이 없으면 **전화번호 모양(11자리)** 은 인가번호로 보지 않는다.
    //      인가번호는 1~4자리 수준이고, 010으로 시작하는 11자리는 연락처다.
    //   ③ 그래도 숫자가 남으면 인가번호로 본다.
    // ══════════════════════════════════════════════════════════════════
    final identNum = numC.text.trim();
    final identPhone = phoneC.text.trim();
    final identRawDigits = identNum.replaceAll(RegExp(r'[^0-9]'), '');
    final phoneDigits = identPhone.replaceAll(RegExp(r'[^0-9]'), '');
    // 11자리(휴대폰) 모양은 인가번호가 아니라 연락처다.
    final looksLikePhone =
        identRawDigits.length >= 10 || identRawDigits.startsWith('01');
    final identDigits = looksLikePhone ? '' : identRawDigits;

    // ── ① 매칭된 회원 우선 ────────────────────────────────────────────
    final matchedNumber =
        '${matched?['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final matchedIsRegular = matched?['isRegular'] == true;
    final matchedCorps = '${matched?['corps'] ?? ''}'.trim();

    bool isLicensed;
    String identityType;
    String identityKey;
    String rowNumber = identNum;
    String rowPhone = identPhone;
    String rowCorps = '';

    if (matched != null && !matchedIsRegular && matchedNumber.isNotEmpty) {
      // 매칭된 **인가자** → 그 번호를 신원으로 못박는다.
      isLicensed = true;
      identityType = 'licensed';
      final isE = matchedCorps == 'eunha';
      identityKey = isE ? 'eunha:G$matchedNumber' : 'tsak:$matchedNumber';
      rowCorps = isE ? 'eunha' : 'tsak';
      // 인가번호 칸에 전화번호를 넣었더라도 실제 인가번호로 바로잡는다.
      rowNumber = isE ? 'G$matchedNumber' : matchedNumber;
    } else if (matched != null && matchedIsRegular) {
      // 매칭된 **일반회원** → 전화번호가 신원.
      final mm = matched!;
      isLicensed = false;
      identityType = 'regular';
      final mpRaw = '${mm['phone'] ?? ''}';
      final mp = mpRaw.replaceAll(RegExp(r'[^0-9]'), '');
      final keyPh = phoneDigits.isNotEmpty ? phoneDigits : mp;
      identityKey = keyPh.isNotEmpty ? 'reg:$keyPh' : '';
      // 인가번호 칸에 전화번호가 들어와 있으면 번호 칸은 비운다.
      rowNumber = looksLikePhone ? '' : identNum;
      if (rowPhone.isEmpty && mp.isNotEmpty) rowPhone = mpRaw;
    } else if (identDigits.isNotEmpty) {
      // 매칭 없음 + 진짜 인가번호 모양 → 인가자로 저장.
      isLicensed = true;
      identityType = 'licensed';
      final wantsEunha =
          RegExp(r'^(g|G|은하|갤럭시)').hasMatch(identNum);
      identityKey = wantsEunha ? 'eunha:G$identDigits' : 'tsak:$identDigits';
      rowCorps = wantsEunha ? 'eunha' : 'tsak';
    } else {
      // 일반(비인가) — 전화번호가 신원.
      isLicensed = false;
      identityType = 'regular';
      // 인가번호 칸에 전화번호가 들어와 있으면 그 값을 전화번호로 옮긴다.
      final keyPh = phoneDigits.isNotEmpty
          ? phoneDigits
          : (looksLikePhone ? identRawDigits : '');
      identityKey = keyPh.isNotEmpty ? 'reg:$keyPh' : '';
      if (rowPhone.isEmpty && looksLikePhone) rowPhone = identNum;
      rowNumber = looksLikePhone ? '' : identNum;
    }

    final row = <String, dynamic>{
      'number': rowNumber,
      'name': nameC.text.trim(),
      'unit': unitC.text.trim(),
      'gender': genderC.text.trim(),
      'phone': rowPhone,
      'email': emailC.text.trim(),
      'address': addrC.text.trim(),
      'roles': roles.toList(),
      // ── 신원 명시 필드(위 규칙) ──────────────────────────────────────
      'identityType': identityType,
      'identityKey': identityKey,
      'licensed': isLicensed,
      if (isLicensed) 'corps': rowCorps,
      // (요구) 참가신청 창과 동일한 추가 입력 항목.
      'transport': transportC.text.trim(),
      'transportNote': transportNoteC.text.trim(),
      'lodging': lodgingC.text.trim(),
      'arrive': arriveC.text.trim(),
      'arriveNote': arriveNoteC.text.trim(),
      'from': fromC.text.trim(),
      'eta': etaC.text.trim(),
      'companion': companionC.text.trim(),
      'message': messageC.text.trim(),
    };
    setState(() {
      if (editIndex != null) {
        _attendees[editIndex] = row;
      } else {
        _attendees.add(row);
      }
    });
    await _saveAttendees();
    // (요구) 이 참가자의 개인정보 "행사참가 이력"에 이 행사를 **즉시** 반영.
    //   서버(/api/event/attendee/set)가 eventAttend[행사명]=true 를 기록하지만
    //   앱 메모리 캐시는 그대로라 개인정보 창을 열면 아직 안 보인다.
    //   여기서 로컬 캐시를 함께 갱신해 곧바로 확인할 수 있게 한다.
    if (!mounted) return;
    final state = context.read<AppState>();
    final ident = [
      numC.text.trim(),
      phoneC.text.trim(),
      '${matched?['number'] ?? ''}',
    ].where((e) => '$e'.replaceAll(RegExp(r'[^0-9]'), '').isNotEmpty);
    if (ident.isNotEmpty) {
      try {
        await state.linkEventToMembers(widget.title, ident.map((e) => '$e'));
      } catch (_) {}
    }
  }

  // ============================ 사진+동영상 ============================
  static const List<String> _mediaExts = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'mp4',
    'mov',
    'webm',
  ];

  /// 서버가 업로드 폴더를 처음 만들 때 넣어두는 **안내용 샘플 파일**.
  ///
  /// `샘플_사진설명.txt` 같은 파일이 실제 사진과 똑같은 카드로 보여
  /// "사진이 이 파일 하나뿐"으로 오해되던 문제를 막는다(요구: "나스 내에
  /// 있는 폴더내 사진이 보여지지 않음"). 이름이 `샘플_` 로 시작하면 목록에서
  /// 감추되, 폴더가 완전히 비어 보이지 않도록 안내 문구는 따로 띄운다.
  static bool _isSampleHint(String name) {
    final n = name.trim();
    return n.startsWith('샘플_') && n.toLowerCase().endsWith('.txt');
  }

  Widget _mediaTab() {
    // 샘플 안내문(.txt)은 그리드에서 제외 — 사진/영상만 보이게.
    final visible = _media
        .where((m) => !_isSampleHint('${m['name'] ?? ''}'))
        .toList();
    final folders = visible.where((m) => m['isdir'] == true).toList();
    final files = visible.where((m) => m['isdir'] != true).toList();
    return Column(
      children: [
        // ---- 브레드크럼 (하위폴더 탐색) ----
        if (_mediaPath.isNotEmpty)
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: HScrollMenu(
              height: 30,
              child: Row(
                children: [
                  _crumb(
                    '사진+동영상',
                    () => setState(() {
                      _mediaPath = [];
                      _mediaSel.clear();
                      _load();
                    }),
                  ),
                  for (var i = 0; i < _mediaPath.length; i++) ...[
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.textGray,
                    ),
                    _crumb(
                      _mediaPath[i],
                      i == _mediaPath.length - 1
                          ? null
                          : () => setState(() {
                              _mediaPath = _mediaPath.sublist(0, i + 1);
                              _mediaSel.clear();
                              _load();
                            }),
                    ),
                  ],
                ],
              ),
            ),
          ),
        // ---- 업로드 / 폴더 / 선택 툴바 ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                  ),
                  onPressed: () => _uploadFiles(
                    'media',
                    allowedExts: _mediaExts,
                    sub: _mediaSub,
                  ),
                  icon: const Icon(Icons.add_photo_alternate),
                  label: Text(_mediaPath.isEmpty ? '사진/동영상 올리기' : '이 폴더에 올리기'),
                ),
              ),
              const SizedBox(width: 8),
              // 새 폴더 만들기
              IconButton(
                tooltip: '새 폴더 만들기',
                onPressed: _createMediaFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              // 열 수 조절 (−/열수/+): 핀치 줌이 안 되는 PC·마우스 환경 지원
              IconButton(
                tooltip: '열 줄이기 (사진 확대)',
                visualDensity: VisualDensity.compact,
                onPressed: _cols > 1
                    ? () => setState(() => _cols = (_cols - 1).clamp(1, 10))
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$_cols열',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                tooltip: '나스에서 다시 불러오기\n(PC·탐색기에서 직접 올린 파일 반영)',
                visualDensity: VisualDensity.compact,
                onPressed: _refreshMedia,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: '열 늘리기 (사진 축소)',
                visualDensity: VisualDensity.compact,
                onPressed: _cols < 10
                    ? () => setState(() => _cols = (_cols + 1).clamp(1, 10))
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              // 선택 모드 토글 (항목 있을 때만)
              if (files.isNotEmpty || folders.isNotEmpty)
                IconButton(
                  tooltip: _mediaSelect ? '선택 취소' : '선택',
                  onPressed: () => setState(() {
                    _mediaSelect = !_mediaSelect;
                    if (!_mediaSelect) _mediaSel.clear();
                  }),
                  icon: Icon(
                    _mediaSelect ? Icons.close : Icons.check_circle_outline,
                    color: _mediaSelect ? AppColors.taegeukRed : null,
                  ),
                ),
              // 그리드 열 선택 (1~5열)
              PopupMenuButton<int>(
                tooltip: '그리드',
                icon: const Icon(Icons.grid_view),
                onSelected: (v) => setState(() => _cols = v),
                itemBuilder: (_) => [
                  for (var i = 1; i <= 10; i++)
                    PopupMenuItem(
                      value: i,
                      child: Row(
                        children: [
                          if (_cols == i)
                            const Icon(
                              Icons.check,
                              size: 16,
                              color: AppColors.purple,
                            ),
                          Text('$i열'),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // ---- 다운로드 바 ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: visible.isEmpty
                      ? null
                      : () => _download(
                          _nas.eventZipUrl(
                            widget.year,
                            widget.title,
                            'media',
                            sub: _mediaSub,
                          ),
                        ),
                  icon: const Icon(Icons.download),
                  label: const Text('전체 다운로드'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _mediaSel.isEmpty
                        ? Colors.grey
                        : AppColors.scoutGreen,
                  ),
                  onPressed: _mediaSelect && _mediaSel.isNotEmpty
                      ? _downloadSelectedMedia
                      : null,
                  icon: const Icon(Icons.check_circle),
                  label: Text('선택 다운로드 (${_mediaSel.length})'),
                ),
              ),
              if (_mediaSelect && _mediaSel.isNotEmpty && widget.canManage) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.taegeukRed,
                    ),
                    onPressed: _deleteSelectedMedia,
                    icon: const Icon(Icons.delete_outline),
                    label: Text('선택 삭제 (${_mediaSel.length})'),
                  ),
                ),
              ],
            ],
          ),
        ),
        // ── 폴더명 불일치 안내 ───────────────────────────────────────────
        //  (요구) "결정적 단서를 찾았습니다. 앱 상단 제목과 나스 폴더명이
        //  다릅니다." — 서버가 실제 나스 폴더명을 알려주면 그대로 노출한다.
        if (_folderAlias != null &&
            _mediaPath.isEmpty &&
            widget.canManage)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(10, 2, 10, 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.tigerGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.tigerGold.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.drive_file_rename_outline,
                  size: 18,
                  color: AppColors.tigerGold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '나스 실제 폴더명: '
                        '${_folderAlias!['nas'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '앱 제목과 달라도 위 폴더의 사진을 그대로 불러옵니다.',
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          color: AppColors.textGray.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        // ── 재귀 평탄화 보기 안내 ────────────────────────────────────────
        if (_mediaDeep && _mediaPath.isEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(10, 2, 10, 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.scoutGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.scoutGreen.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.photo_library_outlined,
                  size: 17,
                  color: AppColors.scoutGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '하위 폴더까지 모두 펼쳐서 보는 중 · ${visible.length}개',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // ── 폴더만 있는 상태 안내 ────────────────────────────────────────
        //  (요구) "나스 내에 있는 폴더내 사진이 보여지지 않음"
        //  폴더가 2개 이상이라 자동 진입을 하지 못한 경우, 폴더를 눌러야
        //  사진이 보인다는 것을 **명시적으로** 알려준다(빈 화면 오해 방지).
        if (visible.isNotEmpty &&
            folders.isNotEmpty &&
            files.isEmpty &&
            _mediaPath.isEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(10, 2, 10, 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.folder_open,
                  size: 18,
                  color: AppColors.purple,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '사진은 아래 폴더 ${folders.length}개 안에 있습니다. '
                    '폴더를 눌러 여세요.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '사진·동영상을 올려주세요',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: _createMediaFolder,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('새 폴더 만들기'),
                      ),
                    ],
                  ),
                )
              : GestureDetector(
                  // 핀치(두 손가락) 확대/축소 → 이미지 열 수 조절 (1~10열, 아이폰식)
                  onScaleStart: (_) => _pinchBaseCols = _cols,
                  onScaleUpdate: (d) {
                    if (d.pointerCount < 2 || d.scale == 0) return;
                    // 확대(scale>1)하면 열이 줄어 이미지가 커지고, 축소하면 열이 늘어남
                    final target = (_pinchBaseCols / d.scale).round();
                    final clamped = target.clamp(1, 10);
                    if (clamped != _cols) setState(() => _cols = clamped);
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _cols,
                      mainAxisSpacing: _cols > 5 ? 3 : 6,
                      crossAxisSpacing: _cols > 5 ? 3 : 6,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (_, i) => _mediaTile(visible[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _crumb(String label, VoidCallback? onTap) {
    final isLast = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isLast ? FontWeight.w800 : FontWeight.w600,
          color: isLast ? AppColors.purple : AppColors.textGray,
        ),
      ),
    );
  }

  Future<void> _createMediaFolder() async {
    final ctrl = TextEditingController();
    // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 바텀시트로 전환.
    final ok = await showTsakFormSheet(
      context: context,
      title: '새 폴더 만들기',
      subtitle: _mediaPath.isEmpty ? '사진첩 폴더를 만듭니다' : '하위 폴더를 만듭니다',
      icon: Icons.create_new_folder_outlined,
      saveLabel: '만들기',
      builder: (ctx, setSheetState) => SizedBox(
        width: 420,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '폴더 이름',
            hintText: _mediaPath.isEmpty ? '예: 1일차, 단체사진' : '하위 폴더',
          ),
        ),
      ),
    );
    final name = ctrl.text.trim();
    if (ok != true || name.isEmpty) return;
    final done = await _nas.eventMediaMkdir(
      widget.year,
      widget.title,
      'media',
      name,
      sub: _mediaSub,
    );
    if (!done) _snack('폴더 생성 실패');
    await _load();
  }

  /// 나스에서 **강제로 다시 읽기** — PC·탐색기에서 직접 올린 파일 반영.
  Future<void> _refreshMedia() async {
    _snack('나스에서 다시 불러오는 중…');
    await _load(fresh: true);
    if (!mounted) return;
    final n = _mediaHere.where((m) => m['isdir'] != true).length;
    final d = _mediaHere.where((m) => m['isdir'] == true).length;
    _snack('새로고침 완료 · 폴더 $d개 / 파일 $n개');
  }

  void _enterFolder(String name, {bool auto = false}) {
    setState(() {
      _mediaPath = [..._mediaPath, name];
      _mediaSel.clear();
      if (auto) _mediaAutoOpened = true;
    });
    // 폴더 진입: 썸네일·최적화본을 미리 만들며 불러오는 중임을 안내.
    //  단, '자동 진입'은 사용자가 누른 게 아니므로 안내 오버레이를 띄우지
    //  않는다(앱이 저절로 멈춘 것처럼 보이는 것을 막는다).
    if (!auto) _showMediaBusy('사진 폴더를 여는 중입니다');
    _load();
  }

  /// 사진/동영상 목록 로딩 중 공통 오버레이(멈춤 아님 안내).
  void _showMediaBusy(String title) {
    if (!mounted) return;
    showBusy(
      context,
      title: title,
      lines: [
        'NAS 서버에서 목록을 불러오고 있습니다...',
        '썸네일·최적화 이미지를 준비하는 중...',
        '잠시만 기다려 주세요...',
      ],
    );
  }

  /// 선택 항목 토큰 ('현재폴더 파일'=name, '하위폴더 파일'=segSub:name)
  void _downloadSelectedMedia() {
    if (_mediaSel.isEmpty) return;
    // [중요] 평탄화 보기(하위폴더 펼침)에서는 같은 사진 이름이 서로 다른
    //  폴더에 있을 수 있다. 서버는 'sub/seg:name' 토큰으로 하위폴더 파일을
    //  구분하므로, 항목의 sub 를 토큰에 함께 실어 보낸다.
    //  (그냥 이름만 보내면 엉뚱한 폴더의 동명 파일이 내려간다)
    final tokens = <String>[];
    for (final m in _media) {
      final nm = '${m['name']}';
      if (!_mediaSel.contains(nm)) continue;
      final s = '${m['sub'] ?? ''}';
      tokens.add(s.isEmpty ? nm : '$s:$nm');
    }
    if (tokens.isEmpty) return;
    _download(
      _nas.eventZipUrl(
        widget.year,
        widget.title,
        'media',
        sub: _mediaSub,
        files: tokens,
      ),
    );
  }

  /// 선택한 사진/동영상 일괄 삭제 (선택 모드)
  Future<void> _deleteSelectedMedia() async {
    if (_mediaSel.isEmpty) return;
    final items = _media
        .where((m) => _mediaSel.contains('${m['name']}'))
        .toList();
    final hasDir = items.any((m) => m['isdir'] == true);
    final n = _mediaSel.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('선택 삭제'),
        content: Text(
          hasDir
              ? '선택한 $n개 항목(폴더 포함)을 삭제할까요?\n폴더는 안의 내용까지 모두 삭제됩니다.'
              : '선택한 $n개 항목을 삭제할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    var fail = 0;
    for (final m in items) {
      final name = '${m['name']}';
      final isdir = m['isdir'] == true;
      // [중요] 평탄화 보기에서는 항목마다 폴더가 다르다 → 항목의 sub 사용.
      final itemSub = '${m['sub'] ?? ''}'.isNotEmpty
          ? '${m['sub']}'
          : _mediaSub;
      try {
        final done = await _nas.eventFileDelete(
          widget.year,
          widget.title,
          'media',
          name,
          sub: itemSub,
          isdir: isdir,
        );
        if (done != true) fail++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() {
      _mediaSel.clear();
      _mediaSelect = false;
    });
    await _load();
    _snack(fail == 0 ? '선택한 항목을 삭제했습니다' : '$fail개 삭제 실패');
  }

  Widget _mediaTile(Map<String, dynamic> item) {
    final m = item;
    final name = '${m['name']}';
    final isDir = m['isdir'] == true;
    final kind = '${m['kind'] ?? 'image'}';
    final uploader = _uploaderLabel('${m['uploader'] ?? ''}');
    final selected = _mediaSel.contains(name);

    // (버그 수정) '사진+동영상' 탭이 이미지/영상이 **아닌 파일**까지 썸네일로
    //  요청해 회색 빈칸(16×16 플레이스홀더)만 보이던 문제.
    //  서버 `/api/event/thumb2` 는 이미지가 아니면 썸네일을 만들 수 없어
    //  회색 JPEG 를 돌려준다 → 화면은 '빈 사진'으로 보인다.
    //  미디어가 아닌 파일(.txt·.xlsx 등)은 썸네일을 아예 요청하지 않고
    //  파일 카드로 그린다.
    final isMedia = kind == 'image' || kind == 'video';
    // [중요] 하위폴더까지 펼친 보기(평탄화)에서는 각 파일이 서로 다른
    //  폴더에 있다. 항상 현재 폴더(_mediaSub)를 쓰면 썸네일이 404 로
    //  깨져 '사진이 안 보인다'로 되돌아간다 → 항목별 sub 를 우선 사용.
    final itemSub = '${m['sub'] ?? ''}'.isNotEmpty
        ? '${m['sub']}'
        : _mediaSub;
    // 썸네일 경로가 없으면 Image.network 을 만들지 않는다 —
    //  null URL 로 네트워크 요청이 나가는 것을 막는다.
    final thumbUrl = isMedia
        ? _nas.eventThumb2Url(widget.year, widget.title, name, sub: itemSub)
        : '';
    // 화면 폭/열 수에 맞춰 디코딩 크기를 제한 → 메모리·디코딩 비용 절감(로딩 가속).
    final cacheW =
        ((MediaQuery.of(context).size.width / _cols) *
                MediaQuery.of(context).devicePixelRatio)
            .round()
            .clamp(60, 2048);

    if (isDir) {
      final cnt = m['count'] ?? 0;
      return RepaintBoundary(
        child: GestureDetector(
          onTap: () => _enterFolder(name),
          onLongPress: () => _mediaFolderMenu(name),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3EEFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder, size: 40, color: AppColors.purple),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: MarqueeText(
                    name,
                    maxLines: 1,
                    align: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  ((m['photo'] as num?)?.toInt() ?? 0) +
                              ((m['video'] as num?)?.toInt() ?? 0) >
                          0
                      ? '사진 ${(m['photo'] as num?)?.toInt() ?? 0} · '
                          '영상 ${(m['video'] as num?)?.toInt() ?? 0}'
                      : '$cnt개',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textGray,
                  ),
                ),
                if (((m['sizeTotal'] as num?)?.toInt() ?? 0) > 0)
                  Text(
                    _fmtSize((m['sizeTotal'] as num).toInt()),
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.purple.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 2),
                MarqueeText(
                  _uploaderLabel('${m['uploader'] ?? ''}'),
                  maxLines: 1,
                  align: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 미디어가 아닌 파일(.txt·.xlsx·.pdf 등) — 썸네일 대신 확장자 카드.
    if (!isMedia) {
      return RepaintBoundary(
        child: GestureDetector(
          onTap: () {
            if (_mediaSelect) {
              setState(() {
                if (selected) {
                  _mediaSel.remove(name);
                } else {
                  _mediaSel.add(name);
                }
              });
            } else {
              _openOtherFile(name);
            }
          },
          onLongPress: () {
            setState(() {
              _mediaSelect = true;
              _mediaSel.add(name);
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.purple.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _fileIcon(name),
                              size: 32,
                              color: AppColors.purple.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _fileExtLabel(name),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppColors.purple.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_mediaSelect)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.scoutGreen
                                  : Colors.black38,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(3),
                            child: Icon(
                              selected ? Icons.check : Icons.circle_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              MarqueeText(
                name,
                maxLines: 1,
                align: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textGray,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Builder(
                builder: (_) {
                  final sz = (m['size'] as num?)?.toInt() ?? 0;
                  if (sz <= 0) return const SizedBox.shrink();
                  return Text(
                    _fmtSize(sz),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.purple.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          if (_mediaSelect) {
            setState(() {
              if (selected) {
                _mediaSel.remove(name);
              } else {
                _mediaSel.add(name);
              }
            });
          } else {
            _openViewer(m);
          }
        },
        onLongPress: () {
          setState(() {
            _mediaSelect = true;
            _mediaSel.add(name);
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (kind == 'video')
                      Image.network(
                        thumbUrl,
                        fit: BoxFit.cover,
                        cacheWidth: cacheW,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.black87,
                          child: const Icon(
                            Icons.videocam,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      )
                    else
                      Image.network(
                        thumbUrl,
                        fit: BoxFit.cover,
                        cacheWidth: cacheW,
                        loadingBuilder: (_, child, prog) => prog == null
                            ? child
                            : Container(
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image, size: 28),
                        ),
                      ),
                    if (kind == 'video')
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    // 선택 표시
                    if (_mediaSelect)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.scoutGreen
                                : Colors.black38,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            selected ? Icons.check : Icons.circle_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 업로더 이름 (사진 아래, 구글포토식)
            const SizedBox(height: 2),
            MarqueeText(
              uploader,
              maxLines: 1,
              align: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textGray,
                fontWeight: FontWeight.w600,
              ),
            ),
            // 사진·동영상 용량(사용자가 열어볼지 결정하는 데 도움)
            Builder(
              builder: (_) {
                final sz = (m['size'] as num?)?.toInt() ?? 0;
                if (sz <= 0) return const SizedBox.shrink();
                return Text(
                  _fmtSize(sz),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: AppColors.purple.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mediaFolderMenu(String name) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('이 폴더 전체 다운로드 (ZIP)'),
              onTap: () => Navigator.pop(ctx, 'zip'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('이름 변경'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.taegeukRed,
              ),
              title: const Text(
                '폴더 삭제',
                style: TextStyle(color: AppColors.taegeukRed),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (v == 'zip') {
      _download(
        _nas.eventZipUrl(
          widget.year,
          widget.title,
          'media',
          sub: _mediaSub.isEmpty ? name : '$_mediaSub/$name',
        ),
      );
    } else if (v == 'rename') {
      await _renameFile('media', name, sub: _mediaSub);
    } else if (v == 'delete') {
      await _deleteFile('media', name, sub: _mediaSub, isdir: true);
    }
  }

  /// 미디어가 아닌 파일(.txt·.xlsx·.pdf 등) 열기 — 외부 뷰어/다운로드.
  Future<void> _openOtherFile(String name) async {
    try {
      final url = _nas.eventFile2Url(
        widget.year,
        widget.title,
        'media',
        name,
        sub: _mediaSub,
      );
      await _download(url);
    } catch (e) {
      if (mounted) _snack('파일을 열 수 없습니다: $e');
    }
  }

  /// 파일 이름 → 확장자별 아이콘(썸네일을 만들 수 없는 파일 카드용).
  IconData _fileIcon(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (n.endsWith('.xlsx') || n.endsWith('.xls') || n.endsWith('.csv')) {
      return Icons.table_chart;
    }
    if (n.endsWith('.docx') || n.endsWith('.doc') || n.endsWith('.hwp')) {
      return Icons.description;
    }
    if (n.endsWith('.zip') || n.endsWith('.7z') || n.endsWith('.tar')) {
      return Icons.folder_zip;
    }
    if (n.endsWith('.pptx') || n.endsWith('.ppt')) return Icons.slideshow;
    return Icons.insert_drive_file;
  }

  /// 파일 이름 → 짧은 확장자 라벨('.txt' → 'TXT', 없으면 'FILE').
  String _fileExtLabel(String name) {
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return 'FILE';
    final ext = name.substring(i + 1).toUpperCase();
    return ext.length > 5 ? ext.substring(0, 5) : ext;
  }

  void _openViewer(Map<String, dynamic> tile) {
    // 뷰어는 **미디어(이미지·영상)만** 받는다. 목록에 .txt 같은 일반 파일이
    //  섞여 있으면 뷰어 인덱스와 타일 인덱스가 어긋나 엉뚱한 사진이 열린다.
    //  → 뷰어에 넘길 목록을 먼저 만들고, 그 안에서의 위치를 계산해 넘긴다.
    //  (버그 수정) 인덱스가 아니라 **타일 항목 자체**를 넘겨, 샘플 안내문을
    //   숨긴 뒤에도 순서가 어긋나지 않게 한다.
    final items = _media
        .where((m) => m['isdir'] != true)
        .where((m) => !_isSampleHint('${m['name'] ?? ''}'))
        .where((m) {
      final k = '${m['kind'] ?? 'image'}';
      return k == 'image' || k == 'video';
    }).toList();
    // 현재 타일이 가리키는 파일이 뷰어 목록에서 몇 번째인지.
    //  (평탄화 보기에서는 같은 이름이 서로 다른 폴더에 있을 수 있어
    //   이름 + sub 를 함께 비교한다)
    final name = '${tile['name']}';
    final tileSub = '${tile['sub'] ?? ''}';
    var at = items.indexWhere((m) =>
        '${m['name']}' == name && '${m['sub'] ?? ''}' == tileSub);
    if (at < 0) at = items.indexWhere((m) => '${m['name']}' == name);
    if (at < 0) at = 0;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MediaViewer(
          year: widget.year,
          title: widget.title,
          sub: _mediaSub,
          items: items,
          initialIndex: at,
          canDeleteAll: widget.canManage,
          myName: _uploaderName(),
        ),
      ),
    ).then((_) => _load());
  }

  String _uploaderName() {
    final s = context.read<AppState>();
    if (s.isMaster) return '마스터';
    if (s.isApp) return '관리자';
    if (s.who.isNotEmpty) {
      // 인가번호가 아닌 '이름'으로 기록 (사진 올린 사람 이름 표시)
      final m = s.repo.byNumber(s.who);
      if (m != null && m.name.isNotEmpty) return m.name;
      return s.who;
    }
    return '참가자';
  }

  /// 사진/폴더에 표시할 업로더 라벨.
  ///
  /// - 개별 파일 메타에 업로더가 있으면 → 이름으로 변환(인가번호면 회원명)
  /// - 업로더 정보가 없으면(예: 폴더째 올린 사진) → '415호' 로 일괄 표시
  String _uploaderLabel(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '415호';
    if (v == '마스터' || v == '관리자' || v == '참가자') return v;
    final m = context.read<AppState>().repo.byNumber(v);
    if (m != null && m.name.isNotEmpty) return m.name;
    return v;
  }

  // ============================ 재무(참가비/후원금·지출) ============================
  /// 재무 탭 3종.
  ///  · `fee`      → 참가비 (category == '참가비')
  ///  · `donation` → 후원·기타수입 (후원 / 후원금 / 기타)
  ///  · `expense`  → 행사비지출 (_expenses 전체)
  /// (요구) "참가비/후원금, 후원·기타수입, 행사비지출을 각각 따로 관리"
  /// ※ 후원 카테고리 판정은 `lib/services/donation_kinds.dart` 의
  ///   `DonationKind.isNonDonation()` 하나만 쓴다(중복 정의 금지).

  List<Map<String, dynamic>> _rowsOf(String kind) {
    if (kind == 'expense') return _expenses;
    if (kind == 'fee') {
      return _fees
          .where((r) => '${r['category'] ?? '참가비'}'.trim() == '참가비')
          .toList();
    }
    // 후원·기타수입 — 참가비를 제외한 모든 수입(후원/후원금/기타/수송지원 등).
    return _fees
        .where((r) => '${r['category'] ?? '참가비'}'.trim() != '참가비')
        .toList();
  }

  String _financeTitle(String kind) => switch (kind) {
    'fee' => '참가비 납부자',
    'donation' => '후원 · 기타수입',
    _ => '행사비 지출내역',
  };

  Color _financeColor(String kind) => switch (kind) {
    'fee' => AppColors.scoutGreen,
    'donation' => AppColors.tigerGold,
    _ => AppColors.taegeukRed,
  };

  /// 재무 로드 실패 안내 — "0건"과 명확히 구분하기 위한 배너.
  Widget _financeErrorBanner(String err) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.taegeukRed.withValues(alpha: 0.07),
        border: Border.all(
          color: AppColors.taegeukRed.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: AppColors.taegeukRed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '재무 자료를 불러오지 못했습니다',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.taegeukRed,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  // 자료가 없는 것이 아니라 '못 읽은' 상태임을 분명히 한다.
                  '$err\n※ 자료가 삭제된 것이 아닙니다. 다시 시도해 주세요.',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => _load(),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: AppColors.taegeukRed,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '다시 시도',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _financeTab(String kind) {
    final fk = FinanceKind.fromKey(kind);
    final rows = _rowsOf(kind);
    // [버그 수정] "0건"과 "못 불러옴"을 구분한다 — 종전에는 401(세션만료·
    //  등급부족)이 조용히 빈 목록이 되어 입력자료가 사라진 것처럼 보였다.
    final err = _financeError;

    // ── [버그 수정 2026-10-26] 후원 탭에서 **후원 내역이 안 보이던 문제** ──
    //
    //  증상: '현물후원 5건 440,000원' 요약은 나오는데 그 아래 내역 목록이
    //        통째로 비어 있었다(아주 긴 공백만 남음).
    //
    //  원인: `DonationListPanel` 은 내부에 `Expanded` + `ListView` 를 가진
    //        '스스로 높이를 채우는' 위젯인데, 종전에는 이것을
    //        `EventFinanceTab` 의 Column 에 **일반 자식(header)** 으로 넣었다.
    //        Column 은 비-flex 자식에게 **높이 제약을 주지 않으므로**,
    //        그 안의 Expanded/ListView 는 높이 0 으로 계산되어
    //        릴리스 빌드에서 **아무것도 그리지 않았다**(예외도 없이 조용히).
    //        → 화면에는 요약만 남고 목록은 사라진 것처럼 보였다.
    //
    //  릴리스 빌드에서 **아무것도 그리지 않았다**(예외도 없이 조용히).
    //        → 화면에는 요약만 남고 목록은 사라진 것처럼 보였다.
    //
    //  또한 후원 탭은 **같은 5건을 두 번** 그리는 구조였다(패널 목록 +
    //        하단 EventFinanceTab 목록). 요약·후원자별/내역별 전환·필터·
    //        '+ 후원 추가'·'출력' 은 이미 패널이 모두 제공하므로,
    //        후원 탭은 **패널 단독**으로 구성하는 것이 맞다.
    if (kind == 'donation') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (err != null) _financeErrorBanner(err),
          // Expanded 안에서 패널이 남은 높이를 모두 쓰도록 한다(핵심).
          Expanded(
            child: DonationListPanel(
              rows: rows,
              won: _won,
              onAdd: () => _financeEdit(kind),
              onEdit: (r) => _financeEdit(kind, row: r),
              onDelete: (r) => _deleteFinanceRow(kind, r),
              // 후원자 이름 → 회원 상세. "클릭하면 서로 스위칭되는 링크".
              onOpenMember: _openMemberByDonor,
              onOutput: (view, focus) =>
                  _outputDonationList(rows: rows, view: view, focus: focus),
            ),
          ),
        ],
      );
    }

    return EventFinanceTab(
      kind: fk,
      rows: rows,
      color: _financeColor(kind),
      // 참가비 탭 — 납부 계좌 안내. 재무 로드 실패 시에는 사유 배너를 먼저.
      header: err != null
          ? _financeErrorBanner(err)
          : kind == 'fee'
          ? const Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: DonationAccounts(title: '참가비·후원 납부 계좌', showHolder: true),
            )
          : null,
      won: _won,
      onAdd: () => _financeEdit(kind),
      onEdit: (r) => _financeEdit(kind, row: r),
      onDelete: (r) => _deleteFinanceRow(kind, r),
      onReload: _load,
      // (요구) 출력 시 포함여부 — 선택된 행만 문서로 만든다.
      onOutput: (included) => _outputFinance(kind, rows: included),
    );
  }

  Future<void> _financeEdit(String kind, {Map<String, dynamic>? row}) async {
    final nameC = TextEditingController(text: '${row?['name'] ?? ''}');
    final numC = TextEditingController(text: '${row?['number'] ?? ''}');
    final amtC = TextEditingController(
      text: row != null && (row['amount'] as num? ?? 0) != 0
          ? '${row['amount']}'
          : '',
    );
    final dateC = TextEditingController(text: '${row?['date'] ?? _today()}');
    final memoC = TextEditingController(text: '${row?['memo'] ?? ''}');
    // (요구) 후원 내역 — '무엇을 후원했는지'(김밥 100줄, 버스 1대).
    final itemC = TextEditingController(text: '${row?['item'] ?? ''}');
    // (요구) '000원 상당' — 금액이 정확하지 않은 후원의 환산 가치.
    final valueC = TextEditingController(
      text: row != null && (row['value'] as num? ?? 0) != 0
          ? '${row['value']}'
          : '',
    );
    // (요구) 지출은 출금계좌(대표 3계좌 중 선택) 또는 직접입력.
    final accountC = TextEditingController(text: '${row?['account'] ?? ''}');
    String category =
        '${row?['category'] ?? (kind == 'expense' ? '행사비' : (kind == 'donation' ? '후원금' : '참가비'))}';
    // 후원 탭은 '후원금' 만 수입 — 후원(현물)은 별도 분류.
    if (kind == 'donation' && !DonationKindOptions.all.contains(category)) {
      category = '후원금';
    }
    final isDonation = kind == 'donation';
    final isSponsor = isDonation && category != '후원금';

    // (요구) "후원 및 후원금, 참가비 등은 행사비 항목에 인가번호를 기입하면
    //  자동으로 개인카드에 반영되도록 함"
    //
    //  인가번호를 넣는 **그 자리에서** 회원을 찾아
    //    ① 이름(후원자/납부자)을 자동으로 채우고
    //    ② "○○○ (415호) 개인카드에 반영됩니다" 를 초록색으로 보여주고
    //    ③ 못 찾으면 빨간색으로 '인가번호를 확인하세요' 를 보여준다.
    //  서버(finance/add·update)도 같은 인가번호로 회원을 다시 확인해
    //  status=matched / memberId 를 채우므로 개인카드 '입금 내역'에 즉시 뜬다.
    var cardBusy = false;
    var cardOk = false;
    String cardHint = '인가번호를 넣으면 그분 개인카드에 자동 반영됩니다';
    String cardName = '';

    // ── [요구 2026-11-04] 후원자/납부자 **명부 전체 검색**을 위한 인적사항 ──
    //  멘토·페런츠 인적사항(link_profiles)은 회원 카드가 없는 분들도 담고
    //  있어서, 참가비·후원 납부자를 이름/전화/연맹/단위대로 찾으려면 필요하다.
    //  관리자·마스터는 전체를, 개인 로그인은 본인 연결분만 서버가 내려준다.
    final state0 = context.read<AppState>();
    var payerProfiles = <String, dynamic>{};
    if (kind != 'expense') {
      payerProfiles = state0.linkProfiles;
      // 아직 비어 있으면(로그인 직후 등) 한 번 받아 온다 — 실패해도 무해.
      if (payerProfiles.isEmpty) {
        unawaited(state0.loadLinkProfiles());
      }
    }

    // (요구) 모바일에서 키보드가 떠도 입력칸이 잘리지 않도록 전용 시트 사용.
    final ok = await showTsakFormSheet(
      context: context,
      title: switch (kind) {
        'fee' => '참가비 입력',
        'donation' => '후원 입력',
        _ => '행사비 지출 입력',
      },
      subtitle: isDonation ? '후원금만 수입으로 잡힙니다 · 후원(현물)은 금액/상당액을 따로 기록' : null,
      icon: switch (kind) {
        'fee' => Icons.volunteer_activism,
        'donation' => Icons.card_giftcard,
        _ => Icons.payments,
      },
      accent: _financeColor(kind),
      builder: (ctx, setD) {
        // ── 인가번호 → 회원 조회 → 개인카드 반영 안내 ─────────────────
        //
        //  참석자 수동입력(`autoFill`)과 **같은 2단 조회**를 쓴다:
        //    ① 로컬 AppState 캐시(즉시·오프라인 안전)
        //    ② 서버 `memberLookup`(범+은하 통합·최신값)
        //  이름 칸이 비어 있으면 회원 이름을 **채워준다**(오타 방지).
        //  이미 적어둔 이름은 건드리지 않는다.
        Future<void> linkCard() async {
          final q = numC.text.trim();
          if (q.isEmpty || cardBusy) return;
          setD(() {
            cardBusy = true;
            cardHint = '인가번호 확인 중…';
          });
          Map<String, dynamic>? m;
          try {
            final st = context.read<AppState>();
            final local = st.byNumber(q);
            if (local != null) {
              m = {
                'id': local.id,
                'number': local.number,
                'name': local.name,
                'corps': local.corps,
                'numberLabel': local.numberLabel,
                'isRegular': local.isRegular,
              };
            }
            if (m == null) {
              final res = await _nas.memberLookup(q);
              if (res['found'] == true && res['member'] is Map) {
                m = (res['member'] as Map).cast<String, dynamic>();
              }
            }
          } catch (_) {
            m = null;
          }
          if (!mounted) return;
          setD(() {
            cardBusy = false;
            if (m == null) {
              cardOk = false;
              cardName = '';
              cardHint = '인가번호 $q 를 찾지 못했습니다 · 번호를 확인하세요';
              return;
            }
            final mm = m;
            cardOk = true;
            cardName = '${mm['name'] ?? ''}'.trim();
            final label = '${mm['numberLabel'] ?? mm['number'] ?? q}';
            cardHint = '$cardName ($label) 개인카드에 반영됩니다';
            // 이름이 비어 있을 때만 채운다(관리자가 고친 값 보존).
            if (nameC.text.trim().isEmpty && cardName.isNotEmpty) {
              nameC.text = cardName;
            }
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 후원자/납부자 — **명부 전체에서 검색해 고른다** ──
            //  [요구 2026-11-04] "납부자검색항목을 좀더 폭넓게 해주세요.
            //  인가자번호, 서포터즈이름, 멘토, 멘티, 페런츠 등 명부에 있는
            //  사람들의 전화번호, 이름, 연맹, 단위대 등등 중에서 선택할 수
            //  있도록 해줘." / "후원자, 참가비 등에도 동일하게"
            //
            //  회원 카드 + 멘토·페런츠 인적사항(link_profiles)을 **한 목록**으로
            //  합쳐 이름·인가번호·전화번호·연맹·단위대·직위로 찾는다.
            //  고르면 ① 이름을 채우고 ② 인가번호를 채운 뒤 ③ 카드 연동
            //  조회(linkCard)까지 자동 실행해 개인카드 반영 안내가 뜨게 한다.
            if (kind == 'expense')
              TsakField(
                label: '지출처 / 사용내역',
                required: true,
                child: TextField(
                  controller: nameC,
                  decoration: const InputDecoration(isDense: true),
                ),
              )
            else
              TsakPayerLookupField(
                controller: nameC,
                profiles: payerProfiles,
                onPicked: (nm, numText, ph) {
                  setD(() {
                    if (nm.isNotEmpty) nameC.text = nm;
                    if (numText.isNotEmpty) {
                      numC.text = numText;
                      cardOk = true;
                      cardName = nm;
                      cardHint = ph.isNotEmpty
                          ? '$nm (${numText.replaceAll('G', '')}) 개인카드에 반영됩니다'
                          : '$nm ($numText) 개인카드에 반영됩니다';
                    } else if (nm.isNotEmpty && ph.isNotEmpty) {
                      // 카드·인가번호가 없는 분(비인가 멘토·페런츠) — 이름/전화만.
                      numC.text = '';
                      cardOk = false;
                      cardName = nm;
                      cardHint = '$nm (전화 $ph) — 인가번호가 없어 개인카드 연동은 없습니다';
                    }
                  });
                },
              ),
            // ── 인가번호 → 개인카드 자동 연결 (요구) ──
            Focus(
              onFocusChange: (has) {
                if (!has) linkCard();
              },
              child: TsakField(
                label: '인가번호',
                hint: '넣으면 그분 개인카드에 자동 반영됩니다',
                child: TextField(
                  controller: numC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) {
                    // 번호를 고치면 이전 판정을 지운다(틀린 초록불 방지).
                    if (cardOk || cardName.isNotEmpty) {
                      setD(() {
                        cardOk = false;
                        cardName = '';
                        cardHint = '인가번호를 넣으면 그분 개인카드에 자동 반영됩니다';
                      });
                    }
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '예: 415',
                    helperText: cardHint,
                    helperMaxLines: 2,
                    helperStyle: TextStyle(
                      fontSize: 10.5,
                      height: 1.3,
                      color: cardOk ? AppColors.scoutGreen : AppColors.textGray,
                    ),
                    suffixIcon: cardBusy
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: '인가번호로 회원 확인',
                            icon: const Icon(Icons.badge_outlined, size: 18),
                            onPressed: linkCard,
                          ),
                  ),
                ),
              ),
            ),
            // ── 후원: 분류 세분화 (후원금/식사/물품/차량/기타) ──
            if (isDonation)
              TsakField(
                label: '후원 항목',
                required: true,
                child: DonationKindPicker(
                  value: category,
                  onChanged: (v) => setD(() => category = v),
                ),
              ),
            // ── 후원: 후원 내역(무엇을 후원했는지) ──
            if (isDonation)
              TsakField(
                label: '후원 내역',
                hint: isSponsor ? '예: 김밥 100줄, 버스 1대' : '선택',
                required: isSponsor,
                child: TextField(
                  controller: itemC,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '예: 김밥 100줄 / 생수 10박스 / 버스 1대',
                  ),
                ),
              ),
            // ── (요구) 금액 · 상당액 두 개의 창 ──
            if (isDonation)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TsakField(
                      label: '금액(현금)',
                      hint: '실제 낸 돈',
                      child: TextField(
                        controller: amtC,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          isDense: true,
                          suffixText: '원',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TsakField(
                      label: '금액 상당',
                      hint: '예: 10만원 상당',
                      child: TextField(
                        controller: valueC,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          isDense: true,
                          suffixText: '원 상당',
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              TsakField(
                label: '금액',
                required: true,
                child: TextField(
                  controller: amtC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: '원',
                  ),
                ),
              ),
            TsakField(
              label: '날짜',
              hint: '예: 2026-03-14',
              child: TextField(
                controller: dateC,
                decoration: const InputDecoration(isDense: true),
              ),
            ),
            // 참가비·지출 분류
            if (!isDonation)
              TsakField(
                label: '구분',
                child: DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (final c
                        in (kind == 'expense'
                            ? const [
                                '행사비',
                                '각종 지출',
                                '수품제작',
                                '기념품제작',
                                '수송지원',
                                '장소임차',
                                '식비',
                                '기타',
                              ]
                            : const ['참가비']))
                      DropdownMenuItem(
                        value: c,
                        child: Text(c, style: const TextStyle(fontSize: 12.5)),
                      ),
                  ],
                  onChanged: (v) => setD(() => category = v ?? category),
                ),
              ),
            // 지출: 출금계좌
            if (kind == 'expense')
              TsakField(
                label: '출금계좌',
                child: EventAccountPicker(
                  value: accountC.text,
                  onChanged: (v) => setD(() => accountC.text = v),
                ),
              ),
            TsakField(
              label: '메모',
              child: TextField(
                controller: memoC,
                maxLines: 2,
                decoration: const InputDecoration(isDense: true),
              ),
            ),
            // 안내 — 후원 수입 규칙을 현장에서 바로 확인.
            if (isDonation)
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color:
                      (isSponsor ? AppColors.tigerGold : AppColors.scoutGreen)
                          .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSponsor
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                      size: 14,
                      color: isSponsor
                          ? AppColors.tigerGold
                          : AppColors.scoutGreen,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        isSponsor
                            ? '${category}은(는) 수입에 넣지 않고 후원 내역으로만 집계합니다.'
                                  '금액·상당액은 결산의 후원 항목에 따로 표시됩니다.'
                            : '후원금은 현금 수입으로 합산됩니다(수입 = 참가비 + 후원금).',
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
    if (ok != true) return;
    final amt = int.tryParse(amtC.text.trim()) ?? 0;
    final val = int.tryParse(valueC.text.trim()) ?? 0;
    if (nameC.text.trim().isEmpty) {
      _snack(kind == 'expense' ? '지출처를 입력하세요' : '이름을 입력하세요');
      return;
    }
    if (amt == 0 && val == 0) {
      _snack('금액 또는 금액 상당 중 하나는 입력하세요');
      return;
    }
    final data = <String, dynamic>{
      'name': nameC.text.trim(),
      'number': numC.text.trim(),
      'amount': amt,
      'date': dateC.text.trim(),
      'category': category,
      'memo': memoC.text.trim(),
      // (요구) 후원 내역 · 금액 상당 — 후원 탭에서만 의미가 있지만
      //   서버/재무 원장이 함께 보관하도록 항상 실어 보낸다.
      if (isDonation) 'item': itemC.text.trim(),
      if (isDonation) 'value': val,
      if (kind == 'expense') 'account': accountC.text.trim(),
    };
    final saveKind = kind == 'expense' ? 'expense' : 'fee';
    final isNew = row == null || '${row['id']}'.isEmpty;
    if (isNew) {
      await _nas.eventFinanceAdd(widget.year, widget.title, saveKind, data);
    } else {
      await _nas.eventFinanceUpdate(
        widget.year,
        widget.title,
        saveKind,
        '${row['id']}',
        data,
      );
    }
    await _load();
  }

  /// 재무 행 삭제 — **화면 종류(kind)를 서버 종류로 변환해서** 보낸다.
  ///
  /// ── [버그 수정 2026-10-26] 후원 탭에서 '삭제'가 안 되던 문제 ──────────
  ///
  ///  증상: 후원 상세의 ⋮ → 삭제를 눌러도 목록에서 사라지지 않았다.
  ///
  ///  원인: 화면의 kind 는 `fee | donation | expense` 인데, 서버는
  ///        `fee | expense` **두 가지**만 안다.
  ///        · 저장은 `kind == 'expense' ? 'expense' : 'fee'` 로 변환해
  ///          올바로 `fees` 배열에 들어갔다.
  ///        · 그런데 **삭제만 `kind` 를 그대로**(`'donation'`) 보냈다.
  ///        → 서버는 `kind == 'fee'` 가 아니므로 `expenses` 배열을 뒤졌고,
  ///          해당 id 가 없으니 아무것도 지우지 않은 채
  ///          **`{"ok": true}` 를 돌려줬다.**
  ///        → 화면은 성공으로 오해하고 다시 불러왔지만 그대로였다.
  ///
  ///  수정: 저장과 **똑같은 변환 규칙**을 적용하고, 실패하면 사용자에게
  ///        명확히 알린다(조용한 성공 위장 금지).
  Future<bool> _deleteFinanceRow(String kind, Map<String, dynamic> row) async {
    final id = '${row['id'] ?? ''}';
    if (id.isEmpty) {
      _snack('삭제할 항목의 식별자가 없습니다. 새로고침 후 다시 시도해 주세요.');
      return false;
    }
    final serverKind = kind == 'expense' ? 'expense' : 'fee';
    try {
      final ok = await _nas.eventFinanceDelete(
        widget.year,
        widget.title,
        serverKind,
        id,
      );
      if (!mounted) return ok;
      if (!ok) {
        _snack('삭제하지 못했습니다 — 서버가 거부했습니다. 다시 로그인 후 시도해 주세요.');
        return false;
      }
      await _load();
      if (mounted) _snack('삭제했습니다');
      return true;
    } catch (e) {
      if (mounted) _snack('삭제 실패: $e');
      return false;
    }
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  // ============================ 출력 (요구 #2/#3) ============================
  //  기본출력 법칙(명단출력과 동일):
  //   ① 출력내용선택(열)·위치이동 ② 두줄방지(noWrap) ③ 줄간격·글씨·용지
  //   ④ 미리보기 → PDF·인쇄·엑셀 등 공용 시트.
  //  공용 엔진(table_export / tsak_output_sheet)을 그대로 재사용한다.

  /// 재무 항목(참가비·후원·지출) 표 문서.
  ///
  /// (요구) "출력시 포함여부를 선택" — `rows` 를 주면 그 행만 문서에 담는다.
  ///  선택 출력일 때는 부제·합계에 '선택 n/m건' 을 명시해 혼동을 막는다.
  TsakTableDoc _financeDoc(String kind, {List<Map<String, dynamic>>? rows}) {
    final all = _rowsOf(kind);
    final list = rows ?? all;
    final isExpense = kind == 'expense';
    final cols = [
      if (isExpense) '연번' else '연번',
      '날짜',
      '구분',
      isExpense ? '지출처/내역' : '이름/납부자',
      '인가번호',
      if (isExpense) '출금계좌',
      '금액',
      '메모',
      '자료',
    ];
    final body = <List<String>>[];
    var i = 0;
    for (final r in list) {
      i++;
      final n = (r['attach'] as num?)?.toInt() ?? 0;
      body.add([
        '$i',
        '${r['date'] ?? ''}',
        '${r['category'] ?? ''}',
        '${r['name'] ?? ''}',
        '${r['number'] ?? ''}',
        if (isExpense) '${r['account'] ?? ''}',
        _won((r['amount'] as num?)?.toInt() ?? 0),
        '${r['memo'] ?? ''}',
        n > 0 ? '$n건' : '-',
      ]);
    }
    final total = list.fold<int>(
      0,
      (s, r) => s + ((r['amount'] as num?)?.toInt() ?? 0),
    );
    final picked = rows != null && list.length != all.length;
    return TsakTableDoc(
      title: '${widget.year} ${widget.title}',
      subtitle:
          '${_financeTitle(kind)} · ${list.length}건'
          '${picked ? ' (선택 ${list.length}/${all.length}건)' : ''}',
      description: isExpense
          ? '행사에 지출한 내역을 연번 순으로 정리하고 합계를 기재합니다.'
          : '납부·후원 내역을 연번 순으로 정리하고 합계를 기재합니다.',
      columns: cols,
      rows: body,
      summary: ['총 ${list.length}건 · 합계 ${_won(total)}'],
      footerLeft: '한국범스카우트중앙회 · 행사 ${_financeTitle(kind)}',
      landscape: true,
      options: TableOutputOptions(
        // (요구) 2줄 방지 — 좁은 열은 한 줄 유지(넘치면 자동 축소).
        noWrap: const {'연번', '날짜', '구분', '인가번호', '금액', '자료'},
      ),
    );
  }

  /// 참가자 명단 표 문서(결산 탭·하단 출력 공용).
  TsakTableDoc _attendeeDoc() {
    final cols = ['연번', '이름', '인가번호', '소속', '직책', '연락처'];
    final body = <List<String>>[];
    var i = 0;
    for (final a in _attendees) {
      i++;
      final roles = ((a['roles'] as List?) ?? const [])
          .map((e) => '$e')
          .join(',');
      body.add([
        '$i',
        '${a['name'] ?? ''}',
        Member.numLabelOf(
          '${a['number'] ?? ''}',
          '${a['corps'] ?? 'tsak'}',
          a['isRegular'] == true,
        ),
        '${a['unitText'] ?? a['unit'] ?? ''}',
        roles,
        '${a['phoneText'] ?? a['phone'] ?? ''}',
      ]);
    }
    return TsakTableDoc(
      title: '${widget.year} ${widget.title}',
      subtitle: '참가자 명단 · ${_attendees.length}명',
      description: '행사 참가자 명단을 연번 순으로 정리합니다.',
      columns: cols,
      rows: body,
      summary: [
        '총 ${_attendees.length}명',
        EventAttendeeBreakdown.fromAttendees(_attendees).summaryLine,
      ],
      footerLeft: '한국범스카우트중앙회 · 행사 참가자 명단',
      landscape: true,
      options: TableOutputOptions(noWrap: const {'연번', '인가번호', '연락처'}),
    );
  }

  /// 행사 결산표 문서 — 사용자가 고른 **블록(항목)만, 고른 순서로**.
  ///
  /// (요구) "결산페이지 … 각 항목별로 취합된 데이터를 보여주고, 출력여부를 그
  ///  페이지에서 선택 … 항목별 위치 이동 … 실시간 미리보기"
  /// → 결산 탭이 만든 [SettlementLayout] + 블록 데이터를 그대로 문서로 옮긴다.
  ///   화면 미리보기와 **같은 데이터**라 "보이는 것 = 인쇄되는 것"이 된다.
  /// 행사 결산표 문서 — 사용자가 고른 **블록(항목)만, 고른 순서로**.
  ///
  /// (요구) "결산페이지 … 각 항목별로 취합된 데이터를 보여주고, 출력여부를 그
  ///  페이지에서 선택 … 항목별 위치 이동 … 실시간 미리보기"
  ///
  /// ## 왜 [SettlementDoc] 로 옮겼나
  /// 종전에는 이 화면 안에서 4열 행을 조립하고 reportBlocks 를 만들었다.
  /// 그 결과 **미리보기 위젯**(SettlementPaperView)과 **문서**가 각자 조립해
  /// 상세 내역·메모 규칙이 어긋날 위험이 있었다. 이제 변환 지점은
  /// `SettlementDoc.build` 하나뿐이고, 미리보기·PDF·JPG·엑셀·워드·인쇄가
  /// 모두 이 함수를 쓴다 — "보이는 것 = 인쇄되는 것".
  TsakTableDoc _settlementDoc(
    SettlementLayout layout,
    Map<SettlementBlock, SettlementBlockData> data,
  ) =>
      SettlementDoc.build(
        year: widget.year,
        title: widget.title,
        layout: layout,
        data: data,
        settlement: _settlementOf(),
        won: _won,
      );

  /// 결산 집계(문서·요약 공용).
  EventSettlement _settlementOf() => EventSettlement(
    title: widget.title,
    year: widget.year,
    attendeeCount: EventAttendeeBreakdown.fromAttendees(_attendees),
    attendees: _attendees,
    fees: _fees.map((e) => EventMoneyRow.fromMap(e)).toList(),
    expenses: _expenses
        .map((e) => EventMoneyRow.fromMap(e, expense: true))
        .toList(),
  );

  /// 공용 출력 시트 실행 — 옵션·미리보기·인쇄·저장.
  ///
  /// [opts] 는 **사용자가 옵션 시트에서 직접 고른 경우에만** 채워진다.
  /// 채워지기 전에는 각 문서가 스스로 만든 옵션(예: 결산 미리보기의
  /// 글씨·줄간격·용지)을 **그대로** 쓴다 — 종전에는 빈 옵션이 문서 옵션을
  /// 덮어써 미리보기에서 맞춘 서식이 인쇄물에서 사라졌다.
  Future<void> _runOutputDoc(
    TsakTableDoc Function() build, {
    required String title,
    required String subtitle,
    /// 추가입력 항목 선택 정보 — 주면 미리보기에서 항목을 켜고 끌 수 있다.
    TsakExtraPick? extra,
  }) async {
    TableOutputOptions? opts;
    // (버그 수정) 결산이 "PDF 출력해도 계속 계산서처럼 나온다"의 **진짜 원인**.
    //
    //  `_settlementDoc` 은 reportBlocks(블록 그래픽)를 채워 넘겼지만,
    //  이 함수가 문서를 **새로 조립**하면서 reportBlocks 를 **복사하지 않았다**.
    //  → buildReport 라우터가 `null` 을 보고 무인양품 표로 폴백.
    //  → PDF·JPG·HTML 인쇄 전부 계산서형. 화면 미리보기만 보고서형(모순).
    //
    //  reportBlocks / template 을 반드시 함께 넘긴다.
    TsakTableDoc doc() {
      final d = build();
      // 사용자가 고른 옵션을 반영(열 선택·순서·글씨·간격·용지).
      return TsakTableDoc(
        title: d.title,
        subtitle: d.subtitle,
        description: d.description,
        author: d.author,
        extra: d.extra,
        columns: d.columns,
        rows: d.rows,
        summary: d.summary,
        footerLeft: d.footerLeft,
        landscape: opts?.landscape ?? d.landscape,
        options: opts ?? d.options,
        reportBlocks: d.reportBlocks,
        template: d.template,
      );
    }

    await showTsakOutputSheet(
      context,
      title: title,
      subtitle: subtitle,
      onPick: (f) => _doExport(doc(), f),
      onOpen: (f) => _doExport(doc(), f, open: true),
      onPrint: () => _doPrint(doc()),
      // (요구 2026-10-31) "출력 미리보기시에도 추가항목 선택할 수 있도록"
      //  extra 를 넘기면 미리보기 창에 항목 칩이 나타나고,
      //  칩을 누르면 그 항목 열이 **즉시** 붙어 다시 그려진다.
      onPreview: () => showTsakOutputPreview(
        context,
        doc: doc(),
        extra: extra,
      ),
      onOptions: () async {
        final base = build();
        final out = await showTsakTableOptions(
          context,
          title: '$title · 출력 옵션',
          subtitle: '출력할 항목·순서·글씨·줄간격·용지를 정하세요.',
          columns: base.columns,
          initial: opts ?? base.options ?? const TableOutputOptions(),
        );
        if (out != null) opts = out;
      },
    );
  }

  Future<void> _doExport(
    TsakTableDoc doc,
    TsakOutputFormat format, {
    bool open = false,
  }) async {
    try {
      final loc = await askTsakSaveLocation(
        context,
        info: '${doc.title} · ${format.label}',
      );
      if (loc == null) return;
      if (!mounted) return;
      await saveTsakTableChosen(context, doc, format, choose: loc);
      if (mounted) _snack('${format.label} 저장을 시작했습니다');
    } catch (e) {
      if (mounted) _snack('출력 실패: $e');
    }
  }

  Future<void> _doPrint(TsakTableDoc doc) async {
    try {
      await printTsakTable(doc);
    } catch (e) {
      if (mounted) _snack('인쇄 실패: $e');
    }
  }

  /// (요구) 출력 시 포함여부 — `rows` 를 주면 그 행만 출력한다.
  Future<void> _outputFinance(String kind, {List<Map<String, dynamic>>? rows}) {
    final list = rows ?? _rowsOf(kind);
    final picked = rows != null && list.length != _rowsOf(kind).length;
    // (요구) "후원항목만 출력시 후원물품 혹은 금액에 대한 선택할 수 있도록"
    //  → 후원 탭은 후원자별/내역별 · 물품중심/금액중심을 먼저 고르게 한다.
    if (kind == 'donation') {
      return _outputDonation(list, view: null, focus: null);
    }
    return _runOutputDoc(
      () => _financeDoc(kind, rows: list),
      title: '${widget.title} · ${_financeTitle(kind)}',
      subtitle:
          '${list.length}건'
          '${picked ? ' (선택 출력)' : ''} · 옵션·미리보기·인쇄',
    );
  }

  /// 후원 전용 출력 — 보기 방식/초점을 고르고 문서를 만든다.
  Future<void> _outputDonation(
    List<Map<String, dynamic>> list, {
    DonationViewMode? view,
    DonationFocus? focus,
  }) async {
    var v = view ?? _donView;
    var f = focus ?? _donFocus;
    var fields = <DonationField>{..._donFields};
    if (view == null) {
      final picked = await _askDonationShape(
        initialView: v,
        initialFocus: f,
        initialFields: fields,
      );
      if (picked == null) return;
      v = picked.$1;
      f = picked.$2;
      fields = picked.$3;
      _donView = v;
      _donFocus = f;
      _donFields = fields;
    }
    final opts = DonationDocOptions(view: v, focus: f, fields: {...fields});
    await _runOutputDoc(
      () => _donationDoc(rows: list, options: opts),
      title: '${widget.title} · 후원 ${v.label}',
      subtitle: '${list.length}건 · ${opts.badge} · 옵션·미리보기·인쇄',
    );
  }

  /// 후원 출력 설정 시트 — 보기(후원자별/내역별) + 초점 + **노출 항목**.
  ///
  /// (요구) "후원내역 출력시 메모내용을 추가해서 출력해줘 / 항목 및 세부항목,
  ///  메모, 내용등을 노출할지 선택할 수 있도록"
  /// → 9개 항목(후원자·인가번호·후원항목·세부항목·금액·금액상당·날짜·메모·자료)을
  ///   체크박스로 켜고 끈다. 물품중심/금액중심을 고르면 모순되는 항목은 자동 해제.
  Future<(DonationViewMode, DonationFocus, Set<DonationField>)?>
  _askDonationShape({
    required DonationViewMode initialView,
    required DonationFocus initialFocus,
    required Set<DonationField> initialFields,
  }) async {
    var v = initialView;
    var f = initialFocus;
    var fields = <DonationField>{...initialFields};

    // 보기/초점이 바뀌면 기본값으로 다시 맞춘다(빈 표 방지).
    void retune() {
      final o = DonationDocOptions(view: v, focus: f, fields: {...fields});
      o.applyFocus();
      fields = o.fields;
    }

    final ok = await showTsakFormSheet(
      context: context,
      title: '후원 출력 설정',
      subtitle: '정리 방식 · 출력 초점 · 노출할 항목을 고르세요',
      icon: Icons.card_giftcard,
      saveLabel: '출력',
      heightFactor: 0.9,
      builder: (ctx, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 정리 방식 ──
          const _SheetLabel('정리 방식'),
          for (final e in DonationViewMode.values)
            RadioListTile<DonationViewMode>(
              value: e,
              groupValue: v,
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.tigerGold,
              title: Text(
                e.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(e.hint, style: const TextStyle(fontSize: 10.5)),
              onChanged: (x) {
                if (x == null) return;
                setSheetState(() {
                  v = x;
                  retune();
                });
              },
            ),
          const SizedBox(height: 4),
          // ── 출력 초점 ──
          const _SheetLabel('출력 초점'),
          for (final e in DonationFocus.values)
            RadioListTile<DonationFocus>(
              value: e,
              groupValue: f,
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.tigerGold,
              title: Text(
                e.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(e.hint, style: const TextStyle(fontSize: 10.5)),
              onChanged: (x) {
                if (x == null) return;
                setSheetState(() {
                  f = x;
                  retune();
                });
              },
            ),
          const SizedBox(height: 8),
          // ── 노출 항목 ──
          Row(
            children: [
              const Expanded(child: _SheetLabel('노출할 항목')),
              Text(
                '${fields.length}개 선택',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final x in DonationField.values)
                _FieldChip(
                  label: x.label,
                  hint: x.hint,
                  on: fields.contains(x),
                  // 초점과 모순되는 항목은 잠금(왜 꺼지는지 알 수 있게).
                  locked:
                      (f == DonationFocus.item &&
                          (x == DonationField.amount ||
                              x == DonationField.value)) ||
                      (f == DonationFocus.money && x == DonationField.detail),
                  onTap: () => setSheetState(() {
                    if (fields.contains(x)) {
                      // 최소 1개는 남긴다(빈 표 방지).
                      if (fields.length > 1) fields.remove(x);
                    } else {
                      fields.add(x);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.tigerGold.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '※ 후원금(현금)은 수입으로, 현물후원은 참고 금액으로 따로 표기됩니다.\n'
              '※ 물품중심을 고르면 금액 항목이, 금액중심을 고르면 세부항목이 자동으로 빠집니다.',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textGray,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return (v, f, fields);
  }

  /// 후원 표 문서 — [buildDonationDocData] 가 만든 열/행/요약을 그대로 옮긴다.
  TsakTableDoc _donationDoc({
    required List<Map<String, dynamic>> rows,
    required DonationDocOptions options,
  }) {
    final data = buildDonationDocData(rows: rows, options: options, won: _won);
    final view = options.view;
    return TsakTableDoc(
      title: '${widget.year} ${widget.title}',
      subtitle: '후원 ${view.label} · ${data.subtitle}',
      description: view == DonationViewMode.bySponsor
          ? '후원자 한 명을 한 줄로 묶어 후원내역·금액을 정리합니다. '
                '후원금(현금)은 수입으로, 현물후원은 수입에 넣지 않고 참고로 표기합니다.'
          : '후원 분류별로 묶어 후원자와 내역을 정리합니다. '
                '후원금(현금)은 수입으로, 현물후원은 수입에 넣지 않고 참고로 표기합니다.',
      columns: data.columns,
      rows: data.rows,
      summary: data.summary,
      footerLeft: '한국범스카우트중앙회 · 행사 후원목록',
      landscape: true,
      options: TableOutputOptions(
        noWrap: const {'연번', '후원분류', '건수', '인가번호', '금액', '금액 상당'},
      ),
    );
  }

  /// 후원자 이름 → 회원 상세로 이동.
  ///
  /// ## [요구 2026-10-30] "서로간의 링크도 잘 연계되어서 클릭하면 서로
  ///  스위칭되는 링크가 잘 작동되어야 모든 회원들의 후원을 이끌어 낼 수 있어"
  ///
  /// ## ⚠️ 소속(corps)을 반드시 본다
  /// 후원 행의 인가번호는 `G75`(은하) 일 수도 `75`(범) 일 수도 있다. 숫자만
  /// 비교하면 **은하 G75 를 눌렀는데 범 75호(다른 사람)가 열린다.**
  /// (이번 세션에서 고친 것과 같은 종류의 버그 — 여기서도 막는다.)
  ///   ① 번호 문자열에 `G`/`은하` 가 있으면 은하 명단에서 먼저 찾는다.
  ///   ② 없으면 범 명단에서 찾는다.
  ///   ③ 번호로 못 찾으면 이름으로 찾되, **동명이인이면 열지 않고 알린다**.
  Future<void> _openMemberByDonor(String number, String name) async {
    final s = context.read<AppState>();
    final raw = number.trim();
    final low = raw.toLowerCase();
    final wantEunha = low.startsWith('g') ||
        raw.startsWith('은하') ||
        raw.startsWith('갤럭시');
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    Member? pick;
    // ① 번호 + 소속으로 정확히 찾기
    if (digits.isNotEmpty) {
      for (final m in s.members) {
        if (m.number.replaceAll(RegExp(r'[^0-9]'), '') != digits) continue;
        final isEunha = m.corps == 'eunha';
        if (isEunha == wantEunha) {
          pick = m;
          break;
        }
      }
    }
    // ② 번호가 없거나 못 찾으면 이름으로
    if (pick == null && name.trim().isNotEmpty) {
      final hits = s.members
          .where((m) => m.name.trim() == name.trim())
          .toList();
      if (hits.length == 1) {
        pick = hits.first;
      } else if (hits.length > 1) {
        // 동명이인 — 잘못 열면 남의 후원내역을 보여주게 된다. 열지 않는다.
        _snack('동명이인 ${hits.length}명입니다. 이름으로는 열 수 없습니다'
            ' (인가번호를 확인하세요)');
        return;
      }
    }
    if (pick == null) {
      _snack(name.trim().isEmpty
          ? '회원을 찾을 수 없습니다'
          : '${name.trim()} 님의 회원 등록정보가 없습니다');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberDetailScreen(memberId: pick!.id)),
    );
    if (mounted) _load();
  }

  /// (요구) 후원 목록 출력 — 패널에서 고른 '보기(후원자별/내역별)'와
  ///  '출력초점(물품중심/금액중심/둘 다)'을 그대로 문서에 반영한다.
  void _outputDonationList({
    required List<Map<String, dynamic>> rows,
    required DonationViewMode view,
    required DonationFocus focus,
  }) {
    if (rows.isEmpty) {
      _snack('후원 내역이 없습니다');
      return;
    }
    final opts = DonationDocOptions(view: view, focus: focus)..applyFocus();
    _runOutputDoc(
      () => _donationDoc(rows: rows, options: opts),
      title: '${widget.title} · 후원목록',
      subtitle: '${rows.length}건 · ${view.label} · ${focus.label}',
    );
  }

  void _outputAttendees() {
    if (_attendees.isEmpty) {
      _snack('참가자가 없습니다');
      return;
    }
    _runOutputDoc(
      _attendeeDoc,
      title: '${widget.title} · 참가자 명단',
      subtitle: '${_attendees.length}명 · 옵션·미리보기·인쇄',
      extra: TsakExtraPick(source: _attendees),
    );
  }

  /// **추가항목별 인원 확인** 출력 — 별도 출력 옵션.
  ///
  /// (요구 2026-10-31) "그리고 추가항목별로 인원 확인 할 수 있는 출력 옵션도 추가해줘"
  ///  · 이동·숙박·도착 → 선택지별 인원수
  ///  · 출발장소·소요시간·동행자·주소 → 값별 인원 + 명단
  ///  · 운영진 전달사항 → 작성 인원 + 내용
  void _outputExtraHeadcount() {
    if (_attendees.isEmpty) {
      _snack('참가자가 없습니다');
      return;
    }
    _runOutputDoc(
      () => extraHeadcountDoc(
        title: widget.title,
        year: widget.year,
        attendees: _attendees,
      ),
      title: '${widget.title} · 추가입력 인원 현황',
      subtitle: '${_attendees.length}명 · 항목별 인원·명단',
    );
  }

  void _outputSettlement(
    SettlementLayout layout,
    Map<SettlementBlock, SettlementBlockData> data,
  ) {
    // 결산 탭에서 고른 배치를 기억(탭 재진입 시 유지).
    _settleLayout = layout.copy();
    _runOutputDoc(
      () => _settlementDoc(layout, data),
      title: '${widget.title} · 행사 결산서',
      subtitle:
          '${layout.includedCount}개 항목 · 참가자 ${_attendees.length}명 · '
          '수입 ${_fees.length}건 · 지출 ${_expenses.length}건',
    );
  }

  // ============================ 관리 (마스터 전용) ============================
  /// (요구) "마스터창에서는 관리자의 세부권한을 체계적으로 관리할 수 있도록"
  ///   행사 단위에서 바로 관리자 세부권한 화면으로 들어갈 수 있게 한다.
  Widget _masterManageTab() {
    final s = context.read<AppState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.purple.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings,
                    size: 18,
                    color: AppColors.purple,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '마스터 전용 · 관리자 세부권한',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '역할별로 이 행사에서 무엇을 할 수 있는지(참가자 편집·재무 입력·'
                '결산 출력·사진 관리)를 켜고 끕니다. 값은 서버에 저장되어 모든 '
                '기기에 즉시 반영됩니다.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textGray,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RolePermissionsScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.tune, size: 17),
                      label: const Text(
                        '역할별 메뉴 권한 관리',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // 행사 스텝(STAFF) 관리 — 지정자는 이 행사의 모든 게시판이 열린다.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.taegeukBlue.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.engineering,
                    size: 18,
                    color: AppColors.taegeukBlue,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '행사 스텝 ${_staff.length}명',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.taegeukBlue,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _manageStaff,
                    icon: const Icon(Icons.person_add_alt, size: 16),
                    label: const Text('스텝 등록'),
                  ),
                ],
              ),
              const Text(
                '스텝은 이 행사의 참가자 명단·사진·후기·재무를 모두 열람합니다.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
              ),
              if (_staff.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final st in _staff)
                      Chip(
                        label: Text(
                          '${st['name'] ?? ''}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        onDeleted: () async {
                          await _nas.eventStaffRemove(
                            year: widget.year,
                            title: widget.title,
                            number: '${st['number'] ?? ''}',
                          );
                          await _load();
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        // 현재 세션 요약 — 마스터가 누구로 접속했는지 확인.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.tigerGold.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.verified_user,
                    size: 18,
                    color: AppColors.lifetimeGold,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '현재 세션',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.lifetimeGold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${s.isMaster ? '마스터' : (s.isApp ? '관리자' : '개인')}'
                '${s.who.isNotEmpty ? ' · ${s.who}' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.textDark),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================ 부가 기능 ============================
  Future<void> _requestPhoto() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('사진 업로드 요청'),
        content: const Text(
          '모든 참가자에게 이 행사의 사진 업로드를 요청합니다.\n'
          '(명단 연락처로 문자/메일 발송 시 안내 문구가 포함됩니다)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('요청'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final s = context.read<AppState>();
    await _nas.eventRequestPhoto(
      widget.year,
      widget.title,
      by: s.who,
      message: '${widget.title} 사진을 올려주세요',
    );
    _snack('참가자에게 사진 업로드 요청을 등록했습니다');
  }

  /// 추가입력사항 **항목별 취합** 시트 열기.
  ///
  /// [요구 2026-10-30] "항목별로 취합도 가능해야 해"
  ///  · 참석자 전원의 이동·숙박·도착·경로·동행·전달사항을 모아 보여준다.
  ///  · 회원 명부를 함께 넘겨 이름 보정에 쓴다(참석자 행의 이름이 비어도
  ///    인가번호로 찾아 표시).
  Future<void> _openExtraSummary() async {
    await showExtraFieldsSummary(
      context,
      eventTitle: widget.title,
      attendees: _attendees,
      members: context
          .read<AppState>()
          .allMembers
          .map((m) => <String, dynamic>{
            'number': m.number,
            'name': m.name,
            'phone': m.phone,
          })
          .toList(),
    );
  }

  Future<void> _openRoster() async {
    // 외부 브라우저 대신 앱 내부 화면으로 열어 뒤로가기·출력·공유가 정상 동작
    final e = _event;
    final s = context.read<AppState>();

    // 참가비 납부자 이름/인가번호 집합 (선택 항목: 참가비 납부 여부)
    final feeKeys = <String>{};
    for (final r in _fees) {
      final k1 = '${r['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
      final k2 = '${r['name'] ?? ''}'.trim();
      if (k1.isNotEmpty) feeKeys.add(k1);
      if (k2.isNotEmpty) feeKeys.add(k2);
    }

    final attendees = [
      for (final a in _attendees)
        {...a, 'visited': _isVisited(a), ..._rosterExtraFlags(a, feeKeys, s)},
    ];
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RosterScreen(
          title: widget.title,
          year: widget.year,
          period: '${e['period'] ?? e['date'] ?? ''}',
          place: '${e['place'] ?? ''}',
          desc: '${e['desc'] ?? ''}',
          attendees: attendees,
        ),
      ),
    );
  }

  /// 행사 후기 게시판 화면으로 이동
  void _openReview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EventReviewScreen(year: widget.year, title: widget.title),
      ),
    );
  }

  // ======================== 메뉴추가(사용자 정의 탭) ========================
  /// 커스텀 탭 하나의 뷰 — 제목 + 관리자 편집 가능한 메모(내용).
  Widget _customTabView(Map<String, dynamic> t) {
    // [요구 2026-10-26] '메뉴 추가'는 이제 **게시판형**이 기본이다.
    //  글쓰기 + 첨부 업로드 + 다운로드 + 상단 열람권한 토글이 모두 동작한다.
    //  kind='note' 인 기존 메뉴는 종전 메모장 UI 를 그대로 쓴다(하위 호환).
    final kind = '${t['kind'] ?? 'board'}';
    if (kind != 'note') {
      return EventCustomBoard(
        year: widget.year,
        title: widget.title,
        boardName: '${t['name'] ?? '게시판'}',
        note: '${t['note'] ?? ''}',
      );
    }
    final note = '${t['note'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        Row(
          children: [
            const Icon(Icons.tab, size: 18, color: AppColors.purple),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${t['name'] ?? '메뉴'}',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _editCustomTab(t),
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('편집', style: TextStyle(fontSize: 12.5)),
            ),
            TextButton.icon(
              onPressed: () => _removeCustomTab(t),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('삭제', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE6E1D6)),
          ),
          child: Text(
            note.trim().isEmpty ? '내용을 입력하려면 우측 상단 "편집"을 눌러주세요.' : note,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: note.trim().isEmpty
                  ? AppColors.textGray
                  : AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }

  /// 커스텀 탭 추가(메뉴추가).
  Future<void> _addCustomTab() async {
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 바텀시트로 전환.
    final ok = await showTsakFormSheet(
      context: context,
      title: '메뉴 추가',
      subtitle: '행사 전용 메뉴를 하나 만듭니다',
      icon: Icons.add_box_outlined,
      saveLabel: '추가',
      builder: (ctx, setSheetState) => SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: '메뉴 이름 (예: 준비물 체크)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '내용/메모 (선택)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final next = <Map<String, dynamic>>[
      ..._customTabs.map(
        (e) => {'name': '${e['name'] ?? ''}', 'note': '${e['note'] ?? ''}'},
      ),
      {'name': name, 'note': noteCtrl.text.trim()},
    ];
    await _saveCustomTabs(next);
  }

  /// 커스텀 탭 편집(이름/내용).
  Future<void> _editCustomTab(Map<String, dynamic> t) async {
    final nameCtrl = TextEditingController(text: '${t['name'] ?? ''}');
    final noteCtrl = TextEditingController(text: '${t['note'] ?? ''}');
    final ok = await showTsakFormSheet(
      context: context,
      title: '메뉴 편집',
      subtitle: '이름과 내용을 고칩니다',
      icon: Icons.edit_note,
      saveLabel: '저장',
      builder: (ctx, setSheetState) => SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(hintText: '메뉴 이름'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '내용/메모',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final next = _customTabs.map((e) {
      final same =
          identical(e, t) ||
          ('${e['name'] ?? ''}' == '${t['name'] ?? ''}' &&
              '${e['note'] ?? ''}' == '${t['note'] ?? ''}');
      return same
          ? {'name': name, 'note': noteCtrl.text.trim()}
          : {'name': '${e['name'] ?? ''}', 'note': '${e['note'] ?? ''}'};
    }).toList();
    await _saveCustomTabs(next);
  }

  // ==================== 메뉴 관리 (추가·변경·삭제) ====================
  /// [요구 2026-10-26] "메뉴추가 기능은 있는데, 메뉴 삭제 및 관리 기능이
  ///  없음 / 관리자·마스터는 생성·삭제·변경 등의 관리 기능을 할 수 있음"
  ///
  ///  요구(2차): "관리자/마스터 권한으로 구분해서 정리해줘"
  ///   → 이 창에서 **현재 내 권한**을 제목에 명시하고, 동작마다 허용 범위를
  ///     서버(_auth_ok / _require)와 똑같이 맞춘다.
  ///
  ///  ## 권한 경계 (2026-10-26 확정)
  ///   1차 요구: "관리자 / 마스터는 생성, 삭제, 변경 등의 관리 기능을 할 수 있음"
  ///   2차 요구: "관리자/마스터 권한으로 구분해서 정리해줘"
  ///   → **관리자도 삭제할 수 있다.** 다만 '게시판 통째로 삭제'(글·첨부목록이
  ///     전부 소멸)만 마스터에 남긴다. 탭에서 빼는 것(항목 삭제)은 관리자도
  ///     가능하다 — 그래야 "삭제 기능이 없다"는 1차 지적이 다시 나오지 않는다.
  ///
  ///   · 메뉴 추가 / 이름·내용 변경 / 순서 이동      → 관리자·마스터
  ///   · 항목 삭제(탭에서 빼기, 게시판 데이터는 보존) → 관리자·마스터
  ///   · 게시판 통째로 삭제(글·첨부목록까지 소멸)     → 마스터 전용
  ///   · 노출권한 변경(all/staff/admin)              → 관리자·마스터
  Future<void> _manageCustomTabs() async {
    // 최신 목록을 서버에서 다시 받아온다(다른 기기에서 바꿨을 수 있다).
    await _load();
    if (!mounted) return;

    // 게시판별 노출권한을 함께 보여준다(실패해도 관리 창은 열린다).
    Map<String, String> visOf = {};
    // 이름 → 게시판 id (노출권한 변경에 필요)
    Map<String, String> idOf = {};
    try {
      final ls = await _nas.customBoards(widget.year, widget.title);
      for (final b in ((ls['boards'] as List?) ?? [])) {
        final m = (b as Map).cast<String, dynamic>();
        final nm = '${m['name'] ?? ''}';
        visOf[nm] = '${m['visibility'] ?? ''}';
        final bid = '${m['id'] ?? ''}';
        if (bid.isNotEmpty) idOf[nm] = bid;
      }
    } catch (_) {}
    if (!mounted) return;

    String visLabel(String v) => switch (v) {
          'all' => '전체 노출',
          'staff' => '스탭 이상',
          'admin' => '관리자·마스터',
          _ => '—',
        };

    // ── 권한 구분 (요구: "관리자/마스터 권한으로 구분해서 정리해줘") ──
    //  [요구 2026-10-26] "B + A 조합"
    //   A: 스탭도 관리 가능(_canManageMenu)
    //   B: 권한이 없으면 동작을 **회색으로 노출**(기능 위치를 알 수 있게)
    final isAdmin = _canManageMenu;
    final isMaster = _isMasterView;

    var changed = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            final tabs = _customTabs;
            return AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.dashboard_customize_outlined,
                          size: 20, color: AppColors.purple),
                      SizedBox(width: 8),
                      Text('메뉴 관리', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 현재 권한을 명시 — "관리자/마스터 권한으로 구분"
                  Text(
                    isMaster
                        ? '마스터 권한 · 추가 / 변경 / 삭제 / 게시판 통째로 삭제'
                        : (isAdmin
                            ? (_isStaff && !widget.canManage
                                ? '스탭 권한 · 추가 / 변경 / 삭제 가능 '
                                    '(게시판 통째로 삭제는 마스터만)'
                                : '관리자 권한 · 추가 / 변경 / 삭제 가능 '
                                    '(게시판 통째로 삭제는 마스터만)')
                            : '권한 없음 · 항목은 보이지만 실행할 수 없습니다'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isMaster
                          ? AppColors.tigerGold
                          : (isAdmin ? AppColors.purple : AppColors.textGray),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: tabs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          '추가된 메뉴가 없습니다.\n아래 [메뉴 추가]로 첫 게시판을 만드세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textGray),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < tabs.length; i++)
                            Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 6),
                              color: const Color(0xFFFBF9F4),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(10, 6, 4, 6),
                                child: Row(
                                  children: [
                                    const Icon(Icons.forum_outlined,
                                        size: 16, color: AppColors.purple),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${tabs[i]['name'] ?? ''}',
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text(
                                            '노출: '
                                            '${visLabel(visOf['${tabs[i]['name'] ?? ''}'] ?? '')}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textGray,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // ── 노출권한 변경 (관리자·마스터·스탭) ──
                                    //  [요구 2026-10-26] "B + A" — 권한이 없어도
                                    //  버튼은 보이게 하고(회색), 눌리지 않게 한다.
                                    PopupMenuButton<String>(
                                      tooltip: isAdmin
                                          ? '노출권한 변경'
                                          : '노출권한 변경 (권한 없음)',
                                      enabled: isAdmin &&
                                          !(idOf['${tabs[i]['name'] ?? ''}']
                                                  ?.isEmpty ??
                                              true),
                                        onSelected: (v) async {
                                          final nm =
                                              '${tabs[i]['name'] ?? ''}';
                                          final bid = idOf[nm] ?? '';
                                          if (bid.isEmpty) {
                                            _snack('게시판을 찾지 못했습니다 '
                                                '(아직 개설 전일 수 있습니다)');
                                            return;
                                          }
                                          try {
                                            final r = await _nas
                                                .customBoardVisibility(
                                              year: widget.year,
                                              title: widget.title,
                                              id: bid,
                                              visibility: v,
                                            );
                                            if (r['ok'] != true) {
                                              _snack('변경하지 못했습니다 '
                                                  '(${r['error'] ?? '권한'})');
                                              return;
                                            }
                                            visOf[nm] = v;
                                            _snack('노출권한 → ${visLabel(v)}');
                                            changed = true;
                                            if (ctx.mounted) setD(() {});
                                          } catch (e) {
                                            _snack('변경하지 못했습니다: $e');
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                              value: 'all',
                                              child: Text('전체 노출')),
                                          PopupMenuItem(
                                              value: 'staff',
                                              child: Text('스탭 이상')),
                                          PopupMenuItem(
                                              value: 'admin',
                                              child: Text('관리자·마스터')),
                                        ],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.visibility_outlined,
                                                  size: 15,
                                                  color: isAdmin
                                                      ? AppColors.purple
                                                      : AppColors.textGray),
                                              const SizedBox(width: 3),
                                              Text(
                                                '노출',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: isAdmin
                                                      ? AppColors.purple
                                                      : AppColors.textGray,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    // ── 한 줄에 아이콘 5개를 늘어놓으면
                                    //  모바일 좁은 화면에서 넘친다(overflow).
                                    //  권한별 동작을 **하나의 ⋮ 메뉴**로 묶어
                                    //  "관리자/마스터 권한으로 구분"을 한 눈에
                                    //  보이게 한다(요구 2026-10-26).
                                    PopupMenuButton<String>(
                                      tooltip: isAdmin
                                          ? '이 메뉴 관리'
                                          : '이 메뉴 관리 (권한 없음)',
                                      onSelected: (v) async {
                                        final nm = '${tabs[i]['name'] ?? ''}';
                                        switch (v) {
                                          case 'up':
                                          case 'down':
                                            final next = [
                                              ...tabs.map((e) => {
                                                    'name': '${e['name'] ?? ''}',
                                                    'note': '${e['note'] ?? ''}',
                                                  })
                                            ];
                                            final t = next.removeAt(i);
                                            next.insert(
                                                v == 'up' ? i - 1 : i + 1, t);
                                            await _saveCustomTabs(next);
                                            changed = true;
                                            break;
                                          case 'rename':
                                            await _editCustomTab(tabs[i]);
                                            changed = true;
                                            break;
                                          case 'remove':
                                            await _removeCustomTab(tabs[i]);
                                            changed = true;
                                            break;
                                          case 'boarddelete':
                                            final ok = await _deleteBoard(nm);
                                            if (ok) changed = true;
                                            break;
                                        }
                                        if (ctx.mounted) setD(() {});
                                      },
                                      itemBuilder: (_) => [
                                        // [요구 2026-10-26] "B + A" — 항목은
                                        //  항상 보이고, 권한이 없으면 회색.
                                        PopupMenuItem(
                                          value: 'up',
                                          enabled: isAdmin && i > 0,
                                          child: const Text('위로 이동'),
                                        ),
                                        PopupMenuItem(
                                          value: 'down',
                                          enabled: isAdmin &&
                                              i < tabs.length - 1,
                                          child: const Text('아래로 이동'),
                                        ),
                                        PopupMenuItem(
                                          value: 'rename',
                                          enabled: isAdmin,
                                          child: const Text('이름·내용 변경'),
                                        ),
                                        const PopupMenuDivider(),
                                        PopupMenuItem(
                                          value: 'remove',
                                          enabled: isAdmin,
                                          child: const Text(
                                              '메뉴 삭제 (탭에서 빼기)'),
                                        ),
                                        // 게시판 통째로 삭제는 마스터만 —
                                        //  글·첨부목록이 전부 소멸한다.
                                        PopupMenuItem(
                                          value: 'boarddelete',
                                          enabled: isMaster,
                                          child: Row(
                                            children: [
                                              Icon(
                                                  Icons
                                                      .delete_forever_outlined,
                                                  size: 15,
                                                  color: isMaster
                                                      ? AppColors.taegeukRed
                                                      : AppColors.textGray),
                                              const SizedBox(width: 6),
                                              const Text('게시판 통째로 삭제'),
                                              if (!isMaster)
                                                const Padding(
                                                  padding:
                                                      EdgeInsets.only(left: 6),
                                                  child: Icon(
                                                      Icons.lock_outline,
                                                      size: 13,
                                                      color:
                                                          AppColors.textGray),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    await _addCustomTab();
                    changed = true;
                    if (ctx.mounted) setD(() {});
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('메뉴 추가'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    );
    if (changed && mounted) await _load();
  }

  /// 게시판 하나를 **통째로** 삭제한다(글·첨부목록 포함). 마스터 전용.
  ///  ⚠️ NAS 의 실제 첨부파일은 지우지 않는다 — 서버가 글 목록만 비운다.
  ///  돌려주는 값: 삭제했으면 true.
  Future<bool> _deleteBoard(String boardName) async {
    // 해당 게시판 id 찾기
    String bid = '';
    try {
      final ls = await _nas.customBoards(widget.year, widget.title);
      for (final b in ((ls['boards'] as List?) ?? [])) {
        final m = (b as Map).cast<String, dynamic>();
        if ('${m['name'] ?? ''}' == boardName) {
          bid = '${m['id'] ?? ''}';
          break;
        }
      }
    } catch (_) {}
    if (!mounted) return false;
    if (bid.isEmpty) {
      _snack('게시판을 찾지 못했습니다 (아직 개설 전일 수 있습니다)');
      return false;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게시판 삭제', style: TextStyle(fontSize: 16)),
        content: Text(
          '"$boardName" 게시판을 통째로 삭제할까요?\n\n'
          '· 게시글과 첨부 목록이 모두 사라집니다.\n'
          '· NAS 의 실제 첨부파일은 남습니다.\n'
          '· 이 작업은 되돌릴 수 없습니다.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
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
    if (yes != true || !mounted) return false;
    try {
      final r = await _nas.customBoardDeleteBoard(
        year: widget.year,
        title: widget.title,
        id: bid,
      );
      if (!mounted) return false;
      if (r['ok'] == true) {
        _snack('게시판을 삭제했습니다 (글 ${r['removedPosts'] ?? 0}건)');
        return true;
      }
      _snack('삭제하지 못했습니다 (${r['error'] ?? '권한 확인'})');
    } catch (e) {
      if (mounted) _snack('삭제하지 못했습니다: $e');
    }
    return false;
  }

  /// 메뉴(⋯) → '게시판 통째로 삭제' — 어느 게시판인지 고르게 한다.
  Future<void> _deleteCustomBoard() async {
    if (_customTabs.isEmpty) {
      _snack('삭제할 게시판이 없습니다');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게시판 통째로 삭제', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final t in _customTabs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.forum_outlined,
                      size: 18, color: AppColors.purple),
                  title: Text(
                    '${t['name'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  trailing: const Icon(Icons.delete_forever_outlined,
                      size: 18, color: AppColors.taegeukRed),
                  onTap: () => Navigator.pop(ctx, '${t['name'] ?? ''}'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final ok = await _deleteBoard(name);
    if (ok && mounted) await _load();
  }

  /// 커스텀 탭 삭제.
  Future<void> _removeCustomTab(Map<String, dynamic> t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('메뉴 삭제', style: TextStyle(fontSize: 16)),
        content: Text(
          '"${t['name'] ?? ''}" 메뉴를 목록에서 뺄까요?\n\n'
          '· 탭에서만 사라지고, 그 게시판의 글·첨부는 NAS 에 그대로 남습니다.\n'
          '· 같은 이름으로 다시 [메뉴 추가]하면 글이 그대로 되살아납니다.\n'
          '· 글까지 완전히 지우려면 [게시판 통째로 삭제](마스터)를 쓰세요.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final next = _customTabs
        .where(
          (e) =>
              !('${e['name'] ?? ''}' == '${t['name'] ?? ''}' &&
                  '${e['note'] ?? ''}' == '${t['note'] ?? ''}'),
        )
        .map(
          (e) => {'name': '${e['name'] ?? ''}', 'note': '${e['note'] ?? ''}'},
        )
        .toList();
    await _saveCustomTabs(next);
  }

  Future<void> _saveCustomTabs(List<Map<String, dynamic>> tabs) async {
    final r = await _nas.eventTabsSave(
      year: widget.year,
      title: widget.title,
      tabs: tabs,
    );
    if (!mounted) return;
    if (r) {
      _snack('메뉴를 저장했습니다');
      await _load();
    } else {
      _snack('메뉴 저장에 실패했습니다');
    }
  }

  bool _isVisited(Map<String, dynamic> a) {
    final ident = '${a['number'] ?? a['phone'] ?? ''}'.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return ident.isNotEmpty && _access.containsKey(ident);
  }

  /// 명단 선택항목용 플래그: 참가비 납부(eventFee) · 평생회원(lifetime) ·
  /// 행사년도 연회비 납부(yearFee).
  Map<String, dynamic> _rosterExtraFlags(
    Map<String, dynamic> a,
    Set<String> feeKeys,
    AppState s,
  ) {
    final num = '${a['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final name = '${a['name'] ?? ''}'.trim();
    final eventFee =
        (num.isNotEmpty && feeKeys.contains(num)) ||
        (name.isNotEmpty && feeKeys.contains(name));

    // 회원 원본 조회 → 평생회원 여부 + 해당 행사년도 연회비 납부 여부
    //  ⚠️ [2026-10-29] 이름 단독 조회 제거 — 동명이인의 연회비를 잘못 읽으면
    //     "납부했는데 미납으로" 또는 그 반대로 결산이 틀어진다.
    //     번호가 없으면 이름은 **후보가 1명일 때만** 인정한다.
    Member? m;
    final idn = s.resolveIdentity(
      number: num,
      phone: '${a['phone'] ?? a['loginId'] ?? ''}',
      name: name,
      corps: '${a['corps'] ?? ''}'.trim(),
    );
    if (idn.isResolved) m = idn.member;

    final lifetime = a['lifetime'] == true || (m?.lifetimeMember ?? false);
    var yearFee = a['yearFee'] == true;
    if (!yearFee && m != null && widget.year.isNotEmpty) {
      final y = widget.year.replaceAll(RegExp(r'[^0-9]'), '');
      yearFee =
          m.feeYears[y] == true ||
          m.feeYears['$y년'] == true ||
          m.paidYears.any((p) => p.replaceAll(RegExp(r'[^0-9]'), '') == y);
    }
    return {'eventFee': eventFee, 'lifetime': lifetime, 'yearFee': yearFee};
  }

  Future<void> _sendSms() async {
    final nums = _participantPhones();
    if (nums.isEmpty) {
      _snack('연락처가 있는 참가자가 없습니다');
      return;
    }
    final body = Uri.encodeComponent('[한국범스카우트] ${widget.title} 관련 안내드립니다.');
    final uri = Uri.parse('sms:${nums.join(',')}?body=$body');
    try {
      await launchUrl(uri);
    } catch (_) {
      _snack('문자 앱을 열 수 없습니다 (${nums.length}명)');
    }
  }

  Future<void> _sendMail() async {
    final mails = _participantEmails();
    if (mails.isEmpty) {
      _snack('메일주소가 있는 참가자가 없습니다');
      return;
    }
    final subject = Uri.encodeComponent('[한국범스카우트] ${widget.title} 안내');
    final uri = Uri.parse('mailto:${mails.join(',')}?subject=$subject');
    try {
      await launchUrl(uri);
    } catch (_) {
      _snack('메일 앱을 열 수 없습니다 (${mails.length}명)');
    }
  }

  List<String> _participantPhones() => [
    for (final a in _attendees)
      if ('${a['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '').isNotEmpty)
        '${a['phone']}'.replaceAll(RegExp(r'[^0-9]'), ''),
  ];

  List<String> _participantEmails() => [
    for (final a in _attendees)
      if ('${a['email'] ?? ''}'.contains('@')) '${a['email']}',
  ];

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  String _won(int v) {
    final s = v.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}${buf.toString()}원';
  }
}

/// 사진/동영상 뷰어 — 최적 크기 보기 + 원본보기/다운로드, 업로더만 삭제
class _MediaViewer extends StatefulWidget {
  const _MediaViewer({
    required this.year,
    required this.title,
    required this.items,
    required this.initialIndex,
    required this.canDeleteAll,
    required this.myName,
    this.sub = '',
  });

  final String year;
  final String title;
  final String sub;
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  final bool canDeleteAll;
  final String myName;

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late final PageController _pc;
  late int _index;
  bool _original = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pc = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  NasApi get _nas => context.read<NasApi>();

  Map<String, dynamic> get _cur => widget.items[_index];

  /// [중요] 뷰어가 지금 보고 있는 사진의 **하위폴더**.
  ///  하위폴더까지 펼친(평탄화) 목록에서는 사진마다 폴더가 다르므로
  ///  항목의 `sub` 를 우선 쓰고, 없으면 진입한 폴더를 쓴다.
  ///  (이것을 쓰지 않으면 썸네일·원본·다운로드가 404 로 깨진다)
  String get _curSub {
    final s = '${_cur['sub'] ?? ''}';
    return s.isNotEmpty ? s : widget.sub;
  }

  bool get _canDelete {
    if (widget.canDeleteAll) return true;
    return '${_cur['uploader'] ?? ''}' == widget.myName;
  }

  /// 사진/동영상 원본을 **저장 위치를 골라** 저장한다(요구).
  ///
  /// · [askSaveLocation] 로 위치 선택창을 먼저 띄우고,
  /// · 파일 바이트를 직접 받아 [saveFileNamed] 로 저장한다.
  /// · 바이트 수신·저장이 실패하면 기존 방식(외부 앱으로 열기)으로 폴백한다.
  Future<void> _saveMediaToChoosen(String url, String name, String kind) async {
    final ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : (kind == 'video' ? 'mp4' : 'jpg');
    final mime = kind == 'video'
        ? 'video/$ext'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');
    final opt = await askSaveOption(context, info: name);
    if (opt == null) return; // 사용자 취소
    try {
      final (bytes, ct) = await _nas.fetchBytes(url);
      if (!mounted) return;
      final ok = await saveFileOption(
        bytes: bytes,
        filename: name,
        mime: ct.startsWith('image/') || ct.startsWith('video/') ? ct : mime,
        option: opt,
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name 저장을 시작했습니다')));
      }
    } catch (e) {
      // 폴백: 프록시가 외부 다운로드를 처리하도록 기존 방식으로 연다.
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('다운로드 실패: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${_cur['name']}';
    final kind = '${_cur['kind'] ?? 'image'}';
    final uploader = '${_cur['uploader'] ?? ''}';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: TsakAppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.items.length}',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          if (kind == 'image')
            TextButton(
              onPressed: () => setState(() => _original = !_original),
              child: Text(
                _original ? '최적화 보기' : '원본 보기',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          IconButton(
            tooltip: '다운로드',
            icon: const Icon(Icons.download),
            onPressed: () async {
              // 이미지·동영상 원본 화질로 다운로드 (크롭/축소 없음).
              final url = _nas.eventFile2Url(
                widget.year,
                widget.title,
                'media',
                name,
                download: true,
                sub: _curSub,
              );
              // 요구: "사진 저장위치 선택창이 안나오니 이것도 조정해줘요".
              //  · 위치 선택창을 띄운 뒤, 바이트를 직접 받아 지정 위치/기본 폴더에 저장.
              //  · 실패하면 기존 방식(외부 앱 다운로드)으로 폴백.
              await _saveMediaToChoosen(url, name, kind);
            },
          ),
          if (_canDelete)
            IconButton(
              tooltip: '삭제',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _original = false;
              }),
              itemBuilder: (_, i) {
                final m = widget.items[i];
                final n = '${m['name']}';
                final k = '${m['kind'] ?? 'image'}';
                if (k == 'video') {
                  return _VideoBox(
                    url: _nas.eventFile2Url(
                      widget.year,
                      widget.title,
                      'media',
                      n,
                      sub: _curSub,
                    ),
                  );
                }
                final isOrig = i == _index && _original;
                // 최적화 보기: 지연 생성 1600px 캐시본 (빠름).
                // 원본 보기: 실제 원본 파일 (크롭 없이 전체가 보이고 확대 가능).
                final url = _nas.eventThumb2Url(
                  widget.year,
                  widget.title,
                  n,
                  size: isOrig ? 'orig' : 'view',
                  sub: _curSub,
                );
                // 최적화·원본 모두 확대(핀치/더블탭) 가능.
                // 원본은 화면을 가득 채우되 잘리지 않게(contain) 전체가 보인다.
                return SizedBox.expand(
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: isOrig ? 12 : 6,
                    panEnabled: true,
                    scaleEnabled: true,
                    clipBehavior: Clip.none,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      loadingBuilder: (_, child, prog) => prog == null
                          ? child
                          : const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 60,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '$name  ·  ${_fmtSizeV((_cur['size'] as num?)?.toInt() ?? 0)}업로드: ${uploader.trim().isEmpty ? '415호' : uploader.trim()}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 표시용 용량 문자열(0이면 빈 문자열).
  String _fmtSizeV(int b) {
    if (b <= 0) return '';
    if (b < 1024) return '$b B  ·  ';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB  ·  ';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024).toStringAsFixed(1)} MB  ·  ';
    }
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB  ·  ';
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제'),
        content: const Text('이 사진을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _nas.eventFileDelete(
      widget.year,
      widget.title,
      'media',
      '${_cur['name']}',
      sub: _curSub,
    );
    if (mounted) Navigator.pop(context);
  }
}

class _VideoBox extends StatefulWidget {
  const _VideoBox({required this.url});
  final String url;
  @override
  State<_VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<_VideoBox> {
  VideoPlayerController? _c;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _c = c);
      c.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio == 0
                ? 16 / 9
                : c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          VideoProgressIndicator(c, allowScrubbing: true),
          IconButton(
            icon: Icon(
              c.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () =>
                setState(() => c.value.isPlaying ? c.pause() : c.play()),
          ),
        ],
      ),
    );
  }
}

/// 출력 설정 시트의 작은 섹션 제목.
class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 2),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
    ),
  );
}

/// 노출 항목 하나를 켜고 끄는 칩 — 잠긴 항목은 왜 못 켜는지 툴팁으로 알린다.
class _FieldChip extends StatelessWidget {
  const _FieldChip({
    required this.label,
    required this.hint,
    required this.on,
    required this.onTap,
    this.locked = false,
  });

  final String label;
  final String hint;
  final bool on;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = locked
        ? AppColors.textGray.withValues(alpha: 0.55)
        : (on ? AppColors.purple : AppColors.textGray);
    return Tooltip(
      message: locked ? '$hint — 출력 초점과 맞지 않아 빠집니다' : hint,
      child: InkWell(
        onTap: locked ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: on
                ? AppColors.purple.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on
                  ? AppColors.purple.withValues(alpha: 0.55)
                  : const Color(0xFFD8D3CA),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                locked
                    ? Icons.lock_outline
                    : (on ? Icons.check_box : Icons.check_box_outline_blank),
                size: 13,
                color: c,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  color: on ? AppColors.purple : AppColors.textGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
