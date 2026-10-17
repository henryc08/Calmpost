"""Game endpoints: profile/level/impact, daily quests, leagues.

Quests and the once-a-day awards are evaluated lazily on read and made
idempotent with a dedupe_key, so there is no nightly job to go wrong during
a hackathon demo.
"""

from datetime import date, datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query

from .. import binstate, compost, db, ledger
from ..models import (
    Achievement,
    GameResponse,
    ImpactStats,
    LeagueMember,
    LeagueResponse,
    QuestProgress,
    QuestsResponse,
)
from ..security import require_app_key

router = APIRouter(tags=["game"], dependencies=[Depends(require_app_key)])


# --- profile ---------------------------------------------------------------

@router.get("/users/{user_id}/game", response_model=GameResponse)
async def game(user_id: str) -> GameResponse:
    # Credit anything the user has earned but not yet been paid for.
    await _settle_daily_awards(user_id)

    total_xp, seeds = await ledger.totals(user_id)
    current_streak, best_streak = await ledger.streaks(user_id)
    at_risk = await ledger.streak_at_risk(user_id)

    level = compost.level_for_xp(total_xp)
    floor_xp = compost.xp_for_level(level)
    next_xp = compost.xp_for_level(level + 1) if level < 50 else floor_xp

    state = await db.fetchrow(
        "SELECT lid_locks FROM user_state WHERE user_id = $1", user_id
    )
    lid_locks = state["lid_locks"] if state else 0

    grams = await db.fetchrow(
        """
        SELECT coalesce(sum(quantity_g), 0)::int AS g
        FROM add_log
        WHERE user_id = $1 AND action = 'added' AND category IN ('green', 'brown')
        """,
        user_id,
    )
    impact = compost.impact(grams["g"] if grams else 0)

    harvests = await db.fetchrow(
        "SELECT count(*)::int AS n FROM point_events WHERE user_id = $1 AND kind = 'harvest'",
        user_id,
    )
    healthy_days = await db.fetchrow(
        """
        SELECT count(DISTINCT date_trunc('day', time))::int AS n
        FROM point_events
        WHERE user_id = $1 AND kind = 'healthy_layer_day'
        """,
        user_id,
    )
    perfect_weeks = await db.fetchrow(
        "SELECT count(*)::int AS n FROM point_events WHERE user_id = $1 AND kind = 'weekly_balance'",
        user_id,
    )

    badges = compost.achievements(
        {
            "harvests": harvests["n"] if harvests else 0,
            "healthy_days": healthy_days["n"] if healthy_days else 0,
            "perfect_weeks": perfect_weeks["n"] if perfect_weeks else 0,
            "kg_diverted": impact["kg_diverted"],
            "best_streak": best_streak,
        }
    )

    return GameResponse(
        user_id=user_id,
        total_xp=total_xp,
        level=level,
        title=compost.title_for_level(level),
        xp_into_level=max(0, total_xp - floor_xp),
        xp_for_next_level=max(1, next_xp - floor_xp),
        seeds=seeds,
        streak_days=current_streak,
        best_streak=best_streak,
        lid_locks=lid_locks,
        streak_at_risk=at_risk,
        impact=ImpactStats(**impact),
        achievements=[Achievement(**b) for b in badges],
    )


async def _settle_daily_awards(user_id: str) -> None:
    """Pay the healthy-layer-day and weekly-balance awards if earned.

    Both are dedupe_keyed, so calling this on every read is safe.
    """
    today = date.today().isoformat()

    bins = await db.fetch("SELECT bin_id FROM bins WHERE owner_id = $1", user_id)
    async with db.pool().acquire() as conn:
        for b in bins:
            snap = await binstate.snapshot(b["bin_id"])
            if snap is None:
                continue
            for layer, v in snap["layers"].items():
                if not v["measured"]:
                    continue
                if compost.moisture_state(v["moisture_pct"]) != "ok":
                    continue
                await ledger.award(
                    conn,
                    user_id,
                    "healthy_layer_day",
                    bin_id=b["bin_id"],
                    dedupe_key=f"healthy:{b['bin_id']}:{layer}:{today}",
                    meta={"layer": layer, "moisture_pct": v["moisture_pct"]},
                )

            # Weekly balance: last 7 days' greens:browns inside the target.
            greens, browns = snap["greens_7d"], snap["browns_7d"]
            if greens and compost.balance_component(greens, browns) == 100.0:
                week = date.today().isocalendar()
                await ledger.award(
                    conn,
                    user_id,
                    "weekly_balance",
                    bin_id=b["bin_id"],
                    dedupe_key=f"balance:{b['bin_id']}:{week.year}-W{week.week}",
                    meta={"greens": greens, "browns": browns},
                )


# --- quests ----------------------------------------------------------------

@router.get("/quests/today", response_model=QuestsResponse)
async def quests_today(user_id: str = Query(...)) -> QuestsResponse:
    """Three care-based quests, stable for the day, with live progress."""
    today = date.today()
    picks = compost.quests_for_day(user_id, today.isoformat())

    out: list[QuestProgress] = []
    async with db.pool().acquire() as conn:
        for q in picks:
            progress = await _quest_progress(user_id, q["key"])
            complete = progress >= q["target"]
            if complete:
                # Pay on completion, once per quest per day.
                await ledger.award(
                    conn,
                    user_id,
                    "daily_quest",
                    dedupe_key=f"quest:{q['key']}:{today.isoformat()}",
                    meta={"quest": q["key"]},
                )
            out.append(
                QuestProgress(
                    key=q["key"],
                    title=q["title"],
                    detail=q["detail"],
                    target=q["target"],
                    progress=min(progress, q["target"]),
                    complete=complete,
                    xp=compost.XP["daily_quest"],
                    seeds=compost.SEEDS["daily_quest"],
                )
            )

    return QuestsResponse(user_id=user_id, day=today, quests=out)


async def _quest_progress(user_id: str, key: str) -> int:
    """Count today's qualifying actions for one quest."""
    if key == "follow_suggestion":
        row = await db.fetchrow(
            """
            SELECT count(*)::int AS n FROM point_events
            WHERE user_id = $1 AND kind IN ('followed_suggestion', 'avoided_bad_add')
              AND time >= date_trunc('day', now())
            """,
            user_id,
        )
    elif key == "avoid_bad_add":
        row = await db.fetchrow(
            """
            SELECT count(*)::int AS n FROM point_events
            WHERE user_id = $1 AND kind = 'avoided_bad_add'
              AND time >= date_trunc('day', now())
            """,
            user_id,
        )
    elif key == "balance_browns":
        row = await db.fetchrow(
            """
            SELECT count(*)::int AS n FROM add_log
            WHERE user_id = $1 AND category = 'brown' AND action = 'added'
              AND time >= date_trunc('day', now())
            """,
            user_id,
        )
    elif key == "keep_in_band":
        row = await db.fetchrow(
            """
            SELECT count(*)::int AS n FROM point_events
            WHERE user_id = $1 AND kind = 'healthy_layer_day'
              AND time >= date_trunc('day', now())
            """,
            user_id,
        )
    elif key == "check_in":
        row = await db.fetchrow(
            """
            SELECT count(*)::int AS n FROM point_events
            WHERE user_id = $1 AND kind = 'check_in'
              AND time >= date_trunc('day', now())
            """,
            user_id,
        )
    else:
        return 0
    return row["n"] if row else 0


@router.post("/users/{user_id}/check-in")
async def check_in(user_id: str) -> dict:
    """Records that the user looked at their bin today.

    Separate from the live view so merely polling the API does not tick the
    streak -- the app calls this when someone actually opens the bin screen.
    """
    today = date.today().isoformat()
    async with db.pool().acquire() as conn:
        xp = await ledger.award(
            conn, user_id, "check_in", xp=0, seeds=0,
            dedupe_key=f"checkin:{today}",
        )
    return {"user_id": user_id, "counted": xp == 0, "day": today}


# --- leagues ---------------------------------------------------------------

def _week_start(today: date | None = None) -> date:
    """Most recent Sunday, matching the Sunday league reset."""
    today = today or date.today()
    # weekday(): Monday=0 ... Sunday=6
    return today - timedelta(days=(today.weekday() + 1) % 7)


@router.get("/leagues/current", response_model=LeagueResponse)
async def current_league(user_id: str = Query(...)) -> LeagueResponse:
    """This week's cohort, ranked by XP from the xp_weekly aggregate."""
    week_start = _week_start()

    row = await db.fetchrow(
        """
        SELECT l.id, l.tier, l.week_start
        FROM league_members m
        JOIN leagues l ON l.id = m.league_id
        WHERE m.user_id = $1 AND l.week_start = $2
        LIMIT 1
        """,
        user_id,
        week_start,
    )
    if row is None:
        raise HTTPException(
            status_code=404,
            detail="not in a league this week -- run scripts/seed_league.py",
        )

    # xp_weekly buckets on a Sunday origin, so the bucket start is week_start.
    members = await db.fetch(
        """
        SELECT m.user_id, m.display_name, m.is_bot,
               coalesce(x.xp, 0)::int AS xp
        FROM league_members m
        LEFT JOIN xp_weekly x
               ON x.user_id = m.user_id
              AND x.week = $2::timestamptz
        WHERE m.league_id = $1
        ORDER BY xp DESC, m.display_name
        """,
        row["id"],
        datetime.combine(week_start, time.min, tzinfo=timezone.utc),
    )

    size = len(members)
    out: list[LeagueMember] = []
    your_rank = None
    for i, m in enumerate(members, start=1):
        if i <= compost.LEAGUE_PROMOTE:
            zone = "promotion"
        elif i > size - compost.LEAGUE_DEMOTE:
            zone = "demotion"
        else:
            zone = "safe"
        is_you = m["user_id"] == user_id
        if is_you:
            your_rank = i
        out.append(
            LeagueMember(
                user_id=m["user_id"],
                display_name=m["display_name"],
                xp=m["xp"],
                rank=i,
                is_you=is_you,
                zone=zone,
            )
        )

    resets_at = datetime.combine(
        week_start + timedelta(days=7), time.min, tzinfo=timezone.utc
    )

    return LeagueResponse(
        tier=row["tier"],
        week_start=week_start,
        resets_at=resets_at,
        size=size,
        promote_count=compost.LEAGUE_PROMOTE,
        demote_count=compost.LEAGUE_DEMOTE,
        members=out,
        your_rank=your_rank,
    )
