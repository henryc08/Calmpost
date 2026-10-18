import 'advice_rules.dart';
import 'models.dart';
import 'drop.dart' show keepOutLabel;
import 'health_score.dart' show moistureHi;

const truncOverviewQuestion = 'Based on my current bin data, what should I do next?';

/// Mirrored by ACTIONS in backend/app/rules/trunc_guidance.py. Each names
/// something the user can actually reach for.
const truncActions = {
  BinNeed.browns:
      'Your bin is on the wet side, so add some dry browns: shredded cardboard, dry leaves or torn paper egg cartons. Hold off on wet scraps for now.',
  BinNeed.greens: 'Your bin is dry and your recent additions lean brown, so add a handful of greens: fruit or vegetable scraps, or coffee grounds.',
  BinNeed.water: 'Your bin is a bit dry. Add a splash of water to the dry spot and mix it in. No food needed right now.',
  BinNeed.mix: 'Give your bin a gentle stir to let air in, then check back. No food needed right now.',
  BinNeed.nothing:
      'Nothing is urgent. When you add, aim for about one part greens (fruit and veg scraps, coffee grounds) to two parts browns (shredded cardboard, dry leaves).',
};
const truncDoingGreat = "Your compost is doing great. Keep doing what you're doing.";

/// The top looks fine but the bottom doesn't, so say which and what fixes it.
String truncInspectLine(BinSnapshot s) {
  final top = s.topMoisture.round(), bottom = s.bottomMoisture.round();
  return s.bottomMoisture > moistureHi
      ? "The top looks fine ($top%), but the bottom is wet ($bottom%). Feel the bottom: if it's soggy, mix in some shredded cardboard or dry leaves and hold off on wet scraps."
      : "The top looks fine ($top%), but the bottom is dry ($bottom%). Feel the bottom: if it's dry, pour a little water down the side and mix it in.";
}

const _generic = {'', 'anything', 'something', 'next', 'this', 'it', 'that', 'more', 'in', 'bin', 'items', 'item', 'things', 'thing', 'stuff', 'food', 'scraps', 'what', 'now'};

class TruncGuidance {
  const TruncGuidance(this.need, this.status, this.action, this.evidence, this.limits);
  final BinNeed need;
  final String status, action;
  final List<String> evidence, limits;
  bool get usable => status != 'unknown';
  String get summary => [action, if (evidence.isNotEmpty) '${evidence.join('; ')}.', ...limits].join(' ');
}

/// Mirrored by backend/app/rules/trunc_guidance.py. No exact doses/chemistry.
TruncGuidance guidanceFor(BinSnapshot s) {
  final need = needFor(s);
  var status = 'action';
  String action;
  if (!s.topMeasured || s.readingsStale) {
    status = 'unknown';
    action = 'I need a fresh upper moisture reading before recommending an addition. Check the bin by hand and reconnect the sensor.';
  } else if (moistureConflict(s)) {
    status = 'inspect';
    action = truncInspectLine(s);
  } else {
    action = truncActions[need]!;
    if (need == BinNeed.nothing) {
      status = 'steady';
      if (s.bottomMeasured && s.moistureCalibrated && s.bottomMoistureCalibrated && s.greens7d + s.browns7d > 0) {
        action = truncDoingGreat;
      }
    }
  }
  return TruncGuidance(
    need,
    status,
    action,
    [
      if (s.topMeasured) 'Upper probe: ${s.topMoisture.round()}% relative moisture',
      if (s.bottomMeasured) 'Lower probe: ${s.bottomMoisture.round()}% relative moisture',
    ],
    [
      if (!s.moistureCalibrated || (s.bottomMeasured && !s.bottomMoistureCalibrated)) 'An uncalibrated moisture probe is approximate.',
      if (!s.bottomMeasured) 'Lower moisture is unknown.',
      if (s.greens7d + s.browns7d <= 0) 'No recent confirmed mix history is available.',
    ],
  );
}

/// Changes on decision/quality boundaries, not every three-second sensor wobble.
String truncSignature(BinSnapshot s) {
  final a = guidanceFor(s);
  return [
    a.need.name,
    a.status,
    s.topMeasured,
    s.bottomMeasured,
    s.topTemperatureMeasured,
    s.ambientMeasured,
    s.airMeasured,
    s.moistureCalibrated,
    s.bottomMoistureCalibrated,
    s.greens7d + s.browns7d > 0,
  ].join('|');
}

String? truncRequestedItem(String message) {
  final question = message.trim().toLowerCase().replaceAll(RegExp(r'\b(?:my|the|this|your) compost\b'), 'bin');
  if (RegExp(r'\bhow much water\b').hasMatch(question)) return 'water';
  final match = RegExp(r'\b(?:add|adding|compost|put in|put|feed|what about)\s+(?:some\s+|more\s+|a little\s+|an?\s+)?(.+)').firstMatch(question);
  if (match == null) return null;
  // "what should I add to the bin" names no item, not one called "to the bin".
  final rest = match[1]!.replaceFirst(RegExp(r'^(?:to|into|in)\s+(?:the\s+|my\s+|this\s+|your\s+)?(?:bin|pile|compost)\b\s*'), '');
  final item = rest.split(RegExp(r'\s+(?:to|into|in|right now|at the moment|today|now|instead)\b|[?!.,]')).first.trim();
  return _generic.contains(item) ? null : item;
}

String truncMaterialAnswer(BinSnapshot s, String item, Iterable<FoodItem> catalog) {
  if (keepOutLabel(item)) return 'Keep $item out of this bin. It contains a keep-out material; this does not depend on sensor readings.';
  if (item == 'water') {
    final a = guidanceFor(s);
    return '${a.need == BinNeed.water && a.usable ? 'Water fits the current care action, after checking by hand.' : 'I would not add water across the bin right now.'} ${a.summary}';
  }
  final normal =
      const {'apple': 'apple core', 'apples': 'apple core', 'apple scraps': 'apple core', 'apple cores': 'apple core', 'banana peels': 'banana peel'}[item] ??
      item;
  final matches = catalog.where((f) => normal.contains(f.name.toLowerCase()) || f.name.toLowerCase().contains(normal)).toList();
  // Hard-avoid matches take precedence in a mixed description.
  final bad = matches.where((f) => f.category == FoodCategory.avoid).firstOrNull;
  if (bad != null) return 'Keep $item out of this bin: ${bad.note} This does not depend on sensor readings.';
  final known = matches.firstOrNull;
  if (known == null) {
    return "${item[0].toUpperCase()}${item.substring(1)} isn't in my list, so I can't check it against your bin. "
        'Plant-based food scraps and plain paper or cardboard are usually fine; keep out meat, fish, dairy, oily food and bones.';
  }
  final a = guidanceFor(s);
  final intro = switch (a.status) {
    'unknown' || 'inspect' => '$item is generally compostable, but I cannot recommend adding it right now.',
    _ when a.need == (known.category == FoodCategory.green ? BinNeed.greens : BinNeed.browns) =>
      'Yes, $item fits the current care action. Start small; these readings cannot determine an exact quantity.',
    _ when a.need == BinNeed.nothing => '$item is compostable, but it is not needed right now.',
    _ => 'Hold off on $item for now. It is compostable, but it does not address the current need.',
  };
  return '$intro ${a.summary}';
}

String? truncFollowupItem(String message, List<TruncTurn> history) {
  if (!RegExp(r'\b(?:how much|how many|what about it|what about now|and now)\b').hasMatch(message.toLowerCase())) return null;
  for (final turn in history.reversed) {
    if (turn.role != TruncRole.user) continue;
    final item = truncRequestedItem(turn.text);
    if (item != null) return item;
  }
  return null;
}
