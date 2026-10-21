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
    this.genderVisible = false,
    this.updatedAt,
  }) : mentors = mentors ?? <String>[],
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
  String residentNo;

  /// Scout 회원번호 — 명부의 인가번호에 해당하는 정식 회원번호.
  String scoutNo;

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

  /// 성별 공개 여부 — 기본값 false(비노출). true여야 다른 회원에게 노출된다.
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
  String get searchText {
    final base =
        '$number $name $nameEn $league $unit $regLeague $regUnit $address '
        '$zipCode $phone $tel $email $residentNo $scoutNo $bio $atasNo '
        '$activity $position $memo $birthday $anniversary $trainingStatus '
        '$awards $specialtyCourses $purchases $gender '
        '${mentors.join(' ')} ${parents.join(' ')} '
        '${mentees.join(' ')} ${children.join(' ')}';
    // ATAS 를 가진 회원만 'atas 아타스' 토큰을 검색어에 포함한다.
    final atas = hasAtas ? ' atas 아타스' : '';
    return '$base$atas'.toLowerCase();
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

  int get numberInt => int.tryParse(number) ?? 0;

  /// 소속(corps) 표기 말머리 — 범스카우트 '범' / 은하스카우트 '은하'.
  String get corpsPrefix => corps == 'eunha' ? '은하' : '범';

  /// 말머리(소속 배지) 라벨 — 은하'은하' / 범'범' / 일반회원(비인가)'일반'.
  ///   (요구) "일반 비인가자는 범 단추 대신 일반 단추를 달아줘.
  ///    범 단추는 인가자 중심(=인가자에게만 범 단추)."
  ///   즉, 인가자(범/은하)에게만 '범'/'은하' 말머리를 달고, 비인가(일반회원)는
  ///   '일반' 말머리를 단다(범 단추를 달지 않는다).
  String get corpsMarkLabel {
    if (isRegular) return '일반';
    return corps == 'eunha' ? '은하' : '범';
  }

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
    return number.trim().isEmpty ? '' : '$corpsPrefix#$number';
  }

  /// 소속 말머리를 붙인 번호(은하#43). [prefixHash] 면 '#' 표기, 아니면 '은하43'.
  ///   일반회원은 '일반#<전화>' 규칙(numberLabel)을 그대로 따른다.
  String numPrefix({bool prefixHash = true}) {
    if (isRegular) return numberLabel;
    if (number.trim().isEmpty) return '';
    return prefixHash ? '$corpsPrefix#$number' : '$corpsPrefix$number';
  }

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
    return corps == 'eunha'
        ? '은하${number.replaceAll(RegExp(r'[^0-9]'), '')}'
        : number;
  }

  /// (정적) Raw 값용 인가번호 표기 — 서버 map 등 Member 미생성 데이터용.
  ///   예: ['43','eunha'] → '은하#43', ['43'] → '범#43'.
  ///   [isRegular] 가 true 면 인가번호가 없으므로 '일반#<값>' 로 표기한다.
  static String numLabelOf(
    String number, [
    String corps = 'tsak',
    bool isRegular = false,
  ]) {
    final n = number.trim();
    if (n.isEmpty) return '';
    if (isRegular) return '일반#$n';
    return '${corps == 'eunha' ? '은하' : '범'}#$n';
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
      if (v is List)
        return v.map((e) => '$e').where((s) => s.isNotEmpty).toList();
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
      genderVisible: map['genderVisible'] == true,
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
