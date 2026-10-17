"""Persistent, authenticated social graph and invite-only care leaderboards.

Only server-awarded ledger XP is ranked. Profiles default to approved followers;
joining a circle shares the leaderboard, never someone's full private activity.
"""
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from typing import Literal
from uuid import uuid4

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field, field_validator
from starlette.concurrency import run_in_threadpool

from .. import db
from ..rules import game
from ..services import ledger
from ..security import hash_token

router = APIRouter(prefix="/social", tags=["multiplayer"])


class Body(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Credentials(Body):
    handle: str = Field(min_length=3, max_length=24, pattern=r"^[a-zA-Z0-9_]+$")
    password: str = Field(min_length=10, max_length=128)

    @field_validator("handle")
    @classmethod
    def lower_handle(cls, value):
        return value.lower()


class Register(Credentials):
    display_name: str = Field(min_length=1, max_length=48)


class EditProfile(Body):
    display_name: str = Field(min_length=1, max_length=48)
    bio: str = Field(default="", max_length=160)
    is_private: bool = True


class CircleName(Body):
    name: str = Field(min_length=1, max_length=48)


class InviteCode(Body):
    code: str = Field(min_length=10, max_length=100)


class FollowDecision(Body):
    accept: bool


class PairBin(Body):
    device_token: str = Field(min_length=10, max_length=200)


class CareLog(Body):
    catalog_id: str = Field(min_length=1, max_length=80)
    action: Literal["added", "skipped"]
    request_id: str = Field(min_length=10, max_length=100)
    quantity_g: int | None = Field(default=None, ge=0, le=5000)


def password_hash(password: str, salt: str | None = None) -> str:
    salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), 600_000).hex()
    return f"{salt}:{digest}"


async def current_user(request: Request) -> str:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(401, "Sign in to continue")
    user = await db.fetchval(
        "SELECT user_id FROM social_sessions WHERE token_hash=$1 AND expires_at>now()",
        hash_token(header[7:]),
    )
    if not user:
        raise HTTPException(401, "Your session expired. Please sign in again")
    return user


async def auth_throttle(request: Request, handle: str) -> None:
    # Shared DB counters also work across workers. Ignore spoofable forwarded headers.
    host = request.client.host if request.client else "unknown"
    for raw, limit in ((f"ip:{host}", 60), (f"handle:{handle}", 12)):
        scope = hash_token(raw)
        row = await db.fetchrow(
            """INSERT INTO social_auth_attempts(scope,attempts,reset_at)
               VALUES($1,1,now()+interval '15 minutes') ON CONFLICT(scope) DO UPDATE
               SET attempts=CASE WHEN social_auth_attempts.reset_at<=now() THEN 1
                   ELSE social_auth_attempts.attempts+1 END,
                   reset_at=CASE WHEN social_auth_attempts.reset_at<=now() THEN now()+interval '15 minutes'
                   ELSE social_auth_attempts.reset_at END RETURNING attempts""", scope)
        if row["attempts"] > limit:
            raise HTTPException(429, "Too many attempts. Try again in 15 minutes")
    await db.execute("DELETE FROM social_auth_attempts WHERE reset_at<now()-interval '1 day'")


async def session(conn, user_id: str) -> dict:
    token = secrets.token_urlsafe(32)
    await conn.execute("DELETE FROM social_sessions WHERE expires_at<=now()")
    await conn.execute("INSERT INTO social_sessions(token_hash,user_id) VALUES($1,$2)", hash_token(token), user_id)
    return {"token": token, "user_id": user_id}


@router.post("/register", status_code=201)
async def register(body: Register, request: Request):
    await auth_throttle(request, body.handle)
    hashed = await run_in_threadpool(password_hash, body.password)
    uid = "player_" + uuid4().hex
    try:
        async with db.pool().acquire() as conn, conn.transaction():
            await ledger.ensure_user(conn, uid)
            await conn.execute("UPDATE user_state SET display_name=$2 WHERE user_id=$1", uid, body.display_name)
            await conn.execute("INSERT INTO social_profiles(user_id,handle,password_hash) VALUES($1,$2,$3)", uid, body.handle, hashed)
            return await session(conn, uid)
    except asyncpg.UniqueViolationError:
        raise HTTPException(409, "That username is already taken")


@router.post("/login")
async def login(body: Credentials, request: Request):
    await auth_throttle(request, body.handle)
    row = await db.fetchrow("SELECT user_id,password_hash FROM social_profiles WHERE handle=$1", body.handle)
    salt = row["password_hash"].split(":")[0] if row else "00" * 16
    candidate = await run_in_threadpool(password_hash, body.password, salt)
    if not row or not hmac.compare_digest(candidate, row["password_hash"]):
        raise HTTPException(401, "Username or password is incorrect")
    async with db.pool().acquire() as conn:
        return await session(conn, row["user_id"])


@router.post("/logout")
async def logout(request: Request, uid: str = Depends(current_user)):
    await db.execute("DELETE FROM social_sessions WHERE token_hash=$1", hash_token(request.headers["Authorization"][7:]))
    return {"ok": True}


async def identity(uid: str) -> dict:
    row = await db.fetchrow("""SELECT p.user_id,p.handle,p.bio,p.is_private,u.display_name
       FROM social_profiles p JOIN user_state u USING(user_id) WHERE p.user_id=$1""", uid)
    if not row:
        raise HTTPException(404, "Person not found")
    return dict(row)


async def visible(viewer: str, target: str) -> bool:
    return viewer == target or bool(await db.fetchval("""SELECT 1 FROM social_profiles p
       WHERE p.user_id=$2 AND (NOT p.is_private OR EXISTS(SELECT 1 FROM social_follows f
       WHERE f.follower_id=$1 AND f.followed_id=p.user_id AND f.accepted))""", viewer, target))


def week_start():
    today = datetime.now(timezone.utc).date()
    return datetime.combine(today - timedelta(days=(today.weekday()+1) % 7), datetime.min.time(), timezone.utc)


async def progress(uid: str):
    row = await db.fetchrow("""SELECT coalesce(sum(xp),0)::int total_xp,
       coalesce(sum(xp) FILTER(WHERE time >= $2 AND time < $2 + interval '7 days'),0)::int week_xp,
       count(*) FILTER(WHERE kind='harvest')::int harvests FROM point_events WHERE user_id=$1""", uid, week_start())
    cared = [r["day"] for r in await db.fetch("""SELECT DISTINCT (time AT TIME ZONE 'UTC')::date AS day
        FROM point_events WHERE user_id=$1 AND kind=ANY($2::text[]) AND kind<>'lid_lock_used'
        ORDER BY day""", uid, list(game.CARE_KINDS))]
    current, best = game.streak_lengths(cared, datetime.now(timezone.utc).date())
    return {**dict(row), "level": game.level_for_xp(row["total_xp"]), "streak": current,
            "best_streak": best, "care_days": [d.isoformat() for d in cared[-42:]],
            "checked_in_today": await db.fetchval("SELECT EXISTS(SELECT 1 FROM point_events WHERE user_id=$1 AND dedupe_key=$2)", uid, f"checkin:{datetime.now(timezone.utc).date()}")}


async def profile_data(viewer: str, target: str):
    person = await identity(target)
    relation = await db.fetchval("SELECT accepted FROM social_follows WHERE follower_id=$1 AND followed_id=$2", viewer, target)
    person["relationship"] = "following" if relation is True else "requested" if relation is False else "none"
    person["is_self"] = viewer == target
    person["can_view"] = await visible(viewer, target)
    if person["can_view"]:
        person["progress"] = await progress(target)
        person["followers"] = await db.fetchval("SELECT count(*) FROM social_follows WHERE followed_id=$1 AND accepted", target)
        person["following"] = await db.fetchval("SELECT count(*) FROM social_follows WHERE follower_id=$1 AND accepted", target)
    return person


@router.get("/me")
async def me(uid: str = Depends(current_user)):
    result = await profile_data(uid, uid)
    result["bin_id"] = await db.fetchval("SELECT bin_id FROM bins WHERE owner_id=$1 ORDER BY bin_id LIMIT 1", uid)
    return result


@router.patch("/me")
async def edit_me(body: EditProfile, uid: str = Depends(current_user)):
    async with db.pool().acquire() as conn, conn.transaction():
        await conn.execute("UPDATE user_state SET display_name=$2 WHERE user_id=$1", uid, body.display_name)
        await conn.execute("UPDATE social_profiles SET bio=$2,is_private=$3 WHERE user_id=$1", uid, body.bio, body.is_private)
    return await me(uid)


@router.get("/people")
async def people(q: str = Query(default="", max_length=24), uid: str = Depends(current_user)):
    q = q.strip().lower().lstrip("@").replace("%", "").replace("_", "\\_")
    if len(q) < 2:
        return []
    return [dict(r) for r in await db.fetch("""SELECT p.user_id,p.handle,u.display_name,p.is_private
        FROM social_profiles p JOIN user_state u USING(user_id)
        WHERE p.user_id<>$1 AND p.handle LIKE $2 ORDER BY p.handle LIMIT 25""", uid, q+"%")]


@router.get("/people/{target}")
async def person(target: str, uid: str = Depends(current_user)):
    return await profile_data(uid, target)


@router.post("/people/{target}/follow")
async def follow(target: str, uid: str = Depends(current_user)):
    if uid == target:
        raise HTTPException(400, "You cannot follow yourself")
    p = await identity(target)
    await db.execute("""INSERT INTO social_follows(follower_id,followed_id,accepted) VALUES($1,$2,$3)
       ON CONFLICT(follower_id,followed_id) DO NOTHING""", uid, target, not p["is_private"])
    return await profile_data(uid, target)


@router.delete("/people/{target}/follow")
async def unfollow(target: str, uid: str = Depends(current_user)):
    await db.execute("DELETE FROM social_follows WHERE follower_id=$1 AND followed_id=$2", uid, target)
    return {"ok": True}


@router.get("/connections")
async def connections(uid: str = Depends(current_user)):
    rows = await db.fetch("""SELECT p.user_id,p.handle,u.display_name,f.accepted,
        f.followed_id=$1 AS incoming FROM social_follows f
        JOIN social_profiles p ON p.user_id=CASE WHEN f.follower_id=$1 THEN f.followed_id ELSE f.follower_id END
        JOIN user_state u USING(user_id) WHERE f.follower_id=$1 OR f.followed_id=$1
        ORDER BY f.created_at DESC LIMIT 200""", uid)
    return [dict(r) for r in rows]


@router.post("/requests/{target}")
async def decide(target: str, body: FollowDecision, uid: str = Depends(current_user)):
    if body.accept:
        await db.execute("UPDATE social_follows SET accepted=true WHERE follower_id=$1 AND followed_id=$2", target, uid)
    else:
        await db.execute("DELETE FROM social_follows WHERE follower_id=$1 AND followed_id=$2", target, uid)
    return {"ok": True}


@router.delete("/followers/{target}")
async def remove_follower(target: str, uid: str = Depends(current_user)):
    async with db.pool().acquire() as conn, conn.transaction():
        await conn.fetchval("SELECT user_id FROM social_profiles WHERE user_id=$1 FOR NO KEY UPDATE", uid)
        await conn.execute("DELETE FROM social_follows WHERE follower_id=$1 AND followed_id=$2", target, uid)
        await conn.execute("DELETE FROM social_invites WHERE creator_id=$1 AND circle_id IS NULL", uid)
    return {"ok": True}


async def member(circle: str, uid: str, owner=False, conn=None):
    row = await (conn.fetchrow if conn else db.fetchrow)("""SELECT c.* FROM social_circles c
       JOIN social_circle_members m ON m.circle_id=c.id WHERE c.id=$1 AND m.user_id=$2""", circle, uid)
    if not row:
        raise HTTPException(404, "Private group not found")
    if owner and row["owner_id"] != uid:
        raise HTTPException(403, "Only the group owner can do that")
    return row


async def create_invite(uid: str, circle: str | None):
    code = ("C-" if circle else "F-") + secrets.token_urlsafe(18)
    async with db.pool().acquire() as conn, conn.transaction():
        if circle:
            await conn.fetchval("SELECT id FROM social_circles WHERE id=$1 FOR UPDATE", circle)
            await member(circle, uid, owner=True, conn=conn)
        else:
            await conn.fetchval("SELECT user_id FROM social_profiles WHERE user_id=$1 FOR NO KEY UPDATE", uid)
        await conn.execute("DELETE FROM social_invites WHERE creator_id=$1 AND circle_id IS NOT DISTINCT FROM $2::text", uid, circle)
        await conn.execute("INSERT INTO social_invites(token_hash,creator_id,circle_id) VALUES($1,$2,$3)", hash_token(code), uid, circle)
    return {"code": code, "expires_in_days": 7}


@router.post("/invites")
async def invite_friend(uid: str = Depends(current_user)):
    return await create_invite(uid, None)


@router.post("/join")
async def join(body: InviteCode, uid: str = Depends(current_user)):
    async with db.pool().acquire() as conn, conn.transaction():
        token_hash = hash_token(body.code)
        inv = await conn.fetchrow("SELECT * FROM social_invites WHERE token_hash=$1 AND expires_at>now()", token_hash)
        if not inv:
            raise HTTPException(404, "Invite expired or invalid. Ask for a new code")
        owner, circle = inv["creator_id"], inv["circle_id"]
        # Lock the parent before the invite, just like rotation and removal.
        # Recheck after waiting: a removal may have revoked this code meanwhile.
        if circle:
            await conn.fetchval("SELECT id FROM social_circles WHERE id=$1 FOR UPDATE", circle)
        else:
            await conn.fetchval("SELECT user_id FROM social_profiles WHERE user_id=$1 FOR NO KEY UPDATE", owner)
        if not await conn.fetchval("SELECT 1 FROM social_invites WHERE token_hash=$1 AND expires_at>now() FOR UPDATE", token_hash):
            raise HTTPException(404, "Invite expired or invalid. Ask for a new code")
        if circle:
            exists = await conn.fetchval("SELECT 1 FROM social_circle_members WHERE circle_id=$1 AND user_id=$2", circle, uid)
            if not exists and await conn.fetchval("SELECT count(*) FROM social_circle_members WHERE circle_id=$1", circle) >= 50:
                raise HTTPException(409, "This group is full (50 people)")
            await conn.execute("INSERT INTO social_circle_members(circle_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING", circle, uid)
            return {"circle_id": circle}
        if uid == owner:
            raise HTTPException(400, "This is your own invitation")
        for a, b in sorted(((uid, owner), (owner, uid))):
            await conn.execute("""INSERT INTO social_follows(follower_id,followed_id,accepted) VALUES($1,$2,true)
              ON CONFLICT(follower_id,followed_id) DO UPDATE SET accepted=true""", a, b)
        return {"user_id": owner}


@router.get("/circles")
async def circles(uid: str = Depends(current_user)):
    return [dict(r) for r in await db.fetch("""SELECT c.id,c.name,c.owner_id,count(all_m.user_id)::int members
       FROM social_circles c JOIN social_circle_members m ON m.circle_id=c.id AND m.user_id=$1
       JOIN social_circle_members all_m ON all_m.circle_id=c.id GROUP BY c.id ORDER BY c.created_at DESC""", uid)]


@router.post("/circles", status_code=201)
async def create_circle(body: CircleName, uid: str = Depends(current_user)):
    cid = uuid4().hex
    async with db.pool().acquire() as conn, conn.transaction():
        await conn.fetchval("SELECT user_id FROM social_profiles WHERE user_id=$1 FOR UPDATE", uid)
        if await conn.fetchval("SELECT count(*) FROM social_circles WHERE owner_id=$1", uid) >= 20:
            raise HTTPException(409, "You can own up to 20 groups")
        await conn.execute("INSERT INTO social_circles(id,owner_id,name) VALUES($1,$2,$3)", cid, uid, body.name)
        await conn.execute("INSERT INTO social_circle_members(circle_id,user_id) VALUES($1,$2)", cid, uid)
    return {"id": cid, "name": body.name}


@router.post("/circles/{cid}/invite")
async def invite_circle(cid: str, uid: str = Depends(current_user)):
    return await create_invite(uid, cid)


@router.get("/circles/{cid}")
async def leaderboard(cid: str, period: Literal["week", "all"] = "week", uid: str = Depends(current_user)):
    circle = await member(cid, uid)
    start = week_start() if period == "week" else datetime(1970,1,1,tzinfo=timezone.utc)
    rows = await db.fetch("""SELECT p.user_id,p.handle,u.display_name,coalesce(sum(e.xp),0)::int xp
      FROM social_circle_members m JOIN social_profiles p ON p.user_id=m.user_id
      JOIN user_state u ON u.user_id=m.user_id
      LEFT JOIN point_events e ON e.user_id=m.user_id AND e.time >= $2 AND e.time <= now()
      WHERE m.circle_id=$1 GROUP BY p.user_id,u.display_name ORDER BY xp DESC,p.handle""", cid, start)
    out, last_xp, rank = [], None, 0
    for i, row in enumerate(rows, 1):
        if row["xp"] != last_xp:
            rank = i
        last_xp = row["xp"]
        out.append({**dict(row), "rank": rank, "is_you": row["user_id"] == uid})
    return {"id": cid, "name": circle["name"], "owner_id": circle["owner_id"], "members": out,
            "period": period, "resets_at": (week_start()+timedelta(days=7)).isoformat(),
            "team_xp": sum(r["xp"] for r in out)}


@router.delete("/circles/{cid}/members/{target}")
async def leave_or_remove(cid: str, target: str, uid: str = Depends(current_user)):
    async with db.pool().acquire() as conn, conn.transaction():
        await conn.fetchval("SELECT id FROM social_circles WHERE id=$1 FOR UPDATE", cid)
        circle = await member(cid, uid, conn=conn)
        if target == circle["owner_id"]:
            raise HTTPException(400, "The owner must delete the group instead")
        if target != uid and circle["owner_id"] != uid:
            raise HTTPException(403, "Only the owner can remove someone else")
        await conn.execute("DELETE FROM social_circle_members WHERE circle_id=$1 AND user_id=$2", cid, target)
        # Old join codes cannot silently undo a removal.
        await conn.execute("DELETE FROM social_invites WHERE circle_id=$1", cid)
    return {"ok": True}


@router.delete("/circles/{cid}")
async def delete_circle(cid: str, uid: str = Depends(current_user)):
    await member(cid, uid, owner=True)
    await db.execute("DELETE FROM social_circles WHERE id=$1 AND owner_id=$2", cid, uid)
    return {"ok": True}


@router.post("/check-in")
async def check_in(uid: str = Depends(current_user)):
    day = datetime.now(timezone.utc).date().isoformat()
    async with db.pool().acquire() as conn, conn.transaction():
        await conn.execute("SET LOCAL TIME ZONE INTERVAL '+00:00' HOUR TO MINUTE")
        await conn.fetchval("SELECT user_id FROM user_state WHERE user_id=$1 FOR UPDATE", uid)
        xp = await ledger.award(conn, uid, "check_in", dedupe_key=f"checkin:{day}")
    return {"xp_awarded": xp}


@router.post("/bin")
async def pair_bin(body: PairBin, uid: str = Depends(current_user)):
    async with db.pool().acquire() as conn, conn.transaction():
        await conn.fetchval("SELECT user_id FROM social_profiles WHERE user_id=$1 FOR NO KEY UPDATE", uid)
        row = await conn.fetchrow("SELECT bin_id,owner_id FROM bins WHERE token_sha256=$1 FOR UPDATE", hash_token(body.device_token))
        if not row:
            raise HTTPException(404, "Bin token not recognised")
        if row["owner_id"] != uid and await conn.fetchval("SELECT 1 FROM social_profiles WHERE user_id=$1", row["owner_id"]):
            raise HTTPException(409, "This bin already belongs to another account")
        if await conn.fetchval("SELECT 1 FROM bins WHERE owner_id=$1 AND bin_id<>$2", uid, row["bin_id"]):
            raise HTTPException(409, "Your account already has a bin")
        await conn.execute("UPDATE bins SET owner_id=$2 WHERE bin_id=$1", row["bin_id"], uid)
    return {"bin_id": row["bin_id"]}


@router.post("/care-log")
async def care_log(body: CareLog, uid: str = Depends(current_user)):
    from ..catalog.food import lookup
    from ..models import LogCreate
    from ..services import binstate
    from ..services.logging import write_log
    item = lookup(body.catalog_id)
    if not item:
        raise HTTPException(404, "Unknown item")
    bid = await db.fetchval("SELECT bin_id FROM bins WHERE owner_id=$1 ORDER BY bin_id LIMIT 1", uid)
    if not bid:
        raise HTTPException(409, "Connect your bin before sharing sensor-based care")
    snapshot = await binstate.snapshot(bid)
    entry = LogCreate(
        item=item["name"], catalog_id=item["id"], category=item["category"],
        action=body.action, quantity_g=body.quantity_g if body.action == "added" else 0,
        request_id="social:" + body.request_id, was_advised=True,
    )
    async with db.pool().acquire() as conn, conn.transaction():
        await conn.execute("SET LOCAL TIME ZONE INTERVAL '+00:00' HOUR TO MINUTE")
        await conn.fetchval("SELECT user_id FROM user_state WHERE user_id=$1 FOR UPDATE", uid)
        duplicate = bool(await conn.fetchval(
            "SELECT 1 FROM log_requests WHERE bin_id=$1 AND request_id=$2", bid, entry.request_id))
        # Volume and keep-out logs do not depend on sensors. write_log only
        # awards the advice bonus when a fresh snapshot verifies the action.
        result = await write_log(conn, bid, entry, snapshot)
    return {"xp_awarded": result.xp_awarded, "duplicate": duplicate}


@router.get("/feed")
async def feed(target: str | None = None, before: datetime | None = None, uid: str = Depends(current_user)):
    if target and not await visible(uid, target):
        raise HTTPException(403, "This person shares progress with approved followers")
    rows = await db.fetch("""SELECT e.id,e.time,e.user_id,e.kind,e.xp,p.handle,u.display_name,
       (SELECT count(*)::int FROM social_cheers c WHERE c.event_id=e.id AND c.event_time=e.time) cheers,
       EXISTS(SELECT 1 FROM social_cheers c WHERE c.event_id=e.id AND c.event_time=e.time AND c.user_id=$1) cheered
       FROM point_events e JOIN social_profiles p ON p.user_id=e.user_id JOIN user_state u ON u.user_id=e.user_id
       WHERE e.xp>0 AND e.kind=ANY($2::text[]) AND ($3::text IS NULL OR e.user_id=$3)
       AND e.time<coalesce($4::timestamptz,now()+interval '1 second')
       AND (e.user_id=$1 OR ($3::text IS NOT NULL AND NOT p.is_private) OR EXISTS(
          SELECT 1 FROM social_follows f WHERE f.follower_id=$1 AND f.followed_id=e.user_id AND f.accepted))
       ORDER BY e.time DESC,e.id DESC LIMIT 30""", uid, list(game.CARE_KINDS)+["daily_quest"], target, before)
    return [dict(r) for r in rows]


@router.post("/events/{event_id}/cheer")
async def cheer(event_id: int, uid: str = Depends(current_user)):
    row = await db.fetchrow("SELECT user_id,time,kind,xp FROM point_events WHERE id=$1", event_id)
    if not row or row["xp"] <= 0 or row["kind"] not in list(game.CARE_KINDS)+["daily_quest"] or not await visible(uid, row["user_id"]):
        raise HTTPException(404, "Activity not found")
    if row["user_id"] == uid:
        raise HTTPException(400, "Save your cheers for someone else")
    await db.execute("INSERT INTO social_cheers(event_id,event_time,user_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING", event_id, row["time"], uid)
    return {"ok": True}
