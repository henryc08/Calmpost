"""The XP and Loam ledger (point_events), plus streaks.

Append-only: balances, streaks, today's XP and league standings are always
recomputed from the rows. Once-only awards carry a dedupe_key, so re-running
them on every request is free of duplicates.
"""

from datetime import date, datetime, time, timezone

import asyncpg

from .. import db
from ..rules import game


async def award(
    conn: asyncpg.Connection,
    user_id: str,
    kind: str,
    *,
    bin_id: str | None = None,
    xp: int | None = None,
    loam: int = 0,
    dedupe_key: str | None = None,
    meta: dict | None = None,
    at: datetime | None = None,
) -> int:
    """Insert one ledger row; returns the XP actually awarded (0 if deduped).

    XP defaults to game.XP[kind]. Action XP is capped per day; sensor-driven
    awards and quest rewards are not.
    """
    xp = game.XP.get(kind, 0) if xp is None else xp

    if dedupe_key is not None:
        existing = await conn.fetchval(
            "SELECT 1 FROM point_events WHERE user_id = $1 AND dedupe_key = $2 LIMIT 1", user_id, dedupe_key
        )
        if existing is not None:
            return 0

    if xp and kind in game.CAPPED_KINDS:
        earned = await conn.fetchval(
            """
            SELECT coalesce(sum(xp), 0)::int FROM point_events
            WHERE user_id = $1 AND kind = ANY($2::text[]) AND time >= date_trunc('day', now())
            """,
            user_id,
            list(game.CAPPED_KINDS),
        )
        xp = game.cap_xp(xp, earned or 0)

    await conn.execute(
        """
        INSERT INTO point_events (time, user_id, bin_id, kind, xp, loam, dedupe_key, meta)
        VALUES (coalesce($1, now()), $2, $3, $4, $5, $6, $7, $8)
        """,
        at,
        user_id,
        bin_id,
        kind,
        xp,
        loam,
        dedupe_key,
        meta or {},
    )
    if kind in game.CARE_KINDS and kind != "lid_lock_used":
        await apply_lid_locks(conn, user_id)
    return xp


async def balances(user_id: str, conn: asyncpg.Connection | None = None) -> tuple[int, int]:
    """(lifetime XP, Loam balance)."""
    q = "SELECT coalesce(sum(xp), 0)::int AS xp, coalesce(sum(loam), 0)::int AS loam FROM point_events WHERE user_id = $1"
    row = await (conn.fetchrow(q, user_id) if conn else db.fetchrow(q, user_id))
    return (row["xp"], row["loam"]) if row else (0, 0)


async def xp_today(user_id: str) -> int:
    """XP earned since midnight, which fills the daily goal track."""
    return await db.fetchval(
        "SELECT coalesce(sum(xp), 0)::int FROM point_events WHERE user_id = $1 AND time >= date_trunc('day', now())",
        user_id,
    ) or 0


async def care_days(user_id: str, conn: asyncpg.Connection | None = None) -> tuple[list[date], list[date]]:
    """(days with a care action, days covered by a Lid Lock)."""
    q = """
        SELECT DISTINCT date_trunc('day', time)::date AS d, kind = 'lid_lock_used' AS locked
        FROM point_events WHERE user_id = $1 AND kind = ANY($2::text[])
    """
    rows = await (conn.fetch(q, user_id, list(game.CARE_KINDS)) if conn else db.fetch(q, user_id, list(game.CARE_KINDS)))
    cared = {r["d"] for r in rows if not r["locked"]}
    locked = {r["d"] for r in rows if r["locked"]} - cared
    return sorted(cared), sorted(locked)


async def streaks(user_id: str) -> tuple[int, int]:
    """(current, best) streak in days. Lid Lock days count as kept."""
    cared, locked = await care_days(user_id)
    return game.streak_lengths(cared + locked, date.today())


async def streak_at_risk(user_id: str) -> bool:
    """A live streak with no care action yet today."""
    cared, locked = await care_days(user_id)
    current, _ = game.streak_lengths(cared + locked, date.today())
    return current > 0 and date.today() not in cared


async def apply_lid_locks(conn: asyncpg.Connection, user_id: str) -> int:
    """Spend Lid Locks to cover missed days, as applyCareAction() does.

    Called right after a care action. If there is a gap between today and the
    last care day and the player holds enough Lid Locks, each missed day gets
    a 'lid_lock_used' row (dated that day) and a lock is spent. Returns the
    number of locks used.
    """
    cared, locked = await care_days(user_id, conn)
    today = date.today()
    if today not in cared:
        return 0
    missed = game.missed_days_to_cover([d for d in cared + locked if d != today] + [today], today)
    if not missed:
        return 0
    locks = await conn.fetchval("SELECT lid_locks FROM user_state WHERE user_id = $1 FOR UPDATE", user_id) or 0
    if len(missed) > locks:
        return 0  # Not enough locks: the streak resets, as in the app.
    for d in missed:
        await conn.execute(
            """
            INSERT INTO point_events (time, user_id, kind, dedupe_key, meta)
            SELECT $1, $2, 'lid_lock_used', $3, '{}'::jsonb
            WHERE NOT EXISTS (SELECT 1 FROM point_events WHERE user_id = $2 AND dedupe_key = $3)
            """,
            datetime.combine(d, time(12), tzinfo=timezone.utc),
            user_id,
            f"lidlock:{d.isoformat()}",
        )
    await conn.execute("UPDATE user_state SET lid_locks = lid_locks - $2 WHERE user_id = $1", user_id, len(missed))
    return len(missed)


async def count(user_id: str, kind: str) -> int:
    return await db.fetchval("SELECT count(*)::int FROM point_events WHERE user_id = $1 AND kind = $2", user_id, kind) or 0


async def ensure_user(conn: asyncpg.Connection, user_id: str) -> None:
    await conn.execute("INSERT INTO user_state (user_id) VALUES ($1) ON CONFLICT DO NOTHING", user_id)
    # Everyone owns the starter finish, so they can always switch back to it.
    await conn.execute(
        "INSERT INTO collection (user_id, collectible_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        user_id,
        game.STARTER_FINISH,
    )
