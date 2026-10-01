import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 앱 전체 공통 "작업중" 오버레이.
///
/// 긴 대기(로그인·데이터 로딩·출력·업로드·내보내기·사진 불러오기 등) 동안
/// 화면 위에 레이어로 덮여, **멈춘 것이 아니라 작업 중**임을 보여준다.
/// 하단에 진행 상황을 2~3줄 텍스트로 표시한다.
///
/// 사용법(위젯 트리):
///   Stack(children: [ ...내용, BusyOverlay(visible: _busy, title: '...', lines: [...]) ])
///
/// 사용법(간편 전역): [showBusy] / [hideBusy] 로 OverlayEntry 를 띄운다.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({
    super.key,
    required this.visible,
    this.title = '작업 중입니다',
    this.lines = const [],
    this.progress,
    this.onCancel,
    this.cancelLabel = '취소',
  });

  /// true 이면 오버레이가 화면을 덮는다.
  final bool visible;

  /// 큰 제목(기본 '작업 중입니다').
  final String title;

  /// 진행 상황 안내 문구(2~3줄 권장).
  final List<String> lines;

  /// 0.0~1.0 진행률. null 이면 무한 스피너.
  final double? progress;

  /// 취소 가능한 경우 콜백(null 이면 취소 버튼 숨김).
  final VoidCallback? onCancel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: onCancel == null,
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          alignment: Alignment.center,
          child: Container(
            width: 300,
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _spinner(),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark,
                  ),
                ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final l in lines.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 5, right: 6),
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: AppColors.purple,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              l,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: AppColors.textGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 6),
                const Text(
                  '창을 닫거나 나가지 마세요. 잠시만 기다려 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                ),
                if (onCancel != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onCancel,
                    child: Text(
                      cancelLabel,
                      style: const TextStyle(color: AppColors.taegeukRed),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _spinner() {
    if (progress != null) {
      return Column(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              value: progress!.clamp(0.0, 1.0),
              strokeWidth: 5,
              color: AppColors.purple,
              backgroundColor: AppColors.purple.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(progress!.clamp(0.0, 1.0) * 100).round()}%',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.purple,
            ),
          ),
        ],
      );
    }
    return const SizedBox(
      width: 46,
      height: 46,
      child: CircularProgressIndicator(strokeWidth: 4, color: AppColors.purple),
    );
  }
}

// ======================= 전역(OverlayEntry) 간편 API =======================
final ValueNotifier<_BusyState?> _busyNotifier = ValueNotifier(null);
OverlayEntry? _busyEntry;

/// 전역 오버레이로 "작업중" 창을 띄운다. (Navigator/Overlay 가 있는 화면)
void showBusy(
  BuildContext context, {
  String title = '작업 중입니다',
  List<String> lines = const [],
  double? progress,
}) {
  hideBusy();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _busyNotifier.value = _BusyState(
    title: title,
    lines: List.of(lines),
    progress: progress,
  );
  _busyEntry = OverlayEntry(
    builder: (_) => ValueListenableBuilder<_BusyState?>(
      valueListenable: _busyNotifier,
      builder: (_, s, __) => BusyOverlay(
        visible: s != null,
        title: s?.title ?? '',
        lines: s?.lines ?? const [],
        progress: s?.progress,
      ),
    ),
  );
  overlay.insert(_busyEntry!);
}

/// 전역 오버레이 내용을 갱신(진행률·문구 변경).
void updateBusy({String? title, List<String>? lines, double? progress}) {
  final s = _busyNotifier.value;
  if (s == null) return;
  _busyNotifier.value = _BusyState(
    title: title ?? s.title,
    lines: lines ?? s.lines,
    progress: progress ?? s.progress,
  );
}

/// 전역 오버레이를 닫는다.
void hideBusy() {
  _busyEntry?.remove();
  _busyEntry = null;
  _busyNotifier.value = null;
}

class _BusyState {
  _BusyState({this.title = '작업 중입니다', this.lines = const [], this.progress});
  final String title;
  final List<String> lines;
  final double? progress;
}
