import 'health_score.dart';
import 'models.dart';

/// Rule-based advice. The backend's Gemini call replaces this, and this stays
/// as its fallback. Every answer depends on the bin's current readings.
Advice adviseFor(FoodItem item, BinSnapshot s, Map<String, FoodItem> catalog) {
  FoodItem? f(String id) => catalog[id];
  List<FoodItem> pick(List<String> ids) => ids.map(f).whereType<FoodItem>().toList();

  if (item.category == FoodCategory.avoid) {
    return Advice(item: item, verdict: Verdict.avoid, headline: 'Keep it out', reason: '${item.note} Bin it, or freeze it for your city\'s green bin.');
  }

  final balance = balanceOf(s);
  final wet = s.topMoisture > 64;
  final dry = s.topMoisture < 36;

  if (item.category == FoodCategory.green) {
    if (wet) {
      return Advice(
        item: item,
        verdict: Verdict.careful,
        headline: 'Add browns first',
        reason:
            'Your top layer is ${s.topMoisture.round()}% wet, which is soggy. ${item.wet ? 'This adds even more water.' : 'More greens will make it sour.'} Mix in a handful of shredded cardboard with it.',
        pairWith: pick(['cardboard', 'newspaper']),
      );
    }
    if (balance == Balance.needsBrowns) {
      return Advice(
        item: item,
        verdict: Verdict.careful,
        headline: 'Go easy on greens',
        reason: 'You\'ve added a lot of greens this week. Pair this with some browns so the bin stays balanced.',
        pairWith: pick(['dry_leaves', 'cardboard']),
      );
    }
    if (dry && item.wet) {
      return Advice(
        item: item,
        verdict: Verdict.great,
        headline: 'Perfect timing!',
        reason: 'Your top layer is only ${s.topMoisture.round()}% moist. ${item.name} adds the water and nitrogen it\'s missing.',
      );
    }
    return Advice(item: item, verdict: Verdict.great, headline: 'Great add!', reason: '${item.note} Moisture is right where it should be, so toss it in.');
  }

  // Browns.
  if (dry) {
    return Advice(
      item: item,
      verdict: Verdict.careful,
      headline: 'Add with greens',
      reason: 'Your top layer is ${s.topMoisture.round()}% moist, already dry. More browns will stall it. Add some wet greens or a splash of water too.',
      pairWith: pick(['veg_peels', 'coffee_grounds']),
    );
  }
  if (wet || balance == Balance.needsBrowns) {
    return Advice(
      item: item,
      verdict: Verdict.great,
      headline: 'Exactly what it needs!',
      reason: wet
          ? 'Your top layer is ${s.topMoisture.round()}% wet. ${item.name} will soak up the extra water and let it breathe.'
          : 'The bin is green-heavy this week. ${item.name} balances it right out.',
    );
  }
  return Advice(item: item, verdict: Verdict.great, headline: 'Good add', reason: '${item.note} Keeps your greens and browns in balance.');
}

Suggestion suggestFor(BinSnapshot s, Map<String, FoodItem> catalog) {
  List<FoodItem> pick(List<String> ids) => ids.map((id) => catalog[id]).whereType<FoodItem>().toList();
  final avoid = pick(['meat', 'cheese', 'oily_food']);

  if (s.bottomStage == Stage.ready) {
    return Suggestion(
      balance: Balance.balanced,
      line: 'The bottom layer has finished curing and is ready to harvest.',
      add: pick(['veg_peels', 'cardboard']),
      avoid: avoid,
    );
  }
  switch (balanceOf(s)) {
    case Balance.needsBrowns:
      return Suggestion(
        balance: Balance.needsBrowns,
        line: s.topMoisture > 64
            ? 'The top layer is ${s.topMoisture.round()}% wet. Dry browns will soak it up and let air back in.'
            : 'Greens have outpaced browns this week. Balance them out with something dry.',
        add: pick(['cardboard', 'dry_leaves', 'newspaper']),
        avoid: [
          ...pick(['lettuce', 'grass']),
          ...avoid,
        ],
      );
    case Balance.needsGreens:
      return Suggestion(
        balance: Balance.needsGreens,
        line: s.topMoisture < 36
            ? 'The top layer is down to ${s.topMoisture.round()}% moisture. Wet greens will get it going again.'
            : 'The bin is running low on nitrogen. A few fresh scraps will help.',
        add: pick(['veg_peels', 'coffee_grounds', 'banana_peel']),
        avoid: [
          ...pick(['sawdust']),
          ...avoid,
        ],
      );
    case Balance.balanced:
      return Suggestion(
        balance: Balance.balanced,
        line: 'Moisture and balance are on target. Keep alternating greens and browns.',
        add: pick(['veg_peels', 'eggshells', 'dry_leaves']),
        avoid: avoid,
      );
  }
}
