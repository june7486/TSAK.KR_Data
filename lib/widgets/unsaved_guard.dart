import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 수정사항 저장 여부를 묻는 공용 다이얼로그
///  - YES: 저장 후 이탈
///  - NO : 저장하지 않고 이탈
///  - 취소: 페이지에 그대로 머무름
enum UnsavedChoice { save, discard, cancel }

Future<UnsavedChoice> showUnsavedDialog(BuildContext context) async {
  final result = await showDialog<UnsavedChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('수정사항 저장'),
      content: const Text(
        '수정사항을 저장하지 않았습니다. 저장하시겠습니까?',
        style: TextStyle(fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, UnsavedChoice.cancel),
          child: const Text('취소'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.taegeukRed),
          onPressed: () => Navigator.pop(ctx, UnsavedChoice.discard),
          child: const Text('NO (저장 안 함)'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.scoutGreen),
          onPressed: () => Navigator.pop(ctx, UnsavedChoice.save),
          child: const Text('YES (저장)'),
        ),
      ],
    ),
  );
  return result ?? UnsavedChoice.cancel;
}

/// 미저장 상태로 뒤로가기를 시도할 때 확인을 수행하는 헬퍼.
/// [saved] 로 실제 저장을 수행하고, 저장이 성공하면 pop 가능.
class UnsavedGuard extends StatelessWidget {
  const UnsavedGuard({
    super.key,
    required this.child,
    required this.dirty,
    required this.onSave,
  });

  /// 편집 내용이 저장되지 않았는지 여부
  final bool Function() dirty;

  /// 저장 콜백 — 저장 성공 시 true 반환
  final Future<bool> Function() onSave;

  final Widget child;

  Future<void> _handlePop(BuildContext context) async {
    if (!dirty()) {
      Navigator.of(context).pop();
      return;
    }
    final choice = await showUnsavedDialog(context);
    if (!context.mounted) return;
    switch (choice) {
      case UnsavedChoice.save:
        final ok = await onSave();
        if (context.mounted && ok) Navigator.of(context).pop();
        break;
      case UnsavedChoice.discard:
        Navigator.of(context).pop();
        break;
      case UnsavedChoice.cancel:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handlePop(context);
      },
      child: child,
    );
  }
}
