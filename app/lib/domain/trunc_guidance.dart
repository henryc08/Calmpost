import 'advice_rules.dart';
import 'models.dart';
import 'drop.dart' show keepOutLabel;

const truncOverviewQuestion = 'Based on my current bin data, what should I do next?';

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
    action = 'The two moisture probes disagree about what needs care. Check both spots before adding food or water across the bin.';
  } else {
    action = switch (need) {
      BinNeed.browns => 'Try dry browns such as shredded cardboard after checking the compost by hand. Hold off on more wet scraps for now.',
      BinNeed.greens =>
        'A small amount of fruit or vegetable scraps may help: the upper probe is dry and your recent additions lean brown. Check by hand first.',
      BinNeed.water => 'Check the dry spot by hand and add a little water if needed. More food is not the next step.',
      BinNeed.mix => 'Check airflow and gently mix the compost, then watch the readings. More food is not needed for this action.',
      BinNeed.nothing => 'No addition is indicated by the available readings. Keep monitoring rather than adding food just to do something.',
    };
    if (need == BinNeed.nothing) {
      status = 'steady';
      if (s.bottomMeasured && s.moistureCalibrated && s.bottomMoistureCalibrated && s.greens7d + s.browns7d > 0) {
        action = "Your measured moisture and recent mix look steady. Keep doing what you're doing; nothing needs adding right now.";
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
      s.greens7d + s.browns7d <= 0
          ? 'No recent confirmed mix history is available.'
          : "The seven-day mix is an estimate of additions, not the bin's current chemistry.",
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
  final item = match[1]!.split(RegExp(r'\s+(?:to|into|in|right now|at the moment|today|now|instead)\b|[?!.,]')).first.trim();
  return const ['', 'anything', 'something', 'next', 'this', 'it', 'that', 'more', 'in'].contains(item) ? null : item;
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
  if (known == null) return "I cannot confidently identify '$item' as a safe compost material. Tell me what it is made of before adding it.";
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
