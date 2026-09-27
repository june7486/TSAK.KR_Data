import 'package:flutter/material.dart';

/// PC(마우스) 사용자를 위한 좌우 스크롤 화살표 래퍼.
///
/// 마우스를 좌/우 끝에 가까이 대면 해당 방향 화살표가 나타나고,
/// 누르면 부드럽게 스크롤된다. 터치 환경에서도 탭으로 사용 가능.
class ScrollArrows extends StatefulWidget {
  const ScrollArrows({
    super.key,
    required this.child,
    this.step = 260,
    this.color = const Color(0xFF5B2C8D),
  });

  final Widget child;
  final double step;
  final Color color;

  @override
  State<ScrollArrows> createState() => _ScrollArrowsState();
}

class _ScrollArrowsState extends State<ScrollArrows> {
  final _ctrl = ScrollController();
  bool _showLeft = false;
  bool _showRight = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onScroll);
    _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_ctrl.hasClients) return;
    final max = _ctrl.position.maxScrollExtent;
    final off = _ctrl.offset;
    final left = off > 4;
    final right = off < max - 4;
    if (left != _showLeft || right != _showRight) {
      setState(() {
        _showLeft = left;
        _showRight = right;
      });
    }
  }

  void _nudge(double delta) {
    if (!_ctrl.hasClients) return;
    final target = (_ctrl.offset + delta)
        .clamp(0.0, _ctrl.position.maxScrollExtent);
    _ctrl.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _onScroll(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SingleChildScrollView(
            controller: _ctrl,
            scrollDirection: Axis.horizontal,
            child: widget.child,
          ),
          if (_showLeft)
            Positioned(
              left: 0,
              child: _arrow(Icons.chevron_left, () => _nudge(-widget.step)),
            ),
          if (_showRight)
            Positioned(
              right: 0,
              child: _arrow(Icons.chevron_right, () => _nudge(widget.step)),
            ),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback onTap) {
    return Material(
      color: widget.color.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}
