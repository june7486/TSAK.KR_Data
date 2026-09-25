// 웹/비웹 공용 인터페이스 — 조건부 export.
//
// 웹 빌드에서는 실제 location 이동 구현을, 그 외(안드로이드 등)에서는
// 아무 동작도 하지 않는 스텁을 사용한다. (dart:js_interop 은 웹 전용)
export 'web_nav_stub.dart'
    if (dart.library.js_interop) 'web_nav_web.dart';
