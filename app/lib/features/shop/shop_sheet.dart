import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/lid_lock_card.dart';
import '../../state/game.dart';
import '../../ui/ui.dart';

/// Spend acorns: Lid Locks and Wren's wardrobe. Acorns are never sold for money.
class ShopSheet extends ConsumerWidget {
  const ShopSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider);
    const hats = [WrenHat.sprout, WrenHat.straw, WrenHat.beanie, WrenHat.flowers, WrenHat.none];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Shop', style: T.h1)),
            const AcornIcon(size: 26),
            const SizedBox(width: S.x1),
            CountUp(g.acorns, style: T.numL.copyWith(color: const Color(0xFFB06A2C))),
          ],
        ),
        const SizedBox(height: S.x1),
        Text('Earn acorns from quests, streaks and harvests.', style: T.body),
        const SizedBox(height: S.x5),
        Text('Power-ups', style: T.h2),
        const SizedBox(height: S.x3),
        const LidLockCard(),
        const SizedBox(height: S.x5),
        Text('Wren\'s wardrobe', style: T.h2),
        const SizedBox(height: S.x3),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: S.x3,
          crossAxisSpacing: S.x3,
          childAspectRatio: 0.74,
          children: [
            for (final h in hats)
              _HatTile(
                hat: h,
                owned: g.ownedHats.contains(h),
                equipped: g.hat == h,
                price: hatPrices[h] ?? 0,
                affordable: g.acorns >= (hatPrices[h] ?? 0),
                onTap: () {
                  final had = g.ownedHats.contains(h);
                  if (ref.read(gameProvider.notifier).buyOrEquipHat(h)) {
                    had ? Sfx.tap() : Sfx.reward(Sound.chest);
                  }
                },
              ),
          ].animate(interval: 40.ms).fadeIn().scale(begin: const Offset(0.9, 0.9)),
        ),
      ],
    );
  }
}

String _hatName(WrenHat h) => switch (h) {
  WrenHat.none => 'No hat',
  WrenHat.sprout => 'Sprout',
  WrenHat.straw => 'Sun hat',
  WrenHat.beanie => 'Beanie',
  WrenHat.flowers => 'Flower crown',
};

class _HatTile extends StatelessWidget {
  const _HatTile({required this.hat, required this.owned, required this.equipped, required this.price, required this.affordable, required this.onTap});
  final WrenHat hat;
  final bool owned;
  final bool equipped;
  final int price;
  final bool affordable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = owned || affordable;
    return MediaQuery.withClampedTextScaling(maxScaleFactor: 1.1, child: _tile(enabled));
  }

  Widget _tile(bool enabled) {
    return Slab(
      onTap: enabled ? onTap : null,
      edge: equipped ? C.leaf : C.border,
      color: equipped ? C.leafTint : C.surface,
      radius: R.button + 2,
      padding: const EdgeInsets.fromLTRB(S.x1, S.x2, S.x1, S.x2),
      child: Column(
        children: [
          Expanded(
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Wren(mood: WrenMood.happy, size: 84, hat: hat),
            ),
          ),
          Text(
            _hatName(hat),
            style: T.small.copyWith(color: C.ink, fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          const SizedBox(height: 2),
          if (equipped)
            Text('WEARING', style: T.eyebrow.copyWith(color: C.leaf, fontSize: 10.5))
          else if (owned)
            Text('OWNED', style: T.eyebrow.copyWith(fontSize: 10.5))
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsFill.acorn, size: 13, color: affordable ? const Color(0xFFC07A3A) : C.faint),
                const SizedBox(width: 2),
                Text('$price', style: T.numM.copyWith(fontSize: 13, color: affordable ? const Color(0xFFB06A2C) : C.faint)),
              ],
            ),
        ],
      ),
    );
  }
}
