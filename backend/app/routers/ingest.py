"""POST /ingest -- the ESP32 (or the USB serial bridge) sending one sample."""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from .. import compost, db
from ..models import IngestPayload, IngestResult
from ..security import require_device

log = logging.getLogger(__name__)

router = APIRouter(tags=["ingest"])


@router.post("/ingest", response_model=IngestResult)
async def ingest(
    payload: IngestPayload, auth_bin_id: str = Depends(require_device)
) -> IngestResult:
    """Store one wide reading.

    The firmware sends `device_id`; everything else calls it `bin_id`. The
    token decides which bin this is, and a mismatch is rejected rather than
    trusted, so one bin's token cannot write another's history.
    """
    if payload.bin_id != auth_bin_id:
        raise HTTPException(status_code=403, detail="token does not match device_id")

    binr = await db.fetchrow(
        "SELECT moisture_raw_dry, moisture_raw_wet, calibrated FROM bins WHERE bin_id = $1",
        auth_bin_id,
    )
    if binr is None:
        raise HTTPException(status_code=404, detail="unknown bin")

    # The board has no reliable clock and a skewed one would scatter points
    # across the charts, so the server stamps arrival unless told otherwise.
    ts = payload.time or datetime.now(timezone.utc)
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)

    # The probe reports raw ADC counts; percentage is derived here so the
    # firmware never has to know its own calibration.
    pct = compost.moisture_pct(
        payload.moisture_raw, binr["moisture_raw_dry"], binr["moisture_raw_wet"]
    )

    if payload.co2_status not in (None, 0):
        log.warning(
            "bin %s reported co2_status=%s; treating CO2 as unreliable",
            auth_bin_id,
            payload.co2_status,
        )

    async with db.pool().acquire() as conn:
        async with conn.transaction():
            # ON CONFLICT makes a bridge retry harmless: a resend of the same
            # timestamp fills in gaps rather than duplicating or erasing.
            await conn.execute(
                """
                INSERT INTO readings
                    (time, bin_id, probe_layer, probe_temp_c, moisture_raw,
                     moisture_pct, co2_ppm, air_temp_c, air_humidity_pct, co2_status)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
                ON CONFLICT (bin_id, time) DO UPDATE SET
                    probe_temp_c     = COALESCE(EXCLUDED.probe_temp_c,     readings.probe_temp_c),
                    moisture_raw     = COALESCE(EXCLUDED.moisture_raw,     readings.moisture_raw),
                    moisture_pct     = COALESCE(EXCLUDED.moisture_pct,     readings.moisture_pct),
                    co2_ppm          = COALESCE(EXCLUDED.co2_ppm,          readings.co2_ppm),
                    air_temp_c       = COALESCE(EXCLUDED.air_temp_c,       readings.air_temp_c),
                    air_humidity_pct = COALESCE(EXCLUDED.air_humidity_pct, readings.air_humidity_pct),
                    co2_status       = COALESCE(EXCLUDED.co2_status,       readings.co2_status)
                """,
                ts,
                auth_bin_id,
                payload.probe_layer,
                payload.probe_temp_c,
                payload.moisture_raw,
                pct,
                payload.co2_ppm,
                payload.air_temp_c,
                payload.air_humidity_pct,
                payload.co2_status,
            )
            await conn.execute(
                "UPDATE bins SET last_seen_at = $2 WHERE bin_id = $1", auth_bin_id, ts
            )

    return IngestResult(
        accepted=True,
        time=ts,
        moisture_pct=round(pct, 1) if pct is not None else None,
        calibrated=binr["calibrated"],
    )
