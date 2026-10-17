# Calmpost

> A sensor-equipped compost bin + a gamified Android app. **The bin tells you what it needs; the app makes looking after it rewarding.**
> Hack the Valley 11 · Climate Action & Sustainability track · Tiger Data sponsor track

This file is the source of truth for how we build Calmpost. Read it before you write code, and update it when a decision changes.

---

## The key ideas (don't break these)

1. **Reward balance, never volume.** Logging a food scrap earns **0 XP** on its own. XP and Loam come only from *care*: following the next best action, keeping layers in their healthy range, balancing greens and browns, finishing quests, harvesting. If a mechanic would reward dumping more food in the bin, it's wrong.
2. **Same scrap, different answer.** Advice is always based on the bin's *current* readings. This is our demo moment, so protect it.
3. **Honest about accuracy.** Moisture is our most reliable signal; temperature and CO₂ add context. Stage and "ready" are guides from sensor trends, not lab results. Copy should never overclaim.
4. **Sleek, minimal, grown-up.** Calm editorial design: lots of whitespace, one strong hero, hairlines instead of shadows, a soft serif for big numbers. **No mascot, no cartoons, no childish bounce.** Rewards are satisfying but quiet. See *Design system*.
5. **Frontend first.** The app runs fully on mock data through a repository interface. The backend plugs in later with no UI changes.

---

## Tech stack

| Layer | Tech | Notes |
|---|---|---|
| **Mobile app** | **Flutter (Dart)**, Android-first | min SDK 24, edge-to-edge, predictive back |
| State | `flutter_riverpod` 2.x (`Notifier`, `StreamProvider`, `FutureProvider.family`) | providers only, no `setState` for shared state |
| Navigation | `tabProvider` (`AppTab`) + plain `Navigator` | no router package |
| Models | plain immutable Dart classes in `domain/models.dart` | no codegen |
| UI | **Fraunces** (serif) + **Manrope** (sans), bundled in `assets/fonts`; `phosphor_flutter` (Regular/Fill); `flutter_animate`; `fl_chart` (Layers charts) | |
| Feedback | `HapticFeedback.selectionClick` on every tap; `audioplayers` reserved for reward moments | |
| Device | `flutter_local_notifications` (compost ready) | |
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
  app/                      # Flutter app
    lib/
      main.dart             # theme, web phone frame
      app/                  # shell (5-tab nav + event loop), toast, notifications, ComingNext placeholder
      ui/                   # DESIGN SYSTEM: tokens.dart, type.dart, theme.dart, components.dart
      domain/               # pure Dart: models, health_score, xp_rules, advice_rules
      data/                 # calmpost_repository (abstract), mock_repository (+ scenarios), food_catalog
      state/                # Riverpod: providers (bin, health, trends, tab), game (XP/streak/quests/economy), celebrations
      features/home/        # ✅ designed: header, health hero, layer strip, next action, streak calendar, today, impact
      features/<tab>/       # layers/ log/ social/ profile/ rewards/ greenhouse/ (to design)
    assets/                 # fonts/, sfx/
    test/                   # domain_test (rules), home_test (flows + 360dp large-text overflow check, real fonts loaded)
  backend/                  # FastAPI + SQL migrations (phase 2)
  firmware/                 # ESP32 sketch (phase 2)
```

**Rules:**
- Features never import each other. Shared things go in `ui/`, `domain/`, `state/` or `app/`. Switch tabs with `ref.read(tabProvider.notifier).state = AppTab.x`.
- Screens never call HTTP or mocks directly; they go through `repositoryProvider`.
- Game and health logic lives in `domain/` as **pure, unit-tested functions**. No logic in widgets.

---

## Design system

Everything visual comes from `lib/ui/`. **Never use raw Material widgets with default styling** (`AppBar`, `Card`, `ElevatedButton`, `BottomNavigationBar`, `Chip`).

**Colour tokens** (`ui/tokens.dart`)

| Token | Hex | Use |
|---|---|---|
| `paper` | `#F4F2EC` | warm app background |
| `surface` | `#FFFFFF` | panels |
| `sunk` | `#ECE9E1` | tracks, wells |
| `line` | `#E3DFD5` | 1px hairline borders and dividers |
| `ink` / `ink2` / `muted` / `faint` | `#17201B` / `#46504A` / `#8B918C` / `#BCC0BA` | text hierarchy |
| `forest` / `forest2` | `#1F3A2E` / `#2B4D3E` | the hero surface, primary buttons, Log button |
| `onForest` / `onForestMuted` | `#EDEFE6` / `#9DB3A6` | text on forest |
| `sprout` | `#B9DD7B` | positive accent on forest |
| `leaf` + `leafSoft` | `#3F8A5F` / `#E3EEE2` | positive on light, "in range" |
| `amber` + `amberSoft` | `#E39B3A` / `#F6E6CC` | streak, "too dry" |
| `water` + `waterSoft` | `#4F8FC9` / `#E1ECF6` | moisture, "too wet" |
| `clay` + `claySoft` | `#C65A3E` / `#F5E0D9` | warnings, avoid, notification badges |
| `loam` | `#8A5A3B` | the currency |

Rarity colours: Common `#9AA39D` · Uncommon `#3F8A5F` · Rare `#3F7FBF` · Epic `#C0623F` · Legendary `#D9A426`.
**No purple, no gradients, no glass/blur, no drop shadows.**

- **Type** (`ui/type.dart`): **Fraunces** (soft serif, weights 400/500) for the hero number (84), screen greetings (32), card titles (23) and stats (24). **Manrope** (500–800) for everything else: heading 16, body 14.5, label 13, small 12, caps 11 with 1.2 letter-spacing. Numbers use tabular figures. Fraunces has no `₂`, so never put "CO₂" in a serif style.
- **Spacing:** 4/8 grid, 20 px side gutter. **Radii:** 10 chips · 16 tiles · 22 panels · 28 hero · pills fully round.
- **Surfaces:** white `Panel` with a 1 px `line` border. One dark `forest` hero per screen at most.
- **Icons:** Phosphor **Regular** for UI, **Fill** for the active nav tab and small status marks. No emoji anywhere in the UI.
- **Motion:** `flutter_animate` fade + 4% slide-up on entry, 50 ms stagger, curve `M.ease` (0.2, 0.8, 0.2, 1). Numbers count up. Presses scale to 0.98 with a selection haptic. Nothing bounces or wobbles.

**Components** (`ui/components.dart`): `Pressable`, `Panel`, `PillButton`, `Chip2` (outline chip), `Badge2` (tinted label), `ThinBar` (4 px progress), `CountUp`, `Sparkline` (24 h line + healthy band), `LiveDot`, `LoamCoin`, `SectionTitle`, `Hairline`.

**Before you open a PR, check:**
- [ ] Only tokens and `ui/` components (no hard-coded colours or sizes)
- [ ] Empty, loading and error states designed
- [ ] Real, plain copy (no lorem ipsum, no cutesy voice)
- [ ] Looks right at 360dp and 412dp wide, and at font scale 1.3 (`flutter test` checks Home)
- [ ] Runs on a real Android phone

---

## App structure

**Bottom nav (5 tabs):** Home · Layers · **Log** (forest pill in the middle) · Social · Profile.
**Off-tab screens** (opened from buttons, not tabs): **Rewards inbox** (gift button on Home: crates, packets, celebrations), **Greenhouse** (Loam pill on Home: Seed Packet gacha + collection), health breakdown, settings.

| Screen | Status | What's on it |
|---|---|---|
| **Home** | ✅ designed | date + greeting · Loam balance · rewards inbox (badge = unopened items) · **forest health hero** (score, state pill, one-line status, 4 factor bars, live dot) · 3 layer tiles (top / bottom / air, value + 24 h sparkline) · **Next best action** (title, why, suggested items, +15 XP, "Log an item") · **streak calendar** (month grid, streak runs joined, Lid Lock days, "done today") · **Today** quests (claim for XP + Loam) · impact line |
| Layers | to design | per-zone live values, 24 h / 7 d charts with healthy band, what it means |
| Log | to design | search + camera → verdict (great / careful / avoid), reason, pair-with items, XP. **Demo moment** |
| Social | to design | weekly league table with promotion/demotion zones, friends, co-op friend quests |
| Profile | to design | level + title, stats, achievements (with their crate rewards), collection, impact, settings |
| Rewards inbox | to design | unopened crates and packets, open animation, history of celebrations |
| Greenhouse | to design | Seed Packet pulls (1× / 10×), odds, pity counter, collection by rarity |

The **Duolingo-style journey path is gone**. Life-cycle stage shows as a line in the hero and on Layers.
The **mascot is gone**. The bin speaks through plain copy ("The top layer is 76% wet…").

---

## Gamification & economy

**Bin Health Score (0–100)** is the hero number:
```
health = 0.45·moisture + 0.20·temperature + 0.15·co2_trend + 0.20·balance
```
- `moisture`: per layer, 100 inside the 40–60% band, falling linearly to 0 at ±25%. Weighted highest because it's our most reliable sensor.
- `balance`: 7-day greens:browns ≈ 1:2–1:3.
- State pill (`BinMood`): Thriving ≥ 85 · Healthy ≥ 70 · Fair ≥ 50 · Needs care. Top layer > 66% → **Too wet**, < 33% → **Too dry**.

**Core loop:** open → check health → do the next best action → streak day fills in → quests pay XP + Loam → achievements drop crates → crates and Loam open Seed Packets → collection grows → league rank moves.

### XP, streaks, quests

| Mechanic | Rule |
|---|---|
| XP | followed next action +15 · check on layers +5 · healthy layer-day +10 per layer · kept a bad item out +5 · quests +10–20 · weekly balance +30 · harvest +100 · **log = 0**. Action XP capped at 60/day |
| Streak | consecutive days with ≥1 care action (open Layers, follow the next action, fix balance). Shown as a calendar on Home; consecutive days join into one amber run |
| Lid Lock | streak freeze, covers one missed day automatically; hold max 2; 60 Loam (shown as a shield on the calendar) |
| Daily quests | 3 per day, care-based only: "Check on your layers" (10 XP, 10 Loam) · "Follow the next best action" (20 XP, 25 Loam) · "Both layers in range for 6h" (15 XP, 15 Loam) |
| Levels | lifetime XP → Lvl 1–50, level n needs 30·n·(n−1) XP; titles Scrap Saver → Peel Keeper → Soil Whisperer → Worm Wrangler → Humus Hero → Loam Legend → Compost Sage |
| Leagues | weekly 30-person cohorts: Seedling → Sprout → Fern → Sapling → Oak → Sequoia. Top 7 up, bottom 5 down, Sunday reset. League XP only from care, so a bigger bin can't win |
| Friends | friends leaderboard, co-op Friend Quests, nudges |

### Currency: Loam

**Loam** is the one soft currency (coin: `LoamCoin`). **Never sold for real money**, and nothing in the game can be bought with money.

| Earn | Loam |
|---|---|
| Daily quests | 10–25 each |
| Streak milestones (3 / 7 / 14 / 30 / 100 days) | 25 / 50 / 100 / 200 / 500 |
| Harvest | 100 |
| Weekly league finish | promoted 150 · safe 60 · demoted 20 |
| Crates | see below |
| Duplicate collectibles | refunded (see gacha) |

| Spend | Loam |
|---|---|
| Seed Packet (1 pull) | 100 |
| 10 Seed Packets | 900 (one Rare+ guaranteed) |
| Lid Lock | 60 |

### Crates (achievement and milestone rewards)

| Crate | Contains |
|---|---|
| **Sprout Crate** | 40–80 Loam + 1 Seed Packet |
| **Grove Crate** | 120–200 Loam + 3 Seed Packets (one guaranteed Rare or better) |
| **Canopy Crate** | 300–500 Loam + 5 Seed Packets (one guaranteed Epic or better) |

Crates and packets land in the **Rewards inbox** (gift button on Home, badge = unopened count). Opening one is a short, quiet reveal: the lid lifts, items fade up one by one, rarity colour on each card, a single soft chime.

### Achievements → rewards

Each achievement has three tiers; every tier pays a crate.

| Achievement | Tier goals | Rewards per tier |
|---|---|---|
| **First Harvest** | 1 harvest | Grove |
| **Harvester** | 3 / 10 / 25 harvests | Sprout / Grove / Canopy |
| **Hot Streak** | 7 / 30 / 100-day streak | Sprout / Grove / Canopy |
| **In the Zone** | 7 / 30 / 90 days with both layers in range | Sprout / Grove / Canopy |
| **Balanced Diet** | 1 / 4 / 12 balanced weeks (greens:browns in 1:2–1:3) | Sprout / Grove / Canopy |
| **Good Listener** | 10 / 50 / 200 next-best-actions followed | Sprout / Grove / Canopy |
| **Landfill Dodger** | 5 / 25 / 100 kg kept from landfill | Sprout / Grove / Canopy |
| **Quest Keeper** | 25 / 100 / 365 quests claimed | Sprout / Grove / Canopy |
| **Climber** | 1 / 3 / 5 league promotions | Grove / Grove / Canopy |
| **Good Neighbour** | 1 / 5 / 20 friend quests completed | Sprout / Grove / Canopy |
| **Collector** | 10 / 30 / all collectibles | Sprout / Grove / Canopy |

### Gacha: Seed Packets (in the Greenhouse)

A Seed Packet reveals one **collectible**. Collectibles are **cosmetic only**: they never change XP, health or league standing.

| Collectible type | Examples | Where it shows |
|---|---|---|
| **Specimens** (plants) | Fern, Tulip, Lavender, Toadstool, Sunflower… up to Ghost Orchid, Golden Pumpkin | Greenhouse collection, profile showcase |
| **Bin finishes** | Slate, Terracotta, Birch, Moss, Copper | colour of the Home health hero |
| **Profile frames + titles** | "Night Composter", "Mycelium Mind" | profile and league rows |

| Rarity | Odds | Duplicate refund |
|---|---|---|
| Common | 60% | 5 Loam |
| Uncommon | 25% | 10 Loam |
| Rare | 11% | 25 Loam |
| Epic | 3.5% | 60 Loam |
| Legendary | 0.5% | 150 Loam |

- **Pity:** an Epic or better is guaranteed within 30 pulls, a Legendary within 80. Both counters show in the Greenhouse.
- **Odds are always visible** next to the pull button.
- Seasonal **featured specimen** each month (higher share of the Legendary rate), tied to real composting seasons.

### Other

| Mechanic | Rule |
|---|---|
| Impact | kg kept from landfill, kg CO₂e avoided (0.55 kg per kg), $ fertilizer saved; shown on Home and Profile, labelled as estimates |
| Notifications | plain, state-triggered, **max 2/day**: compost ready (built), streak at risk, crate earned |
| Celebrations | short full-screen moments for streak milestones, level-ups, crates and harvests; afterwards they live in the Rewards inbox history |

---

## Mock data & demo scenarios

`MockRepository` supports these scenarios: `healthy`, `tooWet`, `tooDry`, `curing`, `ready`. It also comes with a seeded league of 29 fake users, and it *reacts* to what you log (browns dry the top layer out over ~10 s, wet greens add water), so following the next action visibly raises the health score. Switch scenarios from the hidden demo picker: **long-press the health hero** on Home.

Seed state for the demo: 6-day streak (best 21) that extends to 7 on the first care action, 1 Lid Lock, 240 Loam, 2 unopened crates (Sprout, Grove) + 1 Seed Packet, Level 9.

Verdicts in the app are `great` / `careful` / `avoid`; `careful` covers the backend's `add_with_browns` and `add_with_greens` (the `pairWith` list says which). The rule engine lives in `domain/advice_rules.dart`.

**Web preview deep links** (`flutter run -d chrome`, or a web build): `?tab=0-4`, `?scenario=tooWet`, `?checkin=1`. On a wide window the app renders in a phone-sized frame.

**Demo script:** Home in `tooDry` → next action says "Add fresh scraps" → log banana peel → "great". Switch to `tooWet` → same peel → "careful, add browns first". Open Layers → today's calendar day fills in, quest claimable → claim → Loam ticks up → open a crate in the Rewards inbox → pull a Seed Packet.

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

Gemini is the bin's voice, not its judgement. **Rules decide, Gemini explains.** The deterministic logic in `domain/` (mirrored in the backend) works out *what the bin needs*; Gemini turns that into friendly, specific advice and summaries. If Gemini is slow, fails, or returns something that disagrees with the rules, the rule-based answer is shown instead and nobody notices.

**Every call gets the same context snapshot:**
```
{ live: {moisture_top, moisture_bottom, temp_top, temp_bottom, co2_ppm, co2_slope_24h},
  balance_7d: {greens_kg, browns_kg, ratio},
  stage: {top, bottom, bottom_ready},
  health: {score, breakdown},
  recent_logs: [last 10 adds],
  need: <computed by rules, see below> }
```
The snapshot is stored with the response in `advice` so we can always show *why* the app said something.

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
- Shown in the "Next best action" card on Home. Following it earns the +15 XP.

### 3. Summaries
All summaries are short (≤ 3 sentences or ≤ 4 bullets), in a calm, plain voice, and only reference numbers from the snapshot. No invented stats.

| Summary | Where | What it covers |
|---|---|---|
| **Daily note** | Home, in the health hero status line | Today's state in one or two lines + the one thing to do |
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

1. **Redesign v2 (sleek):** ✅ design system + **Home** (this commit). Other tabs show a "Designing next" placeholder.
2. **Log** tab (demo moment) and **Layers** tab.
3. **Rewards inbox** + crate opening, **Greenhouse** (Seed Packets, collection).
4. **Social** (leagues, friends) and **Profile** (achievements with crate rewards, collection showcase).
5. **Polish:** real phone testing, motion tuning, reward sounds.
6. **Phase 2:** backend + Tiger Data + Gemini + firmware, then write `ApiRepository` and swap it in `state/providers.dart` (one line).

---

## Working together

- **`main` must always build and run.** Pull before you push, and run `flutter analyze && flutter test` first.
- Use small commits with clear messages: `feat(home): health ring`, `fix(log): verdict sheet overflow`.
- One owner per feature folder to avoid merge conflicts. Announce in the team chat before touching `ui/` or `domain/`, because everyone depends on them.
- If you change a design token, rule or mechanic, **update this file in the same commit**.

**Owners** (fill in names): Design system — ___ · Home/Log — ___ · Game (quests, streak, leagues) — ___ · Backend/Tiger/Gemini — ___ · Firmware/hardware — ___
