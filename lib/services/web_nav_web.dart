import 'dart:js_interop';

// 전역 document / window 객체.
@JS('document')
external _Document get _document;

@JS('location')
external _Location get _location;

@JS('setTimeout')
external int _setTimeout(JSFunction cb, int ms);

extension type _Location(JSObject _) implements JSObject {
  external set href(String v);
}

extension type _Document(JSObject _) implements JSObject {
  external _Element createElement(String tag);
  external JSObject get body;
}

extension type _Element(JSObject _) implements JSObject {
  external _Style get style;
  external set src(String v);
  external void remove();
}

extension type _Style(JSObject _) implements JSObject {
  external set display(String v);
}

extension type _Body(JSObject _) implements JSObject {
  external void appendChild(_Element el);
}

bool get isWebRuntime => true;

/// 현재 탭에서 URL(커스텀 스킴 포함)로 이동을 시도한다.
///
/// 모바일 브라우저에서 `supertoss://` 같은 앱 스킴은 `location.href` 로
/// 지정하면 앱이 열린다. 일부 브라우저는 숨은 iframe 방식이 더 안정적이라
/// 둘 다 시도한다. (사용자 제스처 안에서만 허용)
void openUrlInTab(String url) {
  // 1) 숨은 iframe 트릭 (iOS Safari 등에서 안정적)
  try {
    final ifr = _document.createElement('iframe');
    ifr.style.display = 'none';
    ifr.src = url;
    (_document.body as _Body).appendChild(ifr);
    _setTimeout((() => ifr.remove()).toJS, 1500);
  } catch (_) {}
  // 2) 직접 이동 (Android Chrome 등에서 안정적)
  try {
    _location.href = url;
  } catch (_) {}
}
