// 네이티브(안드로이드/데스크톱)용 APK 다운로드·설치 구현.
//
// 다운로드/검증은 순수 Dart(dart:io + crypto)로 처리하고,
// 실제 패키지 설치(설치 화면 호출)만 네이티브(MainActivity.kt)의
// MethodChannel 로 위임한다.
//
//  ── 왜 네이티브인가 ──────────────────────────────────────────────
//  Android 8+ 는 앱이 직접 `Intent(ACTION_VIEW, file://…apk)` 를 열 수 없다.
//  FileProvider 로 content:// URI 를 만들어야 하고, O+ 에서는
//  REQUEST_INSTALL_PACKAGES 권한까지 필요하다. 이 두 가지는 매니페스트/코드
//  수준 작업이라 네이티브에서 처리하는 것이 가장 안전하다.
//
// 채널: "tsak/installer"  ·  메서드: installApk(path) / canRequestInstall() /
//        openInstallSettings() / relaunch()
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const MethodChannel _ch = MethodChannel('tsak/installer');

/// 다운로드 진행률 파일명(고정) — 매 업데이트마다 덮어쓴다.
const String _apkName = 'tsak_update.apk';

bool get supportsApkSelfUpdate => Platform.isAndroid;

/// APK 를 내려받아 로컬 임시경로를 반환한다.
///
/// [onProgress](받은바이트, 전체바이트) — 전체는 미상이면 -1.
/// 실패 시 빈 문자열을 반환하지 않고 예외를 던진다(호출부에서 안내).
Future<String> downloadApkToTemp(
  String url, {
  void Function(int received, int total)? onProgress,
}) async {
  final dir = await getTemporaryDirectory();
  final out = File('${dir.path}/$_apkName');
  if (await out.exists()) {
    try {
      await out.delete();
    } catch (_) {}
  }

  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw HttpException('다운로드 실패 (HTTP ${resp.statusCode})', uri: req.uri);
    }
    final total = resp.contentLength; // -1 가능
    final sink = out.openWrite();
    var received = 0;
    try {
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return out.path;
  } finally {
    client.close(force: true);
  }
}

/// 파일의 SHA-256(소문자 hex) 이 [expectedHex] 와 같은지.
/// [expectedHex] 가 비어 있으면 검증을 건너뛰고 true.
Future<bool> verifyFileSha256(String path, String expectedHex) async {
  final want = expectedHex.trim().toLowerCase();
  if (want.isEmpty) return true;
  final f = File(path);
  if (!await f.exists()) return false;
  final digest = await sha256.bind(f.openRead()).first;
  return digest.toString().toLowerCase() == want;
}

/// FileProvider content URI 로 APK 설치 화면을 띄운다.
/// 성공적으로 설치 화면을 열면 true.
Future<bool> installApkFile(String path) async {
  try {
    final r = await _ch.invokeMethod<bool>('installApk', {'path': path});
    return r ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// REQUEST_INSTALL_PACKAGES 권한(설치 허용) 여부.
Future<bool> canRequestInstall() async {
  try {
    final r = await _ch.invokeMethod<bool>('canRequestInstall');
    return r ?? false;
  } catch (_) {
    return false;
  }
}

/// '출처를 알 수 없는 앱 설치 허용' 설정 화면을 연다.
Future<void> openInstallPermissionSettings() async {
  try {
    await _ch.invokeMethod('openInstallSettings');
  } catch (_) {}
}

/// 앱을 재시작한다(설치 완료 후 적용용, 선택).
Future<void> relaunchApp() async {
  try {
    await _ch.invokeMethod('relaunch');
  } catch (_) {}
}

/// 이전 업데이트 잔여물(임시 APK) 정리.
Future<void> clearTempDownloads() async {
  if (!Platform.isAndroid) return;
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$_apkName');
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
