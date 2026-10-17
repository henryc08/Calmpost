"""Level rewards and seed buffs, mirrored in domain/progression.dart."""
MAX_LEVEL = 50
SEED_BUFFS = {
    'fern': [('quest_healthy', {'xp': 1})],
    'sprout': [('quest_checkin', {'xp': 1})],
    'basil': [('quest_follow', {'xp': 1})],
    'clover': [('check_in', {'xp': 1})],
    'wheat': [('followed_suggestion', {'xp': 1})],
    'pepper': [('avoided_bad_add', {'xp': 1})],
    'carrot': [('quest_follow', {'loam': 1})],
    'acorn': [('quest_checkin', {'loam': 1})],
    'potted': [('daily_quest', {'xpPercent': 10})],
    'tulip': [('daily_quest', {'loamPercent': 10})],
    'cactus': [('check_in', {'xp': 2}), ('avoided_bad_add', {'xp': 2})],
    'lotus': [('quest_healthy', {'xpPercent': 20, 'loamPercent': 20})],
    'citrus': [('quest_follow', {'xpPercent': 20}), ('followed_suggestion', {'xp': 2})],
    'feather': [('quest_checkin', {'xp': 2, 'loam': 2})],
    'oak': [('daily_quest', {'xpPercent': 25})],
    'pine': [('quest_healthy', {'xpPercent': 35}), ('check_in', {'xp': 3})],
    'palm': [('quest_follow', {'loamPercent': 35}), ('followed_suggestion', {'xp': 3})],
    'bloom': [('daily_quest', {'loamPercent': 25})],
    'butterfly_bush': [('daily_quest', {'xpPercent': 20, 'loamPercent': 20})],
    'night_moss': [('daily_quest', {'xpPercent': 40}), ('check_in', {'xp': 4})],
    'firefern': [('quest_follow', {'xpPercent': 50, 'loamPercent': 40}), ('followed_suggestion', {'xp': 5})],
    'frost': [('daily_quest', {'loamPercent': 40}), ('avoided_bad_add', {'xp': 4})],
    'ghost_orchid': [('daily_quest', {'xpPercent': 25, 'loamPercent': 60})],
    'golden_sprout': [('daily_quest', {'xpPercent': 60, 'loamPercent': 25})],
}


def level_reward(level: int) -> dict:
    if not 1 <= level <= MAX_LEVEL:
        raise ValueError('invalid level')
    return {
        'loam': 20 + 5 * (level - 1),
        'packets': 1 if level % 3 == 0 else 0,
        'crate': 'grove' if level % 10 == 0 else ('sprout' if level % 5 == 0 else None),
        'seed': {1: 'sprout', 5: 'clover', 10: 'bloom'}.get(level),
    }


def _boost(base: int, kind: str, seed: str | None, currency: str, quest: str | None) -> int:
    if base <= 0:
        return base
    return base + sum(
        effect.get(currency, 0) + base * effect.get(f'{currency}Percent', 0) // 100
        for target, effect in SEED_BUFFS.get(seed, [])
        if target == kind or (kind == 'daily_quest' and quest is not None and target == f'quest_{quest}')
    )


def seed_xp(base: int, kind: str, seed: str | None, *, quest: str | None = None) -> int:
    return _boost(base, kind, seed, 'xp', quest)


def seed_loam(base: int, kind: str, seed: str | None, *, quest: str | None = None) -> int:
    return _boost(base, kind, seed, 'loam', quest)
