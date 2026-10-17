# Camera drop-in endpoints

Backend side of CLAUDE.md 2.4. The `vision/` service watches the bin and reports what went in. The app shows
"Something was added" and the user confirms it. All routes need `X-API-Key` (the vision service sends
`APP_API_KEY` too).

```
App     POST /bins/{id}/drops/session            arm the camera for 60 s
vision  GET  /bins/{id}/drops/session/active     poll: 204 = not armed
vision  POST /bins/{id}/drops                    report a detection -> pending
vision  POST /bins/{id}/drops/session/{sid}/close   saw nothing ("Didn't see anything")
App     GET  /bins/{id}/drops/stream             SSE, one `drop` event per pending detection
App     GET  /bins/{id}/drops/pending            polling fallback
App     POST /drops/{id}/confirm                 -> add_log rows (source='camera') + verdict + XP
App     POST /drops/{id}/dismiss                 "Nothing was added"
App     GET  /bins/{id}/drops/sessions/{sid}     is the sheet still watching?
        GET  /bins/{id}/drops/hints              recent corrections, fed back to Gemini
        GET  /bins/{id}/drops/accuracy           camera accuracy stat
```

## Confirm

```json
POST /drops/42/confirm
{"items": [{"label": "banana peel", "catalog_id": "banana_peel", "category": "green",
            "amount": "handful", "was_advised": false, "removed": false}]}
```

- Each item goes through `POST /bins/{id}/logs` logic with `source="camera"`, so XP follows the normal rules:
  - 0 for adding an item
  - +15 with `was_advised` (it was the next best action)
  - +5 with `removed` (the user took a keep-out item back out; logged as a skip)
- `amount` maps to grams: small 40, handful 110, large 250.
- The response carries each item's `log` and its scrap-check `verdict` (from `/advice/check`). The verdict is `null` if the bin has no readings yet.
- Confirming twice returns 409, so a double-tap can't log a drop twice.

## Rules over the camera

On both report and confirm, a label that `compost.avoid_reason` flags is always `avoid`, whatever the camera
or the user's edit said. Otherwise the category the camera took from the app's catalog is kept, and a missing one
is filled in by `compost.categorise`.

## Tables (`sql/drops.sql`, applied after `schema.sql` on boot)

- **`drop_sessions`:** one row per arming, with `close_reason` set to `no_motion`, `reported` or `replaced`.
- **`drop_events`:** a hypertable of every detection.
  - What the model saw: `guess`, plus `gemini_ok`, `latency_ms` and the thumbnail (`bytea`, at most 200 KB).
  - What the user confirmed: `final_items` and `corrected`.
  - **Retention is 30 days**, because the photos are personal.
- **`vision_accuracy_1d`:** a continuous aggregate with drops, confirmed, confirmed-as-seen, dismissed, average confidence and average latency.
- **`add_log`:** gains a `drop_id` column, and `source` now also allows `'camera'`.

## Tests

```bash
pip install pytest
TEST_DATABASE_URL=postgresql://postgres@localhost/throwaway pytest    # WIPES that database
```

There are 15 tests. They run on plain Postgres, skipping the TimescaleDB-only statements, so the hypertable,
the aggregate and the retention policy are only exercised on Tiger Cloud.
