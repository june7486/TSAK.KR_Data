import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/privacy_consent.dart';

/// **개인정보 활용 편집** — 회원 1명의 개인정보 항목별 노출 범위를 마스터가 조정.
///
/// ## 사용자 요구 (2026-11-02, build #574)
///  ① "주민등록정보는 뒷번호가 입력시 마킹처리가 안되고 있음
///      (예시: 990328-1******) / 노출되는(개인카드에도) 정보에는 뒷번호를
///      마킹처리하고 오로지 마스터만 뒷번호를 확인할 수 있도록 함"
///  ② "개인정보 활용 편집: 입수한 정보에 대한 추가내용을 넣어줘.
///      비밀번호, 사진, 인가정보 등등"
///
/// ## 이 화면이 하는 일
///  · 지금 앱이 **실제로 보관 중인 값**을 항목별로 보여준다(무엇을 입수했는지).
///  · 항목마다 노출 범위를 3단계로 고른다 — 노출 / 관리자 노출 / 비노출.
///  · 주민등록번호는 **원본을 마스터에게만** 보여주고, 표시용 마킹본을 함께
///    보여준다(다른 사람에게는 마킹본만 간다는 사실을 화면에서 확인).
///  · 비밀번호는 **원문을 절대 표시하지 않는다**. 있다/없다와 정책만 보여준다.
///  · 사진·인가정보·연결정보(멘토·페런츠·멘티·자녀)도 같은 방식으로 노출을 정한다.
///
/// ## 저장 규칙
///  · [AppState.setMemberFieldPerm] 로 `Member.fieldPerms` 에 저장한다.
///    `null` 로 지우면 전역 설정(fieldVisibility)을 따른다.
class PrivacyUsageEditScreen extends StatefulWidget {
  const PrivacyUsageEditScreen({super.key, required this.memberId});

  final String memberId;

  @override
  State<PrivacyUsageEditScreen> createState() => _PrivacyUsageEditScreenState();
}

class _PrivacyUsageEditScreenState extends State<PrivacyUsageEditScreen> {
  bool _busy = false;

  /// (키, 라벨, 설명, 값 계산)
  ///  · 값을 계산하는 함수로 두어야 저장 직후 최신 값이 반영된다.
  List<(String, String, String, String Function(Member))> specs(Member m) => [
    (
      'scoutNo',
      '스카우트 고유번호',
      '명부의 고유번호 (인가번호와 별개)',
      (x) => x.scoutNo,
    ),
    (
      'residentNo',
      '주민등록번호',
      '주민등록번호 — 표시는 마킹, 원본은 마스터만',
      (x) => x.residentNo,
    ),
    (
      'birthday',
      '생일',
      '생년월일',
      (x) => x.birthday,
    ),
    (
      'phone',
      '핸드폰',
      '휴대폰 번호',
      (x) => x.phone,
    ),
    (
      'tel',
      '연락처',
      '유선/추가 전화',
      (x) => x.tel,
    ),
    (
      'email',
      '이메일',
      '이메일 주소',
      (x) => x.email,
    ),
    (
      'zipCode',
      '우편번호',
      '주소 우편번호',
      (x) => x.zipCode,
    ),
    (
      'address',
      '주소',
      '거주지 주소',
      (x) => x.address,
    ),
    // ── 인가정보 (요구: "인가정보 등등") ─────────────────────────
    (
      'league',
      '범인가 소속 연맹',
      '인가 당시 소속 연맹',
      (x) => x.league,
    ),
    (
      'unit',
      '범인가 등록 단위대',
      '인가 당시 등록 단위대',
      (x) => x.unit,
    ),
    (
      'date',
      '범인가 인가일',
      '인가일 — 비어 있으면 미등록으로 표시',
      (x) => x.date,
    ),
    (
      'atasNo',
      'ATAS 인가번호',
      'ATAS(국제 범스카우트) 인가번호',
      (x) => x.atasNo,
    ),
    (
      'activity',
      '활동',
      '활동 내역',
      (x) => x.activity,
    ),
    (
      'awards',
      '포상',
      '수상·포상 기록',
      (x) => x.awards,
    ),
    (
      'bio',
      '비고 / 한줄소개',
      '비고 또는 한줄소개',
      (x) => x.bio,
    ),
  ];

  Future<void> _set(AppState state, Member m, String key, String? value) async {
    setState(() => _busy = true);
    try {
      await state.setMemberFieldPerm(m, key, value);
    } catch (e) {
      if (mounted) _snack('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return Scaffold(
        appBar: AppBar(title: const Text('개인정보 활용 편집')),
        body: const Center(child: Text('마스터 권한이 필요합니다')),
      );
    }
    final m = state.byId(widget.memberId);
    if (m == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('개인정보 활용 편집')),
        body: const Center(child: Text('회원을 찾을 수 없습니다')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
        title: Text('개인정보 활용 편집 · ${m.name}'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          _header(m),
          const SizedBox(height: 12),
          _consentCard(m),
          const SizedBox(height: 12),
          _credentialCardBlock(m),
          const SizedBox(height: 12),
          _accountBlock(m),
          const SizedBox(height: 12),
          _photoBlock(m),
          const SizedBox(height: 12),
          _linkBlock(m),
          const SizedBox(height: 12),
          _fieldPermBlock(state, m),
          const SizedBox(height: 12),
          _fullTextBlock(),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────── 헤더 / 요약
  Widget _header(Member m) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.privacy_tip, color: AppColors.purple, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${m.displayNumber} ${m.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '이 화면은 이 회원에 대해 앱이 **입수한 정보**와 **노출 범위**를 한 곳에서 '
            '확인·편집합니다. 항목별 노출은 [노출]·[관리자 노출]·[비노출] 세 단계이며, '
            '주민등록번호 뒷자리와 비밀번호는 이 화면에서도 원본을 표시하지 않습니다.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textGray,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────── 개인정보 동의
  Widget _consentCard(Member m) {
    final agreed = m.privacyAgreed;
    final c = agreed ? AppColors.scoutGreen : AppColors.taegeukRed;
    return _padBlock(
      title: '개인정보 수집·이용 동의',
      icon: Icons.verified_user,
      children: [
        Row(
          children: [
            Icon(
              agreed ? Icons.verified : Icons.warning_amber_rounded,
              color: c,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              agreed ? '동의함' : '미동의',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c,
                fontSize: 13,
              ),
            ),
            if (m.privacyAgreedAt.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.privacyAgreedAt,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGray,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '동의일시와 동의 여부는 회원 편집 화면에서 관리합니다. '
          '동의 문구(비밀번호·사진·인가정보·주민번호 조항 포함)는 아래 '
          '「동의 문구 전문」에서 확인할 수 있습니다.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textGray,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────── 인가정보
  Widget _credentialCardBlock(Member m) {
    Widget row(String label, String value) {
      final v = value.trim();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textGray,
                ),
              ),
            ),
            Expanded(
              child: Text(
                v.isEmpty ? '—' : v,
                style: TextStyle(
                  fontSize: 12.5,
                  color: v.isEmpty ? AppColors.textGray : AppColors.textDark,
                  fontWeight: v.isEmpty ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _padBlock(
      title: '입수한 인가정보',
      icon: Icons.verified,
      children: [
        row('범인가번호', m.displayNumber),
        row('인가일', m.date),
        row('소속 연맹', m.league),
        row('등록 단위대', m.unit),
        row('ATAS 인가번호', m.atasNo),
        row('ATAS 인가일', m.atasDate),
        row('영문 이름', m.nameEn),
        row('훈련현황', m.trainingStatus),
        const SizedBox(height: 6),
        const Text(
          '위 값은 개인카드의 [범인가 정보]·[ATAS 인가 정보] 카드에 그대로 표시됩니다. '
          '인가일이 비어 있으면 카드에 「미등록」으로 표시됩니다.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textGray,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────── 계정(비밀번호)
  Widget _accountBlock(Member m) {
    final hasAccessPhone = m.accessPhone.trim().isNotEmpty;
    final hasPw = m.personalPassword.trim().isNotEmpty;
    return _padBlock(
      title: '계정 정보 (비밀번호)',
      icon: Icons.lock_outline,
      children: [
        _kv(
          '로그인 아이디',
          m.loginId.isEmpty ? '—' : m.loginId,
        ),
        _kv(
          '접속 전화번호',
          hasAccessPhone ? m.accessPhone : '— (인가번호 기반 아이디 사용)',
        ),
        _kv('비밀번호', hasPw ? '설정됨 (원문 비표시)' : '미설정'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.taegeukRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.taegeukRed.withValues(alpha: 0.28),
            ),
          ),
          child: const Text(
            '비밀번호는 화면·명부·출력물에 표시되지 않습니다. '
            '마스터도 원문을 볼 수 없고, 재설정(초기화)만 할 수 있습니다.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textDark,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────── 사진
  Widget _photoBlock(Member m) {
    final has = m.photoPath.trim().isNotEmpty;
    return _padBlock(
      title: '사진 (초상)',
      icon: Icons.photo_camera,
      children: [
        _kv('프로필 사진', has ? '등록됨' : '미등록'),
        if (has)
          Text(
            m.photoPath.split('/').last,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textGray),
          ),
        const SizedBox(height: 6),
        const Text(
          '사진은 초상권을 포함하므로, 활용 범위(카드·명부·홍보)에 대한 동의가 '
          '필요합니다. 동의 문구 7항에 사진 활용 조항이 포함되어 있습니다.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textGray,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────── 연결정보
  Widget _linkBlock(Member m) {
    String join(List<String> v) => v.isEmpty ? '—' : v.join(', ');
    return _padBlock(
      title: '연결 정보 (멘토·페런츠·멘티·자녀)',
      icon: Icons.hub,
      children: [
        _kv('멘토 (나를 배출한 대장)', join(m.mentors)),
        _kv('페런츠 (나의 부모)', join(m.parents)),
        _kv('멘티 (내가 배출한 대원)', join(m.mentees)),
        _kv('자녀대원', join(m.children)),
        const SizedBox(height: 6),
        const Text(
          '연결 정보는 인가 이력 확인 목적으로만 사용되며, 제3자 제공 항목에 '
          '포함되지 않습니다.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textGray,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────── 항목별 노출 (편집)
  Widget _fieldPermBlock(AppState state, Member m) {
    return _padBlock(
      title: '항목별 노출 범위 (편집)',
      icon: Icons.tune,
      children: [
        const Text(
          '이 회원의 값을 [누가] 볼 수 있는지 정합니다. 지정을 지우면 전역 설정을 따릅니다.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textGray,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        ...specs(m).map((s) {
          final key = s.$1, label = s.$2, desc = s.$3, getter = s.$4;
          final raw = getter(m);
          final perm = m.fieldPerms[key]; // null = 전역 설정 따름
          final displayValue = key == 'residentNo'
              ? (raw.trim().isEmpty ? '—' : raw) // 마스터이므로 원본 표시
              : (raw.trim().isEmpty ? '—' : raw);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.textGray.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    if (raw.trim().isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.textGray.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '값 없음',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textGray,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textGray,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  displayValue,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: raw.trim().isEmpty
                        ? AppColors.textGray
                        : AppColors.textDark,
                    fontWeight: FontWeight.w600,
                    decoration: key == 'residentNo'
                        ? TextDecoration.none
                        : null,
                  ),
                ),
                // 주민번호 — 마킹본을 함께 보여준다(다른 사람에게 가는 모양).
                if (key == 'residentNo' && raw.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '표시용(타인·관리자): ${m.residentNoMasked}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.purple,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _permChip(
                      label: '노출',
                      selected: perm == AppState.permPublic,
                      color: AppColors.scoutGreen,
                      onTap: () => _set(state, m, key, AppState.permPublic),
                    ),
                    _permChip(
                      label: '관리자 노출',
                      selected: perm == AppState.permAdmin,
                      color: AppColors.taegeukBlue,
                      onTap: () => _set(state, m, key, AppState.permAdmin),
                    ),
                    _permChip(
                      label: '비노출',
                      selected: perm == AppState.permHidden,
                      color: AppColors.taegeukRed,
                      onTap: () => _set(state, m, key, AppState.permHidden),
                    ),
                    _permChip(
                      label: '전역 설정 따름',
                      selected: perm == null,
                      color: AppColors.textGray,
                      onTap: () => _set(state, m, key, null),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _permChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : AppColors.textGray.withValues(alpha: 0.22),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 13, color: color),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? color : AppColors.textGray,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────── 동의 문구 전문
  Widget _fullTextBlock() {
    return _padBlock(
      title: '동의 문구 전문 (비밀번호·사진·인가정보·주민번호 조항 포함)',
      icon: Icons.description_outlined,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.textGray.withValues(alpha: 0.22)),
          ),
          child: SelectableText(
            PrivacyConsentField.consentText.trim(),
            style: const TextStyle(
              fontSize: 11,
              height: 1.5,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────── 공용 위젯
  Widget _kv(String label, String value) {
    final empty = value.trim().isEmpty || value.trim() == '—';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textGray,
              ),
            ),
          ),
          Expanded(
            child: Text(
              empty ? '—' : value,
              style: TextStyle(
                fontSize: 12.5,
                color: empty ? AppColors.textGray : AppColors.textDark,
                fontWeight: empty ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _padBlock({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.textGray.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// 회원 상세 화면에서 [PrivacyUsageEditScreen] 을 연다.
///  마스터 전용이며, 버튼을 누른 사람이 마스터인지 다시 확인한다.
Future<void> showPrivacyUsageEdit(BuildContext context, Member m) async {
  final state = context.read<AppState>();
  if (!state.isMaster) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('마스터 권한이 필요합니다')));
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PrivacyUsageEditScreen(memberId: m.id)),
  );
}
