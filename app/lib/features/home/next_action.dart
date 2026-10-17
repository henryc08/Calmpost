import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models.dart';
import '../../domain/xp_rules.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// The one thing to do next, worked out from the live readings.
class NextActionCard extends StatelessWidget {
  const NextActionCard({super.key, required this.suggestion, required this.ready, required this.onLog});
  final Suggestion suggestion;
  final bool ready;
  final ValueChanged<FoodItem?> onLog;

  @override
  Widget build(BuildContext context) {
    final (title, icon, tint, color) = ready
        ? ('Harvest the bottom layer', PhosphorIconsRegular.basket, C.leafSoft, C.leaf)
        : switch (suggestion.balance) {
            Balance.needsBrowns => ('Add something dry', PhosphorIconsRegular.package, C.waterSoft, C.water),
            Balance.needsGreens => ('Add fresh scraps', PhosphorIconsRegular.carrot, C.amberSoft, C.amber),
            Balance.balanced => ('Keep it balanced', PhosphorIconsRegular.scales, C.leafSoft, C.leaf),
          };

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('NEXT BEST ACTION', style: T.caps, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const Badge2('+${Xp.followedSuggestion} XP', color: C.leaf, background: C.leafSoft),
            ],
          ),
          const SizedBox(height: S.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: T.title),
                    const SizedBox(height: S.x1),
                    Text(suggestion.line, style: T.body),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x4),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [for (final f in suggestion.add) Chip2(f.name, icon: f.icon, color: color, onTap: () => onLog(f))],
          ),
          const SizedBox(height: S.x4),
          Row(
            children: [
              Expanded(
                child: Text(
                  suggestion.avoid.isEmpty ? '' : 'Skip ${suggestion.avoid.take(2).map((f) => f.name.toLowerCase()).join(' and ')} for now.',
                  style: T.small,
                ),
              ),
              const SizedBox(width: S.x3),
              Flexible(
                child: PillButton(label: 'Log an item', icon: PhosphorIconsBold.arrowRight, onTap: () => onLog(null)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
