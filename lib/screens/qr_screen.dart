import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/member.dart';
import '../services/app_config.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
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

  /// QR에 담을 요약 데이터 (JSON) — 인가번호·이름·개인접속 안내 포함
  ///
  /// 스캔 시 앱/웹 접속 페이지로 바로 이동할 수 있도록 접속 URL 을 함께 담는다.
  String _payload(BuildContext context) {
    final state = context.read<AppState>();
    final nasBase = state.repo.isNasMode ? state.nas.baseUrl : '';
    // 개인접속(인가자) 접속 페이지 주소 — 스캔하면 바로 로그인 화면으로 진입
    final accessUrl = state.appAccessUrl.isNotEmpty
        ? state.appAccessUrl
        : nasBase;
    return json.encode({
      'tsak': 1,
      'no': member.number,
      'name': member.name,
      'league': member.league,
      'unit': member.unit,
      'date': member.date,
      'phone': member.phone,
      'atas': member.atasNo,
      'url': '$accessUrl/?access=personal&no=${member.number}',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: Text('#${member.number} ${member.name} QR'),
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
                      QrImageView(
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
                      const SizedBox(height: 16),
                      Text(
                        member.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '범스카우트인가번호 #${member.number}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.purple,
                        ),
                      ),
                      if (member.atasNo.isNotEmpty)
                        Text(
                          'ATAS #${member.atasNo}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.scoutGreen,
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        '이 QR을 스캔하면 앱이 열리고,\n로그인 후 해당 인가자 정보를 수정할 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _payload(context)));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('QR 데이터가 복사되었습니다')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('데이터 복사'),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
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
    try {
      final map = json.decode(code) as Map<String, dynamic>;
      if (map['tsak'] == 1) number = '${map['no']}';
    } catch (_) {}

    if (number == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('TSAK 인가자 QR이 아닙니다')));
        Future.delayed(const Duration(seconds: 2), () => _handled = false);
      }
      return;
    }

    final state = context.read<AppState>();

    // 개인 접근: 본인 QR만 허용
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

    // 마스터/개인 접근이 아니면 로그인 확인 후 정보 수정 페이지로 이동
    if (!state.isMaster && !state.isPersonal) {
      final ok = await _askLogin(state, number, target.name);
      if (ok != true) {
        _handled = false;
        return;
      }
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

  /// 개인접속 QR — ID(범스카우트 인가번호) / PW 입력 로그인.
  /// 관리자(TSAK)·마스터 비밀번호로도 접속 가능. 성공 시 정보 수정 페이지로 이동.
  Future<bool?> _askLogin(AppState state, String number, String name) {
    final idCtrl = TextEditingController(text: number);
    final pwCtrl = TextEditingController();
    bool obscure = true;
    bool busy = false;
    String? err;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'QR 인가자: $name (#$number)',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.purple,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: idCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'ID',
                    hintText: '범스카우트 인가번호 (예: 415) 또는 TSAK',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pwCtrl,
                  obscureText: obscure,
                  onSubmitted: (_) async {
                    if (busy) return;
                    setLocal(() => busy = true);
                    final ok = await _verify(state, idCtrl.text, pwCtrl.text);
                    if (!ctx.mounted) return;
                    final nav = Navigator.of(ctx);
                    if (ok) {
                      nav.pop(true);
                    } else {
                      setLocal(() {
                        busy = false;
                        err = 'ID 또는 비밀번호가 올바르지 않습니다';
                      });
                    }
                  },
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    hintText: '개인비번(000!@@) · 앱비번 · 마스터비번',
                    prefixIcon: const Icon(Icons.password),
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setLocal(() => obscure = !obscure),
                    ),
                  ),
                ),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    err!,
                    style: const TextStyle(
                        color: AppColors.taegeukRed, fontSize: 12),
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
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() => busy = true);
                      final ok =
                          await _verify(state, idCtrl.text, pwCtrl.text);
                      if (!ctx.mounted) return;
                      final nav = Navigator.of(ctx);
                      if (ok) {
                        nav.pop(true);
                      } else {
                        setLocal(() {
                          busy = false;
                          err = 'ID 또는 비밀번호가 올바르지 않습니다';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('접속'),
            ),
          ],
        ),
      ),
    );
  }

  /// ID/PW 검증 — 마스터 / 관리자(TSAK) / 개인(인가번호) 순으로 확인
  Future<bool> _verify(AppState state, String idRaw, String pwRaw) async {
    final id = idRaw.trim();
    final pw = pwRaw.trim();
    if (pw.isEmpty) return false;

    // 1) 마스터
    if (pw == AppConfig.masterPassword) return true;
    if (state.repo.isNasMode) {
      try {
        final r = await state.nas.login('master', pw);
        if (r['ok'] == true) return true;
      } catch (_) {}
    }
    // 2) 관리자 (ID = TSAK)
    if (id.toUpperCase() == 'TSAK') {
      if (pw == AppConfig.appPassword) return true;
      if (state.repo.isNasMode) {
        try {
          final r = await state.nas.login('app', pw);
          if (r['ok'] == true) return true;
        } catch (_) {}
      }
    }
    // 3) 개인 (ID = 인가번호)
    final no = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (no.isNotEmpty) {
      final cands = <String>{pw, '$no$pw'};
      for (final c in cands) {
        if (c == '$no${AppConfig.personalSuffix}') return true;
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
