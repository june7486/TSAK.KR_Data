import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'app_config.dart';

import 'build_info.g.dart';

export 'build_info.g.dart';

/// 짧은 버전 라벨 (앱바 등 좁은 공간용)  예: "v1.0.0 · 09-26 09:12"
String get versionShortLabel => 'v${AppConfig.appVersion} · $kBuildShort';

/// 전체 버전 라벨  예: "v1.0.0 · 2025-09-26 09:12"
String get versionFullLabel => 'v${AppConfig.appVersion} · $kBuildDisplay';

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
