"""Apply sql/schema.sql to Tiger Data and register a bin.

    python -m scripts.init_db                   # schema only
    python -m scripts.init_db --bin bin-001     # schema + mint a device token
"""

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import db  # noqa: E402
from app.security import hash_token, new_token  # noqa: E402


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", dest="bin_id", help="bin to register, e.g. bin-001")
    parser.add_argument("--owner", default="demo-user")
    args = parser.parse_args()

    await db.connect()
    print("applying schema...")
    await db.apply_schema()
    print("schema ok")

    if args.bin_id:
        token = new_token()
        async with db.pool().acquire() as conn:
            async with conn.transaction():
                await conn.execute(
                    """
                    INSERT INTO bins (bin_id, display_name, token_sha256, owner_id)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT (bin_id) DO UPDATE SET token_sha256 = EXCLUDED.token_sha256
                    """,
                    args.bin_id,
                    args.bin_id,
                    hash_token(token),
                    args.owner,
                )
                await conn.execute(
                    "INSERT INTO user_state (user_id) VALUES ($1) ON CONFLICT DO NOTHING",
                    args.owner,
                )
        print(f"\nbin_id      : {args.bin_id}")
        print(f"device_token: {token}")
        print("\nPut that in firmware/secrets.h as DEVICE_TOKEN, or pass it to")
        print("the serial bridge. It is shown once -- only its hash is stored.")
        print("\nNext: calibrate the moisture probe, or percentages are guesses:")
        print(f"  POST /bins/{args.bin_id}/calibration "
              '{"moisture_raw_dry": <probe in air>, "moisture_raw_wet": <probe in water>}')

    await db.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
