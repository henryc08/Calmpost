import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models.dart' show WrenMood;
import '../tokens.dart';

export '../../domain/models.dart' show WrenMood;

/// Cosmetic hats bought with Seeds.
enum WrenHat { none, sprout, straw, beanie, flowers }

/// Wren the worm: the mascot. Hand-drawn with a CustomPainter so every mood,
/// hat and wiggle is ours.
class Wren extends StatefulWidget {
  const Wren({super.key, this.mood = WrenMood.happy, this.size = 140, this.hat = WrenHat.none, this.ground = false, this.excited = false, this.tail = 0});

  final WrenMood mood;

  /// Extra body length below the box (in 1/100ths of size), for poking out of soil.
  final double tail;
  final double size;
  final WrenHat hat;

  /// Draws a little soil mound Wren pokes out of.
  final bool ground;

  /// Bigger, bouncier animation for celebrations.
  final bool excited;

  @override
  State<Wren> createState() => _WrenState();
}

class _WrenState extends State<Wren> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  void _scheduleBlink() {
    Future.delayed(Duration(milliseconds: 1800 + _rand.nextInt(2800)), () async {
      if (!mounted) return;
      await _blink.forward();
      if (!mounted) return;
      await _blink.reverse();
      if (mounted) _scheduleBlink();
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_loop, _blink]),
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: WrenPainter(
            mood: widget.mood,
            t: _loop.value,
            blink: _blink.value,
            hat: widget.hat,
            ground: widget.ground,
            excited: widget.excited,
            tail: widget.tail,
          ),
        ),
      ),
    );
  }
}

class WrenPainter extends CustomPainter {
  WrenPainter({required this.mood, required this.t, this.blink = 0, this.hat = WrenHat.none, this.ground = false, this.excited = false, this.tail = 0});

  final WrenMood mood;
  final double t;
  final double blink;
  final WrenHat hat;
  final bool ground;
  final bool excited;
  final double tail;

  static const _sick = Color(0xFFCBD89C);
  static const _dry = Color(0xFFE9B9A2);

  Color get _body => switch (mood) {
    WrenMood.sick => Color.lerp(C.worm, _sick, 0.6)!,
    WrenMood.thirsty => Color.lerp(C.worm, _dry, 0.55)!,
    _ => C.worm,
  };

  Color get _shade => switch (mood) {
    WrenMood.sick => Color.lerp(C.wormShade, const Color(0xFFA9BC72), 0.6)!,
    WrenMood.thirsty => Color.lerp(C.wormShade, const Color(0xFFCB967D), 0.55)!,
    _ => C.wormShade,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 100;
    canvas.save();
    canvas.scale(k);

    final phase = t * math.pi * 2;
    final energy = excited
        ? 1.6
        : switch (mood) {
            WrenMood.thriving => 1.2,
            WrenMood.happy => 1.0,
            WrenMood.okay => 0.7,
            WrenMood.soggy => 0.55,
            WrenMood.thirsty => 0.4,
            WrenMood.sick => 0.3,
          };
    final sway = math.sin(phase) * 7 * energy;
    final bob = excited || mood == WrenMood.thriving ? -math.max(0, math.sin(phase * 2)) * 6 * energy : 0.0;
    final droop = mood == WrenMood.thirsty || mood == WrenMood.sick ? 9.0 : (mood == WrenMood.soggy ? 4.0 : 0.0);

    final base = Offset(50, 104 + tail);
    final head = Offset(50 + sway + (droop > 0 ? 6 : 0), 36 + bob + droop);

    if (ground) {
      canvas.save();
      canvas.clipRect(const Rect.fromLTWH(-50, -50, 200, 152));
    }

    // Body: a thick tube in two tones.
    final body = Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(base.dx - sway * 0.4, 86 + tail * 0.5, head.dx - sway * 0.9 - 6, 62 + bob * 0.5, head.dx, head.dy + 8);
    final w = 25.0;
    canvas.drawPath(
      body.shift(const Offset(2.2, 0)),
      Paint()
        ..color = _shade
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      body.shift(const Offset(-1, 0)),
      Paint()
        ..color = _body
        ..style = PaintingStyle.stroke
        ..strokeWidth = w - 4
        ..strokeCap = StrokeCap.round,
    );

    // Segment rings along the body.
    final ringPaint = Paint()
      ..color = (mood == WrenMood.sick ? const Color(0xFFDDE6B8) : C.wormRing)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (final m in body.computeMetrics()) {
      for (var d = 22.0; d < m.length - 14; d += 10) {
        final tan = m.getTangentForOffset(d)!;
        final n = Offset(-tan.vector.dy, tan.vector.dx);
        final c = tan.position + const Offset(-1, 0);
        final a = c + n * 8;
        final b = c - n * 8;
        final ctrl = c + tan.vector * 2.5;
        canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy),
          ringPaint,
        );
      }
    }

    if (ground) {
      canvas.restore();
      _paintGround(canvas);
    }

    // Head.
    final tilt = (droop > 0 ? 0.18 : 0.0) + math.sin(phase) * 0.05 * energy;
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(tilt);
    canvas.drawCircle(const Offset(2, 1.5), 19, Paint()..color = _shade);
    canvas.drawCircle(Offset.zero, 18.5, Paint()..color = _body);
    canvas.drawOval(Rect.fromCenter(center: const Offset(-7, -9), width: 12, height: 7), Paint()..color = Colors.white.withValues(alpha: 0.32));

    _paintFace(canvas);
    _paintHat(canvas);
    canvas.restore();

    _paintExtras(canvas, head, phase);
    canvas.restore();
  }

  void _paintGround(Canvas canvas) {
    final mound = Path()
      ..moveTo(14, 104)
      ..quadraticBezierTo(18, 88, 50, 87)
      ..quadraticBezierTo(82, 88, 86, 104)
      ..close();
    canvas.drawPath(mound, Paint()..color = C.soil);
    canvas.drawPath(
      Path()
        ..moveTo(22, 96)
        ..quadraticBezierTo(50, 86, 78, 96),
      Paint()
        ..color = C.soilLip
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final speck = Paint()..color = C.soilDeep.withValues(alpha: 0.6);
    for (final o in const [Offset(30, 97), Offset(42, 93), Offset(61, 95), Offset(70, 99), Offset(52, 100)]) {
      canvas.drawCircle(o, 1.4, speck);
    }
    canvas.drawCircle(const Offset(36, 91), 1.6, Paint()..color = C.leaf);
  }

  void _paintFace(Canvas canvas) {
    final ink = Paint()..color = C.ink;
    final white = Paint()..color = Colors.white;
    final halfLid = mood == WrenMood.thirsty || mood == WrenMood.sick;
    final open = (1 - blink).clamp(0.08, 1.0);

    // Cheeks
    if (mood != WrenMood.sick) {
      final cheek = Paint()..color = C.wormCheek.withValues(alpha: 0.55);
      canvas.drawOval(Rect.fromCenter(center: const Offset(-12.5, 6), width: 7, height: 4.5), cheek);
      canvas.drawOval(Rect.fromCenter(center: const Offset(12.5, 6), width: 7, height: 4.5), cheek);
    }

    for (final sx in const [-7.0, 7.0]) {
      final c = Offset(sx, -2);
      if (mood == WrenMood.thriving && blink < 0.5) {
        // Big sparkly eyes.
        canvas.drawOval(Rect.fromCenter(center: c, width: 10.5, height: 12.5 * open), white);
        canvas.drawOval(Rect.fromCenter(center: c + const Offset(0.6, 1), width: 7, height: 8.5 * open), ink);
        canvas.drawCircle(c + const Offset(-1.2, -1.8), 1.9, white);
        canvas.drawCircle(c + const Offset(1.8, 2), 0.9, white);
      } else {
        canvas.drawOval(Rect.fromCenter(center: c, width: 9.5, height: 11 * open), white);
        canvas.drawOval(Rect.fromCenter(center: c + const Offset(0.5, 1), width: 6, height: 7 * open), ink);
        canvas.drawCircle(c + const Offset(-1, -1.4), 1.5, white);
      }
      if (halfLid) {
        // Heavy upper lid.
        final lid = Path()
          ..addArc(Rect.fromCenter(center: c, width: 11, height: 12.5), math.pi, math.pi)
          ..close();
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(c.dx - 6, c.dy - 7, 12, 6.4));
        canvas.drawPath(lid, Paint()..color = _body);
        canvas.restore();
        canvas.drawLine(
          c + const Offset(-5, -0.8),
          c + const Offset(5, -0.8),
          Paint()
            ..color = _shade
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Brows for worried moods.
    if (mood == WrenMood.soggy || mood == WrenMood.sick) {
      final brow = Paint()
        ..color = C.soilDeep
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(-10.5, -10.5), const Offset(-4.5, -12.5), brow);
      canvas.drawLine(const Offset(10.5, -10.5), const Offset(4.5, -12.5), brow);
    }

    // Mouth.
    final mouth = Paint()
      ..color = C.soilDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    switch (mood) {
      case WrenMood.thriving:
        final p = Path()
          ..moveTo(-6, 6.5)
          ..quadraticBezierTo(0, 15, 6, 6.5)
          ..close();
        canvas.drawPath(p, Paint()..color = const Color(0xFF8C3B36));
        canvas.save();
        canvas.clipPath(p);
        canvas.drawCircle(const Offset(0, 13), 4, Paint()..color = const Color(0xFFFF8F8F));
        canvas.restore();
      case WrenMood.happy:
        canvas.drawPath(
          Path()
            ..moveTo(-5, 7)
            ..quadraticBezierTo(0, 12, 5, 7),
          mouth,
        );
      case WrenMood.okay:
        canvas.drawPath(
          Path()
            ..moveTo(-3.5, 8)
            ..quadraticBezierTo(0, 10, 3.5, 8),
          mouth,
        );
      case WrenMood.thirsty:
        canvas.drawOval(Rect.fromCenter(center: const Offset(0, 9), width: 5.5, height: 4.5), Paint()..color = const Color(0xFF8C3B36));
        canvas.drawOval(Rect.fromCenter(center: const Offset(1, 11.5), width: 4, height: 3.6), Paint()..color = const Color(0xFFFF8F8F));
      case WrenMood.soggy:
      case WrenMood.sick:
        canvas.drawPath(
          Path()
            ..moveTo(-5, 9)
            ..quadraticBezierTo(-2.5, 6.5, 0, 9)
            ..quadraticBezierTo(2.5, 11.5, 5, 9),
          mouth,
        );
    }
  }

  void _paintHat(Canvas canvas) {
    switch (hat) {
      case WrenHat.none:
        return;
      case WrenHat.sprout:
        final stem = Paint()
          ..color = C.stem
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(
          Path()
            ..moveTo(0, -18)
            ..quadraticBezierTo(1, -24, 0, -28),
          stem,
        );
        final leaf = Paint()..color = C.leaf;
        canvas.drawPath(
          Path()
            ..moveTo(0, -27)
            ..quadraticBezierTo(-10, -34, -13, -26)
            ..quadraticBezierTo(-6, -22, 0, -27),
          leaf,
        );
        canvas.drawPath(
          Path()
            ..moveTo(0, -27)
            ..quadraticBezierTo(9, -37, 14, -29)
            ..quadraticBezierTo(7, -23, 0, -27),
          Paint()..color = C.grassDeep,
        );
      case WrenHat.straw:
        canvas.drawOval(Rect.fromCenter(center: const Offset(0, -15), width: 46, height: 10), Paint()..color = const Color(0xFFD9A441));
        canvas.drawOval(Rect.fromCenter(center: const Offset(0, -16), width: 42, height: 7), Paint()..color = const Color(0xFFF2C866));
        final crown = RRect.fromRectAndCorners(const Rect.fromLTWH(-12, -28, 24, 13), topLeft: const Radius.circular(9), topRight: const Radius.circular(9));
        canvas.drawRRect(crown, Paint()..color = const Color(0xFFF2C866));
        canvas.drawRect(const Rect.fromLTWH(-12, -19.5, 24, 3.5), Paint()..color = C.coral);
      case WrenHat.beanie:
        final cap = Path()
          ..moveTo(-17, -9)
          ..quadraticBezierTo(-16, -30, 0, -30)
          ..quadraticBezierTo(16, -30, 17, -9)
          ..close();
        canvas.drawPath(cap, Paint()..color = C.flame);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-18.5, -13, 37, 7), const Radius.circular(4)), Paint()..color = C.flameLip);
        final rib = Paint()
          ..color = C.flameLip.withValues(alpha: 0.5)
          ..strokeWidth = 1.4;
        for (var x = -10.0; x <= 10; x += 5) {
          canvas.drawLine(Offset(x, -14), Offset(x * 0.7, -26), rib);
        }
        canvas.drawCircle(const Offset(0, -31), 5, Paint()..color = C.sun);
      case WrenHat.flowers:
        for (final (i, o) in const [Offset(-11, -14), Offset(0, -18.5), Offset(11, -14)].indexed) {
          final petal = Paint()..color = i == 1 ? C.sun : C.petalPink;
          for (var a = 0; a < 5; a++) {
            final ang = a * math.pi * 2 / 5;
            canvas.drawCircle(o + Offset(math.cos(ang), math.sin(ang)) * 3.6, 2.8, petal);
          }
          canvas.drawCircle(o, 2.2, Paint()..color = i == 1 ? C.flame : C.sun);
        }
    }
  }

  void _paintExtras(Canvas canvas, Offset head, double phase) {
    switch (mood) {
      case WrenMood.thriving:
        final p = Paint()..color = C.sun;
        for (final (i, o) in const [Offset(-26, -16), Offset(27, -10), Offset(22, -28)].indexed) {
          final s = 0.6 + 0.4 * math.sin(phase * 2 + i * 1.7).abs();
          _sparkle(canvas, head + o, 5.5 * s, p);
        }
      case WrenMood.soggy:
        final drop = Paint()..color = C.sky;
        for (final (i, o) in const [Offset(-20, -18), Offset(19, -24), Offset(25, -6)].indexed) {
          final fall = ((phase / (math.pi * 2) + i * 0.33) % 1) * 10;
          _drop(canvas, head + o + Offset(0, fall), 3.6, drop);
        }
      case WrenMood.thirsty:
        final puff = Paint()..color = C.soilTint;
        final d = (phase / (math.pi * 2)) % 1;
        canvas.drawCircle(head + Offset(22 + d * 6, 4 - d * 6), 3 + d * 2, puff..color = C.borderDark.withValues(alpha: 1 - d));
        canvas.drawCircle(head + Offset(-24 - d * 4, 10 - d * 4), 2 + d * 2, puff..color = C.borderDark.withValues(alpha: (1 - d) * 0.8));
      case WrenMood.sick:
        final z = Paint()
          ..color = C.muted
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        final d = (phase / (math.pi * 2)) % 1;
        final o = head + Offset(20 + d * 4, -22 - d * 8);
        canvas.drawPath(
          Path()
            ..moveTo(o.dx, o.dy)
            ..lineTo(o.dx + 5, o.dy)
            ..lineTo(o.dx, o.dy + 5)
            ..lineTo(o.dx + 5, o.dy + 5),
          z..color = C.muted.withValues(alpha: 1 - d),
        );
      default:
        break;
    }
  }

  void _sparkle(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    canvas.drawPath(path, p);
  }

  void _drop(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r * 1.8)
      ..quadraticBezierTo(c.dx + r, c.dy - r * 0.2, c.dx + r, c.dy + r * 0.3)
      ..arcToPoint(Offset(c.dx - r, c.dy + r * 0.3), radius: Radius.circular(r))
      ..quadraticBezierTo(c.dx - r, c.dy - r * 0.2, c.dx, c.dy - r * 1.8);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(WrenPainter old) => true;
}
