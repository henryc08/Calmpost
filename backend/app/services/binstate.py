"""Reading the current state of a bin out of Tiger Data.

Shared by GET /bins/{id}/live and the advice endpoints, so the numbers a
judge sees on screen are the numbers Gemini was given.

Field names and units match BinSnapshot in app/lib/domain/models.dart, so
ApiRepository is a direct fromJson rather than a translation layer. Two units
to be careful about:
  - co2_slope_per_day is % per day (the app's co2SlopePerDay), not ppm/hour
  - greens_7d / browns_7d are rough CUPS of volume, not item counts

Uses the hyperfunctions AGENT.md calls for: regr_slope (CO2 trend ->
stage), time_weight (time-weighted moisture), state_agg/duration_in (hours
actually inside the healthy band).
"""

import hashlib
import json
from datetime import datetime, timedelta, timezone

from .. import db
from ..rules import compost

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


async def co2_slope_per_day(bin_id: str, hours: int = 48) -> float | None:
    """CO2 trend as PERCENT PER DAY, matching the app's co2SlopePerDay.

    regr_slope is plain Postgres over (y, x) with x in seconds, giving
    ppm/second; that is scaled to a day and expressed as a share of the mean
    level, so a pile winding down reads about the same whether it peaked at
    1000 or 6000 ppm.

    The app looks at a 48 h trend, so that is the default window.
    """
    row = await db.fetchrow(
        """
        SELECT regr_slope(co2_ppm, extract(epoch FROM time)) AS slope,
               avg(co2_ppm) AS mean,
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
    mean = float(row["mean"] or 0)
    if mean <= 0:
        return None
    ppm_per_day = float(row["slope"]) * 86400.0
    return ppm_per_day / mean * 100.0


async def time_weighted_moisture(bin_id: str, hours: int = 6) -> float | None:
    """Time-weighted mean moisture, via the toolkit's time_weight.

    Correct for irregular sample spacing in a way plain avg() is not: the
    board samples every second while connected and not at all when it is not.
    """
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


async def healthy_hours_today(bin_id: str) -> float | None:
    """Hours moisture sat inside the band since midnight (healthyHoursToday).

    state_agg tracks the duration of each state rather than counting samples,
    so a reporting gap does not skew it.
    """
    row = await db.fetchrow(
        """
        WITH states AS (
            SELECT time,
                   CASE
                       WHEN moisture_pct IS NULL     THEN 'unknown'
                       WHEN moisture_pct < $2        THEN 'dry'
                       WHEN moisture_pct > $3        THEN 'wet'
                       ELSE 'ok'
                   END AS state
            FROM readings
            WHERE bin_id = $1 AND time >= date_trunc('day', now())
        )
        SELECT duration_in(state_agg(time, state), 'ok') AS in_band
        FROM states
        """,
        bin_id,
        compost.MOISTURE_LO,
        compost.MOISTURE_HI,
    )
    if row is None or row["in_band"] is None:
        return None
    return round(row["in_band"].total_seconds() / 3600.0, 2)


async def balance_cups(bin_id: str, days: int = 7) -> tuple[float, float]:
    """Greens and browns added in the window, in rough cups.

    The app's balance ratio is a volume comparison, so grams are converted
    rather than counting items: one cabbage is not one coffee ground. Items
    logged without a weight fall back to one cup.
    """
    row = await db.fetchrow(
        """
        SELECT
            coalesce(sum(CASE WHEN category = 'green'
                              THEN coalesce(quantity_g, $3) END), 0) AS green_g,
            coalesce(sum(CASE WHEN category = 'brown'
                              THEN coalesce(quantity_g, $3) END), 0) AS brown_g
        FROM add_log
        WHERE bin_id = $1
          AND action = 'added'
          AND time >= now() - ($2 || ' days')::interval
        """,
        bin_id,
        str(days),
        int(compost.CUP_GRAMS),
    )
    if row is None:
        return 0.0, 0.0
    return (
        round(float(row["green_g"]) / compost.CUP_GRAMS, 2),
        round(float(row["brown_g"]) / compost.CUP_GRAMS, 2),
    )


async def snapshot(bin_id: str) -> dict | None:
    """Everything the live view and the model need, in one shape.

    Returns None when the bin has never reported, so callers answer honestly
    instead of charting zeros.
    """
    binr = await bin_row(bin_id)
    if binr is None:
        return None

    latest = await latest_reading(bin_id)
    if latest is None:
        return None

    greens, browns = await balance_cups(bin_id)
    slope = await co2_slope_per_day(bin_id)
    tw_moisture = await time_weighted_moisture(bin_id)
    healthy_hours = await healthy_hours_today(bin_id)

    # The sketch prints co2_status: null when the read FAILED, with co2_ppm
    # null alongside -- so a null status is not healthy. CO2 counts only when
    # there is a value and no error flag.
    co2_ok = latest["co2_ppm"] is not None and latest["co2_status"] in (0, None)
    ambient = latest["air_temp_c"]
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

    # Stages. The unmeasured layer gets 'started' rather than an invented
    # stage, which also keeps bottom_ready false until a probe exists.
    stages = {}
    for layer, v in layers.items():
        if v["measured"]:
            stages[layer] = compost.stage(
                v["temp_c"], ambient, latest["co2_ppm"], v["moisture_pct"], slope, co2_ok
            )
        else:
            stages[layer] = "started"

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
            "The CO2 sensor did not return a usable reading, so CO2 is being "
            "ignored rather than charted."
        )
    if ambient is None:
        notes.append(
            "No ambient air temperature, so the temperature score cannot be "
            "computed (it is measured as a rise above ambient)."
        )
    if not layers["bottom"]["measured"]:
        notes.append(
            "Only one probe is fitted, so the bottom layer is unmeasured. Its "
            "moisture and temperature are unknown, not zero."
        )
    if stale:
        notes.append("The bin has not reported recently.")

    return {
        "bin_id": bin_id,
        "time": latest["time"],
        "last_seen_at": last_seen,
        "stale": stale,
        "layers": layers,
        "stages": stages,
        "air": {
            "co2_ppm": latest["co2_ppm"],
            "co2_ok": co2_ok,
            "co2_status": latest["co2_status"],
            "co2_slope_per_day": round(slope, 2) if slope is not None else None,
            "ambient_temp_c": ambient,
            "air_humidity_pct": latest["air_humidity_pct"],
        },
        "moisture_time_weighted_6h": round(tw_moisture, 1) if tw_moisture is not None else None,
        "healthy_hours_today": healthy_hours,
        "greens_7d": greens,
        "browns_7d": browns,
        "healthy_band": [compost.MOISTURE_LO, compost.MOISTURE_HI],
        "moisture_calibrated": binr["calibrated"],
        "notes": notes,
    }


def health_components(snap: dict) -> dict:
    """The four terms computeHealth() weights, computed the app's way.

    Returned as components, not a total: health_score.dart owns the formula,
    and two implementations of one number would eventually disagree.
    """
    top = snap["layers"]["top"]
    bottom = snap["layers"]["bottom"]
    air = snap["air"]
    bottom_curing = compost.stage_at_least(snap["stages"]["bottom"], "curing")

    return {
        "moisture": compost.moisture_component(
            top["moisture_pct"], bottom["moisture_pct"]
        ),
        "temperature": compost.temperature_component(
            top["temp_c"], bottom["temp_c"], air["ambient_temp_c"], bottom_curing
        ),
        "co2": compost.co2_component(
            air["co2_ppm"] if air["co2_ok"] else None,
            snap["stages"]["top"],
            bottom_curing,
            air["co2_slope_per_day"],
        ),
        "balance": compost.balance_component(snap["greens_7d"], snap["browns_7d"]),
    }


def state_hash(snap: dict, item: str | None) -> str:
    """Fingerprint of what should change an answer.

    Values are rounded so sensor jitter reuses a cached answer while a real
    change produces a new one -- which is the demo moment.
    """
    top = snap["layers"]["top"]
    air = snap["air"]
    coarse = {
        "item": (item or "").strip().lower(),
        "moisture": round(top["moisture_pct"] / 5) if top["moisture_pct"] is not None else None,
        "temp": round(top["temp_c"] / 2) if top["temp_c"] is not None else None,
        "ambient": round(air["ambient_temp_c"] / 2) if air["ambient_temp_c"] is not None else None,
        "co2": round(air["co2_ppm"] / 250) if air["co2_ppm"] is not None else None,
        "co2_ok": air["co2_ok"],
        "greens": round(snap["greens_7d"], 1),
        "browns": round(snap["browns_7d"], 1),
    }
    return hashlib.sha256(
        json.dumps(coarse, sort_keys=True, default=str).encode()
    ).hexdigest()
