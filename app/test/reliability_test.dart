import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/domain/drop.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/domain/xp_rules.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/game_codec.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('camera hard-avoid classification survives a green catalog match', () {
    const drop = Drop(
      id: 1,
      items: [Detection(label: 'rice with chicken', catalogId: 'mixed_scraps', category: FoodCategory.avoid, confidence: .99)],
    );
    expect(linesFor(drop, foodById).single.keepOut, isTrue);
    expect(tierOf(drop, foodById), DropTier.unclear);
  });
  test('confirmed selected mass, not catalog serving, drives volume and impact', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final g = c.read(gameProvider.notifier);
    final before = c.read(gameProvider);
    final a = Advice(item: foodById['banana_peel']!, verdict: Verdict.great, headline: '', reason: '');
    expect(g.recordLog(a, added: true, suggestedIds: [], quantityG: 250).xp, 12);
    expect(c.read(gameProvider).kgDiverted, closeTo(before.kgDiverted + .25, .0001));
    expect(c.read(gameProvider).logs.first.quantityG, 250);
    expect(g.recordLog(a, added: true, suggestedIds: [], quantityG: 10).xp, 1);
  });
  test('seventh day pays milestone and achievement only once', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final g = c.read(gameProvider.notifier);
    final before = c.read(gameProvider);
    g.checkIn();
    expect(c.read(gameProvider).loam, before.loam + 50);
    expect(c.read(gameProvider).crates.length, before.crates.length + 2);
    g.checkIn();
    expect(c.read(gameProvider).loam, before.loam + 50);
  });
  test('demo state survives recreation and daily counters reset without losing rewards', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = ProviderContainer(overrides: [gameStorageProvider.overrideWithValue(prefs)]);
    first.read(gameProvider.notifier).checkIn();
    final expected = first.read(gameProvider);
    await Future<void>.delayed(Duration.zero);
    first.dispose();
    final second = ProviderContainer(overrides: [gameStorageProvider.overrideWithValue(prefs)]);
    addTearDown(second.dispose);
    final loaded = second.read(gameProvider);
    expect(loaded.totalXp, expected.totalXp);
    expect(loaded.loam, expected.loam);
    expect(loaded.crates, expected.crates);
    final next = rolloverGame(loaded.copyWith(day: dayOf(DateTime.now()).subtract(const Duration(days: 1)), volumeGramsToday: 110));
    expect(next.xpToday, 0);
    expect(next.volumeGramsToday, 0);
    expect(next.loam, loaded.loam);
  });
}
