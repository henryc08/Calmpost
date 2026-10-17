"""Request/response shapes -- the contract the Flutter app codes against.

Endpoint shapes mirror CalmpostRepository methods so ApiRepository is a
mechanical swap for MockRepository.
"""

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Category = Literal["green", "brown", "avoid", "unknown"]
Verdict = Literal["great", "careful", "avoid"]
Balance = Literal["needs_greens", "needs_browns", "balanced"]
Stage = Literal["started", "active", "hot", "cooling", "curing", "ready", "harvested"]
MoistureState = Literal["dry", "ok", "wet", "unknown"]
Metric = Literal["moisture", "temperature", "co2", "air_temp", "air_humidity"]


# --- ingest (ESP32 -> backend) ---------------------------------------------

class IngestPayload(BaseModel):
    """Exactly what the firmware sends, one wide sample per POST:

        {"device_id":"bin-001","probe_temp_c":25.3,"moisture_raw":412,
         "co2_ppm":850,"air_temp_c":24.1,"air_humidity_pct":58.2,
         "co2_status":0}

    Every sensor field is optional so a failed sensor still lets the rest of
    the sample through. The board has no reliable clock, so `time` is
    optional and the server stamps arrival when it is absent.
    """

    model_config = ConfigDict(populate_by_name=True)

    # The firmware says device_id; the rest of the system says bin_id.
    bin_id: str = Field(alias="device_id")
    time: datetime | None = None
    probe_temp_c: float | None = Field(default=None, ge=-40, le=125)
    moisture_raw: int | None = Field(default=None, ge=0, le=65535)
    co2_ppm: float | None = Field(default=None, ge=0, le=40000)
    air_temp_c: float | None = Field(default=None, ge=-40, le=125)
    air_humidity_pct: float | None = Field(default=None, ge=0, le=100)
    co2_status: int | None = None
    probe_layer: Literal["top", "bottom"] = "top"


class IngestResult(BaseModel):
    accepted: bool
    time: datetime
    # Echoed back so the firmware author can see calibration working.
    moisture_pct: float | None = None
    calibrated: bool = False


# --- live view -------------------------------------------------------------

class LayerLive(BaseModel):
    layer: Literal["top", "bottom"]
    label: str
    # False when no probe reports this layer yet -- the app should show it as
    # unmeasured rather than as 0.
    measured: bool
    moisture_pct: float | None = None
    moisture_raw: int | None = None
    moisture_state: MoistureState = "unknown"
    temp_c: float | None = None
    stage: Stage = "started"


class HealthComponents(BaseModel):
    """Inputs for HealthBreakdown in domain/health_score.dart, which owns the
    formula: 0.45*moisture + 0.20*temperature + 0.15*co2 + 0.20*balance.

    Computed the app's way -- temperature is a rise above ambient, not an
    absolute reading. Any field is null when its sensor has not reported, and
    the app should leave that term out rather than score it 0.
    """

    moisture: float | None = None
    temperature: float | None = None
    co2: float | None = None
    balance: float | None = None
    weights: dict[str, float] = {
        "moisture": 0.45,
        "temperature": 0.20,
        "co2": 0.15,
        "balance": 0.20,
    }


class AirLive(BaseModel):
    co2_ppm: float | None = None
    # False when there is no value, or the sensor flagged an error.
    co2_ok: bool = True
    co2_status: int | None = None
    # PERCENT PER DAY over 48h, matching the app's co2SlopePerDay.
    co2_slope_per_day: float | None = None
    # The app's ambientTemp: the reference the layer temperatures are scored
    # against, since compost heat is a rise above the surrounding air.
    ambient_temp_c: float | None = None
    air_humidity_pct: float | None = None


class LiveResponse(BaseModel):
    """Fills BinSnapshot in app/lib/domain/models.dart.

    greens_7d / browns_7d are rough CUPS of volume, not item counts, because
    that is what the app's balance ratio compares.
    """

    bin_id: str
    time: datetime
    last_seen_at: datetime | None
    # True when the bin has not reported for a while; the app shows "offline".
    stale: bool
    layers: list[LayerLive]
    air: AirLive
    health_components: HealthComponents
    balance: Balance
    greens_7d: float
    browns_7d: float
    healthy_band: list[float]
    moisture_calibrated: bool
    # The app's healthyHoursToday: hours since midnight inside the band.
    healthy_hours_today: float | None = None
    notes: list[str] = []


# --- trends ----------------------------------------------------------------

class TrendPoint(BaseModel):
    bucket: datetime
    value: float | None = None


class TrendSeries(BaseModel):
    metric: Metric
    points: list[TrendPoint]


class TrendsResponse(BaseModel):
    bin_id: str
    hours: int
    resolution: Literal["15m", "1d"]
    healthy_band: list[float] | None = None
    series: list[TrendSeries]


# --- add log ---------------------------------------------------------------

class LogCreate(BaseModel):
    item: str = Field(min_length=1, max_length=120)
    request_id: str | None = Field(default=None, min_length=1, max_length=100)
    # The app's food catalog id when known (FoodItem.id).
    catalog_id: str | None = None
    category: Category = "unknown"
    # "skipped" records trusting an avoid verdict, which is what earns XP.
    action: Literal["added", "skipped"] = "added"
    quantity_g: int | None = Field(default=None, ge=0, le=5000)
    piece_count: int | None = Field(default=None, ge=1, le=999, strict=True)
    source: Literal["manual", "photo", "seed", "camera"] = "manual"
    was_advised: bool = False
    advice_id: int | None = None
    notes: str | None = None


class LogEntry(BaseModel):
    id: int
    bin_id: str
    time: datetime
    item: str
    catalog_id: str | None = None
    category: Category
    action: Literal["added", "skipped"]
    quantity_g: int | None = None
    piece_count: int | None = None
    source: str
    was_advised: bool
    notes: str | None = None
    xp_awarded: int = 0
    # The app calls the soft currency loam.
    loam_awarded: int = 0


# --- advice ----------------------------------------------------------------

class AdviceCheck(BaseModel):
    """POST /bins/{id}/advice/check -- the verdict sheet, our demo moment."""

    item: str
    quantity_g: int | None = Field(default=None, ge=0)


class AdviceResponse(BaseModel):
    """Shape fixed by AGENTS.md: verdict, reason, suggest_add, suggest_avoid,
    balance, stage_top, stage_bottom, bottom_ready, tip."""

    advice_id: int
    bin_id: str
    item: str | None = None
    created_at: datetime
    cached: bool
    model: str
    verdict: Verdict
    # 2-4 words, for the verdict sheet's title.
    headline: str = ""
    reason: str
    # Items to add alongside this one (the app's Advice.pairWith).
    pair_with: list[str] = []
    suggest_add: list[str] = []
    suggest_avoid: list[str] = []
    balance: Balance
    stage_top: Stage
    stage_bottom: Stage
    bottom_ready: bool
    tip: str | None = None
    # The sensor state this answer was based on -- proof that the same scrap
    # got a different answer because the bin changed.
    input_snapshot: dict | None = None


# --- game ------------------------------------------------------------------

class QuestProgress(BaseModel):
    """One of today's three care quests (the app's Quest)."""

    key: str
    title: str
    goal: float
    progress: float
    unit: str = ""
    xp: int
    loam: int
    done: bool
    # Rewards are paid when the player taps Claim, as in the app.
    claimed: bool


class QuestsResponse(BaseModel):
    user_id: str
    day: date
    quests: list[QuestProgress]


class QuestClaimed(BaseModel):
    quest: str
    xp_awarded: int
    loam_awarded: int


class ImpactStats(BaseModel):
    kg_diverted: float
    co2e_kg_avoided: float
    fertilizer_saved_usd: float
    is_estimate: bool = True


class Achievement(BaseModel):
    """GameState.achievements: three tiers, every tier pays a crate."""

    id: str
    title: str
    description: str
    progress: float
    goals: list[float]
    rewards: list[str]
    tier: int
    maxed: bool
    next_goal: float
    next_reward: str


class DailyGoalStep(BaseModel):
    index: int
    xp: int
    label: str
    loam: int
    crate: str | None = None
    reached: bool
    claimed: bool


class DailyGoal(BaseModel):
    xp_today: int
    goals: list[DailyGoalStep]


class GameResponse(BaseModel):
    """Everything the Home HUD, streak calendar, daily goal and Profile need."""

    user_id: str
    display_name: str
    total_xp: int
    week_xp: int = 0
    action_xp_today: int = 0
    grams_today: float = 0
    stats: dict = Field(default_factory=dict)
    level: int
    # The equipped title if any, otherwise the level title.
    title: str
    level_title: str
    xp_into_level: int
    xp_for_next_level: int
    loam: int
    streak_days: int
    best_streak: int
    lid_locks: int
    streak_at_risk: bool
    cared_today: bool
    # The last six weeks for the calendar: care days and Lid Lock days.
    care_days: list[date]
    lock_days: list[date]
    daily_goal: DailyGoal
    crates_waiting: int
    packets: int
    equipped_finish: str
    equipped_title: str | None = None
    collected: int
    collection_total: int
    impact: ImpactStats
    achievements: list[Achievement]


class LeagueMember(BaseModel):
    user_id: str
    # The app's LeagueMember.name.
    display_name: str
    xp: int
    rank: int
    is_you: bool = False
    is_friend: bool = False
    streak: int = 0
    # Stable per-member index for the app's avatar palette.
    color_index: int = 0
    zone: Literal["promote", "safe", "demote"] = "safe"


class LeagueResponse(BaseModel):
    tier: str
    # Position in leagueTiers, so the app knows if promotion/demotion applies.
    tier_index: int = 0
    week_start: date
    resets_at: datetime
    size: int
    promote_count: int
    demote_count: int
    members: list[LeagueMember]
    your_rank: int | None = None


# --- economy (crates, Seed Packets, shop) -----------------------------------

class PullRequest(BaseModel):
    """Open Seed Packets: 1 or 10, paid with owned packets or Loam."""

    count: Literal[1, 10] = 1
    paid_with: Literal["packet", "loam"] = "packet"


class EquipRequest(BaseModel):
    collectible_id: str


# --- harvest ---------------------------------------------------------------

class HarvestRequest(BaseModel):
    layer: Literal["top", "bottom"] = "bottom"
    yield_g: int | None = Field(default=None, ge=0)


class HarvestResponse(BaseModel):
    bin_id: str
    layer: str
    harvested_at: datetime
    xp_awarded: int
    loam_awarded: int
    was_ready: bool
    note: str | None = None


# --- bins ------------------------------------------------------------------

class BinCreate(BaseModel):
    bin_id: str = "bin-001"
    display_name: str = "Compost Bin"
    owner_id: str = "demo-user"


class BinCreated(BaseModel):
    bin_id: str
    display_name: str
    # Shown once -- only its hash is stored.
    device_token: str


class CalibrationUpdate(BaseModel):
    """Raw ADC counts with the probe in air and in water. Capacitive probes
    read lower as they get wetter, so dry is the higher count."""

    moisture_raw_dry: int = Field(ge=0, le=65535)
    moisture_raw_wet: int = Field(ge=0, le=65535)
    # Recompute moisture_pct across stored history with the new curve.
    backfill: bool = True
