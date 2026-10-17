"""One-off: draw the bin-opening ROI over the camera view, saved to roi.json.

    python calibrate.py               # drag a box over the bin opening, then Enter
    python calibrate.py --source 1    # a different camera

Motion outside the ROI (people walking past, the lid) is ignored.
"""

import argparse

import cv2

from camera import Camera
from config import settings
from motion import Roi


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--source", default=None)
    args = p.parse_args()
    source = args.source if args.source is not None else settings.camera_source
    source = int(source) if isinstance(source, str) and source.isdigit() else source

    with Camera(source) as cam:
        frame = cam.read()
    if frame is None:
        raise SystemExit("no frame from the camera")

    x, y, w, h = cv2.selectROI("Drag a box over the bin opening, then press Enter", frame, showCrosshair=False)
    cv2.destroyAllWindows()
    if w == 0 or h == 0:
        raise SystemExit("no box drawn; roi.json unchanged")
    fh, fw = frame.shape[:2]
    roi = Roi(x / fw, y / fh, w / fw, h / fh)
    roi.save(settings.roi_path)
    print(f"saved {settings.roi_path.name}: {roi}")


if __name__ == "__main__":
    main()
