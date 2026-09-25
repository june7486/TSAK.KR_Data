import 'dart:js_interop';

// 전역 location 객체 (window.location).
@JS('location')
external _Location get _location;

extension type _Location(JSObject _) implements JSObject {
  external set href(String v);
}

bool get isWebRuntime => true;

/// 현재 탭에서 URL(커스텀 스킴 포함)로 이동을 시도한다.
///
/// 모바일 브라우저에서 `supertoss://` 같은 앱 스킴을 `location.href` 로
/// 지정하면, 해당 앱이 설치돼 있을 때 앱이 열린다. (사용자 제스처 안에서만 허용)
void openUrlInTab(String url) {
  _location.href = url;
}
