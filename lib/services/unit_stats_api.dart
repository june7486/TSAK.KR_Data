import 'dart:convert';

import 'package:http/http.dart' as http;

import 'nas_api.dart';

/// 단위대 통계 API — 2026-11-11 / turn58
///
/// ## [요구] 사용자 원문
///  "범스카우트 인가자들의 인가시 정보를 활용하여 통계란에 연맹별 단위대별
///   인가자 리스트를 출력 / 동일하게 현재 활동정보를 활용 /
///   단위대 이름을 다르게 쓴 경우가 많아서 체크박스로 선택 가능 /
///   전체 명부의 통계 및 상세내역까지 출력(연맹별 단위대별 선택 가능)"
///
/// ## 목적
///  · 어떤 단위대가 **몇 명을 배출**했는지 → 많이 배출한 곳은 대장께 감사장
///  · 어떤 단위대가 **몇 명을 보유**하고 있는지 → 오래 끊긴 곳은 지원책
///  · 다른 단위대와 **나란히 비교**할 수 있어야 한다.
///
/// ## 서버
///   GET  /api/stats/units?basis=issue|active&names=0|1
///   POST /api/stats/units/alias   (merge/unmerge/hide/unhide/reset — 관리자)
class UnitStatsApi {
  UnitStatsApi(this._nas);

  final NasApi _nas;

  Uri _uri(String action, Map<String, String> q) {
    final base = _nas.baseUrl.replaceAll(RegExp(r'/+$'), '');
    //  base 가 비어 있으면 웹과 같은 origin(상대경로)으로 호출한다.
    final path = '$base/api/stats/units$action';
    return Uri.parse(path).replace(queryParameters: q);
  }

  Map<String, String> _authHeaders() {
    final h = {'Content-Type': 'application/json'};
    //  NasApi.sessionId 는 non-nullable String 이다(빈 문자열 = 미로그인).
    if (_nas.sessionId.isNotEmpty) h['X-TSAK-Session'] = _nas.sessionId;
    return h;
  }

  /// 연맹·단위대 집계를 받아온다.
  ///
  /// [basis] `issue`(인가시) 또는 `active`(현재활동)
  /// [includeNames] true 일 때만 서버가 이름을 내려준다(기본 false).
  Future<UnitStatsResult> load({
    String basis = 'issue',
    bool includeNames = false,
  }) async {
    final r = await http.get(
      _uri('', {
        'basis': basis,
        'names': includeNames ? '1' : '0',
      }),
      headers: _authHeaders(),
    );
    if (r.statusCode != 200) {
      throw UnitStatsException('통계를 불러오지 못했습니다 (${r.statusCode})');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (j['ok'] != true) {
      throw UnitStatsException('${j['error'] ?? '알 수 없는 오류'}');
    }
    return UnitStatsResult.fromJson(j);
  }

  /// 표기 병합·숨김 설정 — 관리자·마스터만 성공한다.
  ///
  /// action: merge | unmerge | hide | unhide | reset
  Future<void> alias({
    required String action,
    String? into,
    List<String>? from,
    String? key,
    String basis = 'issue',
  }) async {
    final body = <String, dynamic>{'action': action, 'basis': basis};
    if (into != null) body['into'] = into;
    if (from != null) body['from'] = from;
    if (key != null) body['key'] = key;
    final r = await http.post(
      _uri('/alias', const {}),
      headers: _authHeaders(),
      body: jsonEncode(body),
    );
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (j['ok'] != true) {
      throw UnitStatsException('${j['error'] ?? '저장에 실패했습니다'}');
    }
  }

  /// [turn61] 병합 후보를 한 번에 모두 묶는다.
  ///
  /// scope: variants(표기 변형 61곳) | extra(추가 후보) | both
  /// 위험한 조합(연맹 다름·번호 다름)은 서버가 알아서 건너뛰고
  /// `skipped` 로 알려준다.
  Future<MergeAllResult> mergeAll({
    String scope = 'variants',
    String basis = 'issue',
  }) async {
    final r = await http.post(
      _uri('/alias', const {}),
      headers: _authHeaders(),
      body: jsonEncode(
          {'action': 'mergeAll', 'scope': scope, 'basis': basis}),
    );
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (j['ok'] != true) {
      throw UnitStatsException('${j['error'] ?? '일괄 병합에 실패했습니다'}');
    }
    return MergeAllResult(
      mergedGroups: (j['mergedGroups'] as num?)?.toInt() ?? 0,
      mergedPeople: (j['mergedPeople'] as num?)?.toInt() ?? 0,
      skipped: (j['skipped'] as num?)?.toInt() ?? 0,
      stats: j['stats'] is Map
          ? UnitStatsResult.fromJson(Map<String, dynamic>.from(j['stats']))
          : null,
    );
  }
}

/// 일괄 병합 결과.
class MergeAllResult {
  MergeAllResult({
    required this.mergedGroups,
    required this.mergedPeople,
    required this.skipped,
    this.stats,
  });

  final int mergedGroups;
  final int mergedPeople;
  final int skipped;
  final UnitStatsResult? stats;
}

class UnitStatsException implements Exception {
  UnitStatsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 단위대 1건.
class UnitRow {
  UnitRow({
    required this.key,
    required this.name,
    required this.league,
    required this.count,
    required this.unitNum,
    required this.kind,
    required this.firstYear,
    required this.lastYear,
    required this.gapYears,
    required this.leagues,
    required this.names,
    required this.years,
    required this.people,
  });

  final String key;
  final String name;
  final String league;
  final int count;
  final int unitNum;
  final String kind;

  /// 첫 배출 연도 / 마지막 배출 연도 / 마지막 배출 이후 경과 연수.
  final int? firstYear;
  final int? lastYear;
  final int? gapYears;

  /// {연맹: 인원} — 연맹이 섞인 단위대를 드러낸다.
  final Map<String, int> leagues;

  /// {원본 표기: 인원} — 체크박스로 확인·병합할 대상.
  final Map<String, int> names;

  /// {연도: 인원}
  final Map<String, int> years;

  final List<UnitPerson> people;

  bool get hasVariants => names.length > 1;

  /// 연맹이 2개 이상이면 "혼재"로 표시한다.
  bool get mixedLeague => leagues.length > 1;

  factory UnitRow.fromJson(Map<String, dynamic> j) {
    Map<String, int> toMap(dynamic v) {
      final out = <String, int>{};
      if (v is Map) {
        v.forEach((k, val) => out['$k'] = (val as num?)?.toInt() ?? 0);
      }
      return out;
    }

    return UnitRow(
      key: '${j['key'] ?? ''}',
      name: '${j['name'] ?? ''}',
      league: '${j['league'] ?? ''}',
      count: (j['count'] as num?)?.toInt() ?? 0,
      unitNum: (j['num'] as num?)?.toInt() ?? 0,
      kind: '${j['kind'] ?? ''}',
      firstYear: (j['firstYear'] as num?)?.toInt(),
      lastYear: (j['lastYear'] as num?)?.toInt(),
      gapYears: (j['gapYears'] as num?)?.toInt(),
      leagues: toMap(j['leagues']),
      names: toMap(j['names']),
      years: toMap(j['years']),
      people: (j['people'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => UnitPerson.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// 단위대 소속 인가자 1명.
class UnitPerson {
  UnitPerson({
    required this.number,
    required this.name,
    required this.date,
    required this.league,
    required this.unit,
    required this.year,
  });

  final String number;
  final String name;
  final String date;
  final String league;
  final String unit;
  final int year;

  factory UnitPerson.fromJson(Map<String, dynamic> j) => UnitPerson(
        number: '${j['number'] ?? ''}',
        name: '${j['name'] ?? ''}',
        date: '${j['date'] ?? ''}',
        league: '${j['league'] ?? ''}',
        unit: '${j['unit'] ?? ''}',
        year: (j['year'] as num?)?.toInt() ?? 0,
      );
}

/// 연맹 1건.
class LeagueGroup {
  LeagueGroup({
    required this.league,
    required this.total,
    required this.unitCount,
    required this.noDate,
    required this.oldest,
    required this.newest,
    required this.units,
  });

  final String league;
  final int total;
  final int unitCount;
  final int noDate;
  final int? oldest;
  final int? newest;
  final List<UnitRow> units;

  factory LeagueGroup.fromJson(Map<String, dynamic> j) => LeagueGroup(
        league: '${j['league'] ?? ''}',
        total: (j['total'] as num?)?.toInt() ?? 0,
        unitCount: (j['unitCount'] as num?)?.toInt() ?? 0,
        noDate: (j['noDate'] as num?)?.toInt() ?? 0,
        oldest: (j['oldest'] as num?)?.toInt(),
        newest: (j['newest'] as num?)?.toInt(),
        units: (j['units'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => UnitRow.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// 표기 변형 그룹 — "같은 단위대일 수 있음".
class VariantGroup {
  VariantGroup({
    required this.key,
    required this.name,
    required this.names,
    this.count = 0,
    this.grade = 'safe',
  });

  final String key;
  final String name;

  /// [(원본 표기, 인원)]
  final List<MapEntry<String, int>> names;

  /// 이 단위대로 묶였을 때의 총 인원.
  final int count;

  /// 병합 위험도 — safe / kindMix / nameMix / check.
  /// kindMix 는 소년대·연장대가 섞인 경우로 **묶으면 안 된다**.
  final String grade;

  bool get isRisky => grade == 'kindMix' || grade == 'nameMix';
  bool get isKindMix => grade == 'kindMix';

  String get gradeLabel => switch (grade) {
        'kindMix' => '소년대·연장대 혼합 — 묶지 마세요',
        'nameMix' => '번호·이름이 다름 — 확인 필요',
        'check' => '확인 필요',
        _ => '같은 표기로 봄',
      };

  factory VariantGroup.fromJson(Map<String, dynamic> j) {
    final list = <MapEntry<String, int>>[];
    final raw = j['names'];
    if (raw is List) {
      for (final e in raw) {
        if (e is List && e.length >= 2) {
          list.add(MapEntry(
            '${e[0]}',
            (e[1] as num?)?.toInt() ?? 0,
          ));
        }
      }
    }
    return VariantGroup(
      key: '${j['key'] ?? ''}',
      name: '${j['name'] ?? ''}',
      names: list,
      count: (j['count'] as num?)?.toInt() ?? 0,
      grade: '${j['grade'] ?? 'safe'}',
    );
  }
}

/// [turn61] 같은 연맹 안에서 번호·이름이 겹쳐 **추가로 발견된** 병합 후보.
///  정규화 키가 달라 원래는 따로 잡히던 것들이다.
class ExtraGroup {
  ExtraGroup({
    required this.reason,
    required this.label,
    required this.into,
    required this.intoName,
    required this.fromKeys,
    required this.keys,
    required this.count,
    required this.memberCount,
    required this.league,
    required this.names,
    this.grade = 'safe',
  });

  /// safe = 묶어도 확실 / check = 사람이 확인해야 함
  final String grade;

  bool get needsCheck => grade == 'check';

  String get gradeLabel =>
      grade == 'check' ? '확인 필요' : '같은 단위대로 봄';

  /// sameName(같은 연맹·같은 이름) 등
  final String reason;
  final String label;
  final String into;
  final String intoName;
  final List<String> fromKeys;
  final List<String> keys;
  final int count;

  /// 묶이는 단위대(키) 개수.
  final int memberCount;
  final String league;
  final List<MapEntry<String, int>> names;

  String get reasonLabel =>
      reason == 'sameNum' ? '같은 연맹 · 같은 번호' : '같은 연맹 · 같은 이름';

  /// [turn61] 서버가 확정한 안전 등급을 읽는다(구버전 서버면 safe).
  static String _gradeOf(Map<String, dynamic> j) =>
      '${j['grade'] ?? 'safe'}';

  factory ExtraGroup.fromJson(Map<String, dynamic> j) {
    final list = <MapEntry<String, int>>[];
    final raw = j['names'];
    if (raw is List) {
      for (final e in raw) {
        if (e is List && e.length >= 2) {
          list.add(MapEntry('${e[0]}', (e[1] as num?)?.toInt() ?? 0));
        }
      }
    }
    List<String> ss(dynamic v) =>
        (v as List? ?? const []).map((e) => '$e').toList();
    return ExtraGroup(
      reason: '${j['reason'] ?? ''}',
      label: '${j['label'] ?? ''}',
      into: '${j['into'] ?? ''}',
      intoName: '${j['intoName'] ?? ''}',
      fromKeys: ss(j['from']),
      keys: ss(j['keys']),
      count: (j['count'] as num?)?.toInt() ?? 0,
      memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
      league: '${j['league'] ?? ''}',
      names: list,
      grade: _gradeOf(j),
    );
  }
}

/// 전체 응답.
class UnitStatsResult {
  UnitStatsResult({
    required this.basis,
    required this.leagues,
    required this.units,
    required this.groups,
    required this.members,
    required this.withUnit,
    required this.noUnit,
    required this.thisYear,
    required this.namesIncluded,
    required this.aliasCount,
    required this.leaguesAll,
    this.extra = const [],
  });

  final String basis;
  final List<LeagueGroup> leagues;
  final List<UnitRow> units;
  final List<VariantGroup> groups;

  /// [turn61] 같은 연맹 안에서 번호·이름이 겹쳐 추가 발견된 병합 후보.
  final List<ExtraGroup> extra;
  final int members;
  final int withUnit;
  final int noUnit;
  final int thisYear;
  final bool namesIncluded;
  final int aliasCount;
  final List<String> leaguesAll;

  bool get isActiveBasis => basis == 'active';

  factory UnitStatsResult.fromJson(Map<String, dynamic> j) {
    List<T> toListOf<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
        (v as List? ?? const [])
            .whereType<Map>()
            .map((e) => f(Map<String, dynamic>.from(e)))
            .toList();
    final t = (j['totals'] as Map?) ?? const {};
    return UnitStatsResult(
      basis: '${j['basis'] ?? 'issue'}',
      leagues: toListOf(j['leagues'], LeagueGroup.fromJson),
      units: toListOf(j['units'], UnitRow.fromJson),
      groups: toListOf(j['groups'], VariantGroup.fromJson),
      extra: toListOf(j['extra'], ExtraGroup.fromJson),
      members: (t['members'] as num?)?.toInt() ?? 0,
      withUnit: (t['withUnit'] as num?)?.toInt() ?? 0,
      noUnit: (t['noUnit'] as num?)?.toInt() ?? 0,
      thisYear: (j['thisYear'] as num?)?.toInt() ?? 0,
      namesIncluded: j['namesIncluded'] == true,
      aliasCount: (j['aliasCount'] as num?)?.toInt() ?? 0,
      leaguesAll: (j['leaguesAll'] as List? ?? const [])
          .map((e) => '$e')
          .toList(),
    );
  }
}
