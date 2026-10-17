"""POST /bins/{id}/advice/check -- the verdict sheet. Our demo moment.

Every answer is stored with the sensor snapshot it was based on, so when the
same scrap gets a different verdict we can show *why* rather than asserting
it.
"""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query

from .. import binstate, db, gemini
from ..config import get_settings
from ..models import AdviceCheck, AdviceResponse
from ..security import require_app_key

router = APIRouter(tags=["advice"], dependencies=[Depends(require_app_key)])


@router.post("/bins/{bin_id}/advice/check", response_model=AdviceResponse)
async def check(
    bin_id: str,
    body: AdviceCheck,
    refresh: bool = Query(False, description="skip the cache and re-ask"),
) -> AdviceResponse:
    return await _advise(bin_id, body.item, refresh)


@router.get("/bins/{bin_id}/advice", response_model=AdviceResponse)
async def whole_bin_advice(
    bin_id: str,
    refresh: bool = Query(False, description="skip the cache and re-ask"),
) -> AdviceResponse:
    """Whole-bin advice for the Home screen's "Wren suggests" card."""
    return await _advise(bin_id, None, refresh)


async def _advise(bin_id: str, item: str | None, refresh: bool) -> AdviceResponse:
    settings = get_settings()

    binr = await binstate.bin_row(bin_id)
    if binr is None:
        raise HTTPException(status_code=404, detail="unknown bin")

    snap = await binstate.snapshot(bin_id)
    if snap is None:
        raise HTTPException(status_code=409, detail="no readings for this bin yet")

    state_hash = binstate.state_hash(snap, item)

    if not refresh:
        cutoff = datetime.now(timezone.utc) - timedelta(
            seconds=settings.advice_ttl_seconds
        )
        cached = await db.fetchrow(
            """
            SELECT id, time, model, payload, input_snapshot
            FROM advice
            WHERE bin_id = $1
              AND state_hash = $2
              AND item IS NOT DISTINCT FROM $3
              AND time >= $4
            ORDER BY time DESC
            LIMIT 1
            """,
            bin_id,
            state_hash,
            item,
            cutoff,
        )
        if cached is not None:
            return _to_response(
                cached["id"], bin_id, item, cached["payload"], cached["model"],
                cached["time"], True, cached["input_snapshot"],
            )

    payload, model = await gemini.advise(snap, item)

    # Store the snapshot as given to the model, minus the advisory prose.
    proof = {
        "measured_at": snap["time"],
        "layers": snap["layers"],
        "stages": snap["stages"],
        "air": snap["air"],
        "greens_7d_cups": snap["greens_7d"],
        "browns_7d_cups": snap["browns_7d"],
        "moisture_time_weighted_6h": snap["moisture_time_weighted_6h"],
        "healthy_hours_today": snap["healthy_hours_today"],
        "moisture_calibrated": snap["moisture_calibrated"],
    }

    row = await db.fetchrow(
        """
        INSERT INTO advice
            (bin_id, item, model, state_hash, verdict, headline, reason, balance,
             stage_top, stage_bottom, bottom_ready, tip,
             suggest_add, suggest_avoid, pair_with, input_snapshot, payload)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
        RETURNING id, time
        """,
        bin_id,
        item,
        model,
        state_hash,
        payload.get("verdict"),
        payload.get("headline"),
        payload.get("reason"),
        payload.get("balance"),
        payload.get("stage_top"),
        payload.get("stage_bottom"),
        bool(payload.get("bottom_ready", False)),
        payload.get("tip"),
        payload.get("suggest_add", []),
        payload.get("suggest_avoid", []),
        payload.get("pair_with", []),
        proof,
        payload,
    )

    return _to_response(
        row["id"], bin_id, item, payload, model, row["time"], False, proof
    )


def _to_response(
    advice_id: int,
    bin_id: str,
    item: str | None,
    payload: dict,
    model: str,
    created_at: datetime,
    cached: bool,
    snapshot: dict | None,
) -> AdviceResponse:
    return AdviceResponse(
        advice_id=advice_id,
        bin_id=bin_id,
        item=item,
        created_at=created_at,
        cached=cached,
        model=model,
        verdict=payload.get("verdict", "great"),
        headline=payload.get("headline", ""),
        reason=payload.get("reason", ""),
        pair_with=payload.get("pair_with", []),
        suggest_add=payload.get("suggest_add", []),
        suggest_avoid=payload.get("suggest_avoid", []),
        balance=payload.get("balance", "balanced"),
        stage_top=payload.get("stage_top", "started"),
        stage_bottom=payload.get("stage_bottom", "started"),
        bottom_ready=bool(payload.get("bottom_ready", False)),
        tip=payload.get("tip"),
        input_snapshot=snapshot,
    )
