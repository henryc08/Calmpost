"""Backfill plausible readings so the charts are not empty during the demo.

    python -m scripts.seed_demo --device bin-01 --days 3

Writes a wet-then-drying top layer and a cooling bottom layer, which is the
shape that makes the life-cycle stages visible.
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

STEP = timedelta(minutes=5)


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True)
    parser.add_argument("--days", type=int, default=3)
    args = parser.parse_args()

    await db.connect()
    exists = await db.fetchrow(
        "SELECT 1 FROM devices WHERE device_id = $1", args.device
    )
    if exists is None:
        raise SystemExit(f"device {args.device} is not registered -- run init_db first")

    now = datetime.now(timezone.utc)
    start = now - timedelta(days=args.days)
    rows = []
    t = start
    while t <= now:
        # Fraction of the way through the window, so the pile visibly evolves.
        p = (t - start) / (now - start)
        diurnal = math.sin((t.hour / 24) * 2 * math.pi)

        top_moisture = 68 - 14 * p + random.uniform(-1.5, 1.5)
        top_temp = 42 - 10 * p + 1.5 * diurnal + random.uniform(-0.5, 0.5)
        bottom_moisture = 52 - 4 * p + random.uniform(-1, 1)
        bottom_temp = 28 - 8 * p + 1.0 * diurnal + random.uniform(-0.4, 0.4)
        co2 = 3200 - 2300 * p + random.uniform(-80, 80)

        rows += [
            (t, args.device, "top", round(top_moisture, 1), round(top_temp, 1), None),
            (t, args.device, "bottom", round(bottom_moisture, 1), round(bottom_temp, 1), None),
            (t, args.device, "airgap", None, None, round(max(co2, 400), 0)),
        ]
        t += STEP

    async with db.pool().acquire() as conn:
        await conn.executemany(
            """
            INSERT INTO readings
                (time, device_id, zone, moisture_pct, temperature_c, co2_ppm)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (device_id, zone, time) DO NOTHING
            """,
            rows,
        )
        await conn.execute(
            "UPDATE devices SET last_seen_at = $2 WHERE device_id = $1", args.device, now
        )
        # The charts read the rollup, so materialise what we just inserted.
        await conn.execute("CALL refresh_continuous_aggregate('readings_hourly', NULL, NULL)")

    print(f"inserted {len(rows)} readings for {args.device} over {args.days} day(s)")
    await db.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
