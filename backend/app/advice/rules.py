"""Rule-based advice. Two jobs:

1. Hard rules that always win (meat, dairy, oil → avoid), even over Gemini.
2. A complete fallback answer when Gemini is down, slow or returns junk.

Healthy moisture band is 40-60% (matches domain/health_score.dart).
Healthy greens:browns is 1:2-1:3.
"""

import re

from .models import Advice, Balance, BinSnapshot, LayerReading, Stage, Verdict

MOISTURE_LOW = 40.0
MOISTURE_HIGH = 60.0

_ALWAYS_AVOID = {
    "meat": "meat", "beef": "meat", "pork": "meat", "chicken": "meat", "bacon": "meat",
    "ham": "meat", "sausage": "meat", "turkey": "meat", "fish": "fish", "salmon": "fish",
    "tuna": "fish", "shrimp": "fish", "bone": "bones", "bones": "bones",
    "dairy": "dairy", "milk": "dairy", "cheese": "dairy", "yogurt": "dairy", "yoghurt": "dairy",
    "butter": "dairy", "cream": "dairy",
    "oil": "oil", "oily": "oil", "grease": "oil", "greasy": "oil", "fried": "oil", "mayo": "oil",
    "mayonnaise": "oil", "lard": "oil",
}

_AVOID_REASONS = {
    "meat": "Meat rots instead of composting — it smells and attracts pests.",
    "fish": "Fish smells strong as it breaks down and brings in pests.",
    "bones": "Bones take years to break down and attract animals.",
    "dairy": "Dairy goes sour and smelly in a small bin and attracts pests.",
    "oil": "Oil coats everything and keeps air and water out, so the bin goes sour.",
}

_BROWNS = {
    "cardboard", "paper", "newspaper", "leaves", "leaf", "straw", "sawdust", "napkin",
    "tissue", "egg carton", "carton", "twigs", "wood", "shredded",
}

_GREENS = {
    "banana", "peel", "apple", "core", "vegetable", "veggie", "carrot", "lettuce", "onion",
    "potato", "tomato", "fruit", "coffee", "grounds", "tea", "grass", "orange", "citrus",
    "cucumber", "melon", "berries", "strawberry", "scraps", "eggshell", "eggshells",
}


def _words(scrap: str) -> set[str]:
    return set(re.findall(r"[a-z]+", scrap.lower()))


def hard_avoid(scrap: str) -> str | None:
    """Return the avoid category ('meat', 'dairy', 'oil', ...) or None."""
    for word in _words(scrap):
        if word in _ALWAYS_AVOID:
            return _ALWAYS_AVOID[word]
    return None


def avoid_reason(category: str) -> str:
    return _AVOID_REASONS[category]


def classify(scrap: str) -> str:
    """'brown', 'green', or 'unknown'. Browns checked first: 'shredded paper towel'."""
    text = scrap.lower()
    words = _words(scrap)
    if words & _BROWNS or any(b in text for b in _BROWNS if " " in b):
        return "brown"
    if words & _GREENS:
        return "green"
    return "unknown"


def balance_of(s: BinSnapshot) -> Balance:
    if s.greens_7d == 0 and s.browns_7d == 0:
        return Balance.balanced
    if s.greens_7d == 0:
        return Balance.needs_greens
    ratio = s.browns_7d / s.greens_7d
    if ratio < 2:
        return Balance.needs_browns
    if ratio > 3:
        return Balance.needs_greens
    return Balance.balanced


def layer_stage(layer: LayerReading, s: BinSnapshot) -> Stage:
    above_ambient = layer.temp_c - s.ambient_temp_c
    if above_ambient >= 20:
        return Stage.hot
    if above_ambient >= 6 or s.co2_trend_ppm_per_hr > 5:
        return Stage.active
    in_band = MOISTURE_LOW <= layer.moisture_pct <= MOISTURE_HIGH
    if above_ambient < 3 and s.co2_trend_ppm_per_hr <= 0 and in_band:
        return Stage.ready
    return Stage.curing


def _moisture_state(layer: LayerReading) -> str:
    if layer.moisture_pct > MOISTURE_HIGH:
        return "wet"
    if layer.moisture_pct < MOISTURE_LOW:
        return "dry"
    return "ok"


def rule_advice(scrap: str, s: BinSnapshot) -> Advice:
    balance = balance_of(s)
    stage_top = layer_stage(s.top, s)
    stage_bottom = layer_stage(s.bottom, s)
    bottom_ready = stage_bottom == Stage.ready
    top = _moisture_state(s.top)
    kind = classify(scrap)
    pct = round(s.top.moisture_pct)

    category = hard_avoid(scrap)
    if category:
        verdict, reason = Verdict.avoid, avoid_reason(category)
    elif kind == "green" and (top == "wet" or balance == Balance.needs_browns):
        verdict = Verdict.add_with_browns
        reason = (f"My top layer is soggy at {pct}% moisture. Add it, but mix in a "
                  "handful of shredded cardboard first." if top == "wet" else
                  "I've had lots of greens this week. Add it with a handful of browns.")
    elif kind == "brown" and top == "dry":
        verdict = Verdict.add
        reason = f"I'm dry at {pct}% moisture, so dampen it with a splash of water as you add it."
    elif kind == "brown":
        verdict = Verdict.add
        reason = ("Perfect, I'm a bit wet and browns soak that up." if top == "wet"
                  else "Browns keep me fluffy and balanced. Add it.")
    elif kind == "green":
        verdict = Verdict.add
        reason = (f"Yes please! I'm dry at {pct}% moisture and this adds some." if top == "dry"
                  else "Looks good. Chop it small so it breaks down faster.")
    else:
        verdict = Verdict.add if top != "wet" else Verdict.add_with_browns
        reason = "I'm not sure what that is. If it's plant-based and unprocessed, it's fine in small pieces."

    if top == "wet" or balance == Balance.needs_browns:
        suggest_add = ["shredded cardboard", "dry leaves", "torn paper"]
    elif top == "dry" or balance == Balance.needs_greens:
        suggest_add = ["vegetable peels", "coffee grounds", "fruit scraps"]
    else:
        suggest_add = ["vegetable peels", "shredded cardboard"]

    suggest_avoid = ["meat", "dairy", "oily food"]
    if top == "wet":
        suggest_avoid = ["watery fruit like melon", "meat", "dairy"]

    if bottom_ready:
        tip = "My bottom layer looks finished. Check it's dark, crumbly and earthy-smelling before you use it."
    elif top == "wet":
        tip = "Leave the lid open for an hour to let me dry out a little."
    elif top == "dry":
        tip = "A small splash of water on the top layer helps me get going."
    else:
        tip = "Chop scraps small — I break them down much faster."

    return Advice(
        verdict=verdict, reason=reason, suggest_add=suggest_add, suggest_avoid=suggest_avoid,
        balance=balance, stage_top=stage_top, stage_bottom=stage_bottom,
        bottom_ready=bottom_ready, tip=tip,
    )
