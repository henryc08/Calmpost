"""asyncpg connection pool and schema bootstrap."""

import json
import re
import ssl
from pathlib import Path
from typing import Any

import asyncpg

from .config import get_settings

_pool: asyncpg.Pool | None = None

SQL_DIR = Path(__file__).resolve().parent.parent / "sql"


def schema_files() -> list[Path]:
    """sql/NNN_*.sql in name order: 000_premigrate, 001_core, 002_game, ..."""
    return sorted(SQL_DIR.glob("[0-9][0-9][0-9]_*.sql"))


def _dump_json(value) -> str:
    # default=str so timestamps inside a snapshot serialise instead of
    # raising -- advice rows embed the measured_at they were based on.
    return json.dumps(value, default=str)


async def _init_connection(conn: asyncpg.Connection) -> None:
    # asyncpg hands jsonb back as a string unless we register a codec.
    await conn.set_type_codec("jsonb", encoder=_dump_json, decoder=json.loads, schema="pg_catalog")


async def connect() -> asyncpg.Pool:
    """Open the pool. Tiger Cloud requires TLS."""
    global _pool
    if _pool is not None:
        return _pool

    settings = get_settings()
    if not settings.database_url:
        raise RuntimeError("DATABASE_URL is not set -- copy .env.example to .env")

    # The service URL carries ?sslmode=require, which asyncpg does not parse;
    # strip it and pass a real SSL context instead.
    dsn = settings.database_url.split("?")[0]
    # Verify the server. A private CA must be supplied explicitly; never
    # silently downgrade certificate or hostname verification.
    ctx = ssl.create_default_context(cafile=settings.database_ca_file or None)

    _pool = await asyncpg.create_pool(dsn, ssl=ctx, min_size=1, max_size=10, init=_init_connection)
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


async def fetchval(query: str, *args: Any) -> Any:
    async with pool().acquire() as conn:
        return await conn.fetchval(query, *args)


async def execute(query: str, *args: Any) -> str:
    async with pool().acquire() as conn:
        return await conn.execute(query, *args)


async def apply_schema() -> None:
    """Run every sql/NNN_*.sql in order. All idempotent, so it runs on every boot."""
    async with pool().acquire() as conn:
        for path in schema_files():
            # Timescale's create_hypertable/policy helpers cannot run inside
            # the implicit transaction asyncpg uses for multi-statement
            # execute, so statements go one at a time.
            for statement in split_statements(path.read_text(encoding="utf-8")):
                await conn.execute(statement)


_DOLLAR_TAG = re.compile(r"\$[A-Za-z_]*\$")


def split_statements(sql: str) -> list[str]:
    """Split SQL text on statement boundaries.

    `--` comments are stripped first, so a semicolon in a comment does not
    split a statement. Single-quoted literals ('it''s') and dollar-quoted
    bodies ($$ ... $$ or $tag$ ... $tag$, as in DO blocks) are tracked, so
    semicolons inside them are not boundaries either.
    """
    stripped = "\n".join(re.sub(r"--.*$", "", line) for line in sql.splitlines())

    out: list[str] = []
    current: list[str] = []
    in_string = False
    dollar_tag: str | None = None
    i, n = 0, len(stripped)
    while i < n:
        ch = stripped[i]
        if dollar_tag is not None:
            if stripped.startswith(dollar_tag, i):
                current.append(dollar_tag)
                i += len(dollar_tag)
                dollar_tag = None
                continue
            current.append(ch)
        elif in_string:
            current.append(ch)
            if ch == "'":
                # '' is an escaped quote inside a literal, not the end of one.
                if i + 1 < n and stripped[i + 1] == "'":
                    current.append("'")
                    i += 1
                else:
                    in_string = False
        elif ch == "'":
            in_string = True
            current.append(ch)
        elif ch == "$" and (m := _DOLLAR_TAG.match(stripped, i)):
            dollar_tag = m.group(0)
            current.append(dollar_tag)
            i += len(dollar_tag)
            continue
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


# Kept for older callers (tests and scripts written before the rename).
_split_statements = split_statements
