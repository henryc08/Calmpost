"""Seed Packet gacha rules. No I/O. Mirrors app/lib/domain/gacha.dart.

Plants can equip progression buffs; finishes and titles stay cosmetic.
No collectible changes measured health or compost safety advice.
"""

import random

from ..catalog.collectibles import COLLECTIBLES

RARITIES = ("common", "uncommon", "rare", "epic", "legendary")

# Odds per pull. Always shown next to the pull buttons.
ODDS = {"common": 0.60, "uncommon": 0.25, "rare": 0.11, "epic": 0.035, "legendary": 0.005}

# Loam refunded for a duplicate.
DUPLICATE_REFUND = {"common": 5, "uncommon": 10, "rare": 25, "epic": 60, "legendary": 150}

PACKET_PRICE = 100
TEN_PACK_PRICE = 900

# Pity: an Epic or better within this many pulls, a Legendary within this many.
EPIC_PITY = 30
LEGENDARY_PITY = 80


def price(count: int) -> int:
    return TEN_PACK_PRICE if count >= 10 else PACKET_PRICE * count


def rank(rarity: str) -> int:
    return RARITIES.index(rarity)


def roll_rarity(rng: random.Random, since_epic: int, since_legendary: int) -> tuple[str, bool]:
    """One rarity, honouring the pity counters. Returns (rarity, forced_by_pity)."""
    if since_legendary >= LEGENDARY_PITY - 1:
        return "legendary", True
    if since_epic >= EPIC_PITY - 1:
        return ("legendary" if rng.random() < 0.125 else "epic"), True
    r = rng.random()
    for rarity, p in ODDS.items():
        if r < p:
            return rarity, False
        r -= p
    return "common", False


def advance(since_epic: int, since_legendary: int, got: str) -> tuple[int, int]:
    return (
        0 if rank(got) >= rank("epic") else since_epic + 1,
        0 if got == "legendary" else since_legendary + 1,
    )


def roll(rng: random.Random, count: int, since_epic: int, since_legendary: int) -> tuple[list[tuple[str, bool]], int, int]:
    """Roll `count` rarities. A 10-pull guarantees at least one Rare or better.

    Returns ([(rarity, pity)], new since_epic, new since_legendary).
    """
    out: list[tuple[str, bool]] = []
    e, leg = since_epic, since_legendary
    for i in range(count):
        rarity, pity = roll_rarity(rng, e, leg)
        last = i == count - 1
        if count >= 10 and last and rank(rarity) < rank("rare") and all(rank(r) < rank("rare") for r, _ in out):
            rarity, pity = "rare", True
        out.append((rarity, pity))
        e, leg = advance(e, leg, rarity)
    return out, e, leg


def pick(rng: random.Random, rarity: str) -> dict:
    pool = [c for c in COLLECTIBLES if c["rarity"] == rarity]
    return rng.choice(pool)
