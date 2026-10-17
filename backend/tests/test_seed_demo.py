"""scripts/seed_demo's economy and league seeding produce the player the app's
mock shows, and re-running it changes nothing."""

from scripts import seed_demo
from tests.conftest import needs_db

pytestmark = needs_db
USER = "demo-user"


async def _no_refresh(*views):
    return None


def test_seed_demo_economy_and_league(c, monkeypatch):
    monkeypatch.setattr(seed_demo, "refresh", _no_refresh)
    for _ in range(2):  # idempotent
        c.portal.call(seed_demo.seed_economy, USER)
    c.portal.call(seed_demo.seed_league, USER)

    p = c.get(f"/users/{USER}/game").json()
    assert p["streak_days"] == 12 and not p["cared_today"] and p["streak_at_risk"]
    assert p["lid_locks"] == 1 and p["packets"] == 1
    # 240 seeded + the 3- and 7-day streak milestones settled on first read.
    assert p["loam"] == 240 + 25 + 50
    col = c.get(f"/users/{USER}/collection").json()
    assert col["collected"] == 10
    crates = c.get(f"/users/{USER}/rewards").json()["crates"]
    assert {"sprout", "grove"} <= {cr["tier"] for cr in crates}

    league = c.get("/leagues/current", params={"user_id": USER}).json()
    assert league["size"] == 30 and league["tier"] == "Fern"
