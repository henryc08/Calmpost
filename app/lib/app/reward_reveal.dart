import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../domain/models.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import '../ui/type.dart';

/// One line in a reveal: an icon, an amount and a label.
class RevealItem {
  const RevealItem(this.icon, this.amount, this.label);
  final Widget icon;
  final String amount;
  final String label;
}

String crateTitle(CrateTier t) => switch (t) {
  CrateTier.sprout => 'Sprout crate',
  CrateTier.grove => 'Grove crate',
  CrateTier.canopy => 'Canopy crate',
};

/// Full-screen reward moment: the box shakes, bursts open with rays, and the
/// rewards rise in one by one. Quiet, quick, satisfying.
Future<void> showRewardReveal(BuildContext context, {required String title, required List<RevealItem> items, IconData icon = PhosphorIconsFill.package}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: C.ink.withValues(alpha: 0.86),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, _) => _Reveal(title: title, items: items, icon: icon),
    transitionBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}

class _Reveal extends StatefulWidget {
  const _Reveal({required this.title, required this.items, required this.icon});
  final String title;
  final List<RevealItem> items;
  final IconData icon;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with TickerProviderStateMixin {
  late final AnimationController _rays = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  bool _open = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _open = true);
    });
  }

  @override
  void dispose() {
    _rays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(S.x6),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      opacity: _open ? 1 : 0,
                      duration: const Duration(milliseconds: 400),
                      child: AnimatedBuilder(
                        animation: _rays,
                        builder: (context, _) => CustomPaint(size: const Size.square(260), painter: _RaysPainter(_rays.value)),
                      ),
                    ),
                    if (_open) const _Burst(),
                    AnimatedScale(
                      scale: _open ? 1.12 : 1,
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutBack,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(color: _open ? C.pink : C.surface, shape: BoxShape.circle),
                        child: Icon(_open ? PhosphorIconsFill.sparkle : widget.icon, size: 56, color: _open ? C.ink : C.pinkDeep),
                      ),
                    ).animate(target: _open ? 0 : 1).shake(hz: 6, rotation: 0.06, offset: Offset.zero, duration: 900.ms),
                  ],
                ),
              ),
              const SizedBox(height: S.x6),
              Text(widget.title, style: T.title.copyWith(color: C.onBrand, fontSize: 28)),
              const SizedBox(height: S.x5),
              if (_open)
                ...[
                  for (final it in widget.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          it.icon,
                          const SizedBox(width: S.x3),
                          Text(it.amount, style: T.value.copyWith(color: C.onBrand)),
                          const SizedBox(width: S.x2),
                          Text(it.label, style: T.label.copyWith(color: C.onBrandMuted)),
                        ],
                      ),
                    ),
                ].animate(interval: 160.ms).fadeIn(duration: 300.ms).slideY(begin: 0.6, curve: Curves.easeOutBack),
              const Spacer(),
              AnimatedOpacity(
                opacity: _open ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: SizedBox(
                  width: double.infinity,
                  child: PillButton(label: 'Collect', color: C.pink, textColor: C.ink, onTap: _open ? () => Navigator.of(context).pop() : null),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()..color = C.pink.withValues(alpha: 0.14);
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a = t * math.pi * 2 + i * math.pi * 2 / n;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - 0.09) * size.width / 2, c.dy + math.sin(a - 0.09) * size.width / 2)
        ..lineTo(c.dx + math.cos(a + 0.09) * size.width / 2, c.dy + math.sin(a + 0.09) * size.width / 2)
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(c, 92, Paint()..color = C.pink.withValues(alpha: 0.12));
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.t != t;
}

/// A ring of small dots flying out once when the box opens.
class _Burst extends StatefulWidget {
  const _Burst();

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(size: const Size.square(260), painter: _BurstPainter(Curves.easeOutCubic.transform(_c.value))),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const colors = [C.pink, C.sprout, C.onBrand, C.amber];
    for (var i = 0; i < 18; i++) {
      final a = i * math.pi * 2 / 18 + (i.isEven ? 0.1 : -0.1);
      final d = 60 + t * (70 + (i % 3) * 18);
      final p = c + Offset(math.cos(a), math.sin(a)) * d;
      canvas.drawCircle(p, (1 - t) * 5 + 1, Paint()..color = colors[i % colors.length].withValues(alpha: 1 - t));
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// Reveal for a crate opening.
Future<void> revealCrate(BuildContext context, CrateTier tier, int loam, int packets) => showRewardReveal(
  context,
  title: crateTitle(tier),
  items: [
    RevealItem(const LoamCoin(size: 26), '+$loam', 'Loam'),
    RevealItem(const Icon(PhosphorIconsFill.plant, size: 26, color: C.sprout), '+$packets', packets == 1 ? 'Seed Packet' : 'Seed Packets'),
  ],
);
