import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'app_config.dart';

import 'build_info.g.dart';

export 'build_info.g.dart';

/// 표시용 버전 이름 — **커밋마다 자동으로 바뀐다**.
///
/// (요구) "버전 이름이 변경되지 않는데, 혹시 버그야?"
///   기존에는 `AppConfig.appVersion`('1.0.0') 이 상수라 재빌드·커밋을 해도
///   화면 버전 이름이 절대 바뀌지 않았다(옆의 빌드 시각만 바뀜).
///   이제 버전 이름 = `앱버전+빌드넘버` 로 만들어, 커밋할 때마다 1씩 오른다.
///   예: v1.0.0+34, v1.0.0+35 …
String get versionName => 'v${AppConfig.appVersion}+$kBuildNumber';

/// 커밋 표식 (변경 눈으로 확인용)  예: "a1b2c3d"
String get buildCommit => kCommit;

/// 짧은 버전 라벨 (앱바 등 좁은 공간용)  예: "v1.0.0+34 · 09-26 09:12"
String get versionShortLabel => '$versionName · $kBuildShort';

/// 전체 버전 라벨  예: "v1.0.0+34 · 2026-10-03 17:01"
String get versionFullLabel => '$versionName · $kBuildDisplay';

/// 서버(프록시) 버전 비교 결과.
enum VersionStatus { unknown, upToDate, serverNewer, serverOlder }

class ServerVersion {
  final int stamp;
  final String display; // 예: "09-26 10:05"
  const ServerVersion(this.stamp, this.display);
}

/// 정수 스탬프(YYYYMMDDHHMMSS)를 "MM-DD HH:MM" 로 변환.
String formatStamp(int stamp) {
  final s = stamp.toString().padLeft(14, '0');
  if (s.length < 12) return '$stamp';
  final mo = s.substring(4, 6);
  final d = s.substring(6, 8);
  final h = s.substring(8, 10);
  final mi = s.substring(10, 12);
  return '$mo-$d $h:$mi';
}

/// 정수 스탬프(YYYYMMDDHHMMSS) → DateTime (실패 시 null)
DateTime? parseStamp(int stamp) {
  final s = stamp.toString().padLeft(14, '0');
  if (s.length != 14) return null;
  try {
    return DateTime(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
      int.parse(s.substring(8, 10)),
      int.parse(s.substring(10, 12)),
      int.parse(s.substring(12, 14)),
    );
  } catch (_) {
    return null;
  }
}

/// 스탬프 정수 비교 시 허용하는 절대 초 오차(시계 오차 흡수용).
/// 서버는 빌드 시 심어둔 version.json 을 그대로 내려주므로 앱↔서버 스탬프가
/// 정확히 일치한다. 0~5초 차이는 같은 빌드(시계 오차)로 간주한다.
const int _kVersionToleranceSec = 5;

/// 서버(프록시)의 최신 빌드 버전을 조회한다. (웹 전용, 실패 시 null)
///
/// 네트워크/서버 오류·CORS·오프라인 등 어떤 이유로든 실패하면 null을 반환한다
/// → 호출부는 "오프라인(알 수 없음)"으로 간주하고 기존 버전을 그대로 진행한다.
Future<ServerVersion?> fetchServerVersion() async {
  if (!kIsWeb) return null;
  try {
    final uri = Uri.base.resolve(
      'version.json?_=${DateTime.now().millisecondsSinceEpoch}',
    );
    final resp = await http
        .get(uri, headers: {'Cache-Control': 'no-store'})
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return null;
    final m = jsonDecode(resp.body);
    if (m is! Map) return null;
    final raw = m['version'] ?? m['build_id'];
    final stamp = int.tryParse('$raw') ?? 0;
    if (stamp <= 0) return null;
    return ServerVersion(stamp, formatStamp(stamp));
  } catch (_) {
    return null;
  }
}

/// 현재 앱 버전과 서버 최신 버전을 비교한다.
///
/// 서버는 빌드 시 심어둔 version.json(앱과 동일 스탬프)을 내려주므로
/// 두 값이 **정확히 같으면 같은 빌드**다. 값이 다르면(±[_kVersionToleranceSec]
/// 초 초과) 다른 버전 → 재다운로드 대상으로 판정한다.
Future<VersionStatus> checkVersion() async {
  final sv = await fetchServerVersion();
  if (sv == null) return VersionStatus.unknown;
  final apt = parseStamp(kBuildStampInt);
  final spt = parseStamp(sv.stamp);
  // 정확 일치(시계 오차 허용)면 같은 빌드.
  if (sv.stamp == kBuildStampInt) return VersionStatus.upToDate;
  if (apt == null || spt == null) {
    if (sv.stamp > kBuildStampInt) return VersionStatus.serverNewer;
    if (sv.stamp < kBuildStampInt) return VersionStatus.serverOlder;
    return VersionStatus.upToDate;
  }
  final diffSec = spt.difference(apt).inSeconds;
  if (diffSec > _kVersionToleranceSec) return VersionStatus.serverNewer;
  if (diffSec < -_kVersionToleranceSec) return VersionStatus.serverOlder;
  return VersionStatus.upToDate;
}

/// 서버에 더 새로운 버전이 있으면 true.
///
/// 네트워크가 안 되거나(오프라인) 판단할 수 없으면 **false** —
/// 호출부는 기존(캐시된) 버전으로 그대로 진행한다.
Future<bool> serverHasNewerVersion() async {
  try {
    final st = await checkVersion();
    return st == VersionStatus.serverNewer;
  } catch (_) {
    return false;
  }
}

// ============================================================================
//  APK 원격 업데이트 (안드로이드 네이티브 전용)
//  --------------------------------------------------------------------------
//  웹은 위의 빌드 스탬프 방식으로 캐시를 지우고 재로드하면 끝이지만,
//  설치형 APK 는 코드/화면을 바꿀 수 없다 → **새 APK 를 내려받아 설치**해야 한다.
//  서버는 `/apk.json` 에 최신 APK 의 버전·URL·무결성(SHA-256)을 게시하고,
//  앱은 그것을 조회해 더 최신이면 다운로드→검증→설치한다.
// ============================================================================

/// 서버가 게시한 최신 APK 정보.
class ApkUpdate {
  /// 서버 빌드 넘버(예: 447). 현재 [kBuildNumber] 보다 크면 최신.
  final int build;

  /// 표시용 버전 문자열(예: "1.0.0+447").
  final String version;

  /// APK 절대 다운로드 URL.
  final String url;

  /// SHA-256(hex, 소문자) — 다운로드 무결성 검증용. 비어 있으면 검증 생략.
  final String sha256;

  /// 파일 크기(바이트, 0=미상).
  final int size;

  /// 릴리스 노트(선택).
  final String notes;

  const ApkUpdate({
    required this.build,
    required this.version,
    required this.url,
    this.sha256 = '',
    this.size = 0,
    this.notes = '',
  });

  /// 현재 앱보다 최신인가?
  bool get isNewer => build > kBuildNumber;
}

/// 서버의 최신 APK 정보를 조회한다. (실패·오프라인 시 null)
///
/// · 서버주소는 `AppConfig.defaultServerBase`(빌드 시 --dart-define=SERVER_BASE 로
///   주입) 또는 사용자가 설정한 값을 사용한다.
/// · apk.json 의 `url` 이 상대경로면 서버주소 기준으로 절대화한다.
Future<ApkUpdate?> fetchApkUpdate() async {
  final base = AppConfig.defaultServerBase.replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty || !base.startsWith('http')) return null;
  try {
    final uri = Uri.parse(
      '$base/apk.json?_=${DateTime.now().millisecondsSinceEpoch}',
    );
    final resp = await http
        .get(uri, headers: {'Cache-Control': 'no-store'})
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final m = jsonDecode(utf8.decode(resp.bodyBytes));
    if (m is! Map) return null;

    final build = int.tryParse('${m['build'] ?? m['build_number'] ?? 0}') ?? 0;
    final version = '${m['version'] ?? ''}';
    final rawUrl = '${m['url'] ?? ''}'.trim();
    var url = rawUrl;
    if (url.isNotEmpty && !url.startsWith('http')) {
      // 상대경로 → 서버주소 기준 절대화
      url = '$base/${url.replaceAll(RegExp(r'^/+'), '')}';
    }
    final sha = '${m['sha256'] ?? ''}'.trim().toLowerCase();
    final size = int.tryParse('${m['size'] ?? 0}') ?? 0;
    final notes = '${m['notes'] ?? ''}';
    if (build <= 0 || url.isEmpty) return null;
    return ApkUpdate(
      build: build,
      version: version.isEmpty ? 'build $build' : version,
      url: url,
      sha256: sha,
      size: size,
      notes: notes,
    );
  } catch (_) {
    return null;
  }
}
