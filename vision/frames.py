"""Frame helpers: sharpest-frame pick, resize, JPEG encode, thumbnails."""

import base64

import cv2
import numpy as np

MAX_SIDE = 1024      # what Gemini gets (AGENT.md: <= 1024 px)
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


def change_box(before: np.ndarray, after: np.ndarray, roi=None, min_area: float = 0.002,
               max_area: float = 0.6) -> list[int] | None:
    """Box around what changed between BEFORE and AFTER, as [ymin, xmin, ymax, xmax] on 0-1000.

    Gemini's boxes drift a lot (IoU 0-0.4 in testing, even at temperature 0);
    the pixel difference is exact for a single drop. Returns None when the
    change is tiny (nothing landed) or huge (lighting shift, camera bumped),
    so the caller can fall back to Gemini's box.
    """
    if before.shape != after.shape:
        return None
    h, w = after.shape[:2]
    x0, y0, rw, rh = roi.pixels(after) if roi else (0, 0, w, h)
    b = cv2.GaussianBlur(before[y0:y0 + rh, x0:x0 + rw], (7, 7), 0).astype(np.int16)
    a = cv2.GaussianBlur(after[y0:y0 + rh, x0:x0 + rw], (7, 7), 0).astype(np.int16)
    diff = np.abs(a - b).max(axis=2).astype(np.uint8)
    _, mask = cv2.threshold(diff, 35, 255, cv2.THRESH_BINARY)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask = cv2.morphologyEx(cv2.morphologyEx(mask, cv2.MORPH_OPEN, k), cv2.MORPH_CLOSE, k, iterations=2)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    big = [c for c in contours if cv2.contourArea(c) >= min_area * rw * rh]
    if not big:
        return None
    bx, by, bw, bh = cv2.boundingRect(np.vstack(big))
    if bw * bh > max_area * rw * rh:
        return None
    return [int((y0 + by) / h * 1000), int((x0 + bx) / w * 1000),
            int((y0 + by + bh) / h * 1000), int((x0 + bx + bw) / w * 1000)]


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
