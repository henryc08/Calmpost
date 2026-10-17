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
        live = (40, 160, 230)
        idle = (200, 200, 200)
        cv2.rectangle(out, (x, y), (x + w, y + h), live if moving else idle, 2)
        if self.last_box:
            out = fr.draw_box(out, *self.last_box)

        # The overlay is drawn before the frame is scaled to 960 wide, so
        # sizes are relative to the source frame: a 640px webcam and a 1080p
        # one end up with the same apparent text size in the browser.
        s = max(out.shape[1] / 960.0, 0.75)
        font = cv2.FONT_HERSHEY_SIMPLEX
        scale = 0.72 * s
        thick = max(1, round(2 * s))
        pad = round(12 * s)
        line = round(30 * s)

        rows = [
            self.status,
            f"motion {self.fraction * 100:5.1f}%   trigger {self.threshold * 100:.1f}%",
        ]
        if self.last_box:
            rows.append(f"last: {self.last_box[1]}")

        bar_w, bar_h = round(300 * s), round(16 * s)
        panel_h = pad + len(rows) * line + bar_h + pad
        panel_w = max(bar_w, *(cv2.getTextSize(r, font, scale, thick)[0][0] for r in rows)) + pad * 2

        # Dark panel behind the text: white-on-white was unreadable against a
        # bright desk, which is exactly the background the camera looks at.
        panel = out[0:panel_h, 0:panel_w]
        if panel.size:
            out[0:panel_h, 0:panel_w] = cv2.addWeighted(
                panel, 0.35, np.zeros_like(panel), 0.65, 0
            )

        yy = pad + round(line * 0.75)
        for row in rows:
            cv2.putText(out, row, (pad, yy), font, scale, (255, 255, 255), thick, cv2.LINE_AA)
            yy += line

        # Motion bar, with the trigger threshold marked so you can see how
        # close you are rather than guessing from a bare bar.
        bx, by = pad, yy - round(line * 0.55)
        full = min(self.fraction / (self.threshold * 4), 1.0)
        cv2.rectangle(out, (bx, by), (bx + bar_w, by + bar_h), (90, 90, 90), -1)
        cv2.rectangle(out, (bx, by), (bx + int(bar_w * full), by + bar_h),
                      live if moving else (180, 180, 180), -1)
        tick = bx + bar_w // 4           # the threshold sits at a quarter of full scale
        cv2.line(out, (tick, by - round(3 * s)), (tick, by + bar_h + round(3 * s)),
                 (255, 255, 255), max(1, round(s)), cv2.LINE_AA)

        ok, buf = cv2.imencode(".jpg", fr.resize_max(out, 960), [cv2.IMWRITE_JPEG_QUALITY, 70])
        if ok:
            with self._lock:
                self._jpeg = buf.tobytes()

    def jpeg(self) -> bytes | None:
        with self._lock:
            return self._jpeg

    def clear(self) -> None:
        with self._lock:
            self._jpeg = None
        self.last_box = None
        self.status = 'idle: not armed'


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
