"""Apply sql/schema.sql to TigerData and register a device.

    python -m scripts.init_db                 # schema only
    python -m scripts.init_db --device bin-01 # schema + mint a device token
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
    parser.add_argument("--device", help="device_id to register, e.g. bin-01")
    parser.add_argument("--owner", default="demo-user")
    args = parser.parse_args()

    await db.connect()
    print("applying schema...")
    await db.apply_schema()
    print("schema ok")

    if args.device:
        token = new_token()
        await db.execute(
            """
            INSERT INTO devices (device_id, display_name, token_sha256, owner_id)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (device_id) DO UPDATE SET token_sha256 = EXCLUDED.token_sha256
            """,
            args.device,
            args.device,
            hash_token(token),
            args.owner,
        )
        print(f"\ndevice_id   : {args.device}")
        print(f"device_token: {token}")
        print("\nPut that token in the Arduino sketch as DEVICE_TOKEN.")
        print("It is shown once -- only its hash is stored.")

    await db.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
