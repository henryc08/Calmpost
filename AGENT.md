# Calmpost

> A sensor-equipped compost bin + a gamified Android app. **The bin tells you what it needs; the app makes looking after it rewarding.**
> Hack the Valley 11 · Climate Action & Sustainability track · Tiger Data sponsor track

This file is the source of truth for how we build Calmpost. Read it before you write code, and update it in the same commit when a decision changes.

**Contents**
1. [Key ideas](#1-key-ideas-dont-break-these)
2. [Major features](#2-major-features): sensing & health · next best action · scrap check · **camera drop-in** · summaries · game & economy · notifications
3. [Gemini: what it does and how](#3-gemini-what-it-does-and-how)
4. [System architecture](#4-system-architecture)
5. [Backend & Tiger Data](#5-backend--tiger-data)
6. [Vision service (camera)](#6-vision-service-camera)
7. [App (Flutter)](#7-app-flutter): structure, screens, design system
8. [Game reference](#8-game-reference): XP, Loam, crates, achievements, gacha
9. [Mock data & demo](#9-mock-data--demo)
10. [Commands, build order, working together](#10-commands)

---

## 1. Key ideas (don't break these)

1. **Reward balance, never volume.** Adding a scrap earns **0 XP** on its own. XP and Loam come only from *care*: following the next best action, keeping layers in their healthy range, balancing greens and browns, finishing quests, harvesting. If a mechanic would reward dumping more food in the bin, it's wrong.
2. **Same scrap, different answer.** Advice is always based on the bin's *current* readings. This is our demo moment, so protect it.
3. **Honest about accuracy.** Moisture is our most reliable signal; temperature and CO₂ add context. Stage and "ready" are guides, not lab results. The camera can be wrong, so **the user always confirms what it saw**.
4. **Sleek, minimal, grown-up.** Calm editorial design, one living illustration per screen, open layout instead of boxes. **No mascot, no cartoons.**
5. **Rules decide, Gemini explains and sees.** Deterministic rules own every judgement. Gemini identifies things and writes words. Every Gemini answer has a rule-based fallback.
6. **Frontend first.** The app runs fully on mock data through `CalmpostRepository`; the backend plugs in later with no UI changes.

---

## 2. Major features

Each feature lists what the user sees, how it works, and its status.

| # | Feature | Status |
|---|---|---|
| 2.1 | Live sensing & Bin Health Score | ✅ app (mock + **live via `ApiRepository`**) · ✅ backend · ⏳ second probe |
| 2.2 | Next best action / **What to add** (Home's main section) | ✅ app (rules) · ⏳ Gemini wording |
| 2.3 | Scrap check ("Can I add this?") | ✅ rules + Log tab verdict sheet · ⏳ Gemini |
| 2.4 | **Camera drop-in: identify and track what goes in** | 📝 planned (this doc), not built |
| 2.5 | Summaries (daily note, recap, batch story) | 📝 planned |
| 2.6 | Game & economy (streaks, quests, Loam, crates, gacha, leagues) | ✅ Home, Social, Profile, **Greenhouse (gacha)**, crate reveal · ⏳ Rewards inbox history |
| 2.7 | Notifications | ✅ compost ready · ⏳ streak at risk, crate earned |

### 2.1 Live sensing & Bin Health Score
- **Sees:** the Bin World on Home (a living cross-section of the bin), the health score on its bezel, three readings (top, bottom, air), and charts on Layers.
- **How:** the board sends probe moisture + temperature and air CO₂/temp/humidity about once a second over USB (the serial bridge posts it). Today there is **one** probe, in the top layer; the bottom layer shows as *not measured*, never 0, until a second probe is added. The score comes from `domain/health_score.dart`:
  ```
  health = 0.45·moisture + 0.20·temperature + 0.15·co2_trend + 0.20·balance
  ```
  `moisture` is per layer: 100 inside 40–60%, falling to 0 at ±25%. `balance` is 7-day greens:browns ≈ 1:2–1:3. State: Thriving ≥ 85 · Healthy ≥ 70 · Fair ≥ 50 · Needs care. Top layer > 66% → **Too wet**, < 33% → **Too dry**.

### 2.2 Next best action → "What to add"
- **Sees:** **What to add**, the main section on Home right under the band: a headline ("Add something dry"), one sentence why, three recommended items shown as tappable circles with what each will do ("Soaks up water", "Adds nitrogen"), what to hold off on, and +15 XP for following it. Tapping an item opens its verdict in Log.
- **How:** rules compute `need` ∈ `browns | greens | water | mix | nothing` from moisture, balance, CO₂ and temperature (table in §3). Gemini only words it. **`nothing` is a good answer**; never suggest food just to have a suggestion.

### 2.3 Scrap check ("Can I add this?")
- **Sees:** on the Log tab, search for an item (or tap a suggestion), then get a verdict: **great**, **careful** (add with browns or greens, with the pair-with items listed) or **avoid**, plus the reason.
- **How:** `domain/advice_rules.dart` decides from the live snapshot. Meat, dairy, oil, pet waste and glossy paper are **always avoid**. Gemini rewrites the reason in plain words and handles items not in the catalog.
- **Demo moment:** banana peel → great when the bin is dry; careful when it's soggy.

### 2.4 Camera drop-in: identify and track what goes in ✅ *backend + vision built; app sheet on mocks*

When you drop something into the bin, a camera sees it, Gemini identifies it, and the app asks you to confirm before it's tracked.

**What the user does**
1. On Home, tap **Drop something in** (forest pill under the score). This arms the camera for 60 s and opens a "Watching the bin…" sheet with a live preview and a countdown.
2. Drop the scrap in.
3. A pop-up slides up: **"Something was added"**. The photo appears with a box around the item, then the details fill in one by one:
   - **Item:** "Banana peel"
   - **Type:** Green / Brown / Keep out
   - **Amount:** Small / Handful / Large (≈ grams behind the scenes)
   - **Confidence:** e.g. 82%
4. If anything is wrong (say, it called the banana a "mango skin"), the user edits it right there. The item field is a search over the catalog with free-text fallback; type and amount are segmented choices. Low-confidence fields (< 60%) are pre-highlighted with "Check this".
5. **Submit.** The drop becomes a tracked add: the scrap-check verdict appears (great / careful / avoid) and XP is awarded by the normal rules (0 for adding; +15 if it was the next best action). If it's a **Keep out** item, the app says to take it back out, and confirming that earns the usual +5.
6. **"Nothing was added"** dismisses a false trigger.

**What "tracked" means**
- The confirmed drop is an `add_log` row with `source = 'camera'`, its photo thumbnail and the model's first guess.
- It counts toward the 7-day greens:browns balance, kg kept from landfill, and the next best action.
- Layers marks it on the moisture/CO₂ chart ("Banana peel · 2:14 pm"), so you can see what each drop did to the bin over the next hours.
- Corrections are kept. They measure camera accuracy (a Tiger Data stat), and recent corrections are fed back to Gemini as hints ("in this bin, items that looked like X were Y").

**How it works (recommended approach)**

```
App ──tap "Drop something in"──▶ POST /bins/{id}/drops/session   (arms for 60 s)
                                         │
Vision service (laptop + webcam) ◀──poll─┘   GET /bins/{id}/drops/session/active
   1. grab a BEFORE frame
   2. OpenCV motion detection on the bin opening (local, free, ~30 fps)
   3. motion starts → something is going in; motion stops for 0.8 s → grab the sharpest AFTER frame
   4. send BEFORE + AFTER to Gemini Flash (vision, JSON schema)  → item, type, grams, confidence, box
   5. POST /bins/{id}/drops  (detection + thumbnail)
                                         │
Backend: validate with rules, store drop_events (status = pending) ──▶ App (SSE / 1 s poll)
App: "Something was added" pop-up → user edits → POST /drops/{id}/confirm → add_log + verdict + XP
```

Why this design:
- **Local motion trigger + one Gemini call per drop**, not continuous video streaming. A drop is a discrete event, so one image request is cheaper, faster (~1–2 s), has no session limits, and doesn't depend on a long-lived connection. OpenCV decides *when*; Gemini decides *what*. The Gemini Live API isn't needed.
- **Before + after frames.** The bin already holds scraps, so we ask Gemini what is *new* in the second image. This avoids "identifying" last week's peels.
- **Gemini Flash for vision**, set by `GEMINI_VISION_MODEL`: use the newest stable Flash model in Google AI Studio. It recognizes food zero-shot ("banana peel" vs "banana"), returns bounding boxes, supports JSON schemas, and needs no training data. We considered a local YOLO/COCO model, but it only knows a handful of whole foods and nothing about compost categories, and we have no time to train a custom one.
- **Constrained output.** `catalog_id` must be one of the food catalog ids or `unknown`, with a free-text `label`. Rules, not Gemini, assign the type for known items, so hard-avoid items can never slip through as "green".
- **Laptop webcam now, in-lid camera later.** Only the vision service touches the camera, via `CAMERA_SOURCE` (`0` for the laptop webcam, later an ESP32-CAM / Pi camera stream URL). Nothing else changes.
- **Privacy.** Frames are captured only while armed, kept as small thumbnails, and deleted after 30 days.

**Edge cases**
- **Several items in one drop:** Gemini returns a list; the pop-up shows one row per item, each editable or removable.
- **No motion within 60 s:** the session closes quietly ("Didn't see anything. Tap to try again.").
- **Gemini fails or times out (> 4 s):** the pop-up still appears with the photo and empty fields for manual entry.
- **Hands, lids or utensils:** the prompt says to ignore them; a person-only detection is treated as no drop.

**Built in this order:** (1) mock flow in the app (`MockRepository` emits a fake banana detection 2.5 s after arming, so the pop-up and edit form can be built now) → (2) vision service with webcam + motion trigger, logging to console → (3) Gemini call → (4) backend endpoints + Tiger tables → (5) swap the app to the API.

### 2.5 Summaries 📝 *planned*
Short, plain text from Gemini, using only numbers from the snapshot: **daily note** (Home status line), **score explainer** (health breakdown), **layer trend** (Layers), **weekly recap** (Sunday, with the league reset), **batch story** (harvest celebration). Details in §3.

### 2.6 Game & economy
Streak calendar, daily quests, XP and levels, **Loam** currency, **crates** from achievements, **Seed Packet** gacha for cosmetic collectibles, weekly leagues and friends. All numbers are in §8.
**Core loop:** open → check health → do the next best action → streak day fills in → quests pay XP + Loam → achievements drop crates → crates and Loam open Seed Packets → collection grows → league rank moves.

### 2.7 Notifications
Plain, state-triggered, **max 2 a day**: compost ready (built), streak at risk, crate earned, "something was added but not confirmed" (from 2.4, after 10 min).

---

## 3. Gemini: what it does and how

**Gemini is the bin's eyes and voice, not its judgement.** Rules in `domain/` (mirrored in the backend) decide; Gemini identifies and explains. If Gemini is slow, fails, or disagrees with the rules, the rule-based answer is shown and nobody notices.

| Job | Feature | Input | Output (JSON schema) | Model |
|---|---|---|---|---|
| **Drop identification** | 2.4 | before + after JPEG (≤ 1024 px), catalog ids, recent corrections | `{items: [{label, catalog_id, est_grams, confidence, box_2d}]}` with `box_2d` = `[ymin, xmin, ymax, xmax]` on 0–1000 | Flash (`GEMINI_VISION_MODEL`) |
| **Scrap check** | 2.3 | item (text or photo) + snapshot | `{verdict: add \| add_with_browns \| add_with_greens \| avoid, reason, suggest_add[], suggest_avoid[], tip}` | Flash |
| **Next best action wording** | 2.2 | snapshot + rule `need` | `{need, headline, why, suggest_add[{item, amount}], suggest_avoid[], confidence}` | Flash |
| **Summaries** | 2.5 | snapshot (+ week stats) | `{title, body, bullets[], mood}` | Flash or Flash-Lite |

**Every text call gets the same context snapshot:**
```
{ live: {moisture_top, moisture_bottom, temp_top, temp_bottom, co2_ppm, co2_slope_24h},
  balance_7d: {greens_kg, browns_kg, ratio},
  stage: {top, bottom, bottom_ready},
  health: {score, breakdown},
  recent_logs: [last 10 adds],
  need: <computed by rules> }
```
The snapshot is stored with each response (`advice` table), so we can always show *why* the app said something.

**Rule-computed `need` (next best action)**

| `need` | When (any of) | Example wording |
|---|---|---|
| `browns` | moisture > 60%, ratio greener than 1:2, CO₂ high + temp low (going anaerobic) | "The top layer is 76% wet. Dry browns will soak it up." |
| `greens` | moisture < 40% *and* ratio browner than 1:3, temp dropping in the Active stage | "Plenty of dry material. Fresh scraps will get it going." |
| `water` | moisture < 40% with balance already fine | "Just a splash of water, no food needed." |
| `mix` | CO₂ rising with flat temp | "Give it a stir to let air in." |
| `nothing` | everything in range, or bottom layer curing / ready | "All on target. Nothing to add today." |

**Guardrails**
- **Validate everything:** responses must match the schema; `verdict` and `need` must match the rules; hard-avoid items can never appear in `suggest_add`; drop `catalog_id` must be in the catalog or `unknown`. Otherwise, fall back.
- **Honest:** stage and "ready" are described as guides ("looks ready"); low-confidence answers say so.
- **Fallback templates** live in `domain/advice_rules.dart` (and the Python mirror), so the app works offline and on mock data.
- **Settings:** `temperature 0` for vision and verdicts, a low thinking budget, `media_resolution` medium for frames.
- **Cost / speed:** cache text answers by `(bin, snapshot hash, job)`; daily note and recap are generated once per day/week. Targets: vision < 2 s, text < 2 s.
- **Keys** live only in the backend and vision service `.env` files. Never in the app.

---

## 4. System architecture

```
                    ┌────────────── laptop next to the bin ──────────────┐
Arduino ─USB─▶ serial_bridge ─POST /ingest─┐  Vision service (Python, OpenCV) ◀── webcam
                                           ▼   │  motion trigger → Gemini Flash (vision)
                                  FastAPI backend ◀┘  POST /bins/{id}/drops
                      │    │    ▲
          Tiger Cloud ◀┘    │    │ REST + SSE
          (TimescaleDB)     ▼    │
                        Gemini   Flutter app (Android; web preview)
```

| Layer | Tech | Notes |
|---|---|---|
| **Mobile app** | **Flutter (Dart)**, Android-first | Riverpod 2, plain Navigator, `CustomPainter` art, Fraunces + Manrope, Phosphor icons, `flutter_animate`, `fl_chart`, `flutter_local_notifications` |
| **Backend** | **Python 3.12 + FastAPI + asyncpg** | the only thing that talks to the DB and to Gemini for text; keeps keys off the phone |
| **Database** | **Tiger Data (Tiger Cloud: Postgres + TimescaleDB)** | hypertables, continuous aggregates, hyperfunctions (sponsor track) |
| **Vision service** | **Python + OpenCV + `google-genai`** | runs on the laptop with the webcam; later the in-lid camera |
| **AI** | **Gemini API** (`google-genai`), JSON-schema structured output | rule fallback always on |
| **Hardware** | Arduino board, **1×** capacitive moisture + temperature probe (top layer), 1× SCD40/41 air sensor (CO₂, temp, humidity); laptop webcam | prints JSON over USB serial; `backend/scripts/serial_bridge.py` POSTs it. The bottom layer is `measured: false` until a second probe exists |

---

## 5. Backend & Tiger Data ✅ *built*

The backend is a thin FastAPI app (`backend/`, full reference in `backend/README.md`). Endpoint shapes mirror `CalmpostRepository`, and the app's `data/api_repository.dart` reads it: live readings (polled every 3 s), trends, the scrap check, logs and the league. It is picked when the app is built with `--dart-define=API_URL=…` (see `app/README.md`); the demo picker switches between **Live bin** and the mock scenarios. The game economy still runs on the phone; moving it to the server is next.

**The app owns the rules; the server enforces them.**
- The numbers in `domain/xp_rules.dart`, `domain/health_score.dart`, `domain/gacha.dart` and `state/game.dart` are re-implemented in `backend/app/rules/` (pure, unit-tested). `tests/test_parity.py` fails if they drift.
- The food and collectible catalogs are **generated** from `lib/data/*.dart` by `python -m scripts.sync_catalogs`, which also writes `vision/catalog.json`.
- All XP and Loam are awarded server-side into an append-only ledger, so the client can't award itself anything. Pulls are rolled on the server.

**Layout:** `app/rules` (pure) → `app/services` (DB + Gemini) → `app/routers` (HTTP). `sql/000…090_*.sql` are applied in order on every boot. Each file is idempotent, and older databases (including the first schema's `seeds` column) upgrade in place.

**Tiger Data schema**

| Object | Kind | What it holds |
|---|---|---|
| `readings` | hypertable | one wide row per POST: probe moisture (raw + %) and temperature for its layer, plus air CO₂/temp/humidity |
| `add_log` | hypertable | every add or skip: item, `catalog_id`, category, grams, `source` (`manual` / `photo` / `seed` / `camera`), `drop_id` |
| `drop_events` | hypertable | every camera detection: session, status (`pending` / `confirmed` / `dismissed`), model guess, final items, `corrected`, latency, thumbnail (30-day retention) |
| `advice` | hypertable | every answer + the snapshot it saw (proof of "same scrap, different answer") |
| `point_events` | hypertable | the XP and Loam ledger (a spend is negative Loam); once-only rewards carry a `dedupe_key` |
| `gacha_pulls` | hypertable | every Seed Packet result with pity counters |
| `stage_history` | hypertable | life-cycle stage changes per layer |
| `readings_15m`, `readings_1d` | continuous aggregates | charts and sparklines |
| `xp_weekly` | continuous aggregate | league tables (Sunday origin) |
| `vision_accuracy_1d` | continuous aggregate | share of drops confirmed without correction, avg confidence, avg latency |
| `gacha_odds_1d` | continuous aggregate | observed vs published odds |
| `bins`, `user_state`, `crates`, `collection`, `leagues`, `league_members`, `drop_sessions` | tables | device tokens + calibration; Lid Locks, packets, pity, equipped items; the crate inbox; owned collectibles; cohorts |

- **Hyperfunctions:**
  - `state_agg` / `duration_in`: time in the healthy band (healthy-layer-day XP, the "in range for 6h" quest)
  - `time_weight`
  - `regr_slope`: CO₂ trend → stage
  - `time_bucket_gapfill` + `locf`: charts
- **Policies:** columnstore after 7 days; 90-day retention on raw readings; 30 days on drop thumbnails.
- **Optional:** a Tiger fork as a "demo" database seeded with `scripts.seed_demo`.

**Endpoints**

| Area | Endpoint |
|---|---|
| Sensors | `POST /ingest` · `GET /bins/{id}/live` · `GET /bins/{id}/trends?hours=&metrics=` · `GET /bins/{id}/stats` · `POST /bins/{id}/calibration` |
| Advice (Gemini) | `POST /bins/{id}/advice/check` · `GET /bins/{id}/advice` (whole-bin "What to add") · 📝 *planned:* `GET /bins/{id}/summary?kind=` |
| Logging | `POST /bins/{id}/logs` (send `catalog_id` when known) · `GET /bins/{id}/logs` · `POST /bins/{id}/harvest` |
| **Camera drop-in** | `POST /bins/{id}/drops/session` (app arms) · `GET /bins/{id}/drops/session/active` (vision polls) · `POST /bins/{id}/drops` (vision reports) · `GET /bins/{id}/drops/stream` (SSE; `GET …/drops/pending` as a polling fallback) · `POST /drops/{id}/confirm` · `POST /drops/{id}/dismiss` |
| Game | `GET /users/{id}/game` (the app's GameState) · `POST /users/{id}/check-in` · `GET /quests/today` · `POST /quests/{key}/claim` · `GET /leagues/current` |
| Economy | `GET /users/{id}/daily-goal` · `POST …/daily-goal/{i}/claim` · `GET /users/{id}/rewards` · `POST …/crates/{id}/open` · `GET /users/{id}/collection` · `POST …/gacha/pull` · `POST …/equip` · `POST …/lid-locks/buy` · `GET /economy/rules` |

**Auth:** the app and vision send `X-API-Key`. The board/bridge sends `X-Device-Token` (only its hash is stored).

**Environment** (`backend/.env` and `vision/.env`, both git-ignored, **never commit them**):
- `backend/.env`: `DATABASE_URL`, `GEMINI_API_KEY`, `GEMINI_MODEL`, `APP_API_KEY`, `DEVICE_TOKEN`
- `vision/.env`: `GEMINI_API_KEY`, `GEMINI_VISION_MODEL`, `CAMERA_SOURCE`, `BIN_ID`, `BACKEND_URL` (`:8000` = real backend, `:8090` = `mock_backend.py`), `APP_API_KEY`

**Tests:** `cd backend && python -m pytest`. They run on a real local Postgres (`pgserver`), with TimescaleDB stand-ins. The final check against Tiger Cloud is `python -m scripts.smoke_test`.

---

## 6. Vision service (camera) ✅ *built*

`vision/` is a small Python process that owns the camera (see 2.4 and `vision/README.md`).

```
vision/
  main.py          # loop: wait for an armed session → watch → detect → report
  camera.py        # OpenCV capture from CAMERA_SOURCE (webcam index or stream URL)
  motion.py        # background subtraction (MOG2) inside a bin-opening ROI; start/stop events
  frames.py        # sharpest-frame pick (Laplacian variance), resize, JPEG encode
  gemini.py        # before/after prompt, JSON schema, catalog enum, timeout + retry
  backend.py       # client for the backend's /drops endpoints
  catalog.json     # GENERATED from app/lib/data/food_catalog.dart
  preview.py       # optional MJPEG preview at :8081 with the detection box (for the demo screen)
  calibrate.py     # one-off: draw the ROI over the bin opening, saved to roi.json
  mock_backend.py  # stand-in for backend/ on :8090
```

- **Trigger tuning:** motion must cover > 2% of the ROI for ≥ 150 ms to start; it ends after 0.8 s of stillness. Ignore the first 0.5 s after arming (the user's hand moving away from the button).
- **Demo setup:** the laptop on a stand, webcam angled down into the open bin, the ROI drawn once with `calibrate.py`. The MJPEG preview on the laptop screen is a good thing for judges to watch.
- **Run:** `cd vision && pip install -r requirements.txt && python main.py`, with `BACKEND_URL=http://localhost:8000` for the real backend.

---

## 7. App (Flutter)

### Layout

```
calmpost/
  CLAUDE.md
  app/                      # Flutter app
    lib/
      main.dart             # theme, web phone frame
      app/                  # shell (5-tab nav + event loop), toast + demo picker + ComingNext, notifications
      ui/                   # DESIGN SYSTEM: tokens, type, theme, components, brand (BrandPage/band, segments, PinkPill, Avatar), backdrop
      domain/               # pure Dart: models, health_score, xp_rules, advice_rules
      data/                 # calmpost_repository (abstract), mock_repository (+ scenarios), api_repository + api_config (live bin), food_catalog
      state/                # Riverpod: providers (bin, health, trends, tab), game (XP/streak/quests/economy), celebrations
      features/home/        # ✅ bin_world, home_screen (band + HUD + score), what_to_add, readings_row, streak_calendar, today_quests
      features/layers/      # ✅ layers_screen (zone switcher, chart with add markers, stats, life cycle)
      features/log/         # ✅ log_screen (search, recommended, lists), verdict_sheet
      features/social/      # ✅ social_screen (league table, ladder, friends, friend quest)
      features/profile/     # ✅ profile_screen (stats, rewards waiting, impact, achievements, collection, settings)
      features/greenhouse/  # ✅ greenhouse_screen, pull_reveal, collectible_art (badges, Seed Packet art)
      features/<…>/         # drop/ rewards/ (to build)
    assets/                 # fonts/, sfx/
    test/                   # domain_test (rules), home_test (flows + 360dp large-text overflow, real fonts)
  backend/                  # FastAPI: app/{rules,services,routers,catalog}, sql/000-090, scripts/, tests/
  vision/                   # camera + motion trigger + Gemini vision
  firmware/sensor_output/   # Arduino sketch (prints JSON over USB serial)
```

**Rules**
- Features never import each other. Shared things go in `ui/`, `domain/`, `state/` or `app/`. Switch tabs with `ref.read(tabProvider.notifier).state = AppTab.x`.
- Screens never call HTTP or mocks directly; they go through `repositoryProvider`.
- Game and health logic lives in `domain/` as **pure, unit-tested functions**.
- For 2.4, `CalmpostRepository` gains: `startDropSession()`, `watchDrops(sessionId)` (stream of detections), `confirmDrop(id, corrected fields)` → `Advice`, `dismissDrop(id)`.

### Screens

**Bottom nav:** Home · Layers · **Log** (forest pill) · Social · Profile.
**Off-tab:** Rewards inbox (gift on Home) · Greenhouse (Loam on Home) · **Drop-in sheet + "Something was added" pop-up** (from Home) · health breakdown · settings.

Every tab opens with the **brand band** (`ui/brand.dart`: `BrandPage`, `BrandBand`): the green header with a two-layer hill edge, a serif title, and a hero element in white on the green. Below it, open sections on the paper separated by `SectionBreak` hairlines with caps `SectionLabel`s. XP and rewards use `PinkPill`.

| Screen | Status | What's on it |
|---|---|---|
| **Home** | ✅ | Band: HUD (level ring + XP, streak, Loam, rewards) · **Bin World** · score, state pill, status. Then the game loop, top to bottom: **Daily goal** (today's XP fills a pink track to 20 / 40 / 60 XP reward nodes: 15 Loam, 30 Loam, Sprout crate; tap a pulsing node to claim) · **What to add** (main section: headline, why, three recommended items with their effect and a +15 XP badge, hold-off list) · **Rewards ready** (crates and Seed Packets wiggling; tap a crate for the reveal) · **Today** quests · **League race** (your rank, XP to the promotion zone, the players just above and below you) · **Streak** calendar + next milestone and its reward · Live readings (moved to the bottom). *Planned:* Drop something in |
| **Layers** | ✅ | Band: Top / Bottom / Air switcher, big live value + state pill. Then moisture/temperature toggle, 24 h chart with healthy band and dashed pink **add markers**, Now / Avg / Low / High, what it means, life-cycle line (Active → Ready), recent adds |
| **Log** | ✅ | Band: search field + camera button (camera drop-in is planned). Then Recommended now (tips), Greens / Browns / Keep out lists → **verdict sheet**: Good to add / Add with care / Keep it out, headline, reason, pair-it-with (tap to check that instead), XP note, Add it / Keep it out. **Demo moment** |
| **Social** | ✅ | Band: league name, reset countdown, your rank, XP this week, "XP to go" or Promotion zone, six-tier ladder. Then This week (table with promotion/demotion zones, your row marked in pink) / Friends (co-op friend quest, friends list with Nudge) |
| **Profile** | ✅ | Band: avatar, level + title, XP bar, streak / total XP / harvests / Loam. Then rewards waiting (crates + packets, Open), impact, achievements (tier dots, progress, next crate), collection by rarity, settings |
| Drop-in | 📝 | "Watching the bin…" sheet with preview + countdown → "Something was added" pop-up → verdict |
| Rewards inbox | to design | unopened crates and packets, quiet open reveal, celebration history |
| **Greenhouse** | ✅ | Opened from the **Loam coin** on Home, the **Seed Packet** in Rewards ready, the gift button (when only packets are waiting), and Profile → Collection. Band: Loam balance, floating Seed Packet, **Open your Seed Packets** (pink), **1 pull · 100** / **10 pulls · 900**, pity counters. Then **What Loam is for** (Seed Packets, Lid Lock with a Buy button, how you earn it), **Collection** (40 items; All / Plants / Finishes / Titles; unowned slots are `???` with a rarity-coloured ring; tap an owned finish or title to **Equip**), **Odds per pull** table. Pulls play the **pull reveal**: the packet shakes (longer and harder for Epic+), bursts in the best item's rarity colour, then one big card or a 5×2 grid with NEW tags and duplicate refunds |

**Bin World** (`features/home/bin_world.dart`): a Flora-style circle showing a cross-section of the bin.
- The sky follows the time of day: sun, dusk, or moon with stars and fireflies.
- A plant on the horizon grows with the batch, blooms at Thriving, and droops when the bin is dry or struggling.
- The two soil bands are the real layers. CO₂ bubbles rise faster when the microbes are busy, rain falls when it's too wet, and the soil cracks when it's too dry.
- A watch-style bezel with a forest arc shows the health score.

Tap the circle to open Layers; long-press it for the demo picker. *Planned:* a confirmed drop briefly falls into the top layer as a small scrap.

### Design system

Everything visual comes from `lib/ui/`. **Never use raw Material widgets with default styling.**

| Token | Hex | Use |
|---|---|---|
| `paper` | `#E1EBD8` | soft green-grey app background, with faint topographic contour lines (`ui/backdrop.dart`, `TopoBackdrop`) |
| `brand` / `brandDeep` / `onBrand` | `#40C274` / `#31AE63` / `#FFFFFF` | **the signature Calmpost green band** at the top of Home (HUD, Bin World, score), with a two-layer hill along its bottom edge; white text and a white gauge on it |
| `surface` / `sunk` / `line` | `#FFFFFF` / `#CFDDC3` / `#C6D7B9` | sheets, nav bar / tracks / hairlines |
| `ink` / `ink2` / `muted` / `faint` | `#11251A` / `#2D4637` / `#6A8273` / `#A6BBAC` | text hierarchy (deep greens, all readable on the green paper) |
| `forest` / `forest2` / `onForest` | `#1F3A2E` / `#2B4D3E` / `#EDEFE6` | primary actions, dark surfaces |
| `sprout` | `#B9DD7B` | positive accent on forest |
| `pink` / `pinkSoft` / `pinkDeep` | `#FF66C4` / `#F3A6D6` / `#B8327F` | **the reward accent**: streak days and flame, XP pills, rewards badge, health-ring marker, the plant's bloom. Use as a fill with dark text on it, never as text on green |
| `leaf` · `amber` · `water` · `clay` (+ `Soft`) | `#2E8A50` · `#E39B3A` · `#4F8FC9` · `#C65A3E` | in range · too dry · moisture / too wet · warnings |
| `loam` | `#6B3F22` | currency |

Rarity: Common `#9AA39D` · Uncommon `#3F8A5F` · Rare `#3F7FBF` · Epic `#C0623F` · Legendary `#D9A426`. **No purple, gradients, glass or drop shadows.**

- **Type:** **Fraunces** (serif, 400/500) for big numbers and titles; **Manrope** (500–800) for UI. Tabular figures for numbers. Fraunces has no `₂`, so "CO₂" always goes in Manrope.
- **Layout:** open sections on the paper, separated by space and full-width hairlines, with a caps label. No rounded "bubbly" cards on main screens. `Panel` is for sheets only.
- **Hero:** at most one animated `CustomPainter` scene per screen.
- **Icons:** Phosphor Regular; Fill for the active tab and status marks. No emoji.
- **Motion:** fade + 4% slide-up, 50 ms stagger, curve (0.2, 0.8, 0.2, 1); numbers count up; presses scale to 0.98 with a selection haptic. Nothing bounces.
- **Components** (`ui/components.dart`): `Pressable`, `Panel`, `PillButton`, `Chip2`, `Badge2`, `ThinBar`, `CountUp`, `Sparkline`, `LiveDot`, `LoamCoin`, `SectionTitle`, `Hairline`.

**PR checklist:** tokens and `ui/` components only · empty / loading / error states · plain copy · 360dp + 412dp + font scale 1.3 · runs on a real Android phone.

---

## 8. Game reference

### XP, streaks, quests, levels, leagues

| Mechanic | Rule |
|---|---|
| XP | followed next action +15 · check on layers +5 · healthy layer-day +10 per layer · kept a bad item out +5 · quests +10–20 · weekly balance +30 · harvest +100 · **add a scrap (manual or camera) = 0**. Action XP capped at 60/day |
| Streak | consecutive days with ≥ 1 care action (open Layers, follow the next action, confirm a camera drop that fixes balance). Calendar on Home; consecutive days join into one amber run |
| Lid Lock | streak freeze; covers one missed day; hold max 2; 60 Loam |
| Daily quests | "Check on your layers" (10 XP, 10 Loam) · "Follow the next best action" (20 XP, 25 Loam) · "Both layers in range for 6h" (15 XP, 15 Loam) |
| Levels | level n needs 30·n·(n−1) XP; titles Scrap Saver → Peel Keeper → Soil Whisperer → Worm Wrangler → Humus Hero → Loam Legend → Compost Sage |
| Leagues | weekly 30-person cohorts: Seedling → Sprout → Fern → Sapling → Oak → Sequoia; top 7 up, bottom 5 down; XP only from care |
| Friends | leaderboard, co-op friend quests, nudges |
| Impact | kg kept from landfill, CO₂e avoided (0.55 kg per kg), $ fertilizer saved; labelled as estimates; on Profile |

### Loam (currency)
**Never sold for real money.**

| Earn | Loam | | Spend | Loam |
|---|---|---|---|---|
| Daily quests | 10–25 | | Seed Packet | 100 |
| Streak milestones 3/7/14/30/100 | 25/50/100/200/500 | | 10 Seed Packets | 900 (one Rare+ guaranteed) |
| Harvest | 100 | | Lid Lock | 60 |
| League finish (promoted/safe/demoted) | 150/60/20 | | | |

### Daily goal (Home)
Today's XP (from any source) fills a track with three rewards, each claimed once a day: **20 XP → 15 Loam · 40 XP → 30 Loam · 60 XP → Sprout crate**. It resets at midnight. Because XP only comes from care, the daily goal can't be hit by dumping food in.

### Crates

| Crate | Contains |
|---|---|
| Sprout | 40–80 Loam + 1 Seed Packet |
| Grove | 120–200 Loam + 3 Seed Packets (one Rare+) |
| Canopy | 300–500 Loam + 5 Seed Packets (one Epic+) |

### Achievements (every tier pays a crate)

| Achievement | Tiers | Crates |
|---|---|---|
| First Harvest | 1 harvest | Grove |
| Harvester | 3 / 10 / 25 harvests | Sprout / Grove / Canopy |
| Hot Streak | 7 / 30 / 100-day streak | Sprout / Grove / Canopy |
| In the Zone | 7 / 30 / 90 days both layers in range | Sprout / Grove / Canopy |
| Balanced Diet | 1 / 4 / 12 balanced weeks | Sprout / Grove / Canopy |
| Good Listener | 10 / 50 / 200 next actions followed | Sprout / Grove / Canopy |
| Landfill Dodger | 5 / 25 / 100 kg kept from landfill | Sprout / Grove / Canopy |
| Quest Keeper | 25 / 100 / 365 quests | Sprout / Grove / Canopy |
| Sharp Eye | 10 / 50 / 200 camera drops confirmed | Sprout / Grove / Canopy |
| Climber | 1 / 3 / 5 league promotions | Grove / Grove / Canopy |
| Good Neighbour | 1 / 5 / 20 friend quests | Sprout / Grove / Canopy |
| Collector | 10 / 30 / all collectibles | Sprout / Grove / Canopy |

### Seed Packets (gacha, in the Greenhouse)
Cosmetic only. The catalog is `data/collectibles.dart` (40 items), and the rules are in `domain/gacha.dart` (pure, unit-tested):
- **24 specimens** (plants: Fern … Ghost Orchid, Golden Sprout) for the collection.
- **10 bin finishes**: equipping one recolours the health ring and marker on the Home band (Classic white, Mint, Sky, Blossom, Copper, Aurora, Gold…).
- **6 titles**: equipping one replaces the level title in the HUD and on Profile (Early Riser, Night Composter, Worm Whisperer, Keeper of Balance, Mycelium Mind, Loam Sage).

**What Loam is for:** Seed Packets (100, or 900 for ten) and Lid Locks (60). Both are bought in the Greenhouse.

| Rarity | Odds | Duplicate refund |
|---|---|---|
| Common | 60% | 5 Loam |
| Uncommon | 25% | 10 |
| Rare | 11% | 25 |
| Epic | 3.5% | 60 |
| Legendary | 0.5% | 150 |

Pity: Epic+ within 30 pulls, Legendary within 80; both counters visible. Odds always shown next to the pull button. A monthly featured specimen is tied to the composting season.

---

## 9. Mock data & demo

- **Scenarios** (`MockRepository`): `healthy`, `tooWet`, `tooDry`, `curing`, `ready`. The mock bin reacts to what you log (browns dry the top layer over ~10 s; wet greens add water). Switch scenarios by **long-pressing the Bin World**.
- **Seed state:** 6-day streak (best 21) that becomes 7 on the first care action, 1 Lid Lock, 240 Loam, 2 crates + 1 Seed Packet, Level 9.
- **Verdicts:** the app's `great` / `careful` / `avoid`; `careful` covers `add_with_browns` and `add_with_greens` (the `pairWith` list says which).
- **Web preview links:** `?tab=0-4`, `?scenario=tooWet`, `?checkin=1`, `?hour=0-24`, `?tab=2&item=banana_peel` (opens a verdict), `?greenhouse=1`, `?greenhouse=1&loam=2000&pull=10` (plays a 10-pull), `?source=mock|live` (planned: `?drop=1` fakes a camera detection).

**Demo script**
1. Home in `tooDry`. The plant droops, and the next action says "Add fresh scraps".
2. Tap **Drop something in** and drop a banana peel under the webcam. The pop-up appears with the photo and box, filling in "Banana peel · Green · Handful".
3. If it's wrong, correct it live, then Submit. The verdict is **great**, and +15 XP because it was the next action.
4. Switch to `tooWet` and drop another peel. Now it's **careful, add browns first**.
5. Open Layers: the drop markers are on the chart, and today's streak day fills in.
6. Claim a quest → Loam ticks up → open a crate → pull a Seed Packet.

---

## 10. Commands

```bash
# app
cd app
flutter pub get
flutter analyze                 # must be clean
flutter test                    # rules + Home flows + small-screen overflow
flutter run                     # Android phone
flutter run -d chrome           # browser preview (deep links above)
flutter build apk --release     # APK for the demo

# backend (see backend/README.md)
cd backend
python -m pytest                                   # local Postgres via pgserver; no Tiger needed
python -m scripts.init_db --bin bin-001            # schema + device token (needs DATABASE_URL in .env)
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
python -m scripts.seed_demo --bin bin-001 --scenario too_wet
python scripts/serial_bridge.py --port COM3        # real board over USB
python -m scripts.smoke_test --token <device token>
python -m scripts.sync_catalogs                    # after editing a catalog in the app

# vision (laptop with webcam)
cd vision && python calibrate.py   # once: draw the bin-opening ROI
cd vision && python main.py
```

### Build order
1. ✅ Design system + **Home** (Bin World, HUD, What to add) + **Layers**, **Log**, **Social**, **Profile** tabs.
2. **Drop-in UI on mocks** (sheet, pop-up, edit form).
3. ✅ **Backend + Tiger Data** (ingest, readings, logs, drops, advice, game + economy) and **vision service** (webcam + motion + Gemini).
4. ✅ Greenhouse (Seed Packets, collection, equip) and crate reveals · Rewards inbox history.
5. ✅ `ApiRepository` (live bin data) · next: game economy from the server, firmware on the real bin, polish on a real phone.

### Working together
- **`main` must always build and run.** Pull before you push; run `flutter analyze && flutter test` first.
- Small commits with clear messages: `feat(drop): confirm pop-up`, `fix(vision): ROI scaling`.
- One owner per folder (`app/features/x`, `backend/`, `vision/`, `firmware/`). Announce before touching `ui/` or `domain/`.
- If you change a token, rule, endpoint or mechanic, **update this file in the same commit**.

**Owners** (fill in names): Design system & app — ___ · Backend & Tiger — ___ · Vision & Gemini — ___ · Firmware & hardware — ___
