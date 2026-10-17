"""Gemini call that turns bin state into plain-language advice.

Hit over REST rather than through an SDK so the only dependency is httpx, and
asked for structured JSON via responseSchema so the app never has to parse
prose. If the key is missing or the call fails we fall back to the rules in
compost.py -- the demo must not depend on the network.
"""

import json
import logging

import httpx

from . import compost
from .config import get_settings

log = logging.getLogger(__name__)

ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

SYSTEM_PROMPT = """You advise the owner of a small two-layer home compost bin \
(about 19 L, sealed step-on lid with vent holes). You are given live sensor \
readings and a log of what was recently added.

Rules:
- Recommend specific household items, not general composting theory.
- Healthy moisture is 40-60%. Too wet needs dry browns; too dry needs greens or water.
- Never recommend meat, fish, dairy, oily or greasy food, bones or pet waste in this bin.
- The bottom layer is only "ready" when it has gone cool and quiet.
- Say the readings are a guide, not a lab test, if you are unsure.
- Keep every reason under 15 words and write for a beginner.
"""

RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "headline": {"type": "string"},
        "balance": {
            "type": "string",
            "enum": ["needs_greens", "needs_browns", "balanced", "unknown"],
        },
        "stage_top": {
            "type": "string",
            "enum": ["active", "curing", "ready", "unknown"],
        },
        "stage_bottom": {
            "type": "string",
            "enum": ["active", "curing", "ready", "unknown"],
        },
        "bottom_ready": {"type": "boolean"},
        "suggestions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "item": {"type": "string"},
                    "action": {"type": "string", "enum": ["add", "avoid"]},
                    "reason": {"type": "string"},
                },
                "required": ["item", "action", "reason"],
            },
        },
        "warnings": {"type": "array", "items": {"type": "string"}},
    },
    "required": [
        "headline", "balance", "stage_top", "stage_bottom",
        "bottom_ready", "suggestions",
    ],
}


async def advise(state: dict) -> tuple[dict, str]:
    """Return (advice dict, model name). Falls back to local rules on failure."""
    settings = get_settings()
    if not settings.gemini_api_key:
        return fallback(state), "rules-fallback"

    body = {
        "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": [
            {
                "role": "user",
                "parts": [
                    {
                        "text": "Current bin state as JSON:\n"
                        + json.dumps(state, indent=2, default=str)
                        + "\n\nGive 2-4 suggestions for what to add or avoid next."
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
                url,
                params={"key": settings.gemini_api_key},
                json=body,
            )
            resp.raise_for_status()
            data = resp.json()
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        return json.loads(text), settings.gemini_model
    except Exception:
        # A judge watching the demo should see advice, not a stack trace.
        log.exception("gemini call failed; using rules fallback")
        return fallback(state), "rules-fallback"


def fallback(state: dict) -> dict:
    """Deterministic advice from compost.py, used offline and on error."""
    top = state.get("zones", {}).get("top", {})
    bottom = state.get("zones", {}).get("bottom", {})
    airgap = state.get("zones", {}).get("airgap", {})

    top_moisture = top.get("moisture_pct")
    bal = compost.balance(
        top_moisture,
        state.get("recent_greens", 0),
        state.get("recent_browns", 0),
    )

    suggestions = []
    if bal == "needs_browns":
        suggestions = [
            {
                "item": "shredded cardboard",
                "action": "add",
                "reason": "soaks up extra moisture and lets air back in",
            },
            {
                "item": "shredded paper",
                "action": "add",
                "reason": "dry carbon to balance wet food scraps",
            },
        ]
        headline = "Top layer is wet -- add some dry browns."
    elif bal == "needs_greens":
        suggestions = [
            {
                "item": "vegetable peels",
                "action": "add",
                "reason": "adds nitrogen and moisture to a dry pile",
            },
            {
                "item": "coffee grounds",
                "action": "add",
                "reason": "nitrogen-rich and holds water well",
            },
        ]
        headline = "Top layer is dry -- add greens or a splash of water."
    else:
        suggestions = [
            {
                "item": "vegetable peels",
                "action": "add",
                "reason": "keeps the pile fed without upsetting the balance",
            }
        ]
        headline = "Bin looks balanced -- keep layering greens and browns."

    suggestions.append(
        {
            "item": "meat, dairy and oily food",
            "action": "avoid",
            "reason": "goes rancid and attracts pests in a sealed bin",
        }
    )

    stage_bottom = compost.stage(
        bottom.get("temperature_c"),
        airgap.get("co2_ppm"),
        bottom.get("moisture_pct"),
    )
    return {
        "headline": headline,
        "balance": bal,
        "stage_top": compost.stage(
            top.get("temperature_c"), airgap.get("co2_ppm"), top_moisture
        ),
        "stage_bottom": stage_bottom,
        "bottom_ready": stage_bottom == "ready",
        "suggestions": suggestions,
        "warnings": ["Readiness is a guide from sensor trends, not a lab test."],
    }
