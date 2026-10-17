import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/stats_bar.dart';
import '../../domain/models.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';

/// The batch journey: Duolingo's lesson path, but every node is a real
/// compost stage reached by the sensors, not by tapping.
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(binProvider).valueOrNull;
    final harvests = ref.watch(gameProvider.select((g) => g.harvests));
    final hat = ref.watch(gameProvider.select((g) => g.hat));
    final mood = ref.watch(healthProvider)?.mood ?? WrenMood.happy;
    final bottomHarvested = harvests > 2;
    final bottomStage = bottomHarvested ? Stage.harvested : (s?.bottomStage ?? Stage.curing);
    final topStage = s?.topStage ?? Stage.active;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          StatsBar(leading: Text('Journey', style: T.h2)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x8),
              children: [
                _UnitBanner(title: 'Batch #3', subtitle: 'Bottom layer · started 5 weeks ago', tone: Tone.soil, done: bottomHarvested),
                _Path(current: bottomStage, seed: 0, mood: mood, hat: hat, isActiveBatch: !bottomHarvested),
                const SizedBox(height: S.x6),
                _UnitBanner(title: 'Batch #4', subtitle: 'Top layer · started 9 days ago', tone: Tone.leaf),
                _Path(current: topStage, seed: 3, mood: mood, hat: hat, isActiveBatch: bottomHarvested),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitBanner extends StatelessWidget {
  const _UnitBanner({required this.title, required this.subtitle, required this.tone, this.done = false});
  final String title;
  final String subtitle;
  final Tone tone;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: tone.lip, borderRadius: BorderRadius.circular(R.card)),
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x3, S.x4),
        decoration: BoxDecoration(color: tone.face, borderRadius: BorderRadius.circular(R.card)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.toUpperCase(), style: T.eyebrow.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                  const SizedBox(height: 4),
                  Text(subtitle, style: T.title.copyWith(color: Colors.white)),
                ],
              ),
            ),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(R.button)),
              child: Icon(done ? PhosphorIconsFill.sealCheck : PhosphorIconsFill.notebook, color: Colors.white, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageInfo {
  const _StageInfo(this.stage, this.title, this.icon, this.what, this.signal, this.duration);
  final Stage stage;
  final String title;
  final IconData icon;
  final String what;
  final String signal;
  final String duration;
}

const _stages = [
  _StageInfo(
    Stage.started,
    'Started',
    PhosphorIconsFill.shovel,
    'Fresh scraps and browns go in. The microbes move in.',
    'Moisture settles into range',
    'Day 1',
  ),
  _StageInfo(
    Stage.active,
    'Active',
    PhosphorIconsFill.bug,
    'Bacteria feast on the greens. Things start to warm up.',
    'CO₂ climbs, temperature rises',
    '1–2 weeks',
  ),
  _StageInfo(Stage.hot, 'Hot phase', PhosphorIconsFill.fire, 'The pile heats up and breaks down fast.', 'Temperature 15°+ above the room', '1–3 weeks'),
  _StageInfo(
    Stage.cooling,
    'Cooling',
    PhosphorIconsFill.snowflake,
    'Heat fades as the easy food runs out. Fungi take over.',
    'Temperature drifts down',
    '1–2 weeks',
  ),
  _StageInfo(
    Stage.curing,
    'Curing',
    PhosphorIconsFill.hourglassMedium,
    'Slow finishing. It turns dark, crumbly and earthy.',
    'CO₂ falling day over day',
    '3–6 weeks',
  ),
  _StageInfo(Stage.ready, 'Ready', PhosphorIconsFill.sparkle, 'Finished compost, ready to feed your plants.', 'CO₂ low, temperature matches the room', 'Now!'),
  _StageInfo(Stage.harvested, 'Harvest', PhosphorIconsFill.basket, 'Scoop it out and use it as free fertilizer.', 'You tap Harvest', '—'),
];

class _Path extends StatelessWidget {
  const _Path({required this.current, required this.seed, required this.mood, required this.hat, required this.isActiveBatch});
  final Stage current;
  final int seed;
  final WrenMood mood;
  final WrenHat hat;
  final bool isActiveBatch;

  @override
  Widget build(BuildContext context) {
    const decor = [PlantSpecies.fern, PlantSpecies.mushroom, PlantSpecies.tulip, PlantSpecies.sunflower, PlantSpecies.succulent, PlantSpecies.lavender];
    return Padding(
      padding: const EdgeInsets.only(top: S.x6),
      child: Column(
        children: [
          for (final (i, info) in _stages.indexed)
            LayoutBuilder(
              builder: (context, c) {
                final dx = math.sin((i + seed) * math.pi / 3.2) * (c.maxWidth * 0.2);
                final state = info.stage.index < current.index
                    ? _NodeState.done
                    : info.stage == current
                    ? _NodeState.current
                    : _NodeState.locked;
                final showDecor = i % 2 == 1;
                return SizedBox(
                  width: double.infinity,
                  height: state == _NodeState.current ? 144 : 96,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      if (showDecor)
                        Positioned(
                          left: dx > 0 ? c.maxWidth * 0.08 : null,
                          right: dx <= 0 ? c.maxWidth * 0.08 : null,
                          child: Plant(decor[(i + seed) % decor.length], size: 64, wilted: state == _NodeState.locked && !isActiveBatch),
                        ),
                      Transform.translate(
                        offset: Offset(dx, 0),
                        child: _Node(info: info, state: state, mood: mood, hat: hat, showWren: state == _NodeState.current && isActiveBatch),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

enum _NodeState { done, current, locked }

class _Node extends StatelessWidget {
  const _Node({required this.info, required this.state, required this.mood, required this.hat, required this.showWren});
  final _StageInfo info;
  final _NodeState state;
  final WrenMood mood;
  final WrenHat hat;
  final bool showWren;

  @override
  Widget build(BuildContext context) {
    final (face, lip, iconColor) = switch (state) {
      _NodeState.done => (C.leaf, C.leafLip, Colors.white),
      _NodeState.current => (info.stage == Stage.ready ? C.sun : C.flame, info.stage == Stage.ready ? C.sunLip : C.flameLip, Colors.white),
      _NodeState.locked => (const Color(0xFFE5DFD3), const Color(0xFFCFC6B4), const Color(0xFFB0A792)),
    };
    final node = ChunkyCircle(
      size: 72,
      face: face,
      lip: lip,
      lipHeight: 7,
      onPressed: () => _showStage(context),
      child: Icon(state == _NodeState.done ? PhosphorIconsBold.check : info.icon, color: iconColor, size: 32),
    );

    if (state != _NodeState.current) return node;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: 6),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(R.chip),
            border: Border.all(color: C.border, width: 2),
          ),
          child: Text(info.stage == Stage.ready ? 'HARVEST ME!' : 'WE\'RE HERE', style: T.eyebrow.copyWith(color: face)),
        ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: 0, end: -5, duration: 700.ms, curve: Curves.easeInOut),
        const SizedBox(height: S.x2),
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            ProgressRing(value: info.stage == Stage.ready ? 1 : 0.62, size: 96, stroke: 8, color: face, track: C.track),
            Padding(padding: const EdgeInsets.only(bottom: 6), child: node),
            if (showWren)
              Positioned(
                right: -64,
                bottom: -6,
                child: Wren(mood: mood, size: 66, hat: hat),
              ),
          ],
        ),
      ],
    );
  }

  void _showStage(BuildContext context) {
    showCalmSheet<void>(
      context,
      builder: (context) => _StageSheet(info: info, state: state),
    );
  }
}

class _StageSheet extends ConsumerWidget {
  const _StageSheet({required this.info, required this.state});
  final _StageInfo info;
  final _NodeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = switch (state) {
      _NodeState.done => Tone.leaf,
      _NodeState.current => info.stage == Stage.ready ? Tone.sun : Tone.flame,
      _NodeState.locked => const Tone(C.faint, C.muted, C.bgDeep),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconBlob(info.icon, tone: tone, size: 56),
            const SizedBox(width: S.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(switch (state) {
                    _NodeState.done => 'COMPLETED',
                    _NodeState.current => 'IN PROGRESS',
                    _NodeState.locked => 'COMING UP',
                  }, style: T.eyebrow.copyWith(color: tone.lip)),
                  const SizedBox(height: 2),
                  Text(info.title, style: T.h1),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x4),
        Text(info.what, style: T.body.copyWith(fontSize: 16)),
        const SizedBox(height: S.x4),
        Slab(
          padding: const EdgeInsets.all(S.x3),
          child: Column(
            children: [
              _Fact(PhosphorIconsFill.waveform, 'Sensor signal', info.signal),
              const SizedBox(height: S.x3),
              _Fact(PhosphorIconsFill.clock, 'Typically lasts', info.duration),
            ],
          ),
        ),
        if (state == _NodeState.current && info.stage == Stage.ready) ...[
          const SizedBox(height: S.x4),
          ChunkyButton(
            label: 'Harvest',
            icon: PhosphorIconsFill.basket,
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(gameProvider.notifier).harvest();
            },
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: C.muted),
        const SizedBox(width: S.x2),
        Text(label, style: T.small),
        const SizedBox(width: S.x3),
        Expanded(
          child: Text(value, textAlign: TextAlign.right, style: T.bodyStrong.copyWith(fontSize: 14)),
        ),
      ],
    );
  }
}
