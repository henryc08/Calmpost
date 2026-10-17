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
- **One probe.** The bin has one probe, in the top layer, so the bottom shows **not measured** (never a number) and the health score leaves it out.
- **Stale readings.** If the bin stops reporting, "LIVE" becomes "SEEN 20 MIN AGO".
- **Unreachable backend.** If the phone can't reach the API, Home says so and offers **Use demo data**.

Check the connection from a laptop: `flutter test test/live_api_test.dart --dart-define=API_URL=http://127.0.0.1:8000 --dart-define=API_KEY=<APP_API_KEY>` reads the live bin, trends, a verdict and the league through the app's own `ApiRepository`.

## Demo controls

Long-press the Bin World on Home to open the demo picker:
- **Live bin**, when built with `API_URL`.
- The mock scenarios: healthy, too wet, too dry, curing and ready. Use them if the venue network drops.

Web preview links (also `?source=mock|live`) are listed in the agent doc, section 9.
