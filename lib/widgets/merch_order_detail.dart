import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';

/// 수품 주문/예약 **상세 내역** 다이얼로그.
///
/// 주문번호를 클릭했을 때 호출한다. 관리자 화면과 개인 프로필(수품구매 내역)
/// 양쪽에서 동일한 형태로 재사용한다.
/// - [editable] == true(관리자·마스터)이면 주문 정보·금액·진행상태를 수정할 수 있다.
/// - 수정/저장 성공 시 [onChanged] 콜백으로 목록을 새로고침한다.
class MerchOrderDetail {
  static Future<bool?> show(
    BuildContext context, {
    required Map<String, dynamic> rec,
    required bool isReserve,
    List<String> statuses = const [],
    bool editable = false,
    Future<void> Function()? onChanged,
    Future<bool> Function()? onDelete,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => _MerchOrderDetailDialog(
        rec: Map<String, dynamic>.from(rec),
        isReserve: isReserve,
        statuses: statuses,
        editable: editable,
        onChanged: onChanged,
        onDelete: onDelete,
      ),
    );
  }
}

class _MerchOrderDetailDialog extends StatefulWidget {
  const _MerchOrderDetailDialog({
    required this.rec,
    required this.isReserve,
    required this.statuses,
    required this.editable,
    this.onChanged,
    this.onDelete,
  });

  final Map<String, dynamic> rec;
  final bool isReserve;
  final List<String> statuses;
  final bool editable;
  final Future<void> Function()? onChanged;
  final Future<bool> Function()? onDelete;

  @override
  State<_MerchOrderDetailDialog> createState() =>
      _MerchOrderDetailDialogState();
}

class _MerchOrderDetailDialogState extends State<_MerchOrderDetailDialog> {
  late Map<String, dynamic> r = widget.rec;
  bool _busy = false;

  NasApi get _nas => context.read<NasApi>();

  String _s(String k) => (r[k] ?? '').toString().trim();

  int _i(String k) {
    final v = r[k];
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

  Future<void> _saveOrder(Map<String, dynamic> patch) async {
    setState(() => _busy = true);
    try {
      final res = await _nas.merchUpdateOrderRaw(
        id: '${r['id']}',
        fields: patch,
      );
      if (!mounted) return;
      if (res['ok'] == true && res['order'] is Map) {
        setState(() => r = (res['order'] as Map).cast<String, dynamic>());
        await widget.onChanged?.call();
        if (mounted) _snack('저장했습니다');
      } else {
        _snack('저장 실패: ${res['error']}');
      }
    } catch (e) {
      if (mounted) _snack('오류: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveReserve(Map<String, dynamic> patch) async {
    setState(() => _busy = true);
    try {
      final res = await _nas.merchUpdateReserveRaw(
        id: '${r['id']}',
        fields: patch,
      );
      if (!mounted) return;
      if (res['ok'] == true && res['reservation'] is Map) {
        setState(() => r = (res['reservation'] as Map).cast<String, dynamic>());
        await widget.onChanged?.call();
        if (mounted) _snack('저장했습니다');
      } else {
        _snack('저장 실패: ${res['error']}');
      }
    } catch (e) {
      if (mounted) _snack('오류: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 1800)),
    );
  }

  /// 주문 정보 편집(상품/수량/단가/주문자/연락처/주소/메모).
  Future<void> _editInfo() async {
    final product = TextEditingController(text: _s('product'));
    final qty = TextEditingController(
      text: '${_i('qty') == 0 ? 1 : _i('qty')}',
    );
    final unit = TextEditingController(text: '${_i('unitPrice')}');
    final fee = TextEditingController(text: '${_i('annualFeeAdded')}');
    final buyer = TextEditingController(text: _s('buyerName'));
    final number = TextEditingController(text: _s('buyerNumber'));
    final phone = TextEditingController(text: _s('phone'));
    final email = TextEditingController(text: _s('email'));
    final address = TextEditingController(text: _s('address'));
    final memo = TextEditingController(text: _s('memo'));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.isReserve ? '예약 정보 수정' : '주문 정보 수정'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _f(product, '상품명'),
                _f(qty, '수량', number: true),
                if (!widget.isReserve) _f(unit, '단가 (원)', number: true),
                if (!widget.isReserve) _f(fee, '연회비 가산 (원)', number: true),
                _f(buyer, '주문자명'),
                _f(number, '인가번호', number: true),
                _f(phone, '연락처'),
                _f(email, '이메일'),
                if (!widget.isReserve) _f(address, '주소'),
                _f(memo, '메모'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final patch = <String, dynamic>{
      'product': product.text.trim(),
      'qty': int.tryParse(qty.text.trim()) ?? 1,
      'buyerName': buyer.text.trim(),
      'buyerNumber': number.text.trim(),
      'phone': phone.text.trim(),
      'email': email.text.trim(),
      'memo': memo.text.trim(),
      if (!widget.isReserve) 'unitPrice': int.tryParse(unit.text.trim()) ?? 0,
      if (!widget.isReserve)
        'annualFeeAdded': int.tryParse(fee.text.trim()) ?? 0,
      if (!widget.isReserve) 'address': address.text.trim(),
    };
    if (widget.isReserve) {
      await _saveReserve(patch);
    } else {
      await _saveOrder(patch);
    }
  }

  /// 금액만 빠르게 수정.
  Future<void> _editAmount() async {
    final unit = TextEditingController(text: '${_i('unitPrice')}');
    final qty = TextEditingController(
      text: '${_i('qty') == 0 ? 1 : _i('qty')}',
    );
    final fee = TextEditingController(text: '${_i('annualFeeAdded')}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('금액 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _f(unit, '단가 (원)', number: true),
            _f(qty, '수량', number: true),
            _f(fee, '연회비 가산 (원)', number: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _saveOrder({
      'unitPrice': int.tryParse(unit.text.trim()) ?? 0,
      'qty': int.tryParse(qty.text.trim()) ?? 1,
      'annualFeeAdded': int.tryParse(fee.text.trim()) ?? 0,
    });
  }

  Widget _f(TextEditingController c, String label, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.editable;
    final isReserve = widget.isReserve;
    final orderNo = _s('orderNo');
    final product = _s('product');
    final qty = _i('qty') == 0 ? 1 : _i('qty');
    final unit = _i('unitPrice');
    final total = _i('total');
    final fee = _i('annualFeeAdded');
    final grand = r['grandTotal'] != null ? _i('grandTotal') : total + fee;
    final status = _s('status').isEmpty
        ? (isReserve ? '예약접수' : '입금확인중')
        : _s('status');
    final paid = r['paid'] == true;
    final created = _s('created').isEmpty ? _s('createdAt') : _s('created');
    final history = (r['statusHistory'] as List?) ?? const [];
    final option = _s('option');
    final size = _s('size');

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Row(
        children: [
          Icon(
            isReserve ? Icons.bookmark_border : Icons.receipt_long,
            color: isReserve ? Colors.orange : AppColors.purple,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isReserve ? '예약 상세 내역' : '주문 상세 내역',
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purpleDark,
                      ),
                    ),
                    if (editable) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.tigerGold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '수정가능',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.lifetimeGold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (orderNo.isNotEmpty)
                  Text(
                    isReserve ? '예약번호 $orderNo' : '주문번호 $orderNo',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.purple,
                      letterSpacing: 0.2,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusHeader(status, paid, isReserve),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '주문 정보',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purpleDark,
                      ),
                    ),
                  ),
                  if (editable)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _busy ? null : _editInfo,
                      icon: const Icon(Icons.edit, size: 15),
                      label: const Text(
                        '정보 수정',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
              _group('', [
                ('구분', isReserve ? '예약(수요조사)' : '주문'),
                ('대표 상품', product.isEmpty ? '-' : product),
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
                (isReserve ? '접수일' : '주문일', created.isEmpty ? '-' : created),
                if (!isReserve)
                  ('배송방법', _s('shipMethod').isEmpty ? '-' : _s('shipMethod')),
                if (!isReserve && _s('address').isNotEmpty)
                  ('주소', _s('address')),
                if (!isReserve && _s('shipNote').isNotEmpty)
                  ('배송메모', _s('shipNote')),
                if (_s('memo').isNotEmpty) ('메모', _s('memo')),
                if (_s('note').isNotEmpty) ('요청', _s('note')),
              ]),
              if (history.isNotEmpty) ...[
                const SizedBox(height: 10),
                _group('진행 이력', [
                  for (final h in history)
                    if (h is Map)
                      (
                        '${h['status'] ?? ''}',
                        '${h['at'] ?? ''}${'${h['by'] ?? ''}'.isNotEmpty ? ' · ${h['by']}' : ''}',
                      )
                    else
                      ('$h', ''),
                ]),
              ],
              if (widget.statuses.isNotEmpty) ...[
                const SizedBox(height: 10),
                _progressSteps(widget.statuses, status),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (editable && !isReserve) ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : _editAmount,
            icon: const Icon(Icons.payments_outlined, size: 16),
            label: const Text('금액 수정'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _saveOrder({'paid': !paid}),
            icon: Icon(
              paid ? Icons.undo : Icons.check_circle_outline,
              size: 16,
            ),
            label: Text(paid ? '입금 취소' : '입금 처리'),
          ),
        ],
        if (editable && widget.onDelete != null)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.taegeukRed),
            onPressed: _busy
                ? null
                : () async {
                    final okDel = await widget.onDelete!.call();
                    if (okDel && context.mounted) {
                      Navigator.pop(context, true);
                    }
                  },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('삭제'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
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
          Icon(
            cancelled ? Icons.cancel_outlined : Icons.timeline,
            size: 18,
            color: c,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: widget.editable && !isReserve
                ? DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: widget.statuses.contains(status)
                          ? status
                          : (widget.statuses.isNotEmpty
                                ? widget.statuses.first
                                : null),
                      isDense: true,
                      isExpanded: true,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: c,
                      ),
                      items: [
                        for (final s in widget.statuses)
                          DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v != null) _saveOrder({'status': v});
                            },
                    ),
                  )
                : Text(
                    status,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: c,
                    ),
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
              child: Text(
                paid ? '입금완료' : '미입금',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: paid ? AppColors.scoutGreen : AppColors.taegeukRed,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _group(String title, List<(String, String)> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.purpleDark,
            ),
          ),
        if (title.isNotEmpty) const SizedBox(height: 5),
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
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 74,
                        child: Text(
                          row.$1,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGray,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.$2,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
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
        const Text(
          '아이템 진행 상황',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: AppColors.purpleDark,
          ),
        ),
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
                        right: i == steps.length - 1 ? 0 : 3,
                      ),
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
