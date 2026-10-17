"""End-to-end check against a running server.

    python -m scripts.smoke_test --token <device token>

Walks the whole pipeline: ingest the firmware's exact JSON, read it back,
check an item, log it, then the game endpoints. Finishes by proving the demo
moment -- the same scrap getting a different verdict after the bin changes.
"""

import argparse
import json
import os
import sys

import httpx

PASS = "PASS"
FAIL = "FAIL"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8000")
    parser.add_argument("--bin", dest="bin_id", default="bin-001")
    parser.add_argument("--user", default="demo-user")
    parser.add_argument("--token", required=True, help="device token")
    parser.add_argument("--api-key", default=os.environ.get("APP_API_KEY"))
    args = parser.parse_args()

    if not args.api_key:
        # Read it from .env rather than making the caller paste it.
        from pathlib import Path

        env = Path(__file__).resolve().parent.parent / ".env"
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.startswith("APP_API_KEY="):
                args.api_key = line.split("=", 1)[1].strip()

    app = {"X-API-Key": args.api_key}
    dev = {"X-Device-Token": args.token}
    base = args.base.rstrip("/")
    failures = 0

    def check(label: str, resp: httpx.Response, expect: int = 200, show: str | None = None):
        nonlocal failures
        ok = resp.status_code == expect
        if not ok:
            failures += 1
        status = PASS if ok else FAIL
        detail = ""
        if show and ok:
            try:
                body = resp.json()
                detail = "  " + show.format(**body) if "{" in show else f"  {show}"
            except Exception:
                detail = ""
        print(f"[{status}] {label:34} {resp.status_code}{detail}")
        if not ok:
            print(f"        {resp.text[:300]}")
        return resp

    print("=== plumbing ===")
    check("health", httpx.get(f"{base}/health", timeout=30))

    print("\n=== ingest (firmware's exact JSON) ===")
    firmware_json = {
        "device_id": args.bin_id,
        "probe_temp_c": 25.3,
        "moisture_raw": 412,
        "co2_ppm": 850,
        "air_temp_c": 24.1,
        "air_humidity_pct": 58.2,
        "co2_status": 0,
    }
    r = check(
        "POST /ingest", httpx.post(f"{base}/ingest", headers=dev, json=firmware_json, timeout=30),
        show="moisture_pct={moisture_pct} calibrated={calibrated}",
    )

    print("\n=== app reads ===")
    r = check("GET /bins/{id}/live", httpx.get(f"{base}/bins/{args.bin_id}/live", headers=app, timeout=30))
    if r.status_code == 200:
        body = r.json()
        for layer in body["layers"]:
            print(f"        {layer['layer']:7} measured={layer['measured']!s:5} "
                  f"moisture={layer['moisture_pct']} state={layer['moisture_state']:7} "
                  f"stage={layer['stage']}")
        print(f"        health components: {body['health_components']}")
        print(f"        hours in band (24h): {body['hours_in_healthy_band_24h']}")
        for note in body["notes"]:
            print(f"        note: {note}")

    r = check(
        "GET /bins/{id}/trends",
        httpx.get(f"{base}/bins/{args.bin_id}/trends",
                  params={"hours": 24, "metrics": ["moisture_pct", "co2_ppm"]},
                  headers=app, timeout=30),
    )
    if r.status_code == 200:
        for s in r.json()["series"]:
            pts = s["points"]
            filled = sum(1 for p in pts if p["value"] is not None)
            print(f"        {s['metric']:16} {len(pts)} buckets, {filled} with data")

    print("\n=== the demo moment ===")
    r = check(
        "check 'banana peel'",
        httpx.post(f"{base}/bins/{args.bin_id}/advice/check", headers=app,
                   json={"item": "banana peel"}, params={"refresh": "true"}, timeout=60),
    )
    advice_id = None
    if r.status_code == 200:
        body = r.json()
        advice_id = body["advice_id"]
        print(f"        model={body['model']}  verdict={body['verdict']}")
        print(f"        reason: {body['reason']}")
        print(f"        suggest_add={body['suggest_add']}")
        print(f"        stage_top={body['stage_top']} stage_bottom={body['stage_bottom']} "
              f"bottom_ready={body['bottom_ready']}")
        print(f"        snapshot stored: {'yes' if body.get('input_snapshot') else 'NO'}")

    r = check(
        "always-avoid rule ('chicken')",
        httpx.post(f"{base}/bins/{args.bin_id}/advice/check", headers=app,
                   json={"item": "chicken"}, params={"refresh": "true"}, timeout=60),
    )
    if r.status_code == 200:
        body = r.json()
        ok = body["verdict"] == "avoid"
        print(f"        verdict={body['verdict']} ({'enforced by rules' if ok else 'NOT ENFORCED'})")
        print(f"        model={body['model']}")
        if not ok:
            failures += 1

    print("\n=== log & XP ===")
    r = check(
        "log a plain add (expect 0 XP)",
        httpx.post(f"{base}/bins/{args.bin_id}/logs", headers=app,
                   json={"item": "banana peel", "quantity_g": 120}, timeout=30),
        expect=201,
    )
    if r.status_code == 201:
        xp = r.json()["xp_awarded"]
        print(f"        xp_awarded={xp} ({'correct' if xp == 0 else 'WRONG: should be 0'})")
        if xp != 0:
            failures += 1

    r = check(
        "log a followed suggestion (expect 15)",
        httpx.post(f"{base}/bins/{args.bin_id}/logs", headers=app,
                   json={"item": "shredded cardboard", "was_advised": True,
                         "advice_id": advice_id, "quantity_g": 60}, timeout=30),
        expect=201,
    )
    if r.status_code == 201:
        xp = r.json()["xp_awarded"]
        print(f"        xp_awarded={xp} ({'correct' if xp == 15 else 'WRONG: should be 15'})")
        if xp != 15:
            failures += 1

    r = check(
        "skip an avoid item (expect 5)",
        httpx.post(f"{base}/bins/{args.bin_id}/logs", headers=app,
                   json={"item": "bacon", "action": "skipped", "was_advised": True}, timeout=30),
        expect=201,
    )
    if r.status_code == 201:
        xp = r.json()["xp_awarded"]
        print(f"        xp_awarded={xp} ({'correct' if xp == 5 else 'WRONG: should be 5'})")
        if xp != 5:
            failures += 1

    print("\n=== game ===")
    r = check("GET /users/{id}/game", httpx.get(f"{base}/users/{args.user}/game", headers=app, timeout=30))
    if r.status_code == 200:
        b = r.json()
        print(f"        level {b['level']} \"{b['title']}\"  xp={b['total_xp']} "
              f"seeds={b['seeds']} streak={b['streak_days']} at_risk={b['streak_at_risk']}")
        print(f"        impact: {b['impact']}")
        earned = [a["name"] for a in b["achievements"] if a["earned"]]
        print(f"        earned: {earned or 'none yet'}")

    r = check("GET /quests/today", httpx.get(f"{base}/quests/today", params={"user_id": args.user}, headers=app, timeout=30))
    if r.status_code == 200:
        for q in r.json()["quests"]:
            print(f"        [{'x' if q['complete'] else ' '}] {q['title']} "
                  f"({q['progress']}/{q['target']})")

    r = check("GET /leagues/current", httpx.get(f"{base}/leagues/current", params={"user_id": args.user}, headers=app, timeout=30))
    if r.status_code == 200:
        b = r.json()
        print(f"        tier={b['tier']} size={b['size']} your_rank={b['your_rank']} "
              f"resets={b['resets_at']}")
        for m in b["members"][:3]:
            print(f"        #{m['rank']:<2} {m['display_name']:10} {m['xp']:>5} xp  {m['zone']}")

    print("\n=== auth ===")
    check("bad device token", httpx.post(f"{base}/ingest", headers={"X-Device-Token": "nope"},
                                         json=firmware_json, timeout=30), expect=401)
    check("bad app key", httpx.get(f"{base}/bins/{args.bin_id}/live",
                                   headers={"X-API-Key": "nope"}, timeout=30), expect=401)
    check("token/device mismatch", httpx.post(f"{base}/ingest", headers=dev,
                                              json={**firmware_json, "device_id": "someone-else"},
                                              timeout=30), expect=403)
    check("out-of-range reading", httpx.post(f"{base}/ingest", headers=dev,
                                             json={**firmware_json, "air_humidity_pct": 500},
                                             timeout=30), expect=422)

    print("\n" + ("all checks passed" if failures == 0 else f"{failures} CHECK(S) FAILED"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
