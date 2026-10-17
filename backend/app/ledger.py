"""Writes to the XP ledger.

point_events is append-only, so totals, streaks and league standings are
always recomputed. Awards that can be re-evaluated on every request (healthy
layer-day, daily quests, weekly balance) carry a dedupe_key so re-evaluating
them is free of duplicates.
"""

from datetime import date

import asyncpg

from . import compost, db


async def award(
    conn: asyncpg.Connection,
    user_id: str,
    kind: str,
    *,
    bin_id: str | None = None,
    xp: int | None = None,
    seeds: int | None = None,
    dedupe_key: str | None = None,
    meta: dict | None = None,
) -> int:
    """Insert one ledger row; returns XP actually awarded (0 if deduped).

    Values default to the constants in compost.py so the rules live in one
    place rather than being retyped at each call site.
    """
    xp = compost.XP.get(kind, 0) if xp is None else xp
    seeds = compost.SEEDS.get(kind, 0) if seeds is None else seeds

    if dedupe_key is not None:
        existing = await conn.fetchrow(
            "SELECT 1 FROM point_events WHERE user_id = $1 AND dedupe_key = $2 LIMIT 1",
            user_id,
            dedupe_key,
        )
        if existing is not None:
            return 0

    await conn.execute(
        """
        INSERT INTO point_events (user_id, bin_id, kind, xp, seeds, dedupe_key, meta)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        """,
        user_id,
        bin_id,
        kind,
        xp,
        seeds,
        dedupe_key,
        meta or {},
    )
    return xp


async def totals(user_id: str) -> tuple[int, int]:
    """Lifetime XP and Seeds."""
    row = await db.fetchrow(
        """
        SELECT coalesce(sum(xp), 0)::int AS xp, coalesce(sum(seeds), 0)::int AS seeds
        FROM point_events WHERE user_id = $1
        """,
        user_id,
    )
    return (row["xp"], row["seeds"]) if row else (0, 0)


# Actions that count as caring for the bin, for streak purposes. A plain log
# is NOT one of them -- CLAUDE.md: a streak tracks care, not volume.
CARE_KINDS = (
    "followed_suggestion",
    "avoided_bad_add",
    "healthy_layer_day",
    "daily_quest",
    "weekly_balance",
    "harvest",
    "check_in",
)


async def streaks(user_id: str) -> tuple[int, int]:
    """(current streak, best streak) in days of care actions."""
    rows = await db.fetch(
        """
        SELECT DISTINCT date_trunc('day', time)::date AS d
        FROM point_events
        WHERE user_id = $1 AND kind = ANY($2::text[])
        ORDER BY d DESC
        """,
        user_id,
        list(CARE_KINDS),
    )
    days = [r["d"] for r in rows]
    if not days:
        return 0, 0

    today = date.today()
    # The streak survives until the end of tomorrow, so caring yesterday but
    # not yet today still shows a live streak (and triggers at-risk).
    current = 0
    if days[0] in (today, today.fromordinal(today.toordinal() - 1)):
        current = 1
        for prev, nxt in zip(days, days[1:]):
            if (prev - nxt).days == 1:
                current += 1
            else:
                break

    best = 1
    run = 1
    for prev, nxt in zip(days, days[1:]):
        if (prev - nxt).days == 1:
            run += 1
            best = max(best, run)
        else:
            run = 1
    return current, max(best, current)


async def streak_at_risk(user_id: str) -> bool:
    """True when a live streak has had no care action today."""
    current, _ = await streaks(user_id)
    if current == 0:
        return False
    row = await db.fetchrow(
        """
        SELECT 1 FROM point_events
        WHERE user_id = $1 AND kind = ANY($2::text[])
          AND time >= date_trunc('day', now())
        LIMIT 1
        """,
        user_id,
        list(CARE_KINDS),
    )
    return row is None
