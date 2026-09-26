/// 전역 앱 설정 — 비밀번호 등 민감 상수 및 서버 주소
///
/// - 마스터 비밀번호(Master): 모든 기능/초기화/통제. 절대 변경 불가.
/// - 앱 비밀번호(App): 앱 설치/접근용. 1시간 후 재입력 요구.
/// - 개인 비밀번호(Personal): 인가번호 + "!@@" (예: 인가번호 000 → "000!@@")
class AppConfig {
  /// 앱 표시 제목
  static const String appTitle = '한국 범스카우트중앙회 통합 앱';

  /// 프로그램 버전 / 업데이트 날짜
  static const String appVersion = '1.0.0';
  static const String appUpdated = '2025.09.24';

  /// 마스터 비밀번호 (불변, 절대 변경 금지)
  static const String masterPassword = 'Corbuser7!@@';

  /// 영구 마스터 인가번호 — 개인 로그인/QR 스캔 시에도 마스터와 동일 권한.
  /// (예: 대표 개발자 415)
  static const Set<String> permanentMasterNumbers = {'415'};

  /// 주어진 인가번호가 영구 마스터인지 판정.
  static bool isPermanentMaster(String number) {
    final n = number.replaceAll(RegExp(r'[^0-9]'), '');
    return n.isNotEmpty && permanentMasterNumbers.contains(n);
  }

  /// 앱 설치/접근 비밀번호
  static const String appPassword = 'Tsak1988!!';

  /// 개인 비밀번호 접미사
  static const String personalSuffix = '!@@';

  /// 세션 유지 시간 (1시간)
  static const Duration sessionTimeout = Duration(hours: 1);

  /// NAS 프록시 서버 주소 (비어 있으면 웹과 동일한 origin 사용 → 상대경로)
  /// Android 등 네이티브에서는 설정에서 절대 URL 입력 가능.
  static String defaultServerBase = '';

  /// 앱 **공개 접속 주소**(웹 배포 URL). QR 생성의 최종 기준.
  ///
  /// 빌드 시 `--dart-define=APP_BASE_URL=https://...` 로 지정하거나,
  /// 마스터가 설정 화면의 'QR 공개 주소'에 입력하면 그것이 우선한다.
  /// NAS DSM 주소는 절대 여기에 넣지 않는다 (QR 스캔 시 DSM 로그인 페이지가
  /// 열려 앱이 뜨지 않는다).
  static const String defaultAppBase = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: '',
  );

  /// QR/딥링크에 쓸 수 없는 주소인지(서버 저장용 NAS 주소 등) 판정.
  static bool isUnusableQrBase(String url) {
    final u = url.trim().toLowerCase();
    if (!u.startsWith('http')) return true;
    // Synology DSM(서버 관리) 주소는 앱 주소가 아니다 → QR에 넣으면 안 됨.
    if (u.contains(':5001')) return true;
    if (u.contains('39.123.241.4')) return true;
    return false;
  }

  /// SharedPreferences 키
  static const String kServerBase = 'nas_server_base';
  static const String kSessionTs = 'auth_session_ts';
  static const String kAuthTier = 'auth_tier';
  static const String kAuthWho = 'auth_who';
  static const String kAdminEmail = 'admin_email';
}
