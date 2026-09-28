import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/phone_format.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/address_field.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/member_avatar.dart';
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
      _league,
      _unit,
      _regLeague,
      _regUnit,
      _address,
      _phone,
      _email,
      _date,
      _atas,
      _activity,
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
    _league = TextEditingController(text: m?.league ?? '');
    _unit = TextEditingController(text: m?.unit ?? '');
    _regLeague = TextEditingController(text: m?.regLeague ?? '');
    _regUnit = TextEditingController(text: m?.regUnit ?? '');
    _address = TextEditingController(text: m?.address ?? '');
    _phone = TextEditingController(text: m?.phone ?? '');
    _email = TextEditingController(text: m?.email ?? '');
    _date = TextEditingController(text: m?.date ?? '');
    _atas = TextEditingController(text: m?.atasNo ?? '');
    _activity = TextEditingController(text: m?.activity ?? '');
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
      _league,
      _unit,
      _regLeague,
      _regUnit,
      _address,
      _phone,
      _email,
      _date,
      _atas,
      _activity,
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
        appBar: AppBar(
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
              _field(
                '인가번호',
                _number,
                hint: '예: 2186',
                icon: Icons.tag,
                numeric: true,
                readOnly: personal,
              ),
              _field(
                '성명',
                _name,
                hint: '홍길동',
                icon: Icons.person,
                required: true,
              ),
              _field(
                '소속 연맹',
                _league,
                hint: '예: 제주 / 광주 / 서울남부',
                icon: Icons.groups,
              ),
              _field('소속 단위대', _unit, hint: '예: 제405단 샘물지역대', icon: Icons.flag),
              _field(
                '등록 연맹 (현재)',
                _regLeague,
                hint: '현재 등록된 연맹 (부여 연맹과 다를 수 있음)',
                icon: Icons.groups_2,
              ),
              _field(
                '등록 단위대 (현재)',
                _regUnit,
                hint: '현재 등록된 단위대',
                icon: Icons.flag_circle,
              ),
              _field(
                '인가일',
                _date,
                hint: '예: 2025.12.19.',
                icon: Icons.event_available,
              ),
              _field(
                'ATAS 인가번호',
                _atas,
                hint: 'ATAS 번호',
                icon: Icons.confirmation_number,
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
              _codeListField(
                label: '멘토',
                icon: Icons.supervisor_account,
                list: _mentors,
                onChanged: (v) => setState(() => _mentors = v),
              ),
              _codeListField(
                label: '페런츠',
                icon: Icons.family_restroom,
                list: _parents,
                onChanged: (v) => setState(() => _parents = v),
              ),
              _field(
                '이메일',
                _email,
                hint: 'name@example.com',
                icon: Icons.email,
                keyboard: TextInputType.emailAddress,
              ),
              AddressField(
                controller: _address,
                label: '주소',
                hint: '주소검색 버튼으로 검색하세요',
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

  /// 수정 여부 판정 (원본과 비교)
  bool _isDirty() {
    final m = _existing;
    return m == null ||
        _number.text.trim() != m.number ||
        _name.text.trim() != m.name ||
        _league.text.trim() != m.league ||
        _unit.text.trim() != m.unit ||
        _regLeague.text.trim() != m.regLeague ||
        _regUnit.text.trim() != m.regUnit ||
        _address.text.trim() != m.address ||
        _phone.text.trim() != m.phone ||
        _email.text.trim() != m.email ||
        _date.text.trim() != m.date ||
        _atas.text.trim() != m.atasNo ||
        _activity.text.trim() != m.activity ||
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

  /// 개인정보 동의 상태 안내 배너 (상단)
  Widget _privacyStatusBanner(AppState state) {
    final agreed = _privacyAgreed;
    final privileged = state.isApp || state.isMaster;
    final exempt = privileged; // 관리자·마스터는 동의 없이도 저장 가능
    final c = (agreed || exempt)
        ? AppColors.scoutGreen
        : AppColors.taegeukRed;
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
              size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agreed
                      ? '개인정보 동의 완료'
                      : (exempt
                          ? '관리자 모드 — 동의 없이 저장 가능'
                          : '개인정보 동의 필요 (필수)'),
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
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                    ),
                  )
                else if (!agreed)
                  const Text(
                    '아래 「개인정보 수집·이용 및 제3자 제공 동의」에 체크해야 저장됩니다',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textGray,
                    ),
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

  /// 멘토/페런츠 등 인가번호 목록 입력 필드 (복수)
  Widget _codeListField({
    required String label,
    required IconData icon,
    required List<String> list,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _addCode(label, list, onChanged),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('추가', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 24, bottom: 4),
              child: Text(
                '등록된 인가번호 없음 (복수 입력 가능)',
                style: TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final code in list)
                  Chip(
                    label: Text('#$code'),
                    backgroundColor: AppColors.purple.withValues(alpha: 0.08),
                    labelStyle: const TextStyle(
                      color: AppColors.purple,
                      fontWeight: FontWeight.w700,
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      final next = List<String>.from(list)..remove(code);
                      onChanged(next);
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _addCode(
    String label,
    List<String> list,
    ValueChanged<List<String>> onChanged,
  ) async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label 인가번호 추가'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '인가번호'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    final c = (code ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (c.isEmpty) return;
    if (list.contains(c)) return;
    onChanged([...list, c]);
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
      league: _league.text.trim(),
      unit: _unit.text.trim(),
      regLeague: _regLeague.text.trim(),
      regUnit: _regUnit.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      date: _date.text.trim(),
      atasNo: _atas.text.trim(),
      activity: _activity.text.trim(),
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
    await state.save(member);
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
