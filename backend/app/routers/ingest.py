"""Arduino -> backend. One POST per sample, authenticated by device token."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from .. import db
from ..models import IngestPayload, IngestResult
from ..security import require_device

router = APIRouter(prefix="/v1", tags=["ingest"])


@router.post("/ingest", response_model=IngestResult)
async def ingest(
    payload: IngestPayload, device_id: str = Depends(require_device)
) -> IngestResult:
    if payload.device_id != device_id:
        raise HTTPException(status_code=403, detail="token does not match device_id")

    # The board may have no clock on first boot, and a wildly skewed clock
    # would scatter points across the charts, so trust the server instead.
    ts = payload.time or datetime.now(timezone.utc)
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)

    rows = [
        (ts, device_id, s.zone, s.moisture_pct, s.temperature_c, s.co2_ppm)
        for s in payload.zones
    ]

    async with db.pool().acquire() as conn:
        async with conn.transaction():
            # ON CONFLICT makes a firmware retry harmless.
            await conn.executemany(
                """
                INSERT INTO readings
                    (time, device_id, zone, moisture_pct, temperature_c, co2_ppm)
                VALUES ($1, $2, $3, $4, $5, $6)
                ON CONFLICT (device_id, zone, time) DO UPDATE SET
                    moisture_pct  = COALESCE(EXCLUDED.moisture_pct,  readings.moisture_pct),
                    temperature_c = COALESCE(EXCLUDED.temperature_c, readings.temperature_c),
                    co2_ppm       = COALESCE(EXCLUDED.co2_ppm,       readings.co2_ppm)
                """,
                rows,
            )
            await conn.execute(
                "UPDATE devices SET last_seen_at = $2 WHERE device_id = $1",
                device_id,
                ts,
            )

    return IngestResult(accepted=len(rows), time=ts)
