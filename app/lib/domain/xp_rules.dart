import 'dart:math' as math;

/// XP values. Confirmed compostable volume and care both earn XP.
abstract final class Xp {
  static const log = 0;
  static const gramsPerXp = 20;
  static const followedSuggestion = 15;
  static const avoidedBadAdd = 5;
  static const checkIn = 5;
  static const healthyLayerDay = 10;
  static const weeklyBalance = 30;
  static const harvest = 100;

  /// Max XP per day from actions (health-based XP is uncapped: it can't be farmed).
  static const dailyActionCap = 60;
}

/// Cumulative daily volume avoids rewarding the splitting of one drop.
int volumeXp(double grams, {double alreadyLogged = 0}) =>
    ((alreadyLogged + math.max(0, grams)) / Xp.gramsPerXp).floor() - (alreadyLogged / Xp.gramsPerXp).floor();

/// XP for logging/checking an item, respecting the daily cap.
int xpForAction({required int base, required int earnedToday}) {
  final room = math.max(0, Xp.dailyActionCap - earnedToday);
  return math.min(base, room);
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

class StreakState {
  const StreakState({required this.days, required this.lidLocks, required this.lastCareDay});
  final int days;
  final int lidLocks;
  final DateTime? lastCareDay;

  bool caredOn(DateTime now) => lastCareDay != null && dayOf(lastCareDay!) == dayOf(now);
}

class StreakUpdate {
  const StreakUpdate(this.state, {required this.extended, required this.locksUsed, required this.reset});
  final StreakState state;
  final bool extended;
  final int locksUsed;
  final bool reset;
}

/// Applies a care action. Missed days are covered by Lid Locks if available.
StreakUpdate applyCareAction(StreakState s, DateTime now) {
  final today = dayOf(now);
  if (s.lastCareDay == null) {
    return StreakUpdate(StreakState(days: 1, lidLocks: s.lidLocks, lastCareDay: today), extended: true, locksUsed: 0, reset: false);
  }
  final last = dayOf(s.lastCareDay!);
  final gap = today.difference(last).inDays;
  if (gap <= 0) return StreakUpdate(s, extended: false, locksUsed: 0, reset: false);
  final missed = gap - 1;
  if (missed == 0) {
    return StreakUpdate(StreakState(days: s.days + 1, lidLocks: s.lidLocks, lastCareDay: today), extended: true, locksUsed: 0, reset: false);
  }
  if (missed <= s.lidLocks) {
    return StreakUpdate(
      StreakState(days: s.days + 1, lidLocks: s.lidLocks - missed, lastCareDay: today),
      extended: true,
      locksUsed: missed,
      reset: false,
    );
  }
  return StreakUpdate(StreakState(days: 1, lidLocks: s.lidLocks, lastCareDay: today), extended: true, locksUsed: 0, reset: true);
}

const streakMilestones = [3, 7, 14, 30, 50, 100, 365];

bool isStreakMilestone(int days) => streakMilestones.contains(days);

/// Level n needs 60·n·(n+1)/2 lifetime XP.
int levelForXp(int xp) {
  var n = 1;
  while (xpForLevel(n + 1) <= xp && n < 50) {
    n++;
  }
  return n;
}

int xpForLevel(int n) => 60 * (n - 1) * n ~/ 2;

const _titles = [
  (1, 'Scrap Saver'),
  (4, 'Peel Keeper'),
  (7, 'Soil Whisperer'),
  (12, 'Worm Wrangler'),
  (18, 'Humus Hero'),
  (26, 'Loam Legend'),
  (36, 'Compost Sage'),
];

String titleForLevel(int level) => _titles.lastWhere((t) => level >= t.$1).$2;

/// Leagues: weekly cohorts of 30.
class LeagueTier {
  const LeagueTier(this.name, this.index);
  final String name;
  final int index;
}

const leagueTiers = [
  LeagueTier('Seedling', 0),
  LeagueTier('Sprout', 1),
  LeagueTier('Fern', 2),
  LeagueTier('Sapling', 3),
  LeagueTier('Oak', 4),
  LeagueTier('Sequoia', 5),
];

const promoteCount = 7;
const demoteCount = 5;

enum LeagueZone { promote, safe, demote }

LeagueZone zoneForRank(int rank, int cohortSize, {required int tierIndex}) {
  if (rank <= promoteCount && tierIndex < leagueTiers.length - 1) return LeagueZone.promote;
  if (rank > cohortSize - demoteCount && tierIndex > 0) return LeagueZone.demote;
  return LeagueZone.safe;
}

/// Impact estimates (shown with an "estimate" footnote in the UI).
abstract final class Impact {
  /// kg CO₂e avoided per kg of food waste kept out of landfill (methane).
  static const co2ePerKg = 0.55;

  /// Store-bought compost/fertilizer value per kg of finished compost.
  static const dollarsPerKgCompost = 1.6;

  /// Roughly how much finished compost a kg of scraps becomes.
  static const compostYield = 0.4;
}
