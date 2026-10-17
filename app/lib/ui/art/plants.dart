import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models.dart' show PlantSpecies;
import '../tokens.dart';

export '../../domain/models.dart' show PlantSpecies;

String speciesName(PlantSpecies s) => switch (s) {
  PlantSpecies.sprout => 'Sprout',
  PlantSpecies.fern => 'Fern',
  PlantSpecies.tulip => 'Tulip',
  PlantSpecies.sunflower => 'Sunflower',
  PlantSpecies.mushroom => 'Toadstool',
  PlantSpecies.succulent => 'Succulent',
  PlantSpecies.lavender => 'Lavender',
  PlantSpecies.pumpkin => 'Harvest Pumpkin',
};

/// A garden plant that sways gently. Wilted plants droop and fade.
class Plant extends StatefulWidget {
  const Plant(this.species, {super.key, this.size = 64, this.wilted = false, this.mound = true, this.swaying = true, this.grow = false});
  final PlantSpecies species;
  final double size;
  final bool wilted;
  final bool mound;
  final bool swaying;

  /// Grows up out of the ground when first shown.
  final bool grow;

  @override
  State<Plant> createState() => _PlantState();
}

class _PlantState extends State<Plant> with TickerProviderStateMixin {
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 3000 + (widget.species.index * 370) % 1400),
  );
  late final AnimationController _grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 900), value: widget.grow ? 0 : 1);

  @override
  void initState() {
    super.initState();
    if (widget.swaying) _sway.repeat();
    if (widget.grow) _grow.forward();
  }

  @override
  void dispose() {
    _sway.dispose();
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_sway, _grow]),
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: PlantPainter(
            widget.species,
            sway: math.sin(_sway.value * math.pi * 2),
            wilt: widget.wilted ? 1 : 0,
            grow: Curves.elasticOut.transform(_grow.value),
            mound: widget.mound,
          ),
        ),
      ),
    );
  }
}

class PlantPainter extends CustomPainter {
  PlantPainter(this.species, {this.sway = 0, this.wilt = 0, this.grow = 1, this.mound = true});
  final PlantSpecies species;
  final double sway;
  final double wilt;
  final double grow;
  final bool mound;

  static const _dry = Color(0xFFC9B98F);

  Color _c(Color c) => wilt > 0 ? Color.lerp(c, _dry, 0.65 * wilt)! : c;

  Paint _p(Color c) => Paint()..color = _c(c);

  Paint _stroke(Color c, double w) => Paint()
    ..color = _c(c)
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 100;
    canvas.save();
    canvas.scale(k);
    canvas.translate(50, 88);

    if (mound) {
      canvas.drawOval(Rect.fromCenter(center: const Offset(0, 4), width: 58, height: 14), Paint()..color = C.soilLip);
      canvas.drawOval(Rect.fromCenter(center: const Offset(0, 2), width: 54, height: 11), Paint()..color = C.soil);
    }

    canvas.save();
    canvas.scale(grow.clamp(0.0, 1.3), grow.clamp(0.0, 1.3));
    canvas.rotate(sway * 0.045 * (1 - wilt * 0.7) + wilt * 0.12);

    switch (species) {
      case PlantSpecies.sprout:
        _sprout(canvas);
      case PlantSpecies.fern:
        _fern(canvas);
      case PlantSpecies.tulip:
        _tulip(canvas);
      case PlantSpecies.sunflower:
        _sunflower(canvas);
      case PlantSpecies.mushroom:
        _mushroom(canvas);
      case PlantSpecies.succulent:
        _succulent(canvas);
      case PlantSpecies.lavender:
        _lavender(canvas);
      case PlantSpecies.pumpkin:
        _pumpkin(canvas);
    }
    canvas.restore();
    canvas.restore();
  }

  void _leaf(Canvas canvas, Offset base, double angle, double len, double width, Color color, {Color? vein}) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(width, -len * 0.5, 0, -len)
      ..quadraticBezierTo(-width, -len * 0.5, 0, 0);
    canvas.drawPath(path, _p(color));
    if (vein != null) {
      canvas.drawLine(Offset(0, -len * 0.12), Offset(0, -len * 0.8), _stroke(vein, 1.4));
    }
    canvas.restore();
  }

  void _stem(Canvas canvas, double h, {double bend = 0, double w = 4}) {
    final droop = wilt * 14;
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(bend + droop * 0.3, -h * 0.5, bend * 0.4 + droop, -h + droop * 0.6);
    canvas.drawPath(path, _stroke(C.stem, w));
  }

  Offset _top(double h, {double bend = 0}) => Offset(bend * 0.4 + wilt * 14, -h + wilt * 14 * 0.6);

  void _sprout(Canvas canvas) {
    _stem(canvas, 34, bend: 3);
    final t = _top(34, bend: 3);
    _leaf(canvas, t, -1.05 - wilt * 0.6, 24, 11, C.leaf, vein: C.leafLip);
    _leaf(canvas, t, 1.0 + wilt * 0.6, 20, 10, C.grassDeep, vein: C.leaf);
  }

  void _fern(Canvas canvas) {
    for (final (i, a) in const [-0.9, -0.45, 0.0, 0.45, 0.9].indexed) {
      final len = i == 2 ? 58.0 : (i == 1 || i == 3 ? 50.0 : 40.0);
      final ang = a + wilt * 0.35 * (a >= 0 ? 1 : -1);
      final end = Offset(math.sin(ang) * len, -math.cos(ang) * len + wilt * 12);
      final ctrl = Offset(math.sin(ang) * len * 0.35, -math.cos(ang) * len * 0.75);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
      final color = i.isEven ? C.leaf : C.stem;
      canvas.drawPath(path, _stroke(color, 2.4));
      for (final m in path.computeMetrics()) {
        for (var d = 8.0; d < m.length - 3; d += 6) {
          final tan = m.getTangentForOffset(d)!;
          final n = Offset(-tan.vector.dy, tan.vector.dx);
          final s = (1 - d / m.length) * 9 + 3;
          for (final side in const [1.0, -1.0]) {
            final p = tan.position + n * side * s * 0.6;
            canvas.drawOval(Rect.fromCenter(center: p, width: s * 0.75, height: s * 0.75), _p(color));
          }
        }
      }
    }
  }

  void _tulip(Canvas canvas) {
    _leaf(canvas, const Offset(-2, 0), -0.4 - wilt * 0.4, 34, 9, C.leaf);
    _leaf(canvas, const Offset(2, 0), 0.45 + wilt * 0.4, 28, 8, C.grassDeep);
    _stem(canvas, 52, bend: -2);
    final t = _top(52, bend: -2);
    canvas.save();
    canvas.translate(t.dx, t.dy);
    canvas.rotate(wilt * 0.9);
    final back = Path()
      ..moveTo(-12, -4)
      ..quadraticBezierTo(-13, -22, -6, -24)
      ..lineTo(0, -16)
      ..lineTo(6, -24)
      ..quadraticBezierTo(13, -22, 12, -4)
      ..quadraticBezierTo(0, 6, -12, -4);
    canvas.drawPath(back, _p(C.coralLip));
    final front = Path()
      ..moveTo(-9, -4)
      ..quadraticBezierTo(-8, -20, 0, -26)
      ..quadraticBezierTo(8, -20, 9, -4)
      ..quadraticBezierTo(0, 5, -9, -4);
    canvas.drawPath(front, _p(C.coral));
    canvas.drawOval(Rect.fromCenter(center: const Offset(-3, -15), width: 3, height: 8), _p(Colors.white.withValues(alpha: 0.35)));
    canvas.restore();
  }

  void _sunflower(Canvas canvas) {
    _stem(canvas, 62, bend: 4, w: 4.5);
    _leaf(canvas, const Offset(1, -22), -1.2 - wilt * 0.4, 22, 10, C.leaf, vein: C.leafLip);
    _leaf(canvas, const Offset(2, -34), 1.15 + wilt * 0.4, 20, 9, C.grassDeep, vein: C.leaf);
    final t = _top(62, bend: 4);
    canvas.save();
    canvas.translate(t.dx, t.dy);
    canvas.rotate(wilt * 1.1);
    for (var i = 0; i < 12; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 6);
      canvas.drawOval(Rect.fromCenter(center: const Offset(0, -13), width: 8, height: 14), _p(i.isEven ? C.sun : C.sunLip));
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, 9, _p(C.soilLip));
    canvas.drawCircle(Offset.zero, 7, _p(C.soil));
    final dot = _p(C.soilDeep);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawCircle(Offset(math.cos(a), math.sin(a)) * 3.8, 1.1, dot);
    }
    canvas.restore();
  }

  void _mushroom(Canvas canvas) {
    final stalk = RRect.fromRectAndRadius(const Rect.fromLTWH(-7, -26, 14, 27), const Radius.circular(6));
    canvas.drawRRect(stalk, _p(const Color(0xFFF6EBDD)));
    canvas.drawRect(const Rect.fromLTWH(-7, -26, 4, 26), _p(const Color(0xFFE8D9C5)));
    canvas.save();
    canvas.translate(0, -24 + wilt * 4);
    canvas.rotate(wilt * 0.3);
    final cap = Path()
      ..moveTo(-24, 2)
      ..quadraticBezierTo(-24, -26, 0, -26)
      ..quadraticBezierTo(24, -26, 24, 2)
      ..quadraticBezierTo(0, 7, -24, 2);
    canvas.drawPath(cap, _p(C.coral));
    canvas.drawPath(
      Path()
        ..moveTo(-24, 2)
        ..quadraticBezierTo(0, 7, 24, 2)
        ..quadraticBezierTo(0, 2, -24, 2),
      _p(C.coralLip),
    );
    final spot = _p(Colors.white);
    canvas.drawCircle(const Offset(-10, -14), 4, spot);
    canvas.drawCircle(const Offset(7, -18), 3, spot);
    canvas.drawCircle(const Offset(14, -6), 2.6, spot);
    canvas.drawCircle(const Offset(-2, -6), 2.2, spot);
    canvas.restore();
  }

  void _succulent(Canvas canvas) {
    const outer = Color(0xFF6FB89A);
    const inner = Color(0xFF8FD1B2);
    for (var i = 0; i < 7; i++) {
      final a = -1.35 + i * 0.45;
      _leaf(canvas, const Offset(0, -4), a * (1 + wilt * 0.3), 26, 9, outer);
    }
    for (var i = 0; i < 5; i++) {
      final a = -0.9 + i * 0.45;
      _leaf(canvas, const Offset(0, -6), a, 20, 7.5, inner);
    }
    _leaf(canvas, const Offset(0, -6), 0, 15, 6, const Color(0xFFB4E3CB));
    canvas.drawCircle(const Offset(0, -20), 2.2, _p(C.petalPink));
  }

  void _lavender(Canvas canvas) {
    const bud = Color(0xFFA98BDB);
    const budDeep = Color(0xFF8C6DC4);
    for (final (i, a) in const [-0.32, 0.0, 0.3].indexed) {
      final h = i == 1 ? 60.0 : 48.0;
      final ang = a + wilt * 0.3;
      final end = Offset(math.sin(ang) * h, -math.cos(ang) * h + wilt * 10);
      canvas.drawLine(Offset.zero, end, _stroke(C.stem, 2.4));
      for (var j = 0; j < 6; j++) {
        final f = 0.62 + j * 0.075;
        final p = Offset(end.dx * f, end.dy * f);
        canvas.drawOval(Rect.fromCenter(center: p + const Offset(-2.5, 0), width: 5.5, height: 7), _p(j.isEven ? bud : budDeep));
        canvas.drawOval(Rect.fromCenter(center: p + const Offset(2.5, -2), width: 5.5, height: 7), _p(j.isEven ? budDeep : bud));
      }
    }
    _leaf(canvas, const Offset(-1, 0), -0.7, 18, 4, C.grassDeep);
    _leaf(canvas, const Offset(1, 0), 0.7, 16, 4, C.grassDeep);
  }

  void _pumpkin(Canvas canvas) {
    const orange = Color(0xFFFF9A3C);
    const ribs = Color(0xFFE77B1C);
    _leaf(canvas, const Offset(10, -26), 0.9, 22, 12, C.leaf, vein: C.leafLip);
    canvas.drawOval(Rect.fromCenter(center: const Offset(-13, -16), width: 26, height: 32), _p(ribs));
    canvas.drawOval(Rect.fromCenter(center: const Offset(13, -16), width: 26, height: 32), _p(ribs));
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -16), width: 30, height: 34), _p(orange));
    canvas.drawOval(Rect.fromCenter(center: const Offset(-17, -16), width: 14, height: 26), _p(orange));
    canvas.drawOval(Rect.fromCenter(center: const Offset(17, -16), width: 14, height: 26), _p(orange));
    canvas.drawOval(Rect.fromCenter(center: const Offset(-6, -24), width: 6, height: 10), _p(Colors.white.withValues(alpha: 0.3)));
    canvas.drawPath(
      Path()
        ..moveTo(0, -32)
        ..quadraticBezierTo(1, -40, 6, -43),
      _stroke(C.stem, 4.5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(4, -38)
        ..cubicTo(14, -46, 20, -36, 12, -34),
      _stroke(C.leaf, 1.8),
    );
  }

  @override
  bool shouldRepaint(PlantPainter old) => old.sway != sway || old.wilt != wilt || old.grow != grow || old.species != species;
}
