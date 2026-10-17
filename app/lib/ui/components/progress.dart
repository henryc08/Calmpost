import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';

/// Duolingo-style progress bar: chunky track, fill with a highlight stripe.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.color = C.leaf, this.height = 16, this.label});
  final double value;
  final Color color;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: v),
      duration: M.slow,
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final fillW = t <= 0 ? 0.0 : math.max(height, w * t);
          return SizedBox(
            height: height,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(color: C.track, borderRadius: BorderRadius.circular(height)),
                ),
                if (fillW > 0)
                  Container(
                    width: fillW,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: EdgeInsets.fromLTRB(height * 0.4, height * 0.22, height * 0.4, 0),
                        height: height * 0.22,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(height)),
                      ),
                    ),
                  ),
                if (label != null)
                  Center(
                    child: Text(
                      label!,
                      style: T.small.copyWith(fontSize: 11, color: t > 0.45 ? Colors.white : C.muted, fontWeight: FontWeight.w900),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Ring gauge with round caps, animated.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 120, this.stroke = 12, this.color = C.leaf, this.track = C.track, this.child});

  final double value;
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(t, stroke, color, track),
          child: Center(child: child),
        ),
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.stroke, this.color, this.track);
  final double t;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, p..color = track);
    if (t > 0) {
      canvas.drawArc(r, -math.pi / 2, math.pi * 2 * t, false, p..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.color != color;
}

/// Animated integer count-up.
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, required this.style, this.prefix = '', this.suffix = '', this.duration = const Duration(milliseconds: 900), this.from});
  final int value;
  final int? from;
  final TextStyle style;
  final String prefix;
  final String suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: (from ?? value).toDouble(), end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$prefix${v.round()}$suffix', style: style),
    );
  }
}
