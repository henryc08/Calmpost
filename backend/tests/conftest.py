"""Shared test setup: a real Postgres with the real schema.

The database comes from TEST_DATABASE_URL (it is WIPED), or, if unset, a
throwaway local server started with the `pgserver` package
(pip install pgserver). Without either, database tests are skipped and the
pure rule tests still run.

Tiger Cloud is TimescaleDB; the local server is plain Postgres. So the
TimescaleDB-only statements (hypertables, continuous aggregates, policies)
are skipped, and tests/timescale_stubs.sql provides stand-ins for the
functions the queries use (time_bucket, locf, time_weight, state_agg ...),
so every query in the backend actually executes here.
"""

import json
import os
import tempfile
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

import asyncpg
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app import db
from app.routers import advice, bins, drops, economy, game, ingest

KEY = {"X-API-Key": "dev-change-me"}
STUBS = Path(__file__).with_name("timescale_stubs.sql")
TIMESCALE_ONLY = (
    "timescaledb",
    "create_hypertable",
    "add_retention_policy",
    "add_continuous_aggregate_policy",
    "add_columnstore_policy",
    "add_compression_policy",
    "MATERIALIZED VIEW",
    "refresh_continuous",
)

_server = None


def _test_db_url() -> str | None:
    url = os.environ.get("TEST_DATABASE_URL")
    if url:
        return url
    global _server
    try:
        import pgserver
    except ImportError:
        return None
    if _server is None:
        _server = pgserver.get_server(Path(tempfile.gettempdir()) / "calmpost_pytest_pg", cleanup_mode=None)
    return _server.get_uri()


TEST_DB = _test_db_url()
needs_db = pytest.mark.skipif(not TEST_DB, reason="no TEST_DATABASE_URL and pgserver is not installed")


async def apply_files(conn: asyncpg.Connection, paths, *, timescale: bool = False) -> None:
    for path in paths:
        for stmt in db.split_statements(Path(path).read_text(encoding="utf-8")):
            # DO blocks are migrations that already branch on what exists.
            if timescale or stmt.lstrip().upper().startswith("DO") or not any(t in stmt for t in TIMESCALE_ONLY):
                await conn.execute(stmt)


async def fresh_schema(conn: asyncpg.Connection) -> None:
    await conn.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    await apply_files(conn, db.schema_files())
    await apply_files(conn, [STUBS], timescale=True)
    # Twice: every schema file must be idempotent (it runs on every boot).
    await apply_files(conn, db.schema_files())


def _init(conn):
    return conn.set_type_codec("jsonb", encoder=db._dump_json, decoder=json.loads, schema="pg_catalog")


@asynccontextmanager
async def lifespan(app):
    db._pool = await asyncpg.create_pool(TEST_DB, min_size=1, max_size=5, init=_init)
    async with db.pool().acquire() as conn:
        await fresh_schema(conn)
    yield
    await db.disconnect()


def make_app() -> FastAPI:
    app = FastAPI(lifespan=lifespan)
    for r in (ingest.router, bins.router, advice.router, game.router, drops.router, economy.router):
        app.include_router(r)
    return app


@pytest.fixture
def c(monkeypatch):
    """A client on a fresh database with one registered bin, bin-001 (owner demo-user)."""
    monkeypatch.setenv("APP_API_KEY", "dev-change-me")
    monkeypatch.setenv("GEMINI_API_KEY", "")
    from app.config import get_settings

    get_settings.cache_clear()
    with TestClient(make_app(), headers=KEY) as client:
        r = client.post("/bins", json={"bin_id": "bin-001", "owner_id": "demo-user"})
        assert r.status_code == 201, r.text
        client.device_token = r.json()["device_token"]
        yield client
    get_settings.cache_clear()


def ingest_series(c, *, moisture_raw: int, probe_temp: float, co2: float, air_temp: float = 21.0, minutes: int = 30, step: int = 5):
    """Post a short series of readings ending now (oldest first)."""
    now = datetime.now(timezone.utc)
    for i in range(minutes // step, -1, -1):
        r = c.post(
            "/ingest",
            headers={"X-Device-Token": c.device_token},
            json={
                "device_id": "bin-001",
                "time": (now - timedelta(minutes=i * step)).isoformat(),
                "probe_temp_c": probe_temp,
                "moisture_raw": moisture_raw,
                "co2_ppm": co2,
                "air_temp_c": air_temp,
                "air_humidity_pct": 55,
                "co2_status": 0,
            },
        )
        assert r.status_code == 200, r.text


def raw_for(pct: float, dry: int = 620, wet: int = 310) -> int:
    """Raw ADC count that the default calibration turns into `pct`."""
    return round(dry - pct / 100 * (dry - wet))


async def run_sql(sql: str, *args):
    """Run SQL against the test DB from a test (via the app's pool)."""
    async with db.pool().acquire() as conn:
        return await conn.execute(sql, *args)
