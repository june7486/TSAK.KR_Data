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
    this.photoPath = '',
    this.lifetimeMember = false,
    this.isRegular = false,
    this.personalPassword = '',
    this.accessPhone = '',
    List<String>? mentors,
    List<String>? parents,
    Map<String, bool>? feeYears,
    Map<String, bool>? eventAttend,
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

  /// 사진 경로 (로컬 파일 경로 또는 base64), 사진을 선택/촬영하여 저장
  String photoPath;

  /// 평생회원 여부
  bool lifetimeMember;

  /// 일반회원(비인가자) 여부 — true면 인가자가 아닌 일반 참가자/신규회원
  bool isRegular;

  /// 개인 접속용 비밀번호 (일반회원: 전화번호 뒤 4자리 자동, 이후 변경 가능)
  String personalPassword;

  /// 일반회원 접속 ID (휴대폰 전화번호). 비어 있으면 인가번호/전화로 로그인
  String accessPhone;

  /// 멘토 인가번호 목록 (복수 지정 가능)
  List<String> mentors;

  /// 페런츠(보호자) 인가번호 목록 (복수 지정 가능)
  List<String> parents;

  /// 연간회비 납부 이력: {"2024": true, "2025": true, ...}
  Map<String, bool> feeYears;

  /// 행사 참가 여부: {"2024 정기총회": true, ...}
  Map<String, bool> eventAttend;

  /// 마지막 수정 시각
  DateTime? updatedAt;

  /// 검색용 통합 텍스트
  String get searchText =>
      '$number $name $league $unit $address $phone $email $atasNo $activity $memo $birthday $anniversary $trainingStatus ${mentors.join(' ')} ${parents.join(' ')}'
          .toLowerCase();

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
    'photoPath': photoPath,
    'lifetimeMember': lifetimeMember,
    'isRegular': isRegular,
    'personalPassword': personalPassword,
    'accessPhone': accessPhone,
    'mentors': mentors,
    'parents': parents,
    'feeYears': feeYears,
    'eventAttend': eventAttend,
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
      photoPath: '${map['photoPath'] ?? ''}',
      lifetimeMember: map['lifetimeMember'] == true,
      isRegular: map['isRegular'] == true,
      personalPassword: '${map['personalPassword'] ?? ''}',
      accessPhone: '${map['accessPhone'] ?? ''}',
      mentors: castStrList(map['mentors']),
      parents: castStrList(map['parents']),
      feeYears: castBoolMap(map['feeYears']),
      eventAttend: castBoolMap(map['eventAttend']),
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
    String? photoPath,
    bool? lifetimeMember,
    bool? isRegular,
    String? personalPassword,
    String? accessPhone,
    List<String>? mentors,
    List<String>? parents,
    Map<String, bool>? feeYears,
    Map<String, bool>? eventAttend,
    DateTime? updatedAt,
  }) {
    return Member(
      id: id,
      number: number ?? this.number,
      name: name ?? this.name,
      league: league ?? this.league,
      unit: unit ?? this.unit,
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
      photoPath: photoPath ?? this.photoPath,
      lifetimeMember: lifetimeMember ?? this.lifetimeMember,
      isRegular: isRegular ?? this.isRegular,
      personalPassword: personalPassword ?? this.personalPassword,
      accessPhone: accessPhone ?? this.accessPhone,
      mentors: mentors ?? List<String>.from(this.mentors),
      parents: parents ?? List<String>.from(this.parents),
      feeYears: feeYears ?? Map<String, bool>.from(this.feeYears),
      eventAttend: eventAttend ?? Map<String, bool>.from(this.eventAttend),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
