"""Phone calibration is owner-scoped and never changes the other sensor."""
import pytest
from .conftest import needs_db
from .test_api import post_reading, NEW_FORMAT
from .test_social import account

pytestmark = needs_db


def test_owner_can_calibrate_only_their_bin_and_selected_probe(c):
    _, owner = account(c, 'probeowner')
    _, other = account(c, 'probeother')
    assert c.post('/social/bin', headers=owner, json={'device_token': c.device_token}).status_code == 200
    post_reading(c, NEW_FORMAT)
    initial = c.get('/bins/bin-001/live', headers=owner).json()
    top = initial['layers'][0]
    body = {'probe': 2, 'moisture_raw_dry': 600, 'moisture_raw_wet': 300, 'backfill': True}
    path = '/bins/bin-001/calibration'
    assert c.post(path, headers=other, json=body).status_code == 403
    assert c.post(path, json=body).status_code == 403
    assert c.post(path, headers={'X-Device-Token': c.device_token}, json=body).status_code == 403
    assert c.post(path, headers=owner, json={**body, 'moisture_raw_wet': 600}).status_code == 422
    result = c.post(path, headers=owner, json=body)
    assert result.status_code == 200, result.text
    after = c.get('/bins/bin-001/live', headers=owner).json()['layers']
    assert after[0]['moisture_pct'] == top['moisture_pct']
    assert after[0]['moisture_calibrated'] == top['moisture_calibrated']
    assert after[1]['moisture_calibrated'] is True
    assert after[1]['moisture_pct'] == pytest.approx(39.3, abs=0.1)
    assert after[1]['temp_c'] is None


def test_no_backfill_changes_only_future_readings(c):
    post_reading(c, NEW_FORMAT)
    before = c.get('/bins/bin-001/live').json()['layers']
    result = c.post('/bins/bin-001/calibration', json={
        'probe': 2, 'moisture_raw_dry': 600, 'moisture_raw_wet': 300, 'backfill': False})
    assert result.status_code == 200
    assert result.json()['readings_recomputed'] == 0
    unchanged = c.get('/bins/bin-001/live').json()['layers']
    assert unchanged[0]['moisture_pct'] == before[0]['moisture_pct']
    assert unchanged[1]['moisture_pct'] == before[1]['moisture_pct']
    post_reading(c, NEW_FORMAT)
    after = c.get('/bins/bin-001/live').json()['layers']
    assert after[1]['moisture_pct'] == pytest.approx(39.3, abs=0.1)
