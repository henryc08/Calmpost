import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/xp_rules.dart';
import '../../state/game.dart';
import '../../app/lid_lock_card.dart';
import '../../ui/ui.dart';

/// Streak details: the last four weeks, Lid Locks, next milestone.
class StreakSheet extends ConsumerWidget {
  const StreakSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider);
    final s = g.streak;
    final lit = s.caredOn(DateTime.now());
    final today = dayOf(DateTime.now());
    final last = s.lastCareDay == null ? null : dayOf(s.lastCareDay!);
    final next = streakMilestones.firstWhere((m) => m > s.days, orElse: () => streakMilestones.last);
    final prev = streakMilestones.lastWhere((m) => m <= s.days, orElse: () => 0);

    bool litDay(DateTime d) => last != null && !d.isAfter(last) && last.difference(d).inDays < s.days;

    // Four weeks ending this week (Mon–Sun rows).
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final start = monday.subtract(const Duration(days: 21));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flame(size: 64, lit: lit, flicker: lit),
            const SizedBox(width: S.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${s.days}', style: T.numXL.copyWith(color: lit ? C.flame : C.muted)),
                      const SizedBox(width: S.x2),
                      Text('day streak', style: T.h2.copyWith(color: lit ? C.flame : C.muted)),
                    ],
                  ),
                  const SizedBox(height: S.x1),
                  Text(lit ? 'You\'ve cared for the bin today. Nice!' : 'Check in, or follow a tip, to light today\'s flame.', style: T.body),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x5),
        Slab(
          child: Column(
            children: [
              Row(
                children: [
                  for (final l in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                    Expanded(
                      child: Center(child: Text(l, style: T.eyebrow)),
                    ),
                ],
              ),
              const SizedBox(height: S.x2),
              for (var w = 0; w < 4; w++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Expanded(
                          child: Center(
                            child: _Day(
                              date: start.add(Duration(days: w * 7 + d)),
                              lit: litDay(start.add(Duration(days: w * 7 + d))),
                              today: start.add(Duration(days: w * 7 + d)) == today,
                              future: start.add(Duration(days: w * 7 + d)).isAfter(today),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        Slab(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Next milestone', style: T.title),
                  const Spacer(),
                  Text('$next days', style: T.numM.copyWith(color: C.flame)),
                ],
              ),
              const SizedBox(height: S.x3),
              ProgressBar(value: (s.days - prev) / (next - prev), color: C.flame, label: '${s.days} / $next'),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        const LidLockCard(),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.date, required this.lit, required this.today, required this.future});
  final DateTime date;
  final bool lit;
  final bool today;
  final bool future;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: lit ? C.flame : (future ? Colors.transparent : C.track),
        shape: BoxShape.circle,
        border: today ? Border.all(color: C.flame, width: 2.5) : null,
      ),
      alignment: Alignment.center,
      child: lit
          ? const Icon(PhosphorIconsFill.fire, size: 16, color: C.sun)
          : Text('${date.day}', style: T.small.copyWith(fontSize: 11.5, color: future ? C.faint : C.muted)),
    );
  }
}
