import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models.dart';
import '../../domain/xp_rules.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// The one thing to do next, worked out from the live readings. Open layout,
/// no card.
class NextAction extends StatelessWidget {
  const NextAction({super.key, required this.suggestion, required this.ready, required this.onLog});
  final Suggestion suggestion;
  final bool ready;
  final ValueChanged<FoodItem?> onLog;

  @override
  Widget build(BuildContext context) {
    final (title, color) = ready
        ? ('Harvest the bottom layer', C.leaf)
        : switch (suggestion.balance) {
            Balance.needsBrowns => ('Add something dry', C.water),
            Balance.needsGreens => ('Add fresh scraps', C.amber),
            Balance.balanced => ('Keep it balanced', C.leaf),
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('NEXT BEST ACTION', style: T.caps)),
            Text('+${Xp.followedSuggestion} XP', style: T.num.copyWith(fontSize: 12, color: C.leaf)),
          ],
        ),
        const SizedBox(height: S.x3),
        Text(title, style: T.title.copyWith(fontSize: 26)),
        const SizedBox(height: S.x2),
        Text(suggestion.line, style: T.body),
        const SizedBox(height: S.x4),
        for (final f in suggestion.add)
          Pressable(
            onTap: () => onLog(f),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Icon(f.icon, size: 18, color: color),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(f.name, style: T.heading.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                  const Icon(PhosphorIconsRegular.plus, size: 16, color: C.muted),
                ],
              ),
            ),
          ),
        const SizedBox(height: S.x3),
        Pressable(
          onTap: () => onLog(null),
          child: Row(
            children: [
              Text('Log something else', style: T.button.copyWith(color: C.forest)),
              const SizedBox(width: 6),
              const Icon(PhosphorIconsBold.arrowRight, size: 15, color: C.forest),
            ],
          ),
        ),
      ],
    );
  }
}
