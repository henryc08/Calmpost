"""Camera drop-in (AGENTS.md 2.4): the app arms the camera, vision/ reports
what it saw, the user confirms or dismisses.

    App ── POST /bins/{id}/drops/session ──▶ armed for 60 s
    vision/ ── GET .../drops/session/active (poll) ── POST /bins/{id}/drops
    App ── GET .../drops/stream (SSE) or .../drops/pending
    App ── POST /drops/{id}/confirm  → add_log rows (source='camera') + verdict + XP
         └ POST /drops/{id}/dismiss  → "Nothing was added"

Afterwards: GET .../drops/history lists resolved drops (guess beside what the
user settled on), GET /drops/{id} is one of them with its thumbnail inlined,
and GET /drops/{id}/photo serves the stored frame as a real JPEG. /drops/pending
is deliberately narrow -- still waiting, last hour only -- so these are the way
back to a drop once it has been answered.

Rules, not the camera, decide categories: a label the rules call avoid is
avoid, whatever the model said. Confirmed items go through the normal log
endpoint, so XP follows the usual rules (1 per 20 g compostable, +15 if it was the
suggested action, +5 for taking a keep-out item back out).
"""

import asyncio
import base64
import binascii
import json
import secrets
from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from .. import db
from ..catalog import food
from ..rules import compost
from ..models import AdviceResponse, LogCreate, LogEntry
from ..security import require_app_key
from ..services import advisor, binstate, identify
from ..services.logging import write_log

router = APIRouter(tags=["drops"], dependencies=[Depends(require_app_key)])

ARM_SECONDS = 60
MAX_THUMB_BYTES = 200_000
HINTS = 5

Amount = Literal["small", "handful", "large"]
AMOUNT_GRAMS = {"small": 40, "handful": 110, "large": 250}


# --- shapes -------------------------------------------------------------------------

class DropItem(BaseModel):
    """One thing the camera saw. box_2d is [ymin, xmin, ymax, xmax] on 0-1000."""
    label: str = Field(min_length=1, max_length=60)
    catalog_id: str = Field(default="unknown", max_length=40)
    category: Literal["green", "brown", "avoid"] | None = None
    est_grams: float | None = Field(default=None, gt=0, lt=5000)
    amount: Amount | None = None
    confidence: float = Field(ge=0, le=1)
    box_2d: list[int] | None = Field(default=None, min_length=4, max_length=4)


class DropReport(BaseModel):
    session_id: str
    items: list[DropItem] = Field(default_factory=list, max_length=10)
    thumbnail_jpeg_b64: str = ""
    latency_ms: int = Field(ge=0)
    gemini_ok: bool
    model: str = ""
    error: str | None = Field(default=None, max_length=500)


class PhotoSubmission(BaseModel):
    """One photo the user took. The app should downscale to about 1024 px
    before sending; identify.MAX_PHOTO_BYTES is the ceiling, not a target."""
    image_jpeg_b64: str = Field(min_length=1)


class SessionClose(BaseModel):
    reason: Literal["no_motion", "reported", "cancelled"] = "no_motion"


class ConfirmItem(BaseModel):
    label: str = Field(min_length=1, max_length=60)
    catalog_id: str = Field(default="unknown", max_length=40)
    category: Literal["green", "brown", "avoid", "unknown"] = "unknown"
    amount: Amount | None = None
    # The user took a keep-out item back out: logged as a skip (+5 by the usual rule).
    removed: bool = False
    # It was the next best action: +15 by the usual rule.
    was_advised: bool = False
    advice_id: int | None = None


class ConfirmBody(BaseModel):
    items: list[ConfirmItem] = Field(min_length=1, max_length=10)


class ConfirmedItem(BaseModel):
    log: LogEntry
    verdict: AdviceResponse | None = None


class ConfirmResponse(BaseModel):
    drop_id: int
    status: Literal["confirmed"]
    corrected: bool
    items: list[ConfirmedItem]


# --- helpers ----------------------------------------------------------------------

def _now() -> datetime:
    return datetime.now(timezone.utc)


def rules_category(label: str, claimed: str | None, catalog_id: str | None = None) -> str:
    """Hard-avoid by the label first (a "mix with chicken" is avoid whatever it
    matched); then the catalog item's own type; then the type the camera or
    the user gave an item the catalog doesn't know; then the rules."""
    if compost.avoid_reason(label):
        return "avoid"
    if catalog_id and catalog_id in food.BY_ID:
        return food.BY_ID[catalog_id]["category"]
    if claimed in ("green", "brown", "avoid"):
        return claimed
    return compost.categorise(label)


async def _bin_or_404(bin_id: str) -> None:
    if await db.fetchrow("SELECT 1 FROM bins WHERE bin_id = $1", bin_id) is None:
        raise HTTPException(status_code=404, detail="unknown bin")


async def _drop_or_404(drop_id: int):
    row = await db.fetchrow("SELECT * FROM drop_events WHERE id = $1", drop_id)
    if row is None:
        raise HTTPException(status_code=404, detail="unknown drop")
    return row


def _public(row) -> dict:
    """A drop as the app sees it (thumbnail as base64 for the pop-up)."""
    thumb = row["thumbnail_jpeg"]
    return {
        "id": row["id"],
        "bin_id": row["bin_id"],
        "session_id": row["session_id"],
        "time": row["time"].isoformat(),
        "status": row["status"],
        "items": row["guess"],
        # 'camera' or 'photo': the same sheet handles both, but a photo the
        # user framed deserves different wording from one the bin noticed.
        "source": row["source"],
        "gemini_ok": row["gemini_ok"],
        "model": row["model"],
        "error": row["error"],
        "latency_ms": row["latency_ms"],
        "thumbnail_jpeg_b64": base64.b64encode(thumb).decode() if thumb else "",
    }


async def _pending(bin_id: str) -> list[dict]:
    rows = await db.fetch(
        """SELECT * FROM drop_events WHERE bin_id = $1 AND status = 'pending'
           ORDER BY time LIMIT 20""", bin_id)
    return [_public(r) for r in rows]


# --- app: arm, watch, confirm ------------------------------------------------------------

@router.post("/bins/{bin_id}/drops/session", status_code=201)
async def arm(bin_id: str) -> dict:
    """'Drop something in': arm the camera for 60 s. Re-arming replaces the open session."""
    await _bin_or_404(bin_id)
    sid = secrets.token_hex(6)
    expires = _now() + timedelta(seconds=ARM_SECONDS)
    async with db.pool().acquire() as conn, conn.transaction():
        await conn.execute(
            """UPDATE drop_sessions SET closed_at = now(), close_reason = 'replaced'
               WHERE bin_id = $1 AND closed_at IS NULL""", bin_id)
        await conn.execute(
            "INSERT INTO drop_sessions (session_id, bin_id, expires_at) VALUES ($1, $2, $3)",
            sid, bin_id, expires)
    return {"session_id": sid, "expires_at": expires.isoformat()}


@router.get("/bins/{bin_id}/drops/sessions/{session_id}")
async def session_status(bin_id: str, session_id: str) -> dict:
    """Lets the sheet tell 'still watching' from 'didn't see anything'."""
    row = await db.fetchrow(
        "SELECT * FROM drop_sessions WHERE session_id = $1 AND bin_id = $2", session_id, bin_id)
    if row is None:
        raise HTTPException(status_code=404, detail="unknown session")
    open_ = row["closed_at"] is None and row["expires_at"] > _now()
    return {"session_id": session_id, "open": open_, "expires_at": row["expires_at"].isoformat(),
            "close_reason": row["close_reason"] or (None if open_ else "expired")}


@router.get("/bins/{bin_id}/drops/pending")
async def pending(bin_id: str) -> list[dict]:
    """Polling fallback for the stream: detections waiting for the user."""
    await _bin_or_404(bin_id)
    return await _pending(bin_id)


@router.get("/bins/{bin_id}/drops/stream")
async def stream(bin_id: str) -> StreamingResponse:
    """Server-sent events: one `drop` event per new pending detection."""
    await _bin_or_404(bin_id)

    async def events():
        seen: set[int] = set()
        while True:
            for d in await _pending(bin_id):
                if d["id"] not in seen:
                    seen.add(d["id"])
                    yield f"event: drop\ndata: {json.dumps(d)}\n\n"
            yield ": keep-alive\n\n"
            await asyncio.sleep(1)

    return StreamingResponse(events(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@router.post("/drops/{drop_id}/confirm", response_model=ConfirmResponse)
async def confirm(drop_id: int, body: ConfirmBody) -> ConfirmResponse:
    """The user submitted the pop-up. Each item becomes an add_log row and gets a verdict."""
    drop = await _drop_or_404(drop_id)
    final = [i.model_dump() for i in body.items]
    for f in final:
        f["category"] = rules_category(f["label"], f["category"], f["catalog_id"])
        if f['amount'] is None:
            guess = next((i for i in drop['guess'] if i.get('catalog_id') == f['catalog_id']), None)
            f['amount'] = (guess or {}).get('amount') or 'handful'
    def comparable(items):
        return [(i.get("catalog_id"), i.get("label", "").lower(), i.get("category"), i.get("amount"), i.get("removed", False)) for i in items]
    corrected = comparable(drop["guess"]) != comparable(final)
    snap = await binstate.snapshot(drop["bin_id"])
    async with db.pool().acquire() as conn, conn.transaction():
        locked = await conn.fetchrow("SELECT * FROM drop_events WHERE id=$1 FOR UPDATE", drop_id)
        if locked["status"] == "confirmed" and locked["confirmation_body"] == final and locked["confirmation_response"]:
            return ConfirmResponse(**locked["confirmation_response"])
        if locked["status"] != "pending":
            raise HTTPException(409, "drop was already handled")
        out = []
        for item, f in zip(body.items, final):
            grams = AMOUNT_GRAMS[f['amount']]
            log = await write_log(conn, drop["bin_id"], LogCreate(
                item=item.label, catalog_id=item.catalog_id if item.catalog_id != "unknown" else None,
                category=f["category"], action="skipped" if item.removed else "added", quantity_g=grams,
                source=drop["source"], was_advised=item.was_advised, notes=f"{drop['source']} drop {drop_id}"), snap)
            await conn.execute("UPDATE add_log SET drop_id=$1 WHERE id=$2 AND time=$3", drop_id, log.id, log.time)
            verdict = None
            if snap is not None and not item.removed:
                payload = advisor.fallback(snap, item.label)
                if f['category'] == 'avoid':
                    payload.update(verdict='avoid', headline='Keep it out', reason='This material does not belong in a home compost bin. Take it back out.')
                verdict = AdviceResponse(advice_id=0, bin_id=drop["bin_id"], item=item.label,
                    created_at=_now(), cached=False, model="rules-confirmation", input_snapshot=None, **payload)
            out.append(ConfirmedItem(log=log, verdict=verdict))
        result = ConfirmResponse(drop_id=drop_id,status="confirmed",corrected=corrected,items=out)
        await conn.execute("""UPDATE drop_events SET status='confirmed',final_items=$2,corrected=$3,resolved_at=now(),
                           confirmation_body=$2,confirmation_response=$4 WHERE id=$1""", drop_id, final, corrected, result.model_dump(mode="json"))
        return result


@router.post("/drops/{drop_id}/dismiss")
async def dismiss(drop_id: int) -> dict:
    """'Nothing was added': a false trigger. Kept for the accuracy stat."""
    drop = await _drop_or_404(drop_id)
    if drop["status"] != "pending":
        raise HTTPException(status_code=409, detail=f"drop is already {drop['status']}")
    await db.execute(
        """UPDATE drop_events SET status = 'dismissed', corrected = true, resolved_at = now()
           WHERE id = $1 AND status = 'pending'""", drop_id)
    return {"drop_id": drop_id, "status": "dismissed"}


@router.get("/bins/{bin_id}/drops/accuracy")
async def accuracy(bin_id: str, days: int = 30) -> dict:
    """Camera accuracy from the vision_accuracy_1d rollup (falls back to raw rows)."""
    await _bin_or_404(bin_id)
    q = """SELECT count(*) AS drops,
                  count(*) FILTER (WHERE status = 'confirmed') AS confirmed,
                  count(*) FILTER (WHERE status = 'confirmed' AND NOT corrected) AS as_seen,
                  count(*) FILTER (WHERE status = 'dismissed') AS dismissed,
                  avg(top_confidence) AS conf, avg(latency_ms) AS latency
           FROM drop_events
           WHERE bin_id = $1 AND time > now() - make_interval(days => $2)
             AND source = 'camera'"""
    r = await db.fetchrow(q, bin_id, days)
    return {
        "days": days, "drops": r["drops"], "confirmed": r["confirmed"], "dismissed": r["dismissed"],
        "confirmed_as_seen_pct": round(100 * r["as_seen"] / r["confirmed"]) if r["confirmed"] else None,
        "avg_confidence": round(r["conf"], 2) if r["conf"] is not None else None,
        "avg_latency_ms": round(r["latency"]) if r["latency"] is not None else None,
    }


@router.post("/bins/{bin_id}/drops/photo", status_code=201)
async def submit_photo(bin_id: str, body: PhotoSubmission) -> dict:
    """Identify one photo the user took, as a pending drop.

    The camera decides for itself that something arrived; this is the user
    pointing a phone at something and asking what it is. It becomes an ordinary
    pending drop_events row, so confirm, dismiss, history, the add_log rows and
    the XP rules all work on it unchanged -- the only difference is source.

    No session is involved. Arming exists so vision/ knows when to look, and
    there is nothing to tell when the photo is already in hand.

    Gemini failing is not an error here: the row is still stored with no items,
    and the user names the item themselves. That is the same path an unknown
    catalog_id already takes, so the sheet needs no new state for it.
    """
    await _bin_or_404(bin_id)

    try:
        jpeg = base64.b64decode(body.image_jpeg_b64, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=422, detail="image is not base64")
    if not jpeg:
        raise HTTPException(status_code=422, detail="image is empty")
    if len(jpeg) > identify.MAX_PHOTO_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"image is {len(jpeg)} bytes; downscale to about 1024 px "
                   f"(limit {identify.MAX_PHOTO_BYTES})")

    started = _now()
    items, model, error = await identify.identify(jpeg)
    latency_ms = int((_now() - started).total_seconds() * 1000)
    top = max((i["confidence"] for i in items), default=None)

    row = await db.fetchrow(
        """INSERT INTO drop_events
               (bin_id, session_id, status, guess, top_confidence, gemini_ok,
                model, error, latency_ms, thumbnail_jpeg, source)
           VALUES ($1, $2, 'pending', $3, $4, $5, $6, $7, $8, $9, 'photo')
           RETURNING *""",
        bin_id, f"photo-{secrets.token_hex(4)}", items, top,
        error is None, model, error, latency_ms, jpeg)
    return _public(row)


@router.get("/bins/{bin_id}/drops/history")
async def history(
    bin_id: str,
    limit: int = Query(20, ge=1, le=100),
    before: datetime | None = Query(None, description="only drops older than this"),
    status: Literal["pending", "confirmed", "dismissed"] | None = None,
) -> dict:
    """Resolved drops, newest first.

    /drops/pending deliberately shows only what is still waiting and only from
    the last hour, so once a drop was confirmed or dismissed its row and its
    photo became unreachable: the bytes sat in Tiger for the 30-day retention
    window with nothing able to read them. This is the way back to them, for
    a history screen and for Trunc's context.

    Thumbnails are not inlined. Twenty base64 photos is several megabytes on a
    phone hotspot, and most callers want the list. `has_photo` says which rows
    have one; GET /drops/{id}/photo fetches it as a real image.
    """
    await _bin_or_404(bin_id)
    rows = await db.fetch(
        """SELECT id, time, session_id, status, guess, final_items, corrected,
                  source, gemini_ok, model, error, latency_ms, top_confidence, resolved_at,
                  thumbnail_jpeg IS NOT NULL AS has_photo
           FROM drop_events
           WHERE bin_id = $1
             AND ($2::timestamptz IS NULL OR time < $2)
             AND ($3::text IS NULL OR status = $3)
           ORDER BY time DESC
           LIMIT $4""",
        bin_id, before, status, limit)
    drops = [
        {
            "id": r["id"],
            "bin_id": bin_id,
            "session_id": r["session_id"],
            "time": r["time"].isoformat(),
            "status": r["status"],
            "items": r["guess"],
            "source": r["source"],
            # What the user settled on, null while still pending. Worth having
            # beside `items`: together they show where the camera was wrong.
            "final_items": r["final_items"],
            "corrected": r["corrected"],
            "gemini_ok": r["gemini_ok"],
            "model": r["model"],
            "error": r["error"],
            "latency_ms": r["latency_ms"],
            "top_confidence": r["top_confidence"],
            "resolved_at": r["resolved_at"].isoformat() if r["resolved_at"] else None,
            "has_photo": r["has_photo"],
        }
        for r in rows
    ]
    return {
        "bin_id": bin_id,
        "drops": drops,
        # Pass back as `before` for the next page; null when the list is short
        # of the limit, meaning there is nothing older.
        "next_before": drops[-1]["time"] if len(drops) == limit else None,
    }


@router.get("/drops/{drop_id}")
async def one(drop_id: int) -> dict:
    """A single drop, thumbnail inlined, whatever its status."""
    return _public(await _drop_or_404(drop_id))


@router.get("/drops/{drop_id}/photo")
async def photo(drop_id: int) -> Response:
    """The stored frame as a real JPEG, so it can be shown without base64.

    Immutable once written, so it is safe to cache hard; the retention policy
    deletes the row at 30 days rather than changing it.
    """
    row = await _drop_or_404(drop_id)
    if row["thumbnail_jpeg"] is None:
        raise HTTPException(status_code=404, detail="no photo for this drop")
    return Response(
        content=bytes(row["thumbnail_jpeg"]),
        media_type="image/jpeg",
        headers={"Cache-Control": "public, max-age=86400, immutable"},
    )


# --- vision service ---------------------------------------------------------------

@router.get("/bins/{bin_id}/drops/session/active")
async def active(bin_id: str):
    """vision/ polls this once a second. 204 = not armed."""
    row = await db.fetchrow(
        """SELECT session_id, expires_at FROM drop_sessions
           WHERE bin_id = $1 AND closed_at IS NULL AND expires_at > now()
           ORDER BY created_at DESC LIMIT 1""", bin_id)
    if row is None:
        return Response(status_code=204)
    return {"session_id": row["session_id"], "expires_at": row["expires_at"].isoformat()}


@router.post("/bins/{bin_id}/drops", status_code=201)
async def report(bin_id: str, body: DropReport) -> dict:
    """vision/ reports a detection. Stored as pending until the user confirms."""
    sess = await db.fetchrow(
        "SELECT closed_at FROM drop_sessions WHERE session_id = $1 AND bin_id = $2", body.session_id, bin_id)
    if sess is None:
        raise HTTPException(status_code=404, detail="unknown session")
    try:
        thumb = base64.b64decode(body.thumbnail_jpeg_b64, validate=True) if body.thumbnail_jpeg_b64 else None
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=422, detail="thumbnail is not base64")
    if thumb and len(thumb) > MAX_THUMB_BYTES:
        raise HTTPException(status_code=413, detail="thumbnail too large")

    items = []
    for it in body.items:
        d = it.model_dump()
        d["category"] = rules_category(it.label, it.category, it.catalog_id)
        if d["amount"] is None and d["est_grams"]:
            d["amount"] = "small" if d["est_grams"] < 60 else "handful" if d["est_grams"] < 180 else "large"
        items.append(d)
    top = max((i["confidence"] for i in items), default=None)

    async with db.pool().acquire() as conn, conn.transaction():
        current = await conn.fetchrow("SELECT * FROM drop_sessions WHERE session_id=$1 FOR UPDATE", body.session_id)
        previous = await conn.fetchrow("SELECT id FROM drop_events WHERE session_id=$1 LIMIT 1", body.session_id)
        if previous is not None:
            return {'drop_id': previous['id'], 'status': 'pending'}
        if current['closed_at'] is not None or current['expires_at'] < _now():
            raise HTTPException(409, 'session is no longer armed')
        row = await conn.fetchrow(
            """INSERT INTO drop_events (bin_id, session_id, guess, top_confidence, gemini_ok, model,
                                         error, latency_ms, thumbnail_jpeg)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id""",
            bin_id, body.session_id, items, top, body.gemini_ok, body.model, body.error,
            body.latency_ms, thumb)
        await conn.execute(
            """UPDATE drop_sessions SET closed_at = now(), close_reason = 'reported'
               WHERE session_id = $1 AND closed_at IS NULL""", body.session_id)
    return {"drop_id": row["id"], "status": "pending"}


@router.post("/bins/{bin_id}/drops/session/{session_id}/close")
async def close(bin_id: str, session_id: str, body: SessionClose) -> dict:
    """vision/ saw nothing in the window: the sheet says 'Didn't see anything'."""
    row = await db.fetchrow(
        """UPDATE drop_sessions SET closed_at = coalesce(closed_at, now()),
                  close_reason = coalesce(close_reason, $3)
           WHERE session_id = $1 AND bin_id = $2 RETURNING session_id""", session_id, bin_id, body.reason)
    if row is None:
        raise HTTPException(status_code=404, detail="unknown session")
    return {"session_id": session_id, "closed": True, "reason": body.reason}


@router.get("/bins/{bin_id}/drops/hints")
async def hints(bin_id: str) -> dict:
    """Recent corrections, fed back to Gemini ('in this bin, X turned out to be Y')."""
    rows = await db.fetch(
        """SELECT guess, final_items, status FROM drop_events
           WHERE bin_id = $1 AND corrected AND resolved_at IS NOT NULL
           ORDER BY resolved_at DESC LIMIT $2""", bin_id, HINTS)
    out = []
    for r in rows:
        seen = r["guess"][0]["label"] if r["guess"] else None
        if not seen:
            continue
        if r["status"] == "dismissed":
            out.append(f'"{seen}" was a false trigger (nothing was added)')
        elif r["final_items"]:
            out.append(f'looked like "{seen}", was "{r["final_items"][0]["label"]}"')
    return {"hints": out}
