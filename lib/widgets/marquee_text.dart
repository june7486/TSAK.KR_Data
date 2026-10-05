import 'package:flutter/material.dart';

/// 넘칠 때만 좌우로 흐르는(마퀴) 텍스트.
///
/// 요구(사용자): "메뉴에서 글자가 짤리면 글자를 슬라이딩 해줘 (우측으로 흐리는
/// 글자, 무한 반복)".
///
/// 동작:
///  - 주어진 폭에 글자가 **다 들어가면** 아무 움직임 없이 정적으로 표시.
///  - 폭을 **넘치면** 글자가 우측→좌측으로 천천히 흐르고, 끝에서 잠시 멈췄다가
///    처음부터 다시 무한 반복한다(끊김 없이 이어지도록 동일 문구 2개를 이어 붙임).
///  - 위젯이 화면 밖에 있으면(TickerMode 비활성) 애니메이션이 자동 정지한다.
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.velocity = 26,
    this.pause = const Duration(milliseconds: 1400),
    this.gap = 32,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle? style;

  /// 흐르는 속도(초당 픽셀). 작을수록 천천히.
  final double velocity;

  /// 한 바퀴 끝에서 다시 시작하기 전 멈춤 시간.
  final Duration pause;

  /// 반복될 때 문구와 문구 사이 간격(픽셀).
  final double gap;

  final int maxLines;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _travelFrac = 1.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _measureText(String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: widget.style),
      maxLines: widget.maxLines,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  double _textHeight() {
    final tp = TextPainter(
      text: TextSpan(text: '가', style: widget.style),
      maxLines: widget.maxLines,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.height;
  }

  /// 넘칠 때 애니메이션 준비(속도·주기 계산 후 반복 시작).
  void _ensureRunning(double textWidth) {
    final cycleDist = textWidth + widget.gap;
    if (cycleDist <= 0) return;
    final travelMs = (cycleDist / widget.velocity * 1000)
        .clamp(700.0, 30000.0)
        .toDouble();
    final cycleMs = travelMs + widget.pause.inMilliseconds;
    _travelFrac = travelMs / cycleMs;
    final dur = Duration(milliseconds: cycleMs.round());
    if (!_ctrl.isAnimating) {
      if (_ctrl.duration != dur) _ctrl.duration = dur;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_ctrl.isAnimating) _ctrl.repeat();
      });
    }
  }

  void _ensureStopped() {
    if (_ctrl.isAnimating) _ctrl.stop();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewWidth = constraints.maxWidth;
        // 폭이 무한(제약 없음)이면 흐를 필요 없음 → 정적 표시.
        if (!viewWidth.isFinite || viewWidth <= 0) {
          _ensureStopped();
          return Text(
            widget.text,
            style: widget.style,
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
          );
        }
        final textWidth = _measureText(widget.text);
        final overflows = textWidth > viewWidth + 0.5;
        if (!overflows) {
          _ensureStopped();
          return Text(
            widget.text,
            style: widget.style,
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
          );
        }

        _ensureRunning(textWidth);
        final cycleDist = textWidth + widget.gap;
        final lineHeight = _textHeight();

        return SizedBox(
          height: lineHeight,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final t = _ctrl.value; // 0..1
                final double offset;
                if (t < _travelFrac) {
                  // 흐르는 구간
                  final p = _travelFrac == 0 ? 0.0 : t / _travelFrac;
                  offset = -(p * cycleDist);
                } else {
                  // 끝에서 잠시 멈춤(두 번째 문구가 시작 위치에 와 있어 자연스럽게 이어짐)
                  offset = -cycleDist;
                }
                return OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  minWidth: 0,
                  child: Transform.translate(
                    offset: Offset(offset, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _fixedText(),
                        SizedBox(width: widget.gap),
                        _fixedText(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _fixedText() => Text(
    widget.text,
    style: widget.style,
    maxLines: widget.maxLines,
    softWrap: false,
    overflow: TextOverflow.visible,
  );
}
