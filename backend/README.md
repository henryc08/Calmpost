# Calmpost backend

FastAPI + Tiger Data + Gemini. A thin API by design: it keeps the database
and Gemini keys off the phone.

```
Arduino ──USB serial──▶ serial_bridge.py ──POST /ingest──▶ FastAPI ──▶ Tiger Cloud
                                                              │ ▲
                                                       Gemini ◀┘ │ REST
                                                                 │
                                                  Flutter app (Riverpod)
```

The sketch lives at `firmware/sensor_output/sensor_output.ino` and talks over
USB, so the laptop running the bridge is the only machine needing internet.

**The Flutter app never connects to Tiger Data directly.** It calls these
endpoints; `ApiRepository` mirrors `CalmpostRepository` method for method, so
swapping `MockRepository` out is mechanical. Never put the database URL or
the Gemini key in the app.

## Setup

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # Windows;  source .venv/bin/activate elsewhere
pip install -r requirements.txt

cp .env.example .env          # then fill in DATABASE_URL and GEMINI_API_KEY
python -m scripts.init_db --bin bin-001
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` matters: the phone running the app needs to reach the
laptop, not just localhost. (The board does not -- it is on USB.) Interactive docs at <http://127.0.0.1:8000/docs>.

`init_db` prints a `device_token` **once**. Put it in `backend/.env` as
`DEVICE_TOKEN=...`, which is where the serial bridge reads it from.

Demo data:

```bash
python -m scripts.seed_demo --bin bin-001 --days 3
python -m scripts.seed_demo --bin bin-001 --scenario too_wet   # hold one state
python -m scripts.smoke_test --token <device token>
```

Scenarios match `MockRepository`: `healthy`, `too_wet`, `too_dry`, `curing`,
`ready`.

## Calibrate the probe before you trust a number

The firmware sends `moisture_raw`, a raw ADC count, and the backend converts
it using each bin's own curve. Until you calibrate, that conversion uses
defaults that are almost certainly wrong for your probe. The sketch sets
`analogReadResolution(10)`, so raw counts run **0-1023** (around 470 in open
air on our board).

Moisture is **45% of the health score**, so this is the single most valuable
five minutes you can spend on the hardware:

1. Hold the probe in **air**, note `moisture_raw` from the ingest response.
2. Stand it in **water** to the normal depth, note `moisture_raw` again.
3. Send both (capacitive probes read *lower* when wetter, so dry is higher):

```bash
curl -X POST http://127.0.0.1:8000/bins/bin-001/calibration \
  -H "X-API-Key: $APP_API_KEY" -H "Content-Type: application/json" \
  -d '{"moisture_raw_dry": 472, "moisture_raw_wet": 230}'
```

`backfill` (default true) replays the new curve over stored history so the
charts don't kink at the moment you calibrated. Until it's done,
`live()` returns `moisture_calibrated: false` and a note the UI should show.

## Auth

| Caller      | Header           | Value                     |
| ----------- | ---------------- | ------------------------- |
| Bridge      | `X-Device-Token` | the token from `init_db`  |
| Flutter app | `X-API-Key`      | `APP_API_KEY` from `.env` |

Only the token's SHA-256 is stored, so a leaked database can't be replayed
against `/ingest`, and re-registering a bin revokes the old token. A shared
app key is deliberately simple for a hackathon; swapping it for per-user auth
touches only `app/security.py`.

## Endpoints

| Method | Path                            | Purpose |
| ------ | ------------------------------- | ------- |
| GET    | `/health`                       | liveness + DB round trip |
| POST   | `/ingest`                       | **board**: one wide sample |
| POST   | `/bins`                         | register a bin, returns a device token |
| GET    | `/bins`                         | list bins |
| POST   | `/bins/{id}/calibration`        | set the probe's dry/wet raw counts |
| GET    | `/bins/{id}/stats`              | is data arriving? counts + `flowing` |
| GET    | `/bins/{id}/live`               | both layers + air gap + health components |
| GET    | `/bins/{id}/trends`             | gap-filled chart series |
| POST   | `/bins/{id}/advice/check`       | **verdict for one item — the demo moment** |
| GET    | `/bins/{id}/advice`             | whole-bin advice for Home |
| POST   | `/bins/{id}/logs`               | log an add, or a skip |
| GET    | `/bins/{id}/logs`               | recent add log |
| POST   | `/bins/{id}/harvest`            | harvest a layer (+100 XP) |
| GET    | `/users/{id}/game`              | level, XP, loam, streak, impact, badges |
| POST   | `/users/{id}/check-in`          | ticks the streak when the bin screen opens |
| GET    | `/quests/today`                 | today's three care quests + progress |
| GET    | `/leagues/current`              | this week's cohort, ranked |

### Ingest

Exactly what the firmware prints, one object per sample. Every sensor field
is optional, so one dead sensor doesn't drop the whole sample. The board has
no reliable clock, so the server stamps arrival time.

```json
POST /ingest
X-Device-Token: <token>

{"device_id":"bin-001","probe_temp_c":25.3,"moisture_raw":412,
 "co2_ppm":850,"air_temp_c":24.1,"air_humidity_pct":58.2,"co2_status":0}
```

Re-posting the same timestamp fills gaps instead of duplicating, so a bridge
retry is harmless. `co2_status != 0` marks CO₂ unreliable rather than
charting a bad number.

### The demo moment

```json
POST /bins/bin-001/advice/check   {"item": "banana peel"}

{
  "verdict": "careful",
  "headline": "Add browns first",
  "reason": "Your top layer is 67% wet, which is soggy. Mix in shredded cardboard.",
  "pair_with": ["shredded cardboard", "newspaper"],
  "suggest_add": ["shredded cardboard", "shredded paper"],
  "suggest_avoid": ["meat", "dairy", "oily or greasy food"],
  "balance": "needs_browns",
  "stage_top": "active", "stage_bottom": "started", "bottom_ready": false,
  "tip": "Tear the cardboard small so it mixes in.",
  "input_snapshot": { "...the sensor state this answer was based on..." }
}
```

`input_snapshot` is the point: it's stored with every answer, so when the
same scrap gets a different verdict you can **show** that the bin changed
rather than asserting it. Add `?refresh=true` to bypass the cache on stage.

Answers are cached for 15 min against a *coarse* hash of bin state
(`ADVICE_TTL_SECONDS`), so sensor jitter reuses an answer but a real change
produces a new one.

## Hardware: one probe, not two

The current firmware has **one** probe (`probe_temp_c` + `moisture_raw`) and
one air sensor. So:

- `live()` returns both layers, but the bottom has `measured: false`. The UI
  must render it as unknown, **not** as 0.
- `stage_bottom` is `"started"` until a second probe exists, and
  `bottom_ready` stays false. `/harvest` still works and reports
  `was_ready: false` with a note, so the celebration stays honest.
- `notes[]` carries the plain-language caveats to surface in the UI.

Adding a second probe needs no migration: post with `probe_layer: "bottom"`.

## Without a Gemini key

`app/gemini.py` falls back to the rules in `app/compost.py` and reports
`"model": "rules-fallback"`. Advice still works offline — useful if the venue
Wi-Fi dies mid-demo. Meat, dairy and oil are **always** avoid via rules, and
the model's own suggestions are filtered against that list, so no model
answer can override it (`"model": "rules-always-avoid"`).

## Data model

Five hypertables, per CLAUDE.md:

| Table | What |
| ----- | ---- |
| `readings` | one **wide** row per POST, raw + derived moisture |
| `add_log` | adds and skips, categorised green/brown/avoid |
| `advice` | every answer **plus the input snapshot** |
| `point_events` | XP/loam ledger, append-only |
| `stage_history` | Batch Journey transitions |

Plus `bins`, `user_state`, `leagues`, `league_members`.

**Continuous aggregates:** `readings_15m` and `readings_1d` back the charts;
`xp_weekly` powers Leagues (bucketed on a Sunday origin to match the reset).

**Hyperfunctions:** `regr_slope` for the CO₂ trend that drives stage,
`time_weight` for time-weighted moisture, `state_agg`/`duration_in` for hours
actually spent in the healthy band, `time_bucket_gapfill`+`locf` for charts
without holes.

**Policies:** columnstore after 7 days, 90-day retention on raw readings
(aggregates keep the long history).

`sql/schema.sql` is idempotent and runs on boot, so nobody runs migrations by
hand. `scripts/reset_db.py --yes` drops the old pre-spec schema — destructive,
and only needed once.

## XP rules

From CLAUDE.md, enforced in `app/compost.py`:

| Action | XP |
| ------ | -- |
| Followed a suggestion | 15 |
| Healthy layer-day (per layer, once/day) | 10 |
| Trusted an avoid verdict and skipped it | 5 |
| Daily quest | 15 |
| Weekly balance | 30 |
| Harvest | 100 |
| **Logging a scrap** | **0** |

A plain log is worth **zero**, deliberately. Paying per scrap logged would
reward wasting more food — the one mechanic the doc rules out. Streaks count
*care* actions, not logs, for the same reason.

The Bin Health Score itself lives in the Flutter app
(`domain/health_score.dart`). `live()` returns the four **components** and
their weights rather than a second implementation of the number that could
drift from the app's.

## The USB bridge

The board prints JSON over USB serial and does not use Wi-Fi, so the bridge
is the ingest path. **Three processes must run together** -- the API, the
bridge, and (optionally) the watcher. See TESTING.md; running only the
watcher is the usual reason nothing appears to happen.

```bash
pip install pyserial requests
python examples/serial_bridge.py --api http://127.0.0.1:8000
```

It auto-detects the port, reads at 115200 (matching the sketch), ignores the
board's `#`-prefixed log lines, queues samples through network drops, and
exits on an auth failure rather than spamming a revoked token.
