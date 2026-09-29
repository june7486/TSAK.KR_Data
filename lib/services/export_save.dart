/// 파일 저장 통합 헬퍼 (규칙: 기본 출력 = PDF **실제 파일**).
///
/// ## 왜 필요한가 (요구 p.28: "파일 생성 자체가 안 됨")
/// 출력물을 저장할 때 파일마다 제각각 처리해, 어떤 곳은 새 창(인쇄),
/// 어떤 곳은 클립보드 복사로 동작해 **"저장이 안 된다"**는 혼선이 있었다.
/// 이 헬퍼 하나로:
///   1. (크롬/엣지) 사용자가 **저장 위치를 직접 고르게** 하고,
///   2. 미지원 브라우저(사파리/파폭)에서는 **기본 다운로드 폴더**로 저장한다.
///
/// [downloadBytesFile]·[saveViaFilePicker] 를 감싼 얇은 래퍼다.
library;

import 'dart:typed_data';

import 'web_nav.dart';

/// 이 환경이 실제 파일 저장을 지원하는지 (웹 여부).
bool get canSaveFiles => isWebRuntime;

/// [bytes] 를 파일로 저장한다.
///
/// 반환: 저장(트리거)되면 true. 비웹에서는 false(호출부에서 클립보드 폴백).
///
/// [preferPicker] 이 true 이고 브라우저가 지원하면 **저장 위치 선택창**을 띄운다.
/// 지원하지 않거나 사용자가 취소하면 자동으로 기본 다운로드로 폴백한다.
Future<bool> saveBytesAs(
  Uint8List bytes,
  String filename,
  String mime, {
  bool preferPicker = true,
}) async {
  if (!isWebRuntime) return false;
  if (preferPicker && supportsSaveFilePicker) {
    final ok = await saveViaFilePicker(bytes, filename, mime);
    if (ok) return true;
    // 취소/실패 → 기본 다운로드 폴백
  }
  downloadBytesFile(bytes, filename, mime);
  return true;
}

/// 텍스트(HTML/CSV 등)를 파일로 저장한다. 비웹이면 false.
Future<bool> saveTextAs(String content, String filename, String mime) async {
  if (!isWebRuntime) return false;
  return downloadTextFile(content, filename, mime);
}

/// 확장자에 맞는 MIME 타입을 돌려준다.
String mimeForFilename(String filename) {
  final f = filename.toLowerCase();
  if (f.endsWith('.pdf')) return 'application/pdf';
  if (f.endsWith('.csv')) return 'text/csv;charset=utf-8';
  if (f.endsWith('.xls')) return 'application/vnd.ms-excel';
  if (f.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (f.endsWith('.doc')) return 'application/msword';
  if (f.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
  if (f.endsWith('.html') || f.endsWith('.htm')) {
    return 'text/html;charset=utf-8';
  }
  if (f.endsWith('.jpg') || f.endsWith('.jpeg')) return 'image/jpeg';
  if (f.endsWith('.png')) return 'image/png';
  if (f.endsWith('.json')) return 'application/json';
  if (f.endsWith('.txt')) return 'text/plain;charset=utf-8';
  return 'application/octet-stream';
}
