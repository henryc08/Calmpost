import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/game.dart';
import '../../ui/ui.dart';

/// Daily quests with Duolingo-style progress bars and reward chests.
class QuestsCard extends ConsumerWidget {
  const QuestsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(gameProvider.select((g) => g.quests));
    final now = DateTime.now();
    final left = DateTime(now.year, now.month, now.day + 1).difference(now);

    return Slab(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Daily quests', style: T.h2)),
              Tag('${left.inHours}h ${left.inMinutes % 60}m left', tone: Tone.flame, dense: true),
            ],
          ),
          const SizedBox(height: S.x2),
          for (final (i, q) in quests.indexed) ...[if (i > 0) const Divider(height: 1, thickness: 2, color: C.border), _QuestRow(q)],
        ],
      ),
    );
  }
}

class _QuestRow extends ConsumerWidget {
  const _QuestRow(this.q);
  final Quest q;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claimable = q.done && !q.claimed;
    final progressLabel = q.unit.isEmpty ? '${q.progress.floor()} / ${q.goal.floor()}' : '${q.progress.toStringAsFixed(1)} / ${q.goal.floor()} ${q.unit}';
    Widget chest = Chest(size: 44, dim: !q.done || q.claimed, open: q.claimed ? 1 : 0);
    if (claimable) {
      chest = chest.animate(onPlay: (c) => c.repeat()).shake(hz: 4, rotation: 0.06, offset: Offset.zero, duration: 600.ms).then(delay: 900.ms);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        children: [
          IconBlob(q.icon, tone: q.claimed ? Tone.leaf : Tone.sun, size: 40, iconSize: 22),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.title, style: T.bodyStrong.copyWith(fontSize: 14.5, color: q.claimed ? C.muted : C.ink)),
                const SizedBox(height: S.x2),
                ProgressBar(value: q.progress / q.goal, color: q.done ? C.leaf : C.sun, height: 16, label: progressLabel),
              ],
            ),
          ),
          const SizedBox(width: S.x3),
          Pressable(
            onTap: claimable ? () => ref.read(gameProvider.notifier).claimQuest(q.id) : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                chest,
                if (claimable)
                  Text('CLAIM', style: T.eyebrow.copyWith(color: C.sunLip, fontSize: 11))
                else
                  Text(q.claimed ? 'DONE' : '+${q.xp} XP', style: T.eyebrow.copyWith(fontSize: 10.5, color: q.claimed ? C.leaf : C.faint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
