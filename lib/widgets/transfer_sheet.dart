import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputFormatter, TextEditingValue;
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// 계좌로 '바로 송금' 시트.
///
/// - 금액 입력(프리셋 칩 포함)
/// - 토스(supertoss://) · 카카오페이 · 주요 은행 앱 등록된 딥링크로 바로 이동
/// - 앱이 없거나 실패하면 스토어 설치 페이지로 폴백
/// - 계좌번호 복사 안전망 (모든 경우에 사용 가능)
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

  @override
  void initState() {
    super.initState();
    _amt = TextEditingController(
      text: (widget.amount != null && widget.amount! > 0)
          ? _won(widget.amount!)
          : '',
    );
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

  int get _amountInt => int.tryParse(_amt.text.replaceAll(',', '').trim()) ?? 0;

  String get _accountDigits =>
      widget.account.replaceAll(RegExp(r'[^0-9]'), '');

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 1400)),
    );
  }

  Future<void> _copyAccount() async {
    await Clipboard.setData(ClipboardData(text: widget.account));
    _toast('${widget.label} ${widget.account} 복사됨');
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
    _toast('앱을 열 수 없어요. 계좌를 복사해 주세요');
  }

  Future<void> _payToss() async {
    final bank = widget.bank;
    final urls = [
      if (_amountInt > 0 && _accountDigits.isNotEmpty)
        'supertoss://send?bank=$bank&accountNo=$_accountDigits&amount=$_amountInt',
      'supertoss://send?bank=$bank&accountNo=$_accountDigits',
      'supertoss://',
    ];
    await _tryOpen(urls, [
      'https://apps.apple.com/kr/app/id839333328',
      'https://play.google.com/store/apps/details?id=viva.republica.toss',
    ]);
  }

  Future<void> _payKakao() async {
    // 카카오페이는 상대 지정 송금 딥링크가 공개돼 있지 않아 앱 실행까지 지원.
    // 정확한 송금은 계좌 복사 후 카카오페이 송금 화면에서 진행.
    await _tryOpen([
      'kakaopay://kakaopay/home',
      'kakaopay://',
    ], [
      'https://apps.apple.com/kr/app/id911927630',
      'https://play.google.com/store/apps/details?id=com.kakaopay.app',
    ]);
  }

  Future<void> _openBankApp(String scheme) async {
    await _tryOpen([scheme], const []);
  }

  static const List<Map<String, String>> _banks = [
    {'name': '토스뱅크', 'scheme': 'supertoss://'},
    {'name': '카카오뱅크', 'scheme': 'kakaobank://'},
    {'name': '국민은행', 'scheme': 'kbbank://'},
    {'name': '신한은행', 'scheme': 'shinhan-sbank://'},
    {'name': '우리은행', 'scheme': 'wooribank://'},
    {'name': '하나은행', 'scheme': 'hanabank://'},
    {'name': '농협은행', 'scheme': 'nhbapp://'},
    {'name': '기업은행', 'scheme': 'ibkonebank://'},
  ];

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.tigerGold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (widget.holder.isNotEmpty)
                      Text(
                        '예금주 ${widget.holder}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // 계좌 표시
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.purple.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.bank,
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
                        tooltip: '복사',
                        onPressed: _copyAccount,
                        icon: const Icon(Icons.copy, color: AppColors.purple),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '보낼 금액',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _amt,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ThousandsFormatter()],
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
                        onPressed: () => setState(() => _amt.text = _won(v)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // 바로 송금 버튼
                Row(
                  children: [
                    Expanded(
                      child: _payBtn(
                        label: '토스로 송금',
                        color: const Color(0xFF0064FF),
                        icon: Icons.send_rounded,
                        onTap: _payToss,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _payBtn(
                        label: '카카오페이',
                        color: const Color(0xFFFEE500),
                        textColor: Colors.black87,
                        icon: Icons.chat_bubble_rounded,
                        onTap: _payKakao,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  '은행 앱 바로 열기',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
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
    );
  }

  Widget _payBtn({
    required String label,
    required Color color,
    required IconData icon,
    required Future<void> Function() onTap,
    Color textColor = Colors.white,
  }) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      onPressed: () => onTap(),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
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
