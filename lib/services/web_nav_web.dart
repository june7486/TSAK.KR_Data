import 'dart:js_interop';

// 전역 document / location / 브라우저 캐시 API.
@JS('document')
external _Document get _document;

@JS('location')
external _Location get _location;

@JS('setTimeout')
external int _setTimeout(JSFunction cb, int ms);

@JS('caches')
external _Caches get _caches;

@JS('navigator')
external _Navigator get _navigator;

extension type _Location(JSObject _) implements JSObject {
  external set href(String v);
  external void reload();
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

// Cache Storage API
extension type _Caches(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSString>> keys();
  external JSPromise<JSBoolean> delete(JSString key);
}

// navigator.serviceWorker
extension type _Navigator(JSObject _) implements JSObject {
  external _ServiceWorkerContainer get serviceWorker;
}

extension type _ServiceWorkerContainer(JSObject _) implements JSObject {
  external JSPromise<JSArray<_ServiceWorkerRegistration>> getRegistrations();
}

extension type _ServiceWorkerRegistration(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> unregister();
}

@JS('localStorage')
external _Storage get _localStorage;

extension type _Storage(JSObject _) implements JSObject {
  external void removeItem(JSString key);
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

/// 브라우저에 캐시된 앱 자산(Cache Storage·서비스워커)을 정리한다.
///
/// 최신 배포(업데이트)가 반영되지 않을 때 사용한다. 사용자 데이터(Hive 등)는
/// 건드리지 않고, "낡은 정적 자산"만 지운다. 실제 적용은 [reloadPage] 호출로
/// 이어진다.
Future<String> clearAppCache() async {
  int clearedCaches = 0;
  int clearedWorkers = 0;

  // 1) Cache Storage 비우기 (서비스워커가 캐싱한 앱 셸/자산)
  try {
    final List<JSString> keys = (await _caches.keys().toDart).toDart;
    for (final k in keys) {
      try {
        await _caches.delete(k).toDart;
        clearedCaches++;
      } catch (_) {}
    }
  } catch (_) {}

  // 2) 서비스워커 해제 (구버전 워커가 요청을 가로채는 것을 차단)
  try {
    final List<_ServiceWorkerRegistration> regs =
        (await _navigator.serviceWorker.getRegistrations().toDart).toDart;
    for (final r in regs) {
      try {
        await r.unregister().toDart;
        clearedWorkers++;
      } catch (_) {}
    }
  } catch (_) {}

  // 3) 버전 표식 초기화 — 페이지 로드 시 최신 버전을 다시 기록하게 함
  try {
    _localStorage.removeItem('tsak_app_version'.toJS);
  } catch (_) {}

  if (clearedCaches == 0 && clearedWorkers == 0) {
    return '캐시를 새로 고칩니다 (저장된 캐시 없음)';
  }
  return '캐시 $clearedCaches개 · 서비스워커 $clearedWorkers개 정리됨';
}

/// 현재 페이지를 새로 고침한다.
void reloadPage() {
  try {
    _location.reload();
  } catch (_) {}
}
