import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/health_score.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';

/// "Why is my score 72?": the health score, explained.
class HealthSheet extends ConsumerWidget {
  const HealthSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(healthProvider);
    if (h == null) return const SizedBox(height: 200);
    final s = h.snapshot;
    final b = h.breakdown;
    final ratio = s.greens7d == 0 ? 0 : s.browns7d / s.greens7d;

    final rows = [
      _Row(
        PhosphorIconsFill.drop,
        'Moisture',
        HealthBreakdown.wMoisture,
        b.moisture,
        Tone.sky,
        'Top ${s.topMoisture.round()}%, bottom ${s.bottomMoisture.round()}%. Healthy is ${moistureLo.round()}–${moistureHi.round()}%. Our most reliable sensor.',
      ),
      _Row(
        PhosphorIconsFill.thermometerSimple,
        'Temperature',
        HealthBreakdown.wTemperature,
        b.temperature,
        Tone.flame,
        'Top layer is ${(s.topTemp - s.ambientTemp).round()}° above the room, which means the microbes are working.',
      ),
      _Row(
        PhosphorIconsFill.cloud,
        'CO₂ activity',
        HealthBreakdown.wCo2,
        b.co2,
        Tone.moss,
        '${s.co2.round()} ppm in the air gap, ${s.co2SlopePerDay >= 0 ? 'rising' : 'falling'} ${s.co2SlopePerDay.abs().toStringAsFixed(0)}% a day.',
      ),
      _Row(
        PhosphorIconsFill.scales,
        'Greens / browns',
        HealthBreakdown.wBalance,
        b.balance,
        Tone.soil,
        '1 : ${ratio.toStringAsFixed(1)} this week. Aim for 1 : 2–3.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ProgressRing(
              value: h.score / 100,
              size: 96,
              stroke: 11,
              color: h.score >= 70 ? C.leaf : (h.score >= 50 ? C.sun : C.coral),
              child: CountUp(h.score, from: 0, style: T.numL),
            ),
            const SizedBox(width: S.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bin health', style: T.h1),
                  const SizedBox(height: S.x1),
                  Text('Four sensor signals, weighted by how much we trust them.', style: T.body),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x5),
        ...rows.animate(interval: 60.ms).fadeIn().slideX(begin: 0.06),
        const SizedBox(height: S.x2),
        Row(
          children: [
            const Icon(PhosphorIconsFill.info, size: 16, color: C.muted),
            const SizedBox(width: S.x2),
            Expanded(child: Text('A guide from sensor trends, not a lab test.', style: T.small)),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.weight, this.score, this.tone, this.detail);
  final IconData icon;
  final String label;
  final double weight;
  final double score;
  final Tone tone;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Slab(
        padding: const EdgeInsets.all(S.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBlob(icon, tone: tone, size: 40, iconSize: 22),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(label, style: T.bodyStrong)),
                      Text('${(weight * 100).round()}% weight', style: T.small.copyWith(fontSize: 11.5)),
                    ],
                  ),
                  const SizedBox(height: S.x2),
                  ProgressBar(value: score / 100, color: tone.face, height: 12),
                  const SizedBox(height: S.x2),
                  Text(
                    detail,
                    style: T.small.copyWith(color: C.inkSoft, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
