"""Drop the pre-spec schema, then apply the current one.

DESTRUCTIVE. Only for the old two-layer tables, whose shape cannot be
migrated into the wide one-row-per-POST readings table. Requires --yes.

    python -m scripts.reset_db --yes

Afterwards, register the bin and seed demo data:

    python -m scripts.init_db --bin bin-001
    python -m scripts.seed_demo --bin bin-001 --days 3
"""

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import db  # noqa: E402

# Order matters: aggregates before their source tables.
LEGACY = [
    "DROP MATERIALIZED VIEW IF EXISTS readings_hourly CASCADE",
    "DROP TABLE IF EXISTS points_ledger CASCADE",
    "DROP TABLE IF EXISTS advice CASCADE",
    "DROP TABLE IF EXISTS add_log CASCADE",
    "DROP TABLE IF EXISTS readings CASCADE",
    "DROP TABLE IF EXISTS zones CASCADE",
    "DROP TABLE IF EXISTS devices CASCADE",
]


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--yes", action="store_true", help="confirm the drop")
    args = parser.parse_args()

    await db.connect()

    counts = []
    for table in ("devices", "readings", "add_log", "advice", "points_ledger"):
        try:
            row = await db.fetchrow(f"SELECT count(*) AS n FROM {table}")
            counts.append(f"{table}={row['n']}")
        except Exception:
            counts.append(f"{table}=absent")
    print("legacy rows:", ", ".join(counts))

    if not args.yes:
        print("\nnothing dropped. re-run with --yes to proceed.")
        await db.disconnect()
        return

    for stmt in LEGACY:
        print("  ", stmt)
        await db.execute(stmt)

    print("\napplying current schema...")
    await db.apply_schema()
    print("done")
    await db.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
