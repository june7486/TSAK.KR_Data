import 'package:flutter/material.dart';
import 'marquee_text.dart';

/// 전 화면 공통 상단바 — TSAK 브랜드를 동일하게 노출한다.
///
/// 요구 #2: "모든창 상단에는 한국범스카우트중앙회 메뉴가 동일하게 나타나야함".
/// 표준 [AppBar] 와 동일한 API 를 갖되, 제목 아래에 브랜드 라벨
/// ("한국 범스카우트중앙회")을 항상 함께 표시한다. 따라서 각 화면은
/// `appBar: AppBar(...)` 를 `appBar: TsakAppBar(...)` 로 바꾸기만 하면
/// 모든 창에 동일한 중앙회 브랜딩이 적용된다.
class TsakAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TsakAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.leadingWidth,
    this.centerTitle,
    this.backgroundColor,
    this.foregroundColor,
    this.titleSpacing,
    this.elevation,
    this.flexibleSpace,
    this.shape,
    this.brandLabel = '한국 범스카우트중앙회',
  });

  /// 화면 제목 (관리자/일반 화면의 실제 제목).
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final double? leadingWidth;
  final bool? centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? titleSpacing;
  final double? elevation;
  final Widget? flexibleSpace;
  final ShapeBorder? shape;

  /// 제목 아래 항상 노출되는 브랜드 라벨.
  final String brandLabel;

  static const double _brandToolbarHeight = 60;

  double get _toolbarHeight =>
      title == null ? kToolbarHeight : _brandToolbarHeight;

  @override
  Size get preferredSize =>
      Size.fromHeight(_toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    // 제목이 없으면 브랜드 라벨만 얇게 노출.
    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      leadingWidth: leadingWidth,
      actions: actions,
      bottom: bottom,
      centerTitle: centerTitle,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      titleSpacing: titleSpacing,
      elevation: elevation,
      flexibleSpace: flexibleSpace,
      shape: shape,
      toolbarHeight: _toolbarHeight,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: centerTitle == true
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (title != null)
            DefaultTextStyle.merge(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
              child: title!,
            ),
          if (title != null) const SizedBox(height: 1),
          MarqueeText(
            brandLabel,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
