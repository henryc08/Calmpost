-- ---------------------------------------------------------------------------
-- Second moisture probe. The firmware now sends both probes in one sample:
--
--   {"device_id":"bin-001","probe_temp_c":22.25,"moisture_raw":464,
--    "probe_temp_c_2":null,"moisture_raw_2":482,
--    "co2_ppm":1498,"air_temp_c":22.67,"air_humidity_pct":40.83,"co2_status":0}
--
-- Probe 1 is the top layer, probe 2 the bottom. Stored on the SAME row rather
-- than as a second row, because readings_bin_time_uniq is UNIQUE (bin_id,
-- time) -- one wide sample per instant, which is exactly what the firmware
-- sends. Two rows per sample would need that index widened and every reader
-- changed; two more columns need neither.
--
-- probe_temp_c_2 is nullable and arrives null today: the second probe reports
-- moisture but not temperature yet. A layer counts as measured on moisture
-- alone, so the bottom layer stops being "unknown" either way.
--
-- Each probe gets its own calibration. They are different physical sensors
-- with different dry/wet counts, and sharing probe 1's numbers would quietly
-- mis-scale probe 2 -- the same class of bug as the 10-bit ADC defaults.
-- Defaults match the single-probe defaults so an uncalibrated second probe
-- reads plausibly rather than pinning to 0 or 100.
-- ---------------------------------------------------------------------------

ALTER TABLE readings
    ADD COLUMN IF NOT EXISTS probe_temp_c_2 double precision,
    ADD COLUMN IF NOT EXISTS moisture_raw_2 integer,
    ADD COLUMN IF NOT EXISTS moisture_pct_2 double precision;

ALTER TABLE bins
    ADD COLUMN IF NOT EXISTS moisture_raw_dry_2 integer NOT NULL DEFAULT 620,
    ADD COLUMN IF NOT EXISTS moisture_raw_wet_2 integer NOT NULL DEFAULT 310,
    ADD COLUMN IF NOT EXISTS calibrated_2 boolean NOT NULL DEFAULT false;

-- ADD CONSTRAINT has no IF NOT EXISTS, so guard each by name.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'readings_probe_temp_2_range') THEN
        ALTER TABLE readings ADD CONSTRAINT readings_probe_temp_2_range
            CHECK (probe_temp_c_2 IS NULL OR probe_temp_c_2 BETWEEN -40 AND 125);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'readings_moisture_raw_2_pos') THEN
        ALTER TABLE readings ADD CONSTRAINT readings_moisture_raw_2_pos
            CHECK (moisture_raw_2 IS NULL OR moisture_raw_2 BETWEEN 0 AND 65535);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'readings_moisture_pct_2_rng') THEN
        ALTER TABLE readings ADD CONSTRAINT readings_moisture_pct_2_rng
            CHECK (moisture_pct_2 IS NULL OR moisture_pct_2 BETWEEN 0 AND 100);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bins_calibration_2_ordered') THEN
        ALTER TABLE bins ADD CONSTRAINT bins_calibration_2_ordered
            CHECK (moisture_raw_dry_2 <> moisture_raw_wet_2);
    END IF;
END $$;

-- NOTE: readings_15m and readings_1d do NOT carry the second probe, so
-- /bins/{id}/trends has no bottom-layer series yet. Adding one means dropping
-- and recreating both continuous aggregates, which re-materialises the whole
-- history -- deliberately not done in the same change as accepting the new
-- payload. The live view and the health score use raw readings and are
-- unaffected.
