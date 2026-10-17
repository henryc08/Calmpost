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
    """Resolve a device token to its bin_id, or 401.

    Only the hash is stored, so a leaked database cannot be replayed against
    /ingest, and re-registering a bin revokes the old token.
    """
    row = await db.fetchrow(
        "SELECT bin_id FROM bins WHERE token_sha256 = $1",
        hash_token(x_device_token),
    )
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="unknown device token"
        )
    return row["bin_id"]


async def require_app_key(x_api_key: str = Header(..., alias="X-API-Key")) -> None:
    """Gate the app-facing endpoints on the shared key.

    compare_digest rather than == so the check does not leak the key's
    length or contents through timing.
    """
    expected = get_settings().app_api_key
    if not hmac.compare_digest(x_api_key, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="bad api key"
        )
