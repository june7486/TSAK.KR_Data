import 'dart:async';

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

  // 1) 저장소 초기화 — NAS 프록시 연결 시도, 실패하면 로컬 시드로 폴백
  final nas = NasApi();
  final repo = MemberRepository(nas: nas);
  await repo.init();

  final appState = AppState(repo, nas: nas);
  final finance = FinanceService(nas);
  // AI 자연어 검색(후원자 명단 등)에서 재무 데이터를 참조할 수 있도록 연결
  appState.finance = finance;
  // 재무 데이터 로드 (AI 후원 검색 대비)
  finance.load();

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
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

  @override
  void initState() {
    super.initState();
    _readDeepLink();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<AppState>();
      await state.restoreSession();
      if (mounted) setState(() => _initialized = true);
      _startTimer();
    });
  }

  /// URL 쿼리스트링에서 인가자 QR 딥링크를 읽는다 (웹).
  void _readDeepLink() {
    if (!kIsWeb) return;
    final uri = Uri.base;
    final no = uri.queryParameters['no'] ?? '';
    final access = uri.queryParameters['access'] ?? '';
    if (access == 'personal' && no.isNotEmpty) {
      _prefillNo = no.replaceAll(RegExp(r'[^0-9]'), '');
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final state = context.watch<AppState>();
    if (!state.unlocked || !state.sessionValid) {
      return LockScreen(
        onUnlocked: () => setState(() {}),
        initialTier: _prefillNo.isNotEmpty ? 'personal' : 'app',
        initialId: _prefillNo,
      );
    }
    return HomeScreen(openMemberNo: _prefillNo);
  }
}
