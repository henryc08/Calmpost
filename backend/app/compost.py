"""Plain composting rules, used for the dials in the app and as the fallback
advice when Gemini is unavailable. Keeping these here means the demo still
works offline and Gemini has a sane baseline to improve on.

Ranges are the usual home-composting targets: 40-60% moisture, and a top
layer that runs warm while it is actively breaking down.
"""

from typing import Literal

MoistureState = Literal["dry", "ok", "wet", "unknown"]

MOISTURE_DRY_BELOW = 40.0
MOISTURE_WET_ABOVE = 60.0

# CO2 in the sealed air gap tracks microbial activity and falls as a batch
# finishes. These are rough thresholds, not lab numbers.
CO2_ACTIVE_ABOVE = 2000.0
CO2_CURING_ABOVE = 800.0


def moisture_state(moisture_pct: float | None) -> MoistureState:
    if moisture_pct is None:
        return "unknown"
    if moisture_pct < MOISTURE_DRY_BELOW:
        return "dry"
    if moisture_pct > MOISTURE_WET_ABOVE:
        return "wet"
    return "ok"


def stage(
    temperature_c: float | None, co2_ppm: float | None, moisture_pct: float | None
) -> str:
    """Life-cycle stage for a layer: active, curing or ready.

    A guide from sensor trends, not a lab test -- the layer is 'ready' only
    when it has gone cool and quiet and is not sopping wet.
    """
    if temperature_c is None and co2_ppm is None:
        return "unknown"

    warm = temperature_c is not None and temperature_c >= 35
    very_active = co2_ppm is not None and co2_ppm >= CO2_ACTIVE_ABOVE
    if warm or very_active:
        return "active"

    mild = temperature_c is not None and temperature_c >= 25
    still_active = co2_ppm is not None and co2_ppm >= CO2_CURING_ABOVE
    if mild or still_active:
        return "curing"

    if moisture_pct is not None and moisture_pct > MOISTURE_WET_ABOVE:
        return "curing"
    return "ready"


def balance(
    top_moisture: float | None, recent_greens: int, recent_browns: int
) -> str:
    """Greens vs browns, from moisture plus what was recently added."""
    state = moisture_state(top_moisture)
    if state == "wet":
        return "needs_browns"
    if state == "dry":
        return "needs_greens"
    if recent_greens > recent_browns * 2:
        return "needs_browns"
    if recent_browns > recent_greens * 2:
        return "needs_greens"
    if state == "unknown":
        return "unknown"
    return "balanced"


# Items we always flag. The bin is a small sealed step-on bin, so these go
# rancid or attract pests rather than composting.
AVOID_ITEMS = {
    "meat": "attracts pests and goes rancid in a small sealed bin",
    "fish": "attracts pests and smells strongly",
    "dairy": "turns sour and slows the pile down",
    "cheese": "turns sour and attracts pests",
    "milk": "waterlogs the pile and smells",
    "oil": "coats the material and blocks airflow",
    "grease": "coats the material and blocks airflow",
    "bones": "will not break down in a home bin",
    "pet waste": "can carry pathogens",
}

GREENS = {
    "vegetable peels", "fruit scraps", "coffee grounds", "tea leaves",
    "grass clippings", "lettuce", "banana peel", "apple core",
}
BROWNS = {
    "shredded cardboard", "shredded paper", "dry leaves", "sawdust",
    "egg carton", "paper towel", "straw",
}


def categorise(item: str) -> str:
    """Best-effort category for a logged item, before Gemini weighs in."""
    low = item.strip().lower()
    for bad, _reason in AVOID_ITEMS.items():
        if bad in low:
            return "avoid"
    if any(g in low or low in g for g in GREENS):
        return "green"
    if any(b in low or low in b for b in BROWNS):
        return "brown"
    return "unknown"
