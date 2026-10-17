-- Calmpost backend schema (TigerData / TimescaleDB on Postgres)
-- Idempotent: safe to run repeatedly.

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ---------------------------------------------------------------------------
-- Devices: one row per physical bin. The ESP32 authenticates with a token
-- whose sha256 hash is stored here (the plaintext token is never persisted).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS devices (
    device_id    text PRIMARY KEY,
    display_name text        NOT NULL DEFAULT 'Compost Bin',
    token_sha256 text        NOT NULL,
    owner_id     text        NOT NULL DEFAULT 'demo-user',
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Zones of the bin. Kept as a lookup table rather than an enum so the
-- firmware can be extended without a migration.
--   top    : fresh scraps + browns   (moisture, temperature)
--   bottom : older/finished compost  (moisture, temperature)
--   airgap : space under the lid     (co2)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zones (
    zone  text PRIMARY KEY,
    label text NOT NULL
);
INSERT INTO zones (zone, label) VALUES
    ('top',    'Top layer'),
    ('bottom', 'Bottom layer'),
    ('airgap', 'Air gap')
ON CONFLICT (zone) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Readings: one row per zone per sample. Columns a zone does not have stay
-- NULL (airgap has no probe, the layers have no CO2 sensor), which keeps the
-- firmware payload shape and the chart queries simple.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS readings (
    time          timestamptz      NOT NULL,
    device_id     text             NOT NULL REFERENCES devices (device_id) ON DELETE CASCADE,
    zone          text             NOT NULL REFERENCES zones (zone),
    moisture_pct  double precision,
    temperature_c double precision,
    co2_ppm       double precision,
    CONSTRAINT readings_moisture_range CHECK (moisture_pct  IS NULL OR moisture_pct  BETWEEN 0 AND 100),
    CONSTRAINT readings_temp_range     CHECK (temperature_c IS NULL OR temperature_c BETWEEN -40 AND 125),
    CONSTRAINT readings_co2_range      CHECK (co2_ppm       IS NULL OR co2_ppm       BETWEEN 0 AND 40000)
);

SELECT create_hypertable('readings', 'time', if_not_exists => TRUE);

-- One sample per zone per instant; makes ingest retries idempotent.
CREATE UNIQUE INDEX IF NOT EXISTS readings_device_zone_time_uniq
    ON readings (device_id, zone, time DESC);

-- ---------------------------------------------------------------------------
-- Hourly rollup for the app's trend charts. Querying raw rows for a week of
-- 5-minute samples is ~2k rows per zone; this keeps the Flutter charts cheap.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS readings_hourly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    device_id,
    zone,
    avg(moisture_pct)  AS moisture_pct_avg,
    avg(temperature_c) AS temperature_c_avg,
    max(temperature_c) AS temperature_c_max,
    avg(co2_ppm)       AS co2_ppm_avg,
    count(*)           AS samples
FROM readings
GROUP BY bucket, device_id, zone
WITH NO DATA;

SELECT add_continuous_aggregate_policy('readings_hourly',
    start_offset => INTERVAL '3 days',
    end_offset   => INTERVAL '1 hour',
    schedule_interval => INTERVAL '30 minutes',
    if_not_exists => TRUE);

-- Raw samples compress after a week; we only need rollups beyond that.
ALTER TABLE readings SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id, zone'
);
SELECT add_compression_policy('readings', INTERVAL '7 days', if_not_exists => TRUE);

-- ---------------------------------------------------------------------------
-- What the user put in the bin. Gemini reads this alongside the sensor
-- trends to judge the greens/browns balance.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS add_log (
    id          bigserial PRIMARY KEY,
    device_id   text        NOT NULL REFERENCES devices (device_id) ON DELETE CASCADE,
    user_id     text        NOT NULL DEFAULT 'demo-user',
    time        timestamptz NOT NULL DEFAULT now(),
    item        text        NOT NULL,
    category    text        NOT NULL CHECK (category IN ('green', 'brown', 'avoid', 'unknown')),
    zone        text        NOT NULL DEFAULT 'top' REFERENCES zones (zone),
    quantity_g  integer     CHECK (quantity_g IS NULL OR quantity_g >= 0),
    source      text        NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'photo', 'seed')),
    was_advised boolean     NOT NULL DEFAULT false,
    notes       text
);
CREATE INDEX IF NOT EXISTS add_log_device_time_idx ON add_log (device_id, time DESC);

-- ---------------------------------------------------------------------------
-- Cached Gemini advice. Recomputing on every app open would burn quota and
-- make the demo slow, so we reuse a recent answer unless the bin has moved.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS advice (
    id            bigserial PRIMARY KEY,
    device_id     text        NOT NULL REFERENCES devices (device_id) ON DELETE CASCADE,
    created_at    timestamptz NOT NULL DEFAULT now(),
    model         text        NOT NULL,
    state_hash    text        NOT NULL,
    stage_top     text,
    stage_bottom  text,
    payload       jsonb       NOT NULL
);
CREATE INDEX IF NOT EXISTS advice_device_created_idx ON advice (device_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Gamification ledger. Points are append-only so streaks and totals can be
-- recomputed, and so the app can show a history instead of just a number.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS points_ledger (
    id        bigserial PRIMARY KEY,
    user_id   text        NOT NULL,
    device_id text        NOT NULL REFERENCES devices (device_id) ON DELETE CASCADE,
    time      timestamptz NOT NULL DEFAULT now(),
    reason    text        NOT NULL,
    points    integer     NOT NULL
);
CREATE INDEX IF NOT EXISTS points_ledger_user_time_idx ON points_ledger (user_id, time DESC);
