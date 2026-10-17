import '../data/food_catalog.dart';
import '../domain/drop.dart';
import '../domain/gacha.dart';
import '../domain/models.dart';
import '../domain/xp_rules.dart';
import 'game.dart';

GameState rolloverGame(GameState g) {
  final today = dayOf(DateTime.now());
  if (g.day == today) return g;
  final sunday = today.subtract(Duration(days: today.weekday % 7));
  return g.copyWith(
    day: today,
    xpToday: 0,
    actionXpToday: 0,
    volumeGramsToday: 0,
    dailyClaimed: {},
    weekXp: g.day == null || g.day!.isBefore(sunday) ? 0 : g.weekXp,
    quests: [for (final q in g.quests) q.copyWith(progress: 0, claimed: false)],
  );
}

Map<String, dynamic> encodeGame(GameState g) => {
  'week': g.weekXp,
  'total': g.totalXp,
  'loam': g.loam,
  'streak': g.streak.days,
  'locks': g.streak.lidLocks,
  'last': g.streak.lastCareDay?.toIso8601String(),
  'day': g.day?.toIso8601String(),
  'action': g.actionXpToday,
  'today': g.xpToday,
  'grams': g.volumeGramsToday,
  'care': [for (final d in g.careDays) d.toIso8601String()],
  'locked': [for (final d in g.lockDays) d.toIso8601String()],
  'best': g.bestStreak,
  'crates': [for (final c in g.crates) c.name],
  'packets': g.packets,
  'owned': g.owned,
  'epic': g.pity.sinceEpic,
  'legendary': g.pity.sinceLegendary,
  'finish': g.equippedFinish,
  'title': g.equippedTitle,
  'claimed': g.dailyClaimed.toList(),
  'harvests': g.harvests,
  'kg': g.kgDiverted,
  'questsClaimed': g.questsClaimedAllTime,
  'friend': g.friendQuestProgress,
  'camera': g.cameraDrops,
  'milestones': g.paidMilestones.toList(),
  'achievements': g.earnedAchievements.toList(),
  'quests': [
    for (final q in g.quests) {'id': q.id, 'progress': q.progress, 'claimed': q.claimed},
  ],
  'garden': [
    for (final p in g.garden) {'species': p.species.name, 'day': p.day.toIso8601String(), 'wilted': p.wilted, 'rare': p.rare},
  ],
  'logs': [
    for (final l in g.logs)
      {
        'id': l.item.id,
        'name': l.item.name,
        'category': l.item.category.name,
        'grams': l.quantityG ?? l.item.grams,
        'verdict': l.verdict.name,
        'time': l.time.toIso8601String(),
        'xp': l.xp,
        'added': l.added,
      },
  ],
};

GameState decodeGame(Map<String, dynamic> j, GameState base) => base.copyWith(
  weekXp: j['week'],
  totalXp: j['total'],
  loam: j['loam'],
  streak: StreakState(days: j['streak'], lidLocks: j['locks'], lastCareDay: j['last'] == null ? null : DateTime.parse(j['last'])),
  day: j['day'] == null ? null : DateTime.parse(j['day']),
  actionXpToday: j['action'],
  xpToday: j['today'],
  volumeGramsToday: (j['grams'] as num).toDouble(),
  careDays: {for (final d in j['care']) DateTime.parse(d)},
  lockDays: {for (final d in j['locked']) DateTime.parse(d)},
  bestStreak: j['best'],
  crates: [for (final c in j['crates']) CrateTier.values.byName(c)],
  packets: j['packets'],
  owned: Map<String, int>.from(j['owned']),
  pity: PityState(sinceEpic: j['epic'], sinceLegendary: j['legendary']),
  equippedFinish: j['finish'],
  equippedTitle: j['title'],
  dailyClaimed: Set<int>.from(j['claimed']),
  harvests: j['harvests'],
  kgDiverted: (j['kg'] as num).toDouble(),
  questsClaimedAllTime: j['questsClaimed'],
  friendQuestProgress: j['friend'],
  cameraDrops: j['camera'],
  paidMilestones: Set<int>.from(j['milestones']),
  earnedAchievements: Set<String>.from(j['achievements']),
  quests: [
    for (final q in base.quests)
      q.copyWith(
        progress: (j['quests'] as List).where((x) => x['id'] == q.id).map((x) => (x['progress'] as num).toDouble()).firstOrNull ?? 0,
        claimed: (j['quests'] as List).any((x) => x['id'] == q.id && x['claimed'] == true),
      ),
  ],
  garden: [
    for (final p in j['garden'])
      GardenPlant(species: PlantSpecies.values.byName(p['species']), day: DateTime.parse(p['day']), wilted: p['wilted'], rare: p['rare']),
  ],
  logs: [
    for (final l in j['logs'])
      LogEntry(
        item: foodById[l['id']] ?? customFood(l['name'], FoodCategory.values.byName(l['category']), amountFor((l['grams'] as num).toDouble())),
        verdict: Verdict.values.byName(l['verdict']),
        time: DateTime.parse(l['time']),
        xp: l['xp'],
        added: l['added'],
        quantityG: (l['grams'] as num).toDouble(),
      ),
  ],
);

GameState emptyGame(GameState base) => base.copyWith(
  weekXp: 0,
  totalXp: 0,
  loam: 0,
  streak: const StreakState(days: 0, lidLocks: 0, lastCareDay: null),
  careDays: {},
  lockDays: {},
  bestStreak: 0,
  garden: [],
  logs: [],
  crates: [],
  packets: 0,
  owned: {},
  pity: const PityState(sinceEpic: 0, sinceLegendary: 0),
  harvests: 0,
  kgDiverted: 0,
  questsClaimedAllTime: 0,
  friendQuestProgress: 0,
  serverAchievements: [],
  leagueTier: 0,
);

GameState serverGame(Map<String, dynamic> bundle, GameState base) {
  final p = bundle['profile'] as Map<String, dynamic>;
  final collection = bundle['collection'];
  final daily = p['daily_goal'];
  final care = {for (final d in p['care_days']) DateTime.parse(d)};
  final quests = bundle['quests']['quests'] as List;
  final achievements = p['achievements'] as List;
  return emptyGame(base).copyWith(
    totalXp: p['total_xp'],
    weekXp: p['week_xp'] ?? 0,
    loam: p['loam'],
    streak: StreakState(days: p['streak_days'], lidLocks: p['lid_locks'], lastCareDay: care.isEmpty ? null : (care.toList()..sort()).last),
    bestStreak: p['best_streak'],
    careDays: care,
    lockDays: {for (final d in p['lock_days']) DateTime.parse(d)},
    quests: [
      for (final q in base.quests)
        q.copyWith(
          progress: quests.where((x) => x['key'] == q.id).map((x) => (x['progress'] as num).toDouble()).firstOrNull ?? 0,
          claimed: quests.any((x) => x['key'] == q.id && x['claimed'] == true),
        ),
    ],
    crates: [for (final c in bundle['rewards']['crates']) CrateTier.values.byName(c['tier'])],
    packets: p['packets'],
    xpToday: daily['xp_today'],
    actionXpToday: p['action_xp_today'] ?? 0,
    volumeGramsToday: (p['grams_today'] as num? ?? 0).toDouble(),
    dailyClaimed: {
      for (final g in daily['goals'])
        if (g['claimed'] == true) g['index'] as int,
    },
    owned: {
      for (final c in collection['items'])
        if ((c['copies'] as int) > 0) c['id'] as String: c['copies'] as int,
    },
    pity: PityState(sinceEpic: collection['pity']['since_epic'], sinceLegendary: collection['pity']['since_legendary']),
    equippedFinish: p['equipped_finish'],
    equippedTitle: p['equipped_title'],
    kgDiverted: (p['impact']['kg_diverted'] as num).toDouble(),
    harvests: (p['stats']?['harvests'] as int?) ?? 0,
    cameraDrops: (p['stats']?['drops_confirmed'] as int?) ?? 0,
    questsClaimedAllTime: (p['stats']?['quests_claimed'] as int?) ?? 0,
    leagueTier: bundle['league']?['tier_index'] ?? 0,
    serverAchievements: [
      for (final a in base.achievements)
        if (achievements.any((x) => x['id'] == a.id))
          Achievement(
            id: a.id,
            title: a.title,
            description: a.description,
            icon: a.icon,
            progress: (achievements.firstWhere((x) => x['id'] == a.id)['progress'] as num).toDouble(),
            goals: a.goals,
            rewards: a.rewards,
          ),
    ],
    logs: [
      for (final l in bundle['logs'])
        LogEntry(
          item:
              foodById[l['catalog_id']] ??
              customFood(
                l['item'],
                FoodCategory.values.where((c) => c.name == l['category']).firstOrNull ?? FoodCategory.avoid,
                amountFor((l['quantity_g'] as num? ?? 0).toDouble()),
              ),
          verdict: l['category'] == 'avoid' ? Verdict.avoid : Verdict.careful,
          time: DateTime.parse(l['time']).toLocal(),
          xp: l['xp_awarded'] ?? 0,
          added: l['action'] == 'added',
          quantityG: (l['quantity_g'] as num? ?? 0).toDouble(),
        ),
    ],
  );
}
