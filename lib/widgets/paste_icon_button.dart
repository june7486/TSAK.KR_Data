import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// 텍스트필드용 **붙여넣기 버튼** (suffixIcon 으로 배치).
///
/// ## 왜 만들었나 (요구 2026-11-19: "copy, cut 등등의 기본 메뉴 자체가 안 뜸")
///
/// 앱은 `main.dart` 에서 **전체를 `SelectionArea` 로 감싸** 정적 텍스트를
/// 선택·복사할 수 있게 했다. `SelectionArea` 는 텍스트필드의 롱프레스와
/// 제스처 경합을 일으켜 **필드 자체의 툴바가 늦게 뜨거나 안 뜰 수 있다.**
///
/// 다만 **[turn72 정정] 웹에서 툴바가 아예 안 뜨는 1차 원인은
/// `SelectionArea` 가 아니었다.** Flutter 소스(`editable_text.dart` 의
/// `showToolbar()`)를 확인한 결과, 웹에서는
/// `if (_webContextMenuEnabled) return false;` 로 **Flutter 가 자체 툴바를
/// 일부러 만들지 않고 브라우저 기본 메뉴에 위임**한다. 그런데 Flutter 웹
/// (CanvasKit)은 입력을 화면 밖 숨은 `<input>` 으로 처리하고,
/// iOS Safari(특히 홈화면 PWA 전체화면)는 그 숨은 input 에 선택 메뉴를
/// 붙여주지 않는다 → 위임할 곳도, Flutter 툴바도 없어 "메뉴가 아예 안 뜸".
///
/// 근본 해결은 `main.dart` 의 `BrowserContextMenu.disableContextMenu()` 이다.
/// **이 버튼은 그 해결이 어떤 이유로든 동작하지 않는 환경을 위한 보조 수단**이며,
/// OS 메뉴를 거치지 않고 앱이 클립보드를 직접 읽는 경로라 항상 동작한다.
///
/// ## 동작
///   · `Clipboard.getData('text/plain')` → 컨트롤러에 삽입
///   · `digitsOnly: true` 면 숫자만 남긴다.
///     "280,000원" / "10만원" 처럼 다른 곳에서 복사한 값을 붙여도
///     쉼표·'원'·'만' 이 걸러져 **조용히 아무 일도 안 일어나는** 문제를 막는다.
///   · `maxLength` 를 주면 앞에서부터 잘라 넣는다.
///
/// ## iOS 주의
/// iOS 16+ 는 첫 호출 때 "붙여넣기 허용?" 팝업을 띄운다. 한 번 허용하면
/// 이후로는 뜨지 않는다(거부했다면 설정 > Safari > 붙여넣기 허용).
class PasteIconButton extends StatelessWidget {
  const PasteIconButton({
    super.key,
    required this.controller,
    this.digitsOnly = false,
    this.maxLength,
    this.tooltip = '붙여넣기',
    this.onDone,
  });

  final TextEditingController controller;
  final bool digitsOnly;
  final int? maxLength;
  final String tooltip;

  /// 붙여넣기 후 호출(검증·저장 상태 갱신용).
  final VoidCallback? onDone;

  /// 붙여넣을 문자열을 정리한다. 숫자 전용이면 숫자만 남긴다.
  static String sanitize(
    String raw, {
    bool digitsOnly = false,
    int? maxLength,
  }) {
    var v = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (digitsOnly) {
      v = v.replaceAll(RegExp(r'[^0-9]'), '');
    }
    if (maxLength != null && v.length > maxLength) {
      v = v.substring(0, maxLength);
    }
    return v;
  }

  Future<void> _paste(BuildContext context) async {
    String raw;
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      raw = d?.text ?? '';
    } catch (_) {
      raw = '';
    }
    if (!context.mounted) return;
    if (raw.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('클립보드가 비어 있습니다. 복사한 뒤 다시 눌러 주세요.'),
          duration: Duration(milliseconds: 1600),
        ),
      );
      return;
    }
    final v = sanitize(raw, digitsOnly: digitsOnly, maxLength: maxLength);
    if (v.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            digitsOnly
                ? '숫자가 없습니다. 복사한 내용: ${raw.length > 20 ? '${raw.substring(0, 20)}…' : raw}'
                : '붙여넣을 내용이 없습니다.',
          ),
          duration: const Duration(milliseconds: 2200),
        ),
      );
      return;
    }
    final text = controller.text;
    final sel = controller.selection;
    // 커서 위치에 삽입(선택 영역이 있으면 대체). 커서가 없으면 끝에 덧붙인다.
    if (sel.isValid && sel.start >= 0 && sel.end <= text.length) {
      controller.value = TextEditingValue(
        text: text.replaceRange(sel.start, sel.end, v),
        selection: TextSelection.collapsed(offset: sel.start + v.length),
      );
    } else {
      final merged = (text + v);
      controller.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(offset: merged.length),
      );
    }
    onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 19,
      // 아이콘 색을 보라로 두어 회색 안내문과 구분되게 한다(누를 수 있는 것임을 알린다).
      color: AppColors.purple,
      onPressed: () => _paste(context),
      icon: const Icon(Icons.content_paste_go_rounded),
    );
  }
}
