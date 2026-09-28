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
