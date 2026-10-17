"""End-to-end tests for the camera drop-in router (AGENTS.md 2.4).

Uses the shared fixture in conftest.py: a fresh database per test with the
real schema. See conftest.py for how the database is provided.
"""

import base64

import pytest

from app.models import AdviceResponse
from app.routers import advice
from tests.conftest import needs_db

pytestmark = needs_db

JPEG = base64.b64encode(b"\xff\xd8\xff\xe0fake-jpeg\xff\xd9").decode()


def arm(c):
    r = c.post("/bins/bin-001/drops/session")
    assert r.status_code == 201
    return r.json()["session_id"]


def report(c, sid, items=None, **kw):
    body = {"session_id": sid, "items": items if items is not None else [
        {"label": "banana peel", "catalog_id": "banana_peel", "category": "green", "est_grams": 110,
         "amount": "handful", "confidence": 0.82, "box_2d": [480, 440, 610, 650]}],
        "thumbnail_jpeg_b64": JPEG, "latency_ms": 2100, "gemini_ok": True, "model": "gemini-2.5-flash", **kw}
    return c.post("/bins/bin-001/drops", json=body)


# --- auth & sessions ------------------------------------------------------------

def test_requires_api_key(c):
    assert c.post("/bins/bin-001/drops/session", headers={"X-API-Key": "wrong"}).status_code == 401


def test_arm_and_poll(c):
    assert c.get("/bins/bin-001/drops/session/active").status_code == 204
    sid = arm(c)
    assert c.get("/bins/bin-001/drops/session/active").json()["session_id"] == sid
    assert c.get(f"/bins/bin-001/drops/sessions/{sid}").json()["open"] is True


def test_rearm_replaces_session(c):
    a, b = arm(c), arm(c)
    assert c.get("/bins/bin-001/drops/session/active").json()["session_id"] == b
    assert c.get(f"/bins/bin-001/drops/sessions/{a}").json()["close_reason"] == "replaced"


def test_unknown_bin_and_session(c):
    assert c.post("/bins/nope/drops/session").status_code == 404
    assert report(c, "nosuch").status_code == 404


def test_no_motion_close(c):
    sid = arm(c)
    assert c.post(f"/bins/bin-001/drops/session/{sid}/close", json={"reason": "no_motion"}).status_code == 200
    assert c.get("/bins/bin-001/drops/session/active").status_code == 204
    assert c.get(f"/bins/bin-001/drops/sessions/{sid}").json()["close_reason"] == "no_motion"


# --- report -------------------------------------------------------------------------

def test_report_creates_pending_and_closes_session(c):
    sid = arm(c)
    r = report(c, sid)
    assert r.status_code == 201 and r.json()["status"] == "pending"
    assert c.get("/bins/bin-001/drops/session/active").status_code == 204
    p = c.get("/bins/bin-001/drops/pending").json()
    assert len(p) == 1 and p[0]["items"][0]["label"] == "banana peel"
    assert base64.b64decode(p[0]["thumbnail_jpeg_b64"]).startswith(b"\xff\xd8")


def test_rules_override_camera_category(c):
    sid = arm(c)
    report(c, sid, items=[{"label": "chicken bones", "catalog_id": "unknown", "category": "green", "confidence": 0.9},
                          {"label": "shredded cardboard", "catalog_id": "cardboard", "confidence": 0.7}])
    items = c.get("/bins/bin-001/drops/pending").json()[0]["items"]
    assert items[0]["category"] == "avoid"      # rules win over the camera
    assert items[1]["category"] == "brown"      # rules fill in a missing category


def test_gemini_failure_still_reported(c):
    sid = arm(c)
    r = report(c, sid, items=[], gemini_ok=False, error="timed out after 4s")
    assert r.status_code == 201
    p = c.get("/bins/bin-001/drops/pending").json()[0]
    assert p["gemini_ok"] is False and p["items"] == []


def test_bad_payloads(c):
    sid = arm(c)
    assert report(c, sid, items=[{"label": "x", "confidence": 3}]).status_code == 422
    assert report(c, sid, thumbnail_jpeg_b64="not base64!!").status_code == 422
    big = base64.b64encode(b"x" * 300_000).decode()
    assert report(c, sid, thumbnail_jpeg_b64=big).status_code == 413


# --- confirm / dismiss -----------------------------------------------------------

def test_confirm_logs_camera_add_with_volume_xp(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    r = c.post(f"/drops/{drop_id}/confirm", json={"items": [
        {"label": "banana peel", "catalog_id": "banana_peel", "category": "green", "amount": "handful"}]})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["corrected"] is False
    log = body["items"][0]["log"]
    assert log["source"] == "camera" and log["xp_awarded"] == 5 and log["quantity_g"] == 110
    assert body["items"][0]["verdict"] is None  # no readings yet in this test DB
    logs = c.get("/bins/bin-001/logs").json()
    assert logs[0]["source"] == "camera"
    assert c.get("/bins/bin-001/drops/pending").json() == []


def test_identical_confirmation_retry_returns_original_receipt(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    item = {"items": [{"label": "banana peel", "catalog_id": "banana_peel", "category": "green"}]}
    first = c.post(f"/drops/{drop_id}/confirm", json=item)
    retry = c.post(f"/drops/{drop_id}/confirm", json=item)
    assert first.status_code == retry.status_code == 200
    assert first.json() == retry.json()
    assert len(c.get('/bins/bin-001/logs').json()) == 1
    assert len(c.get("/bins/bin-001/logs").json()) == 1


def test_removed_keep_out_item_earns_skip_xp(c):
    sid = arm(c)
    drop_id = report(c, sid, items=[{"label": "cheese", "catalog_id": "cheese", "confidence": 0.8}]).json()["drop_id"]
    r = c.post(f"/drops/{drop_id}/confirm", json={"items": [
        {"label": "cheese", "catalog_id": "cheese", "category": "green", "removed": True}]}).json()
    log = r["items"][0]["log"]
    assert log["category"] == "avoid" and log["action"] == "skipped" and log["xp_awarded"] == 5


def test_correction_becomes_hint(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    r = c.post(f"/drops/{drop_id}/confirm", json={"items": [
        {"label": "apple core", "catalog_id": "apple_core", "category": "green"}]}).json()
    assert r["corrected"] is True
    assert c.get("/bins/bin-001/drops/hints").json()["hints"] == ['looked like "banana peel", was "apple core"']


def test_dismiss_and_accuracy(c):
    d1 = report(c, arm(c)).json()["drop_id"]
    d2 = report(c, arm(c)).json()["drop_id"]
    c.post(f"/drops/{d1}/confirm", json={"items": [{"label": "banana peel", "catalog_id": "banana_peel"}]})
    assert c.post(f"/drops/{d2}/dismiss").json()["status"] == "dismissed"
    assert c.post(f"/drops/{d2}/dismiss").status_code == 409
    a = c.get("/bins/bin-001/drops/accuracy").json()
    assert (a["drops"], a["confirmed"], a["dismissed"], a["confirmed_as_seen_pct"]) == (2, 1, 1, 100)
    assert any("false trigger" in h for h in c.get("/bins/bin-001/drops/hints").json()["hints"])


def test_confirm_returns_verdict_when_available(c, monkeypatch):
    async def fake_advise(bin_id, item, refresh):
        return AdviceResponse.model_construct(verdict="great", item=item, reason="dry bin, wet scrap")
    # Confirmation deliberately uses local rules, never a network Gemini call.
    from tests.conftest import ingest_series, raw_for
    ingest_series(c, moisture_raw=raw_for(25), probe_temp=24, co2=750, minutes=0)
    drop_id = report(c, arm(c)).json()["drop_id"]
    r = c.post(f"/drops/{drop_id}/confirm", json={"items": [
        {"label": "banana peel", "catalog_id": "banana_peel", "category": "green"}]}).json()
    assert r["items"][0]["verdict"]["verdict"] == "great"


def test_mixed_drop_the_camera_could_not_separate(c):
    """The camera reports one 'mixed_scraps' item; the user says what was in
    it, including meat they took back out. Same pop-up, same drop."""
    sid = arm(c)
    drop_id = report(c, sid, items=[{"label": "mixed scraps: rice, peels", "catalog_id": "mixed_scraps", "confidence": 0.41}]).json()["drop_id"]
    pending = c.get("/bins/bin-001/drops/pending").json()[0]
    assert pending["items"][0]["category"] == "green"  # the catalog's type, from the rules

    r = c.post(f"/drops/{drop_id}/confirm", json={"items": [
        {"label": "Mixed food scraps", "catalog_id": "mixed_scraps", "category": "green", "amount": "large"},
        {"label": "Meat scraps", "catalog_id": "meat", "category": "avoid", "amount": "small", "removed": True},
    ]}).json()
    added, meat = (i["log"] for i in r["items"])
    assert added["category"] == "green" and added["quantity_g"] == 250 and added["xp_awarded"] == 12
    assert meat["action"] == "skipped" and meat["xp_awarded"] == 5
    assert r["corrected"] is True


def test_a_mix_mentioning_meat_is_never_green(c):
    """Rules over the camera: a 'mixed' label naming a keep-out food is avoid."""
    report(c, arm(c), items=[{"label": "mixed scraps with chicken", "catalog_id": "mixed_scraps", "category": "green", "confidence": 0.5}])
    assert c.get("/bins/bin-001/drops/pending").json()[0]["items"][0]["category"] == "avoid"
# --- history and photos ---------------------------------------------------------
#
# /drops/pending shows only what is still waiting, and only from the last hour.
# Before these routes a resolved drop and its photo were unreachable: the bytes
# sat in Tiger for the 30-day retention window with nothing able to read them.

def test_a_resolved_drop_is_still_reachable(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    assert c.post(f"/drops/{drop_id}/dismiss").status_code == 200

    # Gone from pending, which is correct and was the whole problem.
    assert c.get("/bins/bin-001/drops/pending").json() == []

    hist = c.get("/bins/bin-001/drops/history").json()
    assert [d["id"] for d in hist["drops"]] == [drop_id]
    assert hist["drops"][0]["status"] == "dismissed"
    assert hist["drops"][0]["has_photo"] is True
    assert hist["drops"][0]["resolved_at"] is not None


def test_history_carries_both_the_guess_and_what_the_user_settled_on(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    c.post(f"/drops/{drop_id}/confirm",
           json={"items": [{"label": "apple core", "catalog_id": "apple_core", "category": "green"}]})

    d = c.get("/bins/bin-001/drops/history").json()["drops"][0]
    assert d["items"][0]["label"] == "banana peel", "what the camera guessed"
    assert d["final_items"][0]["label"] == "apple core", "what the user said it was"
    assert d["corrected"] is True


def test_history_does_not_inline_photos(c):
    """Twenty base64 thumbnails is megabytes on a hotspot."""
    report(c, arm(c))
    d = c.get("/bins/bin-001/drops/history").json()["drops"][0]
    assert "thumbnail_jpeg_b64" not in d
    assert d["has_photo"] is True


def test_the_photo_comes_back_as_a_real_jpeg(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    r = c.get(f"/drops/{drop_id}/photo")
    assert r.status_code == 200
    assert r.headers["content-type"] == "image/jpeg"
    assert r.content == base64.b64decode(JPEG)
    assert "immutable" in r.headers.get("cache-control", "")


def test_a_drop_with_no_photo_says_so_rather_than_serving_empty_bytes(c):
    drop_id = report(c, arm(c), thumbnail_jpeg_b64="").json()["drop_id"]
    assert c.get("/bins/bin-001/drops/history").json()["drops"][0]["has_photo"] is False
    assert c.get(f"/drops/{drop_id}/photo").status_code == 404


def test_one_drop_inlines_its_thumbnail_whatever_its_status(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    c.post(f"/drops/{drop_id}/dismiss")
    d = c.get(f"/drops/{drop_id}").json()
    assert d["id"] == drop_id and d["status"] == "dismissed"
    assert d["thumbnail_jpeg_b64"] == JPEG


def test_history_pages_newest_first(c):
    ids = [report(c, arm(c)).json()["drop_id"] for _ in range(3)]

    first = c.get("/bins/bin-001/drops/history", params={"limit": 2}).json()
    assert [d["id"] for d in first["drops"]] == [ids[2], ids[1]], "newest first"
    assert first["next_before"] is not None

    rest = c.get("/bins/bin-001/drops/history",
                 params={"limit": 2, "before": first["next_before"]}).json()
    assert [d["id"] for d in rest["drops"]] == [ids[0]]
    assert rest["next_before"] is None, "nothing older left"


def test_history_can_be_filtered_by_status(c):
    kept = report(c, arm(c)).json()["drop_id"]
    tossed = report(c, arm(c)).json()["drop_id"]
    c.post(f"/drops/{tossed}/dismiss")

    pend = c.get("/bins/bin-001/drops/history", params={"status": "pending"}).json()
    assert [d["id"] for d in pend["drops"]] == [kept]
    gone = c.get("/bins/bin-001/drops/history", params={"status": "dismissed"}).json()
    assert [d["id"] for d in gone["drops"]] == [tossed]


def test_history_and_photo_need_the_api_key(c):
    drop_id = report(c, arm(c)).json()["drop_id"]
    bad = {"X-API-Key": "wrong"}
    assert c.get("/bins/bin-001/drops/history", headers=bad).status_code == 401
    assert c.get(f"/drops/{drop_id}/photo", headers=bad).status_code == 401
    assert c.get(f"/drops/{drop_id}", headers=bad).status_code == 401


def test_unknown_drop_and_bin_are_404(c):
    assert c.get("/drops/999999").status_code == 404
    assert c.get("/drops/999999/photo").status_code == 404
    assert c.get("/bins/nope/drops/history").status_code == 404


# --- single photo submission ----------------------------------------------------
#
# The camera decides for itself that something arrived; this is the user
# pointing a phone at something. It becomes an ordinary pending drop, so
# confirm/dismiss/history/XP all work on it unchanged -- only `source` differs.

REAL_JPEG = base64.b64encode(
    bytes.fromhex("ffd8ffe000104a46494600010100000100010000ffdb004300"
                  "0806060708070807090909") + b"\x00" * 40 + bytes.fromhex("ffd9")
).decode()


def stub_identify(monkeypatch, items, model="gemini-2.5-flash", error=None, seen=None):
    from app.config import get_settings
    from app.services import identify

    async def fake(jpeg):
        if seen is not None:
            seen["jpeg"] = jpeg
        return items, model, error

    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    get_settings.cache_clear()
    monkeypatch.setattr(identify, "identify", fake)


def submit(c, b64=None):
    return c.post("/bins/bin-001/drops/photo", json={"image_jpeg_b64": b64 or REAL_JPEG})


def test_a_submitted_photo_becomes_a_pending_drop(c, monkeypatch):
    seen = {}
    stub_identify(monkeypatch, [
        {"label": "banana peel", "catalog_id": "banana_peel", "category": "green",
         "est_grams": 110.0, "confidence": 0.93, "box_2d": [100, 200, 800, 700]}], seen=seen)

    r = submit(c)
    assert r.status_code == 201
    d = r.json()

    assert d["status"] == "pending"
    assert d["source"] == "photo", "distinguishable from a camera detection"
    assert d["items"][0]["label"] == "banana peel"
    assert d["items"][0]["box_2d"] == [100, 200, 800, 700]
    assert d["gemini_ok"] is True
    # The photo is kept, so it can be shown and reused as Trunc context.
    assert d["thumbnail_jpeg_b64"] == REAL_JPEG
    assert seen["jpeg"] == base64.b64decode(REAL_JPEG)

    # It shows up exactly where a camera drop would.
    assert [p["id"] for p in c.get("/bins/bin-001/drops/pending").json()] == [d["id"]]


def test_a_submitted_photo_confirms_through_the_normal_path(c, monkeypatch):
    """No second confirm endpoint: the XP rules and add_log rows are shared."""
    stub_identify(monkeypatch, [
        {"label": "banana peel", "catalog_id": "banana_peel", "category": "green",
         "est_grams": 110.0, "confidence": 0.93, "box_2d": None}])
    drop_id = submit(c).json()["id"]

    r = c.post(f"/drops/{drop_id}/confirm",
               json={"items": [{"label": "banana peel", "catalog_id": "banana_peel",
                                "category": "green", "amount": "handful"}]})
    assert r.status_code == 200
    assert r.json()["items"][0]["log"]["source"] == "photo"
    # The merged confirmation path keeps both photo attribution and the
    # existing atomic receipt: a lost response must not award volume twice.
    retry = c.post(f"/drops/{drop_id}/confirm",
                   json={"items": [{"label": "banana peel", "catalog_id": "banana_peel",
                                    "category": "green", "amount": "handful"}]})
    assert retry.status_code == 200
    assert retry.json() == r.json()

    d = c.get(f"/drops/{drop_id}").json()
    assert d["status"] == "confirmed" and d["source"] == "photo"


def test_photos_do_not_count_towards_camera_accuracy(c, monkeypatch):
    """/drops/accuracy is a statement about the CAMERA. Counting photos the
    user deliberately framed would flatter it."""
    stub_identify(monkeypatch, [
        {"label": "banana peel", "catalog_id": "banana_peel", "category": "green",
         "est_grams": 110.0, "confidence": 0.93, "box_2d": None}])

    camera_drop = report(c, arm(c)).json()["drop_id"]
    c.post(f"/drops/{camera_drop}/dismiss")
    submit(c)  # a photo, which must not appear in the stat

    acc = c.get("/bins/bin-001/drops/accuracy").json()
    assert acc["drops"] == 1, "only the camera detection"
    assert acc["dismissed"] == 1


def test_gemini_failing_still_keeps_the_photo_for_the_user_to_name(c, monkeypatch):
    """An empty item list is a real answer: the sheet already handles an
    unnamed item, so this needs no new state."""
    stub_identify(monkeypatch, [], model="rules-fallback", error="429 quota exhausted")

    d = submit(c).json()

    assert d["items"] == []
    assert d["gemini_ok"] is False
    assert d["error"] == "429 quota exhausted"
    assert d["thumbnail_jpeg_b64"] == REAL_JPEG, "the photo is not thrown away"
    assert d["status"] == "pending", "still answerable by hand"


def test_a_photo_drop_records_how_long_identification_took(c, monkeypatch):
    stub_identify(monkeypatch, [])
    assert submit(c).json()["latency_ms"] >= 0


def test_bad_images_are_rejected_clearly(c, monkeypatch):
    from app.services import identify

    stub_identify(monkeypatch, [])
    assert submit(c, b64="not base64 at all!!").status_code == 422
    assert c.post("/bins/bin-001/drops/photo", json={"image_jpeg_b64": ""}).status_code == 422

    too_big = base64.b64encode(b"\xff\xd8" + b"\x00" * identify.MAX_PHOTO_BYTES).decode()
    r = submit(c, b64=too_big)
    assert r.status_code == 413
    assert "downscale" in r.json()["detail"], "says what to do about it"


def test_photo_submission_needs_the_api_key_and_a_real_bin(c, monkeypatch):
    stub_identify(monkeypatch, [])
    assert c.post("/bins/bin-001/drops/photo", headers={"X-API-Key": "wrong"},
                  json={"image_jpeg_b64": REAL_JPEG}).status_code == 401
    assert c.post("/bins/nope/drops/photo",
                  json={"image_jpeg_b64": REAL_JPEG}).status_code == 404


# --- what the model is allowed to decide ----------------------------------------

def test_the_rules_categorise_a_photo_not_the_model():
    """The prompt forbids the model from judging; a keep-out item must come
    back as avoid even though the model only supplied a label."""
    from app.services import identify

    items = identify.parse({"items": [
        {"label": "cheese rind", "catalog_id": "unknown", "confidence": 0.8},
        {"label": "banana peel", "catalog_id": "banana_peel", "confidence": 0.9},
        {"label": "shredded cardboard", "catalog_id": "cardboard", "confidence": 0.7},
    ]})

    by_label = {i["label"]: i for i in items}
    assert by_label["cheese rind"]["category"] == "avoid"
    assert by_label["banana peel"]["category"] == "green"
    assert by_label["shredded cardboard"]["category"] == "brown"


def test_hands_and_the_bin_are_not_reported_as_items():
    from app.services import identify

    items = identify.parse({"items": [
        {"label": "hand", "catalog_id": "unknown", "confidence": 0.99},
        {"label": "banana peel", "catalog_id": "banana_peel", "confidence": 0.9},
    ]})
    assert [i["label"] for i in items] == ["banana peel"]


def test_an_off_schema_answer_is_corrected_rather_than_trusted():
    from app.services import identify

    items = identify.parse({"items": [
        {"label": "mystery", "catalog_id": "not_a_real_id", "confidence": 5,
         "est_grams": 99999, "box_2d": [10, 10, 5, 5]},
    ]})

    it = items[0]
    assert it["catalog_id"] == "unknown", "an invented id is not trusted"
    assert it["confidence"] == 1.0, "clamped"
    assert it["est_grams"] is None, "absurd weight dropped"
    assert it["box_2d"] is None, "inverted box dropped"
    assert it["category"] is None, "unknown, not guessed"


def test_at_most_four_items_come_back():
    from app.services import identify
    raw = {"items": [{"label": f"item {i}", "catalog_id": "unknown", "confidence": 0.5}
                     for i in range(9)]}
    assert len(identify.parse(raw)) == 4
