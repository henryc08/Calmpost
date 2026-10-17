import asyncio

import pytest
from fastapi.testclient import TestClient

from app.advice import rules
from app.advice.gemini import GeminiUnavailable
from app.advice.models import Advice, Balance, Stage, Verdict
from app.advice.service import check_scrap
from app.bins import ScenarioBinSource
from app.main import app


def snap(scenario: str):
    return asyncio.run(ScenarioBinSource(scenario).snapshot("bin-1"))


async def no_gemini(scrap, s):
    raise GeminiUnavailable("test")


def run(scrap, scenario, gemini=no_gemini):
    return asyncio.run(check_scrap(scrap, snap(scenario), gemini=gemini))


# --- demo moment: same scrap, different answer ---------------------------------

def test_banana_add_when_dry():
    assert run("banana peel", "too_dry").verdict == Verdict.add


def test_banana_needs_browns_when_wet():
    r = run("banana peel", "too_wet")
    assert r.verdict == Verdict.add_with_browns
    assert "74%" in r.reason


def test_ready_scenario_bottom_ready():
    r = run("banana peel", "ready")
    assert r.bottom_ready is True and r.stage_bottom == Stage.ready


def test_not_ready_when_active():
    assert run("banana peel", "healthy").bottom_ready is False


# --- hard rules -----------------------------------------------------------------

@pytest.mark.parametrize("scrap", ["chicken bones", "Cheese", "leftover fried rice", "olive oil", "salmon skin"])
def test_hard_avoid(scrap):
    assert run(scrap, "too_dry").verdict == Verdict.avoid


def test_hard_rule_overrides_gemini():
    async def bad_gemini(scrap, s):
        return Advice(verdict=Verdict.add, reason="sure", suggest_add=[], suggest_avoid=[],
                      balance=Balance.balanced, stage_top=Stage.active, stage_bottom=Stage.curing,
                      bottom_ready=False, tip="x")
    r = run("cheese", "healthy", gemini=bad_gemini)
    assert r.verdict == Verdict.avoid and r.source == "gemini"


def test_gemini_answer_used_and_trimmed():
    async def ok_gemini(scrap, s):
        return Advice(verdict=Verdict.add_with_browns, reason="I'm soggy", suggest_add=list("abcde"),
                      suggest_avoid=[], balance=Balance.needs_browns, stage_top=Stage.active,
                      stage_bottom=Stage.curing, bottom_ready=False, tip="t")
    r = run("apple core", "too_wet", gemini=ok_gemini)
    assert r.source == "gemini" and r.reason == "I'm soggy" and len(r.suggest_add) == 3


def test_fallback_marks_source_rules():
    assert run("apple core", "healthy").source == "rules"


# --- pieces -------------------------------------------------------------------

def test_classify():
    assert rules.classify("shredded cardboard") == "brown"
    assert rules.classify("egg carton") == "brown"
    assert rules.classify("coffee grounds") == "green"
    assert rules.classify("mystery thing") == "unknown"


def test_balance():
    s = snap("healthy")
    assert rules.balance_of(s.model_copy(update={"greens_7d": 5, "browns_7d": 5})) == Balance.needs_browns
    assert rules.balance_of(s.model_copy(update={"greens_7d": 2, "browns_7d": 10})) == Balance.needs_greens
    assert rules.balance_of(s.model_copy(update={"greens_7d": 4, "browns_7d": 10})) == Balance.balanced


def test_brown_in_wet_bin_is_add():
    assert run("shredded cardboard", "too_wet").verdict == Verdict.add


# --- API ----------------------------------------------------------------------

def test_endpoint_switches_with_scenario(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    c = TestClient(app)
    c.post("/debug/scenario", json={"scenario": "too_dry"})
    a = c.post("/bins/bin-1/advice/check", json={"scrap": "banana peel"}).json()
    c.post("/debug/scenario", json={"scenario": "too_wet"})
    b = c.post("/bins/bin-1/advice/check", json={"scrap": "banana peel"}).json()
    assert a["verdict"] == "add" and b["verdict"] == "add_with_browns"
    assert a["snapshot"]["top"]["moisture_pct"] != b["snapshot"]["top"]["moisture_pct"]


def test_endpoint_rejects_bad_scenario():
    assert TestClient(app).post("/debug/scenario", json={"scenario": "nope"}).status_code == 400


def test_endpoint_rejects_empty_scrap():
    assert TestClient(app).post("/bins/b/advice/check", json={"scrap": ""}).status_code == 422
