import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/toast.dart';
import '../../data/collectibles.dart';
import '../../domain/gacha.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../state/game.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'collectible_art.dart';
import 'pull_reveal.dart';
import 'collectible_details.dart';

/// The Greenhouse: spend Loam on Seed Packets (the gacha), see what Loam is
/// for, browse and equip your collection.
class GreenhouseScreen extends ConsumerStatefulWidget {
  const GreenhouseScreen({super.key});

  @override
  ConsumerState<GreenhouseScreen> createState() => _GreenhouseScreenState();
}

enum _Filter { all, specimen, finish, title }

class _GreenhouseScreenState extends ConsumerState<GreenhouseScreen> {
  _Filter _filter = _Filter.all;
  bool _pulling = false;

  Future<void> _pull(int count, {required bool fromPackets}) async {
    if (_pulling) return;
    setState(() => _pulling = true);
    final game = ref.read(gameProvider.notifier);
    final live = game.isLive;
    try {
      final out = await game.pullAsync(count, fromPackets: fromPackets);
      if (!mounted) return;
      if (out == null) {
        // Live failures already carry feedback from the controller. A timeout
        // is not evidence of insufficient funds (the server may have saved it).
        if (!live) showToast(ref, fromPackets ? 'No Seed Packets left' : 'Not enough Loam yet');
        return;
      }
      await showPullReveal(context, out);
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(gameProvider);
    // Live and demo use the same supported batches; the server accepts 1 or 10.
    final packetCount = g.packets >= 10 ? 10 : 1;
    final pulling = _pulling || ref.watch(gameActionsProvider).contains('pull');
    final pity = g.pity;
    final items = collectibles.where((c) => _filter == _Filter.all || c.type.name == _filter.name).toList();

    return Scaffold(
      backgroundColor: C.paper,
      body: BrandPage(
        title: 'Greenhouse',
        subtitle: 'Open Seed Packets, grow your collection',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
              decoration: BoxDecoration(color: C.onBrand, borderRadius: BorderRadius.circular(R.pill)),
              child: Row(
                children: [
                  const LoamCoin(size: 20),
                  const SizedBox(width: 5),
                  CountUp(g.loam, style: T.num.copyWith(fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(width: S.x2),
            Pressable(
              onTap: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.all(S.x1),
                child: Icon(PhosphorIconsBold.x, color: C.onBrand, size: 22),
              ),
            ),
          ],
        ),
        hero: Column(
          children: [
            const SeedPacketArt(size: 120).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: -4, end: 4, duration: 1600.ms, curve: Curves.easeInOut),
            const SizedBox(height: S.x4),
            if (g.packets > 0) ...[
              SizedBox(
                width: double.infinity,
                child: PillButton(
                  label: packetCount == 1 ? 'Open your Seed Packet' : 'Open 10 Seed Packets',
                  icon: PhosphorIconsBold.sparkle,
                  color: C.pink,
                  textColor: C.ink,
                  onTap: pulling ? null : () => _pull(packetCount, fromPackets: true),
                ),
              ),
              const SizedBox(height: S.x2),
            ],
            Row(
              children: [
                Expanded(
                  child: _BuyButton(label: '1 pull', price: packetPrice, enabled: !pulling && g.loam >= packetPrice, onTap: () => _pull(1, fromPackets: false)),
                ),
                const SizedBox(width: S.x2),
                Expanded(
                  child: _BuyButton(
                    label: '10 pulls',
                    price: tenPackPrice,
                    enabled: !pulling && g.loam >= tenPackPrice,
                    onTap: () => _pull(10, fromPackets: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.x3),
            if (pulling || g.loam < packetPrice) ...[
              Text(pulling ? 'Opening Seed Packets…' : 'Earn ${packetPrice - g.loam} more Loam for a pull.', style: T.small.copyWith(color: C.onBrand)),
              const SizedBox(height: S.x2),
            ],
            Text(
              'Epic or better within ${epicPity - pity.sinceEpic} pulls · Legendary within ${legendaryPity - pity.sinceLegendary}',
              textAlign: TextAlign.center,
              style: T.small.copyWith(color: C.onBrandMuted),
            ),
          ],
        ),
        children: [
          const SectionLabel('ACTIVE SEED'),
          const SizedBox(height: S.x3),
          Text(
            g.activeSeed == null ? 'No seed active yet' : '${collectibleById[g.activeSeed]!.name} · ${buffLabel(seedBuffs[g.activeSeed]!)}',
            style: T.heading,
          ),
          const SizedBox(height: S.x2),
          Text(
            'Tap an owned plant to activate its buff and read its field note. Rarer seeds have stronger, specialized buffs. Only one is active; duplicates never stack.',
            style: T.small,
          ),
          const SectionBreak(),
          const _WhatLoamIsFor(),
          const SectionBreak(),
          SectionLabel('COLLECTION', trailing: Text('${g.collected} / ${collectibles.length}', style: T.num.copyWith(fontSize: 13))),
          const SizedBox(height: S.x3),
          PaperSegments<_Filter>(
            values: _Filter.values,
            selected: _filter,
            label: (f) => switch (f) {
              _Filter.all => 'All',
              _Filter.specimen => 'Plants',
              _Filter.finish => 'Finishes',
              _Filter.title => 'Titles',
            },
            onChanged: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: S.x4),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: S.x4,
            crossAxisSpacing: S.x2,
            // Fixed art plus two scaled text lines; width-based aspect ratios
            // can clip newly unlocked names at Android accessibility sizes.
            mainAxisExtent: 76 + MediaQuery.textScalerOf(context).scale(11.5) * 2.4,
            children: [
              for (final c in items)
                _CollectionTile(
                  item: c,
                  count: g.owned[c.id] ?? 0,
                  equipped: c.id == g.equippedFinish || c.id == g.equippedTitle || c.id == g.activeSeed,
                  onTap: (g.owned[c.id] ?? 0) > 0 ? () => showCollectibleDetails(context, c) : null,
                ),
            ],
          ),
          const SectionBreak(),
          const _OddsTable(),
        ].animate(interval: M.stagger).fadeIn(duration: 320.ms, curve: M.ease),
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({required this.label, required this.price, required this.enabled, required this.onTap});
  final String label;
  final int price;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: enabled ? onTap : null,
      scale: 0.96,
      child: AnimatedOpacity(
        duration: M.base,
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: 46,
          decoration: BoxDecoration(color: C.onBrand, borderRadius: BorderRadius.circular(R.pill)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: T.button.copyWith(color: C.brandDeep)),
              const SizedBox(width: S.x2),
              const LoamCoin(size: 16),
              const SizedBox(width: 3),
              Text('$price', style: T.num.copyWith(fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Why Loam matters: what it buys and how you earn it.
class _WhatLoamIsFor extends ConsumerWidget {
  const _WhatLoamIsFor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider);
    final buying = ref.watch(gameActionsProvider).contains('lid-lock');
    final full = g.streak.lidLocks >= maxLidLocks;
    final canLock = !buying && g.loam >= lidLockPrice && !full;

    Widget row(Widget icon, String title, String sub, Widget? trailing) => Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        children: [
          SizedBox(width: 36, child: Center(child: icon)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.heading.copyWith(fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(sub, style: T.small),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('WHAT LOAM IS FOR'),
        const SizedBox(height: S.x1),
        row(const SeedPacketArt(size: 30), 'Seed Packets · $packetPrice Loam', 'Plants, ring finishes and titles for your collection', null),
        const Hairline(),
        row(
          const Icon(PhosphorIconsFill.shieldCheck, size: 26, color: C.pinkDeep),
          'Lid Lock · $lidLockPrice Loam',
          'Saves your streak if you miss a day · you have ${g.streak.lidLocks} of $maxLidLocks',
          PillButton(
            label: buying
                ? 'Buying…'
                : full
                ? 'Full'
                : 'Buy',
            dense: true,
            onTap: canLock
                ? () async {
                    final bought = await ref.read(gameProvider.notifier).buyLidLockAsync();
                    if (bought && context.mounted) showToast(ref, 'Lid Lock added. Your streak is safer.');
                  }
                : null,
          ),
        ),
        const Hairline(),
        row(const LoamCoin(size: 26), 'How you earn it', 'Quests 10–25 · daily goal 15–30 · streak milestones · crates · league finish · duplicates', null),
        const SizedBox(height: S.x1),
        Text('Loam is never sold for real money.', style: T.small.copyWith(fontSize: 11)),
      ],
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.item, required this.count, required this.equipped, required this.onTap});
  final Collectible item;
  final int count;
  final bool equipped;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final owned = count > 0;
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              owned ? CollectibleBadge(item: item, size: 62) : LockedBadge(rarity: item.rarity, size: 62),
              if (count > 1)
                Positioned(
                  right: -4,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(R.pill)),
                    child: Text('×$count', style: T.num.copyWith(fontSize: 10, color: Colors.white)),
                  ),
                ),
              if (equipped)
                Positioned(
                  left: -2,
                  bottom: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: C.pink,
                      shape: BoxShape.circle,
                      border: Border.all(color: C.paper, width: 2),
                    ),
                    child: const Icon(PhosphorIconsBold.check, size: 10, color: C.ink),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            owned ? item.name : '???',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.small.copyWith(fontSize: 11.5, color: owned ? C.ink : C.faint, height: 1.2),
          ),
        ],
      ),
    );
  }
}

class _OddsTable extends StatelessWidget {
  const _OddsTable();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('ODDS PER PULL', trailing: Text('10 pulls: one Rare+ guaranteed', style: T.small.copyWith(fontSize: 11))),
        const SizedBox(height: S.x2),
        for (final r in Rarity.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: rarityColor(r), shape: BoxShape.circle),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Text(rarityName(r), style: T.heading.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Text('${(rarityOdds[r]! * 100).toStringAsFixed(r == Rarity.epic || r == Rarity.legendary ? 1 : 0)}%', style: T.num),
                const SizedBox(width: S.x5),
                SizedBox(
                  width: 92,
                  child: Text('dupe +${duplicateRefund[r]} Loam', textAlign: TextAlign.right, style: T.small.copyWith(fontSize: 11.5)),
                ),
              ],
            ),
          ),
        const SizedBox(height: S.x2),
        Text('Pity: an Epic or better is guaranteed within $epicPity pulls, a Legendary within $legendaryPity.', style: T.small),
      ],
    );
  }
}
