import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../services/file_pick.dart';
import '../services/web_nav.dart';
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

  /// 서버 접수(기록) 완료 여부 — 작성창 열기 전 중복 접수 방지.
  bool _recorded = false;

  /// 받는 사람(중앙회) 이메일 — config의 adminEmail 사용.
  late final String _toEmail;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _toEmail = app.adminEmail;
    // 로그인 정보로 폼 프리필(가능한 경우).
    final s = app;
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
    final res = await pickDataFiles(
      allowMultiple: true,
      dialogTitle: '문의 첨부파일 선택',
    );
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

  /// 작성창으로 전달할 본문 (발송자 정보 + 동의 + 내용).
  String get _mailBody {
    final b = StringBuffer();
    b.writeln('[TSAK 문의]');
    b.writeln('이름(실명): ${_name.text.trim()}');
    b.writeln(
      '인가번호: ${_number.text.trim().isEmpty ? '(미입력)' : _number.text.trim()}',
    );
    b.writeln(
      '휴대폰: ${_phone.text.trim().isEmpty ? '(미입력)' : _phone.text.trim()}',
    );
    b.writeln('개인정보 활용(사진 포함) 동의: 동의함');
    b.writeln('첨부파일: ${_files.map((f) => f.name).join(', ')}');
    b.writeln('----------');
    b.writeln(_message.text.trim());
    return b.toString();
  }

  /// 1번 방식: 문의자 **본인 메일(작성창)** 을 열어 보낸다.
  ///
  /// - 보낸사람 = 문의자 개인 메일 (로그인은 각 메일 서비스가 처리)
  /// - 받는사람·제목·본문 자동 입력
  /// - 파일은 작성창에서 직접 첨부 (웹 지메일/네이버 메일에서 첨부 가능)
  ///
  /// 초안 유실 방지를 위해 **서버 접수(기록)** 를 먼저 하고 작성창을 연다.
  Future<void> _sendViaMyMail() async {
    final email = _email.text.trim();
    final emailOk = email.contains('@') && email.split('@').last.contains('.');
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
    if (!_agreed) {
      _toast('개인정보 활용(사진 포함) 동의가 필요합니다.');
      return;
    }

    // 서버 접수(기록) 먼저 — 작성창 취소해도 문의가 남도록.
    if (!_recorded) _record();
    final to = _toEmail;
    final subject =
        '[TSAK 문의] ${_subject.text.trim().isEmpty ? '문의' : _subject.text.trim()} — ${_name.text.trim()}';

    // 네이버/지메일 선택 (아이디 있는 서비스로 보낸사람 고정).
    final provider = await showModalBottomSheet<String>(
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
              padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Row(
                children: [
                  Icon(Icons.outgoing_mail, size: 18, color: AppColors.purple),
                  SizedBox(width: 6),
                  Text(
                    '내 메일로 보내기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '평소 쓰는 메일을 골라 작성창을 여세요 (보낸사람=본인)',
                style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline, color: Color(0xFF34A853)),
              title: const Text('Gmail (지메일)로 작성'),
              subtitle: const Text('받는사람·제목·본문 자동 입력 · 지메일 로그인'),
              onTap: () => Navigator.pop(ctx, 'gmail'),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline, color: Color(0xFF03C75A)),
              title: const Text('네이버 메일로 작성'),
              subtitle: const Text('받는사람·제목·본문 자동 입력 · 네이버 로그인'),
              onTap: () => Navigator.pop(ctx, 'naver'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.apps, color: AppColors.textGray),
              title: const Text('기본 메일 앱으로 작성 (mailto)'),
              subtitle: const Text('PC/모바일 기본 메일 프로그램 사용'),
              onTap: () => Navigator.pop(ctx, 'mailto'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (provider == null) return;

    final enc = Uri.encodeComponent;
    final Uri uri;
    if (provider == 'gmail') {
      uri = Uri.parse(
        'https://mail.google.com/mail/?view=cm&fs=1&to=${enc(to)}&su=${enc(subject)}&body=${enc(_mailBody)}',
      );
    } else if (provider == 'naver') {
      uri = Uri.parse(
        'https://mail.naver.com/write/popup?to=${enc(to)}&subject=${enc(subject)}&body=${enc(_mailBody)}',
      );
    } else {
      uri = Uri(
        scheme: 'mailto',
        path: to,
        query: 'subject=${enc(subject)}&body=${enc(_mailBody)}',
      );
    }

    // 웹: 새 창으로 작성창 열기 (모바일 브라우저에서도 동작).
    if (isWebRuntime) {
      try {
        openUrlInNewTab(uri.toString());
        _toast('메일 작성창이 열렸습니다. 파일은 거기서 직접 첨부해 주세요.');
      } catch (_) {
        _toast('메일 앱을 열 수 없습니다.');
      }
      return;
    }
    // 모바일/데스크톱 앱: 외부 앱으로 열기.
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _toast('메일 앱으로 이동했습니다. 파일은 거기서 첨부해 주세요.');
        return;
      }
    } catch (_) {}
    _toast('메일 앱을 열 수 없습니다.');
  }

  /// 서버(NAS)에 문의를 접수·기록한다 (첨부 포함). 성공 시 true.
  Future<bool> _record() async {
    try {
      final files = <Map<String, String>>[];
      for (final f in _files) {
        files.add({'name': f.name, 'data': base64Encode(f.bytes)});
      }
      final res = await context.read<AppState>().nas.submitInquiry(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        number: _number.text.trim(),
        subject: _subject.text.trim(),
        message: _message.text.trim(),
        agreed: _agreed,
        files: files,
      );
      if (res['ok'] == true) {
        _recorded = true;
        return true;
      }
      return false;
    } catch (_) {
      return false;
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
      final ok = await _record();
      if (!mounted) return;
      if (ok) {
        _toast('문의가 접수되었습니다. (서버 접수 완료)');
        Navigator.pop(context);
      } else {
        _toast('문의 전송에 실패했습니다. 잠시 후 다시 시도해 주세요.');
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
                      Icon(
                        Icons.mark_email_read_rounded,
                        color: AppColors.purple,
                        size: 22,
                      ),
                      SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '문의하기',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '문의는 이메일로 접수됩니다',
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
                  _field(_name, '이름 (실명)', required: true),
                  const SizedBox(height: 10),
                  _field(_number, '인가번호 (선택)'),
                  const SizedBox(height: 10),
                  _field(_phone, '휴대폰번호', keyboard: TextInputType.phone),
                  const SizedBox(height: 10),
                  _field(
                    _email,
                    '보낸사람 이메일 (필수)',
                    keyboard: TextInputType.emailAddress,
                    required: true,
                  ),
                  const SizedBox(height: 10),
                  _field(_subject, '제목 (선택)'),
                  const SizedBox(height: 10),
                  _field(_message, '문의 내용', maxLines: 5, required: true),
                  const SizedBox(height: 12),
                  _attachBox(),
                  const SizedBox(height: 14),
                  _consentBox(),
                  const SizedBox(height: 16),
                  // 1) 내 메일(작성창) 열기 — 보낸사람=본인 개인 메일
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.scoutGreen,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _sending ? null : _sendViaMyMail,
                    icon: const Icon(Icons.outgoing_mail, size: 19),
                    label: const Text(
                      '내 메일로 보내기 (작성창 열기)',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 2) 서버 접수만 (메일 앱 없이 기록)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 13),
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
                              strokeWidth: 2,
                              color: AppColors.purple,
                            ),
                          )
                        : const Icon(Icons.save_alt, size: 18),
                    label: Text(
                      _sending ? '전송 중…' : '서버에만 접수 (기록)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '「내 메일로 보내기」는 평소 쓰는 메일(지메일·네이버)로 로그인해 '
                    '보낸사람=본인으로 발송합니다. 파일은 작성창에서 직접 첨부해 주세요.\n'
                    '보낸사람 이메일이 없거나 개인정보 활용에 동의하지 않으면 발송할 수 없습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
              const Text(
                '파일 첨부',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
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
              child: Text(
                '첨부된 파일이 없습니다. (파일당 최대 5MB)',
                style: TextStyle(fontSize: 11, color: AppColors.textGray),
              ),
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
                  const Text(
                    '개인정보 수집·이용 및 사진 활용 동의 (필수)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
                      color: _agreed ? AppColors.textDark : AppColors.textGray,
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
