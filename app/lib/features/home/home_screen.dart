import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/reward_reveal.dart';
import '../../app/routes.dart';
import '../../app/toast.dart';
import '../../domain/health_score.dart';
import '../../domain/models.dart';
import '../../domain/xp_rules.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'bin_world.dart';
import 'daily_track.dart';
import 'league_race.dart';
import 'rewards_shelf.dart';
import 'what_to_add.dart';
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
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.brand)),
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
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ListView(
        padding: const EdgeInsets.only(bottom: S.x8),
        children: [
          // The brand band: HUD, the Bin World and the score on Calmpost green.
          BrandBand(
            child: Padding(
              padding: EdgeInsets.fromLTRB(S.gutter, top + S.x3, S.gutter, 0),
              child: Column(
                children: [
                  _Hud(game: game),
                  const SizedBox(height: S.x2),
                  GestureDetector(
                    onTap: () => goTo(AppTab.layers),
                    onLongPress: () => showScenarioPicker(context, ref),
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, c) => BinWorld(
                          size: math.min(c.maxWidth, 330),
                          score: health.score,
                          mood: health.mood,
                          growth: growth,
                          co2: s.co2,
                          onBrand: true,
                          ringColor: game.ringColor,
                        ),
                      ),
                    ),
                  ),
                  _ScoreBlock(health: health),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.gutter, S.x4, S.gutter, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DailyTrack(),
                const SectionBreak(),
                if (suggestion != null) ...[
                  WhatToAdd(
                    suggestion: suggestion,
                    snapshot: s,
                    onPick: (f) {
                      ref.read(logIntentProvider.notifier).state = f;
                      goTo(AppTab.log);
                    },
                  ),
                  const SectionBreak(),
                ],
                if (game.crates.isNotEmpty || game.packets > 0) ...[const RewardsShelf(), const SectionBreak()],
                const TodayQuests(),
                const SectionBreak(),
                LeagueRace(onOpen: () => goTo(AppTab.social)),
                const SectionBreak(),
                StreakCalendar(game: game),
                const SectionBreak(),
                const SectionLabel('LIVE READINGS'),
                const SizedBox(height: S.x3),
                ReadingsRow(s: s, onOpen: (_) => goTo(AppTab.layers)),
              ].animate(interval: M.stagger).fadeIn(duration: 420.ms, curve: M.ease).slideY(begin: 0.03, curve: M.ease),
            ),
          ),
        ],
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
            child: Center(
              child: Text('$level', style: T.num.copyWith(fontSize: 13, color: C.onBrand)),
            ),
          ),
        ),
        const SizedBox(width: S.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                game.displayTitle,
                style: T.small.copyWith(color: C.onBrand, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 90,
                child: ThinBar(value: xp01, color: C.onBrand, track: C.onBrand.withValues(alpha: 0.28), height: 3),
              ),
            ],
          ),
        ),
        _HudStat(
          icon: Icon(PhosphorIconsFill.fire, size: 18, color: game.caredToday ? C.pink : C.onBrandMuted),
          value: '${game.streak.days}',
          onTap: null,
        ),
        _HudStat(icon: const LoamCoin(size: 18), value: '${game.loam}', onTap: () => Routes.greenhouse(context)),
        Pressable(
          onTap: () async {
            if (game.crates.isNotEmpty) {
              final o = ref.read(gameProvider.notifier).openCrate(0);
              if (o != null && context.mounted) await revealCrate(context, o.tier, o.loam, o.packets);
            } else if (game.packets > 0) {
              await Routes.greenhouse(context);
            } else {
              showToast(ref, 'No rewards waiting. Fill the daily goal to earn more.');
            }
          },
          child: Padding(
            padding: const EdgeInsets.only(left: S.x2),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(PhosphorIconsRegular.gift, size: 22, color: C.onBrand),
                ),
                if (inbox > 0)
                  Positioned(
                    top: 1,
                    right: 1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: C.pink,
                        shape: BoxShape.circle,
                        border: Border.all(color: C.brand, width: 1.5),
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
            Text(value, style: T.num.copyWith(fontSize: 14, color: C.onBrand)),
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
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = C.onBrand.withValues(alpha: 0.28));
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value.clamp(0, 1), false, p..color = C.onBrand);
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
    final pillText = switch (health.mood) {
      BinMood.thriving || BinMood.healthy => C.brandDeep,
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
            CountUp(health.score, from: 0, style: T.hero.copyWith(fontSize: 64, color: C.onBrand)),
            Padding(
              padding: const EdgeInsets.only(bottom: 9, left: 3),
              child: Text('/100', style: T.label.copyWith(color: C.onBrandMuted)),
            ),
          ],
        ),
        const SizedBox(height: S.x2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: C.onBrand, borderRadius: BorderRadius.circular(R.pill)),
              child: Text(moodLabel(health.mood).toUpperCase(), style: T.caps.copyWith(color: pillText, fontSize: 10.5)),
            ),
            Text('   KITCHEN BIN  ·  ', style: T.caps.copyWith(color: C.onBrandMuted)),
            const LiveDot(color: C.onBrand, size: 5),
            Text('LIVE', style: T.caps.copyWith(color: C.onBrandMuted)),
          ],
        ),
        const SizedBox(height: S.x3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Text(
            _status(s),
            textAlign: TextAlign.center,
            style: T.body.copyWith(color: C.onBrand),
          ),
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
