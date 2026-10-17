import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models.dart';
import '../../domain/xp_rules.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import '../../ui/info_dot.dart';

/// The main Home section: what the bin wants right now, as three tappable
/// items with what each will do, plus what to hold off on.
class WhatToAdd extends StatelessWidget {
  const WhatToAdd({super.key, required this.suggestion, required this.snapshot, required this.onPick});
  final Suggestion suggestion;
  final BinSnapshot snapshot;

  /// Called with an item (open its verdict in Log) or null (open Log).
  final ValueChanged<FoodItem?> onPick;

  @override
  Widget build(BuildContext context) {
    final ready = snapshot.bottomMeasured && snapshot.bottomStage == Stage.ready;
    final (title, accent) = ready
        ? ('Harvest the bottom layer', C.leaf)
        : switch (suggestion.need) {
            BinNeed.browns => ('Add something dry', C.water),
            BinNeed.greens => ('Add fresh scraps', C.amber),
            BinNeed.water => ('Just a little water', C.water),
            BinNeed.mix => ('Give it a stir', C.leaf),
            BinNeed.nothing => (!snapshot.topMeasured || snapshot.readingsStale ? 'Check the bin first' : 'Nothing to add today', C.leaf),
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('WHAT TO ADD', info: InfoTip.whatToAdd, trailing: suggestion.add.isEmpty ? null : const PinkPill('+${Xp.followedSuggestion} XP')),
        const SizedBox(height: S.x3),
        Text(title, style: T.title.copyWith(fontSize: 28)),
        const SizedBox(height: S.x2),
        Text(suggestion.line, style: T.body),
        const SizedBox(height: S.x5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, f) in suggestion.add.take(3).indexed)
              Expanded(
                child: _Pick(
                  item: f,
                  accent: accent,
                  effect: _effect(f, snapshot),
                  onTap: () => onPick(f),
                ).animate(delay: (120 + i * 70).ms).fadeIn(duration: 360.ms).scale(begin: const Offset(0.92, 0.92), curve: M.ease),
              ),
          ],
        ),
        if (suggestion.avoid.isNotEmpty) ...[
          const SizedBox(height: S.x5),
          Wrap(
            spacing: S.x3,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Hold off on', style: T.small.copyWith(color: C.ink2)),
              for (final f in suggestion.avoid.take(3))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(color: C.clay, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(f.name, style: T.small),
                  ],
                ),
            ],
          ),
        ],
        const SizedBox(height: S.x4),
        Pressable(
          onTap: () => onPick(null),
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

  static String _effect(FoodItem f, BinSnapshot s) {
    if (f.category == FoodCategory.brown) return s.topMoisture > 60 ? 'Soaks up water' : 'Adds carbon + air';
    if (f.wet) return s.topMoisture < 40 ? 'Adds moisture' : 'Adds nitrogen';
    return 'Adds nitrogen';
  }
}

class _Pick extends StatelessWidget {
  const _Pick({required this.item, required this.accent, required this.effect, required this.onTap});
  final FoodItem item;
  final Color accent;
  final String effect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: C.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
                ),
                child: Icon(item.icon, size: 32, color: accent),
              ),
              Positioned(
                right: -10,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: C.pink,
                    borderRadius: BorderRadius.circular(R.pill),
                    border: Border.all(color: C.paper, width: 2),
                  ),
                  child: Text('+${Xp.followedSuggestion}', style: T.num.copyWith(fontSize: 11, color: C.ink)),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          Text(item.name, textAlign: TextAlign.center, maxLines: 2, style: T.heading.copyWith(fontSize: 13.5, height: 1.25)),
          const SizedBox(height: 3),
          Text(effect, textAlign: TextAlign.center, maxLines: 2, style: T.small.copyWith(fontSize: 11.5)),
        ],
      ),
    );
  }
}
