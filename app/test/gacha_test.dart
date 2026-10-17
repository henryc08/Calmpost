import 'dart:math' as math;

import 'package:calmpost/data/collectibles.dart';
import 'package:calmpost/domain/gacha.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/state/game.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('odds add up to 100%', () {
    expect(rarityOdds.values.reduce((a, b) => a + b), closeTo(1, 1e-9));
  });

  test('every rarity has collectibles to pull', () {
    for (final r in Rarity.values) {
      expect(collectibles.where((c) => c.rarity == r), isNotEmpty, reason: r.name);
    }
  });

  test('pity guarantees an Epic+ within 30 and a Legendary within 80', () {
    final rng = math.Random(1);
    expect(rollRarity(rng, const PityState(sinceEpic: epicPity - 1, sinceLegendary: 0)).index, greaterThanOrEqualTo(Rarity.epic.index));
    expect(rollRarity(rng, const PityState(sinceEpic: 0, sinceLegendary: legendaryPity - 1)), Rarity.legendary);

    var p = const PityState(sinceEpic: 0, sinceLegendary: 0);
    var sinceEpic = 0;
    for (var i = 0; i < 2000; i++) {
      final r = rollRarity(rng, p);
      sinceEpic = r.index >= Rarity.epic.index ? 0 : sinceEpic + 1;
      expect(sinceEpic, lessThan(epicPity));
      p = advancePity(p, r);
    }
  });

  test('a 10-pull always has a Rare or better', () {
    for (var seed = 0; seed < 300; seed++) {
      final (rarities, _) = rollPulls(math.Random(seed), const PityState(sinceEpic: 0, sinceLegendary: 0), 10);
      expect(rarities.any((r) => r.index >= Rarity.rare.index), isTrue);
    }
  });

  test('pulling spends Loam, adds to the collection, refunds duplicates', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final game = c.read(gameProvider.notifier);
    final before = c.read(gameProvider);
    final out = game.pull(1, fromPackets: false)!;
    final after = c.read(gameProvider);
    expect(after.loam, before.loam - packetPrice + out.first.refund);
    expect(after.owned[out.first.item.id], (before.owned[out.first.item.id] ?? 0) + 1);
    expect(game.pull(10, fromPackets: false), isNull, reason: 'not enough Loam for a 10-pull');

    final packets = after.packets;
    expect(game.pull(1, fromPackets: true), isNotNull);
    expect(c.read(gameProvider).packets, packets - 1);
  });

  test('equipping a finish changes the ring colour', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(gameProvider.notifier).equip(collectibleById['finish_mint']!);
    expect(c.read(gameProvider).ringColor, collectibleById['finish_mint']!.color);
    c.read(gameProvider.notifier).equip(collectibleById['finish_gold']!);
    expect(c.read(gameProvider).equippedFinish, 'finish_mint', reason: 'cannot equip what you do not own');
  });
}
