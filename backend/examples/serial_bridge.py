"""Arduino -> USB serial -> Calmpost backend bridge.

For the setup where the board is wired to a laptop over USB rather than
POSTing over Wi-Fi itself. Reads one JSON object per line from the serial
port and forwards it to POST /v1/ingest.

    pip install pyserial requests python-dotenv
    python serial_bridge.py --port COM3 --api http://127.0.0.1:8000

Credentials come from backend/.env (DEVICE_TOKEN) or --token. Never hardcode
them here -- this file is committed.

What the Arduino should print, one line per sample:

    {"top_moisture":64.2,"top_temp":38.1,"bottom_moisture":49.0,
     "bottom_temp":22.4,"co2":1850}

Any missing field is simply omitted from the upload. Readings that fail the
backend's range checks are dropped with a logged reason rather than retried,
so one bad sensor cannot wedge the queue.
"""

import argparse
import json
import logging
import os
import time
from collections import deque
from pathlib import Path

import requests
import serial
from serial.tools import list_ports

log = logging.getLogger("bridge")

# Arduino field name -> (zone, backend field). Extend here if the sketch's
# JSON keys change; nothing else in this file needs to know about them.
FIELD_MAP = {
    "top_moisture": ("top", "moisture_pct"),
    "top_temp": ("top", "temperature_c"),
    "bottom_moisture": ("bottom", "moisture_pct"),
    "bottom_temp": ("bottom", "temperature_c"),
    "co2": ("airgap", "co2_ppm"),
    # Tolerate a few likely aliases so a firmware tweak does not break us.
    "co2_ppm": ("airgap", "co2_ppm"),
    "top_temperature": ("top", "temperature_c"),
    "bottom_temperature": ("bottom", "temperature_c"),
}


def to_payload(raw: dict, device_id: str) -> dict | None:
    """Reshape a flat Arduino reading into the /v1/ingest body.

    Returns None if the line carried no recognised sensor fields, so noise on
    the serial port (boot banners, debug prints) is skipped quietly.
    """
    # Already in the backend's shape? Pass it through.
    if "zones" in raw:
        return {"device_id": device_id, **raw}

    zones: dict[str, dict] = {}
    for key, value in raw.items():
        mapping = FIELD_MAP.get(key)
        if mapping is None or value is None:
            continue
        zone, field = mapping
        zones.setdefault(zone, {"zone": zone})[field] = value

    if not zones:
        return None
    return {"device_id": device_id, "zones": list(zones.values())}


def find_port() -> str | None:
    """Pick the most likely Arduino/ESP32 port when --port is not given."""
    candidates = list(list_ports.comports())
    for p in candidates:
        blurb = f"{p.description} {p.manufacturer or ''}".lower()
        if any(k in blurb for k in ("arduino", "ch340", "cp210", "ftdi", "usb serial", "silicon labs")):
            return p.device
    return candidates[0].device if candidates else None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", help="serial port, e.g. COM3 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--api", default="http://127.0.0.1:8000",
                        help="backend base URL (the laptop running uvicorn)")
    parser.add_argument("--device", default="bin-01")
    parser.add_argument("--token", default=os.environ.get("DEVICE_TOKEN"),
                        help="device token; defaults to DEVICE_TOKEN in env/.env")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    token = args.token
    if not token:
        # Fall back to backend/.env so the token is not typed on the command
        # line (where it would land in shell history).
        env = Path(__file__).resolve().parent.parent / ".env"
        if env.exists():
            for line in env.read_text(encoding="utf-8").splitlines():
                if line.startswith("DEVICE_TOKEN="):
                    token = line.split("=", 1)[1].strip()
    if not token:
        raise SystemExit(
            "no device token: pass --token, set DEVICE_TOKEN, or add "
            "DEVICE_TOKEN=... to backend/.env (get it from scripts/init_db.py)"
        )

    port = args.port or find_port()
    if not port:
        raise SystemExit("no serial port found -- plug the board in or pass --port")

    url = f"{args.api.rstrip('/')}/v1/ingest"
    headers = {"X-Device-Token": token, "Content-Type": "application/json"}
    session = requests.Session()

    # Hold samples that failed to upload so a dropped Wi-Fi link does not lose
    # data. Bounded so a long outage cannot eat all the laptop's memory.
    pending: deque[dict] = deque(maxlen=500)

    log.info("bridge: %s @ %d -> %s (device=%s)", port, args.baud, url, args.device)

    while True:
        try:
            with serial.Serial(port, args.baud, timeout=5) as ser:
                log.info("serial open")
                while True:
                    line = ser.readline().decode("utf-8", errors="replace").strip()
                    if not line:
                        continue
                    if not line.startswith("{"):
                        log.debug("skip non-json: %s", line[:80])
                        continue

                    try:
                        raw = json.loads(line)
                    except json.JSONDecodeError:
                        log.debug("bad json: %s", line[:80])
                        continue

                    payload = to_payload(raw, args.device)
                    if payload is None:
                        log.debug("no sensor fields in: %s", line[:80])
                        continue

                    pending.append(payload)
                    _drain(session, url, headers, pending)

        except serial.SerialException as exc:
            log.warning("serial error (%s); retrying in 3s", exc)
            time.sleep(3)
        except KeyboardInterrupt:
            log.info("stopped")
            return


def _drain(session, url, headers, pending: deque) -> None:
    """Upload queued samples oldest-first, stopping at the first failure."""
    while pending:
        payload = pending[0]
        try:
            resp = session.post(url, json=payload, headers=headers, timeout=10)
        except requests.RequestException as exc:
            log.warning("network error (%s); %d queued", exc, len(pending))
            return

        if resp.status_code == 200:
            pending.popleft()
            log.info("sent %s", json.dumps(payload["zones"]))
        elif resp.status_code in (401, 403):
            # Wrong or revoked token: retrying forever would just spam.
            raise SystemExit(f"auth rejected ({resp.status_code}): {resp.text[:200]}")
        elif resp.status_code == 422:
            # Out-of-range reading; drop it rather than block the queue.
            log.error("rejected (bad values), dropping: %s", resp.text[:200])
            pending.popleft()
        else:
            log.warning("server %s: %s; %d queued",
                        resp.status_code, resp.text[:120], len(pending))
            return


if __name__ == "__main__":
    main()
