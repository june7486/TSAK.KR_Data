import 'package:flutter/material.dart';

import '../services/output_formats.dart';
import '../theme/app_theme.dart';

/// 모든 게시판·명단에서 공통으로 쓰는 **깔끔한 출력 형식 선택 시트**.
///
/// 규칙(#14): 형식은 항상 **PDF → JPG → 엑셀 → PPT → 워드 → TXT** 순서로
/// 노출하고, 형식 선택과 함께 **인쇄 · 이메일 · 이미지 공유 · 링크 공유**를
/// 같은 시트에서 바로 실행할 수 있게 한다.
///
/// 사용 예:
/// ```dart
/// showTsakOutputSheet(
///   context,
///   title: '판매대장 출력',
///   subtitle: '2026년 · 주문·예약 통합 장부',
///   onPick: (f) => _printLedger(format: f),
///   onPrint: () => _printLedger(),
///   onEmail: _emailLedger,
///   onShareLink: () => showLinkShareDialog(context, url),
/// );
/// ```
Future<void> showTsakOutputSheet(
  BuildContext context, {
  required String title,
  String subtitle = '',
  void Function(TsakOutputFormat)? onPick,
  VoidCallback? onPrint,
  VoidCallback? onEmail,
  VoidCallback? onShareImage,
  VoidCallback? onShareLink,
  VoidCallback? onTxt,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFBF9F4),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.ios_share, size: 18, color: AppColors.purple),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.purpleDark,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 25),
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGray,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 25),
              child: Text(
                kTsakOutputRule,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textGray,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── 형식 카드(규칙 순서 고정) ──
            if (onPick != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in kTsakOutputOrder)
                    _FmtCard(f: f, onTap: () => onPick(f)),
                ],
              ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            // ── 부가 동작: 인쇄 · 이메일 · 공유 ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onPrint != null) _act(Icons.print_outlined, '프린트', onPrint),
                if (onEmail != null) _act(Icons.email_outlined, '이메일', onEmail),
                if (onTxt != null) _act(Icons.notes_outlined, 'TXT', onTxt),
                if (onShareImage != null)
                  _act(Icons.image_outlined, '이미지 공유', onShareImage),
                if (onShareLink != null) _act(Icons.link, '링크 공유', onShareLink),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _act(IconData icon, String label, VoidCallback onTap) {
  return OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      foregroundColor: AppColors.purpleDark,
      side: BorderSide(color: AppColors.purple.withValues(alpha: 0.30)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 15),
    label: Text(
      label,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    ),
  );
}

class _FmtCard extends StatelessWidget {
  const _FmtCard({required this.f, required this.onTap});

  final TsakOutputFormat f;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2DCD2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(f.icon, size: 20, color: AppColors.purple),
            const SizedBox(height: 7),
            Text(
              f.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            Text(
              _desc(f),
              style: const TextStyle(fontSize: 10, color: AppColors.textGray),
            ),
          ],
        ),
      ),
    );
  }

  String _desc(TsakOutputFormat f) => switch (f) {
    TsakOutputFormat.pdf => '인쇄·보관용',
    TsakOutputFormat.jpg => '이미지 저장',
    TsakOutputFormat.excel => '표 데이터',
    TsakOutputFormat.ppt => '슬라이드',
    TsakOutputFormat.word => '문서 편집',
    TsakOutputFormat.txt => '간단 목록',
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 실시간 진행 상황 대기창
// ═══════════════════════════════════════════════════════════════════════

/// 진행 상황 상태(진행률·현재 단계 메시지).
class TsakProgressState {
  TsakProgressState({this.progress, this.message = '', this.stepIndex});

  /// 0.0~1.0. null 이면 무한 스피너.
  final double? progress;
  final String message;

  /// 전체 단계 중 현재 단계(0-based). null 이면 표시 안 함.
  final int? stepIndex;
}

/// 진행 상황을 **실시간으로** 보여주는 대기창 컨트롤러.
class TsakProgressController {
  TsakProgressController._(this._notifier);

  final ValueNotifier<TsakProgressState> _notifier;

  /// 진행률(0~1)·메시지·단계를 갱신한다.
  void update({double? progress, String? message, int? stepIndex}) {
    final prev = _notifier.value;
    _notifier.value = TsakProgressState(
      progress: progress ?? prev.progress,
      message: message ?? prev.message,
      stepIndex: stepIndex ?? prev.stepIndex,
    );
  }
}

/// **실시간 진행 대기창** — 파일/문서를 만드는 동안 진행률과 단계를 보여준다.
///
/// [steps] 를 주면 체크리스트로 각 단계 완료를 표시하고, [task] 안에서
/// [TsakProgressController.update] 로 진행률·메시지를 갱신한다.
///
/// ```dart
/// await runWithTsakProgress(
///   context,
///   title: '전체 명단 출력',
///   steps: const ['데이터 수집', '문서 생성', '파일 저장'],
///   task: (ctl) async {
///     ctl.update(progress: 0.2, message: '데이터 수집 중…', stepIndex: 0);
///     ...
///   },
/// );
/// ```
Future<void> runWithTsakProgress(
  BuildContext context, {
  required String title,
  String note = '',
  List<String> steps = const [],
  required Future<void> Function(TsakProgressController ctl) task,
}) async {
  final notifier = ValueNotifier<TsakProgressState>(
    TsakProgressState(progress: steps.isEmpty ? null : 0),
  );
  final ctl = TsakProgressController._(notifier);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(
      title: title,
      note: note,
      steps: steps,
      notifier: notifier,
    ),
  );

  try {
    await task(ctl);
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    notifier.dispose();
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({
    required this.title,
    required this.note,
    required this.steps,
    required this.notifier,
  });

  final String title;
  final String note;
  final List<String> steps;
  final ValueNotifier<TsakProgressState> notifier;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: ValueListenableBuilder<TsakProgressState>(
          valueListenable: notifier,
          builder: (context, st, _) {
            final pct = st.progress == null
                ? null
                : (st.progress! * 100).round();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.purpleDark,
                        ),
                      ),
                    ),
                    if (pct != null)
                      Text(
                        '$pct%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.purple,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: st.progress,
                    minHeight: 7,
                    backgroundColor: AppColors.purple.withValues(alpha: 0.10),
                  ),
                ),
                if (st.message.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    st.message,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
                if (steps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (var i = 0; i < steps.length; i++)
                    _stepRow(
                      steps[i],
                      done: st.stepIndex != null && i < st.stepIndex!,
                      active: st.stepIndex == i,
                    ),
                ],
                if (note.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    note,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  '창을 닫지 마세요. 잠시만 기다려 주세요.',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stepRow(String label, {required bool done, required bool active}) {
    final color = done
        ? AppColors.scoutGreen
        : (active ? AppColors.purple : AppColors.textGray);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle
                : (active
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
            size: 15,
            color: color,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
