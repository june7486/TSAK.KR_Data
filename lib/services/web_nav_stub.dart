// 비웹(모바일·데스크톱 네이티브)용 스텁.
import 'dart:typed_data';

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
void openPrintableHtml(String html, {bool autoPrint = false}) {}

/// 파일 다운로드 — 네이티브에서는 no-op(호출부에서 파일 저장 API 사용).
/// 반환: 웹과 동일한 시그니처(bool)를 유지해야 컴파일된다.
bool downloadTextFile(String content, String filename, String mime) => false;

/// 바이너리 파일 다운로드 — 네이티브에서는 no-op.
void downloadBytesFile(Uint8List bytes, String filename, String mime) {}

/// 임의 파일을 외부 앱/뷰어로 연다 — 웹 전용.
/// 네이티브에서는 새 탭 개념이 없어 false 를 반환한다(호출부가 OS 공유/열기 시트로 폴백).
bool openFileExternally(Uint8List bytes, String filename, String mime) => false;

/// 네이티브는 OS 저장 대화상자를 file_saver 가 처리하므로 위치 선택 불필요.
bool get supportsSaveFilePicker => false;

/// 네이티브(안드로이드·아이폰)는 OS 공유 시트를 항상 쓸 수 있다.
/// (아이폰 사진 저장 = 공유 시트 → '이미지 저장')
bool get webSupportsShareFiles => false;

/// 네이티브에서는 애플 '웹' 구분이 무의미하므로 false.
bool get isAppleMobileWeb => false;

/// 네이티브에서는 대상 아님(항상 false).
Future<bool> saveViaFilePicker(
  Uint8List bytes,
  String filename,
  String mime,
) async => false;

/// 네이티브에는 자동 재로드가 없으므로 항상 허용(사실상 미사용).
bool guardAutoReloadOnce() => true;

/// 카카오 우편번호 — 웹 전용. 네이티브에서는 null 을 반환한다.
Future<String?> openKakaoPostcode() async => null;
