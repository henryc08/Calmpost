import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// App background: the sage paper with faint topographic contour lines, so it
/// feels like terrain rather than a flat fill. Static, painted once.
class TopoBackdrop extends StatelessWidget {
  const TopoBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: ColoredBox(
        color: C.paper,
        child: CustomPaint(painter: _TopoPainter(), size: Size.infinite),
      ),
    );
  }
}

class _TopoPainter extends CustomPainter {
  const _TopoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = C.ink.withValues(alpha: 0.055);

    // Two "hills" of nested contours, offset so lines drift across the page.
    void hill(Offset centre, double base, int rings, double seed) {
      for (var i = 0; i < rings; i++) {
        final r = base + i * 26.0;
        final path = Path();
        const steps = 96;
        for (var s = 0; s <= steps; s++) {
          final a = s / steps * math.pi * 2;
          final wobble = 1 + 0.09 * math.sin(a * 3 + seed + i * 0.35) + 0.05 * math.sin(a * 5 - seed * 1.7 + i * 0.2);
          final p = centre + Offset(math.cos(a) * r * 1.25 * wobble, math.sin(a) * r * wobble);
          s == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path..close(), paint);
      }
    }

    hill(Offset(size.width * 0.95, size.height * 0.12), 30, 16, 0.6);
    hill(Offset(-size.width * 0.05, size.height * 0.78), 40, 18, 2.1);
  }

  @override
  bool shouldRepaint(_TopoPainter old) => false;
}
