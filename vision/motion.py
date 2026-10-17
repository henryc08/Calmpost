"""Motion trigger inside the bin-opening ROI (MOG2 background subtraction).

Tuning from CLAUDE.md section 6: motion must cover > 2% of the ROI for at least
150 ms to start a drop, and the drop ends after 0.8 s of stillness. The
first 0.5 s after arming is ignored (the user's hand leaving the button).
"""

import json
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np

START_FRACTION = 0.02
START_HOLD_S = 0.15
STILL_S = 0.8
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
    grace_s: float = ARM_GRACE_S

    def __post_init__(self):
        self.reset()

    def reset(self) -> None:
        self._bg = cv2.createBackgroundSubtractorMOG2(history=300, varThreshold=32, detectShadows=False)
        self._kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        self.active = False
        self._above_since: float | None = None
        self._still_since: float | None = None
        self.peak_fraction = 0.0
        self.last_fraction = 0.0

    def fraction(self, frame: np.ndarray, learn: bool = True) -> float:
        roi = self.roi.crop(frame)
        scale = WORK_WIDTH / max(roi.shape[1], 1)
        small = cv2.resize(roi, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA) if scale < 1 else roi
        gray = cv2.GaussianBlur(cv2.cvtColor(small, cv2.COLOR_BGR2GRAY), (5, 5), 0)
        # Freeze the background model while something is moving, so a slow
        # drop isn't learned into the background halfway through.
        mask = self._bg.apply(gray, learningRate=-1 if learn else 0)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, self._kernel)
        return float(np.count_nonzero(mask)) / mask.size

    def update(self, frame: np.ndarray, t: float) -> Event | None:
        """t: seconds since the session was armed."""
        f = self.fraction(frame, learn=not self.active)
        self.last_fraction = f
        if t < self.grace_s:
            return None  # still learning the background; hand leaving the button
        moving = f > self.start_fraction

        if not self.active:
            if moving:
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
        if moving:
            self._still_since = None
        else:
            self._still_since = t if self._still_since is None else self._still_since
            if t - self._still_since >= self.still_s:
                self.active = False
                self._above_since = None
                return Event("end", t, f)
        return None
