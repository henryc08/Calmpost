"""Request/response shapes. These are the contract the Flutter app codes against."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

Zone = Literal["top", "bottom", "airgap"]
Category = Literal["green", "brown", "avoid", "unknown"]
Stage = Literal["active", "curing", "ready", "unknown"]


# --- ingest (Arduino -> backend) -------------------------------------------

class ZoneSample(BaseModel):
    """One zone's numbers. Send only the fields that zone actually has."""

    zone: Zone
    moisture_pct: float | None = Field(default=None, ge=0, le=100)
    temperature_c: float | None = Field(default=None, ge=-40, le=125)
    co2_ppm: float | None = Field(default=None, ge=0, le=40000)


class IngestPayload(BaseModel):
    """What the ESP32 POSTs to /v1/ingest every few minutes."""

    device_id: str
    # The board has no reliable clock on first boot, so time is optional and
    # the server stamps it on arrival when missing.
    time: datetime | None = None
    zones: list[ZoneSample] = Field(min_length=1)


class IngestResult(BaseModel):
    accepted: int
    time: datetime


# --- readings (backend -> Flutter) -----------------------------------------

class ZoneStatus(BaseModel):
    zone: Zone
    label: str
    time: datetime | None = None
    moisture_pct: float | None = None
    temperature_c: float | None = None
    co2_ppm: float | None = None
    moisture_state: Literal["dry", "ok", "wet", "unknown"] = "unknown"


class LatestResponse(BaseModel):
    device_id: str
    last_seen_at: datetime | None
    zones: list[ZoneStatus]


class HistoryPoint(BaseModel):
    bucket: datetime
    moisture_pct: float | None = None
    temperature_c: float | None = None
    co2_ppm: float | None = None


class HistoryResponse(BaseModel):
    device_id: str
    zone: Zone
    hours: int
    points: list[HistoryPoint]


# --- add log ---------------------------------------------------------------

class AddLogCreate(BaseModel):
    device_id: str
    item: str
    category: Category = "unknown"
    zone: Zone = "top"
    quantity_g: int | None = Field(default=None, ge=0)
    source: Literal["manual", "photo", "seed"] = "manual"
    was_advised: bool = False
    notes: str | None = None


class AddLogEntry(AddLogCreate):
    id: int
    time: datetime
    points_awarded: int = 0


# --- advice ----------------------------------------------------------------

class Suggestion(BaseModel):
    item: str
    action: Literal["add", "avoid"]
    reason: str


class AdviceResponse(BaseModel):
    device_id: str
    created_at: datetime
    cached: bool
    model: str
    headline: str
    balance: Literal["needs_greens", "needs_browns", "balanced", "unknown"]
    stage_top: Stage
    stage_bottom: Stage
    bottom_ready: bool
    suggestions: list[Suggestion]
    warnings: list[str] = []


# --- gamification ----------------------------------------------------------

class PointsResponse(BaseModel):
    user_id: str
    total_points: int
    streak_days: int
    logs_this_week: int
