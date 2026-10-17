"""Backend -> Flutter. Latest state and trend history."""

from fastapi import APIRouter, Depends, HTTPException, Query

from .. import compost, db
from ..models import (
    HistoryPoint,
    HistoryResponse,
    LatestResponse,
    Zone,
    ZoneStatus,
)
from ..security import require_app_key

router = APIRouter(prefix="/v1", tags=["readings"], dependencies=[Depends(require_app_key)])

ZONE_LABELS = {"top": "Top layer", "bottom": "Bottom layer", "airgap": "Air gap"}


@router.get("/devices/{device_id}/latest", response_model=LatestResponse)
async def latest(device_id: str) -> LatestResponse:
    device = await db.fetchrow(
        "SELECT device_id, last_seen_at FROM devices WHERE device_id = $1", device_id
    )
    if device is None:
        raise HTTPException(status_code=404, detail="unknown device")

    # DISTINCT ON with the (device_id, zone, time DESC) index is an index-only
    # skip scan -- cheap even with weeks of samples.
    rows = await db.fetch(
        """
        SELECT DISTINCT ON (zone)
               zone, time, moisture_pct, temperature_c, co2_ppm
        FROM readings
        WHERE device_id = $1
        ORDER BY zone, time DESC
        """,
        device_id,
    )
    by_zone = {r["zone"]: r for r in rows}

    zones = []
    for zone in ("top", "bottom", "airgap"):
        r = by_zone.get(zone)
        zones.append(
            ZoneStatus(
                zone=zone,
                label=ZONE_LABELS[zone],
                time=r["time"] if r else None,
                moisture_pct=r["moisture_pct"] if r else None,
                temperature_c=r["temperature_c"] if r else None,
                co2_ppm=r["co2_ppm"] if r else None,
                moisture_state=compost.moisture_state(
                    r["moisture_pct"] if r else None
                ),
            )
        )

    return LatestResponse(
        device_id=device_id, last_seen_at=device["last_seen_at"], zones=zones
    )


@router.get("/devices/{device_id}/history", response_model=HistoryResponse)
async def history(
    device_id: str,
    zone: Zone = Query(...),
    hours: int = Query(24, ge=1, le=720),
) -> HistoryResponse:
    """Hourly buckets for the charts.

    Reads the continuous aggregate for older data and raw rows for the last
    hour, so a chart opened mid-demo still shows the sample just ingested.
    """
    rows = await db.fetch(
        """
        SELECT bucket, moisture_pct_avg, temperature_c_avg, co2_ppm_avg
        FROM readings_hourly
        WHERE device_id = $1 AND zone = $2 AND bucket >= now() - ($3 || ' hours')::interval
        UNION ALL
        SELECT time_bucket('1 hour', time) AS bucket,
               avg(moisture_pct), avg(temperature_c), avg(co2_ppm)
        FROM readings
        WHERE device_id = $1 AND zone = $2 AND time >= date_trunc('hour', now())
        GROUP BY 1
        ORDER BY bucket
        """,
        device_id,
        zone,
        str(hours),
    )
    return HistoryResponse(
        device_id=device_id,
        zone=zone,
        hours=hours,
        points=[
            HistoryPoint(
                bucket=r["bucket"],
                moisture_pct=r["moisture_pct_avg"],
                temperature_c=r["temperature_c_avg"],
                co2_ppm=r["co2_ppm_avg"],
            )
            for r in rows
        ],
    )
