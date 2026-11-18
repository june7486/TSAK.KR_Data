import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  static final GlobalKey<NavigatorState> navKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appTitle,
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      theme: AppTheme.light(),
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
