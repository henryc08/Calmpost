"""Two kinds of caller: the bin (device token) and the app (shared API key)."""

import hashlib
import hmac
import secrets

from fastapi import Header, HTTPException, status

from . import db
from .config import get_settings


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def new_token() -> str:
    return secrets.token_urlsafe(24)


async def require_device(
    x_device_token: str = Header(..., alias="X-Device-Token"),
) -> str:
    """Resolve a device token to its device_id, or 401."""
    row = await db.fetchrow(
        "SELECT device_id FROM devices WHERE token_sha256 = $1",
        hash_token(x_device_token),
    )
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="unknown device token"
        )
    return row["device_id"]


async def require_app_key(x_api_key: str = Header(..., alias="X-API-Key")) -> None:
    """Gate the app-facing endpoints on the shared key."""
    expected = get_settings().app_api_key
    if not hmac.compare_digest(x_api_key, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="bad api key"
        )
