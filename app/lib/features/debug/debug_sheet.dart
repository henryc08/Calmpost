import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/mock_repository.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';

/// Hidden demo controls (long-press Wren). Flips the mock bin between states.
class DebugSheet extends ConsumerWidget {
  const DebugSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(scenarioProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const IconBlob(PhosphorIconsFill.flask, tone: Tone.moss, size: 40),
            const SizedBox(width: S.x3),
            Expanded(child: Text('Demo controls', style: T.h2)),
          ],
        ),
        const SizedBox(height: S.x2),
        Text('Switch what the bin\'s sensors report.', style: T.body),
        const SizedBox(height: S.x4),
        for (final s in Scenario.values)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x2),
            child: ChunkyButton(
              label: s.label,
              uppercase: false,
              variant: s == current ? ChunkyVariant.moss : ChunkyVariant.white,
              onPressed: () {
                ref.read(scenarioProvider.notifier).state = s;
                Navigator.of(context).pop();
              },
            ),
          ),
        const SizedBox(height: S.x2),
        ChunkyButton(
          label: 'Reset game progress',
          uppercase: false,
          variant: ChunkyVariant.ghost,
          onPressed: () {
            ref.read(gameProvider.notifier).resetDemo();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
