import 'package:flutter/material.dart';
import '../widgets/marquee_text.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 회원정보 항목별 노출 설정 (마스터 전용, 요구: 민감정보 노출 선택).
///
/// 명단 엑셀에서 반영된 모든 항목 중, 타인(일반 인가자·비인가자)에게
/// 어디까지 보여줄지를 항목별로 켜고 끈다. 민감정보(주민번호·연락처·주소 등)는
/// 기본 비노출이며, 관리자(admin) 및 본인에게는 항상 전체가 노출된다.
class MemberFieldVisibilityScreen extends StatefulWidget {
  const MemberFieldVisibilityScreen({super.key});

  @override
  State<MemberFieldVisibilityScreen> createState() =>
      _MemberFieldVisibilityScreenState();
}

class _MemberFieldVisibilityScreenState
    extends State<MemberFieldVisibilityScreen> {
  bool _busy = false;

  /// (key, 라벨, 민감여부) — 서버 FIELD_SPECS 와 동일한 순서/키를 사용한다.
  static const List<(String, String, bool)> _specs = [
    ('scoutNo', '스카우트 고유번호', true),
    ('residentNo', '주민등록번호', true),
    ('tel', '연락처', true),
    ('phone', '핸드폰', true),
    ('email', '이메일', true),
    ('address', '주소', true),
    ('zipCode', '우편번호', true),
    ('birthday', '생일', true),
    ('bio', '비고/한줄소개', false),
    // 현재활동 — 별도 통계 산출 대상.
    ('regLeague', '현재 소속 연맹', false),
    ('regUnit', '현재 등록 단위대', false),
    ('position', '직위(현재활동)', false),
    // 범인가시(인가 당시) 정보.
    ('league', '범인가시 소속 연맹', false),
    ('unit', '범인가시 등록 단위대', false),
    ('date', '인가일', false),
    ('atasNo', 'ATAS 인가번호', false),
    ('activity', '활동', false),
    ('awards', '포상', false),
    ('specialtyCourses', '전문과정 이수', false),
  ];

  Future<void> _toggle(AppState state, String key, bool value) async {
    final before = state.fieldVisible(key);
    if (before == value) return;
    setState(() => _busy = true);
    try {
      await state.setFieldVisibility(key, value);
    } catch (e) {
      if (mounted) _snack('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return Scaffold(
        appBar: TsakAppBar(title: const Text('항목 노출 설정')),
        body: const Center(child: Text('마스터 권한이 필요합니다')),
      );
    }
    final sensitiveOn = _specs
        .where((s) => s.$3 && state.fieldVisible(s.$1))
        .length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        title: const Text('개인정보 기본 노출 설정'),
        actions: const [AppHomeEmblem(size: 22)],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.visibility_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '명단 항목 기본 노출값',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '전체 회원에게 동일하게 적용되는 기본 노출값입니다.\n'
                            '개별 회원은 각자 페이지에서 따로 조정할 수 있습니다.\n'
                            '민감정보 공개 $sensitiveOn건 · 관리자·본인은 항상 전체 표시',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _sectionLabel('민감정보 (기본 비노출 권장)'),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final s in _specs.where((s) => s.$3))
                      _switchTile(state, s.$1, s.$2, true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _sectionLabel('일반정보'),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final s in _specs.where((s) => !s.$3))
                      _switchTile(state, s.$1, s.$2, false),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '· 여기서 설정한 값은 전체 회원의 기본 노출값으로 동일하게 적용됩니다.\n'
                  '· 개별 회원 페이지에서 항목별 “노출/관리자/비노출/삭제”로 조정하면 그 값이 우선합니다.\n'
                  '· 주민등록번호·연락처 등 민감정보 공개는 신중히 판단하세요.',
                  style: TextStyle(color: AppColors.textGray, fontSize: 12),
                ),
              ),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black.withValues(alpha: 0.25),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 4, left: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: AppColors.textGray,
      ),
    ),
  );

  Widget _switchTile(AppState state, String key, String label, bool sensitive) {
    final on = state.fieldVisible(key);
    return SwitchListTile(
      dense: true,
      value: on,
      onChanged: (v) => _toggle(state, key, v),
      title: Row(
        children: [
          Flexible(
            child: MarqueeText(label, style: const TextStyle(fontSize: 14)),
          ),
          if (sensitive) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.taegeukRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '민감',
                style: TextStyle(
                  color: AppColors.taegeukRed,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        on ? '노출 중 — 타인에게 표시됨' : '비노출 — 관리자·본인만 표시',
        style: TextStyle(
          fontSize: 11,
          color: on ? AppColors.scoutGreen : AppColors.textGray,
        ),
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }
}
