import 'package:flutter/material.dart';

/// 모든 화면에서 사용할 뒤로가기 버튼
/// (하드웨어 뒤로가기 버튼이 없는 폰을 위해 항상 표시)
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return TextButton.icon(
      onPressed: () {
        if (canPop) {
          Navigator.of(context).maybePop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('첫 화면입니다')),
          );
        }
      },
      icon: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
      label: Text(
        label ?? '뒤로',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
