"""POST /ingest -- the ESP32 (or the USB serial bridge) sending one sample."""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from .. import db
from ..rules import compost
from ..models import IngestPayload, IngestResult
from ..security import require_device

log = logging.getLogger("calmpost.ingest")

router = APIRouter(tags=["ingest"])

# Samples stored since this process started. Uvicorn's access log only says
# "POST /ingest 200 OK", which looks identical whether the reading was good,
# empty, or had a dead sensor -- so the count and the values are logged here
# instead. This is the line to watch when you want to see the pipeline work.
_stored = 0


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
        """SELECT moisture_raw_dry, moisture_raw_wet, calibrated,
                  moisture_raw_dry_2, moisture_raw_wet_2, calibrated_2
           FROM bins WHERE bin_id = $1""",
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
    # Probe 2 has its own calibration: different physical sensor, different
    # dry/wet counts. Sharing probe 1's would quietly mis-scale it.
    pct2 = compost.moisture_pct(
        payload.moisture_raw_2, binr["moisture_raw_dry_2"], binr["moisture_raw_wet_2"]
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
                     moisture_pct, co2_ppm, air_temp_c, air_humidity_pct, co2_status,
                     probe_temp_c_2, moisture_raw_2, moisture_pct_2)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
                ON CONFLICT (bin_id, time) DO UPDATE SET
                    probe_temp_c     = COALESCE(EXCLUDED.probe_temp_c,     readings.probe_temp_c),
                    moisture_raw     = COALESCE(EXCLUDED.moisture_raw,     readings.moisture_raw),
                    moisture_pct     = COALESCE(EXCLUDED.moisture_pct,     readings.moisture_pct),
                    co2_ppm          = COALESCE(EXCLUDED.co2_ppm,          readings.co2_ppm),
                    air_temp_c       = COALESCE(EXCLUDED.air_temp_c,       readings.air_temp_c),
                    air_humidity_pct = COALESCE(EXCLUDED.air_humidity_pct, readings.air_humidity_pct),
                    co2_status       = COALESCE(EXCLUDED.co2_status,       readings.co2_status),
                    probe_temp_c_2   = COALESCE(EXCLUDED.probe_temp_c_2,   readings.probe_temp_c_2),
                    moisture_raw_2   = COALESCE(EXCLUDED.moisture_raw_2,   readings.moisture_raw_2),
                    moisture_pct_2   = COALESCE(EXCLUDED.moisture_pct_2,   readings.moisture_pct_2)
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
                payload.probe_temp_c_2,
                payload.moisture_raw_2,
                pct2,
            )
            await conn.execute(
                "UPDATE bins SET last_seen_at = $2 WHERE bin_id = $1", auth_bin_id, ts
            )

    global _stored
    _stored += 1

    # One readable line per stored sample: what arrived, what it became, and
    # anything missing or flagged.
    bits = [f"#{_stored}", auth_bin_id]
    if payload.moisture_raw is not None:
        bits.append(
            f"raw={payload.moisture_raw}->{pct:.1f}%" if pct is not None
            else f"raw={payload.moisture_raw}->?"
        )
    else:
        bits.append("raw=none")
    if payload.probe_temp_c is not None:
        delta = (
            f" ({payload.probe_temp_c - payload.air_temp_c:+.1f} vs air)"
            if payload.air_temp_c is not None
            else ""
        )
        bits.append(f"probe={payload.probe_temp_c:.1f}C{delta}")
    else:
        bits.append("probe=none")
    if payload.moisture_raw_2 is not None:
        bits.append(
            f"raw2={payload.moisture_raw_2}->{pct2:.1f}%" if pct2 is not None
            else f"raw2={payload.moisture_raw_2}->?"
        )
        if payload.probe_temp_c_2 is not None:
            bits.append(f"probe2={payload.probe_temp_c_2:.1f}C")
    else:
        bits.append("raw2=none")
    if payload.co2_ppm is not None:
        flag = "" if payload.co2_status in (0, None) else f" !status={payload.co2_status}"
        bits.append(f"co2={payload.co2_ppm:.0f}ppm{flag}")
    else:
        bits.append("co2=none")
    if payload.air_humidity_pct is not None:
        bits.append(f"rh={payload.air_humidity_pct:.0f}%")
    if not binr["calibrated"]:
        bits.append("[uncalibrated]")
    if payload.moisture_raw_2 is not None and not binr["calibrated_2"]:
        bits.append("[probe2 uncalibrated]")

    log.info("stored " + "  ".join(bits))

    return IngestResult(
        accepted=True,
        time=ts,
        moisture_pct=round(pct, 1) if pct is not None else None,
        moisture_pct_2=round(pct2, 1) if pct2 is not None else None,
        calibrated=binr["calibrated"],
    )
