"""Stand-in for the backend's /drops endpoints until they exist in backend/.

    python mock_backend.py            # http://localhost:8090

In memory only. Routes match AGENT.md section 4, so the real backend (and
the app's ApiRepository) can copy this contract. Open http://localhost:8090
for a small page that plays the app's part: arm the camera, see the
"Something was added" pop-up data, confirm or dismiss.
"""

import asyncio
import json
import uuid
from datetime import datetime, timedelta, timezone

import uvicorn
from fastapi import FastAPI, HTTPException, Response
from fastapi.responses import HTMLResponse, StreamingResponse
from pydantic import BaseModel, Field

import catalog

ARM_SECONDS = 60

app = FastAPI(title="Calmpost drops (mock)")
sessions: dict[str, dict] = {}   # session_id -> {bin_id, expires_at, closed}
drops: dict[str, dict] = {}      # drop_id -> drop
corrections: list[str] = []


def now() -> datetime:
    return datetime.now(timezone.utc)


class DropItem(BaseModel):
    label: str
    catalog_id: str
    category: str | None = None
    est_grams: float | None = None
    amount: str | None = None
    confidence: float = Field(ge=0, le=1)
    box_2d: list[int] | None = None


class DropReport(BaseModel):
    session_id: str
    items: list[DropItem]
    thumbnail_jpeg_b64: str
    latency_ms: int
    gemini_ok: bool
    model: str = ""
    error: str | None = None


class CloseBody(BaseModel):
    reason: str


class ConfirmItem(BaseModel):
    label: str
    catalog_id: str
    category: str
    amount: str | None = None


class ConfirmBody(BaseModel):
    items: list[ConfirmItem]


# --- app side ------------------------------------------------------------------

@app.post("/bins/{bin_id}/drops/session", status_code=201)
def arm(bin_id: str):
    for s in sessions.values():
        if s["bin_id"] == bin_id:
            s["closed"] = True  # one armed session per bin
    sid = uuid.uuid4().hex[:12]
    sessions[sid] = {"bin_id": bin_id, "expires_at": now() + timedelta(seconds=ARM_SECONDS), "closed": False}
    return {"session_id": sid, "expires_at": sessions[sid]["expires_at"].isoformat()}


@app.get("/bins/{bin_id}/drops/pending")
def pending(bin_id: str):
    return [d for d in drops.values() if d["bin_id"] == bin_id and d["status"] == "pending"]


@app.get("/bins/{bin_id}/drops/stream")
async def stream(bin_id: str):
    """SSE: one `drop` event per new pending drop."""
    async def gen():
        seen: set[str] = set()
        while True:
            for d in pending(bin_id):
                if d["id"] not in seen:
                    seen.add(d["id"])
                    yield f"event: drop\ndata: {json.dumps(d)}\n\n"
            await asyncio.sleep(0.5)
    return StreamingResponse(gen(), media_type="text/event-stream")


@app.post("/drops/{drop_id}/confirm")
def confirm(drop_id: str, body: ConfirmBody):
    d = drops.get(drop_id)
    if d is None:
        raise HTTPException(404)
    guess = {(i["catalog_id"], i["label"]) for i in d["items"]}
    final = [i.model_dump() for i in body.items]
    corrected = guess != {(i["catalog_id"], i["label"]) for i in final}
    if corrected and d["items"]:
        corrections.append(f'looked like "{d["items"][0]["label"]}", was "{final[0]["label"]}"' if final else
                           f'"{d["items"][0]["label"]}" was a false trigger')
    d.update(status="confirmed", final_items=final, corrected=corrected)
    # The real backend writes add_log rows (source='camera') and returns the scrap-check verdict here.
    return {"drop_id": drop_id, "status": "confirmed", "corrected": corrected, "items": final}


@app.post("/drops/{drop_id}/dismiss")
def dismiss(drop_id: str):
    d = drops.get(drop_id)
    if d is None:
        raise HTTPException(404)
    d["status"] = "dismissed"
    return {"drop_id": drop_id, "status": "dismissed"}


# --- vision side ---------------------------------------------------------------

@app.get("/bins/{bin_id}/drops/session/active")
def active(bin_id: str):
    for sid, s in sessions.items():
        if s["bin_id"] == bin_id and not s["closed"] and s["expires_at"] > now():
            return {"session_id": sid, "expires_at": s["expires_at"].isoformat()}
    return Response(status_code=204)


@app.post("/bins/{bin_id}/drops", status_code=201)
def report(bin_id: str, body: DropReport):
    s = sessions.get(body.session_id)
    if s is None or s["bin_id"] != bin_id:
        raise HTTPException(404, "unknown session")
    known = set(catalog.ids())
    items = []
    for it in body.items:
        # Validate with rules, like the real backend must: unknown ids stay unknown,
        # and category always comes from the catalog.
        cid = it.catalog_id if it.catalog_id in known else catalog.UNKNOWN
        items.append({**it.model_dump(), "catalog_id": cid, "category": catalog.category_of(cid)})
    did = uuid.uuid4().hex[:12]
    drops[did] = {
        "id": did, "bin_id": bin_id, "session_id": body.session_id, "time": now().isoformat(),
        "status": "pending", "items": items, "thumbnail_jpeg_b64": body.thumbnail_jpeg_b64,
        "latency_ms": body.latency_ms, "gemini_ok": body.gemini_ok, "model": body.model, "error": body.error,
    }
    s["closed"] = True
    return {"drop_id": did, "status": "pending"}


@app.post("/bins/{bin_id}/drops/session/{session_id}/close")
def close(bin_id: str, session_id: str, body: CloseBody):
    s = sessions.get(session_id)
    if s is None:
        raise HTTPException(404)
    s["closed"] = True
    s["close_reason"] = body.reason
    return {"session_id": session_id, "closed": True, "reason": body.reason}


@app.get("/bins/{bin_id}/drops/hints")
def hints(bin_id: str):
    return {"hints": corrections[-5:]}


@app.get("/bins/{bin_id}/drops/sessions/{session_id}")
def session_status(bin_id: str, session_id: str):
    s = sessions.get(session_id)
    if s is None:
        raise HTTPException(404)
    return {**s, "expires_at": s["expires_at"].isoformat()}


# --- tiny stand-in for the app's drop-in sheet -----------------------------------

PAGE = """<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Drop-in mock</title>
<style>
 body{font:15px system-ui;margin:0;padding:16px;background:#f6f4ef;color:#1d2a22;max-width:560px}
 button{font:inherit;padding:10px 16px;border-radius:999px;border:0;background:#3f8a5f;color:#fff;cursor:pointer}
 button.ghost{background:transparent;color:#1d2a22;border:1px solid #c9c4b8}
 .drop{background:#fff;border-radius:16px;padding:12px;margin-top:16px}
 img{width:100%;border-radius:12px} .muted{color:#6b736d} .low{background:#fff4d6}
 table{width:100%;border-collapse:collapse;margin:8px 0} td{padding:4px 0}
</style>
<h2>Drop something in</h2>
<p class=muted>Stand-in for the app's drop-in sheet. Arms the camera for 60 s.</p>
<button id=arm>Drop something in</button> <span id=status class=muted></span>
<div id=drops></div>
<script>
const bin = new URLSearchParams(location.search).get('bin') || 'bin-001';
const $ = s => document.querySelector(s);
let deadline = 0;
$('#arm').onclick = async () => {
  const r = await fetch(`/bins/${bin}/drops/session`, {method:'POST'}).then(r => r.json());
  deadline = Date.parse(r.expires_at);
};
setInterval(() => {
  const left = Math.max(0, Math.round((deadline - Date.now())/1000));
  $('#status').textContent = left ? `Watching the bin… ${left}s` : '';
}, 250);
async function act(id, kind, items) {
  await fetch(`/drops/${id}/${kind}`, {method:'POST', headers:{'content-type':'application/json'},
    body: kind === 'confirm' ? JSON.stringify({items}) : '{}'});
  load();
}
async function load() {
  const list = await fetch(`/bins/${bin}/drops/pending`).then(r => r.json());
  $('#drops').innerHTML = list.map(d => `<div class=drop>
    <b>Something was added</b> <span class=muted>${d.latency_ms} ms${d.gemini_ok ? '' : ' · Gemini failed: fill in by hand'}</span>
    <img src="data:image/jpeg;base64,${d.thumbnail_jpeg_b64}">
    <table>${d.items.map(i => `<tr class="${i.confidence < 0.6 ? 'low' : ''}"><td>${i.label}</td>
      <td>${i.category || '?'}</td><td>${i.amount || '?'}</td><td>${Math.round(i.confidence*100)}%${i.confidence < 0.6 ? ' · check this' : ''}</td></tr>`).join('')
      || '<tr><td class=muted>No item recognised</td></tr>'}</table>
    <button onclick='act("${d.id}","confirm",${JSON.stringify(d.items.filter(i=>i.category).map(i=>({label:i.label,catalog_id:i.catalog_id,category:i.category,amount:i.amount})))})'>Submit</button>
    <button class=ghost onclick='act("${d.id}","dismiss")'>Nothing was added</button></div>`).join('');
}
setInterval(load, 1000); load();
</script>"""


@app.get("/", response_class=HTMLResponse)
def page():
    return PAGE


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8090)
