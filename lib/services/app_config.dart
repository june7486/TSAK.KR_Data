/// 전역 앱 설정 — 비밀번호 등 민감 상수 및 서버 주소
///
/// - 마스터 비밀번호(Master): 모든 기능/초기화/통제. 절대 변경 불가.
/// - 앱 비밀번호(App): 앱 설치/접근용. 1시간 후 재입력 요구.
/// - 개인 비밀번호(Personal): 인가번호 + "!@@" (예: 415호 → "415!@@")
class AppConfig {
  /// 마스터 비밀번호 (불변, 절대 변경 금지)
  static const String masterPassword = 'Corbuser7!@@';

  /// 앱 설치/접근 비밀번호
  static const String appPassword = 'Tsak1988!!';

  /// 개인 비밀번호 접미사
  static const String personalSuffix = '!@@';

  /// 세션 유지 시간 (1시간)
  static const Duration sessionTimeout = Duration(hours: 1);

  /// NAS 프록시 서버 주소 (비어 있으면 웹과 동일한 origin 사용 → 상대경로)
  /// Android 등 네이티브에서는 설정에서 절대 URL 입력 가능.
  static String defaultServerBase = '';

  /// SharedPreferences 키
  static const String kServerBase = 'nas_server_base';
  static const String kSessionTs = 'auth_session_ts';
  static const String kAuthTier = 'auth_tier';
  static const String kAuthWho = 'auth_who';
  static const String kAdminEmail = 'admin_email';
}
