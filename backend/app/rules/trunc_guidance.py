"""Grounded care decisions. Gemini may explain these, never replace them."""
import re
from datetime import datetime, timezone

from . import compost

OVERVIEW_QUESTION = "Based on my current bin data, what should I do next?"

#: What to tell someone for each care need. Each names things they can
#: actually reach for, because "consider adding browns" helps nobody who is
#: standing at the bin wondering what a brown is.
ACTIONS = {
    "browns": "Your bin is on the wet side, so add some dry browns: shredded cardboard, dry leaves or torn paper egg cartons. Hold off on wet scraps for now.",
    "greens": "Your bin is dry and your recent additions lean brown, so add a handful of greens: fruit or vegetable scraps, or coffee grounds.",
    "water": "Your bin is a bit dry. Add a splash of water to the dry spot and mix it in. No food needed right now.",
    "mix": "Give your bin a gentle stir to let air in, then check back. No food needed right now.",
    "nothing": "Nothing is urgent. When you add, aim for about one part greens (fruit and veg scraps, coffee grounds) to two parts browns (shredded cardboard, dry leaves).",
}
DOING_GREAT = "Your compost is doing great. Keep doing what you're doing."

#: Words that ask what to add without naming anything.
_GENERIC = {"", "anything", "something", "next", "this", "it", "that", "more", "in", "bin",
            "items", "item", "things", "thing", "stuff", "food", "scraps", "what", "now"}


def is_stale(snap: dict) -> bool:
    at = snap.get("time")
    if snap.get("stale") or at is None:
        return True
    if isinstance(at, str):
        try:
            at = datetime.fromisoformat(at.replace("Z", "+00:00"))
        except ValueError:
            return True
    if at.tzinfo is None:
        at = at.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - at).total_seconds() > 120


def assess(snap: dict) -> dict:
    top, bottom = snap["layers"]["top"], snap["layers"]["bottom"]
    fresh = not is_stale(snap)
    measured = top.get("measured") and top.get("moisture_pct") is not None
    need = compost.need_for({**snap, "stale": not fresh})
    evidence = []
    for name, layer in (("Upper", top), ("Lower", bottom)):
        if layer.get("measured") and layer.get("moisture_pct") is not None:
            evidence.append(f"{name} probe: {layer['moisture_pct']:.0f}% relative moisture")
    status = "action"
    if not fresh or not measured:
        status = "unknown"
        line = "I need a fresh upper moisture reading before recommending an addition. Check the bin by hand and reconnect the sensor."
    elif compost.moisture_conflict(snap):
        status = "inspect"
        line = inspect_line(snap)
    else:
        line = ACTIONS[need]
        if need == "nothing":
            status = "steady"
            if (bottom.get("measured") and snap.get("moisture_calibrated")
                    and bottom.get("moisture_calibrated") and snap["greens_7d"] + snap["browns_7d"] > 0):
                line = DOING_GREAT
    limits = []
    if not snap.get("moisture_calibrated") or (bottom.get("measured") and not bottom.get("moisture_calibrated")):
        limits.append("An uncalibrated moisture probe is approximate.")
    if not bottom.get("measured"):
        limits.append("Lower moisture is unknown.")
    if snap["greens_7d"] + snap["browns_7d"] <= 0:
        limits.append("No recent confirmed mix history is available.")
    return {"need": need, "status": status, "action": line, "evidence": evidence, "limits": limits,
            "used_readings": bool(fresh and measured)}


def lower_wet(snap: dict) -> bool:
    return (snap["layers"]["bottom"].get("moisture_pct") or 0) > compost.MOISTURE_HI


def inspect_line(snap: dict) -> str:
    """The top looks fine but the bottom doesn't, so say which and what fixes it."""
    top = snap["layers"]["top"]["moisture_pct"]
    bottom = snap["layers"]["bottom"]["moisture_pct"]
    if lower_wet(snap):
        return (f"The top looks fine ({top:.0f}%), but the bottom is wet ({bottom:.0f}%). "
                "Feel the bottom: if it's soggy, mix in some shredded cardboard or dry leaves "
                "and hold off on wet scraps.")
    return (f"The top looks fine ({top:.0f}%), but the bottom is dry ({bottom:.0f}%). "
            "Feel the bottom: if it's dry, pour a little water down the side and mix it in.")


def summary(snap: dict) -> str:
    a = assess(snap)
    return " ".join([a["action"], *([("; ".join(a["evidence"]) + ".")] if a["evidence"] else []), *a["limits"]])


def requested_item(message: str) -> str | None:
    """Conservative add-question extraction; do not treat explanations as adds."""
    low = message.strip().lower()
    low = re.sub(r"\b(?:my|the|this|your) compost\b", "bin", low)
    if re.search(r"\bhow much water\b", low):
        return "water"
    match = re.search(r"\b(?:add|adding|compost|put in|put|feed|what about)\s+(?:some\s+|more\s+|a little\s+|an?\s+)?(.+)", low)
    if not match:
        return None
    rest = re.sub(r"^(?:to|into|in)\s+(?:the\s+|my\s+|this\s+|your\s+)?(?:bin|pile|compost)\b\s*", "", match[1])
    item = re.split(r"\s+(?:to|into|in|right now|at the moment|today|now|instead)\b|[?!.,]", rest)[0].strip()
    if item in _GENERIC:
        return None
    return item


def item_answer(snap: dict, item: str) -> str:
    if item == "water":
        a = assess(snap)
        intro = ("Water fits the current care action, after checking by hand."
                 if a["need"] == "water" and a["used_readings"]
                 else "I would not add water across the bin right now.")
        return intro + " " + summary(snap)
    reason = compost.avoid_reason(item)
    if reason:
        return f"Keep {item} out of this bin: {reason}. This does not depend on the sensor readings."
    category = compost.categorise(item)
    if category == "unknown":
        return (f"{item.capitalize()} isn't in my list, so I can't check it against your bin. "
                "Plant-based food scraps and plain paper or cardboard are usually fine; "
                "keep out meat, fish, dairy, oily food and bones.")
    a = assess(snap)
    if a["status"] in {"unknown", "inspect"}:
        intro = f"{item.capitalize()} is generally compostable, but I cannot recommend adding it right now."
    elif a["need"] == ("greens" if category == "green" else "browns"):
        intro = f"Yes, {item} fits the current care action. Start small; these readings cannot determine an exact quantity."
    elif a["need"] == "nothing":
        intro = f"{item.capitalize()} is compostable, but it is not needed right now."
    else:
        intro = f"Hold off on {item} for now. It is compostable, but it does not address the current need."
    return intro + " " + summary(snap)


def fallback(message: str, snap: dict) -> dict:
    item = requested_item(message)
    text = item_answer(snap, item) if item else summary(snap)
    if any(w in message.lower() for w in ("how much", "how many", "exact")):
        text = "I cannot calculate an exact dose or number of scraps from two moisture points and estimated additions. " + text
    uses = assess(snap)["used_readings"] and (not item or item == "water" or compost.categorise(item) in ("green", "brown"))
    return {"on_topic": True, "reply": text, "used_readings": uses,
            "need": assess(snap)["need"]}


def followup_item(message: str, history: list[dict]) -> str | None:
    if not re.search(r"\b(?:how much|how many|what about it|what about now|and now)\b", message.lower()):
        return None
    for turn in reversed(history):
        if turn.get("role") == "user":
            item = requested_item(turn.get("text", ""))
            if item:
                return item
    return None
