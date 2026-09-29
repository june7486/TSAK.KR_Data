import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

import 'web_nav.dart';

/// 파일 저장 공용 헬퍼.
///
/// - **웹(PC 브라우저)**: Blob + `<a download>` 로 저장한다.
///   PC 기본 다운로드 폴더로 바로 저장되며, 별도 다이얼로그 없이 즉시 저장된다.
///   (file_saver 의 웹 구현이 일부 브라우저에서 동작하지 않는 문제를 회피)
/// - **네이티브(안드로이드 등)**: file_saver 로 저장한다.
///
/// 새 저장 기능을 추가할 때도 이 헬퍼를 사용한다(규칙).
Future<void> saveBytes({
  required Uint8List bytes,
  required String name,
  required String ext,
  required String mime,
  MimeType? mimeType,
}) async {
  if (isWebRuntime) {
    downloadBytesFile(bytes, '$name.$ext', mime);
    return;
  }
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    ext: ext,
    mimeType: mimeType ?? MimeType.other,
  );
}

/// 문자열(CSV·TXT·HTML) 저장 — 웹에서 확실히 동작.
Future<void> saveText({
  required String content,
  required String name,
  required String ext,
  required String mime,
  MimeType? mimeType,
}) async {
  if (isWebRuntime) {
    downloadTextFile(content, '$name.$ext', mime);
    return;
  }
  await FileSaver.instance.saveFile(
    name: name,
    bytes: Uint8List.fromList(content.codeUnits),
    ext: ext,
    mimeType: mimeType ?? MimeType.text,
  );
}

/// 이미지(JPG/PNG) 저장 — 규칙(#14): **기본 저장 위치 = 기기 기본**.
/// - 스마트폰(안드로이드 등): 사진/갤러리 폴더로 저장.
/// - PC(웹): 브라우저 기본 다운로드(Downloads) 폴더로 저장.
/// 사용자가 위치를 바꾸려면 [preferGallery]를 false 로 주거나 OS 저장 대화상자를 쓴다.
Future<void> saveImageBytes({
  required Uint8List bytes,
  required String name,
  String ext = 'jpg',
}) async {
  // 웹은 항상 브라우저 기본(Downloads) 경로로 내려받는다.
  if (isWebRuntime) {
    downloadBytesFile(bytes, '$name.$ext', 'image/$ext');
    return;
  }
  // 네이티브는 file_saver 가 OS 저장 대화상자를 띄워 사용자가 위치 선택 가능.
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    ext: ext,
    mimeType: ext == 'png' ? MimeType.png : MimeType.jpeg,
  );
}
