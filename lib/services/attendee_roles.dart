/// 참석자 직책(역할) 분류 — **앱 전체의 유일한 정의**.
///
/// ## [2026-10-29 "컵" 사고] 왜 이 파일이 생겼나
///
/// 화면에는 `인가자·리더·로버·비버·스카우트·벤처·일반·기타` **8종** 표만 있는데,
/// 서버는 정식 직책으로 `컵(C)`(컵스카우트)까지 **9종**을 알고 있었다.
/// 직책 선택 UI 도 세 곳에서 서로 다른 목록을 쓰고 있었다.
///
/// 그 결과:
///  · `roles: ['컵']` 인 참석자(어야영)가 8종 표에서 **갈 곳을 잃고**
///    마지막 fallback 에서 `인가자` 로 조용히 흡수됐다.
///  · 인가번호 칸에 **이름**(류호준)이나 **전화번호**가 들어 있어도
///    "번호가 있으니 인가자" 로 세어졌다.
///  → 표의 `인가자 14` 와 하단 상세의 인원이 서로 맞지 않아 보였다.
///
/// ## 규칙 (구조적으로 재발 불가)
///  1. 직책 목록은 **이 파일 하나**에만 둔다.
///  2. 표에 없는 직책은 **버리지 않고** `기타` 로 **표시**한다(조용히 흡수 금지).
///  3. 직책이 비어 있을 때만 신원(인가번호 유무)으로 판정한다.
///  4. 인가번호 자리에 들어온 **이름·전화번호**는 인가번호로 보지 않는다.
library;

/// 정규 직책 라벨 — 서버 `_ev_role_label` 과 1:1 대응.
class AttendeeRole {
  static const String leader = '리더';
  static const String rover = '로버';
  static const String venture = '벤처';
  static const String scout = '스카우트';
  static const String cub = '컵';
  static const String beaver = '비버';
  static const String regular = '일반';
  static const String etc = '기타';
}

/// 직책 문자열 정규화·코드 변환·행 분류를 담당한다.
class AttendeeRoles {
  const AttendeeRoles._();

  /// 선택 UI 에 보여 줄 **정규 직책** 목록(표시 순서 고정).
  ///
  /// `비버`·`컵`은 하위 섹션이라 `스카우트` 뒤에 둔다.
  static const List<String> picker = <String>[
    AttendeeRole.leader,
    AttendeeRole.rover,
    AttendeeRole.venture,
    AttendeeRole.scout,
    AttendeeRole.cub,
    AttendeeRole.beaver,
    AttendeeRole.regular,
    AttendeeRole.etc,
  ];

  /// 코드 → 한글 라벨. 서버 `_ev_role_label` 과 **반드시 같게** 유지한다.
  static const Map<String, String> codeToLabel = <String, String>{
    'L': AttendeeRole.leader,
    'R': AttendeeRole.rover,
    'V': AttendeeRole.venture,
    'S': AttendeeRole.scout,
    'C': AttendeeRole.cub,
    'B': AttendeeRole.beaver,
    'regular': AttendeeRole.regular,
    'etc': AttendeeRole.etc,
  };

  /// 한글 라벨 → 코드.
  static const Map<String, String> labelToCode = <String, String>{
    AttendeeRole.leader: 'L',
    AttendeeRole.rover: 'R',
    AttendeeRole.venture: 'V',
    AttendeeRole.scout: 'S',
    AttendeeRole.cub: 'C',
    AttendeeRole.beaver: 'B',
    AttendeeRole.regular: 'regular',
    AttendeeRole.etc: 'etc',
  };

  /// 자유 입력 직책 → 정규 라벨. 하나도 안 맞으면 `null`.
  ///
  /// ## 우선순위가 중요한 이유
  /// `로버스카우트` 는 `로버` 이기도 하고 `스카우트` 이기도 하다.
  /// 더 **구체적인** 쪽을 먼저 봐야 한다(서버 `_ev_role_code` 와 동일 순서):
  ///   리더 > 벤처 > 로버 > 스카우트 > 컵 > 비버
  static String? canonicalOf(Iterable<String> roles) {
    final joined = roles
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .join(' ');
    if (joined.isEmpty) return null;

    // '지도자'·'멘토지도자' 는 리더로 통합한다.
    if (joined.contains('리더') ||
        joined.contains('지도') ||
        joined.contains('멘토') ||
        joined.contains('leader')) {
      return AttendeeRole.leader;
    }
    if (joined.contains('벤처') || joined.contains('벤쳐')) {
      return AttendeeRole.venture;
    }
    if (joined.contains('로버') || joined.contains('rover')) {
      return AttendeeRole.rover;
    }
    if (joined.contains('스카우트') || joined.contains('scout')) {
      return AttendeeRole.scout;
    }
    if (joined.contains('컵') || joined.contains('cub')) {
      return AttendeeRole.cub;
    }
    if (joined.contains('비버') || joined.contains('beaver')) {
      return AttendeeRole.beaver;
    }
    if (joined.contains('일반') || joined.contains('regular')) {
      return AttendeeRole.regular;
    }
    if (joined.contains('기타') || joined.contains('etc')) {
      return AttendeeRole.etc;
    }
    return null;
  }

  /// 행이 **인가번호를 가진 사람**인가? — 직책과 무관하게 판정한다.
  ///
  /// [요구 2026-11-07] "참가자 중 범스카우트 인가자가 리더로 선택할 경우에도
  ///  인가자 항목에 인원을 넣을 것"
  ///
  /// 결산 '인가자' 항목은 **직책과 별개로** 인가번호 보유자 전원을 세야 한다.
  /// 판정 근거를 넓게 보되, [hasRealLicenseNumber] 의 엄격함은 유지한다
  /// (이름·전화번호·자유입력은 인가번호가 아니다).
  ///
  /// 우선순위:
  ///   ① 앱이 이미 판정해 둔 신호 — `licensed == true`, `identityType`
  ///      ('licensed'/'tsak'/'eunha'), `identityKey` 의 `tsak:`/`eunha:` 접두어
  ///   ② `corps` 가 tsak/eunha
  ///   ③ `number` 칸이 **진짜 인가번호 모양** ([hasRealLicenseNumber])
  static bool hasLicenseOnRow(Map<String, dynamic> a) {
    if (a['licensed'] == true) return true;

    final type = '${a['identityType'] ?? ''}'.trim().toLowerCase();
    if (type == 'licensed' || type == 'tsak' || type == 'eunha') return true;

    final key = '${a['identityKey'] ?? ''}'.trim().toLowerCase();
    if (key.startsWith('tsak:') || key.startsWith('eunha:')) return true;
    // 명시적으로 일반으로 표시된 행은 인가자로 세지 않는다.
    if (key.startsWith('reg:')) return false;

    final corps = '${a['corps'] ?? ''}'.trim().toLowerCase();
    if (corps == 'tsak' || corps == 'eunha') return true;

    return hasRealLicenseNumber(a);
  }

  /// 행에 담긴 직책(roles / roleLabel / roleCode)을 정규 라벨로 만든다.
  /// 직책 정보가 전혀 없으면 `null`.
  static String? canonicalOfRow(Map<String, dynamic> a) {
    final raw = <String>[
      ...(((a['roles'] as List?) ?? const <dynamic>[])
          .map((e) => '$e'.trim())),
      if ('${a['roleLabel'] ?? ''}'.trim().isNotEmpty)
        '${a['roleLabel']}'.trim(),
    ];
    final byLabel = canonicalOf(raw);
    if (byLabel != null) return byLabel;

    final code = '${a['roleCode'] ?? ''}'.trim();
    if (code.isNotEmpty && codeToLabel.containsKey(code)) {
      return codeToLabel[code];
    }
    return null;
  }

  /// 코드(표시용) — 선택된 직책들 중 대표 하나.
  static String codeOf(Iterable<String> roles) {
    final c = canonicalOf(roles);
    if (c == null) return '';
    return labelToCode[c] ?? AttendeeRole.etc;
  }

  // ══════════════════════════════════════════════════════════════════
  // 신원 판정 — `number` 칸에 무엇이 들어 있는지 **정직하게** 본다.
  // ══════════════════════════════════════════════════════════════════

  /// `number` 칸이 **인가번호 모양**인가?
  ///
  /// 인가번호는 범 1~415 / 은하 G1~ 수준으로 **짧다**.
  /// 다음은 인가번호가 아니다:
  ///  · 이름이 그대로 들어온 경우 (`류호준`)
  ///  · 휴대폰 번호 (`010-2702-1126`, 11자리)
  ///  · 이름과 숫자가 뒤섞인 자유 입력
  static bool hasRealLicenseNumber(Map<String, dynamic> a) {
    final num = '${a['number'] ?? ''}'.trim();
    if (num.isEmpty) return false;

    // 이름이 그대로 들어온 경우.
    if (num == '${a['name'] ?? ''}'.trim() && num.isNotEmpty) return false;

    final d = num.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return false;
    if (d.length >= 10) return false; // 전화번호
    if (d.startsWith('01') && d.length >= 9) return false; // 전화번호

    // 은하 표기(G/은하/갤럭시)는 접두어가 있어야 인정.
    if (RegExp(r'^(g|G|은하|갤럭시|galaxy|eunha)', caseSensitive: false)
        .hasMatch(num)) {
      return d.isNotEmpty;
    }
    // 그 외에는 4자리 이하만 인가번호로 본다.
    return d.length <= 4;
  }

  /// 일반(비인가) 행인가?
  ///
  /// 종전 구현은 `!numLabelOf(number).contains('범')` 이라는 우회 조건을 썼는데,
  /// `number` 가 이름이나 전화번호일 때도 참이 되어 **일반회원이 인가자로**
  /// 세어지는 원인이었다. 이제 근거를 명시적으로 본다.
  static bool isRegularRow(Map<String, dynamic> a) {
    if (a['isRegular'] == true) return true;

    final key = '${a['identityKey'] ?? ''}'.trim();
    if (key.startsWith('reg:')) return true;
    if (key.startsWith('tsak:') || key.startsWith('eunha:')) return false;

    final corps = '${a['corps'] ?? ''}'.trim();
    if (corps == 'tsak' || corps == 'eunha') return false;
    return corps.isEmpty;
  }
}

// ══════════════════════════════════════════════════════════════════════════
// [요구 2026-10-29] 결산자료 표시·출력의 **표현 순서**를 한 곳에서 정의한다.
//
//  "일반 회원은 범인가자정보가 아니라, 서포터즈 인가자 정보로 표시함
//   상세내역에 표현순서: 이름 / 범인가번호 / 은하인가번호 /
//   등급(리더,로버,벤처,스카우트,컵,비버,일반,서포터츠 등) / 연맹, 단위대 등의 순"
//
//  ## 왜 문제였나
//   `_credentialCard` 가 `m.corps == 'eunha' ? '은하' : '범'` 로 **이분법**이었다.
//   일반회원(서포터즈)은 corps 가 비어 있어서 `범` 가지로 떨어졌고,
//   카드 제목이 **'범인가 정보'**, 항목이 **'범인가번호'** 로 표시됐다.
//   서포터즈는 범 인가자가 **아니다**. 인가번호도 없다(전화번호가 계정).
// ══════════════════════════════════════════════════════════════════════════

/// 신원 구분 — 카드·표·출력에서 쓰는 **정규 명칭**.
enum AttendeeKind {
  /// 범스카우트 인가자 (`tsak:415`)
  tsak('범', '범인가번호', '범스카우트'),

  /// 은하스카우트 인가자 (`eunha:G75`)
  eunha('은하', '은하인가번호', '은하스카우트'),

  /// 서포터즈 = 비인가 일반회원 (`reg:010…`). **범 인가자가 아니다.**
  supporter('서포터즈', '서포터즈 번호', '서포터즈');

  const AttendeeKind(this.mark, this.numberLabel, this.fullName);

  /// 말머리 — '범' / '은하' / '서포터즈'
  final String mark;

  /// 인가번호 항목 라벨 — 서포터즈는 인가번호가 없으므로 '번호'로 쓴다.
  final String numberLabel;

  /// 단체 정식 명칭.
  final String fullName;

  /// 카드 제목 — '범인가 정보' / '은하인가 정보' / '서포터즈 정보'.
  String get cardTitle => this == AttendeeKind.supporter
      ? '서포터즈 정보 (인가 당시 정보)'
      : '$fullName 인가 정보 (인가 당시 정보)';
}

/// 결산 상세 한 줄의 **표현 순서**와 직책 표기를 담당한다.
///
/// 고정 순서: `이름 → 범인가번호 → 은하인가번호 → 등급 → 연맹/단위대 …`
class SettlementLine {
  const SettlementLine._();

  /// 필드 안의 구분자 충돌 제거 — 줄 구분자가 `·` 이므로
  /// 값 안의 `·` 는 `/` 로 바꾼다(예: '스카우트비피클럽 · 지역대 대장').
  static String _clean(String v) => v
      .replaceAll(RegExp(r'\s*[·ㅡ]\s*'), ' / ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  // ══════════════════════════════════════════════════════════════════════
  // [요구 2026-11-08] 참가자 등록정보는 **현재활동** 기준으로 보여준다.
  //
  //   "행사 참가자 명단에서 참가자 등록정보는 현재활동 정보로 넣어줘
  //    이승준+김병혁 등은 인가시 정보가 들어가 있음 / 모두 현재 활동정보로 수정"
  //
  // 참석자 행에는 등록 시점(인가시) 소속이 `league`/`unit` 으로 박혀 있다.
  // 서버(`_ev_attendee_view`)는 표시 시점에 회원 명부의 현재활동
  // (`regLeague`/`regUnit`+`position`)을 조회해 `leagueText`/`unitText` 로
  // 주입한다. **화면·PDF·엑셀이 모두 이 두 값을 써야** 같은 사람이
  // 어디서나 같은 소속으로 보인다.
  //
  // 읽는 순서(현재활동 → 인가시 폴백):
  //   ① leagueText / unitText   — 서버가 주입한 현재활동 표시값
  //   ② regLeague  / regUnit    — 회원 맵을 직접 받은 경우
  //   ③ league     / unit       — 행 스냅샷(현재활동 값이 아예 없을 때만)
  // ══════════════════════════════════════════════════════════════════════

  /// 참석자 행의 **현재활동 소속연맹**. 없으면 인가시 연맹으로 폴백.
  static String currentLeague(Map<String, dynamic> a) {
    for (final k in const ['leagueText', 'regLeague', 'league', 'leagueName']) {
      final v = '${a[k] ?? ''}'.trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// 참석자 행의 **현재활동 단위대**(직위 병기 포함). 없으면 인가시 폴백.
  static String currentUnit(Map<String, dynamic> a) {
    for (final k in const ['unitText', 'regUnit', 'unit']) {
      final v = '${a[k] ?? ''}'.trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// `현재활동` 소속 한 줄 — `연맹 · 단위대` (중복 제거).
  static String currentActivityText(Map<String, dynamic> a) {
    final lg = _clean(currentLeague(a));
    final un = _clean(currentUnit(a));
    if (lg.isEmpty && un.isEmpty) return '';
    if (lg.isEmpty) return un;
    if (un.isEmpty) return lg;
    // 단위대 문자열이 이미 연맹을 품고 있으면 연맹을 또 붙이지 않는다.
    return (un.contains(lg)) ? un : '$lg $un';
  }

  /// 상세 한 줄(가운뎃점 구분).
  ///
  /// [a] 는 참석자 map. [league]/[unit] 인자를 주면 그 값이 **최우선**이고,
  /// 주지 않으면 **현재활동**(`unitText`/`leagueText` → `reg*` → 스냅샷)
  /// 규칙으로 스스로 복원한다.
  static String of(
    Map<String, dynamic> a, {
    String tsakNo = '',
    String eunhaNo = '',
    String league = '',
    String unit = '',
  }) {
    final name = '${a['name'] ?? ''}'.trim();
    if (name.isEmpty) return '';

    // 인자가 비었으면 **현재활동** 기준으로 복원한다(인가시 스냅샷 아님).
    final lgArg = league.trim().isNotEmpty ? league : currentLeague(a);
    final unArg = unit.trim().isNotEmpty ? unit : currentUnit(a);
    // ── ②③ 인가번호 — 범 / 은하를 **따로** 둔다(동시 보유 가능). ────────
    var tNo = tsakNo.trim();
    var eNo = eunhaNo.trim();
    if (tNo.isEmpty && eNo.isEmpty) {
      // 인자로 안 들어왔으면 행 자체에서 복원한다.
      final num = '${a['number'] ?? ''}'.trim();
      if (AttendeeRoles.hasRealLicenseNumber(a)) {
        final d = num.replaceAll(RegExp(r'[^0-9]'), '');
        if (RegExp(r'^(g|은하|갤럭시|galaxy|eunha)', caseSensitive: false)
            .hasMatch(num)) {
          eNo = d.isEmpty ? '' : '은하#$d';
        } else {
          tNo = d.isEmpty ? '' : '범#$d';
        }
      }
    }
    if (eNo.isNotEmpty && !eNo.contains('#')) eNo = '은하#$eNo';
    if (tNo.isNotEmpty && !tNo.contains('#')) tNo = '범#$tNo';

    // ── ④ 등급 — 직책 우선, 없으면 신원으로. ─────────────────────────
    var grade = AttendeeRoles.canonicalOfRow(a) ?? '';
    if (grade.isEmpty) {
      if (tNo.isNotEmpty || eNo.isNotEmpty) {
        grade = '인가자';
      } else if (AttendeeRoles.isRegularRow(a)) {
        grade = AttendeeKind.supporter.mark; // '서포터즈'
      }
    } else if (grade == AttendeeRole.regular &&
        AttendeeRoles.isRegularRow(a)) {
      // '일반' 보다는 '서포터즈' 가 정확한 호칭이다(요구).
      grade = AttendeeKind.supporter.mark;
    }

    // ── ⑤ 연맹 · 단위대 ───────────────────────────────────────────────
    final lg = _clean(lgArg);
    final un0 = _clean(unArg).isNotEmpty
        ? _clean(unArg)
        : _clean('${a['role'] ?? ''}');
    // 단위대 문자열이 이미 연맹을 포함하면 중복해서 붙이지 않는다.
    //  예) league='인천연맹', unit='인천연맹 별무리지역대' → '인천연맹 별무리지역대'
    String place;
    if (lg.isNotEmpty && un0.isNotEmpty) {
      place = (un0.startsWith(lg) || un0.contains(lg)) ? un0 : '$lg $un0';
    } else {
      place = un0.isNotEmpty ? un0 : lg;
    }

    return [
      _clean(name),
      if (tNo.isNotEmpty) tNo,
      if (eNo.isNotEmpty) eNo,
      if (grade.isNotEmpty) grade,
      if (place.isNotEmpty) place,
    ].join(' · ');
  }
}
