"""Calmpost backend: sensor ingest + Tiger Data time-series + Gemini advice.

Thin API by design: it keeps the database and Gemini keys off the phone. The
Flutter app never talks to Tiger Data directly -- it calls these endpoints,
and ApiRepository mirrors CalmpostRepository method for method.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import db
from .config import get_settings
from .routers import advice, bins, drops, game, ingest

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.connect()
    # schema.sql is idempotent, so applying it on boot keeps every teammate's
    # database in step without a migration tool.
    await db.apply_schema()
    await drops.apply_schema()
    yield
    await db.disconnect()


settings = get_settings()

app = FastAPI(
    title="Calmpost API",
    version="0.2.0",
    description="Smart compost bin backend -- Hack the Valley 11",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(ingest.router)
app.include_router(bins.router)
app.include_router(advice.router)
app.include_router(game.router)
app.include_router(drops.router)


@app.get("/health", tags=["meta"])
async def health() -> dict:
    """Liveness plus a real database round trip."""
    row = await db.fetchrow("SELECT now() AS now")
    return {"ok": True, "db_time": row["now"]}
