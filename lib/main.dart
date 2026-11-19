import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// [turn72] 웹에서 브라우저 기본 메뉴를 끄고 Flutter 자체 툴바를 쓰기 위해 필요.
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'services/app_config.dart';
import 'services/app_state.dart';
import 'services/finance_service.dart';
import 'services/member_repository.dart';
import 'services/nas_api.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── [turn72] 웹: 브라우저 기본 메뉴를 끄고 Flutter 툴바를 켠다 ──────────
  //
  //  ## 사용자 보고 (실측)
  //   "copy, cut 등등의 기본 메뉴 자체가 안 뜸"   ← 아이폰(iPhone Safari/PWA)
  //
  //  ## Flutter 소스로 확인한 실제 동작 (추측 아님)
  //   `editable_text.dart` 의 `showToolbar()`:
  //     // Web is using native dom elements to enable clipboard functionality
  //     // of the context menu: copy, paste, select, cut. ... we should not
  //     // show a Flutter toolbar for the editable text elements unless the
  //     // browser's context menu is explicitly disabled.
  //     if (_webContextMenuEnabled) { return false; }
  //
  //   즉 **웹에서는 Flutter 가 자체 복사/붙여넣기 툴바를 일부러 만들지 않고
  //   브라우저 기본 메뉴에 위임한다.** 그런데 Flutter 웹(CanvasKit)은 실제
  //   입력을 **화면 밖에 숨긴 <input>** 으로 처리한다. iOS Safari(특히
  //   홈화면 앱/PWA 전체화면)는 그 숨은 input 에 선택 메뉴를 붙여주지 않는다.
  //   → 위임할 곳도 없고 Flutter 툴바도 없으니 **아무 메뉴도 안 뜬다.**
  //
  //  ## 해결
  //   브라우저 기본 메뉴를 끄면 `_webContextMenuEnabled` 가 false 가 되어
  //   `return false` 분기를 타지 않고, Flutter 가 직접 툴바(잘라내기/복사/
  //   붙여넣기/모두 선택)를 그린다. iOS 에서는 Cupertino 스타일로 뜬다.
  //   앱 전체에 적용되므로 후원 입력 폼뿐 아니라 모든 입력란에 동시에 듣는다.
  //
  //  ## 부작용 (솔직히)
  //   · 브라우저 자체 메뉴(페이지 전체 선택, '웹 검색', '번역' 등)는 사라진다.
  //     이 앱은 업무용 내부 도구라 그 기능을 쓰지 않으므로 손해가 없다.
  //   · 데스크톱 PC 웹의 우클릭 메뉴도 Flutter 메뉴로 바뀐다(동일 항목 제공).
  //   · 웹이 아닌 플랫폼(안드로이드 APK)에서는 이 호출이 no-op 이다.
  //
  //  ## 안전장치
  //   이 호출이 실패해도 앱은 반드시 떠야 한다. main() 에서 던진 예외는
  //   runApp 전에 터져 **흰 화면**이 되므로 try/catch 로 감싼다.
  //   (실패해도 예전 동작으로 돌아갈 뿐, 앱이 죽지는 않는다.)
  if (kIsWeb) {
    try {
      await BrowserContextMenu.disableContextMenu();
    } catch (e) {
      debugPrint('[turn72] BrowserContextMenu 비활성화 실패(무시): $e');
    }
  }

  // 1) 저장소 초기화 — NAS 연결 시도, 실패하면 로컬 시드로 폴백.
  //  [로딩 가속] 첫 프레임(화면)을 NAS 통신으로 막지 않도록, 초기화를
  //  백그라운드로 시작하고 즉시 UI 를 띄운다. 데이터는 준비되는 대로
  //  repo.revision → AppState.refresh 로 화면에 반영된다(빈 목록은 곧 채워짐).
  final nas = NasApi();
  final repo = MemberRepository(nas: nas);
  unawaited(repo.init());

  final appState = AppState(repo, nas: nas);
  final finance = FinanceService(nas);
  // AI 자연어 검색(후원자 명단 등)에서 재무 데이터를 참조할 수 있도록 연결
  appState.finance = finance;
  // 재무 데이터 로드 — 첫 프레임을 막지 않도록 백그라운드로.
  unawaited(finance.load());

  runApp(
    MultiProvider(
      providers: [
        Provider<NasApi>.value(value: nas),
        Provider<MemberRepository>.value(value: repo),
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<FinanceService>.value(value: finance),
      ],
      child: const TsakApp(),
    ),
  );
}

class TsakApp extends StatelessWidget {
  const TsakApp({super.key});

  /// [turn66] 전역 네비게이터 키.
  ///
  /// ## 왜 필요한가 (실측 버그)
  ///  로그인 성공 시 `AppState.login()` 안에서 `notifyListeners()` 가
  ///  먼저 실행된다. 그러면 AuthGate 가 곧바로 HomeScreen 으로 교체되고
  ///  **LockScreen 은 위젯 트리에서 사라진다**. 그 뒤 LockScreen 의
  ///  context 로 다이얼로그를 띄우면 "죽은 context" 가 되어, 닫히는 순간
  ///  로그인 화면이 다시 그려졌다("확인하면 다시 로그인 창이 열림").
  ///  → 트리에 살아 있는 전역 Navigator 로 띄우면 이 문제가 사라진다.
  static final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appTitle,
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      theme: AppTheme.light(),
      // ── [turn72] 한글 로컬라이제이션 ────────────────────────────────────
      //  요구: "copy, cut 등등의 기본 메뉴 자체가 안 뜸"
      //
      //  원인 1) **[turn72 정정] SelectionArea 는 주범이 아니었다.**
      //    Flutter 소스를 직접 확인한 결과, 웹에서 툴바가 안 뜨는 1차 원인은
      //    `_webContextMenuEnabled` 가드(브라우저 기본 메뉴에 위임)였고,
      //    iOS PWA 의 숨은 <input> 에는 그 기본 메뉴가 붙지 않아 결과적으로
      //    "아무 메뉴도 안 뜨는" 상태가 됐다. 해결은 main() 위쪽의
      //    `BrowserContextMenu.disableContextMenu()` 주석 참고.
      //    SelectionArea 는 보조 요인(제스처 경합)일 뿐이므로 유지한다.
      //  원인 2) 이 앱에는 **GlobalMaterialLocalizations 가 없었다.**
      //    Flutter 의 선택 툴바(잘라내기/복사/붙여넣기) 라벨은 Material
      //    로컬라이제이션에서 온다. 미등록 상태에서는 영어 기본값에 의존한다.
      //    → 한국어 델리게이트를 등록해 라벨을 '잘라내기/복사/붙여넣기' 로 확정.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      locale: const Locale('ko', 'KR'),
      // 규칙: 모든 창의 텍스트를 선택·복사할 수 있게 한다(PC 우클릭/드래그).
      //  · SelectionArea 가 트리 전체의 Text 를 선택 가능하게 만든다.
      //  · 데스크톱(PC 웹)에서는 마우스 드래그로 스크롤되도록 스크롤 동작을
      //    바꿔, 스크롤 막대 없이도 끌어서 이동할 수 있게 한다.
      scrollBehavior: const _TsakScrollBehavior(),
      builder: (context, child) => _TextSelectionHost(child: child),
      home: const AuthGate(),
    );
  }
}

/// 웹/데스크톱에서 마우스로 목록을 끌어 스크롤할 수 있게 하는 동작.
///
/// (모바일은 기존 터치 스크롤 그대로 — 마우스 입력이 있을 때만 확장한다.)
class _TsakScrollBehavior extends MaterialScrollBehavior {
  const _TsakScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}

/// 모든 화면의 텍스트를 **선택·복사** 가능하게 만드는 전역 래퍼.
///
/// `SelectionArea` 는 하위 트리의 `Text`·`RichText` 를 길게 눌러(모바일) 또는
/// 드래그(PC) 선택할 수 있게 하고, PC 우클릭 시 "복사" 메뉴를 제공한다.
class _TextSelectionHost extends StatelessWidget {
  const _TextSelectionHost({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (child == null) return const SizedBox.shrink();
    return SelectionArea(child: child!);
  }
}

/// 인증 게이트 — 잠금 화면 ↔ 홈 화면, 1시간 세션 만료 시 재잠금
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Timer? _timer;
  bool _initialized = false;

  /// QR 딥링크 파라미터 (?access=personal&no=415)
  String _prefillNo = '';
  bool _fromQr = false;

  /// QR 딥링크 소속 — 은하스카우트 QR이면 'eunha' (기본 'tsak').
  ///   [버그수정] 은하 인가번호는 범 인가번호와 숫자가 겹쳐서, 소속을 함께
  ///   받지 않으면 은하 QR이 범스카우트 회원으로 열린다.
  String _fromCorps = 'tsak';

  /// 행사 QR 딥링크 파라미터 (?access=event&year=..&title=..)
  String _eventYear = '';
  String _eventTitle = '';

  /// 게시판 글 딥링크 파라미터 (?access=board&id=..)
  String _boardId = '';

  @override
  void initState() {
    super.initState();
    _readDeepLink();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<AppState>();
      state.setBootProgress(15, '세션을 확인하는 중…');
      // 개인정보 수정 딥링크(?access=personal)는 세션 복원 시 **본인 1건만**
      //  받아 즉시 연다(무거운 전체 명단 로딩으로 멈추는 문제 방지).
      if (_fromQr && _fromCorps == 'eunha') {
        // 은하스카우트 QR — 소속을 먼저 지정해야 서버가 은하 명단에서 찾는다.
        state.presetCorps('eunha');
      }
      await state.restoreSession(self: _fromQr && _prefillNo.isNotEmpty);
      state.setBootProgress(45, '데이터를 불러오는 중…');
      // 개인 QR 스캔 → 로그인으로 간주(비밀번호 없이) 하고 바로 정보수정으로.
      if (_fromQr && _prefillNo.isNotEmpty && !state.sessionValid) {
        state.setBootProgress(55, '본인 정보를 확인하는 중…');
        await state.qrPersonalLogin(_prefillNo, corps: _fromCorps);
      }
      state.setBootProgress(95, '화면을 그리는 중…');
      if (mounted) setState(() => _initialized = true);
      _startTimer();
    });
  }

  /// URL 쿼리스트링에서 QR 딥링크를 읽는다 (웹).
  void _readDeepLink() {
    if (!kIsWeb) return;
    final uri = Uri.base;
    final no = uri.queryParameters['no'] ?? '';
    final access = uri.queryParameters['access'] ?? '';
    if (access == 'personal' && no.isNotEmpty) {
      _prefillNo = no.replaceAll(RegExp(r'[^0-9]'), '');
      // [버그수정] 은하스카우트 QR(?…&corps=eunha)은 은하 명단에서 찾아야 한다.
      //  소속을 무시하면 같은 숫자의 **범스카우트 회원**이 열린다.
      final c = (uri.queryParameters['corps'] ?? '').toLowerCase().trim();
      _fromCorps = (c == 'eunha') ? 'eunha' : 'tsak';
      _fromQr = true;
    } else if (access == 'event') {
      _eventYear = uri.queryParameters['year'] ?? '';
      _eventTitle = uri.queryParameters['title'] ?? '';
    } else if (access == 'board') {
      _boardId = uri.queryParameters['id'] ?? '';
    }
  }

  void _startTimer() {
    _timer?.cancel();
    // 30초마다 세션 만료 확인 → 만료 시 잠금 화면으로
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      if (state.unlocked && !state.sessionValid) {
        state.lock();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      // [진행률 노출] 무한 스피너만 돌리면 "정지된 것처럼" 오해하므로
      //  진행률(%)과 현재 단계 문구를 함께 보여 준다.
      final st = context.watch<AppState>();
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: (st.bootProgress / 100).clamp(0.0, 1.0),
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '${st.bootProgress.round()}%',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  st.bootStage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  '잠시만 기다려 주세요. 앱이 멈춘 것이 아닙니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final state = context.watch<AppState>();
    if (!state.unlocked || !state.sessionValid) {
      return LockScreen(
        onUnlocked: () => setState(() {}),
        // [버그수정] 은하스카우트 QR은 은하 탭(별도 검증)으로 열어야 한다.
        initialTier: _fromCorps == 'eunha' ? 'eunha' : 'personal',
        initialId: _prefillNo,
      );
    }
    return HomeScreen(
      openMemberNo: _prefillNo,
      openEventYear: _eventYear,
      openEventTitle: _eventTitle,
      openBoardId: _boardId,
    );
  }
}
