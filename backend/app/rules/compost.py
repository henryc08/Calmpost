"""Composting rules: moisture, health components, balance, stage, items.

Mirrors app/lib/domain/health_score.dart and advice_rules.dart. The app owns
these numbers -- change both together. Divergences worth knowing:
  - temperature is scored as the rise ABOVE AMBIENT, not absolute degrees
  - the CO2 trend is % per day, not ppm per hour
  - greens/browns are compared in rough cups of volume, not item counts
"""

import re
from typing import Literal

from ..catalog import food

MoistureState = Literal["dry", "ok", "wet", "unknown"]
# Mirrors Stage in models.dart -- note 'cooling' between hot and curing.
Stage = Literal["started", "active", "hot", "cooling", "curing", "ready", "harvested"]
STAGE_ORDER = ("started", "active", "hot", "cooling", "curing", "ready", "harvested")
Verdict = Literal["great", "careful", "avoid"]
Balance = Literal["needs_greens", "needs_browns", "balanced"]

# --- bands (health_score.dart) ---------------------------------------------

MOISTURE_LO = 40.0
MOISTURE_HI = 60.0
MOISTURE_FALLOFF = 25.0

# Health score weights (HealthBreakdown). The app computes the total; the
# backend returns the components so there is one formula, not two.
WEIGHTS = {"moisture": 0.45, "temperature": 0.20, "co2": 0.15, "balance": 0.20}

# One "cup" of scraps, for converting logged grams into the volume units the
# app's balance ratio uses.
CUP_GRAMS = 200.0


def band_score(v: float, lo: float, hi: float, falloff: float) -> float:
    """100 inside [lo, hi], falling linearly to 0 at `falloff` outside it.
    Identical to bandScore() in health_score.dart."""
    if lo <= v <= hi:
        return 100.0
    d = (lo - v) if v < lo else (v - hi)
    return max(0.0, 100.0 - d / falloff * 100.0)


# --- calibration -----------------------------------------------------------

def moisture_pct(raw: int | None, raw_dry: int, raw_wet: int) -> float | None:
    """Raw ADC count -> percentage.

    Capacitive probes read LOWER as they get wetter, so raw_dry is the high
    count (probe in air). None for a missing reading rather than a fake 0.
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


# --- health components (computeHealth in health_score.dart) ----------------
#
# computeHealth() averages the two layers. With one probe only one layer is
# measured, so each component uses the layers it has.

def moisture_component(top: float | None, bottom: float | None) -> float | None:
    scores = [band_score(v, MOISTURE_LO, MOISTURE_HI, MOISTURE_FALLOFF) for v in (top, bottom) if v is not None]
    return sum(scores) / len(scores) if scores else None


def temperature_component(top_temp: float | None, bottom_temp: float | None, ambient: float | None, bottom_curing: bool) -> float | None:
    """Scored on how far above ambient the pile runs: 25C is cold in a 24C
    room and busy in a 5C garage."""
    if ambient is None:
        return None
    scores = []
    if top_temp is not None:
        scores.append(band_score(top_temp - ambient, 5, 25, 10))
    if bottom_temp is not None:
        # A curing bottom layer is supposed to sit close to ambient.
        scores.append(band_score(bottom_temp - ambient, -2, 8, 10) if bottom_curing else band_score(bottom_temp - ambient, 3, 25, 10))
    return sum(scores) / len(scores) if scores else None


def co2_component(co2_ppm: float | None, top_stage: str, bottom_curing: bool, slope_pct_per_day: float | None) -> float | None:
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


def need_for(snap: dict) -> str:
    top, air = snap["layers"]["top"], snap["air"]
    pct = top["moisture_pct"]
    if snap.get("stale") or not top["measured"] or pct is None:
        return "nothing"
    if snap["stages"]["bottom"] in ("curing", "ready") and snap["layers"]["bottom"]["measured"]:
        return "nothing"
    greens, browns = snap["greens_7d"], snap["browns_7d"]
    ratio = browns / greens if greens > 0 else (4.0 if browns > 0 else 2.5)
    delta = top["temp_c"] - air["ambient_temp_c"] if top["temp_c"] is not None and air["ambient_temp_c"] is not None else None
    if pct > 60 or ratio < 2 or (air.get("co2_ok") and (air["co2_ppm"] or 0) > 6000 and delta is not None and delta < 5):
        return "browns"
    if pct < 40:
        return "greens" if ratio > 3 else "water"
    if air.get("co2_ok") and (air.get("co2_slope_per_day") or 0) > 2 and delta is not None and delta < 5:
        return "mix"
    return "nothing"


# --- stage -----------------------------------------------------------------

def stage(
    temp_c: float | None,
    ambient_c: float | None,
    co2_ppm: float | None,
    pct: float | None,
    slope_pct_per_day: float | None = None,
    co2_ok: bool = True,
    has_mature_history: bool = False,
) -> Stage:
    """Life-cycle stage from sensor trends. A guide, not a lab test."""
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
    # A quiet/dry new bin is not evidence of finished compost.
    if pct is None or pct < MOISTURE_LO or delta is None:
        return "started"
    return "ready" if has_mature_history else "curing"


def stage_at_least(value: str, threshold: str) -> bool:
    """Stage comparison by position, as the app's enum .index does."""
    try:
        return STAGE_ORDER.index(value) >= STAGE_ORDER.index(threshold)
    except ValueError:
        return False


# --- items -----------------------------------------------------------------
#
# The app's food catalog (app/catalog/food.py, generated) is checked first,
# then keywords, so free text the camera or a user types still classifies.

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
    "bread": "goes mouldy and draws pests in a small bin",
    "pet waste": "can carry pathogens",
    "cat litter": "can carry pathogens",
    "glossy": "plastic-coated paper does not break down",
}

GREENS = {
    "vegetable peels", "veg peels", "fruit scraps", "coffee grounds", "tea leaves", "tea bag",
    "grass clippings", "lettuce", "banana peel", "apple core", "orange peel", "cucumber",
    "tomato", "potato peel", "carrot", "onion skin", "melon rind", "berries",
}

BROWNS = {
    "shredded cardboard", "cardboard", "shredded paper", "paper", "dry leaves", "leaves",
    "sawdust", "egg carton", "paper towel", "straw", "wood chips", "newspaper",
}

# Greens that are mostly water (FoodItem.wet in the app).
WET_GREENS = {
    "fruit scraps", "banana peel", "melon rind", "cucumber", "tomato", "coffee grounds",
    "berries", "orange peel", "apple core", "lettuce", "grass clippings",
}


def avoid_reason(item: str) -> str | None:
    """Why an item must stay out, or None. Keyword rules win over everything."""
    low = item.strip().lower()
    for bad, reason in AVOID_ITEMS.items():
        # Word-start match, so "oil" catches "olive oil" but not "soil" or "boiled".
        if re.search(r"\b" + re.escape(bad), low):
            return reason
    hit = food.lookup(item)
    if hit is not None and hit["category"] == "avoid":
        return hit["note"].rstrip(".").lower() or "does not belong in a home bin"
    return None


def categorise(item: str) -> str:
    """green | brown | avoid | unknown."""
    if avoid_reason(item):
        return "avoid"
    hit = food.lookup(item)
    if hit is not None:
        return hit["category"]
    low = item.strip().lower()
    if any(g in low or low in g for g in GREENS):
        return "green"
    if any(b in low or low in b for b in BROWNS):
        return "brown"
    return "unknown"


def is_wet_item(item: str) -> bool:
    hit = food.lookup(item)
    if hit is not None:
        return hit["wet"]
    low = item.strip().lower()
    return any(w in low or low in w for w in WET_GREENS)
