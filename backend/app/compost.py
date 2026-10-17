"""Composting and game rules, per CLAUDE.md.

Two jobs:
  1. Turn raw sensor counts into meaning (calibration, bands, stage).
  2. Hold the XP/level/achievement constants the ledger writes against.

The Bin Health Score itself deliberately lives in the Flutter app
(domain/health_score.dart) -- CLAUDE.md names that the source of truth, so
this module returns the *components* the formula needs rather than a second,
drifting implementation of the number.
"""

from typing import Literal

MoistureState = Literal["dry", "ok", "wet", "unknown"]
Stage = Literal["started", "active", "hot", "curing", "ready", "harvested"]

# Healthy moisture band. 100 inside the band, falling linearly to 0 at +-25
# points outside it -- the curve CLAUDE.md specifies.
MOISTURE_BAND = (40.0, 60.0)
MOISTURE_FALLOFF = 25.0

# Thermophilic composting runs hot; below ~25C a batch is cooling off.
TEMP_HOT_ABOVE = 45.0
TEMP_ACTIVE_ABOVE = 35.0
TEMP_CURING_ABOVE = 25.0

# CO2 in the sealed air gap tracks microbial activity and falls as a batch
# finishes. Rough thresholds, not lab numbers.
CO2_ACTIVE_ABOVE = 2000.0
CO2_CURING_ABOVE = 800.0

# A 7-day greens:browns ratio of roughly 1:2 to 1:3 is the target.
BALANCE_TARGET = (2.0, 3.0)


# --- calibration -----------------------------------------------------------

def moisture_pct(raw: int | None, raw_dry: int, raw_wet: int) -> float | None:
    """Convert a capacitive probe's raw ADC count to a percentage.

    Capacitive probes read LOWER as they get wetter, so raw_dry is the high
    count (probe in air) and raw_wet the low one (probe in water). Returns
    None for a missing reading rather than a misleading 0.
    """
    if raw is None:
        return None
    span = raw_dry - raw_wet
    if span == 0:
        return None
    pct = 100.0 * (raw_dry - raw) / span
    return max(0.0, min(100.0, pct))


def moisture_state(pct: float | None) -> MoistureState:
    if pct is None:
        return "unknown"
    low, high = MOISTURE_BAND
    if pct < low:
        return "dry"
    if pct > high:
        return "wet"
    return "ok"


def moisture_component(pct: float | None) -> float | None:
    """0-100 moisture term of the health score."""
    if pct is None:
        return None
    low, high = MOISTURE_BAND
    if low <= pct <= high:
        return 100.0
    distance = (low - pct) if pct < low else (pct - high)
    return max(0.0, 100.0 * (1.0 - distance / MOISTURE_FALLOFF))


def temperature_component(temp_c: float | None) -> float | None:
    """0-100 temperature term. Warm and working scores best; stone cold or
    overheating scores low."""
    if temp_c is None:
        return None
    if TEMP_ACTIVE_ABOVE <= temp_c <= TEMP_HOT_ABOVE + 10:
        return 100.0
    if temp_c < TEMP_ACTIVE_ABOVE:
        # Linear from 0 at 10C to 100 at 35C.
        return max(0.0, min(100.0, (temp_c - 10.0) / (TEMP_ACTIVE_ABOVE - 10.0) * 100.0))
    # Too hot: falls off above 55C.
    return max(0.0, 100.0 - (temp_c - (TEMP_HOT_ABOVE + 10)) * 10.0)


def balance_component(greens: int, browns: int) -> float | None:
    """0-100 balance term from the 7-day greens:browns counts."""
    if greens == 0 and browns == 0:
        return None
    if greens == 0:
        return 40.0  # all browns: the pile will stall, but it is not rotting
    ratio = browns / greens
    low, high = BALANCE_TARGET
    if low <= ratio <= high:
        return 100.0
    distance = (low - ratio) if ratio < low else (ratio - high)
    return max(0.0, 100.0 - distance * 40.0)


def balance_verdict(pct: float | None, greens: int, browns: int) -> str:
    """What the bin needs next: greens, browns, or nothing."""
    state = moisture_state(pct)
    if state == "wet":
        return "needs_browns"
    if state == "dry":
        return "needs_greens"
    if greens == 0 and browns == 0:
        return "unknown"
    ratio = browns / greens if greens else float("inf")
    low, high = BALANCE_TARGET
    if ratio < low:
        return "needs_browns"
    if ratio > high:
        return "needs_greens"
    return "balanced"


# --- stage -----------------------------------------------------------------

def stage(
    temp_c: float | None,
    co2_ppm: float | None,
    pct: float | None,
    co2_slope_per_hour: float | None = None,
    co2_ok: bool = True,
) -> Stage:
    """Batch Journey stage from sensor trends.

    A guide, not a lab test. co2_slope_per_hour comes from regr_slope over
    the recent window: a clearly falling curve is what separates a finishing
    batch from one that has merely gone quiet. When the CO2 sensor flags
    itself unhealthy we ignore its value entirely rather than trust it.
    """
    if not co2_ok:
        co2_ppm = None

    if temp_c is None and co2_ppm is None:
        return "started"

    if temp_c is not None and temp_c >= TEMP_HOT_ABOVE:
        return "hot"
    if (temp_c is not None and temp_c >= TEMP_ACTIVE_ABOVE) or (
        co2_ppm is not None and co2_ppm >= CO2_ACTIVE_ABOVE
    ):
        return "active"
    if (temp_c is not None and temp_c >= TEMP_CURING_ABOVE) or (
        co2_ppm is not None and co2_ppm >= CO2_CURING_ABOVE
    ):
        return "curing"

    # Cool and quiet. Still curing if it is sopping wet, or if CO2 has not
    # actually started falling yet.
    if pct is not None and pct > MOISTURE_BAND[1]:
        return "curing"
    if co2_slope_per_hour is not None and co2_slope_per_hour > 0:
        return "curing"
    return "ready"


# --- item classification ---------------------------------------------------

# Always avoid, enforced by rules so a model answer can never override it.
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


def categorise(item: str) -> str:
    """Best-effort category before the model weighs in."""
    low = item.strip().lower()
    for bad in AVOID_ITEMS:
        if bad in low:
            return "avoid"
    if any(g in low or low in g for g in GREENS):
        return "green"
    if any(b in low or low in b for b in BROWNS):
        return "brown"
    return "unknown"


def avoid_reason(item: str) -> str | None:
    low = item.strip().lower()
    for bad, reason in AVOID_ITEMS.items():
        if bad in low:
            return reason
    return None


# --- XP, levels, currency --------------------------------------------------
#
# CLAUDE.md: "Reward balance, never volume." Logging a scrap is worth ZERO.
# Every value below pays for care, not for putting more food in the bin.

XP = {
    "followed_suggestion": 15,
    "healthy_layer_day": 10,   # per layer, once per day
    "avoided_bad_add": 5,
    "daily_quest": 15,         # doc says 10-20
    "weekly_balance": 30,
    "harvest": 100,
    "log": 0,                  # explicit: a plain log earns nothing
}

SEEDS = {
    "daily_quest": 5,
    "weekly_balance": 15,
    "harvest": 50,
    "streak_milestone": 20,
}

STREAK_MILESTONES = (3, 7, 14, 30, 100)

LEAGUE_TIERS = ("seedling", "sprout", "fern", "sapling", "oak", "sequoia")
LEAGUE_SIZE = 30
LEAGUE_PROMOTE = 7
LEAGUE_DEMOTE = 5

# Lifetime XP -> level 1-50 with titles. Thresholds grow quadratically so
# early levels come quickly and later ones take real commitment.
LEVEL_TITLES = (
    (1, "Scrap Saver"),
    (5, "Peel Keeper"),
    (10, "Brown Balancer"),
    (15, "Heap Handler"),
    (20, "Moisture Reader"),
    (25, "Curing Captain"),
    (30, "Harvest Hand"),
    (35, "Loam Maker"),
    (40, "Soil Whisperer"),
    (45, "Humus Hero"),
)


def level_for_xp(total_xp: int) -> int:
    """Level 1-50. Needs ~12*n^2 lifetime XP to reach level n."""
    level = 1
    while level < 50 and total_xp >= 12 * (level + 1) ** 2:
        level += 1
    return level


def xp_for_level(level: int) -> int:
    return 0 if level <= 1 else 12 * level**2


def title_for_level(level: int) -> str:
    title = LEVEL_TITLES[0][1]
    for threshold, name in LEVEL_TITLES:
        if level >= threshold:
            title = name
    return title


# --- impact ----------------------------------------------------------------
#
# Deliberately conservative, public-figure estimates. CLAUDE.md: never
# overclaim -- these are presented as estimates in the UI.

# Landfilled food waste emits methane; composting it avoids roughly this
# much CO2-equivalent per kg diverted.
CO2E_KG_PER_KG_DIVERTED = 0.5
# Retail compost/fertiliser value per kg of finished compost.
DOLLARS_PER_KG_COMPOST = 0.50
# Roughly a third of input mass survives as finished compost.
COMPOST_YIELD = 0.33


def impact(total_grams: int) -> dict:
    kg = total_grams / 1000.0
    return {
        "kg_diverted": round(kg, 2),
        "co2e_kg_avoided": round(kg * CO2E_KG_PER_KG_DIVERTED, 2),
        "fertilizer_saved_usd": round(kg * COMPOST_YIELD * DOLLARS_PER_KG_COMPOST, 2),
        "is_estimate": True,
    }


# --- achievements ----------------------------------------------------------

def achievements(stats: dict) -> list[dict]:
    """Tiered badges computed from lifetime stats."""
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
        kg = stats.get("kg_diverted", 0)
        add(f"diverted_{tier}kg", f"{tier} kg Diverted", kg >= tier,
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
        "target": 1,
    },
    {
        "key": "check_in",
        "title": "Check on your bin",
        "detail": "Open the bin's live view and see how the layers are doing",
        "target": 1,
    },
    {
        "key": "keep_in_band",
        "title": "Keep moisture in the healthy band",
        "detail": "Finish the day with moisture between 40% and 60%",
        "target": 1,
    },
    {
        "key": "balance_browns",
        "title": "Balance with browns",
        "detail": "Add a dry brown so the greens have carbon to work with",
        "target": 1,
    },
    {
        "key": "avoid_bad_add",
        "title": "Trust an avoid verdict",
        "detail": "Check an item and skip it when Wren says avoid",
        "target": 1,
    },
)


def quests_for_day(user_id: str, day_iso: str) -> list[dict]:
    """Three quests, stable for a given user and day.

    Deterministic rather than stored, so the same three appear on every
    request without a nightly job writing rows.
    """
    seed = abs(hash((user_id, day_iso)))
    picks = []
    pool = list(QUEST_CATALOG)
    for i in range(3):
        idx = (seed >> (i * 5)) % len(pool)
        picks.append(pool.pop(idx))
    return picks
