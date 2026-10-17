"""Quests, the daily goal, achievements, crates, Seed Packets and the shop.

Mirrors GameController in app/lib/state/game.dart, but server-authoritative:
every spend locks the player's user_state row (SELECT ... FOR UPDATE) so two
taps cannot double-spend, and every once-only reward is dedupe_keyed.
"""

import random
import secrets
from datetime import date, datetime, time, timedelta, timezone

import asyncpg
from fastapi import HTTPException

from .. import db
from ..catalog.collectibles import BY_ID as COLLECTIBLES_BY_ID
from ..catalog.collectibles import COLLECTIBLES
from ..rules import game, gacha, progression
from . import binstate, ledger

_rng = random.SystemRandom()


# --- quests ------------------------------------------------------------------

async def quest_progress(user_id: str) -> dict[str, float]:
    """Today's progress for the three quests."""
    today_kinds = await db.fetch(
        """
        SELECT kind, count(*)::int AS n FROM point_events
        WHERE user_id = $1 AND time >= date_trunc('day', now()) GROUP BY kind
        """,
        user_id,
    )
    n = {r["kind"]: r["n"] for r in today_kinds}

    # "Both layers in range for 6h": hours today inside the band, best bin.
    # With one probe this is the measured layer, which the app labels honestly.
    hours = 0.0
    for b in await db.fetch("SELECT bin_id FROM bins WHERE owner_id = $1", user_id):
        h = await binstate.healthy_hours_today(b["bin_id"])
        hours = max(hours, h or 0.0)

    return {"checkin": n.get("check_in", 0), "follow": n.get("followed_suggestion", 0), "healthy": hours}


async def quests_today(user_id: str) -> list[dict]:
    progress = await quest_progress(user_id)
    day = date.today().isoformat()
    claimed = {
        r["dedupe_key"]
        for r in await db.fetch(
            "SELECT dedupe_key FROM point_events WHERE user_id = $1 AND kind = 'daily_quest' AND time >= date_trunc('day', now())",
            user_id,
        )
    }
    out = []
    for q in game.QUESTS:
        p = min(float(progress[q["key"]]), float(q["goal"]))
        out.append({**q, "progress": p, "done": p >= q["goal"], "claimed": f"quest:{q['key']}:{day}" in claimed})
    return out


async def claim_quest(user_id: str, key: str) -> dict:
    q = game.QUESTS_BY_KEY.get(key)
    if q is None:
        raise HTTPException(404, "unknown quest")
    progress = (await quest_progress(user_id))[key]
    if progress < q["goal"]:
        raise HTTPException(409, "quest is not complete yet")
    claim_key = f"quest:{key}:{date.today().isoformat()}"
    async with db.pool().acquire() as conn, conn.transaction():
        await ledger.ensure_user(conn, user_id)
        xp = await ledger.award(
            conn, user_id, "daily_quest", xp=q["xp"], loam=q["loam"],
            dedupe_key=claim_key, meta={"quest": key},
        )
    if xp == 0:
        raise HTTPException(409, "quest already claimed today")
    paid_loam = await db.fetchval("SELECT loam FROM point_events WHERE user_id=$1 AND dedupe_key=$2", user_id, claim_key)
    return {"quest": key, "xp_awarded": xp, "loam_awarded": paid_loam}


async def claim_level(user_id: str, level: int) -> dict:
    if not 1 <= level <= progression.MAX_LEVEL:
        raise HTTPException(404, "unknown level")
    reward = progression.level_reward(level)
    key = f"level:{level}"
    async with db.pool().acquire() as conn, conn.transaction():
        await ledger.ensure_user(conn, user_id)
        await conn.fetchval("SELECT user_id FROM user_state WHERE user_id=$1 FOR UPDATE", user_id)
        xp, _ = await ledger.balances(user_id, conn)
        if game.level_for_xp(xp) < level:
            raise HTTPException(409, "reach this level first")
        if await conn.fetchval("SELECT 1 FROM point_events WHERE user_id=$1 AND dedupe_key=$2", user_id, key):
            return {"level": level, **reward, "duplicate": True}
        await ledger.award(conn, user_id, "level_reward", xp=0, loam=reward['loam'], dedupe_key=key)
        await conn.execute("UPDATE user_state SET packets=packets+$2 WHERE user_id=$1", user_id, reward['packets'])
        if reward['crate']:
            await grant_crate(conn, user_id, reward['crate'], 'level_reward', key)
        if reward['seed']:
            # Guaranteed unlock, not a random pull; never reduces existing copies.
            await conn.execute("INSERT INTO collection(user_id,collectible_id) VALUES($1,$2) ON CONFLICT(user_id,collectible_id) DO UPDATE SET copies=greatest(collection.copies,1)", user_id, reward['seed'])
    return {"level": level, **reward, "duplicate": False}


# --- daily goal ----------------------------------------------------------------

async def daily_goal(user_id: str) -> dict:
    xp = await ledger.xp_today(user_id)
    day = date.today().isoformat()
    keys = {
        r["dedupe_key"]
        for r in await db.fetch(
            "SELECT dedupe_key FROM point_events WHERE user_id = $1 AND kind = 'daily_goal' AND time >= date_trunc('day', now())",
            user_id,
        )
    }
    return {
        "xp_today": xp,
        "goals": [
            {"index": i, **g, "reached": xp >= g["xp"], "claimed": f"daily_goal:{day}:{i}" in keys}
            for i, g in enumerate(game.DAILY_GOALS)
        ],
    }


async def claim_daily_goal(user_id: str, index: int) -> dict:
    if not 0 <= index < len(game.DAILY_GOALS):
        raise HTTPException(404, "unknown daily goal")
    goal = game.DAILY_GOALS[index]
    if await ledger.xp_today(user_id) < goal["xp"]:
        raise HTTPException(409, "not enough XP today yet")
    key = f"daily_goal:{date.today().isoformat()}:{index}"
    async with db.pool().acquire() as conn, conn.transaction():
        await ledger.ensure_user(conn, user_id)
        if await conn.fetchval("SELECT 1 FROM point_events WHERE user_id = $1 AND dedupe_key = $2", user_id, key):
            raise HTTPException(409, "already claimed today")
        await ledger.award(conn, user_id, "daily_goal", xp=0, loam=goal["loam"], dedupe_key=key, meta={"index": index})
        crate_id = await grant_crate(conn, user_id, goal["crate"], "daily_goal", key) if goal["crate"] else None
    return {"index": index, "loam_awarded": goal["loam"], "crate": goal["crate"], "crate_id": crate_id}


# --- crates ----------------------------------------------------------------------

async def grant_crate(conn: asyncpg.Connection, user_id: str, tier: str, source: str, dedupe_key: str | None) -> int | None:
    """Put a crate in the rewards inbox. Returns its id, or None if already granted."""
    return await conn.fetchval(
        """
        INSERT INTO crates (user_id, tier, source, dedupe_key) VALUES ($1, $2, $3, $4)
        ON CONFLICT (user_id, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING
        RETURNING id
        """,
        user_id,
        tier,
        source,
        dedupe_key,
    )


async def rewards(user_id: str) -> dict:
    crates = await db.fetch(
        "SELECT id, tier, source, earned_at FROM crates WHERE user_id = $1 AND opened_at IS NULL ORDER BY earned_at",
        user_id,
    )
    packets = await db.fetchval("SELECT packets FROM user_state WHERE user_id = $1", user_id) or 0
    return {"crates": [dict(c) | {"name": game.crate_name(c["tier"])} for c in crates], "packets": packets}


async def open_crate(user_id: str, crate_id: int) -> dict:
    async with db.pool().acquire() as conn, conn.transaction():
        crate = await conn.fetchrow(
            "SELECT id, tier, opened_at FROM crates WHERE id = $1 AND user_id = $2 FOR UPDATE", crate_id, user_id
        )
        if crate is None:
            raise HTTPException(404, "unknown crate")
        if crate["opened_at"] is not None:
            raise HTTPException(409, "crate already opened")
        contents = game.CRATE_CONTENTS[crate["tier"]]
        await ledger.ensure_user(conn, user_id)
        await conn.execute(
            "UPDATE crates SET opened_at = now(), loam_awarded = $2, packets_awarded = $3 WHERE id = $1",
            crate_id, contents["loam"], contents["packets"],
        )
        await conn.execute("UPDATE user_state SET packets = packets + $2 WHERE user_id = $1", user_id, contents["packets"])
        await ledger.award(conn, user_id, "crate_open", xp=0, loam=contents["loam"], meta={"crate_id": crate_id, "tier": crate["tier"]})
    return {"crate_id": crate_id, "tier": crate["tier"], "name": game.crate_name(crate["tier"]), **contents}


# --- achievements & streak milestones (settled lazily, idempotently) --------------

async def stats(user_id: str) -> dict:
    """Progress numbers the achievements read."""
    row = await db.fetchrow(
        """
        SELECT
          count(*) FILTER (WHERE kind = 'harvest')::int             AS harvests,
          count(DISTINCT date_trunc('day', time)) FILTER (WHERE kind = 'healthy_layer_day')::int AS healthy_days,
          count(*) FILTER (WHERE kind = 'weekly_balance')::int      AS balanced_weeks,
          count(*) FILTER (WHERE kind = 'followed_suggestion')::int AS tips_followed,
          count(*) FILTER (WHERE kind = 'daily_quest')::int         AS quests_claimed,
          count(*) FILTER (WHERE kind = 'league_finish' AND meta->>'zone' = 'promote')::int AS promotions
        FROM point_events WHERE user_id = $1
        """,
        user_id,
    )
    grams = await db.fetchval(
        "SELECT coalesce(sum(quantity_g), 0)::int FROM add_log WHERE user_id = $1 AND action = 'added' AND category IN ('green', 'brown')",
        user_id,
    )
    drops = await db.fetchval(
        """
        SELECT count(*)::int FROM drop_events d JOIN bins b ON b.bin_id = d.bin_id
        WHERE b.owner_id = $1 AND d.status = 'confirmed'
        """,
        user_id,
    )
    _, best = await ledger.streaks(user_id)
    return {
        **dict(row),
        "best_streak": best,
        "kg_diverted": round((grams or 0) / 1000.0, 2),
        "drops_confirmed": drops or 0,
        # Friend quests are not tracked server-side yet.
        "friend_quests": 0,
    }


def achievements_from(s: dict) -> list[dict]:
    out = []
    for a in game.ACHIEVEMENTS:
        progress = s.get(a["metric"], 0)
        tier = game.achievement_tier(a["goals"], progress)
        maxed = tier >= len(a["goals"])
        out.append(
            {
                "id": a["id"],
                "title": a["title"],
                "description": a["description"],
                "progress": progress,
                "goals": list(a["goals"]),
                "rewards": list(a["rewards"]),
                "tier": tier,
                "maxed": maxed,
                "next_goal": a["goals"][-1] if maxed else a["goals"][tier],
                "next_reward": a["rewards"][-1] if maxed else a["rewards"][tier],
            }
        )
    return out


async def settle(user_id: str) -> dict:
    """Pay out anything earned but not yet granted: achievement-tier crates
    and streak-milestone Loam + crates. Idempotent (dedupe keys)."""
    s = await stats(user_id)
    granted: list[dict] = []
    async with db.pool().acquire() as conn, conn.transaction():
        await ledger.ensure_user(conn, user_id)
        for a in achievements_from(s):
            for t in range(a["tier"]):
                tier = a["rewards"][t]
                if await grant_crate(conn, user_id, tier, f"achievement:{a['id']}", f"ach:{a['id']}:{t + 1}"):
                    granted.append({"achievement": a["id"], "tier": t + 1, "crate": tier})
        for m in game.STREAK_MILESTONES:
            if s["best_streak"] < m["days"]:
                continue
            key = f"streak:{m['days']}"
            new_loam = await conn.fetchval("SELECT 1 FROM point_events WHERE user_id = $1 AND dedupe_key = $2", user_id, key) is None
            if new_loam:
                await ledger.award(conn, user_id, "streak_milestone", xp=0, loam=m["loam"], dedupe_key=key, meta={"days": m["days"]})
            new_crate = await grant_crate(conn, user_id, m["crate"], "streak_milestone", key) if m["crate"] else None
            if new_loam or new_crate:
                granted.append({"streak": m["days"], "loam": m["loam"], "crate": m["crate"]})
    return {"stats": s, "granted": granted}


# --- Seed Packets (gacha) -------------------------------------------------------

async def collection(user_id: str) -> dict:
    owned = {r["collectible_id"]: r["copies"] for r in await db.fetch("SELECT collectible_id, copies FROM collection WHERE user_id = $1", user_id)}
    st = await db.fetchrow(
        "SELECT packets, pity_since_epic, pity_since_legendary, equipped_finish, equipped_title FROM user_state WHERE user_id = $1",
        user_id,
    )
    _, loam = await ledger.balances(user_id)
    return {
        "loam": loam,
        "packets": st["packets"] if st else 0,
        "pity": {
            "since_epic": st["pity_since_epic"] if st else 0,
            "since_legendary": st["pity_since_legendary"] if st else 0,
            "epic_within": gacha.EPIC_PITY - (st["pity_since_epic"] if st else 0),
            "legendary_within": gacha.LEGENDARY_PITY - (st["pity_since_legendary"] if st else 0),
        },
        "equipped_finish": st["equipped_finish"] if st else "finish_classic",
        "equipped_title": st["equipped_title"] if st else None,
        "collected": sum(1 for v in owned.values() if v > 0),
        "total": len(COLLECTIBLES),
        "items": [{**c, "copies": owned.get(c["id"], 0)} for c in COLLECTIBLES],
        "odds": gacha.ODDS,
        "duplicate_refund": gacha.DUPLICATE_REFUND,
        "prices": {"packet": gacha.PACKET_PRICE, "ten_pack": gacha.TEN_PACK_PRICE},
    }


async def pull(user_id: str, count: int, paid_with: str) -> dict:
    """Open `count` Seed Packets (1 or 10), paid with owned packets or Loam."""
    if count not in (1, 10):
        raise HTTPException(422, "pull 1 or 10")
    if paid_with not in ("packet", "loam"):
        raise HTTPException(422, "paid_with must be 'packet' or 'loam'")

    async with db.pool().acquire() as conn, conn.transaction():
        await ledger.ensure_user(conn, user_id)
        st = await conn.fetchrow("SELECT * FROM user_state WHERE user_id = $1 FOR UPDATE", user_id)
        cost = 0
        if paid_with == "packet":
            if st["packets"] < count:
                raise HTTPException(409, "not enough Seed Packets")
        else:
            cost = gacha.price(count)
            _, loam = await ledger.balances(user_id, conn)
            if loam < cost:
                raise HTTPException(409, "not enough Loam")

        rolls, since_epic, since_leg = gacha.roll(_rng, count, st["pity_since_epic"], st["pity_since_legendary"])
        batch = secrets.token_hex(6)
        owned = {r["collectible_id"]: r["copies"] for r in await conn.fetch("SELECT collectible_id, copies FROM collection WHERE user_id = $1", user_id)}
        results, refunds = [], 0
        for rarity, forced in rolls:
            item = gacha.pick(_rng, rarity)
            is_new = owned.get(item["id"], 0) == 0
            owned[item["id"]] = owned.get(item["id"], 0) + 1
            refund = 0 if is_new else gacha.DUPLICATE_REFUND[rarity]
            refunds += refund
            await conn.execute(
                """
                INSERT INTO collection (user_id, collectible_id, copies) VALUES ($1, $2, 1)
                ON CONFLICT (user_id, collectible_id) DO UPDATE SET copies = collection.copies + 1
                """,
                user_id, item["id"],
            )
            await conn.execute(
                """
                INSERT INTO gacha_pulls (user_id, collectible_id, rarity, paid_with, batch_id, is_new, refund_loam, pity)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                """,
                user_id, item["id"], rarity, paid_with, batch, is_new, refund, forced,
            )
            results.append({"item": item, "rarity": rarity, "is_new": is_new, "refund": refund, "pity": forced})

        await conn.execute(
            """
            UPDATE user_state SET pity_since_epic = $2, pity_since_legendary = $3,
                   packets = packets - $4 WHERE user_id = $1
            """,
            user_id, since_epic, since_leg, count if paid_with == "packet" else 0,
        )
        if cost:
            await ledger.award(conn, user_id, "gacha_spend", xp=0, loam=-cost, meta={"batch": batch, "count": count})
        if refunds:
            await ledger.award(conn, user_id, "gacha_refund", xp=0, loam=refunds, meta={"batch": batch})

    best = max(results, key=lambda r: gacha.rank(r["rarity"]))
    return {
        "batch_id": batch,
        "paid_with": paid_with,
        "cost_loam": cost,
        "refund_loam": refunds,
        "results": results,
        "best": best,
        "pity": {"epic_within": gacha.EPIC_PITY - since_epic, "legendary_within": gacha.LEGENDARY_PITY - since_leg},
    }


async def equip(user_id: str, collectible_id: str) -> dict:
    c = COLLECTIBLES_BY_ID.get(collectible_id)
    if c is None:
        raise HTTPException(404, "unknown collectible")
    copies = await db.fetchval("SELECT copies FROM collection WHERE user_id = $1 AND collectible_id = $2", user_id, collectible_id)
    if not copies:
        raise HTTPException(409, "you don't own that yet")
    column = {"finish": "equipped_finish", "title": "equipped_title", "specimen": "equipped_seed"}[c['type']]
    await db.execute(f"UPDATE user_state SET {column} = $2 WHERE user_id = $1", user_id, collectible_id)
    return {"equipped": collectible_id, "type": c["type"]}


# --- shop --------------------------------------------------------------------------

async def buy_lid_lock(user_id: str) -> dict:
    async with db.pool().acquire() as conn, conn.transaction():
        await ledger.ensure_user(conn, user_id)
        locks = await conn.fetchval("SELECT lid_locks FROM user_state WHERE user_id = $1 FOR UPDATE", user_id)
        if locks >= game.MAX_LID_LOCKS:
            raise HTTPException(409, f"you can hold at most {game.MAX_LID_LOCKS} Lid Locks")
        _, loam = await ledger.balances(user_id, conn)
        if loam < game.LID_LOCK_PRICE:
            raise HTTPException(409, "not enough Loam")
        await ledger.award(conn, user_id, "lid_lock_buy", xp=0, loam=-game.LID_LOCK_PRICE)
        await conn.execute("UPDATE user_state SET lid_locks = lid_locks + 1 WHERE user_id = $1", user_id)
    return {"lid_locks": locks + 1, "loam_spent": game.LID_LOCK_PRICE}


# --- leagues: pay last week's finish -------------------------------------------------

def week_start(today: date | None = None) -> date:
    """Most recent Sunday, matching the Sunday league reset."""
    today = today or date.today()
    return today - timedelta(days=(today.weekday() + 1) % 7)


async def settle_league_finishes(user_id: str) -> list[dict]:
    """Pay Loam for any finished week the player has not been paid for yet
    (promoted 150 / safe 60 / demoted 20). Lazy, so no Sunday job."""
    this_week = week_start()
    leagues = await db.fetch(
        """
        SELECT l.id, l.tier, l.week_start FROM league_members m JOIN leagues l ON l.id = m.league_id
        WHERE m.user_id = $1 AND l.week_start < $2
        """,
        user_id, this_week,
    )
    paid = []
    for lg in leagues:
        key = f"league:{lg['week_start'].isoformat()}"
        if await db.fetchval("SELECT 1 FROM point_events WHERE user_id = $1 AND dedupe_key = $2", user_id, key):
            continue
        members = await db.fetch(
            """
            SELECT m.user_id, coalesce(x.xp, 0) AS xp FROM league_members m
            LEFT JOIN xp_weekly x ON x.user_id = m.user_id AND x.week = $2::timestamptz
            WHERE m.league_id = $1 ORDER BY xp DESC, m.display_name
            """,
            lg["id"], datetime.combine(lg["week_start"], time.min, tzinfo=timezone.utc),
        )
        rank = next((i for i, m in enumerate(members, 1) if m["user_id"] == user_id), len(members))
        tier_index = game.LEAGUE_TIERS.index(lg["tier"]) if lg["tier"] in game.LEAGUE_TIERS else 0
        zone = game.league_zone(rank, len(members), tier_index)
        async with db.pool().acquire() as conn:
            await ledger.award(
                conn, user_id, "league_finish", xp=0, loam=game.LEAGUE_FINISH_LOAM[zone], dedupe_key=key,
                meta={"zone": zone, "rank": rank, "tier": lg["tier"]},
            )
        paid.append({"week_start": lg["week_start"], "rank": rank, "zone": zone, "loam": game.LEAGUE_FINISH_LOAM[zone]})
    return paid
