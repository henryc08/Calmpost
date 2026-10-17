"""Trunc: the in-app compost assistant.

Trunc answers free-text questions, which is the one thing the rest of the app
cannot do. /advice/check takes an item name and returns a fixed verdict shape;
there was nowhere to ask "why does my bin smell?".

Three things shape the design:

  1. Trunc is given context, not told to use it. The sensor snapshot, what was
     recently added and the last camera photos go in every call, but the prompt
     says to mention them only when they bear on the question. "Can I compost
     eggshells?" should not come back with a moisture reading.

  2. The rules are generated from app.rules.compost, not retyped. MOISTURE_LO,
     AVOID_ITEMS, GREENS and BROWNS are the same constants the verdict sheet
     and the camera use, so Trunc cannot drift from the rest of the app -- a
     keep-out item added to the rules is a keep-out item to Trunc the same day.

  3. Compost only. The model classifies each question and the backend replies
     with its own fixed line when it is off topic, so the refusal is consistent
     rather than improvised.

Stateless: the client passes the conversation back each turn. Nothing is
stored, so there is no chat table and no history to leak between accounts.
"""

import base64
import json
import logging

import httpx

from ..config import get_settings
from ..rules import compost

log = logging.getLogger(__name__)

ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

#: Photos are the expensive part of the payload, so only the newest few go in.
MAX_PHOTOS = 2
MAX_HISTORY_TURNS = 12
OFF_TOPIC_REPLY = (
    "I only know about composting, so I'll stay out of that one. "
    "Ask me about your bin, what to add, or why something smells off."
)
UNAVAILABLE_REPLY = (
    "I can't reach my brain right now, so here's what the sensors say instead."
)


def _rules_brief() -> str:
    """The app's own rules, rendered from the constants that enforce them."""
    return "\n".join([
        f"- Healthy moisture is {compost.MOISTURE_LO:.0f}-{compost.MOISTURE_HI:.0f}%. "
        f"Above {compost.MOISTURE_HI + 4:.0f}% is soggy; below {compost.MOISTURE_LO - 4:.0f}% is too dry.",
        "- Temperature matters as a rise above the ambient air temperature, not as an "
        "absolute number: 25C in a 24C room is a cold pile.",
        "- Browns dry a wet bin; greens or a little water fix a dry one.",
        f"- One cup is about {compost.CUP_GRAMS:.0f} g, and the greens/browns balance is "
        "measured in cups of volume, not item counts.",
        f"- Stages run {' -> '.join(compost.STAGE_ORDER)}.",
        "- Never tell them to add any of these, whatever they ask: "
        + ", ".join(sorted(compost.AVOID_ITEMS)) + ".",
        "- Greens include: " + ", ".join(sorted(compost.GREENS)) + ".",
        "- Browns include: " + ", ".join(sorted(compost.BROWNS)) + ".",
    ])


SYSTEM_PROMPT = """\
You are Trunc, the composting assistant inside Calmpost, an app for one small \
sealed home compost bin with a lid and vent holes and two layers: fresh scraps \
on top, older compost at the bottom. Speak plainly and calmly, the way the app \
does. No mascots, no roleplay, no emoji.

ONLY answer questions about composting and this bin: what can go in, why the \
bin behaves as it does, smells, pests, moisture, temperature, layers, \
harvesting, and how to read the app's own readings. Anything else -- general \
cooking, coding, homework, personal advice, other topics entirely -- is off \
topic. Set on_topic false for those and leave reply empty; do not try to \
answer them, and do not explain yourself. A question that merely mentions food \
is still on topic if it is asking whether it can be composted.

You are given the bin's live readings, what was recently added, and the last \
few photos the bin's camera took. Be aware of all of it, but bring it up only \
when it bears on the question. If someone asks whether eggshells can be \
composted, just answer; do not recite the moisture. If they ask why the bin \
smells, the readings and the recent adds are exactly the evidence to use.

Rules of this bin, which you must never contradict:
%(rules)s

- A layer whose "measured" is false has no sensor. Say it is unknown; never \
state a number or a stage for it.
- If moisture_calibrated is false, treat percentages as approximate.
- recent_adds is newest first with hours_ago; action "skipped" means they \
decided to keep it out.
- The photos are frames from the bin's camera with what it guessed. The guess \
can be wrong; if the photo disagrees with the label, trust what you see and \
say so plainly.
- Readings are a guide, not a lab test. Never overclaim, and never invent a \
reading you were not given.
- Answer in at most 90 words, in plain sentences. No headings or bullet lists \
unless they genuinely asked for steps.
"""

RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "on_topic": {
            "type": "boolean",
            "description": "false when the question is not about composting or this bin",
        },
        "reply": {"type": "string", "description": "the answer; empty when on_topic is false"},
        "used_readings": {
            "type": "boolean",
            "description": "true when the answer actually leaned on the sensor data",
        },
    },
    "required": ["on_topic", "reply"],
}


def _context_block(snapshot: dict, recent: list[dict], photos: list[dict]) -> str:
    """Everything Trunc may draw on, as one JSON blob."""
    return json.dumps(
        {
            "readings": {
                "measured_at": snapshot["time"],
                "layers": snapshot["layers"],
                "stages": snapshot["stages"],
                "air": snapshot["air"],
                "greens_7d_cups": snapshot["greens_7d"],
                "browns_7d_cups": snapshot["browns_7d"],
                "healthy_band_pct": snapshot["healthy_band"],
                "healthy_hours_today": snapshot["healthy_hours_today"],
                "moisture_calibrated": snapshot["moisture_calibrated"],
            },
            "recent_adds": recent,
            # The photos themselves follow as image parts, in this order.
            "recent_photos": [
                {
                    "position": i + 1,
                    "hours_ago": p["hours_ago"],
                    "camera_guessed": p["labels"],
                    "user_confirmed": p["confirmed"],
                }
                for i, p in enumerate(photos)
            ],
        },
        indent=2,
        default=str,
    )


def _parts(snapshot: dict, recent: list[dict], photos: list[dict], message: str) -> list[dict]:
    parts: list[dict] = [
        {"text": "Bin context as JSON:\n" + _context_block(snapshot, recent, photos)}
    ]
    for i, p in enumerate(photos):
        parts.append({"text": f"Photo {i + 1}, {p['hours_ago']}h ago:"})
        parts.append({
            "inlineData": {
                "mimeType": "image/jpeg",
                "data": base64.b64encode(p["jpeg"]).decode(),
            }
        })
    parts.append({"text": f"Their question: {message}"})
    return parts


def _history(turns: list[dict]) -> list[dict]:
    """Earlier turns in Gemini's shape. Only the last few, newest kept."""
    out = []
    for t in turns[-MAX_HISTORY_TURNS:]:
        text = (t.get("text") or "").strip()
        if not text:
            continue
        out.append({
            "role": "model" if t.get("role") == "assistant" else "user",
            "parts": [{"text": text}],
        })
    return out


async def ask(
    message: str,
    snapshot: dict,
    recent: list[dict],
    photos: list[dict],
    history: list[dict] | None = None,
) -> tuple[dict, str]:
    """Answer one question. Returns (payload, model).

    Never raises for a model failure: a judge should see an answer, not a stack
    trace, so an unreachable Gemini degrades to the rules summary.
    """
    settings = get_settings()
    if not settings.gemini_api_key:
        return _fallback(snapshot), "rules-fallback"

    body = {
        "systemInstruction": {
            "parts": [{"text": SYSTEM_PROMPT % {"rules": _rules_brief()}}]
        },
        "contents": [
            *_history(history or []),
            {"role": "user", "parts": _parts(snapshot, recent, photos, message)},
        ],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": RESPONSE_SCHEMA,
            # Lower than the verdict sheet's 0.4: a wrong composting fact is
            # worse here, because nothing downstream checks the prose.
            "temperature": 0.3,
        },
    }

    try:
        answer = await _call(body)
    except Exception:
        # A single unreadable frame is answered with "Unable to process input
        # image" and a 400, which would otherwise cost the whole reply over a
        # photo nobody asked about. Found with a truncated thumbnail in the
        # table: the text answer was fine, the image was not. Drop the photos
        # and ask once more before giving up.
        if photos:
            log.warning("trunc: call failed with %d photo(s); retrying text-only", len(photos))
            try:
                body["contents"][-1]["parts"] = _parts(snapshot, recent, [], message)
                answer = await _call(body)
            except Exception:
                log.warning("trunc: text-only retry failed too; using the rules summary")
                return _fallback(snapshot), "rules-fallback"
        else:
            log.warning("trunc: gemini call failed; falling back to the rules summary")
            return _fallback(snapshot), "rules-fallback"

    if (not isinstance(answer, dict)
            or not isinstance(answer.get("reply"), str)
            or any(key in answer and not isinstance(answer[key], bool)
                   for key in ("on_topic", "used_readings"))):
        return _fallback(snapshot), "rules-fallback"

    if not answer.get("on_topic", True):
        # Our line, not the model's, so the refusal reads the same every time.
        return {"on_topic": False, "reply": OFF_TOPIC_REPLY, "used_readings": False}, settings.gemini_model

    reply = (answer.get("reply") or "").strip()
    if not reply:
        return _fallback(snapshot), "rules-fallback"

    # Defensively, as the verdict sheet does: never let a keep-out item through
    # as a suggestion, however it was phrased.
    bad = _suggests_keeping_out_item(reply)
    if bad:
        log.warning("trunc: reply suggested %r; replacing with the rules line", bad)
        return {
            "on_topic": True,
            "reply": f"Keep {bad} out of this bin -- {compost.AVOID_ITEMS.get(bad, 'it does not belong in a home bin')}.",
            "used_readings": False,
        }, "rules-override"

    return {
        "on_topic": True,
        "reply": reply,
        "used_readings": bool(answer.get("used_readings", False)),
    }, settings.gemini_model


def _suggests_keeping_out_item(reply: str) -> str | None:
    """A keep-out item named next to 'add' wording. Deliberately narrow: the
    model should be free to say "don't add meat" without being overridden."""
    low = reply.lower()
    for bad in compost.AVOID_ITEMS:
        if bad not in low:
            continue
        for phrase in (f"add {bad}", f"adding {bad}", f"add some {bad}", f"add a little {bad}"):
            at = low.find(phrase)
            if at == -1:
                continue
            before = low[max(0, at - 24):at]
            if any(neg in before for neg in ("don't ", "do not ", "never ", "avoid ", "no ")):
                continue
            return bad
    return None


def _fallback(snapshot: dict) -> dict:
    """No model: say so, and still tell them something true from the sensors."""
    top = snapshot["layers"]["top"]
    pct, state = top["moisture_pct"], top["moisture_state"]
    air = snapshot["air"]
    bits = []
    if pct is not None:
        bits.append(f"the top layer is {pct:.0f}% moisture ({state})")
    if air.get("ambient_temp_c") is not None and top.get("temp_c") is not None:
        rise = top["temp_c"] - air["ambient_temp_c"]
        bits.append(f"{rise:+.1f}C against the room")
    if air.get("co2_ppm") is not None:
        bits.append(f"CO2 {air['co2_ppm']:.0f} ppm")
    reading = ", ".join(bits) if bits else "no readings have arrived yet"
    return {"on_topic": True, "reply": f"{UNAVAILABLE_REPLY} Right now {reading}.", "used_readings": True}


async def _call(body: dict) -> dict:
    """One structured-output call. Raises on any failure; the caller falls back."""
    settings = get_settings()
    url = ENDPOINT.format(model=settings.gemini_model)
    # Longer than the verdict sheet's 20 s: photos make the request bigger.
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(url, headers={"x-goog-api-key": settings.gemini_api_key}, json=body)
        resp.raise_for_status()
        data = resp.json()
    return json.loads(data["candidates"][0]["content"]["parts"][0]["text"])
