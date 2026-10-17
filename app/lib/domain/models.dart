import 'dart:typed_data' show Uint8List;

import 'package:flutter/widgets.dart' show IconData;

/// Where a sensor sits in the bin.
enum Zone { air, top, bottom }

enum Metric { moisture, temperature, co2 }

/// Life-cycle stages of a batch, in order.
enum Stage { started, active, hot, cooling, curing, ready, harvested }

enum FoodCategory { green, brown, avoid }

enum Verdict { great, careful, avoid }

enum Balance { needsGreens, needsBrowns, balanced }

enum BinNeed { browns, greens, water, mix, nothing }

/// The bin's overall state, driven by the health score and moisture.
enum BinMood { thriving, healthy, fair, dry, wet, struggling }

/// One reading from the bin: two layers + the air gap.
class BinSnapshot {
  const BinSnapshot({
    required this.time,
    required this.topMoisture,
    required this.topTemp,
    required this.bottomMoisture,
    required this.bottomTemp,
    required this.co2,
    required this.ambientTemp,
    required this.co2SlopePerDay,
    required this.greens7d,
    required this.browns7d,
    required this.topStage,
    required this.bottomStage,
    required this.healthyHoursToday,
    this.bottomMeasured = true,
    this.stale = false,
    this.topMeasured = true,
    this.topTemperatureMeasured = true,
    this.bottomTemperatureMeasured = true,
    this.airMeasured = true,
    this.ambientMeasured = true,
    this.moistureCalibrated = true,
  });

  final DateTime time;

  /// Moisture in % (0–100).
  final double topMoisture;
  final double bottomMoisture;

  /// Temperatures in °C.
  final double topTemp;
  final double bottomTemp;
  final double ambientTemp;

  /// CO₂ in the air gap, ppm, and its 48 h trend in % per day.
  final double co2;
  final double co2SlopePerDay;

  /// Logged volume over the last 7 days (rough cups).
  final double greens7d;
  final double browns7d;

  final Stage topStage;
  final Stage bottomStage;

  /// Hours today both layers spent in the healthy moisture band.
  final double healthyHoursToday;

  /// False while no probe reports the bottom layer (the real bin has one
  /// probe, in the top layer). Its moisture and temperature are then
  /// unknown: show them as not measured, never as a number.
  final bool bottomMeasured;

  /// The bin hasn't reported for a while (live data only).
  final bool stale;
  final bool topMeasured, topTemperatureMeasured, bottomTemperatureMeasured;
  final bool airMeasured, ambientMeasured, moistureCalibrated;

  bool get readingsStale => stale || DateTime.now().difference(time) > const Duration(minutes: 2);

  /// How old the reading is, e.g. "12 min ago" (shown when [stale]).
  String ageLabel(DateTime now) {
    final m = now.difference(time).inMinutes;
    if (m < 60) return '${m < 1 ? 1 : m} min ago';
    final h = m ~/ 60;
    return h < 48 ? '$h h ago' : '${h ~/ 24} days ago';
  }

  double moisture(Zone z) => z == Zone.bottom ? bottomMoisture : topMoisture;
  double temp(Zone z) => z == Zone.bottom ? bottomTemp : topTemp;
}

class TrendPoint {
  const TrendPoint(this.time, this.value);
  final DateTime time;
  final double value;
}

class FoodItem {
  const FoodItem({required this.id, required this.name, required this.category, required this.icon, required this.grams, this.note = '', this.wet = false});

  final String id;
  final String name;
  final FoodCategory category;
  final IconData icon;

  /// Typical weight of one "add", used for landfill-diverted stats.
  final double grams;

  /// Why it's a green/brown/avoid, in plain words.
  final String note;

  /// Adds a lot of water (fruit, peels, coffee grounds).
  final bool wet;
}

class Advice {
  const Advice({required this.item, required this.verdict, required this.headline, required this.reason, this.pairWith = const [], this.xpAwarded});
  final FoodItem item;
  final Verdict verdict;
  final String headline;
  final String reason;
  final List<FoodItem> pairWith;
  final int? xpAwarded;
}

/// What the bin needs right now.
class Suggestion {
  const Suggestion({required this.balance, required this.line, required this.add, required this.avoid, this.need = BinNeed.nothing});
  final Balance balance;
  final String line;
  final List<FoodItem> add;
  final List<FoodItem> avoid;
  final BinNeed need;
}

class Quest {
  const Quest({
    required this.id,
    required this.title,
    required this.icon,
    required this.goal,
    required this.xp,
    required this.loam,
    this.progress = 0,
    this.claimed = false,
    this.unit = '',
  });

  final String id;
  final String title;
  final IconData icon;
  final double goal;
  final double progress;
  final int xp;
  final int loam;
  final bool claimed;
  final String unit;

  bool get done => progress >= goal;

  Quest copyWith({double? progress, bool? claimed}) => Quest(
    id: id,
    title: title,
    icon: icon,
    goal: goal,
    xp: xp,
    loam: loam,
    unit: unit,
    progress: progress ?? this.progress,
    claimed: claimed ?? this.claimed,
  );
}

class LeagueMember {
  const LeagueMember({required this.name, required this.xp, required this.colorIndex, this.isYou = false, this.isFriend = false, this.streak = 0});
  final String name;
  final int xp;
  final int colorIndex;
  final bool isYou;
  final bool isFriend;
  final int streak;

  String get initials {
    final parts = name.replaceAll(RegExp(r'[^A-Za-z ]'), ' ').trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts.first.substring(0, 1).toUpperCase();
  }

  LeagueMember withXp(int v) => LeagueMember(name: name, xp: v, colorIndex: colorIndex, isYou: isYou, isFriend: isFriend, streak: streak);
}

enum PlantSpecies { sprout, fern, tulip, sunflower, mushroom, succulent, lavender, pumpkin }

class GardenPlant {
  const GardenPlant({required this.species, required this.day, this.wilted = false, this.rare = false});
  final PlantSpecies species;
  final DateTime day;
  final bool wilted;
  final bool rare;
}

class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.progress,
    required this.goals,
    required this.rewards,
  });
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final double progress;

  /// Thresholds for each tier.
  final List<double> goals;

  /// Crate paid out at each tier (same length as [goals]).
  final List<CrateTier> rewards;

  int get tier => goals.where((g) => progress >= g).length;
  bool get maxed => tier >= goals.length;
  double get nextGoal => maxed ? goals.last : goals[tier];
  CrateTier get nextReward => rewards[maxed ? rewards.length - 1 : tier];
}

class LogEntry {
  const LogEntry({required this.item, required this.verdict, required this.time, required this.xp, required this.added, this.quantityG});
  final FoodItem item;
  final Verdict verdict;
  final DateTime time;
  final int xp;

  /// False when the user checked an item and kept it out.
  final bool added;
  final double? quantityG;
}

/// Reward crates, earned from achievements and milestones.
enum CrateTier { sprout, grove, canopy }

/// Gacha rarities for Seed Packet pulls.
enum Rarity { common, uncommon, rare, epic, legendary }

// --- camera drop-in (AGENTS.md 2.4) -----------------------------------------
//
// The app arms the camera, vision/ reports what it saw, the user confirms or
// corrects it. Nothing here talks to Gemini: the vision service calls it and
// the backend decides categories by the rules, so a label the rules call
// avoid stays avoid whatever the model said.

/// A camera session the app armed. The bin watches for about a minute.
class DropSession {
  const DropSession({required this.id, required this.expiresAt});

  final String id;
  final DateTime expiresAt;

  bool get open => DateTime.now().isBefore(expiresAt);

  /// Zero once it has expired, so a countdown never goes negative.
  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

enum DropStatus { pending, confirmed, dismissed }

/// One thing the camera thought it saw.
class DropGuess {
  const DropGuess({
    required this.label,
    required this.catalogId,
    required this.confidence,
    this.item,
    this.category,
    this.amount,
    this.estGrams,
    this.box,
  });

  /// What the model called it, e.g. "banana peel".
  final String label;

  /// Catalog id the backend mapped it to, or 'unknown'.
  final String catalogId;

  final double confidence;

  /// The catalog entry this resolved to, when the app recognises it. Null for
  /// an unknown item, which the user has to name themselves.
  final FoodItem? item;

  /// Null when the backend could not categorise it.
  final FoodCategory? category;

  /// 'small', 'handful' or 'large'.
  final String? amount;

  final double? estGrams;

  /// [ymin, xmin, ymax, xmax] on a 0-1000 grid, as Gemini returns boxes.
  /// Scale by the displayed image size to draw it.
  final List<int>? box;
}

/// A detection waiting for the user to confirm or dismiss.
class CameraDrop {
  const CameraDrop({
    required this.id,
    required this.binId,
    required this.sessionId,
    required this.time,
    required this.status,
    required this.guesses,
    required this.geminiOk,
    required this.latencyMs,
    this.source = 'camera',
    this.model = '',
    this.error,
    this.thumbnailJpeg,
  });

  final int id;
  final String binId;
  final String sessionId;
  final DateTime time;
  final DropStatus status;

  /// 'camera' when the bin noticed it, 'photo' when the user submitted one.
  /// The same sheet handles both, but a photo the user framed deserves
  /// different wording from something the bin spotted on its own.
  final String source;

  bool get fromPhoto => source == 'photo';

  /// Empty when the camera saw something move but could not name it, or when
  /// identification failed on a submitted photo. Either way the user names it.
  final List<DropGuess> guesses;

  /// False when Gemini was unavailable and the rules-based fallback answered.
  /// Worth surfacing: the guess is cruder, so the user is likelier to correct it.
  final bool geminiOk;

  final int latencyMs;
  final String model;
  final String? error;

  /// Decoded JPEG ready for Image.memory, or null when none was sent.
  final Uint8List? thumbnailJpeg;
}

/// What the user says was actually added, after editing the camera's guess.
class DropConfirmation {
  const DropConfirmation({
    required this.label,
    this.catalogId = 'unknown',
    this.category,
    this.amount,
    this.removed = false,
    this.wasAdvised = false,
    this.adviceId,
  });

  final String label;
  final String catalogId;
  final FoodCategory? category;
  final String? amount;

  /// The user took a keep-out item back out again: logged as a skip, which
  /// earns the usual +5 rather than nothing.
  final bool removed;

  /// It was the suggested next action: +15 by the usual rule.
  final bool wasAdvised;
  final int? adviceId;
}

/// What came back from confirming a drop.
class DropResult {
  const DropResult({
    required this.dropId,
    required this.corrected,
    required this.verdicts,
    required this.xpAwarded,
  });

  final int dropId;

  /// True when the user changed what the camera guessed. The backend keeps
  /// this for the accuracy stat.
  final bool corrected;

  /// One per confirmed item the backend could judge; a removed item has none.
  final List<Advice> verdicts;

  final int xpAwarded;
}

// --- Trunc, the compost assistant -------------------------------------------
//
// Free-text questions, answered by the backend's POST /bins/{id}/chat. The app
// never calls Gemini and never holds its key; the backend assembles the sensor
// readings, what was recently added and the last camera photos, and holds the
// answer to the app's own compost rules.
//
// Stateless on the server: the app owns the conversation and passes it back
// each turn, so keep the turns in state and send them with the next question.

enum TruncRole { user, assistant }

class TruncTurn {
  const TruncTurn({required this.role, required this.text});

  final TruncRole role;
  final String text;

  bool get isUser => role == TruncRole.user;
}

/// What Trunc actually had to work with. Worth showing quietly rather than
/// decoratively: when [readingsAt] is null the bin has never reported, so the
/// answer came from general rules and not from this bin.
class TruncContext {
  const TruncContext({this.readingsAt, this.recentAdds = 0, this.photos = 0});

  final DateTime? readingsAt;
  final int recentAdds;
  final int photos;
}

class TruncReply {
  const TruncReply({
    required this.reply,
    required this.model,
    required this.onTopic,
    required this.usedReadings,
    required this.context,
  });

  /// Always something sayable, including when [onTopic] is false or the model
  /// was unreachable. Render it as a normal message either way.
  final String reply;

  /// 'gemini-2.5-flash' when the model answered, 'rules-fallback' when it was
  /// unreachable and the sensors answered instead, 'rules-override' when the
  /// rules replaced an answer that suggested a keep-out item.
  final String model;

  /// False when the question was not about compost. The backend already
  /// supplies the polite redirect, so there is no refusal UI to build.
  final bool onTopic;

  /// True when the answer leaned on the sensor data.
  final bool usedReadings;

  final TruncContext context;

  /// Gemini was unavailable and this came from the rules. A normal reply, not
  /// an error: do not show a failure state for it.
  bool get isFallback => model == 'rules-fallback';
}
