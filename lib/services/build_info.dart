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

/// 빌드 시작(앱 기록)과 빌드 완료(서버 mtime) 사이 오차 허용 범위(분).
/// 같은 빌드인데 수십 초 차이로 "새 버전"으로 오판하지 않도록 한다.
const int _kVersionToleranceMin = 15;

/// 서버(프록시)의 최신 빌드 버전을 조회한다. (웹 전용, 실패 시 null)
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
/// 앱은 빌드 시작, 서버는 빌드 완료(main.dart.js mtime) 시각이므로
/// [_kVersionToleranceMin] 분 이내 차이는 같은 빌드로 간주한다.
Future<VersionStatus> checkVersion() async {
  final sv = await fetchServerVersion();
  if (sv == null) return VersionStatus.unknown;
  final apt = parseStamp(kBuildStampInt);
  final spt = parseStamp(sv.stamp);
  if (apt == null || spt == null) {
    if (sv.stamp > kBuildStampInt) return VersionStatus.serverNewer;
    if (sv.stamp < kBuildStampInt) return VersionStatus.serverOlder;
    return VersionStatus.upToDate;
  }
  final diffMin = spt.difference(apt).inMinutes;
  if (diffMin >= _kVersionToleranceMin) return VersionStatus.serverNewer;
  if (diffMin <= -_kVersionToleranceMin) return VersionStatus.serverOlder;
  return VersionStatus.upToDate;
}
