import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'scout_silhouette.dart';

/// 인가자 사진 아바타 — 사진이 없으면 이름 첫 글자를 이니셜로 표시
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    this.photoPath = '',
    this.size = 52,
    this.league = '',
    this.number = '',
    this.showNumber = true,
    this.square = false,
  });

  final String name;
  final String photoPath;
  final double size;
  final String league;

  /// 인가번호 — 사진이 없을 때 동그라미 안에 표시
  final String number;

  /// false면 사진이 없을 때 번호 대신 회색 실루엣 표시
  final bool showNumber;

  /// true면 사각형(라운드) 프레임
  final bool square;

  @override
  Widget build(BuildContext context) {
    final border = leagueColor(league);

    Widget child;
    if (photoPath.isNotEmpty) {
      child = _buildImage();
    } else if (!showNumber) {
      // 사진 없음 → 회색 스카우트 실루엣 (배낭 + 로빙햇)
      child = ScoutSilhouette(size: size);
    } else {
      // 글자(이니셜) 대신 인가번호를 표시
      final label = number.trim().isNotEmpty ? number.trim() : _initial(name);
      final isNumber = number.trim().isNotEmpty;
      child = Container(
        color: border.withValues(alpha: 0.15),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.12),
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: border,
                fontWeight: FontWeight.w800,
                fontSize: size * (isNumber ? 0.42 : 0.4),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(size * 0.14) : null,
        border: Border.all(color: border, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildImage() {
    // base64 data URI
    if (photoPath.startsWith('data:image') ||
        (photoPath.length > 200 && !photoPath.contains('/'))) {
      try {
        final base64Part = photoPath.contains(',')
            ? photoPath.split(',').last
            : photoPath;
        final bytes = base64Decode(base64Part);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      } catch (_) {
        return _fallback();
      }
    }
    if (kIsWeb) {
      return Image.network(
        photoPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    try {
      return Image.file(
        File(photoPath),
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    } catch (_) {
      return _fallback();
    }
  }

  Widget _fallback() => Container(
    color: AppColors.purple.withValues(alpha: 0.12),
    alignment: Alignment.center,
    child: Icon(Icons.person, color: AppColors.purple, size: size * 0.5),
  );

  String _initial(String n) {
    final t = n.trim();
    if (t.isEmpty) return '?';
    return t.characters.first;
  }
}
