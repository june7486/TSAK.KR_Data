// 크로스플랫폼 파일 선택 헬퍼.
//
// 웹에서는 file_picker 플러그인의 `body.children.add()` 가 일부 Flutter Web
// SDK에서 no-op(.toString())로 컴파일되어 <input type=file> 이 DOM에 붙지
// 않아 파일 선택 창이 열리지 않는 문제가 있다. image_picker_for_web 이 쓰는
// 검증된 `document.body.append()` 패턴으로 직접 구현한 선택기를 사용한다.
//
// 그 외 플랫폼(Android/iOS/데스크톱)에서는 file_picker 플러그인을 그대로 쓴다.
import 'dart:typed_data';

import 'file_pick_stub.dart'
    if (dart.library.js_interop) 'file_pick_web.dart'
    if (dart.library.io) 'file_pick_io.dart';

/// 사용자가 선택한 파일 한 건.
class PickedFileData {
  const PickedFileData({
    required this.name,
    required this.bytes,
    this.path,
  });

  /// 파일 이름 (확장자 포함).
  final String name;

  /// 파일 내용 바이트. (웹/모바일 모두 채움)
  final Uint8List bytes;

  /// 네이티브 플랫폼에서의 실제 경로 (웹은 null).
  final String? path;
}

/// 플랫폼에 맞는 파일 선택 창을 띄우고 선택 결과를 반환한다.
/// [allowedExtensions] 가 비어 있으면 모든 파일을 허용한다.
/// 취소하거나 아무것도 선택하지 않으면 빈 리스트를 반환한다.
Future<List<PickedFileData>> pickDataFiles({
  List<String> allowedExtensions = const [],
  bool allowMultiple = false,
  String? dialogTitle,
}) {
  return platformPickDataFiles(
    allowedExtensions: allowedExtensions,
    allowMultiple: allowMultiple,
    dialogTitle: dialogTitle,
  );
}
