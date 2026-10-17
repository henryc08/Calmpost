# Testing & debugging the backend

Four levels, cheapest first. If something breaks, work *down* this list —
the failure is almost always at the lowest level that still passes.

```
1. logic only      no DB, no network, no hardware
2. API + Tiger      server + database
3. real hardware    Arduino -> bridge -> API
4. the demo         same scrap, different answer
```

---

## 1. Logic only (seconds, nothing external)

Checks calibration maths, stage thresholds, XP values and level curves
without touching the database.

```bash
cd backend
.venv\Scripts\python.exe -c "from app.main import app; print(len(app.openapi()['paths']), 'routes')"
.venv\Scripts\python.exe -c "from app import compost; print(compost.moisture_pct(472, 620, 310))"
```

If `from app.main import app` fails, it's a syntax or import error — nothing
further will work until it's fixed.

## 2. API + Tiger Data

```bash
# one terminal
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# another
.venv\Scripts\python.exe -m scripts.smoke_test --token <device token>
```

17 checks: ingest, live, trends, the advice verdict, the always-avoid rule,
the XP rules, check-in, game/quests/leagues, and four auth rejections. Expect
`all checks passed`.

Interactive docs — the fastest way to poke one endpoint by hand:
<http://127.0.0.1:8000/docs> (click **Authorize**, paste `APP_API_KEY`).

No hardware? Seed fake data:

```bash
.venv\Scripts\python.exe -m scripts.seed_demo --bin bin-001 --days 3
.venv\Scripts\python.exe -m scripts.seed_demo --bin bin-001 --scenario too_wet
```

## 3. Real hardware

The sketch (`firmware/sensor_output/sensor_output.ino`) prints one JSON line
per second at **115200** and does not use Wi-Fi, so the path is
**USB → serial bridge → API**.

### Three things must be running

This is the most common reason "nothing is happening": `watch_db` only READS
Tiger Data. It does not talk to the board. With no bridge running you are
watching a database that nothing is feeding.

| Terminal | Command | Job |
| -------- | ------- | --- |
| 1 | `uvicorn app.main:app --host 0.0.0.0 --port 8000` | the API that writes to Tiger |
| 2 | `python examples/serial_bridge.py --port COM3` | Arduino → API |
| 3 | `python -m scripts.watch_db` | shows what landed (optional) |

```bash
pip install pyserial requests
.venv\Scripts\python.exe examples/serial_bridge.py --port COM3 --api http://127.0.0.1:8000
```

### Wi-Fi and hotspots do not matter for this path

The sketch talks over USB, so only the laptop needs internet (to reach Tiger
Cloud) and any network will do. A hotspot only matters later, when the
Flutter app on a phone needs to reach the laptop's LAN IP.

Expected output, one line per second:

```
INFO bridge: COM3 @ 115200 -> http://127.0.0.1:8000/ingest
INFO serial open
INFO sent raw=472 -> moisture=47.7%  (probe NOT calibrated)
```

**Read the serial port directly** when you want to rule the bridge out
entirely:

```bash
.venv\Scripts\python.exe -c "import serial; s=serial.Serial('COM3',115200,timeout=2); [print(s.readline().decode(errors='replace').strip()) for _ in range(5)]"
```

Note: `setup()` waits **~20 s** for the CO₂ sensor to settle, and opening the
port resets the board — so every reconnect costs another 20 s of silence
before the first line. That silence is normal, not a hang.

## 4. The demo moment

Prove the same scrap gets a different answer because the bin changed:

```bash
KEY=<APP_API_KEY>
curl -s -X POST "http://127.0.0.1:8000/bins/bin-001/advice/check?refresh=true" \
  -H "X-API-Key: $KEY" -H "Content-Type: application/json" \
  -d '{"item":"banana peel"}'
```

Squeeze the probe wet / let it dry (or post a synthetic reading), then run it
again with `?refresh=true`. `verdict` should move between `great`, `careful`
and `avoid` (the app's Verdict enum), and `input_snapshot` shows the readings
each answer was based on.

---

# Calibrate before trusting any percentage

**Do this before the demo.** Moisture is 45% of the health score, and the
default curve is only a guess. The sketch uses `analogReadResolution(10)`, so
raw counts run **0–1023** (a value near 470 in open air is typical).

1. Probe in **air**, note `moisture_raw` → that's your **dry** value.
2. Probe standing in **water** to normal depth, note it → **wet** value
   (capacitive probes read *lower* when wetter, so wet < dry).
3. Send both:

```bash
curl -X POST http://127.0.0.1:8000/bins/bin-001/calibration \
  -H "X-API-Key: $KEY" -H "Content-Type: application/json" \
  -d '{"moisture_raw_dry": 472, "moisture_raw_wet": 230}'
```

`backfill` (default true) replays the curve over stored history. Afterwards
`live()` reports `moisture_calibrated: true` and the warning note disappears.

Sanity check: with the probe in air, moisture should read near **0%**. If air
reads 48%, the curve is still wrong.

---

# Debugging by symptom

## The bridge prints nothing at all

| Check | How |
| ----- | --- |
| Is the board on COM3? | `.venv\Scripts\python.exe -c "from serial.tools import list_ports; [print(p.device, p.description) for p in list_ports.comports()]"` |
| Is the port already open? | Close the Arduino IDE **Serial Monitor** — Windows allows only one reader. This is the single most common cause. |
| Still in the 20 s settle? | Wait 25 s after connecting before concluding anything. |
| Right baud? | Must be 115200. A wrong baud gives garbage characters, not silence. |

## `auth rejected (401)`

The device token doesn't match. Mint a fresh one and update both places:

```bash
.venv\Scripts\python.exe -m scripts.init_db --bin bin-001
```

Then put it in `backend/.env` as `DEVICE_TOKEN=...`. Re-registering a bin
**revokes the previous token**, so an old bridge window will start failing.

## `403 token does not match device_id`

The token belongs to a different bin than the `device_id` in the JSON. The
sketch hardcodes `bin-001` (`const char DEVICE_ID[]`), so the registered bin
must also be `bin-001`.

## `422` on ingest

A value failed validation. The response body names the field. Ranges:
`probe_temp_c`/`air_temp_c` −40…125, `air_humidity_pct` 0…100,
`moisture_raw` 0…65535, `co2_ppm` 0…40000. The bridge **drops** 422s rather
than retrying, so one bad sensor can't block the queue.

## Everything reads 100% or 0% moisture

The calibration curve is wrong for the ADC range — see calibration above. A
10-bit board (0–1023) with a 12-bit curve (0–4095) pins every reading.

## `409 no readings for this bin yet`

`/live` and `/advice` need at least one stored reading. Run the bridge, or
seed: `scripts/seed_demo.py --bin bin-001 --days 1`.

## Charts are empty but `/live` works

`/trends` reads the continuous aggregates, which refresh on a schedule. Force
them (**not** inside a transaction — Timescale rejects that):

```bash
.venv\Scripts\python.exe -c "
import asyncio; from app import db
async def m():
    await db.connect()
    async with db.pool().acquire() as c:
        for v in ('readings_15m','readings_1d','xp_weekly'):
            await c.execute(f\"CALL refresh_continuous_aggregate('{v}', NULL, NULL)\")
    await db.disconnect()
asyncio.run(m())"
```

## Advice says `"model": "rules-fallback"`

Gemini didn't answer, and the rules took over (by design — the demo survives
a dead network). Causes: `GEMINI_API_KEY` missing from `.env`, quota
exhausted, or no internet. The server log holds the real exception. Note
`"model": "rules-always-avoid"` is **not** a failure — it means meat/dairy/oil
was blocked by rules before Gemini was ever called.

## Advice doesn't change when the bin changes

Answers are cached ~15 min against a *coarse* hash of bin state, so jitter
reuses one. Add `?refresh=true`. If it still doesn't move, the state genuinely
didn't change enough — check `input_snapshot` in the response.

## Database connection errors

| Error | Cause |
| ----- | ----- |
| `self-signed certificate in certificate chain` | Tiger Data signs with its own private CA. `app/db.py` matches the `sslmode=require` in the URL — don't "fix" this by adding a CA bundle. |
| `DATABASE_URL is not set` | No `.env`, or it's missing the line. |
| `invalid dsn` / connection refused | The URL must start `postgresql://`, **not** `postgres://` — asyncpg rejects the short form. |

## Server won't start

`schema.sql` runs on every boot. If it errors, the app won't come up — read
the traceback's SQL. The schema is idempotent, so a partial apply is safe to
re-run. To rebuild from scratch (**destroys data**):

```bash
.venv\Scripts\python.exe -m scripts.reset_db --yes
```

## Phone or Arduino can't reach the server

- Start with `--host 0.0.0.0`, not the default localhost.
- Both devices must be on the **same network** (a phone hotspot is the
  reliable choice; campus Wi-Fi usually blocks device-to-device traffic).
- Windows Firewall may prompt on first run — allow it.
- Check the laptop's LAN IP with `ipconfig` and use that in the app's
  `baseUrl`, not `127.0.0.1`.

---

# Inspecting Tiger Data directly

```bash
.venv\Scripts\python.exe -c "
import asyncio; from app import db
async def m():
    await db.connect()
    for q, label in [
        (\"SELECT count(*) n, max(time) latest FROM readings WHERE bin_id='bin-001'\", 'readings'),
        (\"SELECT count(*) n FROM add_log WHERE bin_id='bin-001'\", 'add_log'),
        (\"SELECT kind, sum(xp) xp FROM point_events GROUP BY kind ORDER BY xp DESC\", 'xp by kind'),
    ]:
        print(label, [dict(r) for r in await db.fetch(q)])
    await db.disconnect()
asyncio.run(m())"
```

Server logs are the first place to look for any 500: the traceback names the
file and line. Run uvicorn in a visible terminal rather than the background
while debugging.

## XP awards come back as 0

Action XP is capped at 60 per day (`dailyActionCap` in xp_rules.dart), so once
that is spent, further follows/skips/check-ins correctly award 0. It is the
anti-farming rule working, not a bug. Check what today has already paid:

```bash
.venv\Scripts\python.exe -c "
import asyncio; from app import db
async def m():
    await db.connect()
    for r in await db.fetch(\"\"\"SELECT kind, sum(xp)::int xp FROM point_events
        WHERE user_id='demo-user' AND time >= date_trunc('day', now())
        GROUP BY kind ORDER BY xp DESC\"\"\"):
        print(dict(r))
    await db.disconnect()
asyncio.run(m())"
```

Health-based XP (`healthy_layer_day`) sits outside the cap deliberately: it
depends on the sensors, so it cannot be farmed by tapping.
