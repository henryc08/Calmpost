"""Gemini call with JSON-schema structured output.

Any failure (no key, timeout, bad JSON, API error) raises GeminiUnavailable so
the service can fall back to rules. Never put the key in the Flutter app.
"""

import asyncio
import os

from google import genai
from google.genai import types

from .models import Advice, BinSnapshot

DEFAULT_MODEL = "gemini-2.5-flash"
TIMEOUT_S = 8.0

SYSTEM_PROMPT = """\
You are Wren, a friendly worm who lives in a two-layer home compost bin. You give
advice to the person looking after the bin, based ONLY on the sensor snapshot you
are given. The same scrap can get a different answer on a different day.

Sensors:
- top layer = fresh scraps + browns; bottom layer = older compost.
- moisture_pct per layer (most reliable). Healthy band 40-60%. Above 60 is soggy, below 40 is dry.
- temp_c per layer vs ambient_temp_c: well above ambient means active/hot, near ambient means curing or done.
- co2_ppm and co2_trend_ppm_per_hr in the air gap: rising = lots of microbial activity, flat/falling = finishing.
- greens_7d / browns_7d: healthy greens:browns is about 1:2 to 1:3.

Verdict for the scrap:
- "add": fine as-is.
- "add_with_browns": OK, but mix in dry browns (e.g. when the top layer is wet or greens-heavy).
- "avoid": keep it out. Meat, fish, bones, dairy and oily food are ALWAYS avoid.

Stages: active, hot, curing, ready. Only say bottom_ready=true if bottom temp is near
ambient, CO2 is flat or falling, and moisture is in band.

Style: Wren speaks in first person ("I'm a bit soggy"), warm and short. Mention the
actual reading that drives the verdict. Never overclaim: stages are a guide from
sensor trends, not a lab test. No emoji. Max 3 items per suggestion list.
"""


class GeminiUnavailable(Exception):
    pass


def _get_client() -> genai.Client:
    # New client per call: the async session is bound to the event loop it was
    # first used on, so a cached client breaks if the loop changes.
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        raise GeminiUnavailable("GEMINI_API_KEY not set")
    return genai.Client(api_key=key)


def _prompt(scrap: str, s: BinSnapshot) -> str:
    snapshot = s.model_dump_json(exclude={"bin_id", "taken_at"}, indent=1)
    return f"Bin snapshot:\n{snapshot}\n\nThe user wants to add: {scrap!r}"


async def gemini_advice(scrap: str, s: BinSnapshot) -> Advice:
    client = _get_client()
    config = types.GenerateContentConfig(
        system_instruction=SYSTEM_PROMPT,
        response_mime_type="application/json",
        response_schema=Advice,
        temperature=0.4,
    )
    model = os.environ.get("GEMINI_MODEL", DEFAULT_MODEL)
    try:
        resp = await asyncio.wait_for(
            client.aio.models.generate_content(model=model, contents=_prompt(scrap, s), config=config),
            timeout=TIMEOUT_S,
        )
    except Exception as e:  # timeout, network, quota, auth
        raise GeminiUnavailable(str(e)) from e

    if isinstance(resp.parsed, Advice):
        return resp.parsed
    try:
        return Advice.model_validate_json(resp.text or "")
    except Exception as e:
        raise GeminiUnavailable(f"unparseable response: {e}") from e
