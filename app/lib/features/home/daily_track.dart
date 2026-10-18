import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/reward_reveal.dart';
import '../../state/game.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import '../../ui/info_dot.dart';

/// Today's XP fills a track toward three reward nodes you tap to claim.
class DailyTrack extends ConsumerWidget {
  const DailyTrack({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xp = ref.watch(gameProvider.select((g) => g.xpToday));
    final claimed = ref.watch(gameProvider.select((g) => g.dailyClaimed));
    final pending = ref.watch(gameActionsProvider);
    final goal = dailyGoals.last;
    final ready = [for (var i = 0; i < dailyGoals.length; i++) xp >= dailyGoals[i] && !claimed.contains(i)];

    Future<void> claim(int i) async {
      final reward = await ref.read(gameProvider.notifier).claimDailyAsync(i);
      if (reward == null || !context.mounted) return;
      await showRewardReveal(
        context,
        title: 'Daily reward',
        icon: PhosphorIconsFill.gift,
        items: [
          if (reward.loam > 0) RevealItem(const LoamCoin(size: 26), '+${reward.loam}', 'Loam'),
          if (reward.crate != null) RevealItem(const Icon(PhosphorIconsFill.package, size: 26, color: C.pink), '+1', crateTitle(reward.crate!)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'DAILY GOAL',
          info: InfoTip.xp,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountUp(xp.clamp(0, goal), style: T.num.copyWith(fontSize: 14)),
              Text(' / $goal XP', style: T.num.copyWith(fontSize: 14, color: C.muted)),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        SizedBox(
          height: 44,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth - 22;
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: 0,
                    right: 22,
                    child: ThinBar(value: xp / goal, color: C.pink, track: C.sunk, height: 10),
                  ),
                  for (var i = 0; i < dailyGoals.length; i++)
                    Positioned(
                      left: w * dailyGoals[i] / goal - 22 + 11,
                      child: _Node(
                        reached: xp >= dailyGoals[i],
                        claimed: claimed.contains(i),
                        isCrate: dailyRewards[i].crate != null,
                        onTap: ready[i] && !pending.contains('daily:$i') ? () => claim(i) : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: S.x2),
        SizedBox(
          height: 30,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth - 22;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < dailyGoals.length; i++)
                    Positioned(
                      top: 0,
                      width: 96,
                      left: i == dailyGoals.length - 1 ? null : w * dailyGoals[i] / goal - 48 + 11 + (i == 0 ? 0 : 0),
                      right: i == dailyGoals.length - 1 ? 0 : null,
                      child: Column(
                        crossAxisAlignment: i == dailyGoals.length - 1 ? CrossAxisAlignment.end : CrossAxisAlignment.center,
                        children: [
                          Text('${dailyGoals[i]} XP', style: T.num.copyWith(fontSize: 11, color: ready[i] ? C.ink : C.muted)),
                          Text(
                            dailyRewards[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.small.copyWith(
                              fontSize: 10.5,
                              color: ready[i] ? C.ink : C.muted,
                              fontWeight: ready[i] ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: S.x2),
        Text(
          pending.any((key) => key.startsWith('daily:'))
              ? 'Claiming your reward…'
              : ready.contains(true)
              ? 'A reward is ready. Tap it to claim.'
              : 'Earn XP by caring for the bin: follow a tip, check your layers, finish quests.',
          style: T.small,
        ),
      ],
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.reached, required this.claimed, required this.isCrate, required this.onTap});
  final bool reached;
  final bool claimed;
  final bool isCrate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ready = reached && !claimed;
    final size = isCrate ? 44.0 : 36.0;
    Widget node = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: claimed ? C.forest : (ready ? C.pink : C.surface),
        shape: BoxShape.circle,
        border: Border.all(color: claimed || ready ? C.paper : C.line, width: claimed || ready ? 3 : 1.5),
      ),
      child: Icon(
        claimed ? PhosphorIconsBold.check : (isCrate ? PhosphorIconsFill.package : PhosphorIconsFill.gift),
        size: isCrate ? 20 : 16,
        color: claimed ? C.onForest : (ready ? C.ink : C.faint),
      ),
    );
    if (ready) {
      node = node
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(begin: const Offset(1, 1), end: const Offset(1.12, 1.12), duration: 650.ms, curve: Curves.easeInOut);
    }
    return Pressable(onTap: onTap, scale: 0.9, child: node);
  }
}
