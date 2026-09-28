import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 스크롤 가능한 화면 하단에 **아래 방향 화살표**를 띄워, 더 내려볼 내용이 있음을
/// 알리고 누르면 다음 페이지로 스크롤해 주는 헬퍼 위젯.
///
/// 사용자가 "스크롤이 안 된다"고 느끼는 상황(웹/PC 환경에서 마우스 휠이 안 먹거나,
/// 화면이 넘칠 때)에서도 **무조건 시각적 표시**를 제공해 하단 내용에 접근할 수 있게 한다.
///
/// - [controller] : 화면의 스크롤 컨트롤러(필수). 아래로 더 스크롤 가능할 때만 화살표 노출.
/// - [child]      : 실제 스크롤 뷰(이 래퍼는 그 위에 화살표만 얹는다).
/// - [bottomInset]: 화살표를 띄울 하단 여백(예: 하단 고정 버튼 높이).
class ScrollDownHint extends StatefulWidget {
  const ScrollDownHint({
    super.key,
    required this.controller,
    required this.child,
    this.bottomInset = 12,
    this.step,
  });

  final ScrollController controller;
  final Widget child;
  final double bottomInset;

  /// 한 번 눌렀을 때 이동할 거리(px). null 이면 뷰포트의 82%만큼 이동.
  final double? step;

  @override
  State<ScrollDownHint> createState() => _ScrollDownHintState();
}

class _ScrollDownHintState extends State<ScrollDownHint> {
  bool _more = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    if (!widget.controller.hasClients) {
      if (_more) setState(() => _more = false);
      return;
    }
    final p = widget.controller.position;
    // 아래로 더 내려갈 여지가 8px 이상 남아 있으면 화살표 유지.
    final more = (p.maxScrollExtent - p.pixels) > 8;
    if (more != _more) setState(() => _more = more);
  }

  void _scrollDown() {
    if (!widget.controller.hasClients) return;
    final p = widget.controller.position;
    final step = widget.step ?? (p.viewportDimension * 0.82);
    final target =
        (p.pixels + step).clamp(0.0, p.maxScrollExtent).toDouble();
    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: 0,
          right: 0,
          bottom: widget.bottomInset,
          child: IgnorePointer(
            ignoring: !_more,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _more ? 1 : 0,
              child: Center(
                child: _DownArrow(
                  onTap: _scrollDown,
                  label: '아래로 스크롤',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DownArrow extends StatelessWidget {
  const _DownArrow({required this.onTap, this.label});

  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.purple.withValues(alpha: 0.90),
      shape: const StadiumBorder(),
      elevation: 5,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != null) ...[
                Text(label!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 4),
              ],
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
