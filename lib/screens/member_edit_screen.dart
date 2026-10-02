import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/league_names.dart';
import '../services/phone_format.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/address_field.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';
import '../widgets/member_avatar.dart';
import '../widgets/link_code_field.dart';
import '../widgets/privacy_consent.dart';
import '../widgets/unsaved_guard.dart';

class MemberEditScreen extends StatefulWidget {
  const MemberEditScreen({super.key, this.memberId, this.suggestedNumber});

  final String? memberId;
  final String? suggestedNumber;

  @override
  State<MemberEditScreen> createState() => _MemberEditScreenState();
}

class _MemberEditScreenState extends State<MemberEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _number,
      _name,
      _nameEn,
      _league,
      _unit,
      _regLeague,
      _regUnit,
      _address,
      _zipCode,
      _phone,
      _tel,
      _email,
      _residentNo,
      _scoutNo,
      _date,
      _atas,
      _activity,
      _position,
      _bio,
      _memo,
      _birthday,
      _anniversary;
  String _photoPath = '';
  String _trainingStatus = '';
  late TextEditingController _awards;
  late TextEditingController _specialty;
  late TextEditingController _purchases;
  bool _lifetime = false;
  Map<String, bool> _fees = {};
  Member? _existing;

  /// 마스터 비밀번호 열람 시 가림 여부(기본: 가림).
  bool _pwObscured = true;

  /// 성별 — '남' | '여' | ''. 남/여 중 하나는 필수. 공개여부는 기본 비노출.
  String _gender = '';
  bool _genderVisible = false;

  /// 개인정보 수집·이용 및 제3자 제공 동의 (저장/가입 필수)
  bool _privacyAgreed = false;
  String _privacyAgreedAt = '';

  /// 멘토/페런츠 인가번호 목록 (복수 입력)
  List<String> _mentors = [];
  List<String> _parents = [];

  /// 훈련현황 선택 항목
  static const List<String> _trainingOptions = [
    '중급',
    '상급',
    '커미셔너과정',
    '부교수',
    '교수',
  ];

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _existing = widget.memberId != null ? state.byId(widget.memberId!) : null;
    final m = _existing;

    _number = TextEditingController(
      text: m?.number ?? widget.suggestedNumber ?? '',
    );
    _name = TextEditingController(text: m?.name ?? '');
    _nameEn = TextEditingController(text: m?.nameEn ?? '');
    _league = TextEditingController(text: m?.league ?? '');
    _unit = TextEditingController(text: m?.unit ?? '');
    _regLeague = TextEditingController(text: m?.regLeague ?? '');
    _regUnit = TextEditingController(text: m?.regUnit ?? '');
    _address = TextEditingController(text: m?.address ?? '');
    _zipCode = TextEditingController(text: m?.zipCode ?? '');
    _phone = TextEditingController(text: m?.phone ?? '');
    _tel = TextEditingController(text: m?.tel ?? '');
    _email = TextEditingController(text: m?.email ?? '');
    _residentNo = TextEditingController(text: m?.residentNo ?? '');
    _scoutNo = TextEditingController(text: m?.scoutNo ?? '');
    _date = TextEditingController(text: m?.date ?? '');
    _atas = TextEditingController(text: m?.atasNo ?? '');
    _activity = TextEditingController(text: m?.activity ?? '');
    _position = TextEditingController(text: m?.position ?? '');
    _bio = TextEditingController(text: m?.bio ?? '');
    _memo = TextEditingController(text: m?.memo ?? '');
    _birthday = TextEditingController(text: m?.birthday ?? '');
    _anniversary = TextEditingController(text: m?.anniversary ?? '');
    _awards = TextEditingController(text: m?.awards ?? '');
    _specialty = TextEditingController(text: m?.specialtyCourses ?? '');
    _purchases = TextEditingController(text: m?.purchases ?? '');
    _photoPath = m?.photoPath ?? '';
    _trainingStatus = m?.trainingStatus ?? '';
    _lifetime = m?.lifetimeMember ?? false;
    _fees = Map<String, bool>.from(m?.feeYears ?? {});
    _mentors = List<String>.from(m?.mentors ?? []);
    _parents = List<String>.from(m?.parents ?? []);
    _privacyAgreed = m?.privacyAgreed ?? false;
    _privacyAgreedAt = m?.privacyAgreedAt ?? '';
    _gender = m?.gender ?? '';
    _genderVisible = m?.genderVisible ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _number,
      _name,
      _nameEn,
      _league,
      _unit,
      _regLeague,
      _regUnit,
      _address,
      _zipCode,
      _phone,
      _tel,
      _email,
      _residentNo,
      _scoutNo,
      _date,
      _atas,
      _activity,
      _position,
      _bio,
      _memo,
      _birthday,
      _anniversary,
      _awards,
      _specialty,
      _purchases,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    final state = context.watch<AppState>();
    // 개인/비인가자(본인) 접근: 본인 정보만 수정 가능 (인가번호 변경·삭제·신규추가 금지)
    final personal = state.isSelfAccess;
    return UnsavedGuard(
      dirty: _isDirty,
      onSave: () async {
        await _saveInternal();
        return true;
      },
      child: Scaffold(
        appBar: TsakAppBar(
          leading: AppBackButton(
            label: '뒤로',
            onTap: () async {
              if (_isDirty()) {
                final choice = await showUnsavedDialog(context);
                if (!context.mounted) return;
                if (choice == UnsavedChoice.save) {
                  await _save();
                } else if (choice == UnsavedChoice.discard) {
                  if (context.mounted) Navigator.pop(context);
                }
              } else {
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          leadingWidth: 84,
          title: Text(isNew ? '인가자 추가' : '인가자 편집'),
          actions: [
            const AppHomeEmblem(size: 24),
            TextButton(
              onPressed: _save,
              child: const Text(
                '저장',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _photoPicker(),
              const SizedBox(height: 12),
              _privacyStatusBanner(state),
              const SizedBox(height: 12),
              // (요청) 배치 순서: 이름 → 범스카우트 인가번호 → ATAS 인가번호
              //  → 범스카우트 인가 정보(인가 당시) → 현재 활동 등록 정보
              _field(
                '이름',
                _name,
                hint: '홍길동',
                icon: Icons.person,
                required: true,
              ),
              _field(
                '${_existing?.corpsFullName ?? '범스카우트'} 인가번호',
                _number,
                hint: '예: 2186',
                icon: Icons.tag,
                numeric: true,
                readOnly: personal,
              ),
              _field(
                'ATAS 인가번호',
                _atas,
                hint: 'ATAS 번호',
                icon: Icons.confirmation_number,
              ),
              // (요구) 영문 이름 — ATAS 인가정보에서 가져온 로마자 표기.
              //  · 값이 없으면 **빈칸**으로 두고 여기서 직접 입력할 수 있다.
              _field(
                '영문 이름',
                _nameEn,
                hint: 'ATAS 인가정보의 영문 이름 (없으면 직접 입력, 예: Won Ho CHO)',
                icon: Icons.abc,
              ),
              const SizedBox(height: 4),
              _subHead(
                '${_existing?.corpsFullName ?? '범스카우트'} 인가 정보 (인가 당시 정보)',
                Icons.verified_user,
                AppColors.purple,
              ),
              _field(
                '소속 연맹',
                _league,
                hint: '예: 제주 / 광주 / 서울남부 (인가 당시 연맹)',
                icon: Icons.groups,
              ),
              _field(
                '소속 단위대',
                _unit,
                hint: '예: 제405단 인천연맹 직할대 (인가 당시 단위대)',
                icon: Icons.flag,
              ),
              _field(
                '인가일',
                _date,
                hint: '예: 1991-03-21',
                icon: Icons.event_available,
              ),
              const SizedBox(height: 4),
              _subHead(
                '현재 활동 등록 정보',
                Icons.play_circle_outline,
                AppColors.taegeukBlue,
              ),
              _field(
                '현재 소속 연맹',
                _regLeague,
                hint: '현재 활동 중인 연맹 (인가시 연맹과 다를 수 있음)',
                icon: Icons.groups_2,
              ),
              _field(
                '현재 등록 단위대',
                _regUnit,
                hint: '현재 활동 중인 단위대',
                icon: Icons.flag_circle,
              ),
              _field(
                '직위',
                _position,
                hint: '예: 지역대장 / 부장 / 교수 / 스텝',
                icon: Icons.badge_outlined,
              ),
              _field(
                '핸드폰',
                _phone,
                hint: '010-0000-0000',
                icon: Icons.phone,
                keyboard: TextInputType.phone,
                phone: true,
              ),
              _field(
                '연락처',
                _tel,
                hint: '유선/추가 전화 (예: 051-702-7766)',
                icon: Icons.call,
                keyboard: TextInputType.phone,
              ),
              _field(
                '스카우트 고유번호',
                _scoutNo,
                hint: '인가번호와 다른 별도 고유번호 (예: 16187) — 없으면 비워두세요',
                icon: Icons.confirmation_number_outlined,
                numeric: true,
              ),
              _field(
                '주민등록번호',
                _residentNo,
                hint: '주민등록번호 앞자리 — 민감정보 (노출은 마스터 설정)',
                icon: Icons.credit_card,
              ),
              _field(
                '생일',
                _birthday,
                hint: '예: 1980.05.14 (또는 05-14)',
                icon: Icons.cake,
              ),
              _field(
                '기념일',
                _anniversary,
                hint: '예: 2005.03.01 (입단·기념일)',
                icon: Icons.celebration,
              ),
              _trainingStatusField(),
              _field(
                '포상',
                _awards,
                hint: '예: 2024 우수지도자 표창 (자가 입력)',
                icon: Icons.emoji_events,
                maxLines: 2,
              ),
              _field(
                '종별 전문과정 이수과정',
                _specialty,
                hint: '예: 목공지도자 1급, 응급처치 강사 (자가 입력)',
                icon: Icons.workspace_premium,
                maxLines: 2,
              ),
              _field(
                '수품구매현황',
                _purchases,
                hint: '예: 2025.03 반팔티 1 / 2025.05 모자 1 (자가 입력)',
                icon: Icons.shopping_bag,
                maxLines: 2,
              ),
              LinkCodeField(
                label: '멘토',
                icon: Icons.supervisor_account,
                kind: 'mentor',
                codes: _mentors,
                menteeNumber: _number.text.trim(),
                onChanged: (v) => setState(() => _mentors = v),
                editable: _canEditLinks,
              ),
              LinkCodeField(
                label: '페런츠',
                icon: Icons.family_restroom,
                kind: 'parent',
                codes: _parents,
                // 요구: 소속연맹/단위대가 없으면 인가자(본인) 값을 쓴다.
                defaultLeague: _league.text.trim(),
                defaultUnit: _unit.text.trim(),
                onChanged: (v) => setState(() => _parents = v),
                editable: _canEditLinks,
              ),
              _linkApprovalBar(),
              _field(
                '이메일',
                _email,
                hint: 'name@example.com',
                icon: Icons.email,
                keyboard: TextInputType.emailAddress,
              ),
              _field(
                '우편번호',
                _zipCode,
                hint: '예: 06130',
                icon: Icons.markunread_mailbox,
                numeric: true,
              ),
              AddressField(
                controller: _address,
                label: '주소',
                hint: '주소검색 버튼으로 검색하세요',
              ),
              _field(
                '한줄소개 (비고)',
                _bio,
                hint: '명단 비고/한줄소개',
                icon: Icons.short_text,
                maxLines: 2,
              ),
              _genderEditor(),
              _field(
                '활동',
                _activity,
                hint: '활동 내용 (예: 지도자 양성, 캠프 운영 등)',
                icon: Icons.directions_run,
                maxLines: 2,
              ),
              _field(
                '메모',
                _memo,
                hint: '자유 메모',
                icon: Icons.notes,
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              _feeEditor(),
              const SizedBox(height: 12),
              // 개인정보 수집·이용 및 제3자 제공 동의 (필수)
              PrivacyConsentField(
                agreed: _privacyAgreed,
                onChanged: (v) => setState(() => _privacyAgreed = v),
              ),
              const SizedBox(height: 10),
              Card(
                child: SwitchListTile(
                  title: const Text(
                    '평생회원',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('평생회원으로 지정합니다'),
                  value: _lifetime,
                  activeThumbColor: AppColors.tigerGold,
                  onChanged: (v) => setState(() => _lifetime = v),
                ),
              ),
              const SizedBox(height: 20),
              // 비밀번호 관리 카드 (요구: 개인정보 수정 페이지에서 비밀번호 변경).
              //  · 본인: 변경 + 분실 시 초기화 요청
              //  · 마스터: 열람·변경·초기화 / 관리자: 초기화만
              _passwordCard(state),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: Text(isNew ? '인가자 등록' : '변경사항 저장'),
              ),
              if (!isNew && !personal)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.taegeukRed,
                  ),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('삭제'),
                ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 비밀번호 관리 카드 =================
  //  요구: "모든 회원은 개인정보 페이지에서 비밀번호를 변경할 수 있습니다.
  //   비밀번호 변경창을 넣어주세요. 마스터만 비밀번호를 볼 수 있고 변경·초기화
  //   할 수 있습니다. 관리자는 초기화만 할 수 있습니다. 이런 내용은 해당권한을
  //   갖는 사람에게만 노출합니다."
  String _loginId() {
    final m = _existing;
    if (m != null) return m.loginId;
    final no = _number.text.trim();
    return no.isNotEmpty ? no : _phone.text.trim();
  }

  Widget _passwordCard(AppState state) {
    final isNew = _existing == null;
    if (isNew) return const SizedBox.shrink(); // 신규 등록 시엔 비번 관리 불필요
    final isAdmin = state.isApp || state.isMaster;
    final isMaster = state.isMaster;
    final isSelf = state.isSelfAccess;
    if (!isAdmin && !isSelf) return const SizedBox.shrink(); // 권한 없으면 미노출
    final isRegular = _existing!.isRegular;
    return Card(
      color: AppColors.purple.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.password, size: 19, color: AppColors.purple),
                SizedBox(width: 8),
                Text(
                  '접속 비밀번호 관리',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${isRegular ? '일반회원' : '인가자'} · 아이디 ${_loginId()}',
              style: const TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
            // 마스터 전용: 현재 비밀번호 실제값
            if (isMaster) ...[
              const SizedBox(height: 10),
              _passwordReveal(state),
            ],
            // 관리자·마스터: 초기화(+마스터는 변경)
            if (isAdmin) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _resetPassword,
                    icon: const Icon(Icons.lock_reset, size: 17),
                    label: const Text('비번 초기화'),
                  ),
                  if (isMaster)
                    OutlinedButton.icon(
                      onPressed: _forceChangePassword,
                      icon: const Icon(Icons.lock_open, size: 17),
                      label: const Text('비번 강제 변경'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isMaster
                    ? '마스터는 모든 회원의 비밀번호를 열람·변경·초기화할 수 있습니다.'
                    : '관리자는 비밀번호 초기화만 할 수 있습니다. 변경은 마스터만 가능합니다.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textGray,
                  height: 1.35,
                ),
              ),
            ],
            // 본인(비관리자): 변경 + 분실 시 초기화 요청
            if (isSelf && !isAdmin) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                  ),
                  onPressed: _selfChangePassword,
                  icon: const Icon(Icons.password, size: 18),
                  label: const Text('비밀번호 변경'),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.tigerGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.tigerGold.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.help_outline,
                          size: 15,
                          color: AppColors.lifetimeGold,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '비밀번호를 분실한 경우 관리자·마스터에게 초기화를 요청하세요.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.lifetimeGold,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.tigerGold,
                        ),
                        onPressed: _requestPasswordReset,
                        icon: const Icon(Icons.send, size: 16),
                        label: const Text('비밀번호 초기화 요청'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 마스터 전용 — 현재 비밀번호 실제값(가림/보기 + 복사).
  Widget _passwordReveal(AppState state) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: state.fetchMemberPassword(_loginId()),
      builder: (ctx, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final d = snap.data;
        final pw = d == null ? null : '${d['password'] ?? ''}';
        final isDefault = d?['isDefault'] == true;
        final obscured = _pwObscured;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.purple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.key, size: 17, color: AppColors.purple),
              const SizedBox(width: 8),
              const Text(
                '현재 비밀번호',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loading
                      ? '조회 중…'
                      : (pw == null || pw.isEmpty
                            ? '조회 실패'
                            : '${obscured ? '••••••' : pw}${isDefault ? '  (기본값)' : ''}'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (pw != null && pw.isNotEmpty) ...[
                IconButton(
                  tooltip: obscured ? '보기' : '가리기',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    obscured ? Icons.visibility : Icons.visibility_off,
                    size: 17,
                  ),
                  onPressed: () =>
                      setState(() => _pwObscured = !_pwObscured),
                ),
                IconButton(
                  tooltip: '복사',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 17),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pw));
                    _snack('비밀번호를 복사했습니다');
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 본인 — 비밀번호 변경.
  void _selfChangePassword() {
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final newCtrl2 = TextEditingController();
    bool busy = false;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('비밀번호 변경'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: curCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '현재 비밀번호'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '새 비밀번호 (4자 이상)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newCtrl2,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '새 비밀번호 확인'),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '※ 비밀번호를 분실한 경우 관리자·마스터에게 초기화를 요청하세요.',
                    style: TextStyle(fontSize: 11, color: AppColors.textGray),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final cur = curCtrl.text.trim();
                      final nw = newCtrl.text.trim();
                      final nw2 = newCtrl2.text.trim();
                      if (cur.isEmpty || nw.isEmpty) {
                        _snack('모든 항목을 입력하세요');
                        return;
                      }
                      if (nw.length < 4) {
                        _snack('새 비밀번호는 4자 이상이어야 합니다');
                        return;
                      }
                      if (nw != nw2) {
                        _snack('새 비밀번호가 서로 다릅니다');
                        return;
                      }
                      setLocal(() => busy = true);
                      final err = await context
                          .read<AppState>()
                          .changePersonalPassword(cur, nw);
                      if (!ctx.mounted) return;
                      setLocal(() => busy = false);
                      if (err == null) {
                        Navigator.pop(ctx);
                        _snack('비밀번호가 변경되었습니다');
                      } else {
                        _snack('변경 실패: $err');
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('변경'),
            ),
          ],
        ),
      ),
    );
  }

  /// 본인 — 관리자·마스터에게 초기화 요청 접수.
  Future<void> _requestPasswordReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_reset, color: AppColors.tigerGold, size: 32),
        title: const Text('비밀번호 초기화 요청'),
        content: const Text(
          '관리자·마스터에게 비밀번호 초기화를 요청하시겠습니까?\n\n'
          '· 요청은 통합승인관리에 접수되어 승인 후 초기화됩니다.\n'
          '· 초기화되면 기본 비밀번호로 다시 로그인할 수 있습니다.',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('요청'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<AppState>().requestPasswordReset();
    if (!mounted) return;
    _snack(
      err == null
          ? '초기화 요청을 접수했습니다. 관리자·마스터 승인 후 초기화됩니다.'
          : '요청 실패: $err',
    );
  }

  /// 관리자·마스터 — 비밀번호 초기화.
  Future<void> _resetPassword() async {
    final m = _existing!;
    final target = m.isRegular ? m.phoneLast4 : '${m.number}!@@';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비밀번호 초기화'),
        content: Text(
          '${m.name}(${m.loginId}) 님의 비밀번호를 기본값으로 초기화할까요?\n\n'
          '초기화 값: $target',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.taegeukRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<AppState>().setMemberPassword(m, reset: true);
    if (!mounted) return;
    _snack(err == null ? '비밀번호를 초기화했습니다 ($target)' : '실패: $err');
  }

  /// 마스터 — 비밀번호 강제 변경.
  Future<void> _forceChangePassword() async {
    final m = _existing!;
    final ctrl = TextEditingController();
    final nw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('비밀번호 강제 변경 — ${m.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '새 비밀번호',
            helperText: '4자 이상 입력하세요',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    if (nw == null || nw.length < 4 || !mounted) {
      if (nw != null && mounted) _snack('4자 이상 입력하세요');
      return;
    }
    final err = await context.read<AppState>().setMemberPassword(m, value: nw);
    if (!mounted) return;
    _snack(err == null ? '비밀번호를 변경했습니다' : '실패: $err');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 수정 여부 판정 (원본과 비교)
  bool _isDirty() {
    final m = _existing;
    return m == null ||
        _number.text.trim() != m.number ||
        _name.text.trim() != m.name ||
        _nameEn.text.trim() != m.nameEn ||
        _league.text.trim() != m.league ||
        _unit.text.trim() != m.unit ||
        _regLeague.text.trim() != m.regLeague ||
        _regUnit.text.trim() != m.regUnit ||
        _address.text.trim() != m.address ||
        _zipCode.text.trim() != m.zipCode ||
        _phone.text.trim() != m.phone ||
        _tel.text.trim() != m.tel ||
        _email.text.trim() != m.email ||
        _residentNo.text.trim() != m.residentNo ||
        _scoutNo.text.trim() != m.scoutNo ||
        _date.text.trim() != m.date ||
        _atas.text.trim() != m.atasNo ||
        _activity.text.trim() != m.activity ||
        _position.text.trim() != m.position ||
        _bio.text.trim() != m.bio ||
        _memo.text.trim() != m.memo ||
        _birthday.text.trim() != m.birthday ||
        _anniversary.text.trim() != m.anniversary ||
        _trainingStatus != m.trainingStatus ||
        _awards.text.trim() != m.awards ||
        _specialty.text.trim() != m.specialtyCourses ||
        _purchases.text.trim() != m.purchases ||
        _photoPath != m.photoPath ||
        _lifetime != m.lifetimeMember ||
        _mentors.join(',') != m.mentors.join(',') ||
        _parents.join(',') != m.parents.join(',') ||
        _privacyAgreed != m.privacyAgreed;
  }

  /// 멘토·페런츠 연결 편집 가능 여부 — 본인 또는 관리자·마스터.
  bool get _canEditLinks {
    final state = context.read<AppState>();
    return state.isApp || state.isMaster || state.isSelfAccess;
  }

  /// 멘토·페런츠 연결 승인 상태 바 — 미승인 라벨 + 승인요청 버튼.
  ///   · 연결이 없으면 아무것도 표시하지 않는다.
  ///   · 'pending' 이면 [미승인] 단추 + [승인요청] 버튼.
  ///   · 'approved' 이면 [승인됨], 'held' 이면 [보류].
  Widget _linkApprovalBar() {
    final hasLinks = _mentors.isNotEmpty || _parents.isNotEmpty;
    if (!hasLinks) return const SizedBox.shrink();
    final status = _existing?.linkApprovalStatus ?? '';
    final (label, color, icon) = switch (status) {
      'approved' => ('승인됨', AppColors.scoutGreen, Icons.verified),
      'held' => ('보류', AppColors.tigerGold, Icons.pause_circle_filled),
      _ => ('미승인', AppColors.taegeukRed, Icons.gpp_maybe),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status == 'approved'
                    ? '멘토·페런츠 연결이 승인되었습니다.'
                    : '관리자·마스터의 승인 후 확정됩니다.',
                style: const TextStyle(fontSize: 11, color: AppColors.textGray),
              ),
            ),
            if (status != 'approved')
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _requestLinkApproval,
                icon: const Icon(Icons.send, size: 15),
                label: const Text('승인요청', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  /// 승인요청 — 저장 후 관리자·마스터 승인 큐(배지)로 전송.
  Future<void> _requestLinkApproval() async {
    // 인적사항이 저장되도록 먼저 저장 수행.
    await _saveInternal();
    if (!mounted) return;
    final state = context.read<AppState>();
    final no = _number.text.trim();
    try {
      final r = await state.nas.linkRequest(number: no, note: '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r['ok'] == true
                ? '승인요청을 보냈습니다. 관리자·마스터 승인 후 확정됩니다.'
                : '승인요청 실패 — 잠시 후 다시 시도하세요',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('승인요청 오류: $e')));
    }
  }

  /// 개인정보 동의 상태 안내 배너 (상단)
  Widget _privacyStatusBanner(AppState state) {
    final agreed = _privacyAgreed;
    final privileged = state.isApp || state.isMaster;
    final exempt = privileged; // 관리자·마스터는 동의 없이도 저장 가능
    final c = (agreed || exempt) ? AppColors.scoutGreen : AppColors.taegeukRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            (agreed || exempt) ? Icons.verified : Icons.warning_amber_rounded,
            color: c,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agreed
                      ? '개인정보 동의 완료'
                      : (exempt ? '관리자 모드 — 동의 없이 저장 가능' : '개인정보 동의 필요 (필수)'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: c,
                  ),
                ),
                if (agreed && _privacyAgreedAt.isNotEmpty)
                  Text(
                    '동의일시: $_privacyAgreedAt',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                    ),
                  )
                else if (!agreed && exempt)
                  const Text(
                    '관리자·마스터는 개인정보 동의를 받지 않고도 입력·수정할 수 있습니다',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                  )
                else if (!agreed)
                  const Text(
                    '아래 「개인정보 수집·이용 및 제3자 제공 동의」에 체크해야 저장됩니다',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPicker() {
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              MemberAvatar(
                name: _name.text,
                photoPath: _photoPath,
                league: _league.text,
                size: 110,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.purple,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera, size: 18),
                label: const Text('촬영'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('사진 선택'),
              ),
              if (_photoPath.isNotEmpty) ...[
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => setState(() => _photoPath = ''),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.taegeukRed,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // 저장 호환성을 위해 base64 data URI로 보관 (웹/모바일 공통)
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      setState(() => _photoPath = b64);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('사진을 불러올 수 없습니다: $e')));
      }
    }
  }

  Widget _feeEditor() {
    final years = <String>{
      '2024',
      '2025',
      '2026',
      '2027',
      ..._fees.keys,
    }.toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.card_membership, color: AppColors.purple, size: 20),
                SizedBox(width: 8),
                Text(
                  '연간회비 납부',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: years.map((y) {
                final paid = _fees[y] == true;
                return FilterChip(
                  label: Text(y),
                  selected: paid,
                  selectedColor: AppColors.scoutGreen,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: paid ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (v) => setState(() => _fees[y] = v),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Text(
              '연도를 눌러 납부 여부를 표시합니다.',
              style: TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
          ],
        ),
      ),
    );
  }

  /// 구획 소제목 — 현재활동 / 범인가시 등 정보 그룹 구분용.
  Widget _subHead(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 2),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: color.withValues(alpha: 0.25))),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    IconData? icon,
    bool required = false,
    bool numeric = false,
    int maxLines = 1,
    TextInputType? keyboard,
    bool phone = false,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboard,
        readOnly: readOnly,
        // 핸드폰: 010 입력 시 010-0000-0000 자동 하이픈
        inputFormatters: phone ? const [PhoneHyphenFormatter()] : null,
        onChanged: (_) => setState(() {}),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '필수 입력 항목입니다' : null
            : null,
        decoration: InputDecoration(
          labelText: label + (required ? ' *' : ''),
          hintText: hint,
          prefixIcon: icon != null ? Icon(icon, size: 20) : null,
          suffixIcon: readOnly
              ? const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: AppColors.textGray,
                )
              : null,
        ),
      ),
    );
  }

  /// 훈련현황 선택 필드 — 복수 선택 가능 (중급/상급/커미셔너과정/부교수/교수)
  Widget _trainingStatusField() {
    final selected = _trainingStatus
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school, size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              const Text(
                '훈련현황',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              if (selected.isNotEmpty)
                Text(
                  '${selected.length}개 선택',
                  style: const TextStyle(fontSize: 11, color: AppColors.purple),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '※ 훈련 과정은 복수 선택이 가능합니다 (여러 과정 이수 시 모두 선택)',
            style: TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _trainingOptions)
                FilterChip(
                  label: Text(t),
                  selected: selected.contains(t),
                  showCheckmark: true,
                  checkmarkColor: Colors.white,
                  selectedColor: AppColors.purple,
                  labelStyle: TextStyle(
                    color: selected.contains(t)
                        ? Colors.white
                        : AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                  onSelected: (on) {
                    setState(() {
                      if (on) {
                        selected.add(t);
                      } else {
                        selected.remove(t);
                      }
                      // 표준 순서로 정렬 저장
                      _trainingStatus = _trainingOptions
                          .where((o) => selected.contains(o))
                          .join(', ');
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 현재 시각 문자열 (예: "2025.09.24 10:30")
  String _nowStamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}.${two(n.month)}.${two(n.day)} ${two(n.hour)}:${two(n.minute)}';
  }

  /// 공용 저장 로직 — 저장만 수행 (pop 없음)
  /// 성별 선택 — 남/여 중 하나는 **필수**. 공개여부는 기본 **비노출**.
  /// 남/여 선택 후 '비노출'을 다시 선택할 수 있다.
  Widget _genderEditor() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.purple.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wc, size: 16, color: AppColors.purple),
                const SizedBox(width: 6),
                const Text(
                  '성별',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(width: 6),
                Text(
                  '(남/여 필수 · 공개여부 기본 비노출)',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textGray.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _genderChip('남', AppColors.taegeukBlue),
                const SizedBox(width: 8),
                _genderChip('여', AppColors.taegeukRed),
                const Spacer(),
                // 공개여부(비노출/공개)
                SegmentedButton<bool>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: false, label: Text('비노출')),
                    ButtonSegment(value: true, label: Text('공개')),
                  ],
                  selected: {_genderVisible},
                  onSelectionChanged: (s) =>
                      setState(() => _genderVisible = s.first),
                ),
              ],
            ),
            if (_gender.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '성별(남/여)을 선택해야 저장할 수 있습니다',
                  style: TextStyle(fontSize: 11, color: AppColors.taegeukRed),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _genderChip(String value, Color color) {
    final on = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: on ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: on ? color : color.withValues(alpha: 0.4),
            width: on ? 1.5 : 1,
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: on ? Colors.white : color,
          ),
        ),
      ),
    );
  }

  Future<bool> _saveInternal() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    // 성별(남/여)은 필수
    if (_gender != '남' && _gender != '여') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('성별(남/여)을 선택해 주세요'),
            backgroundColor: AppColors.taegeukRed,
          ),
        );
      }
      return false;
    }
    final state = context.read<AppState>();
    // 관리자(app)·마스터는 개인정보 동의 없이도 입력·수정 가능.
    // (일반 개인/비인가자 본인 접근은 동의가 필수)
    final privileged = state.isApp || state.isMaster;
    // 개인정보 수집·이용 동의(필수) 없이는 저장/가입 불가 (일반 사용자)
    if (!privileged && !_privacyAgreed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('개인정보 수집·이용에 동의해야 저장할 수 있습니다'),
            backgroundColor: AppColors.taegeukRed,
          ),
        );
      }
      return false;
    }
    final id = _existing?.id ?? 'u${DateTime.now().millisecondsSinceEpoch}';
    // 최초 동의 시각 기록
    if (_privacyAgreedAt.isEmpty) {
      _privacyAgreedAt = _nowStamp();
    }

    // 멘토·페런츠 연결 승인 상태 — 대상이 바뀌면 재승인(pending) 요청으로 전환.
    final mentorsChanged =
        _mentors.join(',') != (_existing?.mentors ?? const []).join(',');
    final parentsChanged =
        _parents.join(',') != (_existing?.parents ?? const []).join(',');
    final hasLinks = _mentors.isNotEmpty || _parents.isNotEmpty;
    String linkStatus = _existing?.linkApprovalStatus ?? '';
    String linkNote = _existing?.linkApprovalNote ?? '';
    if ((mentorsChanged || parentsChanged) && hasLinks) {
      linkStatus = 'pending';
      linkNote = '';
    } else if (!hasLinks) {
      linkStatus = '';
      linkNote = '';
    }

    final member = Member(
      id: id,
      number: _number.text.trim(),
      name: _name.text.trim(),
      nameEn: _nameEn.text.trim(),
      // 소속(corps) 보존 — 은하스카우트 편집이 범스카우트 DB로 저장되지 않도록.
      corps: _existing?.corps ?? 'tsak',
      league: normalizeLeague(_league.text),
      unit: _unit.text.trim(),
      regLeague: normalizeLeague(_regLeague.text),
      regUnit: _regUnit.text.trim(),
      address: _address.text.trim(),
      zipCode: _zipCode.text.trim(),
      phone: _phone.text.trim(),
      tel: _tel.text.trim(),
      email: _email.text.trim(),
      residentNo: _residentNo.text.trim(),
      scoutNo: _scoutNo.text.trim(),
      bio: _bio.text.trim(),
      date: _date.text.trim(),
      atasNo: _atas.text.trim(),
      activity: _activity.text.trim(),
      position: _position.text.trim(),
      memo: _memo.text.trim(),
      birthday: _birthday.text.trim(),
      anniversary: _anniversary.text.trim(),
      trainingStatus: _trainingStatus,
      awards: _awards.text.trim(),
      specialtyCourses: _specialty.text.trim(),
      purchases: _purchases.text.trim(),
      photoPath: _photoPath,
      lifetimeMember: _lifetime,
      feeYears: Map<String, bool>.from(_fees)
        ..removeWhere((k, v) => v == false),
      eventAttend: _existing?.eventAttend ?? {},
      mentors: List<String>.from(_mentors),
      parents: List<String>.from(_parents),
      // ⚠ 이 화면은 멘토·페런츠만 편집한다. 멘티·자녀대원 등록정보는 상세화면에서
      //   별도 저장되므로 **기존값을 반드시 보존**해야 데이터 손실을 막을 수 있다.
      mentees: List<String>.from(_existing?.mentees ?? const []),
      children: List<String>.from(_existing?.children ?? const []),
      linkApprovalStatus: linkStatus,
      linkApprovalNote: linkNote,
      linkApprovedAt: _existing?.linkApprovedAt ?? '',
      linkApprovedBy: _existing?.linkApprovedBy ?? '',
      isRegular: _existing?.isRegular ?? false,
      personalPassword: _existing?.personalPassword ?? '',
      accessPhone: _existing?.accessPhone ?? '',
      privacyAgreed: _privacyAgreed,
      privacyAgreedAt: _privacyAgreedAt,
      nameVisible: _existing?.nameVisible ?? true,
      gender: _gender,
      genderVisible: _genderVisible,
    );
    // 연결 승인요청방법 — 이 화면은 직접 입력이므로 'direct'(요구).
    await state.save(member, linkRequestSource: 'direct');
    _existing = member; // 이후 dirty 비교 기준 갱신

    // 사진이 있으면 NAS 서버에도 업로드 (인가번호 기준)
    if (_photoPath.startsWith('data:image') &&
        state.repo.isNasMode &&
        member.number.trim().isNotEmpty) {
      try {
        final base64Part = _photoPath.split(',').last;
        final bytes = base64Decode(base64Part);
        await state.nas.uploadPhoto(member.number.trim(), bytes);
      } catch (_) {}
    }
    return true;
  }

  Future<void> _save() async {
    final ok = await _saveInternal();
    if (!ok) return;
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('저장되었습니다')));
      Navigator.pop(context);
    }
  }

  void _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('${_existing?.name} 인가자를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.taegeukRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppState>().delete(_existing!.id);
      if (mounted) Navigator.pop(context);
    }
  }
}
