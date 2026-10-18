"""Calmpost vision service: watch the bin while the app has armed the camera.

    python mock_backend.py        # until the real backend has /drops
    python main.py                # webcam from CAMERA_SOURCE, preview at :8081

    python main.py --console      # no backend: arm right away, print the result (build step 2)
    python main.py --source clip.mp4 --console --once

Frames are only captured while a session is armed; nothing is written to
disk unless --save-frames is passed.
"""

import argparse
import logging
import time
from datetime import datetime, timezone
from pathlib import Path

import cv2
import httpx

import frames as fr
from backend import Backend
from camera import Camera
from config import settings
from gemini import Identifier
from motion import MotionTrigger, Roi
from preview import PreviewState, serve
from watcher import Watcher

log = logging.getLogger("vision")
POLL_S = 1.0
ARM_WINDOW_S = 60.0


def save_frames(outcome, out_dir: Path) -> None:
    out_dir.mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    cv2.imwrite(str(out_dir / f"{stamp}-before.jpg"), outcome.before)
    after = outcome.after
    for d in outcome.result.items:
        if d.box_2d:
            after = fr.draw_box(after, d.box_2d, d.label)
    cv2.imwrite(str(out_dir / f"{stamp}-after.jpg"), after)


def describe(outcome) -> str:
    r = outcome.result
    if not r.ok:
        return f"Gemini failed ({r.error}); the app shows the photo with empty fields"
    if not r.items:
        return f"nothing new recognised ({r.latency_ms} ms)"
    parts = [f"{d.label} [{d.catalog_id} · {d.category or '?'} · {d.amount or '?'} · {d.confidence:.0%}]"
             for d in r.items]
    return f"{', '.join(parts)} ({r.latency_ms} ms)"


def run(args) -> None:
    roi = Roi.load(settings.roi_path)
    trigger = MotionTrigger(roi=roi)
    identifier = Identifier()
    backend = None if args.console else Backend()
    state = PreviewState(roi)
    if not args.no_preview:
        serve(state, settings.preview_port)
        log.info("preview at http://localhost:%d", settings.preview_port)

    def on_frame(frame, status, fraction):
        state.status, state.fraction = status, fraction
        state.push(frame)

    source = args.source if args.source is not None else settings.camera_source
    source = int(source) if isinstance(source, str) and source.isdigit() else source
    while True:
        try:
            if args.console:
                session_id, window = 'console', ARM_WINDOW_S
            else:
                session = backend.active_session()
                if session is None:
                    time.sleep(POLL_S)
                    continue
                session_id = session.id
                window = max(0.0, (session.expires_at - datetime.now(timezone.utc)).total_seconds())

            def still_armed():
                if backend is None: return True
                current = backend.active_session()
                return current is not None and current.id == session_id

            # Opening Camera starts its reader thread: do it ONLY while armed.
            with Camera(source) as cam:
                watcher = Watcher(cam, trigger, identifier, on_frame=on_frame, still_armed=still_armed)
                log.info('armed (session %s, %.0fs)', session_id, window)
                outcome = watcher.watch(window, hints=backend.hints() if backend else None)
                ended = cam.ended
            state.clear()
            if outcome.kind in ('camera_lost', 'cancelled'):
                log.info('session ended: %s', outcome.kind)
            elif outcome.kind == 'no_motion':
                state.status = 'nothing seen this session'
                if backend: backend.close_session(session_id, 'no_motion')
            else:
                log.info('drop: %s', describe(outcome))
                # Also put it on the preview: the watcher stops pushing
                # frames when it fires, so without this the result only ever
                # reached the terminal and the browser showed a dead feed.
                state.show_result(outcome.after, outcome.result.items,
                                  outcome.result.model, outcome.result.ok,
                                  outcome.result.latency_ms)
                if args.save_frames: save_frames(outcome, settings.thumbs_dir)
                if backend:
                    # Identical session reports are idempotent on the backend.
                    for attempt in range(3):
                        try:
                            resp = backend.report_drop(session_id, [d.to_dict() for d in outcome.result.items],
                                fr.thumbnail_b64(outcome.after), outcome.result.latency_ms,
                                outcome.result.ok, outcome.result.model, outcome.result.error)
                            log.info('reported as drop %s', resp.get('drop_id'))
                            break
                        except httpx.HTTPError:
                            if attempt == 2: raise
                            time.sleep(1)
            if args.once or ended: return
        except (httpx.HTTPError, RuntimeError, OSError) as e:
            state.clear()
            log.warning('camera/backend unavailable (%s); retrying', e)
            if args.once: return
            time.sleep(3)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--source", help="override CAMERA_SOURCE (webcam index, video file or stream URL)")
    p.add_argument("--console", action="store_true", help="no backend: arm immediately and print results")
    p.add_argument("--once", action="store_true", help="exit after one session")
    p.add_argument("--no-preview", action="store_true")
    p.add_argument("--save-frames", action="store_true", help="write before/after JPEGs to vision/thumbs/")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(name)s %(message)s", datefmt="%H:%M:%S")
    for noisy in ("httpx", "google_genai"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
    try:
        run(args)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
