"""Arduino -> USB serial -> Calmpost backend bridge.

For the setup where the board is wired to a laptop over USB instead of
POSTing over Wi-Fi itself. The sketch already prints exactly the shape
/ingest accepts, so this is mostly a reliable pipe: read a line, POST it,
retry when the network blips.

    pip install pyserial requests
    python scripts/serial_bridge.py --api http://127.0.0.1:8000

The port is auto-detected; pass --port COM3 to pin it. Baud defaults to
115200, matching SERIAL_BAUD in the sketch.

Lines the sketch prints for humans start with '#' and are ignored.

Expected input, one object per line:

    {"device_id":"bin-001","probe_temp_c":25.3,"moisture_raw":412,
     "co2_ppm":850,"air_temp_c":24.1,"air_humidity_pct":58.2,"co2_status":0}
"""

import argparse
from datetime import datetime, timezone
import json
import logging
import os
import time
from collections import deque
from pathlib import Path
from queue import Empty, Full, Queue
from threading import Event, Thread

import requests
import serial
from serial.tools import list_ports

log = logging.getLogger("bridge")

# Fields /ingest understands. Anything else in the line is dropped rather
# than forwarded, so a debug field in the sketch cannot cause a 422.
INGEST_FIELDS = {
    "device_id",
    "probe_temp_c",
    "moisture_raw",
    "co2_ppm",
    "air_temp_c",
    "air_humidity_pct",
    "co2_status",
    "probe_layer",
    "time",
}

# Tolerated spellings, so a firmware rename does not need a bridge change.
ALIASES = {
    "bin_id": "device_id",
    "co2": "co2_ppm",
    "probe_temperature_c": "probe_temp_c",
    "temp_c": "probe_temp_c",
    "humidity_pct": "air_humidity_pct",
    "air_rh_pct": "air_humidity_pct",
    "moisture": "moisture_raw",
}


def to_payload(raw: dict, default_device: str) -> dict | None:
    """Normalise one parsed line into an /ingest body.

    Returns None when the line carries no sensor data, so boot banners and
    stray prints are skipped quietly instead of being POSTed.
    """
    out: dict = {}
    for key, value in raw.items():
        field = ALIASES.get(key, key)
        if field in INGEST_FIELDS and value is not None:
            out[field] = value

    sensor_fields = INGEST_FIELDS - {"device_id", "probe_layer", "time"}
    if not (set(out) & sensor_fields):
        return None

    out.setdefault("device_id", default_device)
    out.setdefault("time", datetime.now(timezone.utc).isoformat())
    return out


def find_port() -> str | None:
    """Pick the most likely Arduino/ESP32 port when --port is not given."""
    candidates = list(list_ports.comports())
    for p in candidates:
        blurb = f"{p.description} {p.manufacturer or ''}".lower()
        if any(k in blurb for k in
               ("arduino", "ch340", "cp210", "ftdi", "usb serial", "silicon labs", "esp32")):
            return p.device
    return candidates[0].device if candidates else None


def load_token(explicit: str | None) -> str:
    if explicit:
        return explicit
    env_token = os.environ.get("DEVICE_TOKEN")
    if env_token:
        return env_token
    # Fall back to backend/.env so the token never reaches shell history.
    env = Path(__file__).resolve().parent.parent / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.startswith("DEVICE_TOKEN="):
                return line.split("=", 1)[1].strip()
    raise SystemExit(
        "no device token: pass --token, set DEVICE_TOKEN, or add DEVICE_TOKEN=... "
        "to backend/.env (printed by scripts/init_db.py)"
    )


class UploadWorker:
    """One HTTP writer; serial ingestion never waits for network I/O.

    Keep up to 500 queued samples plus the in-flight sample. If full, discard
    the incoming sample with a warning; accepted samples retain their order.
    This is an in-memory demo buffer, not durable offline storage.
    """

    def __init__(self, url, headers, *, capacity=500, retry_delay=1,
                 session_factory=requests.Session):
        self.url, self.headers = url, headers
        self.queue = Queue(maxsize=capacity)
        self.pending = deque()
        self.stop = Event()
        self.error = None
        self.retry_delay = retry_delay
        self.session_factory = session_factory
        self.thread = Thread(target=self._run, name="sensor-upload", daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.stop.set()
        self.thread.join(timeout=11)  # One bounded HTTP attempt may be finishing.
        remaining = self.queue.qsize() + len(self.pending)
        if remaining:
            log.warning("stopped; %d unsent samples remain in memory and will be lost", remaining)

    def raise_if_failed(self):
        if self.error is not None:
            raise SystemExit(self.error)

    def submit(self, payload):
        self.raise_if_failed()
        try:
            self.queue.put_nowait(payload)
            return True
        except Full:
            log.warning("upload queue full; dropping incoming sample at %s", payload.get("time"))
            return False

    def _run(self):
        try:
            with self.session_factory() as session:
                while not self.stop.is_set():
                    if not self.pending:
                        try:
                            self.pending.append(self.queue.get(timeout=0.1))
                        except Empty:
                            continue
                    _drain(session, self.url, self.headers, self.pending)
                    if self.pending:
                        self.stop.wait(self.retry_delay)
        except SystemExit as exc:
            self.error = str(exc)
        except Exception:
            # Make failures visible to the serial loop, without leaking tokens.
            self.error = "upload worker failed; restart the bridge and check the backend"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", help="serial port, e.g. COM3 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--api", default="http://127.0.0.1:8000",
                        help="backend base URL (the laptop running uvicorn)")
    parser.add_argument("--device", default="bin-001",
                        help="used only when a line omits device_id")
    parser.add_argument("--token")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    token = load_token(args.token)
    port = args.port or find_port()
    if not port:
        raise SystemExit("no serial port found -- plug the board in or pass --port")

    url = f"{args.api.rstrip('/')}/ingest"
    headers = {"X-Device-Token": token, "Content-Type": "application/json"}
    log.info("bridge: %s @ %d -> %s", port, args.baud, url)
    with UploadWorker(url, headers) as uploader:
        read_serial(port, args.baud, args.device, uploader)


def read_serial(port, baud, device, uploader):
    while True:
        try:
            uploader.raise_if_failed()
            with serial.Serial(port, baud, timeout=5) as ser:
                log.info("serial open")
                while True:
                    uploader.raise_if_failed()
                    line = ser.readline().decode("utf-8", errors="replace").strip()
                    if not line or line.startswith("#"):
                        if line:
                            log.debug("board: %s", line[1:].strip())
                        continue
                    if not line.startswith("{"):
                        log.debug("skip non-json: %s", line[:80])
                        continue

                    try:
                        raw = json.loads(line)
                    except json.JSONDecodeError:
                        log.debug("bad json: %s", line[:80])
                        continue

                    payload = to_payload(raw, device)
                    if payload is None:
                        log.debug("no sensor fields: %s", line[:80])
                        continue

                    uploader.submit(payload)

        except serial.SerialException as exc:
            log.warning("serial error (%s); retrying in 3s", exc)
            time.sleep(3)
        except KeyboardInterrupt:
            log.info("serial reader stopped")
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
            try:
                body = resp.json()
            except ValueError:
                body = {}
            if not isinstance(body, dict):
                body = {}
            pct = body.get("moisture_pct")
            log.info(
                "sent raw=%s -> moisture=%s%s",
                payload.get("moisture_raw"),
                f"{pct}%" if pct is not None else "n/a",
                "" if body.get("calibrated") else "  (probe NOT calibrated)",
            )
        elif resp.status_code in (401, 403):
            # Wrong or revoked token: retrying forever would just spam.
            raise SystemExit(f"auth rejected ({resp.status_code}); check the device token")
        elif resp.status_code == 422:
            # Out-of-range or malformed reading: drop it rather than block
            # every later sample behind it.
            log.error("rejected, dropping: %s", resp.text[:200])
            pending.popleft()
        else:
            log.warning("server %s: %s; %d queued",
                        resp.status_code, resp.text[:120], len(pending))
            return


if __name__ == "__main__":
    main()
