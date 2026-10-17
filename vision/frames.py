"""Frame helpers: sharpest-frame pick, resize, JPEG encode, thumbnails."""

import base64

import cv2
import numpy as np

MAX_SIDE = 1024      # what Gemini gets (CLAUDE.md: <= 1024 px)
THUMB_SIDE = 320     # what the app's pop-up shows


def sharpness(frame: np.ndarray) -> float:
    """Variance of the Laplacian: higher = sharper, low = motion blur."""
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def sharpest(frames: list[np.ndarray]) -> np.ndarray:
    if not frames:
        raise ValueError("no frames")
    return max(frames, key=sharpness)


def resize_max(frame: np.ndarray, side: int = MAX_SIDE) -> np.ndarray:
    h, w = frame.shape[:2]
    scale = side / max(h, w)
    if scale >= 1:
        return frame
    return cv2.resize(frame, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)


def jpeg(frame: np.ndarray, side: int = MAX_SIDE, quality: int = 85) -> bytes:
    ok, buf = cv2.imencode(".jpg", resize_max(frame, side), [cv2.IMWRITE_JPEG_QUALITY, quality])
    if not ok:
        raise RuntimeError("JPEG encode failed")
    return buf.tobytes()


def thumbnail_b64(frame: np.ndarray) -> str:
    return base64.b64encode(jpeg(frame, THUMB_SIDE, 75)).decode()


def draw_box(frame: np.ndarray, box_2d: list[int], label: str) -> np.ndarray:
    """box_2d is Gemini's [ymin, xmin, ymax, xmax] on a 0-1000 scale."""
    out = frame.copy()
    h, w = out.shape[:2]
    y0, x0, y1, x1 = box_2d
    p0 = (int(x0 / 1000 * w), int(y0 / 1000 * h))
    p1 = (int(x1 / 1000 * w), int(y1 / 1000 * h))
    forest = (95, 138, 63)  # BGR of the app's forest green #3F8A5F
    cv2.rectangle(out, p0, p1, forest, 3)
    cv2.putText(out, label, (p0[0], max(p0[1] - 8, 16)), cv2.FONT_HERSHEY_SIMPLEX, 0.6, forest, 2, cv2.LINE_AA)
    return out
