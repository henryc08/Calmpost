from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel

from .advice.models import AdviceCheckRequest, AdviceResponse
from .advice.service import check_scrap
from .bins import SCENARIOS, BinSource, ScenarioBinSource

load_dotenv()

app = FastAPI(title="Calmpost API")

_bins = ScenarioBinSource()


def get_bins() -> BinSource:
    return _bins


@app.post("/bins/{bin_id}/advice/check", response_model=AdviceResponse)
async def advice_check(bin_id: str, body: AdviceCheckRequest, bins: BinSource = Depends(get_bins)):
    snapshot = await bins.snapshot(bin_id)
    return await check_scrap(body.scrap, snapshot)


class ScenarioBody(BaseModel):
    scenario: str


@app.post("/debug/scenario")
async def set_scenario(body: ScenarioBody):
    """Demo control: switch the fake bin state until real sensors are wired up."""
    if body.scenario not in SCENARIOS:
        raise HTTPException(400, f"unknown scenario, pick one of {sorted(SCENARIOS)}")
    _bins.set_scenario(body.scenario)
    return {"scenario": body.scenario}
