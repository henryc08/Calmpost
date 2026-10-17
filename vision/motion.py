"""Motion trigger inside the bin-opening ROI.

Tuning from AGENT.md section 6: motion must cover > 2% of the ROI for at least
150 ms to start a drop, and the drop ends after 0.8 s of stillness. The
first 0.5 s after arming is ignored (the user's hand leaving the button).

Two different measurements, because "something arrived" and "nothing is
moving" are different questions:
  - fraction(): MOG2 background subtraction. Something is in the ROI that was
    not part of the scene. Blind to gradual lighting drift.
  - change():   difference from the previous frame. Nothing is moving now.

Judging stillness from the background fraction does not work: the model is
frozen during a drop, so an item at rest stays 'foreground' indefinitely.
"""

import json
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np

START_FRACTION = 0.02
START_HOLD_S = 0.15
STILL_S = 0.8
# Frame-to-frame change below this counts as still. Lower than
# START_FRACTION: arrival is measured against the background (a big, lasting
# difference), stillness against the previous frame (which goes to ~0).
STILL_FRACTION = 0.004
ARM_GRACE_S = 0.5
WORK_WIDTH = 320  # motion runs on a small copy: cheap, and less sensor noise


@dataclass
class Roi:
    """Normalised (0-1) rectangle over the bin opening."""
    x: float = 0.0
    y: float = 0.0
    w: float = 1.0
    h: float = 1.0

    def crop(self, frame: np.ndarray) -> np.ndarray:
        fh, fw = frame.shape[:2]
        x0, y0 = int(self.x * fw), int(self.y * fh)
        x1, y1 = int((self.x + self.w) * fw), int((self.y + self.h) * fh)
        return frame[y0:max(y1, y0 + 1), x0:max(x1, x0 + 1)]

    def pixels(self, frame: np.ndarray) -> tuple[int, int, int, int]:
        fh, fw = frame.shape[:2]
        return int(self.x * fw), int(self.y * fh), int(self.w * fw), int(self.h * fh)

    @classmethod
    def load(cls, path: Path) -> "Roi":
        if path.exists():
            d = json.loads(path.read_text())
            return cls(d["x"], d["y"], d["w"], d["h"])
        return cls()

    def save(self, path: Path) -> None:
        path.write_text(json.dumps({"x": self.x, "y": self.y, "w": self.w, "h": self.h}, indent=2))


@dataclass
class Event:
    kind: str          # "start" | "end"
    t: float           # seconds since arming
    fraction: float    # share of ROI pixels moving


@dataclass
class MotionTrigger:
    """Feed frames with timestamps; get 'start' and 'end' events back."""

    roi: Roi = field(default_factory=Roi)
    start_fraction: float = START_FRACTION
    start_hold_s: float = START_HOLD_S
    still_s: float = STILL_S
    still_fraction: float = STILL_FRACTION
    grace_s: float = ARM_GRACE_S

    def __post_init__(self):
        self.reset()

    def reset(self) -> None:
        self._bg = cv2.createBackgroundSubtractorMOG2(history=300, varThreshold=32, detectShadows=False)
        self._kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        self.active = False
        self._above_since: float | None = None
        self._still_since: float | None = None
        self._prev_gray: np.ndarray | None = None
        self.peak_fraction = 0.0
        self.last_fraction = 0.0
        self.last_change = 0.0

    def _gray(self, frame: np.ndarray) -> np.ndarray:
        roi = self.roi.crop(frame)
        scale = WORK_WIDTH / max(roi.shape[1], 1)
        small = cv2.resize(roi, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA) if scale < 1 else roi
        return cv2.GaussianBlur(cv2.cvtColor(small, cv2.COLOR_BGR2GRAY), (5, 5), 0)

    def fraction(self, frame: np.ndarray, learn: bool = True) -> float:
        """Share of ROI pixels that differ from the learned background.

        Good for deciding something has ARRIVED, and deliberately blind to
        gradual lighting drift. Not usable for deciding something has
        STOPPED: see change() for why.
        """
        gray = self._gray(frame)
        # Freeze the background model while something is moving, so a slow
        # drop isn't learned into the background halfway through.
        mask = self._bg.apply(gray, learningRate=-1 if learn else 0)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, self._kernel)
        return float(np.count_nonzero(mask)) / mask.size

    def change(self, frame: np.ndarray) -> float:
        """Share of ROI pixels that differ from the PREVIOUS frame.

        Stillness has to be measured frame-to-frame, not against the
        background. While a drop is active the background model is frozen, so
        an item resting in the ROI stays 'foreground' indefinitely and the
        background fraction never falls back under the threshold -- the end
        event would never fire and watcher.py's MAX_DROP_S timeout would have
        to rescue every drop. That only looked fine with a whole-frame ROI,
        where a small item sits just under the 2% threshold by luck; with the
        tight ROI calibrate.py produces, the item is a much larger share of
        the ROI and nothing ever ends.

        Frame differencing goes to ~0 the moment the item comes to rest,
        which is the actual question being asked.
        """
        gray = self._gray(frame)
        prev, self._prev_gray = self._prev_gray, gray
        if prev is None or prev.shape != gray.shape:
            return 0.0
        diff = cv2.absdiff(gray, prev)
        # 12 grey levels: above sensor noise, below a real moving object.
        moved = cv2.threshold(diff, 12, 255, cv2.THRESH_BINARY)[1]
        moved = cv2.morphologyEx(moved, cv2.MORPH_OPEN, self._kernel)
        return float(np.count_nonzero(moved)) / moved.size

    def update(self, frame: np.ndarray, t: float) -> Event | None:
        """t: seconds since the session was armed."""
        f = self.fraction(frame, learn=not self.active)
        c = self.change(frame)
        self.last_fraction = f
        self.last_change = c
        if t < self.grace_s:
            return None  # still learning the background; hand leaving the button

        if not self.active:
            # Arrival: something is in the ROI that was not in the background.
            if f > self.start_fraction:
                self._above_since = t if self._above_since is None else self._above_since
                if t - self._above_since >= self.start_hold_s:
                    self.active = True
                    self._still_since = None
                    self.peak_fraction = f
                    return Event("start", self._above_since, f)
            else:
                self._above_since = None
            return None

        self.peak_fraction = max(self.peak_fraction, f)
        # Stillness: nothing is MOVING any more, which is not the same as
        # nothing being there. Measured frame-to-frame (see change()).
        if c > self.still_fraction:
            self._still_since = None
        else:
            self._still_since = t if self._still_since is None else self._still_since
            if t - self._still_since >= self.still_s:
                self.active = False
                self._above_since = None
                return Event("end", t, f)
        return None
