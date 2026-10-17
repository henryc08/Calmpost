import re
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest

from app import db
from app.catalog.collectibles import COLLECTIBLES
from app.rules import game, progression
from app.services import ledger
from tests.conftest import needs_db, run_sql
from tests.test_social import account


def test_progression_rules_and_dart_seed_parity():
    dart = (Path(__file__).parents[2] / 'app/lib/domain/progression.dart').read_text(encoding='utf-8')
    dart_buffs = {}
    for seed, effects in re.findall(r"'([^']+)': SeedBuff\('[^']+',\s*\[(.*?)\]", dart, re.S):
        dart_buffs[seed] = [
            (target, {key: int(value) for key, value in re.findall(r'(\w+):\s*(\d+)', values)})
            for target, values in re.findall(r"SeedEffect\('([^']+)'(.*?)\)", effects, re.S)
        ]
    assert dart_buffs == progression.SEED_BUFFS
    assert set(progression.SEED_BUFFS) == {c['id'] for c in COLLECTIBLES if c['type'] == 'specimen'}
    xp_dart = (Path(__file__).parents[2] / 'app/lib/domain/xp_rules.dart').read_text(encoding='utf-8')
    assert int(re.search(r'const xpPerLevel = (\d+)', xp_dart)[1]) == game.XP_PER_LEVEL == 120
    for level in range(1, 51):
        xp = (level - 1) * 120
        assert game.xp_for_level(level) == xp
        assert game.level_for_xp(xp) == level
        if level > 1:
            assert game.level_for_xp(xp - 1) == level - 1
    assert progression.level_reward(1) == {'loam': 20, 'packets': 0, 'crate': None, 'seed': 'sprout'}
    assert progression.level_reward(10) == {'loam': 65, 'packets': 0, 'crate': 'grove', 'seed': 'bloom'}
    assert progression.level_reward(3)['packets'] == 1
    assert game.level_for_xp(99999) == 50
    assert progression.seed_xp(15, 'followed_suggestion', 'firefern') == 20
    assert progression.seed_xp(15, 'compost_added', 'clover') == 15
    assert progression.seed_xp(10, 'daily_quest', 'sprout', quest='checkin') == 11
    assert progression.seed_xp(20, 'daily_quest', 'sprout', quest='follow') == 20
    assert progression.seed_xp(10, 'daily_quest', 'golden_sprout') == 16
    assert progression.seed_loam(25, 'daily_quest', 'bloom') == 31
    assert progression.seed_loam(100, 'level_reward', 'bloom') == 100
    for seed in progression.SEED_BUFFS:
        for kind in ('compost_added', 'harvest', 'level_reward', 'crate_open', 'healthy_layer_day'):
            assert progression.seed_xp(100, kind, seed) == 100
            assert progression.seed_loam(100, kind, seed) == 100
        assert progression.seed_xp(0, 'daily_quest', seed, quest='checkin') == 0
        assert progression.seed_loam(-100, 'daily_quest', seed, quest='checkin') == -100


@needs_db
def test_level_claims_are_atomic_retryable_and_scoped(c):
    uid, headers = account(c, 'trail')
    _, other = account(c, 'other')
    path = f'/users/{uid}/levels/1/claim'
    assert c.post(path).status_code == 403
    assert c.post(path, headers=other).status_code == 403
    assert c.post(f'/users/{uid}/levels/2/claim', headers=headers).status_code == 409
    assert c.post(f'/users/{uid}/levels/51/claim', headers=headers).status_code == 404
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(lambda _: c.post(path, headers=headers), range(4)))
    assert all(r.status_code == 200 for r in responses)
    assert sum(not r.json()['duplicate'] for r in responses) == 1
    profile = c.get(f'/users/{uid}/game', headers=headers).json()
    assert profile['loam'] == 20 and profile['total_xp'] == 0
    assert profile['level_claimed'] == [1]
    assert c.post(f'/users/{uid}/equip', headers=headers, json={'collectible_id': 'sprout'}).status_code == 200
    assert c.get(f'/users/{uid}/game', headers=headers).json()['equipped_seed'] == 'sprout'
    assert c.post(f'/users/{uid}/equip', headers=headers, json={'collectible_id': 'ghost_orchid'}).status_code == 409
    c.portal.call(run_sql, "INSERT INTO point_events(user_id,kind,xp) VALUES($1,'test',1080)", uid)
    for level in (3, 5, 10):
        path = f'/users/{uid}/levels/{level}/claim'
        assert not c.post(path, headers=headers).json()['duplicate']
        assert c.post(path, headers=headers).json()['duplicate']
    p = c.get(f'/users/{uid}/game', headers=headers).json()
    assert p['total_xp'] == 1080 and p['level'] == 10
    assert p['loam'] == 20 + 30 + 40 + 65
    assert p['packets'] == 1 and p['crates_waiting'] == 2


@needs_db
@pytest.mark.parametrize('seed,check_xp,quest_xp,loam', [
    ('sprout', 5, 11, 10), ('clover', 6, 10, 10), ('bloom', 5, 10, 12),
    ('acorn', 5, 10, 11), ('potted', 5, 11, 10), ('feather', 5, 12, 12),
    ('night_moss', 9, 14, 10), ('ghost_orchid', 5, 12, 16), ('golden_sprout', 5, 16, 12),
])
def test_owned_seed_buffs_pay_actual_rewards_once(c, seed, check_xp, quest_xp, loam):
    uid, headers = account(c, 'gardener')
    c.portal.call(run_sql, "INSERT INTO collection(user_id,collectible_id,copies) VALUES($1,$2,7)", uid, seed)
    assert c.post(f'/users/{uid}/equip', headers=headers, json={'collectible_id': seed}).status_code == 200
    assert c.post('/social/check-in', headers=headers).json()['xp_awarded'] == check_xp
    assert c.post('/social/check-in', headers=headers).json()['xp_awarded'] == 0
    claim = c.post(f'/quests/checkin/claim?user_id={uid}', headers=headers)
    assert claim.status_code == 200, claim.text
    assert claim.json() == {'quest': 'checkin', 'xp_awarded': quest_xp, 'loam_awarded': loam}
    assert c.post(f'/quests/checkin/claim?user_id={uid}', headers=headers).status_code == 409
    p = c.get(f'/users/{uid}/game', headers=headers).json()
    assert p['total_xp'] == check_xp + quest_xp and p['loam'] == loam


@needs_db
def test_specialized_quest_bonus_and_seed_switch_do_not_repay_old_rewards(c):
    uid, headers = account(c, 'specialist')
    for seed in ('firefern', 'sprout'):
        c.portal.call(run_sql, "INSERT INTO collection(user_id,collectible_id) VALUES($1,$2)", uid, seed)
    assert c.post(f'/users/{uid}/equip', headers=headers, json={'collectible_id': 'firefern'}).status_code == 200

    async def follow():
        async with db.pool().acquire() as conn:
            return await ledger.award(conn, uid, 'followed_suggestion', dedupe_key='test-follow')

    assert c.portal.call(follow) == 20
    assert c.post(f'/quests/follow/claim?user_id={uid}', headers=headers).json() == {
        'quest': 'follow', 'xp_awarded': 30, 'loam_awarded': 35,
    }
    assert c.post(f'/users/{uid}/equip', headers=headers, json={'collectible_id': 'sprout'}).status_code == 200
    assert c.portal.call(follow) == 0
    assert c.post(f'/quests/follow/claim?user_id={uid}', headers=headers).status_code == 409
    assert c.post('/social/check-in', headers=headers).json()['xp_awarded'] == 5
    assert c.post(f'/quests/checkin/claim?user_id={uid}', headers=headers).json()['xp_awarded'] == 11
    p = c.get(f'/users/{uid}/game', headers=headers).json()
    assert p['total_xp'] == 66 and p['loam'] == 45


@needs_db
def test_care_buff_obeys_cap_and_cannot_boost_volume(c):
    uid, headers = account(c, 'capped')
    c.portal.call(run_sql, "INSERT INTO collection(user_id,collectible_id) VALUES($1,'clover')", uid)
    c.post(f'/users/{uid}/equip', headers=headers, json={'collectible_id': 'clover'})

    async def volume():
        async with db.pool().acquire() as conn:
            return await ledger.award(conn, uid, 'compost_added', xp=58)

    assert c.portal.call(volume) == 58
    assert c.post('/social/check-in', headers=headers).json()['xp_awarded'] == 2
    assert c.post('/social/check-in', headers=headers).json()['xp_awarded'] == 0
    assert c.get(f'/users/{uid}/game', headers=headers).json()['action_xp_today'] == 60
