"""Regenerate vision/catalog.json from the app's food catalog.

    python tools/sync_catalog.py ../app/lib/data/food_catalog.dart
    git show origin/frontend:app/lib/data/food_catalog.dart | python tools/sync_catalog.py -

The app's catalog is the source of truth; Gemini's `catalog_id` must be one
of these ids (or "unknown"), so re-run this whenever the catalog changes.
"""

import json
import re
import sys
from pathlib import Path

ITEM = re.compile(r"FoodItem\((.*?)\)\s*,", re.S)
FIELD = {
    "id": re.compile(r"id:\s*'([^']+)'"),
    "name": re.compile(r"name:\s*'((?:[^'\\]|\\.)+)'"),
    "category": re.compile(r"category:\s*FoodCategory\.(\w+)"),
    "grams": re.compile(r"grams:\s*([\d.]+)"),
}


def parse(dart: str) -> list[dict]:
    items = []
    for body in ITEM.findall(dart):
        got = {k: (m.group(1) if (m := rx.search(body)) else None) for k, rx in FIELD.items()}
        if got["id"] and got["category"]:
            items.append({
                "id": got["id"],
                "name": (got["name"] or got["id"]).replace("\\'", "'"),
                "category": got["category"],
                "grams": float(got["grams"]) if got["grams"] else None,
            })
    return items


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else "-"
    dart = sys.stdin.read() if src == "-" else Path(src).read_text(encoding="utf-8")
    items = parse(dart)
    if not items:
        sys.exit("no FoodItem entries found")
    out = Path(__file__).resolve().parent.parent / "catalog.json"
    out.write_text(json.dumps(items, indent=2) + "\n", encoding="utf-8")
    cats = {c: sum(i["category"] == c for i in items) for c in sorted({i["category"] for i in items})}
    print(f"wrote {len(items)} items to {out.name}: {cats}")


if __name__ == "__main__":
    main()
