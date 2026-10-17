import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Color, IconData;

import 'models.dart';

/// Plants have one equippable progression buff; finishes and titles are cosmetic.
/// No collectible changes measured health or compost safety advice.
enum CollectibleType { specimen, finish, title }

class Collectible {
  const Collectible({required this.id, required this.name, required this.type, required this.rarity, required this.icon, required this.color, this.blurb = ''});
  final String id;
  final String name;
  final CollectibleType type;
  final Rarity rarity;
  final IconData icon;

  /// Specimens: tint of the plant. Finishes: colour of the Bin World ring.
  final Color color;
  final String blurb;
}

/// Odds per pull. Always shown next to the pull buttons.
const rarityOdds = {Rarity.common: 0.60, Rarity.uncommon: 0.25, Rarity.rare: 0.11, Rarity.epic: 0.035, Rarity.legendary: 0.005};

/// Loam refunded for a duplicate.
const duplicateRefund = {Rarity.common: 5, Rarity.uncommon: 10, Rarity.rare: 25, Rarity.epic: 60, Rarity.legendary: 150};

const packetPrice = 100;
const tenPackPrice = 900;

/// Pity: an Epic or better within this many pulls, a Legendary within this many.
const epicPity = 30;
const legendaryPity = 80;

String rarityName(Rarity r) => switch (r) {
  Rarity.common => 'Common',
  Rarity.uncommon => 'Uncommon',
  Rarity.rare => 'Rare',
  Rarity.epic => 'Epic',
  Rarity.legendary => 'Legendary',
};

class PityState {
  const PityState({required this.sinceEpic, required this.sinceLegendary});
  final int sinceEpic;
  final int sinceLegendary;
}

class PullOutcome {
  const PullOutcome(this.item, {required this.isNew, required this.refund});
  final Collectible item;
  final bool isNew;
  final int refund;
}

/// Rolls one rarity, honouring the pity counters.
Rarity rollRarity(math.Random rng, PityState pity) {
  if (pity.sinceLegendary >= legendaryPity - 1) return Rarity.legendary;
  if (pity.sinceEpic >= epicPity - 1) return rng.nextDouble() < 0.125 ? Rarity.legendary : Rarity.epic;
  var r = rng.nextDouble();
  for (final e in rarityOdds.entries) {
    if (r < e.value) return e.key;
    r -= e.value;
  }
  return Rarity.common;
}

PityState advancePity(PityState p, Rarity got) =>
    PityState(sinceEpic: got.index >= Rarity.epic.index ? 0 : p.sinceEpic + 1, sinceLegendary: got == Rarity.legendary ? 0 : p.sinceLegendary + 1);

/// Pulls [count] packets. A 10-pull guarantees at least one Rare or better.
(List<Rarity>, PityState) rollPulls(math.Random rng, PityState pity, int count) {
  final out = <Rarity>[];
  var p = pity;
  for (var i = 0; i < count; i++) {
    var r = rollRarity(rng, p);
    final last = i == count - 1;
    if (count >= 10 && last && out.every((x) => x.index < Rarity.rare.index) && r.index < Rarity.rare.index) r = Rarity.rare;
    out.add(r);
    p = advancePity(p, r);
  }
  return (out, p);
}

Collectible pickOfRarity(math.Random rng, List<Collectible> catalog, Rarity r) {
  final pool = catalog.where((c) => c.rarity == r).toList();
  return pool[rng.nextInt(pool.length)];
}
