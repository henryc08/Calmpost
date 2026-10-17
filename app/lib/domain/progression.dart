import 'models.dart';

const maxLevel = 50;

class LevelReward {
  const LevelReward({required this.loam, this.packets = 0, this.crate, this.seed});
  final int loam;
  final int packets;
  final CrateTier? crate;
  final String? seed;
}

LevelReward rewardForLevel(int level) {
  if (level < 1 || level > maxLevel) throw RangeError.range(level, 1, maxLevel);
  return LevelReward(
    loam: 20 + 5 * (level - 1),
    packets: level % 3 == 0 ? 1 : 0,
    crate: level % 10 == 0 ? CrateTier.grove : (level % 5 == 0 ? CrateTier.sprout : null),
    seed: switch (level) {
      1 => 'sprout',
      5 => 'clover',
      10 => 'bloom',
      _ => null,
    },
  );
}

class SeedEffect {
  const SeedEffect(this.kind, {this.xp = 0, this.loam = 0, this.xpPercent = 0, this.loamPercent = 0});
  final String kind;
  final int xp, loam, xpPercent, loamPercent;

  bool matches(String event, String? quest) => kind == event || (event == 'daily_quest' && quest != null && kind == 'quest_$quest');
}

class SeedBuff {
  const SeedBuff(this.name, this.effects);
  final String name;
  final List<SeedEffect> effects;
}

// One active plant; duplicate copies never stack. Commons use tiny flat awards
// so their bonuses actually pay out instead of rounding a small percentage to 0.
const seedBuffs = <String, SeedBuff>{
  // Common: one extra point on a narrow activity.
  'fern': SeedBuff('Quiet canopy', [SeedEffect('quest_healthy', xp: 1)]),
  'sprout': SeedBuff('First steps', [SeedEffect('quest_checkin', xp: 1)]),
  'basil': SeedBuff('Good habits', [SeedEffect('quest_follow', xp: 1)]),
  'clover': SeedBuff('Daily luck', [SeedEffect('check_in', xp: 1)]),
  'wheat': SeedBuff('Steady tending', [SeedEffect('followed_suggestion', xp: 1)]),
  'pepper': SeedBuff('Little guardian', [SeedEffect('avoided_bad_add', xp: 1)]),
  'carrot': SeedBuff('Root savings', [SeedEffect('quest_follow', loam: 1)]),
  'acorn': SeedBuff('Pocket change', [SeedEffect('quest_checkin', loam: 1)]),
  // Uncommon: broader 10% rewards or focused 20% rewards and small care boosts.
  'potted': SeedBuff('Room to grow', [SeedEffect('daily_quest', xpPercent: 10)]),
  'tulip': SeedBuff('Petal purse', [SeedEffect('daily_quest', loamPercent: 10)]),
  'cactus': SeedBuff('Watchful spines', [SeedEffect('check_in', xp: 2), SeedEffect('avoided_bad_add', xp: 2)]),
  'lotus': SeedBuff('Still water', [SeedEffect('quest_healthy', xpPercent: 20, loamPercent: 20)]),
  'citrus': SeedBuff('Fresh start', [SeedEffect('quest_follow', xpPercent: 20), SeedEffect('followed_suggestion', xp: 2)]),
  'feather': SeedBuff('Light touch', [SeedEffect('quest_checkin', xp: 2, loam: 2)]),
  // Rare: stronger specialists, with a clear choice between growth and savings.
  'oak': SeedBuff('Deep roots', [SeedEffect('daily_quest', xpPercent: 25)]),
  'pine': SeedBuff('Evergreen watch', [SeedEffect('quest_healthy', xpPercent: 35), SeedEffect('check_in', xp: 3)]),
  'palm': SeedBuff('Sunny savings', [SeedEffect('quest_follow', loamPercent: 35), SeedEffect('followed_suggestion', xp: 3)]),
  'bloom': SeedBuff('Abundance', [SeedEffect('daily_quest', loamPercent: 25)]),
  'butterfly_bush': SeedBuff('Shared garden', [SeedEffect('daily_quest', xpPercent: 20, loamPercent: 20)]),
  // Epic: pronounced quest bonuses paired with a complementary care effect.
  'night_moss': SeedBuff('Moonlit study', [SeedEffect('daily_quest', xpPercent: 40), SeedEffect('check_in', xp: 4)]),
  'firefern': SeedBuff('Kindled growth', [SeedEffect('quest_follow', xpPercent: 50, loamPercent: 40), SeedEffect('followed_suggestion', xp: 5)]),
  'frost': SeedBuff('Winter reserves', [SeedEffect('daily_quest', loamPercent: 40), SeedEffect('avoided_bad_add', xp: 4)]),
  // Legendary: dual rewards, with a different primary focus for each seed.
  'ghost_orchid': SeedBuff('Hidden riches', [SeedEffect('daily_quest', xpPercent: 25, loamPercent: 60)]),
  'golden_sprout': SeedBuff('Golden age', [SeedEffect('daily_quest', xpPercent: 60, loamPercent: 25)]),
};

const _effectTargets = {
  'daily_quest': 'all daily quests',
  'quest_checkin': 'the layers quest',
  'quest_follow': 'the next-action quest',
  'quest_healthy': 'the healthy-layers quest',
  'check_in': 'daily check-in',
  'followed_suggestion': 'following advice',
  'avoided_bad_add': 'keeping bad items out',
};

String buffLabel(SeedBuff buff) => buff.effects
    .map((e) {
      final amounts = [
        if (e.xp > 0) '+${e.xp} XP',
        if (e.xpPercent > 0) '+${e.xpPercent}% XP',
        if (e.loam > 0) '+${e.loam} Loam',
        if (e.loamPercent > 0) '+${e.loamPercent}% Loam',
      ].join(' / ');
      return '$amounts for ${_effectTargets[e.kind]}';
    })
    .join(' · ');

String buffDetail(SeedBuff buff) => [
  '${buff.name}.',
  if (buff.effects.any((e) => e.kind == 'daily_quest' || e.kind.startsWith('quest_'))) 'Quest bonuses use the seed active when claimed.',
  if (buff.effects.any((e) => e.xpPercent > 0 || e.loamPercent > 0)) 'Percentage bonuses round down.',
  if (buff.effects.any((e) => const ['check_in', 'followed_suggestion', 'avoided_bad_add'].contains(e.kind)))
    'Care bonuses count toward the 60 XP daily action cap.',
  'Volume XP is unchanged. One active seed; duplicates never stack.',
].join(' ');

int seedXp(int base, String kind, String? seed, {String? quest}) {
  if (base <= 0) return base;
  final effects = seedBuffs[seed]?.effects.where((e) => e.matches(kind, quest)) ?? const <SeedEffect>[];
  return base + effects.fold<int>(0, (bonus, e) => bonus + e.xp + base * e.xpPercent ~/ 100);
}

int seedLoam(int base, String kind, String? seed, {String? quest}) {
  if (base <= 0) return base;
  final effects = seedBuffs[seed]?.effects.where((e) => e.matches(kind, quest)) ?? const <SeedEffect>[];
  return base + effects.fold<int>(0, (bonus, e) => bonus + e.loam + base * e.loamPercent ~/ 100);
}
