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
