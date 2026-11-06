// 웹 전용 구현 (dart:js_interop / package:web).
// file_picker 의 DOM 부착 버그를 우회하여 image_picker_for_web 과 동일한
// 검증된 `document.body.append()` + `<input type=file>` 패턴을 사용한다.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_pick.dart';

/// file_picker 의 input 컨테이너(id)와 동일한 노드를 사용해 재사용/정리 이슈를
/// 피하기 위해 별도의 컨테이너를 둔다.
const String _kContainerId = '__tsak_file_inputs';

web.Element _ensureContainer() {
  web.Element? target = web.document.querySelector('#$_kContainerId');
  if (target == null) {
    final web.Element el = web.document.createElement('flt-tsak-file-inputs')
      ..id = _kContainerId;
    web.document.body!.append(el);
    target = el;
  }
  return target;
}

String _acceptOf(List<String> exts) {
  if (exts.isEmpty) return '';
  return exts.map((e) => '.${e.replaceAll('.', '')}').join(',');
}

Future<List<PickedFileData>> platformPickDataFiles({
  List<String> allowedExtensions = const [],
  bool allowMultiple = false,
  String? dialogTitle,
}) async {
  final completer = Completer<List<PickedFileData>>();

  final web.HTMLInputElement input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = allowMultiple
    ..style.display = 'none';
  final accept = _acceptOf(allowedExtensions);
  if (accept.isNotEmpty) input.accept = accept;

  var done = false;
  // ── [버그 수정 2026-11-04] "여러 파일 선택이 안 된다" ─────────────────
  //  종전에는 `focus` 리스너가 **800ms 뒤 무조건 빈 결과로 완료**시켰다.
  //  그런데 파일을 고른 직후 브라우저는 창으로 포커스를 돌려주므로,
  //  파일을 읽는 중(특히 큰 파일)에 이 타이머가 먼저 발동해
  //  `complete(const [])` 를 호출했고, 뒤늦게 읽힌 결과는 버려졌다.
  //  실측 증상: 작은 파일 1개는 되고, 큰 파일을 여러 개 고르면
  //  아무 일도 일어나지 않음(= 사용자에게는 "여러 개 선택이 안 된다").
  //
  //  수정: 파일을 읽기 **시작했으면** 취소가 아니다 → `picked` 플래그로
  //  보호하고, 타이머도 800ms → 2500ms 로 늘려 넉넉히 기다린다.
  var picked = false;

  void finish(List<PickedFileData> files) {
    if (done) return;
    done = true;
    if (!completer.isCompleted) completer.complete(files);
  }

  input.onchange = (web.Event event) {
    picked = true; // 이 시점 이후로는 '취소'가 아니다.
    final target = event.target as web.HTMLInputElement?;
    final files = target?.files;
    if (files == null || files.length == 0) {
      finish(const []);
      return;
    }
    _readAll(files).then((f) => finish(f)).catchError((Object e) {
      // 읽기 실패는 '빈 선택'이 아니라 **오류로 알린다**.
      //  조용히 빈 배열을 돌려주면 화면은 아무 반응이 없어 원인을 못 찾는다.
      if (!done) {
        done = true;
        if (!completer.isCompleted) completer.completeError(e);
      }
    });
  }.toJS;

  input.oncancel = (web.Event _) {
    finish(const []);
  }.toJS;

  // 포커스 복귀 = 취소로 판단 (file_picker 와 동일한 안전장치).
  //  단, 파일을 이미 골랐다면(picked) 취소가 아니다.
  final focusListener = (web.Event _) {
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (!picked && !done && !completer.isCompleted) finish(const []);
    });
  }.toJS;
  web.window.addEventListener('focus', focusListener);

  // DOM 에 붙이고 클릭해야 브라우저가 파일 창을 연다.
  final container = _ensureContainer();
  container.replaceChildren(<JSAny>[].toJS);
  container.append(input);
  input.click();

  final result = await completer.future;
  web.window.removeEventListener('focus', focusListener);
  container.replaceChildren(<JSAny>[].toJS);
  return result;
}

Future<List<PickedFileData>> _readAll(web.FileList files) async {
  // ── [같은 버그의 예방 조치 2026-11-04] ──────────────────────────────
  //  `input.files` 는 **live FileList** 다. 읽는 도중 input 이 DOM 에서
  //  떨어지거나 value 가 비워지면 length 가 0 이 되어, 남은 파일이
  //  조용히 사라진다(웹에서 "여러 개 골랐는데 1개만 올라간다"의 원인).
  //  → 시작 전에 **배열로 스냅샷**을 떠서 그 사본으로 읽는다.
  final list = <web.File>[];
  for (var i = 0; i < files.length; i++) {
    final web.File? f = files.item(i);
    if (f != null) list.add(f);
  }
  final out = <PickedFileData>[];
  for (final f in list) {
    final bytes = await _readBytes(f);
    out.add(PickedFileData(name: f.name, bytes: bytes));
  }
  return out;
}

Future<Uint8List> _readBytes(web.File file) {
  final completer = Completer<Uint8List>();
  final reader = web.FileReader();
  reader.onloadend = (web.Event _) {
    final result = reader.result;
    if (result.isA<JSArrayBuffer>()) {
      completer.complete((result as JSArrayBuffer).toDart.asUint8List());
    } else {
      completer.complete(Uint8List(0));
    }
  }.toJS;
  reader.onerror = (web.Event _) {
    if (!completer.isCompleted) completer.complete(Uint8List(0));
  }.toJS;
  reader.readAsArrayBuffer(file);
  return completer.future;
}
