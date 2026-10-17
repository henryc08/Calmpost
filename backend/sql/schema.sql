-- Calmpost schema -- Tiger Data (Tiger Cloud: Postgres + TimescaleDB)
--
-- Shapes follow CLAUDE.md: readings is one WIDE row per ESP32 POST, matching
-- the firmware JSON exactly. Idempotent, so it runs on every server boot.
--
-- Firmware payload this table mirrors:
--   {"device_id":"bin-001","probe_temp_c":25.3,"moisture_raw":412,
--    "co2_ppm":850,"air_temp_c":24.1,"air_humidity_pct":58.2,"co2_status":0}

CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit;

-- ---------------------------------------------------------------------------
-- Bins. The firmware calls this device_id; the app calls it bin_id. One row
-- per physical bin, authenticating with a token whose sha256 is stored here.
--
-- The probe reports a RAW ADC count, not a percentage, so the raw->percent
-- calibration lives here per bin: capacitive probes vary unit to unit, and
-- moisture is 45% of the health score, so a wrong curve poisons everything
-- downstream. calibrated=false means the defaults are still in place and the
-- app should say so rather than present a confident number.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bins (
    bin_id           text PRIMARY KEY,
    display_name     text        NOT NULL DEFAULT 'Compost Bin',
    token_sha256     text        NOT NULL,
    owner_id         text        NOT NULL DEFAULT 'demo-user',
    moisture_raw_dry integer     NOT NULL DEFAULT 3000,
    moisture_raw_wet integer     NOT NULL DEFAULT 1000,
    calibrated       boolean     NOT NULL DEFAULT false,
    created_at       timestamptz NOT NULL DEFAULT now(),
    last_seen_at     timestamptz,
    CONSTRAINT bins_calibration_ordered CHECK (moisture_raw_dry <> moisture_raw_wet)
);

-- ---------------------------------------------------------------------------
-- readings: one wide row per POST.
--
-- The current build has ONE probe (probe_temp_c + moisture_raw) and ONE air
-- sensor (co2 + air temp + humidity), so there is no top/bottom split at the
-- sensor level. probe_layer records where the probe physically sits, ready
-- for a second probe without a migration.
--
-- moisture_pct is derived server-side from the bin's calibration and stored
-- alongside the raw count so a recalibration can be replayed over history.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS readings (
    time             timestamptz      NOT NULL,
    bin_id           text             NOT NULL REFERENCES bins (bin_id) ON DELETE CASCADE,
    probe_layer      text             NOT NULL DEFAULT 'top',
    probe_temp_c     double precision,
    moisture_raw     integer,
    moisture_pct     double precision,
    co2_ppm          double precision,
    air_temp_c       double precision,
    air_humidity_pct double precision,
    -- Sensor's own health flag (0 = ok). Non-zero means treat CO2 as
    -- unreliable rather than silently charting a bad number.
    co2_status       smallint,
    CONSTRAINT readings_probe_temp_range CHECK (probe_temp_c     IS NULL OR probe_temp_c     BETWEEN -40 AND 125),
    CONSTRAINT readings_air_temp_range   CHECK (air_temp_c       IS NULL OR air_temp_c       BETWEEN -40 AND 125),
    CONSTRAINT readings_humidity_range   CHECK (air_humidity_pct IS NULL OR air_humidity_pct BETWEEN 0 AND 100),
    CONSTRAINT readings_moisture_raw_pos CHECK (moisture_raw     IS NULL OR moisture_raw     BETWEEN 0 AND 65535),
    CONSTRAINT readings_moisture_pct_rng CHECK (moisture_pct     IS NULL OR moisture_pct     BETWEEN 0 AND 100),
    CONSTRAINT readings_co2_range        CHECK (co2_ppm          IS NULL OR co2_ppm          BETWEEN 0 AND 40000)
);

SELECT create_hypertable('readings', 'time', if_not_exists => TRUE);

-- One sample per bin per instant, so a firmware retry is idempotent.
CREATE UNIQUE INDEX IF NOT EXISTS readings_bin_time_uniq
    ON readings (bin_id, time DESC);

-- ---------------------------------------------------------------------------
-- add_log: what went into the bin. Gemini reads this with the sensor trends
-- to judge the greens:browns balance.
--
-- action distinguishes a real add from "Wren said avoid and I listened",
-- which is what earns the avoided-bad-add XP.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS add_log (
    id          bigserial,
    time        timestamptz NOT NULL DEFAULT now(),
    bin_id      text        NOT NULL REFERENCES bins (bin_id) ON DELETE CASCADE,
    user_id     text        NOT NULL DEFAULT 'demo-user',
    item        text        NOT NULL,
    category    text        NOT NULL CHECK (category IN ('green', 'brown', 'avoid', 'unknown')),
    action      text        NOT NULL DEFAULT 'added' CHECK (action IN ('added', 'skipped')),
    quantity_g  integer     CHECK (quantity_g IS NULL OR quantity_g >= 0),
    source      text        NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'photo', 'seed')),
    was_advised boolean     NOT NULL DEFAULT false,
    -- The advice row this followed, when the app passes it through. No FK:
    -- advice is a hypertable keyed (time, id).
    advice_id   bigint,
    notes       text,
    PRIMARY KEY (time, id)
);

SELECT create_hypertable('add_log', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS add_log_bin_time_idx  ON add_log (bin_id, time DESC);
CREATE INDEX IF NOT EXISTS add_log_user_time_idx ON add_log (user_id, time DESC);

-- ---------------------------------------------------------------------------
-- advice: every Gemini (or rules) answer, WITH the sensor snapshot it was
-- based on. The snapshot is the point: it is our proof that the same scrap
-- got a different answer because the bin had changed, not because the model
-- is random. Keep it.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS advice (
    id             bigserial,
    time           timestamptz NOT NULL DEFAULT now(),
    bin_id         text        NOT NULL REFERENCES bins (bin_id) ON DELETE CASCADE,
    -- NULL for whole-bin advice; set when checking one item.
    item           text,
    model          text        NOT NULL,
    state_hash     text        NOT NULL,
    verdict        text        CHECK (verdict IS NULL OR verdict IN ('add', 'add_with_browns', 'avoid')),
    reason         text,
    balance        text,
    stage_top      text,
    stage_bottom   text,
    bottom_ready   boolean,
    tip            text,
    suggest_add    jsonb       NOT NULL DEFAULT '[]'::jsonb,
    suggest_avoid  jsonb       NOT NULL DEFAULT '[]'::jsonb,
    input_snapshot jsonb       NOT NULL,
    payload        jsonb       NOT NULL,
    PRIMARY KEY (time, id)
);

SELECT create_hypertable('advice', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS advice_bin_time_idx ON advice (bin_id, time DESC);
CREATE INDEX IF NOT EXISTS advice_lookup_idx   ON advice (bin_id, item, state_hash, time DESC);

-- ---------------------------------------------------------------------------
-- point_events: the XP ledger, append-only so totals, streaks and league
-- standings are always recomputed rather than stored and drifting.
--
-- dedupe_key makes once-per-day awards (healthy layer-day, quests, weekly
-- balance) safe to re-evaluate on every request.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS point_events (
    id         bigserial,
    time       timestamptz NOT NULL DEFAULT now(),
    user_id    text        NOT NULL,
    bin_id     text        REFERENCES bins (bin_id) ON DELETE CASCADE,
    kind       text        NOT NULL,
    xp         integer     NOT NULL DEFAULT 0,
    seeds      integer     NOT NULL DEFAULT 0,
    dedupe_key text,
    meta       jsonb       NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (time, id)
);

SELECT create_hypertable('point_events', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS point_events_user_time_idx ON point_events (user_id, time DESC);
CREATE INDEX IF NOT EXISTS point_events_dedupe_idx    ON point_events (user_id, dedupe_key)
    WHERE dedupe_key IS NOT NULL;

-- ---------------------------------------------------------------------------
-- stage_history: the Batch Journey path. Stage transitions are driven by
-- sensors, not taps -- except 'harvested', which the user triggers.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stage_history (
    id       bigserial,
    time     timestamptz NOT NULL DEFAULT now(),
    bin_id   text        NOT NULL REFERENCES bins (bin_id) ON DELETE CASCADE,
    layer    text        NOT NULL DEFAULT 'top',
    stage    text        NOT NULL CHECK (stage IN ('started', 'active', 'hot', 'curing', 'ready', 'harvested')),
    source   text        NOT NULL DEFAULT 'sensor' CHECK (source IN ('sensor', 'user')),
    evidence jsonb       NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (time, id)
);

SELECT create_hypertable('stage_history', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS stage_history_bin_time_idx ON stage_history (bin_id, layer, time DESC);

-- ---------------------------------------------------------------------------
-- Per-user mutable state. Not a hypertable: it is current state, not events.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_state (
    user_id    text PRIMARY KEY,
    lid_locks  integer     NOT NULL DEFAULT 0 CHECK (lid_locks BETWEEN 0 AND 2),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Leagues: weekly 30-person cohorts, Sunday reset.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS leagues (
    id         bigserial PRIMARY KEY,
    tier       text NOT NULL CHECK (tier IN ('seedling', 'sprout', 'fern', 'sapling', 'oak', 'sequoia')),
    week_start date NOT NULL,
    UNIQUE (tier, week_start)
);

CREATE TABLE IF NOT EXISTS league_members (
    league_id   bigint  NOT NULL REFERENCES leagues (id) ON DELETE CASCADE,
    user_id     text    NOT NULL,
    display_name text   NOT NULL,
    is_bot      boolean NOT NULL DEFAULT false,
    PRIMARY KEY (league_id, user_id)
);

CREATE INDEX IF NOT EXISTS league_members_user_idx ON league_members (user_id);

-- ---------------------------------------------------------------------------
-- Continuous aggregates. readings_15m and readings_1d back the charts;
-- xp_weekly powers Leagues.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS readings_15m
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('15 minutes', time) AS bucket,
    bin_id,
    avg(moisture_pct)     AS moisture_pct_avg,
    avg(probe_temp_c)     AS probe_temp_c_avg,
    max(probe_temp_c)     AS probe_temp_c_max,
    avg(co2_ppm)          AS co2_ppm_avg,
    avg(air_temp_c)       AS air_temp_c_avg,
    avg(air_humidity_pct) AS air_humidity_pct_avg,
    count(*)              AS samples
FROM readings
GROUP BY bucket, bin_id
WITH NO DATA;

SELECT add_continuous_aggregate_policy('readings_15m',
    start_offset      => INTERVAL '3 days',
    end_offset        => INTERVAL '15 minutes',
    schedule_interval => INTERVAL '15 minutes',
    if_not_exists     => TRUE);

CREATE MATERIALIZED VIEW IF NOT EXISTS readings_1d
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', time) AS bucket,
    bin_id,
    avg(moisture_pct)  AS moisture_pct_avg,
    min(moisture_pct)  AS moisture_pct_min,
    max(moisture_pct)  AS moisture_pct_max,
    avg(probe_temp_c)  AS probe_temp_c_avg,
    max(probe_temp_c)  AS probe_temp_c_max,
    avg(co2_ppm)       AS co2_ppm_avg,
    count(*)           AS samples
FROM readings
GROUP BY bucket, bin_id
WITH NO DATA;

SELECT add_continuous_aggregate_policy('readings_1d',
    start_offset      => INTERVAL '30 days',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists     => TRUE);

-- Weekly XP per user. origin is a Sunday so buckets line up with the
-- Sunday league reset rather than the epoch's Thursday.
CREATE MATERIALIZED VIEW IF NOT EXISTS xp_weekly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('7 days', time, origin => '2024-01-07 00:00:00+00'::timestamptz) AS week,
    user_id,
    sum(xp)::bigint    AS xp,
    sum(seeds)::bigint AS seeds,
    count(*)           AS events
FROM point_events
GROUP BY week, user_id
WITH NO DATA;

SELECT add_continuous_aggregate_policy('xp_weekly',
    start_offset      => INTERVAL '21 days',
    end_offset        => INTERVAL '1 minute',
    schedule_interval => INTERVAL '5 minutes',
    if_not_exists     => TRUE);

-- ---------------------------------------------------------------------------
-- Policies: columnstore for older raw samples, then drop them. The
-- aggregates keep the long history the charts need.
-- ---------------------------------------------------------------------------
ALTER TABLE readings SET (
    timescaledb.enable_columnstore = true,
    timescaledb.segmentby = 'bin_id',
    timescaledb.orderby = 'time DESC'
);

CALL add_columnstore_policy('readings', after => INTERVAL '7 days', if_not_exists => TRUE);

SELECT add_retention_policy('readings', INTERVAL '90 days', if_not_exists => TRUE);
