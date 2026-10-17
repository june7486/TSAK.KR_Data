import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member.dart';
import '../services/app_config.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';
import 'member_edit_screen.dart';

/// 인가자 QR코드 생성 + 스캔 화면
class QrScreen extends StatelessWidget {
  const QrScreen({super.key, this.member});

  final Member? member;

  @override
  Widget build(BuildContext context) {
    if (member == null) {
      return const _QrScanView();
    }
    return _QrGenerateView(member: member!);
  }
}

class _QrGenerateView extends StatelessWidget {
  const _QrGenerateView({required this.member});

  final Member member;

  /// QR에 담을 값 — **카메라로 스캔하면 앱이 바로 열리는 절대 URL**.
  ///
  /// 이전에는 여러 정보를 담은 JSON을 넣어 데이터가 커져 인식률이 낮고,
  /// 상대경로라 스캔해도 열리지 않았다. 이제 짧은 절대 URL 하나만 담는다.
  /// (인가번호는 URL의 `no` 파라미터에 들어가며, 스캔 시 본인확인 후
  ///  바로 정보수정 페이지로 연결된다.)
  String _payload(BuildContext context) {
    final state = context.read<AppState>();
    return state.personalQrLink(member.number);
  }

  /// QR 링크를 복사한다(요구: "데이터 복사" → "링크주소 복사").
  void _copyLink(BuildContext context) {
    final link = _payload(context);
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('접속 링크주소를 복사했습니다. 붙여넣기로 공유하세요.')),
    );
  }

  /// 현재 접속 중인 브라우저 창에서 링크를 연다(QR·링크주소 클릭 → 접속).
  ///
  ///  · 웹: 새 탭으로 열리지 않고 **같은 창에서 바로** 접속 주소로 이동한다.
  ///  · 그 외(모바일 등): 외부 브라우저/앱으로 연다.
  Future<void> _openLink(BuildContext context) async {
    final link = _payload(context);
    if (!link.startsWith('http')) {
      // 공개 접속 주소가 설정되지 않은 상대경로 — 열 수 없다.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('공개 접속 주소가 설정되지 않아 링크를 열 수 없습니다.\n설정 → "QR 공개 주소"를 입력하세요.'),
        ),
      );
      return;
    }
    final uri = Uri.parse(link);
    try {
      // 웹에서는 같은 창(_self)으로 이동해 새 탭/팝업 차단을 피하고,
      //  곧바로 접속(딥링크)되게 한다. 그 외 플랫폼은 기본 동작(외부 열기).
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      if (!ok) {
        final ok2 = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!ok2) throw Exception('open failed');
      }
    } catch (_) {
      if (!context.mounted) return;
      // 열기가 막힌 환경(일부 인앱 브라우저)에서는 주소를 복사해 준다.
      Clipboard.setData(ClipboardData(text: link));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 주소창에 붙여넣어 접속하세요. (주소를 복사했습니다)')),
      );
    }
  }

  /// QR 화면에서 해당 인가자 정보수정 페이지로 이동.
  /// 마스터/본인(개인접근)은 바로, 그 외는 로그인 확인 후 이동.
  Future<void> _openEdit(BuildContext context) async {
    final state = context.read<AppState>();
    final isSelf =
        (state.isPersonal || state.isMaster) &&
        state.who.replaceAll(RegExp(r'[^0-9]'), '') ==
            member.number.replaceAll(RegExp(r'[^0-9]'), '');
    if (!state.isMaster && !isSelf) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _QrLoginDialog(
          number: member.number,
          name: member.name,
          corps: member.corps,
        ),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberEditScreen(memberId: member.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: Text('${member.numberLabel} ${member.name} QR'),
        actions: [
          const AppHomeEmblem(size: 24),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: '스캔',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _QrScanView()),
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Card(
                margin: const EdgeInsets.all(20),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/tsak_emblem.png',
                            width: 44,
                            height: 44,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.shield, size: 40),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              '한국범스카우트 중앙회\n인가자 QR',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // (요구) QR을 클릭하면 접속 가능 — QR 자체를 탭하면
                      //  QR에 담긴 접속 주소로 이동한다.
                      Tooltip(
                        message: 'QR/링크를 클릭하면 접속 화면이 열립니다',
                        child: InkWell(
                          onTap: () => _openLink(context),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: QrImageView(
                              data: _payload(context),
                              version: QrVersions.auto,
                              size: 230,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: AppColors.purple,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: AppColors.purpleDark,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        member.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${member.corpsFullName}인가번호 ${member.number}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.purple,
                        ),
                      ),
                      if (member.atasNo.isNotEmpty)
                        Text(
                          'ATAS ${member.atasNo}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.scoutGreen,
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        '이 QR을 스캔하면 앱이 열리고,\n본인 확인 후 인가자 정보를 바로 수정할 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textGray,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 실제로 QR에 인코딩된 주소(검증용). 스캔이 안 되면 이 값이
                      // http(s)로 시작하는지 확인하면 된다.
                      // (요구) 주소를 클릭하면 바로 접속된다.
                      Tooltip(
                        message: '클릭하면 접속 주소가 열립니다',
                        child: InkWell(
                          onTap: () => _openLink(context),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              _payload(context),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.purple,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.purple,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!context.read<AppState>().hasQrBase) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.taegeukRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.taegeukRed.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          child: const Text(
                            '⚠ 공개 접속 주소가 설정되지 않아 QR이 상대경로입니다.\n'
                            '스캔해도 앱이 열리지 않습니다.\n'
                            '설정 → “QR 공개 주소”에서 배포 주소를 입력하세요.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: AppColors.taegeukRed,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // (요구) "데이터 복사" → "링크주소 복사": QR에 담긴 접속 링크를 복사.
                  OutlinedButton.icon(
                    onPressed: () => _copyLink(context),
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('링크주소 복사'),
                  ),
                  const SizedBox(width: 10),
                  // (요구) 버튼으로도 바로 접속 가능하게 — 링크 열기.
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                    ),
                    onPressed: () => _openLink(context),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('링크 열기'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // QR을 보는 화면에서 바로 해당 인가자 정보수정 페이지로 이동
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 13,
                  ),
                ),
                onPressed: () => _openEdit(context),
                icon: const Icon(Icons.edit_note, size: 20),
                label: const Text(
                  '인가자 정보수정',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

/// QR 화면에서 정보수정 진입 시 사용하는 로그인 다이얼로그.
/// ID(인가번호/TSAK) + PW. 개인비번·앱비번·마스터비번 중 하나로 통과.
class _QrLoginDialog extends StatefulWidget {
  const _QrLoginDialog({
    required this.number,
    required this.name,
    this.corps = 'tsak',
  });

  final String number;
  final String name;
  final String corps;

  @override
  State<_QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends State<_QrLoginDialog> {
  bool get _isEunha => widget.corps == 'eunha';
  String get _prefix => _isEunha ? '은하' : '범';

  /// 표기 라벨 — 은하 '#43' → 은하#43.
  String get _numberLabel =>
      widget.number.trim().isEmpty ? '' : '$_prefix#${widget.number}';

  /// 로그인 기본 ID — 은하는 '은하N'(서버 개인 아이디), 범은 인가번호.
  String get _defaultLoginId =>
      _isEunha ? '$_prefix${widget.number}' : widget.number;

  late final TextEditingController _idCtrl = TextEditingController(
    text: _defaultLoginId,
  );
  final _pwCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<bool> _verify(AppState state, String idRaw, String pwRaw) async {
    final id = idRaw.trim();
    final pw = pwRaw.trim();
    if (pw.isEmpty) return false;
    if (pw == AppConfig.masterPassword) return true;
    if (state.repo.isNasMode) {
      try {
        final r = await state.nas.login('master', pw);
        if (r['ok'] == true) return true;
      } catch (_) {}
    }
    if (id.toUpperCase() == 'TSAK') {
      if (pw == AppConfig.appPassword) return true;
      if (state.repo.isNasMode) {
        try {
          final r = await state.nas.login('app', pw);
          if (r['ok'] == true) return true;
        } catch (_) {}
      }
    }
    final no = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (_isEunha) {
      // 은하스카우트 — 개인 로그인 id='은하N', pw='N!@@' (서버 전용 검증).
      if (no.isNotEmpty && pw == '$no!@@') return true;
      if (state.repo.isNasMode) {
        final cands = <String>{pw, if (no.isNotEmpty) '$no!@@'};
        for (final c in cands) {
          try {
            final r = await state.nas.login(
              'personal',
              c,
              id: _defaultLoginId,
              corps: 'eunha',
            );
            if (r['ok'] == true) return true;
          } catch (_) {}
        }
      }
      return false;
    }
    if (no.isNotEmpty) {
      final cands = <String>{pw, '$no$pw'};
      if (cands.contains('$no${AppConfig.personalSuffix}')) return true;
      if (state.repo.isNasMode) {
        for (final c in cands) {
          try {
            final r = await state.nas.login('personal', c);
            if (r['ok'] == true) return true;
          } catch (_) {}
        }
      }
    }
    return false;
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final ok = await _verify(
      context.read<AppState>(),
      _idCtrl.text,
      _pwCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _err = 'ID 또는 비밀번호가 올바르지 않습니다';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
      scrollable: true,
      icon: const Icon(Icons.lock_open, color: AppColors.purple, size: 30),
      title: const Text('인가자 정보 접속', textAlign: TextAlign.center),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '인가자: ${widget.name} ($_numberLabel)',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.purple,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _idCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'ID',
                hintText: _isEunha
                    ? '은하스카우트 아이디 (예: 은하100)'
                    : '범스카우트 인가번호 (예: 415) 또는 TSAK',
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pwCtrl,
              obscureText: _obscure,
              onSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: '비밀번호',
                hintText: '개인비번(000!@@) · 앱비번 · 마스터비번',
                prefixIcon: const Icon(Icons.password),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_err != null) ...[
              const SizedBox(height: 8),
              Text(
                _err!,
                style: const TextStyle(
                  color: AppColors.taegeukRed,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              '※ 개인 인가번호+개인비번, 관리자(TSAK) 앱비번, 마스터 비번 중 하나로 접속할 수 있습니다.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textGray),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('접속'),
        ),
      ],
    );
  }
}

class _QrScanView extends StatefulWidget {
  const _QrScanView();

  @override
  State<_QrScanView> createState() => _QrScanViewState();
}

class _QrScanViewState extends State<_QrScanView> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;
    _handled = true;

    String? number;
    // 1) 새 형식: 절대/상대 URL (…?access=personal&no=415)
    try {
      final uri = Uri.parse(code);
      final acc = uri.queryParameters['access'];
      if (acc == 'personal') {
        number = uri.queryParameters['no'];
      } else if (uri.queryParameters['no'] != null &&
          uri.queryParameters['tsak'] != null) {
        number = uri.queryParameters['no'];
      }
    } catch (_) {}
    // 2) 구 형식: JSON 페이로드 {tsak:1, no:415, …}
    if (number == null) {
      try {
        final map = json.decode(code) as Map<String, dynamic>;
        if (map['tsak'] == 1) number = '${map['no']}';
      } catch (_) {}
    }

    if (number == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('TSAK 인가자 QR이 아닙니다')));
        Future.delayed(const Duration(seconds: 2), () => _handled = false);
      }
      return;
    }
    number = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (number.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('인가번호가 없는 QR입니다')));
        Future.delayed(const Duration(seconds: 2), () => _handled = false);
      }
      return;
    }

    final state = context.read<AppState>();

    // 다른 사람이 개인 로그인 중일 때만 본인 QR 제한.
    // (로그인 안 됨 / 마스터 / 관리자 세션이면 그대로 진행)
    if (state.isPersonal) {
      final mine = state.who.replaceAll(RegExp(r'[^0-9]'), '');
      final scanned = number.replaceAll(RegExp(r'[^0-9]'), '');
      if (mine.isNotEmpty && mine != scanned) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('개인 접근에서는 본인 QR만 열람·수정할 수 있습니다'),
              backgroundColor: AppColors.taegeukRed,
            ),
          );
          Future.delayed(const Duration(seconds: 2), () => _handled = false);
        }
        return;
      }
    }

    final target = state.byNumber(number);
    if (target == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('인가번호 $number 를 찾을 수 없습니다')));
        Future.delayed(const Duration(seconds: 2), () => _handled = false);
      }
      return;
    }

    // 개인 QR 스캔 = 개인 로그인으로 간주 (비밀번호 없이) → 정보수정 바로 이동.
    // 권한은 기존 개인 로그인과 완전히 동일 (추가 권한 없음, 본인만 수정).
    final ok = await state.qrPersonalLogin(number);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR 인증에 실패했습니다'),
            backgroundColor: AppColors.taegeukRed,
          ),
        );
        Future.delayed(const Duration(seconds: 2), () => _handled = false);
      }
      return;
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MemberEditScreen(memberId: target.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('QR 코드 스캔 → 수정'),
        actions: const [AppHomeEmblem(size: 24)],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  '인가자 QR코드를 사각형 안에 맞춰주세요',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 12),
                IconButton.filled(
                  onPressed: () => _controller.toggleTorch(),
                  icon: const Icon(Icons.flash_on),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
