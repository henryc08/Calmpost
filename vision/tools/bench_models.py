"""Compare Gemini models on real saved drops: latency and whether the item
actually maps to the food catalog.

Run it once billing is enabled -- on the free tier it will exhaust a model's
daily allowance in a single pass.

    python tools/bench_models.py                       # default candidates
    python tools/bench_models.py --models a,b,c
    python tools/bench_models.py --runs 5 --side 640

Uses vision/thumbs/*-before.jpg + *-after.jpg, which main.py --save-frames
writes, so the comparison is on frames from your actual camera and lighting
rather than synthetic images.

What to look for, in order:
  1. catalog_id is a real id, not "unknown" -- a confident wrong label is
     worse than no label, because rules key the category off the id.
  2. p90 latency under BUDGET_S (gemini.py), or it times out in production.
  3. median latency: this is what the user waits after their hand clears.
"""

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

import cv2

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import catalog  # noqa: E402
from config import settings  # noqa: E402
from gemini import PROMPT, parse, schema  # noqa: E402
from google import genai  # noqa: E402
from google.genai import types  # noqa: E402

# Small, fast models first: identifying one scrap is not a reasoning task,
# and measurement so far has bigger models slower AND worse at mapping.
DEFAULT_MODELS = [
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-flash-latest",
    "gemini-flash-lite-latest",
]


def pairs(thumbs: Path) -> list[tuple[Path, Path]]:
    out = []
    for before in sorted(thumbs.glob("*-before.jpg")):
        after = before.with_name(before.name.replace("-before", "-after"))
        if after.exists():
            out.append((before, after))
    return out


def encode(path: Path, side: int, quality: int) -> bytes:
    img = cv2.imread(str(path))
    h, w = img.shape[:2]
    scale = side / max(h, w)
    if scale < 1:
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    return cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])[1].tobytes()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default=",".join(DEFAULT_MODELS))
    ap.add_argument("--runs", type=int, default=3, help="per model per image pair")
    ap.add_argument("--side", type=int, default=1024)
    ap.add_argument("--quality", type=int, default=85)
    ap.add_argument("--thumbs", default=str(Path(__file__).resolve().parent.parent / "thumbs"))
    args = ap.parse_args()

    samples = pairs(Path(args.thumbs))
    if not samples:
        print(f"no before/after pairs in {args.thumbs}")
        print("run: python main.py --console --save-frames   and drop something in")
        return 1

    ids = catalog.ids()
    cfg = types.GenerateContentConfig(
        response_mime_type="application/json",
        response_schema=schema(ids),
        temperature=0,
        media_resolution=types.MediaResolution.MEDIA_RESOLUTION_LOW,
        thinking_config=types.ThinkingConfig(thinking_budget=0),
    )
    prompt = PROMPT + "\nAllowed catalog ids:\n" + ", ".join(ids)
    client = genai.Client(api_key=settings.gemini_api_key)

    models = [m.strip() for m in args.models.split(",") if m.strip()]
    calls = len(models) * len(samples) * args.runs
    print(f"{len(samples)} drop(s) x {len(models)} model(s) x {args.runs} run(s) = {calls} calls")
    print(f"images at {args.side}px q{args.quality}\n")

    for model in models:
        times: list[float] = []
        labels: list[str] = []
        mapped = 0
        failed = 0
        for before, after in samples:
            bj, aj = encode(before, args.side, args.quality), encode(after, args.side, args.quality)
            parts = [
                types.Part.from_text(text="Image 1 (BEFORE):"),
                types.Part.from_bytes(data=bj, mime_type="image/jpeg"),
                types.Part.from_text(text="Image 2 (AFTER):"),
                types.Part.from_bytes(data=aj, mime_type="image/jpeg"),
                types.Part.from_text(text=prompt),
            ]
            for _ in range(args.runs):
                try:
                    t0 = time.perf_counter()
                    resp = client.models.generate_content(model=model, contents=parts, config=cfg)
                    times.append((time.perf_counter() - t0) * 1000)
                    items = parse(json.loads(resp.text))
                    if items:
                        labels.append(items[0].label)
                        if items[0].catalog_id != catalog.UNKNOWN:
                            mapped += 1
                    else:
                        labels.append("(nothing)")
                except Exception as exc:
                    failed += 1
                    msg = str(exc)
                    if "429" in msg:
                        print(f"  {model:28} QUOTA EXHAUSTED -- stopping this model")
                        break
                    labels.append(f"error: {msg[:60]}")
            else:
                continue
            break

        if not times:
            print(f"  {model:28} no successful calls\n")
            continue

        times.sort()
        p90 = times[min(len(times) - 1, int(len(times) * 0.9))]
        over = "  OVER BUDGET" if p90 > 4000 else ""
        print(f"  {model:28} median {statistics.median(times):6.0f} ms   "
              f"p90 {p90:6.0f} ms{over}")
        print(f"  {'':28} mapped to catalog {mapped}/{len(times)}   failures {failed}")
        print(f"  {'':28} labels: {sorted(set(labels))}\n")

    print("Pick the fastest model that maps reliably. A confident wrong label is")
    print("worse than 'unknown': the rules read the category off catalog_id.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
