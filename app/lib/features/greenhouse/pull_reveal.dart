import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../domain/gacha.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'collectible_art.dart';
import 'collectible_details.dart';
import 'seed_learning.dart';

/// The pull: the packet shakes, tears open in the colour of the best rarity,
/// then the collectibles appear (one big card, or a 5×2 grid for ten).
Future<void> showPullReveal(BuildContext context, List<PullOutcome> pulls) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: C.ink.withValues(alpha: 0.94),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, _, _) => _PullReveal(pulls: pulls),
    transitionBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}

class _PullReveal extends StatefulWidget {
  const _PullReveal({required this.pulls});
  final List<PullOutcome> pulls;

  @override
  State<_PullReveal> createState() => _PullRevealState();
}

class _PullRevealState extends State<_PullReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _rays = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
  bool _open = false;

  PullOutcome get _best => widget.pulls.reduce((a, b) => b.item.rarity.index > a.item.rarity.index ? b : a);

  @override
  void initState() {
    super.initState();
    final rare = _best.item.rarity.index >= 3;
    Future.delayed(Duration(milliseconds: rare ? 1400 : 900), () {
      if (!mounted) return;
      rare ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
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
    final best = _best;
    final color = rarityColor(best.item.rarity);
    final single = widget.pulls.length == 1;
    final newCount = widget.pulls.where((p) => p.isNew).length;
    final refund = widget.pulls.fold<int>(0, (s, p) => s + p.refund);

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(S.x6),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: S.x5),
                      if (!_open)
                        SizedBox(
                          height: 300,
                          child: Center(
                            child: const SeedPacketArt(size: 150)
                                .animate()
                                .shake(hz: best.item.rarity.index >= 3 ? 9 : 6, rotation: 0.07, offset: Offset.zero, duration: 1400.ms)
                                .scaleXY(end: 1.08, duration: 1400.ms),
                          ),
                        )
                      else if (single)
                        _Single(pull: best, rays: _rays)
                      else
                        _Grid(pulls: widget.pulls, rays: _rays, color: color),
                      const SizedBox(height: S.x6),
                      AnimatedOpacity(
                        opacity: _open ? 1 : 0,
                        duration: const Duration(milliseconds: 400),
                        child: Column(
                          children: [
                            if (!single) ...[Text('Best pull: ${best.item.name}', style: T.title.copyWith(color: C.onBrand)), const SizedBox(height: S.x2)],
                            Text(
                              [if (newCount > 0) '$newCount new', if (refund > 0) '+$refund Loam from duplicates'].join(' · '),
                              style: T.label.copyWith(color: C.onBrandMuted),
                            ),
                          ],
                        ),
                      ),
                      if (_open && single && best.item.type == CollectibleType.specimen) ...[
                        const SizedBox(height: S.x5),
                        SeedLearning(id: best.item.id, onDark: true),
                        const SizedBox(height: S.x3),
                        PillButton(label: 'View / activate seed', color: C.onBrand, textColor: C.ink, onTap: () => showCollectibleDetails(context, best.item)),
                      ],
                      if (_open && !single) ...[
                        const SizedBox(height: S.x3),
                        Text('Explore your plants', style: T.heading.copyWith(color: C.onBrand)),
                        const SizedBox(height: S.x2),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final p in {
                              for (final p in widget.pulls)
                                if (p.item.type == CollectibleType.specimen) p.item.id: p,
                            }.values)
                              PillButton(
                                label: '${p.item.name} · field note',
                                dense: true,
                                color: C.onBrand,
                                textColor: C.ink,
                                onTap: () => showCollectibleDetails(context, p.item),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: S.x5),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: S.x3),
              SizedBox(
                width: double.infinity,
                child: PillButton(label: 'Collect', color: C.pink, textColor: C.ink, onTap: _open ? () => Navigator.of(context).pop() : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Single extends StatelessWidget {
  const _Single({required this.pull, required this.rays});
  final PullOutcome pull;
  final Animation<double> rays;

  @override
  Widget build(BuildContext context) {
    final color = rarityColor(pull.item.rarity);
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          SizedBox(
            width: 220,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: rays,
                  builder: (context, _) => CustomPaint(size: const Size(220, 200), painter: _Rays(rays.value, color)),
                ),
                CollectibleBadge(item: pull.item, size: 130).animate().scale(begin: const Offset(0.3, 0.3), duration: 520.ms, curve: Curves.easeOutBack),
              ],
            ),
          ),
          const SizedBox(height: S.x3),
          Text(pull.item.name, style: T.title.copyWith(color: C.onBrand, fontSize: 28)).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: S.x2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RarityPill(pull.item.rarity, onDark: true),
              const SizedBox(width: S.x2),
              if (pull.isNew) const PinkPill('NEW') else Text('Duplicate · +${pull.refund}', style: T.small.copyWith(color: C.onBrandMuted)),
            ],
          ).animate().fadeIn(delay: 320.ms),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.pulls, required this.rays, required this.color});
  final List<PullOutcome> pulls;
  final Animation<double> rays;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: rays,
            builder: (context, _) => CustomPaint(size: const Size(340, 300), painter: _Rays(rays.value, color)),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: S.x3,
            runSpacing: S.x4,
            children: [
              for (final (i, p) in pulls.indexed)
                SizedBox(
                  width: 58,
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CollectibleBadge(item: p.item, size: 54),
                          if (p.isNew)
                            Positioned(
                              right: -6,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(color: C.pink, borderRadius: BorderRadius.circular(R.pill)),
                                child: Text('NEW', style: T.caps.copyWith(fontSize: 8, color: C.ink, letterSpacing: 0.4)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: T.small.copyWith(fontSize: 10.5, color: rarityColor(p.item.rarity)),
                      ),
                    ],
                  ),
                ).animate(delay: (i * 110).ms).scale(begin: const Offset(0.2, 0.2), duration: 380.ms, curve: Curves.easeOutBack).fadeIn(),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rays extends CustomPainter {
  _Rays(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.max(size.width, size.height) / 2;
    final paint = Paint()..color = color.withValues(alpha: 0.16);
    const n = 16;
    for (var i = 0; i < n; i++) {
      final a = t * math.pi * 2 + i * math.pi * 2 / n;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + math.cos(a - 0.08) * r, c.dy + math.sin(a - 0.08) * r)
          ..lineTo(c.dx + math.cos(a + 0.08) * r, c.dy + math.sin(a + 0.08) * r)
          ..close(),
        paint,
      );
    }
    canvas.drawCircle(c, 90, Paint()..color = color.withValues(alpha: 0.12));
  }

  @override
  bool shouldRepaint(_Rays old) => old.t != t || old.color != color;
}
