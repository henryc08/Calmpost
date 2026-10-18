# Calmpost vision service

The camera half of **camera drop-in** (AGENTS.md 2.4 and section 6). A small Python process on the
laptop next to the bin:

1. Polls the backend for a session the app has armed ("Drop something in", 60 s).
2. Keeps the last still frame as **BEFORE**.
3. Uses OpenCV motion detection inside the bin-opening ROI to see something go in.
4. After 0.8 s of stillness, picks the sharpest **AFTER** frame.
5. Asks Gemini Flash what is new in AFTER: `label`, `catalog_id`, grams, confidence and box.
6. Reports the drop to the backend. The app then shows "Something was added" for the user to confirm.

OpenCV decides **when**, Gemini decides **what**: one image request per drop, with no video streaming.

## Run

```bash
cd vision
py -3.12 -m venv .venv && .venv/Scripts/activate       # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env                                    # add GEMINI_API_KEY (and APP_API_KEY for the real backend)

python calibrate.py          # once: drag a box over the bin opening -> roi.json
python mock_backend.py       # only without the real backend (http://localhost:8090 plays the app's part)
python main.py               # webcam + preview at http://localhost:8081
```

With the real backend instead, set `BACKEND_URL=http://localhost:8000` and `APP_API_KEY` in `.env`, run
`uvicorn app.main:app --port 8000` in `backend/`, and arm a session from the app (or `POST /bins/bin-001/drops/session`).
`catalog.json` is generated from the app's food catalog by `backend/scripts/sync_catalogs.py`; don't edit it by hand.

With the mock: open http://localhost:8090, press **Drop something in** and drop a scrap under the camera. The pop-up
data (photo, item, type, amount, confidence) appears there within a couple of seconds.

Other modes:

```bash
python main.py --console                          # no backend: arm right away, print the result
python main.py --source clip.mp4 --once           # a recorded clip instead of the webcam
python main.py --save-frames                      # also write before/after JPEGs to vision/thumbs/
```

## Files

| File | What it does |
|---|---|
| `main.py` | Poll for an armed session, then watch, identify and report, in a loop |
| `watcher.py` | One session: BEFORE frame, motion start/end, sharpest AFTER frame, Gemini call |
| `camera.py` | OpenCV capture from `CAMERA_SOURCE` (webcam index, file or stream URL) on a background thread |
| `motion.py` | MOG2 background subtraction in the ROI. A drop starts at >1% of the ROI for 150 ms and ends after 0.55 s still; the first 0.5 s after arming is ignored |
| `frames.py` | Sharpest frame (Laplacian variance), resize to ≤1024 px, JPEG, thumbnails, box drawing |
| `gemini.py` | Before/after prompt, JSON schema with catalog ids as an enum, 4 s budget, validation |
| `catalog.py` / `catalog.json` | The app's food catalog. **Category comes from here, never from Gemini** |
| `backend.py` | Client for the `/drops` endpoints |
| `mock_backend.py` | In-memory stand-in for those endpoints, plus a tiny app-like page |
| `preview.py` | MJPEG preview with ROI, motion level, state and detection box |
| `calibrate.py` | Draw the ROI once |
| `tools/sync_catalog.py` | Regenerate `catalog.json` from `app/lib/data/food_catalog.dart` |

## Guarantees

- **Hard-avoid items can't slip through.** Gemini only picks a `catalog_id` from the enum. The category (green / brown / avoid) is looked up from the catalog, both here and again in the mock backend. Unknown ids become `unknown` with no category, and the user picks one.
- **Gemini failure never blocks the flow.** With no key, a bad key, a timeout over 4 s, or bad JSON, the drop is still reported with `gemini_ok: false` and no items. The app then asks "What went in?" with the photo, as in AGENTS.md.
- **A mix it can't separate is said, not guessed.** The prompt asks for one `mixed_scraps` item (plus any keep-out food it can see) and a low confidence for anything unclear. The app always asks "Is this right?" before logging, so a confident mistake is one tap to fix.
- **Hands and utensils are ignored.** A hand-only detection is not a drop.
- **Privacy.** Frames are only processed while a session is armed. Nothing goes to disk unless `--save-frames` is set. The backend gets a 320 px thumbnail.

## Endpoints the backend needs

Implemented by `mock_backend.py`. The routes are from AGENTS.md section 4, plus three small additions marked *new*.

| Method | Path | Called by | Body → response |
|---|---|---|---|
| POST | `/bins/{id}/drops/session` | app | → `{session_id, expires_at}` (arms for 60 s, replaces an older one) |
| GET | `/bins/{id}/drops/session/active` | vision | → `{session_id, expires_at}` or `204` |
| POST | `/bins/{id}/drops` | vision | `{session_id, items[], thumbnail_jpeg_b64, latency_ms, gemini_ok, model, error}` → `{drop_id, status: "pending"}` |
| POST | `/bins/{id}/drops/session/{sid}/close` | vision | *new* `{reason: "no_motion"}`: "Didn't see anything" |
| GET | `/bins/{id}/drops/pending` | app | pending drops (polling fallback) |
| GET | `/bins/{id}/drops/stream` | app | SSE, one `drop` event per new pending drop |
| POST | `/drops/{id}/confirm` | app | `{items: [{label, catalog_id, category, amount}]}` → the real backend writes `add_log` (`source='camera'`) and returns the verdict |
| POST | `/drops/{id}/dismiss` | app | "Nothing was added" |
| GET | `/bins/{id}/drops/hints` | vision | *new*, optional: recent corrections fed back to Gemini |

Each item has the shape `{label, catalog_id, category, piece_count (optional), est_grams, amount: small|handful|large, confidence 0-1, box_2d: [ymin, xmin, ymax, xmax] on 0-1000}`.
The vision service sends `X-Device-Token: $DEVICE_TOKEN` for player-owned bins, or `X-API-Key: $APP_API_KEY` for demo bins.

## Tests

```bash
pytest     # 23 tests: motion trigger, frames, catalog/Gemini validation, watcher, backend client vs mock
```

They use synthetic footage (`tests/synth.py`): a textured bin, with a yellow peel and a hand falling in. No webcam or Gemini key is needed.

### Inventory counts and player-owned bins

Vision groups identical new scraps into rows and proposes optional `piece_count`
alongside the total `est_grams`. Uncountable material has no model count; the app
asks the user to review pieces/portions and total weight before saving. No guess
counts as compost until confirmed, and original guesses are retained separately.

For a player-owned bin, set `DEVICE_TOKEN` in `vision/.env` to that bin's device
token. The client sends `X-Device-Token`, scoped to active sessions, reports,
closing sessions and correction hints. `APP_API_KEY` remains the demo fallback.
The service cannot confirm detections or read the user's inventory.
