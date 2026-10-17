import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Celebration particles: leaves, petals and seeds instead of generic confetti.
/// Fires once when built (or whenever [trigger] changes).
class LeafBurst extends StatefulWidget {
  const LeafBurst({
    super.key,
    this.trigger = 0,
    this.count = 46,
    this.origin = const Alignment(0, -0.2),
    this.colors = const [C.leaf, C.grassDeep, C.sun, C.flame, C.petalPink, C.sky],
    this.power = 1,
  });

  final int trigger;
  final int count;
  final Alignment origin;
  final List<Color> colors;
  final double power;

  @override
  State<LeafBurst> createState() => _LeafBurstState();
}

class _P {
  _P(math.Random r, List<Color> colors, double power)
    : angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.5,
      speed = (380 + r.nextDouble() * 520) * power,
      spin = (r.nextDouble() - 0.5) * 14,
      rot0 = r.nextDouble() * math.pi * 2,
      size = 7 + r.nextDouble() * 9,
      color = colors[r.nextInt(colors.length)],
      shape = r.nextInt(3),
      wobble = r.nextDouble() * math.pi * 2;
  final double angle, speed, spin, rot0, size, wobble;
  final Color color;
  final int shape; // 0 leaf, 1 petal, 2 seed
}

class _LeafBurstState extends State<LeafBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  List<_P> _ps = [];

  @override
  void initState() {
    super.initState();
    _fire();
  }

  @override
  void didUpdateWidget(LeafBurst old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _fire();
  }

  void _fire() {
    final r = math.Random();
    _ps = List.generate(widget.count, (_) => _P(r, widget.colors, widget.power));
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(size: Size.infinite, painter: _BurstPainter(_ps, _c.value * 2.2, widget.origin)),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.ps, this.t, this.origin);
  final List<_P> ps;
  final double t; // seconds
  final Alignment origin;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 2.2) return;
    final o = origin.alongSize(size);
    const g = 900.0;
    for (final p in ps) {
      final drag = 1 - math.exp(-t * 2.2);
      final vx = math.cos(p.angle) * p.speed;
      final vy = math.sin(p.angle) * p.speed;
      final x = o.dx + vx * drag / 2.2 + math.sin(t * 5 + p.wobble) * 14 * t;
      final y = o.dy + vy * drag / 2.2 + 0.5 * g * t * t * 0.35;
      final fade = t > 1.5 ? (2.2 - t) / 0.7 : 1.0;
      final paint = Paint()..color = p.color.withValues(alpha: fade.clamp(0, 1));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rot0 + p.spin * t);
      final s = p.size;
      switch (p.shape) {
        case 0:
          final path = Path()
            ..moveTo(0, -s)
            ..quadraticBezierTo(s * 0.8, 0, 0, s)
            ..quadraticBezierTo(-s * 0.8, 0, 0, -s);
          canvas.drawPath(path, paint);
          canvas.drawLine(
            Offset(0, -s * 0.8),
            Offset(0, s * 0.8),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.35 * fade.clamp(0, 1))
              ..strokeWidth = 1.2,
          );
        case 1:
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: s * 1.1, height: s * 0.7), paint);
        default:
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s * 0.5, height: s * 0.9), Radius.circular(s)), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => true;
}
