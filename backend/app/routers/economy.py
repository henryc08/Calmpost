"""Economy endpoints: the rewards inbox and crates, the daily goal, the
Greenhouse (Seed Packet gacha, collection, equipping) and the Lid Lock shop.

All spending is server-authoritative and locked per player, so the app only
ever shows what the backend actually paid.
"""

from fastapi import APIRouter, Depends

from ..models import EquipRequest, PullRequest
from ..rules import game, gacha
from ..security import require_app_key
from ..services import economy

router = APIRouter(tags=["economy"], dependencies=[Depends(require_app_key)])


# --- rewards inbox & crates ------------------------------------------------

@router.get("/users/{user_id}/rewards")
async def rewards(user_id: str) -> dict:
    """Unopened crates and Seed Packets (the gift button's badge count)."""
    await economy.settle(user_id)
    return await economy.rewards(user_id)


@router.post("/users/{user_id}/crates/{crate_id}/open")
async def open_crate(user_id: str, crate_id: int) -> dict:
    """Open a crate: Sprout 60 Loam + 1 packet, Grove 160 + 3, Canopy 400 + 5."""
    return await economy.open_crate(user_id, crate_id)


# --- daily goal ------------------------------------------------------------

@router.get("/users/{user_id}/daily-goal")
async def daily_goal(user_id: str) -> dict:
    """Today's XP against the 20 / 40 / 60 XP rewards."""
    return await economy.daily_goal(user_id)


@router.post("/users/{user_id}/daily-goal/{index}/claim")
async def claim_daily_goal(user_id: str, index: int) -> dict:
    return await economy.claim_daily_goal(user_id, index)


# --- Greenhouse ------------------------------------------------------------

@router.get("/users/{user_id}/collection")
async def collection(user_id: str) -> dict:
    """The Greenhouse: every collectible with copies owned, pity counters,
    what is equipped, odds, prices and the Loam balance."""
    return await economy.collection(user_id)


@router.post("/users/{user_id}/gacha/pull")
async def pull(user_id: str, body: PullRequest) -> dict:
    """Open Seed Packets (1 or 10), paid with owned packets or Loam.
    A 10-pull guarantees a Rare or better; pity guarantees Epic+ within 30
    and Legendary within 80. Duplicates refund Loam."""
    return await economy.pull(user_id, body.count, body.paid_with)


@router.post("/users/{user_id}/equip")
async def equip(user_id: str, body: EquipRequest) -> dict:
    """Equip an owned finish (recolours the Home ring) or title."""
    return await economy.equip(user_id, body.collectible_id)


# --- shop ------------------------------------------------------------------

@router.post("/users/{user_id}/lid-locks/buy")
async def buy_lid_lock(user_id: str) -> dict:
    """Spend 60 Loam on a Lid Lock (hold at most 2)."""
    return await economy.buy_lid_lock(user_id)


@router.get("/economy/rules")
async def rules() -> dict:
    """Published economy numbers, so the app can show odds and prices that
    always match what the backend enforces."""
    return {
        "odds": gacha.ODDS,
        "duplicate_refund": gacha.DUPLICATE_REFUND,
        "prices": {"packet": gacha.PACKET_PRICE, "ten_pack": gacha.TEN_PACK_PRICE, "lid_lock": game.LID_LOCK_PRICE},
        "pity": {"epic": gacha.EPIC_PITY, "legendary": gacha.LEGENDARY_PITY},
        "crates": game.CRATE_CONTENTS,
        "daily_goals": game.DAILY_GOALS,
        "quests": game.QUESTS,
        "streak_milestones": game.STREAK_MILESTONES,
        "league_finish_loam": game.LEAGUE_FINISH_LOAM,
        "max_lid_locks": game.MAX_LID_LOCKS,
    }
