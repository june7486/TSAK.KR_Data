/// 키보드 안전 입력 시트 — 큰 입력 폼(참석자·재무·메뉴추가) 공용.
///
/// ## 왜 만들었나 (버그 원인)
/// "스마트폰으로 행사추가항목 선택시 입력창이 보이지 않고 스크롤해야만하는 버그가
///  있음. 행사창 입력시 창이 급격히 줄어들고 입력창이 안보임. 지속적인 오류생김"
///
/// 종전 구현은 `AlertDialog(scrollable: true)` 안에 다시
/// `SizedBox(width: 360)` + `SingleChildScrollView` 를 넣은 **이중 제약**이었다.
/// 키보드가 올라오면 AlertDialog 는 화면 높이에서 `viewInsets.bottom` 을 빼고
/// 자기 크기를 다시 계산한다. 여기에 고정폭 SizedBox 와 내부 스크롤이 겹치면
/// ① 창이 급격히 줄고 ② 포커스된 입력칸이 스크롤 밖으로 밀려나 보이지 않는다.
///
/// ## 해결 방식
/// · `showModalBottomSheet(isScrollControlled: true)` — 높이 상한(9/16) 없음.
/// · 시트 높이를 **키보드를 뺀 화면 높이의 94%** 로 고정 계산한다.
///   `insets + 0.94*(H - insets) < H` 이므로 화면을 넘지 않고, 키보드가 떠도
///   높이가 '줄어들지' 않는다(내용만 스크롤).
/// · 헤더/본문/버튼을 Column 으로 분리 — 본문만 Expanded + 스크롤.
///   → 어떤 입력칸을 눌러도 스크롤로 항상 보이고, 저장 버튼은 항상 보인다.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 큰 입력 폼용 바텀시트.
///
/// 반환값: 저장=true / 취소·바깥탭=null.
Future<bool?> showTsakFormSheet({
  required BuildContext context,
  required String title,
  String? subtitle,
  required Widget Function(BuildContext ctx, StateSetter setSheetState) builder,
  String saveLabel = '저장',
  String cancelLabel = '취소',
  IconData icon = Icons.edit_note,
  Color? accent,
  double heightFactor = 0.94,
  bool scrollableBody = true,
}) {
  final color = accent ?? AppColors.purple;
  return showModalBottomSheet<bool>(
    context: context,
    // 핵심 ①: 높이 제한(9/16) 해제 → 창이 급격히 줄지 않는다.
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final mq = MediaQuery.of(ctx);
          // 핵심 ②: 키보드 높이를 뺀 영역의 94%로 고정.
          final avail = mq.size.height - mq.viewInsets.bottom;
          final h = avail * heightFactor;
          return Padding(
            // 시트를 키보드 위로 올린다(입력칸이 키보드에 가리지 않음).
            padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
            child: SizedBox(
              height: h,
              child: Column(
                children: [
                  // ---- 헤더 ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (subtitle != null && subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textGray,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: color.withValues(alpha: 0.15)),
                  // ---- 본문 (여기만 스크롤) ----
                  Expanded(
                    child: scrollableBody
                        ? SingleChildScrollView(
                            // 키보드가 떠도 스크롤 가능하게 유지.
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            child: builder(ctx, setSheetState),
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            child: builder(ctx, setSheetState),
                          ),
                  ),
                  // ---- 버튼 (항상 보임) ----
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: color.withValues(alpha: 0.12)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: Text(cancelLabel),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: color,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              saveLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 폼 안에서 쓰는 라벨+입력 한 줄 묶음(간격 통일).
class TsakField extends StatelessWidget {
  const TsakField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.required = false,
  });

  final String label;
  final Widget child;
  final String? hint;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textGray,
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.taegeukRed,
                  ),
                ),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textGray,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          child,
        ],
      ),
    );
  }
}

/// 결과값을 돌려주는 일반형 폼 시트 — [showTsakFormSheet] 의 제네릭 판.
///
/// ## 왜 필요한가
/// 행사 만들기/수정 폼은 저장 시 여러 입력값([EventFormResult])을 돌려줘야
/// 하는데 `showTsakFormSheet` 는 `bool` 만 반환한다. 같은 레이아웃 규칙
/// (키보드 높이 차감 · 헤더/스크롤/버튼 고정)을 그대로 쓰면서 **결과 타입만**
/// 제네릭으로 바꾼 버전이다.
///
/// ## 키보드 처리 (핵심)
/// `showModalBottomSheet(isScrollControlled: true, useSafeArea: true)` +
/// `height = (화면높이 − 키보드높이) × heightFactor` + `padding.bottom = 키보드높이`.
/// → 키보드가 올라와도 창이 **줄지 않고** 입력칸이 가려지지 않는다.
/// (AlertDialog + SingleChildScrollView 조합에서 반복 발생하던
///  "창이 급격히 줄어 입력이 불가" 문제의 근본 해결)
Future<T?> showTsakFormSheetResult<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required Widget Function(BuildContext ctx, StateSetter setSheetState) builder,
  required T Function() buildResult,
  bool Function()? validate,
  String saveLabel = '저장',
  String cancelLabel = '취소',
  IconData icon = Icons.edit_note,
  Color? accent,
  double heightFactor = 0.94,
}) {
  final color = accent ?? AppColors.purple;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final mq = MediaQuery.of(ctx);
          final avail = mq.size.height - mq.viewInsets.bottom;
          final h = avail * heightFactor;
          return Padding(
            padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
            child: SizedBox(
              height: h,
              child: Column(
                children: [
                  // 헤더
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (subtitle != null && subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textGray,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: color.withValues(alpha: 0.15)),
                  // 본문(여기만 스크롤)
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: builder(ctx, setSheetState),
                    ),
                  ),
                  // 버튼(항상 보임)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: color.withValues(alpha: 0.12)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: Text(cancelLabel),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: color,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            onPressed: () {
                              if (validate != null && !validate()) return;
                              Navigator.pop(ctx, buildResult());
                            },
                            child: Text(
                              saveLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
