"""Gemini advice, in the shape the Flutter app's Advice model expects.

Verdict values are the app's: great / careful / avoid. The rules fallback
mirrors adviseFor() in app/lib/domain/advice_rules.dart, so an offline answer
reads the same as an online one.

Three guarantees, in order of precedence:
  1. Meat, dairy and oil are ALWAYS avoid, decided by rules. No model answer
     can override that.
  2. If Gemini fails or there is no key, the rules answer. The demo must
     never depend on the network.
  3. Every answer records the sensor snapshot it was based on, so "same
     scrap, different answer" is provable rather than asserted.
"""

import json
import logging

import httpx

from . import compost
from .config import get_settings

log = logging.getLogger(__name__)

ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

SYSTEM_PROMPT = """You are Wren, a friendly worm who looks after someone's \
small home compost bin (about 19 L, sealed step-on lid with vent holes, two \
layers: fresh scraps on top, older compost at the bottom).

You are given live sensor readings and a log of what was recently added, and \
you answer whether a specific item should go in right now.

verdict must be exactly one of:
- "great"   : good to add now
- "careful" : fine to add, but it needs something alongside it (usually dry \
browns when the bin is wet, or greens/water when it is dry)
- "avoid"   : should not go in this bin at all

Rules:
- Healthy moisture is 40-60%. Above 64% is soggy; below 36% is too dry.
- Each layer carries a moisture_state of "dry", "ok" or "wet". Describe the \
bin to match it. NEVER call a layer healthy when its state is "dry" or "wet".
- NEVER tell them to add meat, fish, dairy, oily or greasy food, bones or pet waste.
- A layer whose "measured" is false has NO sensor. Say it is unknown; never \
state a number or a stage for it.
- Temperature matters as a RISE ABOVE the ambient air temperature, not as an \
absolute number: 25C in a 24C room is a cold pile.
- If moisture_calibrated is false, treat the percentage as approximate.
- Recommend specific household items, never general composting theory.
- headline is 2-4 words, like "Great add!" or "Add browns first".
- Warm, encouraging, plain language. reason under 30 words, tip under 15.
- Readings are a guide, not a lab test. Never overclaim.
"""

RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "verdict": {"type": "string", "enum": ["great", "careful", "avoid"]},
        "headline": {"type": "string"},
        "reason": {"type": "string"},
        "pair_with": {"type": "array", "items": {"type": "string"}},
        "suggest_add": {"type": "array", "items": {"type": "string"}},
        "suggest_avoid": {"type": "array", "items": {"type": "string"}},
        "balance": {
            "type": "string",
            "enum": ["needs_greens", "needs_browns", "balanced"],
        },
        "stage_top": {
            "type": "string",
            "enum": ["started", "active", "hot", "cooling", "curing", "ready", "harvested"],
        },
        "stage_bottom": {
            "type": "string",
            "enum": ["started", "active", "hot", "cooling", "curing", "ready", "harvested"],
        },
        "bottom_ready": {"type": "boolean"},
        "tip": {"type": "string"},
    },
    "required": [
        "verdict", "headline", "reason", "suggest_add", "suggest_avoid",
        "balance", "stage_top", "stage_bottom", "bottom_ready",
    ],
}


async def advise(snapshot: dict, item: str | None) -> tuple[dict, str]:
    """Return (advice dict, model name).

    `item` is the thing being checked, or None for whole-bin advice.
    """
    settings = get_settings()

    # Rule 1: hard avoids never reach the model.
    if item:
        reason = compost.avoid_reason(item)
        if reason is not None:
            answer = fallback(snapshot, item)
            answer["verdict"] = "avoid"
            answer["headline"] = "Keep it out"
            answer["reason"] = (
                f"{item.strip().capitalize()}: {reason}. "
                "Bin it, or freeze it for your city's green bin."
            )
            return answer, "rules-always-avoid"

    if not settings.gemini_api_key:
        return fallback(snapshot, item), "rules-fallback"

    question = (
        f'Should they add "{item}" to the bin right now?'
        if item
        else "What should they add or avoid next?"
    )

    body = {
        "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": [
            {
                "role": "user",
                "parts": [
                    {
                        "text": "Bin state as JSON:\n"
                        + json.dumps(_for_model(snapshot), indent=2, default=str)
                        + f"\n\n{question}"
                    }
                ],
            }
        ],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": RESPONSE_SCHEMA,
            "temperature": 0.4,
        },
    }

    url = ENDPOINT.format(model=settings.gemini_model)
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.post(
                url, params={"key": settings.gemini_api_key}, json=body
            )
            resp.raise_for_status()
            data = resp.json()
        answer = json.loads(data["candidates"][0]["content"]["parts"][0]["text"])
    except Exception:
        # A judge should see advice, not a stack trace.
        log.exception("gemini call failed; using rules fallback")
        return fallback(snapshot, item), "rules-fallback"

    # Rule 1 again, defensively: strip never-add items out of the model's own
    # suggestions, in case it ignored the instruction.
    for key in ("suggest_add", "pair_with"):
        if key in answer:
            answer[key] = [
                s for s in answer[key] if compost.avoid_reason(s) is None
            ]
    # The bottom layer has no probe in this build; do not let the model
    # declare it ready.
    if not snapshot["layers"]["bottom"]["measured"]:
        answer["stage_bottom"] = "started"
        answer["bottom_ready"] = False
    return answer, settings.gemini_model


def _for_model(snapshot: dict) -> dict:
    """Trim the snapshot to what actually informs an answer."""
    return {
        "layers": snapshot["layers"],
        "stages": snapshot["stages"],
        "air": snapshot["air"],
        "greens_7d_cups": snapshot["greens_7d"],
        "browns_7d_cups": snapshot["browns_7d"],
        "healthy_band_pct": snapshot["healthy_band"],
        "moisture_calibrated": snapshot["moisture_calibrated"],
        "healthy_hours_today": snapshot["healthy_hours_today"],
    }


def fallback(snapshot: dict, item: str | None) -> dict:
    """Rules advice, mirroring adviseFor() / suggestFor() in advice_rules.dart."""
    top = snapshot["layers"]["top"]
    air = snapshot["air"]
    stages = snapshot["stages"]

    pct = top["moisture_pct"]
    greens = snapshot["greens_7d"]
    browns = snapshot["browns_7d"]
    balance = compost.balance_of(pct, greens, browns)

    # The app's thresholds, which are wider than the healthy band.
    wet = pct is not None and pct > 64
    dry = pct is not None and pct < 36

    if balance == "needs_browns":
        suggest_add = ["shredded cardboard", "shredded paper", "dry leaves"]
        line = "The bin is green-heavy -- add some dry browns."
        tip = "Tear the cardboard small so it mixes in."
    elif balance == "needs_greens":
        suggest_add = ["vegetable peels", "coffee grounds", "fruit scraps"]
        line = "The bin needs greens, or a splash of water."
        tip = "Bury greens under a little brown to keep flies off."
    else:
        suggest_add = ["vegetable peels", "shredded cardboard"]
        line = "The bin looks balanced -- keep layering."
        tip = "Alternate a scoop of greens with a handful of browns."

    suggest_avoid = ["meat", "cheese", "oily food"]

    verdict = "great"
    headline = "Good add"
    reason = line
    pair_with: list[str] = []

    if item:
        avoid = compost.avoid_reason(item)
        category = compost.categorise(item)
        name = item.strip()

        if avoid:
            verdict, headline = "avoid", "Keep it out"
            reason = f"{name.capitalize()}: {avoid}. Bin it, or use your city's green bin."
        elif category == "green":
            if wet:
                verdict, headline = "careful", "Add browns first"
                extra = (
                    "This adds even more water."
                    if compost.is_wet_item(item)
                    else "More greens will make it sour."
                )
                reason = (
                    f"Your top layer is {round(pct)}% wet, which is soggy. {extra} "
                    "Mix in a handful of shredded cardboard with it."
                )
                pair_with = ["shredded cardboard", "newspaper"]
            elif balance == "needs_browns":
                verdict, headline = "careful", "Go easy on greens"
                reason = (
                    "You've added a lot of greens this week. Pair this with some "
                    "browns so the bin stays balanced."
                )
                pair_with = ["dry leaves", "shredded cardboard"]
            elif dry and compost.is_wet_item(item):
                verdict, headline = "great", "Perfect timing!"
                reason = (
                    f"Your top layer is only {round(pct)}% moist. {name} adds the "
                    "water and nitrogen it's missing."
                )
            else:
                verdict, headline = "great", "Great add!"
                reason = "Moisture is about right, so toss it in."
        elif category == "brown":
            if dry:
                verdict, headline = "careful", "Add with greens"
                reason = (
                    f"Your top layer is {round(pct)}% moist, already dry. More browns "
                    "will stall it. Add some wet greens or a splash of water too."
                )
                pair_with = ["vegetable peels", "coffee grounds"]
            elif wet or balance == "needs_browns":
                verdict, headline = "great", "Exactly what it needs!"
                reason = (
                    f"Your top layer is {round(pct)}% wet. {name} will soak up the "
                    "extra water and let it breathe."
                    if wet
                    else f"The bin is green-heavy this week. {name} balances it right out."
                )
            else:
                verdict, headline = "great", "Good add"
                reason = "Keeps your greens and browns in balance."
        else:
            verdict, headline = "careful", "Not sure on this one"
            reason = (
                "This is not in the catalogue, so add a little and watch the "
                "moisture rather than filling the bin with it."
            )

    # suggestFor(): a finished bottom layer is the headline news.
    if item is None and stages["bottom"] == "ready":
        line = "The bottom layer has finished curing and is ready to harvest."
        reason = line

    return {
        "verdict": verdict,
        "headline": headline,
        "reason": reason,
        "pair_with": pair_with,
        "suggest_add": suggest_add,
        "suggest_avoid": suggest_avoid,
        "balance": balance,
        "stage_top": stages["top"],
        "stage_bottom": stages["bottom"],
        "bottom_ready": stages["bottom"] == "ready",
        "tip": tip,
    }
