import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../theme/app_theme.dart';

/// 문의 시트 (t12).
///
/// - 문의는 **이메일(서버 발송)** 로만 접수한다.
/// - 보낸사람 이메일이 없으면 발송 불가.
/// - 발송자 정보: 이름(실명), 인가번호(선택), 휴대폰번호
/// - 개인정보 활용 동의(사진 활용 포함) 체크 필수 — 미동의 시 발송 불가.
/// - 문의내용 및 **파일 첨부** 가능.
///
/// 문의 내용은 정책개발·연구에 활용되며, 카페 등에 노출되어
/// 범스카우트중앙회 발전의 기본자료로 활용될 수 있다.
Future<void> showInquirySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _InquirySheet(),
  );
}

class _InquirySheet extends StatefulWidget {
  const _InquirySheet();

  @override
  State<_InquirySheet> createState() => _InquirySheetState();
}

class _InquirySheetState extends State<_InquirySheet> {
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _message = TextEditingController();

  bool _agreed = false;
  bool _sending = false;
  final List<PickedFileData> _files = [];

  @override
  void initState() {
    super.initState();
    // 로그인 정보로 폼 프리필(가능한 경우).
    final s = context.read<AppState>();
    if (s.isSelfAccess && s.who.isNotEmpty) {
      final m = s.repo.byNumber(s.who);
      if (m != null) {
        _number.text = m.number;
        if (m.phone.isNotEmpty) _phone.text = m.phone;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _phone.dispose();
    _email.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(milliseconds: 2200)),
    );
  }

  Future<void> _pickFiles() async {
    final res = await pickDataFiles(allowMultiple: true, dialogTitle: '문의 첨부파일 선택');
    if (res.isEmpty) return;
    setState(() {
      for (final f in res) {
        // 5MB 초과 파일은 제외
        if (f.bytes.length > 5 * 1024 * 1024) continue;
        _files.add(f);
      }
    });
    if (res.any((f) => f.bytes.length > 5 * 1024 * 1024)) {
      _toast('5MB를 넘는 파일은 첨부할 수 없습니다.');
    }
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    final emailOk = email.contains('@') && email.split('@').last.contains('.');

    // 1) 보낸사람 메일 없으면 발송 금지
    if (!emailOk) {
      _toast('보낸사람 이메일을 정확히 입력하세요. (메일이 없으면 발송이 불가합니다)');
      return;
    }
    if (_name.text.trim().isEmpty) {
      _toast('이름(실명)을 입력하세요.');
      return;
    }
    if (_message.text.trim().isEmpty) {
      _toast('문의 내용을 입력하세요.');
      return;
    }
    // 2) 동의 없으면 발송 금지
    if (!_agreed) {
      _toast('개인정보 활용(사진 포함) 동의가 필요합니다.');
      return;
    }

    setState(() => _sending = true);
    try {
      final files = <Map<String, String>>[];
      for (final f in _files) {
        files.add({'name': f.name, 'data': base64Encode(f.bytes)});
      }
      final res = await context.read<AppState>().nas.submitInquiry(
            name: _name.text.trim(),
            email: email,
            phone: _phone.text.trim(),
            number: _number.text.trim(),
            subject: _subject.text.trim(),
            message: _message.text.trim(),
            agreed: _agreed,
            files: files,
          );
      if (!mounted) return;
      if (res['ok'] == true) {
        final mailed = res['mailed'] == true;
        _toast(mailed
            ? '문의가 접수되어 이메일로 발송되었습니다. 감사합니다!'
            : '문의가 접수되었습니다. (서버 접수 완료)');
        Navigator.pop(context);
      } else {
        _toast('${res['error'] ?? '문의 전송에 실패했습니다. 잠시 후 다시 시도해 주세요.'}');
      }
    } catch (e) {
      _toast('문의 전송에 실패했습니다: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
                          Text('문의는 이메일로 접수됩니다',
                              style: TextStyle(
                                  fontSize: 11.5, color: AppColors.textGray)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _field(_name, '이름 (실명)', required: true),
                  const SizedBox(height: 10),
                  _field(_number, '인가번호 (선택)'),
                  const SizedBox(height: 10),
                  _field(_phone, '휴대폰번호', keyboard: TextInputType.phone),
                  const SizedBox(height: 10),
                  _field(_email, '보낸사람 이메일 (필수)',
                      keyboard: TextInputType.emailAddress, required: true),
                  const SizedBox(height: 10),
                  _field(_subject, '제목 (선택)'),
                  const SizedBox(height: 10),
                  _field(_message, '문의 내용', maxLines: 5, required: true),
                  const SizedBox(height: 12),
                  _attachBox(),
                  const SizedBox(height: 14),
                  _consentBox(),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _sending ? '전송 중…' : '문의 보내기',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '※ 보낸사람 이메일이 없거나 개인정보 활용에 동의하지 않으면 발송할 수 없습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppColors.textGray),
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

  Widget _attachBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_file, size: 16, color: AppColors.purple),
              const SizedBox(width: 6),
              const Text('파일 첨부',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                onPressed: _sending ? null : _pickFiles,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('파일 추가'),
              ),
            ],
          ),
          if (_files.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 2, top: 2),
              child: Text('첨부된 파일이 없습니다. (파일당 최대 5MB)',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray)),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _files.length; i++)
                  Chip(
                    label: Text(
                      '${_files[i].name} (${_kb(_files[i].bytes.length)})',
                      style: const TextStyle(fontSize: 11),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 15),
                    onDeleted: _sending
                        ? null
                        : () => setState(() => _files.removeAt(i)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static String _kb(int bytes) {
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)}KB';
    return '${(kb / 1024).toStringAsFixed(1)}MB';
  }

  Widget _consentBox() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _sending ? null : () => setState(() => _agreed = !_agreed),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _agreed
              ? AppColors.scoutGreen.withValues(alpha: 0.08)
              : AppColors.tigerGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _agreed
                ? AppColors.scoutGreen.withValues(alpha: 0.4)
                : AppColors.tigerGold.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _agreed,
              activeColor: AppColors.scoutGreen,
              onChanged: _sending
                  ? null
                  : (v) => setState(() => _agreed = v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('개인정보 수집·이용 및 사진 활용 동의 (필수)',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    '· 수집 항목: 이름(실명), 인가번호(선택), 휴대폰번호, 이메일, 문의 내용, 첨부파일\n'
                    '· 이용 목적: 문의 응대, 정책 개발 및 연구 활동\n'
                    '· 문의 내용은 카페 등에 노출되어 범스카우트중앙회 발전의 기본자료로 활용될 수 있습니다.\n'
                    '· 「사진·영상(초상)」이 포함된 경우, 홍보·소식지·공식 홈페이지·네이버 카페 등에 활용될 수 있습니다.\n'
                    '· 동의하지 않을 경우 발송이 제한되며, 이후 삭제를 요청할 수 있습니다.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: _agreed
                          ? AppColors.textDark
                          : AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
