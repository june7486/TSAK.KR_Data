import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 좌우로 스크롤되는 메뉴/버튼 행에 **좌우 화살표 인디케이터**를 노출한다.
///
/// ## 규칙 (프로젝트 전역)
/// 메뉴/버튼 행이 화면(창)을 벗어날 수 있는 곳에는 **반드시** 이 위젯으로
/// 감싸 좌우 화살표를 노출한다. 신규 메뉴 추가 시에도 동일하게 적용한다.
///
/// - 내용이 넘칠 때만 해당 방향 화살표를 표시한다(양끝에서는 숨김).
/// - `ScrollMetricsNotification`을 구독해 **초기 레이아웃/내용 변경** 시에도
///   넘침 여부를 정확히 감지한다(스크롤 이벤트가 없어도 동작).
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
    this.alignment = MainAxisAlignment.start,
  });

  /// 가로로 나열할 내용(보통 Row).
  final Widget child;

  /// 스크롤 영역 높이(지정 시 고정, 미지정 시 44).
  final double? height;

  /// 내부 패딩.
  final EdgeInsets padding;

  /// 화살표/페이드 색(기본: 투명).
  final Color? arrowColor;

  /// 좌우 페이드 폭.
  final double fadeWidth;

  /// 내용 정렬(기본: start).
  final MainAxisAlignment alignment;

  @override
  State<HScrollMenu> createState() => _HScrollMenuState();
}

class _HScrollMenuState extends State<HScrollMenu> {
  final ScrollController _c = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onScroll);
    // 초기 레이아웃 반영 후 넘침 여부를 재확인(여러 프레임에 걸쳐 안전하게).
    _scheduleCheck();
  }

  @override
  void dispose() {
    _c.removeListener(_onScroll);
    _c.dispose();
    super.dispose();
  }

  void _scheduleCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _check();
      });
    });
  }

  /// 스크롤 위치/최대치를 기준으로 화살표 노출 여부를 갱신한다.
  void _check() {
    if (!mounted) return;
    double max = 0;
    double off = 0;
    if (_c.hasClients) {
      max = _c.position.maxScrollExtent;
      off = _c.position.pixels;
    }
    final l = off > 1;
    final r = off < max - 1;
    if (l != _canLeft || r != _canRight) {
      setState(() {
        _canLeft = l;
        _canRight = r;
      });
    }
  }

  void _onScroll() => _check();

  void _nudge(double dir) {
    if (!_c.hasClients) return;
    final max = _c.position.maxScrollExtent;
    final step = _c.position.viewportDimension * 0.7 * dir;
    final target = (_c.position.pixels + step).clamp(0.0, max);
    _c.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fade = widget.arrowColor ?? Colors.white.withValues(alpha: 0.0);
    final wrapH = widget.height ?? 44;
    return SizedBox(
      height: wrapH,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          // 내용/뷰포트 크기 변경(초기 레이아웃 포함) 시 재검사.
          _scheduleCheck();
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _check();
            return false;
          },
          child: Stack(
            alignment: Alignment.center,
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
                _edge(left: true, fade: fade, onTap: () => _nudge(-1)),
              // 우측 화살표/페이드
              if (_canRight)
                _edge(left: false, fade: fade, onTap: () => _nudge(1)),
            ],
          ),
        ),
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
                color: Colors.black.withValues(alpha: 0.20),
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

/// [TabController] 기반의 **좌우 화살표 지원 탭 스트립**.
///
/// 기본 [TabBar]는 창을 벗어나도 화살표가 없으므로, 프로젝트 전역 규칙에 따라
/// 이 위젯으로 대체한다(가로로 넘칠 때 좌우 화살표 자동 노출).
class HsTabStrip extends StatelessWidget {
  const HsTabStrip({
    super.key,
    required this.controller,
    required this.labels,
    this.icons,
    this.bg,
    this.selectedColor,
    this.unselectedColor,
    this.height = 46,
  });

  final TabController controller;
  final List<String> labels;

  /// 선택 시 각 탭에 표시할 아이콘(라벨과 길이 동일 시 적용, 아니면 무시).
  final List<IconData>? icons;
  final Color? bg;
  final Color? selectedColor;
  final Color? unselectedColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final background = bg ?? AppColors.purple;
    final selBg = selectedColor ?? Colors.white;
    final selFg = AppColors.purpleDark;
    final unselBg = Colors.white.withValues(alpha: 0.14);
    final unselFg = unselectedColor ?? Colors.white;

    return Container(
      color: background,
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return HScrollMenu(
            height: height - 6,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: labels.asMap().entries.map((e) {
                final i = e.key;
                final selected = controller.index == i;
                final hasIcon = icons != null && icons!.length == labels.length;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => controller.animateTo(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? selBg : unselBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasIcon) ...[
                            Icon(
                              icons![i],
                              size: 16,
                              color: selected ? selFg : unselFg,
                            ),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            e.value,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: selected ? selFg : unselFg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
