"""Gemini-backed recommendations for the bin's current state."""

import hashlib
import json
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query

from .. import db, gemini
from ..config import get_settings
from ..models import AdviceResponse, Suggestion
from ..security import require_app_key

router = APIRouter(prefix="/v1", tags=["advice"], dependencies=[Depends(require_app_key)])


async def _collect_state(device_id: str) -> dict:
    """The snapshot handed to Gemini: current readings, 6h trend, recent adds."""
    zone_rows = await db.fetch(
        """
        SELECT DISTINCT ON (zone) zone, time, moisture_pct, temperature_c, co2_ppm
        FROM readings
        WHERE device_id = $1
        ORDER BY zone, time DESC
        """,
        device_id,
    )
    trend_rows = await db.fetch(
        """
        SELECT zone,
               avg(moisture_pct)  AS moisture_pct,
               avg(temperature_c) AS temperature_c,
               avg(co2_ppm)       AS co2_ppm
        FROM readings
        WHERE device_id = $1 AND time >= now() - interval '6 hours'
        GROUP BY zone
        """,
        device_id,
    )
    log_rows = await db.fetch(
        """
        SELECT item, category, time
        FROM add_log
        WHERE device_id = $1 AND time >= now() - interval '7 days'
        ORDER BY time DESC
        LIMIT 20
        """,
        device_id,
    )

    greens = sum(1 for r in log_rows if r["category"] == "green")
    browns = sum(1 for r in log_rows if r["category"] == "brown")

    return {
        "zones": {
            r["zone"]: {
                "moisture_pct": r["moisture_pct"],
                "temperature_c": r["temperature_c"],
                "co2_ppm": r["co2_ppm"],
                "measured_at": r["time"],
            }
            for r in zone_rows
        },
        "six_hour_average": {
            r["zone"]: {
                "moisture_pct": r["moisture_pct"],
                "temperature_c": r["temperature_c"],
                "co2_ppm": r["co2_ppm"],
            }
            for r in trend_rows
        },
        "recent_adds": [
            {"item": r["item"], "category": r["category"], "at": r["time"]}
            for r in log_rows
        ],
        "recent_greens": greens,
        "recent_browns": browns,
        "healthy_moisture_pct": [40, 60],
    }


def _state_hash(state: dict) -> str:
    """Fingerprint the numbers that should change the answer.

    Moisture and temperature are rounded so sensor jitter alone does not
    invalidate a cached answer, but a real change does.
    """
    coarse = {
        zone: [
            round(v["moisture_pct"] / 5) if v["moisture_pct"] is not None else None,
            round(v["temperature_c"] / 2) if v["temperature_c"] is not None else None,
            round(v["co2_ppm"] / 250) if v["co2_ppm"] is not None else None,
        ]
        for zone, v in sorted(state["zones"].items())
    }
    coarse["adds"] = len(state["recent_adds"])
    return hashlib.sha256(
        json.dumps(coarse, sort_keys=True, default=str).encode()
    ).hexdigest()


@router.get("/devices/{device_id}/advice", response_model=AdviceResponse)
async def advice(
    device_id: str,
    refresh: bool = Query(False, description="skip the cache and re-ask Gemini"),
) -> AdviceResponse:
    settings = get_settings()
    device = await db.fetchrow(
        "SELECT device_id FROM devices WHERE device_id = $1", device_id
    )
    if device is None:
        raise HTTPException(status_code=404, detail="unknown device")

    state = await _collect_state(device_id)
    if not state["zones"]:
        raise HTTPException(status_code=409, detail="no readings for this device yet")

    state_hash = _state_hash(state)

    if not refresh:
        cutoff = datetime.now(timezone.utc) - timedelta(
            seconds=settings.advice_ttl_seconds
        )
        cached = await db.fetchrow(
            """
            SELECT created_at, model, payload
            FROM advice
            WHERE device_id = $1 AND state_hash = $2 AND created_at >= $3
            ORDER BY created_at DESC
            LIMIT 1
            """,
            device_id,
            state_hash,
            cutoff,
        )
        if cached is not None:
            return _to_response(device_id, cached["payload"], cached["model"], cached["created_at"], True)

    payload, model = await gemini.advise(state)

    row = await db.fetchrow(
        """
        INSERT INTO advice
            (device_id, model, state_hash, stage_top, stage_bottom, payload)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING created_at
        """,
        device_id,
        model,
        state_hash,
        payload.get("stage_top"),
        payload.get("stage_bottom"),
        payload,
    )
    return _to_response(device_id, payload, model, row["created_at"], False)


def _to_response(
    device_id: str, payload: dict, model: str, created_at: datetime, cached: bool
) -> AdviceResponse:
    return AdviceResponse(
        device_id=device_id,
        created_at=created_at,
        cached=cached,
        model=model,
        headline=payload.get("headline", ""),
        balance=payload.get("balance", "unknown"),
        stage_top=payload.get("stage_top", "unknown"),
        stage_bottom=payload.get("stage_bottom", "unknown"),
        bottom_ready=bool(payload.get("bottom_ready", False)),
        suggestions=[Suggestion(**s) for s in payload.get("suggestions", [])],
        warnings=payload.get("warnings", []),
    )
