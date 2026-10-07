import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'marquee_text.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io' show File;

import '../services/file_save.dart';
import '../theme/app_theme.dart';

/// 인가자 사진을 PiP(작은 창)로 확대해 보여주고,
/// 「저장」 시 하단에 범 로고 + 인가번호 + ATAS번호 + 이름을 합성한 카드 JPG로 저장한다.
Future<void> showPhotoPip(
  BuildContext context, {
  required String name,
  required String number,
  required String atasNo,
  String league = '',
  String unit = '',
  Uint8List? photoBytes,
  String photoPath = '',
  String fallbackPhotoUrl = '',
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _PhotoPip(
      name: name,
      number: number,
      atasNo: atasNo,
      league: league,
      unit: unit,
      photoBytes: photoBytes,
      photoPath: photoPath,
      fallbackPhotoUrl: fallbackPhotoUrl,
    ),
  );
}

class _PhotoPip extends StatefulWidget {
  const _PhotoPip({
    required this.name,
    required this.number,
    required this.atasNo,
    required this.league,
    required this.unit,
    required this.photoBytes,
    required this.photoPath,
    required this.fallbackPhotoUrl,
  });

  final String name;
  final String number;
  final String atasNo;
  final String league;
  final String unit;
  final Uint8List? photoBytes;
  final String photoPath;

  /// photoPath 가 비어 있을 때 대신 쓸 서버 사진 URL(예: `/api/photo/1346`).
  ///  (요구: 사진 확대 시 파일이 있는데도 실루엣만 뜨던 문제 복원)
  final String fallbackPhotoUrl;

  @override
  State<_PhotoPip> createState() => _PhotoPipState();
}

class _PhotoPipState extends State<_PhotoPip> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _busy = false;
  Uint8List? _imgBytes;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  /// 사진 소스 정리 (data URI/base64 → 바이트, URL은 그대로 위젯에서 로드)
  /// 실제 사용할 사진 소스 — photoPath 우선, 없으면 서버 폴백 URL.
  String get _src {
    final p = widget.photoPath.trim();
    if (p.isNotEmpty) return p;
    return widget.fallbackPhotoUrl.trim();
  }

  Future<void> _resolveImage() async {
    final p = _src;
    try {
      if (widget.photoBytes != null && widget.photoBytes!.isNotEmpty) {
        _imgBytes = widget.photoBytes;
      } else if (p.startsWith('data:image')) {
        _imgBytes = base64Decode(p.split(',').last);
      } else if (p.isNotEmpty && !p.contains('/') && p.length > 200) {
        _imgBytes = base64Decode(p);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  bool get _hasPhoto =>
      (_imgBytes != null && _imgBytes!.isNotEmpty) ||
      _src.startsWith('http') ||
      (_src.isNotEmpty && _src.contains('/'));

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 저장될 카드 (캡처 대상)
            RepaintBoundary(key: _boundaryKey, child: _card()),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _btn(
                  icon: Icons.close,
                  label: '닫기',
                  bg: Colors.white24,
                  fg: Colors.white,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                _btn(
                  icon: Icons.download,
                  label: _busy ? '저장 중…' : '저장',
                  bg: AppColors.tigerGold,
                  fg: Colors.black87,
                  onTap: _busy ? null : _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card() {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.tigerGold, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 사진
          AspectRatio(
            aspectRatio: 1,
            child: _hasPhoto
                ? (_imgBytes != null
                      ? Image.memory(_imgBytes!, fit: BoxFit.cover)
                      : Image.network(
                          _src,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(),
                        ))
                : _placeholder(),
          ),
          // 하단 정보 밴드 (보라)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            color: AppColors.purple,
            child: Row(
              children: [
                // 범 로고
                Image.asset(
                  'assets/images/tsak_emblem.png',
                  width: 46,
                  height: 46,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.shield,
                    color: AppColors.tigerGold,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (widget.number.trim().isNotEmpty)
                            _tag('인가번호 ${widget.number}'),
                          if (widget.atasNo.trim().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _tag(
                              'ATAS ${widget.atasNo}',
                              color: AppColors.tigerGold,
                              dark: true,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      MarqueeText(
                        widget.name,
                        maxLines: 1,
                        style: const TextStyle(
                          fontFamily: 'NanumGothic',
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontSize: 19,
                        ),
                      ),
                      if ((widget.unit.isNotEmpty) ||
                          (widget.league.isNotEmpty))
                        MarqueeText(
                          [
                            widget.league,
                            widget.unit,
                          ].where((e) => e.isNotEmpty).join(' · '),
                          maxLines: 1,
                          style: const TextStyle(
                            fontFamily: 'NanumGothic',
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, {Color color = Colors.white, bool dark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: dark ? color : color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'NanumGothic',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: dark ? Colors.black87 : color,
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.purple.withValues(alpha: 0.15),
    alignment: Alignment.center,
    child: const Icon(Icons.person, color: Colors.white24, size: 120),
  );

  Widget _btn({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    VoidCallback? onTap,
  }) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final ratio = MediaQuery.of(context).devicePixelRatio.clamp(2.0, 4.0);
      final image = await boundary.toImage(pixelRatio: ratio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw '이미지 변환 실패';
      final png = byteData.buffer.asUint8List();
      final fname =
          'TSAK_${widget.number.isNotEmpty ? widget.number : widget.name}';
      if (!mounted) return;

      // 저장 위치·방법을 먼저 묻는다(공용 규칙) —
      //   요구: "사진 저장위치 선택창이 안나오니 이것도 조정해줘요".
      //   요구: "개인사진 다운시 아이폰은 기본폴더 오류가 있음.
      //        저장위치 지정 또는 외부앱, 내사진에 저장 같은 선택지가 필요함"
      //   · [위치 직접 선택] → 폴더/파일명 지정(크롬·엣지·안드로이드)
      //   · [공유·내보내기]  → 아이폰 「이미지 저장(사진 앱)」·외부앱·카톡·메일
      //   · [기본 폴더에 저장] → 다운로드(Downloads) 폴더로 바로 저장
      final opt = await askSaveOption(context, info: '$fname.png');
      if (opt == null) return; // 사용자 취소
      if (!mounted) return;

      // 웹: 선택한 방법/위치로 저장 / 모바일: 시스템 저장(실패 시 공유 시트)
      try {
        await saveFileOption(
          bytes: png,
          filename: '$fname.png',
          mime: 'image/png',
          mimeType: MimeType.png,
          option: opt,
        );
      } catch (_) {
        // 폴백: 임시 파일로 저장 후 공유 시트
        if (!kIsWeb) {
          final dir = await getTemporaryDirectory();
          final f = File('${dir.path}/$fname.png');
          await f.writeAsBytes(png);
          await Share.shareXFiles([XFile(f.path)], text: '${widget.name} 인가증');
        } else {
          rethrow;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 완료: $fname.png')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
