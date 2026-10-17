"""Photo identification must not expose provider credentials on failure."""

import asyncio
import json
from types import SimpleNamespace

import httpx
import pytest

from app.services import identify


@pytest.mark.parametrize("failure", ["http", "timeout", "unexpected"])
def test_provider_errors_do_not_expose_secrets(monkeypatch, caplog, failure):
    secret = "fake-review-key-not-a-real-credential"
    monkeypatch.setattr(identify, "get_settings", lambda: SimpleNamespace(
        gemini_api_key=secret, gemini_model="test-model"))
    request = httpx.Request("POST", f"https://example.invalid/generate?key={secret}")
    response = httpx.Response(429, request=request)

    async def fail(_body):
        if failure == "http":
            response.raise_for_status()
        if failure == "timeout":
            raise httpx.ReadTimeout(f"request failed with {secret}", request=request)
        raise RuntimeError(f"provider details contain {secret}")

    monkeypatch.setattr(identify, "_call", fail)
    items, model, error = asyncio.run(identify.identify(b"fake-photo"))
    assert items == []
    assert model == "rules-fallback"
    assert error == "Photo identification is unavailable. Please identify the items manually."
    assert secret not in error
    assert secret not in caplog.text
    assert "example.invalid" not in caplog.text
    assert all(record.exc_info is None for record in caplog.records)


def test_provider_key_is_in_header_not_url(monkeypatch):
    secret = "fake-review-key-not-a-real-credential"
    monkeypatch.setattr(identify, "get_settings", lambda: SimpleNamespace(
        gemini_api_key=secret, gemini_model="test-model"))
    requests = []

    def respond(request):
        requests.append(request)
        return httpx.Response(200, json={"candidates": [{"content": {
            "parts": [{"text": json.dumps({"items": []})}]}}]})

    client_class = httpx.AsyncClient
    monkeypatch.setattr(identify.httpx, "AsyncClient", lambda **kwargs: client_class(
        transport=httpx.MockTransport(respond), **kwargs))
    assert asyncio.run(identify._call({"contents": []})) == {"items": []}
    assert len(requests) == 1
    assert requests[0].headers["x-goog-api-key"] == secret
    assert "key" not in requests[0].url.params
    assert secret not in str(requests[0].url)


def test_photo_count_is_optional_and_does_not_multiply_total_weight():
    from app.services import identify
    for proposed,expected in [(2,2),(None,None),(0,None),(1000,None),(True,None),(1.5,None)]:
        item=identify.parse({'items':[{'label':'banana peel','catalog_id':'banana_peel',
            'confidence':.9,'piece_count':proposed,'est_grams':90}]})[0]
        assert item['piece_count']==expected and item['est_grams']==90
