/// 행사 **추가 입력 사항** 필드 정의 — 단일 출처(single source of truth).
///
/// ## 요구 (원문 2026-10-30)
///  > "추가입력사항도 매우 중요한 정보야
///  >  이 내용도 자세히 보여주고 정리되고 출력시 구분해서 보여져야 해,
///  >  그리고 항목별로 취합도 가능해야 해"
///
/// ## 왜 이 파일이 필요한가
///  추가 입력 항목은 지금까지 **4곳에 하드코딩**되어 있었다.
///   · `qr.html`(참가신청서 웹폼) — `inTransport`/`inLodging`/`inArrive`…
///   · `event_detail_screen.dart` 입력 시트 — `transportC`/`lodgingC`…
///   · `event_detail_screen.dart` 표시부 — 마퀴 한 줄에 이모지로 이어붙임
///   · 출력(CSV/PDF) — 누락
///  그래서 **입력은 되는데 볼 수 없고, 출력에는 아예 없었다.**
///  라벨을 하나 바꾸려면 4곳을 고쳐야 하고, 한 곳만 빠지면 조용히 어긋난다.
///
///  이 파일은 그 4곳이 **모두 참조하는 유일한 정의**다.
///  항목을 추가하려면 [_all] 에 한 줄만 넣으면 표시·출력·취합이 함께 따라온다.
///
/// ## 저장 키 규칙
///  서버(`events.json` 의 `attendees[i]`)에 저장되는 **원본 키**를 [key] 로 쓴다.
///  기존 데이터와 반드시 호환되어야 하므로 키 이름은 **바꾸지 않는다**.
///  단, `transportNote`/`arriveNote` 처럼 `기타` 직접입력 값이 있는 항목은
///  [noteKey] 로 분리해 두었다 — 화면·출력에서는 **하나로 합쳐** 보여준다.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 추가 입력 항목의 **성격** — 표시 그룹과 취합 단위를 정한다.
enum ExtraGroup {
  /// 이동(교통) — 자차/대중교통. 취합 시 카풀·차량 배차에 쓰인다.
  transport('이동', Icons.directions_car),

  /// 숙박 — 숙박/비숙박(당일). 취합 시 방 배정·인원 산정에 쓰인다.
  lodging('숙박', Icons.hotel),

  /// 도착 — 정시/기타(직접입력). 취합 시 현장 인수인계 시간표.
  arrival('도착', Icons.schedule),

  /// 경로 — 출발 장소·예상 소요시간. 이동 계획 파악.
  route('경로', Icons.route),

  /// 동행 — 함께 오는 사람. 취합 시 좌석·차량 산정.
  companion('동행', Icons.groups),

  /// 요청 — 운영진에게 전달할 내용. **가장 놓치면 안 되는 항목**.
  request('요청', Icons.campaign);

  const ExtraGroup(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 추가 입력 항목 1개의 정의.
@immutable
class ExtraField {
  const ExtraField({
    required this.key,
    required this.label,
    required this.group,
    required this.icon,
    this.noteKey,
    this.hint = '',
    this.options = const <String>[],
    this.multiline = false,
    this.aliases = const <String>[],
  });

  /// `events.json` attendees 행의 저장 키(원본 그대로 — 호환성).
  final String key;

  /// 사람이 읽는 라벨(입력·표시·출력·취합 공통).
  final String label;

  final ExtraGroup group;
  final IconData icon;

  /// `기타` 직접입력 값이 저장되는 보조 키(예: `transportNote`).
  final String? noteKey;

  /// 입력 힌트.
  final String hint;

  /// 선택지(있으면 선택 UI, 없으면 자유 입력).
  final List<String> options;

  /// 여러 줄 입력 여부(전달사항).
  final bool multiline;

  /// 과거 오탈자·별칭 키 허용 목록(읽기 전용 폴백).
  final List<String> aliases;

  /// 행에서 **표시용 한 줄 값**을 만든다.
  ///
  /// `기타` + 직접입력이 함께 있으면 `기타(인천 송도 경유)` 처럼 합쳐
  /// 정보를 잃지 않게 한다. 둘 다 비면 빈 문자열.
  String valueOf(Map<String, dynamic> a) {
    final main = '${a[key] ?? ''}'.trim();
    var note = noteKey == null ? '' : '${a[noteKey!] ?? ''}'.trim();
    // 별칭 키 폴백(과거 데이터).
    if (main.isEmpty) {
      for (final alt in aliases) {
        final v = '${a[alt] ?? ''}'.trim();
        if (v.isNotEmpty) {
          note = v;
          break;
        }
      }
    }
    if (main.isEmpty) return note;
    if (note.isEmpty) return main;
    // 이미 값 안에 직접입력이 포함돼 있으면 중복 표기를 피한다.
    if (main.contains(note)) return main;
    return '$main($note)';
  }

  /// 값이 있는지.
  bool hasValue(Map<String, dynamic> a) => valueOf(a).isNotEmpty;
}

/// 추가 입력 사항 **전체 정의** — 순서가 곧 화면·출력 순서다.
///
/// 순서 원칙: 사용자가 참가신청서에서 마주치는 순서
/// (이동 → 숙박 → 도착 → 경로 → 동행 → 요청).
class ExtraFields {
  const ExtraFields._();

  /// 이동 방법 — `자차`/`대중교통`/`기타`.
  static const transport = ExtraField(
    key: 'transport',
    label: '이동 방법',
    group: ExtraGroup.transport,
    icon: Icons.directions_car,
    noteKey: 'transportNote',
    options: <String>['자차', '대중교통', '기타'],
    hint: '예: 자차 / 대중교통 / 기타(직접입력)',
  );

  /// 숙박 여부 — `숙박`/`비숙박`.
  static const lodging = ExtraField(
    key: 'lodging',
    label: '숙박 여부',
    group: ExtraGroup.lodging,
    icon: Icons.hotel,
    options: <String>['숙박', '비숙박'],
    hint: '예: 숙박 / 비숙박(당일)',
  );

  /// 도착 예정 시간 — `정시`/`기타`.
  static const arrive = ExtraField(
    key: 'arrive',
    label: '도착 예정 시간',
    group: ExtraGroup.arrival,
    icon: Icons.schedule,
    noteKey: 'arriveNote',
    options: <String>['정시', '기타'],
    hint: '예: 정시 / 1일 14:30',
  );

  /// 출발 장소.
  static const from = ExtraField(
    key: 'from',
    label: '출발 장소',
    group: ExtraGroup.route,
    icon: Icons.place_outlined,
    hint: '예: 인천 송도',
  );

  /// 예상 소요시간.
  static const eta = ExtraField(
    key: 'eta',
    label: '예상 소요시간',
    group: ExtraGroup.route,
    icon: Icons.timer_outlined,
    hint: '예: 3시간 30분',
  );

  /// 동행자 이름.
  static const companion = ExtraField(
    key: 'companion',
    label: '동행자',
    group: ExtraGroup.companion,
    icon: Icons.groups,
    hint: '여러 명은 쉼표로',
  );

  /// 현재 주소 — **회원정보에도 반영**되는 항목.
  static const address = ExtraField(
    key: 'address',
    label: '현재 주소',
    group: ExtraGroup.route,
    icon: Icons.home_outlined,
    hint: '도로명 주소 (회원정보에 반영)',
  );

  /// 운영진에게 전달할 내용 — **놓치면 안 되는 요청사항**.
  static const message = ExtraField(
    key: 'message',
    label: '운영진 전달사항',
    group: ExtraGroup.request,
    icon: Icons.campaign,
    multiline: true,
    hint: '식이요법·알레르기·특이사항 등',
  );

  /// 전체 정의(표시·출력 순서).
  static const List<ExtraField> all = <ExtraField>[
    transport,
    lodging,
    arrive,
    from,
    eta,
    companion,
    address,
    message,
  ];

  /// 취합(집계) 대상 — 선택지가 있는 항목만.
  ///
  /// 자유 입력(출발 장소·소요시간·동행자·주소·전달사항)은 값이 사람마다 달라
  /// 숫자로 셀 수 없으므로 **목록형 취합**([listOf])으로 보여준다.
  static const List<ExtraField> countable = <ExtraField>[transport, lodging, arrive];

  /// 해당 그룹의 항목들.
  static List<ExtraField> ofGroup(ExtraGroup g) =>
      all.where((f) => f.group == g).toList();

  /// 행의 추가입력 총 건수(값이 있는 항목 수).
  static int filledCount(Map<String, dynamic> a) =>
      all.where((f) => f.hasValue(a)).length;

  /// 값이 있는 항목만 (정의 순서대로).
  static List<ExtraField> filled(Map<String, dynamic> a) =>
      all.where((f) => f.hasValue(a)).toList();

  /// 그룹 → 색상(표시 일관성).
  static Color colorOf(ExtraGroup g) => switch (g) {
    ExtraGroup.transport => AppColors.taegeukBlue,
    ExtraGroup.lodging => AppColors.purple,
    ExtraGroup.arrival => AppColors.hermesOrange,
    ExtraGroup.route => AppColors.scoutGreen,
    ExtraGroup.companion => AppColors.tigerGold,
    ExtraGroup.request => AppColors.taegeukRed,
  };

  /// 집계 — 선택지별 인원수. 빈 값은 `미입력`으로 모은다.
  ///
  /// 반환: `{ '자차': 2, '대중교통': 1, '미입력': 4 }` (정의 순서 유지)
  static Map<String, int> tally(ExtraField f, Iterable<Map<String, dynamic>> rows) {
    final out = <String, int>{for (final o in f.options) o: 0};
    var blank = 0;
    for (final a in rows) {
      // 선택지 값만 센다(`기타` 직접입력은 '기타' 로 집계).
      final v = '${a[f.key] ?? ''}'.trim();
      if (v.isEmpty) {
        // 직접입력만 있고 선택은 비었으면 '기타'로 친다(정보 유실 방지).
        final note = f.noteKey == null ? '' : '${a[f.noteKey!] ?? ''}'.trim();
        if (note.isNotEmpty && out.containsKey('기타')) {
          out['기타'] = out['기타']! + 1;
        } else {
          blank++;
        }
        continue;
      }
      if (out.containsKey(v)) {
        out[v] = out[v]! + 1;
      } else {
        // 정의에 없는 값(과거 자유입력)은 그대로 별도 집계한다.
        out[v] = (out[v] ?? 0) + 1;
      }
    }
    if (blank > 0) out['미입력'] = blank;
    out.removeWhere((k, v) => v == 0);
    return out;
  }

  /// 목록형 취합 — 자유 입력 항목의 **값 → 명단**.
  ///
  /// 예: `{ '인천 송도': ['김승수'], '서울': ['이승준'] }`
  static Map<String, List<String>> listOf(
    ExtraField f,
    Iterable<Map<String, dynamic>> rows,
  ) {
    final out = <String, List<String>>{};
    for (final a in rows) {
      final v = f.valueOf(a);
      if (v.isEmpty) continue;
      final nm = '${a['name'] ?? ''}'.trim();
      final no = '${a['number'] ?? ''}'.trim();
      final who = nm.isEmpty ? (no.isEmpty ? '(이름없음)' : '#$no') : nm;
      out.putIfAbsent(v, () => <String>[]).add(who);
    }
    return out;
  }
}
