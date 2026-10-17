-- Camera drop-in (AGENTS.md 2.4): sessions the app arms, detections the
-- vision service reports, and the camera-accuracy rollup. Confirmed drops
-- become add_log rows with source = 'camera' and a drop_id (001).
-- Idempotent: runs on every boot.

-- ---------------------------------------------------------------------------
-- A session is the app arming the camera ("Drop something in", 60 s). The
-- vision service polls for the open one. Plain table: a handful of rows.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS drop_sessions (
    session_id   text        PRIMARY KEY,
    bin_id       text        NOT NULL REFERENCES bins (bin_id) ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL,
    closed_at    timestamptz,
    close_reason text        CHECK (close_reason IS NULL OR close_reason IN ('no_motion', 'reported', 'replaced'))
);
CREATE INDEX IF NOT EXISTS drop_sessions_bin_open_idx ON drop_sessions (bin_id, expires_at DESC) WHERE closed_at IS NULL;

-- ---------------------------------------------------------------------------
-- Every camera detection. `guess` is what the model said; `final_items` is
-- what the user confirmed, so `corrected` measures camera accuracy.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS drop_events (
    id              bigserial,
    time            timestamptz NOT NULL DEFAULT now(),
    bin_id          text        NOT NULL REFERENCES bins (bin_id) ON DELETE CASCADE,
    session_id      text        NOT NULL,
    status          text        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'dismissed')),
    guess           jsonb       NOT NULL DEFAULT '[]'::jsonb,
    final_items     jsonb,
    corrected       boolean,
    top_confidence  real,
    gemini_ok       boolean     NOT NULL,
    model           text,
    error           text,
    latency_ms      integer,
    thumbnail_jpeg  bytea,
    resolved_at     timestamptz,
    PRIMARY KEY (time, id)
);

SELECT create_hypertable('drop_events', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS drop_events_id_idx ON drop_events (id);
CREATE INDEX IF NOT EXISTS drop_events_bin_status_idx ON drop_events (bin_id, status, time DESC);

-- Photos are personal: keep detections (and their thumbnails) for 30 days.
SELECT add_retention_policy('drop_events', INTERVAL '30 days', if_not_exists => TRUE);

-- Camera accuracy per day, a Tiger Data stat for the demo: share of drops
-- confirmed without correction, average confidence and latency.
CREATE MATERIALIZED VIEW IF NOT EXISTS vision_accuracy_1d
WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT
    time_bucket('1 day', time) AS bucket,
    bin_id,
    count(*)                                              AS drops,
    count(*) FILTER (WHERE status = 'confirmed')          AS confirmed,
    count(*) FILTER (WHERE status = 'confirmed' AND NOT corrected) AS confirmed_as_seen,
    count(*) FILTER (WHERE status = 'dismissed')          AS dismissed,
    avg(top_confidence)                                   AS avg_confidence,
    avg(latency_ms)                                       AS avg_latency_ms
FROM drop_events
GROUP BY bucket, bin_id
WITH NO DATA;

SELECT add_continuous_aggregate_policy('vision_accuracy_1d',
    start_offset => INTERVAL '30 days',
    end_offset   => INTERVAL '1 hour',
    schedule_interval => INTERVAL '30 minutes',
    if_not_exists => TRUE);
