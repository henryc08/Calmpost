"""Authenticated offers and requests inside existing private groups."""
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import Field

from .. import db
from ..services import exchange
from .social import Body, current_user, member

router = APIRouter(prefix='/social/circles/{cid}/exchange', tags=['exchange'])


class CreatePost(Body):
    kind: Literal['request', 'offer']
    material_id: str = Field(min_length=1, max_length=80)
    quantity: str = Field(min_length=1, max_length=80)
    details: str = Field(default='', max_length=500)
    request_id: str = Field(min_length=10, max_length=100)


class Claim(Body):
    version: int = Field(ge=1, strict=True)
    request_id: str = Field(min_length=10, max_length=100)
    note: str = Field(default='', max_length=500)


class Reservation(Body):
    reservation_id: str = Field(min_length=10, max_length=100)


class Note(Reservation):
    note: str = Field(max_length=500)


class Cancel(Body):
    version: int = Field(ge=1, strict=True)


async def lock_group(conn, cid: str, uid: str):
    await conn.fetchval('SELECT id FROM social_circles WHERE id=$1 FOR UPDATE', cid)
    return await member(cid, uid, conn=conn)


def active(row):
    if exchange.expired(row):
        raise HTTPException(409, 'This post expired. Create a new post if it is still needed')


def participant(row, uid: str, reservation_id: str):
    if uid not in (row['creator_id'], row['responder_id']):
        raise HTTPException(403, 'Only the two participants can do this')
    if row['reservation_id'] != reservation_id:
        raise HTTPException(409, 'This reservation changed. Refresh before continuing')


@router.get('')
async def board(cid: str, view: Literal['active', 'history', 'mine'] = 'active',
                before: int | None = Query(default=None, ge=1), limit: int = Query(default=20, ge=1, le=50),
                uid: str = Depends(current_user)):
    circle = await member(cid, uid)
    rows = await db.fetch(exchange.SELECT + """ WHERE e.circle_id=$1 AND ($2::bigint IS NULL OR e.id<$2)
        AND (($3='active' AND e.status IN ('open','reserved') AND e.expires_at>now())
          OR ($3='history' AND (e.status IN ('completed','cancelled') OR e.expires_at<=now()))
          OR ($3='mine' AND (e.creator_id=$4 OR e.responder_id=$4)))
        ORDER BY e.id DESC LIMIT $5""", cid, before, view, uid, limit+1)
    return {'name': circle['name'], 'owner_id': circle['owner_id'],
            'materials': list(exchange.MATERIALS.values()),
            'posts': [exchange.public(row, uid) for row in rows[:limit]],
            'next_before': rows[limit-1]['id'] if len(rows)>limit else None}


@router.post('', status_code=201)
async def create(cid: str, body: CreatePost, uid: str = Depends(current_user)):
    if body.material_id not in exchange.MATERIALS:
        raise HTTPException(422, 'Choose a compostable material or one of the listed help tasks')
    async with db.pool().acquire() as conn, conn.transaction():
        await lock_group(conn, cid, uid)
        # Serialize create retries and the active-post limit across groups.
        await conn.fetchval('SELECT user_id FROM user_state WHERE user_id=$1 FOR UPDATE', uid)
        payload = {**body.model_dump(), 'circle_id': cid}
        previous = await conn.fetchrow('SELECT id,create_payload FROM exchange_posts WHERE creator_id=$1 AND request_id=$2', uid, body.request_id)
        if previous:
            if previous['create_payload'] != payload:
                raise HTTPException(409, 'This post was already saved with different details')
            return exchange.public(await exchange.post(conn, cid, previous['id']), uid)
        count = await conn.fetchval("""SELECT count(*) FROM exchange_posts WHERE creator_id=$1
            AND status IN ('open','reserved') AND expires_at>now()""", uid)
        if count >= 10:
            raise HTTPException(409, 'You can have 10 active exchange posts. Close an older post first')
        pid = await conn.fetchval("""INSERT INTO exchange_posts(circle_id,creator_id,request_id,create_payload,kind,material_id,quantity,details)
            VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id""", cid, uid, body.request_id, payload,
            body.kind, body.material_id, body.quantity, body.details)
        return exchange.public(await exchange.post(conn, cid, pid), uid)


@router.post('/{pid}/claim')
async def claim(cid: str, pid: int, body: Claim, uid: str = Depends(current_user)):
    async with db.pool().acquire() as conn, conn.transaction():
        await lock_group(conn, cid, uid)
        row = await exchange.post(conn, cid, pid)
        active(row)
        if row['creator_id'] == uid:
            raise HTTPException(400, 'You cannot reserve your own post')
        if row['status']=='reserved' and row['responder_id']==uid and row['reservation_id']==body.request_id:
            if row['claim_payload'] != body.model_dump():
                raise HTTPException(409, 'This reservation was already saved with different details')
            return exchange.public(row, uid)
        if row['status'] != 'open' or row['version'] != body.version:
            raise HTTPException(409, 'This post changed or was already reserved. Refresh to see its status')
        await conn.execute("""UPDATE exchange_posts SET status='reserved',responder_id=$2,reservation_id=$3,
            responder_note=$4,claim_payload=$5,version=version+1,expires_at=now()+interval '7 days' WHERE id=$1""",
            pid, uid, body.request_id, body.note, body.model_dump())
        return exchange.public(await exchange.post(conn, cid, pid), uid)


@router.post('/{pid}/note')
async def note(cid: str, pid: int, body: Note, uid: str = Depends(current_user)):
    async with db.pool().acquire() as conn, conn.transaction():
        await lock_group(conn, cid, uid)
        row = await exchange.post(conn, cid, pid)
        participant(row, uid, body.reservation_id)
        active(row)
        if row['status']!='reserved':
            raise HTTPException(409, 'Notes can only be changed during a reservation')
        column = 'creator_note' if uid==row['creator_id'] else 'responder_note'
        await conn.execute(f'UPDATE exchange_posts SET {column}=$2 WHERE id=$1', pid, body.note)
        return exchange.public(await exchange.post(conn, cid, pid), uid)


@router.post('/{pid}/confirm')
async def confirm(cid: str, pid: int, body: Reservation, uid: str = Depends(current_user)):
    async with db.pool().acquire() as conn, conn.transaction():
        await conn.execute("SET LOCAL TIME ZONE INTERVAL '+00:00' HOUR TO MINUTE")
        await lock_group(conn, cid, uid)
        row = await exchange.post(conn, cid, pid)
        participant(row, uid, body.reservation_id)
        if row['status']=='completed':
            return exchange.public(row, uid)
        active(row)
        if row['status']!='reserved':
            raise HTTPException(409, 'This exchange is no longer reserved')
        # Both must still belong to the group at the time of completion.
        await member(cid, row['creator_id'], conn=conn)
        await member(cid, row['responder_id'], conn=conn)
        column = 'creator_confirmed' if uid==row['creator_id'] else 'responder_confirmed'
        await conn.execute(f'UPDATE exchange_posts SET {column}=true WHERE id=$1', pid)
        row = await exchange.post(conn, cid, pid)
        if row['creator_confirmed'] and row['responder_confirmed']:
            paid = await exchange.rewards(conn, row)
            await conn.execute("""UPDATE exchange_posts SET status='completed',completed_at=now(),version=version+1,
                creator_xp=$2,responder_xp=$3 WHERE id=$1""", pid, paid[row['creator_id']], paid[row['responder_id']])
        return exchange.public(await exchange.post(conn, cid, pid), uid)


@router.post('/{pid}/release')
async def release(cid: str, pid: int, body: Reservation, uid: str = Depends(current_user)):
    async with db.pool().acquire() as conn, conn.transaction():
        await lock_group(conn, cid, uid)
        row = await exchange.post(conn, cid, pid)
        participant(row, uid, body.reservation_id)
        if uid!=row['responder_id']:
            raise HTTPException(403, 'Only the person who reserved can release it')
        if row['status']!='reserved' or row['creator_confirmed'] or row['responder_confirmed']:
            raise HTTPException(409, 'A confirmed handoff cannot be reopened. Cancel it if it did not happen')
        await conn.execute("""UPDATE exchange_posts SET status='open',version=version+1,responder_id=NULL,
            reservation_id=NULL,claim_payload=NULL,creator_note='',responder_note='' WHERE id=$1""", pid)
        return exchange.public(await exchange.post(conn, cid, pid), uid)


@router.post('/{pid}/cancel')
async def cancel(cid: str, pid: int, body: Cancel, uid: str = Depends(current_user)):
    async with db.pool().acquire() as conn, conn.transaction():
        circle = await lock_group(conn, cid, uid)
        row = await exchange.post(conn, cid, pid)
        if uid not in (row['creator_id'], row['responder_id'], circle['owner_id']):
            raise HTTPException(403, 'Only a participant or the group owner can close this post')
        if row['status']=='cancelled':
            return exchange.public(row, uid)
        if row['status']=='completed' or row['version']!=body.version:
            raise HTTPException(409, 'This post changed or is already completed. Refresh its status')
        await conn.execute("UPDATE exchange_posts SET status='cancelled',version=version+1 WHERE id=$1", pid)
        return exchange.public(await exchange.post(conn, cid, pid), uid)
