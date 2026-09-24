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
  String _payload(BuildContext context) {
    final state = context.read<AppState>();
    return json.encode({
      'tsak': 1,
      'no': member.number,
      'name': member.name,
      'league': member.league,
      'unit': member.unit,
      'date': member.date,
      'phone': member.phone,
      'atas': member.atasNo,
      'url': state.repo.isNasMode ? state.nas.baseUrl : '',
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
                        '인가번호 #${member.number}',
                        style: const TextStyle(color: AppColors.purple),
                      ),
                      if (member.atasNo.isNotEmpty)
                        Text(
                          'ATAS ${member.atasNo} · #${member.number}',
                          style: const TextStyle(
                            color: AppColors.scoutGreen,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        '이 QR을 스캔하면 해당 인가자 정보를 수정할 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
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
                      Clipboard.setData(
                          ClipboardData(text: _payload(context)));
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('TSAK 인가자 QR이 아닙니다')),
        );
        Future.delayed(const Duration(seconds: 2), () => _handled = false);
      }
      return;
    }

    final state = context.read<AppState>();
    final target = state.byNumber(number);
    if (target == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('인가번호 $number 를 찾을 수 없습니다')),
        );
        Future.delayed(const Duration(seconds: 2), () => _handled = false);
      }
      return;
    }

    // 개인 접근 비밀번호 확인 (마스터는 생략)
    if (!state.isMaster) {
      final ok = await _askPersonalPassword(state, number);
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

  Future<bool?> _askPersonalPassword(AppState state, String number) {
    final ctrl = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('본인 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('인가번호 $number 의 정보를 수정하려면\n개인 비밀번호를 입력하세요.',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '인가번호 + ${AppConfig.personalSuffix}',
                hintText: '$number${AppConfig.personalSuffix}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              final ok = v == '$number${AppConfig.personalSuffix}' ||
                  v == AppConfig.masterPassword;
              Navigator.pop(ctx, ok);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
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
