# Calmpost

Hack the Valley 2026 — a sensor-equipped compost bin and a gamified app that
tells you what to add, what to avoid, and when your compost is ready.

See [AGENTS.md](AGENTS.md) for the design, tech stack and game rules.

```
Arduino ──USB serial──▶ backend/scripts/serial_bridge.py ──POST /ingest──▶ FastAPI ──▶ Tiger Cloud
                                                                             │ ▲
webcam ──▶ vision/ ──POST /bins/{id}/drops───────────────────────────────────┤ │
                                                                  Gemini ◀───┘ │ REST
                                                                               │
                                                                 Flutter app (Riverpod)
```

Everything lives on `main`.

| Part | Where | Docs |
| ---- | ----- | ---- |
| Flutter app (Android-first; runs on mock data) | `app/` | [AGENTS.md §7](AGENTS.md) |
| Backend: FastAPI + Tiger Data + Gemini, game and economy | `backend/` | [backend/README.md](backend/README.md), [backend/TESTING.md](backend/TESTING.md) |
| Camera drop-in: OpenCV + Gemini vision | `vision/` | [vision/README.md](vision/README.md) |
| Arduino sketch: one probe + air sensor, JSON over USB | `firmware/sensor_output/` | |

Quick checks, no Tiger or hardware needed:

```powershell
cd app;     flutter test
cd backend; .venv\Scripts\python.exe -m pytest     # local Postgres via pgserver
cd vision;  .venv\Scripts\python.exe -m pytest
```

---

## Running the backend with the real board

**Three processes, three terminals.** All of them. The watcher only *reads*
the database — with no bridge running you are watching a database that
nothing is feeding, which looks exactly like broken hardware.

```powershell
cd backend
```

**Terminal 1 — the API** (writes to Tiger Data)

```powershell
.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

**Terminal 2 — the bridge** (Arduino → API)

```powershell
.venv\Scripts\python.exe scripts\serial_bridge.py --port COM3
```

**Terminal 3 — the watcher** (optional: what landed in Tiger Data)

```powershell
.venv\Scripts\python.exe -m scripts.watch_db
```

### What "working" looks like

Terminal 1 logs the values, not just a status code:

```
INFO:calmpost.ingest:stored #42  bin-001  raw=473->47.4%  probe=21.4C (+0.0 vs air)  co2=390ppm  rh=48%
```

Terminal 2, one line per second:

```
INFO sent raw=473 -> moisture=47.4%  (probe NOT calibrated)
```

Or ask the backend directly:

```powershell
curl.exe -s -H "X-API-Key: <APP_API_KEY from backend\.env>" http://127.0.0.1:8000/bins/bin-001/stats
```

```json
{"readings_total": 2007, "readings_last_minute": 61, "seconds_since_last": 0, "flowing": true}
```

`flowing: true` is the single answer to "is it actually reaching the backend".

### First-run setup

```powershell
cd backend
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
copy .env.example .env      # then fill in DATABASE_URL and GEMINI_API_KEY (never commit .env)
.venv\Scripts\python.exe -m scripts.init_db --bin bin-001
```

`init_db` prints a device token once — put it in `backend\.env` as
`DEVICE_TOKEN=...`.

### Two errors you will hit

| Error | Cause |
| ----- | ----- |
| `[Errno 10048] only one usage of each socket address` | port 8000 is already taken — another `uvicorn` is running |
| `could not open port 'COM3': Access is denied` | COM3 is already taken — another bridge, or the Arduino IDE's **Serial Monitor** |

Windows allows one reader per serial port. Close the other thing.

The sketch's `setup()` waits ~20 s for the CO₂ sensor, but this board has
native USB, so opening the port does not reset it: that wait only happens on
power-up or after an upload, not on every reconnect.

More in [backend/TESTING.md](backend/TESTING.md) — testing levels,
calibration, and debugging by symptom. API reference in
[backend/README.md](backend/README.md).

### Calibrate before the demo

Moisture is 45% of the health score and the default curve is a guess. Hold
the probe in air, note `moisture_raw`; stand it in water, note it again; then
post both. Steps in [backend/TESTING.md](backend/TESTING.md).

## Multiplayer

The `multiplayer` branch adds accounts, friend invitations, follows, shared progress,
and private leaderboards. See [MULTIPLAYER.md](MULTIPLAYER.md) for setup and a two-person walkthrough.
