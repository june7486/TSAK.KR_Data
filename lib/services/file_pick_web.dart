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

  void finish(List<PickedFileData> files) {
    if (done) return;
    done = true;
    if (!completer.isCompleted) completer.complete(files);
  }

  input.onchange = (web.Event event) {
    final target = event.target as web.HTMLInputElement?;
    final files = target?.files;
    if (files == null || files.length == 0) {
      finish(const []);
      return;
    }
    _readAll(files).then((f) => finish(f)).catchError((Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    });
  }.toJS;

  input.oncancel = (web.Event _) {
    finish(const []);
  }.toJS;

  // 포커스 복귀 = 취소로 판단 (file_picker 와 동일한 안전장치).
  final focusListener = (web.Event _) {
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!done && !completer.isCompleted) finish(const []);
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
  final out = <PickedFileData>[];
  for (var i = 0; i < files.length; i++) {
    final web.File? f = files.item(i);
    if (f == null) continue;
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
