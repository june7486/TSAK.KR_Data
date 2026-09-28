import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';
import '../widgets/address_field.dart';
import '../widgets/app_home_emblem.dart';

/// 수품 주문/예약 전용 화면 — 팝업(다이얼로그) 대신 전체 페이지로 구현하여
/// 모든 브라우저/모바일에서 오류 없이 동작하도록 한다.
///
/// mode == 'order'   : 결제 단계(공지확인·연회비·배송방법·입금자정보)
/// mode == 'reserve' : 예약/수요조사(구매의사 접수)
class MerchCheckoutScreen extends StatefulWidget {
  const MerchCheckoutScreen({
    super.key,
    required this.lines,
    required this.config,
    this.mode = 'order',
  });

  /// [{productId, name, image, price, option, qty}]
  final List<Map<String, dynamic>> lines;
  final Map<String, dynamic> config;
  final String mode;

  @override
  State<MerchCheckoutScreen> createState() => _MerchCheckoutScreenState();
}

class _MerchCheckoutScreenState extends State<MerchCheckoutScreen> {
  NasApi get _nas => context.read<NasApi>();
  bool get _isReserve => widget.mode == 'reserve';

  final _number = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _memo = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _noticeChecked = false;
  bool _feePaidYes = true; // 연간회비 납부 여부(예=면제, 아니요=추가)
  String _ship = '현장구매';
  bool _busy = false;

  Map<String, dynamic> get _account =>
      ((widget.config['account'] as Map?) ?? {}).cast<String, dynamic>();
  Map<String, dynamic> get _guide =>
      ((widget.config['guide'] as Map?) ?? {}).cast<String, dynamic>();
  int get _shipFee => (_account['shipFee'] as num?)?.toInt() ?? 0;
  int get _annualFee => (widget.config['annualFee'] as num?)?.toInt() ?? 0;
  String get _notices => '${widget.config['notices'] ?? ''}';

  int get _goodsTotal => widget.lines.fold<int>(
      0, (s, e) => s + ((e['price'] as num?)?.toInt() ?? 0) * ((e['qty'] as num?)?.toInt() ?? 1));
  int get _shipExtra => _ship == '택배발송' ? _shipFee : 0;
  int get _feeExtra =>
      (!_isReserve && !_feePaidYes && _annualFee > 0) ? _annualFee : 0;
  int get _grandTotal => _goodsTotal + _shipExtra + _feeExtra;

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _memo.dispose();
    super.dispose();
  }

  String _won(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${b.toString()}원';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_isReserve ? '수품 예약 (수요조사)' : '수품 주문 / 결제'),
        actions: const [AppHomeEmblem(size: 22)],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            if (_busy) ...[
              _waitingNotice(),
              const SizedBox(height: 12),
            ],
            _orderSummary(),
            const SizedBox(height: 12),
            _noticeSection(),
            const SizedBox(height: 12),
            if (!_isReserve) ...[
              _feeSection(),
              const SizedBox(height: 12),
            ],
            _buyerSection(),
            const SizedBox(height: 12),
            if (!_isReserve) ...[
              _shippingSection(),
              const SizedBox(height: 12),
            ],
            _totalSection(),
            const SizedBox(height: 16),
            _submitButton(),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.purple.withValues(alpha: 0.14)),
        ),
        child: child,
      );

  Widget _title(String t, {IconData? icon, Color? color}) => Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color ?? AppColors.purpleDark),
            const SizedBox(width: 6),
          ],
          Text(t,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: color ?? AppColors.purpleDark)),
        ],
      );

  // ── 주문 상품 요약 ──
  Widget _orderSummary() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(_isReserve ? '예약 상품' : '주문 상품', icon: Icons.inventory_2_outlined),
            const SizedBox(height: 8),
            for (final l in widget.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 40,
                        height: 40,
                        color: const Color(0xFFF7F5FB),
                        child: _nas.merchImageUrl('${l['image'] ?? ''}').isEmpty
                            ? const Icon(Icons.image_outlined,
                                size: 18, color: AppColors.textGray)
                            : Image.network(
                                _nas.merchImageUrl('${l['image'] ?? ''}'),
                                fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${l['name']}'
                        '${'${l['option'] ?? ''}'.isNotEmpty ? ' (${l['option']})' : ''}'
                        ' × ${l['qty']}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if ((l['price'] as num?)?.toInt() != null &&
                        (l['price'] as num?)!.toInt() > 0)
                      Text(
                          _won(((l['price'] as num).toInt()) *
                              ((l['qty'] as num?)?.toInt() ?? 1)),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.taegeukBlue)),
                  ],
                ),
              ),
          ],
        ),
      );

  // ── 공지 + 확인 체크박스(필수) ──
  Widget _noticeSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('수품 구매 안내 공지', icon: Icons.campaign_outlined, color: AppColors.taegeukRed),
            const SizedBox(height: 8),
            if (_notices.trim().isNotEmpty)
              Text(_notices,
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _guideBlock('멤버십 안내', '${_guide['membership'] ?? ''}'),
            _guideBlock('구매 자격', '${_guide['rules'] ?? ''}'),
            _guideBlock('멤버십 세트 구성', '${_guide['sets'] ?? ''}'),
            _guideBlock('유의사항 · 문의', '${_guide['notes'] ?? ''}'),
            const Divider(height: 18),
            // 입금자=주문자 안내 (강조)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.tigerGold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '※ 입금자명과 주문자(인가자) 이름이 같아야 합니다.\n'
                '※ 인가번호 또는 인가자 이름을 꼭 함께 넣어주세요.\n'
                '   → 기록이 남아 구매 이력이 관리됩니다.',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.45),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _noticeChecked,
              onChanged: (v) => setState(() => _noticeChecked = v == true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('위 수품 구매 안내 공지를 확인하였습니다. (필수)',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );

  // ── 연간회비 납부 여부 ──
  Widget _feeSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('연간회비 납부 여부', icon: Icons.card_membership_outlined),
            const SizedBox(height: 6),
            const Text('연간회비를 납부하셨습니까?',
                style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('예 (면제)')),
                ButtonSegment(value: false, label: Text('아니요 (추가 결제)')),
              ],
              selected: {_feePaidYes},
              onSelectionChanged: (s) => setState(() => _feePaidYes = s.first),
            ),
            if (!_feePaidYes) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.taegeukBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '연간회비 ${_won(_annualFee)}가 결제 항목에 추가됩니다.\n'
                  '수품과 함께 입금해 주시면 됩니다.',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, height: 1.4),
                ),
              ),
            ],
          ],
        ),
      );

  // ── 주문자 정보 ──
  Widget _buyerSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('주문자 정보', icon: Icons.person_outline),
            const SizedBox(height: 8),
            TextFormField(
              controller: _number,
              keyboardType: TextInputType.number,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? '인가번호(또는 전화번호)를 입력하세요'
                  : null,
              decoration: const InputDecoration(
                labelText: '인가번호 * (없으면 연락처만 입력)',
                helperText: '인가번호가 없어도 연락처로 구매 가능합니다.',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? '입금자명(주문자 이름)을 입력하세요'
                  : null,
              decoration: const InputDecoration(
                labelText: '입금자명 * (주문자 이름과 동일)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? '연락처를 입력하세요'
                  : null,
              decoration:
                  const InputDecoration(labelText: '연락처 *', isDense: true),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
                    ? null
                    : '이메일 형식이 올바르지 않습니다';
              },
              decoration: const InputDecoration(
                  labelText: '이메일 (선택)', isDense: true),
            ),
            if (_isReserve) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _memo,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: '요청사항 · 메모 (선택)', isDense: true),
              ),
            ],
          ],
        ),
      );

  // ── 배송 방법 ──
  Widget _shippingSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('배송 방법', icon: Icons.local_shipping_outlined),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final m in ['현장구매', '택배발송', '기타'])
                  ChoiceChip(
                    label: Text(m),
                    selected: _ship == m,
                    onSelected: (_) => setState(() => _ship = m),
                  ),
              ],
            ),
            if (_ship == '택배발송') ...[
              const SizedBox(height: 8),
              AddressField(
                controller: _address,
                label: '배송 주소',
                hint: '주소검색 버튼으로 검색하세요',
                required: true,
              ),
              if (_shipFee > 0) ...[
                const SizedBox(height: 6),
                Text('· 택배 배송료 ${_won(_shipFee)} (우체국 택배)',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textGray)),
              ],
            ],
          ],
        ),
      );

  // ── 합계 ──
  Widget _totalSection() => _card(
        child: Column(
          children: [
            _sumRow(_isReserve ? '예약 상품 합계' : '상품 합계', _goodsTotal),
            if (!_isReserve && _shipExtra > 0) _sumRow('택배 배송료', _shipExtra),
            if (!_isReserve && _feeExtra > 0) _sumRow('연간회비 추가', _feeExtra),
            const Divider(height: 16),
            Row(
              children: [
                Text(_isReserve ? '예약 총 수량' : '합계:',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                    _isReserve
                        ? '${widget.lines.fold<int>(0, (s, e) => s + ((e['qty'] as num?)?.toInt() ?? 1))}개'
                        : _won(_grandTotal),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: AppColors.taegeukBlue)),
              ],
            ),
          ],
        ),
      );

  Widget _sumRow(String label, int v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12.5)),
            const Spacer(),
            Text(_won(v), style: const TextStyle(fontSize: 12.5)),
          ],
        ),
      );

  Widget _waitingNotice() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.tigerGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.tigerGold.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text('현재 주문이 진행 중입니다',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: AppColors.purpleDark)),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              '시간이 다소 소요되더라도 기다려 주십시오.\n'
              '뒤로 가기나 창을 닫지 말아 주십시오.\n'
              '창을 닫을 경우 개인 페이지에 들어가서 주문 내역을 확인할 수 있습니다.\n'
              '만일 주문 내역이 없을 경우 다시 주문을 넣어 주십시오.',
              style: TextStyle(
                  fontSize: 12.5, height: 1.5, color: AppColors.textDark),
            ),
          ],
        ),
      );

  Widget _submitButton() => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.purple,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onPressed: (!_noticeChecked || _busy) ? null : _submit,
          icon: Icon(_isReserve ? Icons.bookmark_add_outlined : Icons.payment,
              size: 20),
          label: Text(
            _busy
                ? '처리 중...'
                : (_isReserve ? '예약 신청 완료' : '주문 완료'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
      );

  Widget _guideBlock(String title, String body) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: AppColors.purpleDark)),
          const SizedBox(height: 2),
          Text(body,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textDark, height: 1.45)),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) {
      _snack('입력 항목을 확인해 주세요.', color: AppColors.taegeukRed);
      return;
    }
    if (!_noticeChecked) {
      _snack('구매 안내 공지를 확인해 주세요.', color: AppColors.taegeukRed);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isReserve) {
        int ok = 0;
        for (final l in widget.lines) {
          final r = await _nas.merchReserve(
            productId: '${l['productId']}',
            buyerName: _name.text.trim(),
            buyerNumber: _number.text.trim(),
            qty: (l['qty'] as num?)?.toInt() ?? 1,
            option: '${l['option'] ?? ''}',
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            note: _memo.text.trim(),
          );
          if (r['ok'] == true) ok++;
        }
        if (!mounted) return;
        if (ok > 0) {
          await _resultDialog(reserve: true);
          if (mounted) Navigator.pop(context, true);
        } else {
          _snack('예약 접수에 실패했습니다.', color: AppColors.taegeukRed);
        }
      } else {
        int ok = 0;
        Map<String, dynamic> last = {};
        for (int i = 0; i < widget.lines.length; i++) {
          final l = widget.lines[i];
          final r = await _nas.merchOrder(
            productId: '${l['productId']}',
            buyerName: _name.text.trim(),
            buyerNumber: _number.text.trim(),
            qty: (l['qty'] as num?)?.toInt() ?? 1,
            option: '${l['option'] ?? ''}',
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            address: _address.text.trim(),
            shipMethod: _ship,
            shipNote: '',
            memo: '묶음주문',
            unitPrice: (l['price'] as num?)?.toInt(),
            // 연회비는 첫 라인에만 1회 가산
            addAnnualFee: (i == 0 && !_feePaidYes),
          );
          if (r['ok'] == true) {
            ok++;
            last = r;
          } else if (r['error'] == 'annual_fee_required') {
            if (!mounted) return;
            _snack('연회비 납부 후 구매할 수 있습니다.',
                color: AppColors.taegeukRed);
            setState(() => _busy = false);
            return;
          } else if (r['error'] == 'sales_closed') {
            if (!mounted) return;
            _snack('현재 판매가 중지되어 있습니다.', color: AppColors.taegeukRed);
            setState(() => _busy = false);
            return;
          } else {
            if (!mounted) return;
            _snack('주문 실패: ${r['error']}', color: AppColors.taegeukRed);
            setState(() => _busy = false);
            return;
          }
        }
        if (!mounted) return;
        if (ok > 0) {
          await _resultDialog(reserve: false, last: last);
          if (mounted) Navigator.pop(context, true);
        } else {
          _snack('주문에 실패했습니다.', color: AppColors.taegeukRed);
        }
      }
    } catch (e) {
      if (mounted) _snack('오류: $e', color: AppColors.taegeukRed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resultDialog(
      {required bool reserve, Map<String, dynamic> last = const {}}) async {
    final order = ((last['order'] as Map?) ?? {}).cast<String, dynamic>();
    final contactId = '${last['contactId'] ?? ''}';
    final contactType = '${last['contactType'] ?? ''}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reserve ? '예약이 접수되었습니다' : '주문이 접수되었습니다'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!reserve) ...[
                Text('주문번호: ${order['id'] ?? ''}'),
                Text('주문자: ${_name.text.trim()}'
                    '${_number.text.trim().isNotEmpty ? ' (${_number.text.trim()})' : ''}'),
                const SizedBox(height: 4),
                Text('합계: ${_won(_grandTotal)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.taegeukBlue)),
              ],
              if (contactType == 'regular' && contactId.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('· 비인가 회원으로 등록되었습니다 (회원번호 $contactId).\n'
                    '  이후 주문 진행 상황을 조회할 수 있습니다.',
                    style: const TextStyle(fontSize: 11.5, height: 1.4)),
              ] else if (contactId.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('· 주문 내역이 인가자 프로필에 기록되었습니다.',
                    style: TextStyle(fontSize: 11.5)),
              ],
              if (!reserve) ...[
                const Divider(height: 20),
                const Text('입금 계좌 (수품계좌)',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
                const SizedBox(height: 4),
                Text('${_account['bank'] ?? ''} ${_account['no'] ?? ''}'),
                Text('예금주: ${_account['holder'] ?? ''}'),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.tigerGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '입금자명: 인가자이름 + "수품구매" (예: 홍길동수품구매)\n'
                    '※ 입금자명과 주문자 이름이 같아야 합니다.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              const Text('진행 상황은 개인 프로필의 "수품구매" 항목에서 확인할 수 있습니다.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textGray)),
            ],
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
        ],
      ),
    );
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }
}
