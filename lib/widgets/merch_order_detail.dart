import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 수품 주문/예약 **상세 내역** 다이얼로그.
///
/// 주문번호를 클릭했을 때 호출한다. 관리자 화면과 개인 프로필(수품구매 내역)
/// 양쪽에서 동일한 형태로 재사용한다. 주문은 상품 1건 단위로 저장되므로
/// 이 다이얼로그 하나가 곧 "해당 아이템의 현재 진행 상황"이 된다.
class MerchOrderDetail {
  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> rec,
    required bool isReserve,
    List<String> statuses = const [],
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _MerchOrderDetailDialog(
        rec: rec,
        isReserve: isReserve,
        statuses: statuses,
      ),
    );
  }
}

class _MerchOrderDetailDialog extends StatelessWidget {
  const _MerchOrderDetailDialog({
    required this.rec,
    required this.isReserve,
    required this.statuses,
  });

  final Map<String, dynamic> rec;
  final bool isReserve;
  final List<String> statuses;

  String _s(String k) => (rec[k] ?? '').toString().trim();

  int _i(String k) {
    final v = rec[k];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  String _won(num? v) {
    final n = v?.toInt() ?? 0;
    final s = n.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}${b.toString()}원';
  }

  @override
  Widget build(BuildContext context) {
    final orderNo = _s('orderNo');
    final product = _s('product');
    final qty = _i('qty') == 0 ? 1 : _i('qty');
    final unit = _i('unitPrice');
    final total = _i('total');
    final fee = _i('annualFeeAdded');
    final grand = rec['grandTotal'] != null ? _i('grandTotal') : total + fee;
    final status = _s('status').isEmpty
        ? (isReserve ? '예약접수' : '입금확인중')
        : _s('status');
    final paid = rec['paid'] == true;
    final created = _s('created').isEmpty ? _s('createdAt') : _s('created');
    final history = (rec['statusHistory'] as List?) ?? const [];
    final option = _s('option');
    final size = _s('size');

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Row(
        children: [
          Icon(isReserve ? Icons.bookmark_border : Icons.receipt_long,
              color: isReserve ? Colors.orange : AppColors.purple, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isReserve ? '예약 상세 내역' : '주문 상세 내역',
                    style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purpleDark)),
                if (orderNo.isNotEmpty)
                  Text(isReserve ? '예약번호 $orderNo' : '주문번호 $orderNo',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.purple,
                          letterSpacing: 0.2)),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusHeader(status, paid, isReserve),
              const SizedBox(height: 12),
              _group('주문 정보', [
                ('구분', isReserve ? '예약(수요조사)' : '주문'),
                ('상품', product.isEmpty ? '-' : product),
                if (option.isNotEmpty) ('옵션', option),
                if (size.isNotEmpty) ('사이즈', size),
                ('수량', '$qty개'),
                if (unit > 0) ('단가', _won(unit)),
                ('상품금액', _won(total)),
                if (fee > 0) ('연회비', _won(fee)),
                ('합계금액', _won(grand)),
              ]),
              const SizedBox(height: 10),
              _group('주문자 정보', [
                ('주문자', _s('buyerName').isEmpty ? '-' : _s('buyerName')),
                ('인가번호', _s('buyerNumber').isEmpty ? '-' : _s('buyerNumber')),
                ('연락처', _s('phone').isEmpty ? '-' : _s('phone')),
                ('이메일', _s('email').isEmpty ? '-' : _s('email')),
              ]),
              const SizedBox(height: 10),
              _group(isReserve ? '접수 정보' : '배송 정보', [
                (
                  isReserve ? '접수일' : '주문일',
                  created.isEmpty ? '-' : created
                ),
                if (!isReserve) ('배송방법', _s('shipMethod').isEmpty ? '-' : _s('shipMethod')),
                if (!isReserve && _s('address').isNotEmpty) ('주소', _s('address')),
                if (!isReserve && _s('shipNote').isNotEmpty) ('배송메모', _s('shipNote')),
                if (_s('memo').isNotEmpty) ('메모', _s('memo')),
                if (_s('note').isNotEmpty) ('요청', _s('note')),
              ]),
              if (history.isNotEmpty) ...[
                const SizedBox(height: 10),
                _group(
                  '진행 이력',
                  [
                    for (final h in history)
                      if (h is Map)
                        (
                          '${h['status'] ?? ''}',
                          '${h['at'] ?? ''}${'${h['by'] ?? ''}'.isNotEmpty ? ' · ${h['by']}' : ''}'
                        )
                      else ('$h', ''),
                  ],
                ),
              ],
              if (statuses.isNotEmpty && !isReserve) ...[
                const SizedBox(height: 10),
                _progressSteps(statuses, status),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }

  Widget _statusHeader(String status, bool paid, bool isReserve) {
    final cancelled = status.contains('취소');
    final c = cancelled
        ? AppColors.taegeukRed
        : isReserve
            ? Colors.orange
            : AppColors.purple;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(cancelled ? Icons.cancel_outlined : Icons.timeline,
              size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800, color: c),
            ),
          ),
          if (!isReserve)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (paid ? AppColors.scoutGreen : AppColors.taegeukRed)
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(paid ? '입금완료' : '미입금',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: paid ? AppColors.scoutGreen : AppColors.taegeukRed)),
            ),
        ],
      ),
    );
  }

  Widget _group(String title, List<(String, String)> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.purpleDark)),
        const SizedBox(height: 5),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.10)),
          ),
          child: Column(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 74,
                        child: Text(r.$1,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textGray)),
                      ),
                      Expanded(
                        child: Text(r.$2,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _progressSteps(List<String> steps, String status) {
    final current = steps.indexOf(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('아이템 진행 상황',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.purpleDark)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (int i = 0; i < steps.length; i++)
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 6,
                      margin: EdgeInsets.only(
                          right: i == steps.length - 1 ? 0 : 3),
                      decoration: BoxDecoration(
                        color: i <= current
                            ? AppColors.purple
                            : AppColors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 8,
                        color: i <= current
                            ? AppColors.purpleDark
                            : AppColors.textGray,
                        fontWeight: i == current
                            ? FontWeight.w800
                            : FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
