"""Regenerate the backend's catalogs from the Flutter app, which owns them.

    python -m scripts.sync_catalogs            # from backend/

Writes app/catalog/food.py (from app/lib/data/food_catalog.dart) and
app/catalog/collectibles.py (from app/lib/data/collectibles.dart), and the
vision camera's label list, vision/catalog.json. tests/test_parity.py fails
if any of them drifts, so run this after editing a catalog in the app.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP_DATA = ROOT / "app" / "lib" / "data"
OUT = Path(__file__).resolve().parents[1] / "app" / "catalog"
VISION_CATALOG = ROOT / "vision" / "catalog.json"

STRING = r"'((?:[^'\\]|\\.)*)'"
TYPES = {"_s": "specimen", "_f": "finish", "_t": "title"}


def _calls(dart: str, name: str) -> list[str]:
    """Argument text of every `name(...)` call.

    Parentheses are matched (skipping string literals), so nested calls such
    as Color(...) and dart format's line wrapping are both handled.
    """
    bodies = []
    for m in re.finditer(r"\b" + name + r"\(", dart):
        depth, i, in_str = 1, m.end(), False
        while i < len(dart) and depth:
            ch = dart[i]
            if in_str:
                if ch == "\\":
                    i += 1
                elif ch == "'":
                    in_str = False
            elif ch == "'":
                in_str = True
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            i += 1
        bodies.append(dart[m.end() : i - 1])
    return bodies


def _field(body: str, name: str, pattern: str, default=None):
    m = re.search(r"\b" + name + r":\s*" + pattern, body)
    return m.group(1) if m else default


def _text(body: str, name: str, default: str | None = None) -> str | None:
    raw = _field(body, name, STRING, default)
    return raw.replace("\\'", "'") if raw is not None else None


def parse_food(dart: str) -> list[dict]:
    items = []
    for body in _calls(dart, "FoodItem"):
        if "id:" not in body:
            continue
        items.append(
            {
                "id": _text(body, "id"),
                "name": _text(body, "name"),
                "category": _field(body, "category", r"FoodCategory\.(\w+)"),
                "grams": float(_field(body, "grams", r"([\d.]+)")),
                "wet": _field(body, "wet", r"(true|false)", "false") == "true",
                "note": _text(body, "note", ""),
            }
        )
    return items


def parse_collectibles(dart: str) -> list[dict]:
    items = []
    for body in _calls(dart, "Collectible"):
        if "id:" not in body:
            continue
        argb = _field(body, "color", r"Color\(0x([0-9A-Fa-f]{8})\)")
        items.append(
            {
                "id": _text(body, "id"),
                "name": _text(body, "name"),
                "type": TYPES[_field(body, "type", r"(_\w)")],
                "rarity": _field(body, "rarity", r"Rarity\.(\w+)"),
                "color": "#" + argb[2:].upper(),
            }
        )
    return items


def render_food(items: list[dict]) -> str:
    rows = "\n".join(f"    {item!r}," for item in items)
    return f'''"""Food catalog -- GENERATED from app/lib/data/food_catalog.dart.

The app owns this list. Do not edit by hand: change the Dart file, then run
`python -m scripts.sync_catalogs`. tests/test_parity.py fails on drift.
"""

FOOD: list[dict] = [
{rows}
]

BY_ID: dict[str, dict] = {{f["id"]: f for f in FOOD}}
BY_NAME: dict[str, dict] = {{f["name"].lower(): f for f in FOOD}}


def lookup(text: str | None) -> dict | None:
    """A catalog item by id or name, case-insensitive."""
    if not text:
        return None
    t = text.strip().lower()
    return BY_ID.get(t) or BY_NAME.get(t) or BY_ID.get(t.replace(" ", "_"))
'''


def render_collectibles(items: list[dict]) -> str:
    rows = "\n".join(f"    {item!r}," for item in items)
    return f'''"""Seed Packet collectibles -- GENERATED from app/lib/data/collectibles.dart.

The app owns this list (names, icons, colours). Do not edit by hand: change
the Dart file, then run `python -m scripts.sync_catalogs`.
tests/test_parity.py fails on drift.

type: specimen (plant) | finish (recolours the Home health ring) | title
color: the plant's tint, or the ring colour for a finish
"""

COLLECTIBLES: list[dict] = [
{rows}
]

BY_ID: dict[str, dict] = {{c["id"]: c for c in COLLECTIBLES}}
'''


def vision_catalog(food: list[dict]) -> list[dict]:
    """The fields vision/ prompts Gemini with."""
    return [{k: f[k] for k in ("id", "name", "category", "grams")} for f in food]


def load() -> tuple[list[dict], list[dict]]:
    food = parse_food((APP_DATA / "food_catalog.dart").read_text(encoding="utf-8"))
    coll = parse_collectibles((APP_DATA / "collectibles.dart").read_text(encoding="utf-8"))
    return food, coll


def main() -> int:
    food, coll = load()
    if not food or not coll:
        print("could not parse the app catalogs", file=sys.stderr)
        return 1
    (OUT / "food.py").write_text(render_food(food), encoding="utf-8")
    (OUT / "collectibles.py").write_text(render_collectibles(coll), encoding="utf-8")
    if VISION_CATALOG.parent.exists():
        VISION_CATALOG.write_text(json.dumps(vision_catalog(food), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {len(food)} food items and {len(coll)} collectibles to {OUT} (and {VISION_CATALOG.name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
