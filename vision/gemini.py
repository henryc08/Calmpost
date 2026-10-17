"""Identify what was dropped in, from a BEFORE and an AFTER frame.

One Gemini Flash call per drop, JSON schema output, catalog ids as an enum.
Hard budget of 4 s (CLAUDE.md): on timeout or any error we return no items
and the app shows the photo with empty fields for manual entry.
"""

import asyncio
import json
import logging
import time
from dataclasses import asdict, dataclass

from google import genai
from google.genai import types

import catalog
from config import settings

log = logging.getLogger(__name__)

BUDGET_S = 4.0
IGNORE_LABELS = {"hand", "person", "finger", "arm", "lid", "spoon", "fork", "knife", "utensil", "glove"}

PROMPT = """\
You are looking into a home compost bin from above. Image 1 is BEFORE, image 2
is AFTER something was dropped in. Report only items that are NEW in image 2.
The bin already holds old scraps: ignore anything already visible in image 1.
Ignore hands, arms, lids and utensils. If nothing new was added, return an
empty list.

For each new item:
- label: short plain name, e.g. "banana peel" (not "banana" if it's a peel)
- catalog_id: the closest id from the allowed list, or "unknown" if none fits
- est_grams: rough weight in grams
- confidence: 0 to 1, how sure you are of catalog_id
- box_2d: [ymin, xmin, ymax, xmax] of the item in image 2, scaled 0-1000
"""


@dataclass
class Detection:
    label: str
    catalog_id: str
    category: str | None     # from the catalog (rules), never from Gemini
    est_grams: float | None
    amount: str | None       # small | handful | large
    confidence: float
    box_2d: list[int] | None

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class Result:
    items: list[Detection]
    latency_ms: int
    ok: bool                 # False = Gemini failed or timed out; app shows empty fields
    error: str | None = None
    model: str = ""


def schema(catalog_ids: list[str]) -> dict:
    return {
        "type": "OBJECT",
        "properties": {
            "items": {
                "type": "ARRAY",
                "items": {
                    "type": "OBJECT",
                    "properties": {
                        "label": {"type": "STRING"},
                        "catalog_id": {"type": "STRING", "enum": catalog_ids},
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


def _valid_box(box) -> list[int] | None:
    if not isinstance(box, list) or len(box) != 4:
        return None
    try:
        y0, x0, y1, x1 = (max(0, min(1000, int(v))) for v in box)
    except (TypeError, ValueError):
        return None
    return [y0, x0, y1, x1] if y1 > y0 and x1 > x0 else None


def parse(raw: dict) -> list[Detection]:
    """Validate Gemini's JSON. Anything off-schema is corrected or dropped."""
    known = set(catalog.ids())
    out = []
    for it in raw.get("items") or []:
        if not isinstance(it, dict):
            continue
        label = str(it.get("label", "")).strip()[:60]
        if not label or label.lower() in IGNORE_LABELS:
            continue  # a hand-only detection is not a drop
        cid = it.get("catalog_id") if it.get("catalog_id") in known else catalog.UNKNOWN
        grams = it.get("est_grams")
        grams = float(grams) if isinstance(grams, (int, float)) and 0 < grams < 5000 else None
        if grams is None and cid != catalog.UNKNOWN:
            grams = catalog.load()[cid].grams or None
        try:
            conf = max(0.0, min(1.0, float(it.get("confidence", 0))))
        except (TypeError, ValueError):
            conf = 0.0
        out.append(Detection(
            label=label, catalog_id=cid, category=catalog.category_of(cid),
            est_grams=grams, amount=catalog.amount_of(grams), confidence=round(conf, 2),
            box_2d=_valid_box(it.get("box_2d")),
        ))
    return out


class Identifier:
    def __init__(self, api_key: str = settings.gemini_api_key, model: str = settings.gemini_vision_model):
        self.model = model
        self.api_key = api_key

    async def identify(self, before_jpeg: bytes, after_jpeg: bytes, hints: list[str] | None = None) -> Result:
        t0 = time.monotonic()
        if not self.api_key:
            return Result([], 0, ok=False, error="GEMINI_API_KEY not set", model=self.model)
        prompt = PROMPT + "\nAllowed catalog ids:\n" + ", ".join(catalog.ids())
        if hints:
            prompt += "\n\nRecent corrections in this bin:\n" + "\n".join(f"- {h}" for h in hints[:5])
        config = types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=schema(catalog.ids()),
            temperature=0,
            media_resolution=types.MediaResolution.MEDIA_RESOLUTION_MEDIUM,
            thinking_config=types.ThinkingConfig(thinking_budget=0),
        )
        contents = [
            types.Part.from_text(text="Image 1 (BEFORE):"),
            types.Part.from_bytes(data=before_jpeg, mime_type="image/jpeg"),
            types.Part.from_text(text="Image 2 (AFTER):"),
            types.Part.from_bytes(data=after_jpeg, mime_type="image/jpeg"),
            types.Part.from_text(text=prompt),
        ]
        client = genai.Client(api_key=self.api_key)
        error = None
        for attempt in range(2):  # one retry, only if time is left in the budget
            remaining = BUDGET_S - (time.monotonic() - t0)
            if remaining < 1.0:
                break
            try:
                resp = await asyncio.wait_for(
                    client.aio.models.generate_content(model=self.model, contents=contents, config=config),
                    timeout=remaining)
                items = parse(json.loads(resp.text or "{}"))
                return Result(items, int((time.monotonic() - t0) * 1000), ok=True, model=self.model)
            except asyncio.TimeoutError:
                error = f"timed out after {BUDGET_S:.0f}s"
                break
            except Exception as e:  # auth, quota, network, bad JSON
                error = f"{type(e).__name__}: {e}"[:300]
                log.warning("gemini attempt %d failed: %s", attempt + 1, error)
                if getattr(e, "code", None) in (400, 401, 403, 429):
                    break  # bad key, bad request or quota: retrying now won't help
        return Result([], int((time.monotonic() - t0) * 1000), ok=False, error=error, model=self.model)
