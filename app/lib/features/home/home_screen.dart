import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/toast.dart';
import '../../domain/models.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'health_hero.dart';
import 'layer_strip.dart';
import 'next_action.dart';
import 'streak_calendar.dart';
import 'today_quests.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    final suggestion = ref.watch(suggestionProvider);
    final game = ref.watch(gameProvider);

    void goTo(AppTab tab) => ref.read(tabProvider.notifier).state = tab;

    return SafeArea(
      bottom: false,
      child: health == null
          ? const Center(
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.forest)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(S.gutter, S.x4, S.gutter, S.x8),
              children: [
                const _Header(),
                const SizedBox(height: S.x6),
                HealthHero(health: health, onTap: () => goTo(AppTab.layers), onLongPress: () => showScenarioPicker(context, ref)),
                const SizedBox(height: S.x3),
                LayerStrip(s: health.snapshot, onOpen: (_) => goTo(AppTab.layers)),
                const SizedBox(height: S.x6),
                if (suggestion != null) ...[
                  NextActionCard(suggestion: suggestion, ready: health.snapshot.bottomStage == Stage.ready, onLog: (_) => goTo(AppTab.log)),
                  const SizedBox(height: S.x3),
                ],
                StreakCalendar(game: game),
                const SizedBox(height: S.x3),
                const TodayQuests(),
                const SizedBox(height: S.x6),
                _ImpactRow(game: game),
              ].animate(interval: M.stagger).fadeIn(duration: 380.ms, curve: M.ease).slideY(begin: 0.04, curve: M.ease),
            ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loam = ref.watch(gameProvider.select((g) => g.loam));
    final inbox = ref.watch(gameProvider.select((g) => g.crates.length + g.packets));
    final now = DateTime.now();
    final greeting = now.hour < 12 ? 'Good morning' : (now.hour < 18 ? 'Good afternoon' : 'Good evening');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}'.toUpperCase(), style: T.caps),
              const SizedBox(height: 6),
              Text(greeting, style: T.display),
            ],
          ),
        ),
        Pressable(
          onTap: () => showToast(ref, 'Greenhouse and Seed Packets are next'),
          child: Container(
            height: 40,
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(R.pill),
              border: Border.all(color: C.line),
            ),
            child: Row(
              children: [
                const LoamCoin(size: 22),
                const SizedBox(width: 6),
                CountUp(loam, style: T.num.copyWith(fontSize: 14)),
              ],
            ),
          ),
        ),
        const SizedBox(width: S.x2),
        Pressable(
          onTap: () => showToast(ref, 'Rewards inbox is next'),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: C.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: C.line),
                  ),
                  child: const Center(child: Icon(PhosphorIconsRegular.gift, size: 20, color: C.ink)),
                ),
                if (inbox > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: C.clay,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: C.paper, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text('$inbox', style: T.num.copyWith(fontSize: 10, color: Colors.white)),
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

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: T.stat),
          const SizedBox(height: 2),
          Text(label, style: T.small),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('YOUR IMPACT', style: T.caps),
        const SizedBox(height: S.x3),
        IntrinsicHeight(
          child: Row(
            children: [
              stat('${game.kgDiverted.toStringAsFixed(1)} kg', 'kept from landfill'),
              const Hairline(vertical: true),
              const SizedBox(width: S.x4),
              stat('${game.co2eAvoided.toStringAsFixed(1)} kg', 'CO₂e avoided'),
              const Hairline(vertical: true),
              const SizedBox(width: S.x4),
              stat('\$${game.dollarsSaved.toStringAsFixed(0)}', 'fertilizer saved'),
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        Text('Estimates from what you\'ve logged.', style: T.small.copyWith(color: C.faint, fontSize: 11)),
      ],
    );
  }
}
