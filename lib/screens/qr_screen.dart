import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'member_detail_screen.dart';

/// 인가자 QR코드 생성 + 스캔 화면
class QrScreen extends StatelessWidget {
  const QrScreen({super.key, this.member});

  /// member가 있으면 QR 생성, 없으면 스캔 모드
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

  /// QR에 담을 요약 데이터 (JSON)
  String get _payload => json.encode({
    'tsak': 1,
    'no': member.number,
    'name': member.name,
    'league': member.league,
    'unit': member.unit,
    'date': member.date,
    'phone': member.phone,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('#${member.number} ${member.name} QR'),
        actions: [
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
                        data: _payload,
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
                      if (member.league.isNotEmpty || member.unit.isNotEmpty)
                        Text(
                          '${member.league} ${member.unit}',
                          style: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 12.5,
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
                      Clipboard.setData(ClipboardData(text: _payload));
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

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;

    // TSAK QR이면 해당 인가자로 이동, 아니면 텍스트 검색
    String? targetId;
    try {
      final map = json.decode(code) as Map<String, dynamic>;
      if (map['tsak'] == 1) {
        final no = '${map['no']}';
        final appState = context.read<AppState>();
        final match = appState.members.where((m) => m.number == no).toList();
        if (match.isNotEmpty) targetId = match.first.id;
      }
    } catch (_) {
      // 일반 텍스트 QR — 무시
    }

    _handled = true;
    if (!mounted) return;

    if (targetId != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MemberDetailScreen(memberId: targetId!),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('TSAK 인가자 QR이 아닙니다')));
      Future.delayed(const Duration(seconds: 2), () => _handled = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR 코드 스캔')),
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
