import 'package:flutter/material.dart';

/// 상단 엠블럼 버튼 — 누르면 초기(홈) 화면으로 이동
///
/// [onHome] 이 주어지면 그 동작을 수행하고, 없으면 첫 라우트까지 pop 한다.
class AppHomeEmblem extends StatelessWidget {
  const AppHomeEmblem({
    super.key,
    this.size = 30,
    this.onHome,
    this.showLabel = false,
  });

  final double size;
  final VoidCallback? onHome;
  final bool showLabel;

  void _goHome(BuildContext context) {
    if (onHome != null) {
      onHome!();
      return;
    }
    // 첫 화면(홈)까지 되돌아간다
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final emblem = Image.asset(
      'assets/images/tsak_emblem.png',
      width: size,
      height: size,
      errorBuilder: (_, __, ___) => Icon(
        Icons.shield,
        size: size * 0.9,
        color: Colors.white,
      ),
    );

    return InkWell(
      onTap: () => _goHome(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: showLabel
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  emblem,
                  const SizedBox(width: 6),
                  const Text('한국 범스카우트중앙회 통합 앱'),
                ],
              )
            : emblem,
      ),
    );
  }
}
