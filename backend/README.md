# Calmpost backend

This is FastAPI plus Tiger Data (Postgres with TimescaleDB) plus Gemini. The API is kept thin on purpose: its job is to hold the database URL and Gemini key so they never sit on the phone.

```
Arduino ──USB serial──▶ scripts/serial_bridge.py ──POST /ingest──▶ FastAPI ──▶ Tiger Cloud
                                                                     │ ▲
camera ──▶ vision/ ──POST /bins/{id}/drops───────────────────────────┤ │
                                                          Gemini ◀───┘ │ REST
                                                                       │
                                                         Flutter app (Riverpod)
```

**The Flutter app never connects to Tiger Data directly.** It calls these endpoints instead. `ApiRepository` mirrors `CalmpostRepository` method for method, so moving off `MockRepository` is a mechanical swap. `examples/calmpost_api.dart` is a ready-made client for it.

## Layout

```
backend/
  app/
    main.py            app + router wiring; applies the schema on boot
    config.py          settings from .env
    db.py              asyncpg pool, ordered schema loader (dollar-quote aware)
    security.py        X-API-Key (app) and X-Device-Token (board) checks
    models.py          request/response shapes (mirror the app's domain models)
    rules/             PURE functions, no I/O, unit-tested
      compost.py         bands, health components, balance, stage, categorise, always-avoid
      game.py            XP, Loam, quests, daily goal, crates, streaks, Lid Locks, achievements, leagues
      gacha.py           Seed Packet odds, pity, duplicate refunds
    catalog/           GENERATED from the app (food.py, collectibles.py) -- don't edit
    services/          I/O built on the rules
      binstate.py        current bin state from readings (one query per screen)
      advisor.py         Gemini advice with the rules fallback
      ledger.py          the append-only point_events ledger: award, balances, streaks, Lid Locks
      economy.py         quests, daily goal, crates, achievements, Greenhouse pulls, equip, shop, leagues
    routers/           thin HTTP layer: ingest, bins, advice, game, economy, drops
  sql/                 applied in filename order on every boot; every file is idempotent
    000_premigrate.sql   fixes needed before anything else (seeds -> loam rename)
    001_core.sql         bins, readings, add_log, advice, stage_history + chart aggregates
    002_game.sql         point_events ledger, user_state, leagues, xp_weekly
    003_drops.sql        camera drop-in: drop_sessions, drop_events, vision_accuracy_1d
    004_economy.sql      crates, collection, gacha_pulls, gacha_odds_1d
    090_migrations.sql   brings databases built from older schemas up to date
  scripts/             init_db, seed_demo, smoke_test, watch_db, serial_bridge, sync_catalogs, reset_db
  tests/               pytest; real Postgres (see Tests)
  examples/            calmpost_api.dart (Dart client for the app)
```

**The app owns the rules.** The Dart files in `app/lib/domain`, `app/lib/state` and `app/lib/data` are the source of truth. `app/rules/` re-implements them so the server can enforce them, which means the client can't hand itself XP or Loam. `tests/test_parity.py` reads the Dart files and fails if any number drifts. The catalogs are generated, not copied: after you edit `food_catalog.dart` or `collectibles.dart`, run `python -m scripts.sync_catalogs`. That rewrites `app/catalog/*.py` and `vision/catalog.json`.

## Setup

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # Windows;  source .venv/bin/activate elsewhere
pip install -r requirements.txt

cp .env.example .env          # then fill in DATABASE_URL and GEMINI_API_KEY yourself
python -m scripts.init_db --bin bin-001
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- **Bind to 0.0.0.0.** `--host 0.0.0.0` matters: the phone running the app has to reach the laptop, not just localhost. The interactive docs are at <http://127.0.0.1:8000/docs>.
- **Save the device token.** `init_db` prints a `device_token` **once**. Put it in `backend/.env` as `DEVICE_TOKEN=...`, which is where the serial bridge reads it.
- **Keep `.env` out of git.** It is git-ignored; never commit it.

Next, add demo data and check the whole pipeline:

```bash
python -m scripts.seed_demo --bin bin-001 --days 3              # readings, adds, a 12-day streak, economy, league
python -m scripts.seed_demo --bin bin-001 --scenario too_wet    # hold one state (healthy/too_wet/too_dry/curing/ready)
python -m scripts.smoke_test --token <device token>             # end-to-end against the running server
python -m scripts.watch_db                                      # tail what lands in Tiger Data
```

`seed_demo` is safe to re-run. It leaves the player the way the app's mock shows them:
- 240 Loam and 1 Seed Packet
- a Sprout and a Grove crate waiting
- 1 Lid Lock
- 10 collectibles
- a 12-day streak with today still to do

The schema is applied on every boot, so nobody runs migrations by hand. An existing database built from the old single `schema.sql` (with `seeds` instead of `loam`) upgrades in place, and `tests/test_migration.py` proves it. `scripts/reset_db.py --yes` is only for the pre-spec two-layer tables. It is destructive.

## Calibrate the probe before you trust a number

The firmware sends `moisture_raw`, a raw ADC count. The backend converts it using each bin's own curve. Until you calibrate, the conversion uses defaults that are almost certainly wrong for your probe. The sketch sets `analogReadResolution(10)`, so raw counts run **0–1023** (around 470 in open air on our board). Moisture is **45% of the health score**, so these five minutes matter most:

1. Hold the probe in **air** and note `moisture_raw`.
2. Stand it in **water** at its normal depth and note `moisture_raw` again.
3. Post both values. Capacitive probes read *lower* when wetter, so the dry value is the higher one.

```bash
curl -X POST http://127.0.0.1:8000/bins/bin-001/calibration \
  -H "X-API-Key: $APP_API_KEY" -H "Content-Type: application/json" \
  -d '{"moisture_raw_dry": 472, "moisture_raw_wet": 230}'
```

`backfill` (default true) replays the new curve over stored history, so the charts don't kink at the moment you calibrated. Until you calibrate, `live()` returns `moisture_calibrated: false` and a note for the UI.

## Auth

| Caller                       | Header           | Value                     |
| ---------------------------- | ---------------- | ------------------------- |
| Bridge / board               | `X-Device-Token` | the token from `init_db`  |
| Flutter app, `vision/`       | `X-API-Key`      | `APP_API_KEY` from `.env` |

- **Hashed tokens:** only the device token's SHA-256 is stored, and re-registering a bin revokes the old token.
- **Bound to one bin:** a token only posts for its own bin, and a mismatch returns 403.
- **Easy to upgrade:** the shared app key is deliberately simple for a hackathon. Per-user auth would only change `app/security.py`.

## Endpoints

| Method | Path | Purpose |
| ------ | ---- | ------- |
| GET  | `/health` | liveness + DB round trip |
| POST | `/ingest` | **board**: one wide sample |
| POST | `/bins` · GET `/bins` | register a bin (returns a device token) · list bins |
| POST | `/bins/{id}/calibration` | the probe's dry/wet raw counts |
| GET  | `/bins/{id}/stats` | is data arriving? counts + `flowing` |
| GET  | `/bins/{id}/live` | layers + air gap + health components + notes |
| GET  | `/bins/{id}/trends` | gap-filled chart series |
| POST | `/bins/{id}/advice/check` | **verdict for one item — the demo moment** |
| GET  | `/bins/{id}/advice` | whole-bin "what to add" for Home |
| POST · GET | `/bins/{id}/logs` | log an add or a skip · recent log |
| POST | `/bins/{id}/harvest` | harvest a layer (+100 XP, +50 Loam) |
| GET  | `/users/{id}/game` | the app's GameState (see below); settles rewards due |
| POST | `/users/{id}/check-in` | the care action for opening the bin screen (+5, once a day) |
| GET  | `/quests/today?user_id=` | today's three care quests, progress, claimed |
| POST | `/quests/{key}/claim?user_id=` | claim a finished quest |
| GET  | `/users/{id}/daily-goal` · POST `/users/{id}/daily-goal/{i}/claim` | 20/40/60 XP ladder |
| GET  | `/users/{id}/rewards` · POST `/users/{id}/crates/{crate}/open` | crate inbox · open one |
| GET  | `/users/{id}/collection` | Greenhouse: owned collectibles, copies, pity |
| POST | `/users/{id}/gacha/pull` | `{"count": 1 \| 10, "paid_with": "packet" \| "loam"}` |
| POST | `/users/{id}/equip` | `{"collectible_id": ...}`: a finish or a title |
| POST | `/users/{id}/lid-locks/buy` | 60 Loam, hold 2 at most |
| GET  | `/economy/rules` | prices, odds, pity, reward tables (for display) |
| GET  | `/leagues/current?user_id=` | this week's cohort, ranked, with zones |
| …    | `/bins/{id}/drops/…`, `/drops/{id}/…` | camera drop-in (see below) |

Spending and claiming return **409** when the action isn't allowed: not enough Loam, a quest that isn't done, something already claimed, or an item you don't own.

### Ingest

The body is exactly what the firmware prints, one object per sample. Every sensor field is optional, so one dead sensor doesn't drop the whole sample. The board has no reliable clock, so the server stamps the arrival time.

```json
POST /ingest
X-Device-Token: <token>

{"device_id":"bin-001","probe_temp_c":25.3,"moisture_raw":412,
 "co2_ppm":850,"air_temp_c":24.1,"air_humidity_pct":58.2,"co2_status":0}
```

- **Retries are safe.** Re-posting the same timestamp fills gaps instead of duplicating, so a bridge retry is harmless.
- **Bad CO₂ is flagged.** `co2_status != 0` marks the CO₂ reading as unreliable instead of charting a bad number.

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

The verdict is `great`, `careful` or `avoid`, matching the app's Log sheet.
- **The snapshot is the point.** `input_snapshot` is stored with every answer. When the same scrap gets a different verdict, you can **show** that the bin changed instead of just claiming it. `tests/test_api.py::test_same_scrap_different_answer` checks this.
- **Caching.** Answers are cached for 15 minutes against a *coarse* hash of the bin's state (`ADVICE_TTL_SECONDS`). Sensor jitter reuses an answer, but a real change produces a new one.
- **On stage.** Add `?refresh=true` to skip the cache during the demo.

**Without a Gemini key** (or if the venue Wi-Fi dies), `services/advisor.py` falls back to the rules and reports `"model": "rules-fallback"`. Meat, dairy, oil and bones are **always** `avoid`. The model's suggestions are filtered against that list, so no model answer can override it (`"model": "rules-always-avoid"`).

### Camera drop-in (`vision/`)

The `vision/` service watches the bin opening and reports what went in. The app shows "Something was added" and the user confirms. Every route needs `X-API-Key`.

```
App     POST /bins/{id}/drops/session               arm the camera for 60 s
vision  GET  /bins/{id}/drops/session/active        poll: 204 = not armed
vision  POST /bins/{id}/drops                       report a detection -> pending
vision  POST /bins/{id}/drops/session/{sid}/close   saw nothing ("Didn't see anything")
App     GET  /bins/{id}/drops/stream                SSE, one `drop` event per pending detection
App     GET  /bins/{id}/drops/pending               polling fallback
App     POST /drops/{id}/confirm                    -> add_log rows (source='camera') + verdict + XP
App     POST /drops/{id}/dismiss                    "Nothing was added"
App     GET  /bins/{id}/drops/sessions/{sid}        is the sheet still watching?
        GET  /bins/{id}/drops/hints                 recent corrections, fed back to Gemini
        GET  /bins/{id}/drops/accuracy              camera accuracy stat
```

- **Confirming logs normally.** Each confirmed item follows the usual `/logs` rules:
  - adding an item earns 0
  - `was_advised` earns +15
  - `removed` earns +5 (the user took a keep-out item back out)
- **Amounts become grams:** small 40, handful 110, large 250.
- **No double logging.** Confirming twice returns 409, so a double tap can't log a drop twice.
- **Rules beat the camera.** A label that the always-avoid rule flags is `avoid`, whatever the camera or the user's edit said.
- **Photos expire.** Thumbnails are capped at 200 KB, and `drop_events` keeps them for 30 days because the photos are personal.

Run `vision/` against this backend by setting `BACKEND_URL=http://localhost:8000` in `vision/.env`. Its `mock_backend.py` on :8090 only stands in when this backend isn't running.

## Hardware: one probe, not two

The current firmware has **one** probe (`probe_temp_c` + `moisture_raw`) in the top layer and one air sensor (CO₂, temperature, humidity). So:

- **Bottom layer:** `live()` returns both layers, but the bottom has `measured: false` and `moisture_pct: null`. The UI must render it as unknown, **not** as 0.
- **Bottom stage:** `stage_bottom` stays `"started"` and `bottom_ready` stays false until a second probe exists.
- **Harvest stays honest:** `/harvest` still works and reports `was_ready: false` with a note.
- **Notes:** `notes[]` carries the plain-language caveats for the UI to show.

Adding a second probe needs no migration: post with `probe_layer: "bottom"`.

## The game, server-side

Everything is enforced here, so the numbers the app shows can't be faked by the client. All of these rules come from the app (`xp_rules.dart`, `state/game.dart`, `gacha.dart`), and the parity tests keep the two in step.

**XP: reward balance, never volume.**

| Action | XP |
| ------ | -- |
| **Logging a scrap** | **0** |
| Followed the suggestion | 15 |
| Trusted an avoid verdict and skipped it | 5 |
| Check-in (once a day) | 5 |
| Healthy layer-day (per measured layer, once a day) | 10 |
| Weekly balance | 30 |
| Harvest | 100 (+50 Loam) |

- **Daily cap:** follow, skip and check-in XP together cap at **60 a day**.
- **Uncapped:** quest and daily-goal rewards aren't capped.
- **Streaks count care, not logs:** a check-in, a followed suggestion or a quest keeps a streak alive.

**Loam** is the soft currency. It is never bought with money.

- **Quests** pay only when claimed:

  | Quest | XP | Loam |
  | ----- | -- | ---- |
  | Check on your layers | 10 | 10 |
  | Follow the next best action | 20 | 25 |
  | In range for 6 hours | 15 | 15 |

- **Daily goal:** reaching 20 / 40 / 60 XP pays 15 Loam / 30 Loam / a Sprout crate.
- **Streak milestones:**

  | Days | Pays |
  | ---- | ---- |
  | 3 | 25 Loam |
  | 7 | 50 Loam + Sprout crate |
  | 14 | 100 Loam |
  | 30 | 200 Loam + Grove crate |
  | 100 | 500 Loam + Canopy crate |

- **League finish:** promoted 150, safe 60, demoted 20.
- **Achievements:** 10 of them, each with 3 tiers, and every tier pays a crate.
- **Crates:**

  | Crate | Loam | Seed Packets |
  | ----- | ---- | ------------ |
  | Sprout | 60 | 1 |
  | Grove | 160 | 3 |
  | Canopy | 400 | 5 |

- **Lid Locks** cost 60 Loam and you can hold 2. When a care action follows missed days, enough locks are spent automatically to cover the gap. This writes `lid_lock_used` rows, and those days show on the calendar as kept. Without enough locks, the streak resets.

Once-only rewards carry a `dedupe_key`, so settling twice never pays twice. Spends lock the player's row (`SELECT … FOR UPDATE`), so two taps can't overspend.

**Greenhouse (Seed Packets).**
- **Price:** a pull costs 1 Seed Packet or 100 Loam; ten pulls cost 900 Loam.
- **Odds:** common 60%, uncommon 25%, rare 11%, epic 3.5%, legendary 0.5%.
- **Pity:** an epic or better within 30 pulls, a legendary within 80.
- **Ten-pull guarantee:** every ten-pull includes a rare or better.
- **Duplicates** refund 5 / 10 / 25 / 60 / 150 Loam, by rarity.
- **Equipping:** finishes recolour the Home health ring and titles show on Profile; both can be equipped.

The server rolls every pull, and the app only plays the animation.

**The health score** itself lives in the app (`domain/health_score.dart`). `live()` returns its four **components** and their weights, rather than a second copy of the formula that could drift.

## Data model (Tiger Data)

| Hypertable | What |
| ---------- | ---- |
| `readings` | one **wide** row per POST: raw + derived moisture |
| `add_log` | adds and skips, categorised green/brown/avoid, with `catalog_id`, `source` (manual/photo/seed/camera) and `drop_id` |
| `advice` | every answer **plus its input snapshot** |
| `point_events` | the append-only XP and Loam ledger (`loam < 0` is a spend); `kind` says why |
| `stage_history` | Batch Journey transitions |
| `drop_events` | camera detections and what the user confirmed (30-day retention) |
| `gacha_pulls` | every Seed Packet result (rarity, pity counters) |

Plain tables:
- `bins`
- `user_state`: balances that aren't ledger sums (Lid Locks, packets, pity counters, equipped items)
- `leagues` and `league_members`
- `crates`
- `collection`
- `drop_sessions`

**Continuous aggregates:**
- `readings_15m` and `readings_1d` back the charts.
- `xp_weekly` powers Leagues. It is bucketed on a Sunday origin to match the reset.
- `vision_accuracy_1d` backs the camera accuracy stat.
- `gacha_odds_1d` shows observed against published odds.

**Hyperfunctions:**
- `regr_slope` gives the CO₂ trend that drives stage.
- `time_weight` gives time-weighted moisture.
- `state_agg` / `duration_in` give the hours actually spent in the healthy band, which feeds healthy-layer-day XP and the 6-hour quest.
- `time_bucket_gapfill` with `locf` gives charts without holes.

**Policies:** readings move to the columnstore after 7 days and are kept for 90 days (the aggregates keep the long history). Drop photos are kept for 30 days.

## Tests

```bash
pip install pytest pgserver
python -m pytest                      # from backend/
```

- **Database:** the tests run on a **real Postgres**, either `TEST_DATABASE_URL` (which gets **wiped**) or, if that's unset, a throwaway local server from `pgserver`.
- **TimescaleDB stand-ins:** Tiger is TimescaleDB, so the TimescaleDB-only statements (hypertables, continuous aggregates, policies) are skipped locally. `tests/timescale_stubs.sql` provides stand-ins for the functions the queries call, so every query in the backend still executes.
- **No database:** without one, only the pure rule and parity tests run.

| File | Covers |
| ---- | ------ |
| `test_rules.py` | compost/game/gacha rules, pity, streaks, the schema splitter |
| `test_parity.py` | the backend's numbers and catalogs equal the Dart app's |
| `test_api.py` | the full loop: ingest → live → advice → logs → check-in → quests → daily goal → crates → pulls → equip → Lid Locks → leagues |
| `test_drops.py` | the camera drop-in flow |
| `test_migration.py` | an old `main` database (with `seeds`) upgrades in place |
| `test_seed_demo.py` | the demo seed builds the expected player and is re-runnable |

The hypertables, aggregates and policies themselves only run on Tiger Cloud. `scripts/smoke_test.py` against the real database is the final check. More detail in [TESTING.md](TESTING.md).

## The USB bridge

The board prints JSON over USB serial and doesn't use Wi-Fi, so the bridge is the ingest path. **Three processes run together:** the API, the bridge, and (optionally) the watcher. See TESTING.md. Running only the watcher is the usual reason nothing seems to happen.

```bash
pip install pyserial requests
python scripts/serial_bridge.py --api http://127.0.0.1:8000
```

The bridge:
- auto-detects the port and reads at 115200 baud, matching the sketch
- ignores the board's `#`-prefixed log lines
- queues samples through network drops
- exits on an auth failure rather than retrying with a revoked token
