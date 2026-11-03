import '../services/attendee_roles.dart';
import '../services/league_names.dart';

/// 한국범스카우트 중앙회 인가자(회원) 모델
/// 요구사항: 인가번호, 이름, 주소, 단위대, 소속연맹, 활동, 메모,
///           사진, QR, 메일, 연간회비(평생/연도별), 행사참가, ATAS 인가번호, 인가일
class Member {
  Member({
    required this.id,
    required this.number,
    required this.name,
    this.nameEn = '',
    this.corps = 'tsak',
    this.league = '',
    this.unit = '',
    this.regLeague = '',
    this.regUnit = '',
    this.address = '',
    this.zipCode = '',
    this.phone = '',
    this.tel = '',
    this.email = '',
    this.residentNo = '',
    this.scoutNo = '',
    this.bio = '',
    this.date = '',
    this.atasNo = '',
    this.atasLeague = '',
    this.atasUnit = '',
    this.atasDate = '',
    this.activity = '',
    this.position = '',
    this.memo = '',
    this.birthday = '',
    this.anniversary = '',
    this.trainingStatus = '',
    this.awards = '',
    this.specialtyCourses = '',
    this.purchases = '',
    this.photoPath = '',
    this.lifetimeMember = false,
    this.lifetimeSince = '',
    this.qualificationStatus = '',
    this.qualificationNote = '',
    this.isRegular = false,
    this.approvalStatus = '',
    this.personalPassword = '',
    this.accessPhone = '',
    this.privacyAgreed = false,
    this.privacyAgreedAt = '',
    List<String>? mentors,
    List<String>? scoutNoList,
    List<String>? parents,
    List<String>? mentees,
    List<String>? children,
    this.linkApprovalStatus = '',
    this.linkApprovalNote = '',
    this.linkRequestSource = '',
    this.linkRequestedAt = '',
    this.linkApprovedAt = '',
    this.linkApprovedBy = '',
    this.linkFixNote = '',
    this.linkFixRequestedAt = '',
    this.linkFixRequestedBy = '',
    this.linkFixScope = '',
    Map<String, bool>? feeYears,
    Map<String, bool>? eventAttend,
    List<String>? pendingEventNames,
    Map<String, String>? fieldPerms,
    List<Map<String, dynamic>>? donations,
    List<Map<String, dynamic>>? infoHistory,
    this.sample = false,
    this.nameVisible = true,
    this.gender = '',
    this.genderVisible = true,
    this.updatedAt,
  }) : mentors = mentors ?? <String>[],
       scoutNos = scoutNoList ?? <String>[],
       parents = parents ?? <String>[],
       mentees = mentees ?? <String>[],
       children = children ?? <String>[],
       feeYears = feeYears ?? <String, bool>{},
       eventAttend = eventAttend ?? <String, bool>{},
       pendingEventNames = pendingEventNames ?? <String>[],
       fieldPerms = fieldPerms ?? <String, String>{},
       donations = donations ?? <Map<String, dynamic>>[],
       infoHistory = infoHistory ?? <Map<String, dynamic>>[];

  /// 내부 고유 ID
  String id;

  /// 인가번호 (예: "2186")
  String number;

  /// 성명
  String name;

  /// 영문 이름 (ATAS 인가정보에서 가져온 로마자 표기, 예: "Won Ho CHO").
  ///  · 값이 없으면 **빈칸**으로 두고 개인정보 페이지에서 직접 입력할 수 있다.
  ///  · ATAS 명부 출력 시 한글 이름 **옆**에 함께 배치한다.
  String nameEn;

  /// 소속 단체(corps) — 'tsak'(범스카우트, 기본) | 'eunha'(은하스카우트).
  /// 은하스카우트는 범스카우트와 **별도 관리**(통계·명단·로그인 분리)한다.
  String corps;

  /// 소속 연맹 (예: "제주", "광주")
  String league;

  /// 소속 단위대 (예: "제405단 샘물지역대")
  String unit;

  /// 현재 등록된(재적) 연맹 — 범(TSAK) 인가 시 부여된 연맹과 다를 수 있다.
  String regLeague;

  /// 현재 등록된(재적) 단위대.
  String regUnit;

  /// 주소
  String address;

  /// 우편번호 (예: "06130")
  String zipCode;

  /// 핸드폰
  String phone;

  /// 연락처(유선/추가 전화) — 핸드폰과 별도 관리 (예: "051-702-7766")
  String tel;

  /// 이메일
  String email;

  /// 주민등록번호(앞자리) — 민감정보. 마스터가 항목별 노출 여부를 결정한다.
  ///
  /// ## 표시 규칙 (2026-11-02, build #574)
  ///  요구: "주민등록정보는 뒷번호가 입력시 마킹처리가 안되고 있음
  ///        (예시: 990328-1******) / 노출되는(개인카드에도) 정보에는 뒷번호를
  ///        마킹처리하고 오로지 마스터만 뒷번호를 확인할 수 있도록 함"
  ///
  ///  원본 값은 **그대로 보관**한다(저장·내보내기·마스터 열람에 필요).
  ///  화면에 그릴 때는 [residentNoMasked] 를 쓴다.
  String residentNo;

  /// 뒷자리(하이픈 뒤)를 `*` 로 가린 표기 — **화면 표시 기본값**.
  ///
  ///  · `990328-1234567` → `990328-1******`
  ///  · 하이픈이 없어도 13자리면 6자리 + `-` + 성별1 + `*` 로 정규화한다.
  ///  · 이미 `*` 로 가려진 값은 그대로 둔다(두 번 마킹해도 모양이 같다).
  ///  · 7자리 미만처럼 판단이 어려운 값은 **전부 가린다**(안전 우선).
  ///
  ///  마스터만 [residentNo] 원본을 볼 수 있게 하는 판단은 **화면 쪽 책임**이다
  ///  ([isMaster] 는 서버 권한이라 모델이 알 수 없다).
  String get residentNoMasked {
    final raw = residentNo.trim();
    if (raw.isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    // 이미 마킹된 값은 그대로 신뢰한다.
    if (raw.contains('*')) return raw;
    if (digits.length >= 7) {
      final front = digits.substring(0, 6);
      final backFirst = digits.substring(6, 7); // 성별(1~4, 5~8 등)
      return '$front-$backFirst${'*' * 6}';
    }
    // 6자리 이하(앞자리만 입력된 경우): 그대로 두되 뒤가 없다는 걸 표시.
    if (digits.length == 6) return '$digits-******';
    // 그 외(비정상 길이) — 전부 마킹.
    return '*' * (raw.length.clamp(4, 14));
  }

  /// 주민번호 뒷자리가 **실제로 채워져 있는지** (마스터에게 알려줄지 판단용).
  bool get hasResidentBack =>
      residentNo.replaceAll(RegExp(r'[^0-9]'), '').length >= 7;

  /// Scout 회원번호 — 명부의 인가번호에 해당하는 정식 회원번호.
  ///
  /// ## [요구 2026-11-03] 회원번호 노출 규칙
  ///   "회원명부에 스카우트회원번호 적는 칸을 넣고, 관리자 및 마스터는
  ///    모든 번호를 확인할 수 있도록 하고, 회원에게는 뒷번호 2자리에
  ///    * 표 처리해서 노출해줘"
  ///
  ///   · 관리자·마스터 → [scoutNoRaw] (원본 전체)
  ///   · 그 외(본인·일반회원) → [scoutNoMasked] (뒷 2자리만 `**`)
  ///
  ///   화면에서는 [scoutNoDisplay] 를 쓰면 권한 판단이 한 곳으로 모인다.
  String scoutNo;

  /// 회원번호 **추가 등록분** — 한 사람이 여러 개를 가질 수 있다.
  ///
  /// ## [요구 2026-11-03] "스카우트 고유번호는 복수로 등록되어 있는 사람도 있음
  ///   / 스카우트 고유번호를 추가로 등록할 수 있도록 할 것"
  ///
  ///  · [scoutNo] = **대표(첫 번째)** 회원번호. 기존 데이터·검색·출력과의
  ///    하위 호환이라 그대로 둔다.
  ///  · [scoutNos] = 전체 목록(대표 포함). 서버에는 `scoutNos` 배열로 저장한다.
  ///  · `scoutNos` 가 비어 있고 `scoutNo` 만 있으면 [allScoutNos] 가
  ///    `[scoutNo]` 를 돌려준다 → 구 데이터도 그대로 동작.
  List<String> scoutNos;

  /// 대표 포함 **전체** 회원번호(공백·중복 제거, 순서 유지).
  List<String> get allScoutNos {
    final out = <String>[];
    void add(String v) {
      final s = v.trim();
      if (s.isEmpty) return;
      if (!out.contains(s)) out.add(s);
    }

    for (final v in scoutNos) {
      add(v);
    }
    add(scoutNo);
    return out;
  }

  /// 대표 포함 전체 회원번호를 **권한에 따라 마킹**해 돌려준다.
  ///  · [canSeeAll] true(관리자·마스터) → 원본
  ///  · false(본인·일반회원) → 각각 뒷 2자리 `**`
  List<String> allScoutNosDisplay({required bool canSeeAll}) {
    return allScoutNos
        .map((v) => _maskScoutNo(v, reveal: canSeeAll))
        .toList();
  }

  /// 회원번호 마킹의 **단일 구현** — 뒷 2개의 숫자만 `*` 로 바꾼다.
  ///
  ///  · [reveal] true → 원본 그대로
  ///  · 구분자(-, 공백)는 세지 않는다: `123-456` → `123-4**`
  ///  · 이미 `*` 가 있으면 그대로 신뢰(이중 마킹 방지)
  ///  · 숫자가 2개 미만이면 전부 가린다(안전 우선)
  static String _maskScoutNo(String raw, {required bool reveal}) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    if (reveal) return s;
    if (s.contains('*')) return s;

    final chars = s.split('');
    var masked = 0;
    for (var i = chars.length - 1; i >= 0 && masked < 2; i--) {
      if (RegExp(r'\d').hasMatch(chars[i])) {
        chars[i] = '*';
        masked++;
      }
    }
    if (masked < 2) return '*' * s.length;
    return chars.join();
  }

  /// [scoutNo] 한 건을 마킹한 표기 (뒷 2자리 `*`).
  ///
  /// `123456` → `1234**` · `12345` → `123**` · `1234` → `12**`
  ///  · 2자리 이하거나 비어 있으면 **전부 가린다**(안전 우선).
  ///  · 이미 `*` 가 섞인 값은 그대로 신뢰한다(두 번 마킹 방지).
  ///  · 하이픈·공백 같은 구분자는 보존해 읽기 쉽게 둔다.
  ///
  /// 요구: "회원에게는 뒷번호 2자리에 * 표 처리해서 노출해줘"
  String get scoutNoMasked => _maskScoutNo(scoutNo, reveal: false);

  /// 권한에 따른 회원번호 표기.
  ///
  /// [canSeeAll] 이 true(관리자·마스터)면 원본, 아니면 [scoutNoMasked].
  /// 값이 비어 있으면 두 경우 모두 빈 문자열.
  String scoutNoDisplay({required bool canSeeAll}) {
    if (scoutNo.trim().isEmpty) return '';
    return canSeeAll ? scoutNo.trim() : scoutNoMasked;
  }

  /// 복수 회원번호를 한 칸에 넣을 때의 표기 — `16187 · 22541`
  ///
  /// [canSeeAll] 에 따라 각 값이 마킹된다. 없으면 빈 문자열.
  String scoutNosDisplay({required bool canSeeAll, String sep = ' · '}) {
    return allScoutNosDisplay(canSeeAll: canSeeAll).join(sep);
  }

  /// 비고 / 한줄소개 (명단 비고 열 등)
  String bio;

  /// 인가일 (예: "2025.12.19.")
  String date;

  /// ATAS 인가번호
  String atasNo;

  /// **ATAS 인가 당시 소속 연맹** — 범인가(`league`)와 별개다.
  ///  (요구: "아타스인가정보 중 인가번호만 있다면 나머지는 추후 입력할 수 있도록
  ///         항목만 만들고 비워 놔") 지금은 대부분 비어 있고, 추후 입력한다.
  String atasLeague;

  /// **ATAS 인가 당시 등록 단위대** — 범인가(`unit`)와 별개.
  String atasUnit;

  /// **ATAS 인가일** — 범인가(`date`)와 별개.
  String atasDate;

  /// 활동 내용
  String activity;

  /// 직위 (현재활동) — 예: "지역대장", "부장", "교수", "스텝" 등.
  ///   현재활동 통계(활동기준) 산출에 사용한다.
  String position;

  /// 메모
  String memo;

  /// 생일 (예: "1980.05.14" 또는 "05-14")
  String birthday;

  /// 기념일 (예: "2005.03.01" — 입단/기념일 등)
  String anniversary;

  /// 훈련현황 (중급 / 상급 / 커미셔너과정 / 부교수 / 교수)
  String trainingStatus;

  /// 포상 내역 (자가 입력, 예: "2024 우수지도자 표창")
  String awards;

  /// 종별 전문과정 이수과정 (자가 입력, 예: "목공지도자 1급, 응급처치 강사")
  String specialtyCourses;

  /// 수품구매현황 (자가/관리자 입력, 예: "2025.03 반팔티 1 / 2025.05 모자 1")
  String purchases;

  /// 사진 경로 (로컬 파일 경로 또는 base64), 사진을 선택/촬영하여 저장
  String photoPath;

  /// 평생회원 여부
  bool lifetimeMember;

  /// 평생회원 등록일 (예: "2022-04-13") — 등록요청 승인 시 기록.
  String lifetimeSince;

  /// 자격 지정 상태: ''(미지정) | 'approved'(승인) — 등록요청 승인 시 기록.
  String qualificationStatus;

  /// 자격 지정 메모 (승인 시 관리자 의견).
  String qualificationNote;

  /// 일반회원(비인가자) 여부 — true면 인가자가 아닌 일반 참가자/신규회원
  bool isRegular;

  /// 승인 상태: 'pending'(미승인) | 'approved'(승인) | 'held'(보류) | ''(레거시=승인)
  String approvalStatus;

  /// 미승인(승인 대기) 여부
  bool get isPendingApproval =>
      isRegular && (approvalStatus == 'pending' || approvalStatus == 'held');

  /// 승인 대기 중(pending) 여부 (보류 제외)
  bool get isPendingOnly => isRegular && approvalStatus == 'pending';

  /// 개인 접속용 비밀번호 (일반회원: 전화번호 뒤 4자리 자동, 이후 변경 가능)
  String personalPassword;

  /// 일반회원 접속 ID (휴대폰 전화번호). 비어 있으면 인가번호/전화로 로그인
  String accessPhone;

  /// 개인정보 수집·이용 및 제3자 제공 동의 여부 (가입/저장 필수)
  bool privacyAgreed;

  /// 개인정보 동의 일시 (예: "2025.09.24 10:30")
  String privacyAgreedAt;

  /// 멘토 인가번호 목록 (복수 지정 가능)
  List<String> mentors;

  /// 페런츠(보호자) 인가번호 목록 (복수 지정 가능)
  List<String> parents;

  /// 멘티대원 인가번호 목록 — 본인이 **멘토**로서 등록한 멘티들의 인가번호.
  /// (요구: 인가자 개인창의 '멘티 등록정보 창' / 멘토=멘티=페런츠 연동)
  List<String> mentees;

  /// 자녀대원 인가번호 목록 — 본인이 **페런츠**로서 등록한 자녀대원들의 인가번호.
  /// (요구: 페런츠 인가자 개인창의 '자녀대원 등록정보 창')
  List<String> children;

  /// 후원금·후원물품 이력 — 수동입력 후 관리자·마스터 승인 시 기록된다.
  ///  각 항목: {kind:'donation'|'supply', item, amount, date, note, status, ...}
  List<Map<String, dynamic>> donations;

  /// (요구) 개인정보 히스토리 — 참가신청 등으로 갱신된 email/phone/address 이력.
  ///  각 항목: {at:'YYYY-MM-DD HH:MM', by:'행사명', email?, phone?, address?}
  List<Map<String, dynamic>> infoHistory;

  /// 후원금 합계(승인된 금액 합).
  int get donationTotal => donations
      .where((d) => '${d['kind']}' == 'donation')
      .fold<int>(0, (p, d) => p + ((d['amount'] as num?)?.toInt() ?? 0));

  /// 후원물품 합계(승인된 금액 합).
  int get supplyTotal => donations
      .where((d) => '${d['kind']}' == 'supply')
      .fold<int>(0, (p, d) => p + ((d['amount'] as num?)?.toInt() ?? 0));

  /// 멘토·페런츠 연결 상태: ''(미요청) | 'pending'(요청) | 'approved'(승인) | 'held'(보류)
  /// 한 대상(멘토/페런츠)을 가리키는 연결 단위 상태.
  String linkApprovalStatus;

  /// 멘토·페런츠 연결 승인요청방법 — 'merch'(수품신청시) | 'direct'(직접입력).
  String linkRequestSource;

  /// 멘토·페런츠 연결 최초 승인요청 시각.
  String linkRequestedAt;

  /// 연결 요청/처리 메모(요청 사유·처리 의견 등)
  String linkApprovalNote;

  /// 연결 승인 처리 일시(예: "2025.09.24 10:30") 및 처리자
  String linkApprovedAt;
  String linkApprovedBy;

  /// [요구] 정보 수정요청 메모 — 비인가회원(본인)이 관리자·마스터에게 정보
  ///  수정을 요청한 내용. 처리(승인/보류/거절) 또는 실제 수정 시 해제된다.
  String linkFixNote;
  String linkFixRequestedAt;
  String linkFixRequestedBy;
  String linkFixScope;

  bool get hasLinkFixNote => linkFixNote.trim().isNotEmpty;

  /// 연간회비 납부 이력: {"2024": true, "2025": true, ...}
  Map<String, bool> feeYears;

  /// 행사 참가 여부: {"2024 정기총회": true, ...}
  Map<String, bool> eventAttend;

  /// 본인이 제안했으나 아직 관리자·마스터 승인 전인 행사명 목록.
  /// 프로필에서 '관리목록누락행사-심사중'으로 표시된다.
  List<String> pendingEventNames;

  /// 항목별 노출 권한(마스터가 회원별로 지정).
  /// key: 회원 필드명, value: 'public'(노출) | 'admin'(관리자노출) | 'hidden'(비노출).
  /// 값이 없으면 전역 기본 노출 설정(config.fieldVisibility)을 따른다.
  Map<String, String> fieldPerms;

  /// 샘플(예시) 회원 여부 — 모든 회원에게 노출된다.
  bool sample;

  /// 이름 공개 여부 — 관리자가 개인 프로필에서 토글. false면 다른 회원에게 "(이름 비공개)".
  bool nameVisible;

  /// 성별 — '남' | '여' | ''(미입력). 저장 시 남/여 중 하나는 필수.
  String gender;

  /// 성별 공개 여부 — **기본값 true(노출)**. false 로 두어야 다른 회원에게 숨겨진다.
  ///   (요구: "기본값은 현재 비노출에서 노출로 변경")
  bool genderVisible;

  /// 다른 회원(관리자·본인 제외)에게 보여줄 표시 이름.
  /// [canSeeRealName]이 true(관리자·마스터·본인)면 실제 이름,
  /// 아니면서 nameVisible=false면 "(이름 비공개)"로 마스킹한다.
  String displayName({required bool canSeeRealName}) {
    if (canSeeRealName || nameVisible) {
      return name.isEmpty ? '(이름없음)' : name;
    }
    return '(이름 비공개)';
  }

  /// 마지막 수정 시각
  DateTime? updatedAt;

  /// ATAS 인가번호를 보유했는지.
  bool get hasAtas => atasNo.trim().isNotEmpty;

  /// 검색용 통합 텍스트
  ///
  /// · ATAS 보유자는 `atas`/`아타스` 키워드로도 잡히도록 토큰을 덧붙인다.
  ///   (atasNo 자체는 숫자만 저장되므로 — 예: "358" — 키워드 검색이 불가능했다.
  ///    요구: "검색창에 atas 치면 ATAS 명부 대상자가 나오게 해줘")
  /// 사람이 실제로 **부르는 표기**를 검색 텍스트에 넣는다.
  ///
  /// ## [2026-11-02 build #579] 요구(원문)
  ///   "검색기능: 범스카우 번호, 예를들면 범415 로 검색해도 검색결과가 안나옴,
  ///    은하19호 같이 검색해도 은하스카우트가 안 나옴"
  ///
  ///   종전 [searchText] 에는 `'415'` 와 `'범스카우트'` 가 따로 있어
  ///   **`'범415'` 라는 연속 문자열이 없었다** → 부분 문자열 비교로는 절대 못 찾음.
  ///   근본 해법은 표기 해석 계층(`SearchQuery`)이지만, 그 위에 이것까지 얹으면
  ///   **일반 통합검색 경로에서도** 그대로 걸린다(이중 안전장치).
  ///
  ///   범 415  → `범415 범#415 범 415 415호`
  ///   은하 19 → `은하19 은하#19 은하 19 19호 G19 g19`
  String get searchNotation {
    if (number.trim().isEmpty) return '';
    final d = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return '';
    // 일반회원(서포터즈)은 인가번호가 없다 → 표기 대상 아님.
    if (isRegular) return '';
    final p = corpsPrefix; // '범' | '은하'
    final g = corps == 'eunha' ? ' G$d g$d' : '';
    return '$p$d $p#$d $p $d $d호$g';
  }

  /// **인가 연도** — `date`(인가일)에서 4자리 연도를 정규화해 뽑는다.
  ///
  /// ## [요구 2026-11-03] "2000년인가자 → 2000년 인가자" 연도 검색
  ///   통계 화면에 `19980년` `19710년` 이라는 **없는 연도**가 찍혀 있었다.
  ///   원인은 데이터 입력 오타였다.
  ///     #658 김영훈  '19980-6-30'  → 1998
  ///     #69  이한진  '19710-9-13'  → 1971
  ///     #875 전명호  '03.3.11'     → 2003 (2자리 연도)
  ///     #1290/1291   '09-12-28-'   → 2009 (2자리 연도, 뒤 하이픈)
  ///   값을 지우지 않고 **읽을 때 정규화**한다(원본 보존 — 마스터가 보고
  ///   고칠 수 있어야 하므로 서버 데이터는 건드리지 않는다).
  ///
  ///   규칙
  ///     ① `19980-6-30` 처럼 연도 자리에 숫자가 더 붙으면 **앞 4자리**를
  ///        연도로 보고 나머지는 월로 밀어 읽는다.
  ///     ② `03.3.11` / `09-12-28-` 처럼 2자리 연도는 **30 기준**으로 세기
  ///        판정(30~99 → 19xx, 00~29 → 20xx). 인가일이 2003/2009 이므로 맞다.
  ///     ③ 연도를 못 찾으면 0.
  int get credYear {
    final raw = date.trim();
    if (raw.isEmpty) return 0;
    // ① 4자리 연도(19xx / 20xx)가 앞쪽에 있으면 그 값을 쓴다.
    final m = RegExp(r'(19|20)\d{2}').firstMatch(raw);
    if (m != null) {
      // '19980-...' 처럼 5자리 이상이면 앞 4자리만 취한다(위 ①).
      return int.parse(m.group(0)!);
    }
    // ② 2자리 연도 형식.
    final m2 = RegExp(r'^(\d{2})\s*[.\-/]').firstMatch(raw);
    if (m2 != null) {
      final yy = int.parse(m2.group(1)!);
      return yy >= 30 ? 1900 + yy : 2000 + yy;
    }
    return 0;
  }

  /// 인가 연도 표기 — `'2003년'`. 연도를 못 읽으면 빈 문자열.
  String get credYearLabel => credYear > 0 ? '$credYear년' : '';

  /// 통합검색용 텍스트(소문자). 모든 검색 경로의 공통 재료.
  String get searchText {
    final base =
        '$number $name $nameEn $league $unit $regLeague $regUnit $address '
        '$zipCode $phone $tel $email $residentNo $scoutNo $bio $atasNo '
        // [요구 2026-11-03] 복수 회원번호도 검색에 걸리게 한다.
        '${allScoutNos.join(' ')} '
        '$activity $position $memo $birthday $anniversary $trainingStatus '
        '$awards $specialtyCourses $purchases $gender '
        '${mentors.join(' ')} ${parents.join(' ')} '
        '${mentees.join(' ')} ${children.join(' ')}';
    // ATAS 를 가진 회원만 'atas 아타스' 토큰을 검색어에 포함한다.
    final atas = hasAtas ? ' atas 아타스' : '';
    // [build #579] 사람 표기('범415'·'은하19호')도 통합검색에 포함.
    final notation = searchNotation.isEmpty ? '' : ' $searchNotation';
    // [요구 2026-11-03] 연도 검색 — '2000년'·'2000년인가자' 로 찾을 수 있게
    //  인가 연도를 검색 텍스트에 넣는다. (오타 데이터도 정규화된 연도로 걸린다)
    final yr = credYear > 0 ? ' $credYear $credYear년' : '';
    return '$base$atas$notation$yr'.toLowerCase();
  }

  /// 다른 회원에게 보여줄 성별 — 관리자·마스터·본인은 실제값, 아니면 비노출 시 ''.
  String displayGender({required bool canSeeRealName}) {
    if (canSeeRealName || genderVisible) return gender;
    return '';
  }

  /// 로그인 아이디 — 표준은 **'tiger<인가번호>'**(요구: "ID의 tiger 붙여 주고").
  ///  · 일반회원(서포터즈): 전화번호(숫자)
  ///  · 인가자: 'tiger' + 인가번호 (예: 인가번호 415 → 'tiger415')
  ///  · (하위호환) 명시된 접속전화(accessPhone)가 있으면 그 숫자를 그대로 사용
  static const String loginPrefix = 'tiger';
  String get loginId {
    final ap = accessPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (ap.isNotEmpty) return ap;
    final n = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (isRegular) return n;
    if (n.isEmpty) return number.trim();
    return '$loginPrefix$n';
  }

  /// 전화번호 뒤 4자리 (기본 개인비밀번호)
  String get phoneLast4 {
    final d = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 4 ? d.substring(d.length - 4) : d;
  }

  /// 전화번호에서 숫자만 추출 (하이픈 무관 검색용)
  String get phoneDigits => phone.replaceAll(RegExp(r'[^0-9]'), '');

  /// 번호의 **숫자부만** 정수로. 은하 `'G19'` 도 19 로 읽는다.
  ///
  /// ## [2026-11-02 build #579] `int.tryParse(number)` → 숫자 추출로 교체
  ///   종전 `int.tryParse('G19')` 는 **null → 0** 이었다. 그래서 은하 회원은
  ///   번호 비교(`범19` / `은하19호`)와 범위 검색에서 **통째로 빠졌다**.
  ///   (`범위 검색은 그대로 동작` 테스트에서 범 19 만 잡히고 은하 19 는
  ///    잡히지 않던 원인.)
  int get numberInt {
    final d = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return 0;
    return int.tryParse(d) ?? 0;
  }

  /// 소속(corps) 표기 말머리 — 범스카우트 '범' / 은하스카우트 '은하'.
  String get corpsPrefix => corps == 'eunha' ? '은하' : '범';

  /// ── [번호체계 2026-10-26] 은하 번호는 이미 'G43' 이다 ──────────────────
  ///  요구: "은하스카우트는 1~165 … G1~G165 … G는 Galaxy(은하)의 약자임"
  ///
  ///  **역할 구분 (요구 2026-10-27)**
  ///   "은하 스카우트를 G라고 구분하는 것은 매우 좋음 /
  ///    개인카드에는 G대신 은하로 표기해야 함"
  ///
  ///   · `_numKey` = **명부·목록 전용 구분자** `G43`
  ///       수천 건을 훑을 때 `G` 한 글자가 범 43 과 은하 43 을 즉시 갈라준다.
  ///   · `cardNumberLabel` = **개인카드 전용** `은하#43`
  ///       한 사람만 보는 화면에서는 약어보다 읽히는 말이 맞다.
  ///   · `numLabelOf` = 정적(보고서·메시지) `은하#43`
  ///
  ///  하위호환: 서버 캐시 등으로 '43' 처럼 G 없는 값이 와도 화면에는
  ///  'G43' 으로 보이게 정규화한다(체계가 눈에 보여야 혼동이 줄어든다).
  String get _numKey {
    final d = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return '';
    if (corps == 'eunha') return 'G$d';
    return d;
  }

  /// **명부·목록 전용** 인가번호 — 은하 `G43`, 범 `415`.
  ///   (개인카드는 [cardNumberLabel] 을 쓴다.)
  String get rosterNumber => _numKey;

  /// 말머리(소속 배지) 라벨 — 은하'은하' / 범'범' / 일반회원(비인가)'일반'.
  ///   (요구) "일반 비인가자는 범 단추 대신 일반 단추를 달아줘.
  ///    범 단추는 인가자 중심(=인가자에게만 범 단추)."
  ///   즉, 인가자(범/은하)에게만 '범'/'은하' 말머리를 달고, 비인가(일반회원)는
  ///   '일반' 말머리를 단다(범 단추를 달지 않는다).
  String get corpsMarkLabel {
    if (isRegular) return '일반';
    return corps == 'eunha' ? '은하' : '범';
  }

  // ══════════════════════════════════════════════════════════════════════
  // [신원 모델 2026-10-29] 이름은 ID 가 아니다 — 구조적 재발 방지
  //
  //  ## 사고: 비인가자 '김순철' 이 범인가자 동명이인 카드로 연결됨
  //   원인은 두 가지가 겹친 것이다.
  //     ① 참가자 항목에 "이 사람이 인가자인지" 를 **저장하지 않았다**.
  //     ② 조회 함수가 번호가 없으면 **이름으로 폴백**했고,
  //        `byName()` 은 동명이인이면 **첫 번째를 조용히** 돌려줬다.
  //   → '번호 없음' 이 정상 상태(비인가자)인데 '실패' 로 오해한 설계 결함.
  //
  //  ## 해결: 신원을 **타입**으로 못박는다
  //   · `identityKey` = 카드 연결에 쓰는 **유일한 키** (이름 절대 사용 금지)
  //   · `isVerifiedIdentity` = 신뢰할 수 있는 키인가
  //   이름은 `nameHint`(표시용 힌트)로만 쓰고, **동명이인이면 힌트로도 쓰지 않는다**.
  // ══════════════════════════════════════════════════════════════════════

  /// 카드 연결용 **정규 신원 키** — `tsak:415` / `eunha:G75` / `reg:01074451179`.
  ///
  /// · 인가자: `corps:번호`  (은하는 접두어 G 보존 → 범 75 와 절대 충돌 안 함)
  /// · 비인가(일반): `reg:전화숫자`
  /// · 전화번호도 없으면 **빈 문자열** — 이때는 카드 연결을 포기한다.
  ///   (이름으로 대신 찾지 않는다. 그게 사고의 원인이었다.)
  String get identityKey {
    final d = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (!isRegular && d.isNotEmpty) {
      return corps == 'eunha' ? 'eunha:G$d' : 'tsak:$d';
    }
    final ph = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (ph.isNotEmpty) return 'reg:$ph';
    return '';
  }

  /// [identityKey] 가 **믿을 수 있는** 키인지 — 빈 키로 카드를 열면 안 된다.
  bool get isVerifiedIdentity => identityKey.isNotEmpty;

  /// 동명이인 판별에 쓰는 정규화 이름(공백 제거).
  String get nameKey => name.replaceAll(RegExp(r'\s+'), '').trim();

  /// 소속 단체 정식 명칭 — 개인창 명칭 전환용(범스카우트 → 은하스카우트).
  String get corpsFullName => corps == 'eunha' ? '은하스카우트' : '범스카우트';

  /// 소속 중앙회 명칭 — 은하스카우트 개인창 헤더용.
  String get corpsOrgName => corps == 'eunha' ? '한국은하스카우트중앙회' : '한국범스카우트중앙회';

  /// 인가번호 표기 라벨 — 은하스카우트는 '은하#43', 범스카우트는 '범#43'.
  ///   · 일반회원(비인가자)은 인가번호가 **없다**. 대신 전화번호를 써서
  ///     '일반#01074451179' 로 표기한다.
  ///   (요구: "일반회원은 회원명부에서 범#01074451179로 표시하지 말고 →
  ///    일반#01074451179로 표시해줘 (모든 개인카드에 동일규칙임)")
  ///   (기존: "은하스카우트는 #43 → 은하#43, 모든 창에서 그렇게 표시")
  String get numberLabel {
    if (isRegular) {
      final d = phoneDigits;
      final tail = d.isNotEmpty ? d : number.replaceAll(RegExp(r'[^0-9]'), '');
      return tail.isEmpty ? '' : '일반#$tail';
    }
    if (number.trim().isEmpty) return '';
    // 은하 번호는 이미 G 를 포함하므로 말머리를 붙이지 않는다('G43').
    if (corps == 'eunha') return _numKey;
    return '$corpsPrefix#$number';
  }

  /// 소속 말머리를 붙인 번호(은하#43). [prefixHash] 면 '#' 표기, 아니면 '은하43'.
  ///   일반회원은 '일반#<전화>' 규칙(numberLabel)을 그대로 따른다.
  ///
  /// ## [요구 2026-10-27] `G` 는 **목록 전용 구분자**, 카드에서는 '은하'
  ///  "은하 스카우트를 G라고 구분하는 것은 매우 좋음 / 개인카드에는
  ///   G대신 은하로 표기해야 함"
  ///
  ///  정리하면 역할이 다르다.
  ///   · **명부·목록·검색**  → `G43`  … 수천 건을 훑을 때 `G` 한 글자가
  ///       범 43 과 은하 43 을 순간적으로 갈라준다(구분자로서 탁월).
  ///   · **개인카드(단일 열람)** → `은하#43` … 한 사람만 보고 있으므로
  ///       약어보다 **읽히는 말**이 맞다. `범#415` 와 같은 '말머리+#번호'
  ///       문법을 써서 두 카드가 같은 규칙으로 읽힌다.
  ///   · **내보내기·보고서**  → `은하43` (prefixHash=false)
  ///
  ///  즉 `_numKey`('G43')는 명부 표기이고, 이 함수는 **사람이 읽는 표기**다.
  String numPrefix({bool prefixHash = true}) {
    if (isRegular) return numberLabel;
    if (number.trim().isEmpty) return '';
    // [요구 2026-10-27] 카드·보고서에서는 G 대신 '은하' 말머리를 쓴다.
    return prefixHash ? '$corpsPrefix#$number' : '$corpsPrefix$number';
  }

  /// **개인카드 전용** 인가번호 — 은하도 '은하#43' 으로 말머리를 붙인다.
  ///
  /// (요구 2026-10-27) "개인카드에는 G대신 은하로 표기해야 함"
  ///
  /// `numberLabel`('G43')은 **명부·목록용 구분자**이므로 그대로 두고,
  /// 개인카드(헤더 큰 번호 · 범인가정보 첫 줄)에서만 이 게터를 쓴다.
  ///   · 범   : `범#415`
  ///   · 은하 : `은하#43`
  ///   · 일반 : `일반#0107445…`  (인가번호 없음 — 전화번호)
  String get cardNumberLabel {
    // [2026-10-29] 서포터즈는 인가번호가 없다. 전화번호를 그대로 크게
    //  노출하면 개인카드 첫 줄이 '일반#01027021126' 처럼 길고 어색해진다.
    //  머리글은 '서포터즈'로 짧게 쓰고, 실제 번호는 아래 항목 행에서 보여준다.
    if (isRegular) return '서포터즈';
    if (number.trim().isEmpty) return '';
    if (corps == 'eunha') {
      final d = number.replaceAll(RegExp(r'[^0-9]'), '');
      return d.isEmpty ? '' : '은하#$d';
    }
    return '범#$number';
  }

  /// 신원 구분 — 카드·표·출력의 정규 명칭.
  ///
  /// ## [2026-10-29 서포터즈 사고] 이분법이 원인이었다
  /// 종전에는 `corps == 'eunha' ? 은하 : 범` **이분법**이라, 일반회원
  /// (서포터즈)이 corps 가 비어 있다는 이유로 **'범' 가지로 떨어졌다**.
  /// 그래서 서포터즈 개인카드에 **'범인가 정보'**, 항목에 **'범인가번호'**가
  /// 표시됐다. 서포터즈는 범 인가자가 아니고 인가번호도 없다.
  AttendeeKind get kind {
    if (isRegular) return AttendeeKind.supporter;
    return corps == 'eunha' ? AttendeeKind.eunha : AttendeeKind.tsak;
  }

  /// 인가정보 카드의 항목 라벨 — '범인가번호' / '은하인가번호' / '서포터즈 번호'.
  ///  (카드 제목이 '은하인가 정보' 인데 항목이 '범인가번호' 면 어긋난다.)
  String get numberRowLabel => kind.numberLabel;

  /// 인가정보 카드 항목의 **값** — 라벨과 짝을 맞춘다.
  ///  · 범/은하 : `범#415`, `은하#43`
  ///  · 서포터즈: 전화번호(없으면 빈 값) — **'서포터즈 번호 : 서포터즈'** 처럼
  ///    라벨과 값이 같은 말이 되어 정보가 0 이 되던 버그 수정.
  ///    (요구: 서포터즈는 인가번호가 없으므로 실제 연락처를 보여준다)
  String get numberRowValue {
    if (isRegular) {
      final ph = phone.trim();
      if (ph.isNotEmpty) return ph;
      final tel = this.tel.trim();
      if (tel.isNotEmpty) return tel;
      return '';
    }
    return cardNumberLabel;
  }

  /// 인가정보 카드 제목 — '범스카우트 인가 정보' / '은하스카우트 인가 정보'
  /// / **'서포터즈 정보'**.
  String get credentialCardTitle => kind.cardTitle;

  /// 화면 표기용 인가번호 — **은하스카우트는 '은하'+번호**(예: 은하46),
  ///   범스카우트는 기존처럼 번호만(예: 46). '#' 없이 붙여 쓴다.
  ///   일반회원은 인가번호 대신 전화번호를 붙여 '일반010…' 로 표기한다.
  ///   (요구: "은하스카우트의 모든 창에는 인가번호 앞에 은하 접두어를 넣을 것
  ///    '은하'+'n', 예)은하46 … 그래야 범스카우트랑 헷갈리지 않아")
  String get displayNumber {
    if (isRegular) {
      final d = phoneDigits;
      return d.isEmpty ? number : '일반$d';
    }
    // [번호체계 2026-10-26] 은하는 'G43' 자체가 표기다(은하G43 아님).
    return corps == 'eunha' ? _numKey : number;
  }

  /// (정적) Raw 값용 인가번호 표기 — 서버 map 등 Member 미생성 데이터용.
  ///   예: ['43','eunha'] → '은하#43', ['43'] → '범#43'.
  ///   [isRegular] 가 true 면 인가번호가 없으므로 '일반#<값>' 로 표기한다.
  ///
  /// ## [요구 2026-10-27] `G` 는 **명부 전용**, 이 함수는 **사람이 읽는 표기**
  ///  "은하 스카우트를 G라고 구분하는 것은 매우 좋음 / 개인카드에는
  ///   G대신 은하로 표기해야 함"
  ///  → 정적 라벨은 카드·보고서·메시지에 쓰이므로 `은하#43` 을 기본으로 한다.
  ///    명부의 `G43` 표기는 `Member._numKey`(인스턴스 게터)가 담당한다.
  static String numLabelOf(
    String number, [
    String corps = 'tsak',
    bool isRegular = false,
  ]) {
    final n = number.trim();
    if (n.isEmpty) return '';
    if (isRegular) return '일반#$n';
    if (corps == 'eunha') {
      final d = n.replaceAll(RegExp(r'[^0-9]'), '');
      return d.isEmpty ? '' : '은하#$d';
    }
    return '범#$n';
  }

  /// 납부한 연도 목록
  List<String> get paidYears =>
      feeYears.entries.where((e) => e.value).map((e) => e.key).toList()..sort();

  /// 참가한 행사 목록
  List<String> get attendedEvents =>
      eventAttend.entries.where((e) => e.value).map((e) => e.key).toList()
        ..sort();

  /// 자격 지정이 승인되었는지 여부.
  bool get qualificationApproved => qualificationStatus.trim() == 'approved';

  Map<String, dynamic> toMap() => {
    'id': id,
    'number': number,
    'name': name,
    'nameEn': nameEn,
    'corps': corps,
    'league': league,
    'unit': unit,
    'regLeague': regLeague,
    'regUnit': regUnit,
    'address': address,
    'zipCode': zipCode,
    'phone': phone,
    'tel': tel,
    'email': email,
    'residentNo': residentNo,
    'scoutNo': scoutNo,
    // [요구 2026-11-03] 복수 회원번호 — 대표(scoutNo)를 포함한 전체 목록.
    'scoutNos': allScoutNos,
    'bio': bio,
    'date': date,
    'atasNo': atasNo,
    'atasLeague': atasLeague,
    'atasUnit': atasUnit,
    'atasDate': atasDate,
    'activity': activity,
    'position': position,
    'memo': memo,
    'birthday': birthday,
    'anniversary': anniversary,
    'trainingStatus': trainingStatus,
    'awards': awards,
    'specialtyCourses': specialtyCourses,
    'purchases': purchases,
    'photoPath': photoPath,
    'lifetimeMember': lifetimeMember,
    'lifetimeSince': lifetimeSince,
    'qualificationStatus': qualificationStatus,
    'qualificationNote': qualificationNote,
    'isRegular': isRegular,
    'approvalStatus': approvalStatus,
    'personalPassword': personalPassword,
    'accessPhone': accessPhone,
    'privacyAgreed': privacyAgreed,
    'privacyAgreedAt': privacyAgreedAt,
    'mentors': mentors,
    'parents': parents,
    'mentees': mentees,
    'children': children,
    'donations': donations,
    'infoHistory': infoHistory,
    'linkApprovalStatus': linkApprovalStatus,
    'linkRequestSource': linkRequestSource,
    'linkRequestedAt': linkRequestedAt,
    'linkApprovalNote': linkApprovalNote,
    'linkApprovedAt': linkApprovedAt,
    'linkApprovedBy': linkApprovedBy,
    'linkFixNote': linkFixNote,
    'linkFixRequestedAt': linkFixRequestedAt,
    'linkFixRequestedBy': linkFixRequestedBy,
    'linkFixScope': linkFixScope,
    'feeYears': feeYears,
    'eventAttend': eventAttend,
    'pendingEventNames': pendingEventNames,
    'fieldPerms': fieldPerms,
    'sample': sample,
    'nameVisible': nameVisible,
    'gender': gender,
    'genderVisible': genderVisible,
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
  };

  factory Member.fromMap(Map<dynamic, dynamic> map) {
    Map<String, bool> castBoolMap(dynamic v) {
      final out = <String, bool>{};
      if (v is Map) {
        v.forEach((k, val) => out['$k'] = val == true);
      }
      return out;
    }

    List<String> castStrList(dynamic v) {
      if (v is List) {
        return v.map((e) => '$e').where((s) => s.isNotEmpty).toList();
      }
      if (v is String && v.trim().isNotEmpty) {
        return v.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
      }
      return <String>[];
    }

    return Member(
      id: '${map['id'] ?? ''}',
      number: '${map['number'] ?? ''}',
      name: '${map['name'] ?? ''}',
      nameEn: '${map['nameEn'] ?? ''}',
      corps: (map['corps'] != null && '${map['corps']}'.isNotEmpty)
          ? '${map['corps']}'
          : 'tsak',
      league: normalizeLeague('${map['league'] ?? ''}'),
      unit: '${map['unit'] ?? ''}',
      regLeague: normalizeLeague('${map['regLeague'] ?? ''}'),
      regUnit: '${map['regUnit'] ?? ''}',
      address: '${map['address'] ?? ''}',
      zipCode: '${map['zipCode'] ?? ''}',
      phone: '${map['phone'] ?? ''}',
      tel: '${map['tel'] ?? ''}',
      email: '${map['email'] ?? ''}',
      residentNo: '${map['residentNo'] ?? ''}',
      scoutNo: '${map['scoutNo'] ?? ''}',
      // [요구 2026-11-03] 복수 회원번호 — 서버가 배열로 주면 그대로 읽고,
      //  구 데이터(scoutNo 문자열만)면 [allScoutNos] 가 대표값으로 채운다.
      scoutNoList: castStrList(map['scoutNos']),
      bio: '${map['bio'] ?? ''}',
      date: '${map['date'] ?? ''}',
      atasNo: '${map['atasNo'] ?? ''}',
      atasLeague: '${map['atasLeague'] ?? ''}',
      atasUnit: '${map['atasUnit'] ?? ''}',
      atasDate: '${map['atasDate'] ?? ''}',
      activity: '${map['activity'] ?? ''}',
      position: '${map['position'] ?? ''}',
      memo: '${map['memo'] ?? ''}',
      birthday: '${map['birthday'] ?? ''}',
      anniversary: '${map['anniversary'] ?? ''}',
      trainingStatus: '${map['trainingStatus'] ?? ''}',
      awards: '${map['awards'] ?? ''}',
      specialtyCourses: '${map['specialtyCourses'] ?? ''}',
      purchases: '${map['purchases'] ?? ''}',
      photoPath: '${map['photoPath'] ?? ''}',
      lifetimeMember: map['lifetimeMember'] == true,
      lifetimeSince: '${map['lifetimeSince'] ?? ''}',
      qualificationStatus: '${map['qualificationStatus'] ?? ''}',
      qualificationNote: '${map['qualificationNote'] ?? ''}',
      isRegular: map['isRegular'] == true,
      approvalStatus: '${map['approvalStatus'] ?? ''}',
      personalPassword: '${map['personalPassword'] ?? ''}',
      accessPhone: '${map['accessPhone'] ?? ''}',
      privacyAgreed: map['privacyAgreed'] == true,
      privacyAgreedAt: '${map['privacyAgreedAt'] ?? ''}',
      mentors: castStrList(map['mentors']),
      parents: castStrList(map['parents']),
      mentees: castStrList(map['mentees']),
      children: castStrList(map['children']),
      donations: () {
        final out = <Map<String, dynamic>>[];
        final v = map['donations'];
        if (v is List) {
          for (final e in v) {
            if (e is Map) out.add(e.cast<String, dynamic>());
          }
        }
        return out;
      }(),
      infoHistory: () {
        final out = <Map<String, dynamic>>[];
        final v = map['infoHistory'];
        if (v is List) {
          for (final e in v) {
            if (e is Map) out.add(e.cast<String, dynamic>());
          }
        }
        return out;
      }(),
      linkApprovalStatus: '${map['linkApprovalStatus'] ?? ''}',
      linkRequestSource: '${map['linkRequestSource'] ?? ''}',
      linkRequestedAt: '${map['linkRequestedAt'] ?? ''}',
      linkApprovalNote: '${map['linkApprovalNote'] ?? ''}',
      linkApprovedAt: '${map['linkApprovedAt'] ?? ''}',
      linkApprovedBy: '${map['linkApprovedBy'] ?? ''}',
      linkFixNote: '${map['linkFixNote'] ?? ''}',
      linkFixRequestedAt: '${map['linkFixRequestedAt'] ?? ''}',
      linkFixRequestedBy: '${map['linkFixRequestedBy'] ?? ''}',
      linkFixScope: '${map['linkFixScope'] ?? ''}',
      feeYears: castBoolMap(map['feeYears']),
      eventAttend: castBoolMap(map['eventAttend']),
      pendingEventNames: castStrList(map['pendingEventNames']),
      fieldPerms: () {
        final out = <String, String>{};
        final v = map['fieldPerms'];
        if (v is Map) {
          v.forEach((k, val) => out['$k'] = '$val');
        }
        return out;
      }(),
      sample: map['sample'] == true,
      nameVisible: map['nameVisible'] != false,
      gender: '${map['gender'] ?? ''}',
      genderVisible: map['genderVisible'] != false,
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  Member copyWith({
    List<Map<String, dynamic>>? infoHistory,
    String? number,
    String? name,
    String? nameEn,
    String? corps,
    String? league,
    String? unit,
    String? regLeague,
    String? regUnit,
    String? address,
    String? zipCode,
    String? phone,
    String? tel,
    String? email,
    String? residentNo,
    String? scoutNo,
    List<String>? scoutNoList,
    String? bio,
    String? date,
    String? atasNo,
    String? atasLeague,
    String? atasUnit,
    String? atasDate,
    String? activity,
    String? position,
    String? memo,
    String? birthday,
    String? anniversary,
    String? trainingStatus,
    String? awards,
    String? specialtyCourses,
    String? purchases,
    String? photoPath,
    bool? lifetimeMember,
    String? lifetimeSince,
    String? qualificationStatus,
    String? qualificationNote,
    bool? isRegular,
    String? approvalStatus,
    String? personalPassword,
    String? accessPhone,
    bool? privacyAgreed,
    String? privacyAgreedAt,
    List<String>? mentors,
    List<String>? parents,
    List<String>? mentees,
    List<String>? children,
    String? linkApprovalStatus,
    String? linkRequestSource,
    String? linkRequestedAt,
    String? linkApprovalNote,
    String? linkApprovedAt,
    String? linkApprovedBy,
    String? linkFixNote,
    String? linkFixRequestedAt,
    String? linkFixRequestedBy,
    String? linkFixScope,
    Map<String, bool>? feeYears,
    Map<String, bool>? eventAttend,
    Map<String, String>? fieldPerms,
    List<Map<String, dynamic>>? donations,
    bool? sample,
    bool? nameVisible,
    String? gender,
    bool? genderVisible,
    DateTime? updatedAt,
  }) {
    return Member(
      id: id,
      number: number ?? this.number,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      corps: corps ?? this.corps,
      league: league ?? this.league,
      unit: unit ?? this.unit,
      regLeague: regLeague ?? this.regLeague,
      regUnit: regUnit ?? this.regUnit,
      address: address ?? this.address,
      zipCode: zipCode ?? this.zipCode,
      phone: phone ?? this.phone,
      tel: tel ?? this.tel,
      email: email ?? this.email,
      residentNo: residentNo ?? this.residentNo,
      scoutNo: scoutNo ?? this.scoutNo,
      scoutNoList: scoutNoList ?? List<String>.from(this.scoutNos),
      bio: bio ?? this.bio,
      date: date ?? this.date,
      atasNo: atasNo ?? this.atasNo,
      atasLeague: atasLeague ?? this.atasLeague,
      atasUnit: atasUnit ?? this.atasUnit,
      atasDate: atasDate ?? this.atasDate,
      activity: activity ?? this.activity,
      position: position ?? this.position,
      memo: memo ?? this.memo,
      birthday: birthday ?? this.birthday,
      anniversary: anniversary ?? this.anniversary,
      trainingStatus: trainingStatus ?? this.trainingStatus,
      awards: awards ?? this.awards,
      specialtyCourses: specialtyCourses ?? this.specialtyCourses,
      purchases: purchases ?? this.purchases,
      photoPath: photoPath ?? this.photoPath,
      lifetimeMember: lifetimeMember ?? this.lifetimeMember,
      lifetimeSince: lifetimeSince ?? this.lifetimeSince,
      qualificationStatus: qualificationStatus ?? this.qualificationStatus,
      qualificationNote: qualificationNote ?? this.qualificationNote,
      isRegular: isRegular ?? this.isRegular,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      personalPassword: personalPassword ?? this.personalPassword,
      accessPhone: accessPhone ?? this.accessPhone,
      privacyAgreed: privacyAgreed ?? this.privacyAgreed,
      privacyAgreedAt: privacyAgreedAt ?? this.privacyAgreedAt,
      mentors: mentors ?? List<String>.from(this.mentors),
      parents: parents ?? List<String>.from(this.parents),
      mentees: mentees ?? List<String>.from(this.mentees),
      children: children ?? List<String>.from(this.children),
      donations: donations ?? List<Map<String, dynamic>>.from(this.donations),
      infoHistory: infoHistory ?? this.infoHistory,
      linkApprovalStatus: linkApprovalStatus ?? this.linkApprovalStatus,
      linkRequestSource: linkRequestSource ?? this.linkRequestSource,
      linkRequestedAt: linkRequestedAt ?? this.linkRequestedAt,
      linkApprovalNote: linkApprovalNote ?? this.linkApprovalNote,
      linkApprovedAt: linkApprovedAt ?? this.linkApprovedAt,
      linkApprovedBy: linkApprovedBy ?? this.linkApprovedBy,
      linkFixNote: linkFixNote ?? this.linkFixNote,
      linkFixRequestedAt: linkFixRequestedAt ?? this.linkFixRequestedAt,
      linkFixRequestedBy: linkFixRequestedBy ?? this.linkFixRequestedBy,
      linkFixScope: linkFixScope ?? this.linkFixScope,
      feeYears: feeYears ?? Map<String, bool>.from(this.feeYears),
      eventAttend: eventAttend ?? Map<String, bool>.from(this.eventAttend),
      fieldPerms: fieldPerms ?? Map<String, String>.from(this.fieldPerms),
      sample: sample ?? this.sample,
      nameVisible: nameVisible ?? this.nameVisible,
      gender: gender ?? this.gender,
      genderVisible: genderVisible ?? this.genderVisible,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
