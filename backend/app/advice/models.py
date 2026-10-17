"""Pydantic models for advice: what goes in (a bin snapshot) and what comes out.

`Advice` is also the JSON schema we hand Gemini for structured output, so keep
field descriptions short and concrete — Gemini reads them.
"""

from datetime import datetime, timezone
from enum import Enum

from pydantic import BaseModel, Field


class Verdict(str, Enum):
    add = "add"
    add_with_browns = "add_with_browns"
    avoid = "avoid"


class Balance(str, Enum):
    needs_greens = "needs_greens"
    needs_browns = "needs_browns"
    balanced = "balanced"


class Stage(str, Enum):
    active = "active"
    hot = "hot"
    curing = "curing"
    ready = "ready"


class LayerReading(BaseModel):
    moisture_pct: float = Field(ge=0, le=100)
    temp_c: float


class BinSnapshot(BaseModel):
    """Everything the advice is based on. Stored with each answer as proof of
    'same scrap, different answer'."""

    bin_id: str
    taken_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    top: LayerReading
    bottom: LayerReading
    co2_ppm: float = Field(ge=0)
    co2_trend_ppm_per_hr: float = 0.0
    ambient_temp_c: float = 21.0
    greens_7d: int = Field(0, ge=0, description="green adds logged in the last 7 days")
    browns_7d: int = Field(0, ge=0, description="brown adds logged in the last 7 days")
    recent_adds: list[str] = Field(default_factory=list)


class AdviceCheckRequest(BaseModel):
    scrap: str = Field(min_length=1, max_length=80)


class Advice(BaseModel):
    verdict: Verdict = Field(description="add, add_with_browns (add it but mix in dry browns), or avoid")
    reason: str = Field(description="1-2 short sentences in Wren the worm's voice explaining the verdict from the readings")
    suggest_add: list[str] = Field(description="up to 3 specific things to add next")
    suggest_avoid: list[str] = Field(description="up to 3 specific things to keep out right now")
    balance: Balance
    stage_top: Stage
    stage_bottom: Stage
    bottom_ready: bool = Field(description="true only if the bottom layer looks finished and usable as fertilizer")
    tip: str = Field(description="one short practical tip")


class AdviceResponse(Advice):
    scrap: str
    source: str = Field(description="'gemini' or 'rules'")
    snapshot: BinSnapshot
