"""Reading the current state of a bin out of Tiger Data.

Shared by GET /bins/{id}/live and the advice endpoint so the numbers a judge
sees on screen are the same numbers Gemini was given.

Uses the hyperfunctions CLAUDE.md calls for:
  - regr_slope  : CO2 trend per hour, which drives the stage decision
  - time_weight : time-weighted average moisture, correct for irregular
                  sample spacing in a way plain avg() is not
  - state_agg / duration_in : how long moisture actually sat in the healthy
                  band, rather than what fraction of samples happened to be
"""

import hashlib
import json
from datetime import datetime, timedelta, timezone

from . import compost, db

# A bin that has not reported for this long is shown as offline.
STALE_AFTER = timedelta(minutes=20)


async def bin_row(bin_id: str):
    return await db.fetchrow(
        """
        SELECT bin_id, display_name, owner_id, moisture_raw_dry,
               moisture_raw_wet, calibrated, last_seen_at
        FROM bins WHERE bin_id = $1
        """,
        bin_id,
    )


async def latest_reading(bin_id: str):
    return await db.fetchrow(
        """
        SELECT time, probe_layer, probe_temp_c, moisture_raw, moisture_pct,
               co2_ppm, air_temp_c, air_humidity_pct, co2_status
        FROM readings
        WHERE bin_id = $1
        ORDER BY time DESC
        LIMIT 1
        """,
        bin_id,
    )


async def co2_slope_per_hour(bin_id: str, hours: int = 6) -> float | None:
    """ppm change per hour over the recent window.

    regr_slope is plain Postgres over (y, x); x is seconds since epoch, so
    the raw slope is ppm/second and gets scaled to the hour for readability.
    """
    row = await db.fetchrow(
        """
        SELECT regr_slope(co2_ppm, extract(epoch FROM time)) AS slope,
               count(*) AS n
        FROM readings
        WHERE bin_id = $1
          AND time >= now() - ($2 || ' hours')::interval
          AND co2_ppm IS NOT NULL
          AND coalesce(co2_status, 0) = 0
        """,
        bin_id,
        str(hours),
    )
    if row is None or row["slope"] is None or row["n"] < 3:
        return None
    return float(row["slope"]) * 3600.0


async def time_weighted_moisture(bin_id: str, hours: int = 6) -> float | None:
    """Time-weighted mean moisture, via the toolkit's time_weight."""
    row = await db.fetchrow(
        """
        SELECT average(time_weight('linear', time, moisture_pct)) AS avg_pct
        FROM readings
        WHERE bin_id = $1
          AND time >= now() - ($2 || ' hours')::interval
          AND moisture_pct IS NOT NULL
        """,
        bin_id,
        str(hours),
    )
    return float(row["avg_pct"]) if row and row["avg_pct"] is not None else None


async def hours_in_healthy_band(bin_id: str, hours: int = 24) -> float | None:
    """How long moisture actually sat inside the 40-60% band.

    state_agg tracks the duration of each state rather than counting
    samples, so an irregular reporting interval does not skew it.
    """
    low, high = compost.MOISTURE_BAND
    row = await db.fetchrow(
        """
        WITH states AS (
            SELECT time,
                   CASE
                       WHEN moisture_pct IS NULL      THEN 'unknown'
                       WHEN moisture_pct < $3         THEN 'dry'
                       WHEN moisture_pct > $4         THEN 'wet'
                       ELSE 'ok'
                   END AS state
            FROM readings
            WHERE bin_id = $1
              AND time >= now() - ($2 || ' hours')::interval
        )
        SELECT duration_in(state_agg(time, state), 'ok') AS in_band
        FROM states
        """,
        bin_id,
        str(hours),
        low,
        high,
    )
    if row is None or row["in_band"] is None:
        return None
    return round(row["in_band"].total_seconds() / 3600.0, 2)


async def balance_counts(bin_id: str, days: int = 7) -> tuple[int, int]:
    """Greens and browns actually added in the window (skips don't count)."""
    row = await db.fetchrow(
        """
        SELECT
            count(*) FILTER (WHERE category = 'green') AS greens,
            count(*) FILTER (WHERE category = 'brown') AS browns
        FROM add_log
        WHERE bin_id = $1
          AND action = 'added'
          AND time >= now() - ($2 || ' days')::interval
        """,
        bin_id,
        str(days),
    )
    return (int(row["greens"]), int(row["browns"])) if row else (0, 0)


async def snapshot(bin_id: str) -> dict | None:
    """Everything the live view and the model need, in one shape.

    Returns None when the bin has never reported, so callers can answer
    honestly instead of charting zeros.
    """
    binr = await bin_row(bin_id)
    if binr is None:
        return None

    latest = await latest_reading(bin_id)
    if latest is None:
        return None

    greens, browns = await balance_counts(bin_id)
    slope = await co2_slope_per_hour(bin_id)
    tw_moisture = await time_weighted_moisture(bin_id)
    in_band = await hours_in_healthy_band(bin_id)

    co2_ok = (latest["co2_status"] or 0) == 0
    probe_layer = latest["probe_layer"]
    pct = latest["moisture_pct"]

    layers: dict[str, dict] = {}
    for layer in ("top", "bottom"):
        if layer == probe_layer:
            layers[layer] = {
                "measured": True,
                "moisture_pct": pct,
                "moisture_raw": latest["moisture_raw"],
                "moisture_state": compost.moisture_state(pct),
                "temp_c": latest["probe_temp_c"],
            }
        else:
            # No second probe in this build. Say so rather than imply 0.
            layers[layer] = {
                "measured": False,
                "moisture_pct": None,
                "moisture_raw": None,
                "moisture_state": "unknown",
                "temp_c": None,
            }

    now = datetime.now(timezone.utc)
    last_seen = binr["last_seen_at"]
    stale = last_seen is None or (now - last_seen) > STALE_AFTER

    notes: list[str] = []
    if not binr["calibrated"]:
        notes.append(
            "Moisture probe is not calibrated yet, so the percentage is a rough "
            "guess. Calibrate with POST /bins/{bin_id}/calibration."
        )
    if not co2_ok:
        notes.append(
            f"CO2 sensor reported status {latest['co2_status']}, so its reading "
            "is being treated as unreliable."
        )
    if not layers["bottom"]["measured"]:
        notes.append(
            "Only one probe is fitted, so the bottom layer is unmeasured and its "
            "stage is a guess from the air-gap readings."
        )
    if stale:
        notes.append("The bin has not reported recently.")

    return {
        "bin_id": bin_id,
        "last_seen_at": last_seen,
        "stale": stale,
        "measured_at": latest["time"],
        "layers": layers,
        "air": {
            "co2_ppm": latest["co2_ppm"],
            "co2_ok": co2_ok,
            "co2_status": latest["co2_status"],
            "co2_slope_per_hour": round(slope, 2) if slope is not None else None,
            "air_temp_c": latest["air_temp_c"],
            "air_humidity_pct": latest["air_humidity_pct"],
        },
        "moisture_time_weighted_6h": round(tw_moisture, 1) if tw_moisture is not None else None,
        "hours_in_healthy_band_24h": in_band,
        "greens_7d": greens,
        "browns_7d": browns,
        "healthy_band": list(compost.MOISTURE_BAND),
        "moisture_calibrated": binr["calibrated"],
        "notes": notes,
    }


def health_components(snap: dict) -> dict:
    """The four terms domain/health_score.dart multiplies by its weights."""
    probe = next(
        (v for v in snap["layers"].values() if v["measured"]),
        {"moisture_pct": None, "temp_c": None},
    )
    slope = snap["air"].get("co2_slope_per_hour")

    # A falling CO2 curve is a healthy, maturing pile; a sharply rising one
    # means it is overloaded. Mapped onto 0-100 around a flat trend.
    co2_trend = None
    if slope is not None and snap["air"].get("co2_ok", True):
        co2_trend = max(0.0, min(100.0, 50.0 - slope * 0.5))

    return {
        "moisture": compost.moisture_component(probe["moisture_pct"]),
        "temperature": compost.temperature_component(probe["temp_c"]),
        "co2_trend": co2_trend,
        "balance": compost.balance_component(snap["greens_7d"], snap["browns_7d"]),
    }


def state_hash(snap: dict, item: str | None) -> str:
    """Fingerprint of what should change an answer.

    Values are rounded so sensor jitter reuses a cached answer, while a real
    change produces a new one -- which is the demo moment.
    """
    probe = next((v for v in snap["layers"].values() if v["measured"]), {})
    coarse = {
        "item": (item or "").strip().lower(),
        "moisture": round(probe.get("moisture_pct") / 5) if probe.get("moisture_pct") is not None else None,
        "temp": round(probe.get("temp_c") / 2) if probe.get("temp_c") is not None else None,
        "co2": round(snap["air"]["co2_ppm"] / 250) if snap["air"].get("co2_ppm") is not None else None,
        "co2_ok": snap["air"].get("co2_ok", True),
        "greens": snap["greens_7d"],
        "browns": snap["browns_7d"],
    }
    return hashlib.sha256(
        json.dumps(coarse, sort_keys=True, default=str).encode()
    ).hexdigest()
