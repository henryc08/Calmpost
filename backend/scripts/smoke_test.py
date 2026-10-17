"""End-to-end check against a running server.

    python -m scripts.smoke_test --base http://127.0.0.1:8000 --device bin-01 --token <device token>

Posts a reading, reads it back, logs an item and fetches advice.
"""

import argparse
import os
import sys

import httpx


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8000")
    parser.add_argument("--device", default="bin-01")
    parser.add_argument("--token", required=True, help="device token")
    parser.add_argument("--api-key", default=os.environ.get("APP_API_KEY", "dev-change-me"))
    args = parser.parse_args()

    app_headers = {"X-API-Key": args.api_key}

    r = httpx.get(f"{args.base}/health", timeout=20)
    print("health      ", r.status_code, r.text[:120])

    r = httpx.post(
        f"{args.base}/v1/ingest",
        headers={"X-Device-Token": args.token},
        json={
            "device_id": args.device,
            "zones": [
                {"zone": "top", "moisture_pct": 64.2, "temperature_c": 38.1},
                {"zone": "bottom", "moisture_pct": 49.0, "temperature_c": 22.4},
                {"zone": "airgap", "co2_ppm": 1850},
            ],
        },
        timeout=20,
    )
    print("ingest      ", r.status_code, r.text[:200])
    if r.status_code != 200:
        return 1

    r = httpx.get(f"{args.base}/v1/devices/{args.device}/latest", headers=app_headers, timeout=20)
    print("latest      ", r.status_code, r.text[:300])

    r = httpx.get(
        f"{args.base}/v1/devices/{args.device}/history",
        params={"zone": "top", "hours": 24},
        headers=app_headers,
        timeout=20,
    )
    print("history     ", r.status_code, r.text[:200])

    r = httpx.post(
        f"{args.base}/v1/log",
        headers=app_headers,
        json={"device_id": args.device, "item": "shredded cardboard", "was_advised": True},
        timeout=20,
    )
    print("log         ", r.status_code, r.text[:200])

    r = httpx.get(f"{args.base}/v1/devices/{args.device}/advice", headers=app_headers, timeout=60)
    print("advice      ", r.status_code, r.text[:600])

    r = httpx.get(f"{args.base}/v1/users/demo-user/points", headers=app_headers, timeout=20)
    print("points      ", r.status_code, r.text[:200])
    return 0


if __name__ == "__main__":
    sys.exit(main())
