# Calmpost

> A sensor-equipped compost bin + a gamified Android app. **The bin tells you what it needs; the app makes looking after it fun.**
> Hack the Valley 11 · Climate Action & Sustainability track · Tiger Data sponsor track

This file is the source of truth for how we build Calmpost. Read it before you write code, and update it when a decision changes.

---

## The key ideas (don't break these)

1. **Reward balance, never volume.** Logging a food scrap earns **0 XP** on its own. XP comes only from *care*: following a suggestion, keeping layers in their healthy range, balancing greens and browns, finishing quests, harvesting. If a mechanic would reward dumping more food in the bin, it's wrong.
2. **Same scrap, different answer.** Advice is always based on the bin's *current* readings. This is our demo moment, so protect it.
3. **Honest about accuracy.** Moisture is our most reliable signal; temperature and CO₂ add context. Stage and "ready" are guides from sensor trends, not lab results. Copy should never overclaim.
4. **It must not look vibe-coded.** It's a designed product: Flora's calm, illustrated softness + Duolingo's game structure and tactile UI. See *Design system*.
5. **Frontend first.** The app runs fully on mock data through a repository interface. The backend plugs in later with no UI changes.

---

## Tech stack

| Layer | Tech | Notes |
|---|---|---|
| **Mobile app** | **Flutter (Dart)**, Android-first | min SDK 24, edge-to-edge, predictive back |
| State | `flutter_riverpod` 2.x (`Notifier`, `StreamProvider`) | providers only, no `setState` for shared state |
| Navigation | plain `Navigator` + custom routes in `app/routes.dart` | no router package needed yet |
| Models | plain immutable Dart classes in `domain/models.dart` | no codegen, nothing to build |
| UI | Nunito (bundled in `assets/fonts`), `phosphor_flutter`, `flutter_animate`, `fl_chart` | all art is hand-drawn `CustomPainter` (Wren, plants, bin, badges) |
| Feedback | `audioplayers` (sfx in `assets/sfx`, synthesised by us), `HapticFeedback` | |
| Device | `flutter_local_notifications` (compost ready), `shared_preferences` (onboarding seen) | |
| **Backend** (phase 2) | **Python 3.12 + FastAPI + asyncpg** | thin API: keeps DB + Gemini keys off the phone |
| **Database** | **Tiger Data (Tiger Cloud: Postgres + TimescaleDB)** | hypertables, continuous aggregates, hyperfunctions |
| AI | **Gemini API** (`google-genai`), JSON-schema structured output | rule-based fallback always on |
| **Hardware** | ESP32 (Arduino), 2× capacitive moisture, 2× DS18B20 temp, 1× SCD40/41 CO₂ | POSTs JSON over Wi-Fi |

```
ESP32 ──POST /ingest──▶ FastAPI ──▶ Tiger Cloud
                           │ ▲
                 Gemini ◀──┘ │ REST
                             │
                    Flutter app (Riverpod)
```

---

## Repo layout

```
calmpost/
  CLAUDE.md
  app/                      # Flutter app (frontend, built)
    lib/
      main.dart             # theme, onboarding gate, web phone frame
      app/                  # shell (tabs + game event loop), routes, stats bar, toasts, notifications, dev hooks
      ui/                   # DESIGN SYSTEM: tokens, type, theme, sfx, components/, art/ (Wren, plants, bin, badges)
      domain/               # pure Dart: models, health_score, xp_rules, advice_rules
      data/                 # calmpost_repository (abstract), mock_repository (+ scenarios), food_catalog
      state/                # Riverpod: providers (bin, health, standings), game (XP/streak/quests/shop), celebrations
      features/             # home/ layer/ log/ journey/ leagues/ profile/ streak/ shop/ celebrations/ onboarding/ debug/
    assets/                 # fonts/, sfx/
    test/                   # domain_test (rules), flow_test (full user flow + 360dp large-text overflow check)
  backend/                  # FastAPI + SQL migrations (phase 2)
  firmware/                 # ESP32 sketch (phase 2)
```

**Rules:**
- Features never import each other. Shared things go in `ui/`, `domain/`, `state/` or `app/`. Cross-feature navigation goes through `app/routes.dart`.
- Screens never call HTTP or mocks directly; they go through `repositoryProvider`.
- Game and health logic lives in `domain/` as **pure, unit-tested functions**. No logic in widgets.

---

## Design system

Everything visual comes from `lib/ui/`. **Never use raw Material widgets with default styling** (`AppBar`, `Card`, `ElevatedButton`, default `BottomNavigationBar`).

**Colour tokens**

| Token | Hex | Use |
|---|---|---|
| `bg` | `#FBF7EF` | warm cream app background |
| `surface` | `#FFFFFF` | cards |
| `border` | `#EEE7DA` | 2px card/button borders |
| `ink` / `muted` | `#2B2A26` / `#8A8578` | text |
| `leaf` / `leafLip` | `#58B85C` / `#3F8F43` | primary + its 3D lip |
| `soil` | `#8B5E3C` | browns, bin illustration |
| `sky` | `#4FB3E8` | moisture |
| `sun` | `#FFC83D` | XP |
| `flame` | `#FF8A1F` | streak |
| `coral` | `#FF6B5E` | warnings / avoid |
| `moss` | `#2FAE9B` | leagues, CO₂ |

Each accent is a `Tone` trio in `ui/tokens.dart`: `face`, `lip` (the darker 3D edge) and `tint` (~12% for chip and card fills). **No purple, no gradients, no glass/blur.**
League tiers: Seedling `#A7D88A` · Sprout leaf · Fern moss · Sapling sun · Oak flame · Sequoia `#E0533D`.

- **Type:** Nunito, weights 600/800/900 only. Scale is 34 / 28 / 22 / 17 / 15 / 13. Numbers use tabular figures.
- **Spacing:** 4/8 grid. **Radii:** 12 chips · 16 buttons · 24 cards · 32 sheets.
- **Depth:** no drop shadows. Use a 2px border + 4px darker bottom "lip" (the Duolingo look).
- **Icons:** Phosphor (fill/duotone) only. **No emoji as icons.** Emoji in copy is OK, sparingly.
- **Motion:** `flutter_animate`, 250 ms ease-out entrances with a 40 ms stagger, count-up numbers, springy tap scale. Every reward gets sfx + haptic.

**Core components** (`ui/components/`): `ChunkyButton` / `ChunkyCircle` (press → face drops into the lip, haptic + tap sound), `Pressable` (squish on tap), `Slab` (the card), `Tag`, `IconBlob`, `ProgressBar` (with highlight stripe), `ProgressRing`, `CountUp`, `TabBarCalm`, `showCalmSheet`, `LeafBurst` (leaf/petal confetti).

**Art** (`ui/art/`, all `CustomPainter`, no image assets): `Wren`, `Plant` (8 species, sway + wilt + grow-in), `BinScene` (cutaway bin with live zones, probe, ESP32), `Flame`, `LeagueBadge`, `Chest`, `AcornIcon`.

**Mascot: Wren the worm.** Six moods driven by the health score (thriving / happy / okay / thirsty / soggy / sick), blinks, sways, wears hats bought with acorns. Wren voices all advice and notifications. The launcher icon and splash are Wren too.

**Before you open a PR, check:**
- [ ] Only tokens and `ui/` components (no hard-coded colours or sizes)
- [ ] Empty, loading (brand shimmer) and error states designed
- [ ] Real copy (no lorem ipsum), Wren's voice where it fits
- [ ] Looks right at 360dp and 412dp wide, and at font scale 1.3
- [ ] Runs on a real Android phone

---

## App structure

**Bottom nav (custom `TabBarCalm`):** Home · Journey · **[ + Log ]** (raised centre button) · Leagues · Profile.
**Top bar on main screens** (`app/stats_bar.dart`): health score · streak flame (grey until you care for the bin today) · acorns. Each opens a sheet.

| Screen | What's on it |
|---|---|
| Home | Wren in a cutaway bin (air gap / top / bottom tinted by state), health ring, 3 daily quests, "Wren suggests" card |
| Layer detail | moisture / temp / CO₂ trend charts with the healthy band shaded |
| Log | search + camera → verdict sheet (add / add with browns / avoid), Wren's reason, XP earned. **Demo moment** |
| Journey | Duolingo-style path for the current batch |
| Leagues | tier banner, reset countdown, ranked list with promotion/demotion zones, Weekly / Friends tabs |
| Profile | level, Garden, achievements, impact stats, friends |
| Celebrations | streak milestone, quest complete, league result, compost ready, level up |
| Onboarding | meet Wren → "care earns XP, volume never does" → garden → pair bin (first launch only) |
| Sheets | health breakdown, streak calendar + Lid Locks, shop (Lid Locks + Wren hats), demo controls |

---

## Gamification rules

**Bin Health Score (0–100)** is the hero number and drives Wren's mood:
```
health = 0.45·moisture + 0.20·temperature + 0.15·co2_trend + 0.20·balance
```
- `moisture`: per layer, 100 inside the 40–60% band, falling linearly to 0 at ±25%. Weighted highest because it's our most reliable sensor.
- `balance`: 7-day greens:browns ≈ 1:2–1:3.
- It lives in `domain/health_score.dart`, and the breakdown sheet explains the score ("why is my score 72?").

**Core loop:** open → see Wren + health → do today's quests → earn XP / acorns → streak ticks → garden grows → league rank moves.

| Mechanic | Rule |
|---|---|
| Streak | consecutive days with ≥1 care action (check-in / followed suggestion / balance fix). Milestones at 3/7/14/30/100 |
| Lid Lock | streak freeze; hold max 2; 60 acorns |
| XP | followed suggestion +15 · check-in +5 · healthy layer-day +10 per layer · avoided bad add +5 · daily quest +10–20 · weekly balance +30 · harvest +100 · **log = 0**. Action XP capped at 60/day |
| Acorns | soft currency from quests/harvests → Lid Locks, Wren hats. **Never real money** |
| Daily Quests | 3 per day, always care-based ("Follow 1 of Wren's suggestions"), never "add N scraps" |
| Batch Journey | Duolingo-style path: Started → Active → Hot → Curing → Ready → Harvested, driven by sensors, not taps |
| Garden | health ≥ 70 for a day → a plant grows. Harvest → rare species. Neglect → plants **wilt**, then recover |
| Leagues | weekly 30-person cohorts: Seedling → Sprout → Fern → Sapling → Oak → Sequoia. Top 7 up, bottom 5 down, Sunday reset |
| Friends | friends leaderboard, co-op Friend Quests, nudges |
| Levels | lifetime XP → Lvl 1–50 with titles (Scrap Saver → Soil Whisperer → Humus Hero) |
| Achievements | 9 badges with bronze/silver/gold tiers (Wildfire, Landfill Dodger, Harvester, Moisture Master, Green Thumb, Quest Seeker, Perfect Balance, Rare Collector, Climber). Level-ups toast |
| Impact | kg diverted from landfill, CO₂e avoided, $ fertilizer saved, as a shareable card |
| Notifications | in Wren's voice, state-triggered, **max 2/day** |

All of the above is built on mock data. Still to do: streak-at-risk notification (needs scheduled notifications), weekly recap, real friends.

---

## Mock data & demo scenarios

`MockRepository` supports these scenarios: `healthy`, `tooWet`, `tooDry`, `curing`, `ready`. It also comes with a seeded league of 29 fake users, and it *reacts* to what you log (browns dry the top layer out over ~10 s, wet greens add water), so following a tip visibly raises the health score. Switch scenarios from the hidden demo panel (**long-press Wren**).

Verdicts in the app are `great` / `careful` / `avoid`; `careful` covers the backend's `add_with_browns` and `add_with_greens` (the `pairWith` list says which). The rule engine lives in `domain/advice_rules.dart`.

**Web preview deep links** (`flutter run -d chrome`, or a web build): `?tab=0-3`, `?scenario=tooWet`, `?open=log&item=banana_peel`, `?open=layer&zone=top|bottom|air`, `?open=health|streak|shop|debug`, `?celebrate=streak|quest|level|ready|harvest|promo`, `?onboarding=1`, `?checkin=1`. On a wide window the app renders in a phone-sized frame.

**Demo script:** log "banana peel" in `too_dry` → add. Switch to `too_wet` → "add browns first". Switch to `ready` → notification + celebration. Then show the streak, league rank and garden.

---

## Backend & Tiger Data (phase 2)

Endpoint shapes mirror `CalmpostRepository` methods, so `ApiRepository` is a mechanical swap.

- **Hypertables:** `readings` (one wide row per ESP32 POST), `add_log`, `advice` (stores the input snapshot as proof of "same scrap, different answer"), `point_events` (XP ledger), `stage_history`
- **Continuous aggregates:** `readings_15m`, `readings_1d` (charts), `xp_weekly` (powers Leagues)
- **Hyperfunctions:** `state_agg`/`duration_in` (time in healthy band), `time_weight`, `regr_slope` (CO₂ trend → stage), `time_bucket_gapfill` + `locf`
- **Policies:** columnstore after 7 days, retention on raw readings
- **Endpoints:** `POST /ingest` · `GET /bins/{id}/live` · `GET /bins/{id}/trends` · `POST /bins/{id}/logs` · `POST /bins/{id}/advice/check` · `GET /bins/{id}/advice/next` · `GET /bins/{id}/summary` · `GET /users/{id}/game` · `GET /leagues/current` · `GET /quests/today` · `POST /bins/{id}/harvest`
- **Gemini:** JSON-schema output `{verdict, reason, suggest_add[], suggest_avoid[], balance, stage_top, stage_bottom, bottom_ready, tip}`. Meat, dairy and oil are **always** `avoid` via rules, and rules also answer if Gemini fails. Full feature list in *Gemini features*.
- **Optional:** a Tiger fork as a "demo" database seeded with scenarios.
- **Secrets:** go in `backend/.env` only, which is git-ignored. **Never put keys in the Flutter app.**

---

## Gemini features

Gemini is Wren's voice, not Wren's judgement. **Rules decide, Gemini explains.** The deterministic logic in `domain/` (mirrored in the backend) works out *what the bin needs*; Gemini turns that into friendly, specific advice and summaries. If Gemini is slow, fails, or returns something that disagrees with the rules, the rule-based answer is shown instead and nobody notices.

**Every call gets the same context snapshot:**
```
{ live: {moisture_top, moisture_bottom, temp_top, temp_bottom, co2_ppm, co2_slope_24h},
  balance_7d: {greens_kg, browns_kg, ratio},
  stage: {top, bottom, bottom_ready},
  health: {score, breakdown},
  recent_logs: [last 10 adds],
  need: <computed by rules, see below> }
```
The snapshot is stored with the response in `advice` so we can always show *why* Wren said something.

### 1. Scrap check ("Can I add this?") — demo moment
- Input: scrap name (typed) **or** a photo from the Log camera (Gemini vision identifies it, the user confirms).
- Output: `{verdict: add | add_with_browns | add_with_greens | avoid, reason, suggest_add[], suggest_avoid[], tip}`.
- The verdict depends on the current snapshot, so the same banana peel gets a different answer in `too_dry` vs `too_wet`.
- Hard rules win: meat, dairy, oil, pet waste, glossy/plastic-coated paper → always `avoid`.

### 2. "What should I add?" (balance advisor)
Proposes what the bin needs next, including **whether it needs more browns or more greens**.
- Rules compute `need`, one of:

  | `need` | When (any of) | Example advice |
  |---|---|---|
  | `browns` | moisture > 60%, ratio greener than 1:2, CO₂ high + temp low (going anaerobic) | "I'm a bit soggy. Tear up some cardboard or add dry leaves." |
  | `greens` | moisture < 40% *and* ratio browner than 1:3, temp dropping in the Active stage | "I've got plenty of dry stuff. Some veggie peels would wake me up." |
  | `water` | moisture < 40% with balance already fine | "Just a splash of water, no food needed." |
  | `mix` | CO₂ rising with flat temp | "Give me a stir to let some air in." |
  | `nothing` | everything in range, or bottom layer is curing / ready | "I'm happy! Nothing to add today." |

- Gemini output: `{need, headline, why, suggest_add[{item, amount}], suggest_avoid[], confidence: low | medium | high}`. `amount` is plain-language ("a handful", "two egg cartons"), never grams.
- `suggest_add` prefers items the user has logged before, so advice fits their kitchen.
- **`nothing` is a valid, good answer.** Never suggest food just to have a suggestion (key idea 1).
- Shown in the "Wren suggests" card on Home. Following it earns the +15 XP.

### 3. Summaries
All summaries are short (≤ 3 sentences or ≤ 4 bullets), in Wren's voice, and only reference numbers from the snapshot. No invented stats.

| Summary | Where | What it covers |
|---|---|---|
| **Daily note** | Home, under Wren | Today's state in one or two lines + the one thing to do |
| **Score explainer** | Health score breakdown sheet | "Why is my score 72?": the biggest drag on the score and how to fix it |
| **Layer trend** | Layer detail | What moisture / temp / CO₂ did this week, in plain words |
| **Weekly recap** | Sunday, alongside the league reset | Health trend, greens:browns balance, care actions, XP, streak; one win and one thing to try next week |
| **Batch story** | Harvest celebration | How the batch went from Started to Ready: days per stage, kg diverted, best week. Shareable card |

Output: `{title, body, bullets[], mood}`. `mood` must match the rule-computed mood; if it doesn't, fall back.

### Guardrails
- **Honest:** stage and "ready" are described as guides ("looks ready", "seems to be curing"), never certainties. Low-confidence answers say so.
- **Validate everything:** responses must match the JSON schema, `verdict`/`need` must match the rules, and hard-avoid items can never be in `suggest_add`. Otherwise use the rule fallback.
- **Fallback templates** live in `domain/advice_templates.dart` (and the Python mirror), so the app works fully offline and on mock data.
- **Cost / speed:** cache by `(bin, snapshot hash, feature)`; daily note and recap are generated once per day/week, not per app open. Target < 2 s, show the brand shimmer while waiting.
- **Endpoints:** `POST /bins/{id}/advice/check` (scrap check) · `GET /bins/{id}/advice/next` (balance advisor) · `GET /bins/{id}/summary?kind=daily|score|layer|weekly|batch`. `CalmpostRepository` gets matching methods so `MockRepository` can return canned responses for each scenario.

---

## Commands

```bash
# app
cd app
flutter pub get
flutter analyze                                            # must be clean
flutter test                                               # rules + full-flow + small-screen overflow tests
flutter run                     # debug on connected Android phone
flutter run --profile           # check for jank
flutter run -d chrome           # quick design review in the browser (see deep links above)
flutter build apk --release     # APK to sideload for the demo

# backend (phase 2)
cd backend && uvicorn app.main:app --reload
python scripts/simulator.py --scenario too_wet
```

---

## Build order

1. ~~M0 Foundation~~ done
2. ~~M1 Home + Log~~ done: "same scrap, different answer" works on mocks
3. ~~M2 Game core~~ done
4. ~~M3 Leagues + Journey~~ done
5. ~~M4 Profile / Garden / Achievements / Impact, onboarding, notifications~~ done
6. **M5 Polish:** test on a real phone, tune motion and sound, Gemini summaries in the UI (daily note, layer trend).
7. **Phase 2:** backend + Tiger Data + Gemini + firmware, then write `ApiRepository` and swap it in `state/providers.dart` (one line).

---

## Working together

- **`main` must always build and run.** Pull before you push, and run `flutter analyze && flutter test` first.
- Use small commits with clear messages: `feat(home): health ring`, `fix(log): verdict sheet overflow`.
- One owner per feature folder to avoid merge conflicts. Announce in the team chat before touching `ui/` or `domain/`, because everyone depends on them.
- If you change a design token, rule or mechanic, **update this file in the same commit**.

**Owners** (fill in names): Design system & art (Wren) — ___ · Home/Log — ___ · Game (quests, streak, leagues) — ___ · Backend/Tiger/Gemini — ___ · Firmware/hardware — ___
