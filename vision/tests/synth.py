"""Synthetic "looking into the bin" footage for tests and dry runs.

A textured compost-coloured background; optionally a yellow banana-ish
shape falls in at `drop_at` seconds and comes to rest.
"""

import cv2
import numpy as np

W, H, FPS = 640, 480, 30


def background(seed: int = 7) -> np.ndarray:
    rng = np.random.default_rng(seed)
    base = np.full((H, W, 3), (40, 60, 85), np.uint8)  # brown, BGR
    noise = rng.integers(-25, 25, (H // 8, W // 8, 3))
    noise = cv2.resize(noise.astype(np.int16), (W, H), interpolation=cv2.INTER_CUBIC)
    img = np.clip(base.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    for _ in range(40):  # old scraps
        c = (int(rng.integers(0, W)), int(rng.integers(0, H)))
        cv2.circle(img, c, int(rng.integers(6, 18)), (30, int(rng.integers(50, 90)), 60), -1)
    return img


def frame_at(t: float, bg: np.ndarray, drop_at: float | None, fall_s: float = 0.6,
             sensor_noise: int = 3, seed: int = 0) -> np.ndarray:
    img = bg.copy()
    if drop_at is not None and t >= drop_at:
        p = min((t - drop_at) / fall_s, 1.0)
        cy = int(-40 + p * (H * 0.55 + 40))
        cx = W // 2 + 30
        cv2.ellipse(img, (cx, cy), (70, 22), 20, 0, 360, (40, 200, 235), -1)   # yellow peel
        cv2.ellipse(img, (cx, cy), (70, 22), 20, 0, 360, (20, 120, 150), 2)
        if p < 1.0:  # a hand comes in with it
            cv2.rectangle(img, (cx - 40, max(0, cy - 160)), (cx + 40, max(1, cy - 40)), (120, 160, 205), -1)
    if sensor_noise:
        rng = np.random.default_rng(int(t * 1000) + seed)
        img = np.clip(img.astype(np.int16) + rng.integers(-sensor_noise, sensor_noise + 1, img.shape), 0, 255)
        img = img.astype(np.uint8)
    return img


def write_clip(path: str, seconds: float, drop_at: float | None) -> None:
    bg = background()
    out = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), FPS, (W, H))
    for i in range(int(seconds * FPS)):
        out.write(frame_at(i / FPS, bg, drop_at))
    out.release()


class FakeCamera:
    """Frames on a simulated clock: each read() advances time by one frame."""

    def __init__(self, drop_at: float | None, fps: int = FPS, max_s: float = 120):
        self.bg = background()
        self.drop_at = drop_at
        self.fps = fps
        self.t = 0.0
        self.max_s = max_s

    def clock(self) -> float:
        return self.t

    def read(self, timeout: float = 5.0):
        if self.t > self.max_s:
            return None
        f = frame_at(self.t, self.bg, self.drop_at)
        self.t += 1 / self.fps
        return f
