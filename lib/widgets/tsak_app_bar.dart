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
    this.actionRows,
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

  /// 상단바 액션 아이콘을 **여러 줄**로 나눠 배치한다.
  ///
  /// 예) `actionRows: [2, 4]` → 1번째 줄 2개, 2번째 줄 4개.
  ///
  /// ## [요구 2026-10-29] "행사관리 아이콘을 2줄로 구분해서 겹쳐지지 않도록"
  /// 행사관리 화면은 액션이 5~6개(행사자료·게시판·사진·썸네일·새로고침·엠블럼)라
  /// 좁은 폰 폭에서 **한 줄에 몰리면 툴바 제목과 겹치고 일부가 잘렸다.**
  /// 줄 수/줄당 개수를 지정하면 [preferredSize] 가 그만큼 자동으로 늘어나
  /// 제목과 아이콘이 **절대 겹치지 않는다.**
  ///
  /// `null` 이면 종전과 똑같이 [AppBar] 기본(한 줄) 동작이다.
  /// 지정한 개수의 합이 [actions] 길이보다 작으면 나머지는 마지막 줄에 이어 붙는다.
  final List<int>? actionRows;

  static const double _brandToolbarHeight = 60;

  /// 액션 1줄 높이 / 아이콘 1칸 폭.
  static const double _actionRowHeight = 42;
  static const double _actionCellWidth = 42;

  /// 실제로 몇 줄을 그리는가 (설정 없으면 0 = 기본 한 줄).
  int get _actionRowCount {
    if (actionRows == null || actionRows!.isEmpty) return 0;
    return actionRows!.where((n) => n > 0).length;
  }

  double get _toolbarHeight {
    final base = title == null ? kToolbarHeight : _brandToolbarHeight;
    if (_actionRowCount <= 1) return base;
    final needed = _actionRowCount * _actionRowHeight + 6;
    return needed > base ? needed : base;
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(_toolbarHeight + (bottom?.preferredSize.height ?? 0));

  /// [actionRows] 설정대로 액션을 잘라 여러 줄로 묶는다.
  List<Widget> _buildActionRows() {
    final list = actions ?? const <Widget>[];
    final spec = actionRows;
    if (spec == null || spec.isEmpty || list.isEmpty) return list;

    final rows = <List<Widget>>[];
    var idx = 0;
    for (final n in spec) {
      if (n <= 0) continue;
      if (idx >= list.length) break;
      final end = (idx + n) > list.length ? list.length : idx + n;
      rows.add(list.sublist(idx, end));
      idx = end;
    }
    // 남은 액션은 마지막 줄에 이어 붙인다(잘려 사라지면 안 된다).
    if (idx < list.length) {
      if (rows.isEmpty) {
        rows.add(list.sublist(idx));
      } else {
        rows.last.addAll(list.sublist(idx));
      }
    }
    if (rows.length <= 1) return rows.isEmpty ? list : rows.first;

    return [
      Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final row in rows)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final w in row)
                    SizedBox(
                      width: _actionCellWidth,
                      height: _actionRowHeight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: _actionCellWidth,
                          height: _actionRowHeight,
                          child: Center(child: w),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final multiRow = _actionRowCount > 1;
    // 제목이 없으면 브랜드 라벨만 얇게 노출.
    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      leadingWidth: leadingWidth,
      actions: multiRow ? _buildActionRows() : actions,
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
