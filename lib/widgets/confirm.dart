import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 삭제·제거 등 **되돌리기 어려운 작업 전 확인창** 공용 헬퍼.
///
/// 요구: "삭제 버튼을 누를 경우 확인 다시 한번 할 것".
///
/// 반환: 사용자가 확인(실행)을 누르면 true, 취소하면 false.
///  · [danger] 가 true 면 실행 버튼을 경고색(붉은색)으로 표시한다(기본 true).
Future<bool> confirmDialog(
  BuildContext context, {
  required String message,
  String title = '확인',
  String confirmLabel = '삭제',
  String cancelLabel = '취소',
  bool danger = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        danger ? Icons.warning_amber_rounded : Icons.help_outline,
        color: danger ? AppColors.taegeukRed : AppColors.purple,
        size: 28,
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13.5, height: 1.45),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? AppColors.taegeukRed : AppColors.purple,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}
