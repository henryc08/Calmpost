"""Client for the backend's /drops endpoints (CLAUDE.md section 4).

Until the real backend has them, run `python mock_backend.py` and point
BACKEND_URL at it (the default).
"""

import logging
from dataclasses import dataclass
from datetime import datetime

import httpx

from config import settings

log = logging.getLogger(__name__)


@dataclass
class Session:
    id: str
    expires_at: datetime


class Backend:
    def __init__(self, base_url: str = settings.backend_url, bin_id: str = settings.bin_id,
                 api_key: str = settings.api_key, client: httpx.Client | None = None):
        self.bin_id = bin_id
        headers = {"X-API-Key": api_key} if api_key else {}
        self.http = client or httpx.Client(base_url=base_url, headers=headers, timeout=5.0)

    def active_session(self) -> Session | None:
        """The app arms the camera with POST /bins/{id}/drops/session; we poll for it."""
        r = self.http.get(f"/bins/{self.bin_id}/drops/session/active")
        if r.status_code in (204, 404):
            return None
        r.raise_for_status()
        d = r.json()
        if not d or not d.get("session_id"):
            return None
        return Session(d["session_id"], datetime.fromisoformat(d["expires_at"]))

    def report_drop(self, session_id: str, items: list[dict], thumbnail_b64: str, latency_ms: int,
                    gemini_ok: bool, model: str, error: str | None) -> dict:
        r = self.http.post(f"/bins/{self.bin_id}/drops", json={
            "session_id": session_id,
            "items": items,
            "thumbnail_jpeg_b64": thumbnail_b64,
            "latency_ms": latency_ms,
            "gemini_ok": gemini_ok,
            "model": model,
            "error": error,
        })
        r.raise_for_status()
        return r.json()

    def close_session(self, session_id: str, reason: str) -> None:
        """reason: 'no_motion' (nothing seen in 60 s) or 'reported'."""
        r = self.http.post(f"/bins/{self.bin_id}/drops/session/{session_id}/close", json={"reason": reason})
        if r.status_code not in (200, 204, 404):
            r.raise_for_status()

    def hints(self) -> list[str]:
        """Recent user corrections, fed to Gemini. Optional: an empty list if the backend lacks it."""
        try:
            r = self.http.get(f"/bins/{self.bin_id}/drops/hints")
            return r.json().get("hints", []) if r.status_code == 200 else []
        except httpx.HTTPError:
            return []
