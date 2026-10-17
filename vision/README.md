# Calmpost vision service

The camera half of **camera drop-in** (CLAUDE.md 2.4 and section 6). A small Python process on the
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
python mock_backend.py       # until backend/ has /drops (http://localhost:8090 plays the app's part)
python main.py               # webcam + preview at http://localhost:8081
```

Open http://localhost:8090, press **Drop something in** and drop a scrap under the camera. The pop-up
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
| `motion.py` | MOG2 background subtraction in the ROI. A drop starts at >2% of the ROI for 150 ms and ends after 0.8 s still; the first 0.5 s after arming is ignored |
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
- **Gemini failure never blocks the flow.** With no key, a bad key, a timeout over 4 s, or bad JSON, the drop is still reported with `gemini_ok: false` and no items. The app then shows the photo with empty fields, as in CLAUDE.md.
- **Hands and utensils are ignored.** A hand-only detection is not a drop.
- **Privacy.** Frames are only processed while a session is armed. Nothing goes to disk unless `--save-frames` is set. The backend gets a 320 px thumbnail.

## Endpoints the backend needs

Implemented by `mock_backend.py`. The routes are from CLAUDE.md section 4, plus three small additions marked *new*.

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

Each item has the shape `{label, catalog_id, category, est_grams, amount: small|handful|large, confidence 0-1, box_2d: [ymin, xmin, ymax, xmax] on 0-1000}`.
The vision service sends `X-API-Key: $APP_API_KEY` when it's set.

## Tests

```bash
pytest     # 20 tests: motion trigger, frames, catalog/Gemini validation, watcher, backend client vs mock
```

They use synthetic footage (`tests/synth.py`): a textured bin, with a yellow peel and a hand falling in. No webcam or Gemini key is needed.
