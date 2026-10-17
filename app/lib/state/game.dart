import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../data/collectibles.dart';
import '../data/food_catalog.dart';
import '../domain/gacha.dart';
import '../domain/models.dart';
import '../domain/xp_rules.dart';
import 'celebrations.dart';

/// Everything the game layer tracks. In-memory for the demo; the backend's
/// point_events ledger becomes the source of truth later.
class GameState {
  const GameState({
    required this.weekXp,
    required this.totalXp,
    required this.loam,
    required this.streak,
    required this.quests,
    required this.garden,
    required this.logs,
    required this.actionXpToday,
    required this.careDays,
    required this.lockDays,
    required this.bestStreak,
    required this.crates,
    required this.packets,
    required this.xpToday,
    required this.owned,
    required this.pity,
    required this.equippedFinish,
    this.equippedTitle,
    required this.dailyClaimed,
    required this.harvests,
    required this.kgDiverted,
    required this.questsClaimedAllTime,
    required this.friendQuestProgress,
    this.cameraDrops = 0,
  });

  static const playerName = 'You';
  static const tierIndex = 2; // Fern league

  final int weekXp;
  final int totalXp;
  final int loam;
  final StreakState streak;
  final List<Quest> quests;
  final List<GardenPlant> garden;
  final List<LogEntry> logs;
  final int actionXpToday;

  /// Days the bin was cared for (for the streak calendar).
  final Set<DateTime> careDays;

  /// Missed days covered by a Lid Lock.
  final Set<DateTime> lockDays;
  final int bestStreak;

  /// Unopened reward crates and Seed Packets (the rewards inbox).
  final List<CrateTier> crates;
  final int packets;

  /// XP earned today (drives the daily goal track) and which of its rewards are claimed.
  final int xpToday;

  /// Greenhouse: collectible id → copies owned, pity counters, what's equipped.
  final Map<String, int> owned;
  final PityState pity;
  final String equippedFinish;
  final String? equippedTitle;

  int get collected => owned.values.where((n) => n > 0).length;
  Color get ringColor => collectibleById[equippedFinish]?.color ?? const Color(0xFFFFFFFF);
  String get displayTitle => equippedTitle == null ? titleForLevel(level) : (collectibleById[equippedTitle]?.name ?? titleForLevel(level));
  final Set<int> dailyClaimed;
  final int harvests;
  final double kgDiverted;
  final int questsClaimedAllTime;
  final int friendQuestProgress;

  /// Camera drops the user reviewed and confirmed (Sharp Eye).
  final int cameraDrops;

  int get level => levelForXp(totalXp);
  bool get caredToday => streak.caredOn(DateTime.now());
  double get co2eAvoided => kgDiverted * Impact.co2ePerKg;
  double get dollarsSaved => kgDiverted * Impact.compostYield * Impact.dollarsPerKgCompost;

  GameState copyWith({
    int? weekXp,
    int? totalXp,
    int? loam,
    StreakState? streak,
    List<Quest>? quests,
    List<GardenPlant>? garden,
    List<LogEntry>? logs,
    int? actionXpToday,
    Set<DateTime>? careDays,
    Set<DateTime>? lockDays,
    int? bestStreak,
    List<CrateTier>? crates,
    int? packets,
    int? xpToday,
    Map<String, int>? owned,
    PityState? pity,
    String? equippedFinish,
    String? equippedTitle,
    Set<int>? dailyClaimed,
    int? harvests,
    double? kgDiverted,
    int? questsClaimedAllTime,
    int? friendQuestProgress,
    int? cameraDrops,
  }) => GameState(
    weekXp: weekXp ?? this.weekXp,
    totalXp: totalXp ?? this.totalXp,
    loam: loam ?? this.loam,
    streak: streak ?? this.streak,
    quests: quests ?? this.quests,
    garden: garden ?? this.garden,
    logs: logs ?? this.logs,
    actionXpToday: actionXpToday ?? this.actionXpToday,
    careDays: careDays ?? this.careDays,
    lockDays: lockDays ?? this.lockDays,
    bestStreak: bestStreak ?? this.bestStreak,
    crates: crates ?? this.crates,
    packets: packets ?? this.packets,
    xpToday: xpToday ?? this.xpToday,
    owned: owned ?? this.owned,
    pity: pity ?? this.pity,
    equippedFinish: equippedFinish ?? this.equippedFinish,
    equippedTitle: equippedTitle ?? this.equippedTitle,
    dailyClaimed: dailyClaimed ?? this.dailyClaimed,
    harvests: harvests ?? this.harvests,
    kgDiverted: kgDiverted ?? this.kgDiverted,
    questsClaimedAllTime: questsClaimedAllTime ?? this.questsClaimedAllTime,
    friendQuestProgress: friendQuestProgress ?? this.friendQuestProgress,
    cameraDrops: cameraDrops ?? this.cameraDrops,
  );

  List<Achievement> get achievements => [
    Achievement(
      id: 'hot_streak',
      title: 'Hot Streak',
      description: 'Keep a care streak going',
      icon: PhosphorIconsRegular.fire,
      progress: streak.days.toDouble(),
      goals: const [7, 30, 100],
      rewards: const [CrateTier.sprout, CrateTier.grove, CrateTier.canopy],
    ),
    Achievement(
      id: 'harvester',
      title: 'Harvester',
      description: 'Harvest finished compost',
      icon: PhosphorIconsRegular.basket,
      progress: harvests.toDouble(),
      goals: const [3, 10, 25],
      rewards: const [CrateTier.sprout, CrateTier.grove, CrateTier.canopy],
    ),
    const Achievement(
      id: 'in_the_zone',
      title: 'In the Zone',
      description: 'Days with both layers in range',
      icon: PhosphorIconsRegular.target,
      progress: 18,
      goals: [7, 30, 90],
      rewards: [CrateTier.sprout, CrateTier.grove, CrateTier.canopy],
    ),
    const Achievement(
      id: 'balanced_diet',
      title: 'Balanced Diet',
      description: 'Weeks with greens and browns in balance',
      icon: PhosphorIconsRegular.scales,
      progress: 3,
      goals: [1, 4, 12],
      rewards: [CrateTier.sprout, CrateTier.grove, CrateTier.canopy],
    ),
    Achievement(
      id: 'good_listener',
      title: 'Good Listener',
      description: 'Next best actions followed',
      icon: PhosphorIconsRegular.lightbulb,
      progress: 34 + logs.where((l) => l.xp >= Xp.followedSuggestion).length.toDouble(),
      goals: const [10, 50, 200],
      rewards: const [CrateTier.sprout, CrateTier.grove, CrateTier.canopy],
    ),
    Achievement(
      id: 'landfill_dodger',
      title: 'Landfill Dodger',
      description: 'Kilograms kept from landfill',
      icon: PhosphorIconsRegular.recycle,
      progress: kgDiverted,
      goals: const [5, 25, 100],
      rewards: const [CrateTier.sprout, CrateTier.grove, CrateTier.canopy],
    ),
    Achievement(
      id: 'quest_keeper',
      title: 'Quest Keeper',
      description: 'Daily quests claimed',
      icon: PhosphorIconsRegular.checkCircle,
      progress: questsClaimedAllTime.toDouble(),
      goals: const [25, 100, 365],
      rewards: const [CrateTier.sprout, CrateTier.grove, CrateTier.canopy],
    ),
    Achievement(
      id: 'sharp_eye',
      title: 'Sharp Eye',
      description: 'Camera drops confirmed',
      icon: PhosphorIconsRegular.camera,
      progress: cameraDrops.toDouble(),
      goals: const [10, 50, 200],
      rewards: const [CrateTier.sprout, CrateTier.grove, CrateTier.canopy],
    ),
    const Achievement(
      id: 'climber',
      title: 'Climber',
      description: 'League promotions',
      icon: PhosphorIconsRegular.trendUp,
      progress: 2,
      goals: [1, 3, 5],
      rewards: [CrateTier.grove, CrateTier.grove, CrateTier.canopy],
    ),
    const Achievement(
      id: 'good_neighbour',
      title: 'Good Neighbour',
      description: 'Friend quests completed',
      icon: PhosphorIconsRegular.usersThree,
      progress: 1,
      goals: [1, 5, 20],
      rewards: [CrateTier.sprout, CrateTier.grove, CrateTier.canopy],
    ),
  ];
}

GameState _initial() {
  final now = DateTime.now();
  final today = dayOf(now);
  const cycle = [
    PlantSpecies.sprout,
    PlantSpecies.fern,
    PlantSpecies.tulip,
    PlantSpecies.sunflower,
    PlantSpecies.succulent,
    PlantSpecies.mushroom,
    PlantSpecies.lavender,
  ];
  final garden = <GardenPlant>[
    for (var i = 20; i >= 1; i--)
      GardenPlant(
        species: i == 12 ? PlantSpecies.pumpkin : cycle[(i * 3) % cycle.length],
        day: today.subtract(Duration(days: i)),
        wilted: i == 9 || i == 4,
        rare: i == 12,
      ),
  ];
  return GameState(
    weekXp: 185,
    totalXp: 2340,
    loam: 240,
    streak: StreakState(days: 6, lidLocks: 1, lastCareDay: today.subtract(const Duration(days: 1))),
    quests: const [
      Quest(id: 'checkin', title: 'Check on your layers', icon: PhosphorIconsRegular.stack, goal: 1, xp: 10, loam: 10),
      Quest(id: 'follow', title: 'Follow the next best action', icon: PhosphorIconsRegular.lightbulb, goal: 1, xp: 20, loam: 25),
      Quest(id: 'healthy', title: 'Both layers in range for 6h', icon: PhosphorIconsRegular.drop, goal: 6, xp: 15, loam: 15, unit: 'h'),
    ],
    garden: garden,
    logs: [
      LogEntry(item: foodById['cardboard']!, verdict: Verdict.great, time: now.subtract(const Duration(hours: 2, minutes: 10)), xp: 15, added: true),
      LogEntry(item: foodById['veg_peels']!, verdict: Verdict.great, time: now.subtract(const Duration(hours: 5, minutes: 40)), xp: 0, added: true),
      LogEntry(item: foodById['cheese']!, verdict: Verdict.avoid, time: now.subtract(const Duration(hours: 21)), xp: 5, added: false),
      LogEntry(item: foodById['coffee_grounds']!, verdict: Verdict.great, time: now.subtract(const Duration(hours: 26)), xp: 0, added: true),
    ],
    actionXpToday: 0,
    // Streak history: cared Oct 1–8 (4th covered by a Lid Lock), missed the 9th,
    // then six days in a row up to yesterday. Relative to today for the demo.
    careDays: {
      for (final d in const [16, 15, 14, 13, 11, 10, 9, 6, 5, 4, 3, 2, 1]) today.subtract(Duration(days: d)),
    },
    lockDays: {today.subtract(const Duration(days: 12))},
    bestStreak: 21,
    crates: const [CrateTier.sprout, CrateTier.grove],
    packets: 1,
    xpToday: 0,
    owned: const {'fern': 2, 'clover': 1, 'sprout': 3, 'acorn': 1, 'basil': 1, 'tulip': 1, 'cactus': 1, 'oak': 1, 'finish_classic': 1, 'finish_mint': 1},
    pity: const PityState(sinceEpic: 7, sinceLegendary: 19),
    equippedFinish: 'finish_classic',
    dailyClaimed: const {},
    harvests: 2,
    kgDiverted: 14.6,
    questsClaimedAllTime: 34,
    friendQuestProgress: 6,
  );
}

class LogOutcome {
  const LogOutcome({required this.xp, required this.followed, required this.capped});
  final int xp;
  final bool followed;
  final bool capped;
}

const lidLockPrice = 60;
const maxLidLocks = 2;

class GameController extends Notifier<GameState> {
  @override
  GameState build() => _initial();

  CelebrationQueue get _party => ref.read(celebrationProvider.notifier);

  /// Runs an action and toasts any achievement that levelled up because of it.
  T _act<T>(T Function() f) {
    final before = {for (final a in state.achievements) a.id: a.tier};
    final out = f();
    for (final a in state.achievements) {
      if (a.tier > (before[a.id] ?? 0)) {
        Future.delayed(const Duration(milliseconds: 2600), () => _toast.show('Achievement unlocked: ${a.title} Lv ${a.tier}'));
        break;
      }
    }
    return out;
  }

  ToastNotifier get _toast => ref.read(toastProvider.notifier);

  /// Adds XP, checking for level-ups and entering the promotion zone.
  void _addXp(int xp) {
    if (xp <= 0) return;
    final beforeLevel = state.level;
    state = state.copyWith(weekXp: state.weekXp + xp, totalXp: state.totalXp + xp, xpToday: state.xpToday + xp);
    if (state.level > beforeLevel) {
      _party.push(LevelUpCelebration(state.level, titleForLevel(state.level)));
    }
  }

  void _care() {
    final up = applyCareAction(state.streak, DateTime.now());
    state = state.copyWith(
      streak: up.state,
      careDays: {...state.careDays, dayOf(DateTime.now())},
      bestStreak: up.state.days > state.bestStreak ? up.state.days : state.bestStreak,
    );
    if (up.extended && !up.reset) {
      _party.push(StreakCelebration(up.state.days, lockUsed: up.locksUsed > 0));
    }
  }

  void _progressQuest(String id, double progress) {
    final quests = [for (final q in state.quests) q.id == id ? q.copyWith(progress: progress.clamp(0, q.goal).toDouble()) : q];
    final wasDone = state.quests.firstWhere((q) => q.id == id).done;
    state = state.copyWith(quests: quests);
    if (!wasDone && quests.firstWhere((q) => q.id == id).done) {
      _toast.show('Quest complete! Claim your reward');
    }
  }

  /// Opening the Layers tab counts as checking on the bin.
  void checkIn() => _act(_checkIn);

  void _checkIn() {
    final quest = state.quests.firstWhere((q) => q.id == 'checkin');
    if (quest.done) return;
    final xp = xpForAction(base: Xp.checkIn, earnedToday: state.actionXpToday);
    state = state.copyWith(actionXpToday: state.actionXpToday + xp);
    _progressQuest('checkin', 1);
    _addXp(xp);
    _toast.show('Checked on the bin', xp: xp);
    _care();
  }

  /// Logs a scrap. Adding earns nothing on its own: only following advice or
  /// keeping a bad item out does.
  LogOutcome recordLog(Advice advice, {required bool added, required Iterable<String> suggestedIds}) =>
      _act(() => _recordLog(advice, added: added, suggestedIds: suggestedIds));

  LogOutcome _recordLog(Advice advice, {required bool added, required Iterable<String> suggestedIds}) {
    final followed = added && advice.verdict != Verdict.avoid && suggestedIds.contains(advice.item.id);
    final keptOut = !added && advice.verdict == Verdict.avoid;
    final base = followed ? Xp.followedSuggestion : (keptOut ? Xp.avoidedBadAdd : Xp.log);
    final xp = xpForAction(base: base, earnedToday: state.actionXpToday);
    final entry = LogEntry(item: advice.item, verdict: advice.verdict, time: DateTime.now(), xp: xp, added: added);
    state = state.copyWith(
      logs: [entry, ...state.logs],
      actionXpToday: state.actionXpToday + xp,
      kgDiverted: added && advice.item.category != FoodCategory.avoid ? state.kgDiverted + advice.item.grams / 1000 : state.kgDiverted,
    );
    if (followed) {
      _progressQuest('follow', 1);
      state = state.copyWith(friendQuestProgress: state.friendQuestProgress + 1);
    }
    _addXp(xp);
    _care();
    return LogOutcome(xp: xp, followed: followed, capped: base > 0 && xp < base);
  }

  /// A reviewed camera drop: each row is logged like a manual add (adding
  /// earns 0; following the next action or taking a keep-out item back out
  /// earns the usual XP), and the drop counts toward Sharp Eye.
  List<LogOutcome> recordDrop(List<Advice> verdicts, {required List<bool> added, required Iterable<String> suggestedIds}) => _act(() {
    final out = [for (final (i, a) in verdicts.indexed) _recordLog(a, added: added[i], suggestedIds: suggestedIds)];
    state = state.copyWith(cameraDrops: state.cameraDrops + 1);
    return out;
  });

  void syncHealthyHours(double hours) {
    final q = state.quests.firstWhere((q) => q.id == 'healthy');
    if (q.progress != hours) _progressQuest('healthy', hours);
  }

  void claimQuest(String id) => _act(() => _claimQuest(id));

  void _claimQuest(String id) {
    final q = state.quests.firstWhere((q) => q.id == id);
    if (!q.done || q.claimed) return;
    final quests = [for (final x in state.quests) x.id == id ? x.copyWith(claimed: true) : x];
    state = state.copyWith(quests: quests, loam: state.loam + q.loam, questsClaimedAllTime: state.questsClaimedAllTime + 1);
    _party.push(QuestCelebration(q, allDone: quests.every((x) => x.claimed)));
    _toast.show('Quest done · +${q.loam} Loam', xp: q.xp);
    _addXp(q.xp);
  }

  void harvest() => _act(_harvest);

  void _harvest() {
    const xp = Xp.harvest;
    const loam = 50;
    final plant = GardenPlant(species: PlantSpecies.pumpkin, day: DateTime.now(), rare: true);
    final kg = 4.2;
    state = state.copyWith(harvests: state.harvests + 1, loam: state.loam + loam, garden: [...state.garden, plant]);
    _party.push(HarvestCelebration(plant, xp, loam, kg));
    _addXp(xp);
  }

  bool buyLidLock() {
    if (state.loam < lidLockPrice || state.streak.lidLocks >= maxLidLocks) return false;
    final s = state.streak;
    state = state.copyWith(
      loam: state.loam - lidLockPrice,
      streak: StreakState(days: s.days, lidLocks: s.lidLocks + 1, lastCareDay: s.lastCareDay),
    );
    return true;
  }

  /// Daily goal track: claim the reward at milestone [i] once today's XP reaches it.
  DailyReward? claimDaily(int i) {
    if (i < 0 || i >= dailyGoals.length) return null;
    if (state.xpToday < dailyGoals[i] || state.dailyClaimed.contains(i)) return null;
    final reward = dailyRewards[i];
    state = state.copyWith(
      dailyClaimed: {...state.dailyClaimed, i},
      loam: state.loam + reward.loam,
      crates: reward.crate == null ? state.crates : [...state.crates, reward.crate!],
    );
    return reward;
  }

  /// Opens the crate at [index] and pays out Loam + Seed Packets.
  CrateOpening? openCrate(int index) {
    if (index < 0 || index >= state.crates.length) return null;
    final tier = state.crates[index];
    final (loam, packets) = switch (tier) {
      CrateTier.sprout => (60, 1),
      CrateTier.grove => (160, 3),
      CrateTier.canopy => (400, 5),
    };
    final crates = [...state.crates]..removeAt(index);
    state = state.copyWith(crates: crates, loam: state.loam + loam, packets: state.packets + packets);
    return CrateOpening(tier, loam, packets);
  }

  final _rng = math.Random();

  /// Opens [count] Seed Packets, either from the inbox ([fromPackets]) or by
  /// spending Loam (100 each, 900 for ten). Duplicates refund Loam.
  List<PullOutcome>? pull(int count, {required bool fromPackets}) {
    final cost = fromPackets ? 0 : (count >= 10 ? tenPackPrice : packetPrice * count);
    if (fromPackets ? state.packets < count : state.loam < cost) return null;
    final (rarities, pity) = rollPulls(_rng, state.pity, count);
    final owned = {...state.owned};
    var refunds = 0;
    final out = <PullOutcome>[];
    for (final r in rarities) {
      final item = pickOfRarity(_rng, collectibles, r);
      final isNew = (owned[item.id] ?? 0) == 0;
      owned[item.id] = (owned[item.id] ?? 0) + 1;
      final refund = isNew ? 0 : duplicateRefund[r]!;
      refunds += refund;
      out.add(PullOutcome(item, isNew: isNew, refund: refund));
    }
    state = state.copyWith(owned: owned, pity: pity, packets: fromPackets ? state.packets - count : state.packets, loam: state.loam - cost + refunds);
    return out;
  }

  /// Equips a finish (Bin World ring colour) or a title (shown under your name).
  void equip(Collectible c) {
    if ((state.owned[c.id] ?? 0) == 0) return;
    switch (c.type) {
      case CollectibleType.finish:
        state = state.copyWith(equippedFinish: c.id);
      case CollectibleType.title:
        state = state.copyWith(equippedTitle: c.id);
      case CollectibleType.specimen:
        break;
    }
  }

  /// Demo / preview only: top up Loam.
  void debugGrantLoam(int n) => state = state.copyWith(loam: state.loam + n);

  void resetDemo() => state = _initial();
}

final gameProvider = NotifierProvider<GameController, GameState>(GameController.new);

/// Daily goal track: XP milestones and what each pays.
const dailyGoals = [20, 40, 60];

class DailyReward {
  const DailyReward(this.label, {this.loam = 0, this.crate});
  final String label;
  final int loam;
  final CrateTier? crate;
}

const dailyRewards = [DailyReward('15 Loam', loam: 15), DailyReward('30 Loam', loam: 30), DailyReward('Sprout crate', crate: CrateTier.sprout)];

class CrateOpening {
  const CrateOpening(this.tier, this.loam, this.packets);
  final CrateTier tier;
  final int loam;
  final int packets;
}
