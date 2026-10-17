import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/health_score.dart' show ZoneState;
import '../../domain/models.dart' show Zone;
import '../tokens.dart';
import 'wren.dart';

/// The hero illustration: a cutaway of the real bin, with the air gap, both
/// compost layers, the sensor probe and the ESP32, and Wren poking out.
///
/// Drawn on a 340×300 design grid and scaled to fit.
class BinScene extends StatefulWidget {
  const BinScene({
    super.key,
    required this.states,
    required this.mood,
    this.hat = WrenHat.none,
    this.labels = const {},
    this.onZone,
    this.onWren,
    this.onWrenLongPress,
  });

  final Map<Zone, ZoneState> states;
  final WrenMood mood;
  final WrenHat hat;
  final Map<Zone, Widget> labels;
  final ValueChanged<Zone>? onZone;
  final VoidCallback? onWren;
  final VoidCallback? onWrenLongPress;

  static const designW = 340.0;
  static const designH = 300.0;

  /// Vertical centre of each zone on the design grid (for labels).
  static const zoneY = {Zone.air: 104.0, Zone.top: 172.0, Zone.bottom: 246.0};

  @override
  State<BinScene> createState() => _BinSceneState();
}

class _BinSceneState extends State<BinScene> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  bool _wrenDown = false;

  static const _wrenRect = Rect.fromLTWH(118, -6, 112, 150);

  Zone? _zoneAt(Offset p) {
    if (p.dx < 96 || p.dx > 300) return null;
    if (p.dy >= 78 && p.dy < 132) return Zone.air;
    if (p.dy >= 132 && p.dy < 212) return Zone.top;
    if (p.dy >= 212 && p.dy < 290) return Zone.bottom;
    return null;
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: BinScene.designW / BinScene.designH,
      child: LayoutBuilder(
        builder: (context, c) {
          final k = c.maxWidth / BinScene.designW;
          Offset toDesign(Offset p) => p / k;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              if (_wrenRect.contains(toDesign(d.localPosition))) setState(() => _wrenDown = true);
            },
            onTapCancel: () => setState(() => _wrenDown = false),
            onTapUp: (d) {
              setState(() => _wrenDown = false);
              final p = toDesign(d.localPosition);
              if (_wrenRect.contains(p)) {
                widget.onWren?.call();
                return;
              }
              final z = _zoneAt(p);
              if (z != null) widget.onZone?.call(z);
            },
            onLongPressStart: (d) {
              if (_wrenRect.contains(toDesign(d.localPosition))) widget.onWrenLongPress?.call();
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _t,
                      builder: (context, _) => CustomPaint(painter: _BackPainter(_t.value, widget.states)),
                    ),
                  ),
                ),
                Positioned(
                  left: _wrenRect.left * k,
                  top: _wrenRect.top * k,
                  width: _wrenRect.width * k,
                  height: _wrenRect.width * k,
                  child: AnimatedScale(
                    scale: _wrenDown ? 0.9 : 1,
                    duration: M.fast,
                    alignment: Alignment.bottomCenter,
                    child: Wren(mood: widget.mood, size: _wrenRect.width * k, hat: widget.hat, tail: 36),
                  ),
                ),
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _t,
                      builder: (context, _) => CustomPaint(painter: _FrontPainter(_t.value, widget.states)),
                    ),
                  ),
                ),
                for (final e in widget.labels.entries)
                  Positioned(
                    left: 0,
                    width: 104 * k,
                    top: BinScene.zoneY[e.key]! * k - 24,
                    height: 48,
                    child: Align(alignment: Alignment.centerLeft, child: e.value),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

const _bin = Color(0xFF6DBE7A);
const _binLip = Color(0xFF4E9A5B);
const _binDeep = Color(0xFF3C7E48);
const _interior = Color(0xFFEFE6D4);
const _topSoil = Color(0xFFA0714A);
const _topSoilDry = Color(0xFFC9A274);
const _bottomSoil = Color(0xFF5E3D26);

Path _interiorPath() => Path()
  ..moveTo(110, 76)
  ..lineTo(290, 76)
  ..lineTo(279, 272)
  ..quadraticBezierTo(278, 282, 268, 282)
  ..lineTo(132, 282)
  ..quadraticBezierTo(122, 282, 121, 272)
  ..close();

double _wallX(double y, {required bool left}) {
  // Linear interpolation of the tapered walls.
  final f = (y - 76) / (282 - 76);
  return left ? 110 + 11 * f : 290 - 11 * f;
}

class _BackPainter extends CustomPainter {
  _BackPainter(this.t, this.states);
  final double t;
  final Map<Zone, ZoneState> states;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / BinScene.designW;
    canvas.save();
    canvas.scale(k);

    // Ground shadow.
    canvas.drawOval(Rect.fromCenter(center: const Offset(200, 290), width: 230, height: 18), Paint()..color = C.soil.withValues(alpha: 0.14));

    // Lid tipped open backwards: we see its underside behind the opening.
    final lid = Path()
      ..moveTo(108, 64)
      ..lineTo(120, 26)
      ..quadraticBezierTo(122, 18, 132, 18)
      ..lineTo(268, 18)
      ..quadraticBezierTo(278, 18, 280, 26)
      ..lineTo(292, 64)
      ..close();
    canvas.drawPath(lid, Paint()..color = _binLip);
    canvas.drawPath(
      Path()
        ..moveTo(118, 62)
        ..lineTo(128, 30)
        ..quadraticBezierTo(129, 26, 134, 26)
        ..lineTo(266, 26)
        ..quadraticBezierTo(271, 26, 272, 30)
        ..lineTo(282, 62)
        ..close(),
      Paint()..color = _binDeep,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(118, 12, 164, 10), const Radius.circular(5)), Paint()..color = _bin);

    // Interior back wall (air gap).
    canvas.drawPath(_interiorPath(), Paint()..color = _interior);
    canvas.drawRect(const Rect.fromLTWH(110, 76, 180, 10), Paint()..color = const Color(0xFFE3D8C2));

    // CO₂ bubbles drifting up through the air gap.
    final bubble = Paint()
      ..color = (states[Zone.air] == ZoneState.hot ? C.flame : C.faint).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (var i = 0; i < 7; i++) {
      final phase = (t * 1.6 + i / 7) % 1;
      final x = 122 + (i * 37 % 110) + math.sin(phase * math.pi * 2 + i) * 4;
      final y = 130 - phase * 50;
      final r = 2.5 + (i % 3) * 1.4;
      bubble.color = bubble.color.withValues(alpha: 0.6 * math.sin(phase * math.pi));
      canvas.drawCircle(Offset(x, y), r, bubble);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackPainter old) => true;
}

class _FrontPainter extends CustomPainter {
  _FrontPainter(this.t, this.states);
  final double t;
  final Map<Zone, ZoneState> states;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / BinScene.designW;
    canvas.save();
    canvas.scale(k);
    canvas.save();
    canvas.clipPath(_interiorPath());

    final topState = states[Zone.top] ?? ZoneState.good;
    final bottomState = states[Zone.bottom] ?? ZoneState.good;

    // Top layer with a lumpy surface.
    final surface = Path()..moveTo(100, 140);
    for (var x = 100.0; x <= 300; x += 20) {
      surface.quadraticBezierTo(x + 10, 128 + (x % 40 == 0 ? 2 : -3), x + 20, 134 + (x % 60 == 0 ? -2 : 1));
    }
    surface
      ..lineTo(300, 300)
      ..lineTo(100, 300)
      ..close();
    canvas.drawPath(surface, Paint()..color = topState == ZoneState.dry ? _topSoilDry : _topSoil);

    // Scraps: peels, leaves and cardboard bits.
    final rand = math.Random(4);
    for (var i = 0; i < 26; i++) {
      final x = 118 + rand.nextDouble() * 165;
      final y = 142 + rand.nextDouble() * 64;
      final kind = i % 4;
      final rot = rand.nextDouble() * math.pi;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);
      switch (kind) {
        case 0:
          canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-6, -3, 12, 6), const Radius.circular(1.5)), Paint()..color = const Color(0xFFD9B98A));
        case 1:
          canvas.drawOval(const Rect.fromLTWH(-5, -2.5, 10, 5), Paint()..color = C.leaf.withValues(alpha: 0.85));
        case 2:
          canvas.drawArc(
            const Rect.fromLTWH(-6, -4, 12, 8),
            0,
            math.pi,
            false,
            Paint()
              ..color = C.flame
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6
              ..strokeCap = StrokeCap.round,
          );
        default:
          canvas.drawCircle(Offset.zero, 1.6, Paint()..color = _bottomSoil.withValues(alpha: 0.6));
      }
      canvas.restore();
    }

    // Moisture states.
    if (topState == ZoneState.wet) {
      canvas.drawRect(const Rect.fromLTWH(100, 128, 200, 84), Paint()..color = C.sky.withValues(alpha: 0.22));
      final shine = Paint()..color = Colors.white.withValues(alpha: 0.55);
      for (var i = 0; i < 5; i++) {
        final x = 130 + i * 32.0;
        final y = 150 + (i % 2) * 26.0 + math.sin(t * math.pi * 4 + i) * 1.5;
        canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 16, height: 4), shine);
      }
      final drop = Paint()..color = C.sky;
      for (var i = 0; i < 4; i++) {
        final phase = (t * 2 + i / 4) % 1;
        canvas.drawCircle(Offset(140 + i * 38.0, 140 + phase * 64), 2.2, drop..color = C.sky.withValues(alpha: 1 - phase));
      }
    } else if (topState == ZoneState.dry) {
      final crack = Paint()
        ..color = _topSoil
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (final o in const [Offset(140, 160), Offset(200, 184), Offset(250, 156), Offset(170, 200)]) {
        canvas.drawPath(
          Path()
            ..moveTo(o.dx, o.dy)
            ..lineTo(o.dx + 7, o.dy + 4)
            ..lineTo(o.dx + 5, o.dy + 10)
            ..moveTo(o.dx + 7, o.dy + 4)
            ..lineTo(o.dx + 14, o.dy + 2),
          crack,
        );
      }
    }

    // Bottom layer: older, darker compost.
    final divider = Path()..moveTo(100, 214);
    for (var x = 100.0; x <= 300; x += 25) {
      divider.quadraticBezierTo(x + 12, 208 + (x % 50 == 0 ? 0 : 6), x + 25, 212);
    }
    divider
      ..lineTo(300, 300)
      ..lineTo(100, 300)
      ..close();
    canvas.drawPath(divider, Paint()..color = bottomState == ZoneState.dry ? const Color(0xFF7D5A3E) : _bottomSoil);
    final speck = Paint()..color = const Color(0xFF7A5536);
    for (var i = 0; i < 40; i++) {
      canvas.drawCircle(Offset(120 + (i * 53 % 165).toDouble(), 222 + (i * 29 % 56).toDouble()), 1.3 + (i % 3) * 0.5, speck);
    }
    if (bottomState == ZoneState.wet) {
      canvas.drawRect(const Rect.fromLTWH(100, 210, 200, 80), Paint()..color = C.sky.withValues(alpha: 0.18));
    }

    // A tiny worm friend in the finished compost.
    final w = Paint()
      ..color = C.worm
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    final wx = 150 + math.sin(t * math.pi * 2) * 3;
    canvas.drawPath(
      Path()
        ..moveTo(wx, 258)
        ..quadraticBezierTo(wx + 6, 252, wx + 12, 258)
        ..quadraticBezierTo(wx + 18, 264, wx + 24, 258),
      w,
    );

    canvas.restore(); // interior clip

    // Probe pipe with sensors.
    const px = 252.0;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(px - 7, 44, 14, 230), const Radius.circular(7)), Paint()..color = const Color(0xFFD9D4C9));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(px + 1, 44, 6, 230), const Radius.circular(4)), Paint()..color = const Color(0xFFC2BCAF));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(px - 8, 40, 16, 8), const Radius.circular(3)), Paint()..color = const Color(0xFFB3AC9E));

    // CO₂ module in the air gap.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(px - 26, 94, 20, 18), const Radius.circular(4)), Paint()..color = const Color(0xFF2F3A33));
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(px - 22, 99 + i * 4.0),
        Offset(px - 10, 99 + i * 4.0),
        Paint()
          ..color = const Color(0xFF55635A)
          ..strokeWidth = 1.4,
      );
    }

    // Sensor nodes pulse with their zone's colour.
    for (final (zone, y) in const [(Zone.top, 172.0), (Zone.bottom, 246.0)]) {
      final st = states[zone] ?? ZoneState.good;
      final color = switch (st) {
        ZoneState.wet => C.sky,
        ZoneState.dry => C.flame,
        ZoneState.hot => C.coral,
        _ => C.leaf,
      };
      final pulse = (t * 3 + (zone == Zone.top ? 0 : 0.5)) % 1;
      canvas.drawCircle(Offset(px, y), 7 + pulse * 9, Paint()..color = color.withValues(alpha: 0.35 * (1 - pulse)));
      canvas.drawCircle(Offset(px, y), 7, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(px, y), 4.6, Paint()..color = color);
    }

    // Walls and rim.
    final wall = Paint()
      ..color = _bin
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_interiorPath().shift(const Offset(0, 0)), wall);
    canvas.drawPath(
      Path()
        ..moveTo(_wallX(120, left: true) - 3, 120)
        ..lineTo(_wallX(270, left: true) - 3, 270),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    final rim = RRect.fromRectAndRadius(const Rect.fromLTWH(100, 62, 200, 18), const Radius.circular(9));
    canvas.drawRRect(rim.shift(const Offset(0, 3)), Paint()..color = _binLip);
    canvas.drawRRect(rim, Paint()..color = _bin);
    for (var i = 0; i < 9; i++) {
      canvas.drawCircle(Offset(116 + i * 21.0, 71), 2.6, Paint()..color = _binDeep);
    }

    // Feet.
    for (final x in const [140.0, 260.0]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 12, 284, 24, 7), const Radius.circular(3.5)), Paint()..color = _binLip);
    }

    // ESP32 box on the outside, wired into the probe.
    canvas.drawPath(
      Path()
        ..moveTo(px, 42)
        ..cubicTo(px + 12, 20, 340, 40, 318, 150),
      Paint()
        ..color = const Color(0xFF2F3A33)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    final box = RRect.fromRectAndRadius(const Rect.fromLTWH(300, 148, 34, 46), const Radius.circular(7));
    canvas.drawRRect(box.shift(const Offset(0, 3)), Paint()..color = const Color(0xFF1E2621));
    canvas.drawRRect(box, Paint()..color = const Color(0xFF2F3A33));
    final blink = (t * 6) % 1 < 0.5;
    canvas.drawCircle(const Offset(309, 158), 3, Paint()..color = blink ? const Color(0xFF7CF08B) : const Color(0xFF3E6B47));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(306, 170, 22, 14), const Radius.circular(3)), Paint()..color = const Color(0xFF55635A));
    // Wi-Fi arcs.
    final wifi = Paint()
      ..color = C.leaf.withValues(alpha: blink ? 0.9 : 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i <= 2; i++) {
      canvas.drawArc(Rect.fromCircle(center: const Offset(326, 144), radius: 5.0 * i), -math.pi * 0.85, math.pi * 0.7, false, wifi);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_FrontPainter old) => true;
}
