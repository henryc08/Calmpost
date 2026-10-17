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
| State | `flutter_riverpod` | providers only, no `setState` for shared state |
| Routing | `go_router` | |
| Models | `freezed` + `json_serializable` | run build_runner after editing models |
| UI | `google_fonts` (Nunito), `phosphor_flutter`, `flutter_animate`, `rive`, `fl_chart`, `confetti`, `shimmer` | |
| Feedback | `audioplayers` (sfx), `HapticFeedback` | |
| Device | `image_picker`, `flutter_local_notifications` | |
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
  app/                      # Flutter app (frontend — current focus)
    lib/
      main.dart, app.dart   # router + theme
      ui/                   # DESIGN SYSTEM: tokens.dart, theme.dart, components/, motion.dart, sfx.dart
      domain/               # pure Dart: models, health_score.dart, stage.dart, xp_rules.dart
      data/                 # calmpost_repository.dart (abstract), mock_repository.dart, api_repository.dart
      features/             # home/ layer_detail/ log/ journey/ leagues/ profile/ garden/ onboarding/ celebrations/
      debug/                # scenario switcher (long-press Wren) — also our live-demo control
    assets/                 # rive/, svg/, sfx/
    test/
  backend/                  # FastAPI + SQL migrations (phase 2)
  firmware/                 # ESP32 sketch (phase 2)
```

**Rules:**
- Features never import each other. Shared things go in `ui/` or `domain/`.
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
| `league` | `#8E6CF0` | leagues |

Each accent also has a ~12% `tint` for chip and card fills.

- **Type:** Nunito, weights 600/800/900 only. Scale is 34 / 28 / 22 / 17 / 15 / 13. Numbers use tabular figures.
- **Spacing:** 4/8 grid. **Radii:** 12 chips · 16 buttons · 24 cards · 32 sheets.
- **Depth:** no drop shadows. Use a 2px border + 4px darker bottom "lip" (the Duolingo look).
- **Icons:** Phosphor (fill/duotone) only. **No emoji as icons.** Emoji in copy is OK, sparingly.
- **Motion:** `flutter_animate`, 250 ms ease-out entrances with a 40 ms stagger, count-up numbers, springy tap scale. Every reward gets sfx + haptic.

**Core components:** `ChunkyButton` (press → shifts down 4px, lip collapses, light haptic), `CalmCard`, `StatPill`, `ProgressRing`, `SegmentedBar`, `SectionHeader`, `BottomSheetScaffold`, `TabBarCalm`, `CelebrationOverlay`.

**Mascot: Wren the worm.** Built in Rive, with 5 moods driven by the health score: thriving / happy / okay / thirsty-or-soggy / sick. Wren also voices all advice and notifications.

**Before you open a PR, check:**
- [ ] Only tokens and `ui/` components (no hard-coded colours or sizes)
- [ ] Empty, loading (brand shimmer) and error states designed
- [ ] Real copy (no lorem ipsum), Wren's voice where it fits
- [ ] Looks right at 360dp and 412dp wide, and at font scale 1.3
- [ ] Runs on a real Android phone

---

## App structure

**Bottom nav (custom `TabBarCalm`):** Home · Journey · **[ + Log ]** (raised centre button) · Leagues · Profile.
**Top bar on main screens:** streak · Seeds · health score, as `StatPill`s.

| Screen | What's on it |
|---|---|
| Home | Wren in a cutaway bin (air gap / top / bottom tinted by state), health ring, 3 daily quests, "Wren suggests" card |
| Layer detail | moisture / temp / CO₂ trend charts with the healthy band shaded |
| Log | search + camera → verdict sheet (add / add with browns / avoid), Wren's reason, XP earned. **Demo moment** |
| Journey | Duolingo-style path for the current batch |
| Leagues | tier banner, reset countdown, ranked list with promotion/demotion zones, Weekly / Friends tabs |
| Profile | level, Garden, achievements, impact stats, friends |
| Celebrations | streak milestone, quest complete, league result, compost ready, level up |
| Onboarding | meet Wren → how points work → pair bin |

---

## Gamification rules

**Bin Health Score (0–100)** is the hero number and drives Wren's mood:
```
health = 0.45·moisture + 0.20·temperature + 0.15·co2_trend + 0.20·balance
```
- `moisture`: per layer, 100 inside the 40–60% band, falling linearly to 0 at ±25%. Weighted highest because it's our most reliable sensor.
- `balance`: 7-day greens:browns ≈ 1:2–1:3.
- It lives in `domain/health_score.dart`, and the breakdown sheet explains the score ("why is my score 72?").

**Core loop:** open → see Wren + health → do today's quests → earn XP / Seeds → streak ticks → garden grows → league rank moves.

| Mechanic | Rule |
|---|---|
| Streak | consecutive days with ≥1 care action (check-in / followed suggestion / balance fix). Milestones at 3/7/14/30/100 |
| Lid Lock | streak freeze; hold max 2; bought with Seeds or earned from a perfect week |
| XP | followed suggestion +15 · healthy layer-day +10 per layer · avoided bad add +5 · daily quest +10–20 · weekly balance +30 · harvest +100 · **log = 0** |
| Seeds | soft currency from quests/milestones → Lid Locks, garden pots, rare plants, Wren cosmetics. **Never real money** |
| Daily Quests | 3 per day, always care-based ("Follow 1 of Wren's suggestions"), never "add N scraps" |
| Batch Journey | Duolingo-style path: Started → Active → Hot → Curing → Ready → Harvested, driven by sensors, not taps |
| Garden | health ≥ 70 for a day → a plant grows. Harvest → rare species. Neglect → plants **wilt**, then recover |
| Leagues | weekly 30-person cohorts: Seedling → Sprout → Fern → Sapling → Oak → Sequoia. Top 7 up, bottom 5 down, Sunday reset |
| Friends | friends leaderboard, co-op Friend Quests, nudges |
| Levels | lifetime XP → Lvl 1–50 with titles (Scrap Saver → Soil Whisperer → Humus Hero) |
| Achievements | tiered badges: First Harvest, Perfect Week, Moisture Master, kg diverted 1/5/10/25 |
| Impact | kg diverted from landfill, CO₂e avoided, $ fertilizer saved, as a shareable card |
| Notifications | in Wren's voice, state-triggered, **max 2/day** |

**Hackathon priority:** streak + streak-at-risk notification → leagues → garden → daily quests → friend quests.

---

## Mock data & demo scenarios

`MockRepository` supports these scenarios: `healthy`, `too_wet`, `too_dry`, `curing`, `ready`. It also comes with a seeded league of 29 fake users. Switch scenarios from the hidden debug panel (long-press Wren).

**Demo script:** log "banana peel" in `too_dry` → add. Switch to `too_wet` → "add browns first". Switch to `ready` → notification + celebration. Then show the streak, league rank and garden.

---

## Backend & Tiger Data (phase 2)

Endpoint shapes mirror `CalmpostRepository` methods, so `ApiRepository` is a mechanical swap.

- **Hypertables:** `readings` (one wide row per ESP32 POST), `add_log`, `advice` (stores the input snapshot as proof of "same scrap, different answer"), `point_events` (XP ledger), `stage_history`
- **Continuous aggregates:** `readings_15m`, `readings_1d` (charts), `xp_weekly` (powers Leagues)
- **Hyperfunctions:** `state_agg`/`duration_in` (time in healthy band), `time_weight`, `regr_slope` (CO₂ trend → stage), `time_bucket_gapfill` + `locf`
- **Policies:** columnstore after 7 days, retention on raw readings
- **Endpoints:** `POST /ingest` · `GET /bins/{id}/live` · `GET /bins/{id}/trends` · `POST /bins/{id}/logs` · `POST /bins/{id}/advice/check` · `GET /users/{id}/game` · `GET /leagues/current` · `GET /quests/today` · `POST /bins/{id}/harvest`
- **Gemini:** JSON-schema output `{verdict, reason, suggest_add[], suggest_avoid[], balance, stage_top, stage_bottom, bottom_ready, tip}`. Meat, dairy and oil are **always** `avoid` via rules, and rules also answer if Gemini fails.
- **Optional:** a Tiger fork as a "demo" database seeded with scenarios.
- **Secrets:** go in `backend/.env` only, which is git-ignored. **Never put keys in the Flutter app.**

---

## Commands

```bash
# app
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after editing freezed models
flutter analyze                                            # must be clean
flutter test
flutter run                     # debug on connected Android phone
flutter run --profile           # check for jank

# backend (phase 2)
cd backend && uvicorn app.main:app --reload
python scripts/simulator.py --scenario too_wet
```

---

## Build order

1. **M0 Foundation:** tokens, theme, core components, bottom bar, router, mock repository + scenarios. *(Art owner starts Wren in parallel.)*
2. **M1 Home + Log:** "same scrap, different answer" working on mocks.
3. **M2 Game core:** health score, streak + Lid Lock, daily quests, XP, celebrations, sfx/haptics.
4. **M3 Leagues + Journey.**
5. **M4 Profile / Garden / Achievements / Impact,** onboarding, notifications.
6. **M5 Polish:** empty/loading/error states, motion tuning, 360dp check, design checklist.
7. **Phase 2:** backend + Tiger Data + Gemini + firmware, then swap `MockRepository` → `ApiRepository`.

---

## Working together

- **`main` must always build and run.** Pull before you push, and run `flutter analyze && flutter test` first.
- Use small commits with clear messages: `feat(home): health ring`, `fix(log): verdict sheet overflow`.
- One owner per feature folder to avoid merge conflicts. Announce in the team chat before touching `ui/` or `domain/`, because everyone depends on them.
- If you change a design token, rule or mechanic, **update this file in the same commit**.

**Owners** (fill in names): Design system & art (Wren) — ___ · Home/Log — ___ · Game (quests, streak, leagues) — ___ · Backend/Tiger/Gemini — ___ · Firmware/hardware — ___
