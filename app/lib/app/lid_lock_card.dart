import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../state/game.dart';
import '../ui/ui.dart';

/// Lid Locks: streak freezes. Shared by the streak sheet and the shop.
class LidLockCard extends ConsumerWidget {
  const LidLockCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider);
    final locks = g.streak.lidLocks;
    final canBuy = locks < maxLidLocks && g.acorns >= lidLockPrice;
    return Slab(
      color: C.skyTint,
      edge: C.sky.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < maxLidLocks; i++)
                Padding(
                  padding: const EdgeInsets.only(right: S.x2),
                  child: Icon(PhosphorIconsFill.shieldCheck, size: 34, color: i < locks ? C.sky : C.borderDark)
                      .animate(target: i < locks ? 1 : 0)
                      .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), curve: Curves.elasticOut, duration: 600.ms),
                ),
              const SizedBox(width: S.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lid Lock', style: T.title.copyWith(color: C.skyLip)),
                    Text('Protects your streak for one missed day. Hold up to $maxLidLocks.', style: T.small.copyWith(color: C.inkSoft)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          ChunkyButton(
            label: locks >= maxLidLocks ? 'Fully stocked' : 'Get one · $lidLockPrice acorns',
            variant: ChunkyVariant.sky,
            height: 46,
            onPressed: canBuy
                ? () {
                    if (ref.read(gameProvider.notifier).buyLidLock()) Sfx.reward(Sound.chest);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
