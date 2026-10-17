import 'package:calmpost/data/collectibles.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/data/seed_lessons.dart';
import 'package:calmpost/domain/gacha.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/domain/progression.dart';
import 'package:calmpost/domain/xp_rules.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/game_codec.dart';
import 'package:calmpost/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class NewPlayerGame extends GameController {
  @override
  GameState build() => super.build().copyWith(totalXp: 0, weekXp: 0, loam: 0, owned: {}, crates: [], packets: 0);
}

void main() {
  test('level boundaries and every level reward', () {
    for (final pair in [(1, 0), (2, 120), (3, 240), (5, 480), (10, 1080), (50, 5880)]) {
      expect(xpForLevel(pair.$1), pair.$2);
      expect(levelForXp(pair.$2), pair.$1);
      if (pair.$1 > 1) expect(levelForXp(pair.$2 - 1), pair.$1 - 1);
    }
    for (var n = 1; n <= maxLevel; n++) {
      expect(xpForLevel(n + 1) - xpForLevel(n), 120);
      expect(levelForXp(xpForLevel(n)), n);
      if (n > 1) expect(levelForXp(xpForLevel(n) - 1), n - 1);
      expect(rewardForLevel(n).loam, 20 + 5 * (n - 1));
      expect(rewardForLevel(n).packets, n % 3 == 0 ? 1 : 0);
    }
    expect(rewardForLevel(1).seed, 'sprout');
    expect(rewardForLevel(5).seed, 'clover');
    expect(rewardForLevel(10).seed, 'bloom');
    expect(rewardForLevel(10).crate, CrateTier.grove);
    expect(levelForXp(2340), 20);
    expect(levelForXp(-1), 1);
    expect(levelForXp(99999), maxLevel);
  });

  test('every plant has a distinct buff and a sourced lesson, scaling by rarity', () {
    expect(seedBuffs.keys.toSet(), collectibles.where((c) => c.type == CollectibleType.specimen).map((c) => c.id).toSet());
    for (final id in seedBuffs.keys) {
      expect(lessonForSeed(id).fact, isNotEmpty);
      expect(lessonForSeed(id).action, isNotEmpty);
      expect(buffLabel(seedBuffs[id]!), isNot(contains('null')));
      // One of each care action + all three quests: compare a consistent day.
      final bonus =
          seedXp(5, 'check_in', id) -
          5 +
          seedXp(15, 'followed_suggestion', id) -
          15 +
          seedXp(5, 'avoided_bad_add', id) -
          5 +
          [
            (10, 10, 'checkin'),
            (20, 25, 'follow'),
            (15, 15, 'healthy'),
          ].fold<int>(0, (sum, q) => sum + seedXp(q.$1, 'daily_quest', id, quest: q.$3) - q.$1 + seedLoam(q.$2, 'daily_quest', id, quest: q.$3) - q.$2);
      final (low, high) = switch (collectibleById[id]!.rarity) {
        Rarity.common => (1, 1),
        Rarity.uncommon => (4, 6),
        Rarity.rare => (8, 19),
        Rarity.epic => (22, 25),
        Rarity.legendary => (38, 40),
      };
      expect(bonus, inInclusiveRange(low, high), reason: id);
      for (final kind in ['compost_added', 'harvest', 'level_reward', 'crate_open', 'healthy_layer_day']) {
        expect(seedXp(100, kind, id), 100, reason: '$id $kind');
        expect(seedLoam(100, kind, id), 100, reason: '$id $kind');
      }
      expect(seedXp(0, 'daily_quest', id, quest: 'checkin'), 0);
      expect(seedLoam(-100, 'daily_quest', id, quest: 'checkin'), -100);
    }
    expect(seedBuffs.values.map(buffLabel).toSet().length, 24);
    expect(seedXp(10, 'daily_quest', 'sprout', quest: 'checkin'), 11);
    expect(seedXp(20, 'daily_quest', 'sprout', quest: 'follow'), 20);
    expect(seedXp(10, 'daily_quest', 'golden_sprout'), 16);
    expect(seedXp(15, 'followed_suggestion', 'firefern'), 20);
    expect(seedXp(15, 'compost_added', 'clover'), 15);
    expect(seedLoam(25, 'daily_quest', 'bloom'), 31);
    expect(seedLoam(100, 'level_reward', 'bloom'), 100);
    expect(xpForAction(base: seedXp(5, 'check_in', 'clover'), earnedToday: 59), 1);
    expect(seedXp(10, 'daily_quest', 'unknown'), 10);
    expect(seedLoam(10, 'daily_quest', null), 10);
  });

  test('starter reward, seed activation and boosted quest persist without double claims', () async {
    final c = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(MockRepository(Scenario.healthy)), gameProvider.overrideWith(NewPlayerGame.new)],
    );
    addTearDown(c.dispose);
    final game = c.read(gameProvider.notifier);
    expect(await game.claimLevelAsync(2), isFalse);
    expect(await game.claimLevelAsync(1), isTrue);
    expect(await game.claimLevelAsync(1), isFalse);
    expect(c.read(gameProvider).loam, 20);
    expect(c.read(gameProvider).owned['sprout'], 1);
    expect(await game.equipAsync(collectibleById['oak']!), isFalse);
    expect(await game.equipAsync(collectibleById['sprout']!), isTrue);
    game.checkIn();
    final before = c.read(gameProvider);
    game.claimQuest('checkin');
    final after = c.read(gameProvider);
    expect(after.totalXp - before.totalXp, 11);
    expect(after.loam - before.loam, 10);
    game.claimQuest('checkin');
    expect(c.read(gameProvider).totalXp, after.totalXp);
    final decoded = decodeGame(encodeGame(after), before);
    expect(decoded.activeSeed, 'sprout');
    expect(decoded.levelClaimed, {1});
    final old = encodeGame(after)
      ..remove('seed')
      ..remove('levelClaimed');
    expect(decodeGame(old, c.read(gameProvider)).levelClaimed, isEmpty);
    // Rebalancing changes the derived level, not saved XP or previous claims.
    final saved = after.copyWith(totalXp: 40, levelClaimed: {1, 2});
    final restored = decodeGame(encodeGame(saved), before);
    expect(restored.totalXp, 40);
    expect(restored.level, 1);
    expect(restored.levelClaimed, {1, 2});
    expect(restored.levelRewardsReady, 0);
    expect(restored.loam, saved.loam);
    expect(restored.owned, saved.owned);
  });
}
