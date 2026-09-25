import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputFormatter, TextEditingValue;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// 계좌로 '바로 송금' — **웹 우선** 시트.
///
/// 앱 설치 없이 웹 브라우저에서 바로 송금할 수 있도록 설계:
///  - 금액 입력(프리셋 칩 포함)
///  - 송금 정보(은행·계좌·금액·예금주) **원탭 복사** → 은행 앱/인터넷뱅킹에 붙여넣기
///  - **QR 코드** 생성 → 휴대폰 카메라로 스캔하면 송금 정보 그대로 전달
///  - (참고) 실제 폰에서 딥링크 앱 실행도 지원(앱 설치형 사용자용)
///
/// 금액·계좌를 미리 지정해주면 더 편하다. (amount 미지정 시 사용자가 입력)
Future<void> showTransferSheet(
  BuildContext context, {
  required String label,
  required String bank,
  required String account,
  String holder = '',
  int? amount,
  String memo = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TransferSheet(
      label: label,
      bank: bank,
      account: account,
      holder: holder,
      amount: amount,
      memo: memo,
    ),
  );
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({
    required this.label,
    required this.bank,
    required this.account,
    required this.holder,
    required this.amount,
    required this.memo,
  });

  final String label;
  final String bank;
  final String account;
  final String holder;
  final int? amount;
  final String memo;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  late final TextEditingController _amt;
  int _amount = 0;
  String? _bankOverride;

  @override
  void initState() {
    super.initState();
    final initial =
        (widget.amount != null && widget.amount! > 0) ? widget.amount! : 0;
    _amount = initial;
    _amt = TextEditingController(text: initial > 0 ? _won(initial) : '');
  }

  @override
  void dispose() {
    _amt.dispose();
    super.dispose();
  }

  static String _won(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      );

  String get _accountDigits => widget.account.replaceAll(RegExp(r'[^0-9]'), '');

  String get _bankName => _bankOverride ?? _matchBank(widget.bank);

  /// 시트에 전달된 은행명을 딥링크 목록의 표준 이름으로 정규화.
  static String _matchBank(String raw) {
    final t = raw.replaceAll(RegExp(r'\s+'), '');
    if (t.isEmpty) return '토스';
    for (final b in _banks) {
      final n = b['name']!;
      if (t.contains(n) || n.contains(t)) return n;
    }
    return '토스';
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 1400)),
    );
  }

  Future<void> _copy(String text, String msg) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast(msg);
  }

  /// 송금 정보 전체를 붙여넣기 좋은 한 덩어리 텍스트로.
  String _copyAllText() {
    final b = StringBuffer();
    b.writeln('[$_bankName] ${widget.account}');
    if (widget.holder.isNotEmpty) b.writeln('예금주: ${widget.holder}');
    if (_amount > 0) b.writeln('금액: ${_won(_amount)}원');
    b.write('사용처: ${widget.label}');
    return b.toString();
  }

  /// QR 코드에 담을 값.
  ///
  /// 웹에서는 현재 브라우저 주소의 origin으로 `/pay` 착지 페이지를 만들어
  /// 담는다 → 폰으로 스캔하면 https 페이지가 열리고 토스/은행 앱이 자동 실행.
  /// (웹이 아니거나 origin을 알 수 없으면 송금 텍스트를 담는다.)
  String _qrData() {
    if (kIsWeb) {
      final base = Uri.base;
      if (base.host.isNotEmpty) {
        final qp = <String, String>{
          'bank': _bankName,
          'account': widget.account,
          if (_amount > 0) 'amount': '$_amount',
          if (widget.holder.isNotEmpty) 'holder': widget.holder,
          if (widget.memo.isNotEmpty) 'memo': widget.memo,
        };
        return base
            .replace(path: '/pay', queryParameters: qp, fragment: '')
            .toString();
      }
    }
    return [
      'TSAK 송금정보',
      '은행=$_bankName',
      '계좌=${widget.account}',
      if (_amount > 0) '금액=$_amount',
      if (widget.holder.isNotEmpty) '예금주=${widget.holder}',
      if (widget.memo.isNotEmpty) '메모=${widget.memo}',
    ].join('\n');
  }

  /// 앱 딥링크를 열고, 실패하면 스토어 설치 페이지로 폴백한다.
  Future<void> _tryOpen(List<String> urls, List<String> stores) async {
    for (final u in urls) {
      try {
        final ok = await launchUrl(
          Uri.parse(u),
          mode: LaunchMode.externalNonBrowserApplication,
        );
        if (ok) return;
      } catch (_) {}
    }
    for (final s in stores) {
      try {
        if (await launchUrl(
          Uri.parse(s),
          mode: LaunchMode.externalApplication,
        )) {
          return;
        }
      } catch (_) {}
    }
    _toast('앱을 열 수 없어요. 송금 정보를 복사해 주세요');
  }

  Future<void> _payToss() async {
    final bank = _bankName;
    final urls = [
      if (_amount > 0 && _accountDigits.isNotEmpty)
        'supertoss://send?bank=$bank&accountNo=$_accountDigits&amount=$_amount',
      'supertoss://send?bank=$bank&accountNo=$_accountDigits',
      'supertoss://',
    ];
    await _tryOpen(urls, [
      'https://apps.apple.com/kr/app/id839333328',
      'https://play.google.com/store/apps/details?id=viva.republica.toss',
    ]);
  }

  Future<void> _openBankApp(String scheme) async {
    await _tryOpen([scheme], const []);
  }

  /// 딥링크 가능한 은행·핀테크 앱 전체 목록.
  /// scheme: 앱 실행용 URL 스킴(참고용 — 웹에서는 실행되지 않음).
  static const List<Map<String, String>> _banks = [
    {'name': '토스', 'scheme': 'supertoss://'},
    {'name': '카카오뱅크', 'scheme': 'kakaobank://'},
    {'name': '케이뱅크', 'scheme': 'kbank://'},
    {'name': '국민은행', 'scheme': 'kbbank://'},
    {'name': '신한은행', 'scheme': 'shinhan-sbank://'},
    {'name': '우리은행', 'scheme': 'wooribank://'},
    {'name': '하나은행', 'scheme': 'hanabank://'},
    {'name': '농협은행', 'scheme': 'nhbapp://'},
    {'name': '기업은행', 'scheme': 'ibkonebank://'},
    {'name': 'SC제일은행', 'scheme': 'scbank://'},
    {'name': '한국씨티은행', 'scheme': 'citibank://'},
    {'name': '부산은행', 'scheme': 'busanbank://'},
    {'name': '경남은행', 'scheme': 'knbank://'},
    {'name': '대구은행', 'scheme': 'dgbbank://'},
    {'name': '광주은행', 'scheme': 'kjbank://'},
    {'name': '전북은행', 'scheme': 'jbbank://'},
    {'name': '제주은행', 'scheme': 'jejubank://'},
    {'name': '수협은행', 'scheme': 'suhyupbank://'},
    {'name': '우체국', 'scheme': 'epostbank://'},
    {'name': '새마을금고', 'scheme': 'mgbank://'},
    {'name': '신협', 'scheme': 'cuapp://'},
  ];

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  _header(),
                  const SizedBox(height: 12),
                  _bankPicker(),
                  const SizedBox(height: 10),
                  _accountCard(),
                  const SizedBox(height: 14),
                  _amountField(),
                  const SizedBox(height: 16),
                  _qrCard(),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () =>
                        _copy(_copyAllText(), '송금 정보가 복사됐어요'),
                    icon: const Icon(Icons.copy_all_rounded, size: 18),
                    label: const Text(
                      '송금 정보 복사 (은행·계좌·금액)',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _howTo(),
                  const SizedBox(height: 8),
                  _appSection(),
                  const SizedBox(height: 12),
                  Text(
                    '※ 입금자명을 꼭 남겨주세요. 앱이 자동으로 납부 내역과 매칭합니다.'
                    '${widget.memo.isNotEmpty ? '\n메모: ${widget.memo}' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.tigerGold.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        const Spacer(),
        if (widget.holder.isNotEmpty)
          Text(
            '예금주 ${widget.holder}',
            style: const TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
      ],
    );
  }

  Widget _bankPicker() {
    return Row(
      children: [
        const Text(
          '송금할 은행',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _bankName,
                isExpanded: true,
                isDense: true,
                icon: const Icon(Icons.expand_more, color: AppColors.purple),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
                items: [
                  for (final b in _banks)
                    DropdownMenuItem<String>(
                      value: b['name']!,
                      child: Text(b['name']!),
                    ),
                ],
                onChanged: (v) => setState(() => _bankOverride = v),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _accountCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bankName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textGray,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.account,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '계좌번호 복사',
            onPressed: () => _copy(widget.account, '계좌번호가 복사됐어요'),
            icon: const Icon(Icons.copy, color: AppColors.purple),
          ),
        ],
      ),
    );
  }

  Widget _amountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '보낼 금액',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _amt,
          keyboardType: TextInputType.number,
          inputFormatters: [_ThousandsFormatter()],
          onChanged: (v) => setState(
            () => _amount = int.tryParse(v.replaceAll(',', '').trim()) ?? 0,
          ),
          decoration: InputDecoration(
            hintText: '금액 입력 (선택)',
            suffixText: '원',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in const [10000, 30000, 50000, 100000])
              ActionChip(
                label: Text('${_won(v)}원'),
                onPressed: () => setState(() {
                  _amount = v;
                  _amt.text = _won(v);
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _qrCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.purple.withValues(alpha: 0.08),
            AppColors.tigerGold.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_rounded,
                  size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              const Text(
                'QR로 휴대폰에 전달',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '폰 카메라로 스캔',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textGray.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: QrImageView(
              data: _qrData(),
              version: QrVersions.auto,
              size: 176,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.textDark,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '폰으로 스캔하면 송금 정보가 열려요',
            style: TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _howTo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '송금 방법 (앱 설치 없이)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 6),
          Text(
            '1. 「송금 정보 복사」를 누르거나 QR을 폰으로 스캔\n'
            '2. 쓰던 은행 앱·인터넷뱅킹을 열고 「송금」 메뉴로 이동\n'
            '3. 계좌번호·금액을 붙여넣고 입금자명을 입력해 전송',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textDark,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 앱을 설치한 사람을 위한 선택 기능. 웹에서는 열리지 않을 수 있음을 안내.
  /// 좁은 화면(휴대폰 브라우저)에서는 딥링크가 실제로 열리므로 자동 펼침.
  Widget _appSection() {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        initiallyExpanded: narrow,
        leading: const Icon(Icons.install_mobile_rounded,
            size: 18, color: AppColors.textGray),
        title: const Text(
          '앱 설치형 — 토스·은행 앱으로 바로 열기 (선택)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0064FF),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _payToss,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text(
                    '토스로 송금',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in _banks)
                  OutlinedButton(
                    onPressed: () => _openBankApp(b['scheme']!),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      b['name']!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '※ 웹 브라우저에서는 앱 실행이 막힐 수 있어요. 휴대폰(앱 설치)에서 유용합니다.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
            ),
          ),
        ],
      ),
    );
  }
}

/// 숫자 입력을 천 단위 콤마로 포맷.
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final n = int.parse(digits);
    final s = n.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'),
          (m) => '${m[1]},',
        );
    return TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}
