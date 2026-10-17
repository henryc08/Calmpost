import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/domain/advice_rules.dart';
import 'package:calmpost/domain/health_score.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/domain/xp_rules.dart';
import 'package:flutter_test/flutter_test.dart';

BinSnapshot snap({double topM = 50, double botM = 50, double greens = 3, double browns = 7, Stage bottom = Stage.curing}) => BinSnapshot(
  time: DateTime(2026, 10, 16),
  topMoisture: topM,
  topTemp: 35,
  bottomMoisture: botM,
  bottomTemp: 23,
  co2: 2400,
  ambientTemp: 21,
  co2SlopePerDay: -2,
  greens7d: greens,
  browns7d: browns,
  topStage: Stage.active,
  bottomStage: bottom,
  healthyHoursToday: 4,
);

void main() {
  group('health score', () {
    test('weights sum to 1', () {
      expect(HealthBreakdown.wMoisture + HealthBreakdown.wTemperature + HealthBreakdown.wCo2 + HealthBreakdown.wBalance, closeTo(1, 1e-9));
    });

    test('band score is 100 inside the band and falls off outside', () {
      expect(bandScore(50, 40, 60, 25), 100);
      expect(bandScore(40, 40, 60, 25), 100);
      expect(bandScore(72.5, 40, 60, 25), closeTo(50, 1e-9));
      expect(bandScore(10, 40, 60, 25), 0);
    });

    test('a balanced bin scores high, a soggy one lower', () {
      final good = computeHealth(snap()).total;
      final soggy = computeHealth(snap(topM: 80, botM: 70, greens: 8, browns: 4)).total;
      expect(good, greaterThanOrEqualTo(90));
      expect(soggy, lessThan(good - 20));
    });

    test('mood follows moisture first', () {
      expect(moodFor(snap(topM: 75), 90), BinMood.wet);
      expect(moodFor(snap(topM: 20), 90), BinMood.dry);
      expect(moodFor(snap(), 90), BinMood.thriving);
    });
  });

  group('advice: same scrap, different answer', () {
    final banana = foodById['banana_peel']!;

    test('banana peel is great when the bin is dry', () {
      expect(adviseFor(banana, snap(topM: 25, greens: 2, browns: 9), foodById).verdict, Verdict.great);
    });

    test('banana peel needs browns when the bin is soggy', () {
      final a = adviseFor(banana, snap(topM: 76, greens: 8, browns: 4), foodById);
      expect(a.verdict, Verdict.careful);
      expect(a.pairWith.map((f) => f.category), everyElement(FoodCategory.brown));
    });

    test('meat is always avoid', () {
      for (final s in [snap(), snap(topM: 20), snap(topM: 80)]) {
        expect(adviseFor(foodById['meat']!, s, foodById).verdict, Verdict.avoid);
      }
    });
  });

  group('xp rules', () {
    test('logging a scrap earns nothing on its own', () {
      expect(Xp.log, 0);
      expect(xpForAction(base: Xp.log, earnedToday: 0), 0);
    });

    test('daily action cap', () {
      expect(xpForAction(base: 15, earnedToday: Xp.dailyActionCap - 5), 5);
      expect(xpForAction(base: 15, earnedToday: Xp.dailyActionCap), 0);
    });

    test('streak extends on consecutive days and ignores repeats', () {
      final mon = DateTime(2026, 10, 12, 9);
      var s = const StreakState(days: 3, lidLocks: 0, lastCareDay: null);
      s = applyCareAction(StreakState(days: 3, lidLocks: 0, lastCareDay: mon), mon.add(const Duration(days: 1))).state;
      expect(s.days, 4);
      final again = applyCareAction(s, mon.add(const Duration(days: 1, hours: 5)));
      expect(again.extended, isFalse);
      expect(again.state.days, 4);
    });

    test('a Lid Lock covers a missed day', () {
      final mon = DateTime(2026, 10, 12);
      final up = applyCareAction(StreakState(days: 6, lidLocks: 1, lastCareDay: mon), mon.add(const Duration(days: 2)));
      expect(up.state.days, 7);
      expect(up.locksUsed, 1);
      expect(up.state.lidLocks, 0);
    });

    test('streak resets without a Lid Lock', () {
      final mon = DateTime(2026, 10, 12);
      final up = applyCareAction(StreakState(days: 6, lidLocks: 0, lastCareDay: mon), mon.add(const Duration(days: 3)));
      expect(up.reset, isTrue);
      expect(up.state.days, 1);
    });

    test('levels grow and titles change', () {
      expect(levelForXp(0), 1);
      expect(levelForXp(xpForLevel(9)), 9);
      expect(levelForXp(xpForLevel(9) - 1), 8);
      expect(titleForLevel(1), 'Scrap Saver');
      expect(titleForLevel(9), 'Soil Whisperer');
    });

    test('league zones', () {
      expect(zoneForRank(1, 30, tierIndex: 2), LeagueZone.promote);
      expect(zoneForRank(7, 30, tierIndex: 2), LeagueZone.promote);
      expect(zoneForRank(8, 30, tierIndex: 2), LeagueZone.safe);
      expect(zoneForRank(26, 30, tierIndex: 2), LeagueZone.demote);
      expect(zoneForRank(30, 30, tierIndex: 0), LeagueZone.safe, reason: 'no demotion from the bottom tier');
    });
  });
}
