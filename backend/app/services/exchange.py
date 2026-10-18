"""Private group exchanges with two-party confirmation and bounded ledger rewards.

Confirmations are attestations by the participants, not sensor verification.
Every mutation locks the circle before the post; reward locks use sorted player
IDs, so simultaneous exchanges cannot bypass either daily cap or deadlock.
"""
from datetime import datetime, timezone

from fastapi import HTTPException

from ..catalog.food import FOOD
from ..rules import game
from . import ledger

MATERIALS = {f['id']: {k: f[k] for k in ('id', 'name', 'category', 'note')}
             for f in FOOD if f['category'] in ('green', 'brown')}
MATERIALS.update({
    'finished_compost': {'id': 'finished_compost', 'name': 'Finished compost', 'category': 'finished',
                         'note': 'Sharing finished compost does not add scraps to your bin.'},
    'help_turning': {'id': 'help_turning', 'name': 'Help turning a bin', 'category': 'help',
                     'note': 'Agree what help is needed before meeting.'},
    'help_harvesting': {'id': 'help_harvesting', 'name': 'Help harvesting compost', 'category': 'help',
                        'note': 'Agree what help is needed before meeting.'},
})


def expired(row) -> bool:
    return row['status'] in ('open', 'reserved') and row['expires_at'] <= datetime.now(timezone.utc)


def public(row, uid: str) -> dict:
    participant = uid in (row['creator_id'], row['responder_id'])
    out = {key: row[key] for key in ('id', 'circle_id', 'kind', 'quantity', 'details', 'version',
           'created_at', 'expires_at', 'creator_confirmed', 'responder_confirmed', 'completed_at',
           'creator_xp', 'responder_xp')}
    out.update(status='expired' if expired(row) else row['status'], material=MATERIALS[row['material_id']],
               creator={'user_id': row['creator_id'], 'handle': row['creator_handle'], 'display_name': row['creator_name']},
               responder=None if row['responder_id'] is None else {
                   'user_id': row['responder_id'], 'handle': row['responder_handle'], 'display_name': row['responder_name']})
    if participant:
        out.update(reservation_id=row['reservation_id'], creator_note=row['creator_note'], responder_note=row['responder_note'])
    return out


SELECT = """SELECT e.*, c.handle creator_handle, u.display_name creator_name,
    r.handle responder_handle, v.display_name responder_name FROM exchange_posts e
    JOIN social_profiles c ON c.user_id=e.creator_id JOIN user_state u ON u.user_id=e.creator_id
    LEFT JOIN social_profiles r ON r.user_id=e.responder_id LEFT JOIN user_state v ON v.user_id=e.responder_id"""


async def post(conn, cid: str, post_id: int):
    row = await conn.fetchrow(SELECT + ' WHERE e.circle_id=$1 AND e.id=$2 FOR UPDATE OF e', cid, post_id)
    if row is None:
        raise HTTPException(404, 'Exchange not found')
    return row


async def rewards(conn, row) -> dict[str, int]:
    users = sorted([row['creator_id'], row['responder_id']])
    # The circle and post are already locked. Take both player locks in a
    # stable order before reading any caps, including across different groups.
    for uid in users:
        await conn.fetchval('SELECT user_id FROM user_state WHERE user_id=$1 FOR UPDATE', uid)
    day = await conn.fetchval("SELECT to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD')")
    key = f'exchange-pair:{users[0]}:{users[1]}:{day}'
    paid = {}
    for uid in users:
        earned = await conn.fetchval("""SELECT coalesce(sum(xp),0)::int FROM point_events
            WHERE user_id=$1 AND kind='exchange_completed' AND time>=date_trunc('day',now())""", uid)
        paid[uid] = await ledger.award(conn, uid, 'exchange_completed', xp=game.exchange_xp(earned),
            dedupe_key=key, meta={'exchange_id': row['id'], 'circle_id': row['circle_id']})
    return paid


async def remove_member(conn, cid: str, uid: str) -> None:
    """Called under the circle lock. Removed accounts cannot strand reservations."""
    await conn.execute("""UPDATE exchange_posts SET status='cancelled',version=version+1
        WHERE circle_id=$1 AND creator_id=$2 AND status IN ('open','reserved')""", cid, uid)
    await conn.execute("""UPDATE exchange_posts SET status='open',version=version+1,responder_id=NULL,
        reservation_id=NULL,claim_payload=NULL,creator_note='',responder_note=''
        WHERE circle_id=$1 AND responder_id=$2 AND status='reserved'
        AND NOT creator_confirmed AND NOT responder_confirmed""", cid, uid)
    await conn.execute("""UPDATE exchange_posts SET status='cancelled',version=version+1
        WHERE circle_id=$1 AND responder_id=$2 AND status='reserved'""", cid, uid)
