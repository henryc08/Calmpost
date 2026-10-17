# Calmpost backend

Sensor ingest + TigerData (TimescaleDB) time-series storage + Gemini advice,
behind a small HTTP/JSON API that both the ESP32 and the Flutter app talk to.

```
ESP32  --POST /v1/ingest-->  FastAPI  --SQL-->  TigerData
                                |
Flutter  --GET /v1/...--------->+---> Gemini (recommendations)
```

## Setup

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # Windows;  source .venv/bin/activate on mac/linux
pip install -r requirements.txt

cp .env.example .env          # then fill in DATABASE_URL and GEMINI_API_KEY
```

`DATABASE_URL` is the **Service URL** from the TigerData / Timescale Cloud
console (Connect -> Service URL). `.env` is gitignored -- never commit it.

Create the tables and mint a token for the bin:

```bash
python -m scripts.init_db --device bin-01
```

That prints a `device_token` **once**. Paste it into
`firmware/calmpost_esp32.ino` as `DEVICE_TOKEN`; only its hash is stored.

Run the server (`--host 0.0.0.0` so the ESP32 and phone can reach it):

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Interactive docs: <http://127.0.0.1:8000/docs>

Optional, for a demo with non-empty charts:

```bash
python -m scripts.seed_demo --device bin-01 --days 3
python -m scripts.smoke_test --token <device token>
```

## Auth

| Caller       | Header           | Value                                  |
| ------------ | ---------------- | -------------------------------------- |
| ESP32        | `X-Device-Token` | the token from `init_db`               |
| Flutter app  | `X-API-Key`      | `APP_API_KEY` from `.env`              |

A shared app key is deliberately simple for a hackathon build; swapping it for
per-user auth later only touches `app/security.py`.

## Endpoints

| Method | Path                                | Purpose |
| ------ | ----------------------------------- | ------- |
| GET    | `/health`                           | liveness + DB round trip |
| POST   | `/v1/devices`                       | register a bin, returns a device token |
| GET    | `/v1/devices`                       | list bins |
| POST   | `/v1/ingest`                        | **ESP32**: one sample, all zones |
| GET    | `/v1/devices/{id}/latest`           | current reading per zone + moisture state |
| GET    | `/v1/devices/{id}/history?zone=top&hours=24` | hourly buckets for charts |
| POST   | `/v1/log`                           | log an added item, returns points awarded |
| GET    | `/v1/devices/{id}/log`              | recent add log |
| GET    | `/v1/devices/{id}/advice`           | Gemini recommendations (`?refresh=true` to bypass cache) |
| GET    | `/v1/users/{id}/points`             | total points, streak, weekly logs |

### Ingest payload

Send only the fields a zone actually has. The server stamps the time, so the
board needs no clock.

```json
POST /v1/ingest
X-Device-Token: <token>

{
  "device_id": "bin-01",
  "zones": [
    {"zone": "top",    "moisture_pct": 64.2, "temperature_c": 38.1},
    {"zone": "bottom", "moisture_pct": 49.0, "temperature_c": 22.4},
    {"zone": "airgap", "co2_ppm": 1850}
  ]
}
```

Re-posting the same timestamp updates that row instead of duplicating it, so a
firmware retry is harmless.

### Advice response

```json
{
  "headline": "Top layer is wet -- add some dry browns.",
  "balance": "needs_browns",
  "stage_top": "active",
  "stage_bottom": "curing",
  "bottom_ready": false,
  "suggestions": [
    {"item": "shredded cardboard", "action": "add", "reason": "soaks up extra moisture"},
    {"item": "meat, dairy and oily food", "action": "avoid", "reason": "goes rancid in a sealed bin"}
  ],
  "warnings": ["Readiness is a guide from sensor trends, not a lab test."],
  "cached": false,
  "model": "gemini-2.5-flash"
}
```

Answers are cached per coarse bin state for 15 minutes (`ADVICE_TTL_SECONDS`),
so repeated app opens do not burn Gemini quota — but a real change in the
readings produces a new answer, which is the demo moment.

## Data model

Three TigerData tables do the work:

- **`readings`** — hypertable, one row per zone per sample. Compresses after
  7 days; `readings_hourly` is a continuous aggregate that backs the charts.
- **`add_log`** — what the user added, categorised green/brown/avoid.
- **`advice`** — cached Gemini answers, keyed by a coarse hash of bin state.

Plus `devices`, `zones` and `points_ledger` (append-only, so streaks and
totals are recomputed rather than stored).

Full definitions in [`sql/schema.sql`](sql/schema.sql). It is idempotent and
runs automatically on server boot, so teammates never run a migration by hand.

## Without a Gemini key

`app/gemini.py` falls back to the rules in `app/compost.py` and reports
`"model": "rules-fallback"`. Advice still works offline — useful if the venue
Wi-Fi gives out mid-demo.
