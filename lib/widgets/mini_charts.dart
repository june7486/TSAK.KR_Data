import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 의존성 없는 미니 막대 그래프
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.data,
    this.height = 150,
    this.color = AppColors.purple,
    this.valueFormatter,
    this.maxBars = 12,
  });

  final Map<String, int> data;
  final double height;
  final Color color;
  final String Function(int)? valueFormatter;
  final int maxBars;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            '데이터 없음',
            style: TextStyle(color: AppColors.textGray, fontSize: 12),
          ),
        ),
      );
    }
    final entries = data.entries.toList();
    final trimmed = entries.length > maxBars
        ? entries.sublist(entries.length - maxBars)
        : entries;
    final maxV = trimmed
        .map((e) => e.value.abs())
        .fold<int>(0, (a, b) => a > b ? a : b);
    final fmt = valueFormatter ?? _defaultFmt;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in trimmed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      fmt(e.value),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Flexible(
                      child: FractionallySizedBox(
                        heightFactor: maxV == 0
                            ? 0
                            : (e.value.abs() / maxV).clamp(0.02, 1.0),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [color, color.withValues(alpha: 0.55)],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _defaultFmt(int v) {
    if (v.abs() >= 100000000) {
      return '${(v / 100000000).toStringAsFixed(1)}억';
    }
    if (v.abs() >= 10000) {
      return '${(v / 10000).toStringAsFixed(0)}만';
    }
    return '$v';
  }
}

/// 도넛(파이) 그래프 — 분류 비중
class MiniDonut extends StatelessWidget {
  const MiniDonut({
    super.key,
    required this.data,
    this.size = 150,
    this.colors = const [
      AppColors.purple,
      AppColors.taegeukRed,
      AppColors.tigerGold,
      AppColors.scoutGreen,
      AppColors.taegeukBlue,
      Color(0xFF00838F),
      Color(0xFF6D4C41),
    ],
  });

  final Map<String, int> data;
  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    if (total == 0) {
      return SizedBox(
        height: size,
        child: const Center(
          child: Text(
            '데이터 없음',
            style: TextStyle(color: AppColors.textGray, fontSize: 12),
          ),
        ),
      );
    }
    return SizedBox(
      height: size,
      child: Row(
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _DonutPainter(entries, total, colors),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _short(total),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textDark,
                      ),
                    ),
                    const Text(
                      '합계(원)',
                      style: TextStyle(fontSize: 9, color: AppColors.textGray),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < entries.length && i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colors[i % colors.length],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entries[i].key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        Text(
                          '${(entries[i].value / total * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textGray,
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

  static String _short(int v) {
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(1)}억';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(0)}만';
    return '$v';
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.entries, this.total, this.colors);
  final List<MapEntry<String, int>> entries;
  final int total;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const stroke = 18.0;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);
    var start = -1.5708; // -90deg
    for (var i = 0; i < entries.length; i++) {
      final sweep = entries[i].value / total * 6.28318;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.entries != entries || old.total != total;
}

/// 가로 막대 (인가자별 TOP 등)
class MiniRankBar extends StatelessWidget {
  const MiniRankBar({
    super.key,
    required this.label,
    required this.value,
    required this.maxValue,
    this.color = AppColors.purple,
    this.trailing,
  });

  final String label;
  final int value;
  final int maxValue;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: maxValue == 0 ? 0 : (value / maxValue).clamp(0.0, 1.0),
                minHeight: 12,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 78,
            child: Text(
              trailing ?? '${value ~/ 10000}만',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
