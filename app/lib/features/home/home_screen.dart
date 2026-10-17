import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/routes.dart';
import '../../app/stats_bar.dart';
import '../../domain/health_score.dart';
import '../../domain/models.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';
import 'quests_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    final suggestion = ref.watch(suggestionProvider);
    final hat = ref.watch(gameProvider.select((g) => g.hat));

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const StatsBar(leading: _BinPicker()),
          Expanded(
            child: health == null
                ? const _Loading()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x8),
                    children: [
                      if (suggestion != null) _SpeechBubble(text: suggestion.line, mood: health.mood),
                      const SizedBox(height: S.x1),
                      BinScene(
                        states: {for (final z in Zone.values) z: zoneState(health.snapshot, z)},
                        mood: health.mood,
                        hat: hat,
                        labels: _labels(health.snapshot),
                        onZone: (z) {
                          ref.read(gameProvider.notifier).checkIn();
                          Routes.layer(context, z);
                        },
                        onWren: () {
                          Sfx.play(Sound.great, volume: 0.5);
                          ref.read(gameProvider.notifier).checkIn();
                        },
                        onWrenLongPress: () => Routes.debug(context),
                      ),
                      const SizedBox(height: S.x4),
                      ...[_HealthCard(health), if (suggestion != null) _SuggestCard(suggestion), const QuestsCard(), const _ImpactStrip()]
                          .expand((w) => [w, const SizedBox(height: S.x4)])
                          .toList()
                          .animate(interval: M.stagger)
                          .fadeIn(duration: M.base)
                          .slideY(begin: 0.08, curve: Curves.easeOutCubic),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Map<Zone, Widget> _labels(BinSnapshot s) => {
    Zone.air: _ZoneChip(icon: PhosphorIconsFill.cloud, value: _co2(s.co2), unit: 'CO₂', tone: Tone.moss),
    Zone.top: _ZoneChip(icon: PhosphorIconsFill.drop, value: '${s.topMoisture.round()}%', unit: '${s.topTemp.round()}°', tone: _moistureTone(s.topMoisture)),
    Zone.bottom: _ZoneChip(
      icon: PhosphorIconsFill.drop,
      value: '${s.bottomMoisture.round()}%',
      unit: '${s.bottomTemp.round()}°',
      tone: _moistureTone(s.bottomMoisture),
    ),
  };
}

String _co2(double ppm) => ppm >= 1000 ? '${(ppm / 1000).toStringAsFixed(1)}k' : ppm.round().toString();

Tone _moistureTone(double m) {
  if (m > moistureHi + 4) return Tone.sky;
  if (m < moistureLo - 4) return Tone.flame;
  return Tone.leaf;
}

class _BinPicker extends StatelessWidget {
  const _BinPicker();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(color: C.leaf, shape: BoxShape.circle),
        ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.35, duration: 900.ms),
        const SizedBox(width: S.x2),
        Flexible(
          child: Text('Kitchen bin', style: T.title, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Wren(mood: WrenMood.okay, size: 120, ground: true),
          const SizedBox(height: S.x3),
          Text('Listening to your bin…', style: T.body),
        ],
      ),
    );
  }
}

class _ZoneChip extends StatelessWidget {
  const _ZoneChip({required this.icon, required this.value, required this.unit, required this.tone});
  final IconData icon;
  final String value;
  final String unit;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _chip());
  }

  Widget _chip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(R.chip),
        border: Border.all(color: tone.face.withValues(alpha: 0.6), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: tone.face),
          const SizedBox(width: 3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: T.numM.copyWith(fontSize: 14, color: tone.lip)),
              Text(unit, style: T.small.copyWith(fontSize: 10.5, height: 1.1)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wren's speech bubble, with a tail pointing down at the bin.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text, required this.mood});
  final String text;
  final WrenMood mood;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x6),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(R.card - 4),
              border: Border.all(color: C.border, width: 2),
            ),
            child: AnimatedSwitcher(
              duration: M.base,
              child: Text(
                text,
                key: ValueKey(text),
                textAlign: TextAlign.center,
                style: T.bodyStrong.copyWith(color: C.inkSoft),
              ),
            ),
          ),
          CustomPaint(size: const Size(22, 11), painter: _TailPainter()),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack, alignment: Alignment.bottomCenter);
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, -2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, -2);
    canvas.drawPath(path, Paint()..color = C.surface);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0),
      Paint()
        ..color = C.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) => false;
}

class _HealthCard extends StatelessWidget {
  const _HealthCard(this.health);
  final BinHealth health;

  @override
  Widget build(BuildContext context) {
    final score = health.score;
    final tone = score >= 70 ? Tone.leaf : (score >= 50 ? Tone.sun : Tone.coral);
    return Slab(
      onTap: () => Routes.health(context),
      child: Row(
        children: [
          ProgressRing(
            value: score / 100,
            size: 84,
            stroke: 10,
            color: tone.face,
            child: CountUp(score, style: T.numL.copyWith(color: tone.lip)),
          ),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BIN HEALTH', style: T.eyebrow),
                const SizedBox(height: S.x1),
                Text('Wren is ${moodLabel(health.mood).toLowerCase()}', style: T.title),
                const SizedBox(height: S.x2),
                Row(
                  children: [
                    _Mini(label: 'Moist', value: health.breakdown.moisture, color: C.sky),
                    _Mini(label: 'Temp', value: health.breakdown.temperature, color: C.flame),
                    _Mini(label: 'CO₂', value: health.breakdown.co2, color: C.moss),
                    _Mini(label: 'Mix', value: health.breakdown.balance, color: C.soil),
                  ],
                ),
              ],
            ),
          ),
          const Icon(PhosphorIconsBold.caretRight, color: C.faint, size: 20),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProgressBar(value: value / 100, color: color, height: 8),
            const SizedBox(height: 3),
            Text(label, style: T.small.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SuggestCard extends StatelessWidget {
  const _SuggestCard(this.s);
  final Suggestion s;

  @override
  Widget build(BuildContext context) {
    final (title, tone) = switch (s.balance) {
      Balance.needsBrowns => ('Needs browns', Tone.soil),
      Balance.needsGreens => ('Needs greens', Tone.leaf),
      Balance.balanced => ('Nicely balanced', Tone.moss),
    };
    return Slab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBlob(PhosphorIconsFill.lightbulb, tone: Tone.sun, size: 40),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WREN SUGGESTS', style: T.eyebrow),
                    const SizedBox(height: 2),
                    Text(title, style: T.title),
                  ],
                ),
              ),
              Tag('+15 XP', tone: Tone.sun, icon: PhosphorIconsFill.lightning, dense: true),
            ],
          ),
          const SizedBox(height: S.x3),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              for (final f in s.add)
                _FoodChip(
                  f,
                  tone: tone,
                  onTap: () => Routes.log(context, item: f),
                ),
            ],
          ),
          const SizedBox(height: S.x3),
          Text('KEEP OUT', style: T.eyebrow.copyWith(fontSize: 11)),
          const SizedBox(height: S.x2),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              for (final f in s.avoid.take(3))
                _FoodChip(
                  f,
                  tone: Tone.coral,
                  crossed: true,
                  onTap: () => Routes.log(context, item: f),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FoodChip extends StatelessWidget {
  const _FoodChip(this.f, {required this.tone, required this.onTap, this.crossed = false});
  final FoodItem f;
  final Tone tone;
  final VoidCallback onTap;
  final bool crossed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
        decoration: BoxDecoration(
          color: tone.tint,
          borderRadius: BorderRadius.circular(R.chip),
          border: Border.all(color: tone.face.withValues(alpha: 0.35), width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(f.icon, size: 18, color: tone.face),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.small.copyWith(
                  color: tone.lip,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  decoration: crossed ? TextDecoration.lineThrough : null,
                  decorationColor: tone.lip,
                  decorationThickness: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImpactStrip extends ConsumerWidget {
  const _ImpactStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider);
    return Slab(
      color: C.leafTint,
      edge: C.leaf.withValues(alpha: 0.35),
      child: Row(
        children: [
          const IconBlob(PhosphorIconsFill.globeHemisphereWest, tone: Tone.leaf, size: 48),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR IMPACT', style: T.eyebrow.copyWith(color: C.leafLip)),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    style: T.bodyStrong,
                    children: [
                      TextSpan(
                        text: '${g.kgDiverted.toStringAsFixed(1)} kg',
                        style: const TextStyle(color: C.leafDeep, fontWeight: FontWeight.w900),
                      ),
                      const TextSpan(text: ' of food kept out of landfill, about '),
                      TextSpan(
                        text: '${g.co2eAvoided.toStringAsFixed(1)} kg CO₂e',
                        style: const TextStyle(color: C.leafDeep, fontWeight: FontWeight.w900),
                      ),
                      const TextSpan(text: ' of methane emissions avoided.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
