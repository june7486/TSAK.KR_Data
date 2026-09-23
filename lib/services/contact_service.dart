import 'dart:convert';

import '../models/member.dart';

/// 단체 문자/메일 수신자 목록 생성 서비스
///
/// 실제 대량 발송은 통신사/메일 서버 연동이 필요하므로,
/// 이 앱에서는 "수신자 목록 자동 생성 + 시스템 문자/메일 앱으로 전달 + 복사" 방식을 사용한다.
class ContactService {
  /// 이메일 주소만 추출 (중복 제거)
  static List<String> emails(List<Member> members) {
    final set = <String>{};
    for (final m in members) {
      final e = m.email.trim();
      if (e.contains('@')) set.add(e);
    }
    return set.toList()..sort();
  }

  /// 전화번호만 추출 (중복 제거, 숫자만)
  static List<String> phones(List<Member> members) {
    final set = <String>{};
    for (final m in members) {
      final p = m.phone.trim();
      if (p.isNotEmpty) set.add(_digits(p));
    }
    return set.toList()..sort();
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

  /// 이메일 CSV 문자열 (클립보드/붙여넣기용)
  static String emailCsv(List<Member> members) => emails(members).join(', ');

  /// 이메일 줄바꿈 문자열
  static String emailList(List<Member> members) => emails(members).join('\n');

  /// 전화번호 CSV
  static String phoneCsv(List<Member> members) => phones(members).join(', ');

  /// 전화번호 줄바꿈
  static String phoneList(List<Member> members) => phones(members).join('\n');

  /// mailto URI 생성 (시스템 메일 앱 호출)
  static String mailtoUri(
    List<Member> members, {
    String subject = '',
    String body = '',
  }) {
    final to = emails(members).join(',');
    return 'mailto:$to?subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}';
  }

  /// sms URI 생성 (시스템 문자 앱 호출 — 다수 수신자 지원)
  static String smsUri(List<Member> members, {String body = ''}) {
    final to = phones(members).join(',');
    // Android는 , 로 다수 지정 가능
    return 'sms:$to${body.isNotEmpty ? '?body=${Uri.encodeComponent(body)}' : ''}';
  }

  /// JSON 파일로 내보내기 (백업/교환용)
  static String buildBackupJson(List<Member> members) {
    final data = members.map((m) => m.toMap()).toList();
    return const JsonEncoder.withIndent('  ').convert({
      'generatedAt': DateTime.now().toIso8601String(),
      'count': members.length,
      'members': data,
    });
  }
}
