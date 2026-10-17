"""Atomic, retryable confirmed logging. The server computes rewards."""

from fastapi import HTTPException

from ..catalog import food
from ..models import LogCreate, LogEntry
from ..rules import compost, game
from . import ledger


async def write_log(conn, bin_id: str, body: LogCreate, snapshot: dict | None) -> LogEntry:
    owner = await conn.fetchval("SELECT owner_id FROM bins WHERE bin_id = $1", bin_id)
    if owner is None:
        raise HTTPException(404, "unknown bin")
    await ledger.ensure_user(conn, owner)
    await conn.fetchval("SELECT user_id FROM user_state WHERE user_id = $1 FOR UPDATE", owner)
    payload = body.model_dump(mode="json")
    if body.request_id:
        prior = await conn.fetchrow("SELECT body, response FROM log_requests WHERE bin_id=$1 AND request_id=$2", bin_id, body.request_id)
        if prior:
            if prior["body"] != payload:
                raise HTTPException(409, "this request was already saved with different items")
            return LogEntry(**prior["response"])

    catalog = food.lookup(body.catalog_id) or food.lookup(body.item)
    if compost.avoid_reason(body.item) or compost.avoid_reason(body.catalog_id or ""):
        category = "avoid"
    else:
        category = catalog["category"] if catalog else body.category
        if category == "unknown":
            category = compost.categorise(body.item)
    grams = body.quantity_g if body.quantity_g is not None else int(catalog["grams"] if catalog else 0)
    added = body.action == "added" and category in ("green", "brown")
    advised = False
    if added and grams > 0 and body.was_advised and snapshot and not snapshot["stale"]:
        need = compost.need_for(snapshot)
        advised = (need == "browns" and category == "brown") or (need == "greens" and category == "green")
    previous = await conn.fetchval(
        """SELECT coalesce(sum(quantity_g),0) FROM add_log WHERE user_id=$1
           AND action='added' AND category IN ('green','brown') AND time >= date_trunc('day',now())""", owner)
    row = await conn.fetchrow(
        """INSERT INTO add_log(bin_id,user_id,item,catalog_id,category,action,quantity_g,source,was_advised,advice_id,notes)
           VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id,time""",
        bin_id, owner, body.item, catalog["id"] if catalog else None, category,
        body.action, grams, body.source, advised, body.advice_id, body.notes)
    xp = 0
    if added and grams > 0:
        xp += await ledger.award(conn, owner, "compost_added", bin_id=bin_id,
                                 xp=game.volume_xp(grams, float(previous)), meta={"log_id":row["id"], "grams":grams})
    if advised:
        xp += await ledger.award(conn, owner, "followed_suggestion", bin_id=bin_id, meta={"log_id":row["id"]})
    elif body.action == "skipped" and category == "avoid":
        xp += await ledger.award(conn, owner, "avoided_bad_add", bin_id=bin_id, meta={"log_id":row["id"]})
    result = LogEntry(id=row["id"],time=row["time"],bin_id=bin_id,item=body.item,category=category,catalog_id=catalog['id'] if catalog else None,
                     action=body.action,quantity_g=grams,source=body.source,was_advised=advised,
                     notes=body.notes,xp_awarded=xp)
    if body.request_id:
        await conn.execute("INSERT INTO log_requests VALUES($1,$2,$3,$4)", bin_id, body.request_id, payload, result.model_dump(mode="json"))
    return result
