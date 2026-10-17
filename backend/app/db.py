"""asyncpg connection pool and schema bootstrap."""

import json
import re
import ssl
from pathlib import Path
from typing import Any

import asyncpg

from .config import get_settings

_pool: asyncpg.Pool | None = None

SCHEMA_PATH = Path(__file__).resolve().parent.parent / "sql" / "schema.sql"


async def _init_connection(conn: asyncpg.Connection) -> None:
    # asyncpg hands jsonb back as a string unless we register a codec.
    await conn.set_type_codec(
        "jsonb", encoder=json.dumps, decoder=json.loads, schema="pg_catalog"
    )


async def connect() -> asyncpg.Pool:
    """Open the pool. Timescale Cloud requires TLS."""
    global _pool
    if _pool is not None:
        return _pool

    settings = get_settings()
    if not settings.database_url:
        raise RuntimeError("DATABASE_URL is not set -- copy .env.example to .env")

    # The service URL carries ?sslmode=require, which asyncpg does not parse;
    # strip it and pass a real SSL context instead.
    dsn = settings.database_url.split("?")[0]
    ctx = ssl.create_default_context()

    _pool = await asyncpg.create_pool(
        dsn, ssl=ctx, min_size=1, max_size=10, init=_init_connection
    )
    return _pool


async def disconnect() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("database pool is not initialised")
    return _pool


async def fetch(query: str, *args: Any) -> list[asyncpg.Record]:
    async with pool().acquire() as conn:
        return await conn.fetch(query, *args)


async def fetchrow(query: str, *args: Any) -> asyncpg.Record | None:
    async with pool().acquire() as conn:
        return await conn.fetchrow(query, *args)


async def execute(query: str, *args: Any) -> str:
    async with pool().acquire() as conn:
        return await conn.execute(query, *args)


async def apply_schema() -> None:
    """Run sql/schema.sql. Idempotent, so it runs on every boot."""
    sql = SCHEMA_PATH.read_text(encoding="utf-8")
    async with pool().acquire() as conn:
        # Timescale's create_hypertable/policy helpers cannot run inside the
        # implicit transaction asyncpg uses for multi-statement execute, so
        # statements go one at a time.
        for statement in _split_statements(sql):
            await conn.execute(statement)


def _split_statements(sql: str) -> list[str]:
    """Split schema.sql on statement boundaries.

    Comments are stripped first: a semicolon inside a `--` comment would
    otherwise split a statement in half. String literals are tracked so a
    semicolon inside quotes is not treated as a boundary either.
    """
    stripped = "\n".join(
        re.sub(r"--.*$", "", line) for line in sql.splitlines()
    )

    out: list[str] = []
    current: list[str] = []
    in_string = False
    i = 0
    while i < len(stripped):
        ch = stripped[i]
        if in_string:
            current.append(ch)
            if ch == "'":
                # '' is an escaped quote inside a literal, not the end of one.
                if i + 1 < len(stripped) and stripped[i + 1] == "'":
                    current.append("'")
                    i += 1
                else:
                    in_string = False
        elif ch == "'":
            in_string = True
            current.append(ch)
        elif ch == ";":
            stmt = "".join(current).strip()
            if stmt:
                out.append(stmt)
            current = []
        else:
            current.append(ch)
        i += 1

    tail = "".join(current).strip()
    if tail:
        out.append(tail)
    return out
