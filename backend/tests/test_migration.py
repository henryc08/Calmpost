"""An existing Tiger database built from the old main schema (backend/sql/schema.sql,
with a `seeds` currency) must upgrade in place on boot: no data lost, Seeds become
Loam, and the API works on it.

The old schema is read from git (`main` before the reconcile); skipped if git or
that revision isn't available.
"""

import asyncio
import subprocess
from pathlib import Path

import asyncpg
import pytest

from app import db
from tests.conftest import STUBS, TEST_DB, apply_files, needs_db

ROOT = Path(__file__).resolve().parents[2]
OLD_REV = "66b75b6"  # main before the reconcile


def old_schema() -> str | None:
    try:
        out = subprocess.run(
            ["git", "show", f"{OLD_REV}:backend/sql/schema.sql"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", check=True
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return out.stdout


OLD = old_schema()
pytestmark = [needs_db, pytest.mark.skipif(OLD is None, reason="old schema not in git")]


async def _upgrade():
    conn = await asyncpg.connect(TEST_DB)
    try:
        await conn.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
        old = Path(__file__).with_name("_old_schema.sql")
        old.write_text(OLD, encoding="utf-8")
        try:
            await apply_files(conn, [old])
        finally:
            old.unlink()
        # Stand-in for the old xp_weekly continuous aggregate, built on `seeds`.
        await conn.execute(
            "CREATE VIEW xp_weekly AS SELECT user_id, sum(xp)::bigint AS xp, sum(seeds)::bigint AS seeds FROM point_events GROUP BY 1"
        )
        await conn.execute("INSERT INTO bins (bin_id, owner_id, token_sha256) VALUES ('bin-001', 'demo-user', 'x')")
        await conn.execute(
            "INSERT INTO point_events (user_id, bin_id, kind, xp, seeds) VALUES "
            "('demo-user', 'bin-001', 'check_in', 5, 0), ('demo-user', 'bin-001', 'daily_quest', 10, 40)"
        )
        assert await conn.fetchval("SELECT count(*) FROM information_schema.columns WHERE column_name = 'seeds'") >= 1

        # Boot twice on the upgraded database.
        await apply_files(conn, db.schema_files())
        await apply_files(conn, [STUBS], timescale=True)
        await apply_files(conn, db.schema_files())

        cols = {r["column_name"] for r in await conn.fetch("SELECT column_name FROM information_schema.columns WHERE table_name = 'point_events'")}
        user_cols = {r["column_name"] for r in await conn.fetch("SELECT column_name FROM information_schema.columns WHERE table_name = 'user_state'")}
        return (
            cols,
            user_cols,
            await conn.fetchval("SELECT sum(loam) FROM point_events WHERE user_id = 'demo-user'"),
            await conn.fetchval("SELECT sum(xp) FROM point_events WHERE user_id = 'demo-user'"),
            await conn.fetchval("SELECT count(*) FROM bins"),
        )
    finally:
        await conn.close()


def test_old_main_database_upgrades_in_place():
    cols, user_cols, loam, xp, bins = asyncio.run(_upgrade())
    assert "loam" in cols and "seeds" not in cols
    assert {"lid_locks", "packets", "pity_since_epic", "equipped_finish"} <= user_cols
    assert loam == 40 and xp == 15 and bins == 1
