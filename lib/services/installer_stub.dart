// 웹 등 네이티브 설치가 불가능한 환경용 스텁.
//
// 웹에서는 APK 자체 설치가 불가하므로 모두 무동작/실패 신호를 준다.
// (호출부는 '설치 불가'로 간주하고 안내만 한다.)

/// APK 를 내려받아 임시경로를 반환한다. 웹에서는 빈 문자열.
Future<String> downloadApkToTemp(
  String url, {
  void Function(int received, int total)? onProgress,
}) async => '';

/// 파일의 SHA-256 이 기대값과 같은지 검사. 웹에서는 항상 false.
Future<bool> verifyFileSha256(String path, String expectedHex) async => false;

/// APK 설치 화면을 띄운다. 웹에서는 항상 false.
Future<bool> installApkFile(String path) async => false;

/// '출처를 알 수 없는 앱 설치' 권한이 있는지. 웹은 개념 없음 → false.
Future<bool> canRequestInstall() async => false;

/// 설치 권한 설정 화면을 연다. 웹에서는 무동작.
Future<void> openInstallPermissionSettings() async {}

/// 이 런타임이 APK 자체 업데이트를 지원하는가? (웹=아니오)
bool get supportsApkSelfUpdate => false;

/// 임시 경로를 비운다(이전 다운로드 잔여물 정리). 웹에서는 무동작.
Future<void> clearTempDownloads() async {}
