"""Scoped player sessions, legacy demo API keys, and bin device tokens."""

import hashlib
import hmac
import secrets

from fastapi import Header, HTTPException, Request, status

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


async def require_app_key(request: Request, x_api_key: str | None = Header(None, alias="X-API-Key")) -> None:
    """Legacy demo key or a scoped player session. Shared keys cannot impersonate players."""
    from .routers.social import current_user
    uid = await current_user(request) if request.headers.get("Authorization") else None
    if uid is None and not hmac.compare_digest((x_api_key or "").encode(), get_settings().app_api_key.encode()):
        raise HTTPException(401, "bad api key")
    body = {}
    if request.method in ("POST", "PATCH", "PUT"):
        try:
            body = await request.json()
        except Exception:
            pass
        if not isinstance(body, dict):
            body = {}
    targets = {v for v in (request.path_params.get("user_id"), request.query_params.get("user_id"), body.get("owner_id"), body.get("user_id")) if isinstance(v, str)}
    bin_id = request.path_params.get("bin_id") or body.get("bin_id")
    if request.path_params.get("drop_id"):
        try:
            drop_id = int(request.path_params["drop_id"])
        except ValueError:
            raise HTTPException(422, "Invalid drop id")
        bin_id = await db.fetchval("SELECT bin_id FROM drop_events WHERE id=$1", drop_id)
    if bin_id:
        owner = await db.fetchval("SELECT owner_id FROM bins WHERE bin_id=$1", bin_id)
        if owner:
            targets.add(owner)
    for target in targets:
        protected = target.startswith("player_") or await db.fetchval("SELECT 1 FROM social_profiles WHERE user_id=$1", target)
        if (protected and uid != target) or (uid and uid != target):
            raise HTTPException(403, "This account or bin belongs to someone else")
    if uid:
        # Owned-account game reads and validated economy actions share the
        # same ledger as Social. Unvalidated demo writes (notably harvest)
        # remain blocked; logging and check-in still use Social.
        route = request.scope["route"].path
        readable = {"/bins/{bin_id}/live", "/bins/{bin_id}/trends", "/bins/{bin_id}/stats",
                    "/bins/{bin_id}/logs", "/bins/{bin_id}/advice",
                    "/users/{user_id}/game", "/users/{user_id}/rewards",
                    "/users/{user_id}/collection", "/users/{user_id}/daily-goal",
                    "/quests/today", "/leagues/current"}
        writable = {"/bins/{bin_id}/advice/check", "/bins/{bin_id}/chat",
                    "/quests/{key}/claim", "/users/{user_id}/daily-goal/{index}/claim",
                    "/users/{user_id}/crates/{crate_id}/open", "/users/{user_id}/gacha/pull",
                    "/users/{user_id}/equip", "/users/{user_id}/lid-locks/buy"}
        allowed = (request.method == "GET" and route in readable) or (
            request.method == "POST" and route in writable)
        if not allowed:
            raise HTTPException(403, "Use the account's /social endpoints to save care and progress")
    if uid and not targets:
        raise HTTPException(403, "Use an account-scoped endpoint")
