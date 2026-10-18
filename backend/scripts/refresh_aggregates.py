"""Force the chart aggregates to materialise now instead of on their schedule.

    python scripts/refresh_aggregates.py

readings_15m refreshes every 15 minutes and readings_1d every hour, which is
fine in normal running but not when you have just rebuilt them and want the
charts populated immediately -- after 008_bottom_trends.sql, for instance,
which recreates both and leaves them WITH NO DATA.

Deliberately a script rather than part of apply_schema: CALL
refresh_continuous_aggregate cannot run inside a transaction, and a failure in
the boot path would stop the backend starting. Refreshing is a convenience;
not starting is not.
"""

import asyncio
import os
import ssl
import sys

import asyncpg
from dotenv import load_dotenv

VIEWS = ("readings_15m", "readings_1d")


async def main() -> int:
    load_dotenv()
    url = os.environ.get("DATABASE_URL", "")
    if not url:
        print("DATABASE_URL is not set (backend/.env)")
        return 1
    url = url.replace("postgres://", "postgresql://").split("?")[0]

    # Tiger Data signs with its own private CA; sslmode=require means encrypt
    # without verifying the peer, and this matches that rather than pretending
    # to a stronger guarantee. See app/db.py.
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    conn = await asyncpg.connect(url, ssl=ctx)
    try:
        for view in VIEWS:
            print(f"refreshing {view} ...", flush=True)
            # NULL, NULL = the whole range. Cheap here: raw readings are kept
            # for 90 days and there are only a few thousand rows.
            await conn.execute(f"CALL refresh_continuous_aggregate('{view}', NULL, NULL)")
            rows = await conn.fetchval(f"SELECT count(*) FROM {view}")
            print(f"  {view}: {rows} buckets")
    finally:
        await conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
