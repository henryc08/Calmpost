"""Two demo accounts share physical readings, never private account ledgers."""
from concurrent.futures import ThreadPoolExecutor

from app import db
from app.services import binstate, economy
from tests.conftest import needs_db, ingest_series
from tests.test_social import account
from tests.test_drops import JPEG

pytestmark = needs_db


def pair(c, auth, token=None):
    return c.post('/social/bin', headers=auth, json={'device_token': token or c.device_token})


def test_two_accounts_share_sensors_not_private_progress(c):
    alice, a = account(c, 'alice')
    bob, b = account(c, 'bob')
    _, stranger = account(c, 'eve')
    assert pair(c, a).status_code == 200
    assert pair(c, b, 'wrong-token').status_code == 404
    assert pair(c, b).status_code == 200
    assert pair(c, b).status_code == 200  # Safe retry, no ownership transfer.
    assert pair(c, a).status_code == 200
    assert pair(c, stranger).status_code == 409
    assert c.portal.call(db.fetchval, 'SELECT owner_id FROM bins WHERE bin_id=$1', 'bin-001') == alice
    ingest_series(c, moisture_raw=380, probe_temp=30, co2=900)
    for auth in (a, b):
        assert c.get('/social/me', headers=auth).json()['bin_id'] == 'bin-001'
        for path in ('live', 'trends?hours=24&metrics=moisture', 'stats', 'logs', 'advice', 'drops/history'):
            assert c.get('/bins/bin-001/' + path, headers=auth).status_code == 200
    login = c.post('/social/login', json={'handle': 'bob', 'password': 'compost-test-password'})
    assert c.get('/social/me', headers={'Authorization': 'Bearer ' + login.json()['token']}).json()['bin_id'] == 'bin-001'
    assert c.get('/bins/bin-001/live', headers=stranger).status_code == 403
    assert c.get('/bins/bin-001/live').status_code == 403
    for auth, other in ((a, bob), (b, alice)):
        for path in ('game', 'rewards', 'collection', 'daily-goal'):
            assert c.get(f'/users/{other}/{path}', headers=auth).status_code == 403
        assert c.post(f'/users/{other}/gacha/pull', headers=auth, json={'count': 1, 'paid_with': 'loam'}).status_code == 403
        assert c.post('/quests/checkin/claim', headers=auth, params={'user_id': other}).status_code == 403
    calibration = {'probe': 1, 'moisture_raw_dry': 620, 'moisture_raw_wet': 310}
    assert c.post('/bins/bin-001/calibration', headers=b, json=calibration).status_code == 403
    # Same client request id is independent on each account; retries pay once.
    body = {'catalog_id': 'banana_peel', 'action': 'added', 'quantity_g': 100, 'request_id': 'shared-request-001'}
    for auth in (a, b):
        first = c.post('/social/care-log', headers=auth, json=body)
        assert first.status_code == 200, first.text
        assert first.json() == {'xp_awarded': 5, 'duplicate': False}
        assert c.post('/social/care-log', headers=auth, json=body).json()['duplicate']
        assert c.get('/bins/bin-001/inventory', headers=auth).json()['grams'] == 100
        assert c.get('/social/me', headers=auth).json()['progress']['total_xp'] == 5
    assert len(c.get('/bins/bin-001/logs', headers=b).json()) == 2
    assert c.post('/social/check-in', headers=b).json()['xp_awarded'] == 5
    assert c.post('/quests/checkin/claim', params={'user_id': bob}, headers=b).status_code == 200
    assert c.get('/social/me', headers=a).json()['progress']['total_xp'] == 5
    second = c.post('/bins', json={'bin_id': 'bin-002', 'owner_id': 'demo-user'}).json()['device_token']
    assert pair(c, b, second).status_code == 409
    for auth in (a, b):
        long_request = {**body, 'request_id': 'x' * 100}
        assert c.post('/social/care-log', headers=auth, json=long_request).status_code == 200
        assert c.post('/social/care-log', headers=auth, json=long_request).json()['duplicate']


def test_camera_credit_and_retry_belong_to_confirming_account(c):
    alice, a = account(c, 'alice')
    bob, b = account(c, 'bob')
    pair(c, a)
    pair(c, b)
    sid = c.post('/bins/bin-001/drops/session', headers=b).json()['session_id']
    report = c.post('/bins/bin-001/drops', headers={'X-Device-Token': c.device_token}, json={
        'session_id': sid, 'items': [{'label': 'Banana peel', 'catalog_id': 'banana_peel', 'confidence': .9}],
        'thumbnail_jpeg_b64': JPEG, 'gemini_ok': True, 'latency_ms': 100})
    assert report.status_code == 201, report.text
    did = report.json()['drop_id']
    body = {'items': [{'label': 'Banana peel', 'catalog_id': 'banana_peel', 'quantity_g': 100}]}
    result = c.post(f'/drops/{did}/confirm', headers=b, json=body)
    assert result.status_code == 200, result.text
    assert result.json()['items'][0]['log']['xp_awarded'] == 5
    assert c.post(f'/drops/{did}/confirm', headers=b, json=body).json() == result.json()
    assert c.post(f'/drops/{did}/confirm', headers=a, json=body).status_code == 409
    assert c.get('/bins/bin-001/inventory', headers=a).json()['grams'] == 0
    assert c.get('/bins/bin-001/inventory', headers=b).json()['grams'] == 100
    assert c.portal.call(economy.stats, bob)['drops_confirmed'] == 1
    assert c.portal.call(economy.stats, alice)['drops_confirmed'] == 0
    for auth in (a, b):
        assert c.get(f'/drops/{did}/photo', headers=auth).status_code == 200
        assert len(c.get('/bins/bin-001/drops/history', headers=auth).json()['drops']) == 1


def test_concurrent_guests_cannot_take_a_third_slot(c):
    _, a = account(c, 'alice')
    _, b = account(c, 'bob')
    _, e = account(c, 'eve')
    pair(c, a)
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda auth: pair(c, auth), [b, e]))
    assert sorted(r.status_code for r in responses) == [200, 409]
    assert c.portal.call(db.fetchval, 'SELECT count(*) FROM bin_access WHERE bin_id=$1', 'bin-001') == 2


def test_shared_health_quests_and_awards_use_guest_bin(c, monkeypatch):
    alice, a = account(c, 'alice')
    bob, b = account(c, 'bob')
    pair(c, a)
    pair(c, b)
    ingest_series(c, moisture_raw=465, probe_temp=30, co2=900)

    async def six_hours(bin_id):
        assert bin_id == 'bin-001'
        return 6

    monkeypatch.setattr(binstate, 'healthy_hours_today', six_hours)
    for uid, auth in ((alice, a), (bob, b)):
        quests = c.get('/quests/today', params={'user_id': uid}, headers=auth).json()['quests']
        healthy = next(q for q in quests if q['key'] == 'healthy')
        assert healthy['done']
        assert c.post('/quests/healthy/claim', params={'user_id': uid}, headers=auth).status_code == 200
        assert c.post('/quests/healthy/claim', params={'user_id': uid}, headers=auth).status_code == 409
        assert c.get(f'/users/{uid}/game', headers=auth).status_code == 200
        assert c.portal.call(db.fetchval,
            "SELECT count(*) FROM point_events WHERE user_id=$1 AND kind='healthy_layer_day'", uid) > 0


def test_concurrent_photo_confirmation_pays_only_one_account(c):
    _, a = account(c, 'alice')
    _, b = account(c, 'bob')
    pair(c, a)
    pair(c, b)
    photo = c.post('/bins/bin-001/drops/photo', headers=b, json={'image_jpeg_b64': JPEG})
    assert photo.status_code == 201, photo.text
    did = photo.json()['id']
    body = {'items': [{'label': 'Apple core', 'catalog_id': 'apple_core', 'quantity_g': 100}]}
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda auth: c.post(f'/drops/{did}/confirm', headers=auth, json=body), [a, b]))
    assert sorted(r.status_code for r in responses) == [200, 409]
    assert c.portal.call(db.fetchval, 'SELECT count(*) FROM add_log WHERE drop_id=$1', did) == 1
    assert c.portal.call(db.fetchval, "SELECT sum(xp) FROM point_events WHERE kind='compost_added'") == 5
