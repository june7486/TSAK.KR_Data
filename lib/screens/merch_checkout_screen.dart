import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/nas_api.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/address_field.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

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

  /// 각인 메달(멘토/페런츠) 라인별 수령인 입력 컨트롤러.
  ///  key = 라인 인덱스. 각인 내용(수여받는 사람 정보)이 있어야 판매 가능.
  ///  value = 수량(qty)만큼의 수령인 1:1 목록(복수 구매 시 그 수만큼 입력).
  final Map<int, List<_RecipientCtl>> _recips = {};

  bool _noticeChecked = false;
  bool _feePaidYes = true; // 연간회비 납부 여부(예=면제, 아니요=추가)
  String _ship = '현장구매';
  bool _busy = false;

  /// 주문 진행 단계 문구 — 로딩 중 현재 진행 상황을 사용자에게 보여준다.
  String _step = '';
  double _stepProgress = 0;

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

  /// 각인 메달 수령인 대상 라인 인덱스 → recipientKind('mentor'|'parent').
  Map<int, String> get _medalLines {
    final out = <int, String>{};
    for (int i = 0; i < widget.lines.length; i++) {
      final k = '${widget.lines[i]['recipientKind'] ?? ''}'.trim();
      if (k == 'mentor' || k == 'parent') out[i] = k;
    }
    return out;
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _memo.dispose();
    for (final list in _recips.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    // 화면 종료 시 화면 꺼짐 방지를 확실히 해제.
    try {
      WakelockPlus.disable();
    } catch (_) {}
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
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _busy) {
          _snack('주문을 저장하는 중입니다. 잠시만 기다려 주세요.',
              color: AppColors.tigerGold);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: TsakAppBar(
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
              // 각인 메달(멘토/페런츠) — 수여받는 사람 정보 필수 입력.
              if (_medalLines.isNotEmpty) ...[
                _recipientSection(),
                const SizedBox(height: 12),
              ],
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

  /// 각인 메달(멘토/페런츠) — 수여받는 사람(수령인) 정보 입력 섹션.
  ///  멘토: 소속 · 이름 · 연락처 / 페런츠: 이름 · 연락처.
  ///  이 정보(각인 내용)가 있어야 판매 가능하다.
  Widget _recipientSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('각인 메달 — 수여받는 분 정보 (필수)',
                icon: Icons.card_giftcard, color: AppColors.taegeukRed),
            const SizedBox(height: 6),
            const Text(
              '멘토·페런츠 메달은 각인 작업을 위해 수여받는 분의 정보가 반드시 필요합니다.\n'
              '· 멘토 메달: 멘토 대장님의 소속 · 이름 · 연락처 · 범인가번호\n'
              '· 페런츠 메달: 페런츠의 이름 · 연락처 · 범인가번호\n'
              '· 여러 개를 구매하면 그 수량만큼 각각 입력해 주세요.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
            for (final e in _medalLines.entries) ...[
              const SizedBox(height: 10),
              _recipientFields(e.key, e.value),
            ],
          ],
        ),
      );

  /// 라인 [idx] 의 수령인 컨트롤러 목록 — 수량(qty)만큼 1:1로 생성/보장한다.
  List<_RecipientCtl> _lineRecips(int idx) {
    final qty = (widget.lines[idx]['qty'] as num?)?.toInt() ?? 1;
    final n = qty < 1 ? 1 : qty;
    final list = _recips.putIfAbsent(
        idx, () => List<_RecipientCtl>.generate(n, (_) => _RecipientCtl()));
    while (list.length < n) {
      list.add(_RecipientCtl());
    }
    return list;
  }

  Widget _recipientFields(int idx, String kind) {
    final list = _lineRecips(idx);
    final pname = (widget.lines[idx]['name'] ?? '')
        .toString()
        .split('(')
        .first
        .trim();
    final isMentor = kind == 'mentor';
    final qty = list.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int u = 0; u < list.length; u++) ...[
          if (u > 0) const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.tigerGold.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.tigerGold.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '$pname · ${isMentor ? '멘토' : '페런츠'} 수령인'
                    '${qty > 1 ? ' ${u + 1}/${qty}' : ''}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                if (isMentor)
                  TextFormField(
                    key: ValueKey('rcp-unit-$idx-$u'),
                    controller: list[u].unit,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? '멘토 소속을 입력하세요'
                        : null,
                    decoration: const InputDecoration(
                        labelText: '멘토 소속 *', isDense: true),
                  ),
                if (isMentor) const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('rcp-name-$idx-$u'),
                  controller: list[u].name,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '수령인 이름을 입력하세요'
                      : null,
                  decoration: InputDecoration(
                      labelText: '${isMentor ? '멘토' : '페런츠'} 이름 *',
                      isDense: true),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('rcp-phone-$idx-$u'),
                  controller: list[u].phone,
                  keyboardType: TextInputType.phone,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '수령인 연락처를 입력하세요'
                      : null,
                  decoration: InputDecoration(
                      labelText: '${isMentor ? '멘토' : '페런츠'} 연락처 *',
                      isDense: true),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('rcp-number-$idx-$u'),
                  controller: list[u].number,
                  keyboardType: TextInputType.number,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '범인가번호를 입력하세요'
                      : null,
                  decoration: InputDecoration(
                    labelText: '범인가번호 (필수)',
                    hintText: '입력 시 해당 회원 개인프로필(멘토·페런츠)에 추가됩니다',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _waitingNotice() {
    final pct = (_stepProgress * 100).round();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tigerGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tigerGold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _step.isEmpty ? '주문을 처리하고 있습니다' : _step,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: AppColors.purpleDark),
                ),
              ),
              if (_stepProgress > 0)
                Text('$pct%',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: AppColors.purple)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _stepProgress > 0 ? _stepProgress : null,
              minHeight: 7,
              backgroundColor: AppColors.purpleLight.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(AppColors.purple),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '⏳ 주문 데이터를 생성하고 있습니다. 창을 닫지 말고 잠시만 기다려 주세요.\n'
            '· 처리 중에는 화면이 자동으로 꺼지지 않습니다.\n'
            '· 진행률이 멈춘 듯 보여도 정상 처리 중일 수 있으니 그대로 기다려 주세요.\n'
            '· 부득이 창을 닫았다면 개인 프로필의 "수품구매"에서 주문 내역을 확인하세요.\n'
            '· 주문 내역이 없을 경우에만 다시 주문해 주세요.',
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }

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
    setState(() {
      _busy = true;
      _step = _isReserve ? '예약을 접수하는 중…' : '주문을 접수하는 중…';
      _stepProgress = 0.15;
    });
    // 처리 중에는 화면이 꺼지지 않도록 유지(사용자가 이탈/오류로 오해하지 않게).
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    // 실제 처리 시간이 길어도 진행률이 멈춘 듯 보이지 않도록 90%까지 서서히 올린다.
    final ticker = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!mounted) return;
      setState(() {
        if (_stepProgress < 0.9) {
          _stepProgress = (_stepProgress + 0.04).clamp(0.0, 0.9);
        }
      });
    });
    try {
      if (_isReserve) {
        int ok = 0;
        for (final l in widget.lines) {
          _setStep('예약 항목을 저장하는 중…', 0.4);
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
        _setStep('접수 결과를 확인하는 중…', 0.95);
        if (!mounted) return;
        if (ok > 0) {
          await _resultDialog(reserve: true);
          if (mounted) Navigator.pop(context, true);
        } else {
          _snack('예약 접수에 실패했습니다.', color: AppColors.taegeukRed);
        }
      } else {
        // 장바구니의 모든 라인을 **하나의 주문번호**로 통합 주문.
        final lines = <Map<String, dynamic>>[];
        final medalLines = _medalLines;
        for (int i = 0; i < widget.lines.length; i++) {
          final l = widget.lines[i];
          final mk = medalLines[i];
          lines.add({
            'productId': '${l['productId']}',
            'qty': (l['qty'] as num?)?.toInt() ?? 1,
            'option': '${l['option'] ?? ''}',
            if ((l['size'] ?? '') != '') 'size': '${l['size']}',
            if (l['price'] != null) 'unitPrice': (l['price'] as num).toInt(),
            // 각인 메달: 수여받는 사람(수령인) 정보 필수 전송.
            if (mk != null)
              'recipients': [
                for (final c in _lineRecips(i))
                  {
                    'unit': c.unit.text.trim(),
                    'name': c.name.text.trim(),
                    'number': c.number.text.trim(),
                    'phone': c.phone.text.trim(),
                  }
              ],
          });
        }
        _setStep('서버에 주문을 저장하는 중… (가장 오래 걸리는 단계)', 0.45);
        final r = await _nas.merchOrderBatch(
          lines: lines,
          buyerName: _name.text.trim(),
          buyerNumber: _number.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          address: _address.text.trim(),
          shipMethod: _ship,
          memo: '묶음주문',
          addAnnualFee: !_feePaidYes,
        );
        if (!mounted) return;
        if (r['ok'] == true) {
          _setStep('주문 내역을 개인 프로필에 연동하는 중…', 0.9);
          await _resultDialog(reserve: false, last: r);
          if (mounted) Navigator.pop(context, true);
        } else if (r['error'] == 'medal_recipient_required') {
          _snack('각인 메달은 수량만큼 수여받는 분의 정보(범인가번호·이름·연락처, 멘토는 소속 포함)를 '
              '모두 입력해야 판매할 수 있습니다.', color: AppColors.taegeukRed);
          await WakelockPlus.disable();
          setState(() => _busy = false);
          return;
        } else if (r['error'] == 'annual_fee_required') {
          _snack('연회비 납부 후 구매할 수 있습니다.', color: AppColors.taegeukRed);
          await WakelockPlus.disable();
          setState(() => _busy = false);
          return;
        } else if (r['error'] == 'sales_closed') {
          _snack('현재 판매가 중지되어 있습니다.', color: AppColors.taegeukRed);
          await WakelockPlus.disable();
          setState(() => _busy = false);
          return;
        } else {
          _snack('주문 실패: ${r['error']}', color: AppColors.taegeukRed);
          await WakelockPlus.disable();
          setState(() => _busy = false);
          return;
        }
      }
    } catch (e) {
      if (mounted) _snack('오류: $e', color: AppColors.taegeukRed);
    } finally {
      ticker.cancel();
      // 처리 종료 시 화면 꺼짐 방지 해제.
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _busy = false;
          _step = '';
          _stepProgress = 0;
        });
      }
    }
  }

  void _setStep(String text, double progress) {
    if (!mounted) return;
    setState(() {
      _step = text;
      if (progress > _stepProgress) _stepProgress = progress;
    });
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
                Text('· 비인가 회원(신규 ID)으로 등록되었습니다 (회원번호 $contactId).\n'
                    '  이후 주문 진행 상황을 조회할 수 있습니다.',
                    style: const TextStyle(fontSize: 11.5, height: 1.4)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppColors.tigerGold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '전화번호로 아이디가 생성되었습니다.\n'
                    '· ID: ${_phone.text.trim()}\n'
                    '· PW: 전화번호 뒷 4자리\n'
                    '아이디·비밀번호로 로그인하면 주문·배송 상태를 확인할 수 있습니다.\n'
                    '로그인 후 본인 비밀번호로 변경할 수 있습니다.',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        height: 1.45,
                        color: AppColors.purpleDark),
                  ),
                ),
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
          // 주문확인하기 — 입력한 전화번호로 자동 로그인 후 개인 화면으로 이동.
          if (contactType == 'regular' && _phone.text.trim().length >= 4)
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _autoLoginAndGoHome();
              },
              icon: const Icon(Icons.login, size: 18),
              label: const Text('주문확인하기 (자동 로그인)'),
            ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
        ],
      ),
    );
  }

  /// 신규(비인가) 주문자 — 전화번호+뒤4자리로 자동 로그인 후 첫 화면으로 이동.
  Future<void> _autoLoginAndGoHome() async {
    final state = context.read<AppState>();
    final phone = _phone.text.trim();
    final last4 = phone.replaceAll(RegExp(r'[^0-9]'), '');
    String pw = '';
    if (last4.length >= 4) pw = last4.substring(last4.length - 4);
    try {
      final ok = await state.login('guest', pw, id: phone);
      if (!mounted) return;
      if (ok) {
        // 모든 화면을 닫고 첫 화면(개인 프로필)으로 이동.
        Navigator.of(context).popUntil((r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('전화번호로 로그인했습니다. 개인 화면에서 진행상황을 확인하세요.'),
            backgroundColor: AppColors.scoutGreen,
          ),
        );
      } else {
        _snack('자동 로그인에 실패했습니다. 전화번호와 뒤 4자리를 확인해 주세요.',
            color: AppColors.taegeukRed);
      }
    } catch (e) {
      if (mounted) _snack('로그인 오류: $e', color: AppColors.taegeukRed);
    }
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }
}


/// 각인 메달 수령인 입력 컨트롤러 모음.
class _RecipientCtl {
  final unit = TextEditingController();
  final name = TextEditingController();
  final number = TextEditingController(); // 수령인 인가번호(개인프로필 연동)
  final phone = TextEditingController();

  void dispose() {
    unit.dispose();
    name.dispose();
    number.dispose();
    phone.dispose();
  }
}
