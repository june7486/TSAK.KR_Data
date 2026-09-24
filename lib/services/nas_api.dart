import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/member.dart';
import 'app_config.dart';

/// NAS 프록시 REST API 클라이언트
///
/// baseUrl 이 비어 있으면 웹앱과 동일 origin(상대경로)으로 호출한다.
class NasApi {
  NasApi({String? baseUrl})
      : _base = (baseUrl ?? AppConfig.defaultServerBase).replaceAll(
          RegExp(r'/+$'),
          '',
        );

  String _base;

  String get baseUrl => _base;
  set baseUrl(String v) =>
      _base = v.replaceAll(RegExp(r'/+$'), '');

  Uri _uri(String path) => Uri.parse('$_base$path');

  // ---- Health ----
  Future<bool> health() async {
    try {
      final r = await http
          .get(_uri('/api/health'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return false;
      final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
      return j['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // ---- Auth ----
  /// tier: master | app | personal
  Future<Map<String, dynamic>> login(String tier, String value) async {
    final r = await http
        .post(
          _uri('/api/login'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'tier': tier, 'value': value}),
        )
        .timeout(const Duration(seconds: 15));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- Members ----
  Future<List<Member>> fetchMembers() async {
    final r = await http
        .get(_uri('/api/members'))
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    final list = (j['members'] as List?) ?? [];
    return list
        .map((e) => Member.fromMap(e as Map))
        .toList();
  }

  /// 전체 DB 저장(서버가 자동 백업 후 교체)
  Future<Map<String, dynamic>> saveAll(
    List<Member> members, {
    String by = 'app',
  }) async {
    final r = await http
        .post(
          _uri('/api/members'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'members': members.map((m) => m.toMap()).toList(),
            'by': by,
          }),
        )
        .timeout(const Duration(seconds: 90));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- Meta / Config ----
  Future<Map<String, dynamic>> fetchMeta() async {
    final r = await http
        .get(_uri('/api/meta'))
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchConfig() async {
    final r = await http
        .get(_uri('/api/config'))
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveConfig(
    Map<String, dynamic> patch, {
    bool requirePw = false,
    String? pw,
  }) async {
    final body = Map<String, dynamic>.from(patch);
    if (requirePw) {
      body['requirePw'] = true;
      body['_pw'] = pw ?? '';
    }
    final r = await http
        .post(
          _uri('/api/config'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(body),
        )
        .timeout(const Duration(seconds: 20));
    return json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ---- Backups ----
  Future<List<Map<String, dynamic>>> backups() async {
    final r = await http
        .get(_uri('/api/backups'))
        .timeout(const Duration(seconds: 30));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return ((j['backups'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<String?> createBackup([String? name]) async {
    final r = await http
        .post(
          _uri('/api/backup'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'name': name ?? ''}),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true ? j['name'] as String? : null;
  }

  Future<List<Member>?> restore(String name) async {
    final r = await http
        .post(
          _uri('/api/restore'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'name': name}),
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    if (j['ok'] != true) return null;
    final list = (j['members'] as List?) ?? [];
    return list.map((e) => Member.fromMap(e as Map)).toList();
  }

  // ---- Photos ----
  Future<bool> uploadPhoto(String number, List<int> bytes,
      {String ext = 'jpg'}) async {
    final r = await http
        .post(
          _uri('/api/photo/$number'),
          headers: {'Content-Type': 'image/$ext'},
          body: bytes,
        )
        .timeout(const Duration(seconds: 60));
    final j = json.decode(utf8.decode(r.bodyBytes)) as Map;
    return j['ok'] == true;
  }

  String photoUrl(String number) => '$_base/api/photo/$number';
}
