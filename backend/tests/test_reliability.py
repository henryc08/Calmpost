from concurrent.futures import ThreadPoolExecutor

from app.services import binstate
from tests.conftest import ingest_series, needs_db, raw_for, run_sql
from tests.test_drops import arm, report

pytestmark = needs_db


def test_manual_retries_do_not_duplicate_volume(c):
    body = {'item': 'Banana peel', 'catalog_id': 'banana_peel', 'quantity_g': 110, 'request_id': 'same-add'}
    first = c.post('/bins/bin-001/logs', json=body)
    retry = c.post('/bins/bin-001/logs', json=body)
    assert first.status_code == retry.status_code == 201
    assert first.json() == retry.json()
    assert len(c.get('/bins/bin-001/logs').json()) == 1
    assert c.post('/bins/bin-001/logs', json={**body, 'quantity_g': 250}).status_code == 409


def test_split_volume_and_concurrent_cap(c):
    for grams, expected in [(110, 5), (10, 1)]:
        r = c.post('/bins/bin-001/logs', json={'item': 'Banana peel', 'quantity_g': grams})
        assert r.json()['xp_awarded'] == expected
    def add(i):
        return c.post('/bins/bin-001/logs', json={'item': 'Banana peel', 'quantity_g': 500, 'request_id': f'parallel-{i}'}).json()['xp_awarded']
    with ThreadPoolExecutor(max_workers=4) as pool:
        assert sum(pool.map(add, range(4))) == 54


def test_cache_does_not_cross_verdict_threshold(c):
    ingest_series(c, moisture_raw=raw_for(63), probe_temp=30, co2=2000, minutes=0)
    first = c.post('/bins/bin-001/advice/check', json={'item': 'Banana peel'}).json()
    ingest_series(c, moisture_raw=raw_for(65), probe_temp=30, co2=2000, minutes=0)
    second = c.post('/bins/bin-001/advice/check', json={'item': 'Banana peel'}).json()
    assert first['verdict'] == 'great'
    assert second['verdict'] == 'careful' and not second['cached']


def test_camera_report_retry_and_cancel(c):
    sid = arm(c)
    first = report(c, sid).json()
    assert report(c, sid).json() == first
    assert len(c.get('/bins/bin-001/drops/pending').json()) == 1
    sid = arm(c)
    assert c.post(f'/bins/bin-001/drops/session/{sid}/close', json={'reason': 'cancelled'}).status_code == 200
    assert report(c, sid).status_code == 409


def test_confirmation_rolls_back_every_item_on_failure(c, monkeypatch):
    from app.routers import drops
    real = drops.write_log
    calls = 0
    async def fail_second(*args, **kwargs):
        nonlocal calls
        calls += 1
        if calls == 2: raise RuntimeError('simulated write failure')
        return await real(*args, **kwargs)
    monkeypatch.setattr(drops, 'write_log', fail_second)
    drop_id = report(c, arm(c)).json()['drop_id']
    import pytest
    with pytest.raises(RuntimeError):
        c.post(f'/drops/{drop_id}/confirm', json={'items': [
            {'label': 'Banana peel', 'catalog_id': 'banana_peel', 'amount': 'handful'},
            {'label': 'Coffee grounds', 'catalog_id': 'coffee_grounds', 'amount': 'small'}]})
    assert c.get('/bins/bin-001/logs').json() == []
    assert c.get('/bins/bin-001/drops/pending').json()[0]['id'] == drop_id


def test_existing_bin_cannot_be_reassigned(c):
    assert c.post('/bins', json={'bin_id': 'bin-001', 'owner_id': 'different-user'}).status_code == 409
    assert c.get('/bins').json()[0]['owner_id'] == 'demo-user'
