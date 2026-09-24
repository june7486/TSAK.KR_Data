import 'package:flutter/material.dart';

/// 사진이 없을 때 표시하는 회색 스카우트 실루엣
/// (배낭을 메고 로빙햇(ranger hat)을 쓴 정면 인물)
class ScoutSilhouette extends StatelessWidget {
  const ScoutSilhouette({super.key, required this.size, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF9AA0A6);
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFEDEEF0),
      alignment: Alignment.center,
      child: CustomPaint(
        size: Size(size * 0.82, size * 0.82),
        painter: _ScoutPainter(c),
      ),
    );
  }
}

class _ScoutPainter extends CustomPainter {
  _ScoutPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // 비율 좌표 (0~1) → 실제 크기
    Offset pt(double x, double y) => Offset(x * w, y * h);

    // 1) 로빙햇 (ranger hat) — 넓은 챙 + 높은 크라운
    final hat = Path()
      ..moveTo(0.16 * w, 0.30 * h)
      ..quadraticBezierTo(cx, 0.18 * h, 0.84 * w, 0.30 * h)
      ..quadraticBezierTo(cx, 0.36 * h, 0.16 * w, 0.30 * h)
      ..close();
    canvas.drawPath(hat, p);
    // 크라운
    final crown = Path()
      ..moveTo(0.34 * w, 0.30 * h)
      ..lineTo(0.36 * w, 0.15 * h)
      ..quadraticBezierTo(cx, 0.08 * h, 0.64 * w, 0.15 * h)
      ..lineTo(0.66 * w, 0.30 * h)
      ..close();
    canvas.drawPath(crown, p);
    // 크라운 밴드(약간 진하게)
    final bandPaint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTRB(0.35 * w, 0.255 * h, 0.65 * w, 0.295 * h),
      bandPaint,
    );

    // 2) 얼굴 (원형)
    canvas.drawCircle(Offset(cx, 0.40 * h), 0.16 * w, p);

    // 3) 어깨 + 몸통
    final body = Path()
      ..moveTo(0.30 * w, 0.60 * h)
      ..quadraticBezierTo(cx, 0.50 * h, 0.70 * w, 0.60 * h)
      ..lineTo(0.74 * w, 0.86 * h)
      ..lineTo(0.26 * w, 0.86 * h)
      ..close();
    canvas.drawPath(body, p);

    // 4) 배낭 (어깨 뒤 위쪽, 양옆으로 살짝 보이게) — 좌우 실루엣
    final packL = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(0.20 * w, 0.50 * h, 0.31 * w, 0.72 * h),
        Radius.circular(0.05 * w),
      ));
    final packR = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(0.69 * w, 0.50 * h, 0.80 * w, 0.72 * h),
        Radius.circular(0.05 * w),
      ));
    canvas.drawPath(packL, p);
    canvas.drawPath(packR, p);
    // 배낭 어깨끈 (몸통 위 얇은 선)
    final strap = Paint()
      ..color = const Color(0xFFEDEEF0)
      ..strokeWidth = 0.03 * w
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pt(0.40, 0.58), pt(0.44, 0.80), strap);
    canvas.drawLine(pt(0.60, 0.58), pt(0.56, 0.80), strap);
    // 배낭 상단 손잡이
    canvas.drawLine(pt(0.20, 0.52), pt(0.80, 0.52), Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 0.015 * w);
  }

  @override
  bool shouldRepaint(covariant _ScoutPainter old) => old.color != color;
}
