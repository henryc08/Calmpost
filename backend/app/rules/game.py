"""Game and economy rules. No I/O.

Mirrors app/lib/domain/xp_rules.dart and app/lib/state/game.dart (and
AGENTS.md section 8). Confirmed compostable volume and care both earn XP.
"""

import hashlib
from datetime import date

# --- XP --------------------------------------------------------------------

XP = {
    "log": 0,
    "followed_suggestion": 15,
    "avoided_bad_add": 5,
    "check_in": 5,
    "healthy_layer_day": 10,
    "weekly_balance": 30,
    "harvest": 100,
}

# Action XP is capped per day so it cannot be farmed by tapping
# (xpForAction / dailyActionCap). Sensor-driven XP and quest rewards are not.
DAILY_ACTION_CAP = 60
GRAMS_PER_XP = 20
CAPPED_KINDS = ("compost_added", "followed_suggestion", "avoided_bad_add", "check_in")


def volume_xp(grams: float, already_logged: float = 0) -> int:
    return int((already_logged + max(0, grams)) // GRAMS_PER_XP) - int(already_logged // GRAMS_PER_XP)


def cap_xp(base: int, earned_today: int) -> int:
    return min(base, max(0, DAILY_ACTION_CAP - earned_today))


# Ledger kinds that count as caring for the bin (keep a streak alive).
# A confirmed compostable addition keeps the streak alive.
CARE_KINDS = (
    "compost_added",
    "followed_suggestion",
    "avoided_bad_add",
    "check_in",
    "healthy_layer_day",
    "weekly_balance",
    "harvest",
    "daily_quest",
    "lid_lock_used",
)

# --- Loam (the soft currency, never sold for money) ------------------------

LOAM = {"harvest": 50}

LID_LOCK_PRICE = 60
MAX_LID_LOCKS = 2
STARTER_FINISH = "finish_classic"  # owned by everyone from the start (the app seeds it too)

# --- levels ----------------------------------------------------------------

_TITLES = (
    (1, "Scrap Saver"),
    (4, "Peel Keeper"),
    (7, "Soil Whisperer"),
    (12, "Worm Wrangler"),
    (18, "Humus Hero"),
    (26, "Loam Legend"),
    (36, "Compost Sage"),
)


XP_PER_LEVEL = 120


def xp_for_level(n: int) -> int:
    """Every step costs the same amount; lifetime XP is preserved."""
    return XP_PER_LEVEL * (n - 1)


def level_for_xp(xp: int) -> int:
    n = 1
    while n < 50 and xp_for_level(n + 1) <= xp:
        n += 1
    return n


def title_for_level(level: int) -> str:
    title = _TITLES[0][1]
    for threshold, name in _TITLES:
        if level >= threshold:
            title = name
    return title


# --- daily quests (the app's three, game.dart _initial) ---------------------

QUESTS = (
    {"key": "checkin", "title": "Check on your layers", "goal": 1, "unit": "", "xp": 10, "loam": 10},
    {"key": "follow", "title": "Follow the next best action", "goal": 1, "unit": "", "xp": 20, "loam": 25},
    {"key": "healthy", "title": "Both layers in range for 6h", "goal": 6, "unit": "h", "xp": 15, "loam": 15},
)
QUESTS_BY_KEY = {q["key"]: q for q in QUESTS}

# --- daily goal: today's XP unlocks three rewards (dailyGoals) --------------

DAILY_GOALS = (
    {"xp": 20, "label": "15 Loam", "loam": 15, "crate": None},
    {"xp": 40, "label": "30 Loam", "loam": 30, "crate": None},
    {"xp": 60, "label": "Sprout crate", "loam": 0, "crate": "sprout"},
)

# --- crates (openCrate) -------------------------------------------------------

CRATE_TIERS = ("sprout", "grove", "canopy")
CRATE_CONTENTS = {"sprout": {"loam": 60, "packets": 1}, "grove": {"loam": 160, "packets": 3}, "canopy": {"loam": 400, "packets": 5}}


def crate_name(tier: str) -> str:
    return f"{tier.capitalize()} crate"


# --- streak milestones -----------------------------------------------------

STREAK_MILESTONES = (
    {"days": 3, "loam": 25, "crate": None},
    {"days": 7, "loam": 50, "crate": "sprout"},
    {"days": 14, "loam": 100, "crate": None},
    {"days": 30, "loam": 200, "crate": "grove"},
    {"days": 100, "loam": 500, "crate": "canopy"},
)

# --- achievements (every tier pays a crate; GameState.achievements) ---------
#
# metric names the stat the service computes for progress.

ACHIEVEMENTS = (
    {"id": "hot_streak", "title": "Hot Streak", "description": "Keep a care streak going", "metric": "best_streak", "goals": (7, 30, 100), "rewards": ("sprout", "grove", "canopy")},
    {"id": "harvester", "title": "Harvester", "description": "Harvest finished compost", "metric": "harvests", "goals": (3, 10, 25), "rewards": ("sprout", "grove", "canopy")},
    {"id": "in_the_zone", "title": "In the Zone", "description": "Days with both layers in range", "metric": "healthy_days", "goals": (7, 30, 90), "rewards": ("sprout", "grove", "canopy")},
    {"id": "balanced_diet", "title": "Balanced Diet", "description": "Weeks with greens and browns in balance", "metric": "balanced_weeks", "goals": (1, 4, 12), "rewards": ("sprout", "grove", "canopy")},
    {"id": "good_listener", "title": "Good Listener", "description": "Next best actions followed", "metric": "tips_followed", "goals": (10, 50, 200), "rewards": ("sprout", "grove", "canopy")},
    {"id": "landfill_dodger", "title": "Landfill Dodger", "description": "Kilograms kept from landfill", "metric": "kg_diverted", "goals": (5, 25, 100), "rewards": ("sprout", "grove", "canopy")},
    {"id": "quest_keeper", "title": "Quest Keeper", "description": "Daily quests claimed", "metric": "quests_claimed", "goals": (25, 100, 365), "rewards": ("sprout", "grove", "canopy")},
    {"id": "sharp_eye", "title": "Sharp Eye", "description": "Camera drops confirmed", "metric": "drops_confirmed", "goals": (10, 50, 200), "rewards": ("sprout", "grove", "canopy")},
    {"id": "climber", "title": "Climber", "description": "League promotions", "metric": "promotions", "goals": (1, 3, 5), "rewards": ("grove", "grove", "canopy")},
    {"id": "good_neighbour", "title": "Good Neighbour", "description": "Friend quests completed", "metric": "friend_quests", "goals": (1, 5, 20), "rewards": ("sprout", "grove", "canopy")},
)


def achievement_tier(goals: tuple, progress: float) -> int:
    return sum(1 for g in goals if progress >= g)


# --- leagues -----------------------------------------------------------------

LEAGUE_TIERS = ("Seedling", "Sprout", "Fern", "Sapling", "Oak", "Sequoia")
LEAGUE_SIZE = 30
LEAGUE_PROMOTE = 7
LEAGUE_DEMOTE = 5
LEAGUE_FINISH_LOAM = {"promote": 150, "safe": 60, "demote": 20}


def league_zone(rank: int, cohort_size: int, tier_index: int) -> str:
    """zoneForRank(): no promotion from the top tier, no demotion from the bottom."""
    if rank <= LEAGUE_PROMOTE and tier_index < len(LEAGUE_TIERS) - 1:
        return "promote"
    if rank > cohort_size - LEAGUE_DEMOTE and tier_index > 0:
        return "demote"
    return "safe"


# --- impact (Impact in xp_rules.dart) -----------------------------------------

CO2E_PER_KG = 0.55
DOLLARS_PER_KG_COMPOST = 1.6
COMPOST_YIELD = 0.4


def impact(total_grams: int) -> dict:
    kg = total_grams / 1000.0
    return {
        "kg_diverted": round(kg, 2),
        "co2e_kg_avoided": round(kg * CO2E_PER_KG, 2),
        "fertilizer_saved_usd": round(kg * COMPOST_YIELD * DOLLARS_PER_KG_COMPOST, 2),
        "is_estimate": True,
    }


# --- streaks -------------------------------------------------------------------

def streak_lengths(care_days: list[date], today: date) -> tuple[int, int]:
    """(current, best) streak from distinct care days (any order).

    A streak survives until the end of the day after the last care day, so
    caring yesterday but not yet today still shows a live streak.
    """
    days = sorted(set(care_days), reverse=True)
    if not days:
        return 0, 0
    current = 0
    if (today - days[0]).days <= 1:
        current = 1
        for prev, nxt in zip(days, days[1:]):
            if (prev - nxt).days == 1:
                current += 1
            else:
                break
    best = run = 1
    for prev, nxt in zip(days, days[1:]):
        run = run + 1 if (prev - nxt).days == 1 else 1
        best = max(best, run)
    return current, max(best, current)


def missed_days_to_cover(care_days: list[date], today: date) -> list[date]:
    """Days a Lid Lock would cover so today's care continues the streak.

    The gap between the most recent care day before today and today, or []
    when there is no gap (or no earlier streak to protect).
    """
    earlier = sorted(d for d in set(care_days) if d < today)
    if not earlier:
        return []
    last = earlier[-1]
    gap = (today - last).days - 1
    return [date.fromordinal(last.toordinal() + i) for i in range(1, gap + 1)]


# --- misc ------------------------------------------------------------------

def stable_index(text: str, modulo: int) -> int:
    """A stable small number from text (Python's hash() is salted per process)."""
    return hashlib.sha256(text.encode()).digest()[0] % modulo
