"""End-to-end API tests on a real Postgres (see conftest.py).

Covers the loop the app runs: readings -> live/trends -> advice (same scrap,
different answer) -> logging (care earns XP, volume never does) -> check-in,
streaks and Lid Locks -> quests -> daily goal -> crates -> Seed Packets ->
equipping -> leagues.
"""

import pytest
import json
from datetime import date, datetime, time, timedelta, timezone

from app.rules import game, gacha
from tests.conftest import ingest_series, needs_db, raw_for, run_sql

pytestmark = needs_db
USER = "demo-user"


def sql(c, query, *args):
    return c.portal.call(run_sql, query, *args)


def give_loam(c, n):
    sql(c, "INSERT INTO point_events (user_id, kind, loam) VALUES ($1, 'test_grant', $2)", USER, n)


def care_on(c, days_ago: int):
    at = datetime.combine(date.today() - timedelta(days=days_ago), time(12), tzinfo=timezone.utc)
    sql(c, "INSERT INTO point_events (time, user_id, kind, xp) VALUES ($1, $2, 'check_in', 5)", at, USER)


def profile(c):
    r = c.get(f"/users/{USER}/game")
    assert r.status_code == 200, r.text
    return r.json()


# --- sensors -----------------------------------------------------------------

def test_ingest_live_stats_and_trends(c):
    ingest_series(c, moisture_raw=raw_for(52), probe_temp=33, co2=2400)
    live = c.get("/bins/bin-001/live").json()
    top = next(layer for layer in live["layers"] if layer["layer"] == "top")
    bottom = next(layer for layer in live["layers"] if layer["layer"] == "bottom")
    assert abs(top["moisture_pct"] - 52) < 1 and top["moisture_state"] == "ok"
    assert bottom["measured"] is False and bottom["moisture_pct"] is None  # one probe: unknown, not 0
    assert live["health_components"]["moisture"] == 100
    assert c.get("/bins/bin-001/stats").json()["flowing"] is True
    trends = c.get("/bins/bin-001/trends", params={"hours": 24, "metrics": ["moisture"]}).json()
    assert trends["series"][0]["points"]


def test_ingest_rejects_a_token_for_another_bin(c):
    r = c.post("/ingest", headers={"X-Device-Token": c.device_token}, json={"device_id": "bin-999", "moisture_raw": 400})
    assert r.status_code == 403


# --- the demo moment -------------------------------------------------------------

def test_same_scrap_different_answer(c):
    ingest_series(c, moisture_raw=raw_for(25), probe_temp=24, co2=750, minutes=10)
    dry = c.post("/bins/bin-001/advice/check", json={"item": "Banana peel"}).json()
    assert dry["verdict"] == "great" and dry["model"] == "rules-fallback"

    ingest_series(c, moisture_raw=raw_for(76), probe_temp=31, co2=3900, minutes=0)
    wet = c.post("/bins/bin-001/advice/check", json={"item": "Banana peel"}).json()
    assert wet["verdict"] == "careful" and wet["pair_with"]
    assert dry["input_snapshot"]["layers"]["top"]["moisture_pct"] < wet["input_snapshot"]["layers"]["top"]["moisture_pct"]

    meat = c.post("/bins/bin-001/advice/check", json={"item": "leftover chicken"}).json()
    assert meat["verdict"] == "avoid" and meat["model"] == "rules-always-avoid"


# --- logging: care earns XP, volume never does -------------------------------------

def test_logging_rules(c):
    plain = c.post("/bins/bin-001/logs", json={"item": "Banana peel", "catalog_id": "banana_peel"}).json()
    assert plain["xp_awarded"] == 0 and plain["category"] == "green"
    assert plain["quantity_g"] == 110  # the catalog's typical weight

    tip = c.post("/bins/bin-001/logs", json={"item": "Shredded cardboard", "was_advised": True}).json()
    assert tip["xp_awarded"] == game.XP["followed_suggestion"]

    kept_out = c.post("/bins/bin-001/logs", json={"item": "Cheese & dairy", "action": "skipped"}).json()
    assert kept_out["xp_awarded"] == game.XP["avoided_bad_add"] and kept_out["category"] == "avoid"

    # Rules beat a wrong category from the client.
    sneaky = c.post("/bins/bin-001/logs", json={"item": "bacon", "category": "green", "was_advised": True}).json()
    assert sneaky["category"] == "avoid" and sneaky["xp_awarded"] == 0


# --- check-in, streaks, Lid Locks ---------------------------------------------------

def test_check_in_starts_a_streak_once_a_day(c):
    assert c.post(f"/users/{USER}/check-in").json()["xp_awarded"] == game.XP["check_in"]
    assert c.post(f"/users/{USER}/check-in").json()["xp_awarded"] == 0
    p = profile(c)
    assert p["streak_days"] == 1 and p["cared_today"] and date.today().isoformat() in p["care_days"]
    assert p["daily_goal"]["xp_today"] == 5


def test_lid_lock_covers_a_missed_day(c):
    for d in (3, 2):
        care_on(c, d)
    give_loam(c, 200)
    assert c.post(f"/users/{USER}/lid-locks/buy").status_code == 200
    assert profile(c)["lid_locks"] == 1

    c.post(f"/users/{USER}/check-in")  # today; yesterday was missed
    p = profile(c)
    assert p["streak_days"] == 4
    assert p["lid_locks"] == 0
    assert (date.today() - timedelta(days=1)).isoformat() in p["lock_days"]


def test_lid_lock_shop_limits(c):
    give_loam(c, 59)
    assert c.post(f"/users/{USER}/lid-locks/buy").status_code == 409  # not enough Loam
    give_loam(c, 200)
    assert c.post(f"/users/{USER}/lid-locks/buy").status_code == 200
    assert c.post(f"/users/{USER}/lid-locks/buy").status_code == 200
    assert c.post(f"/users/{USER}/lid-locks/buy").status_code == 409  # max 2


# --- quests and the daily goal ---------------------------------------------------------

def test_quests_are_claimed_not_auto_paid(c):
    quests = {q["key"]: q for q in c.get("/quests/today", params={"user_id": USER}).json()["quests"]}
    assert set(quests) == {"checkin", "follow", "healthy"} and not quests["checkin"]["done"]

    c.post(f"/users/{USER}/check-in")
    assert c.post("/quests/checkin/claim", params={"user_id": USER}).json() == {"quest": "checkin", "xp_awarded": 10, "loam_awarded": 10}
    assert c.post("/quests/checkin/claim", params={"user_id": USER}).status_code == 409
    assert c.post("/quests/follow/claim", params={"user_id": USER}).status_code == 409
    assert profile(c)["loam"] == 10


def test_daily_goal_rewards(c):
    c.post(f"/users/{USER}/check-in")  # 5
    c.post("/quests/checkin/claim", params={"user_id": USER})  # 10
    c.post("/bins/bin-001/logs", json={"item": "Shredded cardboard", "was_advised": True})  # 15
    goal = c.get(f"/users/{USER}/daily-goal").json()
    assert goal["xp_today"] == 30 and goal["goals"][0]["reached"] and not goal["goals"][1]["reached"]

    assert c.post(f"/users/{USER}/daily-goal/0/claim").json()["loam_awarded"] == 15
    assert c.post(f"/users/{USER}/daily-goal/0/claim").status_code == 409
    assert c.post(f"/users/{USER}/daily-goal/1/claim").status_code == 409


# --- crates, achievements, streak milestones ---------------------------------------------

def test_streak_milestone_and_achievement_pay_crates(c):
    for d in range(1, 8):
        care_on(c, d)
    rewards = c.get(f"/users/{USER}/rewards").json()
    tiers = sorted(cr["tier"] for cr in rewards["crates"])
    assert tiers == ["sprout", "sprout"]  # Hot Streak tier 1 + the 7-day milestone
    p = profile(c)
    assert p["loam"] == 25 + 50  # 3- and 7-day milestones
    assert p["crates_waiting"] == 2
    assert next(a for a in p["achievements"] if a["id"] == "hot_streak")["tier"] == 1

    # Settling again pays nothing twice.
    c.get(f"/users/{USER}/rewards")
    assert profile(c)["crates_waiting"] == 2

    crate_id = rewards["crates"][0]["id"]
    opened = c.post(f"/users/{USER}/crates/{crate_id}/open").json()
    assert opened["loam"] == 60 and opened["packets"] == 1
    assert c.post(f"/users/{USER}/crates/{crate_id}/open").status_code == 409
    p = profile(c)
    assert p["packets"] == 1 and p["loam"] == 75 + 60


# --- Seed Packets, collection, equipping ----------------------------------------------------

def test_pulls_spend_correctly_and_grow_the_collection(c):
    assert c.post(f"/users/{USER}/gacha/pull", json={"count": 1, "paid_with": "packet"}).status_code == 409
    assert c.post(f"/users/{USER}/gacha/pull", json={"count": 10, "paid_with": "loam"}).status_code == 409

    give_loam(c, 1000)
    res = c.post(f"/users/{USER}/gacha/pull", json={"count": 10, "paid_with": "loam"}).json()
    assert len(res["results"]) == 10 and res["cost_loam"] == gacha.TEN_PACK_PRICE
    assert any(gacha.rank(r["rarity"]) >= gacha.rank("rare") for r in res["results"])

    col = c.get(f"/users/{USER}/collection").json()
    assert col["loam"] == 1000 - 900 + res["refund_loam"]
    assert sum(i["copies"] for i in col["items"]) == 10 + 1  # + the starter finish
    assert col["collected"] == len({r["item"]["id"] for r in res["results"]} | {game.STARTER_FINISH})
    assert col["pity"]["epic_within"] == res["pity"]["epic_within"]


def test_equip_finish_and_title(c):
    sql(c, "INSERT INTO user_state (user_id) VALUES ($1) ON CONFLICT DO NOTHING", USER)
    sql(c, "INSERT INTO collection (user_id, collectible_id) VALUES ($1, 'finish_gold'), ($1, 'title_sage')", USER)
    assert c.post(f"/users/{USER}/equip", json={"collectible_id": "finish_gold"}).status_code == 200
    assert c.post(f"/users/{USER}/equip", json={"collectible_id": "title_sage"}).status_code == 200
    assert c.post(f"/users/{USER}/equip", json={"collectible_id": "finish_aurora"}).status_code == 409  # not owned
    assert c.post(f"/users/{USER}/equip", json={"collectible_id": "fern"}).status_code == 422  # plants aren't equipped
    p = profile(c)
    assert p["equipped_finish"] == "finish_gold" and p["title"] == "Loam Sage" and p["level_title"] == "Scrap Saver"


# --- harvest and leagues -------------------------------------------------------------

def test_harvest_pays_xp_and_loam(c):
    ingest_series(c, moisture_raw=raw_for(46), probe_temp=21.4, co2=500, minutes=10)
    r = c.post("/bins/bin-001/harvest", json={"layer": "top"}).json()
    assert r["xp_awarded"] == game.XP["harvest"] and r["loam_awarded"] == game.LOAM["harvest"]


def test_league_table_and_last_weeks_finish(c):
    from app.services.economy import week_start

    this_week, last_week = week_start(), week_start() - timedelta(days=7)
    for tier, start in (("Fern", this_week), ("Fern", last_week)):
        sql(c, "INSERT INTO leagues (tier, week_start) VALUES ($1, $2)", tier, start)
    sql(
        c,
        """
        INSERT INTO league_members (league_id, user_id, display_name, is_bot)
        SELECT l.id, m.user_id, m.name, m.user_id <> $1
        FROM leagues l CROSS JOIN (VALUES ($1, 'Me'), ('bot-a', 'Ana'), ('bot-b', 'Ben')) AS m(user_id, name)
        """,
        USER,
    )
    last = datetime.combine(last_week + timedelta(days=2), time(12), tzinfo=timezone.utc)
    sql(c, "INSERT INTO point_events (time, user_id, kind, xp) VALUES ($1, $2, 'check_in', 500)", last, USER)
    sql(c, "INSERT INTO point_events (user_id, kind, xp) VALUES ('bot-a', 'check_in', 40), ($1, 'check_in', 15)", USER)

    league = c.get("/leagues/current", params={"user_id": USER}).json()
    assert league["tier"] == "Fern" and league["size"] == 3
    assert league["your_rank"] == 2 and league["members"][1]["display_name"] == "You"

    # Last week I came first in a 3-person Fern league: promotion zone, 150 Loam.
    p = profile(c)
    assert p["loam"] == game.LEAGUE_FINISH_LOAM["promote"]
    assert next(a for a in p["achievements"] if a["id"] == "climber")["progress"] == 1


def test_economy_rules_endpoint(c):
    r = c.get("/economy/rules").json()
    assert r["prices"]["packet"] == 100 and r["pity"]["legendary"] == 80


# --- found in the live run against Tiger ---------------------------------------------

def test_rules_override_a_gemini_verdict_that_disagrees(c, monkeypatch):
    """Gemini once called a banana peel 'avoid' because the layer was curing.
    For a catalogue item the rules' verdict stands (AGENTS.md key idea 5)."""
    from app.config import get_settings
    from app.services import advisor

    async def gemini_says_avoid(body):
        return {"verdict": "avoid", "headline": "Hold off", "reason": "The top layer is curing.",
                "pair_with": [], "suggest_add": [], "suggest_avoid": [], "balance": "balanced",
                "stage_top": "curing", "stage_bottom": "started", "bottom_ready": False, "tip": ""}

    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    get_settings.cache_clear()
    monkeypatch.setattr(advisor, "_ask_gemini", gemini_says_avoid)
    ingest_series(c, moisture_raw=raw_for(25), probe_temp=24, co2=750, minutes=10)
    r = c.post("/bins/bin-001/advice/check", json={"item": "Banana peel"}, params={"refresh": "true"}).json()
    assert r["verdict"] == "great" and r["model"] == "rules-override"

    # Outside the catalogue, the model's answer is used.
    r = c.post("/bins/bin-001/advice/check", json={"item": "durian rind"}, params={"refresh": "true"}).json()
    assert r["verdict"] == "avoid" and r["model"] != "rules-override"


def test_starter_finish_can_always_be_re_equipped(c):
    c.post(f"/users/{USER}/check-in")  # creates the player
    sql(c, "INSERT INTO collection (user_id, collectible_id) VALUES ($1, 'finish_gold')", USER)
    assert c.post(f"/users/{USER}/equip", json={"collectible_id": "finish_gold"}).status_code == 200
    assert c.post(f"/users/{USER}/equip", json={"collectible_id": "finish_classic"}).status_code == 200
    assert profile(c)["equipped_finish"] == "finish_classic"


def test_the_model_is_given_the_items_that_actually_went_in(c, monkeypatch):
    """The prompt promises "a log of what was recently added". It used to get
    only greens_7d/browns_7d cup totals, so it could not name anything."""
    from app.config import get_settings
    from app.services import advisor

    seen: dict = {}

    async def capture(body):
        seen["text"] = body["contents"][0]["parts"][0]["text"]
        return {"verdict": "great", "headline": "Good add", "reason": "Fine.",
                "pair_with": [], "suggest_add": [], "suggest_avoid": [], "balance": "balanced",
                "stage_top": "active", "stage_bottom": "started", "bottom_ready": False, "tip": ""}

    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    get_settings.cache_clear()
    monkeypatch.setattr(advisor, "_ask_gemini", capture)

    ingest_series(c, moisture_raw=raw_for(50), probe_temp=30, co2=1500, minutes=10)
    c.post("/bins/bin-001/logs", json={"item": "Coffee grounds", "category": "green"})
    c.post("/bins/bin-001/logs", json={"item": "Cheese", "category": "avoid", "action": "skipped"})

    c.post("/bins/bin-001/advice/check", json={"item": "Banana peel"}, params={"refresh": "true"})

    payload = json.loads(seen["text"].split("Bin state as JSON:\n", 1)[1].rsplit("\n\n", 1)[0])
    adds = payload["recent_adds"]
    assert [a["item"] for a in adds] == ["Cheese", "Coffee grounds"], "newest first"
    assert adds[0]["action"] == "skipped", "a kept-out item is part of the history"
    assert adds[1]["category"] == "green"
    assert all(a["hours_ago"] >= 0 for a in adds)


def test_recent_adds_is_empty_rather_than_absent_for_a_fresh_bin(c, monkeypatch):
    """An empty list tells the model to say nothing about recent additions;
    a missing key would leave it guessing from the cup totals."""
    from app.config import get_settings
    from app.services import advisor

    seen: dict = {}

    async def capture(body):
        seen["text"] = body["contents"][0]["parts"][0]["text"]
        return {"verdict": "great", "headline": "Good add", "reason": "Fine.",
                "pair_with": [], "suggest_add": [], "suggest_avoid": [], "balance": "balanced",
                "stage_top": "active", "stage_bottom": "started", "bottom_ready": False, "tip": ""}

    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    get_settings.cache_clear()
    monkeypatch.setattr(advisor, "_ask_gemini", capture)

    ingest_series(c, moisture_raw=raw_for(50), probe_temp=30, co2=1500, minutes=10)
    c.post("/bins/bin-001/advice/check", json={"item": "Banana peel"}, params={"refresh": "true"})

    payload = json.loads(seen["text"].split("Bin state as JSON:\n", 1)[1].rsplit("\n\n", 1)[0])
    assert payload["recent_adds"] == []


# --- second moisture probe -------------------------------------------------------
#
# The firmware now sends both probes in one sample. Probe 1 is the top layer,
# probe 2 the bottom; probe_temp_c_2 arrives null today because the second
# probe reports moisture but not temperature.

NEW_FORMAT = {
    "device_id": "bin-001", "probe_temp_c": 22.25, "moisture_raw": 464,
    "probe_temp_c_2": None, "moisture_raw_2": 482,
    "co2_ppm": 1498, "air_temp_c": 22.67, "air_humidity_pct": 40.83, "co2_status": 0,
}


def post_reading(c, body):
    return c.post("/ingest", headers={"X-Device-Token": c.device_token}, json=body)


def test_the_new_firmware_payload_is_accepted_verbatim(c):
    r = post_reading(c, NEW_FORMAT)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["accepted"] is True
    # Both probes get a percentage, each from its own calibration.
    assert body["moisture_pct"] is not None
    assert body["moisture_pct_2"] is not None


def test_the_second_probe_makes_the_bottom_layer_measured(c):
    """It used to be hardcoded unmeasured: "No second probe in this build"."""
    post_reading(c, NEW_FORMAT)

    live = c.get("/bins/bin-001/live").json()
    bottom = [l for l in live["layers"] if l["layer"] == "bottom"][0]

    assert bottom["measured"] is True
    assert bottom["moisture_raw"] == 482
    assert bottom["moisture_pct"] is not None
    assert bottom["moisture_state"] in ("dry", "ok", "wet")
    # Moisture alone is enough to count as measured; temperature is still null.
    assert bottom["temp_c"] is None

    top = [l for l in live["layers"] if l["layer"] == "top"][0]
    assert top["moisture_raw"] == 464, "probe 1 still drives the top layer"


def test_a_sample_without_the_second_probe_leaves_the_bottom_unknown(c):
    """The old payload must keep working: nothing should imply 0."""
    old = {k: v for k, v in NEW_FORMAT.items() if not k.endswith("_2")}
    assert post_reading(c, old).status_code == 200

    bottom = [l for l in c.get("/bins/bin-001/live").json()["layers"]
              if l["layer"] == "bottom"][0]
    assert bottom["measured"] is False
    assert bottom["moisture_pct"] is None
    assert bottom["moisture_state"] == "unknown"


def test_each_probe_calibrates_separately(c):
    """Different physical sensors, different dry/wet counts. Sharing probe 1's
    would quietly mis-scale probe 2 -- the 10-bit ADC bug again."""
    post_reading(c, NEW_FORMAT)

    # Probe 2 reads 482. Calibrate it so that lands mid-range.
    r = c.post("/bins/bin-001/calibration",
               json={"moisture_raw_dry": 600, "moisture_raw_wet": 300, "probe": 2})
    assert r.status_code == 200 and r.json()["probe"] == 2
    assert r.json()["readings_recomputed"] >= 1, "history replayed"

    layers = {l["layer"]: l for l in c.get("/bins/bin-001/live").json()["layers"]}
    # (600-482)/(600-300) = 39.3%
    assert layers["bottom"]["moisture_pct"] == pytest.approx(39.3, abs=0.5)

    # Probe 1 must be untouched by that call.
    before = layers["top"]["moisture_pct"]
    c.post("/bins/bin-001/calibration",
           json={"moisture_raw_dry": 475, "moisture_raw_wet": 177, "probe": 1})
    after = {l["layer"]: l for l in c.get("/bins/bin-001/live").json()["layers"]}
    assert after["bottom"]["moisture_pct"] == pytest.approx(39.3, abs=0.5), \
        "calibrating probe 1 must not move probe 2"
    assert after["top"]["moisture_pct"] != before


def test_a_resend_of_the_same_timestamp_fills_the_second_probe_in(c):
    """ON CONFLICT must cover the new columns, or a bridge retry would drop
    whichever probe arrived second."""
    ts = "2026-10-17T20:00:00+00:00"
    first = {k: v for k, v in NEW_FORMAT.items() if not k.endswith("_2")}
    assert post_reading(c, {**first, "time": ts}).status_code == 200
    assert post_reading(c, {**NEW_FORMAT, "time": ts}).status_code == 200

    # Asserted through the live view rather than SQL: run_sql wraps
    # conn.execute, which returns a status string rather than rows.
    layers = {l["layer"]: l for l in c.get("/bins/bin-001/live").json()["layers"]}
    assert layers["top"]["moisture_raw"] == 464, "probe 1 survived the resend"
    assert layers["bottom"]["moisture_raw"] == 482, "probe 2 was filled in"


def test_an_out_of_range_second_probe_is_rejected(c):
    bad = {**NEW_FORMAT, "moisture_raw_2": 99999}
    assert post_reading(c, bad).status_code == 422
    assert post_reading(c, {**NEW_FORMAT, "probe_temp_c_2": 500}).status_code == 422
