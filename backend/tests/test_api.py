"""End-to-end API tests on a real Postgres (see conftest.py).

Covers the loop the app runs: readings -> live/trends -> advice (same scrap,
different answer) -> logging (care earns XP, volume never does) -> check-in,
streaks and Lid Locks -> quests -> daily goal -> crates -> Seed Packets ->
equipping -> leagues.
"""

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
    assert sum(i["copies"] for i in col["items"]) == 10
    assert col["collected"] == len({r["item"]["id"] for r in res["results"]})
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
