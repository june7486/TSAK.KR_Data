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
    return MaterialApp(
      title: 'TSAK 인가자 관리',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomeScreen(),
    );
  }
}
