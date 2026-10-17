"""Optional MJPEG preview at http://localhost:8081 for the demo screen.

Shows the camera, the bin-opening ROI, the live motion level, the watcher's
state and the last detection box. Judges can watch the trigger fire.
"""

import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2
import numpy as np

import frames as fr
from motion import Roi


class PreviewState:
    def __init__(self, roi: Roi):
        self.roi = roi
        self._lock = threading.Lock()
        self._jpeg: bytes | None = None
        self.status = "idle"
        self.fraction = 0.0
        self.threshold = 0.02
        self.last_box: tuple[list[int], str] | None = None

    def push(self, frame: np.ndarray) -> None:
        out = frame.copy()
        x, y, w, h = self.roi.pixels(out)
        moving = self.fraction > self.threshold
        cv2.rectangle(out, (x, y), (x + w, y + h), (40, 160, 230) if moving else (200, 200, 200), 2)
        if self.last_box:
            out = fr.draw_box(out, *self.last_box)
        bar = int(min(self.fraction / (self.threshold * 4), 1.0) * 200)
        cv2.rectangle(out, (12, 12), (212, 26), (60, 60, 60), 1)
        cv2.rectangle(out, (12, 12), (12 + bar, 26), (40, 160, 230) if moving else (180, 180, 180), -1)
        cv2.putText(out, self.status, (12, 48), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2, cv2.LINE_AA)
        ok, buf = cv2.imencode(".jpg", fr.resize_max(out, 960), [cv2.IMWRITE_JPEG_QUALITY, 70])
        if ok:
            with self._lock:
                self._jpeg = buf.tobytes()

    def jpeg(self) -> bytes | None:
        with self._lock:
            return self._jpeg


def serve(state: PreviewState, port: int) -> ThreadingHTTPServer:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            if self.path == "/":
                body = b'<!doctype html><title>Calmpost camera</title><body style="margin:0;background:#111">' \
                       b'<img src="/stream" style="width:100%">'
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(body)
                return
            if self.path != "/stream":
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.end_headers()
            try:
                while True:
                    jpg = state.jpeg()
                    if jpg:
                        self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\n\r\n" + jpg + b"\r\n")
                    time.sleep(1 / 15)
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
