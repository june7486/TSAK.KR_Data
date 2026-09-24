import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';

/// 앱 접근 안내 — NAS에 배포된 앱 주소 + QR
/// (상단 QR 픽토그램 / 제목 버튼에서 진입)
class AppAccessScreen extends StatelessWidget {
  const AppAccessScreen({super.key});

  String _url(AppState state) {
    if (state.appAccessUrl.isNotEmpty) return state.appAccessUrl;
    if (kIsWeb) {
      // 웹에서 실행 중이면 현재 origin이 곧 배포 주소
      return Uri.base.origin;
    }
    return '(NAS 주소 미설정 — 설정에서 입력)';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final url = _url(state);
    final hasUrl = url.startsWith('http');

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('앱 접근 주소 · QR'),
        actions: const [AppHomeEmblem(size: 26)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
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
                            '한국범스카우트 중앙회\n인가자 관리 앱',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 26),
                    if (hasUrl)
                      QrImageView(
                        data: url,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.purple,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppColors.purpleDark,
                        ),
                      )
                    else
                      Container(
                        width: 220,
                        height: 220,
                        alignment: Alignment.center,
                        color: AppColors.purple.withValues(alpha: 0.06),
                        child: const Text(
                          '앱 주소가 설정되면\nQR이 표시됩니다',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textGray),
                        ),
                      ),
                    const SizedBox(height: 14),
                    SelectableText(
                      url,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.purple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '이 QR을 스캔하면 누구나 앱에 접속할 수 있습니다.\n최초 접속 시 비밀번호가 필요합니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: url));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('주소가 복사되었습니다')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('주소 복사'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              color: AppColors.purple.withValues(alpha: 0.05),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '접속 안내',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '• 앱 접근: 비밀번호는 관리자에게 문의 (1시간마다 재입력)',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '• 개인 접근: ID = 본인 인가번호  ·  비밀번호 = 인가번호 + !@@ (예: 000!@@)',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
