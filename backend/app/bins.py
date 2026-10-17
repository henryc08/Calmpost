"""Where bin snapshots come from.

Until Tiger Data is wired up, snapshots come from the same demo scenarios as the
app's MockRepository (healthy, too_wet, too_dry, curing, ready). Swap
`ScenarioBinSource` for a Tiger-backed source later; the endpoint won't change.
"""

from typing import Protocol

from .advice.models import BinSnapshot, LayerReading

SCENARIOS: dict[str, dict] = {
    "healthy": dict(top=LayerReading(moisture_pct=52, temp_c=38), bottom=LayerReading(moisture_pct=48, temp_c=29),
                    co2_ppm=1400, co2_trend_ppm_per_hr=8, greens_7d=4, browns_7d=10),
    "too_wet": dict(top=LayerReading(moisture_pct=74, temp_c=27), bottom=LayerReading(moisture_pct=66, temp_c=24),
                    co2_ppm=1900, co2_trend_ppm_per_hr=2, greens_7d=9, browns_7d=6),
    "too_dry": dict(top=LayerReading(moisture_pct=28, temp_c=24), bottom=LayerReading(moisture_pct=33, temp_c=23),
                    co2_ppm=700, co2_trend_ppm_per_hr=-1, greens_7d=2, browns_7d=9),
    "curing": dict(top=LayerReading(moisture_pct=50, temp_c=27), bottom=LayerReading(moisture_pct=47, temp_c=25),
                   co2_ppm=900, co2_trend_ppm_per_hr=-3, greens_7d=3, browns_7d=8),
    "ready": dict(top=LayerReading(moisture_pct=50, temp_c=31), bottom=LayerReading(moisture_pct=45, temp_c=22),
                  co2_ppm=600, co2_trend_ppm_per_hr=-4, greens_7d=3, browns_7d=8),
}


class BinSource(Protocol):
    async def snapshot(self, bin_id: str) -> BinSnapshot: ...


class ScenarioBinSource:
    def __init__(self, scenario: str = "healthy"):
        self.scenario = scenario

    def set_scenario(self, scenario: str) -> None:
        if scenario not in SCENARIOS:
            raise KeyError(scenario)
        self.scenario = scenario

    async def snapshot(self, bin_id: str) -> BinSnapshot:
        return BinSnapshot(bin_id=bin_id, **SCENARIOS[self.scenario])
