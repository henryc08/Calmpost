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

## 1. The test suite (seconds, no Tiger, no hardware)

```bash
cd backend
.venv\Scripts\python.exe -m pip install pytest pgserver    # once
.venv\Scripts\python.exe -m pytest
```

- **The database:** the tests use a **real local Postgres**. `pgserver` starts a throwaway server; set `TEST_DATABASE_URL` to use your own instead, and note that it gets **wiped**.
- **TimescaleDB stand-ins:** TimescaleDB-only statements are skipped locally, and `tests/timescale_stubs.sql` stands in for the hyperfunctions. Every endpoint and query still runs.
- **Without pgserver:** only the rule and parity tests run.

The suite covers:
- **the rules:** calibration maths, bands, stage, XP, the daily cap, levels, streaks across Lid Lock days, league zones and gacha pity
- **parity:** the backend's numbers and catalogs against the Dart app
- **the full API loop:** ingest, live, the same scrap getting a different answer, the logging XP rules, check-in, quests, the daily goal, crates, pulls, equipping, Lid Locks and leagues
- **the camera drop-in**
- **the upgrade** of an old `main` database (with `seeds`)
- **the demo seed**

If `from app.main import app` fails, it's a syntax or import error, and nothing else will work until it's fixed:

```bash
.venv\Scripts\python.exe -c "from app.main import app; print(len(app.openapi()['paths']), 'routes')"
```

After editing `food_catalog.dart` or `collectibles.dart` in the app, run `python -m scripts.sync_catalogs`. Otherwise the parity test fails.

## 2. API + Tiger Data

```bash
# one terminal
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# another
.venv\Scripts\python.exe -m scripts.smoke_test --token <device token>
```

It runs about 20 checks:
- ingest, live and trends
- the advice verdict and the always-avoid rule
- the XP rules and check-in
- game, quests, daily goal, collection, economy rules and leagues
- four auth rejections

It never spends: it doesn't open crates or pull. Expect
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
| 2 | `python scripts/serial_bridge.py --port COM3` | Arduino → API |
| 3 | `python -m scripts.watch_db` | shows what landed (optional) |

```bash
pip install pyserial requests
.venv\Scripts\python.exe scripts/serial_bridge.py --port COM3 --api http://127.0.0.1:8000
```

### Wi-Fi and hotspots do not matter for this path

The sketch talks over USB, so only the laptop needs internet (to reach Tiger
Cloud) and any network will do. A hotspot only matters later, when the
Flutter app on a phone needs to reach the laptop's LAN IP.

### Proving it reached the backend, not just the terminal

The bridge printing `sent raw=...` only proves the bridge read the board. For
the backend's own view, use any of these:

**The server terminal** logs each stored sample with its values, which is
more useful than uvicorn's `POST /ingest 200 OK`:

```
INFO:calmpost.ingest:stored #42  bin-001  raw=473->47.4%  probe=21.4C (+0.0 vs air)  co2=390ppm  rh=48%
```

The `#42` counts samples stored since the server started, so a climbing
number is the pipeline working. `[uncalibrated]` and `!status=N` appear when
they apply.

**One call that answers it outright:**

```bash
curl.exe -s -H "X-API-Key: $APP_API_KEY" http://127.0.0.1:8000/bins/bin-001/stats
```

```json
{"readings_total": 2329, "readings_last_minute": 24, "seconds_since_last": 1,
 "flowing": true, "missing_co2": 7, "co2_error_rows": 0, "calibrated": false}
```

`flowing` is simply "a reading arrived in the last two minutes".

**Tiger Cloud's console** is the slowest place to look. Its Metrics
dashboard aggregates on a delay of several minutes, so a healthy feed can
look like a flat line. To see rows now, use the console's **SQL editor**:

```sql
SELECT time, probe_temp_c, moisture_raw, moisture_pct, co2_ppm, air_humidity_pct
FROM readings WHERE bin_id = 'bin-001'
ORDER BY time DESC LIMIT 20;
```

Don't judge whether ingest works from the Metrics graph -- use `/stats`,
`watch_db`, or that query.

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

Note: the sketch's `setup()` waits ~20 s for the CO2 sensor to settle, but
this board has native USB, so **opening the port does not reset it**. That
wait happens on power-up and after an upload -- not on every reconnect, so a
bridge restart gives you data within a second or two. If you do get a long
silence, the board was just plugged in or reflashed.

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
| Just powered on or reflashed? | `setup()` waits ~20 s for the CO₂ sensor then. Not on a plain reconnect -- native USB means opening the port does not reset the board. |
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

`sql/0*.sql` runs in order on every boot. If a file errors, the app won't come up, so read the SQL in the traceback. Every file is idempotent, so a partial apply is safe to re-run. Older databases, including the original single `schema.sql` with `seeds`, are upgraded in place by `000_premigrate.sql` and `090_migrations.sql`. To rebuild from scratch (**destroys data**):

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
