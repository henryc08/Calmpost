"""Gemini advice, in the response shape CLAUDE.md fixes.

Three guarantees, in order of precedence:
  1. Meat, dairy and oil are ALWAYS avoid, decided by rules. A model answer
     can never override that.
  2. If Gemini fails or there is no key, the rules answer instead. The demo
     must never depend on the network.
  3. Every answer records the sensor snapshot it was based on, so "same
     scrap, different answer" is provable rather than asserted.

Called over REST so httpx is the only dependency, with responseSchema so the
app never parses prose.
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

Rules:
- Healthy moisture is 40-60%. Too wet needs dry browns; too dry needs greens or water.
- Each layer carries a moisture_state of "dry", "ok" or "wet". Describe the bin \
to match it. NEVER call a layer healthy when its state is "dry" or "wet" -- if it \
says dry, say the bin is dry; if wet, say it is wet.
- NEVER tell them to add meat, fish, dairy, oily or greasy food, bones or pet waste.
- verdict is "add" when it is fine, "add_with_browns" when it is fine but the \
bin is too wet and needs dry material alongside it, "avoid" when it should not go in.
- Recommend specific household items, never general composting theory.
- A layer is only "ready" when it has gone cool and quiet.
- If a reading is missing or flagged unreliable, say so instead of guessing.
- If moisture_calibrated is false, treat the percentage as approximate.
- Warm, encouraging, plain language. Keep reason under 20 words, tip under 15.
- Readings are a guide, not a lab test. Never overclaim.
"""

RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "verdict": {"type": "string", "enum": ["add", "add_with_browns", "avoid"]},
        "reason": {"type": "string"},
        "suggest_add": {"type": "array", "items": {"type": "string"}},
        "suggest_avoid": {"type": "array", "items": {"type": "string"}},
        "balance": {
            "type": "string",
            "enum": ["needs_greens", "needs_browns", "balanced", "unknown"],
        },
        "stage_top": {
            "type": "string",
            "enum": ["started", "active", "hot", "curing", "ready", "harvested"],
        },
        "stage_bottom": {
            "type": "string",
            "enum": ["started", "active", "hot", "curing", "ready", "harvested"],
        },
        "bottom_ready": {"type": "boolean"},
        "tip": {"type": "string"},
    },
    "required": [
        "verdict", "reason", "suggest_add", "suggest_avoid",
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
            answer["reason"] = f"{item.strip().capitalize()}: {reason}."
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
                        + json.dumps(snapshot, indent=2, default=str)
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

    # Rule 1 again, defensively: strip anything on the never-add list out of
    # the model's own suggestions.
    answer["suggest_add"] = [
        s for s in answer.get("suggest_add", []) if compost.avoid_reason(s) is None
    ]
    return answer, settings.gemini_model


def fallback(snapshot: dict, item: str | None) -> dict:
    """Deterministic advice from the rules in compost.py."""
    top = snapshot.get("layers", {}).get("top", {})
    bottom = snapshot.get("layers", {}).get("bottom", {})
    air = snapshot.get("air", {})

    pct = top.get("moisture_pct")
    greens = snapshot.get("greens_7d", 0)
    browns = snapshot.get("browns_7d", 0)
    balance = compost.balance_verdict(pct, greens, browns)
    state = compost.moisture_state(pct)

    if balance == "needs_browns":
        suggest_add = ["shredded cardboard", "shredded paper", "dry leaves"]
        tip = "Tear the cardboard small so it mixes in."
    elif balance == "needs_greens":
        suggest_add = ["vegetable peels", "coffee grounds", "fruit scraps"]
        tip = "A splash of water helps if it still feels dry."
    else:
        suggest_add = ["vegetable peels", "shredded cardboard"]
        tip = "Keep layering greens with a bit of brown."

    suggest_avoid = ["meat", "fish", "dairy", "oily or greasy food", "bones"]

    # Verdict for the specific item, if one was asked about.
    verdict = "add"
    reason = "Looks fine for the bin right now."
    if item:
        avoid = compost.avoid_reason(item)
        category = compost.categorise(item)
        if avoid:
            verdict = "avoid"
            reason = f"{item.strip().capitalize()}: {avoid}."
        elif category == "green" and state == "wet":
            verdict = "add_with_browns"
            reason = "The top layer is already wet, so add a dry brown with it."
        elif category == "brown" and state == "dry":
            verdict = "add"
            reason = "Fine to add, though the bin could use greens or water too."
        elif category == "green" and state == "dry":
            verdict = "add"
            reason = "Good choice -- the bin is dry and this adds moisture."
        elif category == "unknown":
            reason = "Not sure about this one, so add a little and watch the moisture."
    else:
        reason = {
            "needs_browns": "The top layer is wet -- add some dry browns.",
            "needs_greens": "The top layer is dry -- add greens or a splash of water.",
            "balanced": "The bin looks balanced -- keep layering.",
            "unknown": "Not enough readings yet to judge the balance.",
        }[balance]

    stage_top = compost.stage(
        top.get("temp_c"),
        air.get("co2_ppm"),
        pct,
        air.get("co2_slope_per_hour"),
        air.get("co2_ok", True),
    )
    # With a single probe the bottom layer is unmeasured; say "started"
    # rather than inventing a stage for it.
    if bottom.get("measured"):
        stage_bottom = compost.stage(
            bottom.get("temp_c"),
            air.get("co2_ppm"),
            bottom.get("moisture_pct"),
            air.get("co2_slope_per_hour"),
            air.get("co2_ok", True),
        )
    else:
        stage_bottom = "started"

    return {
        "verdict": verdict,
        "reason": reason,
        "suggest_add": suggest_add,
        "suggest_avoid": suggest_avoid,
        "balance": balance,
        "stage_top": stage_top,
        "stage_bottom": stage_bottom,
        "bottom_ready": stage_bottom == "ready",
        "tip": tip,
    }
