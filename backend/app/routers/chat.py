"""POST /bins/{id}/chat -- Trunc, the in-app compost assistant.

The context is assembled here and the answering lives in services/trunc.py.
Everything it draws on already existed: binstate.snapshot for the readings,
binstate.recent_adds for what went in, and drop_events for the camera photos
that /bins/{id}/drops/history made reachable.

Stateless by design. The client sends the conversation back each turn, so
there is no chat table, nothing to grow unbounded in Tiger, and no stored
history to leak between accounts.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from .. import db
from ..security import require_app_key
from ..services import binstate, trunc

log = logging.getLogger(__name__)

router = APIRouter(tags=["chat"], dependencies=[Depends(require_app_key)])


class ChatTurn(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    text: str = Field(min_length=1, max_length=2000)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=1000)
    history: list[ChatTurn] = Field(default_factory=list, max_length=20)
    #: Off for a text-only turn, which is cheaper and faster.
    include_photos: bool = True


class ChatContext(BaseModel):
    """What Trunc actually had to work with, so a UI can be honest about it."""
    readings_at: str | None = None
    recent_adds: int = 0
    photos: int = 0
    readings_stale: bool = False


class ChatReply(BaseModel):
    reply: str
    model: str
    on_topic: bool
    used_readings: bool = False
    context: ChatContext
    need: str | None = None


async def _photos(bin_id: str, limit: int) -> list[dict]:
    """The newest camera frames, with what the camera and the user each said.

    Only drops that actually have a photo; a motion trigger with no frame is
    no use as context.
    """
    rows = await db.fetch(
        """SELECT guess, final_items, thumbnail_jpeg,
                  extract(epoch FROM now() - time) / 3600.0 AS hours_ago
           FROM drop_events
           WHERE bin_id = $1 AND thumbnail_jpeg IS NOT NULL
           ORDER BY time DESC
           LIMIT $2""",
        bin_id, limit)
    return [
        {
            "jpeg": bytes(r["thumbnail_jpeg"]),
            "hours_ago": round(float(r["hours_ago"]), 1),
            "labels": [i.get("label") for i in (r["guess"] or [])],
            "confirmed": [i.get("label") for i in (r["final_items"] or [])] or None,
        }
        for r in rows
    ]


@router.post("/bins/{bin_id}/chat", response_model=ChatReply)
async def chat(bin_id: str, body: ChatRequest) -> ChatReply:
    """Ask Trunc something. Compost questions only; it declines the rest."""
    if await binstate.bin_row(bin_id) is None:
        raise HTTPException(status_code=404, detail="unknown bin")

    snap = await binstate.snapshot(bin_id)
    if snap is None:
        # Unlike /advice/check this is not a 409: a question like "what are
        # browns?" does not need a reading, and refusing to talk because the
        # bin has never reported would be the wrong call.
        snap = _no_readings_yet()

    recent = await binstate.recent_adds(bin_id)
    photos = await _photos(bin_id, trunc.MAX_PHOTOS) if body.include_photos else []

    payload, model = await trunc.ask(
        body.message,
        snap,
        recent,
        photos,
        [t.model_dump() for t in body.history],
    )

    return ChatReply(
        reply=payload["reply"],
        model=model,
        on_topic=payload["on_topic"],
        used_readings=payload.get("used_readings", False),
        need=payload.get("need"),
        context=ChatContext(
            readings_at=str(snap["time"]) if snap.get("time") else None,
            recent_adds=len(recent),
            photos=payload.get("photos_used", 0),
            readings_stale=trunc.guidance.is_stale(snap),
        ),
    )


def _no_readings_yet() -> dict:
    """A snapshot shaped like the real one, with every value absent.

    Trunc is told a layer whose "measured" is false has no sensor, so this
    makes it say the readings are unknown rather than inventing them.
    """
    layer = {"moisture_pct": None, "moisture_state": None, "temp_c": None, "measured": False}
    return {
        "time": None,
        "layers": {"top": dict(layer), "bottom": dict(layer)},
        "stages": {"top": None, "bottom": None},
        "air": {"ambient_temp_c": None, "co2_ppm": None, "co2_ok": None, "co2_slope_per_day": None},
        "greens_7d": 0.0,
        "browns_7d": 0.0,
        "healthy_band": None,
        "healthy_hours_today": None,
        "moisture_calibrated": False,
    }
