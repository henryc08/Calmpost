"""Seed readings, log entries, a care history, an economy and a league so the
app is not empty.

    python -m scripts.seed_demo --bin bin-001 --days 3
    python -m scripts.seed_demo --bin bin-001 --scenario too_wet
    python -m scripts.seed_demo --bin bin-001 --no-league --no-economy

Scenarios mirror MockRepository's: healthy, too_wet, too_dry, curing, ready.
The default arc runs wet-and-hot to cool-and-quiet, which is the shape that
makes the Batch Journey stages visible on one screen.
"""

import argparse
import asyncio
import math
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import db  # noqa: E402
from app.catalog import collectibles  # noqa: E402
from app.services import economy  # noqa: E402

STEP = timedelta(minutes=5)

# Endpoint targets per scenario: (moisture_pct, probe_temp_c, co2_ppm).
SCENARIOS = {
    "healthy": (52.0, 38.0, 1800.0),
    "too_wet": (72.0, 34.0, 2600.0),
    "too_dry": (28.0, 24.0, 700.0),
    "curing": (50.0, 28.0, 900.0),
    "ready": (46.0, 19.0, 450.0),
}

ITEMS = [
    ("banana peel", "green", 120),
    ("coffee grounds", "green", 80),
    ("shredded cardboard", "brown", 60),
    ("apple core", "green", 90),
    ("dry leaves", "brown", 50),
    ("vegetable peels", "green", 150),
    ("shredded paper", "brown", 40),
]

BOT_NAMES = [
    "Maya", "Ravi", "Jonas", "Lena", "Omar", "Priya", "Nils", "Tara", "Kofi",
    "Sora", "Mateo", "Ines", "Hugo", "Yuki", "Aziz", "Noor", "Dara", "Theo",
    "Ada", "Bruno", "Wen", "Iris", "Luca", "Mina", "Pedro", "Rosa", "Sven",
    "Vera", "Zane",
]


def raw_from_pct(pct: float, dry: int, wet: int) -> int:
    """Invert the calibration so seeded data is consistent with the probe."""
    return int(round(dry - (pct / 100.0) * (dry - wet)))


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", dest="bin_id", required=True)
    parser.add_argument("--days", type=int, default=3)
    parser.add_argument("--scenario", choices=sorted(SCENARIOS), default=None,
                        help="hold a fixed state instead of the default arc")
    parser.add_argument("--no-league", action="store_true")
    parser.add_argument("--no-economy", action="store_true", help="skip Loam, crates, collection and streak history")
    args = parser.parse_args()

    await db.connect()
    binr = await db.fetchrow(
        "SELECT owner_id, moisture_raw_dry, moisture_raw_wet FROM bins WHERE bin_id = $1",
        args.bin_id,
    )
    if binr is None:
        raise SystemExit(f"bin {args.bin_id} is not registered -- run init_db first")

    dry, wet = binr["moisture_raw_dry"], binr["moisture_raw_wet"]
    user_id = binr["owner_id"]

    now = datetime.now(timezone.utc)
    start = now - timedelta(days=args.days)

    rows = []
    t = start
    while t <= now:
        p = (t - start) / (now - start)
        diurnal = math.sin((t.hour / 24) * 2 * math.pi)

        if args.scenario:
            pct, temp, co2 = SCENARIOS[args.scenario]
            pct += random.uniform(-1.5, 1.5)
            temp += 1.0 * diurnal + random.uniform(-0.4, 0.4)
            co2 += random.uniform(-60, 60)
        else:
            # Wet and hot -> drier, cooler, quieter.
            pct = 70 - 22 * p + random.uniform(-1.5, 1.5)
            temp = 44 - 22 * p + 1.5 * diurnal + random.uniform(-0.5, 0.5)
            co2 = 3200 - 2700 * p + random.uniform(-80, 80)

        pct = max(0.0, min(100.0, pct))
        rows.append(
            (
                t,
                args.bin_id,
                "top",
                round(temp, 1),
                raw_from_pct(pct, dry, wet),
                round(pct, 1),
                round(max(co2, 400), 0),
                round(temp - 12 + random.uniform(-0.5, 0.5), 1),  # ambient air
                round(min(99.0, pct + 8 + random.uniform(-3, 3)), 1),  # humidity
                0,
            )
        )
        t += STEP

    async with db.pool().acquire() as conn:
        await conn.executemany(
            """
            INSERT INTO readings
                (time, bin_id, probe_layer, probe_temp_c, moisture_raw,
                 moisture_pct, co2_ppm, air_temp_c, air_humidity_pct, co2_status)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            ON CONFLICT (bin_id, time) DO NOTHING
            """,
            rows,
        )
        await conn.execute(
            "UPDATE bins SET last_seen_at = $2 WHERE bin_id = $1", args.bin_id, now
        )

        # A week of adds so the greens:browns balance is not empty.
        for day in range(7, 0, -1):
            for item, category, grams in random.sample(ITEMS, k=random.randint(1, 3)):
                await conn.execute(
                    """
                    INSERT INTO add_log
                        (time, bin_id, user_id, item, category, action, quantity_g, source)
                    VALUES ($1, $2, $3, $4, $5, 'added', $6, 'seed')
                    """,
                    now - timedelta(days=day, hours=random.randint(0, 12)),
                    args.bin_id,
                    user_id,
                    item,
                    category,
                    grams,
                )

    await refresh("readings_15m", "readings_1d")

    print(f"inserted {len(rows)} readings for {args.bin_id} over {args.days} day(s)"
          + (f" (scenario={args.scenario})" if args.scenario else ""))

    if not args.no_economy:
        await seed_economy(user_id)
    if not args.no_league:
        await seed_league(user_id)

    await db.disconnect()


async def refresh(*views: str) -> None:
    """Refresh continuous aggregates now (they also refresh on a policy).
    Cannot run inside a transaction."""
    for view in views:
        await db.execute(f"CALL refresh_continuous_aggregate('{view}', NULL, NULL)")


def _noon(days_ago: int) -> datetime:
    d = datetime.now(timezone.utc).date() - timedelta(days=days_ago)
    return datetime.combine(d, datetime.min.time(), tzinfo=timezone.utc) + timedelta(hours=12)


async def seed_economy(user_id: str) -> None:
    """A mid-game player, matching the app's mock: a 12-day streak (one day
    kept by a Lid Lock, today not yet cared for), 240 Loam, a Sprout and a
    Grove crate waiting, 1 Seed Packet, 1 Lid Lock and 10 collectibles.
    Idempotent: dedupe keys and ON CONFLICT make re-running a no-op."""
    async with db.pool().acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                """
                INSERT INTO user_state (user_id, display_name, lid_locks, packets)
                VALUES ($1, 'You', 1, 1)
                ON CONFLICT (user_id) DO UPDATE SET lid_locks = 1, packets = 1
                """,
                user_id,
            )
            for days_ago in range(1, 13):
                kind = "lid_lock_used" if days_ago == 6 else "check_in"
                await conn.execute(
                    """
                    INSERT INTO point_events (time, user_id, kind, xp, dedupe_key, meta)
                    SELECT $1, $2, $3, $4, $5, '{"seed": true}'::jsonb
                    WHERE NOT EXISTS (SELECT 1 FROM point_events WHERE user_id = $2 AND dedupe_key = $5)
                    """,
                    _noon(days_ago),
                    user_id,
                    kind,
                    0 if kind == "lid_lock_used" else 5,
                    f"seed:{kind}:{days_ago}",
                )
            await conn.execute(
                """
                INSERT INTO point_events (user_id, kind, loam, dedupe_key, meta)
                SELECT $1, 'seed', 240, 'seed:loam', '{"seed": true}'::jsonb
                WHERE NOT EXISTS (SELECT 1 FROM point_events WHERE user_id = $1 AND dedupe_key = 'seed:loam')
                """,
                user_id,
            )
            for tier in ("sprout", "grove"):
                await economy.grant_crate(conn, user_id, tier, "seed", f"seed:crate:{tier}")
            owned = [c["id"] for c in collectibles.COLLECTIBLES if c["rarity"] in ("common", "uncommon") and c["id"] != "finish_classic"][:9]
            for cid in ["finish_classic", *owned][:10]:
                await conn.execute(
                    "INSERT INTO collection (user_id, collectible_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                    user_id,
                    cid,
                )
    await refresh("xp_weekly")
    print("seeded economy: 12-day streak, 240 Loam, 2 crates, 1 packet, 1 Lid Lock, 10 collectibles")


async def seed_league(user_id: str) -> None:
    """Put the user in a league with 29 bots, as MockRepository does."""
    week_start = economy.week_start()
    async with db.pool().acquire() as conn:
        async with conn.transaction():
            league = await conn.fetchrow(
                """
                INSERT INTO leagues (tier, week_start) VALUES ('Fern', $1)
                ON CONFLICT (tier, week_start) DO UPDATE SET tier = EXCLUDED.tier
                RETURNING id
                """,
                week_start,
            )
            await conn.execute(
                """
                INSERT INTO league_members (league_id, user_id, display_name, is_bot)
                VALUES ($1, $2, 'You', false)
                ON CONFLICT (league_id, user_id) DO NOTHING
                """,
                league["id"],
                user_id,
            )
            for i, name in enumerate(BOT_NAMES):
                bot_id = f"bot-{i:02d}"
                await conn.execute(
                    """
                    INSERT INTO league_members
                        (league_id, user_id, display_name, is_bot, is_friend, streak)
                    VALUES ($1, $2, $3, true, $4, $5)
                    ON CONFLICT (league_id, user_id) DO UPDATE
                        SET is_friend = EXCLUDED.is_friend, streak = EXCLUDED.streak
                    """,
                    league["id"],
                    bot_id,
                    name,
                    i % 5 == 0,           # a few of them read as friends
                    random.randint(0, 24),
                )
                # Give the bots a plausible spread of weekly XP.
                xp = max(0, int(random.gauss(120, 70)))
                await conn.execute(
                    """
                    INSERT INTO point_events (time, user_id, kind, xp, meta)
                    VALUES ($1, $2, 'seed', $3, '{"bot": true}'::jsonb)
                    """,
                    datetime.combine(
                        week_start, datetime.min.time(), tzinfo=timezone.utc
                    ) + timedelta(hours=random.randint(1, 100)),
                    bot_id,
                    xp,
                )
    await refresh("xp_weekly")
    print(f"seeded 'Fern' league for week of {week_start} with 29 bots")


if __name__ == "__main__":
    asyncio.run(main())
