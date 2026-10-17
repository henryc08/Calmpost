"""Game endpoints: profile (HUD, streak calendar, daily goal), check-in,
daily quests, leagues.

Once-a-day awards and earned rewards are settled lazily on read and made
idempotent with dedupe keys, so there is no nightly job to go wrong during a
demo.
"""

from datetime import date, datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query

from .. import db
from ..catalog.collectibles import BY_ID as COLLECTIBLES_BY_ID
from ..catalog.collectibles import COLLECTIBLES
from ..models import (
    Achievement,
    DailyGoal,
    GameResponse,
    ImpactStats,
    LeagueMember,
    LeagueResponse,
    QuestClaimed,
    QuestProgress,
    QuestsResponse,
)
from ..rules import compost, game
from ..security import require_app_key
from ..services import binstate, economy, ledger

router = APIRouter(tags=["game"], dependencies=[Depends(require_app_key)])

CALENDAR_DAYS = 42


# --- profile ---------------------------------------------------------------

@router.get("/users/{user_id}/game", response_model=GameResponse)
async def profile(user_id: str) -> GameResponse:
    """The HUD, streak calendar, daily goal, Profile stats and achievements.

    Reading this also pays anything earned but not yet granted: healthy
    layer-days, weekly balance, achievement crates, streak milestones and
    last week's league finish. All idempotent.
    """
    async with db.pool().acquire() as conn:
        await ledger.ensure_user(conn, user_id)
    await _settle_daily_awards(user_id)
    await economy.settle_league_finishes(user_id)
    settled = await economy.settle(user_id)

    total_xp, loam = await ledger.balances(user_id)
    cared, locked = await ledger.care_days(user_id)
    today = date.today()
    current, best = game.streak_lengths(cared + locked, today)
    since = today - timedelta(days=CALENDAR_DAYS)

    level = game.level_for_xp(total_xp)
    floor_xp = game.xp_for_level(level)
    next_xp = game.xp_for_level(level + 1) if level < 50 else floor_xp

    st = await db.fetchrow("SELECT * FROM user_state WHERE user_id = $1", user_id)
    crates_waiting = await db.fetchval("SELECT count(*)::int FROM crates WHERE user_id = $1 AND opened_at IS NULL", user_id)
    collected = await db.fetchval("SELECT count(*)::int FROM collection WHERE user_id = $1 AND copies > 0", user_id)
    grams = await db.fetchval(
        "SELECT coalesce(sum(quantity_g), 0)::int FROM add_log WHERE user_id = $1 AND action = 'added' AND category IN ('green', 'brown')",
        user_id,
    )
    equipped_title = st["equipped_title"]
    level_title = game.title_for_level(level)
    title = COLLECTIBLES_BY_ID[equipped_title]["name"] if equipped_title in COLLECTIBLES_BY_ID else level_title

    return GameResponse(
        user_id=user_id,
        display_name=st["display_name"],
        total_xp=total_xp,
        week_xp=await db.fetchval("SELECT coalesce(sum(xp),0)::int FROM point_events WHERE user_id=$1 AND time >= $2", user_id, datetime.combine(economy.week_start(), time.min, tzinfo=timezone.utc)),
        action_xp_today=await db.fetchval("SELECT coalesce(sum(xp),0)::int FROM point_events WHERE user_id=$1 AND time >= date_trunc('day',now()) AND kind=ANY($2::text[])", user_id, list(game.CAPPED_KINDS)),
        grams_today=await db.fetchval("SELECT coalesce(sum(quantity_g),0) FROM add_log WHERE user_id=$1 AND time>=date_trunc('day',now()) AND action='added' AND category IN ('green','brown')", user_id),
        stats=settled['stats'],
        level=level,
        title=title,
        level_title=level_title,
        xp_into_level=max(0, total_xp - floor_xp),
        xp_for_next_level=max(1, next_xp - floor_xp),
        loam=loam,
        streak_days=current,
        best_streak=best,
        lid_locks=st["lid_locks"],
        streak_at_risk=current > 0 and today not in cared,
        cared_today=today in cared,
        care_days=[d for d in cared if d >= since],
        lock_days=[d for d in locked if d >= since],
        daily_goal=DailyGoal(**await economy.daily_goal(user_id)),
        crates_waiting=crates_waiting or 0,
        packets=st["packets"],
        equipped_finish=st["equipped_finish"],
        equipped_title=equipped_title,
        equipped_seed=st['equipped_seed'],
        level_claimed=[int(r['dedupe_key'].split(':')[1]) for r in await db.fetch(
            "SELECT dedupe_key FROM point_events WHERE user_id=$1 AND kind='level_reward'", user_id)],
        collected=collected or 0,
        collection_total=len(COLLECTIBLES),
        impact=ImpactStats(**game.impact(grams or 0)),
        achievements=[Achievement(**a) for a in economy.achievements_from(settled["stats"])],
    )


async def _settle_daily_awards(user_id: str) -> None:
    """Pay healthy-layer-day and weekly-balance XP if earned (dedupe_keyed)."""
    today = date.today().isoformat()
    week = date.today().isocalendar()
    bins = await db.fetch("SELECT bin_id FROM bins WHERE owner_id = $1", user_id)
    async with db.pool().acquire() as conn:
        for b in bins:
            snap = await binstate.snapshot(b["bin_id"])
            if snap is None:
                continue
            for layer, v in snap["layers"].items():
                if v["measured"] and compost.moisture_state(v["moisture_pct"]) == "ok":
                    await ledger.award(
                        conn, user_id, "healthy_layer_day", bin_id=b["bin_id"],
                        dedupe_key=f"healthy:{b['bin_id']}:{layer}:{today}",
                        meta={"layer": layer, "moisture_pct": v["moisture_pct"]},
                    )
            greens, browns = snap["greens_7d"], snap["browns_7d"]
            if greens and compost.balance_component(greens, browns) == 100.0:
                await ledger.award(
                    conn, user_id, "weekly_balance", bin_id=b["bin_id"],
                    dedupe_key=f"balance:{b['bin_id']}:{week.year}-W{week.week}",
                    meta={"greens": greens, "browns": browns},
                )


@router.post("/users/{user_id}/check-in")
async def check_in(user_id: str) -> dict:
    """The player opened Layers ("Check on your layers"). +5 XP once a day;
    a care action, so it keeps the streak (and may spend a Lid Lock).

    Separate from /live so merely polling the API does not tick the streak.
    """
    today = date.today().isoformat()
    async with db.pool().acquire() as conn, conn.transaction():
        await ledger.ensure_user(conn, user_id)
        await conn.fetchval("SELECT user_id FROM user_state WHERE user_id=$1 FOR UPDATE", user_id)
        xp = await ledger.award(conn, user_id, "check_in", dedupe_key=f"checkin:{today}")
    current, _ = await ledger.streaks(user_id)
    return {"user_id": user_id, "xp_awarded": xp, "day": today, "streak_days": current}


# --- quests ----------------------------------------------------------------

@router.get("/quests/today", response_model=QuestsResponse)
async def quests_today(user_id: str = Query(...)) -> QuestsResponse:
    """Today's three care quests with live progress. Claim to get paid."""
    return QuestsResponse(user_id=user_id, day=date.today(), quests=[QuestProgress(**q) for q in await economy.quests_today(user_id)])


@router.post("/quests/{key}/claim", response_model=QuestClaimed)
async def claim_quest(key: str, user_id: str = Query(...)) -> QuestClaimed:
    return QuestClaimed(**await economy.claim_quest(user_id, key))


# --- leagues ---------------------------------------------------------------

@router.get("/leagues/current", response_model=LeagueResponse)
async def current_league(user_id: str = Query(...)) -> LeagueResponse:
    """This week's cohort, ranked by XP from the xp_weekly aggregate."""
    await economy.settle_league_finishes(user_id)
    week_start = economy.week_start()

    row = await db.fetchrow(
        """
        SELECT l.id, l.tier, l.week_start FROM league_members m JOIN leagues l ON l.id = m.league_id
        WHERE m.user_id = $1 AND l.week_start = $2 LIMIT 1
        """,
        user_id,
        week_start,
    )
    if row is None:
        raise HTTPException(404, "not in a league this week -- run python -m scripts.seed_demo")

    members = await db.fetch(
        """
        SELECT m.user_id, m.display_name, m.is_bot, coalesce(x.xp, 0)::int AS xp,
               coalesce(m.streak, 0) AS streak, m.is_friend
        FROM league_members m
        LEFT JOIN xp_weekly x ON x.user_id = m.user_id AND x.week = $2::timestamptz
        WHERE m.league_id = $1
        ORDER BY xp DESC, m.display_name
        """,
        row["id"],
        datetime.combine(week_start, time.min, tzinfo=timezone.utc),
    )

    size = len(members)
    tier_index = game.LEAGUE_TIERS.index(row["tier"]) if row["tier"] in game.LEAGUE_TIERS else 0
    out: list[LeagueMember] = []
    your_rank = None
    for i, m in enumerate(members, start=1):
        is_you = m["user_id"] == user_id
        if is_you:
            your_rank = i
        out.append(
            LeagueMember(
                user_id=m["user_id"],
                display_name="You" if is_you else m["display_name"],
                xp=m["xp"],
                rank=i,
                is_you=is_you,
                is_friend=m["is_friend"],
                streak=m["streak"] or 0,
                color_index=game.stable_index(m["user_id"], 6),
                zone=game.league_zone(i, size, tier_index),
            )
        )

    return LeagueResponse(
        tier=row["tier"],
        tier_index=tier_index,
        week_start=week_start,
        resets_at=datetime.combine(week_start + timedelta(days=7), time.min, tzinfo=timezone.utc),
        size=size,
        promote_count=game.LEAGUE_PROMOTE,
        demote_count=game.LEAGUE_DEMOTE,
        members=out,
        your_rank=your_rank,
    )
