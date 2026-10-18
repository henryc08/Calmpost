-- ---------------------------------------------------------------------------
-- Bottom-layer history. 007 made the second probe live, but the charts stayed
-- empty: readings_15m and readings_1d only averaged probe 1, so there was no
-- bottom series to draw and the app deliberately returned nothing rather than
-- plot the TOP probe's history under a bottom label.
--
-- A continuous aggregate cannot gain a column, so both are dropped and
-- recreated with moisture_pct_2. That re-materialises from raw `readings`,
-- which is cheap here (90-day retention, a few thousand rows) but is NOT
-- something to repeat on every boot -- so the drop is guarded: it only fires
-- when the new column is missing. Afterwards this file is a no-op, like every
-- other migration.
--
-- The guard is a DO block because that is the only way to make DDL
-- conditional in plain SQL. DROP is allowed inside a transaction; CREATE
-- ... WITH (timescaledb.continuous) is not, which is why the creates sit
-- outside it as ordinary statements.
--
-- Deliberately NOT refreshed here. CALL refresh_continuous_aggregate cannot
-- run inside a transaction, and a failure in the boot path would stop the
-- backend starting. The policies below backfill within their schedule, and
-- scripts/refresh_aggregates.py forces it immediately when you do not want to
-- wait.
-- ---------------------------------------------------------------------------

-- relkind 'm' only, deliberately. The test harness replaces these with plain
-- views (tests/timescale_stubs.sql) and skips the timescaledb.continuous
-- creates below, so dropping a plain view here would delete it with nothing
-- to put it back -- and this file runs twice in those tests, by design, to
-- prove idempotence.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_class WHERE relname = 'readings_15m' AND relkind = 'm'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'readings_15m' AND column_name = 'moisture_pct_2_avg'
    ) THEN
        DROP MATERIALIZED VIEW IF EXISTS readings_15m CASCADE;
        DROP MATERIALIZED VIEW IF EXISTS readings_1d CASCADE;
    END IF;
END $$;

CREATE MATERIALIZED VIEW IF NOT EXISTS readings_15m
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('15 minutes', time) AS bucket,
    bin_id,
    avg(moisture_pct)     AS moisture_pct_avg,
    avg(moisture_pct_2)   AS moisture_pct_2_avg,
    avg(probe_temp_c)     AS probe_temp_c_avg,
    max(probe_temp_c)     AS probe_temp_c_max,
    avg(probe_temp_c_2)   AS probe_temp_c_2_avg,
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
    avg(moisture_pct)    AS moisture_pct_avg,
    min(moisture_pct)    AS moisture_pct_min,
    max(moisture_pct)    AS moisture_pct_max,
    avg(moisture_pct_2)  AS moisture_pct_2_avg,
    min(moisture_pct_2)  AS moisture_pct_2_min,
    max(moisture_pct_2)  AS moisture_pct_2_max,
    avg(probe_temp_c)    AS probe_temp_c_avg,
    max(probe_temp_c)    AS probe_temp_c_max,
    avg(probe_temp_c_2)  AS probe_temp_c_2_avg,
    avg(co2_ppm)         AS co2_ppm_avg,
    count(*)             AS samples
FROM readings
GROUP BY bucket, bin_id
WITH NO DATA;

SELECT add_continuous_aggregate_policy('readings_1d',
    start_offset      => INTERVAL '30 days',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists     => TRUE);
