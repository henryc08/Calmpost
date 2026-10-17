import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
    required this.harvests,
    required this.kgDiverted,
    required this.questsClaimedAllTime,
    required this.friendQuestProgress,
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
  final int harvests;
  final double kgDiverted;
  final int questsClaimedAllTime;
  final int friendQuestProgress;

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
    int? harvests,
    double? kgDiverted,
    int? questsClaimedAllTime,
    int? friendQuestProgress,
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
    harvests: harvests ?? this.harvests,
    kgDiverted: kgDiverted ?? this.kgDiverted,
    questsClaimedAllTime: questsClaimedAllTime ?? this.questsClaimedAllTime,
    friendQuestProgress: friendQuestProgress ?? this.friendQuestProgress,
  );

  List<Achievement> get achievements => [
    Achievement(
      id: 'streak',
      title: 'Wildfire',
      description: 'Keep a care streak going',
      icon: PhosphorIconsFill.fire,
      progress: streak.days.toDouble(),
      goals: const [3, 7, 30],
    ),
    Achievement(
      id: 'diverted',
      title: 'Landfill Dodger',
      description: 'Kilograms kept out of landfill',
      icon: PhosphorIconsFill.recycle,
      progress: kgDiverted,
      goals: const [5, 10, 25],
    ),
    Achievement(
      id: 'harvest',
      title: 'Harvester',
      description: 'Harvest finished compost',
      icon: PhosphorIconsFill.basket,
      progress: harvests.toDouble(),
      goals: const [1, 2, 5],
    ),
    const Achievement(
      id: 'moisture',
      title: 'Moisture Master',
      description: 'Days with both layers in range',
      icon: PhosphorIconsFill.drop,
      progress: 18,
      goals: [7, 14, 30],
    ),
    Achievement(
      id: 'garden',
      title: 'Green Thumb',
      description: 'Grow plants in your garden',
      icon: PhosphorIconsFill.plant,
      progress: garden.where((p) => !p.wilted).length.toDouble(),
      goals: const [10, 25, 50],
    ),
    Achievement(
      id: 'quests',
      title: 'Quest Seeker',
      description: 'Complete daily quests',
      icon: PhosphorIconsFill.target,
      progress: questsClaimedAllTime.toDouble(),
      goals: const [10, 25, 50],
    ),
    const Achievement(
      id: 'balance',
      title: 'Perfect Balance',
      description: 'Weeks with greens and browns balanced',
      icon: PhosphorIconsFill.scales,
      progress: 3,
      goals: [1, 2, 4],
    ),
    Achievement(
      id: 'rare',
      title: 'Rare Collector',
      description: 'Grow rare plants from harvests',
      icon: PhosphorIconsFill.sparkle,
      progress: garden.where((p) => p.rare).length.toDouble(),
      goals: const [2, 5, 10],
    ),
    const Achievement(id: 'league', title: 'Climber', description: 'Get promoted in leagues', icon: PhosphorIconsFill.trophy, progress: 2, goals: [1, 3, 5]),
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
    logs: const [],
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
    state = state.copyWith(weekXp: state.weekXp + xp, totalXp: state.totalXp + xp);
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

  void resetDemo() => state = _initial();
}

final gameProvider = NotifierProvider<GameController, GameState>(GameController.new);
