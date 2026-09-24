import 'package:flutter/services.dart';

/// 핸드폰 번호 자동 하이픈 포매터
///
/// - 숫자 "010"으로 시작하면 010-0000-0000 형태로 자동 하이픈을 삽입한다.
/// - 그 외 번호(예: 02, 031 등)는 사용자가 입력한 그대로 둔다.
class PhoneHyphenFormatter extends TextInputFormatter {
  const PhoneHyphenFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    // "010"으로 시작하는 경우에만 하이픈을 자동 생성
    if (!digits.startsWith('010')) {
      return newValue;
    }
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 11; i++) {
      if (i == 3 || i == 7) buf.write('-');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
