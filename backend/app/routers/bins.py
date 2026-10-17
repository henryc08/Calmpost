"""Bin endpoints: registration, live view, trends, the add log, harvest."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query

from .. import binstate, compost, db, ledger
from ..models import (
    AirLive,
    BinCreate,
    BinCreated,
    CalibrationUpdate,
    HarvestRequest,
    HarvestResponse,
    HealthComponents,
    LayerLive,
    LiveResponse,
    LogCreate,
    LogEntry,
    Metric,
    TrendPoint,
    TrendSeries,
    TrendsResponse,
)
from ..security import hash_token, new_token, require_app_key

router = APIRouter(tags=["bins"], dependencies=[Depends(require_app_key)])

LAYER_LABELS = {"top": "Top layer", "bottom": "Bottom layer"}


# --- registration & calibration -------------------------------------------

@router.post("/bins", response_model=BinCreated, status_code=201)
async def register_bin(body: BinCreate) -> BinCreated:
    token = new_token()
    async with db.pool().acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                """
                INSERT INTO bins (bin_id, display_name, token_sha256, owner_id)
                VALUES ($1, $2, $3, $4)
                ON CONFLICT (bin_id) DO UPDATE SET
                    display_name = EXCLUDED.display_name,
                    token_sha256 = EXCLUDED.token_sha256,
                    owner_id     = EXCLUDED.owner_id
                """,
                body.bin_id,
                body.display_name,
                hash_token(token),
                body.owner_id,
            )
            await conn.execute(
                "INSERT INTO user_state (user_id) VALUES ($1) ON CONFLICT DO NOTHING",
                body.owner_id,
            )
    return BinCreated(
        bin_id=body.bin_id, display_name=body.display_name, device_token=token
    )


@router.get("/bins")
async def list_bins() -> list[dict]:
    rows = await db.fetch(
        """
        SELECT bin_id, display_name, owner_id, calibrated, created_at, last_seen_at
        FROM bins ORDER BY created_at
        """
    )
    return [dict(r) for r in rows]


@router.post("/bins/{bin_id}/calibration")
async def set_calibration(bin_id: str, body: CalibrationUpdate) -> dict:
    """Store the probe's dry/wet raw counts and optionally replay history.

    Without this the moisture percentage is a guess, and moisture is the
    heaviest term in the health score -- so calibrating is the single most
    valuable thing to do with the hardware.
    """
    if body.moisture_raw_dry == body.moisture_raw_wet:
        raise HTTPException(status_code=422, detail="dry and wet counts must differ")

    binr = await binstate.bin_row(bin_id)
    if binr is None:
        raise HTTPException(status_code=404, detail="unknown bin")

    updated = 0
    async with db.pool().acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                """
                UPDATE bins
                SET moisture_raw_dry = $2, moisture_raw_wet = $3, calibrated = true
                WHERE bin_id = $1
                """,
                bin_id,
                body.moisture_raw_dry,
                body.moisture_raw_wet,
            )
            if body.backfill:
                # Recompute stored percentages with the new curve so the
                # charts are consistent instead of kinking at this moment.
                result = await conn.execute(
                    """
                    UPDATE readings
                    SET moisture_pct = greatest(0, least(100,
                        100.0 * ($2::double precision - moisture_raw)
                              / ($2::double precision - $3::double precision)))
                    WHERE bin_id = $1 AND moisture_raw IS NOT NULL
                    """,
                    bin_id,
                    body.moisture_raw_dry,
                    body.moisture_raw_wet,
                )
                updated = int(result.split()[-1]) if result.startswith("UPDATE") else 0

    return {
        "bin_id": bin_id,
        "calibrated": True,
        "moisture_raw_dry": body.moisture_raw_dry,
        "moisture_raw_wet": body.moisture_raw_wet,
        "readings_recomputed": updated,
    }


# --- stats -----------------------------------------------------------------

@router.get("/bins/{bin_id}/stats")
async def stats(bin_id: str) -> dict:
    """Is data actually arriving? One call, straight from Tiger Data.

    Separate from /live because /live answers "what is the bin doing" while
    this answers "is the pipeline working" -- the question you want when the
    bridge terminal is scrolling but you are not sure anything is landing.
    """
    binr = await binstate.bin_row(bin_id)
    if binr is None:
        raise HTTPException(status_code=404, detail="unknown bin")

    row = await db.fetchrow(
        """
        SELECT count(*)::int                                            AS total,
               min(time)                                                AS oldest,
               max(time)                                                AS newest,
               count(*) FILTER (WHERE time > now() - interval '1 minute')::int AS last_minute,
               count(*) FILTER (WHERE time > now() - interval '1 hour')::int   AS last_hour,
               count(*) FILTER (WHERE co2_ppm IS NULL)::int             AS missing_co2,
               count(*) FILTER (WHERE moisture_raw IS NULL)::int        AS missing_moisture,
               count(*) FILTER (WHERE coalesce(co2_status, 0) <> 0)::int AS co2_errors
        FROM readings WHERE bin_id = $1
        """,
        bin_id,
    )

    newest = row["newest"]
    age = (
        (datetime.now(timezone.utc) - newest).total_seconds()
        if newest is not None
        else None
    )

    return {
        "bin_id": bin_id,
        "readings_total": row["total"],
        "readings_last_minute": row["last_minute"],
        "readings_last_hour": row["last_hour"],
        "oldest": row["oldest"],
        "newest": newest,
        "seconds_since_last": round(age) if age is not None else None,
        # The plain answer. Anything over ~2 minutes means the bridge is not
        # running, or the board's port is held by something else.
        "flowing": age is not None and age < 120,
        "missing_moisture": row["missing_moisture"],
        "missing_co2": row["missing_co2"],
        "co2_error_rows": row["co2_errors"],
        "calibrated": binr["calibrated"],
    }


# --- live ------------------------------------------------------------------

@router.get("/bins/{bin_id}/live", response_model=LiveResponse)
async def live(bin_id: str) -> LiveResponse:
    binr = await binstate.bin_row(bin_id)
    if binr is None:
        raise HTTPException(status_code=404, detail="unknown bin")

    snap = await binstate.snapshot(bin_id)
    if snap is None:
        raise HTTPException(status_code=409, detail="no readings for this bin yet")

    air = snap["air"]
    layers = [
        LayerLive(
            layer=layer,
            label=LAYER_LABELS[layer],
            measured=snap["layers"][layer]["measured"],
            moisture_pct=(
                round(snap["layers"][layer]["moisture_pct"], 1)
                if snap["layers"][layer]["moisture_pct"] is not None
                else None
            ),
            moisture_raw=snap["layers"][layer]["moisture_raw"],
            moisture_state=snap["layers"][layer]["moisture_state"],
            temp_c=snap["layers"][layer]["temp_c"],
            stage=snap["stages"][layer],
        )
        for layer in ("top", "bottom")
    ]

    # A stage change is worth recording so the Journey path has history.
    await _record_stage(bin_id, layers)

    return LiveResponse(
        bin_id=bin_id,
        time=snap["time"],
        last_seen_at=snap["last_seen_at"],
        stale=snap["stale"],
        layers=layers,
        air=AirLive(**air),
        health_components=HealthComponents(**binstate.health_components(snap)),
        balance=compost.balance_of(
            snap["layers"]["top"]["moisture_pct"], snap["greens_7d"], snap["browns_7d"]
        ),
        greens_7d=snap["greens_7d"],
        browns_7d=snap["browns_7d"],
        healthy_band=snap["healthy_band"],
        moisture_calibrated=snap["moisture_calibrated"],
        healthy_hours_today=snap["healthy_hours_today"],
        notes=snap["notes"],
    )


async def _record_stage(bin_id: str, layers: list[LayerLive]) -> None:
    """Append to stage_history only when a measured layer's stage changes."""
    async with db.pool().acquire() as conn:
        for layer in layers:
            if not layer.measured:
                continue
            last = await conn.fetchrow(
                """
                SELECT stage FROM stage_history
                WHERE bin_id = $1 AND layer = $2
                ORDER BY time DESC LIMIT 1
                """,
                bin_id,
                layer.layer,
            )
            # Never walk a batch back out of 'harvested' from a sensor read.
            if last is not None and last["stage"] == "harvested":
                continue
            if last is None or last["stage"] != layer.stage:
                await conn.execute(
                    """
                    INSERT INTO stage_history (bin_id, layer, stage, source, evidence)
                    VALUES ($1, $2, $3, 'sensor', $4)
                    """,
                    bin_id,
                    layer.layer,
                    layer.stage,
                    {
                        "moisture_pct": layer.moisture_pct,
                        "temp_c": layer.temp_c,
                    },
                )


# --- trends ----------------------------------------------------------------

DEFAULT_METRICS: list[Metric] = ["moisture", "temperature", "co2"]

# The app's Metric enum -> the aggregate column holding it. Column names
# differ between the two continuous aggregates.
AGG_COLUMNS = {
    "15m": {
        "moisture": "moisture_pct_avg",
        "temperature": "probe_temp_c_avg",
        "co2": "co2_ppm_avg",
        "air_temp": "air_temp_c_avg",
        "air_humidity": "air_humidity_pct_avg",
    },
    "1d": {
        "moisture": "moisture_pct_avg",
        "temperature": "probe_temp_c_avg",
        "co2": "co2_ppm_avg",
    },
}


@router.get("/bins/{bin_id}/trends", response_model=TrendsResponse)
async def trends(
    bin_id: str,
    hours: int = Query(24, ge=1, le=2160),
    metrics: list[Metric] = Query(default=DEFAULT_METRICS),
) -> TrendsResponse:
    """Chart series, gap-filled so a dropout shows as a flat carry rather
    than a hole the chart would misdraw.

    Reads the 15-minute aggregate for short windows and the daily one beyond
    a week, then carries the last value forward with locf.
    """
    binr = await binstate.bin_row(bin_id)
    if binr is None:
        raise HTTPException(status_code=404, detail="unknown bin")

    resolution = "15m" if hours <= 168 else "1d"
    bucket_width = "15 minutes" if resolution == "15m" else "1 day"
    view = "readings_15m" if resolution == "15m" else "readings_1d"
    columns = AGG_COLUMNS[resolution]

    wanted = [m for m in metrics if m in columns] or ["moisture"]

    series: list[TrendSeries] = []
    for metric in wanted:
        col = columns[metric]
        rows = await db.fetch(
            f"""
            SELECT time_bucket_gapfill(
                       -- via text so asyncpg sends a string, not an interval
                       $3::text::interval, bucket,
                       start => now() - ($2 || ' hours')::interval,
                       finish => now()
                   ) AS t,
                   locf(avg({col})) AS value
            FROM {view}
            WHERE bin_id = $1
              AND bucket >= now() - ($2 || ' hours')::interval
            GROUP BY t
            ORDER BY t
            """,
            bin_id,
            str(hours),
            bucket_width,
        )
        series.append(
            TrendSeries(
                metric=metric,
                points=[
                    TrendPoint(
                        bucket=r["t"],
                        value=round(float(r["value"]), 2) if r["value"] is not None else None,
                    )
                    for r in rows
                ],
            )
        )

    return TrendsResponse(
        bin_id=bin_id,
        hours=hours,
        resolution=resolution,
        healthy_band=(
            [compost.MOISTURE_LO, compost.MOISTURE_HI] if "moisture" in wanted else None
        ),
        series=series,
    )


# --- add log ---------------------------------------------------------------

@router.post("/bins/{bin_id}/logs", response_model=LogEntry, status_code=201)
async def add_log_entry(bin_id: str, body: LogCreate) -> LogEntry:
    """Record an add -- or a skip.

    XP rules (CLAUDE.md): a plain log is worth ZERO. Following a suggestion
    pays 15; trusting an avoid verdict and skipping the item pays 5. Paying
    per scrap logged would reward wasting more food, which is the one thing
    the game must never do.
    """
    binr = await db.fetchrow(
        "SELECT owner_id FROM bins WHERE bin_id = $1", bin_id
    )
    if binr is None:
        raise HTTPException(status_code=404, detail="unknown bin")
    user_id = binr["owner_id"]

    category = body.category
    if category == "unknown":
        category = compost.categorise(body.item)

    xp = 0
    seeds = 0
    kind = None
    if body.action == "skipped":
        # Only an avoid-worthy item earns the skip reward; skipping a perfectly
        # good scrap is not an achievement.
        if category == "avoid" or compost.avoid_reason(body.item):
            kind = "avoided_bad_add"
    elif body.was_advised and category != "avoid":
        kind = "followed_suggestion"

    async with db.pool().acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                """
                INSERT INTO add_log
                    (bin_id, user_id, item, category, action, quantity_g,
                     source, was_advised, advice_id, notes)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
                RETURNING id, time
                """,
                bin_id,
                user_id,
                body.item,
                category,
                body.action,
                body.quantity_g,
                body.source,
                body.was_advised,
                body.advice_id,
                body.notes,
            )
            if kind:
                xp = await ledger.award(
                    conn, user_id, kind, bin_id=bin_id,
                    meta={"item": body.item, "log_id": row["id"]},
                )
                # Loam is only paid when XP was (the daily cap can zero it).
                seeds = compost.LOAM.get(kind, 0) if xp else 0

    return LogEntry(
        id=row["id"],
        bin_id=bin_id,
        time=row["time"],
        item=body.item,
        category=category,
        action=body.action,
        quantity_g=body.quantity_g,
        source=body.source,
        was_advised=body.was_advised,
        notes=body.notes,
        xp_awarded=xp,
        loam_awarded=seeds,
    )


@router.get("/bins/{bin_id}/logs", response_model=list[LogEntry])
async def list_log(bin_id: str, limit: int = Query(50, ge=1, le=200)) -> list[LogEntry]:
    rows = await db.fetch(
        """
        SELECT id, bin_id, time, item, category, action, quantity_g,
               source, was_advised, notes
        FROM add_log
        WHERE bin_id = $1
        ORDER BY time DESC
        LIMIT $2
        """,
        bin_id,
        limit,
    )
    return [LogEntry(**dict(r)) for r in rows]


# --- harvest ---------------------------------------------------------------

@router.post("/bins/{bin_id}/harvest", response_model=HarvestResponse)
async def harvest(bin_id: str, body: HarvestRequest) -> HarvestResponse:
    """Harvest a layer: +100 XP, the biggest single award in the game.

    Allowed even when the sensors do not say "ready" -- it is the user's
    compost. was_ready records whether the sensors agreed, so the celebration
    can be honest rather than claiming a readiness we did not measure.
    """
    binr = await db.fetchrow("SELECT owner_id FROM bins WHERE bin_id = $1", bin_id)
    if binr is None:
        raise HTTPException(status_code=404, detail="unknown bin")
    user_id = binr["owner_id"]

    snap = await binstate.snapshot(bin_id)
    was_ready = False
    note = None
    if snap is None:
        note = "No readings yet, so readiness could not be checked."
    else:
        layer = snap["layers"][body.layer]
        # Stages are already computed in the snapshot, the same way /live
        # reports them, so the celebration cannot disagree with the screen.
        was_ready = snap["stages"][body.layer] == "ready"
        if not layer["measured"]:
            note = (
                f"The {body.layer} layer has no probe, so readiness could not be "
                "measured. Harvesting on your own judgement."
            )
        elif not was_ready:
            note = "Sensors did not say ready yet, so this batch may need longer."

    now = datetime.now(timezone.utc)
    async with db.pool().acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                """
                INSERT INTO stage_history (bin_id, layer, stage, source, evidence)
                VALUES ($1, $2, 'harvested', 'user', $3)
                """,
                bin_id,
                body.layer,
                {"yield_g": body.yield_g, "sensors_said_ready": was_ready},
            )
            xp = await ledger.award(
                conn, user_id, "harvest", bin_id=bin_id,
                meta={"layer": body.layer, "yield_g": body.yield_g},
            )

    return HarvestResponse(
        bin_id=bin_id,
        layer=body.layer,
        harvested_at=now,
        xp_awarded=xp,
        seeds_awarded=compost.LOAM["harvest"],
        was_ready=was_ready,
        note=note,
    )
