import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path
import pytest
from app.rules import compost, trunc_guidance as g
from app.services import trunc

CASES = json.loads((Path(__file__).resolve().parents[2] / "testdata/trunc_cases.json").read_text())


def snapshot(case):
    def layer(value):
        return {"measured": value is not None, "moisture_pct": value, "temp_c": None,
                "moisture_calibrated": True, "moisture_state": compost.moisture_state(value)}
    top, bottom = layer(case["top"]), layer(case["bottom"])
    top["temp_c"] = 21 + case.get("delta", 14)
    return {"time": datetime.now(timezone.utc), "stale": case.get("stale", False),
            "layers": {"top": top, "bottom": bottom}, "stages": {"top": "active", "bottom": "curing"},
            "air": {"ambient_temp_c": 21, "co2_ppm": 2400, "co2_ok": True, "co2_slope_per_day": case.get("slope", -2)},
            "greens_7d": case["greens"], "browns_7d": case["browns"],
            "moisture_calibrated": True, "healthy_band": [40, 60], "healthy_hours_today": 2}


@pytest.mark.parametrize("case", CASES, ids=lambda c: c["name"])
def test_shared_flutter_backend_decisions(case):
    s = snapshot(case)
    assert compost.need_for(s) == case["need"]
    a = g.assess(s)
    assert a["status"] == case["status"]
    assert case["apple"] in g.item_answer(s, "apples")
    assert "nitrogen it's missing" not in g.item_answer(s, "apples")
    if case.get("stale") or case["top"] is None:
        assert not a["used_readings"]


def test_aliases_avoid_unknown_and_quantities():
    s = snapshot(CASES[1])
    for item in ("apple", "apples", "apple core", "apple scraps"):
        assert compost.categorise(item) == "green"
        assert compost.is_wet_item(item)
        assert "Hold off" in g.item_answer(s, item)
    assert "Keep apples and cheese out" in g.item_answer(s, "apples and cheese")
    assert "cannot confidently identify" in g.item_answer(s, "mystery polymer")
    assert "cannot calculate an exact" in g.fallback("How much water?", s)["reply"]
    assert g.requested_item("Should I add more apples to this compost?") == "apples"
    assert g.requested_item("What about apples?") == "apples"
    assert g.requested_item("How is my compost doing?") is None
    assert "Water fits" in g.item_answer(s, "water")
    assert "not add water" in g.item_answer(snapshot(CASES[0]), "water")


def test_material_answer_does_not_depend_on_gemini(monkeypatch):
    async def fail(_):
        raise AssertionError("known material should use current rules directly")
    monkeypatch.setattr(trunc, "_call", fail)
    answer, model = asyncio.run(trunc.ask("Should I add apples?", snapshot(CASES[1]), [], []))
    assert model == "rules-grounded"
    assert "Hold off" in answer["reply"]
    assert answer["need"] == "water"


def test_matching_enum_cannot_smuggle_opposite_add_instruction(monkeypatch):
    from app.config import get_settings
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    get_settings.cache_clear()


    async def wrong(_):
        return {"on_topic": True, "used_readings": True, "need": "browns", "reply": "Add apples and water now."}
    monkeypatch.setattr(trunc, "_call", wrong)
    answer, model = asyncio.run(trunc.ask(g.OVERVIEW_QUESTION, snapshot(CASES[0]), [], []))
    assert model == "rules-override"
    assert "Add apples" not in answer["reply"]
    assert "cardboard" in answer["reply"]
    get_settings.cache_clear()


def test_followup_rechecks_current_bin_and_refuses_exact_dose():
    history = [{"role": "user", "text": "Should I add apples?"}, {"role": "assistant", "text": "Yes, it was dry then."}]
    answer, model = asyncio.run(trunc.ask("And how much of it?", snapshot(CASES[0]), [], [], history))
    assert model == "rules-grounded"
    assert "exact amount" in answer["reply"] and "Hold off" in answer["reply"]


def test_unknown_lower_temperature_and_calibration_are_explicit():
    s = snapshot(CASES[3])
    s["layers"]["bottom"]["moisture_calibrated"] = False
    a = g.assess(s)
    assert "approximate" in g.summary(s)
    assert "look steady" not in a["action"]
    assert s["layers"]["bottom"]["temp_c"] is None


def test_cached_verdict_changes_when_lower_probe_requires_inspection():
    from app.services.binstate import state_hash
    s = snapshot(CASES[3])
    before = state_hash(s, "apples")
    s["layers"]["bottom"]["moisture_pct"] = 80
    assert state_hash(s, "apples") != before
