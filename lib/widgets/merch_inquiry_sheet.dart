import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/web_nav.dart';
import '../theme/app_theme.dart';

/// 수품 구매내역 하단의 **문의하기** 시트.
///
/// 요구사항 반영:
/// - 수신자(받는사람) = une7558@gmail.com **고정**
/// - 주문번호·이름·연락처·이메일·문의내용을 메일 본문에 자동 입력 → 내 메일 작성창 열기
/// - 첨부파일은 각자 개인 메일에서 직접 첨부
/// - 문의 내용에 **수신 가능한 핸드폰 번호 필수**
/// - 안내 문구 2줄 필수 삽입
Future<void> showMerchInquiry({
  required BuildContext context,
  String orderNo = '',
  String name = '',
  String phone = '',
  String email = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MerchInquirySheet(
      orderNo: orderNo,
      name: name,
      phone: phone,
      email: email,
    ),
  );
}

/// 고정 수신자 이메일.
const String kMerchInquiryTo = 'une7558@gmail.com';

class _MerchInquirySheet extends StatefulWidget {
  const _MerchInquirySheet({
    this.orderNo = '',
    this.name = '',
    this.phone = '',
    this.email = '',
  });

  final String orderNo;
  final String name;
  final String phone;
  final String email;

  @override
  State<_MerchInquirySheet> createState() => _MerchInquirySheetState();
}

class _MerchInquirySheetState extends State<_MerchInquirySheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  late final TextEditingController _phone =
      TextEditingController(text: widget.phone);
  late final TextEditingController _email =
      TextEditingController(text: widget.email);
  late final TextEditingController _order =
      TextEditingController(text: widget.orderNo);
  final _subject = TextEditingController(text: '수품 구매 문의');
  final _message = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _order.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 2400)),
    );
  }

  /// 메일 본문 — 주문정보 + 필수 안내문구.
  String get _body {
    final b = StringBuffer();
    b.writeln('[수품 구매 문의]');
    b.writeln('주문번호: ${_order.text.trim()}');
    b.writeln('이름: ${_name.text.trim()}');
    b.writeln('연락처(핸드폰): ${_phone.text.trim()}');
    b.writeln('이메일: ${_email.text.trim()}');
    b.writeln('----------');
    b.writeln(_message.text.trim());
    b.writeln('----------');
    b.writeln('※ 답변이 다소 늦어질 수 있음을 양해해 주시기 바랍니다.');
    b.writeln('※ 만일 답변이 늦어질 경우 관리자에게 전화나 문자를 보내시기 바랍니다.');
    return b.toString();
  }

  Future<void> _openMail({required bool gmail}) async {
    if (_name.text.trim().isEmpty) {
      _toast('이름을 입력하세요.');
      return;
    }
    if (_phone.text.trim().isEmpty) {
      _toast('수신 가능한 핸드폰 번호를 반드시 입력하세요.');
      return;
    }
    if (_message.text.trim().isEmpty) {
      _toast('문의 내용을 입력하세요.');
      return;
    }
    final enc = Uri.encodeComponent;
    final subject =
        '${_subject.text.trim().isEmpty ? '수품 구매 문의' : _subject.text.trim()}'
        '${_order.text.trim().isNotEmpty ? ' (${_order.text.trim()})' : ''}'
        ' — ${_name.text.trim()}';
    final Uri uri = gmail
        ? Uri.parse(
            'https://mail.google.com/mail/?view=cm&fs=1&to=${enc(kMerchInquiryTo)}&su=${enc(subject)}&body=${enc(_body)}')
        : Uri(
            scheme: 'mailto',
            path: kMerchInquiryTo,
            query: 'subject=${enc(subject)}&body=${enc(_body)}',
          );

    if (isWebRuntime) {
      try {
        openUrlInNewTab(uri.toString());
        _toast('메일 작성창이 열렸습니다. 첨부파일은 개인 메일에서 직접 첨부해 주세요.');
        return;
      } catch (_) {}
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _toast('메일 앱으로 이동했습니다. 첨부파일은 개인 메일에서 직접 첨부해 주세요.');
        return;
      }
    } catch (_) {}
    _toast('메일 앱을 열 수 없습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.94),
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
                  const Row(
                    children: [
                      Icon(Icons.mark_email_read_rounded,
                          color: AppColors.purple, size: 22),
                      SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('문의하기',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w900)),
                          Text('내 메일로 보내면 담당자에게 접수됩니다',
                              style: TextStyle(
                                  fontSize: 11.5, color: AppColors.textGray)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.taegeukBlue.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.alternate_email,
                            size: 16, color: AppColors.taegeukBlue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('받는사람(고정): $kMerchInquiryTo',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.taegeukBlue)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _field(_order, '주문번호'),
                  const SizedBox(height: 10),
                  _field(_name, '이름 (실명)', required: true),
                  const SizedBox(height: 10),
                  _field(_phone, '수신 가능한 핸드폰 번호', required: true,
                      keyboard: TextInputType.phone),
                  const SizedBox(height: 10),
                  _field(_email, '내 이메일 (선택)',
                      keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 10),
                  _field(_subject, '제목'),
                  const SizedBox(height: 10),
                  _field(_message, '문의 내용', required: true, maxLines: 5),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.tigerGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.tigerGold.withValues(alpha: 0.5)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('꼭 확인해 주세요',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w900)),
                        SizedBox(height: 4),
                        Text(
                          '※ 답변이 다소 늦어질 수 있음을 양해해 주시기 바랍니다.\n'
                          '※ 만일 답변이 늦어질 경우 관리자에게 전화나 문자를 보내시기 바랍니다.',
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              color: AppColors.textDark),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.scoutGreen,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _openMail(gmail: true),
                    icon: const Icon(Icons.outgoing_mail, size: 19),
                    label: const Text('지메일로 문의 보내기',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _openMail(gmail: false),
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: const Text('기본 메일 앱으로 보내기',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '받는사람은 $kMerchInquiryTo 으로 고정됩니다. '
                    '첨부파일은 각자 개인 메일에서 직접 첨부해 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textGray, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
    );
  }
}
