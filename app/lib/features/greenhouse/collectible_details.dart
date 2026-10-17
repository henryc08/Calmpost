import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/toast.dart';
import '../../domain/gacha.dart';
import '../../state/game.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'collectible_art.dart';
import 'seed_learning.dart';

Future<void> showCollectibleDetails(BuildContext context, Collectible item) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: C.paper,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.hero))),
  builder: (_) => _Details(item: item),
);

class _Details extends ConsumerStatefulWidget {
  const _Details({required this.item});
  final Collectible item;
  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.item;
    final game = ref.watch(gameProvider);
    final owned = (game.owned[c.id] ?? 0) > 0;
    final plant = c.type == CollectibleType.specimen;
    final equipped = c.id == game.equippedFinish || c.id == game.equippedTitle || c.id == game.activeSeed;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(S.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CollectibleBadge(item: c, size: 100),
            const SizedBox(height: S.x3),
            Text(c.name, style: T.title),
            const SizedBox(height: S.x2),
            RarityPill(c.rarity),
            const SizedBox(height: S.x4),
            if (plant) SeedLearning(id: c.id) else Text(c.blurb, style: T.body),
            const SizedBox(height: S.x4),
            if (plant) Text('One active seed at a time. Activating this replaces your current buff. Duplicate copies do not stack.', style: T.small),
            const SizedBox(height: S.x3),
            Text(owned ? 'Owned ×${game.owned[c.id]}' : 'Not unlocked yet', style: T.small),
            const SizedBox(height: S.x3),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                label: _saving
                    ? 'Saving…'
                    : equipped
                    ? (plant ? 'Active seed' : 'Equipped')
                    : (plant ? 'Activate seed' : 'Equip'),
                onTap: !owned || equipped || _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        final saved = await ref.read(gameProvider.notifier).equipAsync(c);
                        if (!mounted) return;
                        setState(() => _saving = false);
                        if (saved) showToast(ref, '${c.name} ${plant ? 'activated' : 'equipped'}');
                      },
              ),
            ),
            const SizedBox(height: S.x2),
            PillButton(label: 'Done', dense: true, color: C.sunk, textColor: C.ink, onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}
