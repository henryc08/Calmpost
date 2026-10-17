"""One armed session, start to finish:

    BEFORE frame → wait for motion to start → wait for 0.8 s of stillness
    → sharpest AFTER frame → Gemini → report the drop (or close quietly).

Kept separate from main.py so tests can drive it with a fake camera and clock.
"""

import asyncio
import logging
import time
from collections import deque
from dataclasses import dataclass
from typing import Callable, Protocol

import numpy as np

import frames as fr
from gemini import Identifier, Result
from motion import MotionTrigger

log = logging.getLogger(__name__)

AFTER_FRAMES = 6         # frames sampled after motion stops; the sharpest wins
MAX_DROP_S = 15.0        # someone leaning over the bin: give up waiting for stillness
BEFORE_MARGIN_S = 0.3    # BEFORE comes from this long before motion was first seen


class FrameSource(Protocol):
    def read(self, timeout: float = 5.0) -> np.ndarray | None: ...


@dataclass
class Outcome:
    kind: str                     # "drop" | "no_motion" | "camera_lost"
    result: Result | None = None
    before: np.ndarray | None = None
    after: np.ndarray | None = None
    motion_s: float = 0.0


class Watcher:
    def __init__(self, camera: FrameSource, trigger: MotionTrigger, identifier: Identifier,
                 clock: Callable[[], float] = time.monotonic, on_frame: Callable | None = None,
                 still_armed: Callable[[], bool] | None = None):
        self.camera = camera
        self.trigger = trigger
        self.identifier = identifier
        self.clock = clock
        self.on_frame = on_frame or (lambda frame, status, fraction: None)
        self.still_armed = still_armed or (lambda: True)

    def watch(self, window_s: float, hints: list[str] | None = None) -> Outcome:
        self.trigger.reset()
        t0 = self.clock()
        before = None
        started_at = None
        recent: deque = deque(maxlen=60)  # ~2 s of (t, frame) before motion
        next_check = 0.0

        while True:
            t = self.clock() - t0
            if t >= next_check:
                if not self.still_armed(): return Outcome('cancelled')
                next_check = t + 1.0
            frame = self.camera.read()
            if frame is None:
                return Outcome("camera_lost")
            ev = self.trigger.update(frame, t)
            status = "dropping…" if self.trigger.active else f"watching {max(0, window_s - t):.0f}s"
            self.on_frame(frame, status, self.trigger.last_fraction)

            if started_at is None and t >= self.trigger.grace_s:
                recent.append((t, frame))
            if ev and ev.kind == "start":
                started_at = t
                # BEFORE = a frame from just before motion first crossed the threshold.
                # Frames right at the threshold already show the item's edge coming in.
                cutoff = ev.t - BEFORE_MARGIN_S
                older = [f for ft, f in recent if ft <= cutoff]
                before = older[-1] if older else (recent[0][1] if recent else None)
                recent.clear()
                log.info("motion start at %.2fs (%.1f%% of ROI)", t, ev.fraction * 100)
            if ev and ev.kind == "end":
                log.info("motion end at %.2fs", t)
                break
            if started_at is not None and t - started_at > MAX_DROP_S:
                log.info("motion never settled; using the current frame")
                break
            if started_at is None and t >= window_s:
                return Outcome("no_motion")

        after_frames = [frame]
        for _ in range(AFTER_FRAMES - 1):
            f = self.camera.read()
            if f is not None:
                after_frames.append(f)
        after = fr.sharpest(after_frames)
        if before is None:
            before = after  # motion began during the grace period; best we have
        self.on_frame(after, "identifying…", 0.0)
        result = asyncio.run(self.identifier.identify(fr.jpeg(before), fr.jpeg(after), hints))
        # One item: box it from the pixel difference (exact) instead of Gemini's (drifts).
        # Several items: one changed region can't be split between them, so keep Gemini's.
        if len(result.items) == 1:
            local = fr.change_box(before, after, self.trigger.roi)
            if local:
                result.items[0].box_2d = local
        motion_s = (self.clock() - t0) - (started_at or 0.0)
        return Outcome("drop", result, before, after, motion_s)
