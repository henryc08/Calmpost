# Calmpost

> A sensor-equipped compost bin + a gamified Android app. **The bin tells you what it needs; the app makes looking after it rewarding.**
> Hack the Valley 11 · Climate Action & Sustainability track · Tiger Data sponsor track

This file is the source of truth for how we build Calmpost. Read it before you write code, and update it in the same commit when a decision changes.

**Contents**
1. [Key ideas](#1-key-ideas-dont-break-these)
2. [Major features](#2-major-features): materials & help exchange · compost inventory · sensing & health · next best action · scrap check · **camera drop-in** · summaries · game & economy · notifications
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

1. **Reward compostable volume as well as care.** Confirmed green and brown additions earn **1 XP per 20 g** (estimated mass is our volume proxy), alongside care bonuses. Accumulate grams across the day before rounding, so splitting one drop does not create extra XP. Volume, following advice (+15), keeping an unsuitable item out (+5), check-ins, and completed exchange rewards (up to +10 each; §2.11) share the **60 XP daily action cap**. Keep-out materials earn no volume XP. Nothing earns rewards until it is saved; retries must not double-log or double-award. Volume rewards do not override compost safety advice.
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
| 2.1 | Live sensing & Bin Health Score | ✅ app (mock + **live via `ApiRepository`**) · ✅ backend · ✅ **two moisture probes + independent histories** · ✅ metric-first Sensors |
| 2.2 | **Trunc: current-bin suggestion** (Home) | ✅ immediate rules + guarded Gemini explanation |
| 2.3 | Scrap check ("Can I add this?") | ✅ rules + Log tab verdict sheet · ⏳ Gemini |
| 2.4 | **Camera drop-in: identify and track what goes in** | ✅ vision + backend + app (sheet, "Is this right?" review, mixed drops) |
| 2.10 | **Confirmed compost inventory** (counts, estimated mass, score breakdown) | ✅ backend + mock/live app + private group totals |
| 2.12 | **Toronto Challenge** (City-data sorting guide, learning badge, civic actions) | ✅ offline reviewed data + app · local learning, no XP |
| 2.11 | **Materials & help exchange** (private group requests/offers) | ✅ app + authenticated backend + two-party rewards |
| 2.5 | Summaries (daily note, recap, batch story) | 📝 planned |
| 2.6 | Game & economy (streaks, quests, Loam, crates, gacha, leagues) | ✅ Home, Social, Profile, **Greenhouse (gacha)**, crate reveal · ⏳ Rewards inbox history |
| 2.7 | Notifications | ✅ compost ready · ⏳ streak at risk, crate earned |
| 2.9 | **Single photo submission** (point a phone at something, ask what it is) | ✅ backend + capture/review UI + mock · live identification needs configured Gemini quota |
| 2.8 | **Trunc: the compost assistant (chat)** | ✅ backend + chat UI + mock · live AI wording needs configured Gemini quota |

### 2.1 Live sensing & Bin Health Score
- **Calibrate probes** opens from Sensors or Profile settings. Choose top/probe 1 or bottom/probe 2, enter separate dry/wet raw counts (or capture the current fresh raw count), then explicitly save. Inputs must be distinct integers from 0–65535. Historical recalculation is opt-in; otherwise new readings use the new curve. Live responses carry each layer's own calibration flag. Signed-in owners may calibrate only their paired bin; other accounts, shared keys targeting a player bin and camera-device tokens are denied. Mock calibration stores the chosen references/flags in-session while its sensor values remain simulated. Switching probes clears the form to prevent accidentally reusing the other sensor's references.
- **Metric-first sensor UI:** Sensors opens to **Moisture / Temperature / CO₂** buttons in that order, with one consistent selected state. Moisture shows both probe readings (upper/probe 1, lower/probe 2), a discrete two-point heat map and a history selector. Never average the probes or interpolate a full-bin measurement from two points. Missing readings are unknown; stale readings lose status colours. Each probe keeps its own calibration flag. The 40–60 shaded moisture band is an app guide on a relative dry/wet sensor scale, not a water-by-weight measurement.
- **Temperature hardware:** the lower temperature sensor is not working. The Temperature page and Home shortcut use only the working primary compost probe; ambient air is a separate comparison, never a substitute. No bottom-temperature toggle or readiness claims. Existing optional backend fields remain backward compatible; this UI change does not rewrite ingestion, health/game rules or Trunc.
- Both moisture histories are supported by migration `008_bottom_trends.sql`: probe 1 requests `moisture`, probe 2 requests `moisture_2`. Keep loading, retryable errors and empty history distinct; older servers or newly connected probes can still return no history. Never show probe 1 history as probe 2. Temperature/CO₂ charts have no asserted healthy band.
- **Sees:** the Bin World on Home (a living cross-section of the bin), the health score on its bezel, metric shortcuts (both moisture readings, compost temperature, CO₂), and charts on Sensors.
- **How:** the board sends probe moisture + temperature and air CO₂/temp/humidity about once a second over USB (the serial bridge posts it). Firmware supports two sensor pairs: A0/D2 retains `moisture_raw` / `probe_temp_c`; A1/D3 adds `moisture_raw_2` / `probe_temp_c_2`. Each externally powered DS18B20 data line needs its own 4.7 kΩ pull-up to 5 V (unless its module already includes one). The bridge forwards both pairs; the backend stores and calibrates them independently. Bottom moisture can be measured while its temperature is unknown. Missing readings remain unknown, never 0; both moisture histories are available after migration 008 and aggregate refresh. The score comes from `domain/health_score.dart`:
  ```
  health = 0.45·moisture + 0.20·temperature + 0.15·co2_trend + 0.20·balance
  ```
  `moisture` is per layer: 100 inside 40–60%, falling to 0 at ±25%. `balance` is 7-day greens:browns ≈ 1:2–1:3. State: Thriving ≥ 85 · Healthy ≥ 70 · Fair ≥ 50 · Needs care. Top layer > 66% → **Too wet**, < 33% → **Too dry**.

### 2.2 Next best action → Trunc on Home
- **Sees:** an open Trunc text section immediately below Home’s bin hero, before the daily goal. It explains what this bin needs now; the bottom-left **Ask Trunc a specific question** button opens the existing conversation. No generic chat window on Home.
- **How:** rules compute `need` ∈ `browns | greens | water | mix | nothing` from moisture, balance, CO₂ and temperature (table in §3). Gemini only words it. **`nothing` is a good answer**; never suggest food just to have a suggestion.

### 2.3 Scrap check ("Can I add this?")
- **Sees:** on the Log tab, search for an item (or tap a suggestion), then get a verdict: **great**, **careful** (add with browns or greens, with the pair-with items listed) or **avoid**, plus the reason.
- **How:** `domain/advice_rules.dart` decides from the live snapshot. Meat, dairy, oil, pet waste and glossy paper are **always avoid**. Gemini rewrites the reason in plain words and handles items not in the catalog.
- **Demo moment:** banana peel → great when the bin is dry; careful when it's soggy.

### 2.4 Camera drop-in: identify and track what goes in ✅ *built*

When you drop something into the bin, a camera sees it, Gemini identifies it, and the app asks you to confirm before it's tracked. This supports mock, legacy demo and player-owned bins. For player-owned bins the app uses the owner's session, while the vision service uses that bin's device token to report detections; it cannot confirm them or claim rewards.

**What the user does**
1. On Home, tap **Drop something in** (forest pill under the score). This first resumes an existing pending drop, or arms the **bin camera** for 60 s and opens a "Watching the bin…" sheet with a countdown. This is not the phone camera. An in-app live preview is **not implemented**; the laptop preview is separate. Closing the waiting sheet cancels the session.
2. Drop the scrap in.
3. A pop-up slides up: **"Something was added"**. The photo appears with a box around the item, then the details fill in one by one:
   - **Item:** "Banana peel"
   - **Type:** Green / Brown / Keep out
   - **Amount:** Small / Handful / Large (≈ grams behind the scenes)
   - **Confidence:** e.g. 82%
4. **It always asks "Is this right?"**, even when the camera is sure, because Gemini can be confidently wrong. Nothing is logged until the user answers. Every row can be changed: tap it to search the catalog (free text if it's not there; the user then picks its type), change the amount, or remove it, and **Add something it missed** adds a row. How hard it asks depends on the camera (`domain/drop.dart`, `tierOf`):
   - **Confident** (every item matched, ≥ 60%): "Is this right?" with **Yes, that's right**.
   - **Check** (some item < 60% or not in the catalog): the same, with those rows marked **Check this**.
   - **Couldn't tell** (no items, Gemini failed, or a mix it couldn't separate): "What went in?" with a quick multi-pick of common items, **Mixed food scraps** (a catalog green, ~150 g), and **Any of these in it?** (meat, fish, dairy, oily food, bones). A keep-out item in a drop says "Take it back out, then tick here"; ticking logs it as a skip (+5).
5. **Submit.** The confirmed amount earns volume XP (1 per 20 g for compostable greens/browns), plus +15 if it follows the next best action, subject to the daily action cap. The scrap-check verdict appears only after saving succeeds. A **Keep out** item earns no volume XP; confirming its removal earns the usual +5. Camera guesses remain visible while correcting, and are retained separately from the confirmed items.
6. **"Nothing was added"** dismisses a false trigger.

**What "tracked" means**
- The confirmed drop is an `add_log` row with `source = 'camera'`, its photo thumbnail and the model's first guess.
- It counts toward the 7-day greens:browns balance, kg kept from landfill, and the next best action.
- Sensors marks it on the moisture/CO₂ chart ("Banana peel · 2:14 pm"), so you can see what each drop did to the bin over the next hours.
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
- **A mix it can't separate** (plate scrapings, leftovers): the prompt asks Gemini for one `mixed_scraps` item rather than a confident guess, plus any keep-out food it can see as its own item. The pop-up goes to **Couldn't tell**. The rules still win: a label naming a keep-out food ("mixed scraps with chicken") is `avoid` whatever it matched.
- **No motion within 60 s:** the session closes quietly ("Didn't see anything. Tap to try again.").
- **Gemini fails or times out (> 4 s):** the pop-up still appears with the photo, in the **Couldn't tell** tier.
- **Camera service down or nothing seen:** the sheet says so and offers **Log it by hand** (the Log tab).
- **Hands, lids or utensils:** the prompt says to ignore them; a person-only detection is treated as no drop.

**Built in this order:** (1) mock flow in the app (`MockRepository` emits a fake banana detection 2.5 s after arming, so the pop-up and edit form can be built now) → (2) vision service with webcam + motion trigger, logging to console → (3) Gemini call → (4) backend endpoints + Tiger tables → (5) swap the app to the API.

### 2.10 Confirmed compost inventory

- Open **Compost inventory** from Log or Profile. It groups confirmed additions by
  catalog item (or normalized free-text label), showing **2 × Banana peel**, estimated
  total grams, green/brown type, addition count, camera/photo attribution and last date.
  Search and **All time / This week** filters are available; weeks start Sunday 00:00 UTC.
- Counts are **pieces / portions**: count whole scraps; use portions for coffee grounds,
  shredded paper and other loose material. Count and **total** weight are independent:
  changing 1 to 2 pieces does not silently double the recorded weight or XP.
- Vision proposes optional `piece_count` (integer 1–999) and `est_grams` for the whole row.
  The review screen always shows the count; missing guesses start at one portion for the
  user to confirm. Both count and exact total weight (1–5000 g) can be corrected, as can
  the item and amount preset. Manual Log uses the same count and weight controls.
- Only a successful confirmation writes `add_log.piece_count` and total `quantity_g`.
  Pending/dismissed detections, skipped/removed items, keep-out materials, and zero-weight
  entries are excluded. Retries and concurrent confirmations never create extra inventory
  or rewards. Original guesses and corrected fields stay separate.
- Historical rows retain NULL counts; their weights count, and the UI labels additions
  without counts. Never invent pieces from historical mass. The inventory is a history
  of inputs, including decomposed/harvested material; it does not claim to measure what
  physically remains or the weight of finished compost.
- **Overall compost score = actual amount XP + care and reward XP** from the server
  ledger. Keep the existing cumulative **1 XP / 20 g** and shared **60 action XP/day** cap.
  Piece count earns no additional XP. Inventory shows the breakdown; private group
  leaderboards include estimated kg, counted pieces/portions and the same breakdown.
  The sensor-based Bin Health Score remains a separate measure.
- `GET /bins/{id}/inventory?period=all|week` is owner-scoped, including the contributor's
  identity so claiming a demo bin cannot transfer its former owner's compost history.
  Group members see aggregate amounts/scores, never private ingredient inventories.
- Signed-in owners can arm, review, confirm/dismiss and submit photos for their bin.
  Vision uses `DEVICE_TOKEN` (`X-Device-Token`) for that bin's active session, reporting,
  closing and correction hints. It cannot arm sessions, confirm drops or read inventories.
  The legacy `APP_API_KEY` continues to work for demo bins only.
- Inventory uses `CalmpostRepository.inventory` in mock and API mode, refreshes after
  successful saves, every 20 seconds while visible, and on manual refresh. Demo inventory
  lasts for the repository session and does not represent a signed-in account's score.

### 2.12 Toronto Challenge

- Open **Toronto Challenge** from Home (also available before pairing a bin) or Log.
  This extends scrap knowledge and everyday compost habits with Toronto civic information;
  it does not replace the bin, Trunc, sensing, existing rewards or confirmation flows.
- `TorontoRepository` loads `assets/data/toronto_waste.json` in mock/live modes and offline.
  The reviewed subset contains **24 materials from 2,206 official Waste Wizard records**,
  retaining original City IDs, titles, categories and instructions plus a resource hash.
  The source resource was refreshed **December 12, 2023**; current summaries were checked
  **October 18, 2026** against the City Green Bin/yard-waste guides and Circular Materials'
  Toronto residential guidance. Display both dates; never call this a live City feed.
  `tools/toronto/curation.json` and its importer preserve provenance and reject changed
  source bytes until a new review. The catalogue's licence field is **License not specified**;
  do not claim an Open Government Licence for this resource. See `TORONTO_CHALLENGE.md`.
- The City-data snapshot supplies **2025 overall diversion rates: 26.3% multi-residential,
  60.3% single-family**, and the City's **about 40%** Green-Bin-compatible share of garbage.
  Rates cover City-serviced residential waste and include recycling/other diversion,
  including estimated Blue Bin tonnage; they are not composting rates, household readings,
  evidence of the causes of the gap, or a score our prototype has changed.
- Search the reviewed materials, including compostable-plastic packaging. Each route has
  condition/packaging instructions and a copyable current source. Unknown/free-text items
  have no inferred municipal category and point to Waste Wizard. Municipal routing is a
  separate deterministic mapping from Calmpost's `green/brown/avoid` safety rules.
  Cheese/meat/bones can be accepted by Toronto while remaining keep-out in this bin.
  Log verdict sheets show both contexts, even if bin checking fails; camera/photo review
  offers Toronto guidance for identified keep-outs without changing removal/save rules.
- **Three first-attempt questions → three lessons → three different transfer questions**
  earns a local **Toronto sorter** learning badge. Original answers are immutable on repeat
  visits. The before/after scores are practice results, not validated learning/impact claims.
  Explicit recovery resets corrupted local learning only. Normal quiz use never resets it.
- Explicit **I used this disposal route** saves one self-reported practice per material.
  Learning/actions are persisted locally per server + account, with a separate guest record;
  they do not sync across devices. Account restoration, corruption and failed saves are
  surfaced. Nothing here writes compost logs, inventory, sensor balance, XP, Loam,
  streaks, private leaderboards or environmental impact estimates. The badge is not a
  seed/plant reward. Existing care still earns existing rewards through existing flows.
- The civic section explains the municipal waste strategy and offers a copyable building
  organics request and a neutral question for 2026 election discussions, with official sources.
  No message is sent. Sorting guidance does not assert collection exists in a building.
- Preview: `?toronto=1` in mock web mode. Verification: `flutter analyze`, `flutter test`;
  `flutter test test/toronto_ui_test.dart --dart-define=CAPTURE_REVIEW=true` renders phone
  previews to `artifacts/toronto/`. Real Android camera/hardware validation remains separate.

### 2.11 Materials & help exchange

- Open **Social → Groups → a group → Materials & help**. Members post a **request**
  ("I need dry leaves") or an **offer** ("I can offer cardboard"), with an amount/help
  description and optional group-visible details. Materials are the catalog's greens
  and browns, finished compost, help turning a bin, or help harvesting. Keep-out and
  unknown material IDs are rejected. No map, public listing, automatic message or
  exchange of bin access is involved. A paired bin is not required to help someone.
- Another member reserves the post and can suggest arrangements. Handoff notes are
  visible **only to the two participants**, including when the group owner moderates.
  Both can update their own note. The owner of a post cannot reserve it themselves.
- **Both people explicitly confirm only after the handoff/help happened.** Posting,
  reserving and one-sided confirmations earn nothing. Completion and both awards save
  in one transaction. These are participant attestations, not hardware verification.
- Each participant earns **up to 10 XP** (`exchange_completed`), subject to **20 exchange
  XP per person per UTC day**, **one rewarded exchange per unordered pair per UTC day
  across all groups**, and the existing **60 XP shared action cap**. No Loam, amount
  multiplier or seed buff applies. Caps may reduce a reward to zero; sharing can still
  be completed. Pair cooldown receipts survive deleting a group. Exchange XP counts
  toward levels, daily progress, streaks, the existing care/reward score component,
  league totals and permitted profile activity; it is never uploaded by the phone.
- Sharing is not composting: it does **not** add weight, pieces or records to inventory,
  affect sensor health, or award amount XP. The recipient logs material when actually
  putting it in their bin, through the normal confirmation flow.
- Posts expire in seven days; reserving starts a fresh seven-day handoff window. The
  responder may release an unconfirmed reservation, reopening the post. Once either
  person has confirmed, release is blocked; either participant may close an unfinished
  exchange without XP. The group owner can close posts but cannot confirm for others.
  Completed posts cannot be reopened/cancelled. History retains closed/expired/completed
  posts; Active / My exchanges / History are paged and refresh every 20 seconds.
- Removal/leaving cancels the departing creator's active posts. A departing responder's
  wholly unconfirmed reservation reopens with private notes cleared; a partially
  confirmed handoff closes without XP. Every mutation rechecks group membership under
  the circle lock. Reservation IDs and post versions reject stale confirmations and
  delayed claims after release. Creation/reservation retries are idempotent; simultaneous
  claims have one winner. At most 10 active posts per creator across all groups.
- `098_materials_exchange.sql` adds `exchange_posts`. The authenticated routes are
  `GET/POST /social/circles/{cid}/exchange` and `POST …/{id}/claim`, `/note`, `/confirm`,
  `/release`, `/cancel`. GET accepts `view=active|mine|history`, `before` and `limit`.
  No shared API key or device-token access. Rewards take player locks in sorted order
  before testing caps, including simultaneous completions in different groups.

### 2.5 Summaries 📝 *planned*
Short, plain text from Gemini, using only numbers from the snapshot: **daily note** (Home status line), **score explainer** (health breakdown), **layer trend** (Sensors), **weekly recap** (Sunday, with the league reset), **batch story** (harvest celebration). Details in §3.

### 2.6 Game & economy
Streak calendar, daily quests, XP and levels, **Loam** currency, **crates** from achievements, **Seed Packet** gacha for plants with equippable buffs plus cosmetic finishes/titles, weekly leagues and friends. Tap the Home level ring to open the **growth trail** and claim rewards for each reached level. All numbers are in §8.
**Core loop:** open → check health → do the next best action → streak day fills in → quests pay XP + Loam → achievements drop crates → crates and Loam open Seed Packets → collection grows → league rank moves.

### 2.7 Notifications
Plain, state-triggered, **max 2 a day**, persisted across restarts: compost looks ready (**foreground-triggered Android alert**, built), streak at risk, crate earned, "something was added but not confirmed" (planned). Background/push delivery is not implemented. A sensor guide must not claim that texture or smell was measured.

---

### 2.9 Single photo submission ✅ *backend + app data layer + capture UI*

Log → **Take or choose a photo** opens Android camera/gallery capture, a local preview and an explicit **Identify and review** action. Orientation is normalized, metadata removed, and images bounded to 1024 px and 1.4 MB before upload. Cancellation, permissions, invalid images and upload failures stay retryable. Android interrupted-picker recovery restores the local preview without uploading. The existing review sheet handles the returned pending drop, including manual identification, corrections and keep-out confirmation; no second confirmation flow is used. An existing pending drop is reviewed before creating another. Source remains `photo` throughout.

The camera drop-in (2.4) watches the bin and decides for itself when something
arrived. This is the other way round: the user points a phone at something and
asks what it is.

`CalmpostRepository.submitPhoto(Uint8List jpeg)` ⇒ a pending `CameraDrop` with
`source == 'photo'` (`drop.fromPhoto`). **It is an ordinary drop**, so
the existing UI's `confirmReviewedDrop` and `dismissReviewedDrop` finish it exactly as they finish a camera
detection — there is no separate photo flow to build, and the XP rules, the
add_log rows and the history all come for free.

- Downscale to about **1024 px** before calling. Over ~1.5 MB is a 413 whose
  message says so.
- **A failed identification is not an error.** `guesses` comes back empty with
  `geminiOk == false` and the photo kept, for the user to name by hand — the
  same state an unknown `catalog_id` already produces.
- Categories are decided by `app/rules/compost.py`, never by the model: the
  prompt explicitly forbids it from judging, so a cheese rind comes back
  `avoid` from its label alone.
- `MockRepository.submitPhoto` returns a scripted banana peel with a bounding
  box, so an overlay has something to draw with no backend. Pass an **empty**
  `Uint8List` to get the failed-identification state.

`source` also keeps `/drops/accuracy` honest: that number is about the camera,
so photos the user framed are excluded from it.

Integration: photo confirmations retain `source = 'photo'` in `add_log` and
use the same atomic, retry-safe confirmation receipt as webcam drops. Both
repository APIs remain available; this does not replace the laptop's USB
webcam flow. Phone capture UI is built; player-owned webcam access uses
the scoped device authorization described in §2.10.
Photo identification sends the Gemini key in a request header, never the URL.
Provider failures return a fixed, safe manual-identification message; raw
exceptions and tracebacks must not enter drop history, responses, or logs.

**Past drops & photos** is reachable from Log. `dropHistory(before, limit)` pages the existing API; the UI shows resolved records with source, original guesses, confirmed items, corrections and removed items. `dropPhoto(id)` fetches JPEGs with the same authenticated repository headers (never credentials in image URLs). Loading, empty, retry, missing/expired photos and account changes are handled. Mock confirmations/dismissals populate the same history contract. Reading history never awards XP or repeats an add.

Mock pending recovery uses the exact detection shown in the review sheet, including failed/mixed identifications. A no-motion session leaves no pending drop. The separate legacy `confirmDrop` volume-XP implementation is retained, not removed or replaced by UI work.

---

### 2.8 Trunc: current-bin guidance + follow-up questions ✅

Open **Ask Trunc** from Home or Log. The paper-and-brand-band conversation includes a keyboard-aware composer, waiting indicator, retry for transport failures, and clear-conversation action. Fallback and off-topic replies render normally, with the actual reading timestamp, recent-add count and photo count underneath. Recent photos are opt-in. Conversation history is in app memory and resets with repository/account/bin changes; only the latest ten completed exchanges are sent, excluding the new question. Late replies from an old account are discarded.

Home shows local guidance immediately, then requests a photo-free overview through the existing chat endpoint. Refresh at most once a minute unless the care decision, sensor quality or confirmed-log count changes; stop listening off Home. Failed/stale/mismatched replies never replace current local guidance. The response must include the same rule-computed `need` and fresh reading context.

Direct material questions (including apples, water, and remembered-material follow-ups) use deterministic current-bin rules, not Gemini's judgement. A generally compostable item can be unnecessary **now**. Gemini explains broader questions using live readings, confirmed additions and optional photos. Shared cases in `testdata/trunc_cases.json` pin Dart/Python decisions.

**Limits:** two moisture points cannot establish whole-bin water content, oxygen, carbon:nitrogen chemistry, decomposition or exact doses. The 40–60% band is a relative sensor guide. Missing/stale upper moisture means inspect first; conflicting probes mean inspect both spots, not add across the bin. Uncalibrated probes remain approximate. A lower curing/ready stage never suppresses upper-probe care. A steady answer is allowed; missing mix history is disclosed. Bottom temperature is optional and never inferred from moisture.

**What the UI has to work with** — `CalmpostRepository.askTrunc` (`app/lib/data/calmpost_repository.dart`):

```dart
Future<TruncReply> askTrunc(String message, {List<TruncTurn> history, bool includePhotos});
```

`TruncReply` and `TruncTurn` are in `app/lib/domain/models.dart`. Backed by
`ApiRepository` (POST `/bins/{id}/chat`) and by `MockRepository`, which answers
from the same deterministic guidance, so **the flow can be demoed without a backend, API key or Gemini quota**.

Conversation contract:

- **Stateless.** The server keeps no conversation. Hold the turns in app state
  and pass them in `history` (oldest first, excluding the question being
  asked). Nothing to fetch on resume.
- **There is no refusal UI to build.** An off-topic question returns
  `onTopic: false` with the redirect text already written. Render it as a
  normal message.
- **`isFallback` is not an error.** `model == 'rules-fallback'` means Gemini was
  unreachable and the sensors answered instead. Still a real reply; no error
  state.
- **`context` is for honesty, not decoration.** `{readingsAt, readingsStale, recentAdds,
  photos}` says what Trunc was actually given. A null `readingsAt` means the
  bin has never reported, so the answer came from general rules rather than
  this bin — worth saying quietly.

Mock shortcuts for building the states: ask anything off topic for the refusal,
and **"test fallback"** for the fallback. `Scenario.tooWet` vs
`Scenario.healthy` change the answer to "why does my bin smell?", so both
branches are reachable. Replies are keyword-matched, not random, so a given
question always gives the same answer.

**Context Trunc gets on the backend** (it does not need asking for): the live
sensor snapshot, the last 48 h of `add_log` (`recent_adds`, newest first, with
`hours_ago`), and, when opted in, the newest two camera photos as real image parts. It is told
to be aware of all of it but to raise it only when it bears on the question.

**Scope and safety.** Compost only, enforced twice: the model classifies each
question, and the backend substitutes its own line when it says off topic. The
care decision comes from `app/rules/compost.py` and `trunc_guidance.py`. The backend checks the structured need and conservatively screens model prose for contradictory additions, keep-outs and unsupported exact quantities; violations use `rules-override`. These prose checks are a backstop, not a guarantee of every AI sentence. Direct material decisions bypass Gemini. `context.photos` counts photos actually used by an accepted model response (zero for rules/text-only fallback).

The app never calls Gemini and never holds its key. The updated backend supplies optional `need` and `context.readings_stale` fields. Older servers remain parseable; Home ignores replies without a matching `need` and uses local guidance. Deploy the updated backend to enable guarded remote wording.

---

## 3. Gemini: what it does and how

**Gemini is the bin's eyes and voice, not its judgement.** Rules in `domain/` (mirrored in the backend) decide; Gemini identifies and explains. If Gemini is slow, fails, or disagrees with the rules, the rule-based answer is shown and nobody notices.

| Job | Feature | Input | Output (JSON schema) | Model |
|---|---|---|---|---|
| **Drop identification** | 2.4 | before + after JPEG (≤ 1024 px), catalog ids, recent corrections | `{items: [{label, catalog_id, piece_count?, est_grams, confidence, box_2d}]}` with `box_2d` = `[ymin, xmin, ymax, xmax]` on 0–1000 | Flash (`GEMINI_VISION_MODEL`) |
| **Scrap check** | 2.3 | item (text or photo) + snapshot | `{verdict: great \| careful \| avoid, headline, reason, balance, suggest_add[], suggest_avoid[], pair_with[], tip}` | Flash |
| **Home Trunc wording** | 2.2 | snapshot + locked care decision + fixed overview question, no photos/history | same Trunc reply schema below; local guidance is immediate | Flash |
| **Photo identification** | 2.9 | one user-supplied JPEG + the catalog ids | same `items` shape as drop identification; categories come from the rules, not the model | Flash |
| **Trunc chat** | 2.8 | snapshot + `recent_adds` + newest 2 drop photos + the question and prior turns | `{on_topic, reply, used_readings, need}`; off topic ⇒ the backend's own line | Flash |
| **Summaries** | 2.5 | snapshot (+ week stats) | `{title, body, bullets[], mood}` | Flash or Flash-Lite |

**Every text call gets the same context snapshot:**
```
{ live: {moisture_top, moisture_bottom, temp_top, temp_bottom, co2_ppm, co2_slope_24h},
  balance_7d: {greens_kg, browns_kg, ratio},
  stage: {top, bottom, bottom_ready},
  health: {score, breakdown},
  recent_adds: [last 48 h of add_log, newest first, with hours_ago and action],
  need: <computed by rules> }
```
Trunc (2.8) gets the same snapshot plus the newest two camera photos as
image parts.
The snapshot is stored with each response (`advice` table), so we can always show *why* the app said something.

**Rule-computed `need` (next best action)**

| `need` | When (any of) | Example wording |
|---|---|---|
| `browns` | upper moisture > 60%, or recent ratio greener than 1:2 after checking dryness | "The top layer is 76% wet. Dry browns will soak it up." |
| `greens` | upper moisture < 40% *and* recent ratio browner than 1:3 | "Plenty of dry material. Fresh scraps will get it going." |
| `water` | upper moisture < 40% without brown-heavy additions | "Just a splash of water, no food needed." |
| `mix` | CO₂ slope > 2/day with measured compost-to-ambient rise < 5°C, after moisture/mix checks | "Give it a stir to let air in." |
| `nothing` | no indicated action; unknown/conflicting data instead requires inspection, never an all-clear | "All on target. Nothing to add today." |

Missing/stale upper moisture and conflicting probes take priority over this table. `nothing` alone is not proof of health; Trunc additionally distinguishes `unknown`, `inspect`, and `steady`.

**Guardrails**
- **Validate everything:** responses must match the schema; `verdict` and `need` must match the rules; hard-avoid items can never appear in `suggest_add`; drop `catalog_id` must be in the catalog or `unknown`. Otherwise, fall back.
- Backend advice validates required fields, list elements and enums before use. Photo parsing failures keep the photo pending for manual review; malformed Trunc replies use its rules summary. Invalid model responses must not become 500s or expose raw provider errors.
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
| **Hardware** | Arduino UNO R4, **2×** analog capacitive moisture sensors + **1 working** DS18B20 compost temperature probe (lower temperature probe unavailable), 1× DFRobot STCC4 air module (CO₂, temp, humidity); laptop webcam | firmware prints both pairs as JSON over USB serial; `backend/scripts/serial_bridge.py` forwards both. Bottom moisture is live; missing bottom temperature remains unknown |

---

## 5. Backend & Tiger Data ✅ *built*

The backend is a thin FastAPI app (`backend/`, full reference in `backend/README.md`). `ApiRepository` reads live readings (every 3 s), trends (every 30 s), scrap checks and logs. Both registered players and legacy API-key demo accounts use server game/economy: quest/daily claims, crates, pulls, equipment and Lid Locks use server responses, refreshed after actions and every minute. Players retain scoped Social check-ins and care logs, but Home, Sensors history, Profile and Greenhouse now read the same server ledger and saved additions. Unpaired accounts see a connection prompt, not seeded progress. Explicit mock mode remains separate and never uploads demo rewards. Build with `--dart-define=API_URL=…` or pair a bin in Social. Demo progression is persisted separately using SharedPreferences.

**The app owns the rules; the server enforces them.**
- The numbers in `domain/xp_rules.dart`, `domain/health_score.dart`, `domain/gacha.dart` and `state/game.dart` are re-implemented in `backend/app/rules/` (pure, unit-tested). `tests/test_parity.py` fails if they drift.
- The food and collectible catalogs are **generated** from `lib/data/*.dart` by `python -m scripts.sync_catalogs`, which also writes `vision/catalog.json`.
- All XP and Loam are awarded server-side into an append-only ledger, so the client can't award itself anything. Pulls are rolled on the server.

**Layout:** `app/rules` (pure) → `app/services` (DB + Gemini) → `app/routers` (HTTP). `sql/000…098_*.sql` are applied in order on every boot. Each file is idempotent. Migration 095 adds manual-log request receipts and camera-confirmation receipts; 096 adds compost counts; 097 adds the active seed. Identical retries return the original result; changed payloads conflict. A whole camera drop saves in one transaction, with deterministic verdicts (no Gemini network call inside confirmation). A per-player lock serializes XP caps and ledger deduplication.

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
| Sensors | `POST /ingest` (both probes in one sample: `moisture_raw`/`probe_temp_c` = top, `moisture_raw_2`/`probe_temp_c_2` = bottom) · `GET /bins/{id}/live` · `GET /bins/{id}/trends?hours=&metrics=` · `GET /bins/{id}/stats` · `POST /bins/{id}/calibration` (send `probe: 1` or `2`; each probe has its own dry/wet counts) |
| Advice (Gemini) | `POST /bins/{id}/advice/check` · `GET /bins/{id}/advice` (whole-bin "What to add") · 📝 *planned:* `GET /bins/{id}/summary?kind=` |
| Logging | `POST /bins/{id}/logs` (send `catalog_id` when known) · `GET /bins/{id}/logs` · `GET /bins/{id}/inventory?period=all\|week` · `POST /bins/{id}/harvest` |
| **Photo submission** | `POST /bins/{id}/drops/photo` — `{image_jpeg_b64}` ⇒ a pending drop with `source: 'photo'`. Downscale to ~1024 px; over ~1.5 MB is a 413. Finishes through the normal `/drops/{id}/confirm` and `/dismiss`. |
| **Trunc (chat)** | `POST /bins/{id}/chat` — `{message, history[], include_photos}` ⇒ `{reply, model, on_topic, used_readings, need, context}`. Stateless: the app owns the conversation. |
| **Camera drop-in** | `POST /bins/{id}/drops/session` (app arms) · `GET /bins/{id}/drops/session/active` (vision polls) · `POST /bins/{id}/drops` (vision reports) · `GET /bins/{id}/drops/stream` (SSE; `GET …/drops/pending` as a polling fallback) · `POST /drops/{id}/confirm` · `POST /drops/{id}/dismiss` · `GET /bins/{id}/drops/history` (resolved drops, paged; `has_photo` rather than inline base64) · `GET /drops/{id}` · `GET /drops/{id}/photo` (real `image/jpeg`) |
| Game | `GET /users/{id}/game` (the app's GameState) · `POST /users/{id}/check-in` · `GET /quests/today` · `POST /quests/{key}/claim` · `GET /leagues/current` |
| Economy | `GET /users/{id}/daily-goal` · `POST …/daily-goal/{i}/claim` · `GET /users/{id}/rewards` · `POST …/crates/{id}/open` · `GET /users/{id}/collection` · `POST …/gacha/pull` · `POST …/equip` · `POST …/lid-locks/buy` · `GET /economy/rules` |

**Auth:** registered players use scoped bearer sessions (see Multiplayer below). Shared demo `X-API-Key` access cannot read or mutate their bins or private state. Legacy demo users/bins still share that key. Vision uses the bin’s `X-Device-Token` for player-owned camera sessions, reports and hints, and the demo key for demo bins. The board/bridge sends `X-Device-Token` (only its hash is stored). Re-registering an existing demo bin returns 409 instead of replacing its owner/token. Database TLS verifies certificates and hostnames; set `DATABASE_CA_FILE` to the provider's CA PEM if needed.

**Environment** (`backend/.env` and `vision/.env`, both git-ignored, **never commit them**):
- `backend/.env`: `DATABASE_URL`, `GEMINI_API_KEY`, `GEMINI_MODEL`, `APP_API_KEY`, `DEVICE_TOKEN`
- `vision/.env`: `GEMINI_API_KEY`, `GEMINI_VISION_MODEL`, `CAMERA_SOURCE`, `BIN_ID`, `DEVICE_TOKEN` (player-owned bin), `BACKEND_URL` (`:8000` = real backend, `:8090` = `mock_backend.py`), `APP_API_KEY`

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
  AGENTS.md                 # this file (CLAUDE.md just imports it for Claude Code)
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
      features/layers/      # ✅ layers_screen (metric switcher, two-probe moisture map/history, temperature, CO₂)
      features/log/         # ✅ log_screen (search, recommended, lists), verdict_sheet
      features/social/      # ✅ social_screen (league table, ladder, friends, friend quest)
      features/profile/     # ✅ profile_screen (stats, rewards waiting, impact, achievements, collection, settings)
      features/greenhouse/  # ✅ greenhouse_screen, pull_reveal, collectible_art (badges, Seed Packet art)
      features/drop/        # ✅ drop_sheet (arm → watching → review → result), drop_review (rows, editor, quick picks), drop_photo
      features/<…>/         # rewards/ (to build)
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
- For 2.4, the upstream data API remains `startDropSession()`, `watchDrops()`, `confirmDrop(id, confirmations)` and `dismissDrop(id)`. The editable sheet uses `watchDrop(session)`, `confirmReviewedDrop(drop, lines)` and `dismissReviewedDrop(drop)` to retain per-row review states. Both share `DropSession` in `models.dart` and the same backend transaction/receipts. Open the sheet with `Routes.drop(context)`.

### Screens

**Bottom nav:** Home · Sensors · **Log** (forest pill) · Social · Profile.
**Off-tab:** Rewards inbox (gift on Home) · Greenhouse (Loam on Home) · **Drop-in sheet + "Something was added" pop-up** (from Home) · health breakdown · settings.

Every tab opens with the **brand band** (`ui/brand.dart`: `BrandPage`, `BrandBand`): the green header with a two-layer hill edge, a serif title, and a hero element in white on the green. Below it, open sections on the paper separated by `SectionBreak` hairlines with caps `SectionLabel`s. XP and rewards use `PinkPill`.

| Screen | Status | What's on it |
|---|---|---|
| **Home** | ✅ | Band: HUD (level ring + XP, streak, Loam, rewards) · **Bin World** · score, state pill, status. Then **Trunc** (current-bin text suggestion + specific-question button), followed by **Daily goal** (today's XP fills a pink track to 20 / 40 / 60 XP reward nodes: 15 Loam, 30 Loam, Sprout crate; tap a pulsing node to claim) · **Rewards ready** (crates and Seed Packets wiggling; tap a crate for the reveal) · **Today** quests · **League race** (your rank, XP to the promotion zone, the players just above and below you) · **Streak** calendar + next milestone and its reward · Live readings (moved to the bottom). **Drop something in** (forest pill under the status line) opens the camera drop-in |
| **Sensors** | ✅ | Band: Moisture / Temperature / CO₂ switcher. Moisture: two live readings, discrete two-point heat map, per-probe calibration warning/link, probe 1/2 history selector. Temperature: working compost probe + ambient comparison, no lower temperature. Both: 24 h chart, Latest / Avg / Low / High, limitations, recent adds. Missing/stale data and loading/error/empty history stay explicit |
| **Log** | ✅ | Band: search field + camera button (opens the camera drop-in). Then Recommended now (tips), Greens / Browns / Keep out lists → **verdict sheet**: Good to add / Add with care / Keep it out, headline, reason, pair-it-with (tap to check that instead), XP note, Add it / Keep it out. **Demo moment** |
| **Social** | ✅ | Band: league name, reset countdown, your rank, XP this week, "XP to go" or Promotion zone, six-tier ladder. Then This week (table with promotion/demotion zones, your row marked in pink) / Friends (co-op friend quest, friends list with Nudge) |
| **Profile** | ✅ | Band: avatar, level + title, XP bar, streak / total XP / harvests / Loam. Then rewards waiting (crates + packets, Open), impact, achievements (tier dots, progress, next crate), collection by rarity, settings |
| **Drop-in** | ✅ | "Watching the bin…" sheet with a 60 s countdown → **"Is this right?"** review (photo with boxes, editable rows, tiers above) → per-item verdicts and XP. "Nothing was added" dismisses a false trigger |
| Rewards inbox | to design | unopened crates and packets, quiet open reveal, celebration history |
| **Greenhouse** | ✅ | Opened from the **Loam coin** on Home, the **Seed Packet** in Rewards ready, the gift button (when only packets are waiting), and Profile → Collection. Band: Loam balance, floating Seed Packet, **Open your Seed Packets** (pink), **1 pull · 100** / **10 pulls · 900**, pity counters. Then **What Loam is for** (Seed Packets, Lid Lock with a Buy button, how you earn it), **Collection** (40 items; All / Plants / Finishes / Titles; unowned slots are `???` with a rarity-coloured ring; tap an owned finish or title to **Equip**), **Odds per pull** table. Pulls play the **pull reveal**: the packet shakes (longer and harder for Epic+), bursts in the best item's rarity colour, then one big card or a 5×2 grid with NEW tags and duplicate refunds |

**Bin World** (`features/home/bin_world.dart`): a Flora-style circle showing a cross-section of the bin.
- The sky follows the time of day: sun, dusk, or moon with stars and fireflies.
- A plant on the horizon grows with the batch, blooms at Thriving, and droops when the bin is dry or struggling.
- The two soil bands are the real layers. CO₂ bubbles rise faster when the microbes are busy, rain falls when it's too wet, and the soil cracks when it's too dry.
- A watch-style bezel with a forest arc shows the health score.

Tap the circle to open Sensors; long-press it for the demo picker. *Planned:* a confirmed drop briefly falls into the top layer as a small scrap.

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
| XP | **confirmed compostable volume +1 per 20 g**, rounded cumulatively per day · followed next action +15 · check on layers +5 · healthy layer-day +10 per layer · kept a bad item out +5 · quests +10–20 · weekly balance +30 · harvest +100 · completed exchange up to +10 each (20 exchange XP/day; same pair once/day). Volume and other action XP share the 60/day cap |
| Streak | consecutive days with ≥ 1 care action (open Sensors, follow the next action, confirm a camera drop that fixes balance). Calendar on Home; consecutive days join into one amber run |
| Lid Lock | streak freeze; covers one missed day; hold max 2; 60 Loam |
| Daily quests | "Check on your layers" (10 XP, 10 Loam) · "Follow the next best action" (20 XP, 25 Loam) · "Both layers in range for 6h" (15 XP, 15 Loam) |
| Levels | 50 levels; **every level-up costs 120 XP**, including 1→2 and 10→11. Level n needs `120·(n−1)` lifetime XP. Existing XP, claimed rewards and collections are retained; displayed levels are recalculated from this flat curve. Titles Scrap Saver → Peel Keeper → Soil Whisperer → Worm Wrangler → Humus Hero → Loam Legend → Compost Sage |
| Leagues | weekly 30-person cohorts: Seedling → Sprout → Fern → Sapling → Oak → Sequoia; top 7 up, bottom 5 down; XP from confirmed compostable volume and care |
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
Today's XP (from any source, including compostable volume) fills a track with three rewards, each claimed once a day: **20 XP → 15 Loam · 40 XP → 30 Loam · 60 XP → Sprout crate**. It resets at midnight. The action cap limits volume and repeat-action rewards; safety advice still applies.

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

### Level map and seed buffs
- Tap the Home level ring to open the growth trail: five chapters of ten levels, current progress, locked/reached/claimed rewards, and the active seed. Every reached level can be claimed once, including level 1 and previously reached levels.
- Level n grants **20 + 5·(n−1) Loam**. Every third level also grants one Seed Packet; every fifth grants a Sprout crate (Grove instead on multiples of ten). Guaranteed plants: **Sprout at 1**, **Clover at 5**, **Wild Bloom at 10**. Level rewards never grant XP. Seed unlocks preserve existing copies.
- **One active owned plant, 24 distinct buff profiles.** Commons grant only +1 XP or Loam on a specific activity. Uncommons grant small dual perks or 10–20% quest bonuses; rares grant broader 20–35% specialties; epics grant 40–50% quest specialties plus care perks; legendaries grant dual quest bonuses with a 60% primary focus. See the examples below; the complete per-seed mapping is in `domain/progression.dart`.
- Flat common bonuses avoid rounding tiny percentages to zero. Percentage bonuses round down **per award**. Care bonuses still share the 60 XP action cap; quest rewards are separate. Volume XP, sensor health, safety verdicts, harvests and other payouts are unchanged. Activating another plant replaces the effects; duplicates never stack. Effects apply to future payouts (quests use the active seed at claim time), not old ledger rows. Quest-specific effects use the server's quest key, never client-supplied reward amounts.
- The mapping and pure rules live in `domain/progression.dart`, mirrored in `backend/app/rules/progression.py`. Live rewards use the server ledger and player lock, not client multipliers. `POST /users/{id}/levels/{level}/claim` checks earned levels and uses idempotent receipts; `/equip` now also accepts owned specimens. Migration `097_progression.sql` follows `096_compost_inventory.sql` and adds nullable `equipped_seed` without rewriting balances. Deploy the backend migration before the new app.
- Seed unlocks/reveals and collection details show curated, offline **field notes** from [US EPA: Composting at Home](https://www.epa.gov/recycle/composting-home), plus a practical action and copyable source link. These are general environmental lessons, not species-specific growing advice. Fantasy plants and game-only buffs are labelled explicitly. No Gemini call is required.

| Rarity | Example seed | Active effects |
|---|---|---|
| Common | Sprout · First steps | +1 XP on the layers quest only |
| Uncommon | Lotus · Still water | +20% XP and Loam on the healthy-layers quest only |
| Rare | Oak · Deep roots | +25% XP on all daily quests |
| Epic | Ember Fern · Kindled growth | +50% XP and +40% Loam on the next-action quest; +5 XP for following advice (action cap applies) |
| Legendary | Ghost Orchid · Hidden riches | +25% XP and +60% Loam on all daily quests |
| Legendary | Golden Sprout · Golden age | +60% XP and +25% Loam on all daily quests |

### Seed Packets (gacha, in the Greenhouse)
Plants have equippable buffs; finishes and titles stay cosmetic. The catalog is `data/collectibles.dart` (40 items), and the rules are in `domain/gacha.dart` (pure, unit-tested):
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
- **Seed state:** 6-day streak (best 21) that becomes 7 on the first care action, 1 Lid Lock, 240 Loam, 2 crates + 1 Seed Packet, 2340 XP (Level 20 on the flat curve), no active seed until chosen.
- **Verdicts:** the app's `great` / `careful` / `avoid`; `careful` covers `add_with_browns` and `add_with_greens` (the `pairWith` list says which).
- **Web preview links:** `?tab=0-4`, `?scenario=tooWet`, `?checkin=1`, `?hour=0-24`, `?tab=2&item=banana_peel` (opens a verdict), `?greenhouse=1`, `?greenhouse=1&loam=2000&pull=10` (plays a 10-pull), `?source=mock|live`, `?drop=banana|check|mixed|unclear|nothing` (opens the drop-in with that fake detection).

**Demo script**
1. Home in `tooDry`. The plant droops, and the next action says "Add fresh scraps".
2. Tap **Drop something in** and drop a banana peel under the webcam. The pop-up appears with the photo and box, filling in "Banana peel · Green · Handful".
3. If it's wrong, correct the item and amount, then Submit. The saved compostable amount earns volume XP, with +15 more if it follows the next action (subject to the cap).
4. Switch to `tooWet` and drop another peel. Now it's **careful, add browns first**.
5. Open Sensors: the drop markers are on the chart, and today's streak day fills in.
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
1. ✅ Design system + **Home** (Bin World, HUD, What to add) + **Sensors**, **Log**, **Social**, **Profile** tabs.
2. ✅ **Drop-in UI** (sheet, "Is this right?" review, edit form, mixed drops), on mocks and the live API.
3. ✅ **Backend + Tiger Data** (ingest, readings, logs, drops, advice, game + economy) and **vision service** (webcam + motion + Gemini).
4. ✅ Greenhouse (Seed Packets, collection, equip) and crate reveals · next: Rewards inbox history.
5. ✅ `ApiRepository` (live bin data + server game/economy), durable demo progress, atomic retry-safe logging · next: real-phone/hardware validation and production authentication/signing.

### Reliability and remaining deployment limits
- Unknown/failed sensors stay unknown, omitted score terms are reweighted, uncalibrated moisture is labelled, and readings older than two minutes are stale. Current layer readings are kept separate; charts request their layer explicitly.
- `need` supports browns, greens, water, mix and nothing. No current top reading means no automatic material recommendation. Changing a rule threshold invalidates advice even if coarse sensor buckets match.
- A quiet new/dry bin is not ready. The readiness guide additionally requires recorded active/hot history at least 14 days old after the last harvest. This is a conservative product heuristic, **not a validation of compost maturity**.
- Serial samples receive a timestamp before queueing so retrying preserves capture time. A single background HTTP uploader keeps serial reads independent of network stalls and retries even without new serial input. The memory-only buffer holds 500 queued samples plus one in flight; full queues warn and drop incoming samples, and exit warns about unsent data. Vision opens the camera only for armed sessions, polls cancellation during watching, and clears its preview after the session.
- A recommendation is **not permission to log**: any catalog green/brown can be logged, including a `careful` verdict, earning volume XP without an unearned advice bonus. Manual verdict sheets scroll so the add button remains reachable with Android large-text accessibility settings. Hard keep-out materials remain a separate safety case.
- The Android demo still permits LAN HTTP and uses debug signing for release APKs. Scoped multiplayer accounts, friends and groups are implemented; production signing/deployment, background notifications, summary generation, rewards history and an embedded live webcam-preview workflow remain unfinished. Player-owned camera capture uses device-scoped vision authorization. Do not describe these as production-ready.
- Visual review: `cd app && flutter test test/visual_correction_test.dart --dart-define=CAPTURE_REVIEW=true` writes actual phone-sized Flutter renders to `artifacts/review/`. Detections are simulated and the missing photo is labelled; this is not a real Gemini/hardware accuracy test.

### Working together
- **`main` must always build and run.** Pull before you push; run `flutter analyze && flutter test` first.
- Small commits with clear messages: `feat(drop): confirm pop-up`, `fix(vision): ROI scaling`.
- One owner per folder (`app/features/x`, `backend/`, `vision/`, `firmware/`). Announce before touching `ui/` or `domain/`.
- If you change a token, rule, endpoint or mechanic, **update this file in the same commit**.

**Owners** (fill in names): Design system & app — ___ · Backend & Tiger — ___ · Vision & Gemini — ___ · Firmware & hardware — ___


## Multiplayer (integrated from `main`)

Social is now a persistent, authenticated feature, backed by `005_social.sql` and
`app/routers/social.py`. The former social league screen is an explicitly labelled
**demo league**, accessible from signed-out Social. The old friends/nudge demo is
not used for multiplayer.

- A person registers a unique username and password, then signs in on any device.
  Passwords use salted PBKDF2-SHA256 (600,000 rounds); session tokens are random,
  hashed in the database, expire after 30 days, and are kept in secure device storage.
  Authentication attempts are throttled in Postgres. Social does not use the shared app key.
- Profiles default to **private**. Names and usernames are searchable; activity,
  XP, levels, streaks, and care calendar require an accepted follow. Public profiles
  are optional. Follow requests can be accepted/declined, followers removed, and follows cancelled.
- Friend invite codes establish mutual approved follows. Group codes grant membership
  only, never access to private profile history. Codes expire in 7 days; issuing a new
  code rotates the old one. Codes are copied for the user to share; no messages are sent automatically.
- Private groups support up to 50 people, weekly/all-time leaderboards, shared ranks
  for tied XP, a team XP total, estimated composted kg and counted pieces/portions. Weekly boundaries are Sunday 00:00 UTC. Only owners
  create group invites, remove others, or delete the group. Members can leave; removals
  revoke existing invites. Each user can own up to 20 groups.
- Feed and profiles read actual `point_events`. Cheers are idempotent and award no XP.
  Scores are never uploaded by the phone. A check-in earns 5 XP once per UTC day,
  serialized to prevent duplicate concurrent rewards.
- Pairing a bin requires its device token; an existing player-owned bin cannot be claimed
  by another account. The app then reads that bin with its user session. Checking Sensors
  saves a check-in, and Log saves via `/social/care-log`: server rules determine advised
  additions/avoids, and selected compostable amounts earn 1 XP per 20 g under the same
  cumulative rounding and 60 XP action cap. Non-recommended compostables remain loggable.
  Requests use transaction receipts: identical retries return original XP; changed bodies
  conflict. Missing/stale sensors do not block logging or volume XP; only the advice
  bonus requires fresh readings. Before the first reading, the verdict sheet gives
  cautious rule-based advice with unknown sensor values. Hard keep-outs stay avoid.
- **Connection recovery:** signing in selects the account's bin, never silently claims the
  legacy demo bin. **Connect bin / Your bin** is directly available on Home (unpaired),
  Sensors (unpaired), Social, Profile settings, and the camera/photo flow. The shared
  connection screen accepts the device token and can recheck the server's saved pairing.
  Pairing from the webcam sheet resumes arming after success. Unpaired graphs show setup,
  not a network-error spinner. `/social/me` refreshes reconcile cached bin IDs without
  rebuilding the data repository when the assignment is unchanged. Failed refreshes and
  friend actions retain pairing; late responses cannot replace a newer account/pairing.
  Friend/group codes do not grant bin access; multi-account shared-bin access remains
  separate from the existing single-owner model.
- Legacy API-key routes cannot read or mutate registered players' private state or bins.
  Player sessions can read their owned bin and game, request advice or Trunc chat, and
  claim earned rewards or spend server balances. Demo harvest/log writes stay blocked;
  player care logs and check-ins still go through Social.
  Demo clients keep access to demo users and bins. Arduino ingestion is unchanged.
- In live account mode, Home/Greenhouse, Profile and Social share server-owned progression.
  Sensors displays that bin's saved additions, not seeded demo logs. Only explicit mock
  mode uses the local demo garden; those rewards never enter social rankings.
- UI uses `socialRepositoryProvider` and `socialDataProvider` as the social counterpart of
  `repositoryProvider`: no HTTP in screens. Visible social data refreshes every 20 seconds,
  after successful writes, and with manual refresh. Errors are shown with retry; no fake successes.
- Supported/tested Flutter SDK: **3.41.9** (Dart 3.11). See `MULTIPLAYER.md` for setup and checks.
- Account recovery, email invitations, push notifications and deployment are not implemented.
