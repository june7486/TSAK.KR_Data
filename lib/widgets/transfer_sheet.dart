import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputFormatter, TextEditingValue;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../services/web_nav.dart';

/// 계좌로 '바로 송금' — **웹 우선** 시트.
///
/// 앱 설치 없이 웹 브라우저에서 바로 송금할 수 있도록 설계:
///  - 금액 입력(프리셋 칩 포함)
///  - **계좌 선택**(계좌번호 앞에 종류 명기) — 대표/수품구매/행사비 등
///  - 송금 정보(은행·계좌·금액·예금주) **원탭 복사** → 은행 앱/인터넷뱅킹에 붙여넣기
///  - **QR 코드** 생성 → 휴대폰 카메라로 스캔하면 송금 정보 그대로 전달
///  - 금융사 아이콘 → 폰 브라우저에서 앱 딥링크 실행(미설치 시 복사 폴백)
///
/// accounts 를 넘기면 계좌를 골라 송금할 수 있다. (없으면 단일 계좌)
Future<void> showTransferSheet(
  BuildContext context, {
  required String label,
  required String bank,
  required String account,
  String holder = '',
  int? amount,
  String memo = '',
  List<Map<String, dynamic>>? accounts,
  int initialIndex = 0,
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
      accounts: accounts,
      initialIndex: initialIndex,
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
    this.accounts,
    this.initialIndex = 0,
  });

  final String label;
  final String bank;
  final String account;
  final String holder;
  final int? amount;
  final String memo;
  final List<Map<String, dynamic>>? accounts;
  final int initialIndex;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  late final TextEditingController _amt;
  int _amount = 0;
  late int _acctIdx;

  List<Map<String, dynamic>> get _accounts {
    final a = widget.accounts;
    if (a != null && a.isNotEmpty) return a;
    return [
      {
        'label': widget.label,
        'bank': widget.bank,
        'account': widget.account,
      },
    ];
  }

  Map<String, dynamic> get _acct => _accounts[_acctIdx.clamp(0, _accounts.length - 1)];

  /// 현재 선택 계좌의 종류 라벨 (혼선 방지용 — 계좌번호 앞에 명기).
  String get _label => '${_acct['label'] ?? widget.label}';
  String get _account => '${_acct['account'] ?? widget.account}';

  @override
  void initState() {
    super.initState();
    _acctIdx = (widget.initialIndex >= 0 && widget.initialIndex < _accounts.length)
        ? widget.initialIndex
        : 0;
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

  String get _accountDigits => _account.replaceAll(RegExp(r'[^0-9]'), '');

  /// 송금 은행은 우리은행으로 고정.
  String get _bankName => '우리은행';

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 1600)),
    );
  }

  Future<void> _copy(String text, String msg) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast(msg);
  }

  /// 송금 정보 전체를 붙여넣기 좋은 한 덩어리 텍스트로.
  String _copyAllText() {
    final b = StringBuffer();
    b.writeln('[$_bankName] $_label');
    b.writeln('계좌번호: $_account');
    if (widget.holder.isNotEmpty) b.writeln('예금주: ${widget.holder}');
    if (_amount > 0) b.writeln('금액: ${_won(_amount)}원');
    b.write('사용처: $_label');
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
          'account': _account,
          'label': _label,
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
      '종류=$_label',
      '은행=$_bankName',
      '계좌=$_account',
      if (_amount > 0) '금액=$_amount',
      if (widget.holder.isNotEmpty) '예금주=${widget.holder}',
      if (widget.memo.isNotEmpty) '메모=${widget.memo}',
    ].join('\n');
  }

  /// 앱 딥링크를 열고, 실패하면 스토어 설치 페이지로 폴백한다.
  Future<void> _tryOpen(List<String> urls, List<String> stores) async {
    // 웹(특히 모바일 브라우저): 커스텀 스킴은 location.href 로만 열린다.
    if (isWebRuntime) {
      try {
        openUrlInTab(urls.first);
        _toast('앱이 열리지 않으면 「송금 정보 복사」 후 은행 앱에 붙여넣으세요');
      } catch (_) {
        _toast('송금 정보를 복사해 은행 앱에 붙여넣으세요');
      }
      return;
    }
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

  /// 선택한 금융사로 바로 송금 (딥링크 → 앱 스토어 폴백).
  Future<void> _payWith(Map<String, String> b) async {
    final bank = b['code'] ?? _bankName;
    final scheme = b['scheme']!;
    final name = b['name']!;
    final urls = <String>[
      if (_amount > 0 && _accountDigits.isNotEmpty)
        '$scheme?bank=$bank&accountNo=$_accountDigits&amount=$_amount',
      '$scheme?bank=$bank&accountNo=$_accountDigits',
      scheme,
    ];
    await _tryOpen(urls, [_storeUrl(name)]);
  }

  /// 금융사 앱 스토어 링크(대표앱) — 미설치 시 설치 유도.
  static String _storeUrl(String name) {
    const ids = {
      '토스': 'viva.republica.toss',
      '카카오뱅크': 'com.kakaobank.channel',
      '케이뱅크': 'com.kbankwith.kbankwith',
      'KB국민은행': 'com.kbstar.kbbank',
      '신한은행': 'com.shinhan.sbanking',
      '우리은행': 'com.wooribank.smart',
      '하나은행': 'com.hanabank.ebk.channel.android.hanabank',
      'NH농협은행': 'nh.smart.nhall',
      'IBK기업은행': 'com.ibk.android.ionebank',
    };
    final id = ids[name];
    return id == null
        ? 'https://play.google.com/store/search?q=$name&c=apps'
        : 'https://play.google.com/store/apps/details?id=$id';
  }

  /// 딥링크 가능한 은행·핀테크 앱 전체 목록.
  /// scheme: 앱 실행용 URL 스킴. code: 은행 표준코드(딥링크 파라미터용).
  /// short: 아이콘용 약칭. color: 브랜드 색.
  static const List<Map<String, String>> _banks = [
    {'name': '토스', 'scheme': 'supertoss://', 'code': '092', 'short': '토스', 'color': '0064FF'},
    {'name': '카카오뱅크', 'scheme': 'kakaobank://', 'code': '090', 'short': '카뱅', 'color': 'FFCD00'},
    {'name': '케이뱅크', 'scheme': 'kbank://', 'code': '089', 'short': '케이', 'color': '00B4B0'},
    {'name': 'KB국민은행', 'scheme': 'kbbank://', 'code': '004', 'short': 'KB', 'color': 'FFB800'},
    {'name': '신한은행', 'scheme': 'shinhan-sbank://', 'code': '088', 'short': '신한', 'color': '0046FF'},
    {'name': '우리은행', 'scheme': 'wooribank://', 'code': '020', 'short': '우리', 'color': '0067AC'},
    {'name': '하나은행', 'scheme': 'hanabank://', 'code': '081', 'short': '하나', 'color': '009A93'},
    {'name': 'NH농협은행', 'scheme': 'nhbapp://', 'code': '011', 'short': 'NH', 'color': '1B7C3D'},
    {'name': 'IBK기업은행', 'scheme': 'ibkonebank://', 'code': '003', 'short': 'IBK', 'color': '005EB8'},
    {'name': 'SC제일은행', 'scheme': 'scbank://', 'code': '023', 'short': 'SC', 'color': '00694E'},
    {'name': '한국씨티은행', 'scheme': 'citibank://', 'code': '027', 'short': '씨티', 'color': '0F4FA8'},
    {'name': '부산은행', 'scheme': 'busanbank://', 'code': '032', 'short': '부산', 'color': '0059A5'},
    {'name': '경남은행', 'scheme': 'knbank://', 'code': '039', 'short': '경남', 'color': 'C8102E'},
    {'name': '대구은행', 'scheme': 'dgbbank://', 'code': '031', 'short': '대구', 'color': '0B4DA2'},
    {'name': '광주은행', 'scheme': 'kjbank://', 'code': '034', 'short': '광주', 'color': 'F0A500'},
    {'name': '전북은행', 'scheme': 'jbbank://', 'code': '037', 'short': '전북', 'color': '005BAC'},
    {'name': '제주은행', 'scheme': 'jejubank://', 'code': '035', 'short': '제주', 'color': 'E87722'},
    {'name': '수협은행', 'scheme': 'suhyupbank://', 'code': '007', 'short': '수협', 'color': '0067A3'},
    {'name': '우체국', 'scheme': 'epostbank://', 'code': '071', 'short': '우체국', 'color': 'E8442E'},
    {'name': '새마을금고', 'scheme': 'mgbank://', 'code': '045', 'short': '새마을', 'color': '00703C'},
    {'name': '신협', 'scheme': 'cuapp://', 'code': '048', 'short': '신협', 'color': '0083C6'},
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
                  _accountSelector(),
                  const SizedBox(height: 14),
                  _amountField(),
                  const SizedBox(height: 14),
                  // 바로 송금 가능한 금융사 아이콘 목록
                  _payIcons(),
                  const SizedBox(height: 10),
                  const Text(
                    '휴대폰에서는 선택한 앱이 바로 열려요. PC라면 아래 QR을 폰으로 스캔하세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppColors.textGray),
                  ),
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
            _label,
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

  /// 바로 송금 가능한 금융사 아이콘 목록.
  Widget _payIcons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 16, color: AppColors.purple),
              const SizedBox(width: 4),
              const Text(
                '바로 송금',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '앱이 열려요',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textGray.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 12,
            children: [for (final b in _banks) _payIcon(b)],
          ),
        ],
      ),
    );
  }

  Widget _payIcon(Map<String, String> b) {
    final color = _hex(b['color'] ?? '5B2C8D');
    final short = b['short'] ?? b['name']!;
    return InkWell(
      onTap: () => _payWith(b),
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.28),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                short,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: short.length > 3 ? 9.5 : 12,
                  fontWeight: FontWeight.w800,
                  color: _onColor(color),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              b['name']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9.5, color: AppColors.textDark),
            ),
          ],
        ),
      ),
    );
  }

  static Color _hex(String h) => Color(int.parse('FF$h', radix: 16));

  /// 밝은 배경색 위에서는 검정 글씨 (카카오뱅크 등).
  static Color _onColor(Color c) =>
      c.computeLuminance() > 0.6 ? Colors.black87 : Colors.white;

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.06),
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 16, color: AppColors.purple),
                const SizedBox(width: 8),
                const Text(
                  '우리은행',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const Spacer(),
                Text(
                  '고정',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textGray.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 계좌 선택 카드 — 누르면 다른 계좌를 고를 수 있다.
  /// 계좌번호 앞에 계좌 종류(라벨)를 반드시 명기해 혼선을 막는다.
  Widget _accountSelector() {
    final multi = _accounts.length > 1;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: multi ? _pickAccount : null,
      child: Container(
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
                  Row(
                    children: [
                      // 계좌 종류 명기 (혼선 방지)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.tigerGold.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          _label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _bankName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                        ),
                      ),
                      if (multi) ...[
                        const Spacer(),
                        const Icon(Icons.expand_more,
                            size: 20, color: AppColors.purple),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _account,
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
              onPressed: () => _copy(_account, '계좌번호가 복사됐어요'),
              icon: const Icon(Icons.copy, color: AppColors.purple),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAccount() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.account_balance, size: 18, color: AppColors.purple),
                  SizedBox(width: 6),
                  Text('송금할 계좌 선택',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            for (var i = 0; i < _accounts.length; i++)
              ListTile(
                leading: Icon(
                  i == _acctIdx
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: i == _acctIdx
                      ? AppColors.purple
                      : AppColors.textGray,
                ),
                title: Text(
                  '${_accounts[i]['label']}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${_accounts[i]['bank']} ${_accounts[i]['account']}',
                  style: const TextStyle(fontSize: 13),
                ),
                onTap: () => Navigator.pop(ctx, i),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && picked != _acctIdx) {
      setState(() => _acctIdx = picked);
    }
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
