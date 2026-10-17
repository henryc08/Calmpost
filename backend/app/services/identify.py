"""Identify one user-supplied photo.

The camera drop-in (2.4) watches the bin and decides for itself when something
arrived. This is the other way round: the user points a phone at something and
asks what it is. Same model, same catalog, same rules -- different trigger.

Deliberately mirrors vision/gemini.py's contract rather than inventing a
second one: the same `items` shape with label, catalog_id, est_grams,
confidence and box_2d on a 0-1000 grid, and the same correct-or-drop parsing,
so a photo submission and a camera detection are interchangeable downstream.
The difference is that vision/ runs on a laptop with the google-genai SDK and
this runs in the backend over REST, because the backend already talks to
Gemini that way and should not grow a second client.
"""

import base64
import json
import logging

import httpx

from ..catalog import food
from ..config import get_settings
from ..rules import compost

log = logging.getLogger(__name__)

ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

#: A phone photo, not a thumbnail. The app should downscale to ~1024 px first;
#: this is the ceiling, not a target. Larger is rejected rather than truncated.
MAX_PHOTO_BYTES = 1_500_000

UNKNOWN = "unknown"

#: Things in frame that are not the item being asked about.
IGNORE_LABELS = {"hand", "hands", "finger", "fingers", "arm", "glove", "bin", "lid"}

PROMPT = """\
Identify the food scrap or household waste item the person is holding up or \
showing in this photo, so a composting app can tell them whether it belongs in \
their bin.

Name every distinct item you can see, at most four, most prominent first. \
Ignore hands, arms, the bin itself and the background.

For each item:
- label: what it is, in two or three plain words, lower case ("banana peel").
- catalog_id: the closest id from the list, or "unknown" if none fits. Do not \
force a poor match; "unknown" is the right answer for anything unusual.
- est_grams: a rough weight for what is visible.
- confidence: how sure you are, 0 to 1. Be honest; a blurry or partly hidden \
item should be low.
- box_2d: [ymin, xmin, ymax, xmax] on a 0-1000 grid over the whole image.

Do not say whether it should be composted. The app decides that by its own \
rules."""


def schema() -> dict:
    return {
        "type": "OBJECT",
        "properties": {
            "items": {
                "type": "ARRAY",
                "items": {
                    "type": "OBJECT",
                    "properties": {
                        "label": {"type": "STRING"},
                        "catalog_id": {"type": "STRING", "enum": sorted(food.BY_ID) + [UNKNOWN]},
                        "est_grams": {"type": "NUMBER"},
                        "confidence": {"type": "NUMBER"},
                        "box_2d": {"type": "ARRAY", "items": {"type": "INTEGER"}},
                    },
                    "required": ["label", "catalog_id", "confidence"],
                },
            }
        },
        "required": ["items"],
    }


def _box(raw) -> list[int] | None:
    if not isinstance(raw, list) or len(raw) != 4:
        return None
    try:
        y0, x0, y1, x1 = (max(0, min(1000, int(v))) for v in raw)
    except (TypeError, ValueError):
        return None
    return [y0, x0, y1, x1] if y1 > y0 and x1 > x0 else None


def parse(raw: dict) -> list[dict]:
    """Validate the model's JSON. Anything off-schema is corrected or dropped.

    Categories are not taken from the model at all: compost.categorise has the
    final say, so a label the rules call avoid is avoid however the photo was
    labelled. That is also why the prompt forbids the model from judging.
    """
    if not isinstance(raw, dict) or not isinstance(raw.get("items"), list):
        raise ValueError("Photo identification must contain an items list")
    out: list[dict] = []
    for it in (raw.get("items") or [])[:4]:
        if not isinstance(it, dict):
            continue
        label = str(it.get("label", "")).strip()[:60]
        if not label or label.lower() in IGNORE_LABELS:
            continue
        cid = it.get("catalog_id") if it.get("catalog_id") in food.BY_ID else UNKNOWN
        grams = it.get("est_grams")
        grams = float(grams) if isinstance(grams, (int, float)) and 0 < grams < 5000 else None
        if grams is None and cid != UNKNOWN:
            grams = food.BY_ID[cid].get("grams") or None
        try:
            conf = max(0.0, min(1.0, float(it.get("confidence", 0))))
        except (TypeError, ValueError):
            conf = 0.0
        out.append({
            "label": label,
            "catalog_id": cid,
            # categorise() already returns "avoid" for a keep-out item.
            # None for unknown, matching the camera's shape.
            "category": cat if (cat := compost.categorise(label)) != "unknown" else None,
            "est_grams": grams,
            "confidence": conf,
            "box_2d": _box(it.get("box_2d")),
        })
    return out


async def identify(jpeg: bytes) -> tuple[list[dict], str, str | None]:
    """Returns (items, model, error).

    Never raises: an empty list with an error is a real answer here. The photo
    is still worth keeping and the user can name the item themselves, which is
    the same path an unknown catalog_id already takes.
    """
    settings = get_settings()
    if not settings.gemini_api_key:
        return [], "rules-fallback", "no GEMINI_API_KEY configured"

    body = {
        "contents": [{
            "role": "user",
            "parts": [
                {"inlineData": {"mimeType": "image/jpeg", "data": base64.b64encode(jpeg).decode()}},
                {"text": PROMPT},
            ],
        }],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": schema(),
            # Identification should be repeatable: the same photo should not
            # come back as a different item on a retry.
            "temperature": 0,
        },
    }

    try:
        raw = await _call(body)
        items = parse(raw)
    except Exception:
        # Provider exceptions can contain credentials, request URLs or body
        # data. Never persist them in drop_events, return them to the app, or
        # include their traceback in logs.
        log.warning("identify: Gemini request failed; using manual identification")
        return [], "rules-fallback", "Photo identification is unavailable. Please identify the items manually."

    return items, settings.gemini_model, None


async def _call(body: dict) -> dict:
    settings = get_settings()
    url = ENDPOINT.format(model=settings.gemini_model)
    async with httpx.AsyncClient(timeout=30) as client:
        # Keep credentials out of URLs (including HTTP client access logs).
        resp = await client.post(url, headers={"x-goog-api-key": settings.gemini_api_key}, json=body)
        resp.raise_for_status()
        data = resp.json()
    return json.loads(data["candidates"][0]["content"]["parts"][0]["text"])
