import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/member_avatar.dart';

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
      _address,
      _phone,
      _email,
      _date,
      _atas,
      _activity,
      _memo;

  String _photoPath = '';
  bool _lifetime = false;
  Map<String, bool> _fees = {};
  Member? _existing;

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
    _address = TextEditingController(text: m?.address ?? '');
    _phone = TextEditingController(text: m?.phone ?? '');
    _email = TextEditingController(text: m?.email ?? '');
    _date = TextEditingController(text: m?.date ?? '');
    _atas = TextEditingController(text: m?.atasNo ?? '');
    _activity = TextEditingController(text: m?.activity ?? '');
    _memo = TextEditingController(text: m?.memo ?? '');
    _photoPath = m?.photoPath ?? '';
    _lifetime = m?.lifetimeMember ?? false;
    _fees = Map<String, bool>.from(m?.feeYears ?? {});
  }

  @override
  void dispose() {
    for (final c in [
      _number,
      _name,
      _league,
      _unit,
      _address,
      _phone,
      _email,
      _date,
      _atas,
      _activity,
      _memo,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: Text(isNew ? '인가자 추가' : '인가자 편집'),
        actions: [
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
            const SizedBox(height: 16),
            _field(
              '인가번호',
              _number,
              hint: '예: 2186',
              icon: Icons.tag,
              numeric: true,
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
            ),
            _field(
              '이메일',
              _email,
              hint: 'name@example.com',
              icon: Icons.email,
              keyboard: TextInputType.emailAddress,
            ),
            _field(
              '주소',
              _address,
              hint: '주소 입력',
              icon: Icons.home,
              maxLines: 2,
            ),
            _field(
              '활동',
              _activity,
              hint: '활동 내용 (예: 지도자 양성, 캠프 운영 등)',
              icon: Icons.directions_run,
              maxLines: 2,
            ),
            _field('메모', _memo, hint: '자유 메모', icon: Icons.notes, maxLines: 3),
            const SizedBox(height: 8),
            _feeEditor(),
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
            if (!isNew)
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
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboard,
        onChanged: (_) => setState(() {}),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '필수 입력 항목입니다' : null
            : null,
        decoration: InputDecoration(
          labelText: label + (required ? ' *' : ''),
          hintText: hint,
          prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        ),
      ),
    );
  }

  void _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (kIsWeb || _photoPath.startsWith('data:')) {
      // base64는 그대로 저장
    }
    final state = context.read<AppState>();
    final id = _existing?.id ?? 'u${DateTime.now().millisecondsSinceEpoch}';

    final member = Member(
      id: id,
      number: _number.text.trim(),
      name: _name.text.trim(),
      league: _league.text.trim(),
      unit: _unit.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      date: _date.text.trim(),
      atasNo: _atas.text.trim(),
      activity: _activity.text.trim(),
      memo: _memo.text.trim(),
      photoPath: _photoPath,
      lifetimeMember: _lifetime,
      feeYears: Map<String, bool>.from(_fees)
        ..removeWhere((k, v) => v == false),
      eventAttend: _existing?.eventAttend ?? {},
    );
    await state.save(member);

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
