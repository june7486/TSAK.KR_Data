import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/app_state.dart';
import 'services/member_repository.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repo = MemberRepository();
  await repo.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<MemberRepository>.value(value: repo),
        ChangeNotifierProvider<AppState>(create: (_) => AppState(repo)),
      ],
      child: const TsakApp(),
    ),
  );
}

class TsakApp extends StatelessWidget {
  const TsakApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 글자 배율을 앱 전체에 반영 (사용자가 하단 슬라이더로 조절)
    final scale = context.select<AppState, double>((s) => s.fontScale);
    return MaterialApp(
      title: 'TSAK 인가자 관리',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (context, child) {
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeScreen(),
    );
  }
}
