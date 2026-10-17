import 'package:flutter/material.dart';

import '../../domain/health_score.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// The hero: one big number for the whole bin, and what's behind it.
class HealthHero extends StatelessWidget {
  const HealthHero({super.key, required this.health, this.onTap, this.onLongPress});
  final BinHealth health;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final b = health.breakdown;
    final s = health.snapshot;
    final (pillColor, pillText) = switch (health.mood) {
      BinMood.thriving || BinMood.healthy => (C.sprout, C.forest),
      BinMood.fair => (const Color(0xFFE9D9A8), C.forest),
      BinMood.wet => (const Color(0xFFB7D3EE), C.forest),
      BinMood.dry => (const Color(0xFFF0C99A), C.forest),
      BinMood.struggling => (const Color(0xFFF0B4A2), C.forest),
    };

    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.99,
      child: Container(
        padding: const EdgeInsets.fromLTRB(S.x6, S.x5, S.x6, S.x6),
        decoration: BoxDecoration(color: C.forest, borderRadius: BorderRadius.circular(R.hero)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('BIN HEALTH', style: T.caps.copyWith(color: C.onForestMuted)),
                ),
                const LiveDot(),
                Text('Live', style: T.small.copyWith(color: C.onForestMuted)),
              ],
            ),
            const SizedBox(height: S.x2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CountUp(health.score, from: 0, style: T.hero.copyWith(color: C.onForest)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 4),
                  child: Text('/100', style: T.label.copyWith(color: C.onForestMuted)),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AnimatedContainer(
                          duration: M.base,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: pillColor, borderRadius: BorderRadius.circular(R.pill)),
                          child: Text(
                            moodLabel(health.mood),
                            style: T.small.copyWith(color: pillText, fontWeight: FontWeight.w800, fontSize: 12.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.x2),
            Text(_status(s), style: T.body.copyWith(color: C.onForest.withValues(alpha: 0.86))),
            const SizedBox(height: S.x5),
            Row(
              children: [
                _Factor('Moisture', b.moisture),
                const SizedBox(width: S.x3),
                _Factor('Temp', b.temperature),
                const SizedBox(width: S.x3),
                _Factor('CO₂', b.co2),
                const SizedBox(width: S.x3),
                _Factor('Balance', b.balance),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One plain sentence about the two layers.
  static String _status(BinSnapshot s) {
    String layer(String name, double m) {
      if (m > moistureHi + 4) return '$name is too wet';
      if (m < moistureLo - 4) return '$name is drying out';
      return '$name is in range';
    }

    if (s.bottomStage == Stage.ready) return 'The bottom layer has finished curing. Time to harvest.';
    final top = layer('Top layer', s.topMoisture);
    final bottom = layer('bottom layer', s.bottomMoisture);
    return '$top, $bottom.';
  }
}

class _Factor extends StatelessWidget {
  const _Factor(this.label, this.value);
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final good = value >= 70;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.small.copyWith(color: C.onForestMuted, fontSize: 11.5),
                ),
              ),
              Text('${value.round()}', style: T.num.copyWith(color: C.onForest, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          ThinBar(value: value / 100, color: good ? C.sprout : const Color(0xFFF0B46A), track: Colors.white.withValues(alpha: 0.12), height: 3),
        ],
      ),
    );
  }
}
