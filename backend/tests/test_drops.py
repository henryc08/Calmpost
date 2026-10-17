"""End-to-end tests for the /drops router against a real Postgres.

Set TEST_DATABASE_URL to a throwaway database; every test wipes it. Skipped
when unset. Runs on plain Postgres: the TimescaleDB-only statements in
schema.sql and drops.sql (hypertables, rollups, policies) are skipped, and
the tables are otherwise exactly what the app creates.
"""

import base64
import json
import os
from contextlib import asynccontextmanager

import asyncpg
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app import db
from app.models import AdviceResponse
from app.routers import advice, bins, drops

TEST_DB = os.environ.get("TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not TEST_DB, reason="TEST_DATABASE_URL not set")

KEY = {"X-API-Key": "dev-change-me"}
TIMESCALE_ONLY = ("timescaledb", "create_hypertable", "add_retention_policy", "add_continuous_aggregate_policy",
                  "add_columnstore_policy", "add_compression_policy", "MATERIALIZED VIEW", "refresh_continuous")
JPEG = base64.b64encode(b"\xff\xd8\xff\xe0fake-jpeg\xff\xd9").decode()


async def _apply(conn, path):
    for stmt in db._split_statements(path.read_text(encoding="utf-8")):
        if not any(t in stmt for t in TIMESCALE_ONLY):
            await conn.execute(stmt)


@asynccontextmanager
async def lifespan(app):
    db._pool = await asyncpg.create_pool(
        TEST_DB, min_size=1, max_size=5,
        init=lambda c: c.set_type_codec("jsonb", encoder=db._dump_json, decoder=json.loads, schema="pg_catalog"))
    async with db.pool().acquire() as conn:
        await conn.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
        await _apply(conn, db.SCHEMA_PATH)
        await _apply(conn, drops.DROPS_SQL)
        await _apply(conn, drops.DROPS_SQL)  # twice: must be idempotent
    yield
    await db.disconnect()


test_app = FastAPI(lifespan=lifespan)
for r in (bins.router, drops.router):
    test_app.include_router(r)


@pytest.fixture
def c(monkeypatch):
    monkeypatch.setenv("APP_API_KEY", "dev-change-me")
    from app.config import get_settings
    get_settings.cache_clear()
    with TestClient(test_app, headers=KEY) as client:
        r = client.post("/bins", json={"bin_id": "bin-001", "owner_id": "eesha"})
        assert r.status_code == 201, r.text
        yield client


def arm(c):
    r = c.post("/bins/bin-001/drops/session")
    assert r.status_code == 201
    return r.json()["session_id"]


def report(c, sid, items=None, **kw):
    body = {"session_id": sid, "items": items if items is not None else [
        {"label": "banana peel", "catalog_id": "banana_peel", "category": "green", "est_grams": 110,
         "amount": "handful", "confidence": 0.82, "box_2d": [480, 440, 610, 650]}],
        "thumbnail_jpeg_b64": JPEG, "latency_ms": 2100, "gemini_ok": True, "model": "gemini-2.5-flash", **kw}
    return c.post("/bins/bin-001/drops", json=body)


# --- auth & sessions ------------------------------------------------------------

def test_requires_api_key(c):
    assert c.post("/bins/bin-001/drops/session", headers={"X-API-Key": "wrong"}).status_code == 401


def test_arm_and_poll(c):
    assert c.get("/bins/bin-001/drops/session/active").status_code == 204
    sid = arm(c)
    assert c.get("/bins/bin-001/drops/session/active").json()["session_id"] == sid
    assert c.get(f"/bins/bin-001/drops/sessions/{sid}").json()["open"] is True


def test_rearm_replaces_session(c):
    a, b = arm(c), arm(c)
    assert c.get("/bins/bin-001/drops/session/active").json()["session_id"] == b
    assert c.get(f"/bins/bin-001/drops/sessions/{a}").json()["close_reason"] == "replaced"


def test_unknown_bin_and_session(c):
    assert c.post("/bins/nope/drops/session").status_code == 404
    assert report(c, "nosuch").status_code == 404


def test_no_motion_close(c):
    sid = arm(c)
    assert c.post(f"/bins/bin-001/drops/session/{sid}/close", json={"reason": "no_motion"}).status_code == 200
    assert c.get("/bins/bin-001/drops/session/active").status_code == 204
    assert c.get(f"/bins/bin-001/drops/sessions/{sid}").json()["close_reason"] == "no_motion"


# --- report -------------------------------------------------------------------------

def test_report_creates_pending_and_closes_session(c):
    sid = arm(c)
    r = report(c, sid)
    assert r.status_code == 201 and r.json()["status"] == "pending"
    assert c.get("/bins/bin-001/drops/session/active").status_code == 204
    p = c.get("/bins/bin-001/drops/pending").json()
    assert len(p) == 1 and p[0]["items"][0]["label"] == "banana peel"
    assert base64.b64decode(p[0]["thumbnail_jpeg_b64"]).startswith(b"\xff\xd8")


def test_rules_override_camera_category(c):
    sid = arm(c)
    report(c, sid, items=[{"label": "chicken bones", "catalog_id": "unknown", "category": "green", "confidence": 0.9},
                          {"label": "shredded cardboard", "catalog_id": "cardboard", "confidence": 0.7}])
    items = c.get("/bins/bin-001/drops/pending").json()[0]["items"]
    assert items[0]["category"] == "avoid"      # rules win over the camera
    assert items[1]["category"] == "brown"      # rules fill in a missing category


def test_gemini_failure_still_reported(c):
    sid = arm(c)
    r = report(c, sid, items=[], gemini_ok=False, error="timed out after 4s")
    assert r.status_code == 201
    p = c.get("/bins/bin-001/drops/pending").json()[0]
    assert p["gemini_ok"] is False and p["items"] == []


def test_bad_payloads(c):
    sid = arm(c)
    assert report(c, sid, items=[{"label": "x", "confidence": 3}]).status_code == 422
    assert report(c, sid, thumbnail_jpeg_b64="not base64!!").status_code == 422
    big = base64.b64encode(b"x" * 300_000).decode()
    assert report(c, sid, thumbnail_jpeg_b64=big).status_code == 413


# --- confirm / dismiss -----------------------------------------------------------

def test_confirm_logs_camera_add_with_zero_xp(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    r = c.post(f"/drops/{drop_id}/confirm", json={"items": [
        {"label": "banana peel", "catalog_id": "banana_peel", "category": "green", "amount": "handful"}]})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["corrected"] is False
    log = body["items"][0]["log"]
    assert log["source"] == "camera" and log["xp_awarded"] == 0 and log["quantity_g"] == 110
    assert body["items"][0]["verdict"] is None  # no readings yet in this test DB
    logs = c.get("/bins/bin-001/logs").json()
    assert logs[0]["source"] == "camera"
    assert c.get("/bins/bin-001/drops/pending").json() == []


def test_confirm_twice_is_rejected(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    item = {"items": [{"label": "banana peel", "catalog_id": "banana_peel", "category": "green"}]}
    assert c.post(f"/drops/{drop_id}/confirm", json=item).status_code == 200
    assert c.post(f"/drops/{drop_id}/confirm", json=item).status_code == 409
    assert len(c.get("/bins/bin-001/logs").json()) == 1


def test_removed_keep_out_item_earns_skip_xp(c):
    sid = arm(c)
    drop_id = report(c, sid, items=[{"label": "cheese", "catalog_id": "cheese", "confidence": 0.8}]).json()["drop_id"]
    r = c.post(f"/drops/{drop_id}/confirm", json={"items": [
        {"label": "cheese", "catalog_id": "cheese", "category": "green", "removed": True}]}).json()
    log = r["items"][0]["log"]
    assert log["category"] == "avoid" and log["action"] == "skipped" and log["xp_awarded"] == 5


def test_correction_becomes_hint(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    r = c.post(f"/drops/{drop_id}/confirm", json={"items": [
        {"label": "apple core", "catalog_id": "apple_core", "category": "green"}]}).json()
    assert r["corrected"] is True
    assert c.get("/bins/bin-001/drops/hints").json()["hints"] == ['looked like "banana peel", was "apple core"']


def test_dismiss_and_accuracy(c):
    d1 = report(c, arm(c)).json()["drop_id"]
    d2 = report(c, arm(c)).json()["drop_id"]
    c.post(f"/drops/{d1}/confirm", json={"items": [{"label": "banana peel", "catalog_id": "banana_peel"}]})
    assert c.post(f"/drops/{d2}/dismiss").json()["status"] == "dismissed"
    assert c.post(f"/drops/{d2}/dismiss").status_code == 409
    a = c.get("/bins/bin-001/drops/accuracy").json()
    assert (a["drops"], a["confirmed"], a["dismissed"], a["confirmed_as_seen_pct"]) == (2, 1, 1, 100)
    assert any("false trigger" in h for h in c.get("/bins/bin-001/drops/hints").json()["hints"])


def test_confirm_returns_verdict_when_available(c, monkeypatch):
    async def fake_advise(bin_id, item, refresh):
        return AdviceResponse.model_construct(verdict="great", item=item, reason="dry bin, wet scrap")
    monkeypatch.setattr(advice, "_advise", fake_advise)
    drop_id = report(c, arm(c)).json()["drop_id"]
    r = c.post(f"/drops/{drop_id}/confirm", json={"items": [
        {"label": "banana peel", "catalog_id": "banana_peel", "category": "green"}]}).json()
    assert r["items"][0]["verdict"]["verdict"] == "great"
