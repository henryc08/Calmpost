-- Test-only stand-ins for TimescaleDB / Toolkit features, so the backend's
-- real queries run on plain Postgres (local test server). Behaviour matches
-- closely enough for correctness tests: time_bucket buckets, gapfill buckets
-- (without inserting gaps), locf passes through, time_weight averages,
-- state_agg/duration_in measure time between consecutive samples.
-- Continuous aggregates become plain views with the same columns.
-- Never applied to Tiger Cloud.

CREATE OR REPLACE FUNCTION time_bucket(bucket_width interval, ts timestamptz)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$ SELECT date_bin(bucket_width, ts, timestamptz '2000-01-03 00:00:00+00') $$;

CREATE OR REPLACE FUNCTION time_bucket(bucket_width interval, ts timestamptz, origin timestamptz)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$ SELECT date_bin(bucket_width, ts, origin) $$;

CREATE OR REPLACE FUNCTION time_bucket_gapfill(bucket_width interval, ts timestamptz, start timestamptz DEFAULT NULL, finish timestamptz DEFAULT NULL)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$ SELECT date_bin(bucket_width, ts, timestamptz '2000-01-03 00:00:00+00') $$;

CREATE OR REPLACE FUNCTION locf(v anyelement)
RETURNS anyelement LANGUAGE sql IMMUTABLE AS $$ SELECT v $$;

CREATE OR REPLACE FUNCTION _tw_sfunc(state double precision[], kind text, ts timestamptz, v double precision)
RETURNS double precision[] LANGUAGE sql IMMUTABLE AS $$
    SELECT ARRAY[state[1] + coalesce(v, 0), state[2] + CASE WHEN v IS NULL THEN 0 ELSE 1 END]
$$;

CREATE OR REPLACE FUNCTION _tw_final(state double precision[])
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$ SELECT CASE WHEN state[2] > 0 THEN state[1] / state[2] END $$;

CREATE AGGREGATE time_weight(text, timestamptz, double precision) (
    SFUNC = _tw_sfunc, STYPE = double precision[], FINALFUNC = _tw_final, INITCOND = '{0,0}'
);

CREATE OR REPLACE FUNCTION average(v double precision)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$ SELECT v $$;

CREATE OR REPLACE FUNCTION _sa_sfunc(state jsonb, ts timestamptz, s text)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
    SELECT state || jsonb_build_array(jsonb_build_array(extract(epoch FROM ts), s))
$$;

CREATE AGGREGATE state_agg(timestamptz, text) (SFUNC = _sa_sfunc, STYPE = jsonb, INITCOND = '[]');

CREATE OR REPLACE FUNCTION duration_in(agg jsonb, s text)
RETURNS interval LANGUAGE sql IMMUTABLE AS $$
    WITH pts AS (
        SELECT (e->>0)::double precision AS t, e->>1 AS st FROM jsonb_array_elements(agg) e
    ), ord AS (
        SELECT t, st, lead(t) OVER (ORDER BY t) AS nt FROM pts
    )
    SELECT make_interval(secs => coalesce(sum(nt - t) FILTER (WHERE st = s AND nt IS NOT NULL), 0)) FROM ord
$$;

CREATE OR REPLACE VIEW readings_15m AS
SELECT time_bucket('15 minutes', time) AS bucket, bin_id,
       avg(moisture_pct) AS moisture_pct_avg, avg(probe_temp_c) AS probe_temp_c_avg,
       avg(moisture_pct_2) AS moisture_pct_2_avg, avg(probe_temp_c_2) AS probe_temp_c_2_avg,
       max(probe_temp_c) AS probe_temp_c_max, avg(co2_ppm) AS co2_ppm_avg,
       avg(air_temp_c) AS air_temp_c_avg, avg(air_humidity_pct) AS air_humidity_pct_avg,
       count(*) AS samples
FROM readings GROUP BY 1, 2;

CREATE OR REPLACE VIEW readings_1d AS
SELECT time_bucket('1 day', time) AS bucket, bin_id,
       avg(moisture_pct) AS moisture_pct_avg, min(moisture_pct) AS moisture_pct_min,
       max(moisture_pct) AS moisture_pct_max, avg(probe_temp_c) AS probe_temp_c_avg,
       avg(moisture_pct_2) AS moisture_pct_2_avg, min(moisture_pct_2) AS moisture_pct_2_min,
       max(moisture_pct_2) AS moisture_pct_2_max, avg(probe_temp_c_2) AS probe_temp_c_2_avg,
       max(probe_temp_c) AS probe_temp_c_max, avg(co2_ppm) AS co2_ppm_avg, count(*) AS samples
FROM readings GROUP BY 1, 2;

CREATE OR REPLACE VIEW xp_weekly AS
SELECT time_bucket('7 days', time, '2024-01-07 00:00:00+00'::timestamptz) AS week, user_id,
       sum(xp)::bigint AS xp, sum(loam)::bigint AS loam, count(*) AS events
FROM point_events GROUP BY 1, 2;

CREATE OR REPLACE VIEW vision_accuracy_1d AS
SELECT time_bucket('1 day', time) AS bucket, bin_id, count(*) AS drops
FROM drop_events GROUP BY 1, 2;

CREATE OR REPLACE VIEW gacha_odds_1d AS
SELECT time_bucket('1 day', time) AS bucket, rarity, count(*) AS pulls
FROM gacha_pulls GROUP BY 1, 2;
