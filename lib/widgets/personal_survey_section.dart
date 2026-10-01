import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/merch_shop_screen.dart';
import '../services/nas_api.dart';
import '../theme/app_theme.dart';

/// 개인 상세 정보창(MemberDetailScreen)에서 **수품 구매(MerchActivitySection)와 함께**
/// 노출되는 "수요 대기 (사전신청 순번)" 위젯.
///
/// - 개인/비인가 로그인(본인 열람) 시에만 의미가 있으므로, 표시 여부는 상위에서 판단한다.
/// - 진행중인 수요조사(사전신청) 항목이 하나도 없으면 아무것도 그리지 않는다.
/// - 본인이 사전신청한 항목은 "N번째 신청자"로 순번을, 미신청 항목은 "아직 미신청"으로
///   표시하고 최소 제작 인원 대비 현재 신청 인원 진행률을 보여준다.
class PersonalSurveySection extends StatefulWidget {
  const PersonalSurveySection({super.key, required this.ident});

  /// 본인 식별자(인가번호 또는 전화번호). 순번 매칭에 사용.
  final String ident;

  @override
  State<PersonalSurveySection> createState() => _PersonalSurveySectionState();
}

class _PersonalSurveySectionState extends State<PersonalSurveySection> {
  bool _loading = true;
  List<Map<String, dynamic>> _surveys = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final api = context.read<NasApi>();
      final r = await api.merch();
      if (!mounted) return;
      setState(() {
        _surveys = ((r['surveys'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

  /// 본인(ident)이 해당 수요조사에 신청한 순번. 미신청이면 0.
  int _mySeq(Map<String, dynamic> s) {
    final me = _digits(widget.ident);
    if (me.isEmpty) return 0;
    final apps = (s['applicants'] as List?) ?? [];
    for (final a in apps) {
      if (a is! Map) continue;
      final numv = _digits('${a['number'] ?? ''}');
      final cid = _digits('${a['contactId'] ?? ''}');
      final ph = _digits('${a['phone'] ?? ''}');
      if ((numv.isNotEmpty && numv == me) ||
          (cid.isNotEmpty && cid == me) ||
          (ph.isNotEmpty && ph == me)) {
        return (a['no'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // 로딩 중이거나 진행중 수요조사가 없으면 아무것도 표시하지 않는다.
    if (_loading || _surveys.isEmpty) return const SizedBox.shrink();

    // 신청한 사람의 프로필에만 노출한다 — 본인이 신청한(순번>0) 항목만 남긴다.
    final mine = _surveys.where((s) => _mySeq(s) > 0).toList();
    if (mine.isEmpty) return const SizedBox.shrink();

    // 다른 섹션(_section: Card + 12px 여백)과 동일한 박스 크기로 맞춘다.
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.campaign_outlined,
                  size: 18,
                  color: AppColors.tigerGold,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '수품 사전 신청 현황',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.purpleDark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(
                    Icons.refresh,
                    size: 18,
                    color: AppColors.textGray,
                  ),
                  tooltip: '새로고침',
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              '회원님이 신청한 수품 사전신청(수요조사) 현황입니다. '
              '최소 제작 착수 수량 달성 시 제작이 진행됩니다.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textGray,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            for (final s in mine) _row(s),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.purple,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MerchShopScreen()),
                ).then((_) => _load()),
                icon: const Icon(Icons.add_shopping_cart, size: 17),
                label: const Text(
                  '수품 사전신청 추가 (수품구매)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final name = '${s['name'] ?? ''}'.trim();
    final mySeq = _mySeq(s);
    final minQty = (s['minQty'] as num?)?.toInt() ?? 0;
    final count = (s['count'] as num?)?.toInt() ?? 0;
    final ratio = minQty > 0 ? (count / minQty).clamp(0.0, 1.0) : 0.0;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.tigerGold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.tigerGold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isEmpty ? '수품' : name,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              if (mySeq > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.tigerGold.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$mySeq번째 신청자',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.purpleDark,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.textGray.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '아직 미신청',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textGray,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '/ $count명 신청 (최소 $minQty명)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.purple,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.purpleLight.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(AppColors.tigerGold),
            ),
          ),
        ],
      ),
    );
  }
}
