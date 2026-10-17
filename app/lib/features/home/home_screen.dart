import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/toast.dart';
import '../../domain/health_score.dart';
import '../../domain/models.dart';
import '../../domain/xp_rules.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'bin_world.dart';
import 'next_action.dart';
import 'readings_row.dart';
import 'streak_calendar.dart';
import 'today_quests.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    final suggestion = ref.watch(suggestionProvider);
    final game = ref.watch(gameProvider);

    void goTo(AppTab tab) => ref.read(tabProvider.notifier).state = tab;

    if (health == null) {
      return const Center(
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.forest)),
      );
    }
    final s = health.snapshot;
    final growth = switch (s.topStage) {
      Stage.started => 0.15,
      Stage.active => 0.55,
      Stage.hot => 0.7,
      Stage.cooling => 0.8,
      _ => 1.0,
    };

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x3, S.gutter, S.x8),
        children: [
          _Hud(game: game),
          const SizedBox(height: S.x2),
          // The world: long-press for the demo scenario picker.
          GestureDetector(
            onTap: () => goTo(AppTab.layers),
            onLongPress: () => showScenarioPicker(context, ref),
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) => BinWorld(size: math.min(c.maxWidth, 340), score: health.score, mood: health.mood, growth: growth, co2: s.co2),
              ),
            ),
          ),
          _ScoreBlock(health: health),
          const SizedBox(height: S.x6),
          ReadingsRow(s: s, onOpen: (_) => goTo(AppTab.layers)),
          const SizedBox(height: S.x6),
          const Hairline(),
          const SizedBox(height: S.x6),
          if (suggestion != null) ...[
            NextAction(suggestion: suggestion, ready: s.bottomStage == Stage.ready, onLog: (_) => goTo(AppTab.log)),
            const SizedBox(height: S.x6),
            const Hairline(),
            const SizedBox(height: S.x6),
          ],
          StreakCalendar(game: game),
          const SizedBox(height: S.x6),
          const Hairline(),
          const SizedBox(height: S.x6),
          const TodayQuests(),
        ].animate(interval: M.stagger).fadeIn(duration: 420.ms, curve: M.ease).slideY(begin: 0.03, curve: M.ease),
      ),
    );
  }
}

/// Game-style HUD: level + XP on the left, streak, Loam and rewards on the right.
class _Hud extends ConsumerWidget {
  const _Hud({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = game.level;
    final from = xpForLevel(level);
    final to = xpForLevel(level + 1);
    final xp01 = (game.totalXp - from) / (to - from);
    final inbox = game.crates.length + game.packets;

    return Row(
      children: [
        SizedBox(
          width: 34,
          height: 34,
          child: CustomPaint(
            painter: _LevelRing(xp01),
            child: Center(child: Text('$level', style: T.num.copyWith(fontSize: 13))),
          ),
        ),
        const SizedBox(width: S.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titleForLevel(level),
                style: T.small.copyWith(color: C.ink, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 90,
                child: ThinBar(value: xp01, color: C.forest, height: 3),
              ),
            ],
          ),
        ),
        _HudStat(
          icon: Icon(PhosphorIconsFill.fire, size: 18, color: game.caredToday ? C.amber : C.faint),
          value: '${game.streak.days}',
          onTap: null,
        ),
        _HudStat(icon: const LoamCoin(size: 18), value: '${game.loam}', onTap: () => showToast(ref, 'Greenhouse and Seed Packets are next')),
        Pressable(
          onTap: () => showToast(ref, 'Rewards inbox is next'),
          child: Padding(
            padding: const EdgeInsets.only(left: S.x2),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(PhosphorIconsRegular.gift, size: 22, color: C.ink),
                ),
                if (inbox > 0)
                  Positioned(
                    top: 1,
                    right: 1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: C.clay,
                        shape: BoxShape.circle,
                        border: Border.all(color: C.paper, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HudStat extends StatelessWidget {
  const _HudStat({required this.icon, required this.value, required this.onTap});
  final Widget icon;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: 6),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 5),
            Text(value, style: T.num.copyWith(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _LevelRing extends CustomPainter {
  _LevelRing(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = C.line);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value.clamp(0, 1), false, p..color = C.forest);
  }

  @override
  bool shouldRepaint(_LevelRing old) => old.value != value;
}

/// Score under the world: the number, the state, one plain sentence.
class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({required this.health});
  final BinHealth health;

  @override
  Widget build(BuildContext context) {
    final s = health.snapshot;
    final color = switch (health.mood) {
      BinMood.thriving || BinMood.healthy => C.leaf,
      BinMood.wet => C.water,
      BinMood.dry => C.amber,
      _ => C.clay,
    };
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CountUp(health.score, from: 0, style: T.hero.copyWith(fontSize: 64)),
            Padding(
              padding: const EdgeInsets.only(bottom: 9, left: 3),
              child: Text('/100', style: T.label),
            ),
          ],
        ),
        const SizedBox(height: S.x2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(moodLabel(health.mood).toUpperCase(), style: T.caps.copyWith(color: color)),
            Text('  ·  KITCHEN BIN  ·  ', style: T.caps.copyWith(color: C.faint)),
            const LiveDot(color: C.leaf, size: 5),
            Text('LIVE', style: T.caps),
          ],
        ),
        const SizedBox(height: S.x3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Text(_status(s), textAlign: TextAlign.center, style: T.body),
        ),
      ],
    );
  }

  static String _status(BinSnapshot s) {
    String layer(String name, double m) {
      if (m > moistureHi + 4) return '$name is too wet';
      if (m < moistureLo - 4) return '$name is drying out';
      return '$name is in range';
    }

    if (s.bottomStage == Stage.ready) return 'The bottom layer has finished curing. Time to harvest.';
    return '${layer('Top layer', s.topMoisture)}, ${layer('bottom layer', s.bottomMoisture)}.';
  }
}
