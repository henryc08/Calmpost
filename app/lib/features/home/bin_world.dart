import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../ui/tokens.dart';

/// The hero: a living cross-section of the bin inside a circle, Flora-style.
///
/// - The plant on the horizon grows with the batch and wilts when health drops.
/// - The two soil layers are the real top and bottom layers; CO₂ rises as
///   bubbles, rain falls when it's too wet, cracks show when it's too dry.
/// - The bezel ring around it is the health score, like a game gauge.
/// - The sky follows the time of day (stars and fireflies at night).
class BinWorld extends StatefulWidget {
  const BinWorld({super.key, required this.score, required this.mood, required this.growth, required this.co2, this.size = 300});

  final int score;
  final BinMood mood;

  /// Batch progress 0..1 (plant size).
  final double growth;
  final double co2;
  final double size;

  /// Web preview override (`?hour=14`) to review day/dusk/night skies.
  static double? debugHour;

  @override
  State<BinWorld> createState() => _BinWorldState();
}

class _BinWorldState extends State<BinWorld> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();

  @override
  void dispose() {
    _loop.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.score.toDouble()),
        duration: const Duration(milliseconds: 1200),
        curve: M.ease,
        builder: (context, score, _) => AnimatedBuilder(
          animation: Listenable.merge([_loop, _intro]),
          builder: (context, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _WorldPainter(
              t: _loop.value * 12,
              intro: Curves.easeOutCubic.transform(_intro.value),
              score: score,
              mood: widget.mood,
              growth: widget.growth,
              co2: widget.co2,
              hour: BinWorld.debugHour ?? DateTime.now().hour + DateTime.now().minute / 60,
            ),
          ),
        ),
      ),
    );
  }
}

class _WorldPainter extends CustomPainter {
  _WorldPainter({required this.t, required this.intro, required this.score, required this.mood, required this.growth, required this.co2, required this.hour});

  final double t; // seconds
  final double intro; // 0..1
  final double score;
  final BinMood mood;
  final double growth;
  final double co2;
  final double hour;

  bool get night => hour < 6.5 || hour >= 19.5;
  bool get dusk => !night && (hour >= 17.5 || hour < 8);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.37;
    _bezel(canvas, c, r);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    final horizon = c.dy + r * 0.12;
    _sky(canvas, c, r, horizon);
    _hills(canvas, c, r, horizon);
    _soil(canvas, c, r, horizon);
    _plant(canvas, Offset(c.dx, horizon), r);
    _weather(canvas, c, r, horizon);
    _motes(canvas, c, r, horizon);
    canvas.restore();

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = C.ink.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  // ── Bezel: watch-style ticks + the health arc ───────────────────────────
  void _bezel(Canvas canvas, Offset c, double r) {
    final ringR = r + 16;
    final tick = Paint()
      ..color = C.line
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 100; i += 2) {
      final a = -math.pi / 2 + i / 100 * math.pi * 2;
      final major = i % 10 == 0;
      final d = Offset(math.cos(a), math.sin(a));
      final lit = i <= score * intro;
      tick.color = lit ? C.forest.withValues(alpha: major ? 0.9 : 0.45) : C.line;
      tick.strokeWidth = major ? 1.8 : 1.2;
      canvas.drawLine(c + d * (ringR - (major ? 7 : 4)), c + d * (ringR + (major ? 2 : 0)), tick);
    }
    final sweep = math.pi * 2 * (score / 100) * intro;
    final arc = Rect.fromCircle(center: c, radius: ringR + 9);
    canvas.drawArc(
      arc,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = C.sunk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawArc(
      arc,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = C.forest
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    // Marker at the end of the arc, with a slow pulse.
    final end = -math.pi / 2 + sweep;
    final m = c + Offset(math.cos(end), math.sin(end)) * (ringR + 9);
    final pulse = (t % 2) / 2;
    canvas.drawCircle(m, 6 + pulse * 8, Paint()..color = C.sprout.withValues(alpha: 0.5 * (1 - pulse) * intro));
    canvas.drawCircle(m, 6, Paint()..color = C.forest);
    canvas.drawCircle(m, 3, Paint()..color = C.sprout);
  }

  // ── Sky ─────────────────────────────────────────────────────────────────
  void _sky(Canvas canvas, Offset c, double r, double horizon) {
    final (top, low) = night
        ? (const Color(0xFF1B2A24), const Color(0xFF25392F))
        : dusk
        ? (const Color(0xFFE9D6C2), const Color(0xFFF1E4D2))
        : (const Color(0xFFDDE9E1), const Color(0xFFEAF1EB));
    final skyRect = Rect.fromLTRB(c.dx - r, c.dy - r, c.dx + r, horizon);
    // Two flat bands, no gradient.
    canvas.drawRect(skyRect, Paint()..color = top);
    canvas.drawRect(Rect.fromLTRB(skyRect.left, horizon - r * 0.35, skyRect.right, horizon), Paint()..color = low);

    if (night) {
      final rand = math.Random(11);
      for (var i = 0; i < 26; i++) {
        final p = Offset(c.dx - r + rand.nextDouble() * 2 * r, c.dy - r + rand.nextDouble() * (r * 0.95));
        final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * (0.8 + rand.nextDouble()) + i));
        canvas.drawCircle(p, 0.6 + rand.nextDouble() * 0.9, Paint()..color = Colors.white.withValues(alpha: tw * 0.8 * intro));
      }
      // Crescent moon.
      final mc = Offset(c.dx + r * 0.42, c.dy - r * 0.5);
      canvas.drawCircle(mc, r * 0.11, Paint()..color = const Color(0xFFEDEFE6));
      canvas.drawCircle(mc + Offset(r * 0.045, -r * 0.03), r * 0.1, Paint()..color = top);
    } else {
      final sc = Offset(c.dx + r * 0.42, c.dy - r * 0.42 + (1 - intro) * r * 0.3);
      canvas.drawCircle(sc, r * 0.2, Paint()..color = (dusk ? const Color(0xFFF2C89A) : const Color(0xFFF6E4B0)).withValues(alpha: 0.5));
      canvas.drawCircle(sc, r * 0.12, Paint()..color = dusk ? const Color(0xFFE9A86A) : const Color(0xFFF2CF75));
    }
  }

  void _hills(Canvas canvas, Offset c, double r, double horizon) {
    final far = night ? const Color(0xFF2E4A3B) : const Color(0xFFBFD6C4);
    final near = night ? const Color(0xFF365A45) : const Color(0xFFA7C9AE);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r, horizon)
        ..quadraticBezierTo(c.dx - r * 0.45, horizon - r * 0.32, c.dx + r * 0.05, horizon - r * 0.08)
        ..quadraticBezierTo(c.dx + r * 0.5, horizon - r * 0.3, c.dx + r, horizon - r * 0.1)
        ..lineTo(c.dx + r, horizon)
        ..close(),
      Paint()..color = far,
    );
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r, horizon - r * 0.04)
        ..quadraticBezierTo(c.dx - r * 0.2, horizon - r * 0.16, c.dx + r * 0.35, horizon - r * 0.02)
        ..lineTo(c.dx + r, horizon)
        ..lineTo(c.dx - r, horizon)
        ..close(),
      Paint()..color = near,
    );
  }

  // ── Soil: the real two layers ───────────────────────────────────────────
  void _soil(Canvas canvas, Offset c, double r, double horizon) {
    final dry = mood == BinMood.dry;
    final wet = mood == BinMood.wet;
    final topColor = dry ? const Color(0xFF9A7350) : (wet ? const Color(0xFF5C4130) : const Color(0xFF6E4C34));
    const bottomColor = Color(0xFF3F2A1D);
    final split = horizon + r * 0.42;

    canvas.drawRect(Rect.fromLTRB(c.dx - r, horizon, c.dx + r, c.dy + r), Paint()..color = topColor);
    final wave = Path()..moveTo(c.dx - r, split);
    for (var x = -1.0; x <= 1.0; x += 0.125) {
      wave.quadraticBezierTo(c.dx + (x + 0.0625) * r, (x * 8).round().isEven ? split + 3 : split - 3, c.dx + (x + 0.125) * r, split);
    }
    wave
      ..lineTo(c.dx + r, c.dy + r)
      ..lineTo(c.dx - r, c.dy + r)
      ..close();
    canvas.drawPath(wave, Paint()..color = bottomColor);

    // Grass edge.
    final grass = Paint()
      ..color = night ? const Color(0xFF4F7A5C) : const Color(0xFF7FAF73)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawRect(Rect.fromLTRB(c.dx - r, horizon - 1.5, c.dx + r, horizon + 2.5), Paint()..color = grass.color);
    for (var i = 0; i < 34; i++) {
      final x = c.dx - r + i / 33 * 2 * r;
      final h = 3.0 + (i * 7 % 5);
      final lean = math.sin(t * 1.3 + i * 0.7) * 1.2;
      canvas.drawLine(Offset(x, horizon), Offset(x + lean, horizon - h), grass);
    }

    // Scraps in the top layer, specks in the bottom.
    final rand = math.Random(5);
    for (var i = 0; i < 22; i++) {
      final p = Offset(c.dx - r + rand.nextDouble() * 2 * r, horizon + 8 + rand.nextDouble() * (split - horizon - 14));
      final kind = i % 3;
      final paint = Paint()..color = [const Color(0xFFD7B486), const Color(0xFF8FB46B), const Color(0xFFE09A55)][kind].withValues(alpha: 0.85);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(rand.nextDouble() * math.pi);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: kind == 0 ? 7 : 5, height: 2.6), const Radius.circular(1.3)), paint);
      canvas.restore();
    }
    for (var i = 0; i < 30; i++) {
      final p = Offset(c.dx - r + rand.nextDouble() * 2 * r, split + 6 + rand.nextDouble() * (c.dy + r - split));
      canvas.drawCircle(p, 0.8 + rand.nextDouble() * 1.1, Paint()..color = const Color(0xFF5E4330));
    }

    // CO₂ bubbles rising through the top layer: more when the microbes are busy.
    final busy = (co2 / 3000).clamp(0.2, 1.4);
    final bubbles = (8 * busy).round();
    for (var i = 0; i < bubbles; i++) {
      final speed = 0.12 + (i % 4) * 0.03;
      final phase = (t * speed + i / bubbles) % 1;
      final x = c.dx - r * 0.85 + ((i * 37) % 100) / 100 * r * 1.7 + math.sin(t + i) * 2;
      final y = split - phase * (split - horizon);
      canvas.drawCircle(
        Offset(x, y),
        1.4 + (i % 3) * 0.6,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35 * math.sin(phase * math.pi))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    if (dry) {
      final crack = Paint()
        ..color = const Color(0xFF7A5A3E)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      for (final o in [Offset(-0.5, 0.2), Offset(0.15, 0.3), Offset(0.55, 0.22)]) {
        final p = Offset(c.dx + o.dx * r, horizon + o.dy * r);
        canvas.drawPath(
          Path()
            ..moveTo(p.dx, p.dy)
            ..lineTo(p.dx + 6, p.dy + 4)
            ..lineTo(p.dx + 4, p.dy + 10)
            ..moveTo(p.dx + 6, p.dy + 4)
            ..lineTo(p.dx + 12, p.dy + 2),
          crack,
        );
      }
    }
    if (wet) {
      final puddle = Paint()..color = const Color(0xFF8FB8DD).withValues(alpha: 0.5);
      for (var i = 0; i < 3; i++) {
        final x = c.dx - r * 0.5 + i * r * 0.5;
        final w = r * (0.22 + 0.04 * math.sin(t * 1.5 + i));
        canvas.drawOval(Rect.fromCenter(center: Offset(x, horizon + 4), width: w, height: 3.5), puddle);
      }
    }
  }

  // ── The plant ───────────────────────────────────────────────────────────
  void _plant(Canvas canvas, Offset base, double r) {
    final h01 = (score / 100).clamp(0.0, 1.0);
    final wilt = mood == BinMood.dry || mood == BinMood.struggling ? 1.0 : (mood == BinMood.fair ? 0.4 : 0.0);
    final g = (0.35 + 0.65 * growth) * intro;
    final height = r * 0.98 * g;
    final sway = math.sin(t * 0.9) * 0.05 * (1 - wilt * 0.6) + wilt * 0.08;

    final healthy = night ? const Color(0xFF8FCB6B) : const Color(0xFF5E9E54);
    final tired = const Color(0xFFB59F68);
    final leafA = Color.lerp(tired, healthy, h01)!;
    final leafB = Color.lerp(tired, night ? const Color(0xFFB9DD7B) : const Color(0xFF7DB86A), h01)!;
    final stemColor = Color.lerp(const Color(0xFF8C7A52), night ? const Color(0xFF6FA55E) : const Color(0xFF4E8045), h01)!;

    // Stem as a curve; sample points for leaves.
    final top = base + Offset(math.sin(sway) * height * 0.9 + wilt * r * 0.12, -height * (1 - wilt * 0.12));
    final ctrl = base + Offset(-height * 0.12, -height * 0.55);
    final stem = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, top.dx, top.dy);
    canvas.drawPath(
      stem,
      Paint()
        ..color = stemColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round,
    );

    final metric = stem.computeMetrics().first;
    final pairs = (2 + growth * 2).round();
    for (var i = 0; i < pairs; i++) {
      final f = 0.32 + i / pairs * 0.62;
      final tan = metric.getTangentForOffset(metric.length * f)!;
      final size = r * (0.34 - i * 0.04) * g;
      final flutter = math.sin(t * 1.4 + i) * 0.08;
      for (final side in const [-1.0, 1.0]) {
        final angle = tan.angle + side * (0.85 - wilt * 0.45) + flutter + wilt * 0.6;
        _leaf(canvas, tan.position, angle, size, (i + (side > 0 ? 1 : 0)).isEven ? leafA : leafB, side);
      }
    }

    // A bloom when the bin is thriving.
    if (score >= 85 && wilt == 0) {
      final bloom = (intro - 0.6).clamp(0.0, 0.4) / 0.4;
      final petal = Paint()..color = night ? const Color(0xFFF2E3D2) : const Color(0xFFF4EFE4);
      for (var i = 0; i < 5; i++) {
        final a = i * math.pi * 2 / 5 + t * 0.15;
        canvas.drawCircle(top + Offset(math.cos(a), math.sin(a)) * 5.5 * bloom, 4.2 * bloom, petal);
      }
      canvas.drawCircle(top, 3.2 * bloom, Paint()..color = const Color(0xFFE9B35A));
    } else {
      canvas.drawCircle(top, 3, Paint()..color = leafB);
    }
  }

  void _leaf(Canvas canvas, Offset at, double angle, double len, Color color, double side) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    final w = len * 0.55;
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(len * 0.45, -w * side, len, 0)
      ..quadraticBezierTo(len * 0.45, w * 0.35 * side, 0, 0);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      Offset.zero,
      Offset(len * 0.8, -w * 0.12 * side),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..strokeWidth = 0.8,
    );
    canvas.restore();
  }

  // ── Weather ─────────────────────────────────────────────────────────────
  void _weather(Canvas canvas, Offset c, double r, double horizon) {
    if (mood != BinMood.wet) return;
    final rain = Paint()
      ..color = (night ? const Color(0xFF9CC3E6) : const Color(0xFF6E9FCB)).withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 28; i++) {
      final phase = (t * (0.9 + (i % 5) * 0.08) + i / 28) % 1;
      final x = c.dx - r + ((i * 53) % 100) / 100 * 2 * r - phase * 8;
      final y = c.dy - r + phase * (horizon - c.dy + r);
      canvas.drawLine(Offset(x, y), Offset(x - 2.5, y + 7), rain);
    }
  }

  // ── Fireflies at night, pollen by day ───────────────────────────────────
  void _motes(Canvas canvas, Offset c, double r, double horizon) {
    final count = (6 + score / 100 * 10).round();
    for (var i = 0; i < count; i++) {
      final phase = (t * (0.05 + (i % 4) * 0.012) + i / count) % 1;
      final x = c.dx - r * 0.8 + ((i * 41) % 100) / 100 * r * 1.6 + math.sin(t * 0.7 + i) * 8;
      final y = horizon - 4 - phase * r * 0.9;
      final a = math.sin(phase * math.pi) * (0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 3 + i)));
      final color = night ? const Color(0xFFE8F5A8) : Colors.white;
      if (night) canvas.drawCircle(Offset(x, y), 4, Paint()..color = color.withValues(alpha: a * 0.18 * intro));
      canvas.drawCircle(Offset(x, y), night ? 1.4 : 1.1, Paint()..color = color.withValues(alpha: a * intro));
    }
  }

  @override
  bool shouldRepaint(_WorldPainter old) => true;
}
