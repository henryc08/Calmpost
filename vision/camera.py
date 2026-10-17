"""OpenCV capture from CAMERA_SOURCE: a webcam index, a video file, or a stream URL.

Only this module touches the camera, so swapping the laptop webcam for an
in-lid ESP32-CAM / Pi stream is a config change.
"""

import sys
import threading
import time

import cv2
import numpy as np


class Camera:
    """Reads frames on a background thread and always hands out the newest one.

    Without this, a slow consumer (a Gemini call) lets the driver buffer fill
    up and we'd be looking at frames from seconds ago.
    """

    def __init__(self, source: int | str, width: int = 1280, height: int = 720):
        self.source = source
        if isinstance(source, int) and sys.platform == "win32":
            self.cap = cv2.VideoCapture(source, cv2.CAP_DSHOW)  # opens much faster than MSMF
        else:
            self.cap = cv2.VideoCapture(source)
        if not self.cap.isOpened():
            raise RuntimeError(f"cannot open camera source {source!r}")
        if isinstance(source, int):
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        self.is_file = isinstance(source, str) and not source.startswith(("http", "rtsp"))
        self.fps = self.cap.get(cv2.CAP_PROP_FPS) or 30.0
        self._frame: np.ndarray | None = None
        self._seq = 0        # bumps on every new frame
        self._read_seq = 0   # last frame handed out
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self.ended = False
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _run(self) -> None:
        delay = 1.0 / self.fps if self.is_file else 0.0  # play files at real speed
        while not self._stop.is_set():
            ok, frame = self.cap.read()
            if not ok:
                if self.is_file:
                    self.ended = True
                    return
                time.sleep(0.05)
                continue
            with self._lock:
                self._frame = frame
                self._seq += 1
            if delay:
                time.sleep(delay)

    def read(self, timeout: float = 5.0) -> np.ndarray | None:
        """The newest frame not yet handed out (a copy), or None if none arrives within timeout.

        Waiting for a *new* frame matters: handing out the same frame twice
        would make the motion model see fake stillness.
        """
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            with self._lock:
                if self._frame is not None and self._seq != self._read_seq:
                    self._read_seq = self._seq
                    return self._frame.copy()
            if self.ended:
                return None
            time.sleep(0.01)
        return None

    def close(self) -> None:
        self._stop.set()
        self._thread.join(timeout=2)
        self.cap.release()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
