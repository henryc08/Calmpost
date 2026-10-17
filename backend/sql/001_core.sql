-- Calmpost core schema: bins, sensor readings, what went in, advice, stages.
-- Tiger Data (Tiger Cloud: Postgres + TimescaleDB). Idempotent: runs on
-- every boot, in file order (000, 001, 002, ...).
--
-- readings is one WIDE row per sample, matching the firmware JSON exactly:
--   {"device_id":"bin-001","probe_temp_c":25.3,"moisture_raw":412,
--    "co2_ppm":850,"air_temp_c":24.1,"air_humidity_pct":58.2,"co2_status":0}

CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit;

-- ---------------------------------------------------------------------------
-- bins. The firmware calls this device_id; the app calls it bin_id. One row
-- per physical bin, authenticating with a token whose sha256 is stored here.
--
-- The probe reports a RAW ADC count, so the raw->percent calibration lives
-- here per bin. Defaults assume the 10-bit ADC (analogReadResolution(10),
-- counts 0-1023) and are only a starting curve: calibrate per probe.
-- calibrated=false means the app should say the percentage is approximate.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bins (
    bin_id           text PRIMARY KEY,
    display_name     text        NOT NULL DEFAULT 'Compost Bin',
    token_sha256     text        NOT NULL,
    owner_id         text        NOT NULL DEFAULT 'demo-user',
    moisture_raw_dry integer     NOT NULL DEFAULT 620,
    moisture_raw_wet integer     NOT NULL DEFAULT 310,
    calibrated       boolean     NOT NULL DEFAULT false,
    created_at       timestamptz NOT NULL DEFAULT now(),
    last_seen_at     timestamptz,
    CONSTRAINT bins_calibration_ordered CHECK (moisture_raw_dry <> moisture_raw_wet)
);

-- ---------------------------------------------------------------------------
-- readings: one wide row per POST (hypertable).
--
-- The current build has ONE probe (probe_temp_c + moisture_raw) and ONE air
-- sensor (CO2 + air temp + humidity). probe_layer records where the probe
-- sits, so a second probe needs no migration. moisture_pct is derived
-- server-side from the bin's calibration and stored beside the raw count so
-- a recalibration can be replayed over history.
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
    -- Sensor's own health flag (0 = ok). Non-zero: treat CO2 as unreliable.
    co2_status       smallint,
    CONSTRAINT readings_probe_temp_range CHECK (probe_temp_c     IS NULL OR probe_temp_c     BETWEEN -40 AND 125),
    CONSTRAINT readings_air_temp_range   CHECK (air_temp_c       IS NULL OR air_temp_c       BETWEEN -40 AND 125),
    CONSTRAINT readings_humidity_range   CHECK (air_humidity_pct IS NULL OR air_humidity_pct BETWEEN 0 AND 100),
    CONSTRAINT readings_moisture_raw_pos CHECK (moisture_raw     IS NULL OR moisture_raw     BETWEEN 0 AND 65535),
    CONSTRAINT readings_moisture_pct_rng CHECK (moisture_pct     IS NULL OR moisture_pct     BETWEEN 0 AND 100),
    CONSTRAINT readings_co2_range        CHECK (co2_ppm          IS NULL OR co2_ppm          BETWEEN 0 AND 40000)
);

SELECT create_hypertable('readings', 'time', if_not_exists => TRUE);

-- One sample per bin per instant, so a bridge retry is idempotent.
CREATE UNIQUE INDEX IF NOT EXISTS readings_bin_time_uniq ON readings (bin_id, time DESC);

-- ---------------------------------------------------------------------------
-- add_log: what went into the bin (hypertable). Feeds the greens:browns
-- balance, impact stats and the advice prompt.
--
-- action 'skipped' records trusting an avoid verdict, which earns XP.
-- source 'camera' rows come from a confirmed drop (drop_id), see 003.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS add_log (
    id          bigserial,
    time        timestamptz NOT NULL DEFAULT now(),
    bin_id      text        NOT NULL REFERENCES bins (bin_id) ON DELETE CASCADE,
    user_id     text        NOT NULL DEFAULT 'demo-user',
    item        text        NOT NULL,
    -- The app's food catalog id when known (app/lib/data/food_catalog.dart).
    catalog_id  text,
    category    text        NOT NULL CHECK (category IN ('green', 'brown', 'avoid', 'unknown')),
    action      text        NOT NULL DEFAULT 'added' CHECK (action IN ('added', 'skipped')),
    quantity_g  integer     CHECK (quantity_g IS NULL OR quantity_g >= 0),
    source      text        NOT NULL DEFAULT 'manual' CONSTRAINT add_log_source_check
                            CHECK (source IN ('manual', 'photo', 'seed', 'camera')),
    was_advised boolean     NOT NULL DEFAULT false,
    -- The advice row this followed. No FK: advice is keyed (time, id).
    advice_id   bigint,
    drop_id     bigint,
    notes       text,
    PRIMARY KEY (time, id)
);

SELECT create_hypertable('add_log', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS add_log_bin_time_idx  ON add_log (bin_id, time DESC);
CREATE INDEX IF NOT EXISTS add_log_user_time_idx ON add_log (user_id, time DESC);

-- ---------------------------------------------------------------------------
-- advice: every Gemini (or rules) answer WITH the sensor snapshot it was
-- based on (hypertable). The snapshot is the proof that the same scrap got a
-- different answer because the bin changed, not because the model is random.
-- Verdicts are the app's: great / careful / avoid.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS advice (
    id             bigserial,
    time           timestamptz NOT NULL DEFAULT now(),
    bin_id         text        NOT NULL REFERENCES bins (bin_id) ON DELETE CASCADE,
    -- NULL for whole-bin advice ("What to add"); set when checking one item.
    item           text,
    model          text        NOT NULL,
    state_hash     text        NOT NULL,
    verdict        text        CONSTRAINT advice_verdict_check
                               CHECK (verdict IS NULL OR verdict IN ('great', 'careful', 'avoid')),
    headline       text,
    pair_with      jsonb       NOT NULL DEFAULT '[]'::jsonb,
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
-- stage_history: life-cycle transitions per layer (hypertable). Driven by
-- sensors, except 'harvested', which the user triggers. Stages are the app's.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stage_history (
    id       bigserial,
    time     timestamptz NOT NULL DEFAULT now(),
    bin_id   text        NOT NULL REFERENCES bins (bin_id) ON DELETE CASCADE,
    layer    text        NOT NULL DEFAULT 'top',
    stage    text        NOT NULL CONSTRAINT stage_history_stage_check
                         CHECK (stage IN ('started', 'active', 'hot', 'cooling', 'curing', 'ready', 'harvested')),
    source   text        NOT NULL DEFAULT 'sensor' CHECK (source IN ('sensor', 'user')),
    evidence jsonb       NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (time, id)
);

SELECT create_hypertable('stage_history', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS stage_history_bin_time_idx ON stage_history (bin_id, layer, time DESC);

-- ---------------------------------------------------------------------------
-- Continuous aggregates behind the charts and sparklines.
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

-- ---------------------------------------------------------------------------
-- Policies: columnstore for older raw samples, then drop them after 90 days.
-- The aggregates keep the long history the charts need.
-- ---------------------------------------------------------------------------
ALTER TABLE readings SET (
    timescaledb.enable_columnstore = true,
    timescaledb.segmentby = 'bin_id',
    timescaledb.orderby = 'time DESC'
);

CALL add_columnstore_policy('readings', after => INTERVAL '7 days', if_not_exists => TRUE);

SELECT add_retention_policy('readings', INTERVAL '90 days', if_not_exists => TRUE);
