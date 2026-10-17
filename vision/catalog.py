"""The food catalog (mirrored from the app, see tools/sync_catalog.py).

Rules, not Gemini, decide an item's category: Gemini only picks a
catalog_id, so a hard-avoid item can never come back as "green".
"""

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from config import settings

UNKNOWN = "unknown"

# Amount buckets shown in the app's pop-up (Small / Handful / Large).
AMOUNTS = [("small", 0, 60), ("handful", 60, 180), ("large", 180, 10_000)]


@dataclass(frozen=True)
class Food:
    id: str
    name: str
    category: str   # green | brown | avoid
    grams: float | None


@lru_cache
def load(path: Path = settings.catalog_path) -> dict[str, Food]:
    return {d["id"]: Food(**d) for d in json.loads(path.read_text(encoding="utf-8"))}


def ids() -> list[str]:
    return list(load()) + [UNKNOWN]


def category_of(catalog_id: str) -> str | None:
    """None for unknown items: the user picks the type in the pop-up."""
    food = load().get(catalog_id)
    return food.category if food else None


def amount_of(grams: float | None) -> str | None:
    if grams is None:
        return None
    return next(name for name, lo, hi in AMOUNTS if lo <= grams < hi)
