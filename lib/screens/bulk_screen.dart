import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../services/contact_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';

/// 단체 소식 / 단체 문자
class BulkScreen extends StatefulWidget {
  const BulkScreen({super.key});

  @override
  State<BulkScreen> createState() => _BulkScreenState();
}

class _BulkScreenState extends State<BulkScreen> {
  final _subject = TextEditingController(text: '한국범스카우트 중앙회 안내');
  final _body = TextEditingController();
  String _scope = '전체';
  String? _league;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final recipients = _recipients(state);
    final phoneCount = ContactService.phones(recipients).length;
    final mailCount = ContactService.emails(recipients).length;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('단체 소식 / 문자'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.groups, color: AppColors.purple, size: 20),
                      SizedBox(width: 8),
                      Text('발송 대상',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('전체 회원'),
                        selected: _scope == '전체',
                        onSelected: (_) => setState(() {
                          _scope = '전체';
                          _league = null;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('연맹별'),
                        selected: _scope == '연맹',
                        onSelected: (_) => setState(() => _scope = '연맹'),
                      ),
                    ],
                  ),
                  if (_scope == '연맹') ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: state.leagues.keys
                          .where((k) => k != '(미지정)')
                          .map((k) => ChoiceChip(
                                label: Text(k),
                                selected: _league == k,
                                onSelected: (_) =>
                                    setState(() => _league = k),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    '수신 대상: 인가자 ${recipients.length}명 '
                    '(전화 $phoneCount건 · 메일 $mailCount건)',
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textGray,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.edit_note, color: AppColors.purple, size: 20),
                      SizedBox(width: 8),
                      Text('내용 작성',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _subject,
                    decoration: const InputDecoration(labelText: '제목 (메일)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _body,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '본문 (소식/문자 내용)',
                      hintText: '예: 2026년 정기총회 안내드립니다...',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.scoutGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _sendSms(recipients),
            icon: const Icon(Icons.sms),
            label: Text('단체 문자 발송 ($phoneCount명)'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.purple,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _sendMail(recipients),
            icon: const Icon(Icons.email),
            label: Text('단체 메일 발송 ($mailCount명)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: '${_subject.text}\n\n${_body.text}',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('소식 내용이 복사되었습니다')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('소식 내용 복사 (공지용)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: ContactService.phoneList(recipients),
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('수신 전화번호가 복사되었습니다')),
              );
            },
            icon: const Icon(Icons.phone_forwarded),
            label: const Text('수신 전화번호 목록 복사'),
          ),
          const SizedBox(height: 20),
          const _YearFolderNote(),
        ],
      ),
    );
  }

  List<Member> _recipients(AppState state) {
    if (_scope == '연맹' && _league != null) {
      return state.members.where((m) => m.league == _league).toList();
    }
    return state.members;
  }

  Future<void> _sendSms(List<Member> recipients) async {
    if (recipients.isEmpty) return;
    final uri = ContactService.smsUri(
      recipients,
      body: _body.text,
    );
    _open(uri, '문자 앱을 열 수 없습니다');
  }

  Future<void> _sendMail(List<Member> recipients) async {
    if (recipients.isEmpty) return;
    final uri = ContactService.mailtoUri(
      recipients,
      subject: _subject.text,
      body: _body.text,
    );
    _open(uri, '메일 앱을 열 수 없습니다');
  }

  Future<void> _open(String uri, String err) async {
    try {
      final u = Uri.parse(uri);
      final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }
}

class _YearFolderNote extends StatelessWidget {
  const _YearFolderNote();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final y = now.year;
    return Card(
      color: AppColors.scoutGreen.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.folder_special,
                    color: AppColors.scoutGreen, size: 18),
                SizedBox(width: 8),
                Text('연회비 폴더 자동 생성',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '현재 $y년 기준, NAS에 $y · ${y + 1} 연회비 폴더가 '
              '실시간 자동 생성됩니다. (앱 실행 시점 기준)',
              style: const TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
          ],
        ),
      ),
    );
  }
}
