# Calmpost app

The Flutter (Android-first) app for Calmpost. The repo-root `AGENTS.md` covers the design system, game rules and architecture.

```bash
flutter pub get
flutter run              # Android phone, mock bin
flutter run -d chrome    # browser preview (phone-sized frame)
flutter test
```

## The real bin

The app reads the real bin through the backend. It never connects to Tiger Data and never holds the database URL or the Gemini key.

```
board ──USB──▶ serial_bridge.py ──POST /ingest──▶ FastAPI ──▶ Tiger Cloud
                                                     ▲
                       app: GET /bins/bin-001/live every 3 s (ApiRepository)
```

1. On the laptop, start the API (`backend/README.md`) bound to the network: `uvicorn app.main:app --host 0.0.0.0 --port 8000`. Start the serial bridge too, or readings go stale.
2. Find the laptop's LAN address with `ipconfig` (e.g. `192.168.1.42`). Put the phone on the same network; a phone hotspot is the reliable choice, because campus Wi-Fi often blocks device-to-device traffic.
3. Build with the address and the app key (`APP_API_KEY` from `backend/.env`):

```bash
flutter run --dart-define=API_URL=http://192.168.1.42:8000 --dart-define=API_KEY=<APP_API_KEY>
flutter build apk --release --dart-define=API_URL=http://192.168.1.42:8000 --dart-define=API_KEY=<APP_API_KEY>
```

The values are compiled in, not committed. Without `API_URL` the app runs on the mock bin.

What comes from the backend:
- live readings
- 24 h trends
- the scrap-check verdict (Gemini wording, rules decide)
- the add log
- the league table

Suggestions and the catalog use the app's own rules. Live XP, Loam, quests, crates, Seed Packets, equipment and Lid Locks now use the server economy. Demo progression is separately persisted on-device. Confirmed compostable volume earns 1 XP per 20 g (rounded cumulatively per day), plus care bonuses, within the shared 60 XP daily action cap.

The camera button arms the **bin camera**, not the phone camera. There is no in-app live preview yet. Existing pending drops are recovered, and users correct the item/type/amount before saving. Logging failures remain visible; identical retries do not duplicate saved additions.

These are demo APKs: LAN HTTP, debug release signing and a shared API key are not production security. Validate on a physical Android device before distribution.

Honest about the hardware:
- **Independent probes.** Probe 2 can report bottom moisture without temperature. Missing values stay **not measured**; bottom-layer historical charts are not available yet. Each probe needs its own calibration.
- **Stale readings.** If the bin stops reporting, "LIVE" becomes "SEEN 20 MIN AGO".
- **Unreachable backend.** If the phone can't reach the API, Home says so and offers **Use demo data**.

Check the connection from a laptop: `flutter test test/live_api_test.dart --dart-define=API_URL=http://127.0.0.1:8000 --dart-define=API_KEY=<APP_API_KEY>` reads the live bin, trends, a verdict and the league through the app's own `ApiRepository`.

## Demo controls

Long-press the Bin World on Home to open the demo picker:
- **Live bin**, when built with `API_URL`.
- The mock scenarios: healthy, too wet, too dry, curing and ready. Use them if the venue network drops.

Web preview links (also `?source=mock|live`) are listed in the agent doc, section 9.

### Assistant, phone photos, history and calibration

- **Home or Log → Ask Trunc:** in-memory conversation, waiting/retry states and the actual sensor/photo context. Ask `test fallback` for a normal rule-based response, or an unrelated question for the redirect. Recent photos are opt-in.
- **Log → Take or choose a photo:** Android camera or gallery, local preview, then **Identify and review**. The JPEG is resized to at most 1024 px and 1.4 MB. The existing correction sheet confirms what was actually composted; identification alone never logs an add. Interrupted Android capture can restore a preview without uploading it.
- **Log → Past drops & photos:** confirmed/dismissed records, original guesses beside corrections, and stored photos. Photos are authenticated and may expire. A freshly started mock repository has no history until you confirm or dismiss a drop.
- **Layers or Profile → Calibrate probes:** choose top/probe 1 or bottom/probe 2, record separate dry/wet raw counts, then save. Historical recalculation is off unless selected. Live calibration requires the paired owner; demo mode saves references in memory without changing physical sensors.

All four screens work in mock mode without Gemini credentials. Real photo identification and AI wording require backend Gemini quota; identification failure still offers manual review and Trunc still supplies rule-based fallback. Mock history and chat do not survive app restart; live drop history is stored by the backend.

Render actual Flutter screenshots with `flutter test test/ui_features_visual_test.dart --dart-define=CAPTURE_REVIEW=true`; output is in `artifacts/ui-features/` at the repository root.

### Compost inventory

Open **Compost inventory** in Log or Profile for grouped item counts, estimated
weight, green/brown totals and weekly/all-time history. Camera/photo review and
manual logging include editable pieces/portions and **total** weight; a count
change does not multiply grams. Only confirmed compostable additions count.
Older logs without counts remain labelled as such.

Live inventory and group rankings show the server's amount XP + care/reward XP
breakdown. The sensor-based health score stays separate. Demo inventory works
without a backend and lasts for the mock repository session.

### Materials & help

Social → Groups → a private group → **Materials & help** opens requests and offers.
Choose compostable scraps/browns, finished compost or turning/harvesting help, then
specify an amount/help description. Another member reserves; only the participants
see arrangement notes. Both confirm completion before the server awards up to 10 XP
each. **How XP works** explains the 20 exchange XP/day, one reward per pair/day and
shared 60 action XP/day limits. Received material is logged separately when composted.

The board has active/mine/history filters, pagination, manual and periodic refresh,
release/cancel actions, and retryable errors. Exchange uses the existing authenticated
SocialRepository boundary; signed-out demo activity never awards multiplayer XP.
