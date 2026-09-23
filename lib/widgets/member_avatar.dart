import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 인가자 사진 아바타 — 사진이 없으면 이름 첫 글자를 이니셜로 표시
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    this.photoPath = '',
    this.size = 52,
    this.league = '',
  });

  final String name;
  final String photoPath;
  final double size;
  final String league;

  @override
  Widget build(BuildContext context) {
    final border = leagueColor(league);

    Widget child;
    if (photoPath.isNotEmpty) {
      child = _buildImage();
    } else {
      child = Container(
        color: border.withValues(alpha: 0.15),
        alignment: Alignment.center,
        child: Text(
          _initial(name),
          style: TextStyle(
            color: border,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.4,
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
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
