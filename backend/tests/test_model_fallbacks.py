"""Malformed model replies must follow the same fallback as network failures."""
import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services import advisor, identify, trunc
from tests.conftest import ingest_series, needs_db, raw_for
from tests.test_drops import REAL_JPEG


@pytest.mark.parametrize('change', [
    {'suggest_add': None}, {'pair_with': [None]}, {'suggest_avoid': 'meat'},
    {'headline': {}}, {'reason': 42}, {'verdict': 'add'},
    {'bottom_ready': 'false'}, {'stage_top': 'invented'},
])
@needs_db
def test_bad_advice_fields_return_rules(c, monkeypatch, change):
    from app.config import get_settings
    from app.services import binstate
    monkeypatch.setenv('GEMINI_API_KEY', 'test-key')
    get_settings.cache_clear()
    ingest_series(c, moisture_raw=raw_for(50), probe_temp=30, co2=900)
    snap = c.portal.call(binstate.snapshot, 'bin-001')
    expected = advisor.fallback(snap, 'Banana peel')
    monkeypatch.setattr(advisor, '_ask_gemini', AsyncMock(return_value={**expected, **change}))
    result = c.post('/bins/bin-001/advice/check', json={'item': 'Banana peel'}, params={'refresh': True})
    assert result.status_code == 200
    assert result.json()['model'] == 'rules-fallback'
    assert result.json()['reason'] == expected['reason']


@pytest.mark.parametrize('raw', [None, [], 'bad', {}, {'items': None}, {'items': {}},
                                  {'items': [{'label': 'peel', 'catalog_id': []}]}])
def test_malformed_photo_replies_never_escape(monkeypatch, raw):
    monkeypatch.setattr(identify, 'get_settings', lambda: SimpleNamespace(gemini_api_key='test-key', gemini_model='test'))
    monkeypatch.setattr(identify, '_call', AsyncMock(return_value=raw))
    items, model, error = asyncio.run(identify.identify(b'fake-photo'))
    assert items == [] and model == 'rules-fallback' and error


@needs_db
def test_photo_parse_failure_keeps_photo_for_manual_confirmation(c, monkeypatch):
    monkeypatch.setattr(identify, 'get_settings', lambda: SimpleNamespace(gemini_api_key='test-key', gemini_model='test'))
    monkeypatch.setattr(identify, '_call', AsyncMock(return_value={'items': {}}))
    result = c.post('/bins/bin-001/drops/photo', json={'image_jpeg_b64': REAL_JPEG})
    assert result.status_code == 201
    photo = result.json()
    assert photo['items'] == [] and photo['gemini_ok'] is False
    assert photo['thumbnail_jpeg_b64'] == REAL_JPEG and photo['status'] == 'pending'
    confirmed = c.post(f"/drops/{photo['id']}/confirm", json={'items': [
        {'label': 'banana peel', 'catalog_id': 'banana_peel', 'amount': 'handful'}]})
    assert confirmed.status_code == 200
    assert confirmed.json()['items'][0]['log']['xp_awarded'] == 5


@pytest.mark.parametrize('raw', [None, [], {'reply': 42}, {'reply': 'hello', 'on_topic': 'false'},
                                 {'reply': 'hello', 'used_readings': []}])
@needs_db
def test_bad_chat_replies_return_summary(c, monkeypatch, raw):
    monkeypatch.setattr(trunc, 'get_settings', lambda: SimpleNamespace(gemini_api_key='test-key', gemini_model='test'))
    monkeypatch.setattr(trunc, '_call', AsyncMock(return_value=raw))
    response = c.post('/bins/bin-001/chat', json={'message': 'How is the bin?', 'include_photos': False})
    assert response.status_code == 200
    assert response.json()['model'] == 'rules-fallback'
    assert response.json()['reply']
