"""Home, Greenhouse and Social use the same scoped server ledger."""
from tests.conftest import ingest_series, needs_db
from tests.test_social import account

pytestmark = needs_db


def test_player_game_and_economy_share_social_progress(c):
    uid, auth = account(c, 'garden_user')
    other_uid, other = account(c, 'other_garden')
    root = f'/users/{uid}'
    assert c.get(root + '/game', headers=auth).json()['total_xp'] == 0
    assert c.get(root + '/collection', headers=auth).status_code == 200
    assert c.get(root + '/rewards', headers=auth).json()['crates'] == []
    assert c.post('/social/check-in', headers=auth).json()['xp_awarded'] == 5
    assert c.post('/quests/checkin/claim', params={'user_id': uid}, headers=auth).json()['xp_awarded'] == 10
    assert c.post('/quests/checkin/claim', params={'user_id': uid}, headers=auth).status_code == 409
    assert c.post('/social/bin', headers=auth, json={'device_token': c.device_token}).status_code == 200
    ingest_series(c, moisture_raw=380, probe_temp=30, co2=900)
    body = {'catalog_id': 'banana_peel', 'action': 'added', 'quantity_g': 250, 'request_id': 'account-game-log'}
    assert c.post('/social/care-log', headers=auth, json=body).json()['xp_awarded'] == 12
    profile = c.get(root + '/game', headers=auth).json()
    assert profile['total_xp'] == c.get('/social/me', headers=auth).json()['progress']['total_xp']
    assert profile['impact']['kg_diverted'] == .25
    assert c.get('/bins/bin-001/logs', headers=auth).json()[0]['catalog_id'] == 'banana_peel'
    assert c.post(root + '/daily-goal/0/claim', headers=auth).status_code == 200
    assert c.post(root + '/daily-goal/0/claim', headers=auth).status_code == 409
    assert c.post(root + '/gacha/pull', headers=auth, json={'count': 1, 'paid_with': 'loam'}).status_code == 409
    # Ownership still applies to every newly allowed route.
    for path in ('/game', '/rewards', '/collection', '/daily-goal'):
        assert c.get(root + path, headers=other).status_code == 403
        assert c.get(root + path).status_code == 403
    for path in ('/daily-goal/0/claim', '/crates/1/open', '/gacha/pull', '/equip', '/lid-locks/buy'):
        assert c.post(root + path, headers=other, json={}).status_code == 403
    assert c.post('/quests/checkin/claim', params={'user_id': other_uid}, headers=auth).status_code == 403
    assert c.post('/bins/bin-001/harvest', headers=auth, json={'layer': 'top', 'yield_g': 1000}).status_code == 403
