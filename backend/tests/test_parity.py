"""The Flutter app owns the rules and catalogs; these tests fail if the
backend drifts from it. Skipped when the app/ folder is not checked out.
"""

import json
import re
from pathlib import Path

import pytest

from app.catalog import collectibles, food
from app.rules import compost, game, gacha
from scripts import sync_catalogs

APP = Path(__file__).resolve().parents[2] / "app" / "lib"
pytestmark = pytest.mark.skipif(not APP.exists(), reason="app/ not checked out")


def dart(rel: str) -> str:
    return (APP / rel).read_text(encoding="utf-8")


def const(text: str, name: str) -> float:
    m = re.search(rf"\b{name}\s*=\s*([\d.]+)", text)
    assert m, f"{name} not found"
    return float(m.group(1))


def test_catalogs_match_the_app():
    app_food, app_coll = sync_catalogs.load()
    assert app_food == food.FOOD, "run: python -m scripts.sync_catalogs"
    assert app_coll == collectibles.COLLECTIBLES, "run: python -m scripts.sync_catalogs"


def test_vision_catalog_matches_the_app():
    path = sync_catalogs.VISION_CATALOG
    if not path.exists():
        pytest.skip("vision/ not checked out")
    app_food, _ = sync_catalogs.load()
    assert json.loads(path.read_text(encoding="utf-8")) == sync_catalogs.vision_catalog(app_food), "run: python -m scripts.sync_catalogs"


def test_xp_values_match_xp_rules_dart():
    src = dart("domain/xp_rules.dart")
    assert const(src, "followedSuggestion") == game.XP["followed_suggestion"]
    assert const(src, "avoidedBadAdd") == game.XP["avoided_bad_add"]
    assert const(src, "checkIn") == game.XP["check_in"]
    assert const(src, "healthyLayerDay") == game.XP["healthy_layer_day"]
    assert const(src, "weeklyBalance") == game.XP["weekly_balance"]
    assert const(src, "harvest") == game.XP["harvest"]
    assert const(src, "log") == game.XP["log"] == 0
    assert const(src, "dailyActionCap") == game.DAILY_ACTION_CAP
    assert const(src, "co2ePerKg") == game.CO2E_PER_KG


def test_health_bands_match_health_score_dart():
    src = dart("domain/health_score.dart")
    assert const(src, "moistureLo") == compost.MOISTURE_LO
    assert const(src, "moistureHi") == compost.MOISTURE_HI
    for key, name in (("moisture", "wMoisture"), ("temperature", "wTemperature"), ("co2", "wCo2"), ("balance", "wBalance")):
        assert const(src, name) == compost.WEIGHTS[key]


def test_gacha_numbers_match_gacha_dart():
    src = dart("domain/gacha.dart")
    assert const(src, "packetPrice") == gacha.PACKET_PRICE
    assert const(src, "tenPackPrice") == gacha.TEN_PACK_PRICE
    assert const(src, "epicPity") == gacha.EPIC_PITY
    assert const(src, "legendaryPity") == gacha.LEGENDARY_PITY
    odds_block = src[src.index("rarityOdds") : src.index("duplicateRefund")]
    refund_block = src[src.index("duplicateRefund") : src.index("packetPrice")]
    for rarity in gacha.RARITIES:
        odds = float(re.search(rf"Rarity\.{rarity}:\s*([\d.]+)", odds_block).group(1))
        refund = int(re.search(rf"Rarity\.{rarity}:\s*(\d+)", refund_block).group(1))
        assert odds == gacha.ODDS[rarity], rarity
        assert refund == gacha.DUPLICATE_REFUND[rarity], rarity


def test_quests_daily_goal_and_crates_match_game_dart():
    src = dart("state/game.dart")
    for q in game.QUESTS:
        assert re.search(rf"title:\s*'{re.escape(q['title'])}'[^)]*xp:\s*{q['xp']}[^)]*loam:\s*{q['loam']}", src), q["key"]
    assert re.search(r"dailyGoals\s*=\s*\[\s*" + r",\s*".join(str(g["xp"]) for g in game.DAILY_GOALS), src)
    for tier, c in game.CRATE_CONTENTS.items():
        assert re.search(rf"CrateTier\.{tier}\s*=>\s*\({c['loam']},\s*{c['packets']}\)", src), tier
    assert const(src, "lidLockPrice") == game.LID_LOCK_PRICE
    assert const(src, "maxLidLocks") == game.MAX_LID_LOCKS
