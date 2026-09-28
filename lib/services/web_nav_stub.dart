// 비웹(모바일·데스크톱 네이티브)용 스텁.
bool get isWebRuntime => false;

/// 네이티브는 웹 구분이 무의미하므로 false.
bool get isMobileWeb => false;

/// 네이티브에서는 브라우저 origin 개념이 없다(호출부에서 NAS 주소로 대체).
String webOrigin() => '';

/// 웹이 아닌 환경에서는 아무 것도 하지 않는다.
void openUrlInTab(String url) {}

/// 네이티브에서는 별도 새창 개념이 없어 아무 것도 하지 않는다.
/// (호출부에서 url_launcher 로 기본 브라우저를 연다.)
void openUrlInNewTab(String url) {}

/// 네이티브에는 브라우저 새 탭 개념이 없다 → 실패 신호(false)를 준다.
bool openExternalUrl(String url) => false;

/// 네이티브에서는 격리 탭 개념이 없다(호출부에서 launchUrl 사용).
void openUrlInIsolatedTab(String url) {}

/// 웹이 아닌 환경에서는 브라우저 캐시가 없으므로 정리할 것도 없다.
Future<String> clearAppCache() async => '모바일 앱에서는 캐시 정리가 필요하지 않습니다';

/// 웹이 아닌 환경에서는 페이지 새로고침 개념이 없다.
void reloadPage() {}

/// 인쇄용 HTML 열기 — 네이티브에서는 no-op(호출부에서 별도 처리).
void openPrintableHtml(String html) {}

/// 파일 다운로드 — 네이티브에서는 no-op(호출부에서 클립보드 폴백).
void downloadTextFile(String content, String filename, String mime) {}

/// 네이티브에는 자동 재로드가 없으므로 항상 허용(사실상 미사용).
bool guardAutoReloadOnce() => true;
