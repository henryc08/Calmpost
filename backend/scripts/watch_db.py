"""Watch rows land in Tiger Data, live.

Reads straight from the database -- not the API -- so it answers exactly one
question: "is data actually reaching Tiger Data?"

    python -m scripts.watch_db                  # tail new readings
    python -m scripts.watch_db --stats          # one-shot summary, then exit
    python -m scripts.watch_db --table add_log  # watch a different table

Run it in one terminal with the serial bridge in another: every line the
bridge sends should appear here within a second or two.
"""

import argparse
import asyncio
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import db  # noqa: E402

TABLES = {
    "readings": (
        """
        SELECT time, probe_temp_c, moisture_raw, moisture_pct, co2_ppm,
               air_temp_c, air_humidity_pct, co2_status
        FROM readings
        WHERE time > $1 AND bin_id = $2
        ORDER BY time
        """,
        lambda r: (
            f"temp={_n(r['probe_temp_c'], 2, 'C'):>8}  "
            f"raw={r['moisture_raw'] if r['moisture_raw'] is not None else '-':>4}  "
            f"moisture={_n(r['moisture_pct'], 1, '%'):>7}  "
            f"co2={_n(r['co2_ppm'], 0, 'ppm'):>8}  "
            f"air={_n(r['air_temp_c'], 1, 'C'):>7}  "
            f"rh={_n(r['air_humidity_pct'], 1, '%'):>7}  "
            f"status={r['co2_status'] if r['co2_status'] is not None else 'null'}"
        ),
    ),
    "add_log": (
        """
        SELECT time, item, category, action, quantity_g, was_advised
        FROM add_log WHERE time > $1 AND bin_id = $2 ORDER BY time
        """,
        lambda r: (
            f"{r['action']:7} {r['item']:24} {r['category']:7} "
            f"{str(r['quantity_g'] or '-'):>5}g  advised={r['was_advised']}"
        ),
    ),
    "advice": (
        """
        SELECT time, item, model, verdict, reason
        FROM advice WHERE time > $1 AND bin_id = $2 ORDER BY time
        """,
        lambda r: (
            f"{(r['item'] or '(whole bin)'):22} -> {r['verdict'] or '-':16} "
            f"[{r['model']}]  {(r['reason'] or '')[:60]}"
        ),
    ),
    "point_events": (
        """
        SELECT time, kind, xp, seeds, user_id
        FROM point_events WHERE time > $1 AND bin_id = $2 ORDER BY time
        """,
        lambda r: f"{r['kind']:22} xp={r['xp']:>4} seeds={r['seeds']:>4}  {r['user_id']}",
    ),
}


def _n(value, places: int, unit: str) -> str:
    """Render a number, or a visible dash for NULL -- a null reading is
    information (a failed sensor), not something to hide behind a 0."""
    if value is None:
        return "-"
    return f"{value:.{places}f}{unit}"


async def stats(bin_id: str) -> None:
    r = await db.fetchrow(
        """
        SELECT count(*) AS n, min(time) AS oldest, max(time) AS newest,
               count(*) FILTER (WHERE time > now() - interval '1 minute')  AS last_min,
               count(*) FILTER (WHERE time > now() - interval '1 hour')    AS last_hour,
               count(*) FILTER (WHERE co2_status <> 0)                     AS co2_errors,
               count(*) FILTER (WHERE moisture_raw IS NULL)                AS no_moisture,
               count(*) FILTER (WHERE probe_temp_c IS NULL)                AS no_probe_temp
        FROM readings WHERE bin_id = $1
        """,
        bin_id,
    )
    if r is None or r["n"] == 0:
        print(f"no readings at all for {bin_id}.")
        print("  - is the serial bridge running?   python examples/serial_bridge.py --port COM3")
        print("  - is the bin registered?          python -m scripts.init_db --bin " + bin_id)
        return

    age = datetime.now(timezone.utc) - r["newest"]
    print(f"bin {bin_id}")
    print(f"  total readings   : {r['n']}")
    print(f"  oldest           : {r['oldest']}")
    print(f"  newest           : {r['newest']}  ({int(age.total_seconds())}s ago)")
    print(f"  last minute      : {r['last_min']}")
    print(f"  last hour        : {r['last_hour']}")
    print(f"  CO2 error rows   : {r['co2_errors']}")
    print(f"  missing moisture : {r['no_moisture']}")
    print(f"  missing probe temp: {r['no_probe_temp']}")

    # A gap of more than a couple of minutes means nothing is feeding it.
    if age.total_seconds() > 120:
        print("\n  >> nothing has arrived for over 2 minutes: the bridge is not running,")
        print("     or the board is unplugged / its port is held by the Serial Monitor.")
    else:
        print("\n  >> data is flowing.")

    cal = await db.fetchrow(
        "SELECT moisture_raw_dry, moisture_raw_wet, calibrated FROM bins WHERE bin_id = $1",
        bin_id,
    )
    if cal:
        print(f"\n  calibration: dry={cal['moisture_raw_dry']} wet={cal['moisture_raw_wet']} "
              f"calibrated={cal['calibrated']}")
        if not cal["calibrated"]:
            print("     moisture percentages are rough until you calibrate (see TESTING.md)")


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", dest="bin_id", default="bin-001")
    parser.add_argument("--table", choices=sorted(TABLES), default="readings")
    parser.add_argument("--stats", action="store_true", help="summary, then exit")
    parser.add_argument("--interval", type=float, default=1.0)
    args = parser.parse_args()

    await db.connect()

    if args.stats:
        await stats(args.bin_id)
        await db.disconnect()
        return

    await stats(args.bin_id)
    query, fmt = TABLES[args.table]

    # Start from now, so the tail shows only rows that arrive from here on.
    row = await db.fetchrow(f"SELECT max(time) AS t FROM {args.table} WHERE bin_id = $1", args.bin_id)
    since = (row and row["t"]) or datetime.now(timezone.utc)

    print(f"\nwatching {args.table} for {args.bin_id} -- Ctrl+C to stop\n")
    seen = 0
    try:
        while True:
            rows = await db.fetch(query, since, args.bin_id)
            for r in rows:
                since = r["time"]
                seen += 1
                print(f"  {r['time']:%H:%M:%S}  {fmt(r)}")
            if not rows:
                print(f"  ... nothing new ({seen} seen so far)", end="\r", flush=True)
            await asyncio.sleep(args.interval)
    except KeyboardInterrupt:
        print(f"\n\nstopped. {seen} new row(s) observed.")
    finally:
        await db.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
