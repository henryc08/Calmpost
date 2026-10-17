import asyncio

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

import catalog
import frames as fr
import gemini
import mock_backend
from backend import Backend
from motion import MotionTrigger, Roi
from tests.synth import FakeCamera, background, frame_at
from watcher import Watcher


# --- motion trigger ---------------------------------------------------------------

def run_trigger(drop_at, seconds=6.0, fps=30):
    trig, bg, events = MotionTrigger(), background(), []
    for i in range(int(seconds * fps)):
        t = i / fps
        ev = trig.update(frame_at(t, bg, drop_at), t)
        if ev:
            events.append(ev)
    return events


def test_still_scene_never_triggers():
    assert run_trigger(None) == []


def test_drop_gives_one_start_then_end():
    events = run_trigger(drop_at=2.0)
    assert [e.kind for e in events] == ["start", "end"]
    start, end = events
    assert 2.0 <= start.t < 2.4                 # starts promptly
    landed = 2.0 + 0.6                          # the peel stops moving here
    assert landed + 0.8 - 0.1 <= end.t < landed + 0.8 + 0.4   # then 0.8 s of stillness


def test_grace_period_ignores_early_motion():
    trig, bg = MotionTrigger(), background()
    other = np.zeros_like(bg)
    assert trig.update(bg, 0.0) is None
    assert trig.update(other, 0.2) is None      # massive change, but inside the 0.5 s grace


def test_motion_outside_roi_is_ignored():
    trig, bg = MotionTrigger(roi=Roi(0.0, 0.0, 0.2, 0.2)), background()  # top-left corner only
    events = []
    for i in range(180):
        t = i / 30
        ev = trig.update(frame_at(t, bg, drop_at=2.0), t)  # the drop lands mid-frame
        if ev:
            events.append(ev)
    assert events == []


def test_roi_roundtrip(tmp_path):
    r = Roi(0.1, 0.2, 0.5, 0.4)
    r.save(tmp_path / "roi.json")
    assert Roi.load(tmp_path / "roi.json") == r
    assert Roi.load(tmp_path / "missing.json") == Roi()


# --- frames ---------------------------------------------------------------------

def test_sharpest_prefers_unblurred():
    img = background()
    blurred = cv2.GaussianBlur(img, (21, 21), 0)
    assert fr.sharpest([blurred, img, blurred]) is img


def test_jpeg_resized_to_max_side():
    big = np.zeros((2000, 3000, 3), np.uint8)
    decoded = cv2.imdecode(np.frombuffer(fr.jpeg(big), np.uint8), cv2.IMREAD_COLOR)
    assert max(decoded.shape[:2]) == 1024


# --- catalog & gemini parsing -----------------------------------------------------------

def test_catalog_categories_from_rules():
    assert catalog.category_of("banana_peel") == "green"
    assert catalog.category_of("cardboard") == "brown"
    assert catalog.category_of("cheese") == "avoid"
    assert catalog.category_of("unknown") is None
    assert catalog.amount_of(30) == "small" and catalog.amount_of(110) == "handful" and catalog.amount_of(400) == "large"


def test_parse_valid_item():
    items = gemini.parse({"items": [{"label": "banana peel", "catalog_id": "banana_peel", "est_grams": 110,
                                     "confidence": 0.82, "box_2d": [300, 400, 700, 800]}]})
    d = items[0]
    assert (d.catalog_id, d.category, d.amount, d.confidence) == ("banana_peel", "green", "handful", 0.82)
    assert d.box_2d == [300, 400, 700, 800]


def test_parse_rejects_bad_ids_hands_and_boxes():
    items = gemini.parse({"items": [
        {"label": "mystery goo", "catalog_id": "made_up", "confidence": 2, "box_2d": [900, 0, 100, 50]},
        {"label": "hand", "catalog_id": "unknown", "confidence": 0.9},
        {"label": "cheese", "catalog_id": "cheese", "confidence": 0.7},
        "garbage",
    ]})
    assert [i.label for i in items] == ["mystery goo", "cheese"]
    goo, cheese = items
    assert goo.catalog_id == "unknown" and goo.category is None and goo.confidence == 1.0 and goo.box_2d is None
    assert cheese.category == "avoid"     # rules say avoid, whatever Gemini thought
    assert cheese.est_grams is None       # catalog has 0 g for avoid items: no fake weight


def test_parse_empty_and_missing():
    assert gemini.parse({}) == [] and gemini.parse({"items": None}) == []


def test_schema_enum_is_catalog():
    enum = gemini.schema(catalog.ids())["properties"]["items"]["items"]["properties"]["catalog_id"]["enum"]
    assert "banana_peel" in enum and enum[-1] == "unknown" and len(enum) == len(catalog.load()) + 1


def test_identify_without_key_fails_soft():
    r = asyncio.run(gemini.Identifier(api_key="").identify(b"x", b"y"))
    assert r.ok is False and r.items == [] and "GEMINI_API_KEY" in r.error


# --- watcher (fake camera + fake Gemini) --------------------------------------------------------

class FakeIdentifier:
    def __init__(self):
        self.calls = []

    async def identify(self, before, after, hints=None):
        self.calls.append((before, after, hints))
        return gemini.Result(gemini.parse({"items": [{"label": "banana peel", "catalog_id": "banana_peel",
                                                      "confidence": 0.9}]}), 1200, ok=True, model="fake")


def test_watcher_reports_drop_with_before_and_after():
    cam, ident = FakeCamera(drop_at=3.0), FakeIdentifier()
    out = Watcher(cam, MotionTrigger(), ident, clock=cam.clock).watch(60)
    assert out.kind == "drop" and out.result.items[0].catalog_id == "banana_peel"
    assert len(ident.calls) == 1
    bg = background()

    def changed(img):  # share of pixels clearly different from the empty bin
        return (np.abs(img.astype(int) - bg).max(axis=2) > 40).mean()

    # BEFORE has no peel (and no hand); AFTER has the peel at rest, hand gone.
    assert changed(out.before) < 0.001
    assert changed(out.after) > 0.01
    assert out.after[int(480 * 0.55) - 5:int(480 * 0.55) + 5, 340:360].mean(axis=(0, 1))[2] > 180  # yellow peel


def test_watcher_closes_quietly_without_motion():
    cam, ident = FakeCamera(drop_at=None), FakeIdentifier()
    out = Watcher(cam, MotionTrigger(), ident, clock=cam.clock).watch(5)
    assert out.kind == "no_motion" and ident.calls == []


def test_watcher_camera_lost():
    cam = FakeCamera(drop_at=None, max_s=1.0)
    assert Watcher(cam, MotionTrigger(), FakeIdentifier(), clock=cam.clock).watch(60).kind == "camera_lost"


# --- backend client against the mock ---------------------------------------------------

@pytest.fixture
def api():
    mock_backend.sessions.clear()
    mock_backend.drops.clear()
    mock_backend.corrections.clear()
    with TestClient(mock_backend.app) as c:
        yield c


def test_full_drop_flow(api):
    be = Backend(bin_id="bin-001", client=api)
    assert be.active_session() is None
    api.post("/bins/bin-001/drops/session")
    s = be.active_session()
    assert s is not None
    items = [{"label": "banana peel", "catalog_id": "banana_peel", "category": "green", "est_grams": 110,
              "amount": "handful", "confidence": 0.82, "box_2d": [1, 2, 3, 4]}]
    drop = be.report_drop(s.id, items, fr.thumbnail_b64(background()), 1500, True, "m", None)
    assert be.active_session() is None                        # reporting closes the session
    pending = api.get("/bins/bin-001/drops/pending").json()
    assert pending[0]["id"] == drop["drop_id"] and pending[0]["items"][0]["category"] == "green"
    # User corrects it: the correction becomes a hint for next time.
    r = api.post(f"/drops/{drop['drop_id']}/confirm",
                 json={"items": [{"label": "apple core", "catalog_id": "apple_core", "category": "green"}]}).json()
    assert r["corrected"] is True
    assert "banana peel" in be.hints()[0]
    assert api.get("/bins/bin-001/drops/pending").json() == []


def test_backend_overrides_category_from_rules(api):
    be = Backend(bin_id="bin-001", client=api)
    api.post("/bins/bin-001/drops/session")
    s = be.active_session()
    be.report_drop(s.id, [{"label": "cheese", "catalog_id": "cheese", "category": "green", "confidence": 0.9}],
                   "", 10, True, "m", None)
    assert api.get("/bins/bin-001/drops/pending").json()[0]["items"][0]["category"] == "avoid"


def test_no_motion_close_and_dismiss(api):
    be = Backend(bin_id="bin-001", client=api)
    api.post("/bins/bin-001/drops/session")
    be.close_session(be.active_session().id, "no_motion")
    assert be.active_session() is None
    api.post("/bins/bin-001/drops/session")
    d = be.report_drop(be.active_session().id, [], "", 10, False, "m", "timed out")
    assert api.post(f"/drops/{d['drop_id']}/dismiss").json()["status"] == "dismissed"


def test_rearming_replaces_old_session(api):
    a = api.post("/bins/bin-001/drops/session").json()["session_id"]
    b = api.post("/bins/bin-001/drops/session").json()["session_id"]
    assert Backend(bin_id="bin-001", client=api).active_session().id == b != a
