// 설치(APK) 실행 — 네이티브 전용 구현으로 연결하는 조건부 export.
//
// · 안드로이드/데스크톱(dart:io 사용 가능) → installer_io.dart (실제 다운로드·설치)
// · 웹(dart:io 없음)                        → installer_stub.dart (무동작)
export 'installer_stub.dart' if (dart.library.io) 'installer_io.dart';
