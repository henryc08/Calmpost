"""Composting and game rules.

**The Flutter app owns these rules.** Every constant and curve here mirrors
`app/lib/domain/` on the frontend branch -- health_score.dart, xp_rules.dart
and advice_rules.dart -- so the backend and the app can never disagree about
what a reading means or what an action is worth.

If you change a number here, change it there too (and vice versa). The
divergences that matter:
  - temperature is scored on the delta ABOVE AMBIENT, not absolute degrees
  - CO2 trend is % per day, not ppm per hour
  - greens/browns are measured in rough cups of volume, not item counts
  - the soft currency is called loam
"""

import math
from typing import Literal

MoistureState = Literal["dry", "ok", "wet", "unknown"]
# Mirrors Stage in models.dart -- note 'cooling' between hot and curing.
Stage = Literal["started", "active", "hot", "cooling", "curing", "ready", "harvested"]
STAGE_ORDER = ("started", "active", "hot", "cooling", "curing", "ready", "harvested")

# Mirrors Verdict in models.dart.
Verdict = Literal["great", "careful", "avoid"]
# Mirrors Balance in models.dart.
Balance = Literal["needs_greens", "needs_browns", "balanced"]

# --- bands (health_score.dart) ---------------------------------------------

MOISTURE_LO = 40.0
MOISTURE_HI = 60.0
MOISTURE_FALLOFF = 25.0

# One "cup" of scraps, for converting logged grams into the volume units the
# app's balance ratio uses.
CUP_GRAMS = 200.0


def band_score(v: float, lo: float, hi: float, falloff: float) -> float:
    """100 inside [lo, hi], falling linearly to 0 at `falloff` outside it.

    Identical to bandScore() in health_score.dart.
    """
    if lo <= v <= hi:
        return 100.0
    d = (lo - v) if v < lo else (v - hi)
    return max(0.0, 100.0 - d / falloff * 100.0)


# --- calibration -----------------------------------------------------------

def moisture_pct(raw: int | None, raw_dry: int, raw_wet: int) -> float | None:
    """Raw ADC count -> percentage.

    The sketch uses analogReadResolution(10), so counts run 0-1023.
    Capacitive probes read LOWER as they get wetter, so raw_dry is the high
    count (probe in air). Returns None for a missing reading rather than a
    misleading 0.
    """
    if raw is None:
        return None
    span = raw_dry - raw_wet
    if span == 0:
        return None
    return max(0.0, min(100.0, 100.0 * (raw_dry - raw) / span))


def moisture_state(pct: float | None) -> MoistureState:
    if pct is None:
        return "unknown"
    if pct < MOISTURE_LO:
        return "dry"
    if pct > MOISTURE_HI:
        return "wet"
    return "ok"


# --- health components (health_score.dart) ---------------------------------
#
# computeHealth() averages the two layers. With one probe we have only one
# measured layer, so each component takes the layers it actually has and the
# caller is told which were measured.

def moisture_component(top: float | None, bottom: float | None) -> float | None:
    scores = [
        band_score(v, MOISTURE_LO, MOISTURE_HI, MOISTURE_FALLOFF)
        for v in (top, bottom)
        if v is not None
    ]
    return sum(scores) / len(scores) if scores else None


def temperature_component(
    top_temp: float | None,
    bottom_temp: float | None,
    ambient: float | None,
    bottom_curing: bool,
) -> float | None:
    """Scored on how far above ambient the pile runs.

    A pile at 25C means nothing on its own: in a 24C room it is cold, in a 5C
    garage it is working hard. This is the app's model, and it is the right
    one -- which is why the air sensor's temperature matters.
    """
    if ambient is None:
        return None
    scores = []
    if top_temp is not None:
        scores.append(band_score(top_temp - ambient, 5, 25, 10))
    if bottom_temp is not None:
        # A curing bottom layer is *supposed* to be close to ambient.
        if bottom_curing:
            scores.append(band_score(bottom_temp - ambient, -2, 8, 10))
        else:
            scores.append(band_score(bottom_temp - ambient, 3, 25, 10))
    return sum(scores) / len(scores) if scores else None


def co2_component(
    co2_ppm: float | None,
    top_stage: str,
    bottom_curing: bool,
    slope_pct_per_day: float | None,
) -> float | None:
    """Activity plus trend, as computeHealth does it."""
    if co2_ppm is None:
        return None
    active = top_stage in ("active", "hot")
    activity = band_score(co2_ppm, 900, 6000, 900) if active else 100.0

    if bottom_curing and slope_pct_per_day is not None:
        trend = 100.0 if slope_pct_per_day <= 2 else max(0.0, 100.0 - slope_pct_per_day * 10)
    else:
        trend = 100.0
    return (activity + trend) / 2


def balance_ratio(greens_cups: float, browns_cups: float) -> float:
    """browns:greens over 7 days. No greens is treated as 4.0, as the app does."""
    return 4.0 if greens_cups <= 0 else browns_cups / greens_cups


def balance_component(greens_cups: float, browns_cups: float) -> float:
    return band_score(balance_ratio(greens_cups, browns_cups), 1.6, 3.4, 1.4)


def balance_of(top_moisture: float | None, greens_cups: float, browns_cups: float) -> Balance:
    """Mirrors balanceOf() in health_score.dart."""
    ratio = balance_ratio(greens_cups, browns_cups)
    if (top_moisture is not None and top_moisture > 64) or ratio < 1.2:
        return "needs_browns"
    if (top_moisture is not None and top_moisture < 36) or ratio > 4:
        return "needs_greens"
    return "balanced"


# --- stage -----------------------------------------------------------------

def stage(
    temp_c: float | None,
    ambient_c: float | None,
    co2_ppm: float | None,
    pct: float | None,
    slope_pct_per_day: float | None = None,
    co2_ok: bool = True,
) -> Stage:
    """Batch Journey stage from sensor trends.

    A guide, not a lab test. Temperature is read as a delta above ambient for
    the same reason the health score does it: absolute degrees cannot tell a
    working pile from a warm room.
    """
    if not co2_ok:
        co2_ppm = None
    if temp_c is None and co2_ppm is None:
        return "started"

    delta = (temp_c - ambient_c) if (temp_c is not None and ambient_c is not None) else None

    if delta is not None and delta >= 20:
        return "hot"
    if (delta is not None and delta >= 8) or (co2_ppm is not None and co2_ppm >= 2500):
        return "active"
    if (delta is not None and delta >= 4) or (co2_ppm is not None and co2_ppm >= 1200):
        return "cooling"
    if (delta is not None and delta >= 1.5) or (co2_ppm is not None and co2_ppm >= 700):
        return "curing"

    # Cool and quiet. Still curing if sopping wet, or if CO2 is climbing.
    if pct is not None and pct > MOISTURE_HI:
        return "curing"
    if slope_pct_per_day is not None and slope_pct_per_day > 2:
        return "curing"
    return "ready"


def stage_at_least(value: str, threshold: str) -> bool:
    """Stage comparison by position, as the app's enum .index does."""
    try:
        return STAGE_ORDER.index(value) >= STAGE_ORDER.index(threshold)
    except ValueError:
        return False


# --- item classification ---------------------------------------------------

# Always avoid, enforced by rules so no model answer can override it.
AVOID_ITEMS = {
    "meat": "attracts pests and goes rancid in a small sealed bin",
    "chicken": "meat attracts pests and goes rancid",
    "beef": "meat attracts pests and goes rancid",
    "pork": "meat attracts pests and goes rancid",
    "bacon": "salty, greasy meat -- pests and odour",
    "fish": "attracts pests and smells strongly",
    "dairy": "turns sour and slows the pile down",
    "cheese": "turns sour and attracts pests",
    "milk": "waterlogs the pile and smells",
    "butter": "fat coats the material and blocks airflow",
    "yogurt": "dairy turns sour in a sealed bin",
    "oil": "coats the material and blocks airflow",
    "oily": "fat coats the material and blocks airflow",
    "grease": "coats the material and blocks airflow",
    "bone": "will not break down in a home bin",
    "pet waste": "can carry pathogens",
    "cat litter": "can carry pathogens",
}

GREENS = {
    "vegetable peels", "veg peels", "fruit scraps", "coffee grounds",
    "tea leaves", "tea bag", "grass clippings", "lettuce", "banana peel",
    "apple core", "orange peel", "cucumber", "tomato", "potato peel",
    "carrot", "onion skin", "melon rind", "berries",
}

BROWNS = {
    "shredded cardboard", "cardboard", "shredded paper", "paper",
    "dry leaves", "leaves", "sawdust", "egg carton", "paper towel",
    "straw", "wood chips", "newspaper", "egg shells", "eggshells",
}

# Greens that are mostly water, which matter when the bin is already wet
# (FoodItem.wet on the frontend).
WET_GREENS = {
    "fruit scraps", "banana peel", "melon rind", "cucumber", "tomato",
    "coffee grounds", "berries", "orange peel", "apple core",
}


def categorise(item: str) -> str:
    low = item.strip().lower()
    for bad in AVOID_ITEMS:
        if bad in low:
            return "avoid"
    if any(g in low or low in g for g in GREENS):
        return "green"
    if any(b in low or low in b for b in BROWNS):
        return "brown"
    return "unknown"


def is_wet_item(item: str) -> bool:
    low = item.strip().lower()
    return any(w in low or low in w for w in WET_GREENS)


def avoid_reason(item: str) -> str | None:
    low = item.strip().lower()
    for bad, reason in AVOID_ITEMS.items():
        if bad in low:
            return reason
    return None


# --- XP, levels, currency (xp_rules.dart) ----------------------------------
#
# "Care earns XP; volume never does." A plain log is worth ZERO.

XP = {
    "log": 0,
    "followed_suggestion": 15,
    "avoided_bad_add": 5,
    "check_in": 5,
    "healthy_layer_day": 10,
    "weekly_balance": 30,
    "harvest": 100,
    "daily_quest": 15,
}

# Actions are capped per day so XP cannot be farmed by logging. Health-based
# XP (healthy_layer_day) is deliberately outside the cap: it cannot be farmed
# because it depends on the sensors, not on tapping.
DAILY_ACTION_CAP = 60
CAPPED_KINDS = ("followed_suggestion", "avoided_bad_add", "check_in", "daily_quest")

# Soft currency. The app calls it loam.
LOAM = {
    "daily_quest": 5,
    "weekly_balance": 15,
    "harvest": 50,
    "streak_milestone": 20,
    "check_in": 0,
}

STREAK_MILESTONES = (3, 7, 14, 30, 50, 100, 365)

LEAGUE_TIERS = ("Seedling", "Sprout", "Fern", "Sapling", "Oak", "Sequoia")
LEAGUE_SIZE = 30
LEAGUE_PROMOTE = 7
LEAGUE_DEMOTE = 5


def league_zone(rank: int, cohort_size: int, tier_index: int) -> str:
    """Mirrors zoneForRank(): no promotion from the top tier, no demotion
    from the bottom one."""
    if rank <= LEAGUE_PROMOTE and tier_index < len(LEAGUE_TIERS) - 1:
        return "promote"
    if rank > cohort_size - LEAGUE_DEMOTE and tier_index > 0:
        return "demote"
    return "safe"


def xp_for_level(n: int) -> int:
    """Level n needs 60*(n-1)*n/2 lifetime XP."""
    return 60 * (n - 1) * n // 2


def level_for_xp(xp: int) -> int:
    n = 1
    while n < 50 and xp_for_level(n + 1) <= xp:
        n += 1
    return n


_TITLES = (
    (1, "Scrap Saver"),
    (4, "Peel Keeper"),
    (7, "Soil Whisperer"),
    (12, "Worm Wrangler"),
    (18, "Humus Hero"),
    (26, "Loam Legend"),
    (36, "Compost Sage"),
)


def title_for_level(level: int) -> str:
    title = _TITLES[0][1]
    for threshold, name in _TITLES:
        if level >= threshold:
            title = name
    return title


def cap_xp(base: int, earned_today: int) -> int:
    """Apply the daily action cap, as xpForAction() does."""
    return min(base, max(0, DAILY_ACTION_CAP - earned_today))


# --- impact (xp_rules.dart Impact) -----------------------------------------

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


# --- achievements ----------------------------------------------------------

def achievements(stats: dict) -> list[dict]:
    out: list[dict] = []

    def add(key: str, name: str, earned: bool, detail: str) -> None:
        out.append({"key": key, "name": name, "earned": earned, "detail": detail})

    add("first_harvest", "First Harvest", stats.get("harvests", 0) >= 1,
        "Harvest a finished batch")
    add("perfect_week", "Perfect Week", stats.get("perfect_weeks", 0) >= 1,
        "Keep the bin healthy every day for a week")
    add("moisture_master", "Moisture Master", stats.get("healthy_days", 0) >= 14,
        "14 days with moisture in the healthy band")

    for tier in (1, 5, 10, 25):
        add(f"diverted_{tier}kg", f"{tier} kg Diverted",
            stats.get("kg_diverted", 0) >= tier,
            f"Keep {tier} kg of food waste out of landfill")

    for days in STREAK_MILESTONES:
        add(f"streak_{days}", f"{days}-Day Streak",
            stats.get("best_streak", 0) >= days,
            f"Care for the bin {days} days running")

    return out


# --- daily quests ----------------------------------------------------------
#
# Always care-based, never "add N scraps".

QUEST_CATALOG = (
    {
        "key": "follow_suggestion",
        "title": "Follow one of Wren's suggestions",
        "detail": "Add something Wren recommended, or skip something it flagged",
        "goal": 1,
    },
    {
        "key": "check_in",
        "title": "Check on your bin",
        "detail": "Open the bin's live view and see how the layers are doing",
        "goal": 1,
    },
    {
        "key": "keep_in_band",
        "title": "Keep moisture in the healthy band",
        "detail": "Finish the day with moisture between 40% and 60%",
        "goal": 1,
    },
    {
        "key": "balance_browns",
        "title": "Balance with browns",
        "detail": "Add a dry brown so the greens have carbon to work with",
        "goal": 1,
    },
    {
        "key": "avoid_bad_add",
        "title": "Trust an avoid verdict",
        "detail": "Check an item and skip it when Wren says avoid",
        "goal": 1,
    },
)


def quests_for_day(user_id: str, day_iso: str) -> list[dict]:
    """Three quests, stable for a given user and day.

    Deterministic rather than stored, so the same three appear on every
    request with no nightly job. Uses a fixed hash so it survives a restart
    (Python's hash() is salted per process).
    """
    import hashlib

    digest = hashlib.sha256(f"{user_id}:{day_iso}".encode()).digest()
    pool = list(QUEST_CATALOG)
    picks = []
    for i in range(3):
        picks.append(pool.pop(digest[i] % len(pool)))
    return picks
