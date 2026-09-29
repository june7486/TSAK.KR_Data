import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

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
  external String? get origin;
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
  external void click();
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

@JS('sessionStorage')
external _SessionStorage get _sessionStorage;

extension type _SessionStorage(JSObject _) implements JSObject {
  external String? getItem(JSString key);
  external void setItem(JSString key, JSString value);
}

@JS('window')
external _Window get _window;

extension type _Window(JSObject _) implements JSObject {
  external void open(String url, String target);
  external double get innerWidth;
}

// fetch — 캐시 무시 강제 재다운로드(cache:'reload')용
@JS('fetch')
external JSPromise<JSAny> _fetch(String url, JSObject opts);

JSObject _cacheReloadOpts() =>
    <String, Object?>{'cache': 'reload'}.jsify() as JSObject;

// Blob / URL (인쇄용 문서 생성)
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, JSObject options);
}

extension type _URL._(JSObject _) implements JSObject {
  external static String createObjectURL(JSObject blob);
  external static void revokeObjectURL(String url);
}

extension type _Anchor(JSObject _) implements JSObject {
  external set href(String v);
  external set download(String v);
  external void click();
  external void remove();
}

/// 텍스트(HTML/CSV 등)를 파일로 다운로드한다. (Blob + <a download>)
/// 반환: 다운로드를 트리거했으면 true.
///
/// ## 버그 수정 (요구 p.28: "파일 생성 자체가 안 됨")
/// 기존에는 `<a>` 를 **DOM 에 붙이지 않고** `.click()` 만 호출해,
/// 사파리·파이어폭스·일부 크롬 환경에서 **다운로드가 트리거되지 않았다**
/// (에러도 조용히 catch 로 삼켜져 "아무 일도 안 일어나는" 증상).
/// `downloadBytesFile` 과 동일하게 DOM 에 붙인 뒤 클릭하고, 끝나면 정리한다.
bool downloadTextFile(String content, String filename, String mime) {
  try {
    final parts = <JSAny>[content.toJS].toJS;
    final optMap = <String, String>{'type': mime};
    final blob = _Blob(parts, optMap.jsify()! as JSObject);
    final url = _URL.createObjectURL(blob);
    final a = _document.createElement('a') as _Anchor;
    a.href = url;
    a.download = filename;
    // DOM 에 붙여야 일부 브라우저(사파리/파폭)에서 클릭 다운로드가 동작한다.
    try {
      (_document.body as _Body).appendChild(a as _Element);
    } catch (_) {}
    a.click();
    _setTimeout((() {
      try {
        a.remove();
      } catch (_) {}
      try {
        _URL.revokeObjectURL(url);
      } catch (_) {}
    }).toJS, 4000);
    return true;
  } catch (_) {
    return false;
  }
}

/// 바이너리(엑셀·PDF·이미지 등)를 파일로 다운로드한다.
/// (Blob + <a download>) — PC 브라우저에서는 기본 저장 폴더(다운로드)로 저장된다.
void downloadBytesFile(Uint8List bytes, String filename, String mime) {
  try {
    final parts = <JSAny>[bytes.toJS].toJS;
    final optMap = <String, String>{'type': mime};
    final blob = _Blob(parts, optMap.jsify()! as JSObject);
    final url = _URL.createObjectURL(blob);
    final a = _document.createElement('a') as _Anchor;
    a.href = url;
    a.download = filename;
    // DOM 에 붙여야 일부 브라우저(사파리/파폭)에서 클릭 다운로드가 동작한다.
    try {
      (_document.body as _Body).appendChild(a as _Element);
    } catch (_) {}
    a.click();
    _setTimeout(
      (() {
        try {
          a.remove();
        } catch (_) {}
        try {
          _URL.revokeObjectURL(url);
        } catch (_) {}
      }).toJS,
      4000,
    );
  } catch (_) {}
}

// ─────────────────────────────────────────────────────────────
// File System Access API — 저장 폴더/위치를 사용자가 직접 선택.
//  (Chromium 계열 브라우저: 크롬·엣지·웨일 등)
//  지원하지 않는 브라우저(사파리/파폭)와 사용자 취소 시 null 을 반환하여
//  호출부가 기존 기본 다운로드(Blob) 방식으로 폴백하게 한다.
// ─────────────────────────────────────────────────────────────

@JS('showSaveFilePicker')
external JSPromise<JSObject> _showSaveFilePicker(JSObject options);

/// 이 브라우저가 '저장 위치 선택'을 지원하는지 (함수 존재 여부).
bool get supportsSaveFilePicker {
  try {
    final v = globalContext.getProperty('showSaveFilePicker'.toJS);
    return v.isA<JSFunction>();
  } catch (_) {
    return false;
  }
}

extension type _FileHandle(JSObject _) implements JSObject {
  external JSPromise<_Writable> createWritable();
}

extension type _Writable(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSAny data);
  external JSPromise<JSAny?> close();
}

/// [showSaveFilePicker] 로 저장 위치를 **사용자가 직접 고르게** 한 뒤 저장한다.
///
/// 반환: true=저장됨, false=취소/미지원(호출부는 기본 다운로드로 폴백).
Future<bool> saveViaFilePicker(
  Uint8List bytes,
  String filename,
  String mime,
) async {
  try {
    final opts =
        <String, Object?>{
              'suggestedName': filename,
              'types': [
                <String, Object?>{
                  'description': '파일',
                  'accept': <String, List<String>>{
                    mime.isEmpty ? 'application/octet-stream' : mime: <String>[
                      filename.contains('.')
                          ? '.${filename.split('.').last}'
                          : '',
                    ],
                  },
                },
              ],
            }.jsify()!
            as JSObject;
    final handle = await _showSaveFilePicker(opts).toDart;
    final writable = await (_FileHandle(handle)).createWritable().toDart;
    await writable.write(bytes.toJS).toDart;
    await writable.close().toDart;
    return true;
  } catch (e) {
    // AbortError(사용자 취소) / 지원 안 함 → false (폴백)
    return false;
  }
}

/// 인쇄용 HTML 문서를 새 탭/창에서 열어 사용자가 인쇄 또는 PDF 저장할 수
/// 있게 한다. (Blob URL + window.open)
///
/// [autoPrint] 가 true 이면 문서 로드 후 자동으로 인쇄(=PDF 저장) 대화상자를
/// 띄운다. 주문내역 등 **기본 출력 형식이 PDF**인 문서에서 사용한다.
void openPrintableHtml(String html, {bool autoPrint = false}) {
  var doc = _withBackButton(html);
  if (autoPrint && !doc.contains('tsak-autoprint')) {
    const script =
        '<script class="tsak-autoprint">window.addEventListener("load",function(){'
        'setTimeout(function(){try{window.print();}catch(e){}},600);});</script>';
    if (doc.contains('</body>')) {
      doc = doc.replaceFirst('</body>', '$script</body>');
    } else {
      doc = '$doc$script';
    }
  }
  try {
    final parts = <JSAny>[doc.toJS].toJS;
    final opts = <String, String>{'type': 'text/html;charset=utf-8'}.jsify()!;
    final blob = _Blob(parts, opts as JSObject);
    final url = _URL.createObjectURL(blob);
    _window.open(url, '_blank');
  } catch (_) {
    try {
      _window.open(
        'data:text/html;charset=utf-8,${Uri.encodeComponent(doc)}',
        '_blank',
      );
    } catch (_) {}
  }
}

/// 새 창에서 연 모든 출력물(인쇄·PDF·이미지 등)에 **"← 돌아가기" 버튼**을
/// 자동으로 붙인다. (요구 p.27·p.28: "새창이 열리면 꼭 돌아가기 버튼을 넣도록 해")
///
///  · 스마트폰 브라우저에는 뒤로가기 버튼이 없어 새 창에 갇히는 문제를 막는다.
///  · history 가 있으면 `history.back()`, 없으면 창을 닫고, 그것도 안 되면
///    원래(앱) URL 로 이동한다 — 어떤 브라우저에서도 빠져나올 수 있게.
///  · 이미 버튼이 있으면(tsak-backbar) 중복 삽입하지 않는다.
String _withBackButton(String html) {
  if (html.contains('tsak-backbar')) return html;
  const bar = '''
<style class="tsak-backbar">
#tsak-backbar{position:fixed;left:12px;top:12px;z-index:2147483647;
  display:inline-flex;align-items:center;gap:6px;
  padding:9px 15px;border-radius:24px;
  background:#5B2C8D;color:#fff;border:0;cursor:pointer;
  font:700 14px/1 -apple-system,BlinkMacSystemFont,'Apple SD Gothic Neo','Noto Sans KR',sans-serif;
  box-shadow:0 3px 12px rgba(0,0,0,.28)}
#tsak-backbar:hover{background:#46216E}
@media print{#tsak-backbar{display:none}}
</style>
<button id="tsak-backbar" class="tsak-backbar" type="button"
  onclick="try{if(window.history.length>1){window.history.back();return;}}catch(e){}
           try{window.close();}catch(e){}
           setTimeout(function(){try{location.href=document.referrer||'/';}catch(e){}},120);">
  ← 돌아가기
</button>
''';
  if (html.contains('</body>')) {
    return html.replaceFirst('</body>', '$bar</body>');
  }
  return html + bar;
}

/// 자동 재로드를 세션당 1회로 제한한다. (허용되면 true)
///
/// 구버전 감지 → 캐시삭제 → 재로드가 반복(루프)되지 않도록 막는다.
bool guardAutoReloadOnce() {
  try {
    const key = 'tsak_auto_reload';
    if (_sessionStorage.getItem(key.toJS) == '1') return false;
    _sessionStorage.setItem(key.toJS, '1'.toJS);
    return true;
  } catch (_) {
    return true;
  }
}

bool get isWebRuntime => true;

/// 모바일(터치) 브라우저인지 — 좁은 화면/터치 포인트로 판정.
///
/// 데스크톱(PC) 웹과 모바일 웹은 앱 스킴 처리 방식이 달라 구분이 필요하다.
bool get isMobileWeb {
  try {
    final w = _window.innerWidth;
    return w <= 820;
  } catch (_) {
    return false;
  }
}

/// 현재 페이지의 origin (예: https://example.com). 실패 시 빈 문자열.
String webOrigin() {
  try {
    final o = _location.origin;
    return o ?? '';
  } catch (_) {
    return '';
  }
}

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

/// 커스텀 스킴을 **새 탭/새 창**으로 연다 (PC 웹 전용 처리).
///
/// PC 브라우저는 `location.href` 로 커스텀 스킴을 지정하면 "알 수 없는
/// 프로토콜" 오류로 **현재 페이지가 망가진다.** 따라서 먼저 숨은 iframe
/// 으로 앱 실행을 유도하고(현재 탭 보존), 그래도 반응이 없으면 새 창으로
/// 한 번 더 시도한다. 앱 실행이 실패해도 현재 탭은 그대로 남는다.
void openUrlInIsolatedTab(String url) {
  // 1) 숨은 iframe — PC에서도 OS 프로토콜 핸들러가 잡으면 앱이 열린다.
  try {
    final ifr = _document.createElement('iframe');
    ifr.style.display = 'none';
    ifr.src = url;
    (_document.body as _Body).appendChild(ifr);
    _setTimeout((() => ifr.remove()).toJS, 1500);
  } catch (_) {}
  // 2) 폴백: 새 창 (현재 페이지를 보존한다)
  try {
    _window.open(url, '_blank');
  } catch (_) {}
}

/// 브라우저 새 탭/새 창으로 URL을 연다. (외부 바로가기용)
void openUrlInNewTab(String url) {
  try {
    _window.open(url, '_blank');
  } catch (_) {
    try {
      _location.href = url;
    } catch (_) {}
  }
}

/// 외부 사이트를 **새 탭으로 확실하게** 연다 (PC 인터넷뱅킹 등).
///
/// 일반 https 주소만 대상으로 한다. 새 창을 열어 현재 앱(SPA) 상태를 보존한다.
/// 팝업 차단으로 실패하면 `location.href` 로 폴백한다.
bool openExternalUrl(String url) {
  try {
    _window.open(url, '_blank');
    return true;
  } catch (_) {
    try {
      _location.href = url;
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// 브라우저에 캐시된 앱 자산(Cache Storage·서비스워커)을 정리한다.
///
/// 최신 배포(업데이트)가 반영되지 않을 때 사용한다. 사용자 데이터(Hive 등)는
/// 건드리지 않고, "낡은 정적 자산"만 지운다. 실제 적용은 [reloadPage] 호출로
/// 이어진다.
Future<String> clearAppCache() async {
  int clearedCaches = 0;
  int clearedWorkers = 0;

  // 0) 아이콘 폰트를 HTTP 캐시까지 무시하고 강제 재다운로드.
  //    → 옛 폰트가 캐시에 남아 픽토그램이 누락되는 문제를 근본 해결.
  try {
    await _fetch(
      'assets/fonts/MaterialIcons-Regular.otf',
      _cacheReloadOpts(),
    ).toDart;
  } catch (_) {}

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

// ─────────────────────────────────────────────────────────────
// 카카오 우편번호(주소검색)
//  window.tsakOpenKakaoPostcode(cb) 브리지를 Dart 에서 호출한다.
//  (브리지 구현은 web/index.html 참고)
// ─────────────────────────────────────────────────────────────

@JS('tsakOpenKakaoPostcode')
external void _tsakOpenKakaoPostcode(JSFunction cb);

extension type _KakaoResult(JSObject _) implements JSObject {
  external String? get zonecode;
  external String? get address;
}

/// 카카오 우편번호 팝업을 연다.
/// 선택 시 `[우편번호] 도로명주소` 문자열을, 취소/실패 시 null 을 반환한다.
Future<String?> openKakaoPostcode() {
  final completer = Completer<String?>();
  try {
    void done(JSAny? data) {
      if (completer.isCompleted) return;
      if (data == null || data.isUndefinedOrNull) {
        completer.complete(null);
        return;
      }
      try {
        final obj = data as _KakaoResult;
        final zip = obj.zonecode ?? '';
        final addr = (obj.address ?? '').trim();
        if (addr.isEmpty) {
          completer.complete(null);
        } else {
          completer.complete(zip.isNotEmpty ? '[$zip] $addr' : addr);
        }
      } catch (_) {
        completer.complete(null);
      }
    }

    _tsakOpenKakaoPostcode(done.toJS);
  } catch (_) {
    if (!completer.isCompleted) completer.complete(null);
  }
  return completer.future;
}
