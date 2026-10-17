"""Device registration. Run once per bin to mint the token the ESP32 uses."""

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from .. import db
from ..security import hash_token, new_token, require_app_key

router = APIRouter(prefix="/v1", tags=["devices"], dependencies=[Depends(require_app_key)])


class DeviceCreate(BaseModel):
    device_id: str
    display_name: str = "Compost Bin"
    owner_id: str = "demo-user"


class DeviceCreated(BaseModel):
    device_id: str
    display_name: str
    # Shown exactly once -- only its hash is stored.
    device_token: str


@router.post("/devices", response_model=DeviceCreated, status_code=201)
async def register(body: DeviceCreate) -> DeviceCreated:
    token = new_token()
    await db.execute(
        """
        INSERT INTO devices (device_id, display_name, token_sha256, owner_id)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (device_id) DO UPDATE SET
            display_name = EXCLUDED.display_name,
            token_sha256 = EXCLUDED.token_sha256,
            owner_id     = EXCLUDED.owner_id
        """,
        body.device_id,
        body.display_name,
        hash_token(token),
        body.owner_id,
    )
    return DeviceCreated(
        device_id=body.device_id,
        display_name=body.display_name,
        device_token=token,
    )


@router.get("/devices")
async def list_devices() -> list[dict]:
    rows = await db.fetch(
        """
        SELECT device_id, display_name, owner_id, created_at, last_seen_at
        FROM devices ORDER BY created_at
        """
    )
    return [dict(r) for r in rows]
