"""Inventory is a history of confirmed inputs, not remaining finished compost."""
from datetime import datetime, timedelta, timezone

from .. import db
from ..catalog import food


def period_start(period: str) -> datetime:
    now = datetime.now(timezone.utc)
    if period == "week":
        return (now - timedelta(days=(now.weekday() + 1) % 7)).replace(hour=0, minute=0, second=0, microsecond=0)
    return datetime(1970, 1, 1, tzinfo=timezone.utc)


async def inventory(bin_id: str, user_id: str, period: str) -> dict:
    start = period_start(period)
    # Scope to the actual contributor as well as the bin: claiming a demo bin
    # does not transfer its former owner's compost or score to a new player.
    rows = await db.fetch(r"""SELECT catalog_id,
        CASE WHEN catalog_id IS NULL THEN lower(regexp_replace(trim(item), '\s+', ' ', 'g')) ELSE catalog_id END AS item_key,
        min(trim(item)) AS label, category,
        coalesce(sum(quantity_g),0)::bigint AS grams,
        coalesce(sum(piece_count),0)::bigint AS pieces,
        count(*) FILTER (WHERE piece_count IS NULL)::int AS uncounted_entries,
        count(*)::int AS entries,
        count(*) FILTER (WHERE source IN ('camera','photo'))::int AS vision_entries,
        max(time) AS last_added_at
        FROM add_log WHERE bin_id=$1 AND user_id=$2 AND time >= $3 AND time <= now()
        AND action='added' AND category IN ('green','brown') AND quantity_g > 0
        GROUP BY catalog_id,item_key,category ORDER BY grams DESC,item_key,category""", bin_id, user_id, start)
    items = []
    for row in rows:
        item = dict(row)
        known = food.BY_ID.get(item['catalog_id'])
        if known:
            item['label'] = known['name']
        items.append(item)
    score = await db.fetchrow("""SELECT coalesce(sum(xp),0)::int AS total_xp,
        coalesce(sum(xp) FILTER (WHERE kind='compost_added'),0)::int AS volume_xp
        FROM point_events WHERE user_id=$1 AND time >= $2 AND time <= now()""", user_id, start)
    return {"period": period, "items": items,
            "grams": sum(i['grams'] for i in items), "pieces": sum(i['pieces'] for i in items),
            "entries": sum(i['entries'] for i in items),
            "uncounted_entries": sum(i['uncounted_entries'] for i in items),
            "volume_xp": score['volume_xp'], "care_xp": score['total_xp'] - score['volume_xp'],
            "total_xp": score['total_xp']}
