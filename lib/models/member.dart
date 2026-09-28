/// 한국범스카우트 중앙회 인가자(회원) 모델
/// 요구사항: 인가번호, 이름, 주소, 단위대, 소속연맹, 활동, 메모,
///           사진, QR, 메일, 연간회비(평생/연도별), 행사참가, ATAS 인가번호, 인가일
class Member {
  Member({
    required this.id,
    required this.number,
    required this.name,
    this.league = '',
    this.unit = '',
    this.regLeague = '',
    this.regUnit = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.date = '',
    this.atasNo = '',
    this.activity = '',
    this.memo = '',
    this.birthday = '',
    this.anniversary = '',
    this.trainingStatus = '',
    this.awards = '',
    this.specialtyCourses = '',
    this.purchases = '',
    this.photoPath = '',
    this.lifetimeMember = false,
    this.isRegular = false,
    this.approvalStatus = '',
    this.personalPassword = '',
    this.accessPhone = '',
    this.privacyAgreed = false,
    this.privacyAgreedAt = '',
    List<String>? mentors,
    List<String>? parents,
    this.linkApprovalStatus = '',
    this.linkApprovalNote = '',
    this.linkApprovedAt = '',
    this.linkApprovedBy = '',
    Map<String, bool>? feeYears,
    Map<String, bool>? eventAttend,
    this.sample = false,
    this.nameVisible = true,
    this.gender = '',
    this.genderVisible = false,
    this.updatedAt,
  }) : mentors = mentors ?? <String>[],
       parents = parents ?? <String>[],
       feeYears = feeYears ?? <String, bool>{},
       eventAttend = eventAttend ?? <String, bool>{};

  /// 내부 고유 ID
  String id;

  /// 인가번호 (예: "2186")
  String number;

  /// 성명
  String name;

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

  /// 핸드폰
  String phone;

  /// 이메일
  String email;

  /// 인가일 (예: "2025.12.19.")
  String date;

  /// ATAS 인가번호
  String atasNo;

  /// 활동 내용
  String activity;

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

  /// 멘토·페런츠 연결 상태: ''(미요청) | 'pending'(요청) | 'approved'(승인) | 'held'(보류)
  /// 한 대상(멘토/페런츠)을 가리키는 연결 단위 상태.
  String linkApprovalStatus;

  /// 연결 요청/처리 메모(요청 사유·처리 의견 등)
  String linkApprovalNote;

  /// 연결 승인 처리 일시(예: "2025.09.24 10:30") 및 처리자
  String linkApprovedAt;
  String linkApprovedBy;

  /// 연간회비 납부 이력: {"2024": true, "2025": true, ...}
  Map<String, bool> feeYears;

  /// 행사 참가 여부: {"2024 정기총회": true, ...}
  Map<String, bool> eventAttend;

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

  /// 검색용 통합 텍스트
  String get searchText =>
      '$number $name $league $unit $regLeague $regUnit $address $phone $email $atasNo $activity $memo $birthday $anniversary $trainingStatus $awards $specialtyCourses $purchases $gender ${mentors.join(' ')} ${parents.join(' ')}'
          .toLowerCase();

  /// 다른 회원에게 보여줄 성별 — 관리자·마스터·본인은 실제값, 아니면 비노출 시 ''.
  String displayGender({required bool canSeeRealName}) {
    if (canSeeRealName || genderVisible) return gender;
    return '';
  }

  /// 로그인 아이디 (일반회원은 전화번호, 인가자는 인가번호)
  String get loginId => accessPhone.trim().isNotEmpty
      ? accessPhone.replaceAll(RegExp(r'[^0-9]'), '')
      : number;

  /// 전화번호 뒤 4자리 (기본 개인비밀번호)
  String get phoneLast4 {
    final d = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 4 ? d.substring(d.length - 4) : d;
  }

  /// 전화번호에서 숫자만 추출 (하이픈 무관 검색용)
  String get phoneDigits => phone.replaceAll(RegExp(r'[^0-9]'), '');

  int get numberInt => int.tryParse(number) ?? 0;

  /// 납부한 연도 목록
  List<String> get paidYears =>
      feeYears.entries.where((e) => e.value).map((e) => e.key).toList()..sort();

  /// 참가한 행사 목록
  List<String> get attendedEvents =>
      eventAttend.entries.where((e) => e.value).map((e) => e.key).toList()
        ..sort();

  Map<String, dynamic> toMap() => {
    'id': id,
    'number': number,
    'name': name,
      'league': league,
      'unit': unit,
      'regLeague': regLeague,
      'regUnit': regUnit,
      'address': address,
    'phone': phone,
    'email': email,
    'date': date,
    'atasNo': atasNo,
    'activity': activity,
    'memo': memo,
    'birthday': birthday,
    'anniversary': anniversary,
      'trainingStatus': trainingStatus,
      'awards': awards,
      'specialtyCourses': specialtyCourses,
      'purchases': purchases,
      'photoPath': photoPath,
    'lifetimeMember': lifetimeMember,
    'isRegular': isRegular,
    'approvalStatus': approvalStatus,
    'personalPassword': personalPassword,
    'accessPhone': accessPhone,
    'privacyAgreed': privacyAgreed,
    'privacyAgreedAt': privacyAgreedAt,
    'mentors': mentors,
    'parents': parents,
    'linkApprovalStatus': linkApprovalStatus,
    'linkApprovalNote': linkApprovalNote,
    'linkApprovedAt': linkApprovedAt,
    'linkApprovedBy': linkApprovedBy,
    'feeYears': feeYears,
    'eventAttend': eventAttend,
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
      if (v is List) return v.map((e) => '$e').where((s) => s.isNotEmpty).toList();
      if (v is String && v.trim().isNotEmpty) {
        return v.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
      }
      return <String>[];
    }

    return Member(
      id: '${map['id'] ?? ''}',
      number: '${map['number'] ?? ''}',
      name: '${map['name'] ?? ''}',
      league: '${map['league'] ?? ''}',
      unit: '${map['unit'] ?? ''}',
      regLeague: '${map['regLeague'] ?? ''}',
      regUnit: '${map['regUnit'] ?? ''}',
      address: '${map['address'] ?? ''}',
      phone: '${map['phone'] ?? ''}',
      email: '${map['email'] ?? ''}',
      date: '${map['date'] ?? ''}',
      atasNo: '${map['atasNo'] ?? ''}',
      activity: '${map['activity'] ?? ''}',
      memo: '${map['memo'] ?? ''}',
      birthday: '${map['birthday'] ?? ''}',
      anniversary: '${map['anniversary'] ?? ''}',
      trainingStatus: '${map['trainingStatus'] ?? ''}',
      awards: '${map['awards'] ?? ''}',
      specialtyCourses: '${map['specialtyCourses'] ?? ''}',
      purchases: '${map['purchases'] ?? ''}',
      photoPath: '${map['photoPath'] ?? ''}',
      lifetimeMember: map['lifetimeMember'] == true,
      isRegular: map['isRegular'] == true,
      approvalStatus: '${map['approvalStatus'] ?? ''}',
      personalPassword: '${map['personalPassword'] ?? ''}',
      accessPhone: '${map['accessPhone'] ?? ''}',
      privacyAgreed: map['privacyAgreed'] == true,
      privacyAgreedAt: '${map['privacyAgreedAt'] ?? ''}',
      mentors: castStrList(map['mentors']),
      parents: castStrList(map['parents']),
      linkApprovalStatus: '${map['linkApprovalStatus'] ?? ''}',
      linkApprovalNote: '${map['linkApprovalNote'] ?? ''}',
      linkApprovedAt: '${map['linkApprovedAt'] ?? ''}',
      linkApprovedBy: '${map['linkApprovedBy'] ?? ''}',
      feeYears: castBoolMap(map['feeYears']),
      eventAttend: castBoolMap(map['eventAttend']),
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
    String? number,
    String? name,
    String? league,
    String? unit,
    String? regLeague,
    String? regUnit,
    String? address,
    String? phone,
    String? email,
    String? date,
    String? atasNo,
    String? activity,
    String? memo,
    String? birthday,
    String? anniversary,
    String? trainingStatus,
    String? awards,
    String? specialtyCourses,
    String? purchases,
    String? photoPath,
    bool? lifetimeMember,
    bool? isRegular,
    String? approvalStatus,
    String? personalPassword,
    String? accessPhone,
    bool? privacyAgreed,
    String? privacyAgreedAt,
    List<String>? mentors,
    List<String>? parents,
    String? linkApprovalStatus,
    String? linkApprovalNote,
    String? linkApprovedAt,
    String? linkApprovedBy,
    Map<String, bool>? feeYears,
    Map<String, bool>? eventAttend,
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
      league: league ?? this.league,
      unit: unit ?? this.unit,
      regLeague: regLeague ?? this.regLeague,
      regUnit: regUnit ?? this.regUnit,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      date: date ?? this.date,
      atasNo: atasNo ?? this.atasNo,
      activity: activity ?? this.activity,
      memo: memo ?? this.memo,
      birthday: birthday ?? this.birthday,
      anniversary: anniversary ?? this.anniversary,
      trainingStatus: trainingStatus ?? this.trainingStatus,
      awards: awards ?? this.awards,
      specialtyCourses: specialtyCourses ?? this.specialtyCourses,
      purchases: purchases ?? this.purchases,
      photoPath: photoPath ?? this.photoPath,
      lifetimeMember: lifetimeMember ?? this.lifetimeMember,
      isRegular: isRegular ?? this.isRegular,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      personalPassword: personalPassword ?? this.personalPassword,
      accessPhone: accessPhone ?? this.accessPhone,
      privacyAgreed: privacyAgreed ?? this.privacyAgreed,
      privacyAgreedAt: privacyAgreedAt ?? this.privacyAgreedAt,
      mentors: mentors ?? List<String>.from(this.mentors),
      parents: parents ?? List<String>.from(this.parents),
      linkApprovalStatus: linkApprovalStatus ?? this.linkApprovalStatus,
      linkApprovalNote: linkApprovalNote ?? this.linkApprovalNote,
      linkApprovedAt: linkApprovedAt ?? this.linkApprovedAt,
      linkApprovedBy: linkApprovedBy ?? this.linkApprovedBy,
      feeYears: feeYears ?? Map<String, bool>.from(this.feeYears),
      eventAttend: eventAttend ?? Map<String, bool>.from(this.eventAttend),
      sample: sample ?? this.sample,
      nameVisible: nameVisible ?? this.nameVisible,
      gender: gender ?? this.gender,
      genderVisible: genderVisible ?? this.genderVisible,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
