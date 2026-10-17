import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../tokens.dart';

/// The streak flame. Grey until you've cared for the bin today (Duolingo's
/// trick: the flame is "lit" by today's action).
class Flame extends StatefulWidget {
  const Flame({super.key, this.size = 24, this.lit = true, this.flicker = false});
  final double size;
  final bool lit;
  final bool flicker;

  @override
  State<Flame> createState() => _FlameState();
}

class _FlameState extends State<Flame> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.flicker) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(Flame old) {
    super.didUpdateWidget(old);
    if (widget.flicker && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.flicker && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) =>
          CustomPaint(size: Size(widget.size * 0.82, widget.size), painter: _FlamePainter(widget.lit, Curves.easeInOut.transform(_c.value))),
    );
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter(this.lit, this.flicker);
  final bool lit;
  final double flicker;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final lean = (flicker - 0.5) * w * 0.08;
    final outer = Path()
      ..moveTo(w * 0.5 + lean, 0)
      ..cubicTo(w * 0.62, h * 0.22, w * 1.02, h * 0.38, w * 0.98, h * 0.66)
      ..cubicTo(w * 0.95, h * 0.9, w * 0.72, h, w * 0.5, h)
      ..cubicTo(w * 0.24, h, w * 0.02, h * 0.88, w * 0.02, h * 0.64)
      ..cubicTo(w * 0.02, h * 0.46, w * 0.16, h * 0.36, w * 0.22, h * 0.24)
      ..cubicTo(w * 0.3, h * 0.36, w * 0.36, h * 0.4, w * 0.4, h * 0.42)
      ..cubicTo(w * 0.36, h * 0.24, w * 0.42, h * 0.1, w * 0.5 + lean, 0);
    canvas.drawPath(outer, Paint()..color = lit ? C.flame : C.faint);
    final inner = Path()
      ..moveTo(w * 0.5, h * 0.45 + flicker * h * 0.04)
      ..cubicTo(w * 0.62, h * 0.58, w * 0.76, h * 0.68, w * 0.74, h * 0.8)
      ..cubicTo(w * 0.72, h * 0.94, w * 0.6, h * 0.98, w * 0.5, h * 0.98)
      ..cubicTo(w * 0.36, h * 0.98, w * 0.26, h * 0.9, w * 0.26, h * 0.79)
      ..cubicTo(w * 0.26, h * 0.66, w * 0.42, h * 0.58, w * 0.5, h * 0.45 + flicker * h * 0.04);
    canvas.drawPath(inner, Paint()..color = lit ? C.sun : const Color(0xFFD9D2C3));
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.lit != lit || old.flicker != flicker;
}

/// League tier visuals.
class TierStyle {
  const TierStyle(this.face, this.lip, this.icon);
  final Color face;
  final Color lip;
  final IconData icon;
}

const tierStyles = [
  TierStyle(Color(0xFFA7D88A), Color(0xFF7FB863), PhosphorIconsFill.acorn),
  TierStyle(C.leaf, C.leafLip, PhosphorIconsFill.plant),
  TierStyle(C.moss, C.mossLip, PhosphorIconsFill.leaf),
  TierStyle(C.sun, C.sunLip, PhosphorIconsFill.flower),
  TierStyle(C.flame, C.flameLip, PhosphorIconsFill.tree),
  TierStyle(Color(0xFFE0533D), Color(0xFFB23A27), PhosphorIconsFill.treeEvergreen),
];

/// Shield badge for a league tier.
class LeagueBadge extends StatelessWidget {
  const LeagueBadge(this.tier, {super.key, this.size = 56, this.locked = false});
  final int tier;
  final double size;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final s = tierStyles[tier];
    return SizedBox(
      width: size,
      height: size * 1.1,
      child: CustomPaint(
        painter: _ShieldPainter(locked ? const Color(0xFFE2DBCD) : s.face, locked ? const Color(0xFFCFC6B4) : s.lip),
        child: Padding(
          padding: EdgeInsets.only(bottom: size * 0.16),
          child: Center(
            child: Icon(locked ? PhosphorIconsFill.lock : s.icon, color: locked ? const Color(0xFFB5AC9A) : Colors.white, size: size * 0.42),
          ),
        ),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  _ShieldPainter(this.face, this.lip);
  final Color face;
  final Color lip;

  Path _shield(Size s, double inset) {
    final w = s.width;
    final h = s.height * 0.94;
    return Path()
      ..moveTo(w * 0.5, inset)
      ..quadraticBezierTo(w * 0.78, h * 0.1, w - inset, h * 0.12)
      ..quadraticBezierTo(w - inset, h * 0.62, w * 0.5, h - inset)
      ..quadraticBezierTo(inset, h * 0.62, inset, h * 0.12)
      ..quadraticBezierTo(w * 0.22, h * 0.1, w * 0.5, inset)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(_shield(size, 0).shift(Offset(0, size.height * 0.06)), Paint()..color = lip);
    canvas.drawPath(_shield(size, 0), Paint()..color = face);
    canvas.drawPath(
      _shield(size, size.width * 0.12),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.05,
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => old.face != face;
}

/// Wooden reward chest. [open] 0..1 animates the lid.
class Chest extends StatelessWidget {
  const Chest({super.key, this.size = 40, this.open = 0, this.dim = false});
  final double size;
  final double open;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size * 0.9), painter: _ChestPainter(open, dim));
  }
}

class _ChestPainter extends CustomPainter {
  _ChestPainter(this.open, this.dim);
  final double open;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 100;
    canvas.save();
    canvas.scale(k);
    final wood = dim ? const Color(0xFFD8CDB9) : const Color(0xFFB07445);
    final woodDark = dim ? const Color(0xFFC6BAA4) : const Color(0xFF8A5631);
    final band = dim ? const Color(0xFFE6DECF) : C.sun;
    final bandDark = dim ? const Color(0xFFD3C9B6) : C.sunLip;

    // Glow when open.
    if (open > 0) {
      final glow = Paint()..color = C.sun.withValues(alpha: 0.35 * open);
      canvas.drawCircle(const Offset(50, 40), 46 * open, glow);
      for (var i = 0; i < 8; i++) {
        final a = -math.pi / 2 + (i - 3.5) * 0.28;
        canvas.drawLine(
          const Offset(50, 46) + Offset(math.cos(a), math.sin(a)) * 22,
          const Offset(50, 46) + Offset(math.cos(a), math.sin(a)) * (22 + 26 * open),
          Paint()
            ..color = C.sun.withValues(alpha: open)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Body.
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(8, 44, 84, 44), const Radius.circular(8));
    canvas.drawRRect(body.shift(const Offset(0, 4)), Paint()..color = woodDark);
    canvas.drawRRect(body, Paint()..color = wood);
    canvas.drawLine(
      const Offset(14, 66),
      const Offset(86, 66),
      Paint()
        ..color = woodDark
        ..strokeWidth = 2,
    );
    canvas.drawRect(const Rect.fromLTWH(20, 44, 8, 44), Paint()..color = band);
    canvas.drawRect(const Rect.fromLTWH(72, 44, 8, 44), Paint()..color = band);

    // Lid, hinged at the back.
    canvas.save();
    canvas.translate(50, 46);
    canvas.rotate(-open * 0.5);
    canvas.translate(0, -open * 10);
    final lid = Path()
      ..moveTo(-42, 0)
      ..lineTo(-42, -14)
      ..quadraticBezierTo(-42, -30, -26, -30)
      ..lineTo(26, -30)
      ..quadraticBezierTo(42, -30, 42, -14)
      ..lineTo(42, 0)
      ..close();
    canvas.drawPath(lid.shift(const Offset(0, 3)), Paint()..color = woodDark);
    canvas.drawPath(lid, Paint()..color = wood);
    canvas.drawRect(const Rect.fromLTWH(-30, -30, 8, 30), Paint()..color = band);
    canvas.drawRect(const Rect.fromLTWH(22, -30, 8, 30), Paint()..color = band);
    canvas.restore();

    // Lock.
    if (open < 0.3) {
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(42, 40, 16, 18), const Radius.circular(4)), Paint()..color = bandDark);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(44, 41, 12, 14), const Radius.circular(3)), Paint()..color = band);
      canvas.drawCircle(const Offset(50, 47), 2.2, Paint()..color = bandDark);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChestPainter old) => old.open != open || old.dim != dim;
}

/// The currency icon: an acorn.
class AcornIcon extends StatelessWidget {
  const AcornIcon({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) => Icon(PhosphorIconsFill.acorn, color: const Color(0xFFC07A3A), size: size);
}
