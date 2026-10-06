import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/tsak_app_bar.dart';

/// 수품(상품·기획사전신청) 확대 이미지 + 상세 설명 화면.
///
/// 요구사항:
///  · 이미지를 클릭하면 **확대 사진**과 **모든 상세 설명**이 누락 없이 노출된다.
///  · 항상 **돌아가기(뒤로)** 버튼을 두어 이전 창으로 안전하게 복귀한다(에러 방지).
///  · 이미지는 순수 수품 이미지(상·하단 텍스트 자동 크롭)로 보여준다.
class MerchDetailScreen extends StatefulWidget {
  const MerchDetailScreen({
    super.key,
    required this.item,
    this.isSurvey = false,
  });

  /// 상품/수요조사 원본 데이터 맵.
  final Map<String, dynamic> item;

  /// true 이면 수요조사(기획실) 항목으로 표시(가격/진행/신청 인원 등).
  final bool isSurvey;

  @override
  State<MerchDetailScreen> createState() => _MerchDetailScreenState();
}

class _MerchDetailScreenState extends State<MerchDetailScreen> {
  NasApi get _nas => context.read<NasApi>();

  String _s(String k) => '${widget.item[k] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final name = _s('name');
    final kind = _s('kind');
    final desc = _s('desc');
    final memo = _s('memo');
    final maker = _s('maker');
    final progress = _s('progress');
    final video = _s('video');
    final photo = widget.isSurvey ? _s('photo') : _s('image');
    final price = (it['price'] as num?)?.toInt() ?? 0;
    // 판매가능재고 — 수품구매에 노출되는 판매 가능 수량(관리자 직접입력, 기본 999).
    final sellable = (it['sellableStock'] as num?)?.toInt() ?? 999;
    final minQty = (it['minQty'] as num?)?.toInt() ?? 0;
    final count =
        (it['count'] as num?)?.toInt() ??
        ((it['applicants'] as List?)?.length ?? 0);
    final applicants = (it['applicants'] as List?) ?? const [];
    final options = ((it['options'] as List?) ?? []).map((e) => '$e').toList();
    final credentialOnly = it['credentialOnly'] == true;
    final imgUrl = photo.isEmpty ? '' : _nas.merchImageUrl(photo);

    // 상세 모든 항목(라벨→값) — 누락 없이 노출.
    final facts = <MapEntry<String, String>>[
      if (kind.isNotEmpty) MapEntry('구분', kind),
      if (credentialOnly) const MapEntry('자격', '범인가자 전용'),
      if (widget.isSurvey && progress.isNotEmpty) MapEntry('진행상황', progress),
      if (maker.isNotEmpty) MapEntry('기획자', maker),
      if (price > 0)
        MapEntry('가격', '${_won(price)}원')
      else
        const MapEntry('가격', '가격문의'),
      if (!widget.isSurvey)
        MapEntry('판매가능재고', sellable > 0 ? '$sellable개' : '품절'),
      if (widget.isSurvey) MapEntry('신청 현황', '$count명 신청 / 최소 제작 착수 $minQty명'),
      if (options.isNotEmpty) MapEntry('옵션', options.join(' · ')),
      if (video.isNotEmpty) MapEntry('영상', video),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        // 항상 뒤로가기 버튼(에러 시에도 이전 창으로 안전 복귀).
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '돌아가기',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(widget.isSurvey ? '수품 상세 (사전신청)' : '수품 상세'),
        actions: [
          TextButton.icon(
            onPressed: () {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.keyboard_return, size: 18),
            label: const Text(
              '돌아가기',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 확대 이미지 (클릭 시 더 크게 전체화면) ──
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                color: Colors.white,
                constraints: const BoxConstraints(minHeight: 220),
                child: imgUrl.isEmpty
                    ? const SizedBox(
                        height: 240,
                        child: Center(
                          child: Icon(
                            Icons.image_outlined,
                            size: 56,
                            color: AppColors.textGray,
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: () => _openFullscreen(imgUrl, name),
                        child: Hero(
                          tag: 'merch-img-${it['id']}',
                          child: Image.network(
                            imgUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (_, child, prog) => prog == null
                                ? child
                                : const SizedBox(
                                    height: 240,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                            errorBuilder: (_, __, ___) => const SizedBox(
                              height: 240,
                              child: Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 48,
                                  color: AppColors.textGray,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            if (imgUrl.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _openFullscreen(imgUrl, name),
                  icon: const Icon(Icons.zoom_in, size: 16),
                  label: const Text(
                    '이미지 크게 보기',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 6),

            // ── 상품명 + 요약 ──
            Text(
              name.isEmpty ? '수품' : name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            if (credentialOnly)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.scoutGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '범인가자 전용',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                  ),
                ),
              ),

            // ── 상세 정보 표 ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.purple.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 17,
                        color: AppColors.purple,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '상세 정보',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppColors.purpleDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final f in facts) _factRow(f.key, f.value),
                  if (desc.isNotEmpty) ...[
                    const Divider(height: 22),
                    const Text(
                      '설명',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      desc,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                  if (memo.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '추가 메모',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      memo,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),

            // ── 수요조사: 신청자 명단(진행 현황) ──
            if (widget.isSurvey && applicants.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.tigerGold.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.people_alt_outlined,
                          size: 17,
                          color: AppColors.tigerGold,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '신청자 명단 (${applicants.length}명)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < applicants.length; i++)
                      _applicantRow(i + 1, applicants[i]),
                  ],
                ),
              ),
            ],

            // ── 돌아가기 버튼(하단, 항상 노출) ──
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.purple,
                  side: BorderSide(
                    color: AppColors.purple.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text(
                  '돌아가기',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _factRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textGray,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _applicantRow(int no, dynamic a) {
    final m = (a as Map).cast<String, dynamic>();
    final name = '${m['name'] ?? ''}';
    final num_ = '${m['number'] ?? ''}';
    final memo = '${m['memo'] ?? ''}';
    final qty = (m['quantity'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$no',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.tigerGold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$name${num_.isNotEmpty ? ' ($num_)' : ''}'
              '${qty > 0 ? ' · $qty개' : ''}'
              '${memo.isNotEmpty ? ' · $memo' : ''}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 전체화면 확대 뷰(핀치줌 가능). 닫기 버튼 항상 노출 → 에러 방지.
  void _openFullscreen(String imgUrl, String name) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    imgUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.white54,
                        size: 60,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text(
                      '닫기',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ),
            if (name.isNotEmpty)
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _won(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return (v < 0 ? '-' : '') + b.toString();
  }
}
