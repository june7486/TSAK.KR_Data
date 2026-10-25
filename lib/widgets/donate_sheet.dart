import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputFormatter, TextEditingValue;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';

/// 개발자 후원 시트 (t11).
///
/// - 개발자(이승준 · 범스카우트415) 정보 표시
/// - 후원계좌: 토스뱅크 1000-1857-2175 이**
/// - 「바로 입금」 → 토스 딥링크(supertoss://send)로 즉시 입금창 오픈
/// - 금액 프리셋 / QR(폰 카메라 스캔) / 계좌 복사
Future<void> showDonateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DonateSheet(),
  );
}

/// 개발자 후원 계좌 (고정).
const String _kDonateBank = '토스뱅크';
const String _kDonateAccount = '1000-1857-2175';
const String _kDonateHolder = '이**';
const String _kDonateDigits = '100018572175';

class _DonateSheet extends StatefulWidget {
  const _DonateSheet();

  @override
  State<_DonateSheet> createState() => _DonateSheetState();
}

class _DonateSheetState extends State<_DonateSheet> {
  final TextEditingController _amt = TextEditingController();
  int _amount = 0;

  @override
  void dispose() {
    _amt.dispose();
    super.dispose();
  }

  static String _won(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 1800)),
    );
  }

  Future<void> _copy(String text, String msg) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast(msg);
  }

  String get _qrData {
    if (kIsWeb) {
      final base = Uri.base;
      if (base.host.isNotEmpty) {
        return base
            .replace(
              path: '/pay',
              queryParameters: {
                'bank': _kDonateBank,
                'account': _kDonateAccount,
                'label': '개발자 후원',
                if (_amount > 0) 'amount': '$_amount',
                'holder': _kDonateHolder,
              },
              fragment: '',
            )
            .toString();
      }
    }
    return [
      'TSAK 개발자 후원',
      '은행=$_kDonateBank',
      '계좌=$_kDonateAccount',
      if (_amount > 0) '금액=$_amount',
    ].join('\n');
  }

  /// 토스로 바로 입금 — 설치되어 있으면 입금창, 아니면 웹/스토어 폴백.
  Future<void> _tossNow() async {
    final url = _amount > 0
        ? 'supertoss://send?bank=$_kDonateBank&accountNo=$_kDonateDigits&amount=$_amount'
        : 'supertoss://send?bank=$_kDonateBank&accountNo=$_kDonateDigits';
    if (isWebRuntime) {
      try {
        // 모바일 브라우저는 현재 탭에서, PC 브라우저는 현재 탭을 보존하는
        // 격리 탭(iframe/새창)에서 토스 앱 실행을 시도한다.
        if (isMobileWeb) {
          openUrlInTab(url);
        } else {
          openUrlInIsolatedTab(url);
        }
        _toast('토스 앱이 열립니다. 열리지 않으면 아래 계좌로 입금해 주세요.');
      } catch (_) {
        _toast('계좌를 복사해 토스·은행 앱에 붙여넣으세요');
      }
      return;
    }
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalNonBrowserApplication,
      )) {
        return;
      }
    } catch (_) {}
    try {
      if (await launchUrl(
        Uri.parse('https://toss.me/$_kDonateDigits'),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    _toast('계좌를 복사해 토스 앱에 붙여넣으세요');
  }

  @override
  Widget build(BuildContext context) {
    final dev = context.read<AppState>().developer;
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
                      height: 6,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // 헤더
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '개발자 후원',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '이 앱을 만든 개발자를 응원해 주세요',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textGray,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _developerCard(dev),
                  const SizedBox(height: 14),
                  _accountCard(),
                  const SizedBox(height: 14),
                  _amountField(),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0064FF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _tossNow,
                    icon: const Icon(Icons.bolt_rounded, size: 20),
                    label: const Text(
                      '토스로 바로 입금',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _copy(
                            '$_kDonateBank $_kDonateAccount',
                            '계좌가 복사됐어요',
                          ),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('계좌 복사'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _qrCard(),
                  const SizedBox(height: 12),
                  const Text(
                    '후원금은 앱 유지·개발에 소중히 사용됩니다. 감사합니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
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

  Widget _developerCard(Map<String, dynamic> dev) {
    final name = '${dev['name'] ?? '이승준'}';
    final unit = '${dev['unit'] ?? '범스카우트415'}';
    final email = '${dev['email'] ?? 'june7558@gmail.com'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.tigerGold,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.pets, size: 24, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '개발 · 운영',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '$unit · 한국범스카우트중앙회',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0064FF).withValues(alpha: 0.08),
            AppColors.tigerGold.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF0064FF).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                size: 16,
                color: Color(0xFF0064FF),
              ),
              const SizedBox(width: 6),
              const Text(
                '후원 계좌',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0064FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '토스뱅크',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_kDonateBank $_kDonateAccount',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          Text(
            '예금주 $_kDonateHolder',
            style: const TextStyle(fontSize: 12, color: AppColors.textGray),
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
          '후원 금액 (선택)',
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in const [3000, 5000, 10000, 30000, 50000])
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.qr_code_2_rounded, size: 18, color: AppColors.purple),
              SizedBox(width: 6),
              Text(
                'QR로 휴대폰에 전달',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: _qrData,
              version: QrVersions.auto,
              size: 168,
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
          const SizedBox(height: 6),
          const Text(
            '폰 카메라로 스캔하면 후원 정보가 열려요',
            style: TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }
}

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
