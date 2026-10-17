import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models.dart';
import '../../state/game.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Today's three care quests.
class TodayQuests extends ConsumerWidget {
  const TodayQuests({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(gameProvider.select((g) => g.quests));
    final now = DateTime.now();
    final left = DateTime(now.year, now.month, now.day + 1).difference(now);
    final done = quests.where((q) => q.claimed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('TODAY', style: T.caps)),
            Text('$done of ${quests.length} · resets in ${left.inHours}h ${left.inMinutes % 60}m', style: T.small),
          ],
        ),
        const SizedBox(height: S.x1),
        for (final (i, q) in quests.indexed) ...[if (i > 0) const Hairline(), _QuestRow(q)],
      ],
    );
  }
}

class _QuestRow extends ConsumerWidget {
  const _QuestRow(this.q);
  final Quest q;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claimable = q.done && !q.claimed;
    final progress = q.unit.isEmpty ? '${q.progress.floor()}/${q.goal.floor()}' : '${q.progress.toStringAsFixed(1)}/${q.goal.floor()} ${q.unit}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x4),
      child: Row(
        children: [
          AnimatedContainer(
            duration: M.base,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: q.claimed ? C.leaf : Colors.transparent,
              border: Border.all(color: q.claimed ? C.leaf : (q.done ? C.leaf : C.faint), width: 1.5),
            ),
            child: q.claimed ? const Icon(PhosphorIconsBold.check, size: 13, color: Colors.white) : null,
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.title,
                  style: T.heading.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: q.claimed ? C.muted : C.ink,
                    decoration: q.claimed ? TextDecoration.lineThrough : null,
                    decorationColor: C.faint,
                  ),
                ),
                const SizedBox(height: S.x2),
                Row(
                  children: [
                    Expanded(
                      child: ThinBar(value: q.progress / q.goal, color: q.done ? C.leaf : C.ink2),
                    ),
                    const SizedBox(width: S.x2),
                    Text(progress, style: T.small.copyWith(fontSize: 11.5)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: S.x4),
          SizedBox(
            width: 74,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: claimable
                    ? PillButton(label: 'Claim', dense: true, onTap: () => ref.read(gameProvider.notifier).claimQuest(q.id))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('+${q.xp} XP', style: T.num.copyWith(fontSize: 12, color: q.claimed ? C.faint : C.ink2)),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const LoamCoin(size: 12),
                              const SizedBox(width: 3),
                              Text('${q.loam}', style: T.num.copyWith(fontSize: 12, color: q.claimed ? C.faint : C.loam)),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
