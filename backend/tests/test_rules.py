"""Pure rule tests (no database): compost, game, gacha."""

import random
from datetime import date, timedelta

from app import db
from app.rules import compost, gacha, game


# --- compost --------------------------------------------------------------

def test_band_score_edges():
    assert compost.band_score(50, 40, 60, 25) == 100
    assert compost.band_score(72.5, 40, 60, 25) == 50
    assert compost.band_score(10, 40, 60, 25) == 0


def test_moisture_pct_from_raw_counts():
    assert compost.moisture_pct(620, 620, 310) == 0
    assert compost.moisture_pct(310, 620, 310) == 100
    assert compost.moisture_pct(None, 620, 310) is None


def test_same_item_classification_uses_the_app_catalog():
    assert compost.categorise("Banana peel") == "green"
    assert compost.categorise("banana_peel") == "green"
    assert compost.categorise("Shredded cardboard") == "brown"
    assert compost.categorise("Eggshells") == "green"  # the app says green
    assert compost.categorise("Cheese & dairy") == "avoid"


def test_hard_avoids_match_whole_words_only():
    assert compost.categorise("olive oil") == "avoid"
    assert compost.categorise("chicken bones") == "avoid"
    assert compost.avoid_reason("potting soil") is None
    assert compost.avoid_reason("boiled potato") is None


def test_balance_and_stage():
    assert compost.balance_of(76, 8, 4) == "needs_browns"
    assert compost.balance_of(25, 2, 9) == "needs_greens"
    assert compost.balance_of(52, 3, 7) == "balanced"
    assert compost.stage(45, 21, 3000, 50) == "hot"
    assert compost.stage(21.5, 21, 600, 45, slope_pct_per_day=-10) == "ready"


# --- game -----------------------------------------------------------------

def test_logging_a_scrap_earns_nothing():
    assert game.XP["log"] == 0


def test_daily_action_cap():
    assert game.cap_xp(15, game.DAILY_ACTION_CAP - 5) == 5
    assert game.cap_xp(15, game.DAILY_ACTION_CAP) == 0
    assert "daily_quest" not in game.CAPPED_KINDS


def test_levels_and_titles_match_the_app():
    assert game.level_for_xp(0) == 1
    assert game.level_for_xp(2340) == 9
    assert game.title_for_level(9) == "Soil Whisperer"


def test_streaks_and_lid_lock_gaps():
    today = date(2026, 10, 17)
    days = [today - timedelta(days=d) for d in (1, 2, 3)]
    assert game.streak_lengths(days, today) == (3, 3)
    assert game.streak_lengths(days + [today], today) == (4, 4)
    # Missed yesterday and the day before: two days for Lid Locks to cover.
    gap = [today - timedelta(days=3)]
    assert game.missed_days_to_cover(gap + [today], today) == [today - timedelta(days=2), today - timedelta(days=1)]
    assert game.missed_days_to_cover([today - timedelta(days=1), today], today) == []


def test_league_zones():
    assert game.league_zone(7, 30, 2) == "promote"
    assert game.league_zone(8, 30, 2) == "safe"
    assert game.league_zone(26, 30, 2) == "demote"
    assert game.league_zone(30, 30, 0) == "safe"
    assert game.league_zone(1, 30, 5) == "safe"


def test_every_achievement_tier_pays_a_crate():
    for a in game.ACHIEVEMENTS:
        assert len(a["goals"]) == len(a["rewards"]) == 3
        assert all(r in game.CRATE_TIERS for r in a["rewards"])


# --- gacha -----------------------------------------------------------------

def test_odds_sum_to_one_and_every_rarity_has_items():
    assert abs(sum(gacha.ODDS.values()) - 1) < 1e-9
    for r in gacha.RARITIES:
        assert gacha.pick(random.Random(1), r)["rarity"] == r


def test_pity_forces_epic_and_legendary():
    rng = random.Random(1)
    assert gacha.rank(gacha.roll_rarity(rng, gacha.EPIC_PITY - 1, 0)[0]) >= gacha.rank("epic")
    assert gacha.roll_rarity(rng, 0, gacha.LEGENDARY_PITY - 1)[0] == "legendary"
    since = 0
    for _ in range(3000):
        rarity, _ = gacha.roll_rarity(rng, since, 0)
        since = 0 if gacha.rank(rarity) >= gacha.rank("epic") else since + 1
        assert since < gacha.EPIC_PITY


def test_ten_pull_has_a_rare_or_better():
    for seed in range(300):
        rolls, _, _ = gacha.roll(random.Random(seed), 10, 0, 0)
        assert any(gacha.rank(r) >= gacha.rank("rare") for r, _ in rolls)


# --- schema loader -----------------------------------------------------------

def test_statement_splitter_handles_quotes_and_do_blocks():
    sql = "CREATE TABLE a (x text DEFAULT 'a;b');\n-- comment; here\nDO $$ BEGIN PERFORM 1; END $$;\nSELECT $t$ ; $t$; SELECT 2"
    assert db.split_statements(sql) == [
        "CREATE TABLE a (x text DEFAULT 'a;b')",
        "DO $$ BEGIN PERFORM 1; END $$",
        "SELECT $t$ ; $t$",
        "SELECT 2",
    ]


def test_schema_files_apply_in_order():
    names = [p.name for p in db.schema_files()]
    assert names == sorted(names)
    assert names[0].startswith("000_") and names[-1].startswith("090_")
