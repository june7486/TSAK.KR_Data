/// 전역 앱 설정 — 비밀번호 등 민감 상수 및 서버 주소
///
/// - 마스터 비밀번호(Master): 모든 기능/초기화/통제. 절대 변경 불가.
/// - 앱 비밀번호(App): 앱 설치/접근용. 1시간 후 재입력 요구.
/// - 개인 비밀번호(Personal): 인가번호 + "!@@" (예: 인가번호 000 → "000!@@")
class AppConfig {
  /// 앱 표시 제목
  static const String appTitle = 'TSAK.KR';

  /// 프로그램 버전 / 업데이트 날짜
  static const String appVersion = '1.0.0';
  static const String appUpdated = '2025.09.24';

  /// ── [turn69] 마스터 비밀번호 — 하드코딩 상수에서 **런타임 보관**으로 전환 ──
  ///
  /// ## 왜 바꿨나 (실제 사고)
  ///  종전에는 `static const String masterPassword = '...'` 로 **앱에 박아** 두고
  ///  그 값을 그대로 서버에 보냈다(`grantSession(master: ...)`, `setServerPaused` 등).
  ///  그런데 서버는 이제 비밀번호를 **해시**로 보관하고 사용자가 바꿀 수 있다.
  ///  → 상수가 낡는 순간 **마스터 전용 기능이 전부 401** 이 된다
  ///     (백업·복원·서버 중지·회원 강제변경·접속기록 …).
  ///  게다가 앱 번들에 평문이 남아 있어, 번들을 받은 사람이 마스터가 될 수 있었다.
  ///
  /// ## 지금 규칙
  ///   · 마스터 **인증은 서버가 판정**한다(앱은 정답을 모른다).
  ///   · 로그인에 성공하면 그 입력값을 `_masterCredential` 에 담아
  ///     이후 서버 호출에만 재사용한다(메모리, 앱 종료 시 소멸).
  ///   · `legacyMasterPassword` 는 **서버에 닿지 못하는 오프라인** 상황의
  ///     최후 폴백일 뿐이며, NAS 모드에서는 먼저 쓰지 않는다.
  static const String legacyMasterPassword = 'Corbuser7!@@';

  static String _masterCredential = '';

  /// 이 실행에서 실제로 인증된 마스터 비밀번호(없으면 빈 문자열).
  static String get masterCredential => _masterCredential;

  /// 로그인 성공 시 호출 — 이후 서버 호출에 재사용된다.
  static void setMasterCredential(String v) {
    _masterCredential = v;
  }

  /// 잠금/로그아웃 시 반드시 비운다.
  static void clearMasterCredential() {
    _masterCredential = '';
  }

  /// 서버 호출에 실어 보낼 마스터 값.
  ///  인증된 값이 있으면 그것을, 없으면 레거시 값(오프라인 폴백)을 쓴다.
  static String get masterPassword =>
      _masterCredential.isNotEmpty ? _masterCredential : legacyMasterPassword;

  /// 영구 마스터 인가번호 — 이 번호는 '개인 권한'으로 로그인해도 앱이 마스터로
  ///  승격해 주던 예외 목록이다.
  ///
  /// ── [요구 2026-10-26] 415 의 영구 마스터 권한 삭제 ─────────────────────
  ///  사용자 지시: "415호의 마스터 영구권한 삭제할 것"
  ///  · 이제 415 는 **일반 인가자**(tiger415 / 415!@@) 로만 동작한다.
  ///  · 마스터 기능은 마스터 탭에서 **마스터 비밀번호**로 로그인해야 한다.
  ///  · 프록시(PERMANENT_MASTERS)도 같은 값(빈 집합)으로 맞춰 두었다.
  ///    ⚠️ 한쪽만 바꾸면 "앱은 마스터 / 서버는 아님" 이 되어 마스터 전용 API
  ///       (비번 조회·접속기록·강제 변경)가 조용히 401 로 실패한다.
  ///  · 되살리려면 여기에 번호를 다시 넣고 프록시도 같이 고쳐야 한다.
  static const Set<String> permanentMasterNumbers = <String>{};

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

  /// NAS 프록시 서버 주소.
  ///
  /// - **웹**: 비어 있으면 웹과 동일한 origin 사용 → 상대경로(`/api/...`).
  /// - **네이티브(APK)**: 빌드 시 `--dart-define=SERVER_BASE=https://...` 로
  ///   주입한다. (안드로이드에서는 상대경로 호스트가 없어 반드시 절대 URL 필요)
  ///   마스터는 설정 화면에서 언제든 덮어쓸 수 있다(SharedPreferences 우선).
  static const String defaultServerBase = String.fromEnvironment(
    'SERVER_BASE',
    defaultValue: '',
  );

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
  static const String kSessionSid = 'auth_session_sid'; // 서버 발급 세션토큰
  static const String kAuthCorps = 'auth_corps'; // 로그인 소속('tsak'|'eunha')
  static const String kAdminEmail = 'admin_email';
  // 영구 마스터 권한 선택 — true=마스터 권한, false=개인 권한.
  //  (목록이 비어 있으면 아무 효과 없음. 나중에 번호를 다시 넣을 때를 위해 유지)
  static const String kPermanentMasterMode = 'permanent_master_mode';
}
