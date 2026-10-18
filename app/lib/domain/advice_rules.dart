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

  if (!s.topMeasured || s.readingsStale) {
    return Advice(
      item: item,
      verdict: Verdict.careful,
      headline: 'Check the bin first',
      reason: 'Current moisture is unavailable. Check the bin by hand before adding more; this item is compostable, but its suitability right now is unknown.',
    );
  }

  final balance = balanceOf(s);
  final need = needFor(s);
  final wet = s.topMoisture > 64;
  final dry = s.topMoisture < 36;

  if (item.category == FoodCategory.green) {
    if (moistureConflict(s) || need == BinNeed.water || need == BinNeed.mix) {
      return Advice(
        item: item,
        verdict: Verdict.careful,
        headline: 'Not needed right now',
        reason: moistureConflict(s)
            ? 'The moisture probes disagree. Check both spots before adding more.'
            : need == BinNeed.water
            ? 'The upper probe is dry, but more food is not the next step. Check by hand and add a little water if dry.'
            : 'Check airflow and gently mix first. More food is not needed for this action.',
      );
    }
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
        reason:
            'The upper probe reads ${s.topMoisture.round()}% relative moisture and recent additions lean brown. ${item.name} can add moisture; check by hand first.',
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

BinNeed needFor(BinSnapshot s) {
  if (!s.topMeasured || s.readingsStale) return BinNeed.nothing;
  if (moistureConflict(s)) return BinNeed.nothing;
  final ratio = s.greens7d > 0 ? s.browns7d / s.greens7d : (s.browns7d > 0 ? 4.0 : 2.5);
  final delta = s.topTemperatureMeasured && s.ambientMeasured ? s.topTemp - s.ambientTemp : null;
  if (s.topMoisture > 60) return BinNeed.browns;
  if (s.topMoisture < 40) return ratio > 3 ? BinNeed.greens : BinNeed.water;
  if (ratio < 2) return BinNeed.browns;
  if (s.airMeasured && s.co2SlopePerDay > 2 && delta != null && delta < 5) return BinNeed.mix;
  return BinNeed.nothing;
}

bool moistureConflict(BinSnapshot s) =>
    s.topMeasured &&
    s.bottomMeasured &&
    ((s.bottomMoisture < moistureLo && s.topMoisture >= moistureLo) || (s.bottomMoisture > moistureHi && s.topMoisture <= moistureHi));

Suggestion suggestFor(BinSnapshot s, Map<String, FoodItem> catalog) {
  List<FoodItem> pick(List<String> ids) => ids.map((id) => catalog[id]).whereType<FoodItem>().toList();
  final avoid = pick(['meat', 'cheese', 'oily_food']);

  final need = needFor(s);
  if (need == BinNeed.nothing || need == BinNeed.water || need == BinNeed.mix) {
    return Suggestion(
      need: need,
      balance: Balance.balanced,
      line: !s.topMeasured || s.readingsStale
          ? 'Current readings are unavailable. Check the bin by hand before adding more.'
          : need == BinNeed.water
          ? 'The top layer is dry, but the mix is balanced. Add a little water; no food is needed.'
          : need == BinNeed.mix
          ? 'CO₂ is rising without much warmth. Stir the top layer to let air in.'
          : moistureConflict(s)
          ? 'The moisture probes disagree. Check both spots before adding anything.'
          : 'Moisture and balance are on target. Nothing needs adding right now.',
      add: const [],
      avoid: avoid,
    );
  }
  switch (need == BinNeed.browns ? Balance.needsBrowns : Balance.needsGreens) {
    case Balance.needsBrowns:
      return Suggestion(
        need: BinNeed.browns,
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
        need: BinNeed.greens,
        balance: Balance.needsGreens,
        line: s.topMoisture < 36
            ? 'The top layer is down to ${s.topMoisture.round()}% moisture. Wet greens will get it going again.'
            : 'Recent additions lean brown. A few fresh scraps may help; this is not a nitrogen measurement.',
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
