import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 좌우로 스크롤되는 메뉴/버튼 행에 **좌우 화살표 인디케이터**를 노출한다.
///
/// - 내용이 넘칠 때만 해당 방향 화살표를 표시한다(양끝에서는 숨김).
/// - 화살표를 누르면 한 화면(약 70%)만큼 부드럽게 이동한다.
/// - 그라데이션 페이드로 "더 있음"을 시각적으로 강조한다.
class HScrollMenu extends StatefulWidget {
  const HScrollMenu({
    super.key,
    required this.child,
    this.height,
    this.padding = EdgeInsets.zero,
    this.arrowColor,
    this.fadeWidth = 26,
  });

  /// 가로로 나열할 내용(보통 Row).
  final Widget child;

  /// 스크롤 영역 높이(지정 시 고정, 미지정 시 내용 기준).
  final double? height;

  /// 내부 패딩.
  final EdgeInsets padding;

  /// 화살표/페이드 색(기본: 배경에 맞춘 반투명 화이트).
  final Color? arrowColor;

  /// 좌우 페이드 폭.
  final double fadeWidth;

  @override
  State<HScrollMenu> createState() => _HScrollMenuState();
}

class _HScrollMenuState extends State<HScrollMenu> {
  final ScrollController _c = ScrollController();
  double _maxExtent = 0;
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _c.removeListener(_onScroll);
    _c.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_c.hasClients) return;
    final max = _c.position.maxScrollExtent;
    final off = _c.position.pixels;
    if (max != _maxExtent || off != _offset) {
      setState(() {
        _maxExtent = max;
        _offset = off;
      });
    }
  }

  bool get _canLeft => _offset > 1;
  bool get _canRight => _offset < _maxExtent - 1;

  void _nudge(double dir) {
    if (!_c.hasClients) return;
    final step = _c.position.viewportDimension * 0.7 * dir;
    final target = (_offset + step).clamp(0.0, _maxExtent);
    _c.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fade = widget.arrowColor ??
        Colors.white.withValues(alpha: 0.0);
    final wrapH = widget.height ?? 44;
    return SizedBox(
      height: wrapH,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _c,
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              child: widget.child,
            ),
          ),
          // 좌측 화살표/페이드
          if (_canLeft)
            _edge(
              left: true,
              fade: fade,
              onTap: () => _nudge(-1),
            ),
          // 우측 화살표/페이드
          if (_canRight)
            _edge(
              left: false,
              fade: fade,
              onTap: () => _nudge(1),
            ),
        ],
      ),
    );
  }

  Widget _edge({
    required bool left,
    required Color fade,
    required VoidCallback onTap,
  }) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!left)
            IgnorePointer(
              child: Container(
                width: widget.fadeWidth,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [fade, Colors.transparent],
                  ),
                ),
              ),
            ),
          _arrow(left),
          if (left)
            IgnorePointer(
              child: Container(
                width: widget.fadeWidth,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.transparent, fade],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _arrow(bool left) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _nudge(left ? -1 : 1),
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            left ? Icons.chevron_left : Icons.chevron_right,
            size: 20,
            color: AppColors.purple,
          ),
        ),
      ),
    );
  }
}
