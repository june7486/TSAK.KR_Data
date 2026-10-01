/// 시스템 메일 앱 호출(mailto) 공용 헬퍼.
///
/// ## 왜 필요한가 (요구: "메일 클릭시 아무것도 안나옴 → 자신의 기기에서
/// mail to 기능을 써주고 → 주문번호와 주문내용이 자동으로 입력됨")
/// 기존에는 `Uri(scheme:'mailto', query:...)` 로 만든 URI 를 `launchUrl` 로
/// 열어, 일부 브라우저/OS 에서 **아무 반응이 없거나 제목·본문이 누락**됐다.
/// 이 헬퍼는 제목·본문을 **RFC 6068 규격대로 인코딩**하고, 실패 시 클립보드
/// 폴백까지 처리해 어떤 기기에서도 "메일 앱 + 미리 채워진 내용"이 뜨게 한다.
library;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

/// `mailto:` URI 를 만든다(제목·본문 인코딩 포함).
///
/// [to] 가 비면 받는사람 없이 메일 앱만 연다(사용자가 직접 입력).
/// [cc] 는 참조(쉼표 구분 허용).
Uri buildMailtoUri({
  String to = '',
  String cc = '',
  required String subject,
  required String body,
}) {
  // mailto 는 query 가 아니라 '?' 뒤에 오는 경우가 많아 Uri(scheme...) 대신
  // 직접 문자열로 조립한다(플랫폼별 인코딩 차이 회피).
  final sb = StringBuffer('mailto:');
  final toList = to.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
  sb.write(toList.join(','));
  final params = <String>[];
  if (cc.trim().isNotEmpty) {
    params.add('cc=${_enc(cc)}');
  }
  params.add('subject=${_enc(subject)}');
  params.add('body=${_enc(body)}');
  sb.write('?${params.join('&')}');
  return Uri.parse(sb.toString());
}

String _enc(String s) => Uri.encodeComponent(s).replaceAll('+', '%20');

/// 메일 앱을 연다. 성공하면 true.
///
/// 1) 기본(외부 앱) 모드 → 2) 플랫폼 기본 모드 순으로 시도하고,
/// 둘 다 실패하면 false 를 돌려준다(호출부에서 클립보드 폴백).
Future<bool> openMail({
  String to = '',
  String cc = '',
  required String subject,
  required String body,
}) async {
  final uri = buildMailtoUri(to: to, cc: cc, subject: subject, body: body);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
  } catch (_) {}
  try {
    if (await launchUrl(uri)) return true;
  } catch (_) {}
  return false;
}

/// 메일 앱 열기를 시도하고, 실패하면 [fallbackText] 를 클립보드에 복사한다.
///
/// 반환: 메일 앱을 열었으면 true, 복사 폴백이면 false.
Future<bool> openMailOrCopy({
  String to = '',
  String cc = '',
  required String subject,
  required String body,
  String? fallbackText,
}) async {
  final ok = await openMail(to: to, cc: cc, subject: subject, body: body);
  if (!ok) {
    await Clipboard.setData(ClipboardData(text: fallbackText ?? body));
  }
  return ok;
}
