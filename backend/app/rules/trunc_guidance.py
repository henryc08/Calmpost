"""Grounded care decisions. Gemini may explain these, never replace them."""
import re
from datetime import datetime, timezone

from . import compost

OVERVIEW_QUESTION = "Based on my current bin data, what should I do next?"


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
        line = "The two moisture probes disagree about what needs care. Check both spots before adding food or water across the bin."
    else:
        line = {
            "browns": "Try dry browns such as shredded cardboard after checking the compost by hand. Hold off on more wet scraps for now.",
            "greens": "A small amount of fruit or vegetable scraps may help: the upper probe is dry and your recent additions lean brown. Check by hand first.",
            "water": "Check the dry spot by hand and add a little water if needed. More food is not the next step.",
            "mix": "Check airflow and gently mix the compost, then watch the readings. More food is not needed for this action.",
            "nothing": "No addition is indicated by the available readings. Keep monitoring rather than adding food just to do something.",
        }[need]
        if need == "nothing":
            status = "steady"
            if (bottom.get("measured") and snap.get("moisture_calibrated")
                    and bottom.get("moisture_calibrated") and snap["greens_7d"] + snap["browns_7d"] > 0):
                line = "Your measured moisture and recent mix look steady. Keep doing what you're doing; nothing needs adding right now."
    limits = []
    if not snap.get("moisture_calibrated") or (bottom.get("measured") and not bottom.get("moisture_calibrated")):
        limits.append("An uncalibrated moisture probe is approximate.")
    if not bottom.get("measured"):
        limits.append("Lower moisture is unknown.")
    if snap["greens_7d"] + snap["browns_7d"] <= 0:
        limits.append("No recent confirmed mix history is available.")
    else:
        limits.append("The seven-day mix is an estimate of additions, not the bin's current chemistry.")
    return {"need": need, "status": status, "action": line, "evidence": evidence, "limits": limits,
            "used_readings": bool(fresh and measured)}


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
    item = re.split(r"\s+(?:to|into|in|right now|at the moment|today|now|instead)\b|[?!.,]", match[1])[0].strip()
    if not item or item in {"anything", "something", "next", "this", "it", "that", "more", "in"}:
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
        return f"I cannot confidently identify '{item}' as a safe compost material. Tell me what it is made of before adding it."
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
