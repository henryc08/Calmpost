import 'package:flutter/widgets.dart' show IconData;

/// Where a sensor sits in the bin.
enum Zone { air, top, bottom }

enum Metric { moisture, temperature, co2 }

/// Life-cycle stages of a batch, in order.
enum Stage { started, active, hot, cooling, curing, ready, harvested }

enum FoodCategory { green, brown, avoid }

enum Verdict { great, careful, avoid }

enum Balance { needsGreens, needsBrowns, balanced }

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
  const Advice({required this.item, required this.verdict, required this.headline, required this.reason, this.pairWith = const []});
  final FoodItem item;
  final Verdict verdict;
  final String headline;
  final String reason;
  final List<FoodItem> pairWith;
}

/// What the bin needs right now.
class Suggestion {
  const Suggestion({required this.balance, required this.line, required this.add, required this.avoid});
  final Balance balance;
  final String line;
  final List<FoodItem> add;
  final List<FoodItem> avoid;
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
  const LogEntry({required this.item, required this.verdict, required this.time, required this.xp, required this.added});
  final FoodItem item;
  final Verdict verdict;
  final DateTime time;
  final int xp;

  /// False when the user checked an item and kept it out.
  final bool added;
}

/// Reward crates, earned from achievements and milestones.
enum CrateTier { sprout, grove, canopy }

String crateLabel(CrateTier t) => switch (t) {
  CrateTier.sprout => 'Sprout crate',
  CrateTier.grove => 'Grove crate',
  CrateTier.canopy => 'Canopy crate',
};

/// One line in the rewards inbox history.
enum RewardKind { crateOpened, packetsOpened, streak, levelUp, harvest }

class RewardEvent {
  const RewardEvent({required this.kind, required this.title, required this.detail, required this.time});
  final RewardKind kind;
  final String title;
  final String detail;
  final DateTime time;
}

/// Gacha rarities for Seed Packet pulls.
enum Rarity { common, uncommon, rare, epic, legendary }
