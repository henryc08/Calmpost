"""What the user put in the bin, plus the points that earns."""

from fastapi import APIRouter, Depends, HTTPException, Query

from .. import compost, db
from ..models import AddLogCreate, AddLogEntry, PointsResponse
from ..security import require_app_key

router = APIRouter(prefix="/v1", tags=["log"], dependencies=[Depends(require_app_key)])

# XP rewards care, never volume (CLAUDE.md: "log = 0"). Logging a scrap earns
# nothing on its own -- otherwise the game would pay people to waste more
# food. XP comes only from following a suggestion here; the healthy-layer-day,
# quest, balance and harvest awards are separate ledger writes.
POINTS_FOLLOWED_ADVICE = 15
POINTS_PLAIN_LOG = 0
POINTS_AVOID_ITEM = 0


@router.post("/log", response_model=AddLogEntry, status_code=201)
async def add_entry(body: AddLogCreate) -> AddLogEntry:
    device = await db.fetchrow(
        "SELECT owner_id FROM devices WHERE device_id = $1", body.device_id
    )
    if device is None:
        raise HTTPException(status_code=404, detail="unknown device")

    # Trust the client's category only when it actually classified something.
    category = body.category
    if category == "unknown":
        category = compost.categorise(body.item)

    if category == "avoid":
        # Added something the bin should not get -- no reward.
        points = POINTS_AVOID_ITEM
        reason = "logged an item to avoid"
    elif body.was_advised:
        points = POINTS_FOLLOWED_ADVICE
        reason = "followed a suggestion"
    else:
        points = POINTS_PLAIN_LOG
        reason = "logged an add"

    async with db.pool().acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                """
                INSERT INTO add_log
                    (device_id, user_id, item, category, zone, quantity_g,
                     source, was_advised, notes)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                RETURNING id, time
                """,
                body.device_id,
                device["owner_id"],
                body.item,
                category,
                body.zone,
                body.quantity_g,
                body.source,
                body.was_advised,
                body.notes,
            )
            if points:
                await conn.execute(
                    """
                    INSERT INTO points_ledger (user_id, device_id, reason, points)
                    VALUES ($1, $2, $3, $4)
                    """,
                    device["owner_id"],
                    body.device_id,
                    reason,
                    points,
                )

    return AddLogEntry(
        **body.model_dump() | {"category": category},
        id=row["id"],
        time=row["time"],
        points_awarded=points,
    )


@router.get("/devices/{device_id}/log", response_model=list[AddLogEntry])
async def list_entries(
    device_id: str, limit: int = Query(50, ge=1, le=200)
) -> list[AddLogEntry]:
    rows = await db.fetch(
        """
        SELECT id, device_id, time, item, category, zone, quantity_g,
               source, was_advised, notes
        FROM add_log
        WHERE device_id = $1
        ORDER BY time DESC
        LIMIT $2
        """,
        device_id,
        limit,
    )
    return [AddLogEntry(**dict(r), points_awarded=0) for r in rows]


@router.get("/users/{user_id}/points", response_model=PointsResponse)
async def points(user_id: str) -> PointsResponse:
    """Total, streak and weekly count in one round trip for the home screen."""
    row = await db.fetchrow(
        """
        WITH ledger AS (
            SELECT coalesce(sum(points), 0)::int AS total
            FROM points_ledger WHERE user_id = $1
        ),
        days AS (
            -- Distinct days the user logged something, newest first.
            SELECT DISTINCT date_trunc('day', time) AS d
            FROM add_log WHERE user_id = $1
        ),
        ranked AS (
            SELECT d, row_number() OVER (ORDER BY d DESC) AS rn FROM days
        ),
        streak AS (
            -- A day is in the streak while it sits exactly rn-1 days before
            -- today; the first gap ends the run.
            SELECT count(*)::int AS days
            FROM ranked
            WHERE d = date_trunc('day', now()) - ((rn - 1) || ' days')::interval
        ),
        week AS (
            SELECT count(*)::int AS n
            FROM add_log
            WHERE user_id = $1 AND time >= now() - interval '7 days'
        )
        SELECT ledger.total, streak.days, week.n FROM ledger, streak, week
        """,
        user_id,
    )
    return PointsResponse(
        user_id=user_id,
        total_points=row["total"],
        streak_days=row["days"],
        logs_this_week=row["n"],
    )
